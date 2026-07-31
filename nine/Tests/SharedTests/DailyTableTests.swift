// DailyTableTests.swift — the whole of PRD-29's arithmetic, with no Game Center
// in sight.
//
// Everything a table *is* — the week window, the tally, the packed score, the
// twenty seats — is pure, so all of it tests here in microseconds. That matters
// more than usual on this PRD: the App Store Connect recurring-leaderboard record
// does not exist, so `loadEntries` returns nothing and the GameKit half cannot be
// run at all. What can be run is everything the GameKit half would carry.
import XCTest
@testable import NineShared
import NineEngine

final class DailyTableTests: XCTestCase {

    /// Monday 2026-07-27. Day ordinal 0 is 2001-01-01, which was a Monday, so
    /// every ordinal ≡ 0 (mod 7) is one.
    private static let monday = 9_338

    private func record(
        day: Int, seconds: TimeInterval, isDaily: Bool = true, hour: Int = 12
    ) -> SolveRecord {
        // A day ordinal is a UTC midnight by construction, so the date that
        // reads back as this ordinal has to be built in UTC too — the trap
        // `DailySeed.utcCalendar` exists for.
        let midnight = Date(timeIntervalSinceReferenceDate: TimeInterval(day) * 86_400)
        let at = midnight.addingTimeInterval(TimeInterval(hour) * 3_600)
        return SolveRecord(
            date: at, difficulty: .steady, isDaily: isDaily, seconds: seconds, points: 10)
    }

    private func history(_ records: [SolveRecord]) -> SolveHistory {
        var history = SolveHistory()
        // `record` inserts at the head, so feeding oldest-first leaves the
        // newest-first contract intact — which is what the app's own writes do.
        for r in records.sorted(by: { $0.date < $1.date }) { history.record(r) }
        return history
    }

    /// The tally, in UTC, because the fixtures above are built there.
    private func tally(
        _ history: SolveHistory, week: ClosedRange<Int>,
        trusting: (Int) -> Bool = { _ in true }
    ) -> DailyTable.Week {
        DailyTable.tally(history, over: week,
                         calendar: DailySeed.utcCalendar, trusting: trusting)
    }

    // MARK: - The week starts on Monday, everywhere

    func testDayOrdinalZeroIsAMondayAndTheWeekIsAnchoredOnIt() {
        XCTAssertEqual(DailyTable.weekStart(containing: 0), 0)
        XCTAssertEqual(DailyTable.weekStart(containing: 6), 0)
        XCTAssertEqual(DailyTable.weekStart(containing: 7), 7)
        XCTAssertEqual(DailyTable.weekStart(containing: Self.monday), Self.monday)
        XCTAssertEqual(DailyTable.weekStart(containing: Self.monday + 6), Self.monday)
        XCTAssertEqual(DailyTable.weekStart(containing: Self.monday + 7), Self.monday + 7)
    }

    /// Ordinals before the reference date are negative, and Swift's `%` keeps
    /// the sign of the dividend — so the floor-mod is not decoration.
    func testTheWeekIsCorrectBeforeTheReferenceDate() {
        XCTAssertEqual(DailyTable.weekStart(containing: -1), -7)
        XCTAssertEqual(DailyTable.weekStart(containing: -7), -7)
        XCTAssertEqual(DailyTable.weekStart(containing: -8), -14)
    }

    func testAWeekIsSevenConsecutiveOrdinals() {
        let week = DailyTable.week(containing: Self.monday + 3)
        XCTAssertEqual(week, Self.monday...(Self.monday + 6))
        XCTAssertEqual(week.count, DailyTable.daysInWeek)
    }

    /// The one place the player's own settings are overruled on purpose. A US
    /// player whose calendar starts on Sunday and a German player whose calendar
    /// starts on Monday, counting against one occurrence, are two people playing
    /// different games and neither can tell.
    func testTheWeekIgnoresTheLocalesFirstWeekday() {
        // The whole function's signature is the proof: there is no `Calendar`
        // and no `Locale` to pass one in through.
        XCTAssertEqual(DailyTable.weekStart(containing: Self.monday + 6), Self.monday)
        // And the Sunday reading, which is what a US calendar would give, is a
        // different answer — so this is a real constraint, not a coincidence.
        XCTAssertNotEqual(DailyTable.weekStart(containing: Self.monday + 6),
                          Self.monday + 6)
    }

