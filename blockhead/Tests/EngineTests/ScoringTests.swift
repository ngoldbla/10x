// Scoring (speed-bonus dots from an injectable clock) and the EpisodeRun
// state machine.
import XCTest
import CouchCore
@testable import BlockheadEngine

final class ScoringTests: XCTestCase {

    // MARK: Speed dots

    func testSpeedDotsThresholds() {
        XCTAssertEqual(Scoring.speedDots(elapsed: 0, limit: 12), 2)
        XCTAssertEqual(Scoring.speedDots(elapsed: 3.0, limit: 12), 2)   // exactly 25%
        XCTAssertEqual(Scoring.speedDots(elapsed: 3.01, limit: 12), 1)
        XCTAssertEqual(Scoring.speedDots(elapsed: 7.19, limit: 12), 1)  // just inside 60%
        XCTAssertEqual(Scoring.speedDots(elapsed: 7.21, limit: 12), 0)
        XCTAssertEqual(Scoring.speedDots(elapsed: 12, limit: 12), 0)
    }

    func testSpeedDotsRejectsNonsense() {
        XCTAssertEqual(Scoring.speedDots(elapsed: -1, limit: 12), 0)
        XCTAssertEqual(Scoring.speedDots(elapsed: 13, limit: 12), 0)
        XCTAssertEqual(Scoring.speedDots(elapsed: 1, limit: 0), 0)
    }

    func testSpeedDotsScaleWithTimerPreference() {
        // The 8s and 20s prefs shift the dot windows proportionally.
        XCTAssertEqual(Scoring.speedDots(elapsed: 2, limit: 8), 2)
        XCTAssertEqual(Scoring.speedDots(elapsed: 4, limit: 8), 1)
        XCTAssertEqual(Scoring.speedDots(elapsed: 5, limit: 20), 2)
        XCTAssertEqual(Scoring.speedDots(elapsed: 11, limit: 20), 1)
    }

    // MARK: EpisodeRun

    private func makeRun(day: Int = 100, limit: TimeInterval = 12) -> EpisodeRun {
        EpisodeRun(episode: EpisodePlanner.episode(forDay: day), timeLimit: limit)
    }

    func testRunPlaysAllTenQuestionsAndScores() {
        var run = makeRun()
        var clock: TimeInterval = 1_000
        run.begin(at: clock)

        for index in 0..<10 {
            XCTAssertEqual(run.currentIndex, index)
            let question = run.currentQuestion!
            // Fast correct answers on even questions, wrong on odd.
            let direction: Direction4 = index.isMultiple(of: 2)
                ? question.correctDirection
                : Question.direction(forAnswerIndex: (question.correctIndex + 1) % 4)
            clock += 2 // 2s into a 12s timer ⇒ 2 dots when correct
            let outcome = run.answer(direction, at: clock)
            XCTAssertNotNil(outcome)
            XCTAssertEqual(outcome!.correct, index.isMultiple(of: 2))
            XCTAssertEqual(outcome!.dots, index.isMultiple(of: 2) ? 2 : 0)
            run.advance(at: clock)
        }

        XCTAssertEqual(run.phase, .finished)
        XCTAssertEqual(run.correctCount, 5)
        XCTAssertEqual(run.dots, 10)
        XCTAssertEqual(run.score, 15)

        let result = run.result(playedDay: 100)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.score, 15)
        XCTAssertFalse(result!.isLate)
    }

    func testWrongAnswerEarnsNoDotsEvenWhenFast() {
        var run = makeRun()
        run.begin(at: 0)
        let question = run.currentQuestion!
        let wrong = Question.direction(forAnswerIndex: (question.correctIndex + 2) % 4)
        let outcome = run.answer(wrong, at: 0.5)!
        XCTAssertFalse(outcome.correct)
        XCTAssertEqual(outcome.dots, 0)
    }

    func testSlowCorrectAnswerEarnsPointButNoDots() {
        var run = makeRun()
        run.begin(at: 0)
        let outcome = run.answer(run.currentQuestion!.correctDirection, at: 11)!
        XCTAssertTrue(outcome.correct)
        XCTAssertEqual(outcome.dots, 0)
        XCTAssertEqual(run.score, 1)
    }

    func testTimeoutCountsAsWrongWithNilPick() {
        var run = makeRun()
        run.begin(at: 0)
        let outcome = run.timeOut(at: 12)!
        XCTAssertNil(outcome.pickedIndex)
        XCTAssertFalse(outcome.correct)
        XCTAssertEqual(run.phase, .verdict(0))
        // Cannot answer during a verdict.
        XCTAssertNil(run.answer(.up, at: 12.1))
    }

    func testShiftClockExcludesPausedTime() {
        var run = makeRun()
        run.begin(at: 0)
        // Player pauses for 100s, then answers 2s of real question time later.
        run.shiftClock(by: 100)
        let outcome = run.answer(run.currentQuestion!.correctDirection, at: 102)!
        XCTAssertEqual(outcome.elapsed, 2, accuracy: 0.001)
        XCTAssertEqual(outcome.dots, 2)
    }

    func testRemainingClampsToZero() {
        var run = makeRun(limit: 12)
        run.begin(at: 0)
        XCTAssertEqual(run.remaining(at: 4), 8, accuracy: 0.001)
        XCTAssertEqual(run.remaining(at: 50), 0)
    }

    func testResultUnavailableBeforeFinish() {
        var run = makeRun()
        run.begin(at: 0)
        XCTAssertNil(run.result(playedDay: 100))
    }

    func testLateArchivePlayIsMarkedLate() {
        var run = EpisodeRun(episode: EpisodePlanner.episode(forDay: 90), timeLimit: 12)
        var clock: TimeInterval = 0
        run.begin(at: clock)
        for _ in 0..<10 {
            clock += 1
            run.answer(.up, at: clock)
            run.advance(at: clock)
        }
        let result = run.result(playedDay: 95)!
        XCTAssertTrue(result.isLate)
        XCTAssertEqual(result.dayNumber, 90)
        XCTAssertEqual(result.playedDay, 95)
    }
}
