// SharedBoard.swift — the app↔widget board file (PRD-3 §4, repointed
// 2026-08-02). The app mirrors the most recent in-progress classic board here
// on every persist (revision++), the widget's PlaceDigitIntent does the same,
// and whoever reads adopts the higher revision (last-writer-wins; both sides
// only ever append moves to the same board, so a lost race costs a move,
// never corruption).
//
// The daily is gone; the join key back to the app's library is `entryID`
// rather than a day ordinal, so the ingest cannot misfile a widget's moves.
//
// Unlike WidgetSnapshot this type carries the Engine's NineGame, so it only
// compiles where the Engine does: the app target, the widget target and
// SwiftPM (NineShared depends on NineEngine there).
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

/// A solve completed inside the widget. The widget has no CouchStored,
/// no Game Center and no history — it parks the fact here and the app
/// ingests it (exactly once) on next activation.
public struct PendingSolve: Codable, Equatable, Sendable {
    public var solvedAt: Date
    public var seconds: TimeInterval

    public init(solvedAt: Date, seconds: TimeInterval) {
        self.solvedAt = solvedAt
        self.seconds = seconds
    }
}

/// The shared board. The type keeps its wire name (`SharedDailyBoard`) and
/// its file name so an update over an old install reads the old file cleanly;
/// a blob written by a pre-removal build carries no `entryID` and decodes
/// with it nil, which every reader treats as "no board".
public struct SharedDailyBoard: Codable, Equatable, Sendable {
    /// The library entry this board mirrors — the app's join key. Nil when
    /// the file was written by an older build; such a board is never adopted.
    public var entryID: UUID?
    /// The day the board was last written on. Kept for wire compatibility
    /// (older builds keyed their stale-day guard on it) and still what the
    /// widget's ephemeral cell selection is keyed against.
    public var dayOrdinal: Int
    /// The Engine's full play state — entries, pencil, undo stack, timer —
    /// Codable end-to-end, so widget moves flow into the app's autosave
    /// with the undo stack intact.
    public var game: NineGame
    /// Monotonic; the higher revision wins on read.
    public var revision: Int
    public var updatedAt: Date
    /// Set by the widget on solve; cleared by the app after ingesting.
    public var pendingSolve: PendingSolve?

    public init(
        entryID: UUID?,
        dayOrdinal: Int,
        game: NineGame,
        revision: Int,
        updatedAt: Date,
        pendingSolve: PendingSolve? = nil
    ) {
        self.entryID = entryID
        self.dayOrdinal = dayOrdinal
        self.game = game
        self.revision = revision
        self.updatedAt = updatedAt
        self.pendingSolve = pendingSolve
    }

    /// Tolerant on `entryID` alone: a pre-removal file has no such key and
    /// must still decode (as an unadoptable board) rather than throw.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entryID = ((try? c.decodeIfPresent(UUID.self, forKey: .entryID)) ?? nil) ?? nil
        dayOrdinal = try c.decode(Int.self, forKey: .dayOrdinal)
        game = try c.decode(NineGame.self, forKey: .game)
        revision = try c.decode(Int.self, forKey: .revision)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        pendingSolve = try c.decodeIfPresent(PendingSolve.self, forKey: .pendingSolve)
    }

    enum CodingKeys: String, CodingKey {
        case entryID, dayOrdinal, game, revision, updatedAt, pendingSolve
    }
}

/// Reads/writes the board in the app group, same conventions as
/// WidgetSnapshotStore (atomic writes, sorted-keys JSON, no CouchKit).
public enum SharedDailyBoardStore {
    public static let boardFileName = "daily-board.json"

    public static var boardURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupID)?
            .appendingPathComponent(boardFileName)
    }

    public static func load(from url: URL? = boardURL) -> SharedDailyBoard? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedDailyBoard.self, from: data)
    }

    public static func save(_ board: SharedDailyBoard, to url: URL? = boardURL) throws {
        guard let url else { throw CocoaError(.fileWriteUnknown) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(board).write(to: url, options: .atomic)
    }

    public static func delete(at url: URL? = boardURL) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Widget-side cell selection (ephemeral, UserDefaults CA92.1)

    static let selectionCellKey = "nine.widget.selection.cell"
    static let selectionDayKey = "nine.widget.selection.day"

    /// The selected cell for `today`, or nil. Selection is keyed to the day
    /// so a leftover selection can't point into a board adopted later.
    public static func selectedCell(today: Int, defaults: UserDefaults? = groupDefaults) -> Int? {
        guard let defaults,
              defaults.object(forKey: selectionCellKey) != nil,
              defaults.integer(forKey: selectionDayKey) == today
        else { return nil }
        let cell = defaults.integer(forKey: selectionCellKey)
        return (0..<81).contains(cell) ? cell : nil
    }

    public static func setSelectedCell(_ cell: Int?, today: Int, defaults: UserDefaults? = groupDefaults) {
        guard let defaults else { return }
        if let cell {
            defaults.set(cell, forKey: selectionCellKey)
            defaults.set(today, forKey: selectionDayKey)
        } else {
            defaults.removeObject(forKey: selectionCellKey)
            defaults.removeObject(forKey: selectionDayKey)
        }
    }

    public static var groupDefaults: UserDefaults? {
        UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)
    }

    // MARK: - App-ingested revision (persisted — fixes the cold-launch clobber)

    static let knownRevisionKey = "nine.widget.knownBoardRevision"

    /// The highest board revision the app has already ingested. Persisted in
    /// the app group so a *cold* launch doesn't re-adopt (and clobber) a
    /// partial: the counter used to live only in memory (`WidgetBridge.
    /// knownBoardRevision`), resetting to 0 every process, so each launch
    /// re-ingested the same widget moves over a fresh free-play game.
    public static func knownRevision(defaults: UserDefaults? = groupDefaults) -> Int {
        defaults?.integer(forKey: knownRevisionKey) ?? 0
    }

    public static func setKnownRevision(_ revision: Int, defaults: UserDefaults? = groupDefaults) {
        defaults?.set(revision, forKey: knownRevisionKey)
    }
}
