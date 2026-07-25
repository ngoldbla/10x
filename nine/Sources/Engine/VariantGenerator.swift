// VariantGenerator.swift — killer supply, by the inverse of the classic dig.
//
// Classic generation starts from a full grid and *removes* clues while the
// puzzle stays provable. Killer cannot: the cages already carry most of the
// information, and a real killer board has **no givens at all**, so digging from
// 81 clues would spend its whole budget walking down to zero. The pipeline
// inverts:
//
//   1. a seeded complete grid (the frozen `BacktrackSolver.completeGrid`)
//   2. a seeded polyomino cage tiling of it, sums read off the solution — so
//      every cage is satisfied by construction and only *uniqueness* is left
//   3. start from an empty board and **add** givens, one at a time, aimed at
//      wherever the technique chain got stuck, until the chain solves it
//   4. trim: offer each added given back, keep it out when the chain still
//      closes — the same local-minimum trick Nocturne's re-dig uses
//   5. prove: unique under the cages, chain-bounded, and enough of the trace is
//      actual cage reasoning that the cages are not decoration
//
// **There is no `while true` here.** PRD-23 states the never-spin rule for
// variants and PRD-17 is the story of why: an attempt budget calibrated against
// wall-clock rather than against attempts fired on nearly every seed and handed
// out boards wearing the wrong label, while the timing *improved*. This budget
// is calibrated against attempts, and when it runs out `generate` returns nil
// rather than a board that missed its band.
import Foundation
import CouchCore

/// What a variant tier asks of a candidate board on top of being unique and
/// solvable inside its chain.
public struct VariantBand: Sendable, Equatable {
    /// The techniques the proven solve may use.
    public let allowed: [Technique]
    /// The clue ceiling. Zero is the real killer aesthetic — the cages alone
    /// determine the grid — and the higher tiers get there.
    public let maxGivens: Int
    /// How many steps of the proven trace must be variant reasoning. Without
    /// this a "killer" board can be one the classic chain would have solved
    /// anyway, with the cages as decoration.
    public let minVariantSteps: Int
    /// The largest cage the tiler may build, and the knob that actually decides
    /// whether a tier has any supply at all.
    ///
    /// Measured, over 40 seeds per setting, on the zero-given board (Release,
    /// `killer-scan.sh --diag`):
    ///
    /// | maxCageSize | cages alone determine the grid | our chain closes it |
    /// |---|---|---|
    /// | 2 | 15/40 | 15/40 |
    /// | 3 | 5/40  | 2/40  |
    /// | 4 | 1/40  | 0/40  |
    /// | 5 | 0/40  | 0/40  |
    ///
    /// Two things fall out of that table. Small cages carry far more information
    /// — a two-cell cage summing to 17 admits exactly {8,9} — so uniqueness
    /// collapses as cages grow. And at size 2 the two columns are *equal*:
    /// whenever the cages determine the grid, the chain closes it, so technique
    /// coverage is not the binding constraint there. It starts to bind at 3.
    ///
    /// The cost is that size-2 boards close on naked singles (38 of 40 traces
    /// ended on one), so buying uniqueness with small cages spends the
    /// difficulty that made the tier worth having. That trade is the finding,
    /// and it is written up rather than tuned away.
    public let maxCageSize: Int

    public init(allowed: [Technique], maxGivens: Int, minVariantSteps: Int, maxCageSize: Int) {
        self.allowed = allowed
        self.maxGivens = maxGivens
        self.minVariantSteps = minVariantSteps
        self.maxCageSize = maxCageSize
    }

    public func admits(steps: [SolveStep], givens: Int) -> Bool {
        givens <= maxGivens
            && steps.count(where: { !$0.technique.isClassic }) >= minVariantSteps
    }
}

extension VariantTier {

    /// Killer's ladder. Two knobs move together: the chain widens and the clue
    /// ceiling falls, so Sharp is the real thing — no givens, cages only.
    public var killerBand: VariantBand {
        switch self {
        case .gentle:
            return VariantBand(
                allowed: [.nakedSingle, .hiddenSingle, .cageSingle,
                          .innieOutie, .cageCombination],
                maxGivens: 24,
                minVariantSteps: 3,
                maxCageSize: 4)
        case .steady:
            return VariantBand(
                allowed: [.nakedSingle, .hiddenSingle, .cageSingle,
                          .innieOutie, .cageCombination,
                          .nakedPair, .hiddenPair, .boxLineReduction],
                maxGivens: 10,
                minVariantSteps: 6,
                maxCageSize: 4)
        case .sharp:
            return VariantBand(
                allowed: Technique.allCases,
                maxGivens: 0,
                minVariantSteps: 10,
                maxCageSize: 3)
        }
    }
}

public enum VariantGenerator {

    /// How many seeded attempts a tier may spend before it gives up.
    ///
    /// **Calibrated against attempts, not against seconds.** PRD-17's budget was
    /// reasoned from wall-clock, fired on nearly every seed, and handed out
    /// boards a band below their label — while the measured compose time
    /// *improved*, so a timing test would have called it a win. See
    /// `PuzzleGenerator.attemptBudget` for the full story; the lesson is that
    /// the number has to bound the quantity it is actually counting.
    public static let attemptBudget: UInt64 = 3_000

