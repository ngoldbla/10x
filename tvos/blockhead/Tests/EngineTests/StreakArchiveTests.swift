// Streak logic (streak-honest lateness) and the archive model.
import XCTest
@testable import BlockheadEngine

final class StreakArchiveTests: XCTestCase {

    // MARK: Streak

    func testConsecutiveOnTimeNightsExtendTheStreak() {
        var streak = StreakState()
        streak.recordCompletion(day: 10, playedDay: 10)
        XCTAssertEqual(streak.length, 1)
        streak.recordCompletion(day: 11, playedDay: 11)
        streak.recordCompletion(day: 12, playedDay: 12)
        XCTAssertEqual(streak.length, 3)
        XCTAssertEqual(streak.current(asOf: 12), 3)
    }

    func testReplayingTonightDoesNotDoubleCount() {
        var streak = StreakState()
        streak.recordCompletion(day: 10, playedDay: 10)
        streak.recordCompletion(day: 10, playedDay: 10)
        XCTAssertEqual(streak.length, 1)
    }

    func testMissedNightRestartsTheStreak() {
        var streak = StreakState()
        streak.recordCompletion(day: 10, playedDay: 10)
        streak.recordCompletion(day: 11, playedDay: 11)
        streak.recordCompletion(day: 13, playedDay: 13) // skipped day 12
        XCTAssertEqual(streak.length, 1)
    }

    func testLateArchivePlayNeverExtendsStreak() {
        var streak = StreakState()
        streak.recordCompletion(day: 10, playedDay: 10)
        streak.recordCompletion(day: 11, playedDay: 14) // caught up late
        XCTAssertEqual(streak.length, 1)
        XCTAssertEqual(streak.lastOnTimeDay, 10)
    }

    func testCurrentStreakDecaysWhenNightsPass() {
        var streak = StreakState()
        streak.recordCompletion(day: 10, playedDay: 10)
        XCTAssertEqual(streak.current(asOf: 10), 1)
        XCTAssertEqual(streak.current(asOf: 11), 1, "tonight is still playable")
        XCTAssertEqual(streak.current(asOf: 12), 0, "flame is out after a missed night")
    }

    func testCompletedTonight() {
        var streak = StreakState()
        XCTAssertFalse(streak.completedTonight(10))
        streak.recordCompletion(day: 10, playedDay: 10)
        XCTAssertTrue(streak.completedTonight(10))
        XCTAssertFalse(streak.completedTonight(11))
    }

    // MARK: Archive

    private func result(day: Int, playedDay: Int) -> EpisodeResult {
        EpisodeResult(episodeNumber: day + 1, dayNumber: day, playedDay: playedDay,
                      correctCount: 7, dots: 4)
    }

    func testArchiveListsPastDaysNewestFirst() {
        let entries = Archive.entries(today: 5, limit: 10, results: [:])
        XCTAssertEqual(entries.map(\.dayNumber), [4, 3, 2, 1, 0])
        XCTAssertEqual(entries.first?.episodeNumber, 5)
        XCTAssertTrue(entries.allSatisfy { !$0.isCompleted })
    }

    func testArchiveRespectsLimitAndMarksCompletion() {
        let results = [
            98: result(day: 98, playedDay: 98),   // on time
            97: result(day: 97, playedDay: 99),   // late catch-up
        ]
        let entries = Archive.entries(today: 100, limit: 4, results: results)
        XCTAssertEqual(entries.map(\.dayNumber), [99, 98, 97, 96])

        XCTAssertFalse(entries[0].isCompleted)
        XCTAssertTrue(entries[1].isCompleted)
        XCTAssertFalse(entries[1].isLate)
        XCTAssertTrue(entries[2].isCompleted)
        XCTAssertTrue(entries[2].isLate, "catch-up plays are marked late")
    }

    func testArchiveEmptyOnLaunchNight() {
        XCTAssertTrue(Archive.entries(today: 0, limit: 10, results: [:]).isEmpty)
    }

    func testResultScoreAndLateness() {
        let onTime = result(day: 20, playedDay: 20)
        XCTAssertEqual(onTime.score, 11)
        XCTAssertFalse(onTime.isLate)
        let late = result(day: 20, playedDay: 22)
        XCTAssertTrue(late.isLate)
    }
}
