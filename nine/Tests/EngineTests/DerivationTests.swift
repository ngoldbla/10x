// DerivationTests — "why must this be a 7?" (PRD-25 §3.2).
//
// The invariant everything else rests on is a **replay**: the beats a
// derivation hands back, applied in order to the grid it was derived for, end
// with the target cell holding the digit the derivation named. That is checkable
// without trusting any of the per-technique reasoning, and it is what makes the
// narration safe to put on screen.
//
// The second rule is the one `Coach.swift` made structural and this file makes
// observable: **the derivation never consults a solution.** It cannot — nothing
// in its signature can reach one — so what is tested here is the consequence:
// the same grid produces the same answer whether or not a solution exists for
// it, and a board with a player's slip in it gets a refusal rather than a
// confident wrong story.
import XCTest
import Foundation
@testable import NineEngine

final class DerivationTests: XCTestCase {

    private func derive(
        _ cell: Int, _ grid: SudokuGrid, allowed: [Technique] = LogicSolver.allTechniques
    ) -> Result<Derivation, DerivationRefusal> {
        LogicSolver.derivation(forCell: cell, in: grid, allowed: allowed)
    }

    // MARK: - The replay invariant

    /// Every empty cell of a real board, on the band's own chain. Applying the
    /// beats in order must land the named digit in the named cell.
    func testEveryBeatReplaysToTheDigitItNames() throws {
        var checked = 0
        for seed in (1 as UInt64)...(6 as UInt64) {
            let puzzle = PuzzleGenerator.generate(seed: seed, difficulty: .steady)
            let empties = (0..<81).filter { puzzle.puzzle[$0] == 0 }
            for cell in empties {
                guard case .success(let derivation) =
                        derive(cell, puzzle.puzzle,
                               allowed: Difficulty.steady.allowedTechniques) else {
                    XCTFail("seed \(seed) cell \(cell): no derivation on a proven board")
                    continue
                }
                checked += 1

                // Replay. Only the recorded beats are applied — the steps the
                // derivation skipped are, by its own claim, irrelevant to this
                // cell, so a replay that needs them would be the claim failing.
                var state = CandidateState(grid: puzzle.puzzle)
                for beat in derivation.steps {
                    LogicSolver.apply(beat.coach.step, to: &state)
                }
                XCTAssertEqual(state.values[cell], derivation.digit,
                               "seed \(seed) cell \(cell): replay did not land")
                XCTAssertEqual(derivation.digit, puzzle.solution[cell],
                               "seed \(seed) cell \(cell): derived the wrong digit")
            }
        }
        XCTAssertGreaterThan(checked, 200, "the sweep has to actually sweep")
    }

    /// Every beat except the last removes at least one candidate from the
    /// target cell, and the last one places it. That is the definition of the
    /// filter, asserted so a future "helpful" widening of it is a failure.
    func testEveryBeatIsAboutTheCellThePlayerAskedAbout() throws {
        let puzzle = PuzzleGenerator.generate(seed: 4, difficulty: .steady)
        var sawMultiStep = false
        for cell in (0..<81).filter({ puzzle.puzzle[$0] == 0 }) {
            guard case .success(let derivation) =
                    derive(cell, puzzle.puzzle,
                           allowed: Difficulty.steady.allowedTechniques) else { continue }
            if derivation.steps.count > 1 { sawMultiStep = true }
            for beat in derivation.steps.dropLast() {
                XCTAssertFalse(beat.ruledOut.isEmpty,
                               "cell \(cell): a beat that changed nothing about it")
                XCTAssertNil(beat.places)
            }
            let last = try XCTUnwrap(derivation.steps.last)
            XCTAssertEqual(last.places, derivation.digit)
            XCTAssertEqual(last.coach.step.placement?.cell, cell)
        }
        XCTAssertTrue(sawMultiStep, "every cell was a one-step answer — filter is inert")
    }

    /// The count-down the narration speaks: the starting candidates, minus
    /// everything the beats ruled out, is exactly the digit that lands.
    func testTheRuledOutDigitsAccountForEveryStartingCandidate() {
        let puzzle = PuzzleGenerator.generate(seed: 2, difficulty: .steady)
        for cell in (0..<81).filter({ puzzle.puzzle[$0] == 0 }) {
            guard case .success(let d) =
                    derive(cell, puzzle.puzzle,
                           allowed: Difficulty.steady.allowedTechniques) else { continue }
            var left = Set(d.startingCandidates)
            for beat in d.steps { left.subtract(beat.ruledOut) }
            XCTAssertEqual(left, [d.digit], """
                cell \(cell): started \(d.startingCandidates), ruled out \
                \(d.steps.flatMap(\.ruledOut).sorted()), landed on \(d.digit)
                """)
        }
    }

    // MARK: - Bounds and honesty

    /// A cell has at most nine candidates, so at most nine beats can bear on
    /// it. The bound is structural, and this is what says so out loud.
    func testTheChainIsBoundedByTheCellsCandidateCount() {
        // Tempest, not Sharp: it composes in ~0.01 s Release against Sharp's
        // ~0.7 s (PRD-25 §5), so the deeper band is also the cheaper fixture —
        // and it is the one whose chains reach the new techniques.
        let puzzle = PuzzleGenerator.generate(seed: 3, difficulty: .tempest)
        for cell in (0..<81).filter({ puzzle.puzzle[$0] == 0 }) {
            guard case .success(let d) =
                    derive(cell, puzzle.puzzle,
                           allowed: Difficulty.tempest.allowedTechniques) else { continue }
            XCTAssertLessThanOrEqual(d.steps.count, d.startingCandidates.count,
                                     "cell \(cell)")
            XCTAssertLessThanOrEqual(d.narrated.count, Derivation.narrationLimit)
            XCTAssertEqual(d.untold, max(0, d.steps.count - Derivation.narrationLimit))
        }
    }

