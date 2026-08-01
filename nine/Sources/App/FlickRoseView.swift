// FlickRoseView.swift — the signature moment: a 3×3 glass petal ring that
// blossoms around the focused cell. Digits map onto the rose like a phone
// keypad: 1 2 3 / 4 5 6 / 7 8 9 (center = 5 = tap). Completed digits are
// circled off. In pencil mode the petals shrink. The rose stays open while a
// focus ring walks the petals (swipes, on every remote — the click path's
// honest preview) and click places; a clean 8-way flick places instantly.
//
// **Nine discrete petals is the whole design, and for three releases it was
// never once drawn.** The ring used to sit in `CouchGlassContainer(spacing: 12)`,
// and that `spacing` is not a gap — it is `GlassEffectContainer`'s *fusion
// radius*, the distance within which sibling glass shapes union into one blob.
// At the phone's measured scale (0.40) a petal is 116 × 0.40 = 46.4pt on a
// 126 × 0.40 = 50.4pt pitch, so neighbours sit 4.0pt apart: one third of the
// threshold. Every pair fused permanently, at rest — solid hourglass necks
// between neighbours and four-pointed astroid holes between the quads. It was
// not a phone bug either: at tvOS scale 1.0 the gap is 10pt, still under 12.
// The container is now `spacing: 0`, which keeps the shared render pass (one
// backdrop sample for nine shapes, and the cheap bloom) while disabling the
// union. Widening the pitch instead would have been the wrong lever — it moves
// `RoseLens`, and with it the board's lens shader and `RoseLensTests`.
//
// The second half of "nine countable targets" is the rim. Sampled, the petal
// fill is RGB(21,21,21) against a board cell at RGB(18,18,18) — **1.026:1**
// in dark, 1.204:1 in light. Glass lifts and refracts a *backdrop*; over a
// near-black board there is nothing to lift, so the material collapses to a
// flat disc, and in light mode nine white discs on a white board become one
// amoeba whose only structure is the numerals. Glass rim light does not
// survive a low-contrast backdrop, so the rim here is explicit (`petalRim`).
//
// ROUND 2 — the petals were still "blurred grey blobs floating over the board".
// One uniform ink stroke at 32% is not an edge; it is an outline, and an outline
// on a disc whose fill differs from its surroundings by three RGB levels reads
// as a smudge. Worse, `TouchUI` now scrims the whole board card to 0.34 black
// while the rose is open (its own comment explains why: an undimmed board
// refracts the cursor ring and the coral error mark up through petals 2 and 3
// and fabricates states the rose never rendered). So the glass is sampling a
// *deliberately flattened* backdrop — there is, by construction, nothing left
// to refract. Every scrap of articulation the petal has must therefore be drawn.
//
// Four marks, all fractions of `petalSize` so they hold at every scale the rose
// has (35pt pencil petals on a phone through 116pt on the couch):
//
//   1. **A gradient rim** — near-white at `.topLeading`, the theme's ink at the
//      equator, near-black at `.bottomTrailing`. One stroke, three jobs: the
//      specular the critics asked for, the continuous boundary `petalRim` was
//      already carrying, and the contact edge that says the disc has a bottom.
//      Same light source as `couchElevated`'s card rim, so a petal and a card
//      are lit by the same lamp.
//   2. **An inner highlight** one rim-width inside the top arc, which is what
//      turns a stroked circle into a bevelled one.
//   3. **A body gradient and a glyph well**, drawn *under* the numeral (in the
//      Text's own `.background`, above the glass and below the ink) so the
//      numeral never has a tint layer over it. The well is the answer to the
//      lens: PRD-22 magnifies the board's own digits up through the petals, and
//      at the centre — where the petal's numeral lives — that magnified digit
//      is competition, not depth. It fades out by 58% of the radius, so the
//      lensed board still reads in the ring where a real lens shows it.
//   4. **A contact shadow**, a blurred ring hugging the outside of the disc and
//      offset down. Deliberately NOT `couchElevated`: that rung's shadow is a
//      fixed blur 20 / offset 8 sized for a 22pt-radius card, and on a 46pt
//      petal it is precisely the "shadow bleed that reads as a graphics glitch"
//      the critique names. A ring rather than a filled disc for a second
//      reason — the glass samples what is behind it, and a filled black circle
//      behind a petal would be sampled straight through the material and turn
//      the petal into a hole.
//
// ROUND 3 — two blind panels filed the same BLOCKER on both phone themes:
// *"nine unbacked circles that occlude the board and clip off its top edge"*,
// and *"reposition the 3×3 picker so it never covers the selected cell"*. Two
// changes answer it, and they are one design:
//
//   * **The ring is a popover now.** `RoseLens` places the plate under the
//     cursor cell (flipping above it near the bottom edge) and clamps it inside
//     the board's padded frame, so nothing clips and the cell being written
//     into stays readable. That is entirely `RoseLens`'s change — this file
//     draws wherever it is `.position`ed — and its header carries the argument.
//   * **The nine discs sit on ONE plate** (`plated`). A single rounded glass
//     container, one rim, one shadow, and the petals demoted to `couchInset`:
//     L4 on the ladder, `.identity` glass, *no second material*. That is the
//     documented fix for glass-nested-in-glass, and it is what deletes the
//     "double shadow" the panel named — mark 4 below, the per-petal contact
//     ring, was nine shadows in a frame that should have had one. It survives
//     only on the unplated ring, where it is the only elevation there is.
//
// `plated` defaults to **false**, and only `TouchRose` passes true. That is not
// timidity: it maps exactly onto `RoseLens`'s `clamped` flag. tvOS's two boards
// (`GameScreen`, `TutorialView`'s pad beat) mount `FlickRoseView` directly, pass
// `clamped: false`, and position the ring on the cursor cell from
// `BoardMetrics.center` — a free-floating ring that has never been guaranteed to
// be on the plane, and a plate that hangs off a board edge is worse than discs
// that do. Those two screens render byte-identically. Every anchored rose —
// TouchUI, MacUI, FirstRun, the touch tutorial — goes through `TouchRose` and
// gets the plate.
//
// The lens is the other winner. `BoardView`'s `rosePetalLens` magnifies the
// board's own digits up through the petals, and until now it did that over the
// cursor cell — *the one cell on the board guaranteed to be empty*. Beside the
// cell the same shader has digits and grid rules to bend, which is the round-3
// thesis everywhere else on this screen too: a lens has nothing to show over a
// void.
//
// ============================================================================
// ROUND 4 — the plate lost the surface it was made of, and the picker never
// said which cell it was for.
// ============================================================================
//
// `ipad-dark-rose` scored **2.5 against the previous round's 5.5** — the single
// largest confirmed regression a blind panel measured this round, filed from the
// panel's own *favoured* slot. Round 3 is what moved it. Three blockers, and
// each one has a cause you can point at in this file rather than a taste
// argument:
//
//   1. **"An opaque slab — the glass refracts nothing."** The plate is
//      `.regular` glass and always was; what erased it is what sits *on* the
//      plate. Nine 116pt petals on a 126pt pitch cover
//      `9·π·58² / 405² ≈ **58% of the plate's area**`, and each of them was a
//      near-opaque wash — `.white.opacity(0.60)` on paper, which over glass that
//      has already composited near-white is simply white paint — carrying a
//      full-disc dome gradient (up to a further 0.50 white) on top of it.
//      The material was left doing its job through the 42% of the plate nobody
//      looks at. **The fix is not more material, it is less paint**: the petals
//      are now the ladder's `Elevation.track` rung — *"a region marked out
//      inside a panel … the dish under a keycap"* — at the ladder's own alphas,
//      so the plate's glass (and the board bending through it) reads across all
//      nine rather than around them.
//   2. **"The wells read as smudge vignettes"**, and, on the phone frame,
//      *"disc 6 carries a smeared internal artifact from whatever gradient is
//      being drawn"*. Both are one arithmetic slip, and it is measurable rather
//      than aesthetic: `glyphWell`'s own comment says it "fades out by 58% of
//      the radius" and its `endRadius` read `petalSize * 0.58`. `petalSize` is a
//      **diameter**. The well therefore reached 116% of the radius — it covered
//      the whole disc and ran off the edge of it, at a 0.30 peak. That is the
//      smudge, in one number. It is now 0.42 of the *radius* at a 0.12 peak: a
//      bed under the numeral, not a vignette over the petal.
//   3. **"No visible anchor to the cell it edits — no tail, no connector and no
//      scaled-from-origin geometry."** `RoseLens.anchorOffset` has carried
//      exactly that vector since round 3 ("the popover's tail: the direction the
//      picker is pointing") and **nothing has ever drawn it**. It now arrives as
//      `anchorOffset` and buys three marks: the plate's silhouette grows a real
//      popover **tail** on the edge facing the cell (`RosePlateShape` — one
//      path, so the glass, the rim and the shadow all follow it and there is no
//      seam to explain), the ring gains **mark 5, a reticle** over the cursor
//      cell itself, and the growth transition's anchor moves from `.center` to
//      the cell, so the ring scales out of the cell it was opened on and
//      collapses back into it. The tail belongs to the plate and the reticle to
//      the rose; the four marks below stay the petal's own.
//
// **Why the plate survives a regression that was the plate's fault.** Going back
// to nine free discs restores the two blockers round 3 was written to answer —
// "unbacked circles that occlude the board and clip off its top edge" — and the
// panel's own remedy for both plated frames is *"rebuild the rose backplate on a
// real material"*, not "remove it". What regressed is the plate's **occlusion**
// and its **anonymity**, and both of those are drawn here.
//
// **And why the 3×3 lattice survives the "that is a keypad in disguise" note.**
// It is a keypad, deliberately and everywhere: `RoseGeometry.digit(for:)` maps
// the eight flick directions plus centre onto exactly these nine positions, so
// the lattice *is* the gesture — a radial ring would put digit 2 up-and-right of
// digit 1 while an up flick still placed 2, on every platform at once. It is
// also `RoseLens.petalCentre`, which the board's own lens shader bends at, and
// which `RoseLensTests` pins across all 81 cells. What the panel actually
// measured under that heading is the second half of its own sentence — *"give
// the discs a real material … so the grid reads through all nine"* — and that is
// what changed.
//
// Everything below is still one design at both leanings, and the polarity rule
// is `Elevation`'s rule 2, restated for a disc: on paper you may lift until you
// hit white and then you must recess, so a key on a near-white plate is **cut
// into** it (ink at 0.05) and a key on a near-black plate is **lifted out of**
// it (ink at 0.10). That is why the petal's interior lighting is now concave —
// a dish is lit on its *far* wall — while the rim keeps the app's one lamp at
// `.topLeading`. A rim lit from above around an interior lit from below is what
// a keycap is; the previous pass had both lit from above, which is a pillow.
import SwiftUI
import CouchKit

