import XCTest
@testable import NineShared

final class ArchiveLedgerTests: XCTestCase {

    // MARK: - The set

    func testEmptyLedgerHasSolvedNothing() {
        let ledger = ArchiveLedger()
        XCTAssertFalse(ledger.isSolved(day: 9_500))
        XCTAssertEqual(ledger.count, 0)
        XCTAssertEqual(ledger.solvedDays, [])
    }

    func testMarkSolvedIsASetInsert() {
        var ledger = ArchiveLedger()
        XCTAssertTrue(ledger.markSolved(day: 9_500))
        XCTAssertFalse(ledger.markSolved(day: 9_500), "a second mark reports no change")
        XCTAssertTrue(ledger.isSolved(day: 9_500))
        XCTAssertEqual(ledger.count, 1)
    }

    func testSolvedDaysAreSortedRegardlessOfInsertionOrder() {
        var ledger = ArchiveLedger()
        for day in [9_503, 9_500, 9_777, 9_501] { ledger.markSolved(day: day) }
        XCTAssertEqual(ledger.solvedDays, [9_500, 9_501, 9_503, 9_777])
    }

    /// `isSolved` binary-searches, so a store that fell out of order would
    /// answer *wrongly* rather than slowly — a missing checkmark, not a slow
    /// one. Ten thousand entries is ~27 years of daily play.
    func testLookupIsCorrectAcrossALargeLedger() {
        var ledger = ArchiveLedger()
        for day in stride(from: 9_000, to: 19_000, by: 2) { ledger.markSolved(day: day) }
        XCTAssertEqual(ledger.count, 5_000)
        XCTAssertTrue(ledger.isSolved(day: 9_000))
        XCTAssertTrue(ledger.isSolved(day: 13_456))
        XCTAssertTrue(ledger.isSolved(day: 18_998))
        XCTAssertFalse(ledger.isSolved(day: 9_001))
        XCTAssertFalse(ledger.isSolved(day: 8_999))
        XCTAssertFalse(ledger.isSolved(day: 19_000))
    }

    // MARK: - The decode covenant (nothing in here may throw)

    func testRoundTrips() throws {
        var ledger = ArchiveLedger()
        for day in [9_500, 9_501, 9_777] { ledger.markSolved(day: day) }
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(ArchiveLedger.self, from: data), ledger)
    }

    /// `CouchStored` discards the whole blob when a decode throws, and a lost
    /// blob here is every checkmark the player has earned.
    func testGarbageDecodesToAnEmptyLedgerRatherThanThrowing() throws {
        for json in ["{}", "{\"days\":\"nope\"}", "{\"days\":{}}", "{\"days\":null}"] {
            let ledger = try JSONDecoder().decode(ArchiveLedger.self, from: Data(json.utf8))
            XCTAssertEqual(ledger.count, 0, json)
        }
    }

    func testAnUnreadableElementIsSkippedAndTheRestSurvive() throws {
        let json = "{\"days\":[9500,\"nope\",9501,null,9502]}"
        let ledger = try JSONDecoder().decode(ArchiveLedger.self, from: Data(json.utf8))
        XCTAssertEqual(ledger.solvedDays, [9_500, 9_501, 9_502])
    }

    func testDuplicatesInAHandEditedBlobAreRepairedOnDecode() throws {
        let json = "{\"days\":[9502,9500,9500,9501]}"
        let ledger = try JSONDecoder().decode(ArchiveLedger.self, from: Data(json.utf8))
        XCTAssertEqual(ledger.solvedDays, [9_500, 9_501, 9_502])
    }

    /// A future build's sibling key survives this build's rewrite — the rule
    /// `SolveHistory` and `BoardLibrary` already keep.
    func testUnknownTopLevelSiblingsAreCarried() throws {
        let json = "{\"days\":[9500],\"firstOpenedAt\":\"2026-07-26\",\"schemaVersion\":2}"
        var ledger = try JSONDecoder().decode(ArchiveLedger.self, from: Data(json.utf8))
        ledger.markSolved(day: 9_501)
        let rewritten = try JSONEncoder().encode(ledger)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: rewritten) as? [String: Any]
        )
        XCTAssertEqual(object["firstOpenedAt"] as? String, "2026-07-26")
        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        XCTAssertEqual(object["days"] as? [Int], [9_500, 9_501])
    }

    /// Identity is the days. The carried trees are an encoding detail, and
    /// excluding them is what lets a hand-built ledger compare equal to a
    /// decoded one — the same call `SolveHistory` and `BoardLibrary` made.
    func testEqualityIgnoresCarriedKeys() throws {
        let decoded = try JSONDecoder().decode(
            ArchiveLedger.self, from: Data("{\"days\":[9500],\"x\":1}".utf8)
        )
        var built = ArchiveLedger()
        built.markSolved(day: 9_500)
        XCTAssertEqual(decoded, built)
    }
}
