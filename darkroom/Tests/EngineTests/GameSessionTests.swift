import XCTest
import CouchCore
@testable import DarkroomEngine

final class GameSessionTests: XCTestCase {

    private func heartSession() -> PuzzleSession {
        PuzzleSession(puzzle: LineSolverTests.heartPuzzle())
    }

    // MARK: - Contradiction rejection (PRD §4.2)

    func testWrongFillIsRefusedWithViolationAndCountsMistake() {
        var s = heartSession()
        // (0,0) is empty in the heart.
        let result = s.toggleFill(x: 0, y: 0)
        guard case .rejected(let violation) = result else {
            return XCTFail("wrong fill must be rejected, got \(result)")
        }
        // The cell was NOT placed — mistake counting, not mistake placing.
        XCTAssertEqual(s.mark(x: 0, y: 0), CellMark.none)
        XCTAssertEqual(s.mistakes, 1)
        // The violated clue is one of the two lines through the cell.
        XCTAssertTrue(
            violation.line == .row(0) || violation.line == .column(0),
            "violation must point at a clue through the refused cell"
        )
    }

    func testWrongXMarkIsAlsoRefused() {
        var s = heartSession()
        // (2,4) is the heart's tip — filled in the solution.
        let result = s.toggleX(x: 2, y: 4)
        guard case .rejected = result else {
            return XCTFail("contradicting ✕ must be rejected, got \(result)")
        }
        XCTAssertEqual(s.mark(x: 2, y: 4), CellMark.none)
        XCTAssertEqual(s.mistakes, 1)
    }

    func testViolationIsProvableWhenLineIsPinnedDown() {
        var s = heartSession()
        // Complete row 1 ([5]) legitimately.
        for x in 0..<5 {
            guard case .placed = s.toggleFill(x: x, y: 1) else {
                return XCTFail("filling row 1 must succeed")
            }
        }
        XCTAssertTrue(s.isRowComplete(1))
        // Now a ✕ inside the completed row's block is provably impossible
        // for that row clue.
        let result = s.toggleX(x: 2, y: 1)
        XCTAssertEqual(result, MoveResult.ignored) // filled cells ignore ✕
    }

    // MARK: - Fills, marks, toggling

    func testFillClearAndMarkLifecycle() {
        var s = heartSession()
        XCTAssertEqual(s.toggleFill(x: 1, y: 0), MoveResult.placed(solvedPuzzle: false))
        XCTAssertEqual(s.mark(x: 1, y: 0), CellMark.filled)
        XCTAssertEqual(s.toggleFill(x: 1, y: 0), MoveResult.cleared)
        XCTAssertEqual(s.mark(x: 1, y: 0), CellMark.none)

        XCTAssertEqual(s.toggleX(x: 0, y: 0), MoveResult.marked)
        XCTAssertEqual(s.mark(x: 0, y: 0), CellMark.xMark)
        XCTAssertEqual(s.toggleX(x: 0, y: 0), MoveResult.unmarked)
        XCTAssertEqual(s.mistakes, 0)
    }

    func testDragFillOnlyPaintsUntouchedCells() {
        var s = heartSession()
        XCTAssertEqual(s.dragFill(x: 1, y: 0), MoveResult.placed(solvedPuzzle: false))
        // Dragging back over the same cell must not clear it.
        XCTAssertEqual(s.dragFill(x: 1, y: 0), MoveResult.ignored)
        XCTAssertEqual(s.mark(x: 1, y: 0), CellMark.filled)
        // Dragging across a wrong cell is refused like a click.
        guard case .rejected = s.dragFill(x: 0, y: 0) else {
            return XCTFail("drag across a wrong cell must be rejected")
        }
    }

    // MARK: - Completion

    func testSolvingReportsSolvedOnFinalFillAndLocksBoard() {
        var s = heartSession()
        let n = s.size
        var last: MoveResult = .ignored
        for y in 0..<n {
            for x in 0..<n where s.puzzle.isFilled(x: x, y: y) {
                last = s.toggleFill(x: x, y: y)
            }
        }
        XCTAssertEqual(last, MoveResult.placed(solvedPuzzle: true))
        XCTAssertTrue(s.isSolved)
        XCTAssertEqual(s.progress, 1.0, accuracy: 0.0001)
        // Input locks after the develop begins.
        XCTAssertEqual(s.toggleFill(x: 0, y: 0), MoveResult.ignored)
        XCTAssertEqual(s.toggleX(x: 0, y: 0), MoveResult.ignored)
    }

    func testLineCompletionForClueDimming() {
        var s = heartSession()
        XCTAssertFalse(s.isRowComplete(1))
        for x in 0..<5 { _ = s.toggleFill(x: x, y: 1) }
        XCTAssertTrue(s.isRowComplete(1))
        // Column 0 needs rows 1 and 2; only row 1 is placed so far.
        XCTAssertFalse(s.isColumnComplete(0))
        _ = s.toggleFill(x: 0, y: 2)
        XCTAssertTrue(s.isColumnComplete(0))
    }

    // MARK: - Snapshot / restore (auto-save model)

    func testSnapshotRoundTripRestoresBoard() throws {
        var s = heartSession()
        _ = s.toggleFill(x: 1, y: 0)
        _ = s.toggleX(x: 0, y: 0)
        _ = s.toggleFill(x: 0, y: 0) // rejected → mistake
        s.coach.fire(at: Date(timeIntervalSinceReferenceDate: 1000))

        let data = try CouchJSON.encode(s.snapshot)
        let snapshot = try CouchJSON.decode(SessionSnapshot.self, from: data)
        let restored = PuzzleSession(puzzle: s.puzzle, restoring: snapshot)

        XCTAssertEqual(restored.marks, s.marks)
        XCTAssertEqual(restored.mistakes, 1)
        XCTAssertEqual(restored.coach.lastFired, s.coach.lastFired)
    }

    func testSnapshotFromDifferentPuzzleIsIgnored() {
        var other = heartSession()
        _ = other.toggleFill(x: 1, y: 0)
        var snapshot = other.snapshot
        snapshot = SessionSnapshot(
            puzzleID: "someone-else|10|1",
            marks: snapshot.marks,
            mistakes: snapshot.mistakes,
            coachLastFired: nil
        )
        let fresh = PuzzleSession(puzzle: LineSolverTests.heartPuzzle(), restoring: snapshot)
        XCTAssertEqual(fresh.filledCount, 0)
        XCTAssertEqual(fresh.mistakes, 0)
    }
}
