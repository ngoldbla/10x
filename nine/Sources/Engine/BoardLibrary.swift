// BoardLibrary.swift — the board tracker's data model (playtest fix D). Replaces
// the single `SaveSlot` autosave: a daily entry (one per day) plus unlimited
// free-play partials, each carrying its own `NineGame`, status and timestamps.
// Pure and Sendable, no hidden clocks (every time-dependent op takes `now`), so
// it lives in the Engine and is fully SwiftPM-testable on Linux.
//
// The whole library persists as ONE `nine.library` blob, which is why the
// decode path at the bottom of this file is hand-written: see the covenant on
// `BoardLibrary` itself.
import Foundation

/// What kind of board is (or was) being played. Moved here from AppModel so the
/// library (Engine) can key on it; the synthesized Codable shape is unchanged
/// (case-name keyed), so old `nine.save` blobs still decode.
public enum GameKind: Codable, Sendable, Equatable, Hashable {
    case daily(day: Int)
    case free(Difficulty)
}

/// Lifecycle of a tracked board.
public enum BoardStatus: String, Codable, Sendable, Equatable {
    case inProgress, solved, archived
}

/// One tracked board.
public struct LibraryEntry: Codable, Sendable, Equatable, Identifiable {
    // `var` (not `let`) so cloud merges can re-home a divergent loser under a
    // fresh id (PRD-8 §2). The synthesized Codable shape is unchanged, and no
    // local code mutates it outside LibrarySync.
    public var id: UUID
    public var kind: GameKind
    public var game: NineGame
    public var status: BoardStatus
    public let createdAt: Date
    /// Last activity — moves, solve, or nothing since creation. The tracker and
    /// the prune order both sort on this.
    public var updatedAt: Date
    public var solvedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: GameKind,
        game: NineGame,
        status: BoardStatus = .inProgress,
        createdAt: Date,
        updatedAt: Date,
        solvedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.game = game
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.solvedAt = solvedAt
    }
}

/// The whole board library. `entries` is kept newest-updated first so the
/// tracker sections and the "most recent partial" queries are cheap first-reads.
///
/// **The persistence covenant: never throw out of a container decode, and never
/// delete what you cannot read.**
///
/// The library is one `CouchStored` blob, and `CouchStored` discards the whole
/// blob when decode throws (`try?` in `CouchStore`). The synthesized decode of
/// `[LibraryEntry]` throws if *any single element* fails — a future `Difficulty`
/// case, a future `GameKind` discriminator, a newly-required field written by a
/// newer build on another device — so one unreadable entry used to destroy the
/// player's entire library. Three rules follow, and all three are enforced by
/// `init(from:)` / `encode(to:)` below:
///
///  1. **Never throw.** Every step of the decode is `try?`-guarded. A missing
///     container, an `entries` key that isn't an array, an element that isn't
///     even an object — all of it yields a library, never an error.
///  2. **Never delete what you cannot read.** An element that fails to decode is
///     not dropped: it is kept verbatim in `quarantined` and re-emitted into the
///     same `entries` array on the way out.
///  3. **Preserve unknown *top-level* keys.** A future sibling of `entries` — a
///     `schemaVersion`, a `settings` — is held in `carriedTopLevel` and
///     re-emitted, so an older build's rewrite does not strip it.
///
/// **What is deliberately NOT protected, and it is the sharp edge on this type:
/// unknown keys *inside an entry this build can decode*.** The synthesized
/// decode of `LibraryEntry` ignores keys it has no property for, so a 1.6 entry
/// carrying a new optional `lastHintAt` decodes cleanly on 1.5, never reaches
/// the quarantine, and is re-encoded from the typed value — the field is gone on
/// the older device's next autosave. Field-level preservation (keep each
/// element's raw tree, merge it back under the typed encoding on the way out)
/// was built and measured, and it costs a full-library decode **1515 ms against
/// a 49 ms baseline** on the synchronous launch path; see the `RawLibraryEntry`
/// header for why the untyped tree is that expensive through `Codable`. It was
/// reverted for that reason. Until the store moves off `Codable`, **a build that
/// adds a field to `LibraryEntry` must assume an older build will erase it** on
/// any device the player still runs the older build on.
public struct BoardLibrary: Codable, Sendable, Equatable {
    public private(set) var entries: [LibraryEntry]