    // MARK: - The tally

    func testAWeekWithNoSolvesTalliesNothing() {
        let week = tally(SolveHistory(), week: DailyTable.week(containing: Self.monday))
        XCTAssertEqual(week, DailyTable.Week(days: 0, seconds: 0))
        XCTAssertTrue(week.isEmpty)
    }

    func testEachDaySolvedCountsOnceAndItsSecondsAdd() {
        let store = history([
            record(day: Self.monday, seconds: 100),
            record(day: Self.monday + 1, seconds: 200),
            record(day: Self.monday + 2, seconds: 300),
        ])
        XCTAssertEqual(tally(store, week: DailyTable.week(containing: Self.monday)),
                       DailyTable.Week(days: 3, seconds: 600))
    }

    /// A daily can be replayed — `BoardLibrary.adoptDaily` reuses the day's slot —
    /// so a day can hold more than one record. It is one day either way, and the
    /// time is the **first** attempt: "fastest" would pay for repetition, which
    /// is the grinding a covenant that bans gamification is trying not to buy.
    func testADayReplayedKeepsItsFirstTime() {
        let store = history([
            record(day: Self.monday, seconds: 400, hour: 9),
            record(day: Self.monday, seconds: 90, hour: 21),
        ])
        XCTAssertEqual(tally(store, week: DailyTable.week(containing: Self.monday)),
                       DailyTable.Week(days: 1, seconds: 400))
    }

    /// Free boards are unbounded, so a league scored on them is a league scored
    /// on volume.
    func testAFreeBoardDoesNotCount() {
        let store = history([
            record(day: Self.monday, seconds: 100, isDaily: false),
            record(day: Self.monday + 1, seconds: 200, isDaily: false),
        ])
        XCTAssertTrue(tally(store, week: DailyTable.week(containing: Self.monday)).isEmpty)
    }

    func testSolvesOutsideTheWeekAreInvisible() {
        let store = history([
            record(day: Self.monday - 1, seconds: 100),
            record(day: Self.monday + 2, seconds: 200),
            record(day: Self.monday + 7, seconds: 300),
        ])
        XCTAssertEqual(tally(store, week: DailyTable.week(containing: Self.monday)),
                       DailyTable.Week(days: 1, seconds: 200))
    }

    /// **The hole this closes is arithmetic, not conduct.** `score` clamps a
    /// week's seconds to at least 1, so a day recorded with no time at all would
    /// rank as the fastest solve possible. A solve nobody timed is a solve nobody
    /// can rank, and dropping the day is the only reading that does not invent a
    /// number or reward the absence of one.
    func testADayWithNoRecordedTimeIsNotCounted() {
        let store = history([
            record(day: Self.monday, seconds: 0),
            record(day: Self.monday + 1, seconds: 250),
        ])
        XCTAssertEqual(tally(store, week: DailyTable.week(containing: Self.monday)),
                       DailyTable.Week(days: 1, seconds: 250))
    }

    /// The audit's gate, as the tally sees it. Excluding one day rather than the
    /// whole week is the deliberate choice: poisoning six honest days for one
    /// unreadable record punishes a bug far more often than a person.
    func testAnUntrustedDayIsDroppedAndTheRestOfTheWeekSurvives() {
        let store = history([
            record(day: Self.monday, seconds: 100),
            record(day: Self.monday + 1, seconds: 200),
            record(day: Self.monday + 2, seconds: 300),
        ])
        let week = tally(store, week: DailyTable.week(containing: Self.monday)) {
            $0 != Self.monday + 1
        }
        XCTAssertEqual(week, DailyTable.Week(days: 2, seconds: 400))
    }

