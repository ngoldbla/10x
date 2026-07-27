// Generator.swift — guarantee-by-construction puzzle supply.
//
// Pipeline per attempt (all deterministic from one attempt seed):
//   1. Build a complete grid (seeded backtracking).
//   2. Dig holes in 180°-rotation-symmetric orbits, in a seeded shuffle order.
//   3. Prove the result: unique (count-limited backtracking) AND solvable by
//      the requested difficulty's technique chain AND hard enough for its band.
// Any failure discards the attempt and moves to the next derived seed, so a
// returned puzzle is unique + technique-bounded *by construction*, and the
// whole thing is a pure function of (seed, difficulty).
import Foundation
import CouchCore

/// Difficulty is defined by the hardest technique the logic chain needs —
/// never by clue count. Nocturne is the one exception, and it is a deliberate
/// one: it shares Sharp's technique chain exactly (PRD-17 §1 — new solver
/// techniques are a future engine PRD) and separates itself by *density*
/// instead, through `demands`.
///
/// **The raw values are frozen, and they are also the localization identity**
/// (PRD-20). They are persisted inside every `GeneratedPuzzle` and so inside the
/// 56 golden-corpus hashes, and `Difficulty.gentle` is `difficulty.gentle.title`
/// in the catalog — derived mechanically rather than mapped by hand, because a
/// hand-written map is a second list that can disagree with the one the hash
/// already pins.
///
/// There is deliberately no `title` here. It used to sit below
/// `allowedTechniques` and return English; the Engine compiles on Linux and must
/// never reach a bundle, so it does not get to name things.
/// `StringSealTests.testEngineNamesNothing` is what keeps it gone. The English
/// moved to `EnglishPhrases.table` and the translations to
/// `Sources/Strings/Localizable.xcstrings`; `Strings.difficulty(_:)` is the
/// App-layer accessor and `SolveCardFacts` the Shared one.
public enum Difficulty: String, CaseIterable, Sendable, Codable, Hashable {
    case gentle, steady, sharp, nocturne

    /// Highest technique the puzzle may require.
    public var ceiling: Technique {
        switch self {
        case .gentle: return .hiddenSingle
        case .steady: return .boxLineReduction
        case .sharp, .nocturne: return .xWing
        }
    }

    /// Lowest rank the *hardest* required technique must reach (nil = none).
    public var floor: Technique? {
        switch self {
        case .gentle: return nil
        case .steady: return .nakedPair
        case .sharp, .nocturne: return .xWing
        }
    }

    public var allowedTechniques: [Technique] {
        LogicSolver.techniques(upTo: ceiling)
    }

    /// Extra proof obligations beyond the technique band, applied by `verify`.
    /// Nil for the three bands that are defined by their chain alone.
    ///
    /// Nocturne's two numbers are measured, not chosen. `scripts/compose-scan.sh`
    /// is the scan and DEVIATIONS.md holds the table; the short version
    /// is that these are the settings at which a proven Nocturne board still
    /// composes in front of a waiting player, and the obvious harder settings
    /// are not — 24 givens costs 13× and a second X-wing costs 16×, both of
    /// which put p95 past a minute on device.
    public var demands: BandDemands? {
        switch self {
        case .gentle, .steady, .sharp: return nil
        case .nocturne:
            return BandDemands(maxGivens: 26, advancedFloor: .boxLineReduction, minAdvancedSteps: 3)
        }
    }

    var index: UInt64 {
        switch self {
        case .gentle: return 1
        case .steady: return 2
        case .sharp: return 3
        case .nocturne: return 4
        }
    }
}

/// What a band asks of a candidate puzzle *on top of* being unique and
/// solvable inside its technique chain.
///
/// This exists because Nocturne is a generator-parameter difficulty. Sharp's
/// floor already requires one X-wing, so "harder than Sharp without new
/// techniques" can only mean two things a board can be measured for: fewer
/// clues, and more weight on the top technique. Both are proven by the verifier
/// from the same `SolveStep` trace the band was already checked against — no
/// new solver machinery, and the proof travels inside `GeneratedPuzzle`.
public struct BandDemands: Sendable, Equatable {
    /// The clue ceiling. A candidate with more givens than this is discarded.
    public let maxGivens: Int
    /// Which techniques count as "advanced" for `minAdvancedSteps`.
    public let advancedFloor: Technique
    /// How many steps at or above `advancedFloor` the proven solve must need.
    /// This is the density knob: it is what stops a lean board that happens to
    /// fall out in a handful of singles from passing as the deep end.
    public let minAdvancedSteps: Int

