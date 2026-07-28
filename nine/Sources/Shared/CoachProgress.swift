// CoachProgress.swift — what the coach remembers about the *player*, not about
// a board (PRD-25 §2.5).
//
// `CoachLedger` is per-board and local-only: how many hints this board has been
// shown is a property of the hand that played it. This is the other axis — which
// techniques this person has met — and it belongs to the person, so it is
// cloud-synced and follows them to the iPad.
//
// **Its own top-level `CouchStored` blob, and that is the whole design.** Not a
// field on `LibraryEntry` (an older build's synthesized decode drops it and
// erases it on the next autosave 0.6 s later, forever, for any mixed-version
// two-device player — field-level preservation was implemented, measured at
// 1515 ms against a 49 ms baseline, and reverted). Not a field on `CoachLedger`
// either, which is pruned to the live library on every write: a technique you
// learned six months ago must not be forgotten because the board you learned it
// on was deleted.
//
// **What it is emphatically not.** No XP, no levels, no badges, no percentage
// ring, no notification, nothing that appears unbidden. PRD-7's constitution
// rules gamification out and this is the file most likely to grow it by
// accident, so the three readers are named here and nowhere else:
//
//   1. Technique School floats the first unmet technique to the top of a list
//      that is otherwise in rank order. Ordering, not gating — every lesson is
//      open from the first launch and none of them ever locks.
//   2. A technique the coach has explained before skips its preamble.
//   3. The stats drawer says "seven of ten techniques met", once, in the
//      hand-inked language that is already there.
//
// A player who never opens School is never told they have not.
//
// Keyed by `Technique` **raw value strings** rather than by the enum, so a
// build that has never heard of `swordfish` carries the row instead of dropping
// it — the same reason `nine.history` writes a `band` sibling. Pure Foundation,
// so it tests on Linux beside `CoachLedger`, which it is modelled on.
// `canImport`, like every other Shared file that names an Engine type: SwiftPM
// builds Engine and Shared as two modules, and the generated Xcode project
// compiles both trees into one target where `NineEngine` does not exist as a
// module at all.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

public struct CoachProgress: Codable, Equatable, Sendable {

    /// The most techniques remembered at once — a bit over double the fourteen
    /// that exist, so every future case has room and the blob is still bounded.
    ///
    /// **The number is measured, not chosen.** It was 64 first, on the reasoning
    /// that a generous ceiling costs nothing; a full blob at 64 is **3,017
    /// bytes** against PRD-25 §2.5's 2 KB budget, at ~47 bytes a row. 32 rows is
    /// ~1.5 KB. `CoachProgressTests.theBlobIsBoundedNoMatterWhatItIsFed` is
    /// where that arithmetic is enforced rather than remembered.
    public static let capacity = 32

    /// What is remembered about one technique.
    public struct Met: Codable, Equatable, Sendable {
        /// How many times the coach has narrated it. Never shown as a number,
        /// and never compared against a threshold — it exists so beat 2 above
        /// can ask "have we done this before" without a second bool that can
        /// disagree with this one.
        public var explained: Int
        /// Whether its School lesson has been played to the end.
        public var lessonDone: Bool

        public init(explained: Int = 0, lessonDone: Bool = false) {
            self.explained = explained
            self.lessonDone = lessonDone
        }

        /// Tolerant per field, for `CouchStored`'s reason: a decode that throws
        /// discards the **whole blob**, so a later build adding a sibling field
        /// here must not be able to erase a player's progress on an older one.
        public init(from decoder: any Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
                explained = 0
                lessonDone = false
                return
            }
            explained = (try? c.decode(Int.self, forKey: .explained)) ?? 0
            lessonDone = (try? c.decode(Bool.self, forKey: .lessonDone)) ?? false
        }
    }

    /// `Technique.rawValue` → record. A string key, not the enum: an older
    /// build meeting `"swordfish"` keeps the row verbatim and hands it back on
    /// its next write, instead of decoding a partial dictionary and quietly
    /// deleting a technique the player has already learned.
    private var met: [String: Met]
    /// Insertion order, for the capacity trim. Beside the dictionary rather
    /// than derived from it, because "which to drop" needs an order a
    /// dictionary cannot give — `CoachLedger`'s shape, for `CoachLedger`'s
    /// reason.
    private var order: [String]

    public init() {
        met = [:]
        order = []
    }

    public var count: Int { met.count }

    /// Never nil: a technique nobody has met reads as zero and not done, which
    /// is the truth.
    public func record(for technique: Technique) -> Met {
        met[technique.rawValue] ?? Met()
    }

    public func hasMet(_ technique: Technique) -> Bool {
        record(for: technique).explained > 0 || record(for: technique).lessonDone
    }

    /// How many of `techniques` the player has met. The stats drawer's one
    /// sentence, computed here so the drawer does not hold the rule.
    public func metCount(of techniques: [Technique]) -> Int {
        techniques.count(where: hasMet)
    }

    public mutating func recordExplanation(of technique: Technique) {
        var record = self.record(for: technique)
        record.explained += 1
        write(record, for: technique.rawValue)
    }

    public mutating func recordLessonFinished(_ technique: Technique) {
        var record = self.record(for: technique)
        record.lessonDone = true
        write(record, for: technique.rawValue)
    }

    /// The curriculum, reordered so the first thing the player has not met sits
    /// at the top. Stable otherwise — this moves *one* lesson, so the list does
    /// not rearrange itself under someone who is reading it.
    public func suggestedOrder(_ techniques: [Technique]) -> [Technique] {
        guard let next = techniques.first(where: { !hasMet($0) }),
              next != techniques.first else { return techniques }
        return [next] + techniques.filter { $0 != next }
    }

    private mutating func write(_ record: Met, for key: String) {
        if met[key] == nil { order.append(key) }
        met[key] = record
        trim()
    }

    private mutating func trim() {
        while order.count > Self.capacity {
            met.removeValue(forKey: order.removeFirst())
        }
    }

    // Nothing in here throws. `CouchStored` discards the entire blob on a
    // decode error, so an unreadable half reads as "nothing met yet" rather
    // than taking a player's whole history of learning down with it.
    public init(from decoder: any Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            met = [:]
            order = []
            return
        }
        met = (try? c.decode([String: Met].self, forKey: .met)) ?? [:]
        order = (try? c.decode([String].self, forKey: .order)) ?? []
        // Repair, so a hand-edited or half-written blob still trims
        // deterministically: anything in `met` with no place in `order` joins
        // the end, anything in `order` with no record leaves.
        let placed = Set(order)
        order.append(contentsOf: met.keys.filter { !placed.contains($0) }.sorted())
        order = order.filter { met[$0] != nil }
        trim()
    }
}