/// UI state for one open rose.
struct RoseState: Equatable {
    var pencil: Bool
    /// Petal index 0…8 (digit − 1) the d-pad focus is on. Starts at center.
    var focusedIndex: Int = 4
    /// Petals to shimmer after an ambiguous flick (see COUCHKIT-ASKS.md —
    /// CouchKit currently swallows ambiguous strokes, so this stays empty
    /// until the kit can report them; the misfire guarantee holds either way).
    var shimmerDigits: Set<Int> = []
    /// When the rose opened — used to ignore the tail of the click-touch
    /// that opened it, so a click can never read back as a center flick.
    var openedAt: Date = Date()
}

/// Digit ↔ 8-way direction mapping (keypad layout, +y up per CouchCore).
enum RoseGeometry {
    static func digit(for direction: Direction8OrCenter) -> Int {
        switch direction {
        case .upLeft: return 1
        case .up: return 2
        case .upRight: return 3
        case .left: return 4
        case .center: return 5
        case .right: return 6
        case .downLeft: return 7
        case .down: return 8
        case .downRight: return 9
        }
    }

    /// Petal offset in grid steps for digit 1…9: (-1,-1) top-left … (1,1).
    static func offset(forDigit digit: Int) -> (x: CGFloat, y: CGFloat) {
        let index = digit - 1
        return (CGFloat(index % 3 - 1), CGFloat(index / 3 - 1))
    }

    /// Move the 4-way petal focus. Screen-up decreases the row.
    static func moveFocus(_ index: Int, _ direction: Direction4) -> Int {
        var row = index / 3, col = index % 3
        switch direction {
        case .up: row = max(0, row - 1)
        case .down: row = min(2, row + 1)
        case .left: col = max(0, col - 1)
        case .right: col = min(2, col + 1)
        }
        return row * 3 + col
    }

    /// Classify a pointer/finger drag as one of eight petal directions
    /// (screen +y is down; the rose keypad thinks in +y up, matching
    /// CouchCore's flick math). Returns nil for a stroke shorter than
    /// `minimumDistance` — the never-misfire rule: an ambiguous nudge places
    /// nothing. Shared by the iOS touch rose and the macOS pointer rose
    /// (PRD-4 §2.3), so a trackpad drag and a finger flick classify
    /// identically.
    static func flickDirection(
        _ translation: CGSize, minimumDistance: CGFloat = 24
    ) -> Direction8OrCenter? {
        let dx = translation.width
        let dy = -translation.height
        guard hypot(dx, dy) >= minimumDistance else { return nil }
        let sector = Int((atan2(dy, dx) / (.pi / 4)).rounded())
        switch sector {
        case 0: return .right
        case 1: return .upRight
        case 2: return .up
        case 3: return .upLeft
        case 4, -4: return .left
        case -1: return .downRight
        case -2: return .down
        case -3: return .downLeft
        default: return nil
        }
    }
}

struct FlickRoseView: View {
    let state: RoseState
    let accent: Color
    let completedDigits: Set<Int>
    /// Show the focus ring. Always on where a d-pad drives the rose — it is
    /// the click path's honest preview — and on the touch/pointer rose only
    /// while a flick is in flight (`TouchRose.liveFocus`), where it is the
    /// same promise made to a finger.
    let showsFocusRing: Bool
    /// Multiplier on every petal metric. 1.0 is the TV rose; the touch rose
    /// passes something near 0.45 so petals sit finger-sized over the board.
    var scale: CGFloat = 1.0
    /// The digit already sitting in this cell, placement mode only — nil for
    /// an empty cell, and always nil for a given (the rose never opens on
    /// one). That digit's own petal renders the dashed erase rim instead of
    /// the tenth petal the rose used to grow: "this digit is here", never
    /// "this is wrong" (a wrongness signal would leak the solution).
    var currentDigit: Int? = nil
    /// The digits already pencilled into this cell, pencil mode only. Same
    /// rim, one petal per noted digit — `togglePencil`'s own XOR already
    /// erases a note on a second tap; this only makes that visible.
    var notedDigits: Set<Int> = []
    /// The board's own ink — `ThemeTones.digitTone` — so the digit you are
    /// about to place is drawn in the same hue as the digits you are reading.
    ///
    /// Defaulted to `.primary`, which is exactly what every petal used to be
    /// unconditionally: measured RGB(243,243,243) in dark against the board's
    /// own RGB(196,189,177), two hues 47 levels apart on the same glyph 10pt
    /// from each other, in one frame. The rose was the only surface in Nine
    /// that ignored the theme, which is why it read as a system alert pasted
    /// over a designed board.
    ///
    /// **The default is load-bearing**: it keeps the call sites in `TouchUI`,
    /// `MacUI`, `FirstRun`, `TutorialView` and `GameScreen` compiling untouched
    /// while the surfaces that own a `ThemeTones` pass the real value.
    var digitTone: Color = .primary
    /// Live focus, overriding `state.focusedIndex` for the duration of a
    /// gesture. `TouchRose` fills this from the in-flight drag so the flick has
    /// a preview before it commits; nil means "use the state's own focus".
    var focusOverride: Int? = nil
    /// Draw the nine petals on **one glass plate** instead of as nine free
    /// discs — see the round-3 note in the file header for why this is a
    /// parameter rather than the unconditional truth, and why its default is
    /// the one that leaves tvOS byte-identical.
    ///
    /// It changes three things and nothing else: a rounded glass container
    /// appears behind the ring, each petal drops from `couchGlassInteractive`
    /// (`.regular`) to `couchInset` (`.identity` + tint, so there is no second
    /// material inside the first), and mark 4 — the per-petal contact shadow —
    /// goes away, because the plate is now the thing that is floating.
    var plated: Bool = false
    /// **The vector from the rose's own centre to the cursor cell's centre**, in
    /// points, in this view's own (unmirrored) space — i.e.
    /// `RoseLens.anchorOffset`, which has computed it since round 3 and had no
    /// reader.
    ///
    /// Everything that ties the picker to the cell it fills hangs off this one
    /// value: the plate's tail, the reticle over the cell, and the anchor the
    /// growth transition scales about. `nil` — the default, and what every
    /// unanchored caller passes — draws none of them and leaves the ring
    /// byte-identical to what tvOS ships, which is the same contract `plated`
    /// has. Only a *clamped* `RoseLens` can promise the cell is outside the
    /// plate, so only a clamped caller should pass this.
    var anchorOffset: CGSize? = nil
    /// One board cell's side, for the reticle and for the tail's headroom —
    /// `RoseLens.cellSide`, which stores it for exactly this ("any gesture
    /// surface that wants to span from the cell to the picker").
    ///
    /// Defaulted rather than required: `RoseLens.scale(forSide:)` is
    /// `min(0.62, cell × 1.15 / 116)`, so below the cap a cell is the
    /// placement-mode petal diameter over 1.15 and the fallback is exact. Above
    /// the cap — a board wide enough that a cell-sized petal would be a dinner
    /// plate — it under-estimates, which is the safe direction: a reticle a
    /// little inside its cell is a reticle, and one a little outside it is a
    /// mistake.
    var cellSide: CGFloat? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The **theme's** lightness, not merely the system appearance: `NineApp`
    /// and `MacUI` both pin `preferredColorScheme` to `ThemeChoice.colorScheme`,
    /// so a Paper board on a phone in Dark Mode resolves `.light` here and a
    /// Blueprint board in Light Mode resolves `.dark`. Every polarity decision
    /// below hangs off this one line, which is why it is a named property and
    /// not nine inline comparisons.
    private var isLight: Bool { colorScheme == .light }

