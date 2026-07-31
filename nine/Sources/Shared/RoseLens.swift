// RoseLens.swift — where the rose's petals are, in board-local points (PRD-22).
//
// This used to be six copies of the same arithmetic: TouchUI, MacUI, FirstRun,
// TutorialView (twice) and GameScreen each recomputed `126 * scale`, the
// `184 * scale` clamp and `centre + inset` by hand. That was survivable while
// only the petals read it. PRD-22 adds a second reader — the board Canvas's
// third layer effect bends and magnifies the digits under each petal — and a
// lens that disagrees with the paint by four points reads as a smear beside the
// glass rather than as glass. So the arithmetic lives once, here, in
// Sources/Shared, where Lane 1 tests it on Linux without a simulator.
//
// Coordinates are **board-local**: the origin is the Canvas's top-left corner,
// which is `inset` points inside the glass plane. That is the space the two
// Afterglow shaders already speak (`BoardMetrics.center(of:side:)` is passed
// straight into `afterglowWave`), so the lens speaks it too. `viewCentre` adds
// the inset back for `.position`, which measures in the padded frame.
//
// Linux-clean on purpose: no SwiftUI, no CoreGraphics, no CGPoint. The App
// layer converts to CGFloat at the boundary.
//
// ============================================================================
// ROUND 3 — **the ring is a popover now, not a bloom.**
// ============================================================================
//
// For three rounds the ring's centre *was* the cursor cell's centre. Round 2's
// header said, in this spot, that displacing it "cannot be reconsidered in this
// file alone" because three of the four constants were pinned by
// `RoseLensTests`, the clamp was pinned twice more, and six call sites
// `.position` the drawn ring from `viewCentre`. That was true, and it is why
// round 2 declined the change rather than doing half of it. Two blind panels
// then filed the same BLOCKER on both phone themes:
//
//   * "nine unbacked circles that occlude the board and clip off its top edge"
//   * "Reposition the 3×3 picker so it never covers the selected cell's
//      row/column context (flip below the cell, or anchor to the board edge)"
//
// Round 3 owns the test file, so the whole change lands in one commit. Three
// facts made it cheap in the end:
//
//   1. **Every consumer is derived.** `viewCentre` (six `.position` call sites),
//      `petalCentre(digit:)` (the drawn petals, the tap targets, and TouchUI's
//      Pencil-hover hit test) and `centre` (`BoardView`'s `rosePetalLens`
//      shader) all read the stored centre. Move the centre and all of them move
//      together, with **no edit to any call site**. The four pinned metrics —
//      `spacing`, `petalRadius`, the pitch and the diameter — did not move at
//      all, so the shader still bends at exactly the radius the paint draws at.
//   2. **The old clamp was the bug it was written to prevent.** It read
//      `min(max(v, radius - 6), frameSide - radius + 6)` — a *negative* six
//      points, so a row-1 cursor put the ring's top arc six points **outside**
//      the padded frame. That is the "clips off its top edge" finding, in the
//      arithmetic, and it has been there since PRD-1. The same six points now
//      point inward (`plateMargin`), which is the whole of that fix.
//   3. **The cell the rose writes into is the one cell guaranteed to be
//      empty.** A lens over it had nothing to refract — the rose was parked on
//      the only hole in the board. Beside it, the same lens sits over digits
//      and grid rules, which is what round 3 is about everywhere else too.
//
// The placement rule is `anchoredCentre`, below: the plate hangs directly under
// the cursor cell like a popover, flipping above it when the frame runs out,
// x-aligned with the cursor's column and clamped so no petal ever leaves the
// board's padded frame. `clearsAnchor` is the guarantee, and `RoseLensTests`
// walks all 81 cells asserting it.
//
// **`clamped: false` is untouched.** tvOS's two boards (`GameScreen`,
// `TutorialView`'s pad beat) pass it, position the ring from
// `BoardMetrics.center` directly, and are driven by a d-pad rather than a
// finger — the couch rose has never been clamped and does not become a popover
// here. Those two screens render byte-identically.
import Foundation

/// Cell geometry, duplicated from `BoardMetrics` because that type lives in the
/// App layer — it needs `CGPoint`/`CGRect` for the accessibility frames — and
/// this one has to compile on Linux. `RoseLensTests` reads `BoardView.swift`
/// and fails if the two formulas stop agreeing.
public enum BoardGeometry {
    /// Centre of a cell in a board of arbitrary side length.
    public static func centre(of cell: Int, side: Double) -> (x: Double, y: Double) {
        let unit = side / 9
        return ((Double(cell % 9) + 0.5) * unit, (Double(cell / 9) + 0.5) * unit)
    }
}

