// VariantTechniqueTests — cage and thermometer reasoning.
//
// The fixtures below name each technique's shape, but the assertion that
// actually protects the engine is `testNoVariantDeductionEverContradictsTheGrid`
// at the bottom: a seeded fuzz that builds cages and thermometers *from a known
// complete grid*, solves, and checks that every placement agrees with that grid
// and every elimination removes a digit the grid does not have there.
//
// That works without needing the fuzzed positions to be unique, and the reason
// is worth stating: a sound technique only ever deduces what is true in *every*
// solution, so it cannot place a digit that differs between two of them — it
// simply makes no deduction there at all. An unsound one, by contrast, will
// eventually place a digit the grid contradicts. Which is the failure mode that
// matters here: a wrong variant technique produces boards that the uniqueness
// prover still calls unique, because the prover would have to be wrong in the
// same way to disagree.
import XCTest
import Foundation
import CouchCore
@testable import NineEngine

final class VariantTechniqueTests: XCTestCase {

    private func context(_ constraints: VariantConstraint...) -> ConstraintContext {
        ConstraintContext.compile(constraints)
    }

    private func cage(_ cells: [Int], _ sum: Int) -> VariantConstraint {
        .cage(Cage(cells: cells, sum: sum)!)
    }

    private func thermo(_ cells: [Int]) -> VariantConstraint {
        .thermometer(Thermometer(cells: cells)!)
    }

    // MARK: - Probe order

    /// `nextStep` walks `probeOrder`, so a technique missing from it is a
    /// technique that silently never runs, and a duplicated one runs twice.
    func testProbeOrderHoldsEveryTechniqueExactlyOnce() {
        for order in [ConstraintContext.classic.probeOrder,
                      context(cage([0, 1], 5)).probeOrder] {
            XCTAssertEqual(Set(order), Set(Technique.allCases))
            XCTAssertEqual(order.count, Technique.allCases.count)
        }
    }

    /// Classic's probe order is literally what `nextStep` iterated before
    /// PRD-23 — the same list, in the same rank order.
    func testClassicProbeOrderIsUnchanged() {
        XCTAssertEqual(ConstraintContext.classic.probeOrder, Technique.allCases)
        XCTAssertEqual(Technique.allCases.prefix(6),
                       [.nakedSingle, .hiddenSingle, .nakedPair,
                        .hiddenPair, .boxLineReduction, .xWing],
                       "the six classic cases and their order are frozen")
        XCTAssertTrue(Technique.allCases.prefix(6).allSatisfy(\.isClassic))
        // PRD-25 broke the "everything after the sixth is a variant" reading of
        // this list, and deliberately: rank is append-only, so its four classic
        // techniques sort *above* PRD-23's four variant ones. What is still
        // true — and is the thing this file actually needs — is that the four
        // variant cases are the only non-classic ones, named rather than
        // counted, so appending another classic technique cannot quietly widen
        // the set of things a killer board's `minVariantSteps` counts.
        XCTAssertEqual(
            Set(Technique.allCases.filter { !$0.isClassic }),
            [.cageSingle, .thermoBound, .innieOutie, .cageCombination])
    }

    /// Classic's technique band cannot reach a variant technique by rank, which
    /// is the second of the two independent reasons generation is unaffected.
    func testNoDifficultyBandAllowsAVariantTechnique() {
        for difficulty in Difficulty.allCases {
            XCTAssertTrue(difficulty.allowedTechniques.allSatisfy(\.isClassic),
                          "\(difficulty) reached a variant technique")
        }
    }

    // MARK: - Cage single

    func testCageSinglePlacesTheLastCellOfACage() {
        var grid = SudokuGrid()
        grid[0] = 2
        grid[1] = 3
        let state = CandidateState(grid: grid, context: context(cage([0, 1, 2], 12)))
        let step = LogicSolver.nextStep(in: state, allowed: [.cageSingle])
        XCTAssertEqual(step?.technique, .cageSingle)
        XCTAssertEqual(step?.placement, Placement(cell: 2, digit: 7))
        XCTAssertEqual(step?.cells, [0, 1, 2], "the whole cage is the pattern the coach shows")
    }