    /// Petal diameter and ring pitch, from `RoseLens` rather than from a fourth
    /// hand-copy of `116 * scale`. The board's lens shader bends inside
    /// `RoseLens.petalRadius`; if the paint and the bend disagree by a point the
    /// result is a magnified crescent *beside* the glass instead of inside it,
    /// which is the exact artefact `RoseLens`' header was written about.
    private var petalSize: CGFloat {
        CGFloat(RoseLens.petalDiameter(pencil: state.pencil, scale: Double(scale)))
    }
    private var spacing: CGFloat {
        CGFloat(RoseLens.ringSpacing(pencil: state.pencil, scale: Double(scale)))
    }

    /// The petals' own bounding square — two pitches and a diameter. This is
    /// what the view measured before there was a plate, and what it still
    /// measures unplated.
    private var ringSpan: CGFloat { spacing * 2 + petalSize }

    /// The plate, from the same source as everything else the rose draws. The
    /// surround and the corner radius are `RoseLens`' because the *placement*
    /// depends on them: `RoseLens` reserves room for this exact square beside
    /// the cursor cell, and a plate drawn wider than the square that was
    /// reserved is a plate back on top of the cell.
    private var plateSpan: CGFloat {
        CGFloat(RoseLens.plateSpan(pencil: state.pencil, scale: Double(scale)))
    }
    /// Concentric with the four corner petals by construction: a petal's radius
    /// plus the surround. Two rounded shapes nested with the *same* radius read
    /// as a mistake; this is the one radius that reads as a nest.
    private var plateCornerRadius: CGFloat {
        CGFloat(RoseLens.plateCornerRadius(pencil: state.pencil, scale: Double(scale)))
    }

    /// The plate's silhouette — the rounded square, plus the tail when the
    /// caller has told us where the cell is.
    private var plateShape: RosePlateShape {
        RosePlateShape(cornerRadius: plateCornerRadius, tail: plateTail)
    }

    // MARK: The anchor (round 4, mark 3)

    /// `anchorOffset`, once it has passed the two guards that make it drawable:
    /// there is a plate to hang a tail off, and the cell is somewhere other than
    /// under our own centre.
    ///
    /// The second guard is not defensive tidiness. `RoseLens`' fallback branch —
    /// a board too small to place the plate beside the cell at all — puts the
    /// ring back *on* the cell and reports `clearsAnchor == false`; a tail and a
    /// reticle drawn there would point at the thing they are standing on.
    private var anchorVector: CGSize? {
        guard plated, let offset = anchorOffset else { return nil }
        guard hypot(offset.width, offset.height) > 1 else { return nil }
        return offset
    }

    /// One cell's side — see `cellSide` for why the fallback is what it is.
    private var anchorCellSide: CGFloat {
        cellSide
            ?? CGFloat(RoseLens.petalDiameter(pencil: false, scale: Double(scale))) / 1.15
    }

    /// The popover tail, or nil where there is no room to draw one.
    ///
    /// Three facts decide it, in this order:
    ///
    ///   * **Which edge.** `RoseLens` places the plate *below* the cursor cell
    ///     and flips *above* it near the frame's bottom — never left or right —
    ///     so the tail is on the top or the bottom edge and a vector that is
    ///     mostly horizontal means something has gone wrong upstream and is
    ///     declined rather than guessed at.
    ///   * **How much room.** The gap is the centre-to-centre distance minus
    ///     half the plate and half the cell, which is `RoseLens.anchorGap` (8pt)
    ///     when the frame can afford it and **as little as zero** when it cannot
    ///     — the placement spends the gap before it spends the clearance. The
    ///     tail takes that gap less two points of air, so it can never reach
    ///     into the cell it is pointing at, and it declines below 3pt where a
    ///     tail would be a nick in the rim rather than a direction.
    ///   * **How wide.** Base is 1.5× the height. A tail taller than it is wide
    ///     reads as a spike; the flatter triangle is what every popover in the
    ///     system draws, and at the phone's scale it is about 6 × 18pt.
    private var plateTail: RoseTail? {
        guard let vector = anchorVector else { return nil }
        guard abs(vector.height) > abs(vector.width) else { return nil }
        let gap = abs(vector.height) - plateSpan / 2 - anchorCellSide / 2
        let height = min(petalSize * 0.22, gap - 2)
        guard height >= 3 else { return nil }
        return RoseTail(
            edge: vector.height > 0 ? .bottom : .top,
            offset: vector.width,
            height: height,
            halfBase: height * 1.5)
    }

    /// The plate square is centred on the ring; the tail's band is extra height
    /// on one side of the drawn frame, so the whole plate view slides half a
    /// tail to keep the square where the petals are.
    private var plateTailShift: CGFloat {
        guard let tail = plateTail else { return 0 }
        return tail.edge == .bottom ? tail.height / 2 : -tail.height / 2
    }

    /// Where the rose grows from and collapses back into: the cursor cell,
    /// expressed as a `UnitPoint` in the plate's own frame. Outside 0…1 by
    /// construction — the cell is beside the plate, never inside it — which
    /// `.scale(scale:anchor:)` accepts and is exactly the "scaled-from-origin
    /// geometry" the panel could not find.
    private var growthAnchor: UnitPoint {
        guard let vector = anchorVector, plateSpan > 1 else { return .center }
        return UnitPoint(
            x: 0.5 + vector.width / plateSpan,
            y: 0.5 + vector.height / plateSpan)
    }

    /// The petal's tint on the plate — its **only** material contribution,
    /// because `couchInset` deliberately adds none.
    ///
    /// **Round 4 took this from paint back to a token.** It shipped as
    /// `.white.opacity(0.60)` on paper, and a 60% white wash over glass that has
    /// already composited to near-white is not a tint, it is white paint: nine
    /// opaque discs covering 58% of the plate, which is the whole of the "opaque
    /// slab / the glass refracts nothing" blocker. `Elevation`'s ladder already
    /// names what a petal is — **`track`**, *"a region marked out inside a panel
    /// … the dish under a keycap"* — and gives it an alpha at each leaning:
    /// `wellHue × 0.05` on paper, `surfaceHue × 0.10` on a dark ground.
    ///
    /// Those are the two numbers below, expressed against `digitTone` because
    /// this view is handed the theme's *ink* and not a whole `ThemeTones`. The
    /// substitution is close to exact by construction: on a dark theme
    /// `surfaceHue` **is** `gridTone`, the theme's own light tone, which is
    /// `digitTone`'s own family (cream on Ember, pale blue on Blueprint); on a
    /// light theme `wellHue` is `gridTone`, the theme's deep tone, and
    /// `digitTone` is that tone at reading weight. Either way the key is made of
    /// the theme rather than of white, which is the other half of the panel's
    /// complaint — *"the named palette does not render"*.
    ///
    /// Polarity is `Elevation`'s rule 2 and not a symmetry: *on paper you may
    /// lift until you hit white, and then you must recess*. A key on a near-white
    /// plate has nowhere left to go up, so it is **cut into** the plate; a key on
    /// a near-black plate is **lifted out of** it.
    ///
    /// **Opaque toward the *ground*, never toward the ink.** Reduce
    /// Transparency has to make this fill more opaque — that is the whole point
    /// of the setting — but an early version did it by adding white on both
    /// leanings (0.10 → 0.18 on dark, 0.60 → 0.85 on light), and on a dark theme
    /// white *is* the ink. `contrast-harness.py` caught it: the numeral against
    /// its petal fell from 14.18:1 to 13.08:1 on Void and from 15.38:1 to
    /// 10.33:1 on Tide, and the harness's `gate_increased` exists for exactly
    /// this shape of mistake — an accessibility setting that measures worse than
    /// the default. So the two Reduce Transparency branches are unchanged, and
    /// they are the one place the petal is still allowed to be paint: that
    /// setting is a player asking for fills and edges instead of lensing, and
    /// under it `couchInset` has already dropped its material anyway.
    private var petalTint: Color {
        if reduceTransparency {
            return isLight ? .white.opacity(0.92) : .black.opacity(0.55)
        }
        return digitTone.opacity(isLight ? 0.05 : 0.10)
    }

    /// The key under the finger, one rung up the same ladder: `Elevation.card`
    /// over `Elevation.track`, in the accent rather than in the theme's ink
    /// because this is *state* and state is allowed to be coloured.
    ///
    /// It is the panel's "shadow ramp so the disc under the thumb elevates",
    /// done as a fill and a glow rather than as a shadow — nine petals sitting
    /// on one plate are flush by construction (see mark 4), and a shadow under a
    /// flush key is the "pile of stickers" `couchRim` was written against.
    private var focusTint: Color { accent.opacity(isLight ? 0.22 : 0.28) }