/// Everything the petals and the shader have to agree on.
public struct RoseLens: Equatable, Sendable {
    /// Petal diameter is `116 * scale` (88 in pencil mode); ring pitch is
    /// `126 * scale` (96). These four numbers are `FlickRoseView`'s, unchanged
    /// — round 3 moved where the ring *is*, not how big it is.
    ///
    /// **The 10pt difference between pitch and diameter is deliberate and it is
    /// not the thing that was broken.** For three releases the rose rendered as
    /// one fused quilt — hourglass necks between neighbours, four-pointed holes
    /// between the quads — and the cause was upstream of this file: the ring
    /// sat in `CouchGlassContainer(spacing: 12)`, and that `spacing` is
    /// `GlassEffectContainer`'s *fusion radius*, not a gap. Ten points of air
    /// (4.0pt at the phone's 0.40 scale) is under 12 at every scale the rose
    /// has, so every neighbour unioned, permanently, at rest.
    ///
    /// The fix is `spacing: 0` in `FlickRoseView`. **Do not widen these four
    /// numbers to buy the gap back** — they are the pitch the board's lens
    /// shader bends at, so moving them moves `plateSpan`, the six call sites'
    /// `.position`, and `RoseLensTests`, to fix a problem that was never here.
    private static let petalSide = 116.0, pencilPetalSide = 88.0
    private static let ringPitch = 126.0, pencilRingPitch = 96.0

    /// A petal's **drawn diameter** at `scale`, and the ring's pitch, as free
    /// functions — because the painter needs them before it has a lens.
    ///
    /// `FlickRoseView` and `TouchRose` each carried their own copy of
    /// `(pencil ? 116 : 88) * scale`, which made four copies of a constant this
    /// file exists to hold one of. The instance properties below are now these
    /// two functions, so the paint, the tap targets and the board's lens shader
    /// cannot drift apart by so much as a point — and a petal drawn a hair
    /// smaller than the radius the shader bends inside is exactly the "smear
    /// beside the glass" failure this file's header warns about.
    ///
    /// Additive: `spacing` and `petalRadius` still return what they always did,
    /// which is what `RoseLensTests` pins.
    public static func petalDiameter(pencil: Bool, scale: Double) -> Double {
        (pencil ? pencilPetalSide : petalSide) * scale
    }

    /// Centre-to-centre distance between neighbouring petals at `scale`.
    public static func ringSpacing(pencil: Bool, scale: Double) -> Double {
        (pencil ? pencilRingPitch : ringPitch) * scale
    }

    // MARK: - The plate (round 3)

    /// Air between the petals' bounding square and the plate's edge, as a
    /// fraction of one petal's **diameter** — so the 35pt pencil petal on a
    /// phone and the 116pt petal on a couch get proportionally the same
    /// surround rather than the same points.
    ///
    /// The panel asked for "one glass plate (single rounded container, one
    /// shadow)" in place of nine unbacked discs, and a plate needs a surround
    /// or it is a clip path. 0.16 puts 7.4pt around the phone's ring and 18.6pt
    /// around the TV's, which is a hair over one `petalGap` in both — the plate
    /// reads as the same kind of air the petals already have between them.
    private static let platePadFraction = 0.16

    /// Half a petal's diameter plus the surround: the radius the plate's
    /// corners must use to stay **concentric** with the four corner petals.
    /// Same rule `Radius.inner(_:inset:)` states in the App layer's tokens,
    /// restated here because this file may not import them.
    public static func plateCornerRadius(pencil: Bool, scale: Double) -> Double {
        petalDiameter(pencil: pencil, scale: scale) / 2
            + platePadding(pencil: pencil, scale: scale)
    }

    /// The surround, in points, at `scale`.
    public static func platePadding(pencil: Bool, scale: Double) -> Double {
        petalDiameter(pencil: pencil, scale: scale) * platePadFraction
    }

    /// The plate's side: two pitches, one petal, two surrounds. This replaces
    /// the old `clampSpan` constant, which was the same arithmetic minus the
    /// surround — `126 + 116/2 = 184` was half the *ring*, and the ring is no
    /// longer the outermost thing the rose draws.
    public static func plateSpan(pencil: Bool, scale: Double) -> Double {
        2 * ringSpacing(pencil: pencil, scale: scale)
            + petalDiameter(pencil: pencil, scale: scale)
            + 2 * platePadding(pencil: pencil, scale: scale)
    }

