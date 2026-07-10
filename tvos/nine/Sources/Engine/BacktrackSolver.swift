// BacktrackSolver.swift — the proof side of the engine: a bitmask MRV
// backtracker used for (a) building complete grids from a seed and
// (b) count-limited uniqueness proving (stop at 2). Deterministic throughout.
import Foundation
import CouchCore

/// Result of a count-limited solution search.
public enum SolutionCount: Sendable, Equatable {
    case none
    case unique(SudokuGrid)
    /// At least two solutions exist (search stops at the second).
    case multiple
}

public enum BacktrackSolver {

    /// Count solutions of `grid`, stopping as soon as `limit` are found.
    /// `limit` defaults to 2, which is all the uniqueness prover needs.
    public static func countSolutions(of grid: SudokuGrid, limit: Int = 2) -> SolutionCount {
        var rowUsed = [UInt16](repeating: 0, count: 9)
        var colUsed = [UInt16](repeating: 0, count: 9)
        var boxUsed = [UInt16](repeating: 0, count: 9)
        var cells = grid.cells

        // Seed the masks; a contradictory given means zero solutions.
        for i in 0..<81 where cells[i] != 0 {
            let bit = Sudoku.bit(cells[i])
            let r = Sudoku.row(of: i), c = Sudoku.col(of: i), b = Sudoku.box(of: i)
            if (rowUsed[r] | colUsed[c] | boxUsed[b]) & bit != 0 { return .none }
            rowUsed[r] |= bit
            colUsed[c] |= bit
            boxUsed[b] |= bit
        }

        var found = 0
        var solution: SudokuGrid?

        func search() {
            if found >= limit { return }
            // Most-constrained-cell heuristic.
            var bestCell = -1
            var bestMask: UInt16 = 0
            var bestCount = 10
            for i in 0..<81 where cells[i] == 0 {
                let r = Sudoku.row(of: i), c = Sudoku.col(of: i), b = Sudoku.box(of: i)
                let mask = Sudoku.allDigitsMask & ~(rowUsed[r] | colUsed[c] | boxUsed[b])
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
                found += 1
                if solution == nil { solution = SudokuGrid(cells: cells) }
                return
            }
            let r = Sudoku.row(of: bestCell), c = Sudoku.col(of: bestCell), b = Sudoku.box(of: bestCell)
            var mask = bestMask
            while mask != 0 {
                let digit = mask.trailingZeroBitCount
                mask &= mask - 1
                let bit = Sudoku.bit(digit)
                cells[bestCell] = digit
                rowUsed[r] |= bit; colUsed[c] |= bit; boxUsed[b] |= bit
                search()
                cells[bestCell] = 0
                rowUsed[r] &= ~bit; colUsed[c] &= ~bit; boxUsed[b] &= ~bit
                if found >= limit { return }
            }
        }

        search()
        switch found {
        case 0: return .none
        case 1: return .unique(solution!)
        default: return .multiple
        }
    }

    /// Convenience: does `grid` have exactly one solution?
    public static func isUnique(_ grid: SudokuGrid) -> Bool {
        if case .unique = countSolutions(of: grid, limit: 2) { return true }
        return false
    }

    /// Build a complete, valid grid deterministically from `seed`
    /// (backtracking fill with per-cell digit orders shuffled by SplitMix64).
    public static func completeGrid(seed: UInt64) -> SudokuGrid {
        var rng = SplitMix64(seed: seed)
        var rowUsed = [UInt16](repeating: 0, count: 9)
        var colUsed = [UInt16](repeating: 0, count: 9)
        var boxUsed = [UInt16](repeating: 0, count: 9)
        var cells = [Int](repeating: 0, count: 81)

        func fill(_ index: Int) -> Bool {
            if index == 81 { return true }
            let r = Sudoku.row(of: index), c = Sudoku.col(of: index), b = Sudoku.box(of: index)
            let mask = Sudoku.allDigitsMask & ~(rowUsed[r] | colUsed[c] | boxUsed[b])
            if mask == 0 { return false }
            var order = Sudoku.digits(in: mask)
            // Fisher–Yates with the seeded generator: deterministic.
            if order.count > 1 {
                for i in stride(from: order.count - 1, to: 0, by: -1) {
                    let j = rng.nextInt(below: i + 1)
                    if i != j { order.swapAt(i, j) }
                }
            }
            for digit in order {
                let bit = Sudoku.bit(digit)
                cells[index] = digit
                rowUsed[r] |= bit; colUsed[c] |= bit; boxUsed[b] |= bit
                if fill(index + 1) { return true }
                cells[index] = 0
                rowUsed[r] &= ~bit; colUsed[c] &= ~bit; boxUsed[b] &= ~bit
            }
            return false
        }

        let ok = fill(0)
        precondition(ok, "backtracking fill of an empty grid cannot fail")
        return SudokuGrid(cells: cells)
    }
}
