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
                lastCompletedDay: streak.lastCompletedDay
            )
            for vantage in (today - 2)...(today + 3) {
                XCTAssertEqual(
                    snapshot.displayedStreak(today: vantage),
                    streak.displayedStreak(today: vantage),
                    "\(label) at vantage \(vantage)"
                )
            }
        }

        assertAgreement("empty streak")
        streak.recordCompletion(day: today - 4)
        streak.recordCompletion(day: today - 3)
        assertAgreement("lapsed chain")
        streak.recordCompletion(day: today - 1)
        assertAgreement("alive via yesterday")
        streak.recordCompletion(day: today)
        assertAgreement("solved today")
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

        // Two days later without a solve: the flame lapses.
        XCTAssertEqual(snapshot.displayedStreak(today: today + 2), 0)
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
