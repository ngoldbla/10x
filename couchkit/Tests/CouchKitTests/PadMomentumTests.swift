import XCTest
@testable import CouchKit
import CouchCore

/// Pins the left-stick momentum curve: a feathered push steps once, a full push
/// glides, the deadzone swallows noise, and a direction change fires instantly.
final class PadMomentumTests: XCTestCase {

    // MARK: direction() 8→4 collapse

    func testDirectionCardinals() {
        let dz = 0.2
        XCTAssertEqual(PadMomentum.direction(x: 1, y: 0, deadzone: dz), .right)
        XCTAssertEqual(PadMomentum.direction(x: -1, y: 0, deadzone: dz), .left)
        XCTAssertEqual(PadMomentum.direction(x: 0, y: 1, deadzone: dz), .up)
        XCTAssertEqual(PadMomentum.direction(x: 0, y: -1, deadzone: dz), .down)
    }

    func testDirectionDeadzone() {
        XCTAssertNil(PadMomentum.direction(x: 0.1, y: 0.05, deadzone: 0.2))
    }

    func testDirectionDiagonalPrefersDominantAxis() {
        // x slightly dominates → horizontal.
        XCTAssertEqual(PadMomentum.direction(x: 0.8, y: 0.7, deadzone: 0.2), .right)
        // y dominates → vertical.
        XCTAssertEqual(PadMomentum.direction(x: 0.6, y: 0.9, deadzone: 0.2), .up)
    }

    // MARK: accumulate()

    func testBelowDeadzoneEmitsNothing() {
        var m = PadMomentum()
        XCTAssertEqual(m.accumulate(x: 0.1, y: 0, dt: 0.016), [])
    }

    func testFeatheredPushStepsOnceThenRests() {
        var m = PadMomentum(deadzone: 0.2, maxRate: 11, curve: 2.2)
        // A gentle push just past the deadzone: the direction-change arms one
        // immediate step, and the low rate doesn't accumulate a second within a
        // frame.
        let first = m.accumulate(x: 0.28, y: 0, dt: 0.016)
        XCTAssertEqual(first, [.right])
        // Holding that same gentle deflection: many frames pass before another
        // whole cell accrues, so the very next frame is empty.
        XCTAssertEqual(m.accumulate(x: 0.28, y: 0, dt: 0.016), [])
    }

    func testFullPushGlidesMultipleCellsPerSecond() {
        var m = PadMomentum(deadzone: 0.2, maxRate: 11, curve: 2.2)
        var total = 0
        // One second of full-right deflection at 60 Hz.
        for _ in 0..<60 { total += m.accumulate(x: 1, y: 0, dt: 1.0 / 60).count }
        // At maxRate 11 the glide should clear roughly a full board width.
        XCTAssertGreaterThanOrEqual(total, 9)
        XCTAssertLessThanOrEqual(total, 13)
    }

    func testDirectionChangeFiresImmediately() {
        var m = PadMomentum()
        _ = m.accumulate(x: 1, y: 0, dt: 0.016) // moving right
        let flip = m.accumulate(x: 0, y: 1, dt: 0.016) // snap to up
        XCTAssertEqual(flip.first, .up, "a deliberate flip of the stick steps at once")
    }

    func testReturnToRestClearsAccumulator() {
        var m = PadMomentum()
        for _ in 0..<10 { _ = m.accumulate(x: 1, y: 0, dt: 1.0 / 60) }
        XCTAssertEqual(m.accumulate(x: 0, y: 0, dt: 1.0 / 60), []) // rest resets
        // A fresh push re-arms a crisp first step.
        XCTAssertEqual(m.accumulate(x: 0.9, y: 0, dt: 1.0 / 60).first, .right)
    }
}
