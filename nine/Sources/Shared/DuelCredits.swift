// DuelCredits.swift — what each hand contributed (PRD-27 §10).
//
// **Credit, never rank.** There is no total here, no ratio, no accuracy figure,
// no winner, and no ordering by anything but seat number. A winner is a badge
// and EXECUTING-A-PRD §1 rules badges out by name; this is the line the feature
// is most likely to drift across later, so the type simply does not carry a
// value anyone could sort on. `ReplayAnalysis`'s header makes the same argument
// about accuracy and this is the second instance of it.
//
// "Cleared", not "errors": the word describes what happened to the board rather
// than passing a verdict on a person — and unlike a solo debrief there is a
// second person in the room reading it.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

public struct DuelCredits: Equatable, Sendable {

    /// Correct placements, per seat.
    public let placed: [Int]
    /// Wrong placements, per seat, **per attempt** — the same definition
    /// `NineGame.errorCount` uses, so three wrong tries at one cell is three.
    public let cleared: [Int]
    /// Who placed the digit that finished the board. Nil when no correct
    /// placement was ever made, which is every untouched and every abandoned
    /// board.
    public let lastPlayer: Int?

    public init(state: DuelState, moves: [LoggedMove], solution: [Int]) {
        var placed = [Int](repeating: 0, count: DuelState.seats)
        var cleared = [Int](repeating: 0, count: DuelState.seats)
        var last: Int?

        for (index, move) in moves.enumerated() {
            guard move.kind == .place else { continue }
            guard solution.indices.contains(move.cell) else { continue }
            guard let player = state.player(forMoveIndex: index),
                  placed.indices.contains(player) else { continue }
            if move.digit == solution[move.cell] {
                placed[player] += 1
                last = player
            } else {
                cleared[player] += 1
            }
        }

        self.placed = placed
        self.cleared = cleared
        self.lastPlayer = last
    }

    /// Whether there is anything worth printing. A duel abandoned before anyone
    /// placed a digit gets no lines rather than three zeroes — `countsLine`'s
    /// own honest-absence rule, which omits the error segment at zero.
    public var isEmpty: Bool {
        placed.allSatisfy { $0 == 0 } && cleared.allSatisfy { $0 == 0 }
    }

    /// Which seat's digit currently sits in each filled cell — what turns a
    /// board *position* into an owner, and therefore what the per-player tint
    /// draws from.
    ///
    /// Recomputed per board draw rather than cached, deliberately: an
    /// incremental cache and a move log are two records of one fact, and the
    /// walk is O(moves) once against a `Canvas` that is about to lay out 81
    /// cells. Givens never appear, because no move ever places one.
    ///
    /// `.undo` is skipped on purpose and it is the subtle case. An undo is
    /// logged as an *event* and reverts a move this walk has already applied —
    /// but replaying its effect here would need the undo stack's snapshots,
    /// which the log does not carry. What makes the omission harmless is that
    /// the board is redrawn from `NineGame.entries`, not from this map: a cell
    /// the player undid is empty, and an owner recorded for an empty cell is
    /// never asked for.
    public static func owners(state: DuelState, moves: [LoggedMove]) -> [Int: Int] {
        var owner: [Int: Int] = [:]
        for (index, move) in moves.enumerated() {
            switch move.kind {
            case .place:
                owner[move.cell] = state.player(forMoveIndex: index)
            case .erase:
                owner[move.cell] = nil
            case .pencil, .undo:
                continue
            }
        }
        return owner
    }
}
