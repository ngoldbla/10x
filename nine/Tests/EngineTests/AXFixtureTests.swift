// AXFixtureTests — the board the accessibility-tree CI lane photographs
// (PRD-19).
//
// `nine/scripts/ax-snapshot.py` diffs `sim-use describe-ui` dumps against
// committed baselines. Those dumps carry per-cell *values* ("5, given",
// "Empty, notes 2, 5, 9", "7, wrong"), so the baselines are only stable if the
// board on screen is always the same board — and a freshly launched Nine shows
// today's daily, which is a different puzzle tomorrow.
//
// So the lane seeds the simulator's container with one frozen library blob
// before first launch, and this test owns that blob: it rebuilds it from the
// engine and asserts the committed bytes still match. The board is chosen to
// exercise every branch of `BoardSpeech.cellValue` at once — givens, a correct
// entry, a wrong entry, an empty cell, an empty cell with notes — so a
// regression in any of them shows up as a one-line diff in CI rather than as
// nothing at all.
//
// Re-freezing is deliberate, same covenant as the golden corpus:
//   NINE_FREEZE_AX_FIXTURE=1 swift test --filter AXFixture
// and a re-freeze means the AX baselines must be re-recorded too:
//   nine/scripts/ax-snapshot.py --record
import XCTest
import Foundation
@testable import NineEngine

final class AXFixtureTests: XCTestCase {

    // MARK: - The frozen board

    /// `(7, .steady)` is a pair the golden corpus already freezes (it covers
    /// steady seeds 1...14 — check before changing this), so if generation
    /// moves, `GoldenCorpusTests` fails first and says so in engine terms, and
    /// this test is the second, quieter signal that the AX baselines are now
    /// photographs of a board that no longer exists. Pointing it at a seed
    /// *outside* the corpus would silently give up that ordering.
    static let seed: UInt64 = 7
    static let difficulty: Difficulty = .steady

    /// Fixed so the blob's bytes are fixed. Nothing reads them for meaning;
    /// `resumeOnLaunch` only needs *a* most-recent partial.
    static let entryID = UUID(uuidString: "19190000-0000-4000-8000-000000000019")!  // PRD-19
    static let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    /// The move script, in indices into the puzzle's empty cells (ascending).
    /// Deliberately sparse and deliberately including a wrong digit: the
    /// `showErrors` privacy rule has a false branch that only a wrong entry
    /// can exercise, and the CI lane dumps the board twice, once per setting.
    static let correctAt = [0, 1, 2]
    static let wrongAt = 4
    static let notedAt = 6
    static let notes = [2, 5, 9]

    /// The blob the lane writes to
    /// `Library/Application Support/CouchKit/default.nine.library.json`.
    static func build() -> BoardLibrary {
        let puzzle = PuzzleGenerator.generate(seed: seed, difficulty: difficulty)
        var game = NineGame(puzzle: puzzle)
        let holes = (0..<81).filter { puzzle.puzzle[$0] == 0 }

        for index in correctAt {
            _ = game.place(puzzle.solution[holes[index]], at: holes[index])
        }
        let wrongCell = holes[wrongAt]
        let solution = puzzle.solution[wrongCell]
        _ = game.place(solution == 9 ? 1 : solution + 1, at: wrongCell)
        for digit in notes {
            _ = game.togglePencil(digit, at: holes[notedAt])
        }

        return BoardLibrary(entries: [
            LibraryEntry(
                id: entryID,
                kind: .free(difficulty),
                game: game,
                status: .inProgress,
                createdAt: timestamp,
                updatedAt: timestamp
            ),
        ])
    }

    // MARK: - The tripwire

    func testFixtureMatchesTheCommittedBlob() throws {
        let rebuilt = try Self.canonicalJSON(Self.build())
        if ProcessInfo.processInfo.environment["NINE_FREEZE_AX_FIXTURE"] != nil {
            try FileManager.default.createDirectory(
                at: Self.fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try rebuilt.write(to: Self.fixtureURL, options: .atomic)
            print("froze \(Self.fixtureURL.path) (\(rebuilt.count) bytes)")
            return
        }
        let committed = try Data(contentsOf: Self.fixtureURL)
        XCTAssertEqual(
            String(decoding: rebuilt, as: UTF8.self),
            String(decoding: committed, as: UTF8.self),
            """
            the seeded board moved, so every AX baseline is now a photograph of \
            a different puzzle. Re-freeze deliberately and re-record together: \
            NINE_FREEZE_AX_FIXTURE=1 swift test --filter AXFixture && \
            nine/scripts/ax-snapshot.py --record
            """
        )
    }

    /// The fixture is only useful if it round-trips through the same tolerant
    /// decode the app uses — a blob the app quarantines would leave the shelf
    /// empty and the lane would photograph the home screen nine times.
    func testFixtureDecodesBackToTheSameLibraryWithNothingQuarantined() throws {
        let library = try Self.decode(BoardLibrary.self, from: Data(contentsOf: Self.fixtureURL))
        XCTAssertEqual(library, Self.build())
        XCTAssertEqual(library.quarantined.count, 0)
        XCTAssertEqual(library.entries.count, 1)
        XCTAssertNotNil(library.mostRecentInProgress, "resumeOnLaunch needs a partial to find")
    }

    /// What the baselines actually depend on. If any of these stops holding,
    /// the dumps stop covering the branch they were built to cover.
    func testFixtureBoardExercisesEveryCellValueBranch() throws {
        let entry = try XCTUnwrap(Self.build().entries.first)
        let game = entry.game
        XCTAssertTrue((0..<81).contains { game.isGiven($0) }, "givens")
        XCTAssertTrue((0..<81).contains { game.entry(at: $0) == 0 }, "empty cells")
        XCTAssertTrue(
            (0..<81).contains { !game.isGiven($0) && game.entry(at: $0) != 0 && !game.isError(at: $0) },
            "a correct user entry"
        )
        XCTAssertEqual(game.errorCells.count, 1, "exactly one wrong digit, so the diff is legible")
        XCTAssertEqual(
            (0..<81).filter { game.hasPencilMarks(at: $0) }.count, 1,
            "exactly one noted cell"
        )
        XCTAssertEqual(game.pencilDigits(at: game.firstNotedCell), Self.notes)
    }

    // MARK: - Helpers

    /// `nine/Tests/AXBaselines/fixture.nine.library.json`, beside the dumps it
    /// makes deterministic.
    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)          // …/Tests/EngineTests/AXFixtureTests.swift
            .deletingLastPathComponent()          // …/Tests/EngineTests
            .deletingLastPathComponent()          // …/Tests
            .appendingPathComponent("AXBaselines/fixture.nine.library.json")
    }

    /// Byte-identical to what `CouchStored` writes: sorted keys, ISO-8601
    /// dates. Spelled out rather than importing CouchKit, which the engine
    /// deliberately does not depend on.
    static func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

private extension NineGame {
    /// First cell carrying pencil marks — the fixture guarantees exactly one.
    var firstNotedCell: Int {
        (0..<81).first { hasPencilMarks(at: $0) } ?? 0
    }
}
