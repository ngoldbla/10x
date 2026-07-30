// ChannelLedger.swift — each channel's own streak and its own solves, in their
// own blob (`nine.channels`), and the structural reason the classic streak
// cannot be diluted by a variant.
//
// PROGRAM-2.0 §Pillar B asks for "each with its own Today, streak, stats slice
// and leaderboard; dailies one-per-day per channel **so the classic streak is
// never diluted**". That last clause is the requirement, and a comment stating it
// survives exactly until the first refactor. Three mechanisms make it a property
// of the code instead:
//
//   1. **`nine.streak`, `nine.history` and `nine.archive` are untouched and
//      classic-only.** Nothing in this file reads or writes them. The dilution
//      question has no code path to travel down.
//   2. **`Channel.Ledgered` has no classic case.** Every mutating entry point
//      below is keyed by it, so "record a classic solve into the channel ledger"
//      is not a call that can be written, rather than one that is guarded.
//      `Channel` itself has three cases because the *shelf* has three pages —
//      the two axes are deliberately different types.
//   3. **The ledger records a solve atomically.** `record(_:on:day:openedOn:)`
//      moves the streak and the history together, so a caller cannot update one
//      and forget the other, which is the shape of every streak bug this repo
//      has had (PRD-13 found a third copy of the streak rule in `BoardIntents`).
//
// **`StreakState` and `SolveHistory` are reused as value types, once per
// channel.** That is not a shortcut, it is the point: per-channel grace is
// PRD-13's non-stacking rule *exactly*, per-channel stats are
// `count(of:)`/`bestSeconds(for:)`/`averageSeconds(for:)`/`trend(window:)`
// exactly, and neither had to be re-derived or kept in step. The one thing that
// does differ is capacity — see `historyCapacity`.
import Foundation
import CouchCore

/// One page of the home shelf. Page order is `allCases` order, and it is a
/// product decision rather than an alphabetical accident: Classic first because
/// it is what the app is, then Thermo, then Killer, which is the order they
/// ship in and the order of increasing strangeness.
///
/// The raw values are **frozen** — they are persisted inside `GameKind.channel`,
/// they key `ChannelLedger`, and they are the localization identity
/// (`channel.<raw>.title`), the same contract `Difficulty` and `Technique` raw
/// values carry.
public enum Channel: String, CaseIterable, Sendable, Codable, Hashable {
    case classic, thermo, killer

    /// The engine ruleset this channel plays.
    public var variant: Variant {
        switch self {
        case .classic: return .classic
        case .thermo: return .thermo
        case .killer: return .killer
        }
    }

    /// The channels that keep their **own** streak and history in
    /// `nine.channels`. There is deliberately no value of this type naming
    /// classic: classic's records are the top-level blobs and must stay there, so
    /// making that a type-level fact is what stops a variant solve reaching them.
    public enum Ledgered: String, CaseIterable, Sendable, Codable, Hashable {
        case thermo, killer

        public var channel: Channel {
            switch self {
            case .thermo: return .thermo
            case .killer: return .killer
            }
        }

        public var variant: Variant { channel.variant }
    }

    /// Non-nil for every channel but classic.
    public var ledgered: Ledgered? {
        switch self {
        case .classic: return nil
        case .thermo: return .thermo
        case .killer: return .killer
        }
    }

    /// Decode tolerantly, for the same reason `Variant` does: a channel this
    /// build has never heard of must not take the blob with it. An unknown
    /// channel reads as classic — the only channel every build can render — and
    /// the entry carrying it is quarantined by `BoardLibrary` anyway, because its
    /// `GameKind` will not type either.
    public init(from decoder: any Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? "classic"
        self = Channel(rawValue: raw) ?? .classic
    }
}

/// One channel's whole record: the streak it holds and the solves it has made.
///
/// No `carriedTopLevel` here, and that is deliberate rather than an omission.
/// This type is an *element* of `ChannelLedger`, and the covenant protects
/// elements by quarantining them whole (`BoardLibrary`'s rule, and
/// `SolveHistory`'s): a state this build cannot read is held verbatim by the
/// container above rather than field-preserved here. Field-level preservation is
/// the shape that measured 1515 ms against a 49 ms baseline.
public struct ChannelState: Sendable, Codable, Equatable {

