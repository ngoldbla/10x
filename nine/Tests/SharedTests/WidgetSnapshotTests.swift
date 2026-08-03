// WidgetSnapshotTests — the shared file deliberately duplicates ~10 lines of
// Engine day math (PRD-3 §2) so the widget extension stays Engine-free; these
// tests cross-check the duplicated line against the original, plus the
// snapshot's persistence and reload-digest behavior.
//
// The daily/streak fields — and the tests that mirrored `StreakState` — left
// with the daily system (2026-08-02).
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

    // MARK: - Persistence

    func testSnapshotRoundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nine-widget-snapshot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = WidgetSnapshot(
            boardFillFraction: 0.64,
            boardSolvedSeconds: nil,
            totalPoints: 4_250,
            generatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
            themeRaw: "dark",
            accentRaw: "glacier"
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

    /// A snapshot written by a pre-removal build carried daily/streak fields
    /// under keys this shape no longer has. It must still decode — as an
    /// empty-but-drawable snapshot, never a discard.
    func testAPreRemovalSnapshotDecodesToADrawableDefault() throws {
        let legacy = Data("""
        {"schemaVersion":1,"dailyDayOrdinal":9200,"dailyFillFraction":0.5,\
        "streakCurrent":12,"streakBest":21,"lastCompletedDay":9199,\
        "totalPoints":4250,"generatedAt":800000000,\
        "themeRaw":"dark","accentRaw":"glacier"}
        """.utf8)
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: legacy)
        XCTAssertEqual(snapshot.totalPoints, 4_250)
        XCTAssertEqual(snapshot.themeRaw, "dark")
        XCTAssertNil(snapshot.boardFillFraction, "the legacy daily fill is not this field")
    }

    // MARK: - Reload digest (the widget reload budget gate)

    func testReloadDigestBucketsFillByDecile() {
        func digest(fill: Double) -> String {
            WidgetSnapshot(boardFillFraction: fill).reloadDigest()
        }
        XCTAssertEqual(digest(fill: 0.31), digest(fill: 0.39), "same decile → no reload")
        XCTAssertNotEqual(digest(fill: 0.39), digest(fill: 0.41), "decile crossed → reload")
        XCTAssertNotEqual(
            WidgetSnapshot().reloadDigest(),
            WidgetSnapshot(boardFillFraction: 0.01).reloadDigest(),
            "first move leaves empty"
        )
    }

    func testReloadDigestTracksPointsSolveAndRevision() {
        let base = WidgetSnapshot(boardFillFraction: 0.5)
        var solved = base
        solved.boardSolvedSeconds = 251
        XCTAssertNotEqual(base.reloadDigest(), solved.reloadDigest())

        var richer = base
        richer.totalPoints += 300
        XCTAssertNotEqual(base.reloadDigest(), richer.reloadDigest())

        XCTAssertEqual(base.reloadDigest(boardRevision: 1), base.reloadDigest(boardRevision: 1),
                       "same revision + facts → stable digest (no wasted reload)")
        XCTAssertNotEqual(base.reloadDigest(boardRevision: 1), base.reloadDigest(boardRevision: 2),
                          "a board move (revision bump) must change the digest")
    }

    func testReloadDigestTracksTheLook() {
        let base = WidgetSnapshot(boardFillFraction: 0.5, themeRaw: "dark", accentRaw: "glacier")
        var recoloured = base
        recoloured.accentRaw = "ember"
        XCTAssertNotEqual(base.reloadDigest(), recoloured.reloadDigest(),
                          "an accent change must reach the Home Screen")
    }
}
