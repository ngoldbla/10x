import XCTest
import CouchCore
@testable import DarkroomEngine

final class LineSolverTests: XCTestCase {

    private func blank(_ n: Int) -> [CellState] {
        [CellState](repeating: .unknown, count: n)
    }

    // MARK: - Single-line deduction on hand-known lines

    func testFullLineClueFillsEverything() {
        let out = LineSolver.deduce(clues: [10], line: blank(10))
        XCTAssertEqual(out, [CellState](repeating: .filled, count: 10))
    }

    func testOverlapDeduction8In10() {
        // [8] in 10: placements start at 0, 1, or 2 → cells 2...7 forced.
        let out = LineSolver.deduce(clues: [8], line: blank(10))!
        for i in 0..<10 {
            if (2...7).contains(i) {
                XCTAssertEqual(out[i], .filled, "cell \(i) must be forced")
            } else {
                XCTAssertEqual(out[i], .unknown, "cell \(i) must stay open")
            }
        }
    }

    func testTwoBlockOverlap() {
        // [4,4] in 10 (slack 1): forced 1-3 and 6-8.
        let out = LineSolver.deduce(clues: [4, 4], line: blank(10))!
        let forced = Set([1, 2, 3, 6, 7, 8])
        for i in 0..<10 {
            XCTAssertEqual(out[i], forced.contains(i) ? .filled : .unknown, "cell \(i)")
        }
    }

    func testNoDeductionWhenSlackTooLarge() {
        // [3,3] in 10 (slack 3): nothing forced.
        let out = LineSolver.deduce(clues: [3, 3], line: blank(10))!
        XCTAssertEqual(out, blank(10))
    }

    func testAnchoredBlockCompletesLine() {
        // [3] in 5 with cell 0 known filled → block is 0-2, rest empty.
        var line = blank(5)
        line[0] = .filled
        let out = LineSolver.deduce(clues: [3], line: line)!
        XCTAssertEqual(out, [.filled, .filled, .filled, .empty, .empty])
    }

    func testBlankClueForcesAllEmpty() {
        let out = LineSolver.deduce(clues: [], line: blank(5))
        XCTAssertEqual(out, [CellState](repeating: .empty, count: 5))
        // [0] is normalized to blank.
        let outZero = LineSolver.deduce(clues: [0], line: blank(5))
        XCTAssertEqual(outZero, [CellState](repeating: .empty, count: 5))
    }

    func testContradictionReturnsNil() {
        // Blank clue but a filled cell.
        var line = blank(5)
        line[2] = .filled
        XCTAssertNil(LineSolver.deduce(clues: [], line: line))
        // [4] in 5 with the middle cell known empty: no placement fits.
        var line2 = blank(5)
        line2[2] = .empty
        XCTAssertNil(LineSolver.deduce(clues: [4], line: line2))
    }

    func testKnownCellsAreRespected() {
        // [2] in 5 with cell 4 filled → block is 3-4.
        var line = blank(5)
        line[4] = .filled
        let out = LineSolver.deduce(clues: [2], line: line)!
        XCTAssertEqual(out, [.empty, .empty, .empty, .filled, .filled])
    }

    // MARK: - Whole-grid solving on a hand-known puzzle

    /// 5×5 heart:
    /// ```
    /// . X . X .
    /// X X X X X
    /// X X X X X
    /// . X X X .
    /// . . X . .
    /// ```
    static let heart: [Bool] = [
        false, true, false, true, false,
        true, true, true, true, true,
        true, true, true, true, true,
        false, true, true, true, false,
        false, false, true, false, false,
    ]

    static func heartPuzzle() -> Puzzle {
        Puzzle(
            photoID: "test-heart",
            size: 5,
            dateSeed: 20260710,
            solution: heart,
            colors: (0..<25).map { _ in RGB(200, 40, 80) },
            difficulty: 1
        )
    }

    func testHeartCluesAreDerivedCorrectly() {
        let p = Self.heartPuzzle()
        XCTAssertEqual(p.rowClues, [[1, 1], [5], [5], [3], [1]])
        XCTAssertEqual(p.colClues, [[2], [4], [4], [4], [2]])
    }

    func testGridSolverSolvesHeartToExactSolution() {
        let p = Self.heartPuzzle()
        let report = GridSolver.solve(size: 5, rowClues: p.rowClues, colClues: p.colClues)
        XCTAssertTrue(report.solved)
        XCTAssertFalse(report.contradiction)
        XCTAssertGreaterThanOrEqual(report.passes, 1)
        for i in 0..<25 {
            XCTAssertEqual(report.cells[i] == .filled, Self.heart[i], "cell \(i)")
        }
        XCTAssertTrue(GridSolver.verify(p))
    }

    func testGridSolverReportsContradiction() {
        // Row clues demand a fill in a column whose clue forbids it.
        let report = GridSolver.solve(
            size: 2,
            rowClues: [[2], [2]],
            colClues: [[], []]
        )
        XCTAssertTrue(report.contradiction)
        XCTAssertFalse(report.solved)
    }

    func testUnsolvableByLineLogicIsNotSolved() {
        // Classic 2×2 checkerboard ambiguity: two valid solutions, no line
        // deduction possible.
        let report = GridSolver.solve(
            size: 2,
            rowClues: [[1], [1]],
            colClues: [[1], [1]]
        )
        XCTAssertFalse(report.solved)
        XCTAssertFalse(report.contradiction)
    }
}
