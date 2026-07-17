// SharedDailyBoard.swift — the second shared file (PRD-3 §4): today's daily
// board, readable and writable from BOTH the app and the widget extension.
// This file — not CouchStored — is the single source of truth for the daily:
// the app writes on every daily persist (revision++), the widget's
// PlaceDigitIntent does the same, and whoever reads adopts the higher
// revision (last-writer-wins; both sides only ever append moves to the same
// day's board, so a lost race costs a move, never corruption).
//
// Unlike WidgetSnapshot this type carries the Engine's NineGame, so it only
// compiles where the Engine does: the app target, the widget target (which
// gains Sources/Engine in Phase 3b), and SwiftPM (NineShared depends on
// NineEngine there).
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

/// A daily solve completed inside the widget. The widget has no CouchStored,
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

public struct SharedDailyBoard: Codable, Equatable, Sendable {
    /// Which daily this board belongs to. Anything ≠ today is stale: the
    /// widget refuses to play it and renders "new puzzle" instead.
    public var dayOrdinal: Int
    /// The Engine's full play state — entries, pencil, undo stack, timer —
    /// Codable end-to-end, so widget moves flow into the app's autosave
    /// with the undo stack intact.
    public var game: NineGame
    /// Monotonic per day; the higher revision wins on read.
    public var revision: Int
    public var updatedAt: Date
    /// Set by the widget on solve; cleared by the app after ingesting.
    public var pendingSolve: PendingSolve?

    public init(
        dayOrdinal: Int,
        game: NineGame,
        revision: Int,
        updatedAt: Date,
        pendingSolve: PendingSolve? = nil
    ) {
        self.dayOrdinal = dayOrdinal
        self.game = game
        self.revision = revision
        self.updatedAt = updatedAt
        self.pendingSolve = pendingSolve
    }

    /// The stale-day guard (PRD-3 §4).
    public func isCurrent(today: Int) -> Bool { dayOrdinal == today }
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
    /// so a leftover selection can't point into tomorrow's board.
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
}