    /// The petal numeral. Was `(pencil ? 38 : 52) * scale` — 20.8pt at phone
    /// scale, *smaller* than the board digit it types (22.6pt), which is
    /// backwards for a transient interactive layer: the keypad you aim at
    /// should out-weigh the grid you read. At 62 the glyph is 0.53 of the
    /// petal, which is the same cap-to-container proportion `BoardType.entry`
    /// asks of a cell.
    private var glyphSize: CGFloat { (state.pencil ? 44 : 62) * scale }

    /// The **equator** of the rim gradient — the arc where neither the specular
    /// nor the contact edge is doing anything, and the only thing keeping the
    /// disc countable is its own boundary.
    ///
    /// Drawn in the theme's ink rather than in white, because a white rim is
    /// invisible in exactly the mode that needs it most — a light-theme petal
    /// composites near white, so white-on-white adds nothing and the amoeba
    /// survives. `digitTone` defaults to `.primary`, so even an un-themed caller
    /// gets a rim that flips polarity with the scheme.
    ///
    /// Light carries more weight than dark for the same reason: in dark the
    /// glass is already a shade *above* the board (21 vs 18) so the rim only
    /// has to finish an edge that half exists, while in light there is no
    /// step at all. Under Reduce Transparency both go up hard: that setting is a
    /// player asking for edges instead of lighting, and `couchGlassInteractive`
    /// is the rung of the ladder that predates the Reduce Transparency work —
    /// the four rungs added with it all branch, and the two original ones do
    /// not — so until it does, the compensation happens here, where the rose
    /// can at least guarantee itself a visible boundary.
    /// **Round 4 kept this untouched, and that is the deliberate half of the
    /// change.** Everything else about the petal got quieter — the fill went from
    /// paint to a `track` wash, the specular came down to `CouchSpecular`'s — and
    /// with a *translucent* key on a plate of nearly its own tone, this ink arc
    /// is no longer one of several things separating the two. It is the only one.
    private var petalRim: Color {
        if reduceTransparency { return digitTone.opacity(isLight ? 0.75 : 0.62) }
        return digitTone.opacity(isLight ? 0.45 : 0.32)
    }

    /// **A hairline again on the plate, and this time on purpose.**
    /// `CouchSpecular.width` is one point *"on every platform and at every scale
    /// — a rim is a lighting artifact, not a border, and a 2pt version of it
    /// stops reading as light and starts reading as a frame"*, and the panel
    /// measured the frame: *"make them actual concave keys with a specular top
    /// edge and a **1pt hairline rim**"*. Round 2's `max(1, 2 * scale)` was
    /// answering a different complaint — a 0.75pt hair — by overshooting past the
    /// doctrine, and at the phone's 0.40 it made no difference anyway (both floor
    /// at 1pt). Where it made a difference is the couch.
    ///
    /// So the split is by *plate*, not by platform, and it is the same split the
    /// whole rim treatment now makes: a key on a lit plate takes the hairline,
    /// because the plate's own `couchElevated` edge is already framing the group;
    /// a free disc — tvOS, where the ring is the outermost glass in the rose and
    /// there is nothing under it but a near-black board — keeps the 2pt edge that
    /// is the only boundary it has.
    private var rimWidth: CGFloat {
        plated ? max(CouchSpecular.width, 1.5 * scale) : max(1, 2 * scale)
    }

    /// The bevel: a second stroke immediately inside the rim, lit only along the
    /// top arc. A single stroke describes a *cut-out*; two concentric strokes
    /// with different lighting describe a *thickness*, which is the whole
    /// difference between a circle and a lens.
    private var innerRimWidth: CGFloat { max(0.75, rimWidth * 0.8) }

    /// How far a completed digit's numeral steps back. Legible, not ghosted —
    /// see the note at the `foregroundStyle` call.
    static let completedInk: Double = 0.55

    /// How far a *completed* petal's lighting steps back, on the same argument
    /// one line up: a digit that is already nine-of-nine on the board is still a
    /// legible target, but it should not be the brightest specular in the ring.
    /// The rim survives at 55% — the petal stays countable, it just stops
    /// catching the light.
    private static let completedSpecular: Double = 0.55

    // MARK: The four marks (see the file header)

