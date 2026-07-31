// BoardView.swift — the 81-cell grid, drawn in a single Canvas on one glass
// plane (PRD §4.2). Box borders are **rules**, not luminance steps: see the
// note above step 2.4, which records the measurement that retired the wash.
// Givens in rounded semibold, entries in the accent tint at regular, errors get
// a coral underline paired with a coral cell rim (colorblind-safe). Completion
// rolls a luminance wave across the grid.
import SwiftUI
import CouchKit

/// What just happened to a cell, so the board can answer it visually.
///
/// The app has fired `haptics.playError()` since 1.0 with no visual partner —
/// a buzz and a still frame. These three are the frames: a placement settles
/// in, an erase settles out, and an error shakes. One enum rather than three
/// booleans because they are mutually exclusive by construction: a cell cannot
/// be placed and erased in the same instant.
enum CellEventKind: Equatable, Sendable {
    /// A digit landed in the cell.
    case place
    /// A digit (or the cell's notes) was cleared.
    case erase
    /// A digit landed and it was wrong.
    case error
}

/// One grammar for every digit this board draws, **as fractions of one cell's
/// side** rather than as point sizes.
///
/// **Every value here forwards to `BoardType` in `DesignTokens.swift`** — this
/// is a naming shim, not a second scale. `BoardInk` rather than `BoardGlyph`,
/// which is taken: `Sources/Shared`'s 81-cell presence constellation owns that
/// name on every target.
///
/// It was briefly a hand-copy, because `DesignTokens.swift` was on the **app**
/// target only while this file is *also* on the **watch** target's source list
/// (`project.yml` — "the board is reused, the phone UI is not"), so naming
/// `BoardType` here compiled on the phone and failed on the wrist. The tokens
/// are now on the watch list too, and the copy is gone: a duplicated scale is a
/// scale that drifts, and two hand-copies in this repo's own tests
/// (`AppearancePaletteTests`' ground and `PrefsDowngradeTests`' defaults) had
/// already gone stale without anything going red.
///
/// The arithmetic behind the numbers, since it is the whole reason they moved:
/// `scale` is `size.width / 900` and `cell` is `size.width / 9`, so
/// `cell == 100 * scale` *exactly* and the shipped `56 * scale` was already
/// `0.56 * cell`. A `BoardType.entry` of 0.56 would therefore have been
/// byte-identical to the size the audit measured as too small. The real
/// reference is the *cap* ratio: SF Rounded's cap height is ≈0.72 em, so a 0.56
/// cell point size puts the cap at 0.40 of the cell — the 40% the audit measured
/// against a 50–55% band. 0.66 puts it at 0.475.
enum BoardInk {
    /// A committed digit — the player's own entry.
    static let entry = BoardType.entry
    /// A clue printed with the puzzle. Same size as an entry by design: a given
    /// and an entry are the same *kind* of mark and differ by weight and tone,
    /// never by size.
    static let given = BoardType.given
    /// The live-flick preview drawn before commit. Identical to `entry` so a
    /// digit does not resize the instant it lands.
    static let ghost = BoardType.ghost
    /// A pencil mark — three across a cell with air.
    static let note = BoardType.note
    /// A pencil-mark preview. Same as `note`, same reason as `ghost`.
    static let noteGhost = BoardType.noteGhost
    /// A killer-cage sum in the corner of a cell. Was `15 * scale` = 0.15 cell,
    /// which made load-bearing puzzle data *smaller than a pencil note*.
    static let cageSum = BoardType.cageSum
    /// The mini 3×3 keypad's pitch. Was 0.28, which left a dead margin all
    /// round and made three marks read as stray digits rather than as a keypad.
    static let notePitch = BoardType.notePitch

    /// A given is one weight *step and a half* above an entry, not one:
    /// `.semibold` against `.regular` is the smallest difference that still
    /// reads at a glance. `.semibold` against `.medium` — what shipped — is
    /// roughly a 4% stroke difference, invisible, which left the whole
    /// given/entry hierarchy resting on hue alone.
    static let givenWeight = BoardType.givenWeight
    /// The player's own marks.
    static let entryWeight = BoardType.entryWeight
    /// Pencil marks. Medium rather than regular because at this size a regular
    /// stroke disappears into the hairlines.
    static let noteWeight = BoardType.noteWeight
}

// `CoachFocus` lives here rather than in `CoachCard.swift` because it is
// board-render input, and PRD-6 puts this file on the watch target's source
// list while the card — an iOS panel — stays off it.
/// The cells a hint lights, by the part each plays in it.
///
/// Arrays rather than a `[Int: Role]` dictionary: where two roles land on one
/// cell the draw order decides what the player sees, and dictionary iteration
/// order is not defined.
struct CoachFocus: Equatable, Sendable {
    /// The cells forming the pattern — an accent wash.
    let pattern: [Int]
    /// The cell the step resolves, if any — a stronger ring.
    let target: Int?
    /// Cells losing a candidate — a dashed, dimmer border.
    let victims: [Int]
    /// The digit under discussion, when the step is about exactly one.
    let digit: Int?
    /// The single cell a deduction turns on — an XY-wing's pivot. Drawn as a
    /// thin inner ring, so a pattern cell that is *also* the pivot reads as
    /// both rather than as neither. Trace schema v2's `.pivot` role, and the
    /// fourth of the four this file's header predicted would arrive.
    let pivot: Int?
    /// The cell the player asked about, held for the whole chain so a
    /// three-beat narration never loses its subject. Nil for a plain hint,
    /// which has no subject to hold.
    let asked: Int?

    init(pattern: [Int], target: Int?, victims: [Int], digit: Int?,
         pivot: Int? = nil, asked: Int? = nil) {
        self.pattern = pattern
        self.target = target
        self.victims = victims
        self.digit = digit
        self.pivot = pivot
        self.asked = asked
    }

    /// Nil for a solved board: the Afterglow owns that moment and nothing
    /// should wash over it.
    init?(_ advice: CoachAdvice) {
        switch advice {
        case .solved:
            return nil
        case .exhausted:
            self.init(pattern: [], target: nil, victims: [], digit: nil)
        case .contradiction(let cells):
            self.init(pattern: cells, target: nil, victims: [], digit: nil)
        case .step(let coach):
            self.init(coach.step, asked: nil)
        }
    }

    /// One beat of a why-chain (PRD-25). Same wash, same dashes, same ring —
    /// the narration is this file's existing vocabulary driven from an array
    /// instead of a single value, which is what `CoachCard`'s header said it
    /// would be.
    init(_ beat: DerivedStep, asked: Int) {
        self.init(beat.coach.step, asked: asked)
    }

    private init(_ step: SolveStep, asked: Int?) {
        pattern = step.cells
        target = step.placement?.cell
        victims = Set(step.eliminations.map(\.cell)).sorted()
        digit = step.digits.count == 1 ? step.digits.first : nil
        // Read off `roles` rather than off the technique, so a technique that
        // grows a pivot later gets the ring without touching this file.
        pivot = step.roles?.firstIndex(of: .pivot).map { step.cells[$0] }
        self.asked = asked
    }
}

/// Shared geometry so the game screens can position the flick rose over a
/// cell. The TV board is a fixed 900pt plane; the touch board passes its own
/// side length, so every drawing constant scales off `side / 900`.
enum BoardMetrics {
    static let side: CGFloat = 900
    static let cell: CGFloat = side / 9

    /// Center of a cell in board-local coordinates (tvOS fixed board).
    static func center(of cell: Int) -> CGPoint {
        center(of: cell, side: side)
    }

    /// Center of a cell in a board of arbitrary side length.
    static func center(of cell: Int, side: CGFloat) -> CGPoint {
        let unit = side / 9
        let row = CGFloat(cell / 9)
        let col = CGFloat(cell % 9)
        return CGPoint(x: (col + 0.5) * unit, y: (row + 0.5) * unit)
    }

    /// The full square a cell occupies, in board-local coordinates. Drawing
    /// sites rebuild this inline off `size.width`; the accessibility layer
    /// needs it in view coordinates, so it lives here once and both agree.
    static func rect(of cell: Int, side: CGFloat) -> CGRect {
        let unit = side / 9
        return CGRect(
            x: CGFloat(cell % 9) * unit,
            y: CGFloat(cell / 9) * unit,
            width: unit,
            height: unit
        )
    }

