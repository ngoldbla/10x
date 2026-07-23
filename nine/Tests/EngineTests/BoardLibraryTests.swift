// BoardLibraryTests — the board tracker's data model (playtest fix D). Pure,
// no UI, no clocks: every timestamp is injected, so the ordering, one-daily-
// per-day merge, prune caps, status transitions and migration are all
// deterministic.
import Testing
import Foundation
@testable import NineEngine

@Suite("BoardLibrary")
struct BoardLibraryTests {

    // MARK: helpers

    private func t(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
    }

    private func game(seed: UInt64 = 1, difficulty: Difficulty = .gentle) -> NineGame {
        NineGame(puzzle: PuzzleGenerator.generate(seed: seed, difficulty: difficulty))
    }

    private func solved(seed: UInt64 = 1) -> NineGame {
        var g = game(seed: seed)
        for cell in 0..<81 where !g.isGiven(cell) {
            g.place(g.puzzle.solution.cells[cell], at: cell)
        }
        return g
    }

    // MARK: ordering

    @Test func upsertKeepsNewestUpdatedFirst() {
        var lib = BoardLibrary()
        let a = lib.create(kind: .free(.gentle), game: game(), now: t(0))
        let b = lib.create(kind: .free(.steady), game: game(), now: t(10))
        #expect(lib.entries.first?.id == b)
        // Touch `a` later → it moves to the front.
        var ea = lib.entry(id: a)!
        ea.updatedAt = t(20)
        lib.upsert(ea)
        #expect(lib.entries.first?.id == a)
    }

    // MARK: the clobber regression

    @Test func adoptDailyIsOnePerDayAndSpareFreePartialsSurvive() {
        var lib = BoardLibrary()
        // A free-play partial the widget-ingest used to clobber on cold launch.
        let free = lib.create(kind: .free(.sharp), game: game(seed: 2), now: t(0))
        // First daily adoption creates the day entry.
        let day = 19_000
        let first = lib.adoptDaily(game: game(seed: 3), day: day, now: t(5))
        // A second adoption on the SAME day reuses the same entry (no duplicate).
        var advanced = game(seed: 3)
        let cell = firstEmpty(advanced)
        advanced.place(advanced.puzzle.solution.cells[cell], at: cell)
        let second = lib.adoptDaily(game: advanced, day: day, now: t(9))
        #expect(first == second)
        #expect(lib.partials.filter { if case .daily = $0.kind { return true }; return false }.count == 1)
        // The free partial is structurally untouched — the real fix.
        #expect(lib.entry(id: free) != nil)
        #expect(lib.mostRecentFreePartial?.id == free)
        // A different day makes a second daily entry.
        _ = lib.adoptDaily(game: game(seed: 4), day: day + 1, now: t(12))
        #expect(lib.partials.filter { if case .daily = $0.kind { return true }; return false }.count == 2)
    }

    private func firstEmpty(_ g: NineGame) -> Int {
        (0..<81).first { !g.isGiven($0) && g.entry(at: $0) == 0 } ?? 0
    }

    @Test func inProgressDailyIgnoresSolvedAndArchived() {
        var lib = BoardLibrary()
        let day = 19_100
        let id = lib.adoptDaily(game: game(), day: day, now: t(0))
        #expect(lib.inProgressDaily(day: day)?.id == id)
        lib.markSolved(id: id, at: t(1))
        #expect(lib.inProgressDaily(day: day) == nil)
        #expect(lib.dailyEntry(day: day)?.status == .solved)
        // Replay-after-solve reuses the same day slot, back to in progress.
        let replay = lib.adoptDaily(game: game(), day: day, now: t(2))
        #expect(replay == id)
        #expect(lib.inProgressDaily(day: day)?.id == id)
    }

    // MARK: status transitions

    @Test func markSolvedRetainsEntryAsPlayed() {
        var lib = BoardLibrary()
        let id = lib.create(kind: .free(.steady), game: solved(), now: t(0))
        lib.markSolved(id: id, at: t(5))
        #expect(lib.partials.isEmpty)
        #expect(lib.played.map(\.id) == [id])
        #expect(lib.entry(id: id)?.solvedAt == t(5))
    }

    @Test func archiveMovesPartialToPlayedDeleteRemoves() {
        var lib = BoardLibrary()
        let id = lib.create(kind: .free(.gentle), game: game(), now: t(0))
        lib.archive(id: id)
        #expect(lib.partials.isEmpty)
        #expect(lib.played.first?.status == .archived)
        lib.delete(id: id)
        #expect(lib.entry(id: id) == nil)
    }

    // MARK: prune caps + order

    @Test func prunePlayedCapDropsArchivedBeforeSolvedOldestFirst() {
        var lib = BoardLibrary()
        // 20 solved (cap) + then push archived/solved to force eviction.
        var solvedIDs: [UUID] = []
        for i in 0..<BoardLibrary.playedCap {
            let id = lib.create(kind: .free(.gentle), game: solved(), now: t(Double(i)))
            lib.markSolved(id: id, at: t(Double(i)))
            solvedIDs.append(id)
        }
        #expect(lib.played.count == BoardLibrary.playedCap)
        // One archived, older than every solved → it's evicted first.
        let arch = lib.create(kind: .free(.gentle), game: game(), now: t(-100))
        lib.archive(id: arch)
        #expect(lib.played.count == BoardLibrary.playedCap) // still capped
        #expect(lib.entry(id: arch) == nil)                 // archived-oldest went first
        #expect(lib.entry(id: solvedIDs.last!) != nil)      // newest solved survives
    }

    @Test func pruneTotalCapKeepsCurrentInProgressLast() {
        var lib = BoardLibrary()
        var ids: [UUID] = []
        for i in 0..<(BoardLibrary.totalCap + 5) {
            ids.append(lib.create(kind: .free(.gentle), game: game(), now: t(Double(i))))
        }
        #expect(lib.entries.count == BoardLibrary.totalCap)
        // The newest in-progress board (the current one) is never evicted.
        #expect(lib.entry(id: ids.last!) != nil)
        // The oldest in-progress boards were dropped.
        #expect(lib.entry(id: ids.first!) == nil)
    }

    // MARK: migration

    @Test func migratingWrapsLegacySaveAsInProgress() {
        let lib = BoardLibrary.migrating(game: game(seed: 7), kind: .daily(day: 42), now: t(0))
        #expect(lib.entries.count == 1)
        let e = lib.entries[0]
        #expect(e.status == .inProgress)
        #expect(e.kind == .daily(day: 42))
        #expect(e.solvedAt == nil)
    }

    @Test func gameKindCodableRoundTripsByteCompatibly() throws {
        // The library persists locally, but a downgrade may still read the old
        // GameKind out of a `nine.save` blob — the shape must not drift.
        let kinds: [GameKind] = [.daily(day: 5), .free(.steady), .free(.sharp)]
        let enc = JSONEncoder(), dec = JSONDecoder()
        for k in kinds {
            let data = try enc.encode(k)
            #expect(try dec.decode(GameKind.self, from: data) == k)
        }
        // Fixed-shape decode: the synthesized associated-value form.
        let daily = try dec.decode(GameKind.self, from: Data(#"{"daily":{"day":9}}"#.utf8))
        #expect(daily == .daily(day: 9))
    }
}
