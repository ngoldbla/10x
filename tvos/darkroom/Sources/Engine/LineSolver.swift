// Darkroom engine — the line solver.
//
// The verifier's core: given one line's clues and its current partial state,
// compute every cell that is *forced* (identical across all consistent
// placements). Iterating this over rows and columns to a fixpoint is exactly
// the reasoning a careful human performs, so a puzzle this solver finishes
// is human-solvable by construction (PRD §5.3).
import Foundation

/// One cell's knowledge state during solving.
public enum CellState: UInt8, Sendable, Codable, Equatable {
    case unknown = 0
    case filled = 1
    case empty = 2
}

public enum LineSolver {

    /// Deduce the forced cells of a single line.
    ///
    /// - Parameters:
    ///   - clues: run lengths, left to right. `[]` (or `[0]`) means blank.
    ///   - line: current knowledge, one entry per cell.
    /// - Returns: the line with every forced cell resolved, or `nil` when no
    ///   placement of the clues is consistent with the knowns (contradiction).
    public static func deduce(clues: [Int], line: [CellState]) -> [CellState]? {
        let n = line.count
        let runs = clues.filter { $0 > 0 }
        let k = runs.count
        guard n > 0 else { return line }

        let stateCount = (n + 1) * (k + 1)
        @inline(__always) func idx(_ i: Int, _ j: Int) -> Int { i * (k + 1) + j }

        // noFilled[i]: line[i...] contains no known-filled cell.
        var noFilled = [Bool](repeating: true, count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            noFilled[i] = noFilled[i + 1] && line[i] != .filled
        }
        // Prefix counts of known-empty cells for O(1) block checks.
        var emptyPrefix = [Int](repeating: 0, count: n + 1)
        for i in 0..<n {
            emptyPrefix[i + 1] = emptyPrefix[i] + (line[i] == .empty ? 1 : 0)
        }
        @inline(__always) func blockClear(_ i: Int, _ len: Int) -> Bool {
            emptyPrefix[i + len] - emptyPrefix[i] == 0
        }

        // feasible[i][j]: runs[j...] can be placed into line[i...].
        var feasible = [Bool](repeating: false, count: stateCount)
        for i in stride(from: n, through: 0, by: -1) {
            for j in stride(from: k, through: 0, by: -1) {
                var ok = false
                if j == k {
                    ok = noFilled[i]
                } else if i < n {
                    // Option A: leave cell i blank.
                    if line[i] != .filled && feasible[idx(i + 1, j)] { ok = true }
                    // Option B: start run j at cell i.
                    if !ok {
                        let len = runs[j]
                        if i + len <= n && blockClear(i, len) {
                            if i + len == n {
                                ok = feasible[idx(n, j + 1)]
                            } else if line[i + len] != .filled {
                                ok = feasible[idx(i + len + 1, j + 1)]
                            }
                        }
                    }
                }
                feasible[idx(i, j)] = ok
            }
        }
        guard feasible[idx(0, 0)] else { return nil }

        // Walk every reachable-and-feasible transition from (0,0), marking
        // which values each cell can take across all consistent placements.
        var canFill = [Bool](repeating: false, count: n)
        var canEmpty = [Bool](repeating: false, count: n)
        var visited = [Bool](repeating: false, count: stateCount)
        var stack: [(Int, Int)] = [(0, 0)]
        visited[idx(0, 0)] = true

        while let (i, j) = stack.popLast() {
            if j == k {
                // Feasibility guarantees no known-filled cell remains.
                for t in i..<n { canEmpty[t] = true }
                continue
            }
            guard i < n else { continue }
            if line[i] != .filled && feasible[idx(i + 1, j)] {
                canEmpty[i] = true
                if !visited[idx(i + 1, j)] {
                    visited[idx(i + 1, j)] = true
                    stack.append((i + 1, j))
                }
            }
            let len = runs[j]
            if i + len <= n && blockClear(i, len) {
                if i + len == n {
                    if feasible[idx(n, j + 1)] {
                        for t in i..<n { canFill[t] = true }
                        if !visited[idx(n, j + 1)] {
                            visited[idx(n, j + 1)] = true
                            stack.append((n, j + 1))
                        }
                    }
                } else if line[i + len] != .filled && feasible[idx(i + len + 1, j + 1)] {
                    for t in i..<(i + len) { canFill[t] = true }
                    canEmpty[i + len] = true
                    if !visited[idx(i + len + 1, j + 1)] {
                        visited[idx(i + len + 1, j + 1)] = true
                        stack.append((i + len + 1, j + 1))
                    }
                }
            }
        }

        var out = line
        for i in 0..<n {
            if canFill[i] && !canEmpty[i] {
                out[i] = .filled
            } else if canEmpty[i] && !canFill[i] {
                out[i] = .empty
            }
        }
        return out
    }
}

/// Result of running the line solver over a whole grid to fixpoint.
public struct SolveReport: Sendable, Equatable {
    /// Every cell resolved — the puzzle is human-solvable by line logic.
    public let solved: Bool
    /// Some line admitted no consistent placement.
    public let contradiction: Bool
    /// Number of full row+column sweeps that produced new information.
    /// This is the difficulty score (PRD §5.4).
    public let passes: Int
    /// Final knowledge grid, row-major.
    public let cells: [CellState]
}

public enum GridSolver {

    /// Iterate single-line deduction over all rows then all columns until no
    /// sweep learns anything new.
    public static func solve(
        size: Int,
        rowClues: [[Int]],
        colClues: [[Int]],
        initial: [CellState]? = nil
    ) -> SolveReport {
        precondition(rowClues.count == size && colClues.count == size)
        var cells = initial ?? [CellState](repeating: .unknown, count: size * size)
        precondition(cells.count == size * size)
        var passes = 0
        var line = [CellState](repeating: .unknown, count: size)

        while true {
            var changed = false
            for y in 0..<size {
                for x in 0..<size { line[x] = cells[y * size + x] }
                guard let deduced = LineSolver.deduce(clues: rowClues[y], line: line) else {
                    return SolveReport(solved: false, contradiction: true, passes: passes, cells: cells)
                }
                for x in 0..<size where deduced[x] != cells[y * size + x] {
                    cells[y * size + x] = deduced[x]
                    changed = true
                }
            }
            for x in 0..<size {
                for y in 0..<size { line[y] = cells[y * size + x] }
                guard let deduced = LineSolver.deduce(clues: colClues[x], line: line) else {
                    return SolveReport(solved: false, contradiction: true, passes: passes, cells: cells)
                }
                for y in 0..<size where deduced[y] != cells[y * size + x] {
                    cells[y * size + x] = deduced[y]
                    changed = true
                }
            }
            if changed {
                passes += 1
            } else {
                break
            }
            if !cells.contains(.unknown) { break }
            if passes > size * size { break } // safety valve; unreachable in practice
        }

        let solved = !cells.contains(.unknown)
        return SolveReport(solved: solved, contradiction: false, passes: passes, cells: cells)
    }

    /// Convenience: verify that a puzzle's clue set is fully resolved by line
    /// logic and lands exactly on its stored solution.
    public static func verify(_ puzzle: Puzzle) -> Bool {
        let report = solve(size: puzzle.size, rowClues: puzzle.rowClues, colClues: puzzle.colClues)
        guard report.solved else { return false }
        for i in 0..<(puzzle.size * puzzle.size) {
            let filled = report.cells[i] == .filled
            if filled != puzzle.solution[i] { return false }
        }
        return true
    }
}