    public init(maxGivens: Int, advancedFloor: Technique, minAdvancedSteps: Int) {
        self.maxGivens = maxGivens
        self.advancedFloor = advancedFloor
        self.minAdvancedSteps = minAdvancedSteps
    }

    /// Whether a proven solve trace satisfies the density half of the band.
    public func admits(steps: [SolveStep]) -> Bool {
        steps.count(where: { $0.technique >= advancedFloor }) >= minAdvancedSteps
    }
}

/// A proven puzzle: grid, solution, and the full explanation trace the
/// verifier produced (serializable — the v2 coach's raw material).
public struct GeneratedPuzzle: Sendable, Codable, Equatable {
    public let puzzle: SudokuGrid
    public let solution: SudokuGrid
    public let difficulty: Difficulty
    /// The (base) seed the caller asked for — regenerating with the same
    /// seed + difficulty yields a byte-identical puzzle.
    public let seed: UInt64
    /// Ordered solver steps proving technique-bounded solvability.
    public let steps: [SolveStep]

    public var hardestTechnique: Technique? { steps.map(\.technique).max() }
    public var givenCount: Int { puzzle.givenCount }
}

public enum PuzzleGenerator {

    /// How many attempts a band with `demands` may spend before it settles for
    /// the closest board it proved. Bands without demands never reach it: their
    /// verifier rejects only on properties the dig already targets, so they
    /// converge in a handful of attempts and have done since 1.0.
    ///
    /// **Calibrated against attempts, not against seconds — the first version of
    /// this number was 500 and it was wrong.** Nocturne's wall-clock p50 is
    /// under a second, which reads like "a few attempts"; it is not. Most
    /// attempts are ~0.4 ms because the dig degenerates early and `verify`
    /// rejects on the X-wing floor before it costs anything, and roughly **one
    /// attempt in 500** actually clears uniqueness, the chain, the floor and
    /// both demands. A 500-attempt budget therefore fired on nearly every seed
    /// and quietly handed out Sharp-grade boards wearing a Nocturne label.
    /// Measured over 200 seeds with no budget at all, the search needs a p95 of
    /// ~12,000 attempts and a worst case near 20,000, so this sits an order of
    /// magnitude above the tail it is bounding.
    ///
    /// PRD-23 states the never-spin rule for variants; Nocturne is the first
    /// band it applies to.
    public static let attemptBudget: UInt64 = 200_000

    /// Generate a proven puzzle. Loops attempts (each fully deterministic
    /// from a seed derived by SplitMix64 mixing) until the verifier accepts.
    public static func generate(seed: UInt64, difficulty: Difficulty) -> GeneratedPuzzle {
        var attempt: UInt64 = 0
        // The best board proved so far that met everything *except* the band's
        // density demand — leanest first. Only ever non-nil for a band that has
        // demands, so the three 1.0 bands take a byte-identical path.
        var nearest: GeneratedPuzzle?
        while true {
            let sub = attemptSeed(seed, difficulty: difficulty, attempt: attempt)
            if let candidate = attemptGenerate(attemptSeed: sub, baseSeed: seed, difficulty: difficulty) {
                // A band with no demands always meets them, so gentle, steady
                // and sharp return on the first proven candidate exactly as
                // they did in 1.0 — the golden corpus is the proof.
                if candidate.meetsDemands { return candidate.puzzle }
                // Proven unique, inside the chain and past the floor; only the
                // density demand missed. Keep the leanest one seen, for free.
                if candidate.puzzle.givenCount < (nearest?.givenCount ?? .max) {
                    nearest = candidate.puzzle
                }
            }
            attempt += 1
            // Unreachable in practice (see `attemptBudget`), and `nearest` is
            // only ever non-nil for a band that has demands, so a band without
            // them keeps its original unbounded loop. If it *is* reached, hand
            // back a genuinely proven board that fell one deduction short —
            // never a stall, and never an unproven puzzle.
            if attempt >= attemptBudget, let nearest { return nearest }
        }
    }

