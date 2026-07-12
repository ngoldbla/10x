// GameScreen.swift — the board screen and the complete remote grammar
// (PRD §4.4). One focusable surface (`.couchRemote`); the cursor lives
// in-canvas; the rose is an input layer that captures gestures while open.
//
//   swipe            move cell cursor
//   click            open rose (entry) / place focused petal (rose open)
//   hold-click       open rose in pencil mode
//   flick (in rose)  place digit instantly (eight-way remotes)
//   play/pause       undo, with a glass toast showing the reverted digit
//   play/pause hold  prefs sheet
//   back             cancel rose · else save + home
import SwiftUI
import CouchKit

struct GameScreen: View {
    let model: AppModel

    @State private var chrome = ChromeVisibility()
    @State private var cursor = 40
    @State private var rose: RoseState?
    @State private var showPrefs = false
    @State private var toast: UndoToastState?
    @State private var toastDismissal: Task<Void, Never>?
    /// The most recent undo, kept briefly so a play/pause *long* press that
    /// also leaked a plain `.playPause` (RemoteKit attaches both handlers)
    /// can be rolled forward again before the prefs sheet opens.
    @State private var lastUndo: (move: NineMove, at: Date)?

    var body: some View {
        // While the prefs sheet is up, the remote surface detaches so the
        // tvOS focus engine can walk the sheet's controls; Back (handled by
        // GlassSheet) brings it home again.
        if showPrefs {
            core
        } else {
            core.couchRemote(chrome: chrome, eightWay: true, interceptsBack: true) { gesture in
                handle(gesture)
            }
        }
    }

