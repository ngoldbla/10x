// VariantGeneratorTests — killer supply, and the seal on the channel.
//
// Debug-affordable only. Generation runs ~50× slower in Debug than in the
// Release configuration that ships (measured, DEVIATIONS.md PRD-17), so the
// distribution — and every compose number PRD-23 reports — lives in
// `KillerSoakTests` and `scripts/killer-scan.sh`. What runs on every push is
// this: a handful of boards, each held to everything its tier claims.
import XCTest
import Foundation
import CouchCore
@testable import NineEngine

final class VariantGeneratorTests: XCTestCase {

    /// Every board handed out must satisfy the whole claim, not just the easy
    /// half of it: unique *under the cages*, solvable inside its own chain,
    /// inside its clue ceiling, and carrying real cage reasoning rather than
    /// cages as decoration.
    private func assertWellFormed(
        _ puzzle: VariantPuzzle, _ tier: VariantTier, _ label: String
    ) {
        let band = tier.killerBand
        let context = puzzle.context
        XCTAssertTrue(context.canEnforceEveryConstraint, label)
        XCTAssertTrue(context.cagesAreDisjoint, "\(label): the tiling must be a partition")
        XCTAssertEqual(context.cages.flatMap(\.cells).count, 81, "\(label): every cell caged")

        // Every cage is satisfied by the solution it was read off.
        for cage in context.cages {
            let digits = cage.cells.map { puzzle.solution[$0] }
            XCTAssertEqual(Set(digits).count, digits.count, "\(label): cage repeats a digit")
            XCTAssertEqual(digits.reduce(0, +), cage.sum, "\(label): cage sum")
        }

        // Givens agree with the solution, and there are not too many of them.
        for cell in 0..<81 where puzzle.puzzle[cell] != 0 {
            XCTAssertEqual(puzzle.puzzle[cell], puzzle.solution[cell], "\(label): given \(cell)")
        }
        XCTAssertLessThanOrEqual(puzzle.givenCount, band.maxGivens, label)

        // Proven unique under the cages, not merely under classic rules.
        XCTAssertEqual(
            ConstraintBacktrackSolver.countSolutions(of: puzzle.puzzle, context: context),
            .unique(puzzle.solution), label)

        // The stored trace is the trace, and it closes the board.
        let outcome = LogicSolver.solve(puzzle.puzzle, allowed: band.allowed, context: context)
        XCTAssertTrue(outcome.solved, "\(label): outside its own chain")
        XCTAssertEqual(outcome.finalGrid, puzzle.solution, label)
        XCTAssertEqual(outcome.steps, puzzle.steps, "\(label): trace drifted")
        XCTAssertTrue(outcome.steps.allSatisfy { band.allowed.contains($0.technique) },
                      "\(label): used a technique its band does not allow")
        XCTAssertTrue(band.admits(steps: puzzle.steps, givens: puzzle.givenCount), label)
    }

    func testAGentleKillerBoardIsEverythingItClaims() throws {
        let puzzle = try XCTUnwrap(
            VariantGenerator.generate(seed: 1, variant: .killer, tier: .gentle))
        assertWellFormed(puzzle, .gentle, "gentle seed 1")
    }

    func testASteadyKillerBoardIsEverythingItClaims() throws {
        let puzzle = try XCTUnwrap(
            VariantGenerator.generate(seed: 1, variant: .killer, tier: .steady))
        assertWellFormed(puzzle, .steady, "steady seed 1")
    }

    /// Sharp is the real killer aesthetic: no givens at all, the cages alone.
    ///
    /// It did not compose at first, and the fix was a measurement rather than a
    /// guess. With cages up to five cells the zero-given board is not uniquely
    /// determined *at all* — 0 of 200 — so no technique could ever have closed
    /// it. Smaller cages carry far more information; see `VariantBand.maxCageSize`
    /// for the table and for what that costs.
    func testASharpKillerBoardHasNoGivens() throws {
        let puzzle = try XCTUnwrap(
            VariantGenerator.generate(seed: 1, variant: .killer, tier: .sharp))
        assertWellFormed(puzzle, .sharp, "sharp seed 1")
        XCTAssertEqual(puzzle.givenCount, 0, "a sharp killer board is cages only")
        XCTAssertTrue(puzzle.puzzle.cells.allSatisfy { $0 == 0 })
    }