    func testAFullWeekIsSevenDays() {
        let store = history((0..<7).map { record(day: Self.monday + $0, seconds: 60) })
        XCTAssertEqual(tally(store, week: DailyTable.week(containing: Self.monday)),
                       DailyTable.Week(days: 7, seconds: 420))
    }

    // MARK: - The score is a lexicographic pair in one integer

    func testMoreDaysAlwaysBeatsFewerNoMatterTheTime() {
        let diligent = DailyTable.score(of: DailyTable.Week(days: 4, seconds: 999_999))
        let quick = DailyTable.score(of: DailyTable.Week(days: 3, seconds: 1))
        XCTAssertGreaterThan(diligent, quick,
                             "consistency is the primary key; no amount of speed closes it")
    }

    func testInsideADayCountTheFasterWeekWins() {
        let fast = DailyTable.score(of: DailyTable.Week(days: 5, seconds: 900))
        let slow = DailyTable.score(of: DailyTable.Week(days: 5, seconds: 1_800))
        XCTAssertGreaterThan(fast, slow)
    }

    /// Every row the table draws is read straight off the entry. There is no
    /// second fetch and no `context` payload, because a second source for a
    /// number the score already determines is a second thing that can disagree.
    func testTheScoreIsInvertible() {
        for days in 0...7 {
            for seconds in [1, 2, 59, 600, 3_600, 86_399, 999_999, 1_000_000] {
                let week = DailyTable.Week(days: days, seconds: seconds)
                XCTAssertEqual(DailyTable.week(fromScore: DailyTable.score(of: week)), week,
                               "\(days)d/\(seconds)s did not round-trip")
            }
        }
    }

    /// The clamp's lower bound is 1 rather than 0, and this is the test that
    /// says why: at zero the second term equals `timeSpan` and the whole score
    /// equals `(days + 1) * timeSpan` — one full day of consistency, manufactured
    /// by arithmetic.
    func testAZeroSecondWeekCannotForgeAnExtraDay() {
        let forged = DailyTable.score(of: DailyTable.Week(days: 3, seconds: 0))
        let real = DailyTable.score(of: DailyTable.Week(days: 4, seconds: 999_999))
        XCTAssertLessThan(forged, real)
        XCTAssertEqual(DailyTable.week(fromScore: forged).days, 3)
    }

    /// A week longer than the field can hold saturates rather than wrapping into
    /// the day count. 11.6 days of solving is not reachable in a 7-day window,
    /// which is exactly why the ceiling can be this generous.
    func testAnAbsurdlyLongWeekSaturatesInsteadOfOverflowing() {
        let score = DailyTable.score(of: DailyTable.Week(days: 2, seconds: 50_000_000))
        XCTAssertEqual(DailyTable.week(fromScore: score).days, 2)
        XCTAssertEqual(DailyTable.week(fromScore: score).seconds, DailyTable.timeSpan)
    }

    /// The whole ordering, swept: sorting packed scores descending must equal
    /// sorting the pairs lexicographically. One assertion for the entire ranking
    /// rule.
    func testSortingByScoreIsSortingByDaysThenTime() {
        var weeks: [DailyTable.Week] = []
        for days in 0...7 {
            for seconds in [1, 30, 300, 3_000, 30_000] {
                weeks.append(DailyTable.Week(days: days, seconds: seconds))
            }
        }
        let byScore = weeks.sorted { DailyTable.score(of: $0) > DailyTable.score(of: $1) }
        let byRule = weeks.sorted {
            $0.days != $1.days ? $0.days > $1.days : $0.seconds < $1.seconds
        }
        XCTAssertEqual(byScore, byRule)
    }

    /// A week's score only ever increases, which is what makes "keep the best
    /// score in the occurrence" the right App Store Connect setting and a dropped
    /// submission cost nothing.
    func testAWeeksScoreOnlyEverGrows() {
        var store = SolveHistory()
        var last = Int.min
        for day in 0..<7 {
            store.record(record(day: Self.monday + day, seconds: 300))
            let score = DailyTable.score(
                of: tally(store, week: DailyTable.week(containing: Self.monday)))
            XCTAssertGreaterThan(score, last, "day \(day) did not raise the score")
            last = score
        }
    }

