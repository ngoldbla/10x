// ChannelRules.swift — the variant rules a persisted board is played under, in
// their own blob (`nine.channelRules`), never a field on `LibraryEntry`.
//
// `EXECUTING-A-PRD.md` §2 gives two sanctioned homes for new per-board state — a
// sibling top-level key of the library blob, or its own `CouchStored` blob — and
// this takes the second, for three reasons in increasing order of weight:
//
//   1. **The library decode is on the 800 ms launch path**, measured at 49 ms for
//      a full 60-entry library, and a cage tiling is ~1 KB of JSON per board.
//      Inflating the blob every launch reads to buy a value most boards do not
//      have is the wrong trade.
//   2. **An older build never touches this file at all.** `carriedTopLevel`
//      preserves an unknown sibling key, which is enough; a separate blob is not
//      merely preserved but never opened, which is strictly stronger.
//   3. `ReplayVault` (PRD-26) had this exact problem — immutable per-board records
//      that must be pruned when the board goes — and this is deliberately the
//      same shape, down to the two-pass decode and the insertion `order` array.
//      Two blobs with one pattern beats two patterns.
//
// **Why the rules are stored rather than regenerated.** A variant board is fully
// determined by `(variant, tier, seed)` and generation is deterministic, so the
// cages could be re-derived on resume for 0.01–0.14 s. They are stored anyway,
// because the failure mode of the cheap option is silent and unbounded: if
// variant generation ever moves by a byte, every stored board's *givens* stay put
// while its *rules* change underneath them, and the player is handed a board whose
// clues contradict its cages with no error anywhere. Storing the rules means a
// board's rules can never drift from its givens. (Variant generation is frozen
// regardless — every channel daily is `(day → seed) → board`, so
// `VariantCorpusTests` pins it the way the golden corpus pins classic.)
import Foundation
import CouchCore

/// The rules one persisted board is played under, and enough identity to know
/// which ruleset they belong to.
///
/// `variant` and `tier` are duplicated from the board's `GameKind.channel`
/// deliberately: this record has to be self-describing, because it is what
/// `ConstraintContext` is compiled from and a mismatch between the two is a bug
/// worth being able to *detect* rather than one that cannot be expressed.
public struct ChannelRules: Sendable, Codable, Equatable {
    public let variant: Variant
    public let tier: VariantTier
    public let constraints: [VariantConstraint]

    public init(variant: Variant, tier: VariantTier, constraints: [VariantConstraint]) {
        self.variant = variant
        self.tier = tier
        self.constraints = constraints
    }

    public init(_ puzzle: VariantPuzzle) {
        self.init(variant: puzzle.variant, tier: puzzle.tier, constraints: puzzle.constraints)
    }

    /// The compiled form the solver runs against.
    public var context: ConstraintContext { ConstraintContext.compile(constraints) }

    /// Whether this build can enforce every rule on the board.
    ///
    /// False when any constraint decoded as `.unrecognized` — a board sent from a
    /// future build carrying an `.arrow`. Such a board must not be played, solved,
    /// error-marked or scored: every answer would be about a different puzzle.
    /// Callers gate on this rather than ignoring the rule, which is the same
    /// contract `ConstraintContext.canEnforceEveryConstraint` states one level
    /// down.
    public var isPlayable: Bool {
        !constraints.isEmpty && context.canEnforceEveryConstraint
    }

    /// Tolerant: nothing throws, so one unreadable record cannot take the blob.
    /// A record whose constraints do not decode lands with an empty list and is
    /// therefore not `isPlayable`, which is the safe answer — better an entry the
    /// player cannot open than one opened under the wrong rules.
    public init(from decoder: any Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            variant = .classic
            tier = .steady
            constraints = []
            return
        }
        variant = (try? c.decode(Variant.self, forKey: .variant)) ?? .classic
        tier = (try? c.decode(VariantTier.self, forKey: .tier)) ?? .steady
        constraints = (try? c.decode([VariantConstraint].self, forKey: .constraints)) ?? []
    }
}

