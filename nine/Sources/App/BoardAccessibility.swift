// BoardAccessibility.swift — PRD-19 "A Voice for the Board". The grid is one
// Canvas (BoardView.swift), which VoiceOver sees as a single opaque drawing:
// before this file, a blind player could reach every button in the chrome and
// not one of the 81 cells. The fix keeps the Canvas exactly as it is and hangs
// virtual accessibility children off it — 81 elements laid out on the same
// geometry the shader draws, labelled by the pure `BoardSpeech` formatter
// (Sources/Shared), each carrying the same grammar the sighted player has.
//
// Two design rules the rest of the file follows:
//
// 1. **No new input concept** (craft charter). The actions rotor mirrors the
//    rose one-for-one — nine digits, plus erase — and honours the pencil
//    toggle already in the control bar. A VoiceOver player and a flicking
//    player are doing the same thing through different doors.
// 2. **Never leak what the sighted player is not shown.** `showErrors` gates
//    the "wrong" word in the spoken value and the Conflicts rotor alike; with
//    error highlighting off, VoiceOver is exactly as much in the dark as the
//    screen is.
import SwiftUI
import CouchKit

/// The board's accessibility grammar, injected by whichever game screen owns
/// the cursor (each platform screen keeps its own `@State`, so this travels
/// as a value rather than reaching into `AppModel`).
///
/// Default-constructed it is *read-only*: labels and rotors, no actions. That
/// is what the tutorial's boards and the solved trophy want — still readable,
/// nothing to commit.
struct BoardAXActions {
    /// Notes mode is on, so the digit actions write pencil marks. Mirrors the
    /// control bar's pencil toggle; the action names change with it, because
    /// "Place 4" doing something other than placing a 4 is a lie.
    var pencilMode: Bool = false
    /// Move the cursor. VoiceOver focus and the visible cursor ring must not
    /// drift apart, or a sighted helper looking over a shoulder sees nothing.
    var select: (@MainActor (Int) -> Void)?
    var place: (@MainActor (_ digit: Int, _ cell: Int) -> Void)?
    var note: (@MainActor (_ digit: Int, _ cell: Int) -> Void)?
    var erase: (@MainActor (_ cell: Int) -> Void)?

    var isInteractive: Bool { place != nil || erase != nil }
}

/// The 81 synthetic elements. Never rendered — `accessibilityChildren` lays
/// this out in the modified view's coordinate space and keeps only the
/// accessibility tree, so the frames land on the drawn cells without adding a
/// single view to the render pass.
struct BoardAXGrid: View {
    let game: NineGame
    let cursor: Int
    let showErrors: Bool
    /// Side of the drawing plane; `inset` is the glass padding around it.
    /// `BoardMetrics` is board-local, the children are laid out in the padded
    /// frame, so every rect shifts by `inset` on the way out.
    let side: CGFloat
    let inset: CGFloat
    let actions: BoardAXActions

    @Namespace private var rotorSpace

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<81, id: \.self) { cell in
                element(for: cell)
            }
        }
        .frame(width: side + 2 * inset, height: side + 2 * inset, alignment: .topLeading)
        .accessibilityRotor(Text(Self.emptyRotor)) {
            ForEach(emptyCells, id: \.self) { cell in
                AccessibilityRotorEntry(Text(BoardSpeech.cellLabel(cell)), id: cell, in: rotorSpace)
            }
        }
        .accessibilityRotor(Text(Self.notesRotor)) {
            ForEach(notedCells, id: \.self) { cell in
                AccessibilityRotorEntry(Text(BoardSpeech.cellLabel(cell)), id: cell, in: rotorSpace)
            }
        }
        .accessibilityRotor(Text(Self.errorRotor)) {
            ForEach(errorCells, id: \.self) { cell in
                AccessibilityRotorEntry(Text(BoardSpeech.cellLabel(cell)), id: cell, in: rotorSpace)
            }
        }
    }

    // MARK: One cell

    private func element(for cell: Int) -> some View {
        let rect = BoardMetrics.rect(of: cell, side: side)
        let given = game.isGiven(cell)
        let playable = actions.isInteractive && !given

        return Color.clear
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX + inset, y: rect.midY + inset)
            .accessibilityElement()
            .accessibilityLabel(BoardSpeech.cellLabel(cell))
            .accessibilityValue(BoardSpeech.cellValue(cell, in: game, showErrors: showErrors))
            .accessibilityHint(playable ? BoardSpeech.cellHint(cell) : "")
            .accessibilityAddTraits(traits(cell: cell, given: given, playable: playable))
            .accessibilityRotorEntry(id: cell, in: rotorSpace)
            // Double-tap moves the cursor and nothing else. It deliberately
            // does *not* bloom the rose: the petals are a spatial flick
            // grammar with no VoiceOver equivalent worth having, and the
            // actions rotor below is the honest door to the same nine digits.
            .accessibilityAction { actions.select?(cell) }
            .accessibilityActions { cellActions(cell: cell, playable: playable) }
    }

    private func traits(cell: Int, given: Bool, playable: Bool) -> AccessibilityTraits {
        var traits: AccessibilityTraits = playable ? .isButton : .isStaticText
        // Keeps VoiceOver's "selected" chime on the cell the cursor ring is
        // drawn around, so audible and visible focus stay one thing.
        if cell == cursor { _ = traits.insert(.isSelected) }
        return traits
    }

    /// Nine digit actions plus erase — the rose, spelled out. Givens get
    /// nothing (there is nothing legal to do to them), which also keeps the
    /// actions rotor from being 81 identical menus.
    @ViewBuilder
    private func cellActions(cell: Int, playable: Bool) -> some View {
        if playable {
            // Reversed: UIKit surfaces custom actions in the reverse of the
            // order they are declared, and a rotor that offers 9 before 1 is
            // eight extra swipes for the commonest case. Verified against
            // `describe-ui`'s `custom_actions` list, not assumed.
            ForEach(Array((1...9).reversed()), id: \.self) { digit in
                Button(digitActionName(digit)) {
                    if actions.pencilMode {
                        actions.note?(digit, cell)
                    } else {
                        actions.place?(digit, cell)
                    }
                }
            }
            if game.entry(at: cell) != 0 {
                Button(Self.eraseAction) { actions.erase?(cell) }
            }
        }
    }

    private func digitActionName(_ digit: Int) -> String {
        actions.pencilMode ? "\(Self.noteAction) \(digit)" : "\(Self.placeAction) \(digit)"
    }

    // MARK: Rotor contents

    private var emptyCells: [Int] {
        (0..<81).filter { game.entry(at: $0) == 0 }
    }

    private var notedCells: [Int] {
        (0..<81).filter { game.entry(at: $0) == 0 && game.hasPencilMarks(at: $0) }
    }

    /// Empty unless the sighted board is also marking errors — see rule 2 in
    /// the file header. An empty rotor simply does not appear in VoiceOver.
    private var errorCells: [Int] {
        showErrors ? game.errorCells : []
    }

    // MARK: Phrases
    //
    // Every user-facing literal in this file sits here, next to the ones in
    // `BoardSpeech.Phrase`, so PRD-20 has one seam per file to convert to
    // `LocalizedStringResource` instead of a hunt through view code.
    private static let emptyRotor = "Empty cells"
    private static let notesRotor = "Cells with notes"
    private static let errorRotor = "Wrong digits"
    private static let placeAction = "Place"
    private static let noteAction = "Note"
    private static let eraseAction = "Erase"
}
