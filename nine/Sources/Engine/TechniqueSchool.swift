// TechniqueSchool.swift — one lesson per technique, from a real board (PRD-25).
//
// **An exemplar is twenty bytes, not a puzzle.** `(seed, difficulty, stepIndex)`
// is enough, because `PuzzleGenerator.generate` is a pure function of the first
// two and the solver is a pure function of the result: the device regenerates
// the board, replays the trace to `stepIndex`, and reads the step off the end.
// Nothing is shipped as a serialized grid.
//
// That is not a size optimisation. A shipped grid is a *fork* of the generator —
// it keeps working after a solver change that would have produced a different
// board, so the day the two disagree is a day nothing tells anyone. An exemplar
// cannot rot quietly: it either still resolves to the technique it claims or CI
// says so on the next push (`TechniqueSchoolTests`), which is the same argument
// the golden corpus makes one layer down.
//
// The lesson list is *mined*, never hand-written — `NINE_MINE=1 swift test
// --filter TechniqueSchoolMiner` prints a replacement for the table below.
import Foundation
import CouchCore

/// One lesson: where to find a live example of a technique.
public struct TechniqueExemplar: Sendable, Equatable, Hashable {
    public let technique: Technique
    public let seed: UInt64
    public let difficulty: Difficulty
    /// Index into the generated puzzle's own trace. The position the lesson
    /// opens on is the board after steps `0..<stepIndex` have been applied, and
    /// the step at `stepIndex` is the one the lesson is about.
    public let stepIndex: Int

    public init(technique: Technique, seed: UInt64, difficulty: Difficulty, stepIndex: Int) {
        self.technique = technique
        self.seed = seed
        self.difficulty = difficulty
        self.stepIndex = stepIndex
    }
}

/// A resolved lesson: the position, and the deduction waiting in it.
public struct TechniqueLesson: Sendable, Equatable {
    public let exemplar: TechniqueExemplar
    /// Cell values at the lesson's position — the givens plus everything the
    /// replayed steps placed.
    public let values: [Int]
    /// Candidate mask per cell at that position. The lesson hands these to the
    /// player as pencil marks, because a technique you cannot see the notes for
    /// is a technique you cannot learn.
    public let candidates: [UInt16]
    /// Which of `values` came from the puzzle rather than from the replay.
    public let givens: [Bool]
    /// The deduction the lesson teaches, with its units resolved.
    public let coach: CoachStep

    public init(
        exemplar: TechniqueExemplar, values: [Int], candidates: [UInt16],
        givens: [Bool], coach: CoachStep
    ) {
        self.exemplar = exemplar
        self.values = values
        self.candidates = candidates
        self.givens = givens
        self.coach = coach
    }
}

public enum TechniqueSchool {

    /// The curriculum, in rank order — which is also teaching order, because
    /// rank *is* "how deep you have to go before you reach for this".
    ///
    /// **Classic only.** PRD-23's four variant techniques are behind a channel
    /// seal with no user-facing surface, and a lesson about a board the player
    /// cannot reach is a lie with a nice animation on it. They join when
    /// PRD-24 opens the channel.
    ///
    /// The bands climb with the ranks — gentle, gentle, steady, steady, steady,
    /// sharp, tempest, tempest, tempest, abyss — and that is the mined result
    /// rather than a hand-arranged one. It is worth reading as a sanity check on
    /// the whole difficulty ladder: each technique first becomes *necessary* at
    /// about the band that is named for it.
    ///
    /// The comment on each row is how many cells are still empty when the
    /// lesson opens, because a technique demonstrated on a nearly-finished
    /// board teaches nothing about finding it.
    ///
    /// GENERATED. See the miner in `TechniqueSchoolMinerTests`.
    public static let lessons: [TechniqueExemplar] = [
        TechniqueExemplar(technique: .nakedSingle, seed: 36, difficulty: .gentle, stepIndex: 0),  // 56 empty
        TechniqueExemplar(technique: .hiddenSingle, seed: 11, difficulty: .gentle, stepIndex: 0),  // 55 empty
        TechniqueExemplar(technique: .nakedPair, seed: 12, difficulty: .steady, stepIndex: 5),  // 50 empty
        TechniqueExemplar(technique: .hiddenPair, seed: 14, difficulty: .steady, stepIndex: 3),  // 50 empty
        TechniqueExemplar(technique: .boxLineReduction, seed: 39, difficulty: .steady, stepIndex: 10),  // 46 empty
        TechniqueExemplar(technique: .xWing, seed: 3002, difficulty: .sharp, stepIndex: 5),  // 49 empty
        TechniqueExemplar(technique: .swordfish, seed: 173, difficulty: .tempest, stepIndex: 16),  // 40 empty
        TechniqueExemplar(technique: .skyscraper, seed: 158, difficulty: .tempest, stepIndex: 10),  // 49 empty
        TechniqueExemplar(technique: .xyWing, seed: 86, difficulty: .tempest, stepIndex: 10),  // 45 empty
        TechniqueExemplar(technique: .simpleColoring, seed: 31, difficulty: .abyss, stepIndex: 6),  // 50 empty
    ]

    /// Resolve a lesson on device: regenerate, replay, and **prove** that the
    /// step at `stepIndex` is the technique the lesson claims.
    ///
    /// Returns nil rather than trapping when it does not. A lesson that has
    /// rotted should quietly leave the list on the player's phone; CI is where
    /// it should be loud.
    public static func resolve(_ exemplar: TechniqueExemplar) -> TechniqueLesson? {
        resolve(exemplar, in: PuzzleGenerator.generate(
            seed: exemplar.seed, difficulty: exemplar.difficulty))
    }

    /// The half that does not compose, split out so a caller holding the board
    /// already does not pay for it twice. Generating the ten curriculum boards
    /// is ~9 s in Debug, which is most of what the School costs in CI.
    static func resolve(
        _ exemplar: TechniqueExemplar, in puzzle: GeneratedPuzzle
    ) -> TechniqueLesson? {
        guard puzzle.steps.indices.contains(exemplar.stepIndex) else { return nil }
        let step = puzzle.steps[exemplar.stepIndex]
        guard step.technique == exemplar.technique else { return nil }

        var state = CandidateState(grid: puzzle.puzzle)
        for earlier in puzzle.steps[0..<exemplar.stepIndex] {
            LogicSolver.apply(earlier, to: &state)
        }
        // The trace is a property of the *puzzle*, so replaying it has to land
        // on a position the step still applies to. A placement whose cell is
        // already filled means the trace and the solver have drifted apart, and
        // the lesson is not safe to show.
        if let placement = step.placement, state.values[placement.cell] != 0 { return nil }
        let target = LogicSolver.targetUnit(for: step, in: state)

        return TechniqueLesson(
            exemplar: exemplar,
            values: state.values,
            candidates: state.candidates,
            givens: (0..<81).map { puzzle.puzzle[$0] != 0 },
            coach: CoachStep(
                step: step,
                patternUnit: LogicSolver.patternUnit(for: step, in: state, target: target),
                targetUnit: target))
    }

    /// Every lesson that resolves, in curriculum order. The list a player sees.
    public static func curriculum() -> [TechniqueLesson] {
        lessons.compactMap(resolve)
    }
}
