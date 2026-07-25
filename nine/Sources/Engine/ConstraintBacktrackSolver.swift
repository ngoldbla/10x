// ConstraintBacktrackSolver.swift — the constraint-checked twin of
// `BacktrackSolver`, and the reason `BacktrackSolver` itself is untouched.
//
// **The originals are frozen. They define classic dailies forever.** Every
// `GeneratedPuzzle` Nine has ever shipped was proved unique by
// `BacktrackSolver.countSolutions`, and the golden corpus freezes the bytes that
// came out; a "harmless" generalisation of its MRV loop — one reordered
// candidate scan — silently re-rolls every future daily and breaks every shared
// seed. So this is a second file rather than an extra parameter, and the classic
// path through it is a *delegation*: `context.isClassic` is one pointer compare
// and the answer comes from the original, byte for byte.
import Foundation
import CouchCore

public enum ConstraintBacktrackSolver {

    /// Count solutions of `grid` under `context`, stopping at `limit`.
    ///
    /// Returns **nil** rather than an answer when the context carries a rule
    /// this build cannot enforce (`canEnforceEveryConstraint == false`). That is
    /// the honest result: a count made without one of the puzzle's rules is a
    /// count of a different puzzle, and claiming uniqueness on it would let a
    /// board from a future build be scored, shared and put on a leaderboard
    /// under rules nobody here understands.
    /// **Every `SolutionCount.none` below is spelled out in full, and it has to
    /// be.** In a function returning `SolutionCount?`, a bare `return .none`
    /// resolves to `Optional.none` — nil — so "provably zero solutions" silently
    /// becomes "cannot answer", and `isUnique` returns false either way, so the
    /// mistake is invisible from every call site. Two tests exist purely to tell
    /// the two apart.
    public static func countSolutions(
        of grid: SudokuGrid, context: ConstraintContext, limit: Int = 2
    ) -> SolutionCount? {
        // Classic delegates to the frozen original. Same code, same order, same
        // answer — this is not a fast path, it is the *only* path for classic.
        if context.isClassic { return BacktrackSolver.countSolutions(of: grid, limit: limit) }
        guard context.canEnforceEveryConstraint else { return nil }

        var rowUsed = [UInt16](repeating: 0, count: 9)
        var colUsed = [UInt16](repeating: 0, count: 9)
        var boxUsed = [UInt16](repeating: 0, count: 9)
        var cageUsed = [UInt16](repeating: 0, count: context.cages.count)
        var cells = grid.cells

        // Seed from the givens; a contradictory one means zero solutions.
        for i in 0..<81 where cells[i] != 0 {
            let digit = cells[i]
            let bit = Sudoku.bit(digit)
            let r = Sudoku.row(of: i), c = Sudoku.col(of: i), b = Sudoku.box(of: i)
            if (rowUsed[r] | colUsed[c] | boxUsed[b]) & bit != 0 { return SolutionCount.none }
            if context.initialCandidates[i] & bit == 0 { return SolutionCount.none }
            rowUsed[r] |= bit
            colUsed[c] |= bit
            boxUsed[b] |= bit
            for cage in context.cagesOfCell[i] {
                if cageUsed[cage] & bit != 0 { return SolutionCount.none }
                cageUsed[cage] |= bit
            }
        }
        // The givens also have to respect every thermometer they touch, and the
        // cage sums they have already committed to.
        for i in 0..<81 where cells[i] != 0 {
            if thermoWindow(i, cells, context) & Sudoku.bit(cells[i]) == 0 { return SolutionCount.none }
        }
        for index in context.cages.indices {
            let used = cageUsed[index]
            if !context.cageCombinations[index].contains(where: { $0 & used == used }) {
                return SolutionCount.none
            }
        }

        /// Digits still legal in `cell`. Every filter is exact, not heuristic —
        /// pruning that is merely *sound* would be enough for the search to stay
        /// correct, but the count would then be of a looser puzzle.
        func allowed(_ cell: Int) -> UInt16 {
            let r = Sudoku.row(of: cell), c = Sudoku.col(of: cell), b = Sudoku.box(of: cell)
            var mask = context.initialCandidates[cell] & ~(rowUsed[r] | colUsed[c] | boxUsed[b])
            for cage in context.cagesOfCell[cell] where mask != 0 {
                let used = cageUsed[cage]
                var reachable: UInt16 = 0
                for combination in context.cageCombinations[cage]
                where combination & used == used {
                    reachable |= combination & ~used
                }
                mask &= reachable
            }
            for position in context.thermoPositions[cell] where mask != 0 {
                mask &= thermoWindow(cell, cells, context, position)
            }
            return mask
        }

        var found = 0
        var solution: SudokuGrid?

        func search() {
            if found >= limit { return }
            var bestCell = -1
            var bestMask: UInt16 = 0
            var bestCount = 10
            for i in 0..<81 where cells[i] == 0 {
                let mask = allowed(i)
                let count = mask.nonzeroBitCount
                if count == 0 { return } // dead branch
                if count < bestCount {
                    bestCount = count
                    bestCell = i
                    bestMask = mask
                    if count == 1 { break }
                }
            }
            if bestCell == -1 {
                // Every cage is now full, and a full cage's digit set is a
                // subset of some combination of its own size — so it *is* that
                // combination, and the sum is right by construction. Nothing
                // left to check.
                found += 1
                if solution == nil { solution = SudokuGrid(cells: cells) }
                return
            }
            let r = Sudoku.row(of: bestCell), c = Sudoku.col(of: bestCell)
            let b = Sudoku.box(of: bestCell)
            let cagesHere = context.cagesOfCell[bestCell]
            var mask = bestMask
            while mask != 0 {
                let digit = mask.trailingZeroBitCount
                mask &= mask - 1
                let bit = Sudoku.bit(digit)
                cells[bestCell] = digit
                rowUsed[r] |= bit; colUsed[c] |= bit; boxUsed[b] |= bit
                for cage in cagesHere { cageUsed[cage] |= bit }
                search()
                cells[bestCell] = 0
                rowUsed[r] &= ~bit; colUsed[c] &= ~bit; boxUsed[b] &= ~bit
                for cage in cagesHere { cageUsed[cage] &= ~bit }
                if found >= limit { return }
            }
        }

        search()
        switch found {
        case 0: return SolutionCount.none
        case 1: return .unique(solution!)
        default: return .multiple
        }
    }

