// DuelCreditsTests.swift — the debrief credits both hands, and never ranks them.
import XCTest
@testable import NineShared
#if canImport(NineEngine)
import NineEngine
#endif

final class DuelCreditsTests: XCTestCase {

    /// A grid where cell N holds (N % 9) + 1. Not a legal sudoku, and it does
    /// not need to be: `DuelCredits` compares a digit to a grid and knows
    /// nothing about rules.
    private let solution = (0..<81).map { ($0 % 9) + 1 }

    private func place(_ cell: Int, _ digit: Int) -> LoggedMove {
        LoggedMove(kind: .place, cell: cell, digit: digit)
    }

    /// Player 0 owns moves 0…2, player 1 owns 3 onwards.
    private func twoTurns() -> DuelState {
        var s = DuelState(accents: ["glacier", "ember"], turnLength: .standard)
        s.beginTurn(player: 0, firstMoveIndex: 0, startedAt: 0)
        s.beginTurn(player: 1, firstMoveIndex: 3, startedAt: 90)
        return s
    }

    // MARK: - Credit

    func testCorrectPlacementsAreCreditedToTheTurnTheyLandedIn() {
        let moves = [place(0, 1), place(1, 2), place(2, 3), place(3, 4), place(4, 5)]
        let credits = DuelCredits(state: twoTurns(), moves: moves, solution: solution)
        XCTAssertEqual(credits.placed, [3, 2])
        XCTAssertEqual(credits.cleared, [0, 0])
    }

    /// Per attempt, which is `NineGame.errorCount`'s own definition: three
    /// wrong tries at one cell is three.
    func testEachWrongAttemptCountsSeparately() {
        let moves = [place(0, 9), place(0, 8), place(0, 1), place(3, 7), place(3, 4)]
        let credits = DuelCredits(state: twoTurns(), moves: moves, solution: solution)
        XCTAssertEqual(credits.cleared, [2, 1])
        XCTAssertEqual(credits.placed, [1, 1])
    }

    func testErasesAndNotesAndUndosAreCreditedToNobody() {
        let moves = [
            place(0, 1),
            LoggedMove(kind: .erase, cell: 0, digit: 1),
            LoggedMove(kind: .pencil, cell: 5, digit: 3),
            LoggedMove(kind: .undo, cell: 0, digit: 1),
        ]
        let credits = DuelCredits(state: twoTurns(), moves: moves, solution: solution)
        XCTAssertEqual(credits.placed, [1, 0])
        XCTAssertEqual(credits.cleared, [0, 0])
    }

    func testTheLastDigitIsTheLastCorrectPlacement() {
        // Four moves, so index 3 actually crosses player 1's boundary — with
        // three the whole log sits inside player 0's turn and the assertion
        // cannot fail for the reason it is written to catch.
        let moves = [place(0, 1), place(1, 2), place(2, 3), place(3, 4), place(4, 9)]
        XCTAssertEqual(
            DuelCredits(state: twoTurns(), moves: moves, solution: solution).lastPlayer, 1,
            "the wrong digit at the end does not steal the credit")
    }

    func testTheLastDigitIsNilWhenNobodyPlacedACorrectOne() {
        XCTAssertNil(DuelCredits(state: twoTurns(), moves: [place(0, 9)], solution: solution).lastPlayer)
    }

    func testAnEmptyLogCreditsNobodyAndIsEmpty() {
        let credits = DuelCredits(state: twoTurns(), moves: [], solution: solution)
        XCTAssertEqual(credits.placed, [0, 0])
        XCTAssertNil(credits.lastPlayer)
        XCTAssertTrue(credits.isEmpty)
    }

    func testAnOutOfRangeCellOrShortSolutionIsSkippedRatherThanTrapping() {
        let moves = [place(0, 1), place(500, 4), place(-1, 2)]
        let credits = DuelCredits(state: twoTurns(), moves: moves, solution: [])
        XCTAssertEqual(credits.placed, [0, 0])
        XCTAssertEqual(credits.cleared, [0, 0])
    }

    func testMovesBeforeAnyTurnAreCreditedToNobody() {
        let s = DuelState(accents: ["glacier", "ember"], turnLength: .brisk)
        XCTAssertEqual(DuelCredits(state: s, moves: [place(0, 1)], solution: solution).placed, [0, 0])
    }

    /// The type carries nothing anyone could sort on — PRD-27 §7's "no winner
    /// is ever declared", asserted against the shape rather than the wording.
    func testTheTypeExposesNoTotalAndNoRanking() {
        let credits = DuelCredits(state: twoTurns(), moves: [place(0, 1)], solution: solution)
        let mirror = Mirror(reflecting: credits)
        XCTAssertEqual(
            Set(mirror.children.compactMap(\.label)), ["placed", "cleared", "lastPlayer"],
            "a new stored property here is a new thing two people can compare — "
            + "if it is a score, PRD-27 §7 forbids it")
    }

    // MARK: - The cell → owner map that feeds the tint

    func testOwnersCreditsEachFilledCellToTheSeatThatFilledIt() {
        let moves = [place(0, 1), place(1, 2), place(2, 3), place(3, 4)]
        let owners = DuelCredits.owners(state: twoTurns(), moves: moves)
        XCTAssertEqual(owners[0], 0)
        XCTAssertEqual(owners[2], 0)
        XCTAssertEqual(owners[3], 1)
        XCTAssertNil(owners[80], "an untouched cell has no owner")
    }

    func testAnErasedCellLosesItsOwner() {
        let moves = [place(0, 1), LoggedMove(kind: .erase, cell: 0, digit: 1)]
        XCTAssertNil(DuelCredits.owners(state: twoTurns(), moves: moves)[0])
    }

    /// The quiet correction is exactly this shape: place, then erase at the
    /// hand-off. The cell must come back ownerless so the next player's digit
    /// wears their tint and not the previous player's.
    func testTheQuietCorrectionLeavesTheCellReadyForTheNextPlayer() {
        var s = DuelState(accents: ["glacier", "ember"], turnLength: .standard)
        s.beginTurn(player: 0, firstMoveIndex: 0, startedAt: 0)
        let moves = [
            place(0, 9),                                   // player 0 places a wrong digit
            LoggedMove(kind: .erase, cell: 0, digit: 9),   // cleared at hand-off, still player 0's range
        ]
        var handed = s
        handed.beginTurn(player: 1, firstMoveIndex: 2, startedAt: 90)
        XCTAssertNil(DuelCredits.owners(state: handed, moves: moves)[0])
        XCTAssertEqual(
            DuelCredits(state: handed, moves: moves, solution: solution).cleared, [1, 0],
            "the clearing is credited to the player who made the mistake, not the one arriving")
    }

    func testOverwritingAnotherSeatsDigitTransfersTheCell() {
        let moves = [place(5, 1), place(5, 6)]
        XCTAssertEqual(DuelCredits.owners(state: twoTurns(), moves: moves)[5], 0)
        var s = DuelState(accents: ["glacier", "ember"], turnLength: .standard)
        s.beginTurn(player: 0, firstMoveIndex: 0, startedAt: 0)
        s.beginTurn(player: 1, firstMoveIndex: 1, startedAt: 90)
        XCTAssertEqual(DuelCredits.owners(state: s, moves: moves)[5], 1)
    }

    func testANoteNeverOwnsACell() {
        let moves = [LoggedMove(kind: .pencil, cell: 7, digit: 3)]
        XCTAssertNil(DuelCredits.owners(state: twoTurns(), moves: moves)[7],
                     "a pencil mark is tentative — it is not a claim on the square")
    }
}
