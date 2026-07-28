// Derivation.swift — "why must this be a 7?" (PRD-25).
//
// `Coach.swift` answers *what next*. This answers *why that*, for one cell the
// player pointed at, and the two are deliberately different questions with
// different shapes of answer.
//
// **The design decision, because the obvious reading of "minimal sub-chain" is
// a trap.** A greedy full-board solve that reaches the target cell in thirty
// steps spends twenty-six of them on the other side of the grid. Neither a
// backward dependency slice nor a drop-one-and-retry reduction shrinks that in
// practice: a hidden single reads every cell of a unit and a naked single reads
// every peer, so within a few steps almost everything transitively supports
// almost everything, and the "minimal" chain is the whole chain. That was
// measured before it was designed around.
//
// What the player is actually owed is narrower and completely answerable. "Why
// must this be a 7" is "here is what killed the 3, here is what killed the 5,
// and that leaves the 7." So this walks the ordinary solver and records only
// the steps that touch **this cell's own candidates**, reporting the number it
// skipped rather than hiding them. The result is bounded by construction — a
// cell has at most nine candidates, so at most nine steps can bear on it — and
// is usually two or three.
//
// Two rules inherited from `Coach.swift`, both structural rather than
// remembered:
//
//   • **Nothing here takes a `NineGame`**, so nothing here can read
//     `puzzle.solution`. A derivation is a function of what is on the board.
//   • **Nothing new goes inside `SolveStep`.** The per-cell framing lives in
//     `DerivedStep` beside the step, the same sibling rule as `CoachStep`.
import Foundation
import CouchCore

/// One narrated beat: a step, and what it did to the cell the player asked
/// about.
public struct DerivedStep: Sendable, Equatable {
    public let coach: CoachStep
    /// Candidates this step removed from the target cell, ascending. Empty for
    /// the final placement.
    public let ruledOut: [Int]
    /// The digit this step placed in the target cell, if it is the last beat.
    public let places: Int?

    public init(coach: CoachStep, ruledOut: [Int], places: Int?) {
        self.coach = coach
        self.ruledOut = ruledOut
        self.places = places
    }
}

/// The answer to "why must this be a 7?".
public struct Derivation: Sendable, Equatable {
    public let cell: Int
    /// The digit the chain proves. Always the last step's placement.
    public let digit: Int
    /// The candidates the cell held when the player asked, ascending. The
    /// narration counts down through these.
    public let startingCandidates: [Int]
    /// The beats, in order, ending with the placement.
    public let steps: [DerivedStep]
    /// Steps the solver took that had nothing to do with this cell. Reported
    /// rather than hidden: "and nine steps elsewhere on the board" is honest
    /// and "here is the whole proof" would not be.
    public let elsewhere: Int

    public init(
        cell: Int, digit: Int, startingCandidates: [Int],
        steps: [DerivedStep], elsewhere: Int
    ) {
        self.cell = cell
        self.digit = digit
        self.startingCandidates = startingCandidates
        self.steps = steps
        self.elsewhere = elsewhere
    }

    /// The most beats the coach narrates. Past this the chain is shown from the
    /// end — the beats nearest the answer are the ones that explain it, and a
    /// seventh card is a text wall wearing an animation (PRD-25 §2.2).
    public static let narrationLimit = 6

    /// The tail the UI shows, and how many beats it is standing in front of.
    public var narrated: ArraySlice<DerivedStep> { steps.suffix(Self.narrationLimit) }
    public var untold: Int { max(0, steps.count - Self.narrationLimit) }
}

/// Why the board cannot answer.
public enum DerivationRefusal: Error, Sendable, Equatable {
    /// The cell already holds a digit — there is nothing to derive.
    case alreadyFilled
    /// The board disagrees with itself. Same rule and the same wording source
    /// as `CoachAdvice.contradiction`: derived from the grid, never from a
    /// solution, so it is identical with `showErrors` on or off.
    case contradiction(cells: [Int])
    /// Consistent, but this cell does not follow inside the band's ceiling.
    /// The honest answer, and the one a harder band would change.
    case beyond
}

extension LogicSolver {

    /// The most solver steps a single derivation will walk before giving up.
    /// A full board is ~60 placements plus eliminations; this is comfortably
    /// past a complete solve and bounds the worst case on a UI thread.
    static let derivationStepLimit = 400

    /// Why the cell at `cell` must hold the digit it must hold.
    ///
    /// `context` is defaulted for `Coach.advice`'s reason: PRD-23's channel
    /// seal fails the build if the app layer names `ConstraintContext`, so the
    /// app calls this without naming it and PRD-24 opens the channel for free.
    public static func derivation(
        forCell cell: Int,
        in grid: SudokuGrid,
        allowed: [Technique] = allTechniques,
        context: ConstraintContext = .classic
    ) -> Result<Derivation, DerivationRefusal> {
        guard (0..<81).contains(cell) else { return .failure(.alreadyFilled) }
        guard grid[cell] == 0 else { return .failure(.alreadyFilled) }

        // Same order as `advice`, and for the same reason: a self-contradicting
        // board can still yield technically valid-looking steps, and narrating
        // one would be the coach lying rather than declining.
        let clashes = grid.conflictingCells
        guard clashes.isEmpty else { return .failure(.contradiction(cells: clashes)) }

        var state = CandidateState(grid: grid, context: context)
        let dead = state.deadCells
        guard dead.isEmpty else { return .failure(.contradiction(cells: dead)) }

        let starting = Sudoku.digits(in: state.candidates[cell])
        var beats: [DerivedStep] = []
        var elsewhere = 0

        for _ in 0..<derivationStepLimit {
            guard let step = nextStep(in: state, allowed: allowed) else {
                return .failure(.beyond)
            }
            // What this step is about to do to *our* cell, measured against the
            // state before it is applied — a candidate already gone is not
            // ruled out again, which is what keeps the count-down honest.
            let before = state.candidates[cell]
            let target = targetUnit(for: step, in: state)
            let coach = CoachStep(
                step: step,
                patternUnit: patternUnit(for: step, in: state, target: target),
                targetUnit: target)

            apply(step, to: &state)

            if state.values[cell] != 0 {
                // The step that resolves the cell — by placing into it, or by
                // placing a peer that leaves it a naked single next time round.
                // Only the first is the end of *this* story.
                if let placement = step.placement, placement.cell == cell {
                    beats.append(DerivedStep(
                        coach: coach,
                        ruledOut: Sudoku.digits(in: before & ~Sudoku.bit(placement.digit)),
                        places: placement.digit))
                    return .success(Derivation(
                        cell: cell, digit: placement.digit,
                        startingCandidates: starting,
                        steps: beats, elsewhere: elsewhere))
                }
                // A cell cannot be filled by a step that did not place into it,
                // so this is unreachable — but it is the kind of unreachable
                // that becomes reachable when a technique starts placing more
                // than one digit, and a silent wrong answer is worse than a
                // refusal.
                return .failure(.beyond)
            }

            let removed = before & ~state.candidates[cell]
            if removed != 0 {
                beats.append(DerivedStep(
                    coach: coach,
                    ruledOut: Sudoku.digits(in: removed),
                    places: nil))
            } else {
                elsewhere += 1
            }
        }
        return .failure(.beyond)
    }
}
