// PadSession.swift — the controller-locked board grammar (PRD-5 §2.1, §4 Step 2).
//
// A reference-type controller (not view `@State`) owns the pad-play state,
// because the gesture stream arrives from PadKit's reader — an external event
// source. GameScreen holds one in `@State` (the reference is stable across
// re-renders) and points `padReader.onGesture` at `handle(_:)`; every mutation
// flows through the same `AppModel` paths the remote and touch grammars use.
//
// The complete grammar, thumb-for-thumb with the rose players already know:
//   left stick     move cursor with analog momentum (glide crosses a box)
//   d-pad          single-step cursor (precision fallback)
//   right stick    flick a digit 1–9 by rose direction (the cell is always armed)
//   R3             place 5 (center petal)
//   Cross          open the visual rose (learning mode: petals + flick/d-pad)
//   Circle         erase user entry / cancel rose
//   Square         sticky pencil toggle
//   Triangle       same-number highlight of the digit under the cursor
//   L1 / R1        previous / next empty cell
//   L2 (hold)      peek — dim all but the highlighted kind
//   Options        prefs sheet
#if os(tvOS)
import SwiftUI
import CouchKit

@MainActor
@Observable
final class PadPlayController {
    @ObservationIgnored let model: AppModel
    @ObservationIgnored let haptics: ControllerHaptics

    /// The armed cell. Always writable-or-not; a right-stick flick places here.
    var cursor = 40
    /// Square toggles sticky pencil — flicks now place corner marks (PRD-5).
    var pencilSticky = false
    /// Triangle-driven same-number highlight (distinct from the remote's
    /// cursor-park highlight — the pad has a dedicated button).
    var highlightDigit: Int?
    /// L2 is held: peek dims all but the highlighted kind.
    var peekHeld = false
    /// Cross opens the visual rose for learning; a flick or d-pad+Cross places.
    var learningRose: RoseState?
    /// Ghost-rose shimmer after an ambiguous flick — the two candidate petals
    /// glow and nothing is placed (the never-misfire covenant, PRD-5 §2.1).
    var shimmer: Set<Int> = []
    /// Options opened the prefs sheet; while up, the pad drives the sheet's
    /// focus and board gestures are parked.
    var showPrefs = false

