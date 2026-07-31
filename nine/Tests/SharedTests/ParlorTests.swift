// ParlorTests.swift — the whole of PRD-28's protocol, with no session in sight.
//
// Everything a parlor *is* — the invite, its two envelopes, the provenance
// guard, the roster and the reveal — is pure, so all of it tests here in
// microseconds. That is not an accident of layering: a FaceTime call cannot be
// placed between two simulators, so anything that needs a live group session to
// be checked is effectively unchecked, and the design pushes as much as possible
// out of that shadow.
import XCTest
@testable import NineShared
import NineEngine

final class ParlorTests: XCTestCase {

    private static let today = 9_400

    private func invite(
        seed: UInt64 = 0xDEAD_BEEF_1234_5678,
        difficulty: Difficulty = .steady,
        day: Int? = nil
    ) -> ParlorInvite {
        ParlorInvite(seed: seed, difficulty: difficulty, day: day)
    }

    // MARK: - Envelope one: Codable, for the SharePlay messenger

    func testAnInviteSurvivesACodableRoundTrip() throws {
        for candidate in [invite(), invite(difficulty: .abyss, day: Self.today)] {
            let data = try JSONEncoder().encode(candidate)
            XCTAssertEqual(try JSONDecoder().decode(ParlorInvite.self, from: data), candidate)
        }
    }

    /// The seed is a `UInt64` and JSON numbers are doubles in several parsers.
    /// A seed that loses its low bits composes a *different board*, silently, on
    /// one side of the call only — so the top of the range is pinned.
    func testASeedAtTheTopOfTheRangeSurvivesBothEnvelopes() throws {
        let candidate = invite(seed: UInt64.max)
        let decoded = try JSONDecoder().decode(
            ParlorInvite.self, from: try JSONEncoder().encode(candidate))
        XCTAssertEqual(decoded.seed, UInt64.max)
        XCTAssertEqual(ParlorInvite(properties: candidate.properties)?.seed, UInt64.max)
    }

    // MARK: - Envelope two: [String: String], for GKGameActivity.properties

    func testAnInviteSurvivesThePropertyDictionaryRoundTrip() {
        for candidate in [invite(), invite(difficulty: .gentle, day: Self.today - 3)] {
            XCTAssertEqual(ParlorInvite(properties: candidate.properties), candidate)
        }
    }

    func testThePropertyDictionaryIsAllStrings() {
        // The point of the test is the type GameKit will accept. If this ever
        // becomes `[String: Any]` the compiler says so here first.
        let properties: [String: String] = invite(day: Self.today).properties
        XCTAssertFalse(properties.isEmpty)
    }

    /// A malformed dictionary must produce **no invite**, never a wrong board.
    /// Every one of these arrives from another device, possibly a newer build.
    func testAMalformedPropertyDictionaryOpensNothing() {
        let good = invite(day: Self.today).properties
        XCTAssertNotNil(ParlorInvite(properties: good))

        var noSeed = good; noSeed[ParlorInvite.PropertyKey.seed] = nil
        XCTAssertNil(ParlorInvite(properties: noSeed), "no seed is no board")

        var badSeed = good; badSeed[ParlorInvite.PropertyKey.seed] = "not a number"
        XCTAssertNil(ParlorInvite(properties: badSeed))

        var negativeSeed = good; negativeSeed[ParlorInvite.PropertyKey.seed] = "-1"
        XCTAssertNil(ParlorInvite(properties: negativeSeed))

        var unknownBand = good; unknownBand[ParlorInvite.PropertyKey.band] = "labyrinth"
        XCTAssertNil(
            ParlorInvite(properties: unknownBand),
            "a band this build cannot compose is refused, not approximated")

        var noBand = good; noBand[ParlorInvite.PropertyKey.band] = nil
        XCTAssertNil(ParlorInvite(properties: noBand))

        XCTAssertNil(ParlorInvite(properties: [:]))
    }

