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
            let unit = size.width / 9
            // Dots sit inside their cell with a hair of air; the 3×3 box
            // structure reads from the gaps alone, so there are no rules to
            // draw and nothing to alias at 34pt.
            let dot = max(1.4, unit * 0.58)
            for cell in 0..<81 {
                let value = game.entry(at: cell)
                guard value != 0 else { continue }
                let center = CGPoint(
                    x: (CGFloat(cell % 9) + 0.5) * unit,
                    y: (CGFloat(cell / 9) + 0.5) * unit
                )
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
        /// Through the catalog rather than string interpolation: the percent
        /// sign leads the number in Turkish and takes a space in French, and
        /// neither is expressible from a Swift interpolation.
        static func percent(_ value: Int) -> String {
            Strings.string("board.progress.percent", .int(value))
        }
    }
}
