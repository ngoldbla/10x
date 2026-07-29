import Testing
import Foundation
import NineEngine
@testable import NineShared

/// PRD-26 §2.1/§2.3 — where the comet is, and what it refuses to reveal.
@Suite("CometTimeline") struct CometTimelineTests {

    private static let puzzle = [Int](repeating: 0, count: 81)

    private func timed(_ stamps: [Double]) -> [LoggedMove] {
        stamps.enumerated().map { LoggedMove(kind: .place, cell: $0.offset, digit: 1, at: $0.element) }
    }

    private func untimed(_ count: Int) -> [LoggedMove] {
        (0..<count).map { LoggedMove(kind: .place, cell: $0, digit: 1) }
    }

    // MARK: - Hesitations are the mapping, not a special case

    /// A ten-second stare is ten seconds of the loop where nothing moves.
    /// Nothing here measures a hesitation; the timeline simply is not uniform.
    @Test func aLongPauseTakesALongStretchOfTheLoop() {
        // Three quick moves, then a long think, then one more.
        let times = CometTimeline.normalizedTimes(timed([0, 1, 2, 100]))
        #expect(times == [0, 0.01, 0.02, 1])
        // 98% of the loop is spent on the hop into the last move.
        #expect(times[3] - times[2] > 0.9)
    }

    /// The pause *before* the first digit is the player reading the board, and
    /// opening on a still frame of nothing is dead air.
    @Test func theLoopIsRebasedOnTheFirstMove() {
        #expect(CometTimeline.normalizedTimes(timed([600, 601, 602])).first == 0)
    }

    /// PRD-26 §2.3: one branch, and nothing downstream can tell which it took.
    @Test func anUntimedLogSpreadsEvenly() {
        #expect(CometTimeline.normalizedTimes(untimed(5)) == [0, 0.25, 0.5, 0.75, 1])
    }

    /// Timed is a property of the whole log — a half-timed one has no honest
    /// cadence, so it takes the uniform one.
    @Test func aHalfTimedLogSpreadsEvenly() {
        let moves = [
            LoggedMove(kind: .place, cell: 0, digit: 1, at: 0),
            LoggedMove(kind: .place, cell: 1, digit: 1),
            LoggedMove(kind: .place, cell: 2, digit: 1, at: 90)
        ]
        #expect(CometTimeline.normalizedTimes(moves) == [0, 0.5, 1])
    }

    /// A hand-edited or clock-skewed log must not make the head jump backwards.
    @Test func timesNeverGoBackwards() {
        let times = CometTimeline.normalizedTimes(timed([0, 50, 20, 80, 100]))
        #expect(times == times.sorted())
    }

    // MARK: - The frame

    @Test func theBoardFillsAsTheLoopRuns() {
        let moves = (0..<9).map { LoggedMove(kind: .place, cell: $0, digit: $0 + 1, at: Double($0)) }
        #expect(CometTimeline.frame(at: 0, puzzle: Self.puzzle, moves: moves).entries[0] == 1)
        let end = CometTimeline.frame(at: 1, puzzle: Self.puzzle, moves: moves)
        #expect(end.entries.prefix(9) == [1, 2, 3, 4, 5, 6, 7, 8, 9])
        #expect(end.to == 8)
    }

    /// The head travels: mid-hop it is between two cells, not on either.
    @Test func theHeadIsBetweenCellsMidHop() {
        let moves = timed([0, 10])
        let frame = CometTimeline.frame(at: 0.5, puzzle: Self.puzzle, moves: moves)
        #expect(frame.from == 0)
        #expect(frame.to == 1)
        #expect(abs(frame.t - 0.5) < 0.001)
    }

    /// Two moves in the same decisecond must not divide by zero.
    @Test func aZeroLengthHopReadsAsArrived() {
        let frame = CometTimeline.frame(at: 1, puzzle: Self.puzzle, moves: timed([0, 5, 5]))
        #expect(frame.t == 1)
        #expect(frame.to == 2)
    }

