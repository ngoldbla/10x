// ChannelLedgerTests — the per-channel streak and stats slice, and the assertion
// that PRD-24's headline safety claim is structural rather than aspirational.
//
// The requirement is "dailies one-per-day per channel **so the classic streak is
// never diluted**". Most of this file is about that sentence, and the tests come
// in two flavours which is worth naming because they are doing different jobs:
//
//   • The ones that check the *type* (`theClassicChannelHasNoLedgerSlot`,
//     `onlyVariantChannelsCanBeRecorded`) assert that the dangerous call cannot
//     be written. They would be redundant if a compiler error were a test result,
//     and they exist because it is not: someone widening `Channel.Ledgered` to
//     include classic would make the dilution bug reachable again, and these are
//     what fail when they do.
//   • The ones that check *behaviour* assert the ledger is a faithful per-channel
//     copy of the classic machinery — PRD-13's grace, the archive provenance
//     guard, the capacity trim — without having re-implemented any of it.
import Testing
import Foundation
import CouchCore
@testable import NineEngine

@Suite("ChannelLedger")
struct ChannelLedgerTests {

    private func day(_ n: Int) -> Int { 20_600 + n }

    private func record(_ seconds: TimeInterval, points: Int = 100) -> SolveRecord {
        SolveRecord(
            date: Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds),
            difficulty: .steady, isDaily: true, seconds: seconds, points: points)
    }

    // MARK: - The dilution proof, as a type fact

    /// The whole safety argument in one assertion. `ChannelLedger`'s mutating API
    /// is keyed by `Channel.Ledgered`, and there is no value of that type naming
    /// classic — so "write a classic streak into the channel ledger" is not a call
    /// that exists. If this ever fails, the dilution bug has become reachable.
    @Test func theClassicChannelHasNoLedgerSlot() {
        #expect(Channel.classic.ledgered == nil)
        #expect(Channel.Ledgered.allCases.map(\.rawValue) == ["thermo", "killer"])
        #expect(!Channel.Ledgered.allCases.contains { $0.channel == .classic })
        // And every ledgered channel maps to a variant the engine can actually
        // supply, or the page would exist with nothing behind it.
        for channel in Channel.Ledgered.allCases {
            #expect(VariantTier.steady.band(for: channel.variant) != nil)
        }
    }

    /// Page order is a product decision (Classic, then Thermo, then Killer — the
    /// order they ship in and of increasing strangeness), and the raw values are
    /// frozen because they are persisted inside `GameKind.channel` and are the
    /// localization identity.
    @Test func channelPageOrderAndRawValuesAreFrozen() {
        #expect(Channel.allCases.map(\.rawValue) == ["classic", "thermo", "killer"])
        #expect(Channel.classic.variant == .classic)
        #expect(Channel.thermo.variant == .thermo)
        #expect(Channel.killer.variant == .killer)
    }

    /// A channel that has never been played reads as an empty state rather than
    /// nil, so a shelf page never has to branch on "has this been opened" — one
    /// designed zero-state per surface is PRD-34's rule.
    @Test func anUnplayedChannelReadsAsEmptyRatherThanAbsent() {
        let ledger = ChannelLedger()
        #expect(ledger.state(for: .thermo).history.records.isEmpty)
        #expect(ledger.displayedStreak(for: .thermo, today: day(0)) == 0)
        #expect(!ledger.hasSolved(.thermo, day: day(0)))
        #expect(ledger.played.isEmpty)
    }

    // MARK: - Per-channel independence

    /// Two channels' streaks are genuinely separate. This is the behavioural half
    /// of the dilution claim: solving thermo every day for a week leaves killer at
    /// zero, and vice versa.
    @Test func channelsDoNotShareAStreak() {
        var ledger = ChannelLedger()
        for n in 0...6 {
            ledger.record(record(60), on: .thermo, day: day(n), openedOn: day(n))
        }
        #expect(ledger.displayedStreak(for: .thermo, today: day(6)) == 7)
        #expect(ledger.displayedStreak(for: .killer, today: day(6)) == 0)
        #expect(ledger.state(for: .thermo).history.records.count == 7)
        #expect(ledger.state(for: .killer).history.records.isEmpty)
        #expect(ledger.played == [.thermo])
    }

    /// One per day per channel: recording the same day twice does not double the
    /// streak. `StreakState.recordCompletion` already no-ops a same-day repeat, and
    /// this pins that the ledger routes through it rather than counting itself.
    @Test func asecondSolveOnTheSameDayDoesNotExtendTheStreak() {
        var ledger = ChannelLedger()
        ledger.record(record(60), on: .thermo, day: day(3), openedOn: day(3))
        ledger.record(record(45), on: .thermo, day: day(3), openedOn: day(3))
        #expect(ledger.displayedStreak(for: .thermo, today: day(3)) == 1)
        // Both solves are still *recorded* — the streak is one per day, the stats
        // slice is every solve.
        #expect(ledger.state(for: .thermo).history.records.count == 2)
    }

    /// PRD-13's grace, inherited whole rather than re-derived. One missed day
    /// bridges; two always break. There is no grace code in `ChannelLedger`.
    @Test func perChannelGraceIsPRD13sRuleUnchanged() {
        var ledger = ChannelLedger()
        ledger.record(record(60), on: .killer, day: day(1), openedOn: day(1))
        ledger.record(record(60), on: .killer, day: day(2), openedOn: day(2))
        // Skip day 3, solve day 4 — the bridge.
        ledger.record(record(60), on: .killer, day: day(4), openedOn: day(4))
        #expect(ledger.displayedStreak(for: .killer, today: day(4)) == 3)
        #expect(ledger.state(for: .killer).streak.standsOnGrace)

        // Non-stacking: a second bridge immediately after cannot fire.
        var twice = ChannelLedger()
        twice.record(record(60), on: .killer, day: day(1), openedOn: day(1))
        twice.record(record(60), on: .killer, day: day(3), openedOn: day(3))
        twice.record(record(60), on: .killer, day: day(5), openedOn: day(5))
        #expect(twice.displayedStreak(for: .killer, today: day(5)) == 1)
    }

    /// The archive provenance guard, also inherited. A board *dated* last week but
    /// opened today must not extend today's streak — `openedOn` is threaded
    /// through to `StreakState` rather than re-checked here.
    @Test func anArchiveSolveDoesNotExtendAChannelStreak() {
        var ledger = ChannelLedger()
        ledger.record(record(60), on: .thermo, day: day(2), openedOn: day(9))
        #expect(ledger.displayedStreak(for: .thermo, today: day(9)) == 0)
        #expect(!ledger.hasSolved(.thermo, day: day(2)))
    }

    /// Free play on a channel counts for the stats slice and not for the streak.
    @Test func freePlayFeedsTheStatsSliceAndNotTheStreak() {
        var ledger = ChannelLedger()
        ledger.recordFreePlay(record(90), on: .thermo)
        #expect(ledger.state(for: .thermo).history.records.count == 1)
        #expect(ledger.displayedStreak(for: .thermo, today: day(0)) == 0)
    }

    /// The stats slice is `SolveHistory`'s existing aggregation, per channel, with
    /// nothing re-derived. This is why per-channel stats were nearly free.
    @Test func theStatsSliceIsSolveHistorysOwnAggregation() {
        var ledger = ChannelLedger()
        for (index, seconds) in [300.0, 200.0, 400.0].enumerated() {
            ledger.record(record(seconds, points: 50), on: .thermo,
                          day: day(index), openedOn: day(index))
        }
        let slice = ledger.state(for: .thermo).history
        #expect(slice.totalPoints == 150)
        #expect(slice.count(of: .steady) == 3)
        #expect(slice.bestSeconds(for: .steady) == 200)
        #expect(slice.averageSeconds(for: .steady) == 300)
    }

    // MARK: - Capacity, the KVS budget

    /// A channel keeps 200 solves against classic's 1000, and classic's number is
    /// untouched. This is a `NSUbiquitousKeyValueStore` budget: the store gives
    /// the whole app 1 MB and already carries ~150 KB, so two channels at
    /// classic's capacity would add ~220 KB for records nobody has made.
    @Test func aChannelHistoryIsCappedWellBelowClassics() {
        #expect(ChannelLedger.historyCapacity == 200)
        #expect(SolveHistory.capacity == 1000)

        var ledger = ChannelLedger()
        for n in 0..<(ChannelLedger.historyCapacity + 25) {
            ledger.recordFreePlay(record(Double(n)), on: .killer)
        }
        #expect(ledger.state(for: .killer).history.records.count
                    == ChannelLedger.historyCapacity)
        // Newest-first is a contract `SolveHistory` states; the trim takes the
        // tail, so the most recent solve must still be at the head.
        let newest = ledger.state(for: .killer).history.records.first
        #expect(newest?.seconds == Double(ChannelLedger.historyCapacity + 24))
    }

    /// Classic's own `record` is byte-identical — the capacity parameter defaults
    /// to `Self.capacity`, so no classic caller changed behaviour.
    @Test func classicHistoryStillKeepsAThousand() {
        var history = SolveHistory()
        for n in 0..<5 { history.record(record(Double(n))) }
        #expect(history.records.count == 5)
        var capped = SolveHistory()
        for n in 0..<5 { capped.record(record(Double(n)), capacity: 3) }
        #expect(capped.records.count == 3)
    }

    // MARK: - The persistence covenant

    @Test func aLedgerRoundTrips() throws {
        var ledger = ChannelLedger()
        ledger.record(record(120), on: .thermo, day: day(1), openedOn: day(1))
        ledger.record(record(240), on: .killer, day: day(2), openedOn: day(2))
        let data = try CouchJSON.encode(ledger)
        let back = try CouchJSON.decode(ChannelLedger.self, from: data)
        #expect(back == ledger)
        #expect(back.displayedStreak(for: .thermo, today: day(1)) == 1)
        #expect(back.state(for: .killer).history.records.count == 1)
    }

    /// `CouchStored` discards the whole blob when a decode throws, so nothing in
    /// the decode may throw — including on input that is not remotely a ledger.
    @Test func aLedgerIsNeverDiscardedWholesale() throws {
        for json in ["{}", "[]", "null", #"{"states": 7}"#, #"{"states": {"thermo": 3}}"#] {
            let back = try CouchJSON.decode(ChannelLedger.self, from: Data(json.utf8))
            #expect(back.state(for: .thermo).history.records.isEmpty)
        }
    }

    /// One unreadable channel must not take the others with it — `BoardLibrary`'s
    /// element-level rule, one blob later.
    @Test func anUnreadableChannelIsQuarantinedNotFatal() throws {
        var ledger = ChannelLedger()
        ledger.record(record(60), on: .thermo, day: day(1), openedOn: day(1))
        let data = try CouchJSON.encode(ledger)
        var tree = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var states = try #require(tree["states"] as? [String: Any])
        states["killer"] = ["streak": "this is not a streak"]
        tree["states"] = states
        let mangled = try JSONSerialization.data(withJSONObject: tree)

        let back = try CouchJSON.decode(ChannelLedger.self, from: mangled)
        // Thermo survived, which is the point.
        #expect(back.displayedStreak(for: .thermo, today: day(1)) == 1)
        // And killer reads as empty rather than as a fabricated streak.
        #expect(back.displayedStreak(for: .killer, today: day(1)) == 0)
    }

    /// A channel a future build invents is held verbatim and handed back, not
    /// dropped — the streak inside it belongs to the player even though this build
    /// cannot address it. Never delete what you cannot read.
    @Test func aFutureChannelSurvivesARewrite() throws {
        var ledger = ChannelLedger()
        ledger.record(record(60), on: .thermo, day: day(1), openedOn: day(1))
        let data = try CouchJSON.encode(ledger)
        var tree = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var states = try #require(tree["states"] as? [String: Any])
        states["sandwich"] = ["streak": ["current": 12, "best": 30], "history": ["records": []]]
        tree["states"] = states
        let incoming = try JSONSerialization.data(withJSONObject: tree)

        // This build reads it, cannot address it, and writes it back out.
        let back = try CouchJSON.decode(ChannelLedger.self, from: incoming)
        #expect(back.played == [.thermo])
        let rewritten = try CouchJSON.encode(back)
        let after = try #require(
            try JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        let afterStates = try #require(after["states"] as? [String: Any])
        let sandwich = try #require(afterStates["sandwich"] as? [String: Any])
        let streak = try #require(sandwich["streak"] as? [String: Any])
        #expect(streak["current"] as? Int == 12)
        #expect(streak["best"] as? Int == 30)
    }

    /// An unknown sibling of `states` is carried, so an older build's rewrite does
    /// not strip a newer build's key. Every other blob in this app does this and
    /// this one must too.
    @Test func anUnknownTopLevelSiblingSurvivesARoundTrip() throws {
        let json = #"{"leaderboardEpoch": 4, "states": {}}"#
        let ledger = try CouchJSON.decode(ChannelLedger.self, from: Data(json.utf8))
        let out = try CouchJSON.encode(ledger)
        let tree = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        #expect(tree["leaderboardEpoch"] as? Int == 4)
    }

    /// The siblings are read before `states`, so they survive even when `states`
    /// itself is unreadable — `BoardLibrary.init(from:)`'s ordering, for its
    /// reason.
    @Test func siblingsSurviveAnUnreadableStatesKey() throws {
        let json = #"{"leaderboardEpoch": 9, "states": 12}"#
        let ledger = try CouchJSON.decode(ChannelLedger.self, from: Data(json.utf8))
        let out = try CouchJSON.encode(ledger)
        let tree = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        #expect(tree["leaderboardEpoch"] as? Int == 9)
    }

    /// An unknown channel raw value decodes as classic rather than throwing — and
    /// the entry carrying it is quarantined by `BoardLibrary` anyway, because its
    /// `GameKind` will not type either.
    @Test func anUnknownChannelRawValueDecodesAsClassic() throws {
        let back = try CouchJSON.decode(Channel.self, from: Data(#""sandwich""#.utf8))
        #expect(back == .classic)
        let broken = try CouchJSON.decode(Channel.self, from: Data("7".utf8))
        #expect(broken == .classic)
    }
}
