// BoardFingerprint.swift — PRD-22. The home shelf used to identify every
// saved board with a `GlassRing`, whose lit arc is `trim(from: 0, to:
// progress)`: at 0% it draws nothing, so a board you generated and have not
// touched appears as a dead gray circle beside the literal text "0%". Three
// boards in that state are three identical dead circles, which is the exact
// opposite of "which board was that one".
//
// A sudoku board already carries a free, deterministic, unique portrait: its
// givens. Seeds are deterministic, so the constellation costs nothing to
// derive and never needs storing — and it changes as you play, because your
// entries light up in the accent. Progress stops being a number you read and
// becomes the picture filling in.
//
// The zero-state is honest rather than fake (craft charter): an untouched
// board shows only its givens and says "Untouched", never "0%".
import SwiftUI
import CouchKit

/// The geometry every board-derived picture *outside* `BoardView` shares.
///
/// Four Canvases draw a sudoku board here — `MiniBoard`, `BoardFingerprint`,
/// `SolvedGridThumb` and `CometView` — and until this type existed each one
/// re-derived its own cell origin, its own corner radius and its own inset. The
/// two thumbnails had **no box gutter at all**, which is why they read as
/// halftone swatches rather than as sudoku: a 9×9 field of evenly spaced dots
/// is a dither pattern, and the entire difference between that and a board is
/// two visible seams per axis.
///
/// `BoardType` (DesignTokens) already owns how big a digit is relative to its
/// cell. This owns where the cell *is*.
enum BoardArt {
    /// The seam at a 3×3 boundary, as a fraction of the square's side, for the
    /// **thumbnails** — `MiniBoard` and `BoardFingerprint`. At 34 pt this is a
    /// 1.19 pt gutter against a 3.51 pt cell, which takes the dot-to-dot gap
    /// from 1.48 pt to 2.66 pt across a box boundary: 1.8× is enough for the
    /// eye to find the three bands without a rule being drawn at all.
    static let thumbGutter: CGFloat = 0.035
    /// The same seam on the **exported** card and the comet, where the digits
    /// are 53 pt and carry the structure themselves so the gap only has to be
    /// present. Unchanged from what those two shipped.
    static let cardGutter: CGFloat = 0.018
    /// The corner radius of one cell's wash, as a fraction of the cell. Was
    /// written out three times across `SolvedGridThumb` and `CometView`.
    static let cellCorner: CGFloat = 0.16
    /// How far a cell's wash sits inside its own cell, as a fraction of it.
    /// The other of the two ratios those three call sites each carried a copy of.
    static let cellInset: CGFloat = 0.035

    /// The side of one cell in a square of `side` points carrying `gutter`-point
    /// seams at the two interior box boundaries.
    static func cell(side: CGFloat, gutter: CGFloat) -> CGFloat {
        (side - gutter * 2) / 9
    }

    /// The frame of one cell. Two gutters accumulate across the axis, one after
    /// each of the first two boxes — which is what makes the boxes read.
    static func cellRect(column: Int, row: Int, cell: CGFloat, gutter: CGFloat) -> CGRect {
        CGRect(
            x: CGFloat(column) * cell + CGFloat(column / 3) * gutter,
            y: CGFloat(row) * cell + CGFloat(row / 3) * gutter,
            width: cell, height: cell
        )
    }

    /// The centre of one cell, addressed by its 0…80 index.
    static func centre(of index: Int, cell: CGFloat, gutter: CGFloat) -> CGPoint {
        let frame = cellRect(column: index % 9, row: index / 9, cell: cell, gutter: gutter)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// The two interior box rules, drawn down the middle of the two seams.
    ///
    /// `context` is taken **by value**: every drawing method on
    /// `GraphicsContext` is non-mutating, and passing the Canvas closure's
    /// `inout` parameter as a plain argument avoids a nested closure capturing
    /// it (which Swift only permits while it provably does not escape).
    static func strokeBoxRules(
        in context: GraphicsContext,
        side: CGFloat, cell: CGFloat, gutter: CGFloat,
        color: Color, lineWidth: CGFloat
    ) {
        var path = Path()
        for boundary in 1...2 {
            // The seam after box `boundary` spans [3·b·cell + (b−1)·g,
            // 3·b·cell + b·g]; its middle is half a gutter into that.
            let offset = CGFloat(boundary) * 3 * cell + (CGFloat(boundary) - 0.5) * gutter
            path.move(to: CGPoint(x: offset, y: 0))
            path.addLine(to: CGPoint(x: offset, y: side))
            path.move(to: CGPoint(x: 0, y: offset))
            path.addLine(to: CGPoint(x: side, y: offset))
        }
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }
}

struct BoardFingerprint: View {
    let game: NineGame
    let accent: Color
    /// Edge length of the square. Dots scale off it, so one view serves the
    /// 34pt Boards row and the 44pt Continue card without a second layout.
    var side: CGFloat = 34

    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var tones: ThemeTones { theme.tones(for: colorScheme) }

