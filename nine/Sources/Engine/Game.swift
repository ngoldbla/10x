// Game.swift — mutable play state over a proven puzzle: entries, pencil
// marks, contradiction detection against the known solution, an undo stack,
// completion detection, elapsed-time bookkeeping (clock injected as `Date`
// arguments — no hidden clocks) and daily-streak logic. Pure, Sendable,
// Codable end to end so the app can autosave the whole thing as one value.
import Foundation
import CouchCore

/// One reversible action, kept on the undo stack with everything needed to
/// restore the prior state (including pencil marks auto-erased by placement).
public struct NineMove: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case place, erase, pencil
    }

    public let kind: Kind
    public let cell: Int
    /// The digit placed / erased / toggled (what the undo toast shows).
    public let digit: Int
    let previousEntry: Int
    /// Pencil masks of every cell this move touched, pre-move.
    let previousPencil: [PencilSnapshot]

    struct PencilSnapshot: Sendable, Codable, Equatable {
        let cell: Int
        let mask: UInt16
    }
}

/// One entry in the append-only move log: what the player did, in order.
/// Undo is logged as an *event* (never popped), so a future solve replay can
/// retrace the true path including corrections. No timestamps — order
/// suffices, and the engine keeps its "no hidden clocks" rule.
public struct LoggedMove: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable { case place, erase, pencil, undo }
    public let kind: Kind
    public let cell: Int
    public let digit: Int

    public init(kind: Kind, cell: Int, digit: Int) {
        self.kind = kind
        self.cell = cell
        self.digit = digit
    }
}

/// Play state for one board.
public struct NineGame: Sendable, Codable, Equatable {
    public let puzzle: GeneratedPuzzle
    /// 81 entries including givens; 0 = empty.
    public private(set) var entries: [Int]
    /// Corner-note bitmasks per cell (bit d = digit d noted).
    public private(set) var pencil: [UInt16]
    public private(set) var undoStack: [NineMove]
    public var timer: ElapsedTimer
    /// Append-only history of every accepted move (solve-replay groundwork).
    public private(set) var moveLog: [LoggedMove]

    public init(puzzle: GeneratedPuzzle) {
        self.puzzle = puzzle
        self.entries = puzzle.puzzle.cells
        self.pencil = [UInt16](repeating: 0, count: 81)
        self.undoStack = []
        self.timer = ElapsedTimer()
        self.moveLog = []
    }

