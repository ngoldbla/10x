// ReplayAnalysis.swift — what the board can prove about the hand that played it
// (PRD-26 §3.3).
//
// **No new solving code.** This walks a `CandidateState` forward with the
// shipped `LogicSolver.nextStep(in:allowed:)` and `apply(_:to:)` and asks, at
// each placement, what the solver could have done from exactly that board. The
// solver is the ground truth PRD-25 already made; this is a consumer of it.
//
// It is also deliberately opinion-free. Nothing here decides that one class of
// placement is better than another, nothing sums them, and only `.found` ever
// reaches a sentence. The covenant bans gamification, and an accuracy score is
// what this file would grow if nobody wrote that down.
import Foundation
import CouchCore

/// What the board could prove about one placement, at the moment it was made.
public enum PlacementClass: String, Sendable, Codable, Equatable, CaseIterable {
    /// The cell had exactly one candidate left. The obvious move, and most of
    /// every solve.
    case forced
    /// The cell had a choice, and a technique resolved it anyway — the class
    /// that earns PRD-26 §2.2's one sentence.
    case found
    /// The cell had a choice and no allowed technique resolved it from here.
    ///
    /// **`.leap`, not "guess".** PROGRAM-2.0 §Pillar C says guess and the word
    /// is wrong for the register — a raw value becomes the localization
    /// identity the moment it ships (PRD-20's finding), so it is worth choosing
    /// once rather than renaming against nine translations later. The covenant
    /// bans streak shaming; this is the same sentence in a kinder mood. The
    /// count is never shown either way.
    case leap
    /// The digit contradicts the proven solution. Recorded because a replay
    /// that hid corrections would be a tidied path nobody walked; never counted
    /// and never displayed.
    case slip
}

/// One placement, classified.
public struct ClassifiedPlacement: Sendable, Equatable {
    /// Index into the replay's move array, so the comet can line the class up
    /// with the beat that produced it.
    public let moveIndex: Int
    public let cell: Int
    public let digit: Int
    public let kind: PlacementClass
    /// The technique that resolved the cell, for `.found`. Nil otherwise —
    /// `.forced` is a naked single by definition and does not need naming.
    public let technique: Technique?

    public init(moveIndex: Int, cell: Int, digit: Int, kind: PlacementClass, technique: Technique?) {
        self.moveIndex = moveIndex
        self.cell = cell
        self.digit = digit
        self.kind = kind
        self.technique = technique
    }
}

public struct ReplayAnalysis: Sendable, Equatable {
    public let placements: [ClassifiedPlacement]

    public init(placements: [ClassifiedPlacement]) {
        self.placements = placements
    }

    /// Techniques the player resolved a cell with, unordered and deduplicated.
    /// This is what `CoachProgress.usedInSolve` is written from — a technique
    /// you found on your own board is a technique you have met.
    public var techniquesUsed: Set<Technique> {
        Set(placements.compactMap { $0.kind == .found ? $0.technique : nil })
    }

    /// The lowest bar a technique must clear to be worth a sentence.
    ///
    /// Both singles sit below it, and that is the whole point: a hidden single
    /// is genuinely a `.found` — the cell had a choice and a technique resolved
    /// it — but "You found the Hidden Single" is a sentence that would appear on
    /// almost every board and mean nothing on any of them. Congratulation that
    /// is automatic is not congratulation.
    public static let sentenceFloor: Technique = .nakedPair

    /// The placement PRD-26 §2.2's one sentence is about: the hardest technique
    /// the player resolved a cell with, at its *first* appearance. Nil on a
    /// board solved entirely by singles, and nothing takes its place.
    public var headline: ClassifiedPlacement? {
        let worthy = placements.filter {
            $0.kind == .found && ($0.technique?.rank ?? -1) >= Self.sentenceFloor.rank
        }
        guard let hardest = worthy.compactMap(\.technique).max() else { return nil }
        return worthy.first { $0.technique == hardest }
    }

