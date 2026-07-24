import XCTest
@testable import CouchKit
import CouchCore

/// Pins the edge policy of `PadButtonSampler` — the pure heart of the PRD-5
/// tvOS-controller fix (every button now rides the poll path). If any of these
/// break, a physical DualSense button silently stops working, which is exactly
/// the bug this whole track exists to kill.
final class PadButtonSamplerTests: XCTestCase {

    // MARK: Rising edges

    func testRestFrameEmitsNothing() {
        var s = PadButtonSampler()
        XCTAssertEqual(s.sample(PadButtonFrame()), [])
    }

    func testEveryButtonRisesExactlyOnceOnPress() {
        let cases: [(WritableKeyPath<PadButtonFrame, Bool>, PadButton)] = [
            (\.cross, .cross), (\.circle, .circle), (\.square, .square),
            (\.triangle, .triangle), (\.l1, .l1), (\.r1, .r1),
            (\.l2, .l2), (\.r2, .r2), (\.r3, .r3), (\.options, .options),
        ]
        for (key, button) in cases {
            var s = PadButtonSampler()
            var frame = PadButtonFrame()
            frame[keyPath: key] = true
            XCTAssertEqual(s.sample(frame), [.button(button)], "\(button) should rise once")
            // Held down the next tick: no repeat.
            XCTAssertEqual(s.sample(frame), [], "\(button) must not repeat while held")
        }
    }

    func testTwoButtonsInOneFrame() {
        var s = PadButtonSampler()
        let out = s.sample(PadButtonFrame(cross: true, square: true))
        XCTAssertTrue(out.contains(.button(.cross)))
        XCTAssertTrue(out.contains(.button(.square)))
        XCTAssertEqual(out.count, 2)
    }

    // MARK: Falling edges — only the held buttons emit .buttonUp

    func testCircleL2R2EmitButtonUpOnRelease() {
        for (frame, button): (PadButtonFrame, PadButton) in [
            (PadButtonFrame(circle: true), .circle),
            (PadButtonFrame(l2: true), .l2),
            (PadButtonFrame(r2: true), .r2),
        ] {
            var s = PadButtonSampler()
            XCTAssertEqual(s.sample(frame), [.button(button)])
            XCTAssertEqual(s.sample(PadButtonFrame()), [.buttonUp(button)], "\(button) hold must report release")
        }
    }

    func testTapButtonsDoNotEmitButtonUp() {
        // Cross/square/triangle/L1/R1/R3/options are taps: releasing them is
        // dead noise, so no .buttonUp should ever be produced.
        for key: WritableKeyPath<PadButtonFrame, Bool> in
            [\.cross, \.square, \.triangle, \.l1, \.r1, \.r3, \.options] {
            var s = PadButtonSampler()
            var frame = PadButtonFrame()
            frame[keyPath: key] = true
            _ = s.sample(frame)
            XCTAssertEqual(s.sample(PadButtonFrame()), [], "release should be silent")
        }
    }

    // MARK: reset()

    func testResetReArmsRisingEdge() {
        var s = PadButtonSampler()
        let frame = PadButtonFrame(cross: true)
        XCTAssertEqual(s.sample(frame), [.button(.cross)])
        XCTAssertEqual(s.sample(frame), []) // still held
        s.reset()
        // After a fresh adopt the same held state must read as a new press.
        XCTAssertEqual(s.sample(frame), [.button(.cross)])
    }

    // MARK: D-pad single-step transitions (0.5 deadzone)

    func testDpadSingleStepsOnTransitionOnly() {
        var s = PadButtonSampler()
        XCTAssertEqual(s.sample(PadButtonFrame(dpadX: 1)), [.move(.right, glide: false)])
        // Held: no repeat (that's the analog stick's job).
        XCTAssertEqual(s.sample(PadButtonFrame(dpadX: 1)), [])
        // Return to center, then a fresh direction.
        XCTAssertEqual(s.sample(PadButtonFrame()), [])
        XCTAssertEqual(s.sample(PadButtonFrame(dpadY: 1)), [.move(.up, glide: false)])
    }

    func testDpadDeadzoneRejectsShallowPush() {
        var s = PadButtonSampler()
        XCTAssertEqual(s.sample(PadButtonFrame(dpadX: 0.4)), []) // below 0.5
        XCTAssertEqual(s.sample(PadButtonFrame(dpadX: 0.6)), [.move(.right, glide: false)])
    }

    func testDpadDirectionChangeFiresImmediately() {
        var s = PadButtonSampler()
        XCTAssertEqual(s.sample(PadButtonFrame(dpadX: -1)), [.move(.left, glide: false)])
        // Diagonal push where y dominates → a new down/up step without resting.
        XCTAssertEqual(s.sample(PadButtonFrame(dpadY: -1)), [.move(.down, glide: false)])
    }

    func testDpadGlideIsAlwaysFalse() {
        var s = PadButtonSampler()
        let out = s.sample(PadButtonFrame(dpadX: 1))
        XCTAssertEqual(out, [.move(.right, glide: false)]) // never a glide step
    }
}