    /// **The version is the guard, and unknown keys are not.**
    ///
    /// Strictness on keys is the obvious choice and it is wrong here:
    /// `GKGameActivityDefinition.defaultProperties` merges App-Store-Connect-owned
    /// keys into every activity, so a dictionary containing something we did not
    /// write is the *normal* case, not an attack. What actually protects the
    /// board is the version — a future build that adds `nine.rules` must bump it,
    /// which is the entire job of a wire version.
    func testAnUnknownKeyIsIgnoredAndAFutureVersionIsRefused() {
        var extra = invite().properties
        extra["some.asc.default"] = "whatever"
        XCTAssertEqual(
            ParlorInvite(properties: extra), invite(),
            "a key we did not write is not a reason to refuse a board")

        var future = invite().properties
        future[ParlorInvite.PropertyKey.version] = "\(ParlorInvite.wireVersion + 1)"
        XCTAssertNil(
            ParlorInvite(properties: future),
            "a newer wire may mean something this build cannot see")

        var unversioned = invite().properties
        unversioned[ParlorInvite.PropertyKey.version] = nil
        XCTAssertNil(ParlorInvite(properties: unversioned), "an unstamped wire is not ours")
    }

    /// A day is optional, and its absence is not an error.
    func testAFreeInviteCarriesNoDayKeyAtAll() {
        let properties = invite(day: nil).properties
        XCTAssertNil(properties[ParlorInvite.PropertyKey.day])
        XCTAssertEqual(ParlorInvite(properties: properties)?.day, nil)
    }

    // MARK: - The provenance guard (PRD-28 §3)

    func testTodaysDailyOpensAsTodaysDaily() {
        XCTAssertEqual(
            invite(day: Self.today).opens(today: Self.today), .daily(day: Self.today))
    }

    func testEveryOtherInviteOpensAFreeBoard() {
        // Yesterday, or a friend in a timezone a day ahead, or no day at all.
        // A streak is a record of days you turned up; none of these are today.
        XCTAssertEqual(
            invite(difficulty: .sharp, day: Self.today - 1).opens(today: Self.today),
            .free(.sharp),
            "a past daily must never take streak credit for a day you did not play")
        XCTAssertEqual(
            invite(difficulty: .sharp, day: Self.today + 1).opens(today: Self.today),
            .free(.sharp))
        XCTAssertEqual(
            invite(difficulty: .nocturne, day: nil).opens(today: Self.today),
            .free(.nocturne))
    }

    // MARK: - Presence

    func testPresenceClampsAFillItCannotHaveHad() {
        XCTAssertEqual(ParlorPresence(fill: -4, done: false).fill, 0)
        XCTAssertEqual(ParlorPresence(fill: 900, done: false).fill, ParlorPresence.maxFill)
    }

    func testPresenceRoundTrips() throws {
        let presence = ParlorPresence(fill: 17, done: false)
        let data = try JSONEncoder().encode(presence)
        XCTAssertEqual(try JSONDecoder().decode(ParlorPresence.self, from: data), presence)
    }

    /// Tolerant, because this arrives from another device and a throw is a
    /// dropped participant rather than a dropped field.
    func testPresenceDecodesTolerantly() throws {
        let wrongTypes = Data(#"{"fill":"twelve","done":"yes"}"#.utf8)
        let decoded = try JSONDecoder().decode(ParlorPresence.self, from: wrongTypes)
        XCTAssertEqual(decoded, ParlorPresence(fill: 0, done: false))
        XCTAssertEqual(
            try JSONDecoder().decode(ParlorPresence.self, from: Data("{}".utf8)),
            ParlorPresence(fill: 0, done: false))
    }

    // MARK: - The seal on the wire (PRD-28 §4)

    /// **The payload half of the seal.** PRD-30's lesson, applied one framework
    /// over: a negative requirement erodes without anything going red, so it is
    /// checked against the *encoded shape* rather than against a comment.
    ///
    /// The source half — that no parlor surface renders a time outside the
    /// revealed branch — is `Tests/EngineTests/ParlorSealTests.swift`. One
    /// without the other is exactly the gap `Text(_:style: .timer)` walked
    /// through in PRD-30: a view can draw a clock the payload never carried.
    func testPresenceCarriesNoClockAndCanNotGrowOne() throws {
        let encoded = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(ParlorPresence(fill: 40, done: true)))
        let keys = Set((encoded as? [String: Any] ?? [:]).keys)

        XCTAssertEqual(keys, ["fill", "done"], "the wire is two facts and stays two facts")

        let forbidden = ["time", "second", "elapsed", "duration", "score", "rank",
                         "name", "player", "date", "at", "clock", "best", "fast"]
        for key in keys {
            let lowered = key.lowercased()
            for word in forbidden {
                XCTAssertFalse(
                    lowered.contains(word),
                    "ParlorPresence.\(key) looks like it carries \(word) — nobody's time is "
                        + "anybody's business until everybody is done (PRD-28 §4)")
            }
        }

        // The Mirror catches a property added but not encoded, which would be a
        // time held in memory on the receiving side and one `encode` from the
        // wire.
        XCTAssertEqual(
            Set(Mirror(reflecting: ParlorPresence(fill: 0, done: false)).children
                .compactMap(\.label)),
            ["fill", "done"])
    }