    /// How far inside the board's padded frame the plate must stay.
    ///
    /// **The same six points the old clamp had, with the sign corrected.** The
    /// shipped expression was `radius - 6 … frameSide - radius + 6`, which
    /// *licensed* six points of overhang; a cursor anywhere in row 1 therefore
    /// put the ring's top arc outside the frame, which is the "clips off its
    /// top edge" BLOCKER. Six points of air is small enough that the plate
    /// still uses the inset band the board leaves around the grid, and large
    /// enough that its shadow has somewhere to land.
    public static let plateMargin = 6.0

    /// Preferred air between the cursor cell's edge and the plate's edge — the
    /// same 8 as `Rhythm.dock`, which this file may not import.
    ///
    /// A *preference*, not a guarantee. Where the frame cannot afford it the
    /// placement gives the gap up point by point and keeps the clearance, which
    /// is the half that matters: a plate 3pt from the cell it is filling still
    /// leaves the cell readable, and a plate on top of it does not.
    public static let anchorGap = 8.0

    public let pencil: Bool
    public let scale: Double
    public let inset: Double
    /// Board-local centre of the ring, already placed and clamped onto the
    /// plane. Stored as two Doubles rather than a tuple because Swift cannot
    /// synthesise `Equatable` for a struct with a tuple stored property, and
    /// `BoardView` drives the lens bloom off `onChange(of: roseLens)`.
    public let centreX: Double
    public let centreY: Double
    /// Board-local centre of the **cursor cell** — where the ring used to
    /// bloom, and where it still points. Stored (rather than recomputed from a
    /// cursor index nobody else needs) because two readers want it: the tests,
    /// which assert the plate clears it, and any gesture surface that wants to
    /// span from the cell to the picker.
    public let anchorX: Double
    public let anchorY: Double
    /// One cell's side. Stored for the same reason: the clearance guarantee is
    /// a statement about a cell-sized rectangle, and this is the only place
    /// that knows how big one is.
    public let cellSide: Double

    public init(
        cursor: Int,
        side: Double,
        inset: Double,
        pencil: Bool,
        scale: Double,
        clamped: Bool = true
    ) {
        self.pencil = pencil
        self.scale = scale
        self.inset = inset
        let cell = side / 9
        self.cellSide = cell

        let raw = BoardGeometry.centre(of: cursor, side: side)
        self.anchorX = raw.x
        self.anchorY = raw.y

        guard clamped else {
            (self.centreX, self.centreY) = raw
            return
        }
        // The placement works in *view* coordinates — the padded frame —
        // because that is where the six call sites `.position` it and what the
        // plate has to stay inside. Converting back at the end keeps the stored
        // value in the board-local space the shader needs.
        //
        // **The non-pencil span, deliberately**, exactly as the old clamp used
        // the non-pencil `184`: a pencil plate is smaller, so reserving room
        // for the placement-mode one is always sufficient, and the ring does
        // not jump under the player's finger when the pencil toggle is hit.
        let half = Self.plateSpan(pencil: false, scale: scale) / 2
        let frameSide = side + 2 * inset
        let cx = raw.x + inset, cy = raw.y + inset
        // Centre-to-centre at which the plate stops overlapping the cursor
        // cell, and the centre-to-centre we would like if the frame allows it.
        let clear = cell / 2 + half
        let want = clear + Self.anchorGap

        // Below first, above second — a popover's own order, and the right one
        // here for a reason beyond convention: the rose is opened by a finger
        // that is *on* the cursor cell, and a picker that opens downward is not
        // the one hidden under the hand that opened it. Two passes: the second
        // spends the margin rather than the clearance, because a plate flush
        // with the frame's edge is a cosmetic loss and a plate over the cell
        // being filled is the BLOCKER.
        var placed: (x: Double, y: Double)?
        for margin in [Self.plateMargin, 0] {
            let lo = half + margin, hi = frameSide - half - margin
            guard lo <= hi else { continue }
            if cy + clear <= hi {
                placed = (min(max(cx, lo), hi), min(cy + want, hi))
            } else if cy - clear >= lo {
                placed = (min(max(cx, lo), hi), max(cy - want, lo))
            }
            if placed != nil { break }
        }

        let view: (x: Double, y: Double)
        if let placed {
            view = placed
        } else {
            // No room on either side: the plate is wider than the board can
            // hold beside a cell. Measured, this needs `inset == 0` — every
            // inset the app actually passes (6, 8, 10, 12, 16, 20, 28) clears
            // at every side from 160 to 1300pt. The fallback is the pre-round-3
            // behaviour minus the overhang: bloom on the cell, stay on the
            // plane. `clearsAnchor` reports false here rather than lying.
            let lo = half, hi = frameSide - half
            view = lo <= hi
                ? (min(max(cx, lo), hi), min(max(cy, lo), hi))
                : (frameSide / 2, frameSide / 2)
        }
        (self.centreX, self.centreY) = (view.x - inset, view.y - inset)
    }

