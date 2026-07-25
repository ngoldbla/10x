// TipCoachTests — the tip budget (PRD-34). The cap is the feature: three tips
// for the life of the install, one per session, each once. A budget enforced
// only by view code is a budget that quietly becomes four tips in a release
// nobody audits, so every clause of it is pinned here.
//
// The privacy branch matters as much as the cap: `errorHighlight == false`
// means the undo tip must stay silent, because its trigger is knowledge of the
// solution the player asked not to be shown.
import XCTest
@testable import NineShared

final class TipCoachTests: XCTestCase {

    /// A moment where every tip's signal is live at once, so each test can
    /// isolate the *budget* rule it cares about rather than the trigger.
    private var everythingQualifies: TipMoment {
        TipMoment(
            placements: 20,
            undosTaken: 0,
            pencilMarks: 0,
            pencilUsed: false,
            highlightUsed: false,
            highlightAvailable: true,
            visibleMistake: true,
            solved: false
        )
    }

    // MARK: - The cap

    func testPriorityOrderIsUndoThenPencilThenHighlight() {
        var ledger = TipLedger()
        XCTAssertEqual(TipCoach.next(for: everythingQualifies, ledger: ledger, shownThisSession: false), .undo)
        ledger.record(.undo)
        XCTAssertEqual(TipCoach.next(for: everythingQualifies, ledger: ledger, shownThisSession: false), .pencil)
        ledger.record(.pencil)
        XCTAssertEqual(TipCoach.next(for: everythingQualifies, ledger: ledger, shownThisSession: false), .highlight)
    }

    func testThreeTipsIsTheWholeBudgetForever() {
        var ledger = TipLedger()
        for tip in NineTip.allCases { ledger.record(tip) }
        XCTAssertTrue(ledger.isSpent)
        XCTAssertNil(TipCoach.next(for: everythingQualifies, ledger: ledger, shownThisSession: false))
    }

    func testOnePerSession() {
        XCTAssertNil(TipCoach.next(for: everythingQualifies, ledger: TipLedger(), shownThisSession: true))
    }

    func testRecordingIsIdempotent() {
        var ledger = TipLedger()
        ledger.record(.undo)
        ledger.record(.undo)
        XCTAssertEqual(ledger.shown, ["undo"])
        XCTAssertFalse(ledger.isSpent)
    }

    /// A tip minted by a later build still costs one of the three when an
    /// older build reads the ledger back — otherwise a downgrade hands the
    /// player a fresh budget and re-teaches them the app.
    func testUnknownIdsFromAFutureBuildStillCountAgainstTheCap() {
        let ledger = TipLedger(shown: ["coach", "variants", "replay"])
        XCTAssertTrue(ledger.isSpent)
        XCTAssertNil(TipCoach.next(for: everythingQualifies, ledger: ledger, shownThisSession: false))
    }

    func testNothingSpeaksOverTheAfterglow() {
        var moment = everythingQualifies
        moment.solved = true
        XCTAssertNil(TipCoach.next(for: moment, ledger: TipLedger(), shownThisSession: false))
    }

    // MARK: - Triggers

    /// The privacy rule: with mistake-marking off the caller reports no visible
    /// mistake, and the undo tip must not appear — it would tell the player,
    /// through a hint, the thing they switched off.
    func testUndoStaysSilentWhenTheMistakeIsNotOnScreen() {
        var moment = TipMoment(placements: 3, visibleMistake: false)
        XCTAssertNil(TipCoach.next(for: moment, ledger: TipLedger(), shownThisSession: false))
        moment.visibleMistake = true
        XCTAssertEqual(TipCoach.next(for: moment, ledger: TipLedger(), shownThisSession: false), .undo)
    }

    func testUndoIsNotOfferedToSomeoneWhoAlreadyUndoes() {
        let moment = TipMoment(placements: 3, undosTaken: 2, visibleMistake: true)
        XCTAssertNil(TipCoach.next(for: moment, ledger: TipLedger(), shownThisSession: false))
    }

    func testPencilWaitsForItsThresholdAndSkipsPlayersWhoPencil() {
        let early = TipMoment(placements: TipCoach.pencilAfter - 1)
        XCTAssertNil(TipCoach.next(for: early, ledger: TipLedger(), shownThisSession: false))

        let due = TipMoment(placements: TipCoach.pencilAfter)
        XCTAssertEqual(TipCoach.next(for: due, ledger: TipLedger(), shownThisSession: false), .pencil)

        let noted = TipMoment(placements: TipCoach.pencilAfter, pencilMarks: 4)
        XCTAssertNil(TipCoach.next(for: noted, ledger: TipLedger(), shownThisSession: false))

        let toggled = TipMoment(placements: TipCoach.pencilAfter, pencilUsed: true)
        XCTAssertNil(TipCoach.next(for: toggled, ledger: TipLedger(), shownThisSession: false))
    }

    func testHighlightIsNeverAdvertisedWhenTheFeatureIsOff() {
        let moment = TipMoment(
            placements: TipCoach.highlightAfter,
            pencilMarks: 1,          // pencil tip already disqualified
            pencilUsed: true,
            highlightAvailable: false
        )
        XCTAssertNil(TipCoach.next(for: moment, ledger: TipLedger(), shownThisSession: false))
    }

    func testHighlightFiresAtItsThreshold() {
        let moment = TipMoment(
            placements: TipCoach.highlightAfter,
            pencilMarks: 1,
            pencilUsed: true
        )
        XCTAssertEqual(TipCoach.next(for: moment, ledger: TipLedger(), shownThisSession: false), .highlight)
    }

    // MARK: - Persistence

    func testRoundTrip() throws {
        var ledger = TipLedger()
        ledger.record(.pencil)
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(TipLedger.self, from: data), ledger)
    }

    /// `CouchStored` throws the whole blob away when a decode throws, and this
    /// blob shares no file with anything else — but the habit is the rule.
    func testGarbageDecodesToAnEmptyLedgerRatherThanThrowing() throws {
        for payload in ["{}", #"{"shown": null}"#, #"{"shown": "three"}"#, #"{"other": 1}"#] {
            let ledger = try JSONDecoder().decode(TipLedger.self, from: Data(payload.utf8))
            XCTAssertEqual(ledger.shown, [], "payload: \(payload)")
        }
    }

    func testEveryTipHasCopyAndAGlyph() {
        for tip in NineTip.allCases {
            XCTAssertFalse(tip.message.isEmpty)
            XCTAssertFalse(tip.symbol.isEmpty)
        }
    }
}
