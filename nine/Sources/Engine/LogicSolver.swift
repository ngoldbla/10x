// LogicSolver.swift — the human-technique solver that defines difficulty and
// emits serializable explanation records (the "why must this be a 7?" ground
// truth for the v2 coach). Ordered greedy chain:
//   naked single → hidden single → naked pair → hidden pair
//   → box-line reduction → X-wing
// A step of technique T is only ever emitted when no lower-ranked technique
// applies to the current state, so "hardest technique used" is a stable,
// deterministic difficulty measure.
import Foundation
import CouchCore

/// The ordered human-technique chain. `rank` follows declaration order.
public enum Technique: String, CaseIterable, Sendable, Codable, Hashable, Comparable {
    case nakedSingle
    case hiddenSingle
    case nakedPair
    case hiddenPair
    case boxLineReduction
    case xWing

    public var rank: Int {
        switch self {
        case .nakedSingle: return 0
        case .hiddenSingle: return 1
        case .nakedPair: return 2
        case .hiddenPair: return 3
        case .boxLineReduction: return 4
        case .xWing: return 5
        }
    }

    public static func < (lhs: Technique, rhs: Technique) -> Bool {
        lhs.rank < rhs.rank
    }

    public var displayName: String {
        switch self {
        case .nakedSingle: return "Naked Single"
        case .hiddenSingle: return "Hidden Single"
        case .nakedPair: return "Naked Pair"
        case .hiddenPair: return "Hidden Pair"
        case .boxLineReduction: return "Box-Line Reduction"
        case .xWing: return "X-Wing"
        }
    }
}

/// A digit placed into a cell.
public struct Placement: Sendable, Codable, Equatable, Hashable {
    public let cell: Int
    public let digit: Int
    public init(cell: Int, digit: Int) {
        self.cell = cell
        self.digit = digit
    }
}

/// A candidate removed from a cell.
public struct Elimination: Sendable, Codable, Equatable, Hashable {
    public let cell: Int
    public let digit: Int
    public init(cell: Int, digit: Int) {
        self.cell = cell
        self.digit = digit
    }
}

/// One explained solver step: the technique, the cells that define the
/// pattern, the digits involved, and its effect (a placement and/or a set of
/// candidate eliminations). Codable — round-trips through `CouchJSON`.
public struct SolveStep: Sendable, Codable, Equatable {
    public let technique: Technique
    /// Cells that form the pattern (the single cell, the pair, the X-wing
    /// corners, the confined box cells, …).
    public let cells: [Int]
    /// Digits the pattern is about.
    public let digits: [Int]
    public let placement: Placement?
    public let eliminations: [Elimination]

    public init(
        technique: Technique,
        cells: [Int],
        digits: [Int],
        placement: Placement? = nil,
        eliminations: [Elimination] = []
    ) {
        self.technique = technique
        self.cells = cells
        self.digits = digits
        self.placement = placement
        self.eliminations = eliminations
    }
}

/// Values + candidate bitmasks the solver iterates on. Exposed so tests can
/// interrogate individual states and so the app can replay explanations.
public struct CandidateState: Sendable, Equatable {
    public private(set) var values: [Int]      // 81; 0 = unsolved
    public private(set) var candidates: [UInt16] // 81; empty cells only, else 0

    public init(grid: SudokuGrid) {
        values = grid.cells
        candidates = [UInt16](repeating: 0, count: 81)
        for i in 0..<81 where values[i] == 0 {
            var mask = Sudoku.allDigitsMask
            for p in Sudoku.peers[i] where values[p] != 0 {
                mask &= ~Sudoku.bit(values[p])
            }
            candidates[i] = mask
        }
    }

    public var isSolved: Bool { !values.contains(0) }

    public var grid: SudokuGrid { SudokuGrid(cells: values) }

    /// True when some empty cell has no candidates left — a contradiction.
    public var isStuckDead: Bool {
        for i in 0..<81 where values[i] == 0 && candidates[i] == 0 { return true }
        return false
    }

    mutating func place(_ digit: Int, at cell: Int) {
        values[cell] = digit
        candidates[cell] = 0
        let bit = Sudoku.bit(digit)
        for p in Sudoku.peers[cell] {
            candidates[p] &= ~bit
        }
    }

    mutating func eliminate(_ digit: Int, at cell: Int) {
        candidates[cell] &= ~Sudoku.bit(digit)
    }
}

/// Outcome of a full logic solve.
public struct SolveOutcome: Sendable, Equatable {
    public let solved: Bool
    public let finalGrid: SudokuGrid
    public let steps: [SolveStep]

    /// The highest-ranked technique the chain needed. Because the chain is
    /// greedy and ordered, this is exactly the puzzle's difficulty driver.
    public var hardestTechnique: Technique? {
        steps.map(\.technique).max()
    }
}

public enum LogicSolver {

    public static let allTechniques: [Technique] = Technique.allCases

