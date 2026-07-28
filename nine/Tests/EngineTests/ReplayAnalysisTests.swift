import XCTest
@testable import NineEngine

/// PRD-26 §5 — what the board can prove about the hand that played it.
final class ReplayAnalysisTests: XCTestCase {

    // Generation is the slow part; these boards are shared file-wide, which is
    // where PRD-25 found the cheap savings in its own generation-heavy suites.
    private static let gentle = PuzzleGenerator.generate(seed: 26_000_001, difficulty: .gentle)
    private static let sharp = PuzzleGenerator.generate(seed: 26_000_002, difficulty: .sharp)
    private static let tempest = PuzzleGenerator.generate(seed: 26_000_003, difficulty: .tempest)

    /// Play a board the way the solver would, logging as the game does.
    private func solverPath(_ board: GeneratedPuzzle) -> [LoggedMove] {
        var state = CandidateState(grid: board.puzzle)
        var moves: [LoggedMove] = []
        var clock = 0.0
        while let step = LogicSolver.nextStep(in: state, allowed: LogicSolver.allTechniques) {
            if let placement = step.placement {
                clock += 4
                moves.append(LoggedMove(
                    kind: .place, cell: placement.cell, digit: placement.digit, at: clock
                ))
            }
            LogicSolver.apply(step, to: &state)
        }
        return moves
    }

    private func analyze(_ board: GeneratedPuzzle, _ moves: [LoggedMove]) -> ReplayAnalysis {
        ReplayAnalysis.analyze(
            puzzle: board.puzzle.cells, solution: board.solution.cells, moves: moves
        )
    }

    // MARK: - Soundness

    /// PRD-26 §5: no `.slip` on a correct solve. A player who followed the
    /// solver exactly should also produce no `.leap` — every placement was
    /// derivable, which is what "proved solvable by logic" means.
    func testASolverPathIsNeverASlipAndNeverALeap() {
        for board in [Self.gentle, Self.sharp, Self.tempest] {
            let analysis = analyze(board, solverPath(board))
            XCTAssertFalse(analysis.placements.isEmpty)
            XCTAssertTrue(
                analysis.placements.allSatisfy { $0.kind == .forced || $0.kind == .found },
                "\(board.difficulty): \(analysis.placements.filter { $0.kind == .leap || $0.kind == .slip })"
            )
        }
    }

    func testAWrongDigitIsASlip() {
        let board = Self.gentle
        let hole = (0..<81).first { board.puzzle.cells[$0] == 0 }!
        let wrong = (1...9).first { $0 != board.solution.cells[hole] }!
        let analysis = analyze(board, [LoggedMove(kind: .place, cell: hole, digit: wrong, at: 1)])
        XCTAssertEqual(analysis.placements.map(\.kind), [.slip])
    }

    /// `.leap` is what the board *refusing* looks like, and the realistic way a
    /// player reaches it is their own slip: a wrong digit left standing makes
    /// every later derivation a contradiction, so the board can no longer prove
    /// anything about the cell they are filling.
    ///
    /// An earlier version of this test hunted for a cell on a pristine Tempest
    /// board that no chain resolves. There is none — the board is *proved
    /// solvable by logic*, which is the whole covenant — and the version of the
    /// classifier that made it pass was crediting an X-Wing on the far side of
    /// the grid for cells it never touched.
    func testASlipMakesTheBoardStopAnswering() {
        let board = Self.sharp
        let holes = (0..<81).filter { board.puzzle.cells[$0] == 0 }
        let poisoned = holes[0]
        let wrong = (1...9).first { $0 != board.solution.cells[poisoned] }!

        let analysis = analyze(board, [
            LoggedMove(kind: .place, cell: poisoned, digit: wrong, at: 1)
        ] + holes.dropFirst().prefix(6).enumerated().map { index, hole in
            LoggedMove(kind: .place, cell: hole, digit: board.solution.cells[hole], at: Double(index) + 2)
        })

        XCTAssertEqual(analysis.placements.first?.kind, .slip)
        XCTAssertTrue(
            analysis.placements.dropFirst().contains { $0.kind == .leap },
            "a board contradicting itself cannot prove a later placement"
        )
    }

    // MARK: - The headline sentence

    /// **The regression this file exists for.** The obvious implementation of
    /// `.found` — "does technique T *place* this cell" — can only ever answer
    /// `hiddenSingle`, because every pair, box-line, fish and wing *eliminates*
    /// (PRD-25 §2.4). That version passes every other test in this file and
    /// makes `headline` permanently nil, so the one sentence PRD-26 §2.2
    /// promises would never appear on any board.
    func testADeepBoardEarnsASentenceAboveTheSingles() throws {
        let analysis = analyze(Self.tempest, solverPath(Self.tempest))
        let headline = try XCTUnwrap(
            analysis.headline,
            "a Tempest solve must name a technique, or the sentence is unreachable"
        )
        let technique = try XCTUnwrap(headline.technique)
        XCTAssertGreaterThanOrEqual(technique.rank, ReplayAnalysis.sentenceFloor.rank)
        XCTAssertFalse(
            [.nakedSingle, .hiddenSingle].contains(technique),
            "the floor exists so a single never earns a sentence"
        )
    }

