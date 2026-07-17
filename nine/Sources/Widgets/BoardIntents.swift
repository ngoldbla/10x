// BoardIntents.swift — the two App Intents behind the playable widget
// (PRD-3 §4). Every tap routes through here (~100-500ms); the real Engine
// `place()` runs in-process on the shared board value. The widget never
// generates puzzles and never touches streak/history/Game Center — a solve
// parks a PendingSolve for the app to ingest.
import AppIntents
import Foundation
import WidgetKit

/// Tap a cell: select it (tap again to deselect). Givens are never
/// selectable. Selection is ephemeral UserDefaults state keyed to the day
/// (privacy manifest reason CA92.1).
struct SelectCellIntent: AppIntent {
    static let title: LocalizedStringResource = "Select Cell"
    static let isDiscoverable = false

    @Parameter(title: "Cell")
    var cell: Int

    init() {}

    init(cell: Int) {
        self.cell = cell
    }

    func perform() async throws -> some IntentResult {
        let today = WidgetSnapshotStore.dayOrdinal(for: Date())
        guard let board = SharedDailyBoardStore.load(), board.isCurrent(today: today),
              (0..<81).contains(cell), !board.game.isGiven(cell)
        else { return .result() }
        let current = SharedDailyBoardStore.selectedCell(today: today)
        SharedDailyBoardStore.setSelectedCell(current == cell ? nil : cell, today: today)
        return .result()
    }
}

/// Tap a digit: place it in the selected cell via the real Engine move.
/// Selection survives placement for fast consecutive entry. No erase in v1.
struct PlaceDigitIntent: AppIntent {
    static let title: LocalizedStringResource = "Place Digit"
    static let isDiscoverable = false

    @Parameter(title: "Digit")
    var digit: Int

    init() {}

    init(digit: Int) {
        self.digit = digit
    }

    func perform() async throws -> some IntentResult {
        let now = Date()
        let today = WidgetSnapshotStore.dayOrdinal(for: now)
        guard var board = SharedDailyBoardStore.load(), board.isCurrent(today: today) else {
            // Stale-day guard: refuse; the reload re-renders "new puzzle".
            SharedDailyBoardStore.setSelectedCell(nil, today: today)
            return .result()
        }
        guard !board.game.isSolved, board.pendingSolve == nil,
              let cell = SharedDailyBoardStore.selectedCell(today: today),
              board.game.place(digit, at: cell)
        else { return .result() }
        board.revision += 1
        board.updatedAt = now

        // Keep the glanceable widgets honest about widget-made progress.
        var snapshot = WidgetSnapshotStore.load() ?? WidgetSnapshot()
        snapshot.dailyDayOrdinal = today
        snapshot.dailyFillFraction = board.game.fillFraction
        snapshot.generatedAt = now

        if board.game.isSolved {
            let seconds = board.game.timer.elapsed(at: now)
            board.pendingSolve = PendingSolve(solvedAt: now, seconds: seconds)
            // Optimistic display only — streak/history/Game Center are
            // recorded when the app next activates and ingests (honest
            // caveat: Game Center lags until then).
            snapshot.dailySolvedSeconds = seconds
            if snapshot.lastCompletedDay == today - 1 {
                snapshot.streakCurrent += 1
            } else if snapshot.lastCompletedDay != today {
                snapshot.streakCurrent = 1
            }
            snapshot.streakBest = max(snapshot.streakBest, snapshot.streakCurrent)
            snapshot.lastCompletedDay = today
            SharedDailyBoardStore.setSelectedCell(nil, today: today)
        }

        try? SharedDailyBoardStore.save(board)
        try? WidgetSnapshotStore.save(snapshot)
        // The tapped widget reloads automatically; the small/medium/lock
        // widgets need an explicit nudge to pick up the new fill/solve.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