    /// The never-spin rule, asserted as the shape it actually has rather than as
    /// a stopwatch: with the budget cut to a single attempt, every tier returns
    /// either nil or a board that fully meets its band. There is no third
    /// outcome — no partially-proven board, no tier quietly downgraded to fill
    /// the gap. PRD-17's attempt-budget bug was precisely that third outcome,
    /// and the wall-clock got *better* while it happened.
    func testABudgetLimitedComposeIsNilOrFullyInBandAndNeverInBetween() {
        for tier in VariantTier.allCases {
            for seed in UInt64(1)...4 {
                guard let composed = VariantGenerator.generate(
                    seed: seed, variant: .killer, tier: tier, budget: 1) else { continue }
                assertWellFormed(composed, tier, "\(tier) seed \(seed) at budget 1")
            }
        }
    }

    func testGenerationIsDeterministic() {
        // Gentle only, and deliberately: `swift test` has ~10 s of headroom
        // against its 120 s budget (DEVIATIONS, PRD-17), a compose is the most
        // expensive thing this file can ask for, and determinism is a property
        // of the seed derivation rather than of any one tier.
        let a = VariantGenerator.generate(seed: 4, variant: .killer, tier: .gentle)
        let b = VariantGenerator.generate(seed: 4, variant: .killer, tier: .gentle)
        XCTAssertEqual(a, b, "same seed, same board")
        XCTAssertNotNil(a)
        XCTAssertNotEqual(
            a, VariantGenerator.generate(seed: 5, variant: .killer, tier: .gentle))
    }

    /// The seed derivation must not depend on anything that moves between
    /// launches. `String.hashValue` is seeded per process in Swift, and an
    /// earlier draft of `attemptSeed` used it.
    func testTheSeedDerivationIsAPureFunction() {
        for attempt in UInt64(0)...3 {
            XCTAssertEqual(
                VariantGenerator.attemptSeed(9, variant: .killer, tier: .sharp, attempt: attempt),
                VariantGenerator.attemptSeed(9, variant: .killer, tier: .sharp, attempt: attempt))
        }
        XCTAssertNotEqual(
            VariantGenerator.attemptSeed(9, variant: .killer, tier: .sharp, attempt: 0),
            VariantGenerator.attemptSeed(9, variant: .classic, tier: .sharp, attempt: 0),
            "different variants must not share a board")
    }

    func testAnUnimplementedVariantReturnsNilRatherThanAClassicBoard() {
        XCTAssertNil(VariantGenerator.generate(seed: 1, variant: .thermo, tier: .gentle))
        XCTAssertNil(VariantGenerator.generate(seed: 1, variant: .classic, tier: .gentle))
        XCTAssertNil(VariantGenerator.generate(
            seed: 1, variant: .unrecognized("sandwich"), tier: .gentle))
    }

    /// `VariantPuzzle` is a sibling of `GeneratedPuzzle`, and it has to survive
    /// the same round trip — including the `.unrecognized` constraints a future
    /// build might have put in it.
    func testAVariantPuzzleRoundTrips() throws {
        let puzzle = try XCTUnwrap(
            VariantGenerator.generate(seed: 2, variant: .killer, tier: .gentle))
        let data = try JSONEncoder().encode(puzzle)
        XCTAssertEqual(try JSONDecoder().decode(VariantPuzzle.self, from: data), puzzle)
    }

    // MARK: - The channel seal

    /// Release cannot reach the composer at all, and Debug needs an environment
    /// variable, so a developer running the app in Xcode still sees nothing.
    func testTheChannelIsShutUnlessDeliberatelyOpened() {
        #if DEBUG
        XCTAssertEqual(VariantChannel.isOpen,
                       ProcessInfo.processInfo.environment["NINE_VARIANTS"] == "1")
        #else
        XCTAssertFalse(VariantChannel.isOpen, "the channel does not exist in Release")
        #endif
        if !VariantChannel.isOpen {
            XCTAssertNil(VariantChannel.compose(seed: 1, variant: .killer, tier: .gentle))
        }
    }
}
