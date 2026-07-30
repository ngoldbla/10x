// VariantGenerator.swift — variant supply, by the inverse of the classic dig.
//
// Classic generation starts from a full grid and *removes* clues while the
// puzzle stays provable. A variant cannot: the rules already carry much of the
// information, and a real killer board has **no givens at all**, so digging from
// 81 clues would spend its whole budget walking down to zero. The pipeline
// inverts:
//
//   1. a seeded complete grid (the frozen `BacktrackSolver.completeGrid`)
//   2. a seeded rule layout over it, read off the solution — cages with their
//      sums, or thermometers along increasing runs — so every rule is satisfied
//      by construction and only *uniqueness* is left
//   3. start from an empty board and **add** givens, one at a time, aimed at
//      wherever the technique chain got stuck, until the chain solves it
//   4. trim: offer each added given back, keep it out when the chain still
//      closes — the same local-minimum trick Nocturne's re-dig uses
//   5. prove: unique under the rules, chain-bounded, and enough of the trace is
//      actual variant reasoning that the rules are not decoration
//
// **Step 2 is the only step that knows which variant it is.** PRD-24 added thermo
// by adding a case to one switch (`constraints(for:of:using:)`); steps 3–5 are
// shared, so thermo inherits the dig, the trim and the verifier that killer's
// measured 100/100-per-tier numbers were taken against, rather than a second copy
// of them that has to be kept in step by hand. Delegate, don't fork — the same
// rule PRD-23 applied to the classic solver paths.
//
// **There is no `while true` here.** PRD-23 states the never-spin rule for
// variants and PRD-17 is the story of why: an attempt budget calibrated against
// wall-clock rather than against attempts fired on nearly every seed and handed
// out boards wearing the wrong label, while the timing *improved*. This budget
// is calibrated against attempts, and when it runs out `generate` returns nil
// rather than a board that missed its band.
import Foundation
import CouchCore

/// The geometry a variant's tiler is asked for, one case per ruleset.
///
/// This is an enum rather than a bag of optional knobs on `VariantBand` so that
/// **a thermo band cannot read a cage size**. PRD-23 shipped with `maxCageSize`
/// as a plain field, which was correct while killer was the only ruleset and
/// becomes a trap the moment a second one exists: a thermo band would have
/// carried a meaningless cage size, and the one line that forgot to ignore it
/// would have compiled.
public enum VariantShape: Sendable, Equatable {

    /// Killer. `maxSize` is the largest cage the tiler may build, and the knob
    /// that actually decides whether a tier has any supply at all.
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
    /// and it is written up rather than tuned away. If a harder Sharp is ever
    /// wanted the lever is a *designed* cage layout, not a smaller one.
    case cages(maxSize: Int)

    /// Thermo. How many tubes to aim for, and the length window each may take.
    ///
    /// Neither knob is the cage-size knob wearing a different name, because a
    /// thermometer's information is **positional** rather than printed: a cage
    /// announces its sum, while a tube's constraint is spent by
    /// `initialCandidates` before the first technique runs. So the supply
    /// question is *coverage* — how much of the board a tube touches — and the
    /// length window is where the density lives. A 2-cell tube says "a < b" and
    /// almost nothing else; a 9-cell tube fixes 1…9 in order along a whole line.
    case thermometers(count: Int, length: ClosedRange<Int>)
}

/// What a variant tier asks of a candidate board on top of being unique and
/// solvable inside its chain.
public struct VariantBand: Sendable, Equatable {
    /// The techniques the proven solve may use.
    public let allowed: [Technique]
    /// The clue ceiling. Zero is the real killer aesthetic — the cages alone
    /// determine the grid — and the higher killer tiers get there. Thermo never
    /// does, and that is a property of the ruleset rather than of the ladder:
    /// see `thermoBand`.
    public let maxGivens: Int
    /// How many steps of the proven trace must be variant reasoning. Without
    /// this a "killer" board can be one the classic chain would have solved
    /// anyway, with the cages as decoration — and the thermo failure mode is the
    /// same sentence with "tubes drawn on it" at the end.
    public let minVariantSteps: Int
    /// The geometry the tiler is asked for.
    public let shape: VariantShape

    public init(
        allowed: [Technique], maxGivens: Int, minVariantSteps: Int, shape: VariantShape
    ) {
        self.allowed = allowed
        self.maxGivens = maxGivens
        self.minVariantSteps = minVariantSteps
        self.shape = shape
    }

    public func admits(steps: [SolveStep], givens: Int) -> Bool {
        givens <= maxGivens
            && steps.count(where: { !$0.technique.isClassic }) >= minVariantSteps
    }
}

extension VariantTier {

