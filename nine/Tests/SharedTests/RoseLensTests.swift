// RoseLens — the rose's geometry, pinned (PRD-22).
//
// Two consumers read this now: `FlickRoseView` paints the petals, and
// `BoardView`'s third layer effect bends the board's digits under them. They
// agree only because they read the same value, and this file is what makes
// "the same value" checkable without a simulator.
//
// The numbers below are not invented. They are the constants the six call sites
// had already been computing by hand since PRD-1, restated as arithmetic — so a
// failure here means the rose moved, not that this file is out of date.
import XCTest
@testable import NineShared

final class RoseLensTests: XCTestCase {

    /// The tvOS board: 900pt, 28pt inset, scale 1.0.
    func testPetalCentresAreTheKeypadGrid() {
        let lens = RoseLens(cursor: 40, side: 900, inset: 28,
                            pencil: false, showsErase: false, scale: 1.0)
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

    /// Pencil petals shrink, and pencil mode never shows the eraser — the rule
    /// TouchUI already enforced at its own call site.
    func testPencilModeShrinksAndDropsErase() {
        let lens = RoseLens(cursor: 40, side: 900, inset: 28,
                            pencil: true, showsErase: true, scale: 1.0)
        XCTAssertEqual(lens.spacing, 96, accuracy: 0.0001)
        XCTAssertEqual(lens.petalRadius, 44, accuracy: 0.0001)
        XCTAssertNil(lens.eraseDrop, "pencil mode never shows the erase petal")
    }

    func testErasePetalSitsBelowTheBottomRow() {
        let lens = RoseLens(cursor: 40, side: 900, inset: 28,
                            pencil: false, showsErase: true, scale: 1.0)
        XCTAssertEqual(lens.eraseDrop ?? 0, 126 + 126 * 0.92, accuracy: 0.0001)
    }

    /// The clamp keeps every petal on the glass plane. A corner cursor on a
    /// touch board must not push a petal off the frame — that is what
    /// `rosePosition` clamped for, and the lens has to clamp identically or the
    /// bend and the paint separate at exactly the cells where it shows most.
    func testCornerCursorIsPulledInside() {
        let side = 360.0, inset = 12.0
        let scale = RoseLens.scale(forSide: side)
        let lens = RoseLens(cursor: 0, side: side, inset: inset,
                            pencil: false, showsErase: false, scale: scale)
        let clampRadius = 184 * scale
        XCTAssertEqual(lens.viewCentre.x, clampRadius - 6, accuracy: 0.0001)
        XCTAssertEqual(lens.viewCentre.y, clampRadius - 6, accuracy: 0.0001)
        // …and that really is *inward*, not a no-op.
        XCTAssertGreaterThan(lens.viewCentre.x,
                             BoardGeometry.centre(of: 0, side: side).x + inset)
    }

    /// The erase petal hangs below the ring, so the bottom clamp has to make
    /// room for it or the eraser lands off the plane.
    func testEraseMakesRoomAtTheBottom() {
        let side = 360.0, inset = 12.0
        let scale = RoseLens.scale(forSide: side)
        let plain = RoseLens(cursor: 76, side: side, inset: inset,
                             pencil: false, showsErase: false, scale: scale)
        let erasing = RoseLens(cursor: 76, side: side, inset: inset,
                               pencil: false, showsErase: true, scale: scale)
        XCTAssertLessThan(erasing.viewCentre.y, plain.viewCentre.y)
    }

    /// A cursor in the middle of a touch board is not clamped at all — the
    /// clamp must not quietly recentre every rose.
    func testMiddleCursorIsUntouched() {
        let side = 360.0, inset = 12.0
        let lens = RoseLens(cursor: 40, side: side, inset: inset,
                            pencil: false, showsErase: false,
                            scale: RoseLens.scale(forSide: side))
        XCTAssertEqual(lens.centre.x, 180, accuracy: 0.0001)
        XCTAssertEqual(lens.centre.y, 180, accuracy: 0.0001)
    }

    /// Petals are a hair wider than a board cell, until the board is big enough
    /// that a cell-sized petal would be a dinner plate.
    func testScalePinsAtPointSixTwo() {
        XCTAssertEqual(RoseLens.scale(forSide: 360), (360.0 / 9 * 1.15) / 116,
                       accuracy: 1e-9)
        XCTAssertEqual(RoseLens.scale(forSide: 1200), 0.62, accuracy: 1e-9)
    }

    /// The unclamped path is what tvOS's two boards have always used; it stays
    /// available so adopting the lens there is a separate, visible decision.
    func testUnclampedKeepsTheRawCentre() {
        let lens = RoseLens(cursor: 0, side: 900, inset: 28,
                            pencil: false, showsErase: false, scale: 1.0,
                            clamped: false)
        XCTAssertEqual(lens.centre.x, 50, accuracy: 0.0001)
        XCTAssertEqual(lens.centre.y, 50, accuracy: 0.0001)
    }

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

    /// Every petal the lens claims to bend has to be inside the reach the
    /// shader is given (`maxSampleOffset`), or the compositor clips the rim
    /// band into a hard edge. This is the arithmetic that pairing depends on.
    func testRingSpanMatchesTheReachTheShaderIsGiven() {
        let lens = RoseLens(cursor: 40, side: 900, inset: 28,
                            pencil: false, showsErase: true, scale: 1.0)
        // Furthest thing the shader has to bend: the eraser's far edge.
        let furthest = (lens.eraseDrop ?? 0) + lens.petalRadius
        XCTAssertEqual(furthest, 126 + 126 * 0.92 + 58, accuracy: 0.0001)
        // The corner petals sit a diagonal away, and are nearer than that.
        let corner = (lens.spacing * lens.spacing * 2).squareRoot() + lens.petalRadius
        XCTAssertLessThan(corner, furthest)
    }
}
