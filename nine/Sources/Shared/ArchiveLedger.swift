// ArchiveLedger.swift — which dailies have been solved (PRD-14 §2).
//
// The daily archive regenerates every board from `DailySeed`, so it stores no
// puzzles. It does have to store one thing, and this is it: the set of day
// ordinals whose daily is solved, which is what puts the checkmarks in the
// month grid.
//
// **Nothing else in the app can answer that question, which is the whole reason
// this type exists.** PRD-14 §2 sources the checkmark from
// `library.dailyEntry(day:)` "+ solve records", and neither can hold it:
//
//   • `BoardLibrary.prune()` caps solved+archived entries at 20 (`playedCap`)
//     and evicts oldest-`updatedAt` first, so the 21st archive solve silently
//     erases the earliest checks — from the one view the feature exists to
//     show, and "hundreds of hours of content" is PRD-14's own pitch.
//   • `SolveRecord` carries the *solve* date and never the puzzle's day
//     ordinal, deliberately, so that the PRD-9 heat grid buckets honestly. It
//     caps at 200 besides.
//   • `StreakState` holds one `lastCompletedDay`, not a set.
//
// **Its own `CouchStored` blob (`nine.archive`), never a `LibraryEntry` field.**
// An older build's synthesized decode drops a field it has no property for and
// erases it on its next autosave 0.6 s later, repeatedly, for any mixed-version
// two-device player; field-level preservation was implemented, measured at
// 1515 ms against a 49 ms baseline on a launch path budgeted at 800 ms, and
// reverted (EXECUTING-A-PRD §2). Its own blob rather than a sibling key of
// `nine.history`, because `SolveHistory` is an array of records with a
// newest-first ordering contract, a capacity prune and a quarantine, and a set
// of ordinals shares none of that — the same call `nine.coach` made one PRD ago.
//
// Cloud-synced, unlike `nine.coach`: a checkmark is a property of the player,
// not of the hand that held the phone, so it belongs beside `nine.streak` and
// `nine.history`.
//
// Size, since the alternative considered was range compression: one `Int` per
// solved day, five digits and a comma. Ten years of unbroken daily play is
// ~3 650 ordinals ≈ **22 KB** against a 1 MB KVS budget already carrying 200
// history records. Ranges win on the contiguous case and *lose* on the
// alternating one, for real code and real tests — so this is a sorted array
// until a measurement says otherwise, and the measurement is written down here
// so whoever revisits it starts from one.
//
// Pure Foundation apart from `RawJSON`, so it tests on Linux CI beside
// `CoachLedger`, which it is deliberately modelled on.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

public struct ArchiveLedger: Codable, Sendable {

    /// Sorted and deduplicated, always — `isSolved` binary-searches it, so an
    /// unsorted store answers *wrongly* rather than slowly.
    private var days: [Int]

    /// Unknown siblings of `days` at the top level of the blob, carried so an
    /// older build's rewrite cannot strip a newer build's key.
    private var carriedTopLevel: [String: RawJSON]

    public init() {
        days = []
        carriedTopLevel = [:]
    }

    // MARK: - The set

    public var solvedDays: [Int] { days }

    public var count: Int { days.count }

    public func isSolved(day: Int) -> Bool {
        var low = 0
        var high = days.count - 1
        while low <= high {
            let mid = low + (high - low) / 2
            if days[mid] == day { return true }
            if days[mid] < day { low = mid + 1 } else { high = mid - 1 }
        }
        return false
    }

    /// Insert, keeping the array sorted. Returns whether anything changed, so
    /// the launch backfill can skip a write on the overwhelmingly common launch
    /// where nothing is new.
    @discardableResult
    public mutating func markSolved(day: Int) -> Bool {
        let index = insertionIndex(of: day)
        guard index == days.count || days[index] != day else { return false }
        days.insert(day, at: index)
        return true
    }

    /// The first position holding a day `>=` this one.
    private func insertionIndex(of day: Int) -> Int {
        var low = 0
        var high = days.count
        while low < high {
            let mid = low + (high - low) / 2
            if days[mid] < day { low = mid + 1 } else { high = mid }
        }
        return low
    }

    // MARK: - Coding (the persistence covenant)

    private enum CodingKeys: String, CodingKey { case days }

    /// Nothing in here throws. `CouchStored` discards the entire blob when a
    /// decode does, and a lost blob here is every checkmark the player earned.
    public init(from decoder: any Decoder) throws {
        days = []
        carriedTopLevel = [:]
        if let anyKey = try? decoder.container(keyedBy: RawJSON.RawKey.self) {
            for key in anyKey.allKeys where key.stringValue != CodingKeys.days.stringValue {
                carriedTopLevel[key.stringValue] =
                    (try? anyKey.decode(RawJSON.self, forKey: key)) ?? .null
            }
        }
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        // The typed decode first, and the untyped tree only when it failed —
        // the same laziness `RawLibraryEntry` exists for, applied at the array
        // rather than the element. A healthy ledger is thousands of plain
        // integers read on the cold-launch path, and `Codable`'s failure path
        // allocates a `DecodingError` with a coding-path array per miss, so
        // building a `RawJSON` node for each of them costs several times what
        // reading the real type costs — and buys nothing until something is
        // actually wrong.
        if let typed = try? container.decode([Int].self, forKey: .days) {
            days = typed
        } else if let raw = try? container.decode([RawJSON].self, forKey: .days) {
            days = raw.compactMap {
                switch $0 {
                case .int(let value): return value
                case .uint(let value): return Int(exactly: value)
                case .double(let value): return Int(exactly: value.rounded())
                default: return nil
                }
            }
        }
        // Repair rather than trust: a hand-edited or half-written blob still
        // has to leave the invariant `isSolved` depends on intact.
        days = Array(Set(days)).sorted()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: RawJSON.RawKey.self)
        for key in carriedTopLevel.keys.sorted() {
            try container.encode(carriedTopLevel[key]!, forKey: RawJSON.RawKey(key))
        }
        try container.encode(days, forKey: RawJSON.RawKey(CodingKeys.days.stringValue))
    }
}

extension ArchiveLedger: Equatable {
    /// Identity is the days. The carried trees are an encoding detail, and
    /// excluding them is load-bearing: every caller and every test builds an
    /// `ArchiveLedger()` by hand and compares it against a decoded one.
    public static func == (lhs: ArchiveLedger, rhs: ArchiveLedger) -> Bool {
        lhs.days == rhs.days
    }
}
