// SolveCardFactsTests — the words on the share card (PRD-12 §2).
//
// The card leaves the app as a PNG and is then seen only where nobody here can
// correct it, so its captions are pinned rather than previewed.
import XCTest
@testable import NineShared
@testable import NineEngine

final class SolveCardFactsTests: XCTestCase {

    /// A finished board, with a paused timer so `elapsed(at:)` is a fact rather
    /// than a race against the test's own wall clock.
    private func solvedGame(seconds: TimeInterval = 220) -> NineGame {
        let puzzle = PuzzleGenerator.generate(seed: 4_242, difficulty: .steady)
        var game = NineGame(puzzle: puzzle)
        for cell in 0..<81 where !game.isGiven(cell) {
            _ = game.place(puzzle.solution[cell], at: cell)
        }
        game.timer.start(at: Date(timeIntervalSinceReferenceDate: 0))
        game.timer.pause(at: Date(timeIntervalSinceReferenceDate: seconds))
        return game
    }

    private func facts(
        difficulty: Difficulty = .steady, isDaily: Bool = false, streak: Int = 0,
        seconds: TimeInterval = 220
    ) -> SolveCardFacts {
        SolveCardFacts(
            game: solvedGame(seconds: seconds),
            difficulty: difficulty, isDaily: isDaily, streak: streak,
            at: Date(timeIntervalSinceReferenceDate: seconds)
        )
    }

    // MARK: - The clock

    func testTimeLineReadsAsMinutesAndSeconds() {
        XCTAssertEqual(SolveCardFacts.elapsedText(220), "3:40")
        XCTAssertEqual(SolveCardFacts.elapsedText(9), "0:09")
        XCTAssertEqual(SolveCardFacts.elapsedText(0), "0:00")
        XCTAssertEqual(SolveCardFacts.elapsedText(3_725), "62:05", "no hours field; minutes run on")
        XCTAssertEqual(SolveCardFacts.elapsedText(-5), "0:00", "a clock skew cannot print a minus")
    }

    /// The card's time comes from the board's own timer, not from how long ago
    /// the solve happened — share it an hour later and it still says 3:40.
    func testTimeLineComesFromTheGameTimerNotTheWallClock() {
        let game = solvedGame(seconds: 220)
        let late = SolveCardFacts(
            game: game, difficulty: .steady, isDaily: false, streak: 0,
            at: Date(timeIntervalSinceReferenceDate: 99_999)
        )
        XCTAssertEqual(late.timeLine, "Solved in 3:40")
    }

    // MARK: - The credit line

    func testCreditLineCarriesTheStreakOnlyWhenThereIsOne() {
        XCTAssertEqual(
            facts(difficulty: .steady, isDaily: true, streak: 12).creditLine,
            "Steady · 12 day streak"
        )
        XCTAssertEqual(
            facts(difficulty: .steady, isDaily: true, streak: 0).creditLine,
            "Steady", "PRD-12 §2: the streak line appears only above zero"
        )
    }

    /// PRD-12 §2 scopes the streak line to dailies. A free-play board solved in
    /// the middle of a 30-day run has not advanced it, and the card must not
    /// imply it did.
    func testFreePlayNeverBorrowsTheStreak() {
        let free = facts(difficulty: .gentle, isDaily: false, streak: 30)
        XCTAssertEqual(free.creditLine, "Gentle")
        XCTAssertNil(free.dailyLine)
    }

    /// Every band names itself, and names itself in *words*.
    ///
    /// This used to assert against `difficulty.title`, which the Engine no
    /// longer has (PRD-20: the Engine emits IDs and names nothing). Asserting
    /// against `EnglishPhrases.table` instead is not the same test rewritten —
    /// it is the test that survives, because `creditLine` and the table are now
    /// two sides of one lookup rather than two copies of one word. The
    /// `hasPrefix` clause is what stops it being circular: if the row went
    /// missing, both sides would be the string `"difficulty.sharp.title"` and a
    /// plain equality would still pass.
    func testEveryDifficultyNamesItself() throws {
        for difficulty in Difficulty.allCases {
            let key = "difficulty.\(difficulty.rawValue).title"
            let expected = try XCTUnwrap(EnglishPhrases.table[key], "no English for \(key)")
            XCTAssertEqual(
                facts(difficulty: difficulty).creditLine, expected,
                "a card for a \(difficulty) board must say so"
            )
            XCTAssertFalse(expected.hasPrefix("difficulty."),
                           "\(key) resolved to its own key — the missing-key fallback in disguise")
        }
    }

    // MARK: - The daily line and the hook

    func testDailyGetsItsSecondLineAndNoURLAnywhere() {
        let daily = facts(isDaily: true, streak: 1)
        XCTAssertEqual(daily.dailyLine, "Nine · daily puzzle")
        for text in [daily.shareTitle, daily.creditLine, daily.dailyLine ?? ""] {
            XCTAssertFalse(text.contains("http"), "no URL spam (PRD-12 §2): \(text)")
            XCTAssertFalse(text.lowercased().contains("app store"), text)
            XCTAssertFalse(text.lowercased().contains("download"), text)
        }
    }

    func testShareTitleLeadsWithTheWordmark() {
        XCTAssertEqual(facts().shareTitle, "NINE · Solved in 3:40")
    }

    // MARK: - The grid

    func testGridCarriesEveryDigitAndKnowsTheGivens() {
        let game = solvedGame()
        let card = SolveCardFacts(
            game: game, difficulty: .steady, isDaily: false, streak: 0,
            at: Date(timeIntervalSinceReferenceDate: 220)
        )
        XCTAssertEqual(card.digits.count, 81)
        XCTAssertEqual(card.givens.count, 81)
        XCTAssertFalse(card.digits.contains(0), "a card is only ever made of a solved board")
        XCTAssertEqual(
            card.givens.filter { $0 }.count,
            (0..<81).filter { game.puzzle.puzzle[$0] != 0 }.count,
            "the givens on the card are the puzzle's givens"
        )
        XCTAssertTrue(
            card.givens.contains(false),
            "and some of the board was the player's, or there is nothing to be proud of"
        )
    }

    /// The picture must be the board that was played, cell for cell.
    func testGridMatchesTheSolvedBoardCellForCell() {
        let game = solvedGame()
        let card = SolveCardFacts(
            game: game, difficulty: .steady, isDaily: false, streak: 0,
            at: Date(timeIntervalSinceReferenceDate: 220)
        )
        for cell in 0..<81 {
            XCTAssertEqual(card.digits[cell], game.entry(at: cell), "cell \(cell)")
            XCTAssertEqual(card.givens[cell], game.isGiven(cell), "cell \(cell)")
        }
    }
}