    /// The chain truncated at (and including) `ceiling`.
    public static func techniques(upTo ceiling: Technique) -> [Technique] {
        Technique.allCases.filter { $0.rank <= ceiling.rank }
    }

    /// Solve as far as the allowed techniques reach. Deterministic.
    public static func solve(
        _ grid: SudokuGrid,
        allowed: [Technique] = allTechniques,
        maxSteps: Int = 2000
    ) -> SolveOutcome {
        var state = CandidateState(grid: grid)
        var steps: [SolveStep] = []
        while !state.isSolved && steps.count < maxSteps {
            guard let step = nextStep(in: state, allowed: allowed) else { break }
            apply(step, to: &state)
            steps.append(step)
        }
        return SolveOutcome(solved: state.isSolved, finalGrid: state.grid, steps: steps)
    }

    /// Apply one step's effect to a state.
    public static func apply(_ step: SolveStep, to state: inout CandidateState) {
        if let placement = step.placement {
            state.place(placement.digit, at: placement.cell)
        }
        for elimination in step.eliminations {
            state.eliminate(elimination.digit, at: elimination.cell)
        }
    }

    /// The first step the ordered chain finds, or nil when the allowed
    /// techniques are exhausted. Techniques are always probed in rank order
    /// regardless of the order of `allowed`.
    public static func nextStep(in state: CandidateState, allowed: [Technique]) -> SolveStep? {
        for technique in Technique.allCases where allowed.contains(technique) {
            let step: SolveStep?
            switch technique {
            case .nakedSingle: step = nakedSingle(state)
            case .hiddenSingle: step = hiddenSingle(state)
            case .nakedPair: step = nakedPair(state)
            case .hiddenPair: step = hiddenPair(state)
            case .boxLineReduction: step = boxLineReduction(state)
            case .xWing: step = xWing(state)
            }
            if let step { return step }
        }
        return nil
    }

    // MARK: - Techniques

    private static func nakedSingle(_ state: CandidateState) -> SolveStep? {
        for cell in 0..<81 where state.values[cell] == 0 {
            let mask = state.candidates[cell]
            if mask.nonzeroBitCount == 1 {
                let digit = mask.trailingZeroBitCount
                return SolveStep(
                    technique: .nakedSingle,
                    cells: [cell],
                    digits: [digit],
                    placement: Placement(cell: cell, digit: digit)
                )
            }
        }
        return nil
    }

    private static func hiddenSingle(_ state: CandidateState) -> SolveStep? {
        for unit in Sudoku.units {
            for digit in 1...9 {
                let bit = Sudoku.bit(digit)
                var spot = -1
                var count = 0
                for cell in unit where state.candidates[cell] & bit != 0 {
                    spot = cell
                    count += 1
                    if count > 1 { break }
                }
                if count == 1 {
                    return SolveStep(
                        technique: .hiddenSingle,
                        cells: [spot],
                        digits: [digit],
                        placement: Placement(cell: spot, digit: digit)
                    )
                }
            }
        }
        return nil
    }

    private static func nakedPair(_ state: CandidateState) -> SolveStep? {
        for unit in Sudoku.units {
            let pairCells = unit.filter { state.candidates[$0].nonzeroBitCount == 2 }
            guard pairCells.count >= 2 else { continue }
            for i in 0..<(pairCells.count - 1) {
                for j in (i + 1)..<pairCells.count {
                    let a = pairCells[i], b = pairCells[j]
                    let mask = state.candidates[a]
                    guard mask == state.candidates[b] else { continue }
                    var eliminations: [Elimination] = []
                    for cell in unit where cell != a && cell != b {
                        let hit = state.candidates[cell] & mask
                        if hit != 0 {
                            for d in Sudoku.digits(in: hit) {
                                eliminations.append(Elimination(cell: cell, digit: d))
                            }
                        }
                    }
                    if !eliminations.isEmpty {
                        return SolveStep(
                            technique: .nakedPair,
                            cells: [a, b],
                            digits: Sudoku.digits(in: mask),
                            eliminations: eliminations
                        )
                    }
                }
            }
        }
        return nil
    }

    private static func hiddenPair(_ state: CandidateState) -> SolveStep? {
        for unit in Sudoku.units {
            // Cells (as a small bitset over unit positions) holding each digit.
            var spots = [UInt16](repeating: 0, count: 10)
            for (position, cell) in unit.enumerated() {
                let mask = state.candidates[cell]
                for d in Sudoku.digits(in: mask) {
                    spots[d] |= UInt16(1) << UInt16(position)
                }
            }
            for d1 in 1...8 {
                guard spots[d1].nonzeroBitCount == 2 else { continue }
                for d2 in (d1 + 1)...9 {
                    guard spots[d2] == spots[d1] else { continue }
                    // `digits(in:)` returns set-bit positions — here unit positions.
                    let cells = Sudoku.digits(in: spots[d1]).map { unit[$0] }
                    let keep = Sudoku.bit(d1) | Sudoku.bit(d2)
                    var eliminations: [Elimination] = []
                    for cell in cells {
                        let extra = state.candidates[cell] & ~keep
                        for d in Sudoku.digits(in: extra) {
                            eliminations.append(Elimination(cell: cell, digit: d))
                        }
                    }
                    if !eliminations.isEmpty {
                        return SolveStep(
                            technique: .hiddenPair,
                            cells: cells,
                            digits: [d1, d2],
                            eliminations: eliminations
                        )
                    }
                }
            }
        }
        return nil
    }

