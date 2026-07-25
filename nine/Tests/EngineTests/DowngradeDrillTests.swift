// DowngradeDrillTests — PRD-17's downgrade drill, run in-process.
//
// Adding a `Difficulty` case is the first schema change Nine has shipped since
// Phase 0, and it is the exact change Phase 0 was built for. The question this
// file answers is narrow and load-bearing: **when a build that has never heard
// of Nocturne meets a store containing Nocturne, what does the player lose?**
//
// The old build is modelled by the `Legacy*` mirror types below — field for
// field, coder for coder, what `Difficulty` / `SolveRecord` / `SolveHistory` /
// `GameKind` / `LibraryEntry` looked like in the shipped 1.5 tree (TestFlight
// tvOS 450 / iOS 451 / macOS 452), with `case gentle, steady, sharp` and the
// *synthesized* Codable that shipped with it. A mirror is a claim about code
// that is not in this tree, so it is checked against the real thing rather than
// trusted: `nine/scripts/downgrade-drill.sh` runs the same assertions against an
// actual git checkout of the previous release. Run that before shipping; run
// this on every commit.
//
// The two stores are not symmetrical, and the asymmetry is the whole design:
//
//   • `nine.library` — a Phase 0 blob. Its decode quarantines whole elements,
//     so a Nocturne board is *preserved verbatim* and handed back on upgrade.
//     Nothing was needed here; these tests pin that it stays true.
//   • `nine.history` — NOT a Phase 0 blob. `SolveHistory` shipped with a
//     synthesized decode, so one Nocturne `SolveRecord` threw the `[SolveRecord]`
//     array decode, `CouchStore`'s `try?` swallowed it, and the player lost
//     **every solve they had ever recorded** — on the old device, and then on
//     every device, because `nine.history` is `cloudSynced` and KVS is
//     last-writer-wins. Tolerance added in *this* build cannot fix that: the
//     build that does the throwing is already in the wild. So the fix has to be
//     on the wire — a Nocturne record persists its `difficulty` as `sharp`
//     (which every shipped build reads) and carries its true identity in a
//     sibling `band` key (which every shipped build ignores).
import Testing
import Foundation
import CouchCore
@testable import NineEngine

@Suite("DowngradeDrill")
struct DowngradeDrillTests {

    // MARK: - The previous release, as it decodes

    /// `Difficulty` as shipped in 1.5: three cases, raw-string `Codable`.
    /// Decoding `"nocturne"` through this throws — that is the hazard.
    enum LegacyDifficulty: String, Codable, Equatable {
        case gentle, steady, sharp
    }

    /// `SolveRecord` as shipped in 1.5: synthesized `Codable`, no tolerance,
    /// no sibling key. An unknown `difficulty` raw value throws out of here.
    struct LegacySolveRecord: Codable, Equatable {
        let date: Date
        let difficulty: LegacyDifficulty
        let isDaily: Bool
        let seconds: TimeInterval
        let points: Int
    }

    /// `SolveHistory` as shipped in 1.5: one synthesized array decode, so a
    /// single bad element takes the whole blob with it.
    struct LegacySolveHistory: Codable, Equatable {
        let records: [LegacySolveRecord]
    }

    /// `GameKind` as shipped in 1.5.
    enum LegacyGameKind: Codable, Equatable {
        case daily(day: Int)
        case free(LegacyDifficulty)
    }

    /// `LibraryEntry` as shipped in 1.5. Only the fields matter — this is the
    /// element `BoardLibrary`'s decode either understands or quarantines.
    struct LegacyLibraryEntry: Codable, Equatable {
        var id: UUID
        var kind: LegacyGameKind
        var game: NineGame
        var status: BoardStatus
        var createdAt: Date
        var updatedAt: Date
        var solvedAt: Date?
    }

    // MARK: - Helpers

    private func t(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
    }

