// RoseLens — the rose's geometry, pinned (PRD-22).
//
// Two consumers read this now: `FlickRoseView` paints the petals, and
// `BoardView`'s third layer effect bends the board's digits under them. They
// agree only because they read the same value, and this file is what makes
// "the same value" checkable without a simulator.
//
// The petal numbers below are not invented. They are the constants the six call
// sites had already been computing by hand since PRD-1, restated as arithmetic —
// so a failure there means the rose's *size* moved, not that this file is out of
// date.
//
// ============================================================================
// ROUND 3 — what moved, and why these expectations moved with it.
// ============================================================================
//
// Round 2 declined to displace the ring off the cursor cell and said so in
// `RoseLens.swift`'s header, because this file pinned `centre == the cell
// centre` for an unclamped middle cursor and pinned the clamp's `184 * scale ± 6`
// twice more. Two blind panels then filed the same BLOCKER on both phone themes:
// the ring occludes the cell it writes into, and it clips off the board's top
// edge. Round 3 owns this file, so the change lands whole.
//
// **Three expectations changed, and each is a different kind of change:**
//
//   1. `testPetalCentresAreTheKeypadGrid` and `testMiddleCursorIsUntouched`
//      asserted "the ring blooms on the cursor cell". That is still exactly true
//      of the **unclamped** rose — tvOS's two boards — so the first test now
//      says so explicitly with `clamped: false` rather than relying on a default
//      that no longer means what it meant. The second is gone: an anchored
//      middle cursor is displaced *by design* now, and a test asserting it is
//      not would be asserting the bug.
//   2. `testCornerCursorIsPulledInside` and `testBottomRowCursorIsPulledUp`
//      pinned `184 * scale ± 6` — literally pinning six points of **overhang**,
//      which is the arithmetic behind "clips off its top edge". They are
//      replaced by `testNoPetalEverLeavesTheBoardFrame`, which is the property
//      those two were groping at, asserted over all 81 cells at every board size
//      and inset the app ships.
//   3. Everything about the plate is new: `testPlateIsConcentricWithItsPetals`,
//      `testTheRingClearsTheCellItWritesInto`, and the three placement pins.
//
// What did NOT change: `spacing`, `petalRadius`, the pitch, the diameter and
// `scale(forSide:)`. The shader still bends at exactly the radius the paint
// draws at, which was the whole reason this file exists.
import XCTest
@testable import NineShared

final class RoseLensTests: XCTestCase {

    /// Every (board side, inset) pair the app actually mounts a rose at.
    /// TouchUI passes 12 (`BoardCompositionRules.boardInset`), FirstRun 10,
    /// MacUI 6 on a desk and 16 otherwise, the touch tutorial 8 (`Space.s`),
    /// tvOS 28. Sides span the smallest first-run board to the couch's.
    private static let shippedInsets: [Double] = [6, 8, 10, 12, 16, 20, 28]
    private static let shippedSides: [Double] = [200, 260, 320, 360, 402, 480, 560, 720, 900]

    // MARK: - Geometry that did not move

    /// The tvOS board: 900pt, 28pt inset, scale 1.0 — and `clamped: false`,
    /// which is what those two screens actually pass. The couch ring still
    /// blooms *on* the cursor cell; only the anchored (touch/pointer) rose
    /// became a popover.
    func testPetalCentresAreTheKeypadGrid() {
        let lens = RoseLens(cursor: 40, side: 900, inset: 28,
                            pencil: false, scale: 1.0, clamped: false)
        XCTAssertEqual(lens.spacing, 126, accuracy: 0.0001)
        XCTAssertEqual(lens.petalRadius, 58, accuracy: 0.0001)
        // Cell 40 is row 5, column 5 — the board's centre.
        XCTAssertEqual(lens.centre.x, 450, accuracy: 0.0001)
        XCTAssertEqual(lens.centre.y, 450, accuracy: 0.0001)
        // Digit 5 is the centre petal; 1 is up-left; 9 is down-right.
        XCTAssertEqual(lens.petalCentre(digit: 5).x, 450, accuracy: 0.0001)
        XCTAssertEqual(lens.petalCentre(digit: 5).y, 450, accuracy: 0.0001)
        XCTAssertEqual(lens.petalCentre(digit: 1).x, 450 - 126, accuracy: 0.0001)
        XCTAssertEqual(lens.petalCentre(digit: 1).y, 450 - 126, accuracy: 0.0001)
        XCTAssertEqual(lens.petalCentre(digit: 3).x, 450 + 126, accuracy: 0.0001)
        XCTAssertEqual(lens.petalCentre(digit: 3).y, 450 - 126, accuracy: 0.0001)
        XCTAssertEqual(lens.petalCentre(digit: 9).x, 450 + 126, accuracy: 0.0001)
        XCTAssertEqual(lens.petalCentre(digit: 9).y, 450 + 126, accuracy: 0.0001)
    }

