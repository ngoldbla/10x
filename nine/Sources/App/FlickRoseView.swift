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
    private var plateShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: CGFloat(
                RoseLens.plateCornerRadius(pencil: state.pencil, scale: Double(scale))),
            style: .continuous)
    }

    /// The petal's tint on the plate — its **only** material contribution,
    /// because `couchInset` deliberately adds none.
    ///
    /// Polarity, not symmetry. On a light theme a card inside a surface has to
    /// be **lighter** than the surface it sits on, never darker, so the petal is
    /// a strong white wash over the plate's own glass; on dark the same
    /// relationship needs a tenth of the alpha, because a 10% white lift over a
    /// near-black plate is already about twenty levels — the step the sampled
    /// 1.026:1 petal never had. Under Reduce Transparency both go up, for the
    /// reason `petalRim` gives below: that setting is a request for edges and
    /// fills instead of lighting.
    /// The wash that separates a petal from the plate it sits on.
    ///
    /// **Opaque toward the *ground*, never toward the ink.** Reduce
    /// Transparency has to make this fill more opaque — that is the whole point
    /// of the setting — but the first version did it by adding white on both
    /// leanings (0.10 → 0.18 on dark, 0.60 → 0.85 on light), and on a dark theme
    /// white *is* the ink. `contrast-harness.py` caught it: the numeral against
    /// its petal fell from 14.18:1 to 13.08:1 on Void and from 15.38:1 to
    /// 10.33:1 on Tide, and the harness's `gate_increased` exists for exactly
    /// this shape of mistake — an accessibility setting that measures worse than
    /// the default. Its own docstring records the first time the board did it,
    /// with box washes, for the same reason: a wash toward `gridTone` moves the
    /// ground toward the ink whichever way the theme leans.
    ///
    /// So the dark branch now deepens instead. Separation from the plate is the
    /// *rim's* job — it already strengthens under the same flag — and a rim can
    /// do that without ever walking the ground toward the glyph.
    private var petalTint: Color {
        if isLight { return .white.opacity(reduceTransparency ? 0.92 : 0.60) }
        return reduceTransparency ? .black.opacity(0.55) : .white.opacity(0.10)
    }

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
    private var petalRim: Color {
        if reduceTransparency { return digitTone.opacity(isLight ? 0.75 : 0.62) }
        return digitTone.opacity(isLight ? 0.45 : 0.32)
    }

    /// Not a hairline any more. 0.75pt was a *hair* — at 3× it is two device
    /// pixels of 32%-alpha ink, which is what the round-2 panel described as
    /// "a flat fill with a hairline stroke, not a material". A 46pt phone petal
    /// carries a 1pt edge comfortably, and the couch's 116pt petal wants 2.
    private var rimWidth: CGFloat { max(1, 2 * scale) }

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

    /// Mark 1 — the rim, as one stroke that changes what it is doing as it goes
    /// round: near-white where the light hits, the theme's ink at the equator,
    /// near-black on the shaded side. `.topLeading → .bottomTrailing` is
    /// `couchElevated`'s axis, so every lit edge in the app agrees about where
    /// the lamp is.
    private func rimGradient(dimmed: Bool) -> LinearGradient {
        let k = dimmed ? Self.completedSpecular : 1
        return LinearGradient(
            stops: [
                .init(color: .white.opacity((isLight ? 0.95 : 0.80) * k), location: 0.00),
                .init(color: .white.opacity((isLight ? 0.34 : 0.26) * k), location: 0.28),
                .init(color: petalRim.opacity(k), location: 0.58),
                .init(color: .black.opacity((isLight ? 0.26 : 0.58) * k), location: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Mark 2 — the inner highlight. Gone by 42% of the diagonal, so it is an
    /// *arc* along the top rather than a second full ring; a trimmed stroke
    /// would have given the same arc plus two end caps to explain.
    private func innerRim(dimmed: Bool) -> LinearGradient {
        let k = dimmed ? Self.completedSpecular : 1
        return LinearGradient(
            stops: [
                .init(color: .white.opacity((isLight ? 0.85 : 0.55) * k), location: 0.00),
                .init(color: .white.opacity((isLight ? 0.22 : 0.14) * k), location: 0.22),
                .init(color: .clear, location: 0.42),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Mark 3a — body. A dome takes the light on its upper shoulder and loses it
    /// on the lower one; without this the disc between the two rims is perfectly
    /// even, which is the read of a sticker, not of a solid.
    ///
    /// Alphas are small on purpose. On dark the numeral is near-white and the
    /// petal near-black, so this layer must not spend the 15:1 that relationship
    /// already has — and it does not, because it lives *below* the numeral.
    private var bodyShading: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(isLight ? 0.50 : 0.10), location: 0.00),
                .init(color: .white.opacity(isLight ? 0.18 : 0.02), location: 0.34),
                .init(color: .clear, location: 0.58),
                .init(color: .black.opacity(isLight ? 0.08 : 0.16), location: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Mark 3b — the glyph well: the ground's own tone, densest under the
    /// numeral and gone by 58% of the radius.
    ///
    /// This is the answer to PRD-22's lens. The board's digits are magnified up
    /// through the petals, which is the effect that sells the glass — but at the
    /// centre of the petal, where its own numeral sits, a magnified board digit
    /// is a second glyph in the same 20pt box. The critique read that as "the
    /// petals are blurred blobs". Bedding the numeral on the ground's tone
    /// resolves both halves at once: the numeral gains contrast, the competing
    /// glyph loses it, and the ring of the petal where a real lens actually
    /// shows its magnification is untouched.
    private var glyphWell: RadialGradient {
        let tone: Color = isLight ? .white : .black
        let peak = reduceTransparency ? 0.46 : 0.30
        return RadialGradient(
            stops: [
                .init(color: tone.opacity(peak), location: 0.00),
                .init(color: tone.opacity(peak * 0.55), location: 0.55),
                .init(color: .clear, location: 1.00),
            ],
            center: .center,
            startRadius: 0,
            endRadius: petalSize * 0.58
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
                if plated {
                    Color.clear
                        .frame(width: plateSpan, height: plateSpan)
                        .couchGlass(in: plateShape)
                        .couchElevated(in: plateShape, isLight: isLight)
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
        // centre, played backwards — so the rose now collapses toward the
        // cursor cell it grew out of.
        .transition(.scale(scale: 0.35, anchor: .center).combined(with: .opacity))
        // The transition only plays if the *parent* removes us inside a
        // transaction that carries an animation. `TouchUI`, `MacUI`, `FirstRun`
        // and `TutorialView` all wrap their `rose = …` in `withAnimation`, but
        // tvOS drives `PadSession.learningRose` straight, so on the couch the
        // insertion arrived with an empty transaction and the old `.onAppear`
        // was what animated it. Supplying a default rather than overriding one
        // keeps every animated caller exactly as it was.
        .transaction { $0.animation = $0.animation ?? .couchFast }
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
                    Circle().fill(bodyShading)
                    Circle().fill(glyphWell)
                }
                .frame(width: petalSize, height: petalSize)
                .allowsHitTesting(false)
            }
            .frame(width: petalSize, height: petalSize)
            .modifier(PetalMaterial(plated: plated, tint: petalTint))
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
/// articulation. They are why this does not simply become `.couchRim`:
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
            plated: true
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
