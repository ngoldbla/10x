// DuelHandoffTests.swift — when a turn ends, and what that costs (PRD-27 §4.1).
//
// These six cases are the whole of the rule. They live here rather than in the
// App layer because `DuelHandoff.decide` is pure, which is what lets the two
// surfaces (Apple TV and the drafting table) share one answer instead of each
// re-deriving it in a view.
import XCTest
@testable import NineShared

final class DuelHandoffTests: XCTestCase {

    private func input(
        remaining: TimeInterval? = 30,
        roseOpen: Bool = false,
        solved: Bool = false,
        untimed: Bool = false,
        placedThisTurn: Int = 0
    ) -> DuelHandoff.Input {
        DuelHandoff.Input(
            remaining: untimed ? nil : remaining,
            isUntimed: untimed,
            roseOpen: roseOpen,
            boardSolved: solved,
            placementsThisTurn: placedThisTurn
        )
    }

    func testATurnWithTimeLeftContinues() {
        XCTAssertEqual(DuelHandoff.decide(input()), .continue)
    }

    func testAnExpiredTurnHandsOff() {
        XCTAssertEqual(DuelHandoff.decide(input(remaining: 0)), .handOff)
    }

    /// PRD-27 §4.1 — a digit you did not confirm is not yours.
    func testAnExpiredTurnWithTheRoseOpenClosesTheRoseFirst() {
        XCTAssertEqual(DuelHandoff.decide(input(remaining: 0, roseOpen: true)), .closeRoseThenHandOff)
    }

    /// PRD-27 §4.1 — a solved board goes straight to Afterglow. A hand-off card
    /// drawn over the celebration is the one outcome that is definitely wrong.
    func testASolvedBoardNeverHandsOff() {
        XCTAssertEqual(DuelHandoff.decide(input(remaining: 0, solved: true)), .finish)
        XCTAssertEqual(DuelHandoff.decide(input(remaining: 30, solved: true)), .finish)
        XCTAssertEqual(DuelHandoff.decide(input(remaining: 0, roseOpen: true, solved: true)), .finish)
        XCTAssertEqual(
            DuelHandoff.decide(input(solved: true, untimed: true, placedThisTurn: 1)), .finish,
            "solved outranks the untimed turn's own end condition too")
    }

    /// PRD-27 §4.2 — VoiceOver and Switch Control suspend the deadline; the turn
    /// ends when the player places a digit instead.
    func testAnUntimedTurnEndsOnAPlacementAndNotBefore() {
        XCTAssertEqual(DuelHandoff.decide(input(untimed: true, placedThisTurn: 0)), .continue)
        XCTAssertEqual(DuelHandoff.decide(input(untimed: true, placedThisTurn: 1)), .handOff)
    }

    func testAnUntimedTurnIgnoresTheClockEntirely() {
        XCTAssertEqual(
            DuelHandoff.decide(input(remaining: 0, untimed: true, placedThisTurn: 0)), .continue,
            "with no deadline there is nothing for an expired clock to mean")
    }

    /// A turn that has not begun has no deadline yet — `remaining` is nil before
    /// the first `beginTurn`, and that must read as "not yet", never as "over".
    func testATurnThatHasNotBegunDoesNotHandOff() {
        XCTAssertEqual(
            DuelHandoff.decide(input(remaining: nil)), .continue,
            "nil remaining is a duel that has not started, not one that has run out")
    }

    /// Total: every combination returns something, and nothing traps.
    func testEveryCombinationIsTotal() {
        for remaining in [nil, 0, 0.5, 90] as [TimeInterval?] {
            for untimed in [true, false] {
                for rose in [true, false] {
                    for solved in [true, false] {
                        for placed in [0, 1, 5] {
                            _ = DuelHandoff.decide(DuelHandoff.Input(
                                remaining: remaining, isUntimed: untimed, roseOpen: rose,
                                boardSolved: solved, placementsThisTurn: placed))
                        }
                    }
                }
            }
        }
    }
}
