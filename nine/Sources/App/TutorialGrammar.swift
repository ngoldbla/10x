// TutorialGrammar.swift — per-platform gesture vocabulary for the interactive
// tutorial's five beats (goal → place → pencil → highlight → difficulty).
//
// Pure data, no `#if`: every platform's copy is compiled everywhere so a shared
// `TutorialView` can be handed whichever one its host speaks. The verbs
// (`placeVerb`, …) are the short nouns other surfaces reach for; the `*Detail`
// strings are the full beat sentences, whose phrasing differs enough between
// input grammars that templating from a verb alone reads awkwardly.
//
// Cross-phase contract (docs/…/2026-07-21-nine-prds-4-6.md): PRD-4 builds
// `.keyboard` and stubs `.pad`; PRD-5 refines `.pad`; the iOS copy becomes
// `.touch` verbatim (zero copy regressions).
//
// **PRD-20: the four grammars are now four key prefixes, not four tables of
// English.** The words live in `EnglishPhrases`/`Localizable.xcstrings` with the
// rest of Nine's copy, and this struct is the mapping from a platform to its
// row of the catalog. Two things fall out of that which the old shape got wrong:
//
//   • The seven fields are computed, so they resolve *after*
//     `Strings.install()`. Held as `let` they would have been formatted at
//     static-initializer time, which is a launch-order dependency nobody would
//     have written down.
//   • `placeDetail(digit:)` is a real format specifier again. It used to
//     `replacingOccurrences(of: "%@", with: digit)` — a hand-rolled substitution
//     that cannot reorder, so a language wanting "press %@ after walking to the
//     cell" had nowhere to put the digit. `%1$@` through `Phrasebook.format` can.
struct TutorialGrammar {
    /// This platform's key prefix — `grammar.touch`, `grammar.pad`, … Private
    /// because it is an implementation detail of the lookup; callers ask for
    /// words, not keys.
    private let scope: String

    private init(_ scope: String) {
        self.scope = scope
    }

    /// Short verb naming how a digit is entered — "tap a petal", "type",
    /// "flick the right stick".
    var placeVerb: String { Strings.string(scope + ".placeVerb") }
    /// How a pencil note is entered.
    var pencilVerb: String { Strings.string(scope + ".pencilVerb") }
    /// How the same-number highlight is toggled.
    var highlightVerb: String { Strings.string(scope + ".highlightVerb") }
    /// One-line reminder of the primary controls, shown under the lesson.
    var advanceHint: String { Strings.string(scope + ".advanceHint") }

    /// The "Pencil notes" beat detail.
    var pencilDetail: String { Strings.string(scope + ".pencilDetail") }
    /// The "Find every 9" beat detail.
    var highlightDetail: String { Strings.string(scope + ".highlightDetail") }

    /// The "Place a digit" beat detail, with the concrete target digit filled in.
    func placeDetail(digit: String) -> String {
        Strings.string(scope + ".placeDetail", .text(digit))
    }

    // MARK: - Siri Remote (tvOS). Defined here for PRD-5's tvOS tutorial port.
    static let remote = TutorialGrammar("grammar.remote")

    // MARK: - Touch (iOS). Existing iOS copy, verbatim.
    static let touch = TutorialGrammar("grammar.touch")

    // MARK: - Keyboard (macOS, PRD-4).
    static let keyboard = TutorialGrammar("grammar.keyboard")

    // MARK: - Controller / pad (tvOS, PRD-5). Real DualSense / Xbox verbs,
    // wired to the pad grammar: the right stick *is* the rose (one deflection
    // per digit, the cell always armed), Square is sticky pencil, Triangle is
    // the same-number highlight, L2 held is peek.
    static let pad = TutorialGrammar("grammar.pad")
}