    /// The 3×3 block a box occupies, in board-local coordinates. Only the
    /// accessibility layer needs it — the Canvas draws box borders as
    /// luminance steps rather than framed regions — but Switch Control's group
    /// scan highlights a real rectangle, so the nine groups need real frames
    /// (PRD-19). Boxes are numbered in reading order, matching `Sudoku.box`.
    static func boxRect(of box: Int, side: CGFloat) -> CGRect {
        let unit = side / 9
        return CGRect(
            x: CGFloat(box % 3) * 3 * unit,
            y: CGFloat(box / 3) * 3 * unit,
            width: 3 * unit,
            height: 3 * unit
        )
    }

    /// The nine cells of a box, in reading order — the order Switch Control
    /// steps them once the group is entered.
    static func cells(inBox box: Int) -> [Int] {
        let firstRow = (box / 3) * 3, firstCol = (box % 3) * 3
        return (0..<3).flatMap { dr in
            (0..<3).map { dc in (firstRow + dr) * 9 + firstCol + dc }
        }
    }

    /// The cell index under a board-local point, or nil when outside.
    static func cellIndex(at point: CGPoint, side: CGFloat) -> Int? {
        let unit = side / 9
        let col = Int(floor(point.x / unit)), row = Int(floor(point.y / unit))
        guard (0..<9).contains(col), (0..<9).contains(row) else { return nil }
        return row * 9 + col
    }

    /// Move a cursor one step. `wrap` toggles edge-wrapping (the Mac keyboard
    /// grammar, PRD-4 §2.2) versus clamping (the TV/touch cursor).
    static func moveCursor(_ cell: Int, _ direction: Direction4, wrap: Bool) -> Int {
        var row = cell / 9, col = cell % 9
        switch direction {
        case .up: row = wrap ? (row + 8) % 9 : max(0, row - 1)
        case .down: row = wrap ? (row + 1) % 9 : min(8, row + 1)
        case .left: col = wrap ? (col + 8) % 9 : max(0, col - 1)
        case .right: col = wrap ? (col + 1) % 9 : min(8, col + 1)
        }
        return row * 9 + col
    }

    /// The next (or previous) empty cell, searched cyclically — Tab / ⇧Tab on
    /// the Mac. Givens are filled, so they're skipped for free. Falls back to
    /// the starting cell when the board has no empties left.
    static func nextEmptyCell(from cell: Int, in game: NineGame, forward: Bool) -> Int {
        let step = forward ? 1 : -1
        for i in 1...81 {
            let idx = ((cell + step * i) % 81 + 81) % 81
            if game.entry(at: idx) == 0 { return idx }
        }
        return cell
    }
}

struct BoardView: View {
    let game: NineGame
    let cursor: Int
    let accent: Color
    let showErrors: Bool
    let solvedAt: Date?
    /// Dim the board content a touch while the rose is open, so the petals
    /// (true glass, lensing the board) are the brightest thing on screen.
    let roseOpen: Bool
    /// The open rose's geometry, or nil (PRD-22). Non-nil arms the third layer
    /// effect: the board's own digits bend and magnify under each petal, and
    /// `FlickRoseView` draws only a glyph and a rim above instead of an opaque
    /// disc. Every call site leaves it nil under Reduce Motion, which restores
    /// today's material exactly — the fallback is the current design, not a
    /// degraded one.
    var roseLens: RoseLens? = nil
    /// While the four-way rose walks petals, the focused digit ghosts into
    /// the selected cell — see the digit before you commit. Nil on eight-way
    /// remotes (flicks place instantly, nothing to preview).
    let previewDigit: Int?
    /// Preview at pencil scale, in the note's own keypad slot (rose opened
    /// in pencil mode).
    let previewPencil: Bool
    /// Same-number highlight: every cell holding this digit — and every
    /// pencil note of it — gets an accent wash, so tapping a 9 shows all
    /// nine 9s (and where you've penciled them).
    var highlightDigit: Int? = nil
    /// The cells a coach hint is lighting (PRD-11), or nil. Default-off, so
    /// tvOS and macOS — which have no coach this PRD — render byte-identically.
    /// One value rather than four parameters because PRD-25 narrates a
    /// *sequence* of these; see CoachCard.swift.
    var coachFocus: CoachFocus? = nil
    /// Pad peek (L2 hold, PRD-5 §2.1): while held, every digit and note that is
    /// not this kind dims to a whisper so the highlighted kind pops. Nil = off,
    /// so every non-pad caller renders byte-identically.
    var dimmedExcept: Int? = nil
    /// The cell under the pointer (macOS, PRD-4 §2.3) — the first hover
    /// affordance in the suite. Drawn as a faint accent halo, dimmer than the
    /// cursor ring, and suppressed when it coincides with the cursor. Nil where
    /// nothing can hover: tvOS, the watch, and an iPad with neither a trackpad
    /// nor a Pencil in range. PRD-31 gave iPadOS the same halo off the same
    /// value, because a hovering Pencil tip and a pointer are the same question.
    var hoverCell: Int? = nil
    /// The variant rules drawn on this board — killer cages, thermo tubes — or nil
    /// for a classic board (PRD-24).
    ///
    /// **Nil by default, so all nine existing call sites render byte-identically**,
    /// which is `coachFocus`'s and `dimmedExcept`'s pattern and the reason the
    /// watch board, the tutorial boards, the first-run board and the school board
    /// needed no change at all.
    ///
    /// A `ChannelRules` rather than a `[VariantConstraint]` because the record is
    /// self-describing and the renderer needs to know *which* ruleset it is
    /// drawing: a cage and a thermometer are both "cells plus a number" on the
    /// wire and completely different marks on the board.
    var channelRules: ChannelRules? = nil
    /// A per-cell tint for placed digits, or nil for one accent everywhere
    /// (PRD-27 §6).
    ///
    /// **Nil by default, so every existing call site renders byte-identically**
    /// — `channelRules`' pattern above, and the reason the watch board, the
    /// tutorial boards, the first-run board, the school board and the
    /// fingerprint need no change at all.
    ///
    /// A closure rather than a `[Int: Color]` because the caller already holds
    /// the answer in a form it can share: `DuelCredits.owners` is built once per
    /// board draw and closed over, where a dictionary parameter would be a
    /// second copy of it made on every body evaluation.
    ///
    /// Givens are never tinted — a given belongs to the puzzle, not to a
    /// player, and colouring one would claim a digit nobody placed.
    var digitTint: ((Int) -> Color?)? = nil
    /// The player's own handwriting (PRD-31). Pencil marks are drawn from these
    /// glyphs when the digit has one and from the rounded typeface when it does
    /// not — so the board fills with the player's hand a digit at a time rather
    /// than switching over all at once.
    ///
    /// Notes only, never placed digits: the two typefaces are the app's way of
    /// saying *tentative* and *committed*, and inking an entry would erase that
    /// distinction to make a nicer screenshot.
    var hand = HandGlyphs()
    /// Origin cell of the Afterglow shockwave — the winning placement.
    /// Nil (or Reduce Motion) keeps the classic diagonal luminance wave.
    var waveOrigin: Int? = nil
    /// Polled once per frame while the solved board is a glass trophy;
    /// returns device tilt (gravity delta from a baseline pose) steering the
    /// specular sheen. Nil on tvOS: the sheen settles and the loop pauses.
    var afterglowTilt: (@MainActor (Date) -> SIMD2<Double>)? = nil
    /// Side length of the drawing plane. The TV board is fixed at 900pt; the
    /// touch board passes whatever the screen affords, and every drawing
    /// constant below scales off `side / 900`.
    var side: CGFloat = BoardMetrics.side
    /// Padding between the grid and the glass edge.
    var inset: CGFloat = 28
    /// PRD-19: the grammar the 81 virtual accessibility children expose.
    /// Default-constructed it is read-only — the tutorial's boards and the
    /// solved trophy stay readable without offering moves that would be
    /// refused. See BoardAccessibility.swift.
    var axActions = BoardAXActions()
    /// Push the 3×3 rules past their resting weight — for a surface where the
    /// board is small enough that the boxes are the only structure that
    /// survives (a shelf thumbnail, a tutorial diagram).
    ///
    /// **Defaulted false, so every existing call site renders identically**;
    /// `channelRules`' and `digitTint`'s pattern, and the reason nothing outside
    /// this file changes.
    var emphasiseBoxes: Bool = false
    /// The last thing that happened to a cell, and when — the input to the
    /// placement settle, the erase echo and the error shake (`CellEventKind`).
    ///
    /// A tuple rather than a struct because it is three scalars with no
    /// behaviour, and `at` is the animation clock: the board reads
    /// `now.timeIntervalSince(at)` rather than holding any state of its own, so
    /// a caller that re-sends the same event with the same `Date` re-renders
    /// the same frame and never restarts the animation.
    ///
    /// **Defaulted nil**, so tvOS, the watch, the tutorial and the first-run
    /// boards are untouched until a caller opts in.
    var lastEvent: (cell: Int, kind: CellEventKind, at: Date)? = nil

