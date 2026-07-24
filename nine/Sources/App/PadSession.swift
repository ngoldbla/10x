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
//   L2 / R2 (hold) peek — dim all but the highlighted kind
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
    /// The glass toast shown after a Circle-tap undo (mirrors the remote's
    /// undo toast; auto-clears like `shimmer`).
    var undoToast: UndoToastState?

    @ObservationIgnored private var shimmerClear: Task<Void, Never>?
    @ObservationIgnored private var undoToastClear: Task<Void, Never>?
    /// Circle is a tap/hold: a hold task fires an erase; a release before it
    /// fires is an undo. `circleConsumed` stops the release from double-acting.
    @ObservationIgnored private var circleHold: Task<Void, Never>?
    private var circleConsumed = false
    /// Hold threshold before Circle switches from undo (tap) to erase.
    private static let circleHoldThreshold: UInt64 = 400_000_000

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
            switch button {
            case .l2, .r2: peekHeld = false // R2 is a first-class peek alias (Phase 3)
            case .circle: circleUp()
            default: break
            }
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
            circleDown()
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
        case .l2, .r2:
            // Peek is held on either trigger — R2 is a first-class alias of L2
            // so right-handed players get the same reach (PRD-5 Phase 3).
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

    // MARK: - Circle: tap undoes, hold erases

    private func circleDown() {
        circleConsumed = false
        // Rose open: Circle still cancels it immediately (unchanged feel), and
        // the release must not then undo.
        if learningRose != nil {
            learningRose = nil
            circleConsumed = true
            return
        }
        // Arm the hold: if Circle is still down past the threshold, erase.
        circleHold?.cancel()
        circleHold = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.circleHoldThreshold)
            guard !Task.isCancelled, let self else { return }
            self.circleConsumed = true
            if self.model.erase(at: self.cursor) { self.haptics.placement() }
        }
    }

    private func circleUp() {
        circleHold?.cancel()
        circleHold = nil
        // A hold (or a rose-cancel) already acted — the release is a no-op.
        guard !circleConsumed else { circleConsumed = false; return }
        performUndo()
    }

    /// Take back the last move with a glass toast (mirrors the remote screen's
    /// play/pause undo; the toast auto-clears like `shimmer`).
    private func performUndo() {
        guard let move = model.undoMove() else { return }
        let text: String
        switch move.kind {
        case .place: text = "Undid \(move.digit)"
        case .erase: text = "Restored \(move.digit)"
        case .pencil: text = "Undid note \(move.digit)"
        }
        haptics.placement()
        let next = UndoToastState(text: text)
        undoToast = next
        undoToastClear?.cancel()
        undoToastClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            if self?.undoToast?.id == next.id { self?.undoToast = nil }
        }
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

// The reconnect veil is retired (PRD-5 revised): a controller drop mid-game now
// falls back to the remote grammar in place with a brief chip, timer running —
// see GameScreen.fallBackToRemote(). No pause, no modal freeze.
#endif
