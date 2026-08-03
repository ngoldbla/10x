// SharedDailyBoardTests — the playable widget's shared state (PRD-3 §4):
// full NineGame round-trip through the group file, the stale-day guard,
// revision monotonicity, and day-keyed selection.
import XCTest
import NineEngine
@testable import NineShared

final class SharedDailyBoardTests: XCTestCase {

    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nine-daily-board-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private static let entryID = UUID(uuidString: "0BADF00D-0000-4000-8000-000000000001")!

    private func makeBoard(day: Int, revision: Int = 1) -> SharedDailyBoard {
        let puzzle = PuzzleGenerator.generate(seed: 7, difficulty: .gentle)
        return SharedDailyBoard(
            entryID: Self.entryID,
            dayOrdinal: day,
            game: NineGame(puzzle: puzzle),
            revision: revision,
            updatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
        )
    }

    func testBoardRoundTripsWithMovesAndUndoStack() throws {
        var board = makeBoard(day: 9_200)
        let hole = (0..<81).first { !board.game.isGiven($0) }!
        let digit = board.game.puzzle.solution[hole]
        XCTAssertTrue(board.game.place(digit, at: hole))
        board.revision += 1

        try SharedDailyBoardStore.save(board, to: url)
        let loaded = SharedDailyBoardStore.load(from: url)
        XCTAssertEqual(loaded, board)
        XCTAssertEqual(loaded?.game.undoStack.count, 1, "undo stack crosses the file intact")

        // The app can undo the widget's move after adopting.
        var adopted = loaded!.game
        XCTAssertEqual(adopted.undo()?.digit, digit)
        XCTAssertEqual(adopted.entry(at: hole), 0)
    }

    /// A file written by a pre-removal build has no `entryID`; it must decode
    /// (never discard a player's board bytes) and read back as unadoptable.
    func testALegacyFileDecodesWithNoEntryID() throws {
        var board = makeBoard(day: 9_200)
        board.entryID = nil
        let encoder = JSONEncoder()
        // A legacy writer simply never wrote the key; encoding nil omits it.
        let data = try encoder.encode(board)
        let decoded = try JSONDecoder().decode(SharedDailyBoard.self, from: data)
        XCTAssertNil(decoded.entryID)
        XCTAssertEqual(decoded.game, board.game)
    }

    func testPendingSolveRoundTrip() throws {
        var board = makeBoard(day: 9_200)
        board.pendingSolve = PendingSolve(
            solvedAt: Date(timeIntervalSinceReferenceDate: 800_000_100), seconds: 251
        )
        try SharedDailyBoardStore.save(board, to: url)
        XCTAssertEqual(SharedDailyBoardStore.load(from: url)?.pendingSolve?.seconds, 251)
    }

    func testMissingFileLoadsAsNil() {
        XCTAssertNil(SharedDailyBoardStore.load(from: url), "no board → 'tap to start', no crash")
    }

    func testSelectionIsKeyedToDay() throws {
        let suite = "nine-shared-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        SharedDailyBoardStore.setSelectedCell(40, today: 9_200, defaults: defaults)
        XCTAssertEqual(SharedDailyBoardStore.selectedCell(today: 9_200, defaults: defaults), 40)
        XCTAssertNil(
            SharedDailyBoardStore.selectedCell(today: 9_201, defaults: defaults),
            "midnight invalidates the leftover selection"
        )
        SharedDailyBoardStore.setSelectedCell(nil, today: 9_200, defaults: defaults)
        XCTAssertNil(SharedDailyBoardStore.selectedCell(today: 9_200, defaults: defaults))
    }
}
