// CoachTests — the explainable-hint seam (PRD-11 11a). These pin the two
// properties the coach is worthless without: it never speaks from the proven
// solution, and every unit it names is one the deduction actually used.
import XCTest
import CouchCore
@testable import NineEngine

final class CoachTests: XCTestCase {

    private var puzzle: GeneratedPuzzle!

    override func setUp() {
        super.setUp()
        // One generate() for the whole suite: `swift test` reads ~112 s against
        // a ~120 s budget, and composing per test is how that budget goes.
        puzzle = PuzzleGenerator.generate(seed: 1, difficulty: .gentle)
    }

    // MARK: - Advice selection

    func testNakedSingleIsOfferedForASingleHole() {
        var grid = puzzle.solution
        grid[40] = 0
        guard case .step(let coach) = LogicSolver.advice(for: grid) else {
            return XCTFail("a one-hole grid must yield a step")
        }
        XCTAssertEqual(coach.step.technique, .nakedSingle)
        XCTAssertEqual(coach.step.placement?.cell, 40)
        XCTAssertEqual(coach.step.placement?.digit, puzzle.solution[40])
        XCTAssertNil(coach.patternUnit, "a naked single is cell-scoped, not unit-scoped")
        XCTAssertNil(coach.targetUnit, "a naked single eliminates nothing")
    }

    func testFullConsistentGridIsSolved() {
        XCTAssertEqual(LogicSolver.advice(for: puzzle.solution), .solved)
    }

    func testEmptyGridIsNeitherSolvedNorContradictory() {
        // Nothing follows from an empty grid, but nothing is wrong with it
        // either — the two "no step" answers must stay distinguishable.
        XCTAssertEqual(LogicSolver.advice(for: SudokuGrid()), .exhausted)
    }

    // MARK: - Contradiction: pure logic, never the solution

    func testPeerClashIsReportedAndBothCellsNamed() {
        var grid = SudokuGrid()
        grid[0] = 7
        grid[5] = 7 // same row
        guard case .contradiction(let cells) = LogicSolver.advice(for: grid) else {
            return XCTFail("duplicate peers must read as a contradiction")
        }
        XCTAssertEqual(cells, [0, 5])
    }

    func testDeadCellIsReportedWhenNoPeerClashExists() {
        // Cell 0's row holds 1...8 and its column holds the 9. Nothing can go
        // in cell 0, and no digit repeats in any unit — so this is a
        // contradiction only the candidate pass can see.
        var grid = SudokuGrid()
        for column in 1...8 { grid[column] = column }
        grid[9] = 9
        XCTAssertTrue(grid.conflictingCells.isEmpty, "no digit repeats in any unit")
        guard case .contradiction(let cells) = LogicSolver.advice(for: grid) else {
            return XCTFail("a dead cell must read as a contradiction")
        }
        XCTAssertEqual(cells, [0], "cell 0 is the one with no candidates left")
    }

    func testContradictionIsCheckedBeforeAnyStepIsOffered() {
        var grid = puzzle.puzzle
        // A gentle board has plenty of legal singles standing; break it with a
        // duplicate peer and the coach must decline rather than hint on.
        let clash = (0..<81).lazy.compactMap { filled -> (Int, Int)? in
            guard grid[filled] != 0,
                  let peer = Sudoku.peers[filled].first(where: { grid[$0] == 0 })
            else { return nil }
            return (filled, peer)
        }.first
        guard let clash else { return XCTFail("no filled cell with an empty peer") }
        grid[clash.1] = grid[clash.0]
        guard case .contradiction(let cells) = LogicSolver.advice(for: grid) else {
            return XCTFail("a contradictory board must never be handed a step")
        }
        XCTAssertTrue(cells.contains(clash.1))
    }

