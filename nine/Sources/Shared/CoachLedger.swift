// CoachLedger.swift — what the coach remembers, per board (PRD-11 §6).
//
// Two things live here: how many hints a board has been shown, and whether auto
// notes is on for it. Neither gates anything. PRD-11 §3 rules hint quotas out
// forever, so the count exists to let the stats drawer be honest and to give
// PRD-25's `CoachProgress` something to build on — never to say no.
//
// **This is its own `CouchStored` blob, keyed by library-entry id, and that is
// the whole design.** A field on `LibraryEntry` would be dropped by an older
// build's synthesized decode and erased on its next autosave 0.6 s later, over
// and over, for any mixed-version two-device player. Field-level preservation
// was implemented, measured at 1515 ms against a 49 ms baseline on a launch
// path budgeted at 800 ms, and reverted (EXECUTING-A-PRD §2). A sibling
// top-level key costs nothing and cannot be clobbered — the same shape
// `nine.tips` and `nine.history`'s `band` already take.
//
// Local-only, never cloud-synced: like `undoCount`, a hint count is a property
// of the hand that played the board, not of the board (PRD-8 §2).
//
// Pure Foundation — no SwiftUI, no clocks — so it tests on Linux CI beside
// `TipLedger`, which it is deliberately modelled on.
import Foundation

public struct CoachLedger: Codable, Equatable, Sendable {

    /// The most boards remembered at once. Pruning drops the oldest first, so
    /// a heavy player's blob stays small and bounded forever.
    public static let capacity = 200

    /// What is remembered about one board.
    public struct Board: Codable, Equatable, Sendable {
        public var hints: Int
        public var autoNotes: Bool

        public init(hints: Int = 0, autoNotes: Bool = false) {
            self.hints = hints
            self.autoNotes = autoNotes
        }

        /// Tolerant per field. A later build adding a sibling field here must
        /// not be able to take the blob down on an older one — and `try?` on
        /// each field is what makes that true rather than hoped for.
        public init(from decoder: any Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
                hints = 0
                autoNotes = false
                return
            }
            hints = (try? c.decode(Int.self, forKey: .hints)) ?? 0
            autoNotes = (try? c.decode(Bool.self, forKey: .autoNotes)) ?? false
        }
    }

    /// `LibraryEntry.id.uuidString` → record.
    private var boards: [String: Board]
    /// The same ids, oldest first. Kept beside the dictionary rather than
    /// derived from it, because "which 200 to keep" needs an order a
    /// dictionary cannot give.
    private var order: [String]

    public init() {
        boards = [:]
        order = []
    }

    public var count: Int { boards.count }

    /// Never nil: a board nobody has asked the coach about reads as zero
    /// hints and auto notes off, which is the truth.
    public func board(_ id: String) -> Board { boards[id] ?? Board() }

    public mutating func recordHint(_ id: String) {
        var record = board(id)
        record.hints += 1
        write(record, for: id)
    }

    public mutating func setAutoNotes(_ on: Bool, for id: String) {
        var record = board(id)
        record.autoNotes = on
        write(record, for: id)
    }

    /// Drop boards the library no longer holds, then trim to `capacity`.
    /// Called on every write from `AppModel`, so the blob tracks the library
    /// rather than accumulating the ids of boards deleted months ago.
    public mutating func prune(to liveIDs: Set<String>) {
        boards = boards.filter { liveIDs.contains($0.key) }
        order = order.filter { boards[$0] != nil }
        trim()
    }

    private mutating func write(_ record: Board, for id: String) {
        if boards[id] == nil { order.append(id) }
        boards[id] = record
        trim()
    }

    private mutating func trim() {
        while order.count > Self.capacity {
            boards.removeValue(forKey: order.removeFirst())
        }
    }

    // `CouchStored` discards the entire blob when a decode throws, so this one
    // cannot: anything unreadable reads as "nothing remembered yet" rather than
    // taking the file down with it.
    public init(from decoder: any Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            boards = [:]
            order = []
            return
        }
        boards = (try? c.decode([String: Board].self, forKey: .boards)) ?? [:]
        order = (try? c.decode([String].self, forKey: .order)) ?? []
        // Repair, so a hand-edited or half-written blob still prunes
        // deterministically: anything in `boards` with no place in `order`
        // joins the end, and anything in `order` with no record leaves.
        let placed = Set(order)
        order.append(contentsOf: boards.keys.filter { !placed.contains($0) }.sorted())
        order = order.filter { boards[$0] != nil }
        trim()
    }
}