    /// **The comet follows the log, not the board.**
    ///
    /// A replay that visited cells top-to-bottom would be a picture of the
    /// grid rather than of the hand that filled it — and it would look
    /// *plausible*, which is what makes it worth a test rather than a comment.
    /// Nothing between `pack` and this frame may sort, dedupe or reorder, so
    /// this walks a deliberately scrambled path and asserts the head hits every
    /// cell in exactly the order it was played.
    @Test func theHeadFollowsTheLogAndNeverTheGrid() {
        let path = [40, 3, 10, 44, 61, 58, 74, 27, 9, 36, 0, 18]
        #expect(path != path.sorted(), "the fixture path must not be in board order")
        let moves = path.enumerated().map {
            LoggedMove(kind: .place, cell: $0.element, digit: 1, at: Double($0.offset))
        }
        // Sample the loop at each beat and collect the cells arrived at.
        let times = CometTimeline.normalizedTimes(moves)
        let visited = times.map {
            CometTimeline.frame(at: $0, puzzle: Self.puzzle, moves: moves).from
        }
        #expect(visited == path.map { Optional($0) })
    }

    @Test func theTailTrailsBehindTheHeadNearestFirst() {
        let moves = (0..<9).map { LoggedMove(kind: .place, cell: $0, digit: 1, at: Double($0)) }
        let frame = CometTimeline.frame(at: 1, puzzle: Self.puzzle, moves: moves)
        #expect(frame.tail == [7, 6, 5, 4, 3, 2])
        #expect(frame.tail.count == CometTimeline.tailLength)
    }

    /// "Erasures loop retrograde" — the flag is on the beat, so the drawing
    /// runs the tail the other way rather than the timeline running backwards.
    @Test func anErasureFlagsRetrograde() {
        let moves = [
            LoggedMove(kind: .place, cell: 0, digit: 5, at: 0),
            LoggedMove(kind: .erase, cell: 0, digit: 5, at: 10)
        ]
        let frame = CometTimeline.frame(at: 1, puzzle: Self.puzzle, moves: moves)
        #expect(frame.isRetrograde)
        #expect(frame.entries[0] == 0, "the erasure must have taken the digit off")
    }

    @Test func anUndoRewindsTheBoardMidLoop() {
        let moves = [
            LoggedMove(kind: .place, cell: 0, digit: 5, at: 0),
            LoggedMove(kind: .place, cell: 1, digit: 6, at: 10),
            LoggedMove(kind: .undo, cell: 1, digit: 6, at: 20)
        ]
        let frame = CometTimeline.frame(at: 1, puzzle: Self.puzzle, moves: moves)
        #expect(frame.isRetrograde)
        #expect(frame.entries[0] == 5)
        #expect(frame.entries[1] == 0)
    }

    // MARK: - Degenerate input

    @Test func anEmptyLogDrawsTheBoardAndNoHead() {
        let frame = CometTimeline.frame(at: 0.5, puzzle: Self.puzzle, moves: [])
        #expect(frame.to == nil)
        #expect(frame.tail.isEmpty)
        #expect(frame.entries.count == 81)
    }

    @Test func aPhaseOutsideTheLoopIsClamped() {
        let moves = timed([0, 10])
        // At the head of the loop the comet is leaving the first cell, not
        // sitting on it — the head lives on the interval between beats.
        let opening = CometTimeline.frame(at: -5, puzzle: Self.puzzle, moves: moves)
        #expect(opening.from == 0)
        #expect(opening.t == 0)
        #expect(CometTimeline.frame(at: 99, puzzle: Self.puzzle, moves: moves).to == 1)
    }

    /// A solve of any length is fitted to one loop: a comet whose duration
    /// advertised how long you took would be a leaderboard with an animation.
    @Test func theLoopWrapsForever() {
        let moves = timed([0, 10])
        let start = Date(timeIntervalSince1970: 0)
        let first = CometTimeline.frame(
            at: Date(timeIntervalSince1970: 1), since: start, puzzle: Self.puzzle, moves: moves
        )
        let second = CometTimeline.frame(
            at: Date(timeIntervalSince1970: 1 + CometTimeline.loopSeconds),
            since: start, puzzle: Self.puzzle, moves: moves
        )
        #expect(first == second)
    }
}
