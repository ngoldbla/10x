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
        // Seed 0 for the three bands that shipped in 1.0, and a deliberately
        // cheap seed for Nocturne: this test composes each band *twice*, and a
        // median Nocturne seed costs ~1 s in Release, so ~50 s in the Debug
        // build `swift test` uses — two of those is a third of the whole 120 s
        // suite budget for a property that does not care which seed proves it.
        // Seed 67 is the head of the Release cost scan (3 ms there).
        let seeds: [Difficulty: UInt64] = [.nocturne: 67]
        for difficulty in Difficulty.allCases {
            let seed = seeds[difficulty] ?? 0
            let a = PuzzleGenerator.generate(seed: seed, difficulty: difficulty)
            let b = PuzzleGenerator.generate(seed: seed, difficulty: difficulty)
            XCTAssertEqual(a, b, "\(difficulty): same (seed, difficulty) must be byte-identical")
        }
        let gentle = PuzzleGenerator.generate(seed: 5, difficulty: .gentle)
        let steady = PuzzleGenerator.generate(seed: 5, difficulty: .steady)
        XCTAssertNotEqual(gentle.puzzle, steady.puzzle,
                          "difficulty participates in the derived seed")
    }

    /// The classic chain, spelled out.
    ///
    /// Sharp used to be asserted as `Technique.allCases`, which was a shorthand
    /// that held only while every technique was a classic one. PRD-23 appended
    /// four variant cases, and the shorthand became false — correctly, and this
    /// is the assertion that said so. It is written out in full now, because
    /// "the whole enum" is exactly the wrong thing for a classic band to mean:
    /// `Difficulty` bands are frozen by the golden corpus, and a technique added
    /// to the enum must never widen one of them by accident.
    func testDifficultyBandsAreExactlyTheChain() {
        XCTAssertEqual(Difficulty.gentle.allowedTechniques, [.nakedSingle, .hiddenSingle])
        XCTAssertEqual(Difficulty.steady.allowedTechniques,
                       [.nakedSingle, .hiddenSingle, .nakedPair, .hiddenPair, .boxLineReduction])
        XCTAssertEqual(Difficulty.sharp.allowedTechniques,
                       [.nakedSingle, .hiddenSingle, .nakedPair,
                        .hiddenPair, .boxLineReduction, .xWing])
        XCTAssertEqual(Difficulty.sharp.floor, .xWing)

        // And the general form: no band, ever, reaches a variant technique.
        for difficulty in Difficulty.allCases {
            XCTAssertTrue(difficulty.allowedTechniques.allSatisfy(\.isClassic),
                          "\(difficulty) reached a variant technique")
        }
    }

    // MARK: - Nocturne (PRD-17)

    /// Nocturne shares Sharp's chain exactly — that is the PRD's scope note, and
    /// it is what makes it a generator-parameter band rather than a solver PRD.
    /// If this ever fails, someone added a technique and Nocturne stopped being
    /// the thing PRD-17 specified.
    func testNocturneSharesSharpsTechniqueChain() {
        XCTAssertEqual(Difficulty.nocturne.allowedTechniques, Difficulty.sharp.allowedTechniques)
        XCTAssertEqual(Difficulty.nocturne.floor, .xWing)
        XCTAssertNil(Difficulty.sharp.demands, "Sharp is defined by its chain alone")
    }

    /// So the whole of Nocturne's identity lives in `demands`, and it has to be
    /// a real step past Sharp on both axes it can be measured on.
    func testNocturneDemandsAreStrictlyDeeperThanSharp() throws {
        let demands = try XCTUnwrap(Difficulty.nocturne.demands)
        // Sharp's median is 28 givens (500-seed release scan), and only ~22% of
        // sharp boards reach 26. Nocturne guarantees it.
        XCTAssertLessThanOrEqual(demands.maxGivens, 26)
        XCTAssertGreaterThanOrEqual(demands.minAdvancedSteps, 3)
        XCTAssertEqual(demands.advancedFloor, .boxLineReduction)
    }

    /// The band's own predicate, exercised without paying for a compose — it is
    /// the thing `verify` leans on, so it gets a test of its own.
    func testBandDemandsCountStepsAtOrAboveTheAdvancedFloor() {
        let demands = BandDemands(maxGivens: 26, advancedFloor: .boxLineReduction, minAdvancedSteps: 3)
        func step(_ t: Technique) -> SolveStep { SolveStep(technique: t, cells: [], digits: []) }

        XCTAssertFalse(demands.admits(steps: [step(.nakedSingle), step(.hiddenPair), step(.xWing)]),
                       "only one step is at or above box-line")
        XCTAssertTrue(demands.admits(steps: [step(.boxLineReduction), step(.boxLineReduction), step(.xWing)]))
        XCTAssertTrue(demands.admits(steps: Array(repeating: step(.xWing), count: 3)))
        XCTAssertFalse(demands.admits(steps: []))
    }

    /// One real Nocturne compose, proven end to end. Deliberately ONE: in the
    /// Debug build `swift test` uses, generation runs ~50× slower than the
    /// Release build that ships (measured: seed 3004 sharp is 0.428 s release,
    /// 30.8 s debug), so a Nocturne soak belongs in the release lane —
    /// `scripts/compose-scan.sh`, which is where the p95 in the PR comes from.
    func testANocturneBoardIsProvenOnEveryAxisItClaims() throws {
        let demands = try XCTUnwrap(Difficulty.nocturne.demands)
        let p = PuzzleGenerator.generate(seed: 67, difficulty: .nocturne)

        // Unique, and the prover's solution is the stored solution.
        guard case .unique(let proven) = BacktrackSolver.countSolutions(of: p.puzzle) else {
            return XCTFail("nocturne seed 67: not unique")
        }
        XCTAssertEqual(proven, p.solution)

        // Inside the chain, and the stored trace is the one a re-solve produces.
        let outcome = LogicSolver.solve(p.puzzle, allowed: Difficulty.nocturne.allowedTechniques)
        XCTAssertTrue(outcome.solved)
        XCTAssertEqual(outcome.steps, p.steps)

        // Both halves of the band, on the trace that travels with the puzzle.
        XCTAssertLessThanOrEqual(p.givenCount, demands.maxGivens)
        XCTAssertTrue(demands.admits(steps: p.steps))
        XCTAssertEqual(p.hardestTechnique, .xWing)

        // And still 180°-symmetric — the re-dig pass works in whole orbits.
        for cell in 0..<81 {
            XCTAssertEqual(p.puzzle[cell] == 0, p.puzzle[80 - cell] == 0,
                           "nocturne seed 67: asymmetric hole at \(cell)")
        }
    }

    /// The re-dig pass is Nocturne-only, and Sharp's bytes are the proof.
    /// `GoldenCorpusTests` covers this across 50 pairs; this is the cheap local
    /// statement of the same rule, so a failure names the cause directly.
    func testTheNocturneReDigDoesNotTouchSharp() {
        let before = PuzzleGenerator.generate(seed: 3017, difficulty: .sharp)
        XCTAssertEqual(before.givenCount, 27, "sharp seed 3017 is frozen at 27 givens")
        XCTAssertNil(Difficulty.sharp.demands)
    }

    /// `generate` may never spin. Sharp and below have no demands and so cannot
    /// reject on one, but Nocturne can, and an unbounded retry loop in front of
    /// a waiting player is the failure mode PRD-23 named and PRD-17 inherits.
    func testTheAttemptBudgetIsBoundedAndGenerousEnoughToBeUnreachable() {
        // About one attempt in 500 is admitted, and the search needs a p95 of
        // ~12,000 attempts (200-seed release scan, no budget). The budget has to
        // sit well above that tail or it stops being a backstop and starts being
        // a silent difficulty cap — which is exactly what 500 did.
        XCTAssertGreaterThanOrEqual(PuzzleGenerator.attemptBudget, 100_000)
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
