// CometTimeline.swift — where the comet is at any instant (PRD-26 §2.1).
//
// A pure function of elapsed time, exactly like `AfterglowPhase`, and for the
// same reason: the thing that decides *what* is drawn tests on Linux in
// microseconds, and the thing that decides *how* is a `Canvas` with no
// branching left in it. Three surfaces draw this one timeline — the debrief's
// board, the share card's 888 pt body, and the Apple TV's ambient screen — so
// there is exactly one answer to "where is the head" and they cannot disagree.
//
// **The two motions PROGRAM-2.0 asks for are both consequences of the mapping,
// not special cases in the drawing.**
//
//   • *Hesitations slow it.* Moves are placed on the loop in proportion to
//     their own `at` stamps, so ten seconds of staring is ten seconds of the
//     loop where the head sits still. Nothing measures a hesitation; the
//     timeline just isn't uniform.
//   • *Erasures loop retrograde.* An erase or an undo is a beat like any
//     other, flagged — the head arrives at the cell it is about to empty, and
//     the drawing runs its tail the other way.
//
// On an untimed log the stamps are replaced by an even spread and nothing else
// changes (PRD-26 §2.3): the moves are true, only their spacing is invented,
// and the comet does not say so.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

/// The comet at one instant.
public struct CometFrame: Equatable, Sendable {
    /// The board as it stood, 81 entries, 0 for empty.
    public let entries: [Int]
    /// The cell the head is travelling from, and the one it is arriving at.
    /// Both nil before the first beat.
    public let from: Int?
    public let to: Int?
    /// How far along that hop, 0...1. The view lerps two cell centres by it.
    public let t: Double
    /// Recent cells behind the head, nearest first.
    public let tail: [Int]
    /// The arriving beat takes something off the board rather than putting
    /// something on it.
    public let isRetrograde: Bool

    public init(
        entries: [Int], from: Int?, to: Int?, t: Double, tail: [Int], isRetrograde: Bool
    ) {
        self.entries = entries
        self.from = from
        self.to = to
        self.t = t
        self.tail = tail
        self.isRetrograde = isRetrograde
    }
}

public enum CometTimeline {

    /// One loop. PROGRAM-2.0 §Pillar C sets it, the share card's body inherits
    /// it, and a solve of any length is fitted to it — a comet whose duration
    /// advertised how long you took would be a leaderboard with an animation.
    public static let loopSeconds: TimeInterval = 5

    /// How many cells trail behind the head. Long enough to read as a path,
    /// short enough that a 300-move solve does not end up a lit board.
    public static let tailLength = 6

    /// Where each move sits on the 0...1 loop.
    ///
    /// Timed logs are spread by their own stamps, **rebased on the first
    /// move** — the pause before the opening digit is the player reading the
    /// board, and opening the loop on a still frame of nothing is dead air.
    ///
    /// Untimed logs get an even spread. That is the whole of PRD-26 §2.3's
    /// "old logs replay at uniform cadence": one branch, here, and nothing
    /// downstream can tell which one it took.
    public static func normalizedTimes(_ moves: [LoggedMove]) -> [Double] {
        let count = moves.count
        guard count > 1 else { return moves.isEmpty ? [] : [0] }
        let stamps = moves.compactMap(\.at)
        guard stamps.count == count, let first = stamps.first, let last = stamps.last,
              last > first else {
            return (0..<count).map { Double($0) / Double(count - 1) }
        }
        let span = last - first
        // Monotone by construction — `at` is elapsed time on a timer that only
        // moves forward — but clamped anyway, because a hand-edited or
        // clock-skewed log must not produce a head that jumps backwards.
        var previous = 0.0
        return stamps.map { stamp in
            previous = max(previous, min(1, (stamp - first) / span))
            return previous
        }
    }

    /// The frame at `phase` (0...1) through the loop.
    public static func frame(at phase: Double, puzzle: [Int], moves: [LoggedMove]) -> CometFrame {
        let clamped = min(1, max(0, phase))
        guard puzzle.count == 81, !moves.isEmpty else {
            return CometFrame(
                entries: puzzle.count == 81 ? puzzle : [Int](repeating: 0, count: 81),
                from: nil, to: nil, t: 0, tail: [], isRetrograde: false
            )
        }
        let times = normalizedTimes(moves)

        // **The head lives on the interval between two beats, not on a beat.**
        // The first version advanced only once a move's time had already
        // passed, so the head teleported onto each cell at the instant of its
        // move and stood still until the next — no travel, and `t` was always
        // 1. `departing` is the last beat that has happened; `arriving` is the
        // one being flown to.
        var departing = 0
        while departing + 1 < times.count, times[departing + 1] <= clamped { departing += 1 }
        let arriving = min(departing + 1, times.count - 1)

        // A zero-length hop — two moves inside the same decisecond — reads as
        // arrived rather than dividing by zero.
        let start = times[departing], end = times[arriving]
        let t = end > start ? min(1, max(0, (clamped - start) / (end - start))) : 1

        return CometFrame(
            // Through `departing + 1`: every beat that has happened is on the
            // board, and the one being flown to is not yet.
            entries: ReplayWalk.board(puzzle: puzzle, moves: moves, through: departing + 1),
            from: moves[departing].cell,
            to: moves[arriving].cell,
            t: t,
            tail: moves[..<departing].suffix(tailLength).map(\.cell).reversed(),
            // The beat being *arrived at*, so the head reaches a cell and the
            // digit leaves as it lands.
            isRetrograde: moves[arriving].kind == .erase || moves[arriving].kind == .undo
        )
    }

    /// The frame at a wall-clock instant, looping forever from `start`.
    public static func frame(
        at now: Date, since start: Date, puzzle: [Int], moves: [LoggedMove]
    ) -> CometFrame {
        let elapsed = max(0, now.timeIntervalSince(start))
        let phase = elapsed.truncatingRemainder(dividingBy: loopSeconds) / loopSeconds
        return frame(at: phase, puzzle: puzzle, moves: moves)
    }
}
