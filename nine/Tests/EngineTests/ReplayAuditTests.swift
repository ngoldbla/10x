// ReplayAuditTests.swift — PRD-29 §5, and the rule that every finding must be
// shown to be able to fire.
//
// PRD-24 shipped a band whose two knobs composed 200/200 and could never have
// rejected anything: `maxGivens` 30/24/18 against a measured max of 19/19/11.
// A constraint nobody falsified is a decision in costume. So each case below
// constructs the input that produces exactly one finding, and there is a test
// that a real solve produces none — because a gate that rejects everything is
// the same defect wearing the other sign.
import XCTest
@testable import NineEngine

final class ReplayAuditTests: XCTestCase {

    /// One real board, generated once: this file's cost is generation, not audit.
    private static let board = PuzzleGenerator.generate(seed: 29_290_731, difficulty: .steady)

    private var puzzle: [Int] { Self.board.puzzle.cells }
    private var solution: [Int] { Self.board.solution.cells }

    /// A perfect solve of `Self.board`: every hole filled with the proven digit,
    /// in cell order, one second apart.
    private func honestMoves(timed: Bool = true) -> [LoggedMove] {
        var moves: [LoggedMove] = []
        var t: TimeInterval = 1
        for cell in 0..<81 where puzzle[cell] == 0 {
            moves.append(LoggedMove(kind: .place, cell: cell, digit: solution[cell],
                                    at: timed ? t : nil))
            t += 1
        }
        return moves
    }

    private var honestSeconds: TimeInterval { TimeInterval(puzzle.count(where: { $0 == 0 })) }

    // MARK: - The clean case

    /// The gate has to let an honest solve through, and this is the assertion
    /// that stops the whole feature silently ranking nobody.
    func testAnHonestSolveIsClean() {
        let verdict = ReplayAudit.audit(
            puzzle: puzzle, moves: honestMoves(), claimedSeconds: honestSeconds)
        XCTAssertTrue(verdict.isClean, "an honest solve was refused: \(verdict.findings)")
    }

    /// An untimed log — every widget solve, every watch solve, every board that
    /// arrived over CloudKit with its log stripped — is clean, not suspect.
    /// PRD-26 §2.3's rule: an absent measurement is absent, never a fabrication
    /// and never an accusation.
    func testAnUntimedLogIsCleanRatherThanSuspect() {
        let verdict = ReplayAudit.audit(
            puzzle: puzzle, moves: honestMoves(timed: false), claimedSeconds: 0)
        XCTAssertTrue(verdict.isClean, "an untimed log was refused: \(verdict.findings)")
    }

    /// The path the player actually walked is messier than the one above: notes,
    /// slips, erases and undos all appear in a real log, and none of them is a
    /// finding. `ReplayWalk` unwinds the undo; the audit only asks where the
    /// board ended up.
    func testASlipCorrectedByUndoIsClean() {
        let holes = (0..<81).filter { puzzle[$0] == 0 }
        guard let first = holes.first, let second = holes.dropFirst().first else {
            return XCTFail("a steady board has holes")
        }
        let wrong = (1...9).first { $0 != solution[first] }!
        var moves: [LoggedMove] = [
            LoggedMove(kind: .pencil, cell: second, digit: 4, at: 0.5),
            LoggedMove(kind: .place, cell: first, digit: wrong, at: 1),
            LoggedMove(kind: .undo, cell: first, digit: wrong, at: 2),
        ]
        var t: TimeInterval = 3
        for cell in holes {
            moves.append(LoggedMove(kind: .place, cell: cell, digit: solution[cell], at: t))
            t += 1
        }
        let verdict = ReplayAudit.audit(puzzle: puzzle, moves: moves, claimedSeconds: t)
        XCTAssertTrue(verdict.isClean, "a corrected slip was refused: \(verdict.findings)")
    }

    // MARK: - `unreadable`

    func testAGridThatIsNotEightyOneCellsIsUnreadable() {
        let verdict = ReplayAudit.audit(puzzle: [1, 2, 3], moves: [], claimedSeconds: 0)
        XCTAssertEqual(verdict.findings, [.unreadable])
    }

    func testADigitOutsideTheAlphabetIsUnreadable() {
        var broken = puzzle
        broken[0] = 42
        let verdict = ReplayAudit.audit(puzzle: broken, moves: [], claimedSeconds: 0)
        XCTAssertEqual(verdict.findings, [.unreadable])
    }

    /// The `SolveReplay` door, rather than the array one: a blob whose magic and
    /// version do not check out unpacks to nil, and nothing else can be said
    /// about it.
    func testAPackedBlobThatDoesNotUnpackIsUnreadableAndNothingElse() {
        let replay = SolveReplay(
            boardID: UUID(), solvedAt: Date(), band: Difficulty.steady.rawValue,
            isDaily: true, seconds: 300, packed: Data([0x00, 0x01, 0x02]))
        XCTAssertEqual(ReplayAudit.audit(replay).findings, [.unreadable])
    }

    // MARK: - `notProvable`

