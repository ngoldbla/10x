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
//
// The tree is two levels deep, not flat, and that is the whole Switch Control
// story: nine box containers, nine cells each. See `BoardAXGrid.body`.
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
    /// Activate a cell: move the cursor, and — for the assistive technologies
    /// that have no actions rotor — open the digit ring, exactly as a tap
    /// does. The screen decides which half applies; see `TouchGameScreen`.
    ///
    /// VoiceOver focus and the visible cursor ring must not drift apart, or a
    /// sighted helper looking over a shoulder sees nothing.
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
    /// `BoardMetrics` is board-local and the children are laid out in the
    /// padded frame, so the nine box containers shift by `inset` on the way out
    /// and each cell is then placed relative to its own box.
    let side: CGFloat
    let inset: CGFloat
    let actions: BoardAXActions

    @Namespace private var rotorSpace

    var body: some View {
        // Nine box containers, nine cells each — nested rather than flat
        // because that hierarchy *is* Switch Control's group scan (there is no
        // separate grouping API; iOS derives groups from the accessibility
        // container tree). Item scanning a flat 81 costs up to 81 switch hits
        // to reach one cell; boxes → cells costs at most 9 + 9.
        //
        // VoiceOver's swipe order follows the same tree, so it now reads
        // box-major instead of row-major. That is a deliberate trade — see
        // DEVIATIONS — and the cost is nil for orientation because every cell
        // still announces its own row and column, while the Empty / Notes /
        // Wrong rotors below stay strictly row-major.
        ZStack(alignment: .topLeading) {
            ForEach(0..<9, id: \.self) { box in
                boxGroup(box)
            }
        }
        .frame(width: side + 2 * inset, height: side + 2 * inset, alignment: .topLeading)
        // The board is drawn by a `Canvas`, and a Canvas draws in raw
        // coordinates — it does not mirror under a right-to-left layout, which
        // is what PRD-20 decision 3 wants: the grid is spatial and numeric, not
        // text, so column 1 stays on the left in every language. But
        // `.position(x:y:)` *is* direction-aware, so every one of these 81
        // synthetic frames mirrored while the pixels stayed put, and in Arabic
        // the element under the left-hand cell announced `column 9`. Measured,
        // not reasoned: `Row 1, column 1` sat at x=342 with the digit 4 drawn
        // at x=20. Pinning the layout direction makes `.position` mean what the
        // Canvas means.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityRotor(Text(BoardActionPhrase.emptyRotor)) {
            ForEach(emptyCells, id: \.self) { cell in
                AccessibilityRotorEntry(Text(BoardSpeech.cellLabel(cell)), id: cell, in: rotorSpace)
            }
        }
        .accessibilityRotor(Text(BoardActionPhrase.notesRotor)) {
            ForEach(notedCells, id: \.self) { cell in
                AccessibilityRotorEntry(Text(BoardSpeech.cellLabel(cell)), id: cell, in: rotorSpace)
            }
        }
        .accessibilityRotor(Text(BoardActionPhrase.errorRotor)) {
            ForEach(errorCells, id: \.self) { cell in
                AccessibilityRotorEntry(Text(BoardSpeech.cellLabel(cell)), id: cell, in: rotorSpace)
            }
        }
    }

    // MARK: One box

    /// A group-scan stop. The container is laid out on the real 3×3 block, so
    /// Switch Control's group highlight frames the box the player can see
    /// rather than the whole board, and the nine cells inside keep their exact
    /// absolute frames (box origin + cell offset within the box).
    ///
    /// `children: .contain` makes it a *container*, not an element: VoiceOver
    /// walks straight through to the cells and never adds nine extra stops.
    private func boxGroup(_ box: Int) -> some View {
        let frame = BoardMetrics.boxRect(of: box, side: side)
        return ZStack(alignment: .topLeading) {
            ForEach(BoardMetrics.cells(inBox: box), id: \.self) { cell in
                element(for: cell, in: frame)
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .position(x: frame.midX + inset, y: frame.midY + inset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(BoardSpeech.boxGroupLabel(box))
        .accessibilityValue(BoardSpeech.boxGroupValue(box, in: game))
    }

    // MARK: One cell

    /// - Parameter box: the enclosing box's board-local block. Cell rects are
    ///   board-local, the container is placed at the box, so the offset
    ///   subtracts out — the absolute frame is unchanged by the nesting, which
    ///   is what keeps the AX-tree baselines stable across this refactor.
    private func element(for cell: Int, in box: CGRect) -> some View {
        let rect = BoardMetrics.rect(of: cell, side: side)
        let given = game.isGiven(cell)
        let playable = actions.isInteractive && !given

        return Color.clear
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX - box.minX, y: rect.midY - box.minY)
            .accessibilityElement()
            .accessibilityLabel(BoardSpeech.cellLabel(cell))
            .accessibilityValue(BoardSpeech.cellValue(cell, in: game, showErrors: showErrors))
            .accessibilityHint(playable ? BoardSpeech.cellHint(cell) : "")
            .accessibilityAddTraits(traits(cell: cell, given: given, playable: playable))
            // Voice Control's vocabulary for the cell. Without these it would
            // inherit the label — "Row 3, comma, column 5" — which a speech
            // recogniser can never produce, leaving all 81 cells unaddressable.
            .accessibilityInputLabels(BoardSpeech.cellInputLabels(cell))
            .accessibilityRotorEntry(id: cell, in: rotorSpace)
            // Under VoiceOver, activation moves the cursor and nothing else:
            // the petals are a spatial flick grammar with no VoiceOver
            // equivalent worth having, and the actions rotor below is the
            // honest door to the same nine digits. Voice Control, Switch
            // Control and Full Keyboard Access have no rotor, so for them the
            // same activation also blooms the rose — see `select`'s doc and
            // `TouchGameScreen.axActivate`.
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
            // Declared backwards, on purpose. UIKit surfaces custom actions in
            // the reverse of declaration order, so this whole block reads
            // bottom-up: erase first here means erase *last* in the rotor, and
            // `9...1` here means `Place 1` is the first thing offered. A rotor
            // that offers 9 before 1 is eight extra swipes for the commonest
            // case, and one that offers Erase before any digit puts a
            // destructive action under the very first swipe of a filled cell.
            // Verified against `describe-ui`'s `custom_actions` list and
            // frozen in the AX baselines, not assumed — on iOS. **The reversal
            // is a UIKit behaviour and this block is platform-shared**: the Mac
            // supplies non-nil `place`/`erase` too, so it emits the same list,
            // and whether AppKit reverses it is unverified (there is no macOS
            // AX-dump harness, and VoiceOver's Mac rotor cannot be read from a
            // script). If it does not reverse, the Mac reads Erase first. Left
            // unforked deliberately rather than split on a guess — a `#if` that
            // guessed wrong would be the same bug with more code. Recorded in
            // DEVIATIONS; the fix, if a manual pass shows it, is a one-line
            // `#if os(macOS)` swap of these two blocks.
            if game.entry(at: cell) != 0 {
                Button(BoardActionPhrase.erase) { actions.erase?(cell) }
            }
            ForEach(Array((1...9).reversed()), id: \.self) { digit in
                Button(digitActionName(digit)) {
                    if actions.pencilMode {
                        actions.note?(digit, cell)
                    } else {
                        actions.place?(digit, cell)
                    }
                }
            }
        }
    }

    /// A whole-sentence key per action, not a verb concatenated with a numeral.
    /// The old form built "Place" + " " + digit, which is unsayable in any
    /// language that puts the object first — and the same two keys label the
    /// rose's petals (`FlickRoseView`), so a VoiceOver player and a flicking
    /// player hear one vocabulary.
    private func digitActionName(_ digit: Int) -> String {
        actions.pencilMode ? BoardActionPhrase.note(digit) : BoardActionPhrase.place(digit)
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

}

/// Every user-facing literal in this file, in one block (PRD-20's seam), next
/// to the ones in `BoardSpeech.Phrase`.
///
/// File-scope rather than nested in `BoardAXGrid` because `FlickRoseView` reads
/// the same three digit actions: the rose's petals and the actions rotor are
/// two doors onto one grammar (craft charter, "no new input concept"), and two
/// copies of "Place 4" is two things for a translator to disagree with itself
/// about.
enum BoardActionPhrase {
    static let emptyRotor = Strings.string("board.rotor.empty")
    static let notesRotor = Strings.string("board.rotor.notes")
    static let errorRotor = Strings.string("board.rotor.errors")
    static let erase = Strings.string("board.action.erase")
    static func place(_ digit: Int) -> String {
        Strings.string("board.action.place", .int(digit))
    }
    static func note(_ digit: Int) -> String {
        Strings.string("board.action.note", .int(digit))
    }
    /// A rose petal whose digit is already in the cell (placement mode) or
    /// already pencilled in (pencil mode) — the petal that used to sit beside
    /// a tenth "erase" petal now carries this label itself and erases when
    /// tapped, rather than re-placing. Says only that the digit is here,
    /// never that it is wrong.
    static func eraseDigit(_ digit: Int) -> String {
        Strings.string("board.rose.eraseDigit", .int(digit))
    }
}
