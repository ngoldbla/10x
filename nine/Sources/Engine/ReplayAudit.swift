// ReplayAudit.swift — what a solve can be made to prove about itself before it
// is submitted to a leaderboard (PRD-29 §5).
//
// **No new solving code**, which is the same rule `ReplayAnalysis` kept and for
// the same reason: the prover that decides what a board's answer is has been
// `BacktrackSolver` since 1.0, and the walker that unwinds an undo has been
// `ReplayWalk` since PRD-26. A second copy of either would drift silently, and a
// desynced auditor is worse than none — it accuses honest players on a schedule
// nobody can reproduce.
//
// Three things this file is careful to be:
//
//   * **Opinion-free about the person.** A finding is a fact about a record, and
//     nothing here maps one to a sentence. PRD-29 §5's rule is that the audit is
//     a gate on *submission*, never a judgement, and the covenant's ban on
//     streak shaming reads the same way one layer over.
//   * **Honest about its reach.** This runs on the player's own device against
//     the player's own replay, so it is no defence at all against a patched
//     binary — and there is no server to move it to, because "no server" was the
//     premise. What it is worth is every *non-adversarial* way a wrong number
//     arrives: a truncated vault, a clock that jumped, a log from a build that
//     has not shipped yet.
//   * **Falsifiable, per check.** PRD-24 shipped a band whose two knobs composed
//     200/200 and could never have rejected anything. Every finding below has a
//     test that constructs the input producing it, and the one that cannot fire
//     through today's only caller says so in its own doc comment rather than
//     collecting a green tick it did not earn.
//
// Pure Foundation plus the Engine's own types, so it tests on Linux.
import Foundation

/// Re-simulating a solve, and the small vocabulary of ways one can fail to add up.
public enum ReplayAudit {

    /// One thing wrong with a record.
    ///
    /// A `String` raw value because it is the shape every stable identity in this
    /// repo has, and **deliberately never localized**: a finding is a diagnostic,
    /// not a sentence, and the moment one has a translation somebody will put it
    /// on a screen.
    public enum Finding: String, Sendable, Codable, Hashable, CaseIterable {
        /// The packed blob does not unpack, or the grid is not 81 digits.
        case unreadable
        /// The board has no single answer to compare the walk against — no
        /// solution at all, or more than one. Both are the same absence.
        case notProvable
        /// A move the game would never have accepted: off the board, or written
        /// onto a clue.
        case illegalMove
        /// The walked board is not the proven solution.
        case unfinished
        /// A stamp goes backwards.
        case nonMonotoneTiming
        /// The claimed elapsed time is shorter than the log's own last stamp,
        /// by more than the packed format's rounding can explain.
        case claimShorterThanLog
    }

    /// Every finding, or none.
    ///
    /// A set rather than a first-failure, because a doctored record rarely has
    /// one thing wrong with it and "the first reason we noticed" is not a useful
    /// thing to hold. The whole set costs one extra walk of an 81-cell array.
    public struct Verdict: Sendable, Equatable {
        public let findings: Set<Finding>

        public init(_ findings: Set<Finding> = []) {
            self.findings = findings
        }

        /// The only question a caller should be asking.
        public var isClean: Bool { findings.isEmpty }
    }

    /// The slack allowed between a claimed time and the log's last stamp.
    ///
    /// **Derived from the format, not chosen.** `SolveReplay.pack` rounds each
    /// inter-move delta to a decisecond *independently* — `previous` advances by
    /// the true stamp — so the reconstructed prefix sum can sit up to 0.05 s per
    /// move above the truth. That bound is exact, and using anything else would
    /// be the kind of number PRD-24 found in `thermoBand`: one nobody can defend.
    public static func timingTolerance(moveCount: Int) -> TimeInterval {
        0.05 * Double(max(0, moveCount))
    }

    /// Audit the record a submission would actually carry.
    ///
    /// An unpackable blob yields `.unreadable` and stops: there is no puzzle to
    /// prove and no path to walk, so every other finding would be an assertion
    /// about bytes nobody read.
    public static func audit(_ replay: SolveReplay) -> Verdict {
        guard let unpacked = SolveReplay.unpack(replay.packed) else {
            return Verdict([.unreadable])
        }
        return audit(
            puzzle: unpacked.puzzle, moves: unpacked.moves, claimedSeconds: replay.seconds)
    }

    /// The audit proper, over the two things a replay is plus the number it
    /// claims.
    ///
    /// Taking a `[LoggedMove]` rather than only a `SolveReplay` is what lets the
    /// timing checks be tested at all — the packed format cannot express a
    /// backwards stamp — and it is the door a future untrusted wire would come
    /// through (`ParlorFinish` already carries a `packed` from another device).
    public static func audit(
        puzzle: [Int], moves: [LoggedMove], claimedSeconds: TimeInterval
    ) -> Verdict {
        guard puzzle.count == 81, puzzle.allSatisfy({ (0...9).contains($0) }) else {
            return Verdict([.unreadable])
        }
        var findings: Set<Finding> = []

        // Legality is about the *log*, so it is asked before anything is walked:
        // `ReplayWalk` silently skips a cell off the board, which is right for a
        // renderer and would hide exactly this finding from an auditor.
        for move in moves {
            guard (0..<81).contains(move.cell), (0...9).contains(move.digit) else {
                findings.insert(.illegalMove)
                continue
            }
            // A clue is not the player's to touch. `NineGame.place` and
            // `.erase` both refuse a given, so a log containing one did not come
            // from the game — and an erased given also moves the board, which
            // would otherwise surface as `.unfinished` and name the wrong cause.
            if puzzle[move.cell] != 0, move.kind == .place || move.kind == .erase {
                findings.insert(.illegalMove)
            }
        }

        // Timing, from the log alone. Equal stamps are fine: a zero delta is
        // representable and two moves inside one decisecond decode to the same
        // instant.
        var previous: TimeInterval?
        var last: TimeInterval?
        for move in moves {
            guard let at = move.at else { continue }
            if let previous, at < previous { findings.insert(.nonMonotoneTiming) }
            previous = at
            last = max(last ?? at, at)
        }
        // `> 0` on both sides, and each zero means something different. A zero
        // claim is the absent measurement PRD-26 §2.3 refuses to fabricate — the
        // debrief drops its timing lines rather than inventing them, and an
        // auditor must not read that absence as a lie. A log with no stamps at
        // all is the same absence from the other end.
        if claimedSeconds > 0, let last, last > 0,
           claimedSeconds < last - timingTolerance(moveCount: moves.count) {
            findings.insert(.claimShorterThanLog)
        }

        // The proven grid. `.unique` or nothing: a board with no answer and a
        // board with several are the same absence of something to compare
        // against, which is what the finding's name says.
        guard case .unique(let solution) = BacktrackSolver.countSolutions(
            of: SudokuGrid(cells: puzzle), limit: 2) else {
            findings.insert(.notProvable)
            return Verdict(findings)
        }
        // The one place undo is unwound, borrowed rather than re-implemented.
        if ReplayWalk.walk(puzzle: puzzle, moves: moves, visit: { _ in }) != solution.cells {
            findings.insert(.unfinished)
        }
        return Verdict(findings)
    }
}