    /// This channel's streak, with PRD-13's grace rule and non-stacking bridge
    /// inherited whole.
    public var streak: StreakState
    /// This channel's solves — the stats slice, and nothing classic's.
    public var history: SolveHistory

    public init(streak: StreakState = StreakState(), history: SolveHistory = SolveHistory()) {
        self.streak = streak
        self.history = history
    }

    /// Tolerant: a missing or unreadable half yields an empty one rather than
    /// throwing, because throwing out of here discards every channel.
    public init(from decoder: any Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            streak = StreakState()
            history = SolveHistory()
            return
        }
        streak = (try? c.decode(StreakState.self, forKey: .streak)) ?? StreakState()
        history = (try? c.decode(SolveHistory.self, forKey: .history)) ?? SolveHistory()
    }
}

/// Every channel's state, in one `CouchStored` blob at `nine.channels`.
///
/// `cloudSynced`, like `nine.streak` and `nine.history` and for the same reason:
/// a streak the player earned on one device is a streak on all of them, and the
/// payload is small enough for KVS. Its budget is bounded by `historyCapacity`
/// rather than by hope — see there.
public struct ChannelLedger: Sendable, Codable, Equatable {

    /// How many solves a channel keeps, against `SolveHistory.capacity`'s 1000
    /// for classic.
    ///
    /// **This number is a KVS budget, not a preference.** `NSUbiquitousKeyValueStore`
    /// gives the whole app 1 MB, and it already carries `nine.history` (1000
    /// records ≈ 110 KB), `nine.archive` (~22 KB/decade), `nine.coachProgress`,
    /// `nine.hand`, `nine.streak`, `nine.appearance` and `nine.graceSeen`. Two
    /// channels at classic's capacity would add ~220 KB for records nobody has
    /// made yet. At 200 the two channels cost ~44 KB together, and 200 dailies is
    /// over six months of playing a channel every single day — past which the
    /// aggregate queries the stats slice actually asks (`trend(window: 20)`,
    /// best, average, count) are unaffected by the tail.
    public static let historyCapacity = 200

    /// Keyed by `Channel.Ledgered.rawValue`. A dictionary rather than an array
    /// because the reads are all by channel and there is no order to keep;
    /// `CouchJSON` sorts keys, so the encoding is stable anyway.
    private var states: [String: ChannelState]

    /// States this build could not decode, held verbatim. Same contract as
    /// `BoardLibrary.quarantined` and `SolveHistory.quarantined`: never delete
    /// what you cannot read.
    private var quarantined: [String: RawJSON]

    /// Unknown siblings of `states`, carried so an older build's rewrite does not
    /// strip a newer build's key.
    private var carriedTopLevel: [String: RawJSON]

    public init() {
        states = [:]
        quarantined = [:]
        carriedTopLevel = [:]
    }

    /// `==` is the states only. The carried and quarantined trees are an encoding
    /// detail, not identity — `BoardLibrary`'s rule, and every test builds a
    /// ledger by hand.
    public static func == (lhs: ChannelLedger, rhs: ChannelLedger) -> Bool {
        lhs.states == rhs.states
    }

    // MARK: - Reading

    /// This channel's state, empty if it has never been played. Total by design:
    /// a shelf page that has to branch on "has this channel ever been opened" is
    /// a shelf page with two zero-states, and PRD-34's rule is one designed
    /// zero-state per surface.
    public func state(for channel: Channel.Ledgered) -> ChannelState {
        states[channel.rawValue] ?? ChannelState()
    }

    /// The streak to show on this channel's page, with PRD-13's grace applied —
    /// the identical call the classic chip makes, on a different streak.
    public func displayedStreak(for channel: Channel.Ledgered, today: Int) -> Int {
        state(for: channel).streak.displayedStreak(today: today)
    }

    /// Whether this channel's daily for `day` is already done. One per day per
    /// channel, which is the whole "never diluted" requirement: this asks
    /// `StreakState.hasCompleted` on the *channel's* streak, and there is no
    /// argument that could make it ask classic's.
    public func hasSolved(_ channel: Channel.Ledgered, day: Int) -> Bool {
        state(for: channel).streak.hasCompleted(day: day)
    }

    /// Every channel that has ever been played, in page order.
    public var played: [Channel.Ledgered] {
        Channel.Ledgered.allCases.filter { states[$0.rawValue] != nil }
    }

    // MARK: - Writing

