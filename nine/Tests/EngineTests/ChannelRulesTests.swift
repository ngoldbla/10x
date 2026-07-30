// ChannelRulesTests — the per-board rule store, and the one question it exists
// to answer safely: *what happens to a board whose rules this build cannot
// enforce?*
//
// Every other tolerance rule in this repo is about preserving a value an old
// build cannot read. This store's hazard runs the other way. A `LibraryEntry`
// whose `GameKind` says `.channel` is a board with cages or tubes on it, and if
// its rules are missing, unreadable, or carry a future `.arrow` this build cannot
// enforce, then opening it as an ordinary sudoku shows the player a grid with no
// cages drawn and marks their correct entries as errors. So `isPlayable` has to
// be false in *all four* of those cases, and the tests below are one per case.
import Testing
import Foundation
import CouchCore
@testable import NineEngine

@Suite("ChannelRules")
struct ChannelRulesTests {

    private func t(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
    }

    private var cages: [VariantConstraint] {
        [Cage(cells: [0, 1, 9], sum: 15), Cage(cells: [2, 3], sum: 11)]
            .compactMap { $0 }.map(VariantConstraint.cage)
    }

    private var tubes: [VariantConstraint] {
        [Thermometer(cells: [40, 41, 42]), Thermometer(cells: [0, 10, 20, 30])]
            .compactMap { $0 }.map(VariantConstraint.thermometer)
    }

    private func killer() -> ChannelRules {
        ChannelRules(variant: .killer, tier: .steady, constraints: cages)
    }

    private func thermo() -> ChannelRules {
        ChannelRules(variant: .thermo, tier: .gentle, constraints: tubes)
    }

    /// A constraint from a build that ships a ruleset this one does not. The
    /// `.unrecognized` case is precisely what `VariantConstraint`'s hand-written
    /// decode exists for, and this is the payload that reaches it.
    private func futureRule() throws -> VariantConstraint {
        let json = #"{"kind": "arrow", "cells": [4, 5, 6], "tail": 4}"#
        return try CouchJSON.decode(VariantConstraint.self, from: Data(json.utf8))
    }

    // MARK: - isPlayable, the four ways a board must refuse to open

    @Test func rulesThisBuildUnderstandsArePlayable() {
        #expect(killer().isPlayable)
        #expect(thermo().isPlayable)
        #expect(killer().context.cages.count == 2)
        #expect(thermo().context.thermometers.count == 2)
    }

    /// (1) No rules at all. A `.channel` entry whose record never arrived — a
    /// board that came from CloudKit while its rules stayed on the other device,
    /// which is exactly the sync gap PRD-24 defers.
    @Test func aChannelBoardWithNoRulesIsNotPlayable() {
        #expect(!ChannelRules(variant: .killer, tier: .steady, constraints: []).isPlayable)
    }

    /// (2) A rule this build cannot enforce. Playing it would be answering
    /// questions about a different puzzle — including marking correct entries as
    /// errors, because the solution would be re-derived under the wrong rules.
    @Test func aFutureRuleMakesTheBoardUnplayableRatherThanIgnored() throws {
        let mixed = ChannelRules(
            variant: .killer, tier: .steady, constraints: cages + [try futureRule()])
        #expect(!mixed.isPlayable)
        #expect(!mixed.context.canEnforceEveryConstraint)
        // The rule is still *held* — refusing to play it is not the same as
        // dropping it, and a round trip must hand it back byte for byte.
        let back = try CouchJSON.decode(
            ChannelRules.self, from: try CouchJSON.encode(mixed))
        #expect(back == mixed)
        #expect(back.constraints.count == 3)
        #expect(back.constraints.last?.kind == "arrow")
    }

    /// (3) A record whose constraints do not decode at all lands with an empty
    /// list, so it is not playable. Better an entry the player cannot open than
    /// one opened under the wrong rules.
    @Test func anUnreadableRecordIsUnplayableRatherThanEmptyClassic() throws {
        let json = #"{"variant": "killer", "tier": "steady", "constraints": "broken"}"#
        let back = try CouchJSON.decode(ChannelRules.self, from: Data(json.utf8))
        #expect(!back.isPlayable)
        #expect(back.constraints.isEmpty)
    }

    /// (4) Not a rules record at all. Nothing throws, and the result refuses.
    @Test func rulesAreNeverDiscardedByAThrow() throws {
        for json in ["{}", "[]", "null", "7"] {
            let back = try CouchJSON.decode(ChannelRules.self, from: Data(json.utf8))
            #expect(!back.isPlayable)
        }
    }

    // MARK: - The store

    @Test func aStoreRoundTripsAndFindsItsBoards() throws {
        var store = ChannelRuleStore()
        let a = UUID(), b = UUID()
        store.store(killer(), for: a)
        store.store(thermo(), for: b)
        let back = try CouchJSON.decode(
            ChannelRuleStore.self, from: try CouchJSON.encode(store))
        #expect(back == store)
        #expect(back.rules(for: a) == killer())
        #expect(back.rules(for: b) == thermo())
        #expect(back.rules(for: UUID()) == nil)
    }