/// Every variant board's rules this device holds, in their own top-level
/// `CouchStored` blob (`nine.channelRules`).
///
/// **Pruned with the library**, exactly as `ReplayVault` is and for the same
/// reason: these rules are about a *board*, so when the board goes they have
/// nothing left to be about. Compare `CoachProgress`, which is about the *person*
/// and must outlive every board they ever played.
///
/// Local-only, not `cloudSynced`. It rides with `nine.library`, which is also
/// local (KVS is 1 MB and a full library is ~500 KB) and reaches other devices
/// through `LibraryCloudStore`'s per-entry CloudKit records instead. A variant
/// board therefore does **not** sync yet — that needs a new record type and a
/// production schema deploy, the human gate PRD-26's replays also had. Recorded
/// as a deferral rather than half-built.
public struct ChannelRuleStore: Sendable, Codable, Equatable {

    /// One per library slot, which is the most boards that can be live at once.
    public static let capacity = 60

    private var rules: [String: ChannelRules]
    /// Insertion order, for the capacity trim — "which to drop" needs an order a
    /// dictionary cannot give. `ReplayVault` and `CoachLedger`'s shape.
    private var order: [String]

    public init() {
        rules = [:]
        order = []
    }

    public var count: Int { rules.count }

    public func rules(for boardID: UUID) -> ChannelRules? { rules[boardID.uuidString] }

    /// Keep a board's rules. Immutable once stored: a board's rules are fixed at
    /// composition and a second write for the same id is the same value, so the
    /// first one wins rather than being replaced. That is the opposite of
    /// `ReplayVault.store`, which *does* replace on a strictly newer solve —
    /// because a replay is about an attempt and there can be a better one, while
    /// rules are about the board and there cannot be a newer set.
    public mutating func store(_ value: ChannelRules, for boardID: UUID) {
        let key = boardID.uuidString
        guard rules[key] == nil else { return }
        order.append(key)
        rules[key] = value
        trim()
    }

    /// Drop one board's rules because the board was deliberately deleted.
    /// Separate from `prune` for the reason `ReplayVault.remove` is: `prune`
    /// refuses an empty live set, because a library that has not loaded yet looks
    /// exactly like an empty one — and that guard is right for a sweep and wrong
    /// for "delete this board", which is the one call that can empty the library.
    public mutating func remove(_ boardID: UUID) {
        let key = boardID.uuidString
        guard rules.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
    }

    /// Drop every record whose board has left the library.
    public mutating func prune(to liveIDs: Set<String>) {
        guard !liveIDs.isEmpty else { return }
        for key in order where !liveIDs.contains(key) {
            rules.removeValue(forKey: key)
        }
        order = order.filter { rules[$0] != nil }
    }

    private mutating func trim() {
        while order.count > Self.capacity {
            rules.removeValue(forKey: order.removeFirst())
        }
    }

    private static func standaloneJSON(_ value: RawJSON) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey { case rules, order }

    /// Nothing throws. Two passes, fast path first — `ReplayVault.init(from:)`'s
    /// pattern and its reasoning: the per-element walk is the shape whose
    /// `LibraryEntry` version measured 1515 ms against a 49 ms baseline, so it
    /// runs only on the blob that needs it.
    public init(from decoder: any Decoder) throws {
        rules = [:]
        order = []
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        if let whole = try? c.decode([String: ChannelRules].self, forKey: .rules) {
            rules = whole
        } else if let raw = try? c.decode([String: RawJSON].self, forKey: .rules) {
            for (key, value) in raw {
                guard let data = try? Self.standaloneJSON(value),
                      let decoded = try? CouchJSON.decode(ChannelRules.self, from: data)
                else { continue }
                rules[key] = decoded
            }
        }
        order = (try? c.decode([String].self, forKey: .order)) ?? []
        // Repair, so a hand-edited or half-written blob still trims
        // deterministically — `CoachProgress`'s rule and `ReplayVault`'s, verbatim.
        let placed = Set(order)
        order.append(contentsOf: rules.keys.filter { !placed.contains($0) }.sorted())
        order = order.filter { rules[$0] != nil }
        trim()
    }
}
