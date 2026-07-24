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
