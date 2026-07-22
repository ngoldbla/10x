// AfterglowScoreTimingTests — pins the Afterglow haptic score so the PRD-5
// refactor (pattern factory shared by iPhone + controller) cannot silently
// drift the crescendo iPhones have shipped since PRD-1. `AfterglowScore`'s
// CoreHaptics builders read these exact numbers, so asserting the numbers
// proves the pattern by construction — no hardware needed.
import XCTest
@testable import NineShared

final class AfterglowScoreTimingTests: XCTestCase {

    // MARK: - Solve crescendo (the load-bearing invariant)

    func testSolveHasNineTicksThenOneThump() {
        XCTAssertEqual(AfterglowScoreTiming.solveTicks.count, 9)
    }

    /// The exact 9-tick crescendo: times 0.25 → 2.15 in 0.2375 steps, intensity
    /// 0.30 → 0.95, sharpness 0.35 → 0.70. These are the shipped iPhone values.
    func testSolveCrescendoEventTimesAndIntensities() {
        let ticks = AfterglowScoreTiming.solveTicks
        for (i, tick) in ticks.enumerated() {
            let progress = Double(i) / 8.0
            XCTAssertEqual(tick.time, 0.25 + Double(i) * 0.2375, accuracy: 1e-9, "tick \(i) time")
            XCTAssertEqual(tick.intensity, 0.30 + 0.65 * progress, accuracy: 1e-9, "tick \(i) intensity")
            XCTAssertEqual(tick.sharpness, 0.35 + 0.35 * progress, accuracy: 1e-9, "tick \(i) sharpness")
        }
        // Endpoints, spelled out so a bad edit to the formula is unmistakable.
        XCTAssertEqual(ticks.first!.time, 0.25, accuracy: 1e-9)
        XCTAssertEqual(ticks.last!.time, 2.15, accuracy: 1e-9)
        XCTAssertEqual(ticks.first!.intensity, 0.30, accuracy: 1e-9)
        XCTAssertEqual(ticks.last!.intensity, 0.95, accuracy: 1e-9)
    }

    func testSolveThumpLandsAt2Point40() {
        let thump = AfterglowScoreTiming.solveThump
        XCTAssertEqual(thump.time, 2.40, accuracy: 1e-9)
        XCTAssertEqual(thump.duration, 0.35, accuracy: 1e-9)
        XCTAssertEqual(thump.intensity, 0.6, accuracy: 1e-9)
        XCTAssertEqual(thump.sharpness, 0.15, accuracy: 1e-9)
    }

    // MARK: - In-play ticks (PRD-5 §2.2)

    func testPlacementIsASingleWhisperTransient() {
        XCTAssertEqual(AfterglowScoreTiming.placementTick.time, 0, accuracy: 1e-9)
        XCTAssertLessThan(AfterglowScoreTiming.placementTick.intensity, 0.5, "a whisper, not a thump")
    }

    func testErrorKnockIsTwoCloseTaps() {
        let knock = AfterglowScoreTiming.errorKnock
        XCTAssertEqual(knock.count, 2)
        XCTAssertEqual(knock[0].time, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(knock[1].time, knock[0].time)
        XCTAssertLessThan(knock[1].time, 0.25, "the two taps read as one knock")
    }

    func testBoxDetentIsOneCrispTransient() {
        XCTAssertEqual(AfterglowScoreTiming.boxDetent.time, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(AfterglowScoreTiming.boxDetent.sharpness, 0.5, "crisp, not warm")
    }
}