    /// The skipped steps are counted, not hidden. On a board where the target
    /// is not the solver's first concern, `elsewhere` has to be non-zero, or
    /// the UI's "and N steps elsewhere" line would be a permanent lie.
    func testStepsTakenElsewhereAreCounted() {
        let puzzle = PuzzleGenerator.generate(seed: 5, difficulty: .tempest)
        let anyElsewhere = (0..<81)
            .filter { puzzle.puzzle[$0] == 0 }
            .contains { cell in
                guard case .success(let d) =
                        derive(cell, puzzle.puzzle,
                               allowed: Difficulty.tempest.allowedTechniques) else { return false }
                return d.elsewhere > 0
            }
        XCTAssertTrue(anyElsewhere, "no cell needed a step taken elsewhere first")
    }

    // MARK: - Refusals

    func testAFilledCellHasNothingToDerive() {
        let puzzle = PuzzleGenerator.generate(seed: 1, difficulty: .gentle)
        let given = try? XCTUnwrap((0..<81).first { puzzle.puzzle[$0] != 0 })
        guard case .failure(let why) = derive(given ?? 0, puzzle.puzzle) else {
            return XCTFail("derived an answer for a cell that already has one")
        }
        XCTAssertEqual(why, .alreadyFilled)
    }

    /// A player's slip gets the same refusal the coach gives, pointing at cells
    /// the *grid* disagrees about — never at cells a solution disagrees with.
    /// This is the `showErrors`-off guarantee, made observable.
    ///
    /// The question is asked about a **different, still-empty** cell, because
    /// that is the only shape the gesture can produce: long-press is bound to
    /// empty cells, and a filled one is refused as `alreadyFilled` before the
    /// board is examined at all.
    func testASlipIsRefusedAndPointsAtTheClashNotTheSolution() {
        let puzzle = PuzzleGenerator.generate(seed: 1, difficulty: .gentle)
        var grid = puzzle.puzzle
        // Duplicate the first given inside its own row — a slip a player could
        // make, and one the grid can see without knowing the answer.
        let source = (0..<81).first { grid[$0] != 0 }!
        let row = Sudoku.row(of: source)
        let slip = (0..<9).map { row * 9 + $0 }.first { grid[$0] == 0 }!
        grid[slip] = grid[source]
        let asked = (0..<81).first { grid[$0] == 0 && Sudoku.row(of: $0) != row }!

        guard case .failure(let why) = derive(asked, grid) else {
            return XCTFail("narrated a story about a contradictory board")
        }
        guard case .contradiction(let cells) = why else {
            return XCTFail("expected a contradiction, got \(why)")
        }
        XCTAssertTrue(cells.contains(source) && cells.contains(slip),
                      "pointed at \(cells), not at the two cells that clash")
        XCTAssertFalse(cells.contains(asked),
                       "pointed at the cell the player asked about, which is innocent")
    }

    /// A cell the band's ceiling cannot reach is refused rather than answered
    /// with a harder technique the board never promised.
    func testACellBeyondTheBandsCeilingIsRefused() {
        let puzzle = PuzzleGenerator.generate(seed: 3, difficulty: .tempest)
        let refusals = (0..<81)
            .filter { puzzle.puzzle[$0] == 0 }
            .filter { cell in
                if case .failure(.beyond) = derive(cell, puzzle.puzzle,
                                                   allowed: Difficulty.gentle.allowedTechniques) {
                    return true
                }
                return false
            }
        XCTAssertFalse(refusals.isEmpty,
                       "a tempest board answered every cell on the gentle chain")
    }

    /// Nothing in the derivation path can name a `NineGame`, which is what
    /// stops it reading `puzzle.solution`. Structural, so it is greppable —
    /// the same instrument `StringSealTests` and `WatchSealTests` use.
    ///
    /// **Comments are stripped first, and that is not a convenience.** The
    /// first version of this test grepped the raw file and failed on
    /// `Derivation.swift`'s own header, which explains at length why it must
    /// not read a solution. A seal that fires on the sentence describing the
    /// seal teaches the next person to delete the sentence, which is the
    /// opposite of what it is for.
    func testTheDerivationCannotReachASolution() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Engine/Derivation.swift"),
            encoding: .utf8)
        let code = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let slashes = line.range(of: "//") else { return line }
                return line[line.startIndex..<slashes.lowerBound]
            }
            .joined(separator: "\n")

        XCTAssertFalse(code.contains("NineGame"), """
            Derivation.swift names NineGame in code. `NineGame.isError` knows the \
            answer, and `errorHighlight` is a setting the player can switch off — a \
            coach that can reach it can leak it through the one surface a stuck \
            player is most likely to open. Coach.swift's header has the long version.
            """)
        XCTAssertFalse(code.contains("solution"),
                       "Derivation.swift names a solution in code")
        // The strip has to leave something behind, or this passes on an empty
        // string — the vacuous-gate failure PRD-20's plural check shipped with.
        XCTAssertTrue(code.contains("public static func derivation"),
                      "comment stripping ate the file")
    }
}
