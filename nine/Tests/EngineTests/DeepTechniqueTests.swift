// DeepTechniqueTests — the tripwire below the golden corpus for PRD-25, and
// the soundness soak for the four techniques it added.
//
// Two jobs, and they fail for different reasons:
//
//   1. **`fish(2)` is `xWing`.** PRD-25 replaced a hand-written X-wing loop with
//      a generalized fish. The golden corpus proves the *bytes* of 56 generated
//      puzzles did not move, which is the contract — but 56 seeds visit a
//      vanishing fraction of the states a player's board can be in, and the
//      corpus's failure message says "generation moved", not where. So a
//      verbatim copy of the pre-PRD-25 implementation lives below and is
//      compared step-for-step across thousands of real solver states. Same
//      shape, same reason, same file naming convention as
//      `ConstraintDelegationTests`.
//
//   2. **Every new technique is sound.** A technique that eliminates a
//      candidate the solution needs does not surface as a wrong answer later:
//      the uniqueness verifier is *downstream* of the solver, so it agrees with
//      the mistake. The only way to catch it is to check every emitted step
//      against a solution the step never saw.
import XCTest
import Foundation
@testable import NineEngine

final class DeepTechniqueTests: XCTestCase {

    // MARK: - fish(2) is xWing

    /// The pre-PRD-25 `LogicSolver.xWing`, copied verbatim. **Do not "improve"
    /// it** — its whole value is being the thing that stopped changing. If this
    /// and `fish(size: 2)` disagree, the generalization moved classic
    /// generation and the 56 golden hashes are the next thing to fail.
    private static func frozenXWing(_ state: CandidateState) -> SolveStep? {
        for baseIsRow in [true, false] {
            for digit in 1...9 {
                let bit = Sudoku.bit(digit)
                var crossSets = [UInt16](repeating: 0, count: 9)
                for base in 0..<9 {
                    for cross in 0..<9 {
                        let cell = baseIsRow ? base * 9 + cross : cross * 9 + base
                        if state.candidates[cell] & bit != 0 {
                            crossSets[base] |= UInt16(1) << UInt16(cross)
                        }
                    }
                }
                for b1 in 0..<8 where crossSets[b1].nonzeroBitCount == 2 {
                    for b2 in (b1 + 1)..<9 where crossSets[b2] == crossSets[b1] {
                        let crosses = Sudoku.digits(in: crossSets[b1])
                        var corners: [Int] = []
                        for base in [b1, b2] {
                            for cross in crosses {
                                corners.append(baseIsRow ? base * 9 + cross : cross * 9 + base)
                            }
                        }
                        var eliminations: [Elimination] = []
                        for base in 0..<9 where base != b1 && base != b2 {
                            for cross in crosses {
                                let cell = baseIsRow ? base * 9 + cross : cross * 9 + base
                                if state.candidates[cell] & bit != 0 {
                                    eliminations.append(Elimination(cell: cell, digit: digit))
                                }
                            }
                        }
                        if !eliminations.isEmpty {
                            return SolveStep(
                                technique: .xWing, cells: corners,
                                digits: [digit], eliminations: eliminations
                            )
                        }
                    }
                }
            }
        }
        return nil
    }

    /// Walk real sharp/nocturne solves one step at a time and compare the two
    /// implementations in **every intermediate state**, not just the ones the
    /// chain happened to use an X-wing in. A disagreement anywhere — including
    /// "one found nothing and the other found something" — is a failure.
    func testFishOfTwoIsByteIdenticalToTheFrozenXWing() {
        var statesWalked = 0
        var xWingsSeen = 0
        for seed in [3002, 3003, 3007, 3013, 3015, 3017] as [UInt64] {
            let puzzle = PuzzleGenerator.generate(seed: seed, difficulty: .sharp)
            var state = CandidateState(grid: puzzle.puzzle)
            while !state.isSolved {
                statesWalked += 1
                let mine = LogicSolver.nextStep(in: state, allowed: [.xWing])
                let frozen = Self.frozenXWing(state)
                XCTAssertEqual(mine, frozen, "seed \(seed), state \(statesWalked)")
                if mine != nil { xWingsSeen += 1 }
                guard let step = LogicSolver.nextStep(
                    in: state, allowed: Difficulty.sharp.allowedTechniques
                ) else { break }
                LogicSolver.apply(step, to: &state)
            }
        }
        XCTAssertGreaterThan(statesWalked, 200, "the walk has to actually walk")
        XCTAssertGreaterThan(xWingsSeen, 0, "and it has to actually find X-wings")
    }

