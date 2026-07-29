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
                            pencil: false, scale: 1.0)
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

    /// The clamp keeps every petal on the glass plane. A corner cursor on a
    /// touch board must not push a petal off the frame — that is what
    /// `rosePosition` clamped for, and the lens has to clamp identically or the
    /// bend and the paint separate at exactly the cells where it shows most.
    func testCornerCursorIsPulledInside() {
        let side = 360.0, inset = 12.0
        let scale = RoseLens.scale(forSide: side)
        let lens = RoseLens(cursor: 0, side: side, inset: inset,
                            pencil: false, scale: scale)
        let clampRadius = 184 * scale
        XCTAssertEqual(lens.viewCentre.x, clampRadius - 6, accuracy: 0.0001)
        XCTAssertEqual(lens.viewCentre.y, clampRadius - 6, accuracy: 0.0001)
        // …and that really is *inward*, not a no-op.
        XCTAssertGreaterThan(lens.viewCentre.x,
                             BoardGeometry.centre(of: 0, side: side).x + inset)
    }

    /// A cursor in the middle of a touch board is not clamped at all — the
    /// clamp must not quietly recentre every rose.
    func testMiddleCursorIsUntouched() {
        let side = 360.0, inset = 12.0
        let lens = RoseLens(cursor: 40, side: side, inset: inset,
                            pencil: false,
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
                            pencil: false, scale: 1.0,
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
}