    @ObservationIgnored private var shimmerClear: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        self.haptics = ControllerHaptics(provider: model.padReader.haptics)
        self.haptics.enabled = model.prefs.controllerHaptics
    }

    /// Mirror the "Controller haptics" pref (call when it or the screen changes).
    func syncHaptics() { haptics.enabled = model.prefs.controllerHaptics }

    /// The kind to spotlight while peeking: the explicit highlight, else the
    /// digit under the cursor. Nil dims nothing.
    var peekDigit: Int? {
        guard peekHeld else { return nil }
        if let highlightDigit { return highlightDigit }
        let d = model.game?.entry(at: cursor) ?? 0
        return d != 0 ? d : nil
    }

    /// The digit a flick/click into the learning rose would place, ghosted.
    var previewDigit: Int? {
        guard let learningRose else { return nil }
        return learningRose.focusedIndex + 1
    }

    // MARK: - Gesture entry

    func handle(_ gesture: PadGesture) {
        guard model.game != nil, model.solvedAt == nil else { return }
        // With prefs up the pad navigates the sheet via the focus engine;
        // Options toggles it closed, everything else is parked.
        if showPrefs {
            if case .button(.options) = gesture { showPrefs = false }
            return
        }
        switch gesture {
        case .move(let direction, let glide):
            move(direction, glide: glide)
        case .flick(let direction):
            placeFlick(direction)
        case .flickAmbiguous(let a, let b):
            shimmerCandidates(a, b)
        case .button(let button):
            press(button)
        case .buttonUp(let button):
            if button == .l2 { peekHeld = false }
        case .connect, .disconnect:
            break
        }
    }

    // MARK: - Movement

    private func move(_ direction: Direction4, glide: Bool) {
        if var rose = learningRose {
            // In learning mode the d-pad walks the petals; the stick is ignored
            // so a stray glide can't scrub the rose.
            guard !glide else { return }
            rose.focusedIndex = RoseGeometry.moveFocus(rose.focusedIndex, direction)
            learningRose = rose
            return
        }
        let before = cursor
        cursor = BoardMetrics.moveCursor(cursor, direction, wrap: false)
        // One detent tick per box crossed while gliding (PRD-5 §2.2).
        if glide, cursor != before, boxIndex(cursor) != boxIndex(before) {
            haptics.detent()
        }
    }

    private func boxIndex(_ cell: Int) -> Int {
        let row = cell / 9, col = cell % 9
        return (row / 3) * 3 + col / 3
    }

    // MARK: - Placement

    private func placeFlick(_ direction: Direction8OrCenter) {
        clearShimmer()
        commit(digit: RoseGeometry.digit(for: direction))
    }

    private func commit(digit: Int) {
        guard let game = model.game, !game.isGiven(cursor) else { return }
        if pencilSticky {
            guard game.entry(at: cursor) == 0 else { learningRose = nil; return }
            model.togglePencil(digit, at: cursor)
            haptics.placement()
        } else {
            model.place(digit, at: cursor)
            if model.solvedAt != nil {
                haptics.solve() // the full crescendo, in hand
            } else if model.prefs.errorHighlight, model.game?.isError(at: cursor) == true {
                haptics.error() // the soft double-knock, only when error highlight is on
            } else {
                haptics.placement() // the whisper tick
            }
        }
        learningRose = nil
    }

    // MARK: - Buttons

    private func press(_ button: PadButton) {
        switch button {
        case .cross:
            // In learning mode Cross confirms the focused petal (d-pad + ✕ to
            // place); otherwise it opens the visual rose on the cursor cell.
            if let rose = learningRose {
                commit(digit: rose.focusedIndex + 1)
            } else {
                openLearningRose()
            }
        case .circle:
            if learningRose != nil {
                learningRose = nil
            } else {
                if model.erase(at: cursor) { haptics.placement() }
            }
        case .square:
            pencilSticky.toggle()
        case .triangle:
            toggleHighlight()
        case .r3:
            clearShimmer()
            commit(digit: 5) // center petal
        case .l1:
            jumpEmpty(forward: false)
        case .r1:
            jumpEmpty(forward: true)
        case .l2:
            peekHeld = true
        case .options:
            showPrefs = true
        }
    }

    private func openLearningRose() {
        guard let game = model.game, !game.isGiven(cursor) else { return }
        if pencilSticky, game.entry(at: cursor) != 0 { return } // notes need an empty cell
        learningRose = RoseState(pencil: pencilSticky)
    }

    private func toggleHighlight() {
        guard let digit = model.game?.entry(at: cursor), digit != 0 else { return }
        highlightDigit = (highlightDigit == digit) ? nil : digit
    }

    private func jumpEmpty(forward: Bool) {
        guard let game = model.game else { return }
        cursor = BoardMetrics.nextEmptyCell(from: cursor, in: game, forward: forward)
    }

    // MARK: - Ghost rose

    private func shimmerCandidates(_ a: Direction8OrCenter, _ b: Direction8OrCenter) {
        shimmer = [RoseGeometry.digit(for: a), RoseGeometry.digit(for: b)]
        shimmerClear?.cancel()
        shimmerClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            self?.shimmer = []
        }
    }

    private func clearShimmer() {
        shimmerClear?.cancel()
        if !shimmer.isEmpty { shimmer = [] }
    }

    /// Back (Menu) while playing: cancel the rose, else exit to the shelf.
    func handleBack() {
        if showPrefs { showPrefs = false; return }
        if learningRose != nil { learningRose = nil; return }
        model.goHome()
    }
}

// MARK: - Reconnect veil

/// The glass veil that freezes the board when the controller drops mid-game
/// (PRD-5 §1). The timer is paused by AppModel; reconnect resumes in place,
/// Menu exits. Purely presentational — connection state lives on the model.
struct ReconnectVeil: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Reconnect your controller")
                    .couchText(CouchTypography.title)
                Text("The board is paused. Press Menu to leave.")
                    .font(CouchTypography.body)
                    .foregroundStyle(.secondary)
            }
            .padding(72)
            .couchGlass(in: RoundedRectangle(cornerRadius: 48, style: .continuous))
        }
        .transition(.opacity)
    }
}
#endif