    static func attemptSeed(_ seed: UInt64, difficulty: Difficulty, attempt: UInt64) -> UInt64 {
        var rng = SplitMix64(
            seed: seed
                ^ (difficulty.index &* 0x9E37_79B9_7F4A_7C15)
                ^ (attempt &* 0xBF58_476D_1CE4_E5B9)
        )
        return rng.next()
    }

    // MARK: - One attempt

    /// A proven candidate plus whether it also satisfied the band's `demands`.
    /// Split so one pass answers both questions: the retry loop needs "keep
    /// looking", and the budget backstop needs the best board seen so far.
    struct Candidate {
        let puzzle: GeneratedPuzzle
        let meetsDemands: Bool
    }

    private static func attemptGenerate(
        attemptSeed: UInt64, baseSeed: UInt64, difficulty: Difficulty
    ) -> Candidate? {
        var rng = SplitMix64(seed: attemptSeed)
        let solution = BacktrackSolver.completeGrid(seed: rng.next())
        let orbits = shuffledOrbits(using: &rng)

        var puzzle = solution
        switch difficulty {
        case .gentle:
            // Dig while a singles-only solve still completes. A singles solve
            // that finishes is a chain of forced moves — uniqueness follows,
            // but the verifier below re-proves it anyway.
            for orbit in orbits {
                let saved = orbit.map { puzzle[$0] }
                for cell in orbit { puzzle[cell] = 0 }
                if !LogicSolver.solve(puzzle, allowed: difficulty.allowedTechniques).solved {
                    for (offset, cell) in orbit.enumerated() { puzzle[cell] = saved[offset] }
                }
            }
        case .steady:
            // Dig while unique AND still solvable inside the steady chain.
            for orbit in orbits {
                let saved = orbit.map { puzzle[$0] }
                for cell in orbit { puzzle[cell] = 0 }
                let keeps = BacktrackSolver.isUnique(puzzle)
                    && LogicSolver.solve(puzzle, allowed: difficulty.allowedTechniques).solved
                if !keeps {
                    for (offset, cell) in orbit.enumerated() { puzzle[cell] = saved[offset] }
                }
            }
        case .sharp, .nocturne:
            // Dig for maximal uniqueness first (fast), then let the healing
            // pass below back off if the result overshoots the X-wing chain.
            var removed: [[Int]] = []
            for orbit in orbits {
                let saved = orbit.map { puzzle[$0] }
                for cell in orbit { puzzle[cell] = 0 }
                if BacktrackSolver.isUnique(puzzle) {
                    removed.append(orbit)
                } else {
                    for (offset, cell) in orbit.enumerated() { puzzle[cell] = saved[offset] }
                }
            }
            // Healing: while the full chain is stuck (puzzle needs techniques
            // beyond X-wing), restore dug orbits one at a time. Each restore
            // only makes the puzzle easier; stop at the first solvable state.
            var healIndex = removed.count - 1
            var restored: [[Int]] = []
            while healIndex >= 0,
                  !LogicSolver.solve(puzzle, allowed: difficulty.allowedTechniques).solved {
                for cell in removed[healIndex] { puzzle[cell] = solution[cell] }
                restored.append(removed[healIndex])
                healIndex -= 1
            }
            // Nocturne only — sharp's output must not move (the golden corpus
            // is the proof that it doesn't). Healing walks the dig order
            // backwards and stops at the first solvable state, so it routinely
            // puts back a whole run of orbits when the chain only needed one of
            // them. Offer each restored orbit back to the hole: keep it out
            // whenever the board stays unique and stays inside the chain. That
            // drives the clue count to a local minimum by construction instead
            // of leaving it to the luck of the dig order, which is what makes
            // Nocturne's clue ceiling reachable without pure rejection.
            if difficulty == .nocturne {
                for orbit in restored {
                    let saved = orbit.map { puzzle[$0] }
                    for cell in orbit { puzzle[cell] = 0 }
                    let keeps = BacktrackSolver.isUnique(puzzle)
                        && LogicSolver.solve(puzzle, allowed: difficulty.allowedTechniques).solved
                    if !keeps {
                        for (offset, cell) in orbit.enumerated() { puzzle[cell] = saved[offset] }
                    }
                }
            }
        }

        return verify(puzzle: puzzle, solution: solution, baseSeed: baseSeed, difficulty: difficulty)
    }

