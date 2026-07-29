import XCTest
import CouchCore
@testable import NineEngine

/// PRD-26 §5 — the replay record, its packed form, and the vault.
final class SolveReplayTests: XCTestCase {

    // Generation is the slow part of this file; one board serves every test.
    private static let board = PuzzleGenerator.generate(seed: 26_260_726, difficulty: .steady)

    // MARK: - `LoggedMove.at` costs nothing when nobody passes it

    /// The claim PRD-26 §3.1 makes about `Optional` and the synthesized
    /// encoder, run rather than asserted. If this fails, every autosaved board
    /// on TestFlight is about to be rewritten with a key an older build will
    /// carry but never fill.
    func testUntimedMoveEncodesWithoutTheTimingKey() throws {
        let move = LoggedMove(kind: .place, cell: 40, digit: 7)
        let json = String(decoding: try CouchJSON.encode(move), as: UTF8.self)
        XCTAssertFalse(json.contains("\"at\""), "an untimed move must not spell the key: \(json)")
        XCTAssertEqual(json, #"{"cell":40,"digit":7,"kind":"place"}"#)
    }

    func testTimedMoveRoundTripsThroughJSON() throws {
        let move = LoggedMove(kind: .erase, cell: 3, digit: 9, at: 12.5)
        let back = try CouchJSON.decode(LoggedMove.self, from: CouchJSON.encode(move))
        XCTAssertEqual(back, move)
    }

    /// An older build's log — no `at` anywhere — must decode, not throw.
    func testLogWithoutTimingDecodes() throws {
        let legacy = Data(#"[{"cell":1,"digit":2,"kind":"pencil"}]"#.utf8)
        let moves = try CouchJSON.decode([LoggedMove].self, from: legacy)
        XCTAssertEqual(moves, [LoggedMove(kind: .pencil, cell: 1, digit: 2)])
        XCTAssertNil(moves[0].at)
    }

    /// The engine reads no clock: a placement with no `elapsed:` logs no time,
    /// and one with `elapsed:` logs exactly what the caller said.
    func testTheEngineOnlyKnowsTheTimeItIsTold() {
        var game = NineGame(puzzle: Self.board)
        let hole = (0..<81).first { !game.isGiven($0) }!
        let digit = Self.board.solution.cells[hole]

        XCTAssertTrue(game.place(digit, at: hole))
        XCTAssertNil(game.moveLog.last?.at)

        game.erase(at: hole, elapsed: 41.25)
        XCTAssertEqual(game.moveLog.last?.at, 41.25)
    }

    // MARK: - The packed format

    func testPackedLogRoundTripsTimedAndUntimed() throws {
        let puzzle = Self.board.puzzle.cells
        let timed = (0..<120).map { index in
            LoggedMove(
                kind: [.place, .erase, .pencil, .undo][index % 4],
                cell: index % 81, digit: index % 9 + 1, at: Double(index) * 1.7
            )
        }
        let untimed = timed.map { LoggedMove(kind: $0.kind, cell: $0.cell, digit: $0.digit) }

        let timedBack = try XCTUnwrap(SolveReplay.unpack(SolveReplay.pack(puzzle: puzzle, moves: timed)))
        XCTAssertTrue(timedBack.timed)
        XCTAssertEqual(timedBack.puzzle, puzzle)
        XCTAssertEqual(timedBack.moves.map(\.kind), timed.map(\.kind))
        XCTAssertEqual(timedBack.moves.map(\.cell), timed.map(\.cell))
        XCTAssertEqual(timedBack.moves.map(\.digit), timed.map(\.digit))
        // Deciseconds, delta-encoded: 0.1 s of rounding per move, not cumulative.
        for (back, original) in zip(timedBack.moves, timed) {
            XCTAssertEqual(try XCTUnwrap(back.at), try XCTUnwrap(original.at), accuracy: 0.06)
        }

        let untimedBack = try XCTUnwrap(SolveReplay.unpack(SolveReplay.pack(puzzle: puzzle, moves: untimed)))
        XCTAssertFalse(untimedBack.timed)
        XCTAssertEqual(untimedBack.moves, untimed)
    }

    /// PRD-26 §3.2: timed is a property of the *log*. A half-timed log replays
    /// honestly at neither cadence, so the conservative reading wins.
    func testAPartiallyTimedLogPacksAsUntimed() throws {
        let moves = [
            LoggedMove(kind: .place, cell: 0, digit: 1, at: 1),
            LoggedMove(kind: .place, cell: 1, digit: 2)
        ]
        let back = try XCTUnwrap(SolveReplay.unpack(SolveReplay.pack(puzzle: Self.board.puzzle.cells, moves: moves)))
        XCTAssertFalse(back.timed)
        XCTAssertTrue(back.moves.allSatisfy { $0.at == nil })
    }

    func testTheSizeBudgetHolds() {
        let moves = (0..<300).map {
            LoggedMove(kind: .place, cell: $0 % 81, digit: $0 % 9 + 1, at: Double($0) * 2)
        }
        let packed = SolveReplay.pack(puzzle: Self.board.puzzle.cells, moves: moves)
        // PROGRAM-2.0 promises 1–2 KB per solve for a long one.
        XCTAssertLessThan(packed.count, 2048, "300 timed moves packed to \(packed.count) bytes")
    }

    /// Nothing here may throw, and a buffer that promises more than it carries
    /// must be refused rather than half-read: a partial replay is a drawing of
    /// a solve that did not happen.
    func testGarbageDecodesToNilAndNeverThrows() {
        let good = SolveReplay.pack(
            puzzle: Self.board.puzzle.cells,
            moves: [LoggedMove(kind: .place, cell: 5, digit: 5, at: 1)]
        )
        XCTAssertNotNil(SolveReplay.unpack(good))

        XCTAssertNil(SolveReplay.unpack(Data()))
        XCTAssertNil(SolveReplay.unpack(Data([0x00, 0x01, 0x02])))
        XCTAssertNil(SolveReplay.unpack(good.prefix(good.count - 1)), "truncated body")
        XCTAssertNil(SolveReplay.unpack(good.prefix(SolveReplay.headerSize)), "no grid")

        var wrongMagic = [UInt8](good)
        wrongMagic[0] = 0x00
        XCTAssertNil(SolveReplay.unpack(Data(wrongMagic)))

        var wrongVersion = [UInt8](good)
        wrongVersion[3] = 99
        XCTAssertNil(SolveReplay.unpack(Data(wrongVersion)))

        var liesAboutCount = [UInt8](good)
        liesAboutCount[5] = 0xFF
        liesAboutCount[6] = 0xFF
        XCTAssertNil(SolveReplay.unpack(Data(liesAboutCount)), "promised 65535 moves, carries one")

        var badDigit = [UInt8](good)
        badDigit[SolveReplay.headerSize + 4] = 99 // a grid cell out of 0...9
        XCTAssertNil(SolveReplay.unpack(Data(badDigit)))
    }

    // MARK: - Minting

    func testAnEmptyLogMintsNoReplay() {
        let game = NineGame(puzzle: Self.board)
        XCTAssertNil(SolveReplay(
            boardID: UUID(), game: game, band: "steady", isDaily: false,
            solvedAt: Date(timeIntervalSince1970: 0), seconds: 0
        ))
    }

    func testAMintedReplayCarriesTheBoardAndThePath() throws {
        var game = NineGame(puzzle: Self.board)
        let holes = (0..<81).filter { !game.isGiven($0) }.prefix(4)
        for (index, hole) in holes.enumerated() {
            game.place(Self.board.solution.cells[hole], at: hole, elapsed: Double(index) * 3)
        }
        let replay = try XCTUnwrap(SolveReplay(
            boardID: UUID(), game: game, band: "steady", isDaily: true,
            solvedAt: Date(timeIntervalSince1970: 1), seconds: 12
        ))
        XCTAssertTrue(replay.isTimed)
        XCTAssertEqual(replay.puzzle, Self.board.puzzle.cells)
        XCTAssertEqual(replay.moves.count, 4)
        XCTAssertEqual(replay.moves.map(\.cell), Array(holes))
    }

    // MARK: - The vault

    private func replay(_ id: UUID, solvedAt: TimeInterval = 0) -> SolveReplay {
        SolveReplay(
            boardID: id, solvedAt: Date(timeIntervalSince1970: solvedAt), band: "steady",
            isDaily: false, seconds: 60,
            packed: SolveReplay.pack(
                puzzle: Self.board.puzzle.cells,
                moves: [LoggedMove(kind: .place, cell: 0, digit: 1, at: 1)]
            )
        )
    }

    /// "Immutable" is enforced, not asked for: an older solve of the same board
    /// cannot overwrite a newer one, and re-storing the same record changes
    /// nothing.
    func testAStoredReplayIsNeverAmended() {
        let id = UUID()
        var vault = ReplayVault()
        vault.store(replay(id, solvedAt: 100))
        vault.store(replay(id, solvedAt: 50))
        XCTAssertEqual(vault.replay(for: id)?.solvedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(vault.count, 1)

        // A genuinely newer solve of the same board replaces the record whole —
        // a daily replayed after solving reuses its day slot.
        vault.store(replay(id, solvedAt: 200))
        XCTAssertEqual(vault.replay(for: id)?.solvedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(vault.count, 1)
    }

    func testTheVaultIsCappedOldestFirst() {
        var vault = ReplayVault()
        let ids = (0..<(ReplayVault.capacity + 10)).map { _ in UUID() }
        for id in ids { vault.store(replay(id)) }
        XCTAssertEqual(vault.count, ReplayVault.capacity)
        XCTAssertNil(vault.replay(for: ids[0]), "the oldest should have been dropped")
        XCTAssertNotNil(vault.replay(for: ids.last!))
    }

    /// PRD-26 §4 — a replay is about a board; when the board goes, so does it.
    func testPruningFollowsTheLibrary() {
        let kept = UUID(), gone = UUID()
        var vault = ReplayVault()
        vault.store(replay(kept))
        vault.store(replay(gone))
        vault.prune(to: [kept.uuidString])
        XCTAssertNotNil(vault.replay(for: kept))
        XCTAssertNil(vault.replay(for: gone))
        XCTAssertEqual(vault.count, 1)
    }

    /// An empty live set is a library that has not loaded yet, not a library
    /// with nothing in it — pruning against it would delete everything.
    func testPruningAgainstNothingIsRefused() {
        let id = UUID()
        var vault = ReplayVault()
        vault.store(replay(id))
        vault.prune(to: [])
        XCTAssertNotNil(vault.replay(for: id))
    }

    func testVaultRoundTrips() throws {
        let id = UUID()
        var vault = ReplayVault()
        vault.store(replay(id, solvedAt: 7))
        let back = try CouchJSON.decode(ReplayVault.self, from: CouchJSON.encode(vault))
        XCTAssertEqual(back, vault)
        XCTAssertEqual(back.replay(for: id)?.moves.count, 1)
    }

    /// `CouchStored` discards the whole blob when a decode throws, so one
    /// unreadable record must cost one record — the fallback path in
    /// `ReplayVault.init(from:)`, which the fast path never reaches.
    func testOneUnreadableRecordCostsOneRecord() throws {
        let good = UUID()
        var vault = ReplayVault()
        vault.store(replay(good))
        var json = try JSONSerialization.jsonObject(with: CouchJSON.encode(vault)) as! [String: Any]
        var replays = json["replays"] as! [String: Any]
        replays["not-a-board"] = ["boardID": "🙃", "band": 17]
        json["replays"] = replays
        json["order"] = (json["order"] as! [String]) + ["not-a-board"]

        let data = try JSONSerialization.data(withJSONObject: json)
        let back = try CouchJSON.decode(ReplayVault.self, from: data)
        XCTAssertEqual(back.count, 1, "the good record must survive its neighbour")
        XCTAssertNotNil(back.replay(for: good))
    }

    func testGarbageBlobDecodesEmptyRatherThanThrowing() throws {
        let back = try CouchJSON.decode(ReplayVault.self, from: Data(#"{"replays":42}"#.utf8))
        XCTAssertEqual(back.count, 0)
    }
}
