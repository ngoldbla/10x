// GeneratorTests — the 25-puzzle generation soak (uniqueness + technique
// bounds + determinism + dig-hole symmetry) and the daily seed mapping.
import XCTest
@testable import NineEngine

final class GeneratorTests: XCTestCase {

    /// 25-puzzle soak: 10 gentle + 10 steady + 5 sharp. Every puzzle must be
    /// unique, technique-bounded for its difficulty (ceiling AND floor),
    /// 180°-symmetric, and deterministic from (seed, difficulty).
    func testGenerationSoakAcrossDifficulties() {
        let plan: [(Difficulty, Int)] = [(.gentle, 10), (.steady, 10), (.sharp, 5)]
        for (difficulty, count) in plan {
            for seed in 0..<count {
                let p = PuzzleGenerator.generate(seed: UInt64(seed), difficulty: difficulty)

                // Unique, and the prover's solution is the stored solution.
                guard case .unique(let proven) = BacktrackSolver.countSolutions(of: p.puzzle) else {
                    XCTFail("\(difficulty) seed \(seed): not unique"); continue
                }
                XCTAssertEqual(proven, p.solution, "\(difficulty) seed \(seed): solution mismatch")
                XCTAssertTrue(p.solution.isValidComplete)

                // Givens are a subset of the solution.
                for cell in 0..<81 where p.puzzle[cell] != 0 {
                    XCTAssertEqual(p.puzzle[cell], p.solution[cell])
                }

                // Ceiling: solvable inside the allowed chain, matching trace.
                let outcome = LogicSolver.solve(p.puzzle, allowed: difficulty.allowedTechniques)
                XCTAssertTrue(outcome.solved, "\(difficulty) seed \(seed): not technique-bounded")
                XCTAssertEqual(outcome.finalGrid, p.solution)
                XCTAssertEqual(outcome.steps, p.steps, "stored explanation must match a re-solve")

                // Floor: the band below must NOT suffice.
                if let floor = difficulty.floor {
                    let hardest = outcome.hardestTechnique
                    XCTAssertNotNil(hardest)
                    XCTAssertGreaterThanOrEqual(hardest!.rank, floor.rank,
                        "\(difficulty) seed \(seed): too easy (hardest \(String(describing: hardest)))")
                    let below = Technique.allCases.filter { $0.rank < floor.rank }
                    XCTAssertFalse(LogicSolver.solve(p.puzzle, allowed: below).solved,
                        "\(difficulty) seed \(seed): solvable without its defining technique")
                }

                // Dig-hole symmetry: 180° rotation maps holes to holes.
                for cell in 0..<81 {
                    XCTAssertEqual(p.puzzle[cell] == 0, p.puzzle[80 - cell] == 0,
                        "\(difficulty) seed \(seed): asymmetric hole at \(cell)")
                }
            }
        }
    }

    func testGenerationIsDeterministic() {
        for difficulty in Difficulty.allCases {
            let a = PuzzleGenerator.generate(seed: 0, difficulty: difficulty)
            let b = PuzzleGenerator.generate(seed: 0, difficulty: difficulty)
            XCTAssertEqual(a, b, "\(difficulty): same (seed, difficulty) must be byte-identical")
        }
        let gentle = PuzzleGenerator.generate(seed: 5, difficulty: .gentle)
        let steady = PuzzleGenerator.generate(seed: 5, difficulty: .steady)
        XCTAssertNotEqual(gentle.puzzle, steady.puzzle,
                          "difficulty participates in the derived seed")
    }

    func testDifficultyBandsAreExactlyTheChain() {
        XCTAssertEqual(Difficulty.gentle.allowedTechniques, [.nakedSingle, .hiddenSingle])
        XCTAssertEqual(Difficulty.steady.allowedTechniques,
                       [.nakedSingle, .hiddenSingle, .nakedPair, .hiddenPair, .boxLineReduction])
        XCTAssertEqual(Difficulty.sharp.allowedTechniques, Technique.allCases)
        XCTAssertEqual(Difficulty.sharp.floor, .xWing)
    }

    // MARK: - Daily seed

    func testDailySeedIsStableWithinADayAndDistinctAcrossDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 7))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 23))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 7))!

        XCTAssertEqual(DailySeed.seed(for: morning, calendar: calendar),
                       DailySeed.seed(for: night, calendar: calendar))
        XCTAssertNotEqual(DailySeed.seed(for: morning, calendar: calendar),
                          DailySeed.seed(for: tomorrow, calendar: calendar))
        XCTAssertEqual(DailySeed.dayOrdinal(for: tomorrow, calendar: calendar),
                       DailySeed.dayOrdinal(for: morning, calendar: calendar) + 1)
    }
}