    /// A one-cell cage is its own sum, with nothing placed at all.
    func testAOneCellCageIsImmediatelyForced() {
        let state = CandidateState(grid: SudokuGrid(), context: context(cage([40], 4)))
        XCTAssertEqual(LogicSolver.nextStep(in: state, allowed: [.cageSingle])?.placement,
                       Placement(cell: 40, digit: 4))
    }

    /// The derived digit has to still be a candidate. When it is not, the
    /// position is already contradictory and placing it anyway would hand the
    /// verifier a grid that disagrees with its own solution.
    func testCageSingleRefusesADigitThatIsNoLongerACandidate() {
        var grid = SudokuGrid()
        grid[0] = 2
        grid[1] = 3
        grid[8] = 7 // same row as cell 2, so 7 is gone from it
        let state = CandidateState(grid: grid, context: context(cage([0, 1, 2], 12)))
        XCTAssertNil(LogicSolver.nextStep(in: state, allowed: [.cageSingle]))
    }

    // MARK: - Thermometer bounds

    func testThermoBoundTightensFromBothEnds() {
        var grid = SudokuGrid()
        grid[1] = 5 // the middle of a 3-cell thermometer
        let state = CandidateState(grid: grid, context: context(thermo([0, 1, 2])))
        let step = LogicSolver.nextStep(in: state, allowed: [.thermoBound])
        XCTAssertEqual(step?.technique, .thermoBound)
        var after = state
        LogicSolver.apply(step!, to: &after)
        // Bulb < 5 (and ≥ 1); tip > 5 (and ≤ 9). Row/box peers of the 5 also
        // strip it, which the peer table already did.
        XCTAssertEqual(Sudoku.digits(in: after.candidates[0]), [1, 2, 3, 4])
        XCTAssertEqual(Sudoku.digits(in: after.candidates[2]), [6, 7, 8, 9])
    }

    /// The static half of the bound is compiled into the starting candidates,
    /// so a fresh state on a long thermometer is already narrowed with no step.
    func testTheStaticBoundNeedsNoStep() {
        let state = CandidateState(grid: SudokuGrid(), context: context(thermo([0, 1, 2, 3, 4])))
        XCTAssertEqual(Sudoku.digits(in: state.candidates[0]), [1, 2, 3, 4, 5])
        XCTAssertEqual(Sudoku.digits(in: state.candidates[4]), [5, 6, 7, 8, 9])
        XCTAssertNil(LogicSolver.nextStep(in: state, allowed: [.thermoBound]),
                     "nothing left for the dynamic pass to remove")
    }

    // MARK: - Rule of 45

    func testAnInnieIsTheNinthCellOfARow() {
        // Row 0, cells 0…8. Cages cover 0…7; cell 8 is the innie.
        // Solution row: 1 2 3 4 5 6 7 8 9 → the covered eight sum to 36.
        let state = CandidateState(grid: SudokuGrid(), context: context(
            cage([0, 1, 2, 3], 10), cage([4, 5, 6, 7], 26)))
        let step = LogicSolver.nextStep(in: state, allowed: [.innieOutie])
        XCTAssertEqual(step?.technique, .innieOutie)
        XCTAssertEqual(step?.placement, Placement(cell: 8, digit: 9))
        XCTAssertEqual(step?.cells, Sudoku.units[0], "the unit is the pattern")
    }

