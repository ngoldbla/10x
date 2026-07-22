// TutorialGrammar.swift — per-platform gesture vocabulary for the interactive
// tutorial's five beats (goal → place → pencil → highlight → difficulty).
//
// Pure data, no `#if`: every platform's copy is compiled everywhere so the
// four grammars can be unit-tested and so a shared `TutorialView` can be
// handed whichever one its host speaks. The verbs (`placeVerb`, …) are the
// short nouns other surfaces reach for; the `*Detail` strings are the full
// beat sentences, whose phrasing differs enough between input grammars that
// templating from a verb alone reads awkwardly.
//
// Cross-phase contract (docs/…/2026-07-21-nine-prds-4-6.md): PRD-4 builds
// `.keyboard` and stubs `.pad`; PRD-5 refines `.pad`; the iOS copy becomes
// `.touch` verbatim (zero copy regressions).
struct TutorialGrammar {
    /// Short verb naming how a digit is entered — "tap a petal", "type",
    /// "flick the right stick".
    let placeVerb: String
    /// How a pencil note is entered.
    let pencilVerb: String
    /// How the same-number highlight is toggled.
    let highlightVerb: String
    /// One-line reminder of the primary controls, shown under the lesson.
    let advanceHint: String

    /// The "Place a digit" beat detail. Contains a single `%@` for the
    /// target digit's name.
    let placeDetailFormat: String
    /// The "Pencil notes" beat detail.
    let pencilDetail: String
    /// The "Find every 9" beat detail.
    let highlightDetail: String

    /// Fill `placeDetailFormat` with the concrete target digit.
    func placeDetail(digit: String) -> String {
        placeDetailFormat.replacingOccurrences(of: "%@", with: digit)
    }

    // MARK: - Siri Remote (tvOS). Defined here for PRD-5's tvOS tutorial port.
    static let remote = TutorialGrammar(
        placeVerb: "flick",
        pencilVerb: "hold-click",
        highlightVerb: "park the cursor",
        advanceHint: "Swipe to move · click for the rose · ▶︎ undoes",
        placeDetailFormat: "Swipe to the glowing cell and click for the rose, then flick toward %@ — or swipe to a petal and click.",
        pencilDetail: "Hold-click an empty cell for the pencil rose. Notes sit small in the corner until a real digit lands.",
        highlightDetail: "Park the cursor on any placed digit and every copy of it lights up — pencil notes too."
    )

    // MARK: - Touch (iOS). Existing iOS copy, verbatim.
    static let touch = TutorialGrammar(
        placeVerb: "tap a petal",
        pencilVerb: "pencil toggle",
        highlightVerb: "tap a placed digit",
        advanceHint: "Tap a cell for the rose · tap a petal to place",
        placeDetailFormat: "Tap the glowing cell, then tap the %@ in the rose. (You can also flick toward it — the rose is a 3×3 keypad.)",
        pencilDetail: "Pencil is on. Tap an empty cell and note a digit you're considering — notes sit small in the corner until a real digit lands.",
        highlightDetail: "Tap any placed digit on the board. Every copy of it lights up — pencil notes too. Tap one again to switch the lights off."
    )

    // MARK: - Keyboard (macOS, PRD-4).
    static let keyboard = TutorialGrammar(
        placeVerb: "type",
        pencilVerb: "Shift-type",
        highlightVerb: "Space",
        advanceHint: "Arrows move · digits place · ⌘Z undoes",
        placeDetailFormat: "Walk to the glowing cell with the arrow keys, then press %@. Digits type straight in — no rose, no modes.",
        pencilDetail: "Hold Shift and press a digit to pencil a note — small in the corner until a real digit lands. Press P for sticky pencil.",
        highlightDetail: "Move the cursor onto any placed digit and press Space. Every copy lights up — pencil notes too. Space again switches the lights off."
    )

    // MARK: - Controller / pad (tvOS, PRD-5). Real DualSense / Xbox verbs,
    // wired to the pad grammar: the right stick *is* the rose (one deflection
    // per digit, the cell always armed), Square is sticky pencil, Triangle is
    // the same-number highlight, L2 held is peek.
    static let pad = TutorialGrammar(
        placeVerb: "flick the right stick",
        pencilVerb: "Square",
        highlightVerb: "Triangle",
        advanceHint: "Left stick moves · right stick flicks a digit · Circle erases",
        placeDetailFormat: "Walk to the glowing cell with the left stick, then flick the right stick toward %@ — the cell is always armed, so it's one flick per digit, no rose to open. (Cross opens the rose if you'd rather learn the petals; R3 places 5.)",
        pencilDetail: "Press Square for sticky pencil, then flick a note into an empty cell — small in the corner until a real digit lands. Square again turns pencil off.",
        highlightDetail: "Rest on any placed digit and press Triangle — every copy lights up, pencil notes too. Hold L2 to dim everything except that kind. Triangle again switches the lights off."
    )
}