    /// The cheap half of the same claim, stated as an identity rather than a
    /// sample: `xWing` is not its own function any more, it is a call.
    func testXWingIsSpelledAsFishOfTwo() {
        let source = try? String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Engine/LogicSolver.swift"),
            encoding: .utf8)
        XCTAssertNotNil(source)
        XCTAssertTrue(
            source?.contains("fish(state, size: 2, technique: .xWing)") == true,
            "X-wing must remain a call into the shared fish loop, not a fork of it")
    }

    // MARK: - Soundness

    /// A technique may only eliminate a candidate that is impossible and only
    /// place a digit that is forced. Checked against the *solution*, which no
    /// technique is allowed to see.
    ///
    /// Runs each new technique alone on positions taken from real solves, so a
    /// step it emits is judged in a state the board could genuinely be in.
    /// The six cheap sharp seeds the golden corpus already pays for. Generation
    /// dominates this file's cost — a sharp board is ~0.7 s in Debug and the
    /// median seed is far worse (`GoldenCorpusTests`' header has the arithmetic)
    /// — so every soak below walks *these* boards and each is generated once.
    private static let walkSeeds: [UInt64] = [3002, 3003, 3007, 3013, 3015, 3017]

    func testNoDeepTechniqueEverContradictsTheSolution() {
        let deep: [Technique] = [.swordfish, .skyscraper, .xyWing, .simpleColoring]
        var emitted = [Technique: Int]()
        for seed in Self.walkSeeds {
            let puzzle = PuzzleGenerator.generate(seed: seed, difficulty: .sharp)
            let solution = puzzle.solution.cells
            var state = CandidateState(grid: puzzle.puzzle)
            var walked = 0
            while !state.isSolved, walked < 200 {
                walked += 1
                for technique in deep {
                    guard let step = LogicSolver.nextStep(in: state, allowed: [technique])
                    else { continue }
                    emitted[technique, default: 0] += 1
                    if let placement = step.placement {
                        XCTAssertEqual(
                            solution[placement.cell], placement.digit,
                            "\(technique) placed a digit the solution disagrees with")
                    }
                    for elimination in step.eliminations {
                        XCTAssertNotEqual(
                            solution[elimination.cell], elimination.digit,
                            "\(technique) eliminated the solution's own digit "
                            + "at cell \(elimination.cell)")
                    }
                }
                // Advance on the ordinary chain so the walk sees deep states.
                guard let next = LogicSolver.nextStep(
                    in: state, allowed: Difficulty.sharp.allowedTechniques
                ) else { break }
                LogicSolver.apply(next, to: &state)
            }
        }
        // A soak that finds nothing proves nothing, and this one is the only
        // place a wrong elimination can surface — the uniqueness verifier is
        // downstream of the solver and would agree with the mistake. So the
        // count is asserted, not just the absence of failures.
        XCTAssertFalse(emitted.isEmpty, "no deep technique fired on any sharp board")
    }

    // MARK: - Hand-built positions

    /// A textbook skyscraper. Digit 4 lives in exactly two cells of row 0
    /// (r0c0, r0c4) and exactly two of row 1 (r1c0, r1c5). The two rows share
    /// **column 0 only** — sharing two columns would be an X-wing, which is why
    /// the roofs must be c4 and c5 rather than the same column twice.
    ///
    /// The victims are the row-2 cells of box 1: they see both roofs, and they
    /// are the only cells that can, because anything in rows 0 or 1 holding a 4
    /// would break the "exactly two homes" premise the pattern is built on.
    /// r2c8 keeps a 4 so the position stays satisfiable after the elimination
    /// rather than being a contradiction that happens to prove the point.
    func testSkyscraperEliminatesFromCellsSeeingBothRoofs() {
        var state = CandidateState(grid: SudokuGrid())
        // Strip 4 from everywhere, then hand it back only where the pattern
        // wants it — the cheapest way to build an exact candidate position.
        state.debugRestrict(digit: 4, to: [0, 4, 9, 14, 21, 22, 23, 26])
        let step = LogicSolver.nextStep(in: state, allowed: [.skyscraper])
        XCTAssertEqual(step?.technique, .skyscraper)
        XCTAssertEqual(step?.digits, [4])
        XCTAssertEqual(step?.cells, [0, 9, 4, 14], "bases lead, roofs follow")
        XCTAssertEqual(step?.roles, [.base, .base, .cover, .cover])
        XCTAssertEqual(step?.eliminations.map(\.cell), [21, 22, 23])

        // Assert the conclusion rather than restating the construction: every
        // victim sees both roofs, which is the entire content of the technique.
        let roofs = Array(step!.cells.suffix(2))
        for elimination in step!.eliminations {
            XCTAssertTrue(
                Sudoku.peers[elimination.cell].contains(roofs[0])
                    && Sudoku.peers[elimination.cell].contains(roofs[1]),
                "cell \(elimination.cell) does not see both roofs")
        }
    }

    /// An XY-wing: pivot {1,2}, pincers {1,3} and {2,3}, conclusion 3.
    func testXYWingEliminatesTheSharedThirdDigit() {
        var state = CandidateState(grid: SudokuGrid())
        state.debugSetCandidates(0, digits: [1, 2])      // pivot,  r0c0
        state.debugSetCandidates(1, digits: [1, 3])      // pincer, r0c1
        state.debugSetCandidates(9, digits: [2, 3])      // pincer, r1c0
        let step = LogicSolver.nextStep(in: state, allowed: [.xyWing])
        XCTAssertEqual(step?.technique, .xyWing)
        XCTAssertEqual(step?.cells.first, 0, "the pivot leads")
        XCTAssertEqual(step?.digits.first, 3, "digits[0] is the conclusion")
        XCTAssertEqual(step?.roles, [.pivot, .cover, .cover])
        // Cell 10 (r1c1) sees both pincers and is in the same box.
        XCTAssertTrue(step?.eliminations.contains(Elimination(cell: 10, digit: 3)) == true)
    }

    // MARK: - Schema v2

    /// The claim the golden corpus rests on, stated where it can be read: no
    /// classic-six step carries a v2 field, so no classic trace encodes one.
    func testTheFrozenSixNeverEmitV2Fields() throws {
        // Same cost discipline as the soaks: cheap bands by seed range, sharp
        // only on the six seeds already proven affordable in Debug.
        var boards: [(UInt64, Difficulty)] = []
        for seed in (1 as UInt64)...(12 as UInt64) { boards.append((seed, .gentle)) }
        for seed in (1 as UInt64)...(8 as UInt64) { boards.append((seed, .steady)) }
        for seed in Self.walkSeeds { boards.append((seed, .sharp)) }

        var stepsChecked = 0
        for (seed, difficulty) in boards {
            let puzzle = PuzzleGenerator.generate(seed: seed, difficulty: difficulty)
            for step in puzzle.steps {
                stepsChecked += 1
                XCTAssertNil(step.roles, "\(step.technique) emitted roles")
                XCTAssertNil(step.chain, "\(step.technique) emitted a chain")
            }
            let text = String(decoding: try JSONEncoder().encode(puzzle), as: UTF8.self)
            XCTAssertFalse(text.contains("\"roles\""), "seed \(seed) \(difficulty)")
            XCTAssertFalse(text.contains("\"chain\""), "seed \(seed) \(difficulty)")
        }
        XCTAssertGreaterThan(stepsChecked, 500, "the sweep has to actually sweep")
    }

    /// A trace written before schema v2 decodes unchanged, and one written
    /// after it round-trips.
    func testV2FieldsAreOptionalOnTheWireBothWays() throws {
        let v1 = Data("""
        {"technique":"nakedSingle","cells":[0],"digits":[7],"eliminations":[]}
        """.utf8)
        let decoded = try JSONDecoder().decode(SolveStep.self, from: v1)
        XCTAssertEqual(decoded.technique, .nakedSingle)
        XCTAssertNil(decoded.roles)
        XCTAssertEqual(decoded.role(at: 0), .base, "no roles means every cell is pattern")

        let v2 = SolveStep(
            technique: .xyWing, cells: [0, 1, 9], digits: [3, 1, 2],
            eliminations: [Elimination(cell: 10, digit: 3)],
            roles: [.pivot, .cover, .cover],
            chain: [StepLink(from: 0, to: 1, isStrong: false)])
        let round = try JSONDecoder().decode(
            SolveStep.self, from: JSONEncoder().encode(v2))
        XCTAssertEqual(round, v2)
    }

    /// A roles array that does not line up with `cells` is dropped rather than
    /// stored: the coach indexes the two together, so a mislabelled step would
    /// draw the wrong ring rather than fail loudly.
    func testMismatchedRolesAreRefused() {
        let step = SolveStep(technique: .xyWing, cells: [0, 1, 9], digits: [3],
                             roles: [.pivot])
        XCTAssertNil(step.roles)
    }
}

// MARK: - Test-only state surgery

extension CandidateState {
    /// Remove `digit` from every cell except `keep`. Lets a test build an exact
    /// single-digit pattern without hand-writing 81 candidate masks.
    mutating func debugRestrict(digit: Int, to keep: [Int]) {
        let kept = Set(keep)
        for cell in 0..<81 where !kept.contains(cell) {
            eliminate(digit, at: cell)
        }
    }

    /// Force one cell's candidates to exactly `digits`.
    mutating func debugSetCandidates(_ cell: Int, digits: [Int]) {
        let wanted = Set(digits)
        for digit in 1...9 where !wanted.contains(digit) {
            eliminate(digit, at: cell)
        }
    }
}
