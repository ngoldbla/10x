// ConstraintDelegationTests — the assertions that fail *before* the golden
// corpus does.
//
// The golden corpus proves classic generation still emits the same bytes, which
// is the contract. But it proves it 56 seeds at a time and its failure message
// says "generation moved", not *where*. These tests pin the specific claim PRD-23
// made when it chose to thread a context through the solver instead of forking
// it: **a classic board runs against the shared empty context, and the shared
// empty context is the static `Sudoku` tables.** If that stops being true, this
// file names the reason in one line.
import XCTest
import Foundation
@testable import NineEngine

final class ConstraintDelegationTests: XCTestCase {

    func testAStateBuiltWithoutAContextGetsTheSharedClassicSingleton() {
        let state = CandidateState(grid: SolverTests.knownPuzzle)
        XCTAssertTrue(state.context === ConstraintContext.classic)
        XCTAssertTrue(state.context.isClassic)
    }

    /// Candidate seeding used to name `Sudoku.allDigitsMask` and `Sudoku.peers`
    /// directly. It now reads them off the context. Same numbers, cell by cell.
    func testClassicCandidateSeedingIsUnchangedCellByCell() {
        let grid = SolverTests.knownPuzzle
        let state = CandidateState(grid: grid)
        for cell in 0..<81 {
            guard grid[cell] == 0 else {
                XCTAssertEqual(state.candidates[cell], 0, "solved cell \(cell)")
                continue
            }
            var expected = Sudoku.allDigitsMask
            for peer in Sudoku.peers[cell] where grid[peer] != 0 {
                expected &= ~Sudoku.bit(grid[peer])
            }
            XCTAssertEqual(state.candidates[cell], expected, "cell \(cell)")
        }
    }

    /// Explicitly passing the classic context must be indistinguishable from
    /// passing nothing — trace included, not just the final grid. A solver
    /// change that still solves the board but explains it differently is exactly
    /// the drift the corpus exists to catch.
    func testPassingTheClassicContextExplicitlyChangesNothing() {
        let implicit = LogicSolver.solve(SolverTests.knownPuzzle)
        let explicit = LogicSolver.solve(SolverTests.knownPuzzle, context: .classic)
        XCTAssertEqual(implicit.solved, explicit.solved)
        XCTAssertEqual(implicit.finalGrid, explicit.finalGrid)
        XCTAssertEqual(implicit.steps, explicit.steps)
    }

    /// Compiling an *empty* rule list is the same object, so a variant board
    /// that happens to carry no rules costs classic nothing.
    func testAnEmptyRuleListSolvesDownTheClassicPath() {
        let context = ConstraintContext.compile([])
        XCTAssertTrue(context === ConstraintContext.classic)
        XCTAssertEqual(LogicSolver.solve(SolverTests.knownPuzzle, context: context).steps,
                       LogicSolver.solve(SolverTests.knownPuzzle).steps)
    }

    /// A cage adds peers, and a peer is the one thing that changes what a
    /// classic technique sees. This is the smallest demonstration that the
    /// shared loops really do read the wider table: two cells that are not
    /// classic peers, put in a cage together, now eliminate each other.
    func testACageWidensWhatTheSharedLoopsSee() {
        var grid = SudokuGrid()
        grid[0] = 5
        // Cells 0 and 80 share no row, column or box.
        XCTAssertEqual(CandidateState(grid: grid).candidates[80], Sudoku.allDigitsMask)

        let caged = ConstraintContext.compile([.cage(Cage(cells: [0, 80], sum: 11)!)])
        let state = CandidateState(grid: grid, context: caged)
        XCTAssertEqual(state.candidates[80], Sudoku.allDigitsMask & ~Sudoku.bit(5),
                       "a cage-mate's digit is eliminated by the same peer loop")
    }

    /// `place` reads the context too, not just the initialiser — the elimination
    /// has to keep travelling down cage edges as the solve proceeds.
    func testPlacementPropagatesDownCageEdgesToo() {
        let caged = ConstraintContext.compile([.cage(Cage(cells: [0, 80], sum: 11)!)])
        var state = CandidateState(grid: SudokuGrid(), context: caged)
        LogicSolver.apply(
            SolveStep(technique: .nakedSingle, cells: [0], digits: [7],
                      placement: Placement(cell: 0, digit: 7)),
            to: &state)
        XCTAssertEqual(state.candidates[80] & Sudoku.bit(7), 0)
    }

    func testStateEqualityIsAboutTheRulesNotThePointer() {
        let a = ConstraintContext.compile([.cage(Cage(cells: [0, 1], sum: 5)!)])
        let b = ConstraintContext.compile([.cage(Cage(cells: [0, 1], sum: 5)!)])
        XCTAssertFalse(a === b, "two compilations, two objects")
        XCTAssertEqual(CandidateState(grid: SudokuGrid(), context: a),
                       CandidateState(grid: SudokuGrid(), context: b))
        XCTAssertNotEqual(CandidateState(grid: SudokuGrid(), context: a),
                          CandidateState(grid: SudokuGrid()))
    }
}