    private func record(_ offset: TimeInterval, _ difficulty: Difficulty, points: Int) -> SolveRecord {
        SolveRecord(date: t(offset), difficulty: difficulty, isDaily: false,
                    seconds: 600, points: points)
    }

    /// A history with one board from every band this build ships, Nocturne last.
    private func mixedHistory() -> SolveHistory {
        var history = SolveHistory()
        history.record(record(0, .gentle, points: 100))
        history.record(record(10, .steady, points: 250))
        history.record(record(20, .sharp, points: 500))
        history.record(record(30, .nocturne, points: 800))
        return history
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    // MARK: - nine.history: the blob with no quarantine

    /// The drill, stated as one assertion: the old build still reads all four
    /// solves. Before the wire bridge this decode threw, and `CouchStore`'s
    /// `try?` turned that throw into an empty history.
    @Test func oldBuildKeepsItsWholeHistoryWhenItMeetsANocturneSolve() throws {
        let blob = try CouchJSON.encode(mixedHistory())

        let old = try CouchJSON.decode(LegacySolveHistory.self, from: blob)

        #expect(old.records.count == 4)
        #expect(old.records.map(\.points) == [800, 500, 250, 100])
    }

    /// PRD-17 §6, verbatim: "entry shown as Sharp". The old build has no word
    /// for Nocturne, and the nearest true thing is the band below it.
    @Test func oldBuildShowsANocturneSolveAsSharp() throws {
        let blob = try CouchJSON.encode(mixedHistory())

        let old = try CouchJSON.decode(LegacySolveHistory.self, from: blob)

        #expect(old.records[0].difficulty == .sharp)   // the Nocturne one
        #expect(old.records.map(\.difficulty) == [.sharp, .sharp, .steady, .gentle])
    }

    /// Points are on the record, not derived from the band, so the 800 survives
    /// the downgrade intact — the score a player earned is never restated.
    @Test func oldBuildKeepsTheNocturnePointsUnrestated() throws {
        let blob = try CouchJSON.encode(mixedHistory())

        let old = try CouchJSON.decode(LegacySolveHistory.self, from: blob)

        #expect(old.records[0].points == 800)
        #expect(old.records.reduce(0) { $0 + $1.points } == mixedHistory().totalPoints)
    }

    /// The sibling key is the whole mechanism, so pin its shape: `difficulty`
    /// is what an old build reads, `band` is what this build reads.
    @Test func aNocturneRecordPersistsAsSharpPlusABandSibling() throws {
        let blob = try CouchJSON.encode(mixedHistory())
        let records = try object(blob)["records"] as! [[String: Any]]

        let nocturne = records[0]
        #expect(nocturne["difficulty"] as? String == "sharp")
        #expect(nocturne["band"] as? String == "nocturne")

        // And no other band grows a sibling — the bytes 1.5 wrote for a sharp
        // solve are the bytes this build writes for one.
        for known in records.dropFirst() { #expect(known["band"] == nil) }
    }

    /// This build reads its own blob back as Nocturne, not as the Sharp it
    /// persisted. The bridge is a wire format, not a demotion.
    @Test func thisBuildReadsTheBandBackAsNocturne() throws {
        let blob = try CouchJSON.encode(mixedHistory())

        let reread = try CouchJSON.decode(SolveHistory.self, from: blob)

        #expect(reread == mixedHistory())
        #expect(reread.records[0].difficulty == .nocturne)
        #expect(reread.count(of: .nocturne) == 1)
        #expect(try CouchJSON.encode(reread) == blob)
    }

    /// The accepted cost, written down as a test so it cannot be forgotten:
    /// the old build re-encodes from its typed value and the sibling goes with
    /// it, so a Nocturne solve that a downgraded device *writes back* comes home
    /// as Sharp. The solve, its time and its points all survive; only the band
    /// label is lost, and only once the old device actually autosaves.
    @Test func anOldBuildRewriteDemotesNocturneToSharpButLosesNoSolve() throws {
        let blob = try CouchJSON.encode(mixedHistory())

        let old = try CouchJSON.decode(LegacySolveHistory.self, from: blob)
        let rewritten = try CouchJSON.encode(old)
        let home = try CouchJSON.decode(SolveHistory.self, from: rewritten)

        #expect(home.records.count == 4)
        #expect(home.totalPoints == mixedHistory().totalPoints)
        #expect(home.count(of: .nocturne) == 0)
        #expect(home.count(of: .sharp) == 2)
    }

    // MARK: - nine.history: the *next* case after Nocturne

    /// Nocturne is not the last band Nine will ever add, and this build is a
    /// future release's "old build". An unrecognised band must not throw here
    /// either — and must not be quietly rewritten into a lie, so the id is
    /// carried and re-emitted verbatim.
    @Test func anUnknownFutureBandDecodesAsSharpAndSurvivesARewrite() throws {
        var blob = try object(CouchJSON.encode(mixedHistory()))
        var records = blob["records"] as! [[String: Any]]
        records[0]["band"] = "tempest"
        blob["records"] = records
        let data = try JSONSerialization.data(withJSONObject: blob)

        let history = try CouchJSON.decode(SolveHistory.self, from: data)
        #expect(history.records.count == 4)
        #expect(history.records[0].difficulty == .sharp)

        let back = try object(CouchJSON.encode(history))["records"] as! [[String: Any]]
        #expect(back[0]["band"] as? String == "tempest")
        #expect(back[0]["difficulty"] as? String == "sharp")
    }

    /// The same, for a future build that writes an unknown band into
    /// `difficulty` itself rather than into the sibling.
    @Test func anUnknownRawDifficultyDecodesAsSharpAndSurvivesARewrite() throws {
        var blob = try object(CouchJSON.encode(mixedHistory()))
        var records = blob["records"] as! [[String: Any]]
        records[3]["difficulty"] = "abyss"
        blob["records"] = records
        let data = try JSONSerialization.data(withJSONObject: blob)

        let history = try CouchJSON.decode(SolveHistory.self, from: data)
        #expect(history.records.count == 4)
        #expect(history.records[3].difficulty == .sharp)

        let back = try object(CouchJSON.encode(history))["records"] as! [[String: Any]]
        #expect(back[3]["band"] as? String == "abyss")
    }

    /// A record this build cannot decode at all — a future release that changed
    /// the record's *shape*, not just a raw value — must cost the player that
    /// one solve, never the log. Same covenant as `BoardLibrary`, same
    /// mechanism.
    @Test func anUnreadableRecordIsQuarantinedNotFatal() throws {
        var blob = try object(CouchJSON.encode(mixedHistory()))
        var records = blob["records"] as! [[String: Any]]
        records.append(["date": ["restructured": true], "points": 900])
        blob["records"] = records
        let data = try JSONSerialization.data(withJSONObject: blob)

        let history = try CouchJSON.decode(SolveHistory.self, from: data)
        #expect(history.records.count == 4)
        #expect(history.quarantined.count == 1)

        // Preserved verbatim, and invisible to the cap.
        let back = try object(CouchJSON.encode(history))["records"] as! [[String: Any]]
        #expect(back.count == 5)
        #expect(back[4]["points"] as? Int == 900)
    }

    @Test func aHistoryBlobIsNeverDiscardedWholesale() throws {
        for blob in [#"{"records":"nope"}"#, #"{}"#, #"{"records":null}"#, #"[1,2,3]"#] {
            let history = try CouchJSON.decode(SolveHistory.self, from: Data(blob.utf8))
            #expect(history.records.isEmpty, "\(blob)")
        }
    }

    /// The 1.x shape, unchanged: a history of known bands writes exactly the
    /// one `records` key 1.5 wrote, byte for byte.
    @Test func aKnownOnlyHistoryRoundTripsByteIdentically() throws {
        var history = SolveHistory()
        history.record(record(0, .gentle, points: 100))
        history.record(record(10, .sharp, points: 500))

        let data = try CouchJSON.encode(history)
        #expect(Array(try object(data).keys) == ["records"])
        let reread = try CouchJSON.decode(SolveHistory.self, from: data)
        #expect(reread == history)
        #expect(try CouchJSON.encode(reread) == data)
    }

    /// An unknown sibling of `records` — a future `schemaVersion`, a future
    /// per-band summary — is carried, not stripped. Same rule as the library's
    /// `carriedTopLevel`, and the reason PRD-17 could add a sibling at all.
    @Test func anUnknownTopLevelSiblingOfRecordsSurvivesARoundTrip() throws {
        var blob = try object(CouchJSON.encode(mixedHistory()))
        blob["schemaVersion"] = 2
        let data = try JSONSerialization.data(withJSONObject: blob)

        let history = try CouchJSON.decode(SolveHistory.self, from: data)
        #expect(history.records.count == 4)
        let back = try object(CouchJSON.encode(history))
        #expect(back["schemaVersion"] as? Int == 2)
    }

    /// The cap counts solves, not carried junk — the same rule the library's
    /// `prune()` follows for its quarantine.
    @Test func theHistoryCapCountsRealRecordsOnly() throws {
        var blob = try object(CouchJSON.encode(mixedHistory()))
        var records = blob["records"] as! [[String: Any]]
        records.append(["date": ["restructured": true]])
        blob["records"] = records
        var history = try CouchJSON.decode(
            SolveHistory.self, from: try JSONSerialization.data(withJSONObject: blob))

        for i in 0..<SolveHistory.capacity {
            history.record(record(1000 + Double(i), .gentle, points: 100))
        }

        #expect(history.records.count == SolveHistory.capacity)
        #expect(history.quarantined.count == 1)
    }

    // MARK: - the newest-first invariant

    /// `records` is newest-first by contract: `capacity` prunes the tail as the
    /// oldest, `trend(window:)` reads `prefix` as the most recent, the History
    /// sheet shows `prefix(15)`, and `WidgetBridge` takes `first`. Quarantined
    /// elements are re-emitted *after* the readable ones — they have to be,
    /// since this build cannot read their dates — so a build that gets them back
    /// must restore the order, exactly as `BoardLibrary.init(from:)` does.
    ///
    /// Without the sort this is not a cosmetic misordering: the recovered
    /// records are the player's *newest* solves, and they would be the first
    /// ones `removeLast` deletes at capacity.
    @Test func recoveredRecordsAreResortedNewestFirst() throws {
        // The blob an older build would write: two readable records, then a
        // newer one it had to hold at the tail.
        var blob = try object(CouchJSON.encode(mixedHistory()))
        var records = blob["records"] as! [[String: Any]]
        let newest = records.removeFirst()                       // the t(30) solve
        records.append(newest)                                    // …parked at the end
        blob["records"] = records
        let data = try JSONSerialization.data(withJSONObject: blob)

        let history = try CouchJSON.decode(SolveHistory.self, from: data)

        #expect(history.records.map(\.date) == history.records.map(\.date).sorted(by: >))
        #expect(history.records.first?.difficulty == .nocturne)
    }

    // MARK: - the stand-in a future build chose is not ours to rewrite

    /// A future band whose downgrade target is Steady rather than Sharp. This
    /// build cannot know that band, but it can carry both halves verbatim — and
    /// it must, or it silently restates the record as Sharp for every build
    /// downstream, including the `sharp.first` achievement gate.
    @Test func aFutureBandsChosenStandInSurvivesThisBuild() throws {
        var blob = try object(CouchJSON.encode(mixedHistory()))
        var records = blob["records"] as! [[String: Any]]
        records[0]["difficulty"] = "steady"
        records[0]["band"] = "dusk"
        blob["records"] = records
        let data = try JSONSerialization.data(withJSONObject: blob)

        let history = try CouchJSON.decode(SolveHistory.self, from: data)
        #expect(history.records[0].difficulty == .steady, "the writer's stand-in, not ours")
        #expect(history.count(of: .sharp) == 1, "the unknown band must not inflate Sharp")

        let back = try object(CouchJSON.encode(history))["records"] as! [[String: Any]]
        #expect(back[0]["difficulty"] as? String == "steady")
        #expect(back[0]["band"] as? String == "dusk")
    }

    /// A future build that changed `difficulty` from a string to something else
    /// is a record whose *shape* this build cannot read. The covenant says
    /// quarantine it — decoding it as Sharp and writing that back destroys it on
    /// the next autosave.
    @Test func aNonStringDifficultyIsQuarantinedRatherThanFlattenedToSharp() throws {
        var blob = try object(CouchJSON.encode(mixedHistory()))
        var records = blob["records"] as! [[String: Any]]
        records[1]["difficulty"] = ["id": "dusk", "since": 3]
        blob["records"] = records
        let data = try JSONSerialization.data(withJSONObject: blob)

        let history = try CouchJSON.decode(SolveHistory.self, from: data)
        #expect(history.records.count == 3)
        #expect(history.quarantined.count == 1)

        let back = try object(CouchJSON.encode(history))["records"] as! [[String: Any]]
        #expect(back.count == 4)
        let held = back.first { ($0["difficulty"] as? [String: Any]) != nil }
        #expect(held?["difficulty"] as? [String: Any] != nil, "the future shape was flattened")
    }

    // MARK: - nine.library: the blob Phase 0 already covered

    /// The library half of the drill. A Nocturne board is an element the old
    /// build cannot decode — `GameKind.free` and the puzzle's own `difficulty`
    /// both carry the unknown raw value — so Phase 0's quarantine catches it and
    /// the player's other boards are untouched.
    @Test func oldBuildKeepsItsWholeLibraryWhenItMeetsANocturneBoard() throws {
        var library = BoardLibrary()
        _ = library.create(kind: .free(.gentle), game: Self.gentleBoard, now: t(0))
        _ = library.create(kind: .free(.steady), game: Self.gentleBoard, now: t(10))
        _ = library.create(kind: .free(.nocturne), game: Self.nocturneBoard, now: t(20))
        let blob = try CouchJSON.encode(library)

        // The old build's `BoardLibrary` decode is this build's — Phase 0
        // shipped it — but its `LibraryEntry` is the legacy one, so model the
        // element decode directly, which is what the quarantine turns on.
        let elements = try object(blob)["entries"] as! [Any]
        #expect(elements.count == 3)
        var readable = 0, unreadable = 0
        for element in elements {
            let data = try JSONSerialization.data(withJSONObject: element)
            if (try? CouchJSON.decode(LegacyLibraryEntry.self, from: data)) != nil {
                readable += 1
            } else {
                unreadable += 1
            }
        }
        #expect(readable == 2)
        #expect(unreadable == 1)
    }

    /// Downgrade → upgrade: the old build quarantines the Nocturne board, writes
    /// the library back, and this build gets the board returned intact. The
    /// board is *invisible* while the player is on the old build — that is the
    /// accepted cost, and it is strictly better than the alternative, because
    /// nothing is lost.
    @Test func aNocturneBoardSurvivesAnOldBuildRewriteVerbatim() throws {
        var library = BoardLibrary()
        _ = library.create(kind: .free(.gentle), game: Self.gentleBoard, now: t(0))
        let nocturneID = library.create(kind: .free(.nocturne), game: Self.nocturneBoard, now: t(20))
        let blob = try CouchJSON.encode(library)

        // The old build: it cannot type the element, so it quarantines it. Model
        // that by rebuilding the blob with the Nocturne element held as raw JSON,
        // which is exactly what `BoardLibrary.init(from:)` does.
        let quarantining = try CouchJSON.decode(QuarantiningLibrary.self, from: blob)
        #expect(quarantining.entries.count == 1)
        #expect(quarantining.quarantined.count == 1)
        let rewritten = try CouchJSON.encode(quarantining)

        let home = try CouchJSON.decode(BoardLibrary.self, from: rewritten)
        #expect(home.entries.count == 2)
        #expect(home.entries.contains { $0.id == nocturneID })
        #expect(home.quarantined.isEmpty)
        let recovered = home.entries.first { $0.id == nocturneID }!
        #expect(recovered.kind == .free(.nocturne))
        #expect(recovered.game.puzzle.difficulty == .nocturne)
    }

    /// `BoardLibrary` with the legacy element type spliced in — the same decode
    /// this build ships, reading through 1.5's `LibraryEntry`.
    struct QuarantiningLibrary: Codable {
        var entries: [LegacyLibraryEntry] = []
        var quarantined: [QuarantinedEntry] = []

        private enum CodingKeys: String, CodingKey { case entries }

        init(from decoder: Decoder) throws {
            guard let container = try? decoder.container(keyedBy: CodingKeys.self),
                  let raw = try? container.decode([RawJSON].self, forKey: .entries) else { return }
            for element in raw {
                let data = try JSONEncoder().encode(element)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let entry = try? decoder.decode(LegacyLibraryEntry.self, from: data) {
                    entries.append(entry)
                } else {
                    quarantined.append(QuarantinedEntry(element))
                }
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            var array = container.nestedUnkeyedContainer(forKey: .entries)
            for entry in entries { try array.encode(entry) }
            for element in quarantined { try array.encode(element) }
        }
    }

    // MARK: - Fixtures for the out-of-tree drill

    /// Writes the blobs `scripts/downgrade-drill.sh` feeds to a real checkout of
    /// the previous release. Not an assertion — a fixture generator that happens
    /// to live in the suite so it cannot drift from the types it serialises.
    ///
    ///     NINE_WRITE_DOWNGRADE_FIXTURES=/tmp/fx swift test --filter DowngradeDrill
    @Test func writeFixturesWhenAsked() throws {
        guard let directory = ProcessInfo.processInfo
            .environment["NINE_WRITE_DOWNGRADE_FIXTURES"] else { return }
        let base = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        try CouchJSON.encode(mixedHistory())
            .write(to: base.appendingPathComponent("nine.history.json"))

        var library = BoardLibrary()
        _ = library.create(kind: .free(.gentle), game: Self.gentleBoard, now: t(0))
        _ = library.create(kind: .free(.sharp), game: Self.gentleBoard, now: t(10))
        _ = library.create(kind: .free(.nocturne), game: Self.nocturneBoard, now: t(20))
        try CouchJSON.encode(library)
            .write(to: base.appendingPathComponent("nine.library.json"))
    }

    // MARK: - Fixtures

    /// Generation is the expensive part of this file, and every assertion here
    /// is about the *raw value in the blob*, never about the board. So the
    /// Nocturne fixture is a gentle puzzle wearing a Nocturne label rather than
    /// a real compose: a real one costs seconds in Release and minutes in the
    /// Debug build `swift test` uses, which would put this file alone over the
    /// suite's 120 s budget. `GeneratorTests` proves real Nocturne boards; this
    /// file proves what happens to the four bytes `"nocturne"` on the way past
    /// a decoder that has never seen them.
    private static let gentleBoard = NineGame(
        puzzle: PuzzleGenerator.generate(seed: 1, difficulty: .gentle))
    private static let nocturneBoard: NineGame = {
        let base = PuzzleGenerator.generate(seed: 1, difficulty: .gentle)
        return NineGame(puzzle: GeneratedPuzzle(
            puzzle: base.puzzle, solution: base.solution, difficulty: .nocturne,
            seed: base.seed, steps: base.steps))
    }()
}
