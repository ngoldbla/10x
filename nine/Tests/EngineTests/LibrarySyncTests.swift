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

extension LibrarySyncTests {

    @Test func syncedEntryRoundTripsDroppingOnlyLocalHistory() {
        let entry = LibraryEntry(
            kind: .free(.sharp), game: progressed(count: 7),
            status: .inProgress, createdAt: t(0), updatedAt: t(10)
        )
        let back = SyncedEntry(entry).hydrated()
        #expect(back.id == entry.id)
        #expect(back.kind == entry.kind)
        #expect(back.status == entry.status)
        #expect(back.createdAt == entry.createdAt)
        #expect(back.updatedAt == entry.updatedAt)
        #expect(back.solvedAt == entry.solvedAt)
        // Board preserved; only the device-local history is gone.
        #expect(back.game.entries == entry.game.entries)
        #expect(back.game.pencil == entry.game.pencil)
        #expect(back.game.undoStack.isEmpty)
        #expect(back.game.moveLog.isEmpty)
    }

    @Test func syncedEntryCodableRoundTrips() throws {
        let entry = LibraryEntry(
            kind: .daily(day: 19_000), game: solved(),
            status: .solved, createdAt: t(0), updatedAt: t(20), solvedAt: t(20)
        )
        let data = try JSONEncoder().encode(SyncedEntry(entry))
        let decoded = try JSONDecoder().decode(SyncedEntry.self, from: data)
        #expect(decoded == SyncedEntry(entry))
    }

    @Test func syncedEntryToleratesMissingSolvedAt() throws {
        // A record written before solvedAt existed must decode, not throw.
        let entry = LibraryEntry(
            kind: .free(.gentle), game: game(), status: .inProgress,
            createdAt: t(0), updatedAt: t(1)
        )
        var obj = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(SyncedEntry(entry))
        ) as! [String: Any]
        obj.removeValue(forKey: "solvedAt")
        let data = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(SyncedEntry.self, from: data)
        #expect(decoded.solvedAt == nil)
        #expect(decoded.id == entry.id)
    }
}