    /// A stored glyph as a `Path`, scaled into a `box`-sized square centred on
    /// `point` (PRD-31).
    ///
    /// `HandGlyphs` stores every specimen already fitted to a unit box, so this
    /// is a scale and a translate and nothing else — the arithmetic that could
    /// let a note paint into its neighbour lives in `HandGlyphs.boxed`, on the
    /// write side, where one test covers every future glyph at once
    /// (`testAStoredGlyphNeverLeavesItsBox`).
    static func inkPath(_ glyph: InkGlyph, centredAt point: CGPoint, box: CGFloat) -> Path {
        var path = Path()
        for stroke in glyph.strokes where stroke.count >= 2 {
            func place(_ ink: InkPoint) -> CGPoint {
                CGPoint(x: point.x + (CGFloat(ink.x) - 0.5) * box,
                        y: point.y + (CGFloat(ink.y) - 0.5) * box)
            }
            path.move(to: place(stroke[0]))
            for ink in stroke.dropFirst() { path.addLine(to: place(ink)) }
        }
        return path
    }

    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Increase Contrast (PRD-22). SwiftUI surfaces the setting as
    /// `colorSchemeContrast`; there is no `accessibilityContrast` key.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Device pixels per point. The cell separators are the one mark on this
    /// board fine enough that the difference between "1 point" and "1 device
    /// pixel" is the difference between a line and a smear: a 1pt stroke on a
    /// 3x screen covers three pixel rows, and because its centre falls on a
    /// cell boundary that is never a whole number of pixels, it lands as four
    /// subpixel-weighted rows of grey. See step 2.
    @Environment(\.displayScale) private var displayScale
    /// The celebration has reached its resting state — nothing animates
    /// anymore, so the 60fps timeline can stop (tvOS and Reduce Motion; the
    /// iOS trophy keeps polling the gyro until the screen goes away).
    @State private var afterglowSettled = false
    /// The petal lens growing in, 0…1. Driven by the same `.couchFast` spring
    /// `FlickRoseView` blooms its petals with, so the bend arrives under the
    /// glass rather than before or after it.
    @State private var lensBloom: Double = 0
    /// A `lastEvent` is still inside its animation window, so the timeline has
    /// to run even though the board is not solved.
    ///
    /// This is state rather than a computed property because `TimelineView`'s
    /// `paused:` is captured when `body` runs: a schedule that started running
    /// keeps running until something re-evaluates `body`, and only a `@State`
    /// flip does that. `settleWhenDone` solves the same problem for the
    /// Afterglow and this is its twin.
    @State private var eventLive = false

    /// How much bigger a digit reads through a petal.
    ///
    /// This one is taste, not measurement, and it is the only number in PRD-22
    /// that is. The floor is set by the covenant rather than by a ratio: at 1.0
    /// there is no lens and the petals are just transparent, and somewhere past
    /// about 1.6 the board starts *performing* under your thumb, which fails
    /// the idle-pixel test the moment you hold a rose open while thinking.
    /// **Taken from 1.34 to 1.15**, and the shader's core clamp is the other
    /// half of the same fix. At 1.34 the petals nearest the board's own digits
    /// (6 and 9 in the shipped crop) smeared the ghosted glyphs underneath into
    /// a double image, which reads as an artifact rather than as glass. At 1.15
    /// the magnification is barely a magnification and the *rim compression* —
    /// the meniscus, the thing that actually says "this is a lens" — is what
    /// survives. Tune it here; the rim's half lives in `rosePetalLens`.
    static let lensMagnification: Double = 1.15

    // MARK: - Cell-event choreography (the visual partner to `playError`)

    /// How long the timeline stays awake after a `lastEvent`. The longest of
    /// the three animations plus a frame.
    static let eventWindow: TimeInterval = 0.45
    /// The placement settle, and its inverse for an erase.
    static let settleDuration: TimeInterval = 0.22
    /// Three decaying half-cycles of shake.
    static let shakeDuration: TimeInterval = 0.45

