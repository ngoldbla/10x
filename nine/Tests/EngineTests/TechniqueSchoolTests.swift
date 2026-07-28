// TechniqueSchoolTests — CI validates every exemplar, and the miner that wrote
// them (PRD-25 §2.3).
//
// The whole point of shipping `(seed, difficulty, stepIndex)` instead of a
// serialized grid is that a *pure function of the seed* cannot rot quietly. A
// stored grid keeps rendering after a solver change that would now produce a
// different board; an exemplar either still resolves to the technique it claims
// or this file fails on the next push. Same argument as the golden corpus, one
// layer up.
//
// The miner is here rather than in a script for the same reason the corpus's
// freeze command is inside the test: the thing that generates the table and the
// thing that checks it must be the same code, or the table is checked against a
// second implementation that can disagree.
//
//     NINE_MINE=1 swift test --filter TechniqueSchoolMiner
import XCTest
import Foundation
@testable import NineEngine

final class TechniqueSchoolTests: XCTestCase {

    /// Resolved once for the whole class. Every assertion below wants the same
    /// ten boards, and regenerating them per test costs ~9 s each in Debug —
    /// the difference between a 36 s file and a 12 s one, against a suite
    /// budget of 120 s.
    /// The generated puzzle behind each lesson.
    private static let boards: [TechniqueExemplar: GeneratedPuzzle] =
        Dictionary(uniqueKeysWithValues: TechniqueSchool.lessons.map {
            ($0, PuzzleGenerator.generate(seed: $0.seed, difficulty: $0.difficulty))
        })

    /// Resolved from those boards rather than by composing them again — the
    /// two-argument `resolve` exists for exactly this.
    private static let resolved: [TechniqueExemplar: TechniqueLesson?] =
        Dictionary(uniqueKeysWithValues: TechniqueSchool.lessons.map { exemplar in
            (exemplar, boards[exemplar].flatMap { TechniqueSchool.resolve(exemplar, in: $0) })
        })

    /// Every lesson resolves, and resolves to what it says. This is the gate.
    func testEveryExemplarRegeneratesAndProves() throws {
        for exemplar in TechniqueSchool.lessons {
            let lesson = try XCTUnwrap(Self.resolved[exemplar] ?? nil, """
                \(exemplar.technique.rawValue) exemplar \
                (seed \(exemplar.seed), \(exemplar.difficulty.rawValue), \
                step \(exemplar.stepIndex)) no longer resolves. Generation moved \
                under it. Re-mine: NINE_MINE=1 swift test --filter TechniqueSchoolMiner
                """)
            XCTAssertEqual(lesson.coach.step.technique, exemplar.technique)

            // The pencil marks the lesson hands the player must never claim a
            // candidate plain sudoku already rules out. They are a *subset* of
            // a fresh peer-only read, not equal to it — the replay has also
            // applied every elimination the earlier steps made, which is the
            // whole reason the position is interesting.
            let state = CandidateState(grid: SudokuGrid(cells: lesson.values))
            for cell in 0..<81 {
                XCTAssertEqual(lesson.candidates[cell] & ~state.candidates[cell], 0, """
                    cell \(cell): the lesson offers a pencil mark that peer \
                    elimination alone already forbids
                    """)
            }

            // The position has to be *live*: the deduction must still be there
            // to make, or the lesson opens on a board where nothing happens.
            var replayed = CandidateState(grid: SudokuGrid(cells: lesson.values))
            for cell in 0..<81 where lesson.values[cell] == 0 {
                for digit in Sudoku.digits(in: replayed.candidates[cell] & ~lesson.candidates[cell]) {
                    replayed.eliminate(digit, at: cell)
                }
            }
            let next = LogicSolver.nextStep(
                in: replayed, allowed: exemplar.difficulty.allowedTechniques)
            XCTAssertEqual(next, lesson.coach.step, """
                \(exemplar.technique.rawValue): the position's next move is \
                \(next?.technique.rawValue ?? "nothing"), not the technique the \
                lesson is about — a player following the lesson would be shown \
                a pattern and then find a different one.
                """)
        }
    }

    /// One lesson per classic technique, no duplicates, in rank order. The
    /// curriculum is a list a player reads top to bottom.
    func testTheCurriculumCoversEveryClassicTechniqueOnce() {
        let taught = TechniqueSchool.lessons.map(\.technique)
        let classic = Technique.allCases.filter(\.isClassic)
        XCTAssertEqual(Set(taught), Set(classic), """
            the school teaches \(Set(taught).count) of \(classic.count) classic \
            techniques. Missing: \(Set(classic).subtracting(taught).map(\.rawValue).sorted())
            """)
        XCTAssertEqual(taught.count, Set(taught).count, "a technique is taught twice")
        XCTAssertEqual(taught, taught.sorted(), "lessons are not in rank order")

        // The four variant techniques stay out until PRD-24 opens the channel.
        XCTAssertTrue(taught.allSatisfy(\.isClassic),
                      "a lesson teaches a board the player cannot reach")
    }

