// CoachLedgerTests — the coach's per-board bookkeeping (PRD-11 §6).
//
// This is a sibling top-level blob rather than a `LibraryEntry` field for the
// reason EXECUTING-A-PRD §2 gives: an older build's synthesized decode drops
// fields it has no property for and erases them on its next autosave, 0.6 s
// later, repeatedly, for any mixed-version two-device player. The tolerance
// tests below are the other half of that discipline — `CouchStored` discards
// the whole blob when a decode throws.
import XCTest
@testable import NineShared

final class CoachLedgerTests: XCTestCase {

    private let board = "11111111-1111-1111-1111-111111111111"
    private let other = "22222222-2222-2222-2222-222222222222"

    func testUnknownBoardReadsAsZeroAndOff() {
        let ledger = CoachLedger()
        XCTAssertEqual(ledger.board(board).hints, 0)
        XCTAssertFalse(ledger.board(board).autoNotes)
        XCTAssertEqual(ledger.count, 0, "asking about a board does not create it")
    }

    func testHintsAccumulatePerBoardIndependently() {
        var ledger = CoachLedger()
        ledger.recordHint(board)
        ledger.recordHint(board)
        ledger.recordHint(other)
        XCTAssertEqual(ledger.board(board).hints, 2)
        XCTAssertEqual(ledger.board(other).hints, 1)
    }

    func testAutoNotesFlagSurvivesAlongsideTheHintCount() {
        var ledger = CoachLedger()
        ledger.recordHint(board)
        ledger.setAutoNotes(true, for: board)
        XCTAssertTrue(ledger.board(board).autoNotes)
        XCTAssertEqual(ledger.board(board).hints, 1, "the flag must not clobber the count")
        ledger.setAutoNotes(false, for: board)
        XCTAssertFalse(ledger.board(board).autoNotes)
        XCTAssertEqual(ledger.board(board).hints, 1)
    }

    func testPruningDropsBoardsTheLibraryNoLongerHas() {
        var ledger = CoachLedger()
        ledger.recordHint(board)
        ledger.recordHint(other)
        ledger.prune(to: [board])
        XCTAssertEqual(ledger.board(board).hints, 1)
        XCTAssertEqual(ledger.board(other).hints, 0, "a deleted board takes its count with it")
        XCTAssertEqual(ledger.count, 1)
    }

    func testTheBlobCannotGrowPastItsCap() {
        var ledger = CoachLedger()
        let ids = (0..<(CoachLedger.capacity + 50)).map { "id-\($0)" }
        for id in ids { ledger.recordHint(id) }
        XCTAssertEqual(ledger.count, CoachLedger.capacity)
        XCTAssertEqual(ledger.board("id-0").hints, 0, "the oldest went first")
        XCTAssertEqual(ledger.board(ids.last!).hints, 1, "the newest stayed")
        ledger.prune(to: Set(ids))
        XCTAssertLessThanOrEqual(ledger.count, CoachLedger.capacity)
    }

    // MARK: - Tolerance: CouchStored discards the whole blob when decode throws

    func testMalformedPayloadDecodesAsEmptyRatherThanThrowing() throws {
        let json = Data(#"{"boards": "not an object"}"#.utf8)
        let ledger = try JSONDecoder().decode(CoachLedger.self, from: json)
        XCTAssertEqual(ledger.count, 0)
    }

    func testEmptyPayloadDecodes() throws {
        let ledger = try JSONDecoder().decode(CoachLedger.self, from: Data("{}".utf8))
        XCTAssertEqual(ledger.count, 0)
    }

    func testFutureShapedRecordKeepsWhatItCanRead() throws {
        // A later build adds a sibling field inside Board. This one must read
        // the fields it knows and ignore the rest, not lose the blob.
        let json = Data(#"""
        {"boards": {"\#(board)": {"hints": 3, "autoNotes": true, "mastery": 9}}}
        """#.utf8)
        let ledger = try JSONDecoder().decode(CoachLedger.self, from: json)
        XCTAssertEqual(ledger.board(board).hints, 3)
        XCTAssertTrue(ledger.board(board).autoNotes)
    }

    func testWrongTypedFieldFallsBackPerFieldNotPerBlob() throws {
        let json = Data(#"""
        {"boards": {"\#(board)": {"hints": "three", "autoNotes": true}}}
        """#.utf8)
        let ledger = try JSONDecoder().decode(CoachLedger.self, from: json)
        XCTAssertEqual(ledger.board(board).hints, 0, "the bad field defaults")
        XCTAssertTrue(ledger.board(board).autoNotes, "the good one beside it survives")
    }

    func testAPayloadWithNoOrderKeyStillPrunesDeterministically() throws {
        let json = Data(#"""
        {"boards": {"\#(board)": {"hints": 1}, "\#(other)": {"hints": 2}}}
        """#.utf8)
        var ledger = try JSONDecoder().decode(CoachLedger.self, from: json)
        XCTAssertEqual(ledger.count, 2)
        ledger.prune(to: [other])
        XCTAssertEqual(ledger.count, 1, "the repaired order still filters cleanly")
        XCTAssertEqual(ledger.board(other).hints, 2)
    }

    func testRoundTrip() throws {
        var ledger = CoachLedger()
        ledger.recordHint(board)
        ledger.setAutoNotes(true, for: board)
        ledger.recordHint(other)
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(CoachLedger.self, from: data), ledger)
    }
}