    /// Pencil petals shrink — the ring and petal geometry both step down
    /// together, same as `FlickRoseView`'s own `petalSize`/`spacing`.
    func testPencilModeShrinks() {
        let lens = RoseLens(cursor: 40, side: 900, inset: 28,
                            pencil: true, scale: 1.0)
        XCTAssertEqual(lens.spacing, 96, accuracy: 0.0001)
        XCTAssertEqual(lens.petalRadius, 44, accuracy: 0.0001)
    }

    /// Petals are a hair wider than a board cell, until the board is big enough
    /// that a cell-sized petal would be a dinner plate.
    func testScalePinsAtPointSixTwo() {
        XCTAssertEqual(RoseLens.scale(forSide: 360), (360.0 / 9 * 1.15) / 116,
                       accuracy: 1e-9)
        XCTAssertEqual(RoseLens.scale(forSide: 1200), 0.62, accuracy: 1e-9)
    }

    /// The unclamped path is what tvOS's two boards have always used; it stays
    /// available so adopting the anchored placement there is a separate,
    /// visible decision — and its rose still blooms exactly on the cell.
    func testUnclampedKeepsTheRawCentre() {
        let lens = RoseLens(cursor: 0, side: 900, inset: 28,
                            pencil: false, scale: 1.0,
                            clamped: false)
        XCTAssertEqual(lens.centre.x, 50, accuracy: 0.0001)
        XCTAssertEqual(lens.centre.y, 50, accuracy: 0.0001)
        // …and it points at itself, so a caller cannot mistake it for a
        // displaced ring.
        XCTAssertEqual(lens.anchorOffset.x, 0, accuracy: 0.0001)
        XCTAssertEqual(lens.anchorOffset.y, 0, accuracy: 0.0001)
        XCTAssertFalse(lens.clearsAnchor,
                       "The couch ring is centred on the cell by design — it "
                           + "must not claim a clearance it does not have.")
    }

    // MARK: - The plate

    /// A rounded square nested around nine circles only reads as *one shape*
    /// if its corners are concentric with the four corner petals. Two curves
    /// with the same radius, one inset inside the other, read as a mistake —
    /// which is the same rule `Radius.inner(_:inset:)` states in the App
    /// layer's tokens, restated here because `RoseLens` may not import them.
    func testPlateIsConcentricWithItsPetals() {
        for pencil in [false, true] {
            for scale in [0.22, 0.3966, 0.62, 1.0] {
                let radius = RoseLens.petalDiameter(pencil: pencil, scale: scale) / 2
                let pad = RoseLens.platePadding(pencil: pencil, scale: scale)
                XCTAssertEqual(
                    RoseLens.plateCornerRadius(pencil: pencil, scale: scale),
                    radius + pad, accuracy: 1e-9,
                    "plate corner must be a petal's radius plus the surround")
                // …and the plate really is the ring plus that surround on each
                // side, which is what `FlickRoseView` draws and what the
                // placement below reserves.
                XCTAssertEqual(
                    RoseLens.plateSpan(pencil: pencil, scale: scale),
                    2 * RoseLens.ringSpacing(pencil: pencil, scale: scale)
                        + RoseLens.petalDiameter(pencil: pencil, scale: scale)
                        + 2 * pad,
                    accuracy: 1e-9)
            }
        }
    }

    // MARK: - Placement: the two round-3 BLOCKERs

