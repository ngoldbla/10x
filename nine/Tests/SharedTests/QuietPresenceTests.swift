// The quiet surfaces' payload and lifecycle (PRD-30).
//
// PRD-30's requirement is a negative: no timers, no countdowns, no
// streak-endangered nagging ever. Negatives are the hardest thing to keep,
// because nothing fails when one erodes — the app just quietly starts asking
// for attention. So the two tests that matter most here look at the encoded
// shape of the payload and at the source of the view, the way
// `VariantChannelSealTests` looks at the app layer.
import XCTest
@testable import NineShared

final class QuietPresenceTests: XCTestCase {

    private static let today = 9_400

    private func glyph(givens: Int, filled: Int) -> BoardGlyph {
        BoardGlyph(
            givenCells: 0..<givens,
            filledCells: (BoardGlyph.cellCount - filled)..<BoardGlyph.cellCount
        )
    }

    private func presence(
        day: Int = QuietPresenceTests.today,
        givens: Int = 30,
        filled: Int = 0
    ) -> DailyPresence {
        DailyPresence(
            dayOrdinal: day,
            bandID: "steady",
            glyph: glyph(givens: givens, filled: filled),
            revision: 3
        )
    }

    // MARK: - The glyph

    func testTheGlyphIsTwentyTwoBytesOfMaskAndAddressesAllEightyOneCells() {
        var given: [Int] = []
        var filled: [Int] = []
        for cell in 0..<81 where cell.isMultiple(of: 2) { given.append(cell) }
        for cell in 0..<81 where !cell.isMultiple(of: 2) { filled.append(cell) }
        let g = BoardGlyph(givenCells: given, filledCells: filled)

        XCTAssertEqual(g.given.count, BoardGlyph.maskBytes)
        XCTAssertEqual(g.filled.count, BoardGlyph.maskBytes)
        XCTAssertEqual(g.given.count + g.filled.count, 22)

        // Every cell, not just the first byte — an off-by-one in the shift lands
        // on cell 8 and nowhere a spot check would look.
        for cell in 0..<81 {
            XCTAssertEqual(g.isGiven(cell), cell.isMultiple(of: 2), "given \(cell)")
            XCTAssertEqual(g.isFilled(cell), !cell.isMultiple(of: 2), "filled \(cell)")
            XCTAssertFalse(g.isEmpty(cell), "cell \(cell) is claimed by one mask")
        }
        XCTAssertEqual(g.givenCount, 41)
        XCTAssertEqual(g.filledCount, 40)
        XCTAssertTrue(g.isComplete)
    }

    /// Cell 81 and above do not exist; asking must be false rather than a trap.
    /// A Live Activity's payload arrives from the system after a possible app
    /// update, so a reader has to survive numbers a writer would never produce.
    func testOutOfRangeCellsAreFalseAndNeverCrash() {
        let g = glyph(givens: 81, filled: 0)
        for cell in [-1, 81, 88, 1_000, Int.max, Int.min] {
            XCTAssertFalse(g.isGiven(cell))
            XCTAssertFalse(g.isFilled(cell))
            XCTAssertTrue(g.isEmpty(cell))
        }
    }

    /// A short or long mask — a hand-edited blob, or a future shape — is clamped
    /// on the way in, so no reader can index off the end of it.
    func testMasksAreNormalisedToLength() {
        XCTAssertEqual(BoardGlyph(given: [], filled: [1, 2, 3]).given.count, 11)
        XCTAssertEqual(BoardGlyph(given: [], filled: [1, 2, 3]).filled.count, 11)
        let over = BoardGlyph(
            given: [UInt8](repeating: 0xFF, count: 40),
            filled: [UInt8](repeating: 0xFF, count: 40)
        )
        XCTAssertEqual(over.given.count, 11)
        // 11 bytes of 0xFF is 88 bits, of which only 81 are addressable — the
        // count is a popcount of the stored bytes, so it reports 88. What matters
        // is that nothing indexes past the array; `isGiven` clamps the question.
        XCTAssertFalse(over.isGiven(81))
    }

    func testAnUntouchedBoardIsNotTouchedAndOneMarkMakesItSo() {
        XCTAssertFalse(glyph(givens: 30, filled: 0).isTouched)
        XCTAssertTrue(glyph(givens: 30, filled: 1).isTouched)
    }

    // MARK: - The seal: no clock, no streak

