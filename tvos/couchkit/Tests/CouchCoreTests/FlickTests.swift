import XCTest
@testable import CouchCore

final class FlickTests: XCTestCase {

    // Convenience: unit vector at `deg` degrees (0 = right, CCW, +y up).
    private func vector(_ deg: Double, length: Double = 1) -> (dx: Double, dy: Double) {
        let rad = deg * .pi / 180
        return (cos(rad) * length, sin(rad) * length)
    }

    // MARK: 4-way geometry

    func testCardinalCenters() {
        for (deg, expected) in [(0.0, Direction4.right), (90, .up), (180, .left), (270, .down), (359, .right)] {
            let v = vector(deg)
            XCTAssertEqual(
                FlickClassifier.direction4(dx: v.dx, dy: v.dy), .direction(expected),
                "\(deg)° should be \(expected)"
            )
        }
    }

    func testDiagonalBoundaryIsAmbiguousWithinCone() {
        // 45° is dead on the up/right boundary; ±8° around it is the cone.
        for deg in [45.0, 38, 52, 135, 224, 313] {
            let v = vector(deg)
            XCTAssertEqual(
                FlickClassifier.direction4(dx: v.dx, dy: v.dy), .ambiguous,
                "\(deg)° should fall in the forgiveness cone"
            )
        }
        // Just outside the cone classifies confidently.
        let low = vector(36.9)
        XCTAssertEqual(FlickClassifier.direction4(dx: low.dx, dy: low.dy), .direction(.right))
        let high = vector(53.1)
        XCTAssertEqual(FlickClassifier.direction4(dx: high.dx, dy: high.dy), .direction(.up))
    }

    // MARK: 8-way geometry

    func testEightWaySectors() {
        let cases: [(Double, Direction8OrCenter)] = [
            (0, .right), (45, .upRight), (90, .up), (135, .upLeft),
            (180, .left), (225, .downLeft), (270, .down), (315, .downRight),
        ]
        for (deg, expected) in cases {
            let v = vector(deg)
            XCTAssertEqual(FlickClassifier.direction8(dx: v.dx, dy: v.dy), .direction(expected))
        }
    }

    func testEightWayBoundariesAmbiguous() {
        for deg in [22.5, 67.5, 112.5, 157.5, 202.5, 247.5, 292.5, 337.5, 30.0, 16.0] {
            let v = vector(deg)
            XCTAssertEqual(
                FlickClassifier.direction8(dx: v.dx, dy: v.dy), .ambiguous,
                "\(deg)° should be ambiguous"
            )
        }
        // 8.1° past the boundary is confident again.
        let v = vector(30.7)
        XCTAssertEqual(FlickClassifier.direction8(dx: v.dx, dy: v.dy), .direction(.upRight))
    }

    // MARK: Rest-touch rejection and taps

    func testRestTouchRejection() {
        // Tiny movement over a long touch: resting thumb.
        XCTAssertEqual(FlickClassifier.classify4(dx: 0.05, dy: 0.02, duration: 2.0), .rest)
        XCTAssertEqual(FlickClassifier.classify8(dx: 0.05, dy: 0.02, duration: 2.0), .rest)
        // Big but slow drag: repositioning, not a flick.
        XCTAssertEqual(FlickClassifier.classify4(dx: 0.9, dy: 0, duration: 3.0), .rest)
        XCTAssertEqual(FlickClassifier.classify8(dx: 0.9, dy: 0, duration: 3.0), .rest)
    }

    func testQuickTapIsCenterOnTheRose() {
        XCTAssertEqual(
            FlickClassifier.classify8(dx: 0.03, dy: 0.01, duration: 0.12),
            .direction(.center)
        )
        // The same touch is not a swipe in the 4-way grammar.
        XCTAssertEqual(FlickClassifier.classify4(dx: 0.03, dy: 0.01, duration: 0.12), .rest)
    }

    func testConfidentFlickPasses() {
        XCTAssertEqual(
            FlickClassifier.classify8(dx: 0.6, dy: 0.6, duration: 0.2),
            .direction(.upRight)
        )
        XCTAssertEqual(
            FlickClassifier.classify4(dx: -0.8, dy: 0.05, duration: 0.25),
            .direction(.left)
        )
    }

    // MARK: Hysteresis

    func testHysteresisHoldsSectorAcrossBoundaryJitter() {
        var h = SectorHysteresis(sectorCount: 8, marginDegrees: 6)
        XCTAssertEqual(h.classify(angleDegrees: 10), 0) // right
        // Jitter just across the 22.5° boundary: held.
        XCTAssertEqual(h.classify(angleDegrees: 24), 0)
        XCTAssertEqual(h.classify(angleDegrees: 27), 0)
        // Clearly into the next sector: switches.
        XCTAssertEqual(h.classify(angleDegrees: 40), 1)
        // And is now sticky around the same boundary from the other side.
        XCTAssertEqual(h.classify(angleDegrees: 21), 1)
        h.reset()
        XCTAssertEqual(h.classify(angleDegrees: 21), 0)
    }

    func testHysteresisWrapsAroundZero() {
        var h = SectorHysteresis(sectorCount: 4, marginDegrees: 6)
        XCTAssertEqual(h.classify(angleDegrees: 350), 0) // right, via wraparound
        XCTAssertEqual(h.classify(angleDegrees: 20), 0)
    }

    // MARK: Drag-fill accumulation

    func testCellStepAccumulator() {
        var acc = CellStepAccumulator(cellSize: 0.25)
        var steps = acc.accumulate(dx: 0.2, dy: 0)
        XCTAssertEqual(steps.x, 0)
        steps = acc.accumulate(dx: 0.1, dy: 0) // total 0.3 → one step, 0.05 left
        XCTAssertEqual(steps.x, 1)
        steps = acc.accumulate(dx: 0.45, dy: -0.6) // 0.5 → 2 steps; -0.6 → -2 steps
        XCTAssertEqual(steps.x, 2)
        XCTAssertEqual(steps.y, -2)
        acc.reset()
        XCTAssertEqual(acc.accumulate(dx: 0.24, dy: 0).x, 0)
    }
}