    /// Compose a proven variant puzzle, or **nil** when this tier could not
    /// reach one from this seed inside the budget.
    ///
    /// Nil is a first-class answer and callers must handle it. A tier whose nil
    /// rate is not near zero is a tier that does not ship — which is the whole
    /// point of measuring before building a channel on top.
    ///
    /// `budget` is a parameter rather than a constant read straight off
    /// `attemptBudget` for one reason: the never-spin rule needs a test, and a
    /// test of it costs the *whole* budget by definition, since it can only pass
    /// by exhausting it. At the shipping budget that is 40 s in Debug against a
    /// `swift test` allowance with about 10 s of headroom left in it. The
    /// default is the real number; only the never-spin test passes anything else.
    public static func generate(
        seed: UInt64, variant: Variant, tier: VariantTier, budget: UInt64 = attemptBudget
    ) -> VariantPuzzle? {
        guard variant == .killer else { return nil }  // thermo is PRD-24
        let band = tier.killerBand
        var attempt: UInt64 = 0
        while attempt < budget {
            let sub = attemptSeed(seed, variant: variant, tier: tier, attempt: attempt)
            if let puzzle = attemptGenerate(
                attemptSeed: sub, baseSeed: seed, tier: tier, band: band) {
                return puzzle
            }
            attempt += 1
        }
        return nil
    }

    /// Mirrors `PuzzleGenerator.attemptSeed`, with a per-variant salt so killer
    /// seed 1 and classic seed 1 are unrelated boards.
    ///
    /// The salt is an **explicit constant**, never `variant.rawValue.hashValue`:
    /// Swift seeds `String`'s hash per process, so a hash in here would make
    /// `generate(seed:)` return a different board on every launch — the one
    /// property the whole golden-corpus discipline exists to protect.
    static func attemptSeed(
        _ seed: UInt64, variant: Variant, tier: VariantTier, attempt: UInt64
    ) -> UInt64 {
        var rng = SplitMix64(
            seed: seed
                ^ variant.seedSalt
                ^ (tier.index &* 0x9E37_79B9_7F4A_7C15)
                ^ (attempt &* 0xBF58_476D_1CE4_E5B9))
        return rng.next()
    }

    // MARK: - One attempt

    private static func attemptGenerate(
        attemptSeed: UInt64, baseSeed: UInt64, tier: VariantTier, band: VariantBand
    ) -> VariantPuzzle? {
        var rng = SplitMix64(seed: attemptSeed)
        let solution = BacktrackSolver.completeGrid(seed: rng.next())
        let cages = CageTiling.cages(of: solution, using: &rng, maxSize: band.maxCageSize)
        let constraints = cages.map(VariantConstraint.cage)
        let context = ConstraintContext.compile(constraints)

        var order = Array(0..<81)
        for i in stride(from: order.count - 1, to: 0, by: -1) {
            let j = rng.nextInt(below: i + 1)
            if i != j { order.swapAt(i, j) }
        }

        // Inverse dig. Each given is aimed at a cell the chain could not reach,
        // so every one strictly shrinks the unsolved set and the loop is bounded
        // by `maxGivens` without needing a separate guard.
        var puzzle = SudokuGrid()
        var added: [Int] = []
        var outcome = LogicSolver.solve(puzzle, allowed: band.allowed, context: context)
        while !outcome.solved {
            guard added.count < band.maxGivens else { return nil }
            guard let cell = order.first(where: { outcome.finalGrid[$0] == 0 }) else { return nil }
            puzzle[cell] = solution[cell]
            added.append(cell)
            outcome = LogicSolver.solve(puzzle, allowed: band.allowed, context: context)
        }

        // Trim, newest first. A given added early to unstick one region is often
        // redundant once a later one opened the board up, and the chain closing
        // is proof enough to drop it: a complete forced chain has exactly one
        // outcome, so uniqueness comes along with it.
        for cell in added.reversed() {
            let saved = puzzle[cell]
            puzzle[cell] = 0
            let trimmed = LogicSolver.solve(puzzle, allowed: band.allowed, context: context)
            if trimmed.solved {
                outcome = trimmed
            } else {
                puzzle[cell] = saved
            }
        }

        return verify(
            puzzle: puzzle, solution: solution, constraints: constraints, context: context,
            baseSeed: baseSeed, tier: tier, band: band)
    }

    /// Prove it from scratch rather than trusting the loop above: unique under
    /// the cages, solvable inside the band's chain, agreeing with the grid it
    /// was built from, and carrying enough variant reasoning to be a killer
    /// board rather than a classic one wearing cages.
    static func verify(
        puzzle: SudokuGrid,
        solution: SudokuGrid,
        constraints: [VariantConstraint],
        context: ConstraintContext,
        baseSeed: UInt64,
        tier: VariantTier,
        band: VariantBand
    ) -> VariantPuzzle? {
        guard case .unique(let proven)? = ConstraintBacktrackSolver.countSolutions(
            of: puzzle, context: context, limit: 2),
              proven == solution else { return nil }
        let outcome = LogicSolver.solve(puzzle, allowed: band.allowed, context: context)
        guard outcome.solved, outcome.finalGrid == solution else { return nil }
        guard band.admits(steps: outcome.steps, givens: puzzle.givenCount) else { return nil }
        return VariantPuzzle(
            variant: .killer,
            tier: tier,
            constraints: constraints,
            puzzle: puzzle,
            solution: solution,
            seed: baseSeed,
            steps: outcome.steps)
    }
}