    /// The headline requirement of PRD-30, asserted against the encoded keys
    /// rather than against a comment. A `Date` or a `TimeInterval` in this
    /// payload is a countdown waiting for someone to render it.
    func testThePresencePayloadCarriesNoClockAndNoStreak() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(presence(filled: 4))
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys), ["dayOrdinal", "bandID", "glyph", "revision"],
            """
            DailyPresence gained a field. PRD-30 forbids timers, countdowns and \
            streak nagging on the quiet surfaces, and the cheapest way to keep \
            that promise is for the payload to have nothing to render. If the \
            new field is a Date, a TimeInterval, an elapsed count or anything \
            named streak, it does not belong here.
            """
        )

        // And the same statement at the type level, so a nested field cannot
        // sneak a clock in inside `glyph`.
        let json = try XCTUnwrap(String(data: data, encoding: .utf8)).lowercased()
        for word in ["date", "time", "elapsed", "second", "streak", "remaining", "deadline"] {
            XCTAssertFalse(json.contains(word), "encoded payload names \"\(word)\"")
        }
    }

    /// ActivityKit hands a running activity's *previously encoded* content state
    /// back after an app update, so this type meets its own past shape the way a
    /// `CouchStored` blob does — and must not throw when it does.
    func testAPayloadFromAnOlderShapeDecodesToADrawableDefault() throws {
        let older = Data(#"{"dayOrdinal":9400}"#.utf8)
        let decoded = try JSONDecoder().decode(DailyPresence.self, from: older)
        XCTAssertEqual(decoded.dayOrdinal, 9_400)
        XCTAssertEqual(decoded.bandID, "")
        XCTAssertEqual(decoded.glyph, .blank)
        XCTAssertEqual(decoded.revision, 0)

        // Junk in the glyph slot degrades to blank rather than throwing.
        let junk = Data(#"{"dayOrdinal":1,"glyph":"nope","revision":"two"}"#.utf8)
        let salvaged = try JSONDecoder().decode(DailyPresence.self, from: junk)
        XCTAssertEqual(salvaged.glyph, .blank)
        XCTAssertEqual(salvaged.revision, 0)
    }

    // MARK: - The lifecycle

    func testNothingStartsUntilThePlayerHasTouchedTheBoard() {
        // On the shelf, board untouched, app in the background: no activity.
        XCTAssertEqual(
            PresencePolicy.decide(
                enabled: true, presence: presence(filled: 0), solved: false,
                foreground: false, live: false, today: Self.today
            ),
            .leave,
            "an untouched board is not a bookmark, it is an advert"
        )
        let touched = presence(filled: 1)
        XCTAssertEqual(
            PresencePolicy.decide(
                enabled: true, presence: touched, solved: false,
                foreground: false, live: false, today: Self.today
            ),
            .start(touched)
        )
    }

    func testNothingStartsWhileThePlayerIsLookingAtTheApp() {
        let touched = presence(filled: 5)
        XCTAssertEqual(
            PresencePolicy.decide(
                enabled: true, presence: touched, solved: false,
                foreground: true, live: false, today: Self.today
            ),
            .leave,
            "start-and-leave: the leaving is half the feature"
        )
        // But a running one keeps tracking, so a phone locked mid-move shows the
        // board that was actually left.
        XCTAssertEqual(
            PresencePolicy.decide(
                enabled: true, presence: touched, solved: false,
                foreground: true, live: true, today: Self.today
            ),
            .update(touched)
        )
    }

    func testSolvingEndsItAndNeverCongratulatesOnTheLockScreen() {
        XCTAssertEqual(
            PresencePolicy.decide(
                enabled: true, presence: presence(filled: 9), solved: true,
                foreground: false, live: true, today: Self.today
            ),
            .end
        )
        // A board full but not yet recorded (a widget solve the app has not
        // ingested) is the same case, reached by a different route.
        XCTAssertEqual(
            PresencePolicy.decide(
                enabled: true, presence: presence(givens: 30, filled: 51),
                solved: false, foreground: false, live: true, today: Self.today
            ),
            .end
        )
    }

    /// Midnight ends yesterday's activity and does **not** replace it with
    /// today's. "Here is a new puzzle" at midnight is the nag PRD-13's grace
    /// exists so Nine never has to send.
    func testDayRolloverEndsAndDoesNotReplace() {
        let yesterday = presence(day: Self.today - 1, filled: 6)
        XCTAssertEqual(
            PresencePolicy.decide(
                enabled: true, presence: yesterday, solved: false,
                foreground: false, live: true, today: Self.today
            ),
            .end
        )
        XCTAssertEqual(
            PresencePolicy.decide(
                enabled: true, presence: nil, solved: false,
                foreground: false, live: false, today: Self.today
            ),
            .leave
        )
    }

    func testThePrefIsAHardStopInEveryOtherwiseLiveCase() {
        for (solved, foreground, live) in [
            (false, false, true), (false, true, true), (true, false, true),
        ] {
            XCTAssertEqual(
                PresencePolicy.decide(
                    enabled: false, presence: presence(filled: 4), solved: solved,
                    foreground: foreground, live: live, today: Self.today
                ),
                .end,
                "solved \(solved) foreground \(foreground)"
            )
        }
        XCTAssertEqual(
            PresencePolicy.decide(
                enabled: false, presence: presence(filled: 4), solved: false,
                foreground: false, live: false, today: Self.today
            ),
            .leave
        )
    }

    /// Erasing back to an empty board dims the glyph; it does not make the
    /// activity vanish. Disappearance is a louder event on a Lock Screen than any
    /// change of content, and the player did not ask for one.
    func testErasingToEmptyKeepsARunningActivityRatherThanVanishing() {
        let emptied = presence(filled: 0)
        XCTAssertEqual(
            PresencePolicy.decide(
                enabled: true, presence: emptied, solved: false,
                foreground: false, live: true, today: Self.today
            ),
            .update(emptied)
        )
    }
}