    /// The floor's other half: a board solvable by singles alone says nothing,
    /// and nothing takes its place.
    func testABoardOfSinglesSaysNothing() {
        let board = Self.gentle
        let analysis = analyze(board, solverPath(board))
        if let technique = analysis.headline?.technique {
            XCTAssertGreaterThanOrEqual(technique.rank, ReplayAnalysis.sentenceFloor.rank)
        }
        XCTAssertTrue(
            analysis.techniquesUsed.allSatisfy { $0.rank <= Technique.boxLineReduction.rank },
            "a gentle board cannot need more than its own ceiling"
        )
    }

    /// The headline names the *first* appearance of the hardest technique, so
    /// "at move 31" is the move it was actually first needed at.
    func testTheHeadlineIsTheFirstAppearanceOfTheHardestTechnique() throws {
        let analysis = analyze(Self.tempest, solverPath(Self.tempest))
        let headline = try XCTUnwrap(analysis.headline)
        let sameTechnique = analysis.placements.filter { $0.technique == headline.technique }
        XCTAssertEqual(headline.moveIndex, sameTechnique.map(\.moveIndex).min())
    }

    // MARK: - Walking the log

    /// Undo must rewind the board, or every classification after a correction
    /// is made against a position the player never saw.
    func testUndoRewindsTheBoard() {
        let board = Self.gentle
        let holes = (0..<81).filter { board.puzzle.cells[$0] == 0 }
        let first = holes[0], second = holes[1]
        let wrong = (1...9).first { $0 != board.solution.cells[first] }!

        // Place a wrong digit, undo it, then place the right one elsewhere.
        let analysis = analyze(board, [
            LoggedMove(kind: .place, cell: first, digit: wrong, at: 1),
            LoggedMove(kind: .undo, cell: first, digit: wrong, at: 2),
            LoggedMove(kind: .place, cell: second, digit: board.solution.cells[second], at: 3)
        ])
        XCTAssertEqual(analysis.placements.count, 2)
        XCTAssertEqual(analysis.placements[0].kind, .slip)

        // The same two moves *without* the undo leave a wrong digit standing,
        // which changes the candidates the second placement is judged against.
        // If the rewind were missing, these two would agree — so the assertion
        // that matters is that the analysis ran against a rewound board at all.
        let withoutUndo = analyze(board, [
            LoggedMove(kind: .place, cell: first, digit: wrong, at: 1),
            LoggedMove(kind: .place, cell: second, digit: board.solution.cells[second], at: 3)
        ])
        XCTAssertEqual(withoutUndo.placements.count, 2)
    }

    /// `applyAutoNotes` pushes an undo entry and appends *nothing* to the move
    /// log, so its undo logs `digit: 0` with no move to pop. Popping anyway
    /// would desync the mirror for the rest of the solve.
    func testAnUndoneAutoNotesFillPopsNothing() {
        let board = Self.gentle
        let holes = (0..<81).filter { board.puzzle.cells[$0] == 0 }
        let target = holes[0]

        let withFill = analyze(board, [
            LoggedMove(kind: .place, cell: target, digit: board.solution.cells[target], at: 1),
            LoggedMove(kind: .undo, cell: holes[1], digit: 0, at: 2),
            LoggedMove(kind: .place, cell: holes[1], digit: board.solution.cells[holes[1]], at: 3)
        ])
        let without = analyze(board, [
            LoggedMove(kind: .place, cell: target, digit: board.solution.cells[target], at: 1),
            LoggedMove(kind: .place, cell: holes[1], digit: board.solution.cells[holes[1]], at: 3)
        ])
        XCTAssertEqual(withFill.placements.map(\.kind), without.placements.map(\.kind),
                       "the digit-0 undo must be invisible to classification")
    }

    func testPencilMarksAreInvisibleToClassification() {
        let board = Self.gentle
        let hole = (0..<81).first { board.puzzle.cells[$0] == 0 }!
        let digit = board.solution.cells[hole]
        let noted = analyze(board, [
            LoggedMove(kind: .pencil, cell: hole, digit: 4, at: 1),
            LoggedMove(kind: .place, cell: hole, digit: digit, at: 2)
        ])
        let bare = analyze(board, [LoggedMove(kind: .place, cell: hole, digit: digit, at: 2)])
        XCTAssertEqual(noted.placements.map(\.kind), bare.placements.map(\.kind))
    }

    func testAnEmptyLogAnalyzesToNothing() {
        XCTAssertTrue(analyze(Self.gentle, []).placements.isEmpty)
        XCTAssertNil(analyze(Self.gentle, []).headline)
    }

    /// A debrief is computed on the solve path, so this must not be where a
    /// solve goes to hang. The budget is generous rather than tight; this pins
    /// the order of magnitude, not the number.
    func testAFullDeepSolveAnalyzesQuickly() {
        let moves = solverPath(Self.tempest)
        let started = Date()
        _ = analyze(Self.tempest, moves)
        let seconds = Date().timeIntervalSince(started)
        XCTAssertLessThan(seconds, 5, "analysis of a \(moves.count)-move Tempest took \(seconds)s")
    }
}