    /// Elements of the persisted `entries` array this build could not decode,
    /// held verbatim so writing the library back never destroys them. They are
    /// deliberately invisible to every query, cap and mutation on this type:
    /// nothing here can read their `updatedAt`, their status or even their
    /// shape, so pretending to manage them would be a lie.
    public private(set) var quarantined: [QuarantinedEntry]

    /// Unknown siblings of the `entries` key at the top level of the blob — a
    /// future `schemaVersion`, a future `settings` — held verbatim and re-emitted
    /// by `encode(to:)`, so an older build's rewrite does not strip them.
    ///
    /// This one is affordable where per-entry field preservation was not: a
    /// sibling key costs a `RawJSON` walk only when it *exists*, and a blob
    /// written by this build has none, so the scan visits an empty key list and
    /// the store stays empty. See the `RawLibraryEntry` header for the
    /// measurement that killed the per-entry version.
    private var carriedTopLevel: [String: RawJSON]

    public init(entries: [LibraryEntry] = []) {
        self.entries = entries
        self.quarantined = []
        self.carriedTopLevel = [:]
        sort()
    }

    /// Explicit, over `entries` + `quarantined` only. `carriedTopLevel` is an
    /// *encoding* detail, not identity: it holds keys this build could not
    /// interpret, so two libraries that agree on every board and every
    /// quarantined element are the same library whether or not one of them also
    /// remembers a newer build's sibling key. Excluding it is also load-bearing —
    /// `LibrarySync` and the tests build a `BoardLibrary(entries:)` (no carried
    /// keys, by construction) and compare it against a decoded one.
    public static func == (lhs: BoardLibrary, rhs: BoardLibrary) -> Bool {
        lhs.entries == rhs.entries && lhs.quarantined == rhs.quarantined
    }

    // MARK: - Caps (local-only persistence: iCloud KVS is full)
    static let totalCap = 60
    static let playedCap = 20 // solved + archived

    // MARK: - Queries

    public func entry(id: UUID) -> LibraryEntry? { entries.first { $0.id == id } }

    /// The single entry for a given day, any status (dailies are one-per-day).
    public func dailyEntry(day: Int) -> LibraryEntry? {
        entries.first { isDaily($0.kind, day: day) }
    }

    /// Today's daily only when it is still in progress (drives openToday resume).
    public func inProgressDaily(day: Int) -> LibraryEntry? {
        guard let e = dailyEntry(day: day), e.status == .inProgress else { return nil }
        return e
    }

    /// The newest in-progress free-play board (the Continue card).
    public var mostRecentFreePartial: LibraryEntry? {
        entries.first { $0.status == .inProgress && isFree($0.kind) }
    }

    /// The newest in-progress board of any kind (resume-on-launch).
    public var mostRecentInProgress: LibraryEntry? {
        entries.first { $0.status == .inProgress }
    }

    /// Every in-progress board, newest first (tracker "In progress" section).
    public var partials: [LibraryEntry] { entries.filter { $0.status == .inProgress } }

    /// Every solved or archived board, newest first ("Previously played").
    public var played: [LibraryEntry] { entries.filter { $0.status != .inProgress } }

    // MARK: - Mutations

    /// Insert or replace an entry by id, then re-sort and prune. The single
    /// funnel every other mutation routes through.
    public mutating func upsert(_ entry: LibraryEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
        sort()
        prune()
    }

    /// Start tracking a brand-new board; returns its id.
    @discardableResult
    public mutating func create(kind: GameKind, game: NineGame, now: Date) -> UUID {
        let entry = LibraryEntry(kind: kind, game: game, status: .inProgress, createdAt: now, updatedAt: now)
        upsert(entry)
        return entry.id
    }

