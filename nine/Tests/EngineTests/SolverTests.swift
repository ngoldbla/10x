// SolverTests — grid builder, logic solver correctness, technique ordering,
// uniqueness prover (incl. a constructed non-unique fixture), explanation
// serialization.
import XCTest
import CouchCore
@testable import NineEngine

final class SolverTests: XCTestCase {

    // The classic Wikipedia sudoku example and its unique solution.
    static let knownPuzzle = SudokuGrid(string: """
        530070000
        600195000
        098000060
        800060003
        400803001
        700020006
        060000280
        000419005
        000080079
        """)!
    static let knownSolution = SudokuGrid(string: """
        534678912
        672195348
        198342567
        859761423
        426853791
        713924856
        961537284
        287419635
        345286179
        """)!

    // MARK: - Grid builder

    func testCompleteGridIsValidAndDeterministic() {
        let a = BacktrackSolver.completeGrid(seed: 42)
        XCTAssertTrue(a.isValidComplete, "seeded builder must emit a valid complete grid")
        XCTAssertEqual(a, BacktrackSolver.completeGrid(seed: 42), "same seed, same grid")
        XCTAssertNotEqual(a, BacktrackSolver.completeGrid(seed: 43), "different seed, different grid")
    }

    // MARK: - Logic solver on a known puzzle

    func testSolverSolvesKnownPuzzleToKnownSolution() {
        let outcome = LogicSolver.solve(Self.knownPuzzle)
        XCTAssertTrue(outcome.solved)
        XCTAssertEqual(outcome.finalGrid, Self.knownSolution)
        XCTAssertFalse(outcome.steps.isEmpty)
        // Every placement in the trace agrees with the known solution.
        for step in outcome.steps {
            if let p = step.placement {
                XCTAssertEqual(p.digit, Self.knownSolution[p.cell],
                               "step \(step.technique) placed a wrong digit")
            }
        }
    }

    func testBacktrackerAgreesOnKnownPuzzle() {
        guard case .unique(let solution) = BacktrackSolver.countSolutions(of: Self.knownPuzzle) else {
            return XCTFail("known puzzle must be unique")
        }
        XCTAssertEqual(solution, Self.knownSolution)
    }

    // MARK: - Technique ordering

    /// The chain is greedy and ordered: replaying a real trace, no step may
    /// be replaceable by a lower-ranked technique at its pre-state.
    func testTraceStepsAreAlwaysTheLowestApplicableTechnique() {
        let generated = PuzzleGenerator.generate(seed: 7, difficulty: .steady)
        var state = CandidateState(grid: generated.puzzle)
        XCTAssertFalse(generated.steps.isEmpty)
        for step in generated.steps {
            let lower = Technique.allCases.filter { $0.rank < step.technique.rank }
            if !lower.isEmpty {
                XCTAssertNil(
                    LogicSolver.nextStep(in: state, allowed: lower),
                    "a \(step.technique) step was emitted while a lower-ranked technique applied"
                )
            }
            XCTAssertEqual(LogicSolver.nextStep(in: state, allowed: LogicSolver.allTechniques), step,
                           "replay must reproduce the recorded step exactly")
            LogicSolver.apply(step, to: &state)
        }
        XCTAssertTrue(state.isSolved)
        XCTAssertEqual(state.grid, generated.solution)
    }

    func testTechniqueRanksAreStrictlyOrdered() {
        let ranks = Technique.allCases.map(\.rank)
        XCTAssertEqual(ranks, ranks.sorted())
        XCTAssertEqual(Set(ranks).count, ranks.count)
        XCTAssertLessThan(Technique.nakedSingle, Technique.xWing)
    }

    // MARK: - Uniqueness prover

    func testProverReportsMultipleOnNonUniqueFixture() throws {
        // Build a complete grid, find an unavoidable rectangle (two rows in
        // the same band, two columns, digits a/b arranged a,b / b,a), and
        // remove its four cells: the result provably has ≥ 2 solutions.
        let full = BacktrackSolver.completeGrid(seed: 7)
        var rectangle: [Int]?
        outer: for r1 in 0..<9 {
            for r2 in (r1 + 1)..<9 where r1 / 3 == r2 / 3 {
                for c1 in 0..<9 {
                    for c2 in (c1 + 1)..<9 {
                        if full[r1, c1] == full[r2, c2], full[r1, c2] == full[r2, c1],
                           full[r1, c1] != full[r1, c2] {
                            rectangle = [r1 * 9 + c1, r1 * 9 + c2, r2 * 9 + c1, r2 * 9 + c2]
                            break outer
                        }
                    }
                }
            }
        }
        let corners = try XCTUnwrap(rectangle, "every practical grid contains an unavoidable rectangle")
        var nonUnique = full
        for cell in corners { nonUnique[cell] = 0 }
        XCTAssertEqual(BacktrackSolver.countSolutions(of: nonUnique), .multiple)
        XCTAssertFalse(BacktrackSolver.isUnique(nonUnique))
    }

    func testProverReportsNoneOnContradictoryGrid() {
        var grid = SudokuGrid()
        grid[0] = 5
        grid[1] = 5 // same row, same digit
        XCTAssertEqual(BacktrackSolver.countSolutions(of: grid), .none)
    }

    func testProverReportsMultipleOnEmptyGrid() {
        XCTAssertEqual(BacktrackSolver.countSolutions(of: SudokuGrid()), .multiple)
    }

    // MARK: - Explanation records

    func testSolveStepsSerializeRoundTrip() throws {
        let generated = PuzzleGenerator.generate(seed: 11, difficulty: .steady)
        let data = try CouchJSON.encode(generated.steps)
        let decoded = try CouchJSON.decode([SolveStep].self, from: data)
        XCTAssertEqual(decoded, generated.steps)
        // The whole proven puzzle round-trips too (autosave format).
        let puzzleData = try CouchJSON.encode(generated)
        XCTAssertEqual(try CouchJSON.decode(GeneratedPuzzle.self, from: puzzleData), generated)
    }

    func testStepsCarryExplanations() {
        let generated = PuzzleGenerator.generate(seed: 3, difficulty: .steady)
        for step in generated.steps {
            XCTAssertFalse(step.cells.isEmpty, "every step names its pattern cells")
            XCTAssertFalse(step.digits.isEmpty, "every step names its digits")
            XCTAssertTrue(step.placement != nil || !step.eliminations.isEmpty,
                          "every step has an effect")
        }
    }
}