    /// An empty week is never submitted, so the score of one is never read — but
    /// it still has to be a number, and it has to be the smallest one.
    func testAnEmptyWeekScoresBelowEveryPlayedOne() {
        let empty = DailyTable.score(of: DailyTable.Week(days: 0, seconds: 0))
        XCTAssertLessThan(empty,
                          DailyTable.score(of: DailyTable.Week(days: 1, seconds: 999_999)))
    }

    // MARK: - The window: twenty seats, always full, always centred

    func testTheWindowIsCentredOnYou() {
        let window = DailyTable.window(around: 100, total: 10_000)
        XCTAssertEqual(window, 91...110)
        XCTAssertEqual(window.count, DailyTable.seatCount)
        XCTAssertTrue(window.contains(100))
    }

    func testTheWindowStaysFullAtTheTop() {
        let window = DailyTable.window(around: 2, total: 10_000)
        XCTAssertEqual(window, 1...20)
        XCTAssertEqual(window.count, DailyTable.seatCount)
    }

    func testTheWindowStaysFullAtTheBottom() {
        let window = DailyTable.window(around: 9_999, total: 10_000)
        XCTAssertEqual(window, 9_981...10_000)
        XCTAssertEqual(window.count, DailyTable.seatCount)
    }

    /// A league smaller than a table is the whole league, and it is not padded
    /// with empty seats — honest absence over fake data, the craft charter's
    /// rule.
    func testALeagueSmallerThanATableIsTheWholeLeague() {
        XCTAssertEqual(DailyTable.window(around: 1, total: 5), 1...5)
        XCTAssertEqual(DailyTable.window(around: 3, total: 3), 1...3)
    }

    /// This arithmetic runs on numbers a server chose, so nonsense in has to give
    /// a legal window out rather than a trap. A rank past the end of the board
    /// slides to the bottom-most *full* window — the same answer a real rank
    /// down there would get — rather than to the top, which would be a different
    /// twenty people for no reason.
    func testANonsenseRankOrTotalStillYieldsALegalWindow() {
        XCTAssertEqual(DailyTable.window(around: 0, total: 0), 1...1)
        XCTAssertEqual(DailyTable.window(around: -4, total: 10_000), 1...20)
        XCTAssertEqual(DailyTable.window(around: 99_999, total: 30), 11...30)
    }

    // MARK: - The negatives, as properties of the types

    /// **There is nothing to be relegated from.** A seat is a row in a window,
    /// not a member of a cohort, and it carries no position — so "you dropped
    /// four places" is not a message we decided against, it is one no code path
    /// can construct.
    func testASeatCarriesNoPositionAndNoHistory() {
        let seat = DailyTable.Seat(
            id: "G:1", name: "Somebody", week: DailyTable.Week(days: 3, seconds: 900),
            isMe: false)
        let fields = Set(Mirror(reflecting: seat).children.compactMap(\.label))
        XCTAssertEqual(fields, ["id", "name", "week", "isMe"])
        for forbidden in ["rank", "position", "seat", "previous", "delta",
                          "change", "movement", "tier", "division", "league"] {
            XCTAssertFalse(
                fields.contains(where: { $0.lowercased().contains(forbidden) }),
                "DailyTable.Seat gained a `\(forbidden)` field — PRD-29 §2: a "
                    + "window has no identity, and nothing stores a previous one")
        }
    }

    /// And the same question of the payload, which is where PRD-30 learned that
    /// a surface can draw what the wire never carried: the score is two numbers,
    /// and a rank is not one of them.
    func testTheWirePairIsTwoNumbersAndNeitherIsAPosition() {
        let fields = Set(Mirror(reflecting: DailyTable.Week(days: 1, seconds: 1))
            .children.compactMap(\.label))
        XCTAssertEqual(fields, ["days", "seconds"])
    }
}