    // MARK: - The room

    // Ordered A1 < B0 < C0 by `uuidString`, so "self first, then by id" and
    // "by id" are distinguishable outcomes rather than the same one.
    private let alice = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let bob = UUID(uuidString: "00000000-0000-0000-0000-0000000000B0")!
    private let carol = UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!

    private func room(fillable: Int = 51) -> ParlorRoom {
        ParlorRoom(me: alice, fillable: fillable)
    }

    func testAFreshRoomIsEmptyAndRevealsNothing() {
        let room = self.room()
        XCTAssertTrue(room.members.isEmpty)
        XCTAssertFalse(room.isComplete)
        XCTAssertFalse(room.isShared)
    }

    func testFillIsAFractionOfALocallyKnownDenominator() {
        var room = self.room(fillable: 51)
        room.update(ParlorPresence(fill: 17, done: false), from: bob)
        XCTAssertEqual(room.members.first?.fraction ?? 0, 1.0 / 3.0, accuracy: 0.0001)
    }

    /// The wire never carries a denominator, so a room told nothing about the
    /// board must not divide by it.
    func testAnUnknownDenominatorIsZeroRatherThanInfinite() {
        var room = self.room(fillable: 0)
        room.update(ParlorPresence(fill: 9, done: false), from: bob)
        XCTAssertEqual(room.members.first?.fraction ?? -1, 0)
    }

    func testOverfillIsClampedToOne() {
        var room = self.room(fillable: 20)
        room.update(ParlorPresence(fill: 99, done: true), from: bob)
        XCTAssertEqual(room.members.first?.fraction ?? 0, 1)
    }

    /// Stable on every device and every redraw: you first, then by id. A row
    /// that re-orders as people fill cells is a leaderboard with soft edges.
    func testOrderingIsSelfFirstThenByIdAndNeverByProgress() {
        var room = self.room()
        room.update(ParlorPresence(fill: 1, done: false), from: carol)
        room.update(ParlorPresence(fill: 50, done: false), from: bob)
        room.update(ParlorPresence(fill: 3, done: false), from: alice)

        XCTAssertEqual(room.members.map(\.id), [alice, bob, carol])
        XCTAssertEqual(room.members.map(\.isMe), [true, false, false])

        // Progress moves; order does not.
        room.update(ParlorPresence(fill: 51, done: true), from: carol)
        XCTAssertEqual(room.members.map(\.id), [alice, bob, carol])
    }

    func testTheLatestPresenceFromAParticipantWins() {
        var room = self.room()
        room.update(ParlorPresence(fill: 4, done: false), from: bob)
        room.update(ParlorPresence(fill: 9, done: false), from: bob)
        XCTAssertEqual(room.members.count, 1)
        XCTAssertEqual(room.members.first?.presence.fill, 9)
    }

    // MARK: - The reveal (PRD-28 §4.1)

