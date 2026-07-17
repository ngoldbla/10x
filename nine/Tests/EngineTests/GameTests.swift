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
        XCTAssertEqual(streak.displayedStreak(today: 103), 0, "older chains lapse")
    }
}
