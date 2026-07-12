import XCTest
@testable import DarkroomEngine

final class CoachRayTests: XCTestCase {

    func testFreshBoardYieldsAProvableHint() throws {
        let session = PuzzleSession(puzzle: LineSolverTests.heartPuzzle())
        let hint = try XCTUnwrap(CoachRay.hint(for: session))
        XCTAssertGreaterThan(hint.deducibleCells, 0)

        // The hint must be *provable*: running the line solver on exactly
        // that line yields new cells.
        let n = session.size
        let states = session.knowledge
        let (clues, line): ([Int], [CellState])
        switch hint.target {
        case .row(let y):
            (clues, line) = (session.puzzle.rowClues[y], (0..<n).map { states[y * n + $0] })
        case .column(let x):
            (clues, line) = (session.puzzle.colClues[x], (0..<n).map { states[$0 * n + x] })
        }
        let deduced = try XCTUnwrap(LineSolver.deduce(clues: clues, line: line))
        let gain = zip(deduced, line).lazy.filter { $0 != $1 }.count
        XCTAssertEqual(gain, hint.deducibleCells)
    }

    func testHintPicksTheMostInformativeLine() throws {
        // Fresh heart: rows [5] (rows 1 and 2) resolve 5 cells at once —
        // no line can beat that.
        let session = PuzzleSession(puzzle: LineSolverTests.heartPuzzle())
        let hint = try XCTUnwrap(CoachRay.hint(for: session))
        XCTAssertEqual(hint.deducibleCells, 5)
        XCTAssertEqual(hint.target, CoachHint.Target.row(1))
    }

    func testUnsolvedConsistentBoardAlwaysHasAHint() {
        // Walk the whole heart via coach hints only: apply each hinted
        // line's deduction as moves until solved. If the ray ever goes
        // silent early, the guarantee is broken.
        var session = PuzzleSession(puzzle: LineSolverTests.heartPuzzle())
        let n = session.size
        var safety = 200
        while !session.isSolved && safety > 0 {
            safety -= 1
            guard let hint = CoachRay.hint(for: session) else {
                return XCTFail("coach ray went silent on an unsolved board")
            }
            let states = session.knowledge
            switch hint.target {
            case .row(let y):
                let line = (0..<n).map { states[y * n + $0] }
                let deduced = LineSolver.deduce(clues: session.puzzle.rowClues[y], line: line)!
                for x in 0..<n where deduced[x] != line[x] {
                    if deduced[x] == .filled { _ = session.toggleFill(x: x, y: y) }
                    else { _ = session.toggleX(x: x, y: y) }
                }
            case .column(let x):
                let line = (0..<n).map { states[$0 * n + x] }
                let deduced = LineSolver.deduce(clues: session.puzzle.colClues[x], line: line)!
                for y in 0..<n where deduced[y] != line[y] {
                    if deduced[y] == .filled { _ = session.toggleFill(x: x, y: y) }
                    else { _ = session.toggleX(x: x, y: y) }
                }
            }
        }
        XCTAssertTrue(session.isSolved, "hint-following must solve the board")
        XCTAssertEqual(session.mistakes, 0, "provable hints never cause mistakes")
        XCTAssertNil(CoachRay.hint(for: session), "solved board has no hint")
    }

    // MARK: - Rate limiting (90s bookkeeping, PRD §4.4)

    func testLimiterCooldownWindow() {
        var limiter = CoachRayLimiter()
        XCTAssertEqual(limiter.cooldown, 90)
        let t0 = Date(timeIntervalSinceReferenceDate: 10_000)

        XCTAssertTrue(limiter.isReady(at: t0), "first ray is free")
        XCTAssertEqual(limiter.readiness(at: t0), 1)
        XCTAssertTrue(limiter.fire(at: t0))

        XCTAssertFalse(limiter.isReady(at: t0.addingTimeInterval(45)))
        XCTAssertEqual(limiter.readiness(at: t0.addingTimeInterval(45)), 0.5, accuracy: 0.001)
        XCTAssertFalse(limiter.fire(at: t0.addingTimeInterval(89)))
        XCTAssertEqual(limiter.lastFired, t0, "failed fire must not reset the clock")

        XCTAssertTrue(limiter.isReady(at: t0.addingTimeInterval(90)))
        XCTAssertTrue(limiter.fire(at: t0.addingTimeInterval(90)))
        XCTAssertEqual(limiter.lastFired, t0.addingTimeInterval(90))
    }
}
