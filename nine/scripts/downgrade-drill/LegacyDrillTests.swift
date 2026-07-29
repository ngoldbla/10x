// LegacyDrillTests — the downgrade drill's old half. PRD-17, PROGRAM-2.0 Phase 0 §3.
//
// This file is NOT part of the build. `scripts/downgrade-drill.sh` copies it
// into a git worktree of the *previous release* and runs it there, so every
// type it names — `SolveHistory`, `BoardLibrary`, `Difficulty` — is that
// release's code, compiled from that release's source. It is the check on
// `DowngradeDrillTests`, whose `Legacy*` mirror types are only a claim about
// code that is not in the tree.
//
// It must compile against a build that has never heard of Nocturne, so it may
// only reference the three bands that shipped in 1.5. If this file ever needs
// `.nocturne` to compile, the drill has stopped testing a downgrade.
import XCTest
import Foundation
import CouchCore
@testable import NineEngine

final class LegacyDrillTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let directory = try XCTUnwrap(
            ProcessInfo.processInfo.environment["NINE_DOWNGRADE_FIXTURES"],
            "run this through scripts/downgrade-drill.sh")
        return try Data(contentsOf: URL(fileURLWithPath: directory)
            .appendingPathComponent(name))
    }

    /// The headline: a history written by a build that has Nocturne, decoded by
    /// one that does not. Before the `band` sibling this threw, `CouchStore`'s
    /// `try?` turned the throw into a default-constructed `SolveHistory`, and
    /// the player's entire solve log was gone — from the old device first, and
    /// then from every device, because `nine.history` is `cloudSynced` and KVS
    /// is last-writer-wins.
    func testTheOldBuildKeepsItsWholeHistory() throws {
        let history = try CouchJSON.decode(SolveHistory.self, from: fixture("nine.history.json"))

        XCTAssertEqual(history.records.count, 4, "a Nocturne solve cost this build its history")
        XCTAssertEqual(history.totalPoints, 100 + 250 + 500 + 800)
        // PRD-17 §6: "entry shown as Sharp".
        XCTAssertEqual(history.records.map(\.difficulty), [.sharp, .sharp, .steady, .gentle])
        XCTAssertEqual(history.records[0].points, 800, "the points earned are never restated")
    }

    /// Task 2 added `SolveRecord.errors`, a plain optional persisted with no
    /// carried-sibling machinery — unlike the band above, there is no
    /// unrecognised *value* here for an old build to preserve, only an unknown
    /// JSON key for it to ignore. The fixture's Nocturne solve carries an
    /// `errors` count, and the whole point of this test is that a build that
    /// has never heard of the key must not care that it is there.
    func testTheOldBuildIgnoresTheUnknownErrorsKey() throws {
        let data = try fixture("nine.history.json")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"errors\""), "the fixture must actually exercise the new key")

        let history = try CouchJSON.decode(SolveHistory.self, from: data)
        XCTAssertEqual(history.records.count, 4, "an unrecognised `errors` key must not throw")
        XCTAssertEqual(history.records[0].points, 800, "the record carrying it is otherwise untouched")

        // The autosave round trip: this build re-encodes from its own typed
        // value, which has no `errors` property to write back — and reading
        // that rewrite must still succeed, exactly as the band's rewrite does.
        let rewritten = try CouchJSON.encode(history)
        let reread = try CouchJSON.decode(SolveHistory.self, from: rewritten)
        XCTAssertEqual(reread.records.count, 4)
    }

    /// And the library: a Nocturne board is an element this build cannot type,
    /// so Phase 0's quarantine holds it verbatim. The other boards are
    /// untouched, and the Nocturne one is handed back on the next upgrade.
    func testTheOldBuildKeepsItsWholeLibrary() throws {
        let data = try fixture("nine.library.json")
        let library = try CouchJSON.decode(BoardLibrary.self, from: data)

        XCTAssertEqual(library.entries.count, 2, "the readable boards survive")
        XCTAssertEqual(library.quarantined.count, 1, "the Nocturne board is held, not dropped")

        // The rewrite an autosave performs 0.6 s after this build opens the
        // library must hand all three elements back.
        let rewritten = try CouchJSON.encode(library)
        let object = try JSONSerialization.jsonObject(with: rewritten) as! [String: Any]
        let elements = object["entries"] as! [Any]
        XCTAssertEqual(elements.count, 3)

        // And the held element is still verbatim Nocturne, ready for the
        // upgrade to re-decode.
        let held = try JSONSerialization.data(withJSONObject: elements[2])
        let text = String(decoding: held, as: UTF8.self)
        XCTAssertTrue(text.contains("nocturne"), "the band was rewritten or lost")
    }

    /// A downgrade is only safe if it is also idempotent: the old build opens
    /// and autosaves repeatedly, and the quarantine must not grow each time.
    func testRepeatedOldBuildRewritesAreStable() throws {
        var data = try fixture("nine.library.json")
        for _ in 0..<3 {
            data = try CouchJSON.encode(CouchJSON.decode(BoardLibrary.self, from: data))
        }
        let library = try CouchJSON.decode(BoardLibrary.self, from: data)
        XCTAssertEqual(library.entries.count, 2)
        XCTAssertEqual(library.quarantined.count, 1)
    }
}