    /// Convenience: exactly one solution under these rules? `false` when the
    /// question cannot be answered, which is the safe reading everywhere it is
    /// used — an unprovable board is never handed out.
    public static func isUnique(_ grid: SudokuGrid, context: ConstraintContext) -> Bool {
        if case .unique = countSolutions(of: grid, context: context, limit: 2) { return true }
        return false
    }

    // MARK: - Thermometers

    /// The digits `cell` may hold given the *nearest filled* cell on each side
    /// of it along one thermometer.
    ///
    /// Nearest-filled rather than immediate-neighbour, because the search fills
    /// cells in MRV order and the neighbour is usually still empty. A filled
    /// cell `k` steps away bounds this one by `k`, since every cell between them
    /// is strictly between the two values. Every adjacent pair still ends up
    /// ordered: whichever of the two is filled second is bounded by the first.
    private static func thermoWindow(
        _ cell: Int,
        _ cells: [Int],
        _ context: ConstraintContext,
        _ position: ConstraintContext.ThermoPosition
    ) -> UInt16 {
        let thermo = context.thermometers[position.thermometer].cells
        let index = position.position
        var low = index + 1
        var high = 9 - (thermo.count - 1 - index)

        var below = index - 1
        while below >= 0 {
            if cells[thermo[below]] != 0 {
                low = max(low, cells[thermo[below]] + (index - below))
                break
            }
            below -= 1
        }
        var above = index + 1
        while above < thermo.count {
            if cells[thermo[above]] != 0 {
                high = min(high, cells[thermo[above]] - (above - index))
                break
            }
            above += 1
        }
        return low <= high ? ConstraintContext.rangeMask(low...high) : 0
    }

    /// Every thermometer through `cell` at once — used to validate the givens.
    private static func thermoWindow(
        _ cell: Int, _ cells: [Int], _ context: ConstraintContext
    ) -> UInt16 {
        var mask = Sudoku.allDigitsMask
        for position in context.thermoPositions[cell] {
            mask &= thermoWindow(cell, cells, context, position)
        }
        return mask
    }
}