    /// One-entry-per-day upsert for the daily — the merge that replaces the old
    /// launch-clobber. If a daily entry for `day` already exists it is reset to
    /// this (fresh or widget-advanced) board and marked in progress (a
    /// replay-after-solve reuses the same day slot); otherwise a new entry is
    /// created. Free-play entries are structurally untouched. Returns the id.
    @discardableResult
    public mutating func adoptDaily(game: NineGame, day: Int, now: Date) -> UUID {
        if var existing = dailyEntry(day: day) {
            existing.game = game
            existing.status = .inProgress
            existing.solvedAt = nil
            existing.updatedAt = now
            upsert(existing)
            return existing.id
        }
        return create(kind: .daily(day: day), game: game, now: now)
    }

    /// Mark a board solved, retained as a "previously played" entry.
    public mutating func markSolved(id: UUID, at date: Date) {
        guard var e = entry(id: id) else { return }
        e.status = .solved
        e.solvedAt = date
        e.updatedAt = date
        upsert(e)
    }

    /// Archive a partial (kept, but out of the active list). updatedAt is left
    /// as-is so the "previously played" order reflects last real activity.
    public mutating func archive(id: UUID) {
        guard var e = entry(id: id) else { return }
        e.status = .archived
        upsert(e)
    }

    /// Remove a board entirely (delete control).
    public mutating func delete(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Seed a library from a legacy single-slot `nine.save` board (migration).
    public static func migrating(game: NineGame, kind: GameKind, now: Date) -> BoardLibrary {
        let solved = game.isSolved
        let entry = LibraryEntry(
            kind: kind,
            game: game,
            status: solved ? .solved : .inProgress,
            createdAt: now,
            updatedAt: now,
            solvedAt: solved ? now : nil
        )
        return BoardLibrary(entries: [entry])
    }

    // MARK: - Coding (the persistence covenant)

    /// Only `entries` is persisted *by this build*. Quarantined elements are
    /// re-emitted *into* that array rather than into a sidecar key, precisely so
    /// an old build's write is readable — and complete — to the newer build that
    /// produced them. Unknown sibling keys are re-emitted alongside it.
    private enum CodingKeys: String, CodingKey { case entries }

    /// Version-tolerant, element-preserving decode. Nothing in here throws.
    public init(from decoder: Decoder) throws {
        entries = []
        quarantined = []
        carriedTopLevel = [:]
        // A non-keyed top level: empty library, nothing preserved. Throwing
        // instead would cost the player the whole blob.
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        // Siblings first, and unconditionally — they survive even when `entries`
        // itself is unreadable, since a sibling key is not implicated by a
        // malformed board list. A second container over the same decoder is safe:
        // keyed containers are independent views onto the one object.
        if let anyKey = try? decoder.container(keyedBy: RawJSON.RawKey.self) {
            for key in anyKey.allKeys where key.stringValue != CodingKeys.entries.stringValue {
                carriedTopLevel[key.stringValue] = (try? anyKey.decode(RawJSON.self, forKey: key)) ?? .null
            }
        }
        // A missing `entries`, or an `entries` that is a string / number / object
        // rather than an array: no element list, so there is nothing to preserve.
        guard let raw = try? container.decode([RawLibraryEntry].self, forKey: .entries) else { return }
        for element in raw {
            if let entry = element.entry {
                entries.append(entry)
            } else {
                quarantined.append(QuarantinedEntry(element.raw ?? .null))
            }
        }
        sort()
    }

    /// Re-emit the decoded entries followed by every quarantined element, into
    /// the one `entries` array. Order: known entries stay newest-updated first,
    /// then the unknowns, because `updatedAt` is exactly the field this build
    /// could not read for them — they cannot be merged into the sort. The
    /// build that *can* read them re-sorts the whole array on its next decode,
    /// so the misordering lasts one write.
    ///
    /// Entries go out as the typed value, straight through the caller's own
    /// encoder — byte-for-byte what 1.x emitted.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RawJSON.RawKey.self)
        // Sorted for stable bytes, and `entries` can never be shadowed: the
        // decode refuses to carry a sibling under that name.
        for key in carriedTopLevel.keys.sorted() {
            try container.encode(carriedTopLevel[key]!, forKey: RawJSON.RawKey(key))
        }
        var array = container.nestedUnkeyedContainer(
            forKey: RawJSON.RawKey(CodingKeys.entries.stringValue)
        )
        for entry in entries { try array.encode(entry) }
        for element in quarantined { try array.encode(element) }
    }