    var body: some View {
        Canvas { context, size in
            // **The gaps this file's comment always claimed.** They were never
            // in the code: `(cell % 9 + 0.5) * unit` is a perfectly uniform 9×9
            // lattice, so "the 3×3 box structure reads from the gaps alone" was
            // describing gaps that did not exist and the tile read as dither.
            // Two seams per axis, and no rules — at 34 pt a sub-point stroke is
            // the aliasing the original comment was right to refuse.
            let gutter = size.width * BoardArt.thumbGutter
            let unit = BoardArt.cell(side: size.width, gutter: gutter)
            // Dots sit inside their cell with a hair of air.
            let dot = max(1.4, unit * 0.58)
            for cell in 0..<81 {
                let value = game.entry(at: cell)
                guard value != 0 else { continue }
                let center = BoardArt.centre(of: cell, cell: unit, gutter: gutter)
                let rect = CGRect(
                    x: center.x - dot / 2, y: center.y - dot / 2,
                    width: dot, height: dot
                )
                // Givens are the board's identity, so they have to survive on a
                // 34pt tile; entries are the news, so they stay brighter still.
                // A solved board therefore reads as almost solid accent, which
                // is what "finished" should look like at a glance — no separate
                // solved mode needed.
                //
                // 0.34 was measured on-device as a smudge in the light themes,
                // where `digitTone` is already close to the glass beneath it.
                let isGiven = game.isGiven(cell)
                let shade: Color = isGiven ? tones.digitTone : accent
                let opacity: Double = isGiven ? 0.55 : 1.0
                context.fill(Path(ellipseIn: rect), with: .color(shade.opacity(opacity)))
            }
        }
        .frame(width: side, height: side)
        // Concentric with the glass tile it sits in, not square inside it. The
        // tile is `side * 0.28` at its corner and the art is inset `side * 0.12`
        // on every edge, so the art's own curve is `Radius.inner` of those two —
        // `side * 0.16`. Square art inside a curved tile is the tell that the
        // picture and its frame were drawn by different people.
        .clipShape(RoundedRectangle(
            cornerRadius: Radius.inner(side * 0.28, inset: side * 0.12),
            style: .continuous
        ))
        .padding(side * 0.12)
        .couchGlass(in: RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
        // One element, one sentence — the constellation is decoration, and
        // 81 dots in the accessibility tree of a shelf row would be noise.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BoardSpeech.progressSummary(game, showErrors: false))
    }
}

/// The words beside a fingerprint. Percentages below the noise floor are a
/// lie of precision — "2%" on a 51-hole board means one digit — so the first
/// stretch of a board is described, not measured.
enum BoardProgressCaption {
    /// Below this fraction the number is meaningless; say so in words.
    static let untouchedFloor = 0.03

    static func text(for game: NineGame) -> String {
        let fraction = game.fillFraction
        if fraction >= 1 { return Phrase.full }
        if fraction < untouchedFloor {
            return fraction == 0 ? Phrase.untouched : Phrase.begun
        }
        return Phrase.percent(Int(fraction * 100))
    }

    private enum Phrase {
        static let untouched = Strings.string("board.progress.untouched")
        static let begun = Strings.string("board.progress.begun")
        static let full = Strings.string("board.progress.full")
        /// Neither a catalog key nor an interpolation (PRD-20 Task 8).
        ///
        /// Task 5 moved this off `"\(value)%"` and into
        /// `board.progress.percent` = `"%1$lld%%"`, because the sign leads the
        /// number in Turkish and takes a space in French. Right diagnosis,
        /// wrong lever: that row has no words in it, so what it really asked
        /// was for nine translators to move a `%` around a specifier by hand.
        /// `.formatted(.percent)` is ICU answering the same question, and it
        /// renders the numerals in the locale's own digits as well — which
        /// `%1$lld` could never do.
        static func percent(_ value: Int) -> String {
            value.formatted(.percent)
        }
    }
}