    /// The theme decides the board's neutral tones; callers pass an accent
    /// already resolved for the theme's leaning.
    private var tones: ThemeTones { theme.tones(for: colorScheme) }
    private var isLight: Bool { tones.isLight }
    private var gridTone: Color { tones.gridTone }
    private var digitTone: Color { tones.digitTone }
    /// The player asked the system for more contrast, so the board's borders
    /// stop being luminance steps and become lines (PRD-22).
    private var increased: Bool { colorSchemeContrast == .increased }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 60.0,
                // Two independent reasons to run: the Afterglow, and a cell
                // event still inside its window. Pausing needs *both* quiet.
                paused: (solvedAt == nil || afterglowSettled) && !eventLive)
        ) { timeline in
            ZStack {
                plane
                refracted(now: timeline.date)
            }
        }
        .frame(width: side, height: side)
        .padding(inset)
        // The lift, not just the material: `couchElevated`'s gradient rim gives
        // the pane an edge to catch light on, and its shadow is a blurred fill
        // of this very shape rather than `.shadow()` — CouchKit's `FocusHalo`
        // recorded that `.shadow` silhouettes opaque geometry and a glass
        // layer's alpha is not that (the tvOS black-rectangle artifact).
        .couchGlassElevated(
            in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous),
            isLight: isLight)
        // No `.opacity(roseOpen ? 0.82 : 1.0)`. Over a near-black ground that
        // was a three-level no-op — it cost a compositing pass and bought
        // nothing — and the rose's real backdrop scrim belongs to the call
        // site, where it can dim the whole screen rather than only the board.
        //
        // PRD-19. The Canvas is one opaque drawing to VoiceOver, so the tree
        // is grafted on rather than derived: 81 synthetic children laid out on
        // `BoardMetrics`, never rendered. While the rose is open the board
        // steps out of the tree entirely — the petals are modal, and a focus
        // that can wander back to the cell underneath would let you commit a
        // digit to a board you can no longer see the state of.
        .accessibilityChildren {
            BoardAXGrid(
                game: game,
                cursor: cursor,
                showErrors: showErrors,
                side: side,
                inset: inset,
                actions: axActions,
                channelRules: channelRules
            )
        }
        .accessibilityHidden(roseOpen)
        .task(id: solvedAt) { await settleWhenDone() }
        // `at` rather than the whole tuple: a tuple is not `Equatable`, and the
        // timestamp is the only part that can identify one event from the next
        // (two errors on the same cell are two events).
        .task(id: lastEvent?.at) { await runEventWindow() }
        // The lens grows and shrinks with the petals, not instead of them.
        .onChange(of: roseLens) { _, lens in
            withAnimation(.couchFast) { lensBloom = lens == nil ? 0 : 1 }
        }
        .onAppear { lensBloom = roseLens == nil ? 0 : 1 }
    }

    /// The theme's own ground, put back between the glass and the drawing
    /// (PRD-22). It covers the grid square only — the 12–28pt inset stays pure
    /// material — and it is a sibling of the Canvas rather than the Canvas's
    /// first fill for one specific reason: `afterglowWave` scales its glint by
    /// `color.a` so the celebration rides drawn content and never fogs empty
    /// board. An opaque fill *inside* the Canvas makes alpha 1 everywhere, and
    /// the wave would wash the whole grid instead of lighting the digits.
    private var plane: some View {
        RoundedRectangle(cornerRadius: planeRadius, style: .continuous)
            .fill(tones.plane)
    }

    /// The glass card's own corner.
    ///
    /// **The floor is 28, not 18** (`Radius.sheet` in `DesignTokens.swift`,
    /// spelled as a literal here because that file is on the app target only
    /// and this one compiles for the watch too). Every phone board falls
    /// through to the floor — `36 * 381 / 900` is 15.2 — so 18 was not a floor
    /// on a large board, it was *the* radius on the only board most players
    /// ever see, and 18pt on a 381pt card is tight by iOS 26 standards.
    private var cardRadius: CGFloat { max(28, 36 * side / BoardMetrics.side) }

    /// The ground under the grid, and the shape the Canvas is clipped to.
    ///
    /// Derived from the card rather than invented: two rounded rectangles, one
    /// inset inside the other, are only concentric when the inner radius is
    /// `outer − inset` (`Radius.inner`). The old `18 * side / 900` was an
    /// independent constant, so the plane's arc and the box washes' arc
    /// (`6 * scale`) disagreed by ~5pt and the Canvas — never clipped — painted
    /// the wash straight onto the glass in the gap. That is the bright L-shaped
    /// notch in all four grid corners of the shipped dark frame.
    ///
    /// The second clamp is the watch: at `side ≈ 170` and `inset 3` the
    /// concentric radius is 25pt against a 19pt cell, and the clip would eat
    /// the corner cells whole. Half a cell is the most a corner can give up
    /// without losing a cell.
    private var planeRadius: CGFloat {
        max(4, min(cardRadius - inset, side / 18))
    }

    /// The board's drawing, and the three shaders that bend it. All three apply
    /// to the Canvas only — inside `couchGlass`, above `plane` — so digits and
    /// grid refract while the glass material, the theme wash and the void
    /// behind them stay optically still.
    ///
    /// **watchOS has no SwiftUI shaders**, so on the wrist this is the Canvas
    /// and nothing else. That costs the watch none of the board and one of the
    /// three celebrations: `waveOrigin` is nil there, which routes step 4 of
    /// `draw` down the Reduce-Motion diagonal luminance wave — already shipped,
    /// already Canvas-drawn, and PRD-6 §2.4 names it the watch's hero moment
    /// for exactly this reason. The rose never opens on a watch (the Crown is
    /// the rose there), so the petal lens has nothing to bend either.
    @ViewBuilder
    private func refracted(now: Date) -> some View {
        let phase = afterglowPhase(now: now)
        let canvas = Canvas { context, size in
            draw(in: &context, size: size, now: now)
        }
        #if os(watchOS)
        canvas
        #else
        canvas
        .layerEffect(
            ShaderLibrary.afterglowWave(
                .float2(originPoint),
                .float(phase.waveProgress ?? 0),
                .float(maxRadius),
                .float(waveAmplitude)
            ),
            maxSampleOffset: CGSize(width: waveAmplitude + 4, height: waveAmplitude + 4),
            isEnabled: phase.waveActive
        )
        .layerEffect(
            ShaderLibrary.afterglowSheen(
                .float2(side, side),
                .float(phase.sheenPos),
                .float2(phase.sheenTilt.x, phase.sheenTilt.y),
                .float(phase.sheenStrength)
            ),
            maxSampleOffset: CGSize(width: 6, height: 6),
            isEnabled: phase.sheenActive
        )
        // PRD-22, third in the chain and last on purpose: during a celebration
        // the board is a trophy and the rose is closed, so the two never
        // overlap in practice — but if they ever did, the Afterglow is the
        // thing the player is being shown.
        .layerEffect(
            ShaderLibrary.rosePetalLens(
                .float2(lensCentre),
                .float(roseLens?.spacing ?? 0),
                .float(roseLens?.petalRadius ?? 0),
                .float(Self.lensMagnification),
                .float(lensBloom)
            ),
            maxSampleOffset: CGSize(width: lensReach, height: lensReach),
            isEnabled: lensActive
        )
        #endif
    }

    // MARK: - The petal lens (PRD-22)

    /// Reduce Motion never reaches the shader — every call site already leaves
    /// `roseLens` nil there, and this is the second lock on the same door.
    private var lensActive: Bool {
        roseLens != nil && !reduceMotion && lensBloom > 0.001
    }

    private var lensCentre: CGPoint {
        guard let roseLens else { return .zero }
        return CGPoint(x: roseLens.centre.x, y: roseLens.centre.y)
    }

    /// How far the shader may sample outside a pixel's own position. The worst
    /// case is a rim pixel: `|delta| * (squeeze - 1)` with `|delta|` at the
    /// radius and `squeeze` at its 1.42 ceiling, so 0.42 radii. This is 1.9,
    /// deliberately loose — under-sizing it clips the compressed band into a
    /// hard edge, visible only where petals sit near the plane's border, which
    /// is exactly where `RoseLens`'s clamp puts them.
    private var lensReach: CGFloat {
        CGFloat((roseLens?.petalRadius ?? 0) * 1.9)
    }

    // MARK: - Afterglow choreography

    /// Everything the shaders need this frame, as a pure function of
    /// time-since-solve. Reduce Motion never reaches the shaders at all —
    /// `waveProgress(now:)` keeps today's diagonal luminance path.
    private func afterglowPhase(now: Date) -> AfterglowPhase {
        guard let solvedAt, !reduceMotion, waveOrigin != nil else { return AfterglowPhase() }
        return AfterglowPhase.at(
            now.timeIntervalSince(solvedAt),
            tilt: afterglowTilt.map { $0(now) }
        )
    }

    /// Flip `afterglowSettled` once the celebration reaches a static frame:
    /// after the wave under Reduce Motion, after the sheen settles on tvOS.
    /// The iOS trophy never settles — tilt keeps steering the light until
    /// the screen goes away. Also fixes the pre-Afterglow behavior where the
    /// solved board's timeline ran at 60fps forever.
    private func settleWhenDone() async {
        afterglowSettled = false
        guard let solvedAt else { return }
        let settleAt: TimeInterval?
        if reduceMotion || waveOrigin == nil {
            settleAt = AfterglowPhase.waveDuration + 0.1
        } else if afterglowTilt == nil {
            settleAt = AfterglowPhase.settleTime
        } else {
            settleAt = nil
        }
        guard let settleAt else { return }
        let remaining = settleAt - Date().timeIntervalSince(solvedAt)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            if Task.isCancelled { return }
        }
        afterglowSettled = true
    }

    // MARK: - Cell events

    /// Hold the timeline awake for one event, then let it pause again.
    ///
    /// Reduce Motion never opens the window at all: the three animations are
    /// *only* animation — every one of them ends on the frame the board would
    /// have drawn anyway — so collapsing them to instant is exactly right, and
    /// it also means a Reduce Motion board never spins the 60fps timeline for
    /// a digit placement. Same lock this file already puts on the petal lens.
    private func runEventWindow() async {
        guard let lastEvent, !reduceMotion else {
            eventLive = false
            return
        }
        let remaining = Self.eventWindow - Date().timeIntervalSince(lastEvent.at)
        guard remaining > 0 else {
            eventLive = false
            return
        }
        eventLive = true
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        if Task.isCancelled { return }
        eventLive = false
    }

    /// How a cell's glyphs are displaced this frame. Identity for every cell
    /// but the one the event landed on, and identity everywhere under Reduce
    /// Motion.
    private struct CellMotion {
        var scale: CGFloat = 1
        var dx: CGFloat = 0
        var isIdentity: Bool { scale == 1 && dx == 0 }
    }

    private func cellMotion(_ index: Int, now: Date, cell: CGFloat) -> CellMotion {
        guard !reduceMotion, let lastEvent, lastEvent.cell == index else {
            return CellMotion()
        }
        let t = now.timeIntervalSince(lastEvent.at)
        guard t >= 0 else { return CellMotion() }

        switch lastEvent.kind {
        case .place, .erase:
            guard t < Self.settleDuration else { return CellMotion() }
            // Ease-out cubic: fast off the mark, still at the end. A settle
            // that decelerates reads as something arriving; a linear one reads
            // as something being dragged.
            let eased = 1 - pow(1 - t / Self.settleDuration, 3.0)
            // A placement lands slightly large and shrinks to true; an erase is
            // its inverse, so whatever the cell holds *afterwards* — the pencil
            // marks the digit was covering, usually — grows in rather than
            // popping. When the cell ends up genuinely empty this frame is a
            // no-op, which is correct: there is nothing to animate.
            let from: CGFloat = lastEvent.kind == .place ? 1.18 : 0.72
            return CellMotion(scale: from + (1 - from) * CGFloat(eased))
        case .error:
            guard t < Self.shakeDuration else { return CellMotion() }
            let p = t / Self.shakeDuration
            // `sin(p · 3π)` has zeros at 0, π, 2π and 3π — exactly three half
            // cycles, ending on the true position rather than mid-swing. The
            // amplitude decays linearly so the last shake is a twitch.
            //
            // 0.12 of a cell is ≈5pt at phone scale and scales with the board,
            // which a flat 5pt would not: 5pt is a shove on a watch and
            // invisible on a 900pt TV board.
            let amplitude = cell * 0.12 * CGFloat(1 - p)
            return CellMotion(dx: amplitude * CGFloat(sin(p * 3 * Double.pi)))
        }
    }

    /// Draw `body` with `motion` applied about `centre` — a scale about the
    /// glyph's own centre plus a horizontal offset. Straight through when the
    /// motion is identity, which is every cell on almost every frame, so the
    /// common path costs one comparison and no extra layer.
    private func withMotion(
        _ motion: CellMotion, about centre: CGPoint,
        in context: inout GraphicsContext,
        _ body: (inout GraphicsContext) -> Void
    ) {
        if motion.isIdentity {
            body(&context)
            return
        }
        context.drawLayer { layer in
            layer.translateBy(x: centre.x + motion.dx, y: centre.y)
            layer.scaleBy(x: motion.scale, y: motion.scale)
            layer.translateBy(x: -centre.x, y: -centre.y)
            body(&layer)
        }
    }

    private var originPoint: CGPoint {
        BoardMetrics.center(of: waveOrigin ?? 40, side: side)
    }

    /// Distance from the wave origin to the farthest board corner — the
    /// crest reaches it exactly at the end of the wave, wherever you win.
    private var maxRadius: CGFloat {
        let o = originPoint
        return max(hypot(o.x, o.y),
                   max(hypot(side - o.x, o.y),
                       max(hypot(o.x, side - o.y), hypot(side - o.x, side - o.y))))
    }

    /// Peak refraction displacement in points, scaled with the board.
    private var waveAmplitude: CGFloat { 16 * side / BoardMetrics.side }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, now: Date) {
        let cell = size.width / 9
        let scale = size.width / BoardMetrics.side

        // 0. Clip to the plane.
        //
        //    The Canvas was never clipped, and the plane's arc and the box
        //    washes' arc (`6 * scale`, 2.4pt against the plane's 7.2pt) did not
        //    agree, so between the two curves the wash painted straight onto
        //    the glass — a bright L-shaped notch in all four grid corners of
        //    the shipped dark frame, which reads as a rendering bug rather than
        //    as a design. Clipping here rather than with `.clipShape` in
        //    `refracted` keeps the three `layerEffect`s sampling exactly the
        //    pixels that survive, and costs no extra layer.
        context.clip(
            to: Path(roundedRect: CGRect(origin: .zero, size: size),
                     cornerRadius: planeRadius, style: .continuous))

        // 1. Peer band: the cursor's row, its column and its box.
        //
        //    Missing entirely until now, which is why the cursor read as a lone
        //    rectangle with no explanation and every screenshot of the board
        //    looked inert. Deliberately drawn **first**, under the grid rules
        //    and under every other wash: it is the quietest statement on the
        //    board and the skeleton has to stay on top of it.
        //
        //    Full cell rects, no inset and no corner radius — also deliberate.
        //    Inset chips would read as twenty separate marks; edge-to-edge
        //    rects fuse into one continuous crosshair band, which is the shape
        //    of the claim being made. One `Path` and one `fill`, so the cells
        //    where the row and the box overlap are not painted twice (non-zero
        //    winding) and the box does not band against its own row.
        //
        //    `cursor` is guarded rather than trusted: the watch passes -1 for
        //    "nothing selected" (`WatchBoardView`), and -1 through
        //    `Sudoku.row` would light row 0 for no reason.
        if solvedAt == nil, (0..<81).contains(cursor) {
            let cursorRow = Sudoku.row(of: cursor)
            let cursorCol = Sudoku.col(of: cursor)
            let cursorBox = Sudoku.box(of: cursor)
            var band = Path()
            for index in 0..<81 where index != cursor {
                guard Sudoku.row(of: index) == cursorRow
                        || Sudoku.col(of: index) == cursorCol
                        || Sudoku.box(of: index) == cursorBox else { continue }
                band.addRect(BoardMetrics.rect(of: index, side: size.width))
            }
            context.fill(band, with: .color(gridTone.opacity(isLight ? 0.06 : 0.05)))
        }

        // 2. Hairline cell separators, snapped to device pixels.
        //
        //    **A 1pt stroke is not a hairline on a 3x screen.** The cell pitch
        //    is 40.33pt, so eight of the nine separators fall on a fractional
        //    pixel; a 1pt-wide stroke centred there covers three pixel rows and
        //    antialiases into a fourth, and the line arrives as a 4px smear of
        //    grey instead of an edge. Snapping the centre to the *middle* of a
        //    device pixel and stroking exactly one pixel wide is the fix, and
        //    the half-pixel is the whole trick: `round(x·px)/px` lands the
        //    stroke centre on a pixel *boundary*, which splits a one-pixel
        //    stroke evenly across two rows and is the same smear at half the
        //    width.
        //
        //    A third of the width at the same alpha would be a third of the
        //    ink, so the alpha carries the difference: `base × min(px, 2.5)`
        //    holds the perceived weight roughly constant (dark 0.05 → 0.125,
        //    light 0.07 → 0.175 at 3x) and is an identity at `px == 1` (tvOS),
        //    where a 1pt line already *was* one device pixel.
        let px = max(1, displayScale)
        func snapped(_ value: CGFloat) -> CGFloat {
            ((value * px).rounded() + 0.5) / px
        }
        // `i % 3 != 0` is new: the two interior box boundaries used to get a
        // hairline *and* (under Increase Contrast) a box rule stacked on the
        // same pixel, which quietly added ink to the one line whose weight this
        // whole step is trying to measure against.
        var lines = Path()
        for i in 1..<9 where i % 3 != 0 {
            let offset = snapped(CGFloat(i) * cell)
            lines.move(to: CGPoint(x: offset, y: 0))
            lines.addLine(to: CGPoint(x: offset, y: size.height))
            lines.move(to: CGPoint(x: 0, y: offset))
            lines.addLine(to: CGPoint(x: size.width, y: offset))
        }
        let hairBase = increased ? (isLight ? 0.20 : 0.16) : (isLight ? 0.07 : 0.05)
        context.stroke(
            lines,
            with: .color(gridTone.opacity(hairBase * Double(min(px, 2.5)))),
            lineWidth: 1 / px)

        // 2.2 Variant rules: killer cages and thermo tubes (PRD-24).
        //
        //     **This seam is chosen, not convenient.** Above the hairlines,
        //     because a tube crossed by a cell separator reads as three marks
        //     rather than one stroke; below the highlight, the coach wash, the
        //     cursor ring and the digits, because those are the loudest marks on
        //     the board and a rule is context rather than news — and because
        //     nothing may ever occlude a digit the player placed.
        if let channelRules { drawRules(channelRules, in: &context, cell: cell, scale: scale) }

        // 2.4 Box rules. **Always drawn now, and the alternating luminance wash
        //     that used to stand in for them is gone.**
        //
        //     The board inverted its own semantic skeleton and the pixels said
        //     so: sampled across y=1450 of the shipped frames, a cell hairline
        //     stepped Δ11/255 in dark against the box boundary's Δ9, and in
        //     light Δ17 against Δ11. The cell lines read as strong as the box
        //     lines in dark and *stronger* in light — which tells the eye that
        //     a sudoku is 81 equal cells rather than nine boxes of nine, i.e.
        //     the opposite of the rule of the game.
        //
        //     Deleting the wash rather than deepening it is the lesson PRD-22
        //     already recorded here, now unconditional. A wash is a wash
        //     *toward `gridTone`*, which is the ink's end of the scale on a
        //     dark theme and the ground's on a light one, so either way it
        //     moves the ground toward the digits and every contrast ratio
        //     inside the box falls — that is how the harness caught it under
        //     Increase Contrast (Void 14.72 → 13.62, Paper's coral 5.06 →
        //     4.43). A *line* costs nothing to a digit that is not on it, so
        //     with the wash gone that regression disappears by construction and
        //     `increased` only changes how loud the rule is.
        //
        //     0.42 of `tones.hairline` at 1.5–2pt is ~5× a cell hairline's ink
        //     in dark and ~4.5× in light — past the 2.5× the eye needs to rank
        //     two line weights, and short of the printed-grid look a solid
        //     black rule would give. `emphasiseBoxes` is for a board drawn
        //     small enough that the boxes are the only structure left.
        let boxWidth = max(1.5, 2 * scale)
        var boxes = Path()
        for i in 1...2 {
            let offset = snapped(CGFloat(i) * 3 * cell)
            boxes.move(to: CGPoint(x: offset, y: 0))
            boxes.addLine(to: CGPoint(x: offset, y: size.height))
            boxes.move(to: CGPoint(x: 0, y: offset))
            boxes.addLine(to: CGPoint(x: size.width, y: offset))
        }
        // The outer boundary is a **rounded rect**, not the `i == 0` and
        // `i == 3` lines it used to be. Straight rules laid along the board's
        // own edge are cut by step 0's corner clip and survive as four
        // disconnected crop marks with 14pt holes between them; this follows
        // the same curve the clip does, inset half its own width so the whole
        // stroke lands inside and reads at full weight, with the concentric
        // radius that keeps it parallel to the plane rather than merely near it.
        boxes.addPath(Path(
            roundedRect: CGRect(origin: .zero, size: size)
                .insetBy(dx: boxWidth / 2, dy: boxWidth / 2),
            cornerRadius: max(1, planeRadius - boxWidth / 2),
            style: .continuous))
        context.stroke(
            boxes,
            with: .color(tones.hairline.opacity(
                increased ? 1.0 : (emphasiseBoxes ? 0.62 : 0.42))),
            lineWidth: boxWidth)

        // 2.5 Same-number highlight: an accent wash on every cell holding the
        //     digit; cells whose pencil notes contain it get a quiet accent
        //     border instead — "where could the 9s go" reads at cell scale.
        if let highlightDigit, solvedAt == nil {
            for index in 0..<81 where game.entry(at: index) == highlightDigit {
                let row = index / 9, col = index % 9
                let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    .insetBy(dx: 3 * scale, dy: 3 * scale)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 12 * scale),
                    with: .color(accent.opacity(isLight ? 0.28 : 0.22))
                )
            }
            // Kept apart from the cursor on purpose: deeper inset, smaller
            // radius, thinner and dimmer stroke, no fill — when both land on
            // one cell the cursor ring draws later, brighter and outside.
            for index in 0..<81 where game.entry(at: index) == 0
                    && game.pencilDigits(at: index).contains(highlightDigit) {
                let row = index / 9, col = index % 9
                let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    .insetBy(dx: 6 * scale, dy: 6 * scale)
                let path = Path(roundedRect: rect, cornerRadius: 12 * scale)
                context.stroke(path, with: .color(accent.opacity(0.55)), lineWidth: max(1.5, 2 * scale))
            }
        }

        // 2.6 Coach wash (PRD-11): the pattern in accent, the cell the step
        //     resolves in a stronger ring, the cells losing a candidate in a
        //     dashed dimmer one. Dashed on purpose — an elimination is the
        //     absence of something, and a solid ring would read as "look here"
        //     rather than "this loses a digit". Drawn before the cursor, which
        //     stays the brightest thing on the board.
        if let coachFocus, solvedAt == nil {
            for index in coachFocus.pattern {
                let rect = BoardMetrics.rect(of: index, side: size.width)
                    .insetBy(dx: 3 * scale, dy: 3 * scale)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 12 * scale),
                    with: .color(accent.opacity(isLight ? 0.30 : 0.24))
                )
            }
            for index in coachFocus.victims {
                let rect = BoardMetrics.rect(of: index, side: size.width)
                    .insetBy(dx: 6 * scale, dy: 6 * scale)
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 12 * scale),
                    with: .color(accent.opacity(0.42)),
                    style: StrokeStyle(
                        lineWidth: max(1.5, 2 * scale),
                        dash: [4 * scale, 3 * scale]
                    )
                )
            }
            // The pivot: a thin *inner* ring, so a cell that is both pattern
            // and pivot reads as both. Drawn before the target ring, because a
            // step that has a pivot never also places, and a step that places
            // should keep the loudest mark on the board.
            if let pivot = coachFocus.pivot {
                let rect = BoardMetrics.rect(of: pivot, side: size.width)
                    .insetBy(dx: 8 * scale, dy: 8 * scale)
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 9 * scale),
                    with: .color(accent.opacity(0.85)),
                    lineWidth: max(1.5, 2 * scale)
                )
            }
            if let target = coachFocus.target {
                let rect = BoardMetrics.rect(of: target, side: size.width)
                    .insetBy(dx: 2 * scale, dy: 2 * scale)
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 15 * scale),
                    with: .color(accent),
                    lineWidth: max(2.5, 4 * scale)
                )
            }
            // The cell the player asked about, held for the whole chain
            // (PRD-25). Last, so it is never covered: a narration that loses
            // track of its own subject is a narration about nothing. Distinct
            // from the target ring by being *outside* the cell rather than
            // inside it, so the two read as different claims when a beat's
            // step finally resolves the asked cell and both land at once.
            if let asked = coachFocus.asked, asked != coachFocus.target {
                let rect = BoardMetrics.rect(of: asked, side: size.width)
                    .insetBy(dx: 1 * scale, dy: 1 * scale)
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 16 * scale),
                    with: .color(accent.opacity(0.7)),
                    style: StrokeStyle(lineWidth: max(2, 3 * scale),
                                       dash: [10 * scale, 5 * scale])
                )
            }
        }

        // 2.7 Hover halo (macOS pointer): a faint accent ring tracking the
        //     cell under the pointer. Dimmer and thinner than the cursor, and
        //     hidden when it lands on the cursor cell so the two never fight.
        if let hoverCell, solvedAt == nil, hoverCell != cursor {
            let row = hoverCell / 9, col = hoverCell % 9
            let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                .insetBy(dx: 5 * scale, dy: 5 * scale)
            let path = Path(roundedRect: rect, cornerRadius: 13 * scale)
            context.fill(path, with: .color(accent.opacity(isLight ? 0.10 : 0.08)))
            context.stroke(path, with: .color(accent.opacity(0.4)), lineWidth: max(1.5, 2 * scale))
        }

        // 3. Cursor.
        if solvedAt == nil {
            let row = cursor / 9, col = cursor % 9
            let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                .insetBy(dx: 4 * scale, dy: 4 * scale)
            let path = Path(roundedRect: rect, cornerRadius: 14 * scale)
            context.fill(path, with: .color(accent.opacity(0.16)))
            context.stroke(path, with: .color(accent.opacity(0.9)), lineWidth: max(2, 3 * scale))
        }

        // 4. Digits, pencil marks, error markers.
        let wave = waveProgress(now: now)
        // The mini keypad's pitch, shared by the notes, the handwritten notes
        // and the pencil ghost so all three land in the same nine slots.
        let notePitch = cell * BoardInk.notePitch
        for index in 0..<81 {
            let row = index / 9, col = index % 9
            let center = BoardMetrics.center(of: index, side: size.width)
            let digit = game.entry(at: index)
            let motion = cellMotion(index, now: now, cell: cell)

            if digit != 0 {
                let isGiven = game.isGiven(index)
                // PRD-27: a duel tints each player's digits. Deliberately above
                // the three branches below — error, completion wave and pad
                // peek all still override it, and their precedence is unchanged.
                var color = isGiven ? digitTone : (digitTint?(index) ?? accent)
                let isError = showErrors && game.isError(at: index)
                if isError { color = tones.coral }

                // Completion wave: a luminance crest. With the Afterglow
                // shader running, the phase is radial from the winning cell
                // so the brightening rides the same crest as the refraction;
                // Reduce Motion (and nil origin) keeps the classic diagonal.
                if let wave {
                    let phase: Double
                    if let waveOrigin, !reduceMotion {
                        let origin = BoardMetrics.center(of: waveOrigin, side: size.width)
                        let scaledRadius = maxRadius * size.width / side
                        phase = hypot(center.x - origin.x, center.y - origin.y) / scaledRadius
                    } else {
                        phase = Double(row + col) / 16.0
                    }
                    let boost = max(0, 1 - abs(wave - phase) * 4.5)
                    if boost > 0 {
                        color = gridTone.opacity(0.6 + 0.4 * boost)
                    }
                }

                // L2 peek: everything that isn't the peeked kind recedes.
                if let dimmedExcept, digit != dimmedExcept { color = color.opacity(0.16) }

                // The glyph, sized and weighted off `BoardInk` so the game
                // board, the mini boards and the widget draw one alphabet.
                // A given is `.semibold` against an entry's `.regular`, not
                // `.medium`: at this size one weight step is a ~4% stroke
                // difference, which is invisible, and it left the whole
                // given/entry hierarchy resting on hue alone — nothing in this
                // file reads `accessibilityDifferentiateWithoutColor`, so hue
                // alone is the same as nothing for some players.
                let glyph = Text("\(digit)")
                    .font(.system(
                        size: cell * (isGiven ? BoardInk.given : BoardInk.entry),
                        weight: isGiven ? BoardInk.givenWeight : BoardInk.entryWeight,
                        design: .rounded))
                    .foregroundStyle(color)
                withMotion(motion, about: center, in: &context) { layer in
                    layer.draw(glyph, at: center)
                }

                if isError {
                    // Coral underline, on the glyph…
                    let underline = CGRect(
                        x: center.x + motion.dx - cell * 0.24, y: center.y + cell * 0.30,
                        width: cell * 0.48,
                        height: increased ? max(3, 6 * scale) : max(2, 4 * scale)
                    )
                    context.fill(Path(roundedRect: underline, cornerRadius: 2 * scale), with: .color(tones.coral))
                    // …and a coral rim on the cell, which replaces the detached
                    // 5pt disc that used to sit 4.8pt off the cell's top edge.
                    // The disc was a third coral signal on one glyph and it read
                    // as dust on the lens — a speck floating beside a digit,
                    // attached to nothing. A rim is the same two channels the
                    // dot was there for (hue *and* shape, which is all
                    // Differentiate Without Colour asks) attached to the thing
                    // that is actually wrong: the cell. It does not move with
                    // the shake, because the cell does not move.
                    let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell,
                                      width: cell, height: cell)
                        .insetBy(dx: 3 * scale, dy: 3 * scale)
                    context.stroke(
                        Path(roundedRect: rect, cornerRadius: 12 * scale),
                        with: .color(tones.coral.opacity(0.5)),
                        lineWidth: max(1.5, 2 * scale))
                }
            } else {
                // Corner notes: a mini 3×3 keypad of pencil digits. A note of
                // the highlighted digit goes bold accent; its cell already
                // carries the border ring from step 2.5.
                //
                // **The pitch was the bug, not the glyph size.** A 0.22-cell
                // mark on a 0.28-cell pitch left a dead margin most of a note
                // wide all the way round the keypad, so three marks floated in
                // the middle of the cell and read as stray digits rather than
                // as candidates in slots. 0.33 pushes the outer ranks to the
                // cell's inner corners — 0.33 + half a glyph is 0.46 of the
                // cell, still inside the hairline — and the nine slots become
                // legible as a grid even when only two are filled. The ink
                // comes up with it (0.55 → 0.68): a note pushed out to the rim
                // sits over less of the cell's own wash and needs the weight.
                for mark in game.pencilDigits(at: index) {
                    let mc = CGFloat((mark - 1) % 3), mr = CGFloat((mark - 1) / 3)
                    let point = CGPoint(
                        x: center.x + (mc - 1) * notePitch,
                        y: center.y + (mr - 1) * notePitch
                    )
                    let highlighted = solvedAt == nil && mark == highlightDigit
                    var noteColor = highlighted ? accent : gridTone.opacity(0.68)
                    if let dimmedExcept, mark != dimmedExcept { noteColor = noteColor.opacity(0.16) }
                    // PRD-31: the player's own glyph if they have written this
                    // digit, the rounded typeface if they have not. Every note
                    // of a learned digit wears the hand — including the ones
                    // placed with the rose, on a phone, with no Pencil in the
                    // room — because a board where three marks are handwritten
                    // and the rest are set looks like a bug rather than a
                    // signature.
                    let ink: (inout GraphicsContext) -> Void
                    if let handGlyph = hand.glyph(for: mark) {
                        // 0.32 of a cell. A written glyph is a thin outline
                        // where the typeface is a solid mass, so it needs to be
                        // a little larger to read; the ceiling is the note
                        // pitch, because a glyph wider than the pitch makes
                        // neighbouring marks in the mini keypad touch. That
                        // ceiling was 0.28 and capped this at 0.30; at a 0.33
                        // pitch it can have the 0.32 it wanted.
                        ink = { layer in
                            layer.stroke(
                                Self.inkPath(handGlyph, centredAt: point, box: cell * 0.32),
                                with: .color(noteColor),
                                style: StrokeStyle(lineWidth: max(1, (highlighted ? 2.6 : 1.9) * scale),
                                                   lineCap: .round, lineJoin: .round)
                            )
                        }
                    } else {
                        let text = Text("\(mark)")
                            .font(.system(size: cell * BoardInk.note,
                                          weight: highlighted ? .bold : BoardInk.noteWeight,
                                          design: .rounded))
                            .foregroundStyle(noteColor)
                        ink = { layer in layer.draw(text, at: point) }
                    }
                    // The erase settle rides the notes, because the notes are
                    // what an erase usually *reveals*.
                    withMotion(motion, about: center, in: &context, ink)
                }
            }
        }

        // 4.5 Erase echo: a ring contracting out of the cell.
        //
        //     The inverse settle above animates whatever the cell holds
        //     afterwards, and a cell cleared down to nothing holds nothing — so
        //     on its own the loudest of the three events would be the one with
        //     no frame. This is the frame: one quiet ring, gone in 0.22s,
        //     drawn over the digits because it is the news.
        if let lastEvent, lastEvent.kind == .erase, !reduceMotion,
           solvedAt == nil, (0..<81).contains(lastEvent.cell) {
            let t = now.timeIntervalSince(lastEvent.at)
            if t >= 0, t < Self.settleDuration {
                let p = CGFloat(t / Self.settleDuration)
                let shrink = 2 * scale + p * cell * 0.34
                let rect = BoardMetrics.rect(of: lastEvent.cell, side: size.width)
                    .insetBy(dx: shrink, dy: shrink)
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 14 * scale),
                    with: .color(gridTone.opacity(0.38 * Double(1 - p))),
                    lineWidth: max(1.5, 2 * scale))
            }
        }

        // 5. Ghost preview: the rose's focused digit rendered in the cursor
        //    cell — accent-tinted and translucent, clearly a maybe, gone the
        //    moment the rose closes or the petal focus moves on.
        //
        //    **The ghost is the committed size, exactly.** It shipped at
        //    `62 * scale` against a digit's `56 * scale` and `26 * scale`
        //    against a note's `22 * scale`, so a digit *shrank 10%* — and a
        //    note 18% — the instant you committed it. A preview whose job is
        //    "this is what will happen" that then does something visibly
        //    different is worse than no preview; the tint and the alpha are
        //    what say "maybe", and they are enough.
        if let previewDigit, solvedAt == nil {
            let center = BoardMetrics.center(of: cursor, side: size.width)
            if previewPencil {
                // Pencil previews land where the note itself would: the
                // digit's slot in the mini 3×3 keypad. A touch more opacity
                // than the big ghost so the small glyph stays legible.
                let mc = CGFloat((previewDigit - 1) % 3), mr = CGFloat((previewDigit - 1) / 3)
                let point = CGPoint(
                    x: center.x + (mc - 1) * notePitch,
                    y: center.y + (mr - 1) * notePitch
                )
                context.draw(
                    Text("\(previewDigit)")
                        .font(.system(size: cell * BoardInk.noteGhost,
                                      weight: BoardInk.noteWeight, design: .rounded))
                        .foregroundStyle(accent.opacity(0.45)),
                    at: point
                )
            } else {
                context.draw(
                    Text("\(previewDigit)")
                        .font(.system(size: cell * BoardInk.ghost,
                                      weight: BoardInk.entryWeight, design: .rounded))
                        .foregroundStyle(accent.opacity(0.35)),
                    at: center
                )
            }
        }
    }

    // MARK: - Variant rules (PRD-24)

    /// Draw whatever rules this board carries. One entry point, dispatching on the
    /// constraint rather than on the channel, so a board that somehow held both
    /// would draw both instead of silently dropping one.
    private func drawRules(
        _ rules: ChannelRules, in context: inout GraphicsContext,
        cell: CGFloat, scale: CGFloat
    ) {
        // A rule this build cannot enforce is not drawn, because drawing a mark
        // whose meaning we do not know is worse than drawing nothing: the player
        // would reason about it. `AppModel.openChannelBoard` refuses to open such a
        // board at all, so this is the second of two guards, kept because a
        // renderer that trusts its input is a renderer that ships the bug.
        guard rules.isPlayable else { return }
        for constraint in rules.constraints {
            switch constraint {
            case .cage(let cage): drawCage(cage, in: &context, cell: cell, scale: scale)
            case .thermometer(let thermo):
                drawThermometer(thermo, in: &context, cell: cell, scale: scale)
            case .unrecognized: continue
            }
        }
    }

    /// A killer cage: a dashed outline hugging the region, with its sum in the
    /// top-left cell's corner.
    ///
    /// The outline is drawn as **the cage's own border only** — each cell
    /// contributes an inset edge where its neighbour across that edge is outside
    /// the cage — rather than as a rounded rect around the bounding box, which
    /// would be wrong for every cage that is not a rectangle, i.e. most of them.
    /// The dash pattern is the same family as the coach's dashed victim ring, so
    /// the board has one vocabulary for "this group of cells is what we are talking
    /// about".
    private func drawCage(
        _ cage: Cage, in context: inout GraphicsContext, cell: CGFloat, scale: CGFloat
    ) {
        let members = Set(cage.cells)
        let inset = 3.0 * scale
        var path = Path()
        for index in cage.cells {
            let row = Sudoku.row(of: index), col = Sudoku.col(of: index)
            let x = CGFloat(col) * cell, y = CGFloat(row) * cell
            let left = x + inset, right = x + cell - inset
            let top = y + inset, bottom = y + cell - inset
            // An edge is drawn only where the cage stops. `row`/`col` bounds are
            // checked before the membership lookup so a cell on the grid's rim
            // does not wrap around to the far side and think it has a neighbour.
            if row == 0 || !members.contains(index - 9) {
                path.move(to: CGPoint(x: left, y: top))
                path.addLine(to: CGPoint(x: right, y: top))
            }
            if row == 8 || !members.contains(index + 9) {
                path.move(to: CGPoint(x: left, y: bottom))
                path.addLine(to: CGPoint(x: right, y: bottom))
            }
            if col == 0 || !members.contains(index - 1) {
                path.move(to: CGPoint(x: left, y: top))
                path.addLine(to: CGPoint(x: left, y: bottom))
            }
            if col == 8 || !members.contains(index + 1) {
                path.move(to: CGPoint(x: right, y: top))
                path.addLine(to: CGPoint(x: right, y: bottom))
            }
        }
        context.stroke(
            path,
            with: .color(digitTone.opacity(increased ? 0.62 : 0.38)),
            style: StrokeStyle(
                lineWidth: max(1, 1.4 * scale), lineCap: .round,
                dash: [3.5 * scale, 3 * scale]))

        // The sum, in the cage's first cell — `Cage.cells` is sorted ascending, so
        // that is its top-left-most cell on every cage shape, deterministically.
        guard let anchor = cage.cells.first else { return }
        let row = Sudoku.row(of: anchor), col = Sudoku.col(of: anchor)
        // **`15 * scale` was 0.15 of a cell — 5.9pt on an iPhone, smaller than
        // a pencil note.** A cage sum is not decoration: on a killer board it
        // is the only thing that makes the cage solvable, and Channels ships to
        // the phone and nowhere else, so the one platform it had to be legible
        // on is the one it was smallest on. `BoardInk.cageSum` puts it at a
        // note's size, which is the floor for anything a player has to read.
        //
        // Pushed into the cell's corner (0.13 rather than 0.19/0.17) and given
        // a plate, the way every printed killer sudoku does it — the plate is
        // what stops a sum and the notes it sits among from reading as one
        // number, and it is what lets the sum be big enough to read without
        // fighting the mini keypad for the same pixels.
        let point = CGPoint(
            x: CGFloat(col) * cell + cell * 0.13,
            y: CGFloat(row) * cell + cell * 0.13)
        let sum = context.resolve(
            Text(verbatim: "\(cage.sum)")
                .font(.system(size: cell * BoardInk.cageSum, weight: .semibold, design: .rounded))
                .foregroundStyle(digitTone.opacity(increased ? 0.95 : 0.72)))
        let sumSize = sum.measure(in: CGSize(width: cell, height: cell))
        let plate = CGRect(
            x: point.x - sumSize.width / 2, y: point.y - sumSize.height / 2,
            width: sumSize.width, height: sumSize.height
        ).insetBy(dx: -2 * scale, dy: -1 * scale)
        context.fill(
            Path(roundedRect: plate, cornerRadius: 3 * scale),
            with: .color(tones.background))
        context.draw(sum, at: point)
    }

    /// A thermometer as a luminous glass tube: a bulb disc at the base and a
    /// capsule stroke running through every cell centre to the tip.
    ///
    /// **No new shader.** PRD-22 established that the board `Canvas` *is* the
    /// render surface the three `layerEffect`s sample, so a tube drawn here is
    /// lensed and washed by the existing pipeline for free — which is what makes it
    /// read as glass rather than as a grey pipe. Two strokes do the work: a wide
    /// soft one for the body and a narrow brighter one along its spine, which is
    /// how a cylinder reads without a gradient.
    ///
    /// Drawn in `gridTone` rather than in the accent, deliberately. The accent is
    /// the app's "this is *your* mark" colour — entries, the same-number highlight,
    /// the cursor — and a thermometer is part of the puzzle, like a given. A board
    /// of accent-coloured tubes would look like a board the player had already
    /// filled in.
    private func drawThermometer(
        _ thermo: Thermometer, in context: inout GraphicsContext,
        cell: CGFloat, scale: CGFloat
    ) {
        let centres = thermo.cells.map { index in
            CGPoint(
                x: CGFloat(Sudoku.col(of: index)) * cell + cell / 2,
                y: CGFloat(Sudoku.row(of: index)) * cell + cell / 2)
        }
        guard let bulb = centres.first else { return }

        var spine = Path()
        spine.move(to: bulb)
        for point in centres.dropFirst() { spine.addLine(to: point) }

        let body = increased ? 0.30 : 0.17
        let highlight = increased ? 0.42 : 0.26
        // Body: wide, soft, round-capped and round-joined so a bend reads as one
        // continuous tube rather than as two segments meeting at a corner.
        context.stroke(
            spine, with: .color(gridTone.opacity(body)),
            style: StrokeStyle(lineWidth: cell * 0.42, lineCap: .round, lineJoin: .round))
        // Spine: narrower and brighter, the specular line down a cylinder.
        context.stroke(
            spine, with: .color(gridTone.opacity(highlight)),
            style: StrokeStyle(lineWidth: cell * 0.13, lineCap: .round, lineJoin: .round))

        // The bulb, which is the only thing telling the player which end is the
        // small one. Without it a tube is symmetric and the constraint is
        // unreadable — so it is drawn last, over the body, and larger than the
        // stroke that leads out of it.
        let radius = cell * 0.30
        let disc = Path(ellipseIn: CGRect(
            x: bulb.x - radius, y: bulb.y - radius, width: radius * 2, height: radius * 2))
        context.fill(disc, with: .color(gridTone.opacity(body)))
        context.stroke(
            disc, with: .color(gridTone.opacity(highlight)),
            lineWidth: max(1, 1.2 * scale))
    }

    /// 0…1 progress of the completion wave, nil when idle / finished.
    private func waveProgress(now: Date) -> Double? {
        guard let solvedAt else { return nil }
        let t = now.timeIntervalSince(solvedAt)
        guard t >= 0, t < 2.6 else { return nil }
        return t / 2.6
    }
}

