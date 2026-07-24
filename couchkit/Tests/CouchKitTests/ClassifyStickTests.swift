import XCTest
@testable import CouchKit
import CouchCore

/// Pins the right-stick rose classifier: eight clean petals, and the never-
/// misfire ambiguity cone reporting BOTH candidates on a boundary angle.
/// (+x right, +y up — GameController's stick convention.)
final class ClassifyStickTests: XCTestCase {

    private func petal(_ dx: Double, _ dy: Double) -> Direction8OrCenter? {
        if case .direction(let d) = PadMomentum.classifyStick(dx: dx, dy: dy) { return d }
        return nil
    }

    func testEightCleanSectors() {
        XCTAssertEqual(petal(1, 0), .right)     // 0°
        XCTAssertEqual(petal(1, 1), .upRight)   // 45°
        XCTAssertEqual(petal(0, 1), .up)        // 90°
        XCTAssertEqual(petal(-1, 1), .upLeft)   // 135°
        XCTAssertEqual(petal(-1, 0), .left)     // 180°
        XCTAssertEqual(petal(-1, -1), .downLeft)// 225°
        XCTAssertEqual(petal(0, -1), .down)     // 270°
        XCTAssertEqual(petal(1, -1), .downRight)// 315°
    }

    func testBoundaryAngleIsAmbiguousWithBothCandidates() {
        // 22.5° sits exactly between right (0°) and upRight (45°).
        let angle = 22.5 * Double.pi / 180
        let result = PadMomentum.classifyStick(dx: cos(angle), dy: sin(angle))
        guard case .ambiguous(let a, let b) = result else {
            return XCTFail("boundary angle must be ambiguous, got \(result)")
        }
        XCTAssertEqual(Set([a, b]), Set([.right, .upRight]))
    }

    func testAmbiguityConeIsNarrow() {
        // Just inside a sector (well clear of the 8° cone) still places cleanly.
        let angle = 40 * Double.pi / 180 // near upRight's 45° center
        XCTAssertEqual(petal(cos(angle), sin(angle)), .upRight)
    }

    func testTighterConeShrinksAmbiguity() {
        // With a 2° cone, an angle 5° off the boundary is a clean petal.
        let angle = 27.5 * Double.pi / 180
        if case .ambiguous = PadMomentum.classifyStick(dx: cos(angle), dy: sin(angle), cone: 2) {
            XCTFail("5° off the boundary should be clean under a 2° cone")
        }
    }
}