    /// Board-local centre of the ring — the space the two Afterglow shaders
    /// already speak.
    public var centre: (x: Double, y: Double) { (centreX, centreY) }

    /// Board-local centre of the cursor cell the rose was opened on.
    public var anchor: (x: Double, y: Double) { (anchorX, anchorY) }

    /// The vector from the ring's centre to the cursor cell's, in points.
    ///
    /// `.zero` for an unclamped (tvOS) rose, which still blooms on the cell.
    /// Anywhere else it is the popover's "tail": the direction the picker is
    /// pointing, and the span a gesture surface would have to cover for a flick
    /// that begins on the cell rather than on the plate.
    public var anchorOffset: (x: Double, y: Double) {
        (anchorX - centreX, anchorY - centreY)
    }

    /// Ring pitch: centre-to-centre between neighbouring petals.
    public var spacing: Double {
        Self.ringSpacing(pencil: pencil, scale: scale)
    }

    /// Half a petal's drawn diameter — the radius the shader bends inside.
    public var petalRadius: Double {
        Self.petalDiameter(pencil: pencil, scale: scale) / 2
    }

    /// The plate's drawn side, corner radius and surround at this lens's own
    /// pencil state — what `FlickRoseView` paints, as opposed to the
    /// placement-mode span the placement above reserves.
    public var plateSpan: Double { Self.plateSpan(pencil: pencil, scale: scale) }
    public var platePadding: Double { Self.platePadding(pencil: pencil, scale: scale) }
    public var plateCornerRadius: Double {
        Self.plateCornerRadius(pencil: pencil, scale: scale)
    }

    /// **The round-3 guarantee, as a predicate.** True when the plate's square
    /// and the cursor cell's square do not overlap — i.e. the player can still
    /// read the cell the next digit is going into, and the digit already in it
    /// if there is one.
    ///
    /// Separated on either axis is enough: two axis-aligned rectangles miss
    /// when they miss on one axis. The tolerance absorbs the exact-touch case
    /// the second placement pass produces when it spends the whole gap.
    public var clearsAnchor: Bool {
        let reach = plateSpan / 2 + cellSide / 2
        return abs(anchorX - centreX) >= reach - 1e-9
            || abs(anchorY - centreY) >= reach - 1e-9
    }

    /// Edge-to-edge air between two neighbouring petals, in points.
    ///
    /// Derived rather than declared, so it can never drift from the pitch and
    /// the diameter it is the difference of. Two readers want it: whatever
    /// draws the ring has to keep any glass fusion radius *below* this number
    /// or the nine petals silently become one shape (see the note on the
    /// constants above), and anything that lights the board under the rose has
    /// to know how much board is still visible between them.
    ///
    /// It is small on purpose — 4.0pt at the phone's measured 0.40, 10pt on
    /// tvOS. Nine discs that nearly touch read as one keypad; nine discs with
    /// room between them read as nine buttons. The gap is the seam, not the
    /// spacing.
    public var petalGap: Double {
        spacing - 2 * petalRadius
    }

    /// Where `.position` puts the rose: the padded frame's coordinates.
    public var viewCentre: (x: Double, y: Double) {
        (centre.x + inset, centre.y + inset)
    }

    /// Digit 1…9 on the phone keypad — 1 2 3 / 4 5 6 / 7 8 9, with 5 at the
    /// centre. Same mapping as `RoseGeometry.offset(forDigit:)`, which is what
    /// paints them.
    public func petalCentre(digit: Int) -> (x: Double, y: Double) {
        let index = digit - 1
        let dx = Double(index % 3 - 1), dy = Double(index / 3 - 1)
        return (centre.x + dx * spacing, centre.y + dy * spacing)
    }

    /// Petals sized for fingers: a hair wider than a board cell, until the
    /// board is big enough that a cell-sized petal would be a dinner plate.
    public static func scale(forSide side: Double) -> Double {
        min(0.62, ((side / 9) * 1.15) / 116)
    }
}