    func testAnOutieIsTheOneCellACageSpillsInto() {
        // Cages cover all of row 0 and spill into cell 9 (row 1).
        // Σcages = 45 + the spill cell's digit.
        let state = CandidateState(grid: SudokuGrid(), context: context(
            cage([0, 1, 2, 3], 10), cage([4, 5, 6, 7, 8], 35), cage([8, 9], 12)))
        // Cell 8 is in two cages, so this set is not disjoint — the rule refuses.
        XCTAssertNil(LogicSolver.nextStep(in: state, allowed: [.innieOutie]),
                     "overlapping cages double-count and must not be added up")

        let disjoint = CandidateState(grid: SudokuGrid(), context: context(
            cage([0, 1, 2, 3], 10), cage([4, 5, 6, 7], 26), cage([8, 9], 12)))
        let step = LogicSolver.nextStep(in: disjoint, allowed: [.innieOutie])
        XCTAssertEqual(step?.placement, Placement(cell: 9, digit: 3),
                       "10 + 26 + 12 = 48, and 48 − 45 = 3")
    }

    // MARK: - Cage combination

    /// The textbook case: two cells summing to 17 can only be {8, 9}.
    func testATwoCellCageOfSeventeenAllowsOnlyEightAndNine() {
        let state = CandidateState(grid: SudokuGrid(), context: context(cage([0, 1], 17)))
        let step = LogicSolver.nextStep(in: state, allowed: [.cageCombination])
        XCTAssertEqual(step?.technique, .cageCombination)
        var after = state
        LogicSolver.apply(step!, to: &after)
        XCTAssertEqual(Sudoku.digits(in: after.candidates[0]), [8, 9])
        XCTAssertEqual(Sudoku.digits(in: after.candidates[1]), [8, 9])
    }

    /// And the case that needs both feasibility filters: a 3-cell cage summing
    /// to 8 is {1,2,5} or {1,3,4}, so 1 is certain and 6…9 are impossible — but
    /// only once combinations no cell can host are discarded.
    func testCageCombinationNarrowsToTheUnionOfLiveCombinations() {
        var grid = SudokuGrid()
        // Cell 27 is a column peer of cell 0 in a *different* box, so it strips
        // the 1 from cell 0 alone. Cell 9 would have looked equivalent and is
        // not: box 0 is cells 0,1,2,9,10,11,18,19,20, so a 1 there kills the
        // whole cage — correctly, since a 3-cell sum-8 cage needs a 1.
        grid[27] = 1
        let state = CandidateState(grid: grid, context: context(cage([0, 1, 2], 8)))
        var after = state
        LogicSolver.apply(LogicSolver.nextStep(in: state, allowed: [.cageCombination])!, to: &after)
        XCTAssertEqual(Sudoku.digits(in: after.candidates[0]), [2, 3, 4, 5])
        XCTAssertEqual(Sudoku.digits(in: after.candidates[1]), [1, 2, 3, 4, 5])
    }

    func testCageCombinationLeavesASingleOpenCellToCageSingle() {
        var grid = SudokuGrid()
        grid[0] = 8
        let state = CandidateState(grid: grid, context: context(cage([0, 1], 17)))
        XCTAssertNil(LogicSolver.nextStep(in: state, allowed: [.cageCombination]))
        XCTAssertEqual(LogicSolver.nextStep(in: state, allowed: [.cageSingle])?.placement,
                       Placement(cell: 1, digit: 9))
    }

    // MARK: - The soundness fuzz

