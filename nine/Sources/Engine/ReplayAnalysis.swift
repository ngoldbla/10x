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

        // The undo mirror lives in `ReplayWalk`, once, because the comet needs
        // the identical walk and two copies would drift silently the moment a
        // `LoggedMove.Kind` case is appended.
        var placements: [ClassifiedPlacement] = []
        _ = ReplayWalk.walk(puzzle: puzzle, moves: moves) { beat in
            guard beat.move.kind == .place, (1...9).contains(beat.move.digit) else { return }
            placements.append(classify(
                moveIndex: beat.index, cell: beat.move.cell, digit: beat.move.digit,
                entries: beat.before, solution: solution, allowed: allowed, context: context
            ))
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

        // **The question is what unlocked *this cell*, and PRD-25 already
        // answers it.** `derivation` walks the ordinary solver and records only
        // the steps that touch this cell's own candidates — which is exactly
        // "why must this be a 7", asked at the moment the player answered it.
        //
        // Two wrong versions were written and measured before this one, and
        // both are worth naming because each looks right:
        //
        //   1. *"Does technique T place this cell?"* — a lane that cannot fire.
        //      Every pair, box-line, fish and wing **eliminates**; only the
        //      singles ever carry a `placement` (PRD-25 §2.4). It can answer
        //      nothing but `hiddenSingle`, so `headline` is permanently nil and
        //      "You found the X-Wing at move 31" never appears on any board.
        //   2. *"Run the whole chain until the cell falls, name the hardest
        //      technique that fired."* — credits an X-Wing on the far side of
        //      the grid for a cell it never touched, and since every board is
        //      proved solvable by logic it makes `.leap` unreachable. That is
        //      what `testALeapIsReachable` caught.
        let grid = SudokuGrid(cells: visible)
        guard case .success(let derivation) = LogicSolver.derivation(
            forCell: cell, in: grid, allowed: allowed, context: context
        ), derivation.digit == digit else { return result(.leap) }

        // **`elsewhere` is deliberately not consulted, and that was measured.**
        // Gating on `elsewhere == 0` — "no unrelated work first" — reads as the
        // principled bar and fails the solver's own path: the chain takes
        // elimination-only steps between placements, none of which bear on the
        // cell it is about to fill, so a perfectly-played Sharp board produced
        // seven leaps and a Tempest board named no technique at all. Any
        // non-zero bar would be a number nobody could defend, so there is none.
        //
        // What is left is exactly PRD-25's answer to "why must this be a 7",
        // reused rather than re-litigated: the hardest technique that bore on
        // *this* cell. `.leap` is what the board refusing looks like — a
        // contradiction the player's own slip introduced, or a cell that does
        // not follow inside the band's ceiling.

        // All-singles is `.forced`: a hidden single is the reachable move on a
        // cell with a choice, and "You found the Hidden Single" is a sentence
        // that would appear on nearly every board and mean nothing on any.
        guard let hardest = derivation.steps.map(\.coach.step.technique).max(),
              hardest.rank > Technique.hiddenSingle.rank else { return result(.forced) }
        return result(.found, hardest)
    }
}
