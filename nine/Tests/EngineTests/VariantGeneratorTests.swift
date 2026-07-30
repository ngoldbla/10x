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
        let band = try! XCTUnwrap(tier.band(for: puzzle.variant), label)
        let context = puzzle.context
        XCTAssertTrue(context.canEnforceEveryConstraint, label)
        XCTAssertEqual(puzzle.variant, puzzle.variant, label)

        switch band.shape {
        case .cages:
            XCTAssertTrue(context.cagesAreDisjoint, "\(label): the tiling must be a partition")
            XCTAssertEqual(context.cages.flatMap(\.cells).count, 81, "\(label): every cell caged")
            XCTAssertTrue(context.thermometers.isEmpty, "\(label): a killer board has no tubes")
            // Every cage is satisfied by the solution it was read off.
            for cage in context.cages {
                let digits = cage.cells.map { puzzle.solution[$0] }
                XCTAssertEqual(Set(digits).count, digits.count, "\(label): cage repeats a digit")
                XCTAssertEqual(digits.reduce(0, +), cage.sum, "\(label): cage sum")
            }
        case .thermometers(let count, let window):
            XCTAssertTrue(context.cages.isEmpty, "\(label): a thermo board has no cages")
            XCTAssertFalse(context.thermometers.isEmpty, "\(label): no tubes at all")
            XCTAssertLessThanOrEqual(context.thermometers.count, count, label)
            // A tube layout is a set of paths, NOT a partition — most cells are
            // on no tube at all, which is the structural difference from cages
            // and the reason there is no rule-of-45 analogue here.
            var onATube = Set<Int>()
            for thermo in context.thermometers {
                XCTAssertTrue(window.contains(thermo.cells.count), "\(label): tube length")
                let digits = thermo.cells.map { puzzle.solution[$0] }
                XCTAssertEqual(digits, digits.sorted(),
                               "\(label): tube not increasing along the solution")
                XCTAssertEqual(Set(digits).count, digits.count, label)
                for cell in thermo.cells {
                    XCTAssertTrue(onATube.insert(cell).inserted, "\(label): cell on two tubes")
                }
            }
            XCTAssertLessThan(onATube.count, 81, "\(label): a tube layout never covers the board")
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
    /// it. Smaller cages carry far more information; see `VariantShape.cages`
    /// for the table and for what that costs.
    func testASharpKillerBoardHasNoGivens() throws {
        let puzzle = try XCTUnwrap(
            VariantGenerator.generate(seed: 1, variant: .killer, tier: .sharp))
        assertWellFormed(puzzle, .sharp, "sharp seed 1")
        XCTAssertEqual(puzzle.givenCount, 0, "a sharp killer board is cages only")
        XCTAssertTrue(puzzle.puzzle.cells.allSatisfy { $0 == 0 })
    }

    // MARK: - Thermo

    /// Thermo is the channel that ships first, and the reason is measurable
    /// rather than editorial: it composes 200/200 at every tier with a Release
    /// p95 of 0.01–0.03 s (`scripts/thermo-scan.sh 200`), against killer Sharp's
    /// 0.14 s and Nocturne's 5.25 s. A ruleset that cheap is the right one to
    /// find out whether the *channel architecture* is wrong.
    func testAThermoBoardIsEverythingItClaims() throws {
        for tier in VariantTier.allCases {
            let puzzle = try XCTUnwrap(
                VariantGenerator.generate(seed: 1, variant: .thermo, tier: tier),
                "\(tier) thermo seed 1 did not compose")
            assertWellFormed(puzzle, tier, "thermo \(tier) seed 1")
            XCTAssertEqual(puzzle.variant, .thermo)
        }
    }

    /// A thermo board always carries givens, and that is a property of the
    /// ruleset rather than a shortcoming of the ladder. Killer Sharp reaches zero
    /// because a cage tiling is a partition carrying a printed sum for every
    /// cell; a tube layout covers the board *partially* by construction, so a
    /// zero-given thermo board is not a purer thermo board — it is an ambiguous
    /// one. If this ever passes with 0 the band ladder has drifted into claiming
    /// something the geometry cannot support.
    func testAThermoBoardIsNeverZeroGiven() throws {
        for tier in VariantTier.allCases {
            let puzzle = try XCTUnwrap(
                VariantGenerator.generate(seed: 3, variant: .thermo, tier: tier))
            XCTAssertGreaterThan(
                puzzle.givenCount, 0,
                "\(tier): tubes alone cannot determine a grid — they do not cover it")
        }
    }

    /// The two knobs that the first draft of `thermoBand` set outside the
    /// measured distribution, where neither could ever reject anything. A band
    /// parameter that cannot fire is a decision dressed as a constraint, so this
    /// pins them *inside* the distribution the soak reported — the clue ceiling
    /// above the observed max but not far above it, and the anti-decoration floor
    /// above the observed p50 rather than below it.
    func testTheThermoBandKnobsCanActuallyReject() {
        for tier in VariantTier.allCases {
            let band = tier.thermoBand
            guard case .thermometers(let count, let window) = band.shape else {
                return XCTFail("\(tier): a thermo band must ask for tubes")
            }
            XCTAssertTrue((2...9).contains(window.lowerBound), "\(tier)")
            XCTAssertTrue((2...9).contains(window.upperBound), "\(tier)")
            XCTAssertGreaterThan(count, 0, "\(tier)")

            // Measured maxima over 200 Release seeds: givens max 19/16/11, and
            // thermo-step p50 10/13/18. A ceiling at or above 30, or a floor at
            // or below 3, is the failure mode this test exists for.
            XCTAssertLessThanOrEqual(band.maxGivens, 24, "\(tier): a ceiling this high never fires")
            XCTAssertGreaterThanOrEqual(
                band.minVariantSteps, 6, "\(tier): a floor this low never fires")
        }
    }

    /// The ladder is walked by **chain width**, not by the clue ceiling, and that
    /// is the PRD-24 finding. A wider chain closes the board with fewer givens
    /// because the extra techniques do work the clues would otherwise do — which
    /// is why Gentle lands at 15 givens (p50), Steady at 12 and Sharp at 7. If
    /// the chains ever stop widening, the tiers stop being tiers.
    func testTheThermoLadderWidensItsChain() {
        let chains = VariantTier.allCases.map { $0.thermoBand.allowed.count }
        XCTAssertEqual(chains, chains.sorted(), "the chain must widen up the ladder")
        XCTAssertLessThan(chains[0], chains[chains.count - 1])
        let ceilings = VariantTier.allCases.map { $0.thermoBand.maxGivens }
        XCTAssertEqual(ceilings, ceilings.sorted(by: >), "the ceiling must fall up the ladder")
        let floors = VariantTier.allCases.map { $0.thermoBand.minVariantSteps }
        XCTAssertEqual(floors, floors.sorted(), "the thermo floor must rise up the ladder")
    }

    /// The never-spin rule, asserted as the shape it actually has rather than as
    /// a stopwatch: with the budget cut to a single attempt, every tier returns
    /// either nil or a board that fully meets its band. There is no third
    /// outcome — no partially-proven board, no tier quietly downgraded to fill
    /// the gap. PRD-17's attempt-budget bug was precisely that third outcome,
    /// and the wall-clock got *better* while it happened.
    func testABudgetLimitedComposeIsNilOrFullyInBandAndNeverInBetween() {
        for variant in [Variant.killer, .thermo] {
            for tier in VariantTier.allCases {
                for seed in UInt64(1)...4 {
                    guard let composed = VariantGenerator.generate(
                        seed: seed, variant: variant, tier: tier, budget: 1) else { continue }
                    assertWellFormed(
                        composed, tier, "\(variant.rawValue) \(tier) seed \(seed) at budget 1")
                }
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

    /// `.thermo` used to be in this list — PRD-23 shipped with a
    /// `guard variant == .killer` and the comment "thermo is PRD-24". Deleting it
    /// from here is the assertion that PRD-24 happened.
    ///
    /// What must stay is that a ruleset with **no supply** returns nil rather
    /// than a classic board wearing its name. `.classic` has no band because
    /// classic generation is `PuzzleGenerator`'s and always was, and
    /// `.unrecognized` has none because a rule this build cannot enforce must not
    /// be composed against — the answer would be about a different puzzle.
    func testAVariantWithNoSupplyReturnsNilRatherThanAClassicBoard() {
        XCTAssertNil(VariantGenerator.generate(seed: 1, variant: .classic, tier: .gentle))
        XCTAssertNil(VariantGenerator.generate(
            seed: 1, variant: .unrecognized("sandwich"), tier: .gentle))
        XCTAssertNil(VariantTier.gentle.band(for: .classic))
        XCTAssertNil(VariantTier.gentle.band(for: .unrecognized("arrow")))
        XCTAssertNotNil(VariantTier.gentle.band(for: .thermo))
        XCTAssertNotNil(VariantTier.gentle.band(for: .killer))
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

    // MARK: - The channel, now open

    /// This replaces `testTheChannelIsShutUnlessDeliberatelyOpened`, which asserted
    /// that Release could not reach the composer at all and that Debug needed
    /// `NINE_VARIANTS=1`. Both were true and both are now false: the channel is the
    /// product.
    ///
    /// What has to stay true is the contract that made one door worth having in the
    /// first place — **nil is a first-class answer, and there is no third
    /// outcome.** A caller either gets a fully proven board or nothing.
    func testTheChannelComposesInEveryConfiguration() throws {
        let board = try XCTUnwrap(
            VariantChannel.compose(seed: 1, variant: .thermo, tier: .gentle),
            "the channel is open in every configuration now")
        assertWellFormed(board, .gentle, "channel thermo gentle seed 1")
        XCTAssertNil(VariantChannel.compose(seed: 1, variant: .classic, tier: .gentle),
                     "classic generation is PuzzleGenerator's and always was")
        XCTAssertNil(VariantChannel.compose(
            seed: 1, variant: .unrecognized("arrow"), tier: .gentle))
    }

    /// The `(day, channel) → board` primitive, which is what "dailies one per day
    /// per channel" is built on. Same day and channel is the same board; two
    /// channels on the same day are different boards.
    func testAChannelDailyIsDeterministicAndPerChannel() throws {
        let day = 20_649
        let thermo = try XCTUnwrap(VariantChannel.daily(day: day, channel: .thermo))
        XCTAssertEqual(thermo, VariantChannel.daily(day: day, channel: .thermo))
        XCTAssertEqual(thermo.variant, .thermo)
        XCTAssertEqual(thermo.tier, VariantChannel.dailyTier)
        // Every daily is `.steady`, matching classic: a daily is the board
        // everybody plays today, so it is not where the player picks a tier.
        XCTAssertEqual(VariantChannel.dailyTier, .steady)

        let killer = try XCTUnwrap(VariantChannel.daily(day: day, channel: .killer))
        XCTAssertNotEqual(thermo.puzzle, killer.puzzle,
                          "two channels must not share a day's board")
        XCTAssertNotEqual(
            thermo.puzzle,
            try XCTUnwrap(VariantChannel.daily(day: day + 1, channel: .thermo)).puzzle)
    }
}