    func testContradictionNeverConsultsTheSolution() {
        // A wrong digit that contradicts nothing on the board yet is invisible
        // to the coach — which is the point. `NineGame.isError` would see it.
        var grid = puzzle.puzzle
        let hole = (0..<81).first { grid[$0] == 0 }!
        let wrong = (1...9).first { digit in
            digit != puzzle.solution[hole]
                && !Sudoku.peers[hole].contains { grid[$0] == digit }
        }
        guard let wrong else { return XCTFail("no legal-but-wrong digit available") }
        grid[hole] = wrong
        XCTAssertNotEqual(wrong, puzzle.solution[hole], "the digit really is wrong")
        if case .contradiction = LogicSolver.advice(for: grid) {
            XCTFail("the coach may only report contradictions the board itself shows")
        }
    }

    // MARK: - The band ceiling

    func testAdviceNeverExceedsTheAllowedTechniques() {
        var grid = puzzle.puzzle
        var seen: Set<Technique> = []
        for _ in 0..<200 {
            guard case .step(let coach) = LogicSolver.advice(
                for: grid, allowed: [.nakedSingle]
            ) else { break }
            seen.insert(coach.step.technique)
            guard let placement = coach.step.placement else { break }
            grid[placement.cell] = placement.digit
        }
        XCTAssertFalse(seen.isEmpty, "a gentle board must offer at least one naked single")
        XCTAssertEqual(seen, [.nakedSingle], "nothing outside `allowed` may ever be offered")
    }

    func testExhaustedWhenNothingFollowsInsideTheCeiling() {
        // Strip the board back to a position no naked single closes, and ask
        // with naked singles only.
        var grid = SudokuGrid()
        grid[0] = 1
        grid[1] = 2
        XCTAssertEqual(LogicSolver.advice(for: grid, allowed: [.nakedSingle]), .exhausted)
    }

    // MARK: - The units the sentences will name

    func testEveryDerivedUnitIsOneTheDeductionActuallyUsed() {
        // Walk a real board and check both invariants on every step it offers.
        // A sentence naming a unit the pattern does not live in would be a
        // confident falsehood, which is worse than no coach at all.
        var grid = puzzle.puzzle
        var steps = 0
        for _ in 0..<200 {
            guard case .step(let coach) = LogicSolver.advice(for: grid) else { break }
            steps += 1

            if let target = coach.targetUnit {
                let unit = Set(Sudoku.units[target])
                XCTAssertTrue(
                    unit.isSuperset(of: Set(coach.step.cells)),
                    "\(coach.step.technique): targetUnit must contain the pattern"
                )
                XCTAssertTrue(
                    unit.isSuperset(of: Set(coach.step.eliminations.map(\.cell))),
                    "\(coach.step.technique): targetUnit must contain every elimination"
                )
            }

            if let pattern = coach.patternUnit {
                XCTAssertNotEqual(pattern, coach.targetUnit, "the two units are distinct")
                if coach.step.technique == .hiddenSingle, let cell = coach.step.cells.first {
                    XCTAssertTrue(
                        Sudoku.unitsOfCell[cell].contains(pattern),
                        "a hidden single's unit must be one of its own cell's three"
                    )
                } else {
                    XCTAssertTrue(
                        Set(Sudoku.units[pattern]).isSuperset(of: Set(coach.step.cells)),
                        "\(coach.step.technique): patternUnit must contain the pattern"
                    )
                }
            }

            guard let placement = coach.step.placement else {
                // An eliminating step changes no entry, so applying it here
                // would loop forever; the invariants above are what matter.
                break
            }
            grid[placement.cell] = placement.digit
        }
        XCTAssertGreaterThan(steps, 0, "the walk must actually exercise some steps")
    }

    func testHiddenSingleNamesTheUnitInWhichTheDigitHasOneHome() {
        // Row 0 has eight givens, so its ninth digit has exactly one home —
        // but cell 8 also has only one candidate, so ask with hidden singles
        // only to force the technique under test.
        var grid = SudokuGrid()
        for column in 0...7 { grid[column] = column + 1 }
        guard case .step(let coach) = LogicSolver.advice(
            for: grid, allowed: [.hiddenSingle]
        ) else {
            return XCTFail("row 0's missing 9 is a hidden single")
        }
        XCTAssertEqual(coach.step.technique, .hiddenSingle)
        XCTAssertEqual(coach.step.placement, Placement(cell: 8, digit: 9))
        XCTAssertEqual(coach.patternUnit, 0, "row 0 is unit 0")
    }
}