    /// Build cages and thermometers *from* a known complete grid, blank most of
    /// it, and let the whole variant chain run. Every placement must agree with
    /// the grid; every elimination must remove a digit the grid does not have
    /// there. See this file's header for why uniqueness is not needed.
    func testNoVariantDeductionEverContradictsTheGrid() {
        var deductions = 0
        for seed in UInt64(1)...60 {
            let solution = BacktrackSolver.completeGrid(seed: seed)
            var rng = SplitMix64(seed: seed &* UInt64(0x9E37_79B9_7F4A_7C15))
            let constraints = CageTiling.cages(of: solution, using: &rng).map(VariantConstraint.cage)
                + Self.thermometers(of: solution, using: &rng)
            let context = ConstraintContext.compile(constraints)

            // Keep roughly a quarter of the digits, so the chain has to work.
            var puzzle = solution
            for cell in 0..<81 where rng.nextInt(below: 4) != 0 { puzzle[cell] = 0 }

            var state = CandidateState(grid: puzzle, context: context)
            var guardRail = 0
            while let step = LogicSolver.nextStep(in: state, allowed: Technique.allCases),
                  guardRail < 2000 {
                guardRail += 1
                deductions += 1
                if let placement = step.placement {
                    XCTAssertEqual(placement.digit, solution[placement.cell],
                                   "seed \(seed): \(step.technique) placed a digit the grid contradicts")
                    guard placement.digit == solution[placement.cell] else { return }
                }
                for elimination in step.eliminations {
                    XCTAssertNotEqual(elimination.digit, solution[elimination.cell],
                                      "seed \(seed): \(step.technique) removed the true digit")
                    guard elimination.digit != solution[elimination.cell] else { return }
                }
                LogicSolver.apply(step, to: &state)
            }
            XCTAssertLessThan(guardRail, 2000, "seed \(seed): the chain did not terminate")
        }
        XCTAssertGreaterThan(deductions, 2_000,
                             "the fuzz has to actually deduce things to prove anything")
    }

    /// Every variant technique must actually fire during the fuzz, or the
    /// soundness result above is only about the ones that did.
    func testTheFuzzExercisesEveryVariantTechnique() {
        var seen: Set<Technique> = []
        for seed in UInt64(1)...60 {
            let solution = BacktrackSolver.completeGrid(seed: seed)
            var rng = SplitMix64(seed: seed &* UInt64(0x9E37_79B9_7F4A_7C15))
            let context = ConstraintContext.compile(
                CageTiling.cages(of: solution, using: &rng).map(VariantConstraint.cage)
                    + Self.thermometers(of: solution, using: &rng))
            var puzzle = solution
            for cell in 0..<81 where rng.nextInt(below: 4) != 0 { puzzle[cell] = 0 }
            var state = CandidateState(grid: puzzle, context: context)
            var guardRail = 0
            while let step = LogicSolver.nextStep(in: state, allowed: Technique.allCases),
                  guardRail < 2000 {
                guardRail += 1
                seen.insert(step.technique)
                LogicSolver.apply(step, to: &state)
            }
        }
        for technique in Technique.allCases where !technique.isClassic {
            XCTAssertTrue(seen.contains(technique), "\(technique) never fired in the fuzz")
        }
    }

    // MARK: - Fuzz fixtures

    /// Thermometers traced along orthogonal neighbours with strictly increasing
    /// values in the grid, so every one of them is satisfied by it.
    static func thermometers(of grid: SudokuGrid, using rng: inout SplitMix64) -> [VariantConstraint] {
        var constraints: [VariantConstraint] = []
        var used = Set<Int>()
        for _ in 0..<6 {
            var cells: [Int] = []
            var cell = rng.nextInt(below: 81)
            while !used.contains(cell), cells.count < 5 {
                cells.append(cell)
                used.insert(cell)
                let row = Sudoku.row(of: cell), col = Sudoku.col(of: cell)
                let steps: [(Int, Int)] = [(row - 1, col), (row + 1, col),
                                           (row, col - 1), (row, col + 1)]
                var neighbours: [Int] = []
                for (r, c) in steps where (0..<9).contains(r) && (0..<9).contains(c) {
                    let candidate = r * 9 + c
                    if !used.contains(candidate) && grid[candidate] > grid[cell] {
                        neighbours.append(candidate)
                    }
                }
                guard let next = neighbours.first else { break }
                cell = next
            }
            if let thermo = Thermometer(cells: cells) { constraints.append(.thermometer(thermo)) }
        }
        return constraints
    }
}
