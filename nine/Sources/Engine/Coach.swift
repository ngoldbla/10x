// Coach.swift — the seam between the solver and the teacher (PRD-11).
//
// `LogicSolver.nextStep` has returned technique + cells + digit + effect since
// 1.0. What was missing was a caller that could ask the question safely, and
// two rules shape everything here:
//
//   • **The coach never reads `puzzle.solution`.** `NineGame.isError` — and the
//     coral highlight it drives — knows the answer, and `errorHighlight` is a
//     setting the player can switch off. A hint pointing at coral would leak,
//     through the one surface a stuck player is most likely to open, exactly
//     what PRD-19 spent a release teaching the AX layer to refuse to say. So a
//     contradiction here is a *peer clash* or a *dead cell*: both provable from
//     what is already on screen, both identical with the setting on or off.
//     Nothing in this file takes a `NineGame`, which is that rule made
//     structural rather than remembered.
//
//   • **Nothing new goes inside `SolveStep`.** It lives in
//     `GeneratedPuzzle.steps` and therefore inside the golden-corpus hash, so
//     the units a deduction used travel *beside* it in `CoachStep` rather than
//     in it. Same sibling rule as `VariantPuzzle` and `nine.history`'s `band`.
//
// Pure and deterministic: a map from a grid to advice. No clocks, no globals.
import Foundation
import CouchCore

/// One explained step, plus the units its sentence will need to name.
///
/// Unit indices follow the convention `Sudoku.units` already fixes — `0..<9`
/// rows, `9..<18` columns, `18..<27` boxes — so the sentence layer can label
/// them without holding any solver state of its own.
public struct CoachStep: Sendable, Equatable {
    public let step: SolveStep
    /// The unit that confines the pattern: for a hidden single, the unit in
    /// which the digit has exactly one home; for a box-line reduction, the
    /// *other* unit the spots share, which is the box when pointing and the
    /// line when claiming. Nil when the technique is not unit-scoped.
    public let patternUnit: Int?
    /// The unit every elimination lands in, when they share one. Nil for an
    /// X-wing — whose victims span two lines — and for techniques that
    /// eliminate nothing.
    public let targetUnit: Int?

    public init(step: SolveStep, patternUnit: Int?, targetUnit: Int?) {
        self.step = step
        self.patternUnit = patternUnit
        self.targetUnit = targetUnit
    }
}

/// What the coach has to say about a position.
public enum CoachAdvice: Sendable, Equatable {
    /// The next move the allowed techniques afford.
    case step(CoachStep)
    /// The board disagrees with itself at these cells — derived from the grid
    /// alone, never from a solution.
    case contradiction(cells: [Int])
    /// Consistent, unfinished, and nothing follows inside the band's ceiling.
    case exhausted
    /// Full and self-consistent.
    case solved
}

extension SudokuGrid {
    /// Filled cells whose value duplicates a peer's, ascending.
    ///
    /// `isConsistent` already answers the yes/no; the coach has to *point*.
    /// Pure geometry — this never consults a solution, which is what makes it
    /// safe to speak while `showErrors` is off.
    public var conflictingCells: [Int] {
        var flagged = Set<Int>()
        for unit in Sudoku.units {
            // Index by digit rather than by a Set, so the first home of a
            // repeated digit can be flagged alongside every later one.
            var firstHome = [Int](repeating: -1, count: 10)
            for cell in unit where cells[cell] != 0 {
                let digit = cells[cell]
                if firstHome[digit] >= 0 {
                    flagged.insert(firstHome[digit])
                    flagged.insert(cell)
                } else {
                    firstHome[digit] = cell
                }
            }
        }
        return flagged.sorted()
    }
}

extension CandidateState {
    /// Empty cells with no candidate left. `isStuckDead` answers whether any
    /// exists; this says which, because the coach has to point at something.
    public var deadCells: [Int] {
        (0..<81).filter { values[$0] == 0 && candidates[$0] == 0 }
    }
}

extension LogicSolver {

    /// The coach's answer for a position.
    ///
    /// `context` is defaulted, and that is load-bearing: PRD-23's channel seal
    /// greps `Sources/App`, `Sources/Widgets` and `Sources/Shared` for the
    /// symbol `ConstraintContext` and fails the build on a match. The app can
    /// therefore call this without naming it — and when PRD-24 opens the
    /// channel, the coach speaks variant boards with no change here.
    public static func advice(
        for grid: SudokuGrid,
        allowed: [Technique] = allTechniques,
        context: ConstraintContext = .classic
    ) -> CoachAdvice {
        // Order matters. A self-contradicting board can still yield a
        // technically valid-looking step, and offering one would be the coach
        // lying rather than declining.
        let clashes = grid.conflictingCells
        guard clashes.isEmpty else { return .contradiction(cells: clashes) }
        guard !grid.isFull else { return .solved }

        let state = CandidateState(grid: grid, context: context)
        let dead = state.deadCells
        guard dead.isEmpty else { return .contradiction(cells: dead) }

        guard let step = nextStep(in: state, allowed: allowed) else { return .exhausted }
        let target = targetUnit(for: step, in: state)
        return .step(CoachStep(
            step: step,
            patternUnit: patternUnit(for: step, in: state, target: target),
            targetUnit: target
        ))
    }

    /// The unit containing every pattern cell *and* every elimination. Exact
    /// for pairs and box-line reductions; nil for an X-wing, whose victims
    /// span two lines, and for techniques that eliminate nothing.
    private static func targetUnit(for step: SolveStep, in state: CandidateState) -> Int? {
        guard !step.eliminations.isEmpty else { return nil }
        let touched = Set(step.cells + step.eliminations.map(\.cell))
        return state.context.units.indices.first {
            Set(state.context.units[$0]).isSuperset(of: touched)
        }
    }

    /// The unit that confines the pattern.
    ///
    /// One rule covers both directions of a box-line reduction: the spots lie
    /// in exactly two units and the eliminations are in one of them, so the
    /// other is the source. Pointing gives box → line, claiming gives line →
    /// box, and neither needs a special case.
    private static func patternUnit(
        for step: SolveStep, in state: CandidateState, target: Int?
    ) -> Int? {
        if step.technique == .hiddenSingle {
            guard let cell = step.cells.first, let digit = step.digits.first else { return nil }
            let bit = Sudoku.bit(digit)
            return state.context.unitsOfCell[cell].first { index in
                state.context.units[index].count(where: { state.candidates[$0] & bit != 0 }) == 1
            }
        }
        guard step.cells.count > 1 else { return nil }
        let pattern = Set(step.cells)
        return state.context.units.indices.first {
            $0 != target && Set(state.context.units[$0]).isSuperset(of: pattern)
        }
    }
}
