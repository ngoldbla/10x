// Darkroom engine — game state (PRD §4.2).
//
// "Mistake counting, not mistake placing": a fill (or ✕) that contradicts
// the hidden solution is *refused* — the board never shows a wrong cell.
// The refusal carries a violated-clue line so the UI can flash the clue
// that best explains the rejection.
import Foundation

/// What the player has placed in a cell.
public enum CellMark: UInt8, Sendable, Codable, Equatable {
    case none = 0
    case filled = 1
    case xMark = 2
}

/// The clue line flashed when a contradicting move is refused.
public struct Violation: Sendable, Equatable {
    public enum Line: Sendable, Equatable, Hashable {
        case row(Int)
        case column(Int)
    }
    public let line: Line

    public init(line: Line) { self.line = line }
}

/// Result of one player move.
public enum MoveResult: Sendable, Equatable {
    /// A cell was filled; `solvedPuzzle` is true when it was the final fill.
    case placed(solvedPuzzle: Bool)
    /// A fill was removed.
    case cleared
    /// A ✕ mark was placed.
    case marked
    /// A ✕ mark was removed.
    case unmarked
    /// The move contradicts the solution — refused, mistake counted.
    case rejected(Violation)
    /// No-op (e.g. ✕ on a filled cell, moves after solving).
    case ignored
}

/// Codable auto-save snapshot (PRD §4.3: board state saved instantly).
public struct SessionSnapshot: Sendable, Codable, Equatable {
    public let puzzleID: String
    public let marks: [CellMark]
    public let mistakes: Int
    public let coachLastFired: Date?

    public init(puzzleID: String, marks: [CellMark], mistakes: Int, coachLastFired: Date?) {
        self.puzzleID = puzzleID
        self.marks = marks
        self.mistakes = mistakes
        self.coachLastFired = coachLastFired
    }
}

/// One in-progress board. Value type: the view model owns a copy and
/// persists snapshots on every mutation.
public struct PuzzleSession: Sendable, Equatable {
    public let puzzle: Puzzle
    public private(set) var marks: [CellMark]
    public private(set) var mistakes: Int
    public var coach: CoachRayLimiter

    public init(puzzle: Puzzle) {
        self.puzzle = puzzle
        self.marks = [CellMark](repeating: .none, count: puzzle.size * puzzle.size)
        self.mistakes = 0
        self.coach = CoachRayLimiter()
    }

    /// Restore from a snapshot; falls back to a fresh board when the
    /// snapshot belongs to a different puzzle.
    public init(puzzle: Puzzle, restoring snapshot: SessionSnapshot?) {
        self.init(puzzle: puzzle)
        guard let snapshot,
              snapshot.puzzleID == puzzle.id,
              snapshot.marks.count == marks.count else { return }
        self.marks = snapshot.marks
        self.mistakes = snapshot.mistakes
        self.coach = CoachRayLimiter(lastFired: snapshot.coachLastFired)
    }

    public var snapshot: SessionSnapshot {
        SessionSnapshot(
            puzzleID: puzzle.id,
            marks: marks,
            mistakes: mistakes,
            coachLastFired: coach.lastFired
        )
    }

    // MARK: - Reading

    public var size: Int { puzzle.size }

    @inlinable
    public func mark(x: Int, y: Int) -> CellMark { marks[y * puzzle.size + x] }

    public var filledCount: Int { marks.lazy.filter { $0 == .filled }.count }

    /// Wrong fills are impossible by construction, so equality of counts
    /// means every filled mark sits on a solution cell.
    public var isSolved: Bool { filledCount == puzzle.filledCount }

    public var progress: Double {
        let target = puzzle.filledCount
        guard target > 0 else { return 1 }
        return Double(filledCount) / Double(target)
    }

    /// A row whose filled cells are all placed — its clues dim to 20%.
    public func isRowComplete(_ y: Int) -> Bool {
        let n = puzzle.size
        for x in 0..<n where puzzle.solution[y * n + x] && marks[y * n + x] != .filled {
            return false
        }
        return true
    }

    public func isColumnComplete(_ x: Int) -> Bool {
        let n = puzzle.size
        for y in 0..<n where puzzle.solution[y * n + x] && marks[y * n + x] != .filled {
            return false
        }
        return true
    }

    // MARK: - Moves

    /// Click: fill / clear the focused cell.
    public mutating func toggleFill(x: Int, y: Int) -> MoveResult {
        guard !isSolved else { return .ignored }
        let i = y * puzzle.size + x
        switch marks[i] {
        case .filled:
            marks[i] = .none
            return .cleared
        case .none, .xMark:
            guard puzzle.solution[i] else {
                mistakes += 1
                return .rejected(violation(x: x, y: y, hypothesis: .filled))
            }
            marks[i] = .filled
            return .placed(solvedPuzzle: isSolved)
        }
    }

    /// Hold + swipe: paint runs. Only fills; never clears, never re-rejects
    /// a cell already marked.
    public mutating func dragFill(x: Int, y: Int) -> MoveResult {
        guard !isSolved else { return .ignored }
        let i = y * puzzle.size + x
        guard marks[i] == .none else { return .ignored }
        guard puzzle.solution[i] else {
            mistakes += 1
            return .rejected(violation(x: x, y: y, hypothesis: .filled))
        }
        marks[i] = .filled
        return .placed(solvedPuzzle: isSolved)
    }

    /// Play/pause: mark ✕ (impossible) / clear the mark. A ✕ on a cell the
    /// solution fills is a contradiction too — refused, mistake counted.
    public mutating func toggleX(x: Int, y: Int) -> MoveResult {
        guard !isSolved else { return .ignored }
        let i = y * puzzle.size + x
        switch marks[i] {
        case .filled:
            return .ignored
        case .xMark:
            marks[i] = .none
            return .unmarked
        case .none:
            guard !puzzle.solution[i] else {
                mistakes += 1
                return .rejected(violation(x: x, y: y, hypothesis: .empty))
            }
            marks[i] = .xMark
            return .marked
        }
    }

    // MARK: - Violation attribution

    /// Player knowledge as solver cell states.
    public var knowledge: [CellState] {
        marks.map { mark in
            switch mark {
            case .none: return CellState.unknown
            case .filled: return CellState.filled
            case .xMark: return CellState.empty
            }
        }
    }

    /// Pick the clue line that best explains why placing `hypothesis` at
    /// (x, y) is wrong: a line the hypothesis renders *provably* infeasible
    /// wins; otherwise the more-complete of the row/column.
    func violation(x: Int, y: Int, hypothesis: CellState) -> Violation {
        let n = puzzle.size
        var states = knowledge
        states[y * n + x] = hypothesis

        let rowLine = (0..<n).map { states[y * n + $0] }
        if LineSolver.deduce(clues: puzzle.rowClues[y], line: rowLine) == nil {
            return Violation(line: .row(y))
        }
        let colLine = (0..<n).map { states[$0 * n + x] }
        if LineSolver.deduce(clues: puzzle.colClues[x], line: colLine) == nil {
            return Violation(line: .column(x))
        }
        // Neither is provably broken yet (the contradiction is against the
        // hidden solution): flash the line closer to completion.
        var rowKnown = 0, colKnown = 0
        for t in 0..<n {
            if marks[y * n + t] != .none { rowKnown += 1 }
            if marks[t * n + x] != .none { colKnown += 1 }
        }
        return colKnown > rowKnown
            ? Violation(line: .column(x))
            : Violation(line: .row(y))
    }
}