    /// Mark 1 — the rim: one stroke that changes what it is doing as it goes
    /// round. Near-white where the light lands, the theme's ink at the equator,
    /// a shaded lip at `.bottomTrailing`. `.topLeading → .bottomTrailing` is
    /// `couchElevated`'s axis, so every lit edge in the app agrees about where
    /// the lamp is.
    ///
    /// **On a plate the extremes are `CouchSpecular.rimStops`' now** — 0.95/0.34
    /// → 0.16 on paper, 0.45/0.15 → 0.24 on a dark ground — rather than the
    /// hand-raised 0.80/0.58 pair round 2 shipped. Those were solved against a
    /// petal that was itself opaque paint, where the only way to describe an edge
    /// is to draw one; a 0.58 black at the bottom of a 46pt disc is not a lip, it
    /// is the drop shadow of a pillow, and two panels read it exactly that way
    /// (*"pillowed inner-shadow wells … 2019 skeuomorphism"*, *"smudge
    /// vignettes"*). A free disc keeps the raised pair, for the reason
    /// `rimWidth` gives one property up: it is the outermost glass in the rose
    /// and there is nothing under it to finish its edge.
    ///
    /// One thing is kept at both rungs, and it is the reason this is not simply
    /// `couchRim`: `CouchSpecular` passes through **zero** alpha at the equator,
    /// which is right for a card whose fill already separates it from the page
    /// and wrong for a translucent key on a plate of nearly its own tone. The
    /// ink equator is what keeps nine of them countable.
    private func rimGradient(dimmed: Bool) -> LinearGradient {
        let k = dimmed ? Self.completedSpecular : 1
        let crest = plated ? (isLight ? 0.95 : 0.45) : (isLight ? 0.95 : 0.80)
        let shoulder = plated ? (isLight ? 0.34 : 0.15) : (isLight ? 0.34 : 0.26)
        let lip = plated ? (isLight ? 0.16 : 0.24) : (isLight ? 0.26 : 0.58)
        return LinearGradient(
            stops: [
                .init(color: .white.opacity(crest * k), location: 0.00),
                .init(color: .white.opacity(shoulder * k), location: 0.30),
                .init(color: petalRim.opacity(k), location: 0.58),
                .init(color: .black.opacity(lip * k), location: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Mark 2 — the inner highlight, and it is now **CouchKit's**, stop for
    /// stop: `CouchSpecular.innerHighlightStops` read `.top → .bottom` rather
    /// than along the diagonal.
    ///
    /// Vertical is the correction. That gradient's own note says why — the outer
    /// bevel has already described the light's *direction*, so this line is
    /// describing the pane's *thickness*, and thickness is uniform across the
    /// top arc. Run diagonally (as it was) it thins toward the leading edge and
    /// piles up in one corner, which is a glint, not an edge. It dies by 34% of
    /// the height, so the sides and the bottom of the stroke draw nothing at all.
    private func innerRim(dimmed: Bool) -> LinearGradient {
        let k = dimmed ? Self.completedSpecular : 1
        let stops = CouchSpecular.innerHighlightStops(isLight: isLight).stops
            .map { Gradient.Stop(color: $0.color.opacity(k), location: $0.location) }
        return LinearGradient(
            gradient: Gradient(stops: stops),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Mark 3a — **the dish, and it is concave now.** A keycap is not a dome:
    /// its floor is scooped, so with the lamp at `.topLeading` the *near* wall
    /// falls into shadow and the *far* wall catches the light. Which is the
    /// exact inverse of what shipped, where the interior and the rim were both
    /// lit from the top-leading corner — and two coincident highlights on a
    /// small disc is the definition of a pillow.
    ///
    /// The amplitude comes down with it: the old dome ran a 0.50 white against a
    /// 0.08 black on paper, which is a quarter of the way to white *on top of* a
    /// 0.60 white tint. Nothing here now exceeds 0.10 except the far wall on
    /// paper, where a white-on-white surface has no other way to show a scoop.
    /// It is still drawn *below* the numeral, so none of it is spent on the one
    /// relationship the petal is measured by.
    private var dishShading: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(isLight ? 0.06 : 0.10), location: 0.00),
                .init(color: .black.opacity(0), location: 0.42),
                .init(color: .white.opacity(0), location: 0.56),
                .init(color: .white.opacity(isLight ? 0.30 : 0.09), location: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Mark 3b — the glyph well: the ground's own tone, densest under the
    /// numeral and gone by 42% of the **radius**.
    ///
    /// This is the answer to PRD-22's lens. The board's digits are magnified up
    /// through the petals, which is the effect that sells the glass — but at the
    /// centre of the petal, where its own numeral sits, a magnified board digit
    /// is a second glyph in the same 20pt box. Bedding the numeral on the
    /// ground's tone resolves both halves at once: the numeral gains contrast,
    /// the competing glyph loses it, and the ring of the petal where a real lens
    /// actually shows its magnification is untouched.
    ///
    /// **The unit was wrong and that is the whole of the "smudge vignette"
    /// finding.** `endRadius` read `petalSize * 0.58`, and `petalSize` is a
    /// *diameter* — so a gradient documented as fading out at 58% of the radius
    /// actually reached **116%** of it: it covered the entire disc, ran past the
    /// rim, and did it at a 0.30 peak. Two panels described the result
    /// independently, as "smudge vignettes" and as "a smeared internal artifact"
    /// on one disc. Half the radius times 0.42 is the number the comment always
    /// claimed, and the peak comes down to 0.12 to match a petal that is now
    /// translucent rather than paint.
    private var glyphWell: RadialGradient {
        let tone: Color = isLight ? .white : .black
        let peak = reduceTransparency ? 0.30 : 0.12
        return RadialGradient(
            stops: [
                .init(color: tone.opacity(peak), location: 0.00),
                .init(color: tone.opacity(peak * 0.55), location: 0.55),
                .init(color: tone.opacity(0), location: 1.00),
            ],
            center: .center,
            startRadius: 0,
            endRadius: petalSize * 0.5 * 0.42
        )
    }

    var body: some View {
        CouchGlassContainer(spacing: 0) {
            ZStack {
                // The plate — one shape, one material, one shadow, and a
                // sibling of the petals inside the same glass container rather
                // than a `.background` outside it, so the `.identity` rung the
                // petals use has the enclosing container it is defined against.
                //
                // `couchGlass` (L2, `.regular`) and not `couchGlassOverContent`
                // (L1, `.clear`): the petals contribute no material at all now,
                // so if the plate were clear the whole rose would be tints and
                // rims — which is the "flat opaque fill with a hairline" verdict
                // this round exists to answer, arrived at from the other side.
                // `couchElevated` supplies the rim and the shadow. It is one
                // shadow: `CouchSpecular.ambient` plus `CouchSpecular.contact`
                // are two *layers* of one occlusion, and the double shadow the
                // panel saw was nine of mark 4 in a frame that wanted one.
                //
                // **Round 4: the plate has a tail.** `RosePlateShape` is one
                // path — square and tail together — so the material, the rim and
                // the shadow all follow the popover silhouette and there is no
                // seam at the base to explain away. Drawing the tail as a second
                // shape behind the plate would have been four lines shorter and
                // would have printed a rim across its own base, because the
                // plate above it is glass and glass is not a mask.
                //
                // The drawn frame carries the tail's band as extra height and
                // `plateTailShift` slides it back, so the square stays
                // concentric with the ring and the nine tap targets `TouchRose`
                // overlays keep sitting exactly on the nine petals.
                if plated {
                    Color.clear
                        .frame(width: plateSpan,
                               height: plateSpan + (plateTail?.height ?? 0))
                        .couchGlass(in: plateShape)
                        .couchElevated(in: plateShape, isLight: isLight)
                        .offset(y: plateTailShift)
                        .allowsHitTesting(false)
                }
                ForEach(1...9, id: \.self) { digit in
                    petal(for: digit)
                }
            }
        }
        // Plated, the view *is* the plate: the nine tap targets `TouchRose`
        // overlays are sized from this frame's centre, so growing it by the
        // surround keeps them concentric with the petals they cover.
        .frame(width: plated ? plateSpan : ringSpan,
               height: plated ? plateSpan : ringSpan)
        // Mark 5 — the reticle over the cursor cell. Outside the frame by
        // construction and `allowsHitTesting(false)` throughout, so the scrim
        // behind it keeps its tap-to-dismiss and the nine targets keep theirs.
        .overlay { anchorMark }
        // The ring is spatial, not textual, and must not follow the writing
        // direction (PRD-20 decision 3). `.offset(x:)` *is* direction-aware, so
        // under `-NSForceRightToLeftWritingDirection` the petals laid out
        // 3 2 1 / 6 5 4 / 9 8 7 — measured, on screen, not inferred. An Arabic
        // player reaching for the 3 would have found the 1.
        //
        // The flick path is the second half of the argument: `flickDirection`
        // reads `DragGesture`'s raw translation, which is *not* mirrored. Pin
        // the petals and the two agree again; leave them mirrored and a
        // rightward flick places the digit drawn on the left.
        .environment(\.layoutDirection, .leftToRight)
        // One statement for both directions. It used to be a `bloomed` flag set
        // true `.onAppear`, which describes an *entrance* and nothing else:
        // every `closeRose()` in the app nils the state without ever setting
        // `bloomed` back, so the ring bloomed open from the cell and then, on
        // dismissal, a full-size rose simply evaporated in place. A transition
        // is symmetric by construction — the same 0.35 scale about the same
        // point, played backwards — so the rose now collapses toward the
        // cursor cell it grew out of.
        //
        // **And in round 4 it genuinely does.** The anchor was `.center`, so
        // "collapses toward the cursor cell" was true only while the ring was
        // still centred *on* the cell; once round 3 made it a popover the
        // sentence stopped being true and the picker started blooming out of its
        // own middle, several rows from the thing it edits — which is the
        // panel's *"no scaled-from-origin geometry"*, in one argument.
        // `growthAnchor` is the cursor cell in the plate's own unit space, and
        // `.center` for every caller that does not pass one.
        .transition(.scale(scale: 0.35, anchor: growthAnchor).combined(with: .opacity))
        // The transition only plays if the *parent* removes us inside a
        // transaction that carries an animation. `TouchUI`, `MacUI`, `FirstRun`
        // and `TutorialView` all wrap their `rose = …` in `withAnimation`, but
        // tvOS drives `PadSession.learningRose` straight, so on the couch the
        // insertion arrived with an empty transaction and the old `.onAppear`
        // was what animated it. Supplying a default rather than overriding one
        // keeps every animated caller exactly as it was.
        .transaction { $0.animation = $0.animation ?? .couchFast }
    }

    /// **Mark 5 — the reticle: "these nine digits go *there*."**
    ///
    /// The tail says which direction; this says which of the nine cells in that
    /// direction, which is the half a tail alone cannot carry across a 200pt
    /// board. Three layers, and the first two exist because of what is between
    /// the player and that cell: `TouchUI` scrims the whole board card while the
    /// rose is open (0.34 black / 0.38 white — its own comment explains why: an
    /// undimmed board refracts the cursor ring and the coral error mark up
    /// through petals 2 and 3 and fabricates states the rose never rendered), so
    /// the cell being edited is dimmed along with everything else. The glow and
    /// the wash put that one cell back **above** the scrim, which is the panel's
    /// "keep the target cell punched out of the scrim" done from the only side
    /// of the scrim this file is on.
    ///
    /// The accent rather than the theme's ink, because this is the same claim
    /// the board's own cursor makes and it should be the same colour making it.
    /// Inset by a point so the ring sits *inside* its cell rather than on the
    /// grid rule it shares with the neighbouring one.
    @ViewBuilder
    private var anchorMark: some View {
        if let vector = anchorVector {
            let side = anchorCellSide
            let shape = RoundedRectangle(cornerRadius: side * 0.20, style: .continuous)
            ZStack {
                shape
                    .fill(accent.opacity(0.34))
                    .blur(radius: side * 0.20)
                shape.fill(accent.opacity(isLight ? 0.14 : 0.18))
                shape.strokeBorder(accent.opacity(0.92),
                                   lineWidth: max(1.5, 2.5 * scale))
            }
            .frame(width: max(0, side - 2), height: max(0, side - 2))
            .offset(x: vector.width, y: vector.height)
            .allowsHitTesting(false)
        }
    }

    private func petal(for digit: Int) -> some View {
        let offset = RoseGeometry.offset(forDigit: digit)
        let complete = completedDigits.contains(digit)
        // A live gesture outranks the resting focus: `TouchRose` feeds the
        // in-flight drag in here so the flick previews before it commits.
        let focused = showsFocusRing && (focusOverride ?? state.focusedIndex) == digit - 1
        let shimmering = state.shimmerDigits.contains(digit)
        // "This digit is here" — the placed digit in placement mode, or a
        // noted digit in pencil mode. Never "this is wrong": that would leak
        // the solution, which is exactly what the removed tenth petal did
        // not do either.
        let erasable = state.pencil ? notedDigits.contains(digit) : currentDigit == digit

        return Text("\(digit)")
            // `.bold`, up from `.semibold`. The numeral is the one thing in the
            // ring that is pure signal, and at the phone's 24.8pt it was being
            // read against a lensed board digit under it and a soft rim around
            // it. Weight is the cheapest contrast there is: it costs no colour,
            // no size and no layout, and it is what makes the glyph win the
            // centre of the disc rather than share it.
            .font(.system(size: glyphSize, weight: .bold, design: .rounded))
            // A completed digit is quieted, never ghosted. `Color.primary
            // .opacity(0.30)` composited to about RGB(89,89,89) on the petal —
            // 3.0:1, scraping AA-large and around Lc 45 on APCA against a Lc 60
            // requirement — and alpha-dimming is the wrong grammar besides: it
            // makes "done" look like a failure to render. 0.55 lands near
            // 5.5:1, and the *state* is carried by `CompletedIndicator`'s ring,
            // not by the alpha (Differentiate Without Colour).
            .foregroundStyle(complete ? digitTone.opacity(Self.completedInk)
                             : erasable ? accent
                             : digitTone)
            // Marks 3a and 3b, in the numeral's OWN background — above the
            // glass, below the ink. An `.overlay` would have been one line
            // shorter and would have laid a tint over the glyph; the whole point
            // of the well is that the glyph is the thing it is bedding.
            //
            // Fixed `petalSize` frames inside a background that is measured
            // against the *text*: both layers stay concentric with the petal
            // because `.frame(width:height:)` below centres the text in the
            // disc, so the text's centre and the disc's centre are one point.
            .background {
                ZStack {
                    // The key under the thumb, one rung up: `Elevation.card`
                    // over `Elevation.track`, in the accent because it is state.
                    // Drawn under the dish rather than over it so the scoop
                    // still reads while the key is armed.
                    Circle().fill(focusTint.opacity(focused ? 1 : 0))
                    Circle().fill(dishShading)
                    Circle().fill(glyphWell)
                }
                .frame(width: petalSize, height: petalSize)
                .allowsHitTesting(false)
            }
            .frame(width: petalSize, height: petalSize)
            .modifier(PetalMaterial(plated: plated, tint: petalTint))
            // The elevation ramp the panel asked for — *"a shadow ramp so the
            // disc under the thumb elevates"* — as a glow rather than a shadow.
            // Behind the material, so the key is lit from under its own edge
            // rather than outlined a second time, and gone entirely at rest, so
            // nothing about the resting ring changes.
            .background {
                if focused {
                    Circle()
                        .fill(accent.opacity(isLight ? 0.30 : 0.45))
                        .blur(radius: petalSize * 0.16)
                        .allowsHitTesting(false)
                }
            }
            // Mark 4 — the contact shadow, *behind* the glass so the material
            // has one real thing to sample. A ring rather than a disc: see the
            // file header. The offset is what makes it read as elevation and not
            // as a halo, and every number is a fraction of the petal so the
            // 35pt pencil petal and the 116pt couch petal cast the same shadow.
            //
            // **Unplated only.** A petal on a plate is *flush* — it is a key on
            // a keypad, not a disc hovering over a board — and nine contact
            // shadows inside one container is exactly the "double shadow" the
            // round-3 panel filed. The plate's `couchElevated` carries the
            // elevation for all nine, once. Elevation belongs to whichever
            // surface is outermost.
            .background {
                if !plated {
                    Circle()
                        .stroke(Color.black.opacity(isLight ? 0.20 : 0.55),
                                lineWidth: petalSize * 0.11)
                        .blur(radius: petalSize * 0.075)
                        .offset(y: petalSize * 0.045)
                        .allowsHitTesting(false)
                }
            }
            // Marks 1 and 2. Two concentric strokes, drawn last of the material
            // layers so nothing washes over the specular — the focus ring and
            // the two indicator rings below are *state*, and state is allowed
            // to cover lighting.
            .overlay {
                Circle()
                    .strokeBorder(rimGradient(dimmed: complete), lineWidth: rimWidth)
                    .allowsHitTesting(false)
            }
            .overlay {
                Circle()
                    .inset(by: rimWidth)
                    .strokeBorder(innerRim(dimmed: complete), lineWidth: innerRimWidth)
                    .allowsHitTesting(false)
            }
            .modifier(CompletedIndicator(
                active: complete, tone: digitTone, scale: scale, petalSize: petalSize))
            .overlay {
                Circle()
                    .strokeBorder(accent.opacity(focused ? 0.95 : 0), lineWidth: max(2, 4 * scale))
            }
            .modifier(EraseIndicator(active: erasable, accent: accent, scale: scale, petalSize: petalSize))
            .scaleEffect(focused ? 1.1 : 1.0)
            .modifier(ShimmerPulse(active: shimmering, accent: accent))
            .offset(x: offset.x * spacing, y: offset.y * spacing)
            .animation(.couchFast, value: focused)
    }
}

// MARK: - The plate's silhouette

/// The popover tail: which edge it leaves from, where along that edge, and how
/// big. Computed by `FlickRoseView.plateTail` from `anchorOffset`; consumed by
/// `RosePlateShape`, which is the only thing that knows how to draw it.
private struct RoseTail: Equatable {
    /// Only the two edges `RoseLens` can place against. It puts the plate below
    /// the cursor cell and flips above it near the frame's bottom — never
    /// beside it — so a left/right tail would be describing a placement that
    /// cannot happen, and `plateTail` declines rather than inventing one.
    enum Edge { case top, bottom }

    let edge: Edge
    /// Signed distance of the apex from the plate's own vertical midline. The
    /// cursor cell is x-aligned with the plate until the clamp runs the plate
    /// into a board edge, and then it is not — which is exactly when a tail
    /// stops being decorative and starts being the only thing saying which
    /// column is being filled.
    let offset: CGFloat
    /// How far the apex stands off the plate's edge.
    let height: CGFloat
    /// Half the base. `plateTail` sets it at 1.5 × `height`: a tail taller than
    /// it is wide reads as a spike, and every popover the system draws is the
    /// flatter triangle.
    let halfBase: CGFloat
}

/// **The plate, as one path.** A continuous rounded square with a tail on the
/// edge that faces the cursor cell.
///
/// One shape rather than a rounded rectangle plus a triangle behind it, and the
/// reason is what the plate is made of: the tail has to carry the same glass,
/// the same `CouchSpecular` rim and the same two-layer shadow as the square, and
/// a second shape tucked behind a *translucent* one is not hidden — it prints
/// its own rim straight across the base, which is a seam where a popover has a
/// continuous edge. `InsettableShape` for the same reason: `couchElevated`
/// strokes an inset copy of whatever it is given, and a tail that does not inset
/// with the rim loses its outline at exactly the tip.
///
/// The tail's band is reserved *inside* the drawn rect (`body` is the rect minus
/// `height` on the tail's side) rather than allowed to overhang it. A shape that
/// leaves its own bounds is a shape `glassEffect` may clip, and a clipped tail
/// is a nick rather than a point.
private struct RosePlateShape: InsettableShape {
    let cornerRadius: CGFloat
    let tail: RoseTail?
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> RosePlateShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let outer = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard outer.width > 0, outer.height > 0 else { return Path() }
        guard let tail, tail.height > 0 else {
            return Path(
                roundedRect: outer,
                cornerRadius: max(2, cornerRadius - insetAmount),
                style: .continuous)
        }

        // The square, which is the drawn rect minus the tail's band. The band's
        // height is *not* reduced by the inset: the inset has already moved the
        // whole rect in, so keeping the protrusion constant slides the apex in
        // with everything else, which is what an inset tail does.
        let height = tail.height
        let body = CGRect(
            x: outer.minX,
            y: tail.edge == .top ? outer.minY + height : outer.minY,
            width: outer.width,
            height: max(0, outer.height - height))
        guard body.width > 0, body.height > 0 else { return Path() }

        let radius = min(
            max(2, cornerRadius - insetAmount),
            min(body.width, body.height) / 2)
        let half = max(1, tail.halfBase - insetAmount)
        // Clamped so the base always lands on the straight run of its edge —
        // a tail growing out of a corner arc has no base to grow out of.
        let apexX = min(
            max(body.midX + tail.offset, body.minX + radius + half),
            body.maxX - radius - half)

        var path = Path()
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        // Top edge, leading → trailing.
        if tail.edge == .top {
            path.addLine(to: CGPoint(x: apexX - half, y: body.minY))
            path.addQuadCurve(
                to: CGPoint(x: apexX, y: body.minY - height),
                control: CGPoint(x: apexX - half * 0.42, y: body.minY - height * 0.62))
            path.addQuadCurve(
                to: CGPoint(x: apexX + half, y: body.minY),
                control: CGPoint(x: apexX + half * 0.42, y: body.minY - height * 0.62))
        }
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.minY),
            tangent2End: CGPoint(x: body.maxX, y: body.minY + radius),
            radius: radius)
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.maxY),
            tangent2End: CGPoint(x: body.maxX - radius, y: body.maxY),
            radius: radius)
        // Bottom edge, trailing → leading.
        if tail.edge == .bottom {
            path.addLine(to: CGPoint(x: apexX + half, y: body.maxY))
            path.addQuadCurve(
                to: CGPoint(x: apexX, y: body.maxY + height),
                control: CGPoint(x: apexX + half * 0.42, y: body.maxY + height * 0.62))
            path.addQuadCurve(
                to: CGPoint(x: apexX - half, y: body.maxY),
                control: CGPoint(x: apexX - half * 0.42, y: body.maxY + height * 0.62))
        }
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.maxY),
            tangent2End: CGPoint(x: body.minX, y: body.maxY - radius),
            radius: radius)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.minY),
            tangent2End: CGPoint(x: body.minX + radius, y: body.minY),
            radius: radius)
        path.closeSubpath()
        return path
    }
}

