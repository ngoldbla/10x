// LibrarySync.swift — the cloud merge core (PRD-8). Pure, Sendable, no
// CloudKit and no UI, so it lives in the Engine and is fully SwiftPM-testable
// on Linux. `SyncedEntry` is the CloudKit projection of a `LibraryEntry`
// (drops the undo stack and move log — device-local UX state, ~1-2 KB once
// gone); `LibrarySync` holds the merge rules that reconcile a remote entry
// into the local library without ever losing progress silently.
import Foundation

/// A `LibraryEntry` as it travels through CloudKit: the board and its
/// lifecycle, minus device-local history. One `SyncedEntry` ⇔ one `CKRecord`.
public struct SyncedEntry: Codable, Sendable, Equatable {
    public let id: UUID
    public var kind: GameKind
    public var status: BoardStatus
    public var game: NineGame
    public let createdAt: Date
    public var updatedAt: Date
    public var solvedAt: Date?

    /// Project a library entry for the cloud: strip undo/move log.
    public init(_ entry: LibraryEntry) {
        var g = entry.game
        g.clearLocalHistory()
        self.id = entry.id
        self.kind = entry.kind
        self.status = entry.status
        self.game = g
        self.createdAt = entry.createdAt
        self.updatedAt = entry.updatedAt
        self.solvedAt = entry.solvedAt
    }

    /// Rebuild a library entry (undo/move log start empty on the new device).
    public func hydrated() -> LibraryEntry {
        LibraryEntry(
            id: id, kind: kind, game: game, status: status,
            createdAt: createdAt, updatedAt: updatedAt, solvedAt: solvedAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, status, game, createdAt, updatedAt, solvedAt
    }

    /// Tolerant decoding: any field added after this ships must fall back to a
    /// default rather than throwing (a thrown decode drops the whole record).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(GameKind.self, forKey: .kind)
        status = (try? c.decode(BoardStatus.self, forKey: .status)) ?? .inProgress
        game = try c.decode(NineGame.self, forKey: .game)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        solvedAt = try c.decodeIfPresent(Date.self, forKey: .solvedAt)
    }
}

public enum LibrarySync {

    /// The outcome of reconciling two versions of the same board id.
    public struct Reconciliation: Equatable {
        /// The version to keep under the shared id.
        public var winner: LibraryEntry
        /// A divergent loser preserved under a NEW id (status `.archived`), or
        /// nil when there was nothing to save.
        public var archivedLoser: LibraryEntry?
    }

    /// Reconcile two entries that share an id, never losing progress silently:
    ///  1. If exactly one is `.solved`, it wins (solved is terminal truth).
    ///  2. If both `.solved`, the later `solvedAt` (tie: later `updatedAt`) wins.
    ///  3. Else if the boards' placed digits are equal, later `updatedAt` wins.
    ///  4. Else if one board is a conflict-free superset of the other, it wins.
    ///  5. Else (divergent) higher `fillFraction` wins; the loser is retained
    ///     as a new `.archived` entry.
    public static func reconcile(
        _ a: LibraryEntry, _ b: LibraryEntry, makeID: () -> UUID
    ) -> Reconciliation {
        // Rule 1/2: solved is terminal truth.
        switch (a.status == .solved, b.status == .solved) {
        case (true, false): return Reconciliation(winner: a, archivedLoser: nil)
        case (false, true): return Reconciliation(winner: b, archivedLoser: nil)
        case (true, true):
            return Reconciliation(winner: laterSolved(a, b), archivedLoser: nil)
        case (false, false):
            break
        }
        // Rule 3: identical boards → metadata last-writer-wins.
        if userEntriesEqual(a.game, b.game) {
            return Reconciliation(winner: newer(a, b), archivedLoser: nil)
        }
        // Rule 4: one board is a conflict-free continuation of the other.
        if isContinuation(of: a.game, from: b.game) {   // a ⊇ b
            return Reconciliation(winner: a, archivedLoser: nil)
        }
        if isContinuation(of: b.game, from: a.game) {   // b ⊇ a
            return Reconciliation(winner: b, archivedLoser: nil)
        }
        // Rule 5: divergent — higher fill wins, loser archived under a new id.
        let (win, lose): (LibraryEntry, LibraryEntry) = a.game.fillFraction == b.game.fillFraction
            ? (newer(a, b), older(a, b))
            : (a.game.fillFraction > b.game.fillFraction ? (a, b) : (b, a))
        var loser = lose
        loser.id = makeID()
        loser.status = .archived
        return Reconciliation(winner: win, archivedLoser: loser)
    }

    // MARK: - Applying a remote entry into the local library

    /// What the caller must tell CloudKit after a local apply.
    public struct ApplyEffects: Equatable {
        /// Local ids whose board changed and should be pushed back up.
        public var reupload: [UUID]
        /// Cloud record ids to delete (daily dedup — redundant same-day rows).
        public var cloudDeletes: [UUID]
        public init(reupload: [UUID] = [], cloudDeletes: [UUID] = []) {
            self.reupload = reupload
            self.cloudDeletes = cloudDeletes
        }
    }