    /// Every lesson's board is one a player could be looking at: the givens are
    /// the puzzle's, and everything else was placed by the replayed trace.
    func testALessonBoardIsTheRealBoardAtThatPoint() throws {
        for exemplar in TechniqueSchool.lessons {
            let lesson = try XCTUnwrap(Self.resolved[exemplar] ?? nil)
            let puzzle = try XCTUnwrap(Self.boards[exemplar])
            for cell in 0..<81 {
                XCTAssertEqual(lesson.givens[cell], puzzle.puzzle[cell] != 0, "cell \(cell)")
                if lesson.givens[cell] {
                    XCTAssertEqual(lesson.values[cell], puzzle.puzzle[cell], "cell \(cell)")
                }
                if lesson.values[cell] != 0 {
                    XCTAssertEqual(lesson.values[cell], puzzle.solution[cell],
                                   "cell \(cell): the lesson board disagrees with the solution")
                }
            }
        }
    }

    /// A lesson opens early enough to be readable. A technique demonstrated on
    /// a board with four empty cells left teaches nothing about finding it.
    func testLessonsOpenOnBoardsThatStillLookLikePuzzles() throws {
        for exemplar in TechniqueSchool.lessons {
            let lesson = try XCTUnwrap(Self.resolved[exemplar] ?? nil)
            let empty = lesson.values.count { $0 == 0 }
            XCTAssertGreaterThanOrEqual(empty, 20, """
                \(exemplar.technique.rawValue)'s lesson opens with only \(empty) empty \
                cells. The pattern is real but the board is nearly finished, which is \
                not what finding it feels like.
                """)
        }
    }
}

/// The generator for the table above. Opt-in — it composes hundreds of boards.
final class TechniqueSchoolMinerTests: XCTestCase {

    private var mining: Bool {
        ProcessInfo.processInfo.environment["NINE_MINE"] == "1"
    }

    /// Search for the earliest clean example of each classic technique and
    /// print a `lessons` table.
    ///
    /// "Clean" is three things, and they are teaching criteria rather than
    /// correctness ones: the step must come **early** (a board that still looks
    /// like a puzzle), the technique must be the **first** occurrence in that
    /// board's trace, and lower bands are searched first so a naked single is
    /// taught on a Gentle board rather than on an Abyss one.
    func testMineTheCurriculum() throws {
        try XCTSkipIf(!mining, "set NINE_MINE=1 to re-mine the curriculum")

        // Band order is teaching order: the shallowest band that can show a
        // technique is the one whose board is least intimidating.
        let hunt: [(Difficulty, ClosedRange<UInt64>)] = [
            (.gentle, 1...40), (.steady, 1...40), (.sharp, 3000...3040),
            (.tempest, 1...200), (.abyss, 1...200),
        ]
        var best = [Technique: TechniqueExemplar]()
        var emptiest = [Technique: Int]()
        var settledIn = [Technique: Difficulty]()

        for (difficulty, seeds) in hunt {
            for seed in seeds {
                let puzzle = PuzzleGenerator.generate(seed: seed, difficulty: difficulty)
                var state = CandidateState(grid: puzzle.puzzle)
                for (index, step) in puzzle.steps.enumerated() {
                    defer { LogicSolver.apply(step, to: &state) }
                    guard step.technique.isClassic else { continue }
                    // **Shallowest band wins, and only then emptiest board.**
                    // The first version of this rule compared emptiness across
                    // every band and taught Naked Single on a Sharp board,
                    // because a harder board is a *lonelier* board and always
                    // won the tie-break. A first lesson should not open on the
                    // hardest thing Nine can make.
                    if let settled = settledIn[step.technique], settled != difficulty { continue }
                    let empty = state.values.count { $0 == 0 }
                    guard empty > (emptiest[step.technique] ?? 0) else { continue }
                    settledIn[step.technique] = difficulty
                    emptiest[step.technique] = empty
                    best[step.technique] = TechniqueExemplar(
                        technique: step.technique, seed: seed,
                        difficulty: difficulty, stepIndex: index)
                }
            }
        }

        var lines = ["    public static let lessons: [TechniqueExemplar] = ["]
        for technique in Technique.allCases where technique.isClassic {
            guard let exemplar = best[technique] else {
                lines.append("    // NOT FOUND: \(technique.rawValue)")
                continue
            }
            lines.append(String(
                format: "        TechniqueExemplar(technique: .%@, seed: %d, "
                    + "difficulty: .%@, stepIndex: %d),  // %d empty",
                technique.rawValue, Int(exemplar.seed),
                exemplar.difficulty.rawValue, exemplar.stepIndex,
                emptiest[technique] ?? 0))
        }
        lines.append("    ]")
        FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }
}