    /// The band for a tier *of a given ruleset*, or nil for a ruleset with no
    /// supply. Nil is the answer `VariantGenerator` turns into nil, and the
    /// reason `.classic` and `.unrecognized` can never accidentally compose.
    public func band(for variant: Variant) -> VariantBand? {
        switch variant {
        case .killer: return killerBand
        case .thermo: return thermoBand
        case .classic, .unrecognized: return nil
        }
    }

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
                shape: .cages(maxSize: 4))
        case .steady:
            return VariantBand(
                allowed: [.nakedSingle, .hiddenSingle, .cageSingle,
                          .innieOutie, .cageCombination,
                          .nakedPair, .hiddenPair, .boxLineReduction],
                maxGivens: 10,
                minVariantSteps: 6,
                shape: .cages(maxSize: 4))
        case .sharp:
            return VariantBand(
                allowed: Technique.allCases,
                maxGivens: 0,
                minVariantSteps: 10,
                shape: .cages(maxSize: 3))
        }
    }

    /// Thermo's ladder, and it does **not** mirror killer's.
    ///
    /// Killer's ladder walks the clue ceiling down to zero because a cage tiling
    /// carries enough printed information to determine a grid on its own. A
    /// thermometer layout does not and cannot: it covers the board partially by
    /// construction, and a board of nine tubes still has forty-odd cells no tube
    /// touches. A zero-given thermo board is not a purer thermo board, it is an
    /// ambiguous one. So the clue ceiling stays well above zero at every tier and
    /// the ladder is walked with the other three knobs — chain width,
    /// `minVariantSteps`, and tube length.
    ///
    /// **These numbers were measured, not chosen**, and the first draft of them
    /// was wrong in an instructive way. `scripts/thermo-scan.sh 200` on the draft
    /// composed 200/200 at every tier, which looks like a pass — but the shape
    /// report showed `maxGivens` set to 30/24/18 against a measured *max* of
    /// 19/19/11, and `minVariantSteps` set to 3/6/10 against a measured p50 of
    /// 11/13/18. **Neither knob could ever reject anything.** A band parameter
    /// that cannot fire is not a constraint, it is a decision dressed as one, and
    /// the tier would have been defined by whatever the dig happened to do.
    ///
    /// What actually separates the tiers is the third knob, and this is the
    /// finding worth keeping: **a wider chain closes the board with fewer
    /// givens**, because the extra techniques do work the clues would otherwise
    /// have to do. Gentle lands at 15 givens (p50), Steady at 12, Sharp at 7 — a
    /// real ladder, and a better-separated one than killer's compressed 6/4/0
    /// (PRD-23 §5 left "does that read as three tiers" open; for thermo it does).
    ///
    /// So both dead knobs are tightened to sit just above the measured
    /// distribution, where they are genuine tripwires: a layout pathological
    /// enough to need 25 clues, or a board whose tubes turn out to be decoration,
    /// is now rejected instead of shipped. The cost is paid in attempts, not in
    /// supply — see PRD-24 §3.2 for the re-measured table.
    public var thermoBand: VariantBand {
        switch self {
        case .gentle:
            return VariantBand(
                allowed: [.nakedSingle, .hiddenSingle, .thermoBound],
                maxGivens: 24,
                minVariantSteps: 6,
                shape: .thermometers(count: 8, length: 3...5))
        case .steady:
            return VariantBand(
                allowed: [.nakedSingle, .hiddenSingle, .thermoBound,
                          .nakedPair, .hiddenPair, .boxLineReduction],
                maxGivens: 22,
                minVariantSteps: 9,
                shape: .thermometers(count: 9, length: 3...6))
        case .sharp:
            return VariantBand(
                allowed: Technique.allCases,
                maxGivens: 16,
                minVariantSteps: 14,
                shape: .thermometers(count: 10, length: 4...7))
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
        guard let band = tier.band(for: variant) else { return nil }
        var attempt: UInt64 = 0
        while attempt < budget {
            let sub = attemptSeed(seed, variant: variant, tier: tier, attempt: attempt)
            if let puzzle = attemptGenerate(
                attemptSeed: sub, baseSeed: seed, variant: variant, tier: tier, band: band) {
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

    /// The rules a shape asks for, over a solved grid. **This switch is the only
    /// difference between killer supply and thermo supply** — everything after it
    /// in `attemptGenerate` is shared, which is what makes thermo inherit the dig,
    /// the trim and the verifier that killer's 100/100-per-tier numbers were
    /// measured against rather than a second copy of them to keep in step.
    static func constraints(
        for shape: VariantShape, of solution: SudokuGrid, using rng: inout SplitMix64
    ) -> [VariantConstraint] {
        switch shape {
        case .cages(let maxSize):
            return CageTiling.cages(of: solution, using: &rng, maxSize: maxSize)
                .map(VariantConstraint.cage)
        case .thermometers(let count, let length):
            return ThermoTiling.thermometers(
                of: solution, using: &rng, count: count, length: length)
                .map(VariantConstraint.thermometer)
        }
    }

    private static func attemptGenerate(
        attemptSeed: UInt64, baseSeed: UInt64, variant: Variant,
        tier: VariantTier, band: VariantBand
    ) -> VariantPuzzle? {
        var rng = SplitMix64(seed: attemptSeed)
        let solution = BacktrackSolver.completeGrid(seed: rng.next())
        let constraints = constraints(for: band.shape, of: solution, using: &rng)
        guard !constraints.isEmpty else { return nil }
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
            baseSeed: baseSeed, variant: variant, tier: tier, band: band)
    }

    /// Prove it from scratch rather than trusting the loop above: unique under
    /// the rules, solvable inside the band's chain, agreeing with the grid it
    /// was built from, and carrying enough variant reasoning to be a killer or
    /// thermo board rather than a classic one wearing cages or tubes.
    static func verify(
        puzzle: SudokuGrid,
        solution: SudokuGrid,
        constraints: [VariantConstraint],
        context: ConstraintContext,
        baseSeed: UInt64,
        variant: Variant,
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
            variant: variant,
            tier: tier,
            constraints: constraints,
            puzzle: puzzle,
            solution: solution,
            seed: baseSeed,
            steps: outcome.steps)
    }
}
