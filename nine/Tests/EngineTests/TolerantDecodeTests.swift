// TolerantDecodeTests — the persistence covenant, exercised: never throw out of
// a container decode, and never delete what you cannot read.
//
// The library persists as ONE `nine.library` blob and `CouchStored` drops the
// whole blob when decode throws, so a single unreadable entry used to cost the
// player every board they had. These tests stand in for the two futures that
// can actually produce one: a newer build writing a `GameKind` discriminator or
// a `Difficulty` raw value this build has never heard of, on another device or
// after a downgrade. The "newer build" is modelled by the `Future*` mirror types
// below — same field names, same coder, one extra case.
//
// Scope, stated plainly: the quarantine is per *element*. An element a newer
// build merely enriched — say 1.6 adding an optional `LibraryEntry.lastHintAt`
// — still decodes on 1.5, so it never reaches the quarantine, and 1.5 re-encodes
// it from the typed value and drops the new field. Preserving unknown *fields*
// on a known entry is a different (and much larger) mechanism; see DEVIATIONS.md
// for why Phase 0 stopped at the element boundary.
import Testing
import Foundation
import CouchCore
@testable import NineEngine

@Suite("TolerantDecode")
struct TolerantDecodeTests {

    // MARK: - The future, as a build that has not shipped would write it

    /// `GameKind` plus a case this build does not have. The synthesized Codable
    /// shape is case-name keyed, so `.timed` lands as `{"timed":{"seconds":N}}`
    /// — an element today's `GameKind` cannot decode under any key.
    enum FutureGameKind: Codable, Equatable {
        case daily(day: Int)
        case free(Difficulty)
        case timed(seconds: Int)
    }

    /// `LibraryEntry` field-for-field, with the wider kind.
    struct FutureLibraryEntry: Codable, Equatable {
        var id: UUID
        var kind: FutureGameKind
        var game: NineGame
        var status: BoardStatus
        var createdAt: Date
        var updatedAt: Date
        var solvedAt: Date?
    }

    // MARK: - helpers

    private func t(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
    }

    /// One generated board, reused everywhere — generation is the expensive part
    /// of this file and none of these assertions care which puzzle it is.
    private static let board = NineGame(puzzle: PuzzleGenerator.generate(seed: 1, difficulty: .gentle))

    private func entry(_ offset: TimeInterval, kind: GameKind = .free(.gentle)) -> LibraryEntry {
        LibraryEntry(
            kind: kind, game: Self.board, status: .inProgress,
            createdAt: t(offset), updatedAt: t(offset)
        )
    }

