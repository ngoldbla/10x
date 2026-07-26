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

    /// A bulk auto-notes move rather than a single toggle (PRD-11 11b).
    ///
    /// Discriminated by snapshot count, not by a new `Kind` case, and that is
    /// not a shortcut. `Kind` is persisted inside every autosaved `NineGame`,
    /// `NineGame.init(from:)` decodes `undoStack` without a `try?`, and the
    /// builds already on TestFlight would throw on an unknown raw value and
    /// lose the whole board. A single toggle always snapshots exactly one cell,
    /// so the count is unambiguous — and an older build's `undo()` restores
    /// every snapshot regardless of kind, so it handles these moves correctly
    /// with no change at all.
    ///
    /// The `kind` half is not redundant: an ordinary `.place` snapshots the
    /// cell plus every peer whose notes held that digit, which is routinely
    /// more than one. Only a `.pencil` move with several snapshots is a fill.
    public var isBulkNotes: Bool { kind == .pencil && previousPencil.count > 1 }
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

    /// Does this cell carry any note? A bit test rather than
    /// `!pencilDigits(at:).isEmpty`, which allocates an array to answer a
    /// yes/no question — the accessibility layer asks this for all 81 cells on
    /// every body evaluation (PRD-19).
    public func hasPencilMarks(at cell: Int) -> Bool { pencil[cell] != 0 }

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

    /// Total corner notes standing on the board (one per set bit), for the
    /// stats drawer. Placement auto-erases peers, so this falls as you solve.
    public var pencilMarkCount: Int {
        pencil.reduce(0) { $0 + $1.nonzeroBitCount }
    }

    /// Every empty cell's legal candidates as a pencil mask; 0 for filled
    /// cells. The auto-notes source of truth (PRD-11 11b), and pure board
    /// arithmetic — like everything the coach touches, it never consults
    /// `puzzle.solution`, so it cannot hand the player an answer.
    public var autoNoteMarks: [UInt16] {
        var marks = [UInt16](repeating: 0, count: 81)
        for cell in 0..<81 where entries[cell] == 0 {
            var mask = Sudoku.allDigitsMask
            for peer in Sudoku.peers[cell] where entries[peer] != 0 {
                mask &= ~Sudoku.bit(entries[peer])
            }
            marks[cell] = mask
        }
        return marks
    }

    /// Undos taken on this device. Read off the append-only log, which records
    /// undo as an event rather than popping it. A board resumed from iCloud
    /// starts at 0: `clearLocalHistory()` empties the log on the way out
    /// (PRD-8 §2 — undo history is device-local and never synced).
    public var undoCount: Int {
        moveLog.count(where: { $0.kind == .undo })
    }

    /// Digits committed to the board over the whole session, corrections
    /// included — not the same as filled cells, which undo and erase reduce.
    public var placementCount: Int {
        moveLog.count(where: { $0.kind == .place })
    }

    /// Seconds of play per digit placed, or nil before the first placement.
    /// The engine keeps no move timestamps ("no hidden clocks"), so this is
    /// total elapsed time divided by placements — a session average, not the
    /// gap between consecutive moves.
    public func averageSecondsPerPlacement(at now: Date) -> TimeInterval? {
        let placements = placementCount
        guard placements > 0 else { return nil }
        return timer.elapsed(at: now) / Double(placements)
    }

    // MARK: - Mutations

    /// Place a digit. Auto-erases pencil marks of that digit from all peers
    /// and every mark in the cell itself; all of it undoes as one move.
    /// Returns false (no-op) on givens or when re-placing the same digit.
    ///
    /// `autoNotes` is the wand's mode (PRD-11 11b): with it on, every empty
    /// cell's marks are re-derived afterwards and folded into *this* move, so
    /// the placement and the marks it implies undo together. Defaulted off, so
    /// every call site that existed before PRD-11 is unchanged in meaning as
    /// well as in text.
    @discardableResult
    public mutating func place(_ digit: Int, at cell: Int, autoNotes: Bool = false) -> Bool {
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
        if autoNotes { foldAutoNotesIntoLastMove() }
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
    ///
    /// This is where auto notes earns its keep: `place` already prunes the
    /// placed digit from peer marks, but nothing re-widens them when a digit
    /// comes back off the board. With `autoNotes` on, erasing hands those
    /// candidates back — folded into this same move, so it all undoes together.
    @discardableResult
    public mutating func erase(at cell: Int, autoNotes: Bool = false) -> Bool {
        guard !isGiven(cell), entries[cell] != 0 else { return false }
        let digit = entries[cell]
        undoStack.append(NineMove(
            kind: .erase, cell: cell, digit: digit,
            previousEntry: digit, previousPencil: []
        ))
        entries[cell] = 0
        moveLog.append(LoggedMove(kind: .erase, cell: cell, digit: digit))
        if autoNotes { foldAutoNotesIntoLastMove() }
        return true
    }

    /// Set every empty cell's notes to its candidates, as one undoable move.
    /// Returns false — pushing nothing — when the marks already match, so a
    /// second press is a no-op rather than a phantom undo entry.
    @discardableResult
    public mutating func applyAutoNotes() -> Bool {
        let target = autoNoteMarks
        let snapshots = pencilSnapshots(changingTo: target)
        guard let first = snapshots.first else { return false }
        undoStack.append(NineMove(
            kind: .pencil, cell: first.cell, digit: 0,
            previousEntry: entries[first.cell], previousPencil: snapshots
        ))
        pencil = target
        return true
    }

    /// Cells whose mask differs from `target`, snapshotted pre-change.
    private func pencilSnapshots(changingTo target: [UInt16]) -> [NineMove.PencilSnapshot] {
        (0..<81).compactMap { cell in
            pencil[cell] == target[cell] ? nil : .init(cell: cell, mask: pencil[cell])
        }
    }

    /// Fold an auto-notes re-derivation into the move on top of the stack, so
    /// a placement and the marks it implies are one undo rather than two.
    ///
    /// Snapshots the move already carries win: it recorded the *pre-move* mask,
    /// which is what undo has to restore, and re-snapshotting now would capture
    /// the post-prune value instead.
    private mutating func foldAutoNotesIntoLastMove() {
        guard let move = undoStack.popLast() else { return }
        let target = autoNoteMarks
        let alreadyHeld = Set(move.previousPencil.map(\.cell))
        let extra = pencilSnapshots(changingTo: target)
            .filter { !alreadyHeld.contains($0.cell) }
        undoStack.append(NineMove(
            kind: move.kind, cell: move.cell, digit: move.digit,
            previousEntry: move.previousEntry,
            previousPencil: move.previousPencil + extra
        ))
        pencil = target
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