/// One frame of the Afterglow celebration, as a pure function of
/// time-since-solve (PRD-1 §2):
///
///   0 – 2.6s   refractive shockwave from the winning cell
///   2.6 – 5.4s one slow autonomous specular sweep (teaches the affordance)
///   ≥ 5.4s     glass trophy — gyro steers the sheen (iOS); without tilt
///              the sheen settles to a faint static and the caller pauses
struct AfterglowPhase: Equatable {
    static let waveDuration: TimeInterval = 2.6
    static let sweepEnd: TimeInterval = 5.4
    /// When the no-tilt settle (≈1s fade after the sweep) is fully static.
    static let settleTime: TimeInterval = 6.5

    private static let sweepStrength = 0.35
    private static let trophyStrength = 0.30
    private static let staticStrength = 0.12

    var waveProgress: Double?
    var sheenPos: Double = 0.5
    var sheenTilt: SIMD2<Double> = .zero
    var sheenStrength: Double = 0

    var waveActive: Bool { waveProgress != nil }
    var sheenActive: Bool { sheenStrength > 0.001 }

    static func at(_ t: TimeInterval, tilt: SIMD2<Double>?) -> AfterglowPhase {
        var phase = AfterglowPhase()
        guard t >= 0 else { return phase }

        if t < waveDuration {
            phase.waveProgress = t / waveDuration
            return phase
        }

        if t < sweepEnd {
            let p = (t - waveDuration) / (sweepEnd - waveDuration)
            phase.sheenPos = smoothstep(p)
            phase.sheenStrength = sweepStrength
            if let tilt, p > 0.85 {
                // Hand off to gyro steering over the sweep's last 15% —
                // position, tilt and strength all blend so there's no jump.
                let blend = smoothstep((p - 0.85) / 0.15)
                phase.sheenPos += (trophyPos(tilt) - phase.sheenPos) * blend
                phase.sheenTilt = tilt * blend
                phase.sheenStrength += (trophyStrength - sweepStrength) * blend
            }
            return phase
        }

        if let tilt {
            phase.sheenPos = trophyPos(tilt)
            phase.sheenTilt = tilt
            phase.sheenStrength = trophyStrength
        } else {
            // No motion source: glide the light back to rest and dim it —
            // the last frame before the timeline pauses.
            let f = smoothstep((t - sweepEnd) / (settleTime - sweepEnd - 0.1))
            phase.sheenPos = 1.0 + (0.5 - 1.0) * f
            phase.sheenStrength = sweepStrength + (staticStrength - sweepStrength) * f
        }
        return phase
    }

    /// Tilt is pre-clamped to ±0.35 by AfterglowMotion, so the highlight
    /// stays within the middle of the board — glass catching light, never
    /// a gimmick.
    private static func trophyPos(_ tilt: SIMD2<Double>) -> Double {
        0.5 + tilt.x * 0.6
    }

    private static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