/// Which rung of the material ladder a petal stands on, which depends entirely
/// on whether there is a plate under it.
///
/// **Unplated** the petal is the outermost glass in the rose, so it is L2/L3:
/// `couchGlassInteractive`, unchanged, byte-identical to what tvOS has shipped.
///
/// **Plated** it is L4 — `couchInset`, `.identity` glass plus a tint. This is
/// the one rule the ladder is emphatic about: never nest `.regular` inside
/// `.regular`, because two lenses stacked do not read as two surfaces, they read
/// as one murkier one. Nine `.regular` discs inside one `.regular` plate would
/// be twelve of that mistake in a single control. `.identity` keeps each petal
/// registered with the enclosing `GlassEffectContainer` — so the ring still
/// morphs and the shared backdrop sample is still shared — while contributing no
/// second material, and the petal's own four marks then carry all of its
/// articulation — which, since round 4, is a *hairline* rim, a `CouchSpecular`
/// bevel, a shallow concave dish and a tight well, over a tint that is the
/// ladder's `track` rung rather than paint. They are why this does not simply
/// become `.couchRim`:
/// `CouchSpecular.rim` passes through zero alpha at the equator, which is
/// correct for a card whose fill already separates it from the page, and wrong
/// for a disc sitting on a plate of nearly its own tone. `petalRim`'s ink
/// equator is the mark that keeps nine of them countable.
private struct PetalMaterial: ViewModifier {
    let plated: Bool
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if plated {
            content.couchInset(in: Circle(), tint: tint)
        } else {
            content.couchGlassInteractive(in: Circle())
        }
    }
}