    /// Tolerant decoding: CouchStored discards the whole blob when decode
    /// throws, so any field added after 1.1 must fall back to its default
    /// instead of destroying a player's in-progress autosave on update.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        puzzle = try c.decode(GeneratedPuzzle.self, forKey: .puzzle)
        entries = try c.decode([Int].self, forKey: .entries)
        pencil = try c.decode([UInt16].self, forKey: .pencil)
        undoStack = try c.decode([NineMove].self, forKey: .undoStack)
        timer = try c.decode(ElapsedTimer.self, forKey: .timer)
        moveLog = try c.decodeIfPresent([LoggedMove].self, forKey: .moveLog) ?? []
    }

    // MARK: - Queries

    public func isGiven(_ cell: Int) -> Bool { puzzle.puzzle.cells[cell] != 0 }

    public func entry(at cell: Int) -> Int { entries[cell] }

    public func pencilDigits(at cell: Int) -> [Int] { Sudoku.digits(in: pencil[cell]) }

    /// All 81 cells filled (correct or not).
    public var isComplete: Bool { !entries.contains(0) }

    /// All 81 cells filled and equal to the proven solution.
    public var isSolved: Bool { entries == puzzle.solution.cells }

    /// User cells whose entry contradicts the proven solution.
    public var errorCells: [Int] {
        (0..<81).filter { entries[$0] != 0 && !isGiven($0) && entries[$0] != puzzle.solution.cells[$0] }
    }

    public func isError(at cell: Int) -> Bool {
        entries[cell] != 0 && !isGiven(cell) && entries[cell] != puzzle.solution.cells[cell]
    }

    /// How many of `digit` are on the board (for dimming completed petals).
    public func count(of digit: Int) -> Int {
        entries.count(where: { $0 == digit })
    }

    /// A digit is complete when all nine instances are placed.
    public func isDigitComplete(_ digit: Int) -> Bool { count(of: digit) >= 9 }

    /// Fraction of non-given cells filled, for progress chrome.
    public var fillFraction: Double {
        let holes = puzzle.puzzle.emptyCount
        guard holes > 0 else { return 1 }
        let filled = (0..<81).count(where: { entries[$0] != 0 && !isGiven($0) })
        return Double(filled) / Double(holes)
    }

    // MARK: - Mutations

    /// Place a digit. Auto-erases pencil marks of that digit from all peers
    /// and every mark in the cell itself; all of it undoes as one move.
    /// Returns false (no-op) on givens or when re-placing the same digit.
    @discardableResult
    public mutating func place(_ digit: Int, at cell: Int) -> Bool {
        guard (1...9).contains(digit), !isGiven(cell), entries[cell] != digit else { return false }
        var snapshots: [NineMove.PencilSnapshot] = []
        if pencil[cell] != 0 {
            snapshots.append(.init(cell: cell, mask: pencil[cell]))
            pencil[cell] = 0
        }
        let bit = Sudoku.bit(digit)
        for peer in Sudoku.peers[cell] where pencil[peer] & bit != 0 {
            snapshots.append(.init(cell: peer, mask: pencil[peer]))
            pencil[peer] &= ~bit
        }
        undoStack.append(NineMove(
            kind: .place, cell: cell, digit: digit,
            previousEntry: entries[cell], previousPencil: snapshots
        ))
        entries[cell] = digit
        moveLog.append(LoggedMove(kind: .place, cell: cell, digit: digit))
        return true
    }

    /// Toggle a corner note. No-op on givens and filled cells.
    @discardableResult
    public mutating func togglePencil(_ digit: Int, at cell: Int) -> Bool {
        guard (1...9).contains(digit), !isGiven(cell), entries[cell] == 0 else { return false }
        undoStack.append(NineMove(
            kind: .pencil, cell: cell, digit: digit,
            previousEntry: entries[cell],
            previousPencil: [.init(cell: cell, mask: pencil[cell])]
        ))
        pencil[cell] ^= Sudoku.bit(digit)
        moveLog.append(LoggedMove(kind: .pencil, cell: cell, digit: digit))
        return true
    }

    /// Clear a user entry. No-op on givens and empty cells.
    @discardableResult
    public mutating func erase(at cell: Int) -> Bool {
        guard !isGiven(cell), entries[cell] != 0 else { return false }
        let digit = entries[cell]
        undoStack.append(NineMove(
            kind: .erase, cell: cell, digit: digit,
            previousEntry: digit, previousPencil: []
        ))
        entries[cell] = 0
        moveLog.append(LoggedMove(kind: .erase, cell: cell, digit: digit))
        return true
    }

    /// Revert the latest move (entry and any auto-erased pencil marks).
    /// Returns the reverted move for the undo toast, or nil when empty.
    @discardableResult
    public mutating func undo() -> NineMove? {
        guard let move = undoStack.popLast() else { return nil }
        switch move.kind {
        case .place, .erase:
            entries[move.cell] = move.previousEntry
        case .pencil:
            break // pencil restored below
        }
        for snapshot in move.previousPencil {
            pencil[snapshot.cell] = snapshot.mask
        }
        moveLog.append(LoggedMove(kind: .undo, cell: move.cell, digit: move.digit))
        return move
    }

    /// Drop device-local UX state (undo stack + move log). The cloud record
    /// carries only the board — undo/redo history is per-device and never
    /// synced (PRD-8 §2). Must live inside NineGame: the two arrays are
    /// `private(set)` (file-scoped setter).
    public mutating func clearLocalHistory() {
        undoStack = []
        moveLog = []
    }
}

/// Elapsed-time bookkeeping with an injectable clock: callers pass `Date`
/// values in, nothing here reads a wall clock — fully testable, Codable.
public struct ElapsedTimer: Sendable, Codable, Equatable {
    public private(set) var accumulated: TimeInterval
    public private(set) var runningSince: Date?

    public init() {
        accumulated = 0
        runningSince = nil
    }

    public var isRunning: Bool { runningSince != nil }

    public mutating func start(at now: Date) {
        guard runningSince == nil else { return }
        runningSince = now
    }

    public mutating func pause(at now: Date) {
        guard let since = runningSince else { return }
        accumulated += max(0, now.timeIntervalSince(since))
        runningSince = nil
    }

    public func elapsed(at now: Date) -> TimeInterval {
        guard let since = runningSince else { return accumulated }
        return accumulated + max(0, now.timeIntervalSince(since))
    }
}

/// Daily-streak bookkeeping keyed on `DailySeed.dayOrdinal` values.
public struct StreakState: Sendable, Codable, Equatable {
    public private(set) var current: Int
    public private(set) var best: Int
    public private(set) var lastCompletedDay: Int?

    public init() {
        current = 0
        best = 0
        lastCompletedDay = nil
    }

    public func hasCompleted(day: Int) -> Bool { lastCompletedDay == day }

    /// Record a daily completion. Same day twice is a no-op; the day after
    /// the last completion extends the streak; any gap restarts it at 1.
    public mutating func recordCompletion(day: Int) {
        if let last = lastCompletedDay {
            guard day > last else { return }
            current = (day == last + 1) ? current + 1 : 1
        } else {
            current = 1
        }
        lastCompletedDay = day
        best = max(best, current)
    }

    /// The streak shown on the shelf: yesterday's chain is still alive today,
    /// anything older has lapsed to 0.
    public func displayedStreak(today: Int) -> Int {
        guard let last = lastCompletedDay, last >= today - 1 else { return 0 }
        return current
    }
}