    /// **"…and clip off its top edge."**
    ///
    /// The shipped clamp read `min(max(v, radius - 6), frameSide - radius + 6)`
    /// — a *negative* six points, so any cursor in row 1 put the ring's top arc
    /// six points outside the padded frame. This is the property those two
    /// removed tests were reaching for, stated directly and over the whole
    /// board rather than at two corners: the plate's bounding square lies
    /// inside the frame, at every cell, every board size and every inset the
    /// app ships.
    func testNoPetalEverLeavesTheBoardFrame() {
        for side in Self.shippedSides {
            for inset in Self.shippedInsets {
                let scale = RoseLens.scale(forSide: side)
                let frameSide = side + 2 * inset
                for cursor in 0..<81 {
                    let lens = RoseLens(cursor: cursor, side: side, inset: inset,
                                        pencil: false, scale: scale)
                    let half = lens.plateSpan / 2
                    let where_ = "cell \(cursor), side \(side), inset \(inset)"
                    XCTAssertGreaterThanOrEqual(
                        lens.viewCentre.x - half, -1e-9, "plate ran off the left — \(where_)")
                    XCTAssertGreaterThanOrEqual(
                        lens.viewCentre.y - half, -1e-9, "plate ran off the top — \(where_)")
                    XCTAssertLessThanOrEqual(
                        lens.viewCentre.x + half, frameSide + 1e-9,
                        "plate ran off the right — \(where_)")
                    XCTAssertLessThanOrEqual(
                        lens.viewCentre.y + half, frameSide + 1e-9,
                        "plate ran off the bottom — \(where_)")
                }
            }
        }
    }

    /// **"…occlude the board", "never covers the selected cell".**
    ///
    /// The rose writes into the cursor cell, and until round 3 the centre petal
    /// sat on top of it. `clearsAnchor` is the guarantee; this walks all 81
    /// cells at every shipped board size and inset and asserts it, in both
    /// placement and pencil mode.
    ///
    /// Pencil mode is not a formality: the placement reserves room for the
    /// *placement-mode* plate (so the ring does not jump when the pencil toggle
    /// is hit), and the pencil plate is smaller, so it must clear by more.
    func testTheRingClearsTheCellItWritesInto() {
        for side in Self.shippedSides {
            for inset in Self.shippedInsets {
                let scale = RoseLens.scale(forSide: side)
                for pencil in [false, true] {
                    for cursor in 0..<81 {
                        let lens = RoseLens(cursor: cursor, side: side, inset: inset,
                                            pencil: pencil, scale: scale)
                        XCTAssertTrue(
                            lens.clearsAnchor,
                            "the plate covers the cell it writes into — cell "
                                + "\(cursor), side \(side), inset \(inset), "
                                + "pencil \(pencil)")
                    }
                }
            }
        }
    }

    /// Toggling pencil mode must not move the ring under the player's finger.
    /// The placement deliberately reserves the non-pencil span for both, the
    /// same way the old clamp used the non-pencil `184`.
    func testPencilDoesNotMoveTheRing() {
        for cursor in [0, 4, 40, 44, 76, 80] {
            let placement = RoseLens(cursor: cursor, side: 360, inset: 12,
                                     pencil: false,
                                     scale: RoseLens.scale(forSide: 360))
            let pencil = RoseLens(cursor: cursor, side: 360, inset: 12,
                                  pencil: true,
                                  scale: RoseLens.scale(forSide: 360))
            XCTAssertEqual(placement.centre.x, pencil.centre.x, accuracy: 1e-9)
            XCTAssertEqual(placement.centre.y, pencil.centre.y, accuracy: 1e-9)
        }
    }

    // MARK: - Placement: the exact numbers

    /// A phone board — 360pt of grid inside a 12pt plane, the geometry
    /// `Tests/AXBaselines/game-rose.txt` was recorded at.
    private var phone: (side: Double, inset: Double, scale: Double, half: Double) {
        let side = 360.0, inset = 12.0
        let scale = RoseLens.scale(forSide: side)
        return (side, inset, scale,
                RoseLens.plateSpan(pencil: false, scale: scale) / 2)
    }

    /// **Row 1, the cell the top-edge clipping was measured on.** The plate
    /// hangs below the cell with the full preferred gap, and its left edge
    /// stops exactly `plateMargin` inside the frame because the cursor is in
    /// column 1 and the plate is wider than the column is far from the edge.
    func testTopLeftCursorHangsTheRingBelowAndInside() {
        let (side, inset, scale, half) = phone
        let lens = RoseLens(cursor: 0, side: side, inset: inset,
                            pencil: false, scale: scale)
        // Cell 0's centre in the padded frame.
        let cellCentre = side / 18 + inset
        XCTAssertEqual(lens.viewCentre.y,
                       cellCentre + side / 18 + half + RoseLens.anchorGap,
                       accuracy: 1e-9)
        XCTAssertEqual(lens.viewCentre.x, half + RoseLens.plateMargin, accuracy: 1e-9)
        // The finding, restated as the number that caused it: the old clamp put
        // this edge at `-6`.
        XCTAssertEqual(lens.viewCentre.y - half,
                       cellCentre + side / 18 + RoseLens.anchorGap, accuracy: 1e-9)
        XCTAssertGreaterThan(lens.viewCentre.y - half, RoseLens.plateMargin)
    }