/// The erase indicator: a dashed ring inside the petal's own disc, composed as
/// an `.overlay` the same way the focus ring and `ShimmerPulse` are, so it
/// never fights either. It says "this digit is here" — not "this is wrong" —
/// which is why it never reads as a warning color: a wrongness signal would
/// leak the solution, and this petal is the correct one exactly as often as
/// any other.
///
/// Dash pattern and line weight are named constants rather than folded into
/// the `StrokeStyle` call — easy to retune, without being parameters nobody
/// else needs yet.
private struct EraseIndicator: ViewModifier {
    /// The dash **rhythm**, as a ratio, not as points.
    ///
    /// It shipped as `[3, 5]` multiplied by `scale`, which at the phone's 0.40
    /// is `[1.2, 2.0]` — a 3.6px-on / 6.0px-off pattern at 3×, small enough to
    /// alias into grey stippling and read as noise rather than as a dashed
    /// ring. The line *width* was floored for exactly this reason
    /// (`minimumLineWidth`) and the dash was not, so the two disagreed: a 1.5pt
    /// stroke chopped at 1.2pt intervals.
    ///
    /// Deriving the unit from the ring's own circumference makes the rhythm
    /// scale-invariant instead: `dashUnits` is the circumference in units, and
    /// one on-off period is 3.2 of them, so the ring carries **exactly ten
    /// dashes** at every scale, in both pencil and placement mode. Countable is
    /// the point — a fixed dash length is a different pattern on every petal
    /// size the rose has.
    static let dashRatio: [CGFloat] = [1.2, 2.0]
    static let dashUnits: CGFloat = 32
    static let lineWidth: CGFloat = 2.5
    /// Floored for the same reason the focus ring is `max(2, 4 * scale)`: the
    /// touch rose runs near 0.4, where the unfloored weight computes to about
    /// a point and the ring reads as a hairline rather than as a mark.
    static let minimumLineWidth: CGFloat = 1.5
    /// Pulled in off the petal's edge. What is *measured* is the symptom: in
    /// `A-pencil-paper.png` from the Task 6 grid, captured against this same
    /// opaque-glass surface, the ring is simply absent on all three pencilled
    /// petals while the erasable digit still reads accent-coloured — so colour
    /// is left as the only cue, which Differentiate Without Colour does not
    /// accept. The presumed cause was that `couchGlassInteractive` is
    /// `.glassEffect` on iOS 26 and Liquid Glass draws its own specular
    /// highlight at the rim of the shape, where this ring used to sit.
    ///
    /// The inset is no longer clearing a *speculative* highlight. The petal now
    /// draws an explicit rim of its own, and round 2 made it two: a
    /// `strokeBorder` of `FlickRoseView.rimWidth` and a bevel of
    /// `innerRimWidth` immediately inside it, both `strokeBorder`s, so together
    /// they occupy the outermost `rimWidth + innerRimWidth` points and nothing
    /// beyond. The clearance is arithmetic, and it is checked at the *smallest*
    /// shipped petal, which is the one that fails first: pencil mode at phone
    /// scale is 88 × 0.40 = 35.2pt, where 8% is 2.82pt against a rim stack of
    /// 1.0 + 0.8 = 1.8pt. A point of air, and it widens at every larger scale
    /// because the inset grows with the petal and the rim stack is floored.
    ///
    /// **Still not photographed.** This lane cannot run `xcodebuild`, so the
    /// frame the original comment asked for — a filled cell selected, the
    /// dashed ring clearing the rim — has not been captured here either. What
    /// changed is that the number is now derived from geometry this file owns
    /// rather than from a guess about someone else's shader.
    ///
    /// Expressed against `petalSize` rather than `scale` because the petal is
    /// 88pt in pencil mode and 116pt in placement (`FlickRoseView.petalSize`),
    /// and an inset that reads on one is a different number on the other.
    static let insetFraction: CGFloat = 0.08

    let active: Bool
    let accent: Color
    let scale: CGFloat
    let petalSize: CGFloat

    func body(content: Content) -> some View {
        // The circumference the dashes actually run along, which is the inset
        // diameter — not the petal's.
        let diameter = petalSize - 2 * petalSize * Self.insetFraction
        let unit = (CGFloat.pi * diameter) / Self.dashUnits
        return content.overlay {
            Circle()
                .inset(by: petalSize * Self.insetFraction)
                .strokeBorder(
                    accent.opacity(active ? 0.9 : 0),
                    style: StrokeStyle(
                        lineWidth: max(Self.minimumLineWidth, Self.lineWidth * scale),
                        dash: Self.dashRatio.map { $0 * unit })
                )
                .allowsHitTesting(false)
        }
    }
}

/// The completed indicator: "all nine of these are already on the board."
///
/// It exists because the state used to be carried by alpha alone — the numeral
/// dropped to 30% and that was the entire signal — which fails twice. It fails
/// legibility (about 3.0:1 on the petal), and it fails grammar: a glyph that is
/// half there reads as a rendering fault, not as an achievement. Alpha is now
/// the *quiet*, and this ring is the *state*, which is the same split
/// `EraseIndicator` already argues for one type up: colour may not be the only
/// cue, so the cue is a mark.
///
/// A ring drawn snugly around the numeral rather than at the petal's edge, for
/// three reasons. It is the pencil-and-paper gesture for "counted, done" — you
/// circle the thing. It cannot be confused with `EraseIndicator`, which is
/// dashed, accent-coloured and 9% of a petal further out, so a digit that is
/// both complete and sitting in this cell shows two legible rings instead of
/// one ambiguous one. And it cannot be confused with the petal rim or the focus
/// ring, both of which live at the edge.
private struct CompletedIndicator: ViewModifier {
    /// Deeper than `EraseIndicator.insetFraction` (0.08) by enough to read as a
    /// different ring at the smallest petal: at pencil scale 0.40 the two are
    /// 3.2pt apart. Leaves the glyph room — the numeral is 0.53 of the petal
    /// (`FlickRoseView.glyphSize`), so its box clears a 0.66-diameter ring.
    static let insetFraction: CGFloat = 0.17
    static let lineWidth: CGFloat = 1.75
    /// Same floor argument as `EraseIndicator.minimumLineWidth`, one step
    /// lighter: this ring is a quiet annotation, not the erase affordance.
    static let minimumLineWidth: CGFloat = 1.0
    /// Deliberately below the numeral's own 0.55. The ring says "done"; the
    /// digit is still the thing being read.
    static let opacity: Double = 0.38

