// BoardIntents.swift — the two App Intents behind the playable widget
// (PRD-3 §4). Every tap routes through here (~100-500ms); the real Engine
// `place()` runs in-process on the shared board value. The widget never
// generates puzzles and never touches history/Game Center — a solve
// parks a PendingSolve for the app to ingest.
import AppIntents
import Foundation
import WidgetKit

// MARK: - Configuration (PRD-33)

/// Which side of a medium board widget the digit pad sits on.
///
/// **This is handedness**, which `DEVIATIONS.md` recorded as deferred at the end
/// of PRD-31: "Left-handed players get the worse half of the
/// controls-lead/stats-trail decision. A handedness row is a settings row and the
/// covenant makes those expensive."
///
/// A widget configuration is not a settings row. It is per *placed widget*,
/// edited in the system's own long-press sheet, and it costs the app no chrome at
/// all — which is why it is the one parameter worth having today. The value of
/// having it is also the substrate: PRD-24's Channels need exactly this
/// `AppIntentConfiguration`, and adding a `channel` parameter to an intent that
/// already exists is a smaller change than converting a `StaticConfiguration`
/// while people have the widget on their Home Screen.
enum RailSide: String, AppEnum {
    case trailing, leading

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent.railSide.title", table: IntentStrings.table)
    )

    /// Written out rather than built from `rawValue`: an interpolated key would
    /// also be invisible to `appintentsmetadataprocessor`, which is a static
    /// extractor — see `IntentStrings`.
    static let caseDisplayRepresentations: [RailSide: DisplayRepresentation] = [
        .trailing: DisplayRepresentation(
            title: LocalizedStringResource("intent.railSide.trailing", table: IntentStrings.table)
        ),
        .leading: DisplayRepresentation(
            title: LocalizedStringResource("intent.railSide.leading", table: IntentStrings.table)
        ),
    ]
}

/// The board widget's configuration. One parameter today; see `RailSide`.
struct BoardWidgetConfiguration: WidgetConfigurationIntent {
    static let title = LocalizedStringResource(
        "intent.boardWidget.title", table: IntentStrings.table
    )
    static let description = IntentDescription(
        LocalizedStringResource("intent.boardWidget.description", table: IntentStrings.table)
    )

    @Parameter(
        title: LocalizedStringResource("intent.railSide.title", table: IntentStrings.table),
        default: .trailing
    )
    var railSide: RailSide

    init() {}

    init(railSide: RailSide) {
        self.railSide = railSide
    }
}

// MARK: - Play

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
        guard let board = SharedDailyBoardStore.load(), board.entryID != nil,
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
        guard var board = SharedDailyBoardStore.load(), board.entryID != nil else {
            // No adoptable board: refuse; the reload re-renders "tap to start".
            SharedDailyBoardStore.setSelectedCell(nil, today: today)
            return .result()
        }
        guard !board.game.isSolved, board.pendingSolve == nil,
              let cell = SharedDailyBoardStore.selectedCell(today: today),
              board.game.place(digit, at: cell)
        else { return .result() }
        board.revision += 1
        board.updatedAt = now

        // Keep the snapshot honest about widget-made progress.
        var snapshot = WidgetSnapshotStore.load() ?? WidgetSnapshot()
        snapshot.boardFillFraction = board.game.fillFraction
        snapshot.generatedAt = now

        if board.game.isSolved {
            let seconds = board.game.timer.elapsed(at: now)
            board.pendingSolve = PendingSolve(solvedAt: now, seconds: seconds)
            // Optimistic display only — history/Game Center are recorded when
            // the app next activates and ingests (honest caveat: Game Center
            // lags until then).
            snapshot.boardSolvedSeconds = seconds
            snapshot.boardFillFraction = nil
            SharedDailyBoardStore.setSelectedCell(nil, today: today)
        }

        try? SharedDailyBoardStore.save(board)
        try? WidgetSnapshotStore.save(snapshot)
        // The tapped widget reloads automatically; an explicit nudge keeps
        // any second placed widget in step.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