    /// An empty grid has 6.6 × 10^21 solutions. A record claiming to be a solve
    /// of one is a record of a board nobody was handed.
    func testAGridWithNoUniqueSolutionIsNotProvable() {
        let verdict = ReplayAudit.audit(
            puzzle: [Int](repeating: 0, count: 81), moves: [], claimedSeconds: 60)
        XCTAssertTrue(verdict.findings.contains(.notProvable))
    }

    /// And the other direction: a contradictory grid has *zero* solutions, which
    /// is the same finding for the opposite reason. Both are "there is no proven
    /// grid to compare the walk against", which is what the name says.
    func testAContradictoryGridIsNotProvable() {
        var broken = [Int](repeating: 0, count: 81)
        broken[0] = 5
        broken[1] = 5
        let verdict = ReplayAudit.audit(puzzle: broken, moves: [], claimedSeconds: 60)
        XCTAssertTrue(verdict.findings.contains(.notProvable))
    }

    // MARK: - `illegalMove`

    /// A clue is not the player's to place on. `NineGame.place` refuses it, so a
    /// log that contains one did not come from the game.
    func testWritingOverAGivenIsAnIllegalMove() {
        guard let given = (0..<81).first(where: { puzzle[$0] != 0 }) else {
            return XCTFail("a steady board has givens")
        }
        var moves = honestMoves()
        moves.insert(LoggedMove(kind: .place, cell: given, digit: solution[given], at: 0.5),
                     at: 0)
        let verdict = ReplayAudit.audit(
            puzzle: puzzle, moves: moves, claimedSeconds: honestSeconds)
        XCTAssertTrue(verdict.findings.contains(.illegalMove))
    }

    /// Erasing one is the same offence with the other verb, and it is the one
    /// that also changes the board — so without this check the walk would end
    /// somewhere the solution is not, and the finding would be the wrong one.
    func testErasingAGivenIsAnIllegalMove() {
        guard let given = (0..<81).first(where: { puzzle[$0] != 0 }) else {
            return XCTFail("a steady board has givens")
        }
        var moves = honestMoves()
        moves.insert(LoggedMove(kind: .erase, cell: given, digit: 0, at: 0.5), at: 0)
        let verdict = ReplayAudit.audit(
            puzzle: puzzle, moves: moves, claimedSeconds: honestSeconds)
        XCTAssertTrue(verdict.findings.contains(.illegalMove))
    }

    /// A cell off the end of the board. `SolveReplay.unpack` cannot produce one —
    /// it guards `(0..<81)` — so like `nonMonotoneTiming` this fires only on a
    /// log handed in directly, and the test says so by building one.
    func testACellOffTheBoardIsAnIllegalMove() {
        let moves = [LoggedMove(kind: .place, cell: 200, digit: 3, at: 1)]
        XCTAssertTrue(
            ReplayAudit.audit(puzzle: puzzle, moves: moves, claimedSeconds: 1)
                .findings.contains(.illegalMove))
    }

    // MARK: - `unfinished`

    /// The headline check: the board the log walks to must be the board the
    /// prover says is the answer.
    func testALogThatDoesNotFinishTheBoardIsUnfinished() {
        let verdict = ReplayAudit.audit(
            puzzle: puzzle, moves: Array(honestMoves().dropLast(3)),
            claimedSeconds: honestSeconds)
        XCTAssertTrue(verdict.findings.contains(.unfinished))
    }

    /// A full grid that is *wrong* is also unfinished — the check is equality
    /// with the proven solution, not "81 non-zero cells". Two digits swapped
    /// inside one row keeps the cell count and breaks the answer.
    func testAFullButWrongGridIsUnfinished() {
        var moves = honestMoves()
        guard moves.count >= 2 else { return XCTFail("a steady board has holes") }
        let a = moves[0], b = moves[1]
        moves[0] = LoggedMove(kind: .place, cell: a.cell, digit: b.digit, at: a.at)
        moves[1] = LoggedMove(kind: .place, cell: b.cell, digit: a.digit, at: b.at)
        XCTAssertTrue(
            ReplayAudit.audit(puzzle: puzzle, moves: moves, claimedSeconds: honestSeconds)
                .findings.contains(.unfinished))
    }

    // MARK: - `nonMonotoneTiming`

    /// **This check cannot fire on a replay that came through `unpack`**, and
    /// PRD-29 §5 says so rather than letting the green tick imply otherwise:
    /// the packed format stores unsigned deltas, so a reconstructed log is
    /// monotone by construction. It is kept because the audit's subject is a
    /// `[LoggedMove]` and one can arrive from somewhere else — and this is the
    /// falsification that proves the check works when it does apply.
    func testAStampThatGoesBackwardsIsNonMonotone() {
        var moves = honestMoves()
        guard moves.count >= 3 else { return XCTFail("a steady board has holes") }
        moves[2] = LoggedMove(kind: moves[2].kind, cell: moves[2].cell,
                              digit: moves[2].digit, at: 0.25)
        XCTAssertTrue(
            ReplayAudit.audit(puzzle: puzzle, moves: moves, claimedSeconds: honestSeconds)
                .findings.contains(.nonMonotoneTiming))
    }