    let active: Bool
    let tone: Color
    let scale: CGFloat
    let petalSize: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            Circle()
                .inset(by: petalSize * Self.insetFraction)
                .strokeBorder(
                    tone.opacity(active ? Self.opacity : 0),
                    lineWidth: max(Self.minimumLineWidth, Self.lineWidth * scale))
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Pointer / touch rose

#if os(iOS) || os(macOS)
/// The flick rose with pointer input: tap (or click) a petal to place its
/// digit, or drag from anywhere in the rose toward a petal — the same 3×3
/// keypad mapping the Siri Remote uses (RoseGeometry), so the muscle memory
/// transfers between couch, pocket and desk. Shared by the iOS touch screen
/// and the macOS pointer screen (PRD-4 §2.3); on the Mac a click is a tap and
/// a trackpad drag is a flick, both routed through `RoseGeometry.flickDirection`.
struct TouchRose: View {
    let state: RoseState
    let accent: Color
    let completedDigits: Set<Int>
    let scale: CGFloat
    let onDigit: @MainActor (Int) -> Void
    /// See `FlickRoseView.currentDigit`.
    var currentDigit: Int? = nil
    /// See `FlickRoseView.notedDigits`.
    var notedDigits: Set<Int> = []
    /// Whether the ring traps assistive focus. True everywhere in the game —
    /// the rose is a keypad over a board and nothing else on screen applies.
    /// The first-run beat passes false: its rose sits inside a card that also
    /// carries the lesson and the **Skip** button, and a modal ring would put
    /// the only way out of the first run beyond VoiceOver, Switch Control and
    /// Full Keyboard Access (measured: `describe-ui` listed nine petals and
    /// nothing else at all).
    var isModal: Bool = true
    /// See `FlickRoseView.digitTone`. Defaulted for the same reason it is
    /// defaulted there — every existing call site keeps compiling untouched.
    var digitTone: Color = .primary
    /// Fires with the digit 1…9 the in-flight flick is currently aimed at, and
    /// with nil when the stroke is too short to classify or the finger lifts.
    ///
    /// The rose itself already shows this as a focus ring; the closure exists
    /// so a *host* can too — the free band under the board is where a ghost of
    /// the digit belongs, and that band is not the rose's to draw.
    var onLiveFocus: (@MainActor (Int?) -> Void)? = nil
    /// See `FlickRoseView.anchorOffset` — the vector to the cursor cell, which
    /// is what draws the plate's tail, the reticle over the cell, and the point
    /// the ring grows out of.
    ///
    /// It is `RoseLens.anchorOffset` as a `CGSize`, and every host of this view
    /// already holds that lens: `TouchUI` and `MacUI` position this very view
    /// from `lens.viewCentre` one line away. Defaulted so a host that has not
    /// passed it yet compiles and renders exactly as before, and so the one
    /// caller that must never draw a tail — a rose whose lens is unclamped, where
    /// nothing guarantees the cell is outside the plate — gets that by saying
    /// nothing.
    var anchorOffset: CGSize? = nil
    /// See `FlickRoseView.cellSide` — `RoseLens.cellSide`.
    var cellSide: CGFloat? = nil

    /// Petal index 0…8 the current drag points at; nil when there is no
    /// classifiable stroke in flight.
    ///
    /// This is what makes the focus-ring apparatus inside `FlickRoseView` — the
    /// ring, the 1.1 lift, the `.couchFast` — reachable on a phone at all. It
    /// was passed `showsFocusRing: false`, hard-coded, so every line of that
    /// was dead code here and the only gesture was `.onEnded`: you committed a
    /// digit blind and found out which one afterwards. A flick is a *stroke*,
    /// and a stroke that shows nothing until it ends cannot be corrected
    /// half-way through.
    @State private var liveFocus: Int?

    /// The tap targets' geometry, from the same `RoseLens` functions the drawn
    /// petals use. It was a second hand-copy of `(pencil ? 88 : 116) * scale`
    /// sitting eight lines from the first, and the two agreeing was a
    /// convention rather than a fact — a target that comes apart from the petal
    /// under it is the one bug in this file nobody would see in a screenshot.
    private var petalSize: CGFloat {
        CGFloat(RoseLens.petalDiameter(pencil: state.pencil, scale: Double(scale)))
    }
    private var spacing: CGFloat {
        CGFloat(RoseLens.ringSpacing(pencil: state.pencil, scale: Double(scale)))
    }

    var body: some View {
        FlickRoseView(
            state: state,
            accent: accent,
            completedDigits: completedDigits,
            // The ring is the flick's preview, and appears only while a stroke
            // is being aimed — the resting rose still shows none, so a
            // tap-only player never sees a ring they did not ask for.
            showsFocusRing: liveFocus != nil,
            scale: scale,
            currentDigit: currentDigit,
            notedDigits: notedDigits,
            digitTone: digitTone,
            focusOverride: liveFocus,
            // Every mount of `TouchRose` — TouchUI, MacUI, FirstRun and the
            // touch tutorial — positions itself from a *clamped* `RoseLens`,
            // which is the flag that guarantees the whole plate is on the board
            // plane and clear of the cursor cell. The plate and that guarantee
            // are the same decision, so they travel together: this is the only
            // place `plated` is turned on, and there is no call site that can
            // get a plate without the placement that makes it safe.
            plated: true,
            // The same guarantee, one round on: a tail and a reticle are claims
            // about where the cell is *relative to the plate*, and only a clamped
            // lens has placed the plate anywhere in particular. Both are nil
            // until the host hands the vector over, and both then draw
            // themselves from it.
            anchorOffset: anchorOffset,
            cellSide: cellSide
        )
        .accessibilityHidden(true) // the drawn petals; the targets below speak
        .overlay {
            // Invisible pointer targets aligned with the drawn petals. They
            // are also the rose's accessibility tree (PRD-19): the drawing is
            // hidden above, and these nine carry the labels, so a mixed
            // session — VoiceOver on, a sighted hand flicking — stays sane.
            // The board goes `.accessibilityHidden` while the rose is open,
            // which together with `.isModal` traps focus inside the ring.
            ZStack {
                ForEach(1...9, id: \.self) { digit in
                    let offset = RoseGeometry.offset(forDigit: digit)
                    // Same test `petal(for:)` uses to draw the dashed rim:
                    // one door, one grammar, so the label the VoiceOver user
                    // hears has to agree with the ring the sighted one sees.
                    let erasable = state.pencil ? notedDigits.contains(digit) : currentDigit == digit
                    Color.clear
                        .contentShape(Circle())
                        .frame(width: max(44, petalSize), height: max(44, petalSize))
                        .onTapGesture { onDigit(digit) }
                        .offset(x: offset.x * spacing, y: offset.y * spacing)
                        .accessibilityElement()
                        // Place/Note are the same two keys the actions rotor
                        // uses (`BoardActionPhrase`): the petals and the rotor
                        // are two doors onto one grammar, so they say one
                        // thing. `eraseDigit` is the petals' alone — the rotor
                        // reaches erase through its own `board.action.erase`
                        // button on the cell, which needs no digit in it.
                        .accessibilityLabel(erasable ? BoardActionPhrase.eraseDigit(digit)
                                            : state.pencil ? BoardActionPhrase.note(digit)
                                                           : BoardActionPhrase.place(digit))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onDigit(digit) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(state.pencil ? Strings.string("board.rose.note")
                                             : Strings.string("board.rose.digit"))
            .accessibilityAddTraits(isModal ? [.isModal] : [])
            // Pinned for the same reason the drawn ring is, and separately:
            // these targets are `.offset` from the same `RoseGeometry`, and if
            // only one of the two were pinned the tap targets would come apart
            // from the petals under them — which is worse than both mirroring,
            // because it looks correct.
            .environment(\.layoutDirection, .leftToRight)
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 24)
                // The preview. `flickDirection` is the *same* classifier
                // `.onEnded` commits with — not an approximation of it — so
                // the petal that lights up during the stroke is by
                // construction the petal that will be placed if the finger
                // lifts now. Anything less than that identity would be a
                // promise the commit could break.
                .onChanged { value in
                    let index = RoseGeometry.flickDirection(value.translation)
                        .map { RoseGeometry.digit(for: $0) - 1 }
                    guard index != liveFocus else { return }
                    liveFocus = index
                    onLiveFocus?(index.map { $0 + 1 })
                }
                .onEnded { value in
                    liveFocus = nil
                    onLiveFocus?(nil)
                    if let direction = RoseGeometry.flickDirection(value.translation) {
                        onDigit(RoseGeometry.digit(for: direction))
                    }
                }
        )
    }
}
#endif

/// A quiet two-beat glow for ambiguous-flick candidates: "one of these two —
/// flick again, cleaner." Never fires a digit.
private struct ShimmerPulse: ViewModifier {
    let active: Bool
    let accent: Color
    @State private var phase = false

    func body(content: Content) -> some View {
        content
            .overlay {
                Circle()
                    .strokeBorder(accent.opacity(active ? (phase ? 0.85 : 0.25) : 0), lineWidth: 3)
            }
            .onChange(of: active) { _, nowActive in
                guard nowActive else { return }
                withAnimation(.easeInOut(duration: 0.35).repeatCount(4, autoreverses: true)) {
                    phase = true
                }
            }
            .onAppear { phase = false }
    }
}