    private var core: some View {
        ZStack {
            board
                .overlay(alignment: .topLeading) { timerChip.padding(48) }
                .overlay(alignment: .bottom) { toastView.padding(.bottom, 24) }
            completionChip
            GlassSheet(isPresented: $showPrefs) {
                PrefsSheetContent(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Board + rose

    @ViewBuilder
    private var board: some View {
        if let game = model.game {
            BoardView(
                game: game,
                cursor: cursor,
                accent: model.prefs.accent.color,
                showErrors: model.prefs.errorHighlight,
                solvedAt: model.solvedAt,
                roseOpen: rose != nil
            )
            .overlay {
                if let rose {
                    let center = BoardMetrics.center(of: cursor)
                    FlickRoseView(
                        state: rose,
                        accent: model.prefs.accent.color,
                        completedDigits: Set((1...9).filter { game.isDigitComplete($0) }),
                        showsFocusRing: RemoteKit.capability == .fourWay
                    )
                    .position(
                        x: center.x + 28, // board padding inset
                        y: center.y + 28
                    )
                }
            }
        } else {
            // Momentary state while a puzzle is composed.
            GlassChip("Composing…", systemImage: "sparkles")
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private var timerChip: some View {
        if model.prefs.showTimer, let game = model.game, model.solvedAt == nil {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                GlassChip(Self.format(game.timer.elapsed(at: timeline.date)), systemImage: "clock")
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            GlassChip(toast.text, systemImage: "arrow.uturn.backward")
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .id(toast.id)
        }
    }

    @ViewBuilder
    private var completionChip: some View {
        if let solvedAt = model.solvedAt {
            TimelineView(.periodic(from: solvedAt, by: 0.5)) { timeline in
                if timeline.date.timeIntervalSince(solvedAt) > 2.4 {
                    VStack(spacing: 24) {
                        Spacer()
                        GlassChip(completionText, systemImage: "checkmark")
                            .transition(.opacity)
                            .padding(.bottom, 90)
                    }
                    .animation(.couchAmbient, value: model.solvedAt)
                }
            }
        }
    }

    private var completionText: String {
        if case .daily? = model.kind, model.displayedStreak > 0 {
            return "Solved · \(model.displayedStreak) day streak"
        }
        return "Solved"
    }

    // MARK: - Remote grammar

    private func handle(_ gesture: CouchGesture) {
        guard model.game != nil else { return }

        if model.solvedAt != nil {
            if case .back = gesture { model.goHome() }
            return
        }

        if rose != nil {
            handleRose(gesture)
        } else {
            handleBoard(gesture)
        }
    }

    private func handleBoard(_ gesture: CouchGesture) {
        switch gesture {
        case .swipe(let direction):
            moveCursor(direction)
        case .click:
            openRose(pencil: false)
        case .holdBegan:
            // Hold on a writable empty cell = pencil rose. Hold anywhere you
            // can't write = prefs — this is also the four-way path to the
            // sheet, since `.playPauseLongPress` only exists with the 8-way
            // reader (see DEVIATIONS.md).
            if canOpenPencilRose {
                openRose(pencil: true)
            } else {
                showPrefs = true
            }
        case .playPause:
            performUndo()
        case .playPauseLongPress:
            // A long press may have leaked a `.playPause` first and undone a
            // move the player never asked to lose — roll it forward again.
            if let last = lastUndo, Date().timeIntervalSince(last.at) < 1.2 {
                redo(last.move)
            }
            showPrefs = true
        case .back:
            model.goHome()
        case .flick, .holdEnded:
            // Cardinal flicks already arrive as .swipe; acting on .flick too
            // would double-move the cursor.
            break
        }
    }

    private func handleRose(_ gesture: CouchGesture) {
        guard var state = rose else { return }
        switch gesture {
        case .flick(let direction):
            // The click that opened the rose is itself a touch; when the
            // finger lifts quickly it classifies as a center tap. Swallow
            // center flicks inside the grace window — a digit misfire is the
            // one unforgivable bug (PRD §4.3).
            if direction == .center, Date().timeIntervalSince(state.openedAt) < 0.4 {
                return
            }
            commit(digit: RoseGeometry.digit(for: direction))
        case .swipe(let direction):
            // Four-way fallback: the d-pad walks the petals. On eight-way
            // remotes the flick reader owns placement, so swipes are noise.
            if RemoteKit.capability == .fourWay {
                state.focusedIndex = RoseGeometry.moveFocus(state.focusedIndex, direction)
                rose = state
            }
        case .click:
            commit(digit: state.focusedIndex + 1)
        case .back:
            withAnimation(.couchFast) { rose = nil }
        case .playPause, .playPauseLongPress, .holdBegan, .holdEnded:
            break
        }
    }

    private var canOpenPencilRose: Bool {
        guard let game = model.game else { return false }
        return !game.isGiven(cursor) && game.entry(at: cursor) == 0
    }

    private func openRose(pencil: Bool) {
        guard let game = model.game, !game.isGiven(cursor) else { return }
        // Notes only make sense in empty cells.
        if pencil, game.entry(at: cursor) != 0 { return }
        withAnimation(.couchFast) {
            rose = RoseState(pencil: pencil)
        }
    }

    /// Re-perform an undone move (place/pencil re-apply cleanly; erase moves
    /// cannot occur — v1 has no erase gesture).
    private func redo(_ move: NineMove) {
        switch move.kind {
        case .place: model.place(move.digit, at: move.cell)
        case .pencil: model.togglePencil(move.digit, at: move.cell)
        case .erase: break
        }
        lastUndo = nil
        toastDismissal?.cancel()
        toast = nil
    }

    private func commit(digit: Int) {
        guard let state = rose else { return }
        if state.pencil {
            model.togglePencil(digit, at: cursor)
        } else {
            model.place(digit, at: cursor)
        }
        withAnimation(.couchFast) { rose = nil }
    }

    private func moveCursor(_ direction: Direction4) {
        var row = cursor / 9, col = cursor % 9
        switch direction {
        case .up: row = max(0, row - 1)
        case .down: row = min(8, row + 1)
        case .left: col = max(0, col - 1)
        case .right: col = min(8, col + 1)
        }
        cursor = row * 9 + col
    }

    private func performUndo() {
        guard let move = model.undoMove() else { return }
        let text: String
        switch move.kind {
        case .place: text = "Undid \(move.digit)"
        case .erase: text = "Restored \(move.digit)"
        case .pencil: text = "Undid note \(move.digit)"
        }
        let next = UndoToastState(text: text)
        lastUndo = (move, Date())
        withAnimation(.couchFast) { toast = next }
        toastDismissal?.cancel()
        toastDismissal = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.couchAmbient) {
                if toast?.id == next.id { toast = nil }
            }
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct UndoToastState: Equatable {
    let id = UUID()
    let text: String
}
