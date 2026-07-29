// GameTests — play-state behavior: placement, pencil auto-erase, undo,
// contradiction detection, completion, the injectable-clock timer, streaks.
import XCTest
import CouchCore
@testable import NineEngine

final class GameTests: XCTestCase {

    var puzzle: GeneratedPuzzle!
    var game: NineGame!
    var hole: Int! // first empty cell

    override func setUp() {
        super.setUp()
        puzzle = PuzzleGenerator.generate(seed: 1, difficulty: .gentle)
        game = NineGame(puzzle: puzzle)
        hole = (0..<81).first { puzzle.puzzle[$0] == 0 }
    }

    // MARK: - Placement & undo

    func testPlaceAndUndoRestoresEntry() {
        let digit = puzzle.solution[hole]
        XCTAssertTrue(game.place(digit, at: hole))
        XCTAssertEqual(game.entry(at: hole), digit)
        let move = game.undo()
        XCTAssertEqual(move?.kind, .place)
        XCTAssertEqual(move?.digit, digit, "toast shows the reverted digit")
        XCTAssertEqual(game.entry(at: hole), 0)
        XCTAssertNil(game.undo(), "empty stack undo is nil")
    }

    func testPlacementOnGivenIsRejected() {
        let given = (0..<81).first { puzzle.puzzle[$0] != 0 }!
        XCTAssertFalse(game.place(5, at: given))
        XCTAssertEqual(game.entry(at: given), puzzle.puzzle[given])
        XCTAssertTrue(game.undoStack.isEmpty)
    }

    func testPencilMarksAutoEraseOnPlacementAndUndoRestoresThem() {
        let digit = puzzle.solution[hole]
        // Mark `digit` in an empty peer, plus a stray note in the cell itself.
        let peer = Sudoku.peers[hole].first { puzzle.puzzle[$0] == 0 && $0 != hole }!
        XCTAssertTrue(game.togglePencil(digit, at: peer))
        XCTAssertTrue(game.togglePencil(digit, at: hole))
        XCTAssertEqual(game.pencilDigits(at: peer), [digit])

        XCTAssertTrue(game.place(digit, at: hole))
        XCTAssertTrue(game.pencilDigits(at: peer).isEmpty, "peer note auto-erased")
        XCTAssertTrue(game.pencilDigits(at: hole).isEmpty, "own notes cleared")

        game.undo() // revert the placement
        XCTAssertEqual(game.entry(at: hole), 0)
        XCTAssertEqual(game.pencilDigits(at: peer), [digit], "undo restores peer note")
        XCTAssertEqual(game.pencilDigits(at: hole), [digit], "undo restores own note")
    }

    func testPencilToggleOnAndOffAndUndo() {
        XCTAssertTrue(game.togglePencil(3, at: hole))
        XCTAssertTrue(game.togglePencil(7, at: hole))
        XCTAssertEqual(game.pencilDigits(at: hole), [3, 7])
        XCTAssertTrue(game.togglePencil(3, at: hole)) // toggle off
        XCTAssertEqual(game.pencilDigits(at: hole), [7])
        game.undo()
        XCTAssertEqual(game.pencilDigits(at: hole), [3, 7])
    }

    func testEraseAndUndo() {
        let digit = puzzle.solution[hole]
        game.place(digit, at: hole)
        XCTAssertTrue(game.erase(at: hole))
        XCTAssertEqual(game.entry(at: hole), 0)
        let move = game.undo()
        XCTAssertEqual(move?.kind, .erase)
        XCTAssertEqual(game.entry(at: hole), digit)
    }

    // MARK: - Errors & completion

    func testContradictionDetectionAgainstSolution() {
        let right = puzzle.solution[hole]
        let wrong = right == 9 ? 1 : right + 1
        game.place(wrong, at: hole)
        XCTAssertTrue(game.isError(at: hole))
        XCTAssertEqual(game.errorCells, [hole])
        game.place(right, at: hole)
        XCTAssertFalse(game.isError(at: hole))
        XCTAssertTrue(game.errorCells.isEmpty)
    }

    func testCompletionDetectionAndDigitCounts() {
        for cell in 0..<81 where puzzle.puzzle[cell] == 0 {
            game.place(puzzle.solution[cell], at: cell)
        }
        XCTAssertTrue(game.isComplete)
        XCTAssertTrue(game.isSolved)
        XCTAssertEqual(game.fillFraction, 1.0)
        for digit in 1...9 {
            XCTAssertEqual(game.count(of: digit), 9)
            XCTAssertTrue(game.isDigitComplete(digit))
        }
    }