    func testARoomIsCompleteOnlyWhenEveryMemberIsDone() {
        var room = self.room()
        room.update(ParlorPresence(fill: 51, done: true), from: alice)
        XCTAssertTrue(room.isComplete, "a parlor of one completes when its one member does")

        room.update(ParlorPresence(fill: 20, done: false), from: bob)
        XCTAssertFalse(room.isComplete)

        room.update(ParlorPresence(fill: 51, done: true), from: bob)
        XCTAssertTrue(room.isComplete)
    }

    /// A parlor of people who have all finished, plus one who hung up, is a
    /// parlor that is finished. A departure can *complete* a room.
    func testLeavingCanCompleteARoom() {
        var room = self.room()
        room.update(ParlorPresence(fill: 51, done: true), from: alice)
        room.update(ParlorPresence(fill: 12, done: false), from: bob)
        XCTAssertFalse(room.isComplete)

        room.retain([alice])
        XCTAssertTrue(room.isComplete)
        XCTAssertEqual(room.members.map(\.id), [alice])
    }

    func testRetainingNobodyEmptiesTheRoomAndCompletesNothing() {
        var room = self.room()
        room.update(ParlorPresence(fill: 51, done: true), from: alice)
        room.retain([])
        XCTAssertTrue(room.members.isEmpty)
        XCTAssertFalse(room.isComplete, "an empty room has nothing to reveal")
    }

    /// **The load-bearing test of this PRD.** A finish that arrives before the
    /// room completes is held, not shown: `Member.finish` is nil, so no view can
    /// draw a time it should not have. The rule is on the type, not on the view.
    func testAFinishIsInvisibleUntilTheRoomCompletes() {
        var room = self.room()
        room.update(ParlorPresence(fill: 51, done: true), from: alice)
        room.update(ParlorPresence(fill: 12, done: false), from: bob)
        room.record(ParlorFinish(seconds: 214, packed: Data([1, 2, 3])), from: alice)

        XCTAssertFalse(room.isComplete)
        XCTAssertNil(
            room.members.first(where: { $0.id == self.alice })?.finish,
            "nobody's time is anybody's business until everybody is done")

        room.update(ParlorPresence(fill: 51, done: true), from: bob)
        room.record(ParlorFinish(seconds: 190, packed: Data([4])), from: bob)

        XCTAssertTrue(room.isComplete)
        XCTAssertEqual(room.members.compactMap(\.finish?.seconds), [214, 190])
    }

    /// The revealed order is the dots' order, so the fastest solve is wherever
    /// it happened to be all along. Sorting by time here is how this feature
    /// becomes a leaderboard in one line.
    func testTheRevealedOrderIsTheDotOrderAndNotTheFastestFirst() {
        var room = self.room()
        for (id, seconds) in [(alice, 400), (bob, 100), (carol, 250)] {
            room.update(ParlorPresence(fill: 51, done: true), from: id)
            room.record(ParlorFinish(seconds: seconds, packed: Data()), from: id)
        }
        XCTAssertEqual(room.members.compactMap(\.finish?.seconds), [400, 100, 250])
    }

    /// A device may send its own finish only once the room agrees it is time —
    /// which is the same predicate on every device, so everyone's number
    /// arrives at once and nobody is waiting on a host.
    func testMayPublishMyFinishIsExactlyTheCompletionPredicate() {
        var room = self.room()
        room.update(ParlorPresence(fill: 30, done: false), from: alice)
        XCTAssertFalse(room.mayPublishFinish)
        room.update(ParlorPresence(fill: 51, done: true), from: alice)
        XCTAssertTrue(room.mayPublishFinish)
        room.update(ParlorPresence(fill: 1, done: false), from: bob)
        XCTAssertFalse(room.mayPublishFinish)
    }

    func testASoloRoomIsNotSharedAndAPairIs() {
        var room = self.room()
        room.update(ParlorPresence(fill: 3, done: false), from: alice)
        XCTAssertFalse(room.isShared)
        room.update(ParlorPresence(fill: 3, done: false), from: bob)
        XCTAssertTrue(room.isShared)
    }
}
