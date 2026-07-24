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

extension LibrarySyncTests {

    private func entry(
        id: UUID = UUID(), kind: GameKind = .free(.gentle), game: NineGame,
        status: BoardStatus = .inProgress, created: TimeInterval = 0,
        updated: TimeInterval, solved: TimeInterval? = nil
    ) -> LibraryEntry {
        LibraryEntry(
            id: id, kind: kind, game: game, status: status,
            createdAt: t(created), updatedAt: t(updated),
            solvedAt: solved.map(t)
        )
    }

    private func sequentialIDs() -> () -> UUID {
        var n = 0
        return { n += 1; return UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")! }
    }

    @Test func reconcileLastWriterWinsWhenBoardsAgree() {
        let id = UUID()
        // Same board content, different metadata timestamps → newer wins.
        let g = progressed(count: 4)
        let a = entry(id: id, game: g, updated: 10)
        let b = entry(id: id, game: g, updated: 20)
        let r = LibrarySync.reconcile(a, b, makeID: sequentialIDs())
        #expect(r.winner.updatedAt == t(20))
        #expect(r.archivedLoser == nil)
    }

    @Test func reconcileSolvedBeatsInProgressRegardlessOfTime() {
        let id = UUID()
        let inProg = entry(id: id, game: progressed(count: 30), status: .inProgress, updated: 100)
        let done = entry(id: id, game: solved(), status: .solved, updated: 5, solved: 5)
        let r = LibrarySync.reconcile(inProg, done, makeID: sequentialIDs())
        #expect(r.winner.status == .solved)          // solved wins though older
        #expect(r.archivedLoser == nil)
    }

    @Test func reconcileContinuationTakesTheSuperset() {
        let id = UUID()
        let short = entry(id: id, game: progressed(count: 5), updated: 10)
        let long = entry(id: id, game: progressed(count: 12), updated: 8) // fewer minutes but more moves
        let r = LibrarySync.reconcile(short, long, makeID: sequentialIDs())
        #expect(r.winner.game.fillFraction > short.game.fillFraction) // the longer board
        #expect(r.archivedLoser == nil)               // pure progress, nothing to archive
    }

    @Test func reconcileDivergentKeepsHigherFillArchivesLoser() throws {
        let id = UUID()
        // Two boards from DIFFERENT seeds progressed to different fills — the
        // user-entry sets conflict, so neither is a superset.
        let lower = entry(id: id, game: progressed(seed: 1, count: 6), updated: 30)
        let higher = entry(id: id, game: progressed(seed: 2, count: 15), updated: 10)
        let r = LibrarySync.reconcile(lower, higher, makeID: sequentialIDs())
        #expect(r.winner.game.fillFraction == higher.game.fillFraction)
        let loser = try #require(r.archivedLoser)
        #expect(loser.status == .archived)
        #expect(loser.id != id)                        // retained under a new id
        #expect(loser.game.entries == lower.game.entries) // progress preserved
    }
}

extension LibrarySyncTests {

    @Test func applyInsertsUnknownRemoteEntry() {
        var lib = BoardLibrary()
        let remote = SyncedEntry(entry(game: progressed(count: 3), updated: 10))
        _ = LibrarySync.apply(remote: remote, into: &lib, now: t(10), makeID: sequentialIDs())
        #expect(lib.entry(id: remote.id)?.game.entries == remote.game.entries)
    }

    @Test func applyDailyFromTwoDevicesConvergesToOneEntry() {
        var lib = BoardLibrary()
        let day = 19_500
        // Device A already has its own daily(day) entry (its own uuid).
        let localID = lib.adoptDaily(game: progressed(seed: 3, count: 4), day: day, now: t(5))
        // Device B's daily(day) arrives from the cloud under a DIFFERENT uuid,
        // further along.
        let remote = SyncedEntry(entry(
            id: UUID(), kind: .daily(day: day),
            game: progressed(seed: 3, count: 11), updated: 20
        ))
        let fx = LibrarySync.apply(remote: remote, into: &lib, now: t(20), makeID: sequentialIDs())
        // Exactly one daily entry for the day survives (the invariant).
        let dailies = lib.entries.filter { if case .daily(let d) = $0.kind { return d == day }; return false }
        #expect(dailies.count == 1)
        // It carries the further-along board.
        #expect(dailies.first?.game.fillFraction == remote.game.fillFraction)
        // The non-canonical (larger uuid) of the two ids is scheduled for a
        // cloud delete — exactly one.
        #expect(fx.cloudDeletes.count == 1)
        let nonCanonical = UUID(uuidString: max(localID.uuidString, remote.id.uuidString))!
        #expect(fx.cloudDeletes.first == nonCanonical)
        // The survivor is homed on the canonical (smaller) uuid — convergent.
        let canonical = UUID(uuidString: min(localID.uuidString, remote.id.uuidString))!
        #expect(dailies.first?.id == canonical)
    }

    @Test func applySolvedDailyMarksSolvedThroughAdoptDaily() {
        var lib = BoardLibrary()
        let day = 19_600
        let localID = lib.adoptDaily(game: progressed(count: 2), day: day, now: t(1))
        let remote = SyncedEntry(entry(
            id: localID, kind: .daily(day: day), game: solved(),
            status: .solved, updated: 30, solved: 30
        ))
        _ = LibrarySync.apply(remote: remote, into: &lib, now: t(30), makeID: sequentialIDs())
        #expect(lib.dailyEntry(day: day)?.status == .solved)
        #expect(lib.dailyEntry(day: day)?.solvedAt == t(30))
    }

    @Test func applyIsIdempotentOnRepeat() {
        var lib = BoardLibrary()
        let ids = sequentialIDs()
        let remote = SyncedEntry(entry(kind: .free(.steady), game: progressed(count: 6), updated: 10))
        _ = LibrarySync.apply(remote: remote, into: &lib, now: t(10), makeID: ids)
        let snapshot = lib
        _ = LibrarySync.apply(remote: remote, into: &lib, now: t(11), makeID: ids)
        #expect(lib == snapshot)   // second apply of the same record changes nothing
    }

    @Test func applyDeletionRemovesEntry() {
        var lib = BoardLibrary()
        let id = lib.create(kind: .free(.gentle), game: game(), now: t(0))
        LibrarySync.applyDeletion(id: id, into: &lib)
        #expect(lib.entry(id: id) == nil)
    }
}
