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
/// never by clue count.
public enum Difficulty: String, CaseIterable, Sendable, Codable, Hashable {
    case gentle, steady, sharp

    /// Highest technique the puzzle may require.
    public var ceiling: Technique {
        switch self {
        case .gentle: return .hiddenSingle
        case .steady: return .boxLineReduction
        case .sharp: return .xWing
        }
    }

    /// Lowest rank the *hardest* required technique must reach (nil = none).
    public var floor: Technique? {
        switch self {
        case .gentle: return nil
        case .steady: return .nakedPair
        case .sharp: return .xWing
        }
    }

    public var allowedTechniques: [Technique] {
        LogicSolver.techniques(upTo: ceiling)
    }

    public var title: String {
        switch self {
        case .gentle: return "Gentle"
        case .steady: return "Steady"
        case .sharp: return "Sharp"
        }
    }

    var index: UInt64 {
        switch self {
        case .gentle: return 1
        case .steady: return 2
        case .sharp: return 3
        }
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

    /// Generate a proven puzzle. Loops attempts (each fully deterministic
    /// from a seed derived by SplitMix64 mixing) until the verifier accepts.
    public static func generate(seed: UInt64, difficulty: Difficulty) -> GeneratedPuzzle {
        var attempt: UInt64 = 0
        while true {
            let sub = attemptSeed(seed, difficulty: difficulty, attempt: attempt)
            if let puzzle = attemptGenerate(attemptSeed: sub, baseSeed: seed, difficulty: difficulty) {
                return puzzle
            }
            attempt += 1
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

    private static func attemptGenerate(
        attemptSeed: UInt64, baseSeed: UInt64, difficulty: Difficulty
    ) -> GeneratedPuzzle? {
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
        case .sharp:
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
            while healIndex >= 0,
                  !LogicSolver.solve(puzzle, allowed: difficulty.allowedTechniques).solved {
                for cell in removed[healIndex] { puzzle[cell] = solution[cell] }
                healIndex -= 1
            }
        }

        return verify(puzzle: puzzle, solution: solution, baseSeed: baseSeed, difficulty: difficulty)
    }

    /// The verifier: proves uniqueness, technique-bounded solvability, the
    /// difficulty floor, and that the logic solution matches the built grid.
    /// Returns nil (discard the attempt) on any failure.
    static func verify(
        puzzle: SudokuGrid, solution: SudokuGrid, baseSeed: UInt64, difficulty: Difficulty
    ) -> GeneratedPuzzle? {
        guard case .unique(let proven) = BacktrackSolver.countSolutions(of: puzzle, limit: 2),
              proven == solution else { return nil }
        let outcome = LogicSolver.solve(puzzle, allowed: difficulty.allowedTechniques)
        guard outcome.solved, outcome.finalGrid == solution else { return nil }
        if let floor = difficulty.floor {
            guard let hardest = outcome.hardestTechnique, hardest >= floor else { return nil }
        }
        return GeneratedPuzzle(
            puzzle: puzzle,
            solution: solution,
            difficulty: difficulty,
            seed: baseSeed,
            steps: outcome.steps
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

    /// Days since the reference epoch in the given calendar's reckoning of
    /// `date`'s local day. Consecutive calendar days differ by exactly 1.
    public static func dayOrdinal(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: components)!
        return Int((midnight.timeIntervalSinceReferenceDate / 86_400).rounded(.down))
    }

    /// Stable daily seed: a hash of the calendar day (yyyymmdd).
    public static func seed(for date: Date, calendar: Calendar = .current) -> UInt64 {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let ymd = UInt64(components.year! * 10_000 + components.month! * 100 + components.day!)
        var rng = SplitMix64(seed: 0x9174_E5D1_0000_0000 ^ ymd)
        return rng.next()
    }
}