    func testCompleteButWrongIsNotSolved() {
        var filled = game!
        for cell in 0..<81 where puzzle.puzzle[cell] == 0 {
            let right = puzzle.solution[cell]
            filled.place(right == 9 ? 1 : right + 1, at: cell)
        }
        XCTAssertTrue(filled.isComplete)
        XCTAssertFalse(filled.isSolved)
        XCTAssertFalse(filled.errorCells.isEmpty)
    }

    func testGameStateSerializesRoundTrip() throws {
        game.place(puzzle.solution[hole], at: hole)
        game.timer.start(at: Date(timeIntervalSinceReferenceDate: 1000))
        game.timer.pause(at: Date(timeIntervalSinceReferenceDate: 1090))
        let data = try CouchJSON.encode(game)
        let decoded = try CouchJSON.decode(NineGame.self, from: data)
        XCTAssertEqual(decoded, game)
    }

    // MARK: - Move log (solve-replay groundwork)

    func testMoveLogRecordsPlacePencilEraseInOrder() {
        let digit = puzzle.solution[hole]
        game.togglePencil(3, at: hole)
        game.place(digit, at: hole)
        game.erase(at: hole)
        XCTAssertEqual(game.moveLog, [
            LoggedMove(kind: .pencil, cell: hole, digit: 3),
            LoggedMove(kind: .place, cell: hole, digit: digit),
            LoggedMove(kind: .erase, cell: hole, digit: digit),
        ])
    }

    func testUndoAppendsAnEventAndNeverPopsTheLog() {
        let digit = puzzle.solution[hole]
        game.place(digit, at: hole)
        game.undo()
        game.place(digit, at: hole)
        XCTAssertEqual(game.moveLog, [
            LoggedMove(kind: .place, cell: hole, digit: digit),
            LoggedMove(kind: .undo, cell: hole, digit: digit),
            LoggedMove(kind: .place, cell: hole, digit: digit),
        ], "a replay must retrace the true path, corrections included")
    }

    func testRejectedMovesAndEmptyUndoAreNotLogged() {
        let given = (0..<81).first { puzzle.puzzle[$0] != 0 }!
        game.place(5, at: given) // rejected: given cell
        game.togglePencil(5, at: given) // rejected: given cell
        game.erase(at: hole) // rejected: already empty
        game.undo() // rejected: empty stack
        XCTAssertTrue(game.moveLog.isEmpty)
    }

    func testMoveLogSurvivesSerializationRoundTrip() throws {
        game.place(puzzle.solution[hole], at: hole)
        game.undo()
        let decoded = try CouchJSON.decode(NineGame.self, from: CouchJSON.encode(game))
        XCTAssertEqual(decoded.moveLog, game.moveLog)
    }