    // MARK: - Internals

    private mutating func sort() {
        entries.sort {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            // Deterministic tie-break so tests (and equal-timestamp bursts) are stable.
            return $0.id.uuidString > $1.id.uuidString
        }
    }

    /// Enforce the caps. Removal order, oldest-updated first within each band:
    /// archived → solved → inProgress. `played` (solved+archived) trims to 20
    /// first, then the whole library trims to 60. In-progress boards are only
    /// ever dropped when the total cap is blown, and the current board — the
    /// most-recently-updated in-progress — is dropped last of all.
    private mutating func prune() {
        let played = entries.filter { $0.status != .inProgress }
        if played.count > Self.playedCap {
            let victims = played
                .sorted { pruneRank($0) < pruneRank($1) }
                .prefix(played.count - Self.playedCap)
                .map(\.id)
            let ids = Set(victims)
            entries.removeAll { ids.contains($0.id) }
        }
        if entries.count > Self.totalCap {
            let victims = entries
                .sorted { pruneRank($0) < pruneRank($1) }
                .prefix(entries.count - Self.totalCap)
                .map(\.id)
            let ids = Set(victims)
            entries.removeAll { ids.contains($0.id) }
        }
    }

    /// Lower rank is pruned first: archived(0) → solved(1) → inProgress(2), and
    /// within a band the oldest `updatedAt` goes first.
    private func pruneRank(_ e: LibraryEntry) -> (Int, Date) {
        let band: Int
        switch e.status {
        case .archived: band = 0
        case .solved: band = 1
        case .inProgress: band = 2
        }
        return (band, e.updatedAt)
    }

    private func isDaily(_ kind: GameKind, day: Int) -> Bool {
        if case .daily(let d) = kind { return d == day }
        return false
    }

    private func isFree(_ kind: GameKind) -> Bool {
        if case .free = kind { return true }
        return false
    }
}

// MARK: - Quarantine

/// One element of the persisted `entries` array that this build could not
/// decode as a `LibraryEntry`, held as structure rather than as bytes.
///
/// Why structure and not `Data`: a `Decoder` never hands out the underlying
/// bytes, and an `Encoder` has no way to splice pre-encoded bytes back in. The
/// only representation that survives a trip *through* the same coder the outer
/// value is using is a decoded JSON tree, so that is what this holds. The round
/// trip is value-exact rather than byte-exact — object keys come back in sorted
/// order and a whole-valued `1.0` may come back as `1` — which is what matters:
/// the newer build re-decodes its own type from it and gets its entry back.
public struct QuarantinedEntry: Codable, Sendable, Equatable, Hashable {
    /// The element exactly as it was persisted.
    public let value: RawJSON

    public init(_ value: RawJSON) { self.value = value }

    public init(from decoder: Decoder) throws {
        value = (try? RawJSON(from: decoder)) ?? .null
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }

    /// The element as standalone JSON, so a build that understands it can decode
    /// the real type straight out of the quarantine (that is the upgrade half of
    /// the downgrade → upgrade round trip). Sorted keys: canonical bytes, same
    /// convention as `CouchJSON`.
    public func rawJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

/// An untyped JSON value: everything the library may have to carry without
/// understanding it. Deliberately a full number ladder — `Int`, then `UInt64`
/// (puzzle seeds are `UInt64` and overflow `Int` on 32-bit and near `.max`),
/// then `Double` — so a quarantined entry's seed survives verbatim.
public enum RawJSON: Codable, Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case uint(UInt64)
    case double(Double)
    case string(String)
    case array([RawJSON])
    case object([String: RawJSON])

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer() {
            if single.decodeNil() { self = .null; return }
            // Bool before the number ladder: a strict JSON decoder rejects a
            // number as Bool and vice versa, so the order only settles ties
            // between the numeric widths.
            if let v = try? single.decode(Bool.self) { self = .bool(v); return }
            if let v = try? single.decode(Int.self) { self = .int(v); return }
            if let v = try? single.decode(UInt64.self) { self = .uint(v); return }
            if let v = try? single.decode(Double.self) { self = .double(v); return }
            if let v = try? single.decode(String.self) { self = .string(v); return }
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var items: [RawJSON] = []
            while !unkeyed.isAtEnd {
                guard let item = try? unkeyed.decode(RawJSON.self) else { break }
                items.append(item)
            }
            self = .array(items)
            return
        }
        if let keyed = try? decoder.container(keyedBy: RawKey.self) {
            var object: [String: RawJSON] = [:]
            for key in keyed.allKeys {
                object[key.stringValue] = (try? keyed.decode(RawJSON.self, forKey: key)) ?? .null
            }
            self = .object(object)
            return
        }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var c = encoder.singleValueContainer()
            try c.encodeNil()
        case .bool(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .int(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .uint(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .double(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .string(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .array(let items):
            var c = encoder.unkeyedContainer()
            for item in items { try c.encode(item) }
        case .object(let object):
            var c = encoder.container(keyedBy: RawKey.self)
            // Sorted so the emitted bytes are stable regardless of Dictionary
            // iteration order (which is seeded per process).
            for key in object.keys.sorted() {
                try c.encode(object[key]!, forKey: RawKey(key))
            }
        }
    }

    /// String-only coding key: JSON objects have no integer keys.
    struct RawKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

/// One element of the persisted array, decoded twice from the same decoder:
/// once as the untyped tree (which cannot fail) and once as the real type
/// (which can). Decoding *the element* rather than stepping an unkeyed
/// container by hand is what keeps this safe — a failed `decode` on an unkeyed
/// container leaves `currentIndex` in an implementation-defined place, whereas
/// each `RawLibraryEntry` is handed its own element decoder.
private struct RawLibraryEntry: Decodable {
    /// nil when this build cannot read the element.
    let entry: LibraryEntry?
    /// The untyped tree — built **only** when the typed decode failed, because
    /// that is the only case quarantine needs it for.
    ///
    /// This ordering is a launch-path requirement, not a style choice.
    /// `RawJSON`'s decode walks a `try?` ladder per scalar, and Swift's Codable
    /// failure path allocates a `DecodingError` with a coding-path array for
    /// every miss — a `NineGame` is ~250 numbers, so building the tree costs
    /// far more than decoding the real type. Measured on a full 60-entry
    /// library (a 502 KB blob, the `totalCap` worst case): eager trees took
    /// **950 ms**, lazy takes **~50 ms**, against a cold-launch budget of
    /// 800 ms for the whole app. Since a healthy library has zero undecodable
    /// elements, the tolerance now costs essentially nothing until the day it
    /// is actually needed.
    let raw: RawJSON?

    init(from decoder: Decoder) throws {
        // Decoded twice from this element's own decoder rather than by stepping
        // an unkeyed container by hand, where a failed `decode` leaves
        // `currentIndex` in an implementation-defined place.
        if let entry = try? LibraryEntry(from: decoder) {
            self.entry = entry
            self.raw = nil
        } else {
            self.entry = nil
            self.raw = (try? RawJSON(from: decoder)) ?? .null
        }
    }
}
