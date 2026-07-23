// BoardLibrary.swift — the board tracker's data model (playtest fix D). Replaces
// the single `SaveSlot` autosave: a daily entry (one per day) plus unlimited
// free-play partials, each carrying its own `NineGame`, status and timestamps.
// Pure and Sendable, no hidden clocks (every time-dependent op takes `now`), so
// it lives in the Engine and is fully SwiftPM-testable on Linux.
import Foundation

/// What kind of board is (or was) being played. Moved here from AppModel so the
/// library (Engine) can key on it; the synthesized Codable shape is unchanged
/// (case-name keyed), so old `nine.save` blobs still decode.
public enum GameKind: Codable, Sendable, Equatable, Hashable {
    case daily(day: Int)
    case free(Difficulty)
}

/// Lifecycle of a tracked board.
public enum BoardStatus: String, Codable, Sendable, Equatable {
    case inProgress, solved, archived
}

/// One tracked board.
public struct LibraryEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var kind: GameKind
    public var game: NineGame
    public var status: BoardStatus
    public let createdAt: Date
    /// Last activity — moves, solve, or nothing since creation. The tracker and
    /// the prune order both sort on this.
    public var updatedAt: Date
    public var solvedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: GameKind,
        game: NineGame,
        status: BoardStatus = .inProgress,
        createdAt: Date,
        updatedAt: Date,
        solvedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.game = game
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.solvedAt = solvedAt
    }
}

/// The whole board library. `entries` is kept newest-updated first so the
/// tracker sections and the "most recent partial" queries are cheap first-reads.
public struct BoardLibrary: Codable, Sendable, Equatable {
    public private(set) var entries: [LibraryEntry]

    public init(entries: [LibraryEntry] = []) {
        self.entries = entries
        sort()
    }

    // MARK: - Caps (local-only persistence: iCloud KVS is full)
    static let totalCap = 60
    static let playedCap = 20 // solved + archived

    // MARK: - Queries

    public func entry(id: UUID) -> LibraryEntry? { entries.first { $0.id == id } }

    /// The single entry for a given day, any status (dailies are one-per-day).
    public func dailyEntry(day: Int) -> LibraryEntry? {
        entries.first { isDaily($0.kind, day: day) }
    }

    /// Today's daily only when it is still in progress (drives openToday resume).
    public func inProgressDaily(day: Int) -> LibraryEntry? {
        guard let e = dailyEntry(day: day), e.status == .inProgress else { return nil }
        return e
    }

    /// The newest in-progress free-play board (the Continue card).
    public var mostRecentFreePartial: LibraryEntry? {
        entries.first { $0.status == .inProgress && isFree($0.kind) }
    }

    /// The newest in-progress board of any kind (resume-on-launch).
    public var mostRecentInProgress: LibraryEntry? {
        entries.first { $0.status == .inProgress }
    }

    /// Every in-progress board, newest first (tracker "In progress" section).
    public var partials: [LibraryEntry] { entries.filter { $0.status == .inProgress } }

    /// Every solved or archived board, newest first ("Previously played").
    public var played: [LibraryEntry] { entries.filter { $0.status != .inProgress } }

    // MARK: - Mutations

    /// Insert or replace an entry by id, then re-sort and prune. The single
    /// funnel every other mutation routes through.
    public mutating func upsert(_ entry: LibraryEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
        sort()
        prune()
    }

    /// Start tracking a brand-new board; returns its id.
    @discardableResult
    public mutating func create(kind: GameKind, game: NineGame, now: Date) -> UUID {
        let entry = LibraryEntry(kind: kind, game: game, status: .inProgress, createdAt: now, updatedAt: now)
        upsert(entry)
        return entry.id
    }

    /// One-entry-per-day upsert for the daily — the merge that replaces the old
    /// launch-clobber. If a daily entry for `day` already exists it is reset to
    /// this (fresh or widget-advanced) board and marked in progress (a
    /// replay-after-solve reuses the same day slot); otherwise a new entry is
    /// created. Free-play entries are structurally untouched. Returns the id.
    @discardableResult
    public mutating func adoptDaily(game: NineGame, day: Int, now: Date) -> UUID {
        if var existing = dailyEntry(day: day) {
            existing.game = game
            existing.status = .inProgress
            existing.solvedAt = nil
            existing.updatedAt = now
            upsert(existing)
            return existing.id
        }
        return create(kind: .daily(day: day), game: game, now: now)
    }

    /// Mark a board solved, retained as a "previously played" entry.
    public mutating func markSolved(id: UUID, at date: Date) {
        guard var e = entry(id: id) else { return }
        e.status = .solved
        e.solvedAt = date
        e.updatedAt = date
        upsert(e)
    }

    /// Archive a partial (kept, but out of the active list). updatedAt is left
    /// as-is so the "previously played" order reflects last real activity.
    public mutating func archive(id: UUID) {
        guard var e = entry(id: id) else { return }
        e.status = .archived
        upsert(e)
    }

    /// Remove a board entirely (delete control).
    public mutating func delete(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Seed a library from a legacy single-slot `nine.save` board (migration).
    public static func migrating(game: NineGame, kind: GameKind, now: Date) -> BoardLibrary {
        let solved = game.isSolved
        let entry = LibraryEntry(
            kind: kind,
            game: game,
            status: solved ? .solved : .inProgress,
            createdAt: now,
            updatedAt: now,
            solvedAt: solved ? now : nil
        )
        return BoardLibrary(entries: [entry])
    }

    // MARK: - Internals

    private mutating func sort() {
        entries.sort {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            // Deterministic tie-break so tests (and equal-timestamp bursts) are stable.
            return $0.id.uuidString > $1.id.uuidString
        }
    }

    /// Enforce the caps. Removal order, oldest-updated first within each band:
    /// archived → solved → inProgress. `played` (solved+archived) trims to 20
    /// first, then the whole library trims to 60. In-progress boards are only
    /// ever dropped when the total cap is blown, and the current board — the
    /// most-recently-updated in-progress — is dropped last of all.
    private mutating func prune() {
        let played = entries.filter { $0.status != .inProgress }
        if played.count > Self.playedCap {
            let victims = played
                .sorted { pruneRank($0) < pruneRank($1) }
                .prefix(played.count - Self.playedCap)
                .map(\.id)
            let ids = Set(victims)
            entries.removeAll { ids.contains($0.id) }
        }
        if entries.count > Self.totalCap {
            let victims = entries
                .sorted { pruneRank($0) < pruneRank($1) }
                .prefix(entries.count - Self.totalCap)
                .map(\.id)
            let ids = Set(victims)
            entries.removeAll { ids.contains($0.id) }
        }
    }

    /// Lower rank is pruned first: archived(0) → solved(1) → inProgress(2), and
    /// within a band the oldest `updatedAt` goes first.
    private func pruneRank(_ e: LibraryEntry) -> (Int, Date) {
        let band: Int
        switch e.status {
        case .archived: band = 0
        case .solved: band = 1
        case .inProgress: band = 2
        }
        return (band, e.updatedAt)
    }

    private func isDaily(_ kind: GameKind, day: Int) -> Bool {
        if case .daily(let d) = kind { return d == day }
        return false
    }

    private func isFree(_ kind: GameKind) -> Bool {
        if case .free = kind { return true }
        return false
    }
}