    func testLegacySaveWithoutMoveLogDecodesToEmptyLog() throws {
        // A 1.1-era autosave blob has no `moveLog` key. Decoding must not
        // throw (CouchStored discards the whole save when it does) and the
        // log must come back empty.
        game.place(puzzle.solution[hole], at: hole)
        let data = try CouchJSON.encode(game)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "moveLog")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try CouchJSON.decode(NineGame.self, from: legacy)
        XCTAssertTrue(decoded.moveLog.isEmpty)
        XCTAssertEqual(decoded.entries, game.entries, "board state restores intact")
    }

    // MARK: - Board stats (the pull-down stats drawer)

    func testPencilMarkCountSumsMasks() {
        XCTAssertEqual(game.pencilMarkCount, 0)
        let digit = puzzle.solution[hole]
        let peer = Sudoku.peers[hole].first { puzzle.puzzle[$0] == 0 && $0 != hole }!
        game.togglePencil(digit, at: hole)
        game.togglePencil(digit, at: peer)
        game.togglePencil(digit == 9 ? 1 : digit + 1, at: peer)
        XCTAssertEqual(game.pencilMarkCount, 3, "one mark per set bit, summed over all cells")

        // Placement auto-erases the cell's own notes *and* the peer's matching
        // note, so the count drops by more than the one cell being filled.
        game.place(digit, at: hole)
        XCTAssertEqual(game.pencilMarkCount, 1, "own notes cleared + peer's matching note erased")
    }

    func testUndoCountReadsMoveLogEvents() {
        XCTAssertEqual(game.undoCount, 0)
        game.undo() // rejected: empty stack, logs nothing
        XCTAssertEqual(game.undoCount, 0, "an undo with nothing to revert does not count")

        let digit = puzzle.solution[hole]
        game.place(digit, at: hole)
        game.undo()
        game.place(digit, at: hole)
        game.undo()
        XCTAssertEqual(game.undoCount, 2)
    }

    func testPlacementCountExcludesPencilEraseUndo() {
        let digit = puzzle.solution[hole]
        let other = (0..<81).first { puzzle.puzzle[$0] == 0 && $0 != hole }!
        XCTAssertEqual(game.placementCount, 0)
        game.togglePencil(3, at: hole)   // pencil
        game.place(digit, at: hole)      // place  → 1
        game.erase(at: hole)             // erase
        game.undo()                      // undo
        game.place(puzzle.solution[other], at: other) // place → 2
        XCTAssertEqual(game.placementCount, 2, "only .place events count")
    }

    func testAveragePaceWithInjectedClock() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertNil(game.averageSecondsPerPlacement(at: t0), "no pace before the first placement")

        game.timer.start(at: t0)
        let other = (0..<81).first { puzzle.puzzle[$0] == 0 && $0 != hole }!
        game.place(puzzle.solution[hole], at: hole)
        game.place(puzzle.solution[other], at: other)
        // Undo the second one: two placements happened, but only one cell is
        // filled. The divisor must follow the effort, not the board — a
        // filled-cell divisor would read 60 here instead of 30.
        game.undo()
        XCTAssertEqual(game.entry(at: other), 0, "the undone cell is empty again")
        XCTAssertEqual(game.placementCount, 2, "the log keeps both placements")
        XCTAssertEqual(game.averageSecondsPerPlacement(at: t0.addingTimeInterval(60)) ?? 0,
                       30, accuracy: 0.001, "60s over 2 placements, one of them undone")
    }

    // MARK: - Timer (injectable clock)

    func testElapsedTimerWithInjectedClock() {
        var timer = ElapsedTimer()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(timer.elapsed(at: t0), 0)
        timer.start(at: t0)
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(30)), 30, accuracy: 0.001)
        timer.pause(at: t0.addingTimeInterval(30))
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(500)), 30, accuracy: 0.001,
                       "paused time does not accrue")
        timer.start(at: t0.addingTimeInterval(500))
        timer.start(at: t0.addingTimeInterval(600)) // double start is a no-op
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(510)), 40, accuracy: 0.001)
    }

    func testCloseOpenRunCapsAtTheGivenDate() {
        var timer = ElapsedTimer()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        timer.start(at: t0)
        // A process death (or a stale decode) means nobody watched the whole
        // interval, so closing must credit only up to `cap`, not "now".
        timer.closeOpenRun(notLaterThan: t0.addingTimeInterval(45))
        XCTAssertFalse(timer.isRunning, "closing a run stops it like pause does")
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(1_000)), 45, accuracy: 0.001,
                       "elapsed is capped at the close date, not the far-future read date")
    }

    func testCloseOpenRunIsANoOpOnAnAlreadyPausedTimer() {
        var timer = ElapsedTimer()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        timer.start(at: t0)
        timer.pause(at: t0.addingTimeInterval(10))
        timer.closeOpenRun(notLaterThan: t0.addingTimeInterval(9_999))
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(20_000)), 10, accuracy: 0.001,
                       "nothing was running, so there is nothing to close")
    }

    func testCloseOpenRunNeverGoesNegative() {
        var timer = ElapsedTimer()
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        timer.start(at: t0)
        // A cap earlier than `runningSince` (a clock the stored `updatedAt`
        // somehow predates) must add +0, never claw back accumulated time.
        timer.closeOpenRun(notLaterThan: t0.addingTimeInterval(-500))
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(500)), 0, accuracy: 0.001,
                       "max(0, …) means an earlier cap adds nothing, not a negative amount")
    }

    // MARK: - Streaks

    func testStreakIncrementsOnConsecutiveDays() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        XCTAssertEqual(streak.current, 1)
        streak.recordCompletion(day: 101)
        streak.recordCompletion(day: 102)
        XCTAssertEqual(streak.current, 3)
        XCTAssertEqual(streak.best, 3)
        XCTAssertTrue(streak.hasCompleted(day: 102))
    }

    func testStreakSameDayTwiceIsNoOp() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 100)
        XCTAssertEqual(streak.current, 1)
        streak.recordCompletion(day: 99) // time travel is also a no-op
        XCTAssertEqual(streak.current, 1)
    }

    func testStreakResetsAfterAGapButKeepsBest() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 101)
        streak.recordCompletion(day: 105)
        XCTAssertEqual(streak.current, 1)
        XCTAssertEqual(streak.best, 2)
    }

    func testDisplayedStreakLapsesWhenStale() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 101)
        XCTAssertEqual(streak.displayedStreak(today: 101), 2)
        XCTAssertEqual(streak.displayedStreak(today: 102), 2, "yesterday's chain is alive")
        // PRD-13 moved this cliff out by one day: with a bridge unspent, one
        // silent missed day no longer lapses the chip.
        XCTAssertEqual(streak.displayedStreak(today: 103), 2, "one silent day is bridgeable")
        XCTAssertEqual(streak.displayedStreak(today: 104), 0, "two silent days lapse")
    }

    // MARK: - Streak grace (PRD-13 §2)

    func testOneMissedDayBridgesInsteadOfBreaking() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 101)
        streak.recordCompletion(day: 103)           // 102 missed
        XCTAssertEqual(streak.current, 3, "the chain extends across the gap")
        XCTAssertEqual(streak.lastGraceDay, 102)
        XCTAssertTrue(streak.standsOnGrace)
    }

    func testBridgeThenNaturalThenBridgeIsAllowed() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 102)           // bridges 101
        XCTAssertTrue(streak.standsOnGrace)
        XCTAssertFalse(streak.graceAvailable)
        streak.recordCompletion(day: 103)           // a natural day re-earns it
        XCTAssertFalse(streak.standsOnGrace)
        XCTAssertTrue(streak.graceAvailable)
        streak.recordCompletion(day: 105)           // bridges 104
        XCTAssertEqual(streak.current, 4)
        XCTAssertEqual(streak.lastGraceDay, 104)
    }

    func testTwoBridgesBackToBackBreakTheStreak() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 102)           // bridges 101
        XCTAssertEqual(streak.current, 2)
        XCTAssertFalse(streak.graceAvailable, "no natural day has been earned since")
        streak.recordCompletion(day: 104)           // would bridge 103 — refused
        XCTAssertEqual(streak.current, 1, "non-stacking: the chain restarts")
        XCTAssertEqual(streak.best, 2)
    }

    func testTwoConsecutiveMissedDaysAlwaysBreak() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 101)
        streak.recordCompletion(day: 104)           // 102 and 103 missed
        XCTAssertEqual(streak.current, 1)
        XCTAssertNil(streak.lastGraceDay, "a gap too wide to bridge spends nothing")
    }

    func testGraceCountsTowardBestLikeAnyOtherChain() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 102)
        XCTAssertEqual(streak.best, 2, "best counts the chain, bridge included")
    }

    /// A broken chain leaves its spent bridge behind, and it stays harmless:
    /// `graceAvailable` compares against `lastCompletedDay`, which has moved
    /// past it, so the new chain gets its bridge without a clearing step that
    /// would be one more rule to keep true.
    func testABrokenChainStartsWithItsBridgeAvailableAgain() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 102)           // bridges 101
        streak.recordCompletion(day: 110)           // far gap: breaks
        XCTAssertEqual(streak.current, 1)
        XCTAssertTrue(streak.graceAvailable)
        XCTAssertFalse(streak.standsOnGrace, "a fresh 1 does not stand on a bridge")
        streak.recordCompletion(day: 112)           // bridges 111
        XCTAssertEqual(streak.current, 2)
        XCTAssertEqual(streak.lastGraceDay, 111)
    }

    /// The display rule and the bridge rule read the same predicate, so the
    /// chip can never promise a streak the next solve would break.
    func testDisplayedStreakHoldsThroughAGapOnlyWhileABridgeRemains() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 101)
        XCTAssertEqual(streak.displayedStreak(today: 103), 2, "one silent day is bridgeable")
        XCTAssertEqual(streak.displayedStreak(today: 104), 0, "two is not")

        var spent = StreakState()
        spent.recordCompletion(day: 100)
        spent.recordCompletion(day: 102)            // bridge spent on 101
        XCTAssertEqual(spent.displayedStreak(today: 103), 2, "alive: yesterday")
        XCTAssertEqual(
            spent.displayedStreak(today: 104), 0,
            "the bridge is spent, so solving today would restart at 1 — say so now"
        )
    }

    /// The property that makes the whole feature safe to reason about: what the
    /// chip shows today is what a solve today would leave behind. Swept over
    /// every reachable state rather than argued.
    func testTheChipNeverPromisesAStreakTheNextSolveWouldBreak() {
        // Every (gap, gap) pair reachable in two completions, from a base day.
        for firstGap in 1...4 {
            for secondGap in 1...4 {
                var streak = StreakState()
                streak.recordCompletion(day: 100)
                streak.recordCompletion(day: 100 + firstGap)
                let last = 100 + firstGap
                let today = last + secondGap
                let shown = streak.displayedStreak(today: today)
                var after = streak
                after.recordCompletion(day: today)
                XCTAssertFalse(
                    shown > 0 && after.current < streak.current,
                    """
                    gaps (\(firstGap), \(secondGap)): chip showed \(shown) and \
                    the solve dropped the chain \(streak.current) → \(after.current)
                    """
                )
            }
        }
    }

    // MARK: - Streaks: the archive can never write one (PRD-14)

    /// The bug the guarded form exists for, and the reason it is a fix rather
    /// than defence in depth. `recordCompletion(day:)`'s `day > last` check
    /// cannot fire when nothing has been completed yet — so a fresh install
    /// that solved yesterday from the archive would come away showing a
    /// one-day streak it never earned, on the one number that has to be true.
    func testArchiveSolveOfYesterdayLeavesAFreshStreakAtZero() {
        var streak = StreakState()
        // Opened today (9_500), for yesterday: an archive board.
        streak.recordCompletion(day: 9_499, openedOn: 9_500)
        XCTAssertEqual(streak.displayedStreak(today: 9_500), 0)
        XCTAssertNil(streak.lastCompletedDay)
        XCTAssertEqual(streak.current, 0)
        XCTAssertEqual(streak.best, 0)
    }

    /// And the same guard on a live streak: working backwards through a whole
    /// month of the archive leaves every field of the state untouched.
    func testArchiveSolveNeverDisturbsALiveStreak() {
        var streak = StreakState()
        streak.recordCompletion(day: 9_499, openedOn: 9_499)
        streak.recordCompletion(day: 9_500, openedOn: 9_500)
        let before = streak
        for pastDay in 9_400..<9_500 {
            streak.recordCompletion(day: pastDay, openedOn: 9_500)
        }
        XCTAssertEqual(streak, before)
        XCTAssertEqual(streak.displayedStreak(today: 9_500), 2)
    }

    func testTodayStillRecordsThroughTheGuardedForm() {
        var streak = StreakState()
        streak.recordCompletion(day: 9_500, openedOn: 9_500)
        XCTAssertEqual(streak.displayedStreak(today: 9_500), 1)
        XCTAssertEqual(streak.lastCompletedDay, 9_500)
    }

    /// The regression a clock-based guard caused, and the reason the guard is
    /// keyed on provenance instead: a daily opened at 23:55 and finished at
    /// 00:03 is still that day's daily, and must still extend the streak.
    /// `guard day >= todayOrdinal` threw this away on the ordinary path.
    func testADailySolvedAcrossMidnightStillCountsForItsOwnDay() {
        var streak = StreakState()
        streak.recordCompletion(day: 9_499, openedOn: 9_499)
        // Board opened on 9_500 for 9_500; the clock is 9_501 by the time the
        // last digit lands, but the board's provenance has not changed.
        streak.recordCompletion(day: 9_500, openedOn: 9_500)
        XCTAssertEqual(streak.current, 2)
        XCTAssertEqual(streak.lastCompletedDay, 9_500)
        XCTAssertEqual(streak.displayedStreak(today: 9_501), 2, "the chain is alive on the new day")
    }

    // MARK: - Auto notes (PRD-11 11b)

    func testAutoNotesFillsEveryEmptyCellWithItsLegalCandidates() {
        XCTAssertTrue(game.applyAutoNotes())
        for cell in 0..<81 where game.entry(at: cell) == 0 {
            let marks = game.pencilDigits(at: cell)
            XCTAssertFalse(marks.isEmpty, "cell \(cell) should carry candidates")
            for digit in marks {
                XCTAssertFalse(
                    Sudoku.peers[cell].contains { game.entry(at: $0) == digit },
                    "cell \(cell) noted \(digit), which a peer already holds"
                )
            }
        }
        for cell in 0..<81 where game.entry(at: cell) != 0 {
            XCTAssertFalse(game.hasPencilMarks(at: cell), "filled cells carry no notes")
        }
    }

    func testAutoNotesUndoesInExactlyOneStep() {
        let before = game.pencil
        XCTAssertTrue(game.applyAutoNotes())
        XCTAssertEqual(game.undoStack.count, 1, "a bulk fill is one undoable move")
        let move = game.undo()
        XCTAssertEqual(move?.kind, .pencil, "no new NineMove.Kind raw value exists")
        XCTAssertEqual(move?.isBulkNotes, true)
        XCTAssertEqual(game.pencil, before, "undo restores every touched cell")
    }

    func testAutoNotesIsANoOpWhenTheMarksAlreadyMatch() {
        XCTAssertTrue(game.applyAutoNotes())
        XCTAssertFalse(game.applyAutoNotes(), "nothing changed, so nothing is pushed")
        XCTAssertEqual(game.undoStack.count, 1)
    }

    func testASingleNoteIsNeverMistakenForABulkFill() {
        XCTAssertTrue(game.togglePencil(4, at: hole))
        XCTAssertEqual(game.undoStack.last?.isBulkNotes, false,
                       "the discriminator is snapshot count, and a toggle snapshots one cell")
    }

    func testPlaceWithAutoNotesFoldsTheRecomputeIntoTheSameMove() {
        XCTAssertTrue(game.applyAutoNotes())
        let stackBefore = game.undoStack.count
        let pencilBefore = game.pencil
        let digit = puzzle.solution[hole]
        XCTAssertTrue(game.place(digit, at: hole, autoNotes: true))
        XCTAssertEqual(game.undoStack.count, stackBefore + 1, "one move, not two")
        _ = game.undo()
        XCTAssertEqual(game.pencil, pencilBefore, "undo restores the pre-placement marks")
        XCTAssertEqual(game.entry(at: hole), 0)
    }

    func testPlaceWithoutAutoNotesIsByteIdenticalToToday() {
        var control = NineGame(puzzle: puzzle)
        var subject = NineGame(puzzle: puzzle)
        let digit = puzzle.solution[hole]
        XCTAssertTrue(control.place(digit, at: hole))
        XCTAssertTrue(subject.place(digit, at: hole, autoNotes: false))
        XCTAssertEqual(control, subject, "the default must not move a single existing call site")
    }

    func testEraseWithAutoNotesRederivesTheWidenedCandidates() {
        let digit = puzzle.solution[hole]
        XCTAssertTrue(game.applyAutoNotes())
        // Pick a peer that genuinely *had* the mark: an arbitrary empty peer
        // may never have carried `digit` at all, because one of its own peers
        // already holds it — in which case this test would prove nothing.
        let peer = Sudoku.peers[hole].first {
            game.entry(at: $0) == 0 && game.pencilDigits(at: $0).contains(digit)
        }
        guard let peer else { return XCTFail("no peer of \(hole!) carries a \(digit) note") }
        XCTAssertTrue(game.place(digit, at: hole, autoNotes: true))
        XCTAssertFalse(game.pencilDigits(at: peer).contains(digit), "placing pruned it")
        XCTAssertTrue(game.erase(at: hole, autoNotes: true))
        XCTAssertTrue(
            game.pencilDigits(at: peer).contains(digit),
            "erasing widens the candidate set, and re-deriving it is the toggle's whole job"
        )
    }

    func testTurningAutoNotesOffClearsNothing() {
        XCTAssertTrue(game.applyAutoNotes())
        let marks = game.pencil
        let digit = puzzle.solution[hole]
        // "Off" is simply the absence of the flag at the call site — there is no
        // engine call for it, which is exactly why nothing can be cleared.
        XCTAssertTrue(game.place(digit, at: hole, autoNotes: false))
        for cell in 0..<81 where cell != hole && !Sudoku.peers[hole].contains(cell) {
            XCTAssertEqual(game.pencil[cell], marks[cell], "untouched cells keep their notes")
        }
    }

    /// The downgrade property this whole design exists for: an older build's
    /// `undo()` restores every snapshot regardless of kind, so it handles both
    /// a bulk fill and an auto-notes placement correctly without any change.
    func testBulkMovesUndoThroughThePlainKindPath() {
        XCTAssertTrue(game.applyAutoNotes())
        let filled = game.pencil
        let digit = puzzle.solution[hole]
        XCTAssertTrue(game.place(digit, at: hole, autoNotes: true))
        let move = game.undoStack.last!
        XCTAssertEqual(move.kind, .place, "still one of the three shipped raw values")
        XCTAssertGreaterThan(move.previousPencil.count, 1, "and it carries the whole recompute")
        _ = game.undo()
        XCTAssertEqual(game.pencil, filled)
    }
}
