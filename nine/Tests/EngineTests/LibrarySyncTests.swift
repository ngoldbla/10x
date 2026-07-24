// LibrarySyncTests — the cloud merge core (PRD-8). Pure, no CloudKit, no UI,
// no clocks: every timestamp is injected, so the projection round-trip, the
// per-entry merge rules and the one-daily-per-day invariant are deterministic.
import Testing
import Foundation
@testable import NineEngine

@Suite("LibrarySync")
struct LibrarySyncTests {

    // MARK: helpers

    private func t(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
    }

    private func game(seed: UInt64 = 1, difficulty: Difficulty = .gentle) -> NineGame {
        NineGame(puzzle: PuzzleGenerator.generate(seed: seed, difficulty: difficulty))
    }

    /// Place `count` correct digits into the first empty non-given cells.
    private func progressed(seed: UInt64 = 1, count: Int) -> NineGame {
        var g = game(seed: seed)
        let holes = (0..<81).filter { !g.isGiven($0) }
        for cell in holes.prefix(count) { g.place(g.puzzle.solution.cells[cell], at: cell) }
        return g
    }

    private func solved(seed: UInt64 = 1) -> NineGame {
        var g = game(seed: seed)
        for cell in 0..<81 where !g.isGiven(cell) {
            g.place(g.puzzle.solution.cells[cell], at: cell)
        }
        return g
    }

    // MARK: projection

    @Test func clearLocalHistoryDropsUndoAndLogKeepsBoard() {
        var g = progressed(count: 5)
        #expect(!g.undoStack.isEmpty)
        #expect(!g.moveLog.isEmpty)
        let entries = g.entries, pencil = g.pencil
        g.clearLocalHistory()
        #expect(g.undoStack.isEmpty)
        #expect(g.moveLog.isEmpty)
        #expect(g.entries == entries)
        #expect(g.pencil == pencil)
    }
}