    /// Pointing (box → line) and claiming (line → box), both directions.
    private static func boxLineReduction(_ state: CandidateState) -> SolveStep? {
        // Pointing: digit confined to one row/column within a box eliminates
        // it from the rest of that row/column.
        for b in 0..<9 {
            let boxCells = Sudoku.units[18 + b]
            for digit in 1...9 {
                let bit = Sudoku.bit(digit)
                let spots = boxCells.filter { state.candidates[$0] & bit != 0 }
                guard spots.count >= 2 else { continue }
                let rows = Set(spots.map { Sudoku.row(of: $0) })
                let cols = Set(spots.map { Sudoku.col(of: $0) })
                if rows.count == 1, let r = rows.first {
                    let eliminations = eliminationsInLine(
                        state, digit: digit, cells: Sudoku.units[r], excluding: Set(spots)
                    )
                    if !eliminations.isEmpty {
                        return SolveStep(
                            technique: .boxLineReduction, cells: spots,
                            digits: [digit], eliminations: eliminations
                        )
                    }
                }
                if cols.count == 1, let c = cols.first {
                    let eliminations = eliminationsInLine(
                        state, digit: digit, cells: Sudoku.units[9 + c], excluding: Set(spots)
                    )
                    if !eliminations.isEmpty {
                        return SolveStep(
                            technique: .boxLineReduction, cells: spots,
                            digits: [digit], eliminations: eliminations
                        )
                    }
                }
            }
        }
        // Claiming: digit confined to one box within a row/column eliminates
        // it from the rest of that box.
        for lineIndex in 0..<18 {
            let line = Sudoku.units[lineIndex]
            for digit in 1...9 {
                let bit = Sudoku.bit(digit)
                let spots = line.filter { state.candidates[$0] & bit != 0 }
                guard spots.count >= 2 else { continue }
                let boxes = Set(spots.map { Sudoku.box(of: $0) })
                guard boxes.count == 1, let b = boxes.first else { continue }
                let eliminations = eliminationsInLine(
                    state, digit: digit, cells: Sudoku.units[18 + b], excluding: Set(spots)
                )
                if !eliminations.isEmpty {
                    return SolveStep(
                        technique: .boxLineReduction, cells: spots,
                        digits: [digit], eliminations: eliminations
                    )
                }
            }
        }
        return nil
    }

    private static func eliminationsInLine(
        _ state: CandidateState, digit: Int, cells: [Int], excluding: Set<Int>
    ) -> [Elimination] {
        let bit = Sudoku.bit(digit)
        return cells.compactMap { cell in
            guard !excluding.contains(cell), state.candidates[cell] & bit != 0 else { return nil }
            return Elimination(cell: cell, digit: digit)
        }
    }

    private static func xWing(_ state: CandidateState) -> SolveStep? {
        // Row-based, then column-based.
        for baseIsRow in [true, false] {
            for digit in 1...9 {
                let bit = Sudoku.bit(digit)
                // For each base line, the set of cross positions holding the digit.
                var crossSets = [UInt16](repeating: 0, count: 9)
                for base in 0..<9 {
                    for cross in 0..<9 {
                        let cell = baseIsRow ? base * 9 + cross : cross * 9 + base
                        if state.candidates[cell] & bit != 0 {
                            crossSets[base] |= UInt16(1) << UInt16(cross)
                        }
                    }
                }
                for b1 in 0..<8 where crossSets[b1].nonzeroBitCount == 2 {
                    for b2 in (b1 + 1)..<9 where crossSets[b2] == crossSets[b1] {
                        let crosses = Sudoku.digits(in: crossSets[b1]) // set-bit positions
                        var corners: [Int] = []
                        for base in [b1, b2] {
                            for cross in crosses {
                                corners.append(baseIsRow ? base * 9 + cross : cross * 9 + base)
                            }
                        }
                        var eliminations: [Elimination] = []
                        for base in 0..<9 where base != b1 && base != b2 {
                            for cross in crosses {
                                let cell = baseIsRow ? base * 9 + cross : cross * 9 + base
                                if state.candidates[cell] & bit != 0 {
                                    eliminations.append(Elimination(cell: cell, digit: digit))
                                }
                            }
                        }
                        if !eliminations.isEmpty {
                            return SolveStep(
                                technique: .xWing, cells: corners,
                                digits: [digit], eliminations: eliminations
                            )
                        }
                    }
                }
            }
        }
        return nil
    }
}
