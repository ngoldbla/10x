// Darkroom engine — the coach ray (PRD §4.4).
//
// Picks one row or column where progress is *provable* by the line solver
// from the player's current knowledge. It never fills cells and never
// explains — it only points where to look. Rate limiting is pure
// bookkeeping so it persists in snapshots and tests without a clock.
import Foundation

/// Where the ray settles, and how much is provably learnable there.
public struct CoachHint: Sendable, Equatable {
    public enum Target: Sendable, Equatable, Hashable {
        case row(Int)
        case column(Int)
    }
    public let target: Target
    /// Number of cells single-line logic resolves on that line right now.
    public let deducibleCells: Int
}

public enum CoachRay {

    /// The line with the most provable progress, or `nil` when the board is
    /// solved. Since marks are always consistent with the solution (wrong
    /// moves are refused) and puzzles are line-solvable by construction, an
    /// unsolved board always yields a hint. Ties break toward earlier rows.
    public static func hint(for session: PuzzleSession) -> CoachHint? {
        guard !session.isSolved else { return nil }
        let n = session.size
        let states = session.knowledge
        var best: CoachHint?

        func consider(_ target: CoachHint.Target, clues: [Int], line: [CellState]) {
            guard let deduced = LineSolver.deduce(clues: clues, line: line) else { return }
            var gain = 0
            for i in 0..<n where deduced[i] != line[i] { gain += 1 }
            guard gain > 0 else { return }
            if best == nil || gain > best!.deducibleCells {
                best = CoachHint(target: target, deducibleCells: gain)
            }
        }

        for y in 0..<n {
            consider(
                .row(y),
                clues: session.puzzle.rowClues[y],
                line: (0..<n).map { states[y * n + $0] }
            )
        }
        for x in 0..<n {
            consider(
                .column(x),
                clues: session.puzzle.colClues[x],
                line: (0..<n).map { states[$0 * n + x] }
            )
        }
        return best
    }
}

/// One ray per 90 seconds (PRD §4.4). Pure, time-injected, Codable so the
/// cooldown survives auto-save.
public struct CoachRayLimiter: Sendable, Codable, Equatable {
    public let cooldown: TimeInterval
    public private(set) var lastFired: Date?

    public init(cooldown: TimeInterval = 90, lastFired: Date? = nil) {
        self.cooldown = cooldown
        self.lastFired = lastFired
    }

    /// Refill fraction for the glass ring, `[0, 1]`.
    public func readiness(at now: Date) -> Double {
        guard let lastFired else { return 1 }
        guard cooldown > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(lastFired) / cooldown))
    }

    public func isReady(at now: Date) -> Bool {
        readiness(at: now) >= 1
    }

    /// Consume the ray. Returns false (and stays untouched) when cooling.
    @discardableResult
    public mutating func fire(at now: Date) -> Bool {
        guard isReady(at: now) else { return false }
        lastFired = now
        return true
    }
}