    /// Splice arbitrary elements into a real library's `entries` array. Goes
    /// through JSONSerialization rather than the engine's own coder precisely so
    /// the test never depends on the code under test to build its fixture.
    private func libraryJSON(known: [LibraryEntry], extra: [Data]) throws -> Data {
        let base = try CouchJSON.encode(BoardLibrary(entries: known))
        var object = try JSONSerialization.jsonObject(with: base) as! [String: Any]
        var array = object["entries"] as! [Any]
        for element in extra {
            array.append(try JSONSerialization.jsonObject(with: element))
        }
        object["entries"] = array
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func elements(of library: Data) throws -> [Any] {
        let object = try JSONSerialization.jsonObject(with: library) as! [String: Any]
        return object["entries"] as! [Any]
    }

    // MARK: - unknown GameKind

    @Test func unknownGameKindIsQuarantinedNotFatal() throws {
        let known = [entry(0), entry(10), entry(20)]
        let future = FutureLibraryEntry(
            id: UUID(), kind: .timed(seconds: 300), game: Self.board,
            status: .inProgress, createdAt: t(30), updatedAt: t(30), solvedAt: nil
        )
        let data = try libraryJSON(known: known, extra: [try CouchJSON.encode(future)])

        // The whole point: this call used to throw, which cost the player all
        // four boards instead of the one it could not read.
        let library = try CouchJSON.decode(BoardLibrary.self, from: data)
        #expect(library.entries.count == 3)
        #expect(Set(library.entries.map(\.id)) == Set(known.map(\.id)))
        #expect(library.quarantined.count == 1)
    }

    /// Downgrade → upgrade: an old build reads a new build's library and writes
    /// it back; the new build must get its entry back, byte-equivalently.
    @Test func quarantinedEntrySurvivesAnOldBuildRewrite() throws {
        let future = FutureLibraryEntry(
            id: UUID(), kind: .timed(seconds: 300), game: Self.board,
            status: .solved, createdAt: t(30), updatedAt: t(40), solvedAt: t(40)
        )
        let data = try libraryJSON(known: [entry(0), entry(10), entry(20)],
                                   extra: [try CouchJSON.encode(future)])

        // The downgrade: decode, then persist again (an autosave is enough).
        let old = try CouchJSON.decode(BoardLibrary.self, from: data)
        let rewritten = try CouchJSON.encode(old)

        // The upgrade, two ways. First: the element is still in `entries`, so a
        // build that understands it decodes the array straight through.
        let array = try elements(of: rewritten)
        #expect(array.count == 4)
        let last = try JSONSerialization.data(withJSONObject: array[3])
        #expect(try CouchJSON.decode(FutureLibraryEntry.self, from: last) == future)

        // Second: straight out of the quarantine, which is the same value.
        let reread = try CouchJSON.decode(BoardLibrary.self, from: rewritten)
        #expect(reread.quarantined.count == 1)
        let raw = try reread.quarantined[0].rawJSON()
        #expect(try CouchJSON.decode(FutureLibraryEntry.self, from: raw) == future)

        // And the round trip is idempotent — quarantine does not accumulate.
        #expect(reread.entries.map(\.id) == old.entries.map(\.id))
        #expect(reread.quarantined == old.quarantined)
    }

    // MARK: - unknown Difficulty

    @Test func unknownDifficultyRawValueIsQuarantinedNotDestroyed() throws {
        // A `Difficulty` case this build does not have, written where the board's
        // proven puzzle carries it. Nothing here can repair that entry — the
        // requirement is only that it is not thrown away.
        var element = try JSONSerialization.jsonObject(
            with: try CouchJSON.encode(entry(30))
        ) as! [String: Any]
        var game = element["game"] as! [String: Any]
        var puzzle = game["puzzle"] as! [String: Any]
        puzzle["difficulty"] = "beyond"
        game["puzzle"] = puzzle
        element["game"] = game
        let future = try JSONSerialization.data(withJSONObject: element)

        let data = try libraryJSON(known: [entry(0), entry(10)], extra: [future])
        let library = try CouchJSON.decode(BoardLibrary.self, from: data)
        #expect(library.entries.count == 2)
        #expect(library.quarantined.count == 1)

        // Preserved verbatim: the unknown raw value is still in the rewrite.
        let rewritten = try CouchJSON.encode(library)
        let back = try elements(of: rewritten)
        #expect(back.count == 3)
        let recovered = (((back[2] as! [String: Any])["game"] as! [String: Any])["puzzle"]
            as! [String: Any])["difficulty"] as? String
        #expect(recovered == "beyond")
    }

    // MARK: - garbage

    @Test func garbageEntriesValueDecodesToAnEmptyLibrary() throws {
        // `entries` is not an array at all: nothing to preserve, and still no
        // throw — the blob survives as an empty library rather than vanishing.
        for blob in [#"{"entries":"nope"}"#, #"{"entries":{"a":1}}"#, #"{}"#, #"{"entries":null}"#] {
            let library = try CouchJSON.decode(BoardLibrary.self, from: Data(blob.utf8))
            #expect(library.entries.isEmpty, "\(blob)")
            #expect(library.quarantined.isEmpty, "\(blob)")
        }
        // A top level that is not even an object.
        let notAnObject = try CouchJSON.decode(BoardLibrary.self, from: Data("[1,2,3]".utf8))
        #expect(notAnObject.entries.isEmpty)
        #expect(notAnObject.quarantined.isEmpty)
    }

    @Test func garbageEntriesElementsAreQuarantinedNotDecoded() throws {
        // An array of numbers *is* an element list, so the covenant applies: no
        // entries, nothing thrown, and the elements are kept rather than eaten.
        let library = try CouchJSON.decode(BoardLibrary.self, from: Data(#"{"entries":[1,2,3]}"#.utf8))
        #expect(library.entries.isEmpty)
        #expect(library.quarantined.count == 3)
        let rewritten = try CouchJSON.encode(library)
        #expect(String(decoding: rewritten, as: UTF8.self) == #"{"entries":[1,2,3]}"#)
    }

    // MARK: - quarantine is invisible to the caps

    @Test func pruneCapsCountRealEntriesOnly() throws {
        // Two unreadable elements plus one real entry to seed from.
        let future = { (n: Int) in
            try CouchJSON.encode(FutureLibraryEntry(
                id: UUID(), kind: .timed(seconds: n), game: Self.board,
                status: .inProgress, createdAt: self.t(0), updatedAt: self.t(0), solvedAt: nil
            ))
        }
        let data = try libraryJSON(known: [entry(0)], extra: [try future(1), try future(2)])
        var library = try CouchJSON.decode(BoardLibrary.self, from: data)
        #expect(library.quarantined.count == 2)
        let quarantined = library.quarantined

        // The played cap, on its own (the total cap evicts solved boards before
        // in-progress ones, so the two have to be exercised separately).
        var played = library
        for i in 0..<(BoardLibrary.playedCap + 5) {
            let id = played.create(kind: .free(.gentle), game: Self.board, now: t(Double(i)))
            played.markSolved(id: id, at: t(Double(i)))
        }
        #expect(played.played.count == BoardLibrary.playedCap)
        #expect(played.quarantined == quarantined)

        // Blow past the total cap. If quarantine counted toward it, the cap
        // would bite two entries early and 58 would survive.
        for i in 1...(BoardLibrary.totalCap + 5) {
            _ = library.create(kind: .free(.gentle), game: Self.board, now: t(Double(i)))
        }
        #expect(library.entries.count == BoardLibrary.totalCap)
        #expect(library.quarantined == quarantined)

        // Delete never reaches into the quarantine either.
        library.delete(id: library.entries[0].id)
        #expect(library.quarantined == quarantined)

        // And the whole thing still round-trips with both halves intact.
        let rewritten = try CouchJSON.encode(library)
        let reread = try CouchJSON.decode(BoardLibrary.self, from: rewritten)
        #expect(reread.entries.map(\.id) == library.entries.map(\.id))
        #expect(reread.quarantined == quarantined)
    }

    // MARK: - the ordinary path is unchanged

    @Test func knownOnlyLibraryRoundTripsWithNoQuarantineKey() throws {
        let library = BoardLibrary(entries: [entry(0), entry(10), entry(20)])
        let data = try CouchJSON.encode(library)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // Exactly the shape 1.x wrote: one `entries` key, no sidecar.
        #expect(Array(object.keys) == ["entries"])
        let reread = try CouchJSON.decode(BoardLibrary.self, from: data)
        #expect(reread == library)
    }

    // MARK: - unknown top-level siblings of `entries`

    @Test func unknownTopLevelKeySurvivesARoundTrip() throws {
        var object = try JSONSerialization.jsonObject(
            with: CouchJSON.encode(BoardLibrary(entries: [entry(0), entry(10)]))
        ) as! [String: Any]
        object["schemaVersion"] = 2
        object["settings"] = ["autoPencil": true]
        let data = try JSONSerialization.data(withJSONObject: object)

        let library = try CouchJSON.decode(BoardLibrary.self, from: data)
        #expect(library.entries.count == 2)

        let rewritten = try CouchJSON.encode(library)
        let back = try JSONSerialization.jsonObject(with: rewritten) as! [String: Any]
        #expect(back["schemaVersion"] as? Int == 2)
        #expect((back["settings"] as? [String: Any])?["autoPencil"] as? Bool == true)
        #expect(back["entries"] != nil)
        // Idempotent: siblings do not multiply or migrate into `entries`.
        let reread = try CouchJSON.decode(BoardLibrary.self, from: rewritten)
        #expect(try CouchJSON.encode(reread) == rewritten)
    }

    /// A sibling is not implicated by a malformed board list, so it outlives one.
    @Test func unknownTopLevelKeySurvivesAnUnreadableEntriesValue() throws {
        let library = try CouchJSON.decode(
            BoardLibrary.self, from: Data(#"{"entries":"nope","schemaVersion":2}"#.utf8)
        )
        #expect(library.entries.isEmpty)
        #expect(library.quarantined.isEmpty)
        let back = try JSONSerialization.jsonObject(with: CouchJSON.encode(library)) as! [String: Any]
        #expect(back["schemaVersion"] as? Int == 2)
    }

    // MARK: - the tolerance stays off the launch path

    /// A library of decodable entries must come back out byte-identical, which
    /// is the observable half of the laziness in `RawLibraryEntry`: every entry
    /// is re-encoded from the *typed* value, so nothing is being rebuilt from an
    /// untyped tree. Building that tree eagerly cost a full 60-entry library
    /// 950 ms of a synchronous 800 ms cold-launch budget, against a 49 ms
    /// baseline — this test is the cheap standing guard on the shape of that
    /// fix, and any reintroduction of a raw-tree rewrite path has to come past
    /// it and past a fresh measurement.
    @Test func healthyLibraryRoundTripsByteIdentically() throws {
        var library = BoardLibrary(entries: [entry(0), entry(10), entry(20)])
        var solved = entry(30, kind: .daily(day: 500))
        solved.status = .solved
        solved.solvedAt = t(35)
        library.upsert(solved) // a nil-Optional key and a non-nil one, both covered

        let data = try CouchJSON.encode(library)
        let reread = try CouchJSON.decode(BoardLibrary.self, from: data)
        #expect(reread == library)
        #expect(try CouchJSON.encode(reread) == data)
        // A second lap, in case the first one silently normalised something.
        #expect(try CouchJSON.encode(CouchJSON.decode(BoardLibrary.self, from: data)) == data)
    }

    /// The same guarantee with a quarantined element in the blob: the elements
    /// this build *can* read still go out as typed values, and the one it cannot
    /// is the only thing carried as a tree.
    @Test func mixedLibraryRoundTripsByteIdenticallyAfterOneNormalisingPass() throws {
        let future = FutureLibraryEntry(
            id: UUID(), kind: .timed(seconds: 300), game: Self.board,
            status: .inProgress, createdAt: t(30), updatedAt: t(30), solvedAt: nil
        )
        let data = try libraryJSON(known: [entry(0), entry(10)],
                                   extra: [try CouchJSON.encode(future)])
        // The first write is where the quarantined element is normalised (sorted
        // keys, value-exact not byte-exact); every write after it is stable.
        let once = try CouchJSON.encode(CouchJSON.decode(BoardLibrary.self, from: data))
        let twice = try CouchJSON.encode(CouchJSON.decode(BoardLibrary.self, from: once))
        #expect(once == twice)
    }
}
