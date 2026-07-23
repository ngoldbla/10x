// KnownRevisionTests — the two widget-sync fixes (playtest fix D3): the
// persisted ingested-revision (kills the cold-launch clobber) and the daily
// revision now folded into the reload digest (kills glanceable lag).
import XCTest
import NineEngine
@testable import NineShared

final class KnownRevisionTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "nine-known-rev-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testKnownRevisionRoundTripsThroughDefaults() {
        // Absent → 0 (the safe default; a brand-new install has ingested nothing).
        XCTAssertEqual(SharedDailyBoardStore.knownRevision(defaults: defaults), 0)
        SharedDailyBoardStore.setKnownRevision(7, defaults: defaults)
        XCTAssertEqual(SharedDailyBoardStore.knownRevision(defaults: defaults), 7)
        // Survives a fresh handle to the same suite (the cold-launch case).
        let reopened = UserDefaults(suiteName: suiteName)
        XCTAssertEqual(SharedDailyBoardStore.knownRevision(defaults: reopened), 7)
    }

    func testDigestChangesOnRevisionBumpStableOtherwise() {
        let today = 19_000
        let snapshot = WidgetSnapshot(
            dailyDayOrdinal: today,
            dailyFillFraction: 0.42,
            streakCurrent: 3,
            lastCompletedDay: today - 1,
            totalPoints: 1234
        )
        let r1 = snapshot.reloadDigest(today: today, boardRevision: 1)
        let r1again = snapshot.reloadDigest(today: today, boardRevision: 1)
        let r2 = snapshot.reloadDigest(today: today, boardRevision: 2)
        XCTAssertEqual(r1, r1again, "same revision + facts → stable digest (no wasted reload)")
        XCTAssertNotEqual(r1, r2, "a daily move (revision bump) must change the digest")
        // A within-decile move used to be invisible to the glanceable digest;
        // now the revision carries it even though the decile is unchanged.
        let sameDecile = WidgetSnapshot(
            dailyDayOrdinal: today,
            dailyFillFraction: 0.48, // still decile 4
            streakCurrent: 3,
            lastCompletedDay: today - 1,
            totalPoints: 1234
        )
        XCTAssertNotEqual(
            snapshot.reloadDigest(today: today, boardRevision: 1),
            sameDecile.reloadDigest(today: today, boardRevision: 2)
        )
    }
}