    /// Walk the log, classifying every placement against the board as it stood
    /// at that moment.
    ///
    /// `solution` is the proven grid, used only to separate `.slip` from the
    /// rest — never to decide what was derivable, which is the rule
    /// `Coach.swift` states and this file keeps: everything else here is a
    /// function of what was on the board.
    public static func analyze(
        puzzle: [Int],
        solution: [Int],
        moves: [LoggedMove],
        allowed: [Technique] = LogicSolver.techniques(upTo: .simpleColoring),
        context: ConstraintContext = .classic
    ) -> ReplayAnalysis {
        guard puzzle.count == 81, solution.count == 81 else { return ReplayAnalysis(placements: []) }

        var entries = puzzle
        // A mirror of the game's own undo stack, so `.undo` events pop the move
        // they actually reverted. `LoggedMove` does not say what an undo undid,
        // and reconstructing it from the stack is exactly how the game knew.
        var stack: [(kind: LoggedMove.Kind, cell: Int, previousEntry: Int)] = []
        var placements: [ClassifiedPlacement] = []

        for (index, move) in moves.enumerated() {
            switch move.kind {
            case .pencil:
                // Notes never move a candidate the solver can see — it derives
                // them from entries — so this is a no-op for classification.
                // It is still pushed, because undo pops it.
                stack.append((.pencil, move.cell, entries[move.cell]))

            case .place:
                guard (0..<81).contains(move.cell), (1...9).contains(move.digit) else { continue }
                placements.append(classify(
                    moveIndex: index, cell: move.cell, digit: move.digit,
                    entries: entries, solution: solution, allowed: allowed, context: context
                ))
                stack.append((.place, move.cell, entries[move.cell]))
                entries[move.cell] = move.digit

            case .erase:
                guard (0..<81).contains(move.cell) else { continue }
                stack.append((.erase, move.cell, entries[move.cell]))
                entries[move.cell] = 0

            case .undo:
                // **`digit == 0` is an undone auto-notes fill, exactly.**
                // `applyAutoNotes` pushes an undo entry and appends *nothing*
                // to the move log, so its undo has no move to pop here — and it
                // is discriminable without ambiguity, because every real
                // pencil, place and erase guards `(1...9).contains(digit)`.
                // Skipping it is what keeps this mirror aligned with the stack
                // the game actually popped.
                guard move.digit != 0, let undone = stack.popLast() else { continue }
                if undone.kind != .pencil, (0..<81).contains(undone.cell) {
                    entries[undone.cell] = undone.previousEntry
                }
            }
        }
        return ReplayAnalysis(placements: placements)
    }

    private static func classify(
        moveIndex: Int, cell: Int, digit: Int,
        entries: [Int], solution: [Int],
        allowed: [Technique], context: ConstraintContext
    ) -> ClassifiedPlacement {
        func result(_ kind: PlacementClass, _ technique: Technique? = nil) -> ClassifiedPlacement {
            ClassifiedPlacement(
                moveIndex: moveIndex, cell: cell, digit: digit, kind: kind, technique: technique
            )
        }
        guard digit == solution[cell] else { return result(.slip) }

        // The state as the player saw it. A cell already holding a wrong digit
        // is emptied first: the player is overwriting a slip, and the board
        // they were reasoning about is the one without it.
        var visible = entries
        if visible[cell] != 0 { visible[cell] = 0 }
        let state = CandidateState(grid: SudokuGrid(cells: visible), context: context)

        // A single candidate is a naked single, whatever else is also true.
        // O(1), and it is most of every solve — which is what keeps the two
        // chain runs below off the hot path.
        if state.candidates[cell].nonzeroBitCount == 1 {
            return result(.forced)
        }

        // **The question is what *unlocked* the cell, not what placed it.**
        //
        // The obvious implementation — "does technique T place this cell?" —
        // is a lane that cannot fire, and it was written before it was
        // measured. PRD-25 §2.4 already records the reason: every pair,
        // box-line, fish and wing *eliminates*; only the singles (and
        // `cageSingle`) ever carry a `placement`. So a per-technique placement
        // probe can only ever answer `hiddenSingle`, `headline` would be
        // permanently nil, and "You found the X-Wing at move 31" would never
        // appear on any board — with every test green.
        //
        // So: exhaust the singles first. If the cell falls to them, the player
        // did the reachable thing. If it does not, run the full chain and name
        // the hardest technique above the singles that fired before the cell
        // came out — that technique is what the player had to see.
        if resolves(cell, to: digit, from: state, allowed: singles) { return result(.forced) }

        var chain = state
        var unlocked: Technique?
        for _ in 0..<chainBudget {
            guard let step = LogicSolver.nextStep(in: chain, allowed: allowed) else { break }
            if step.technique.rank > Technique.hiddenSingle.rank {
                unlocked = max(unlocked ?? step.technique, step.technique)
            }
            LogicSolver.apply(step, to: &chain)
            if chain.values[cell] != 0 {
                guard chain.values[cell] == digit, let unlocked else { return result(.leap) }
                return result(.found, unlocked)
            }
        }
        return result(.leap)
    }

    /// The two techniques that place rather than eliminate. Named once, here,
    /// because three things below depend on the same list agreeing.
    private static let singles: [Technique] = [.nakedSingle, .hiddenSingle]

    /// How far the chain may run looking for one cell. A classic board's whole
    /// solve is ~60 steps, so this is generous rather than tight; it exists so
    /// a pathological state cannot turn a debrief into a hang.
    private static let chainBudget = 200

    /// Does `allowed`, run to exhaustion from `state`, put `digit` in `cell`?
    private static func resolves(
        _ cell: Int, to digit: Int, from state: CandidateState, allowed: [Technique]
    ) -> Bool {
        var chain = state
        for _ in 0..<chainBudget {
            guard let step = LogicSolver.nextStep(in: chain, allowed: allowed) else { break }
            LogicSolver.apply(step, to: &chain)
            if chain.values[cell] != 0 { return chain.values[cell] == digit }
        }
        return false
    }
}