    /// Record a solve on a channel: its streak and its history move **together**,
    /// or neither does.
    ///
    /// `openedOn` is the provenance guard `StreakState.recordCompletion(day:openedOn:)`
    /// already enforces — an archive board opened today but dated last Tuesday
    /// must not extend a streak — and it is threaded through rather than
    /// re-derived so there is exactly one copy of that rule.
    public mutating func record(
        _ record: SolveRecord, on channel: Channel.Ledgered, day: Int, openedOn: Int
    ) {
        var state = self.state(for: channel)
        state.streak.recordCompletion(day: day, openedOn: openedOn)
        state.history.record(record, capacity: Self.historyCapacity)
        states[channel.rawValue] = state
    }

    /// Record a solve that earns no streak — a free-play board on this channel,
    /// which is not a daily and must not move the count.
    public mutating func recordFreePlay(_ record: SolveRecord, on channel: Channel.Ledgered) {
        var state = self.state(for: channel)
        state.history.record(record, capacity: Self.historyCapacity)
        states[channel.rawValue] = state
    }

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey { case states }

    /// Nothing in here throws — `CouchStored` discards the whole blob when a
    /// decode does, and this one holds every channel streak the player has.
    ///
    /// Two passes, and the second almost never runs: `[String: ChannelState]`
    /// decodes as a unit, so one unreadable channel would take the others with
    /// it, but the per-element walk that fixes that is the shape whose
    /// `LibraryEntry` version measured 1515 ms. `ReplayVault`'s pattern exactly —
    /// fast path first, quarantine only on the blob that needs it.
    public init(from decoder: any Decoder) throws {
        states = [:]
        quarantined = [:]
        carriedTopLevel = [:]
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }

        // Siblings first and unconditionally, so they survive an unreadable
        // `states` — `BoardLibrary.init(from:)`'s ordering, for its reason.
        if let anyKey = try? decoder.container(keyedBy: RawJSON.RawKey.self) {
            for key in anyKey.allKeys where key.stringValue != CodingKeys.states.stringValue {
                carriedTopLevel[key.stringValue] =
                    (try? anyKey.decode(RawJSON.self, forKey: key)) ?? .null
            }
        }

        if let whole = try? c.decode([String: ChannelState].self, forKey: .states) {
            states = whole
        } else if let raw = try? c.decode([String: RawJSON].self, forKey: .states) {
            for (key, value) in raw {
                guard let data = try? Self.standaloneJSON(value),
                      let state = try? CouchJSON.decode(ChannelState.self, from: data)
                else {
                    quarantined[key] = value
                    continue
                }
                states[key] = state
            }
        }

        // A channel this build does not know is moved to quarantine rather than
        // dropped. It cannot be *played* — `Channel.Ledgered(rawValue:)` returns
        // nil, so nothing can address it — but the streak inside it belongs to
        // the player, and an upgrade must hand it back intact.
        for key in states.keys.filter({ Channel.Ledgered(rawValue: $0) == nil }) {
            guard let state = states.removeValue(forKey: key) else { continue }
            if quarantined[key] == nil,
               let data = try? CouchJSON.encode(state),
               let tree = try? CouchJSON.decode(RawJSON.self, from: data) {
                quarantined[key] = tree
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: RawJSON.RawKey.self)
        for key in carriedTopLevel.keys.sorted() {
            try container.encode(carriedTopLevel[key]!, forKey: RawJSON.RawKey(key))
        }
        var nested = container.nestedContainer(
            keyedBy: RawJSON.RawKey.self,
            forKey: RawJSON.RawKey(CodingKeys.states.stringValue))
        // Quarantined channels re-emitted alongside the ones we understand, in
        // the same map, so an upgrade finds them where it expects them.
        for key in states.keys.sorted() {
            try nested.encode(states[key]!, forKey: RawJSON.RawKey(key))
        }
        for key in quarantined.keys.sorted() where states[key] == nil {
            try nested.encode(quarantined[key]!, forKey: RawJSON.RawKey(key))
        }
    }

    /// One carried element as standalone JSON, so the real type can be decoded
    /// straight out of it — `ReplayVault.standaloneJSON`'s trick and the same
    /// sorted-keys convention, because the dates inside are already ISO-8601
    /// strings by the time they reach `RawJSON`.
    private static func standaloneJSON(_ value: RawJSON) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
