// WidgetSnapshotTests — the shared file deliberately duplicates ~10 lines of
// Engine math (PRD-3 §2) so the widget extension stays Engine-free; these
// tests cross-check every duplicated line against the originals, plus the
// snapshot's persistence and reload-digest behavior.
import XCTest
import NineEngine
@testable import NineShared

final class WidgetSnapshotTests: XCTestCase {

    // MARK: - dayOrdinal cross-check vs DailySeed (Engine original)

    /// Sweep a year of days — including the 2025 US DST transitions
    /// (Mar 9, Nov 2) — in a DST-observing zone, sampling awkward local
    /// times either side of midnight. The two implementations must agree
    /// everywhere, and consecutive days must differ by exactly 1.
    func testDayOrdinalMatchesEngineAcrossDSTAndMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = DateComponents(calendar: calendar, year: 2025, month: 1, day: 1, hour: 12).date!
        var previous: Int?
        for dayOffset in 0..<400 {
            let noon = calendar.date(byAdding: .day, value: dayOffset, to: start)!
            for secondsFromNoon in [-43_200.0, -43_199.0, -1, 0, 1, 41_400, 43_199] {
                let date = noon.addingTimeInterval(secondsFromNoon)
                XCTAssertEqual(
                    WidgetSnapshotStore.dayOrdinal(for: date, calendar: calendar),
                    DailySeed.dayOrdinal(for: date, calendar: calendar),
                    "diverged at \(date)"
                )
            }
            let ordinal = WidgetSnapshotStore.dayOrdinal(for: noon, calendar: calendar)
            if let previous {
                XCTAssertEqual(ordinal, previous + 1, "consecutive days must differ by 1 at \(noon)")
            }
            previous = ordinal
        }
    }

    // MARK: - displayedStreak cross-check vs StreakState (Engine original)

    /// Drive real StreakState sequences (extend, gap, restart), copy the raw
    /// facts into a snapshot, and require identical displayedStreak at every
    /// vantage day.
    func testDisplayedStreakMatchesEngine() {
        let today = 9_200
        var streak = StreakState()

        func assertAgreement(_ label: String) {
            let snapshot = WidgetSnapshot(
                streakCurrent: streak.current,
                streakBest: streak.best,
                lastCompletedDay: streak.lastCompletedDay,
                lastGraceDay: streak.lastGraceDay
            )
            for vantage in (today - 2)...(today + 3) {
                XCTAssertEqual(
                    snapshot.displayedStreak(today: vantage),
                    streak.displayedStreak(today: vantage),
                    "\(label) at vantage \(vantage)"
                )
                XCTAssertEqual(
                    snapshot.graceAvailable, streak.graceAvailable,
                    "\(label): the bridge must be spent on both sides or neither"
                )
            }
        }

        assertAgreement("empty streak")
        streak.recordCompletion(day: today - 5)
        streak.recordCompletion(day: today - 4)
        assertAgreement("lapsed chain")
        streak.recordCompletion(day: today - 2)      // bridges today - 3
        assertAgreement("alive via a bridge")
        streak.recordCompletion(day: today - 1)
        assertAgreement("a natural day re-earns the bridge")
        streak.recordCompletion(day: today)
        assertAgreement("solved today")
        streak.recordCompletion(day: today + 2)      // bridges today + 1
        assertAgreement("second bridge, after natural days")
    }

    /// The widget must not offer a bridge the app has already spent — the
    /// mirror is only worth having if it is wrong in the same places.
    func testSnapshotRefusesAStackedBridgeExactlyAsTheEngineDoes() {
        let today = 9_200
        var streak = StreakState()
        streak.recordCompletion(day: today - 4)
        streak.recordCompletion(day: today - 2)      // bridge spent on today - 3
        let snapshot = WidgetSnapshot(
            streakCurrent: streak.current,
            streakBest: streak.best,
            lastCompletedDay: streak.lastCompletedDay,
            lastGraceDay: streak.lastGraceDay
        )
        XCTAssertEqual(snapshot.displayedStreak(today: today), 0)
        XCTAssertEqual(
            snapshot.displayedStreak(today: today),
            streak.displayedStreak(today: today)
        )
    }

    // MARK: - The widget's own solve path (PRD-3 §2 × PRD-13)

    /// A daily finished entirely inside the widget takes a different code path
    /// from every other solve, and it had its own hand-rolled copy of the
    /// streak rule — which PRD-13 silently made wrong. Driven against the
    /// Engine rather than against hand-written expectations.
    func testOptimisticWidgetSolveMatchesTheEngineIncludingTheBridge() {
        let base = 9_200
        // Every gap a second solve can arrive after, bridgeable or not.
        for gap in 1...3 {
            var streak = StreakState()
            streak.recordCompletion(day: base)
            var snapshot = WidgetSnapshot(
                streakCurrent: streak.current,
                streakBest: streak.best,
                lastCompletedDay: streak.lastCompletedDay,
                lastGraceDay: streak.lastGraceDay
            )

            streak.recordCompletion(day: base + gap)
            snapshot.recordOptimisticSolve(day: base + gap)

            XCTAssertEqual(snapshot.streakCurrent, streak.current, "gap \(gap)")
            XCTAssertEqual(snapshot.streakBest, streak.best, "gap \(gap)")
            XCTAssertEqual(snapshot.lastCompletedDay, streak.lastCompletedDay, "gap \(gap)")
            XCTAssertEqual(snapshot.lastGraceDay, streak.lastGraceDay, "gap \(gap)")
        }
    }

    func testOptimisticWidgetSolveIgnoresARepeatOfTheSameDay() {
        var snapshot = WidgetSnapshot(streakCurrent: 4, streakBest: 9, lastCompletedDay: 9_200)
        snapshot.recordOptimisticSolve(day: 9_200)
        XCTAssertEqual(snapshot.streakCurrent, 4, "solving today twice is not a two-day streak")
        snapshot.recordOptimisticSolve(day: 9_199)
        XCTAssertEqual(snapshot.streakCurrent, 4, "and time travel is also a no-op")
    }

    /// The specific regression: finish the daily in the widget after one missed
    /// day. The old code reset to 1 while the app's next ingest bridged to 13,
    /// so the widget was the app's one streak-shaming surface.
    func testAWidgetSolveAfterOneMissedDayBridgesRatherThanShames() {
        var snapshot = WidgetSnapshot(
            streakCurrent: 12, streakBest: 12, lastCompletedDay: 9_200
        )
        snapshot.recordOptimisticSolve(day: 9_202)   // 9_201 missed
        XCTAssertEqual(snapshot.streakCurrent, 13)
        XCTAssertEqual(snapshot.lastGraceDay, 9_201)
    }

    // MARK: - Persistence

    func testSnapshotRoundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nine-widget-snapshot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = WidgetSnapshot(
            dailyDayOrdinal: 9_201,
            dailyFillFraction: 0.64,
            dailySolvedSeconds: nil,
            streakCurrent: 12,
            streakBest: 21,
            lastCompletedDay: 9_200,
            totalPoints: 4_250,
            generatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
        )
        try WidgetSnapshotStore.save(snapshot, to: url)
        XCTAssertEqual(WidgetSnapshotStore.load(from: url), snapshot)
    }

    func testMissingAndFutureSchemaSnapshotsLoadAsNil() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nine-widget-missing-\(UUID().uuidString).json")
        XCTAssertNil(WidgetSnapshotStore.load(from: missing), "fresh install → placeholder, no crash")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nine-widget-future-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var future = WidgetSnapshot()
        future.schemaVersion = WidgetSnapshot.currentSchemaVersion + 1
        try WidgetSnapshotStore.save(future, to: url)
        XCTAssertNil(WidgetSnapshotStore.load(from: url), "newer schema is ignored, not misread")
    }

    // MARK: - Per-entry-date derivation (midnight rollover without app launch)

    func testMidnightRolloverDerivation() {
        let today = 9_200
        // Solved today, streak of 5.
        let snapshot = WidgetSnapshot(
            dailyDayOrdinal: today,
            dailyFillFraction: 1,
            dailySolvedSeconds: 252,
            streakCurrent: 5,
            streakBest: 9,
            lastCompletedDay: today,
            totalPoints: 2_000
        )
        XCTAssertTrue(snapshot.isSolved(today: today))
        XCTAssertFalse(snapshot.isInProgress(today: today))
        XCTAssertEqual(snapshot.displayedStreak(today: today), 5)

        // Same facts, next day: new puzzle waiting, flame persists.
        XCTAssertFalse(snapshot.isSolved(today: today + 1))
        XCTAssertFalse(snapshot.isInProgress(today: today + 1))
        XCTAssertEqual(snapshot.displayedStreak(today: today + 1), 5)

        // Two days later without a solve: one silent day is bridged (PRD-13),
        // so the flame is still lit — and the app agrees, because a solve now
        // really would extend the chain.
        XCTAssertEqual(snapshot.displayedStreak(today: today + 2), 5)

        // Three days later: two silent days, and the flame lapses.
        XCTAssertEqual(snapshot.displayedStreak(today: today + 3), 0)
    }

    func testInProgressOnlyForTodaysBoard() {
        let today = 9_200
        let stale = WidgetSnapshot(dailyDayOrdinal: today - 1, dailyFillFraction: 0.4)
        XCTAssertFalse(stale.isInProgress(today: today), "yesterday's leftover board is not today's progress")
        let fresh = WidgetSnapshot(dailyDayOrdinal: today, dailyFillFraction: 0.4)
        XCTAssertTrue(fresh.isInProgress(today: today))
    }

    // MARK: - Reload digest (the widget reload budget gate)

    func testReloadDigestBucketsFillByDecile() {
        let today = 9_200
        func digest(fill: Double) -> String {
            WidgetSnapshot(dailyDayOrdinal: today, dailyFillFraction: fill)
                .reloadDigest(today: today)
        }
        XCTAssertEqual(digest(fill: 0.31), digest(fill: 0.39), "same decile → no reload")
        XCTAssertNotEqual(digest(fill: 0.39), digest(fill: 0.41), "decile crossed → reload")
        XCTAssertNotEqual(
            WidgetSnapshot().reloadDigest(today: today),
            WidgetSnapshot(dailyDayOrdinal: today, dailyFillFraction: 0.01).reloadDigest(today: today),
            "first move leaves notStarted"
        )
    }

    func testReloadDigestTracksStreakPointsAndSolve() {
        let today = 9_200
        let base = WidgetSnapshot(dailyDayOrdinal: today, dailyFillFraction: 0.5)
        var solved = base
        solved.lastCompletedDay = today
        XCTAssertNotEqual(base.reloadDigest(today: today), solved.reloadDigest(today: today))

        var richer = base
        richer.totalPoints += 300
        XCTAssertNotEqual(base.reloadDigest(today: today), richer.reloadDigest(today: today))

        var flame = base
        flame.streakCurrent = 3
        flame.lastCompletedDay = today - 1
        XCTAssertNotEqual(base.reloadDigest(today: today), flame.reloadDigest(today: today))
    }

    // MARK: - Timeline helper

    func testNextLocalMidnightIsStrictlyLaterAndOnBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        // Includes the night the clocks spring forward (Mar 9 2025).
        for (y, m, d, h) in [(2025, 3, 8, 23), (2025, 3, 9, 1), (2025, 11, 1, 23), (2025, 7, 15, 0)] {
            let date = DateComponents(calendar: calendar, year: y, month: m, day: d, hour: h).date!
            let midnight = WidgetSnapshotStore.nextLocalMidnight(after: date, calendar: calendar)
            XCTAssertGreaterThan(midnight, date)
            let comps = calendar.dateComponents([.hour, .minute, .second], from: midnight)
            XCTAssertEqual([comps.hour, comps.minute, comps.second], [0, 0, 0])
            XCTAssertEqual(
                WidgetSnapshotStore.dayOrdinal(for: midnight, calendar: calendar),
                WidgetSnapshotStore.dayOrdinal(for: date, calendar: calendar) + 1,
                "next midnight lands on the next day ordinal"
            )
        }
    }
}
