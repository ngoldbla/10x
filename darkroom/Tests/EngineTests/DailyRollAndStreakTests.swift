import XCTest
import CouchCore
@testable import DarkroomEngine

final class DailyRollAndStreakTests: XCTestCase {

    private var gregorianUTC: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
        return gregorianUTC.date(from: comps)!
    }

    // MARK: - Daily roll

    func testDateSeedIsCalendarDayStable() {
        let cal = gregorianUTC
        XCTAssertEqual(DailyRoll.dateSeed(for: date(2026, 7, 10), calendar: cal), 20_260_710)
        // Any time within the same day maps to the same seed.
        let evening = date(2026, 7, 10).addingTimeInterval(9 * 3600)
        XCTAssertEqual(DailyRoll.dateSeed(for: evening, calendar: cal), 20_260_710)
        XCTAssertNotEqual(
            DailyRoll.dateSeed(for: date(2026, 7, 11), calendar: cal), 20_260_710
        )
    }

    func testPhotoOrderIsDeterministicPermutationAndSlotDistinct() {
        let a = DailyRoll.photoOrder(count: 12, slot: .small, dateSeed: 20_260_710)
        let b = DailyRoll.photoOrder(count: 12, slot: .small, dateSeed: 20_260_710)
        XCTAssertEqual(a, b, "same day + slot ⇒ same order")
        XCTAssertEqual(a.sorted(), Array(0..<12), "order must be a permutation")
        let c = DailyRoll.photoOrder(count: 12, slot: .large, dateSeed: 20_260_710)
        XCTAssertNotEqual(a, c, "slots roll independently")
        XCTAssertEqual(DailyRoll.photoOrder(count: 0, slot: .small, dateSeed: 1), [])
    }

    func testSelectTargetsTheRequestedBand() {
        func stub(_ difficulty: Int, _ id: String) -> Puzzle {
            Puzzle(
                photoID: id, size: 10, dateSeed: 1,
                solution: LineSolverTests.heart + [Bool](repeating: false, count: 75),
                colors: [RGB](repeating: .black, count: 100),
                difficulty: difficulty
            )
        }
        // size 10: easy ≤ 2 passes, medium ≤ 4, hard ≥ 5.
        let easy = stub(1, "a"), medium = stub(3, "b"), hard = stub(7, "c")
        XCTAssertEqual(DailyRoll.select(from: [easy, medium, hard], target: .hard)?.photoID, "c")
        XCTAssertEqual(DailyRoll.select(from: [easy, medium, hard], target: .easy)?.photoID, "a")
        XCTAssertEqual(DailyRoll.select(from: [easy, hard], target: .medium)?.photoID, "a",
                       "band distance ties break toward the earlier roll")
        XCTAssertNil(DailyRoll.select(from: [], target: .easy))
    }

    func testDifficultyBandScalesWithBoardSize() {
        XCTAssertEqual(DifficultyBand.band(passes: 2, size: 10), .easy)
        XCTAssertEqual(DifficultyBand.band(passes: 3, size: 10), .medium)
        XCTAssertEqual(DifficultyBand.band(passes: 5, size: 10), .hard)
        XCTAssertEqual(DifficultyBand.band(passes: 3, size: 15), .easy)
        XCTAssertEqual(DifficultyBand.band(passes: 4, size: 20), .easy)
        XCTAssertEqual(DifficultyBand.band(passes: 9, size: 20), .hard)
    }

    // MARK: - Streaks (calendar-day based, PRD §4.1)

    func testStreakGrowsOnConsecutiveDays() {
        let cal = gregorianUTC
        let d1 = Streaks.dayNumber(for: date(2026, 7, 10), calendar: cal)
        let d2 = Streaks.dayNumber(for: date(2026, 7, 11), calendar: cal)
        XCTAssertEqual(d2, d1 + 1, "consecutive dates differ by exactly one day number")

        var s = StreakState()
        s = Streaks.recordingDevelop(s, day: d1)
        XCTAssertEqual(s.count, 1)
        s = Streaks.recordingDevelop(s, day: d2)
        XCTAssertEqual(s.count, 2)
    }

    func testStreakCrossesMonthBoundary() {
        let cal = gregorianUTC
        let july31 = Streaks.dayNumber(for: date(2026, 7, 31), calendar: cal)
        let aug1 = Streaks.dayNumber(for: date(2026, 8, 1), calendar: cal)
        XCTAssertEqual(aug1, july31 + 1)
    }

    func testSameDayDevelopsAreIdempotent() {
        var s = StreakState(count: 4, lastDay: 100)
        s = Streaks.recordingDevelop(s, day: 100)
        XCTAssertEqual(s, StreakState(count: 4, lastDay: 100))
    }

    func testMissedDayResetsToOne() {
        var s = StreakState(count: 9, lastDay: 100)
        s = Streaks.recordingDevelop(s, day: 103)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.lastDay, 103)
    }

    func testEffectiveStreakLapsesAfterAFullMissedDay() {
        let s = StreakState(count: 5, lastDay: 100)
        XCTAssertEqual(Streaks.effectiveStreak(s, today: 100), 5)
        XCTAssertEqual(Streaks.effectiveStreak(s, today: 101), 5, "still alive: today can extend it")
        XCTAssertEqual(Streaks.effectiveStreak(s, today: 102), 0, "a full day lapsed")
        XCTAssertEqual(Streaks.effectiveStreak(StreakState(), today: 10), 0)
    }

    func testBackwardsClockDoesNotEatTheStreak() {
        var s = StreakState(count: 3, lastDay: 100)
        s = Streaks.recordingDevelop(s, day: 99)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.lastDay, 100)
    }
}