    /// Two moves inside one decisecond share a stamp, because that is what a
    /// zero delta decodes to. Equal is fine; only backwards is a finding.
    func testTwoMovesAtTheSameInstantAreNotAFinding() {
        var moves = honestMoves()
        guard moves.count >= 3 else { return XCTFail("a steady board has holes") }
        moves[2] = LoggedMove(kind: moves[2].kind, cell: moves[2].cell,
                              digit: moves[2].digit, at: moves[1].at)
        XCTAssertFalse(
            ReplayAudit.audit(puzzle: puzzle, moves: moves, claimedSeconds: honestSeconds)
                .findings.contains(.nonMonotoneTiming))
    }

    /// The structural claim above, run rather than asserted: pack an
    /// deliberately non-monotone log and the finding is gone on the way back,
    /// because the format could not carry it.
    func testThePackedFormatCannotExpressANonMonotoneLog() {
        var moves = honestMoves()
        moves[2] = LoggedMove(kind: moves[2].kind, cell: moves[2].cell,
                              digit: moves[2].digit, at: 0.25)
        let packed = SolveReplay.pack(puzzle: puzzle, moves: moves)
        guard let back = SolveReplay.unpack(packed) else { return XCTFail("unpack") }
        XCTAssertFalse(
            ReplayAudit.audit(puzzle: back.puzzle, moves: back.moves,
                              claimedSeconds: honestSeconds)
                .findings.contains(.nonMonotoneTiming),
            "the deltas are unsigned; a round trip must have straightened this")
    }

    // MARK: - `claimShorterThanLog`

    /// The attack this actually catches: a log of a twenty-minute solve carrying
    /// a claim of forty seconds.
    func testAClaimShorterThanTheLogIsAFinding() {
        XCTAssertTrue(
            ReplayAudit.audit(puzzle: puzzle, moves: honestMoves(), claimedSeconds: 40)
                .findings.contains(.claimShorterThanLog))
    }

    /// A claim *longer* than the log is not a finding. Every board's clock keeps
    /// running after the last digit lands, and a player who paused is slower
    /// than their log, never faster — the check has a direction on purpose.
    func testAClaimLongerThanTheLogIsNotAFinding() {
        XCTAssertFalse(
            ReplayAudit.audit(puzzle: puzzle, moves: honestMoves(),
                              claimedSeconds: honestSeconds * 4)
                .findings.contains(.claimShorterThanLog))
    }

    /// The tolerance is the packed format's own quantization bound, not a
    /// number somebody liked: each delta is rounded to a decisecond
    /// independently, so the reconstructed prefix sum can sit up to
    /// `0.05 × moves` above the truth. A claim inside that band is honest.
    func testTheToleranceIsTheFormatsOwnRoundingBound() {
        let moves = honestMoves()
        let last = moves.compactMap(\.at).max() ?? 0
        let slack = ReplayAudit.timingTolerance(moveCount: moves.count)
        XCTAssertEqual(slack, 0.05 * Double(moves.count), accuracy: 1e-9)
        XCTAssertFalse(
            ReplayAudit.audit(puzzle: puzzle, moves: moves,
                              claimedSeconds: last - slack + 0.01)
                .findings.contains(.claimShorterThanLog),
            "a claim inside the rounding band is honest")
        XCTAssertTrue(
            ReplayAudit.audit(puzzle: puzzle, moves: moves,
                              claimedSeconds: last - slack - 1)
                .findings.contains(.claimShorterThanLog),
            "a claim outside it is not")
    }

    /// A zero claim on a timed log is the absent measurement, not a lie — the
    /// same reading `SolveReplay.isTimed` and the debrief's dropped lines take.
    func testAZeroClaimOnATimedLogIsNotAFinding() {
        XCTAssertFalse(
            ReplayAudit.audit(puzzle: puzzle, moves: honestMoves(), claimedSeconds: 0)
                .findings.contains(.claimShorterThanLog))
    }

    // MARK: - The `SolveReplay` door

    /// End to end through the format an actual submission would carry.
    func testARealPackedReplayAuditsClean() {
        let replay = SolveReplay(
            boardID: UUID(), solvedAt: Date(), band: Difficulty.steady.rawValue,
            isDaily: true, seconds: honestSeconds,
            packed: SolveReplay.pack(puzzle: puzzle, moves: honestMoves()))
        let verdict = ReplayAudit.audit(replay)
        XCTAssertTrue(verdict.isClean, "\(verdict.findings)")
    }

    /// Several findings at once, because a doctored record rarely has one thing
    /// wrong with it and a verdict that stopped at the first would under-report.
    func testAVerdictCarriesEveryFindingRatherThanTheFirst() {
        guard let given = (0..<81).first(where: { puzzle[$0] != 0 }) else {
            return XCTFail("a steady board has givens")
        }
        let moves = [LoggedMove(kind: .erase, cell: given, digit: 0, at: 90)]
        let verdict = ReplayAudit.audit(puzzle: puzzle, moves: moves, claimedSeconds: 3)
        XCTAssertEqual(verdict.findings, [.illegalMove, .unfinished, .claimShorterThanLog])
    }
}