    /// Merge a remote entry into the local library honoring every rule.
    public static func apply(
        remote: SyncedEntry, into library: inout BoardLibrary,
        now: Date, makeID: () -> UUID
    ) -> ApplyEffects {
        if case .daily(let day) = remote.kind {
            return applyDaily(remote: remote, day: day, into: &library, makeID: makeID)
        }
        return applyRegular(remote: remote, into: &library, makeID: makeID)
    }

    /// Remove a board the cloud says was deleted.
    public static func applyDeletion(id: UUID, into library: inout BoardLibrary) {
        library.delete(id: id)
    }

    /// Non-daily entries, keyed by id.
    private static func applyRegular(
        remote: SyncedEntry, into library: inout BoardLibrary, makeID: () -> UUID
    ) -> ApplyEffects {
        guard let local = library.entry(id: remote.id) else {
            library.upsert(remote.hydrated())
            return ApplyEffects()
        }
        let r = reconcile(local, remote.hydrated(), makeID: makeID)
        library.upsert(r.winner)
        var fx = ApplyEffects()
        if let loser = r.archivedLoser {
            library.upsert(loser)
            fx.reupload.append(loser.id)
        }
        // The winner differs from what the cloud holds → push it back.
        if r.winner.game.entries != remote.game.entries || r.winner.status != remote.status {
            fx.reupload.append(r.winner.id)
        }
        return fx
    }

    /// Dailies, keyed by day (one entry per day invariant). All same-day
    /// candidates fold to one winning board through `reconcile`, routed through
    /// `adoptDaily`, homed on the canonical (smallest) uuid so both devices
    /// converge on the same surviving id without ping-ponging.
    private static func applyDaily(
        remote: SyncedEntry, day: Int, into library: inout BoardLibrary, makeID: () -> UUID
    ) -> ApplyEffects {
        let locals = library.entries.filter {
            if case .daily(let d) = $0.kind { return d == day }; return false
        }
        // Fold every local daily(day) into the remote. Align ids first so the
        // rules compare the boards (dailies are keyed by day, not id).
        var winner = remote.hydrated()
        var archived: [LibraryEntry] = []
        for local in locals {
            let r = reconcile(local, winner.reIded(local.id), makeID: makeID)
            winner = r.winner
            if let loser = r.archivedLoser { archived.append(loser) }
        }
        // Canonical id: deterministic across devices (smallest uuid seen).
        let allIDs = (locals.map(\.id) + [remote.id]).map(\.uuidString)
        let canonical = UUID(uuidString: allIDs.min()!)!

        var fx = ApplyEffects()
        // Drop every non-canonical daily(day) row and schedule its cloud delete.
        for local in locals where local.id != canonical {
            library.delete(id: local.id)
            fx.cloudDeletes.append(local.id)
        }
        if remote.id != canonical { fx.cloudDeletes.append(remote.id) }

        // Route the winning board through adoptDaily (PRD-8 §2), then re-home
        // onto the canonical id if adoptDaily minted a fresh one.
        let landedID = library.adoptDaily(game: winner.game, day: day, now: winner.updatedAt)
        if landedID != canonical, var e = library.entry(id: landedID) {
            library.delete(id: landedID)
            e.id = canonical
            library.upsert(e)
        }
        if winner.status == .solved {
            library.markSolved(id: canonical, at: winner.solvedAt ?? winner.updatedAt)
        }
        for loser in archived { library.upsert(loser); fx.reupload.append(loser.id) }
        // Push the canonical row back only when the cloud doesn't already hold
        // it verbatim (keeps a repeat apply a no-op).
        if canonical != remote.id
            || winner.game.entries != remote.game.entries
            || winner.status != remote.status {
            fx.reupload.append(canonical)
        }
        return ApplyEffects(
            reupload: Array(Set(fx.reupload)),
            cloudDeletes: Array(Set(fx.cloudDeletes))
        )
    }

    // MARK: - Board comparison (placed digits only; pencil is not progress)

    static func userEntriesEqual(_ x: NineGame, _ y: NineGame) -> Bool {
        x.entries == y.entries
    }

    /// True when every user-placed digit in `source` also appears, identical,
    /// in `whole` — i.e. `whole` is a conflict-free superset of `source`.
    static func isContinuation(of whole: NineGame, from source: NineGame) -> Bool {
        for cell in 0..<81 where !source.isGiven(cell) && source.entry(at: cell) != 0 {
            if whole.entry(at: cell) != source.entry(at: cell) { return false }
        }
        return true
    }

    static func newer(_ a: LibraryEntry, _ b: LibraryEntry) -> LibraryEntry {
        a.updatedAt >= b.updatedAt ? a : b
    }
    static func older(_ a: LibraryEntry, _ b: LibraryEntry) -> LibraryEntry {
        a.updatedAt >= b.updatedAt ? b : a
    }
    static func laterSolved(_ a: LibraryEntry, _ b: LibraryEntry) -> LibraryEntry {
        let sa = a.solvedAt ?? a.updatedAt, sb = b.solvedAt ?? b.updatedAt
        if sa != sb { return sa > sb ? a : b }
        return newer(a, b)
    }
}

private extension LibraryEntry {
    /// A copy under a different id — used so daily reconciliation compares the
    /// boards (dailies are keyed by day) rather than short-circuiting on id.
    func reIded(_ newID: UUID) -> LibraryEntry {
        var copy = self
        copy.id = newID
        return copy
    }
}
