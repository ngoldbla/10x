// BoardGlyphView.swift — a board as a constellation, for every surface too
// small to draw digits (PRD-30).
//
// Same idea as `BoardFingerprint` (PRD-22), which cannot be reused: it lives in
// `Sources/App`, imports CouchKit, and reads `@Environment(\.nineTheme)` — three
// things the widget extension does not have. What the two share is the geometry
// and the rule, and the rule is the part worth restating: **givens are the
// board's identity, entries are the news**, so printed dots sit back at reduced
// opacity and yours come forward at full strength. Progress stops being a number
// you read and becomes a picture that fills in.
//
// Nothing here distinguishes a right entry from a wrong one. `BoardGlyph` cannot
// (it carries no digits) and must not: this draws on a Lock Screen that anyone
// walking past can read, so marking errors here would leak more than the app's
// own `showErrors` pref ever does.
import SwiftUI
import WidgetKit

struct BoardGlyphView: View {
    let glyph: BoardGlyph
    let look: WidgetLook
    /// Edge length. One view serves the Dynamic Island's ~20pt compact slot and a
    /// StandBy face's ~120pt, because everything scales off this.
    var side: CGFloat
    /// Drawn in hierarchical greys rather than colour. Set for `.accented` and
    /// `.vibrant` rendering modes, where the system desaturates whatever it is
    /// given and an arbitrary RGB triple lands somewhere nobody chose.
    var monochrome: Bool = false

    var body: some View {
        Canvas { context, size in
            let unit = size.width / 9
            // The 3×3 box structure reads from the gaps alone at this scale, so
            // there are no rules to draw and nothing to alias — the same
            // reasoning, and the same 0.58 ratio, as `BoardFingerprint`.
            let dot = max(0.9, unit * 0.58)
            for cell in 0..<BoardGlyph.cellCount {
                let isGiven = glyph.isGiven(cell)
                guard isGiven || glyph.isFilled(cell) else { continue }
                let centre = CGPoint(
                    x: (CGFloat(cell % 9) + 0.5) * unit,
                    y: (CGFloat(cell / 9) + 0.5) * unit
                )
                let rect = CGRect(
                    x: centre.x - dot / 2, y: centre.y - dot / 2,
                    width: dot, height: dot
                )
                context.fill(Path(ellipseIn: rect), with: .color(shade(given: isGiven)))
            }
        }
        .frame(width: side, height: side)
        // A glyph is a picture of a board; one sentence, not 81 elements. The
        // wording is the same summary the shelf's fingerprint speaks.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Phrase.glyphLabel(filled: glyph.filledCount))
    }

    private func shade(given: Bool) -> Color {
        if monochrome {
            // `.primary` / `.secondary` rather than two greys: in `.vibrant` they
            // are what the system maps onto its own vibrancy levels, which is how
            // StandBy Night Mode's red tint comes out looking deliberate.
            return given ? .secondary : .primary
        }
        return given ? look.digit.opacity(0.55) : look.accent
    }

    private enum Phrase {
        static func glyphLabel(filled: Int) -> String {
            Strings.string("presence.glyph.label", .int(filled))
        }
    }
}