    /// **The bottom-right cursor flips the plate above the cell**, and pushes
    /// it as far right as the margin allows.
    func testBottomRightCursorFlipsTheRingAbove() {
        let (side, inset, scale, half) = phone
        let frameSide = side + 2 * inset
        let lens = RoseLens(cursor: 80, side: side, inset: inset,
                            pencil: false, scale: scale)
        let cellCentre = frameSide - inset - side / 18
        XCTAssertEqual(lens.viewCentre.y,
                       cellCentre - side / 18 - half - RoseLens.anchorGap,
                       accuracy: 1e-9)
        XCTAssertEqual(lens.viewCentre.x, frameSide - half - RoseLens.plateMargin,
                       accuracy: 1e-9)
        // Upward, not a no-op: the raw centre is lower.
        XCTAssertLessThan(lens.viewCentre.y,
                          BoardGeometry.centre(of: 80, side: side).y + inset)
    }

    /// **The dead-centre cell is the tight one**, and it is why the placement
    /// spends the *gap* before it spends the clearance.
    ///
    /// A phone plate is 160.7pt on a 384pt frame, so a cursor in the middle row
    /// has 108.3pt of clearance to buy and only 105.7pt below it. The plate
    /// therefore goes as low as `plateMargin` allows — 5.3pt of gap instead of
    /// 8 — and still clears the cell, which is the half that matters.
    func testMiddleCursorGivesUpTheGapButNotTheClearance() {
        let (side, inset, scale, half) = phone
        let frameSide = side + 2 * inset
        let lens = RoseLens(cursor: 40, side: side, inset: inset,
                            pencil: false, scale: scale)
        XCTAssertEqual(lens.viewCentre.x, frameSide / 2, accuracy: 1e-9,
                       "the middle column is not clamped on either side")
        XCTAssertEqual(lens.viewCentre.y, frameSide - half - RoseLens.plateMargin,
                       accuracy: 1e-9)
        XCTAssertTrue(lens.clearsAnchor)
        // Displaced downward, and by less than it wanted to be.
        let wanted = frameSide / 2 + side / 18 + half + RoseLens.anchorGap
        XCTAssertLessThan(lens.viewCentre.y, wanted)
        XCTAssertGreaterThan(lens.viewCentre.y, frameSide / 2)
    }

    /// `anchorOffset` is the popover's tail: the vector from the ring back to
    /// the cell it is filling. Anything that wants to span the two — a gesture
    /// surface, a connector — reads it rather than recomputing the placement.
    func testAnchorOffsetPointsBackAtTheCursorCell() {
        let (side, inset, scale, _) = phone
        let lens = RoseLens(cursor: 0, side: side, inset: inset,
                            pencil: false, scale: scale)
        let raw = BoardGeometry.centre(of: 0, side: side)
        XCTAssertEqual(lens.anchor.x, raw.x, accuracy: 1e-9)
        XCTAssertEqual(lens.anchor.y, raw.y, accuracy: 1e-9)
        XCTAssertEqual(lens.anchorOffset.x, raw.x - lens.centre.x, accuracy: 1e-9)
        XCTAssertEqual(lens.anchorOffset.y, raw.y - lens.centre.y, accuracy: 1e-9)
        // Cell 0 is above-left of the ring, so the tail points up and left.
        XCTAssertLessThan(lens.anchorOffset.y, 0)
        XCTAssertLessThan(lens.anchorOffset.x, 0)
    }

    // MARK: - The copy of `BoardMetrics`

    /// `BoardGeometry.centre` is a Linux-clean copy of `BoardMetrics.center`.
    /// Nothing links the two — `Package.swift` covers Engine and Shared only,
    /// because Lane 1 is Linux — so this reads the App source and fails if the
    /// formula this file is a copy of has moved. Same pattern as
    /// `AppearancePaletteTests`' source-literal checks.
    func testBoardMetricsStillComputesTheSameCentre() throws {
        let nine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SharedTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // nine
        let source = try String(
            contentsOf: nine.appendingPathComponent("Sources/App/BoardView.swift"),
            encoding: .utf8)
        XCTAssertTrue(
            source.contains("return CGPoint(x: (col + 0.5) * unit, y: (row + 0.5) * unit)"),
            "BoardMetrics.center no longer reads as (col + 0.5) * unit — "
                + "BoardGeometry.centre is a copy of it and has to move too.")
    }
}