    /// The verifier: proves uniqueness, technique-bounded solvability, the
    /// difficulty floor, and that the logic solution matches the built grid.
    /// Returns nil (discard the attempt) on any failure.
    static func verify(
        puzzle: SudokuGrid, solution: SudokuGrid, baseSeed: UInt64, difficulty: Difficulty
    ) -> Candidate? {
        guard case .unique(let proven) = BacktrackSolver.countSolutions(of: puzzle, limit: 2),
              proven == solution else { return nil }
        let outcome = LogicSolver.solve(puzzle, allowed: difficulty.allowedTechniques)
        guard outcome.solved, outcome.finalGrid == solution else { return nil }
        if let floor = difficulty.floor {
            guard let hardest = outcome.hardestTechnique, hardest >= floor else { return nil }
        }
        // The band's extra obligations are reported, not enforced: a candidate
        // that misses them is still a proven puzzle, and the budget backstop in
        // `generate` is the only thing that will ever hand one out.
        let meets = difficulty.demands.map {
            puzzle.givenCount <= $0.maxGivens && $0.admits(steps: outcome.steps)
        } ?? true
        return Candidate(
            puzzle: GeneratedPuzzle(
                puzzle: puzzle,
                solution: solution,
                difficulty: difficulty,
                seed: baseSeed,
                steps: outcome.steps
            ),
            meetsDemands: meets
        )
    }

    /// 41 dig orbits with 180° rotational symmetry: the center cell alone,
    /// plus 40 pairs (i, 80−i), in a seeded shuffle order.
    static func shuffledOrbits(using rng: inout SplitMix64) -> [[Int]] {
        var orbits: [[Int]] = (0..<40).map { [$0, 80 - $0] }
        orbits.append([40])
        for i in stride(from: orbits.count - 1, to: 0, by: -1) {
            let j = rng.nextInt(below: i + 1)
            if i != j { orbits.swapAt(i, j) }
        }
        return orbits
    }
}

/// Deterministic (date, difficulty) → seed mapping for the daily puzzle,
/// plus the day ordinal the streak logic keys on.
public enum DailySeed {

    /// A day ordinal is a UTC midnight by construction (see `dayOrdinal`), so
    /// every conversion back out of one has to read it in UTC. Rendering one in
    /// the player's own zone lands a day early everywhere west of Greenwich —
    /// silently, with no crash and no warning.
    public static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Days since the reference epoch in the given calendar's reckoning of
    /// `date`'s local day. Consecutive calendar days differ by exactly 1.
    public static func dayOrdinal(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let midnight = utcCalendar.date(from: components)!
        return Int((midnight.timeIntervalSinceReferenceDate / 86_400).rounded(.down))
    }

    /// Stable daily seed: a hash of the calendar day (yyyymmdd).
    public static func seed(for date: Date, calendar: Calendar = .current) -> UInt64 {
        seed(ymdOf: calendar.dateComponents([.year, .month, .day], from: date))
    }

    /// The same seed, addressed by day ordinal — what the archive composes from
    /// (PRD-14).
    ///
    /// Exact rather than approximate, and the asymmetry above is why: `seed(for:)`
    /// hashes the **local** y/m/d, and `dayOrdinal` takes that same local y/m/d
    /// and reinterprets it as a **UTC** midnight. The ordinal therefore already
    /// *is* the local calendar day, re-encoded — so reading it back in UTC
    /// recovers precisely the components `seed(for:)` hashed, with no calendar
    /// round-trip and no timezone hazard. Pinned across four zones by
    /// `testSeedForDayOrdinalMatchesSeedForDate`.
    public static func seed(forDayOrdinal ordinal: Int) -> UInt64 {
        let midnight = Date(timeIntervalSinceReferenceDate: TimeInterval(ordinal) * 86_400)
        return seed(ymdOf: utcCalendar.dateComponents([.year, .month, .day], from: midnight))
    }

    /// The one place the daily mapping's constant lives. Both entry points
    /// funnel here so they cannot drift; `testDailySeedForAKnownDayIsFrozen`
    /// and the golden corpus are the two proofs that extracting it moved
    /// nothing.
    private static func seed(ymdOf components: DateComponents) -> UInt64 {
        let ymd = UInt64(components.year! * 10_000 + components.month! * 100 + components.day!)
        var rng = SplitMix64(seed: 0x9174_E5D1_0000_0000 ^ ymd)
        return rng.next()
    }
}