    /// Rules are immutable once stored, which is the opposite of `ReplayVault`'s
    /// replace-on-newer rule and deliberately so: a replay is about an *attempt*
    /// and there can be a better one, while rules are about the *board* and there
    /// cannot be a newer set. A second write is either the same value or a bug,
    /// and the first one winning means a bug cannot corrupt a live board.
    @Test func rulesAreImmutableOnceStored() {
        var store = ChannelRuleStore()
        let id = UUID()
        store.store(killer(), for: id)
        store.store(thermo(), for: id)
        #expect(store.rules(for: id) == killer())
        #expect(store.count == 1)
    }

    /// Pruned with the library, because these rules are about a board and when the
    /// board goes they have nothing left to be about (`ReplayVault`'s reasoning).
    @Test func pruningDropsRulesWhoseBoardHasLeft() {
        var store = ChannelRuleStore()
        let live = UUID(), gone = UUID()
        store.store(killer(), for: live)
        store.store(thermo(), for: gone)
        store.prune(to: [live.uuidString])
        #expect(store.rules(for: live) != nil)
        #expect(store.rules(for: gone) == nil)
    }

    /// `prune` refuses an empty live set, because a library that has not loaded
    /// yet looks exactly like an empty one and pruning against the second would
    /// delete everything. `remove` is the separate door for "delete this board",
    /// which is the one call that legitimately empties the library.
    @Test func pruningAgainstAnEmptyLibraryIsRefusedButRemoveIsNot() {
        var store = ChannelRuleStore()
        let id = UUID()
        store.store(killer(), for: id)
        store.prune(to: [])
        #expect(store.rules(for: id) != nil, "an unloaded library must not delete everything")
        store.remove(id)
        #expect(store.rules(for: id) == nil, "deleting the last board must take effect now")
        #expect(store.count == 0)
    }

    /// Capacity is one per library slot, which is the most boards that can be live
    /// at once, and the trim takes the oldest insertion.
    @Test func theStoreIsCappedAtOnePerLibrarySlot() {
        #expect(ChannelRuleStore.capacity == 60)
        var store = ChannelRuleStore()
        var ids: [UUID] = []
        for _ in 0..<(ChannelRuleStore.capacity + 5) {
            let id = UUID()
            ids.append(id)
            store.store(killer(), for: id)
        }
        #expect(store.count == ChannelRuleStore.capacity)
        #expect(store.rules(for: ids[0]) == nil, "the oldest insertion is what gets dropped")
        #expect(store.rules(for: ids[ids.count - 1]) != nil)
    }

    /// One unreadable record must not take the other fifty-nine — the fast whole-map
    /// decode falls back to a per-element walk, `ReplayVault`'s two-pass shape.
    @Test func oneUnreadableRecordDoesNotTakeTheStore() throws {
        var store = ChannelRuleStore()
        let good = UUID()
        store.store(killer(), for: good)
        var tree = try #require(try JSONSerialization.jsonObject(
            with: try CouchJSON.encode(store)) as? [String: Any])
        var rules = try #require(tree["rules"] as? [String: Any])
        rules["not-a-uuid"] = "wholly wrong"
        tree["rules"] = rules
        let mangled = try JSONSerialization.data(withJSONObject: tree)

        let back = try CouchJSON.decode(ChannelRuleStore.self, from: mangled)
        #expect(back.rules(for: good) == killer())
    }

    @Test func aStoreIsNeverDiscardedWholesale() throws {
        for json in ["{}", "[]", "null", #"{"rules": 3, "order": "x"}"#] {
            let back = try CouchJSON.decode(ChannelRuleStore.self, from: Data(json.utf8))
            #expect(back.count == 0)
        }
    }

    /// A half-written blob still trims deterministically: keys present in `rules`
    /// but missing from `order` are appended in sorted order, and `order` entries
    /// with no rule are dropped. `CoachProgress`'s repair rule, verbatim.
    @Test func aBlobWithABrokenOrderArrayIsRepaired() throws {
        let id = UUID()
        let json = """
            {"order": ["\(UUID().uuidString)"], "rules": {"\(id.uuidString)": \
            {"variant": "thermo", "tier": "gentle", "constraints": []}}}
            """
        let back = try CouchJSON.decode(ChannelRuleStore.self, from: Data(json.utf8))
        #expect(back.count == 1)
        #expect(back.rules(for: id) != nil)
        // And it still trims, which is what the repair is for.
        var grown = back
        for _ in 0..<(ChannelRuleStore.capacity + 3) { grown.store(killer(), for: UUID()) }
        #expect(grown.count == ChannelRuleStore.capacity)
    }

    // MARK: - The record is self-describing

    /// `variant` and `tier` are duplicated from the board's `GameKind.channel` on
    /// purpose: the record has to be self-describing because it is what the
    /// context is compiled from, and a disagreement between the two is a bug worth
    /// being able to *detect* rather than one that cannot be expressed.
    @Test func aRulesRecordNamesItsOwnRuleset() throws {
        let puzzle = try #require(
            VariantGenerator.generate(seed: 1, variant: .thermo, tier: .gentle))
        let rules = ChannelRules(puzzle)
        #expect(rules.variant == .thermo)
        #expect(rules.tier == .gentle)
        #expect(rules.constraints == puzzle.constraints)
        #expect(rules.isPlayable)
        // The compiled context agrees with the board it was proved against.
        #expect(rules.context.thermometers == puzzle.context.thermometers)
    }
}
