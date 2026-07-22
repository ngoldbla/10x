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
//
// PRD-5 adds the pad session: when `model.padSession` is on, RemoteKit gestures
// are ignored (Menu still exits), and PadKit's reader drives the SAME AppModel
// mutation paths through `PadPlayController`. One master at a time, by design.
import SwiftUI
import CouchKit

#if os(tvOS)
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
    /// The settings-discoverability chip, flashed on the first board of a
    /// session (the once-per-launch gate lives on the model).
    @State private var showHint = false

    // MARK: Pad session (PRD-5)
    /// The controller-locked play state. A reference type (not `@State` value)
    /// because PadKit's gesture stream is an external event source; the
    /// reference is stable across re-renders so `padReader.onGesture` can point
    /// at it once.
    @State private var pad: PadPlayController
    /// The five-beat pad tutorial, shown on the first pad session ever.
    @State private var padTutorial = PadTutorialModel()
    @State private var showPadTutorial = false

    @Environment(\.colorScheme) private var colorScheme

    init(model: AppModel) {
        self.model = model
        _pad = State(initialValue: PadPlayController(model: model))
    }

    /// The accent resolved for the theme's leaning (themes pin the scheme).
    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    var body: some View {
        Group {
            if model.padSession {
                padBody
            } else {
                remoteBody
            }
        }
    }

    // MARK: - Remote body (unchanged grammar)

    @ViewBuilder
    private var remoteBody: some View {
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
                .overlay(alignment: .bottom) { hintView.padding(.bottom, 108) }
            completionChip
            GlassSheet(isPresented: $showPrefs) {
                // New Game ships for remote players too (PRD-5 §2.3: a widened
                // gate lands for everyone, not just the pad).
                PrefsSheetContent(model: model, onNewGame: { difficulty in
                    showPrefs = false
                    cursor = 40
                    model.startFree(difficulty)
                })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { flashHint() }
    }

    // MARK: - Pad body (PRD-5)

    @ViewBuilder
    private var padBody: some View {
        Group {
            // Prefs and the tutorial own the focus engine while up, so the
            // board surface detaches (the prefs-sheet detach pattern).
            if pad.showPrefs || showPadTutorial {
                padCore
            } else {
                padCore.couchRemote(chrome: chrome, interceptsBack: true) { gesture in
                    // A pad session ignores every board gesture from the
                    // remote; only Menu/Back still leaves (save + home).
                    if case .back = gesture { pad.handleBack() }
                }
            }
        }
        .onAppear {
            showPadTutorial = !model.padTutorialSeen
            pad.syncHaptics()
            syncPadRouting()
        }
        .onDisappear { model.padReader.onGesture = nil }
        .onChange(of: showPadTutorial) { syncPadRouting() }
        .onChange(of: pad.showPrefs) { syncPadRouting() }
        .onChange(of: model.prefs.controllerHaptics) { pad.syncHaptics() }
        .onChange(of: padTutorial.finished) { _, done in
            guard done else { return }
            model.padTutorialSeen = true
            showPadTutorial = false
        }
        // Disconnect mid-game freezes the board and pauses the timer; reconnect
        // resumes in place (PRD-5 §1).
        .onChange(of: model.padConnected) { _, connected in
            guard model.padSession else { return }
            if connected { model.resumePadTimer() } else { model.pausePadTimer() }
        }
    }

    private var padCore: some View {
        ZStack {
            padBoard
                .overlay(alignment: .topLeading) { timerChip.padding(48) }
                .overlay(alignment: .top) { padModeChip.padding(.top, 48) }
            completionChip
            if !model.padConnected {
                ReconnectVeil()
            }
            GlassSheet(isPresented: padPrefsBinding) {
                PrefsSheetContent(model: model, onNewGame: startPadNewGame)
            }
            if showPadTutorial {
                PadTutorialView(model: padTutorial, accent: accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var padPrefsBinding: Binding<Bool> {
        Binding(get: { pad.showPrefs }, set: { pad.showPrefs = $0 })
    }

    /// Point the reader at whichever surface is live: the tutorial while it
    /// teaches, the board otherwise. Both targets are stable references.
    private func syncPadRouting() {
        guard model.padSession else { model.padReader.onGesture = nil; return }
        if showPadTutorial {
            model.padReader.onGesture = { [padTutorial] gesture in padTutorial.handle(gesture) }
        } else {
            model.padReader.onGesture = { [pad] gesture in pad.handle(gesture) }
        }
    }

    private func startPadNewGame(_ difficulty: Difficulty) {
        pad.showPrefs = false
        pad.highlightDigit = nil
        pad.learningRose = nil
        pad.cursor = 40
        model.startFree(difficulty) // keeps padSession on
    }

    @ViewBuilder
    private var padModeChip: some View {
        if pad.pencilSticky {
            GlassChip("Pencil", systemImage: "pencil")
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var padBoard: some View {
        if let game = model.game {
            BoardView(
                game: game,
                cursor: pad.cursor,
                accent: accent,
                showErrors: model.prefs.errorHighlight,
                solvedAt: model.solvedAt,
                roseOpen: pad.learningRose != nil,
                previewDigit: pad.previewDigit,
                previewPencil: pad.learningRose?.pencil ?? false,
                // Same-number highlight is the Triangle toggle in a pad session.
                highlightDigit: model.prefs.numberHighlight ? pad.highlightDigit : nil,
                dimmedExcept: pad.peekDigit,
                // Gyro trophy: DualSense/DualShock tilt steers the sheen after
                // the sweep settles (PRD-5 §2.2). No motion → a calm centered
                // highlight, which keeps the loop alive but harmless.
                waveOrigin: model.lastPlacedCell,
                afterglowTilt: { model.padReader.motionTilt(at: $0) }
            )
            .overlay { padRoseOverlay(game: game) }
        } else {
            GlassChip("Composing…", systemImage: "sparkles")
        }
    }

    @ViewBuilder
    private func padRoseOverlay(game: NineGame) -> some View {
        let center = BoardMetrics.center(of: pad.cursor)
        if let rose = pad.learningRose {
            FlickRoseView(
                state: rose,
                accent: accent,
                completedDigits: Set((1...9).filter { game.isDigitComplete($0) }),
                showsFocusRing: true
            )
            .position(x: center.x + 28, y: center.y + 28)
        } else if !pad.shimmer.isEmpty {
            // Ghost rose: the two candidate petals shimmer, nothing placed.
            FlickRoseView(
                state: RoseState(pencil: false, shimmerDigits: pad.shimmer),
                accent: accent,
                completedDigits: [],
                showsFocusRing: false
            )
            .position(x: center.x + 28, y: center.y + 28)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Board + rose (remote)

    @ViewBuilder
    private var board: some View {
        if let game = model.game {
            BoardView(
                game: game,
                cursor: cursor,
                accent: accent,
                showErrors: model.prefs.errorHighlight,
                solvedAt: model.solvedAt,
                roseOpen: rose != nil,
                previewDigit: previewDigit,
                previewPencil: rose?.pencil ?? false,
                // Same-number highlight, remote grammar: parking the cursor
                // on a digit lights up all of its kind (notes included).
                highlightDigit: model.prefs.numberHighlight && game.entry(at: cursor) != 0
                    ? game.entry(at: cursor) : nil,
                // Afterglow: the wave detonates from the winning cell; no
                // tilt source on tvOS — the sheen settles and the loop stops.
                waveOrigin: model.lastPlacedCell
            )
            .overlay {
                if let rose {
                    let center = BoardMetrics.center(of: cursor)
                    FlickRoseView(
                        state: rose,
                        accent: accent,
                        completedDigits: Set((1...9).filter { game.isDigitComplete($0) }),
                        showsFocusRing: true
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

    /// The digit a click would place right now, ghosted into the selected
    /// cell. Live on every remote: swipes walk the petals everywhere, and
    /// even on eight-way remotes the click path needs an honest preview.
    private var previewDigit: Int? {
        guard let rose else { return nil }
        return rose.focusedIndex + 1
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
    private var hintView: some View {
        if showHint {
            GlassChip("Click a cell for digits · Hold ▶︎ for settings", systemImage: "questionmark.circle")
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// Flash the settings-discoverability chip once per launch, on the first
    /// board only (session-scoped by design — never persisted).
    private func flashHint() {
        guard !model.hintFlashed else { return }
        model.hintFlashed = true
        withAnimation(.couchFast) { showHint = true }
        Task {
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            withAnimation(.couchAmbient) { showHint = false }
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
            // The d-pad always walks the petals — on every remote. Real Siri
            // Remotes report eight-way, but the flick classifier drops
            // ambiguous strokes on the floor, so swiping with a visible
            // ring + preview is the path players can always trust; a clean
            // flick still places instantly above.
            state.focusedIndex = RoseGeometry.moveFocus(state.focusedIndex, direction)
            rose = state
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

#endif

/// Undo feedback shared by the TV and touch game screens.
struct UndoToastState: Equatable {
    let id = UUID()
    let text: String
}
