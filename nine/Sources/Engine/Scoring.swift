// Scoring.swift — points and the solve-history log. Pure and Codable like
// the rest of the engine: the app persists a SolveHistory value as-is and
// mirrors totals into Game Center; nothing here touches UI or wall clocks.
import Foundation

/// Points awarded for one solved board. The values are deliberately chunky
/// (100-point base steps) so a session's total feels like a score, not a
/// checksum.
public enum SolveScore {
    /// Longest streak that still grows the daily bonus (30 days).
    public static let streakBonusCap = 30
    /// Solves faster than this earn the speed bonus.
    public static let speedBonusThreshold: TimeInterval = 300

    public static func points(
        difficulty: Difficulty,
        isDaily: Bool,
        streak: Int,
        seconds: TimeInterval
    ) -> Int {
        var points: Int
        switch difficulty {
        case .gentle: points = 100
        case .steady: points = 250
        case .sharp: points = 500
        case .nocturne: points = 800
        case .tempest: points = 1200
        case .abyss: points = 1600
        }
        if isDaily {
            points += 50 + 25 * max(0, min(streak, streakBonusCap))
        }
        if seconds > 0, seconds < speedBonusThreshold {
            points += 50
        }
        return points
    }
}

/// One finished board.
///
/// **The band is persisted twice, on purpose.** `nine.history` is a
/// `cloudSynced` `CouchStored` blob, and every build Nine has ever shipped
/// decodes it through a *synthesized* `[SolveRecord]` decode — so one record
/// carrying a `Difficulty` raw value that build has never heard of throws the
/// whole array, `CouchStore`'s `try?` swallows the throw, and the player loses
/// every solve they have ever recorded. On the old device first, and then
/// everywhere, because KVS is last-writer-wins. Tolerance added *here* cannot
/// help: the build that throws is already in the wild.
///
/// So a band added after 1.5 writes two keys. `difficulty` holds the nearest
/// band an old build can read (`Difficulty.wireBand`), and `band` holds the
/// true identity — an unknown key, which every `Codable` decode ignores. The old
/// build reads a complete history with the new solve shown as Sharp; this build
/// reads `band` first and gets Nocturne back. The three bands that shipped in
/// 1.5 write no sibling at all, so their bytes are unchanged.
///
/// The accepted cost, and it is real: an old build re-encodes from its typed
/// value, so once a downgraded device *writes the history back*, the sibling is
/// gone and the solve is permanently Sharp. The solve, its date, its time and
/// its points all survive — only the band label is lost. See
/// `DowngradeDrillTests`, which asserts exactly that.
public struct SolveRecord: Sendable, Codable, Equatable, Identifiable {
    public var id: Double { date.timeIntervalSinceReferenceDate }
    public let date: Date
    public let difficulty: Difficulty
    public let isDaily: Bool
    public let seconds: TimeInterval
    public let points: Int

    /// Wrong digits placed during this solve (`NineGame.errorCount` at the
    /// moment it finished), or nil when no `NineGame` was in scope to read it
    /// from. That covers every solve recorded through
    /// `recordSolveMadeElsewhere` — widget and watch solves both route through
    /// there — plus every record written before this field existed. Unlike
    /// the band below, a plain optional is enough: there is no unrecognised
    /// value to preserve, and a downgraded build was never taught this key in
    /// the first place, so it has nothing to carry across a round-trip.
    public let errors: Int?

    /// A band id this build does not recognise, held verbatim so a downgrade
    /// from a *future* release does not silently rewrite the record as Sharp.
    /// Nil for every band this build ships. Part of `==`: two records that will
    /// re-encode differently are not the same record.
    private let unrecognisedBand: String?

    /// The downgrade-safe stand-in the *writer* chose, held alongside its band
    /// id. A future band need not degrade to Sharp — one pitched between Steady
    /// and Sharp would write `steady` — and rewriting that to `sharp` on the way
    /// out is the same restating error in the other direction. Nil unless
    /// `unrecognisedBand` is set.
    private let carriedWireBand: String?

    public init(date: Date, difficulty: Difficulty, isDaily: Bool, seconds: TimeInterval, points: Int, errors: Int? = nil) {
        self.date = date
        self.difficulty = difficulty
        self.isDaily = isDaily
        self.seconds = seconds
        self.points = points
        self.errors = errors
        self.unrecognisedBand = nil
        self.carriedWireBand = nil
    }

    private enum CodingKeys: String, CodingKey {
        case date, difficulty, isDaily, seconds, points, band, errors
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Not `try?`: a record whose *shape* this build cannot read is junk, and
        // `SolveHistory` quarantines it rather than storing a fabricated solve.
        date = try c.decode(Date.self, forKey: .date)
        isDaily = try c.decode(Bool.self, forKey: .isDaily)
        seconds = try c.decode(TimeInterval.self, forKey: .seconds)
        points = try c.decode(Int.self, forKey: .points)
        errors = try c.decodeIfPresent(Int.self, forKey: .errors)

        // The sibling wins when it is present: it is the true band, and the
        // `difficulty` beside it is only the downgrade-safe stand-in.
        if let sibling = try c.decodeIfPresent(String.self, forKey: .band) {
            let standIn = try? c.decodeIfPresent(String.self, forKey: .difficulty)
            if let known = Difficulty(rawValue: sibling) {
                difficulty = known
                unrecognisedBand = nil
                carriedWireBand = nil
            } else {
                // A band from a release that has not shipped yet. Show it as the
                // stand-in its own writer picked — that is the band it chose to
                // be mistaken for — and keep both halves verbatim for the way
                // out. Never a throw, and never a restating of either half.
                difficulty = standIn.flatMap(Difficulty.init(rawValue:)) ?? .sharp
                unrecognisedBand = sibling
                carriedWireBand = standIn
            }
        } else {
            // No sibling, so `difficulty` is the whole truth — and it has to be
            // a string. Anything else is a record whose *shape* changed, which
            // is junk to this build: let it throw so `SolveHistory` quarantines
            // it verbatim rather than storing a fabricated Sharp solve and
            // writing that over the real one on the next autosave.
            let raw = try c.decode(String.self, forKey: .difficulty)
            difficulty = Difficulty(rawValue: raw) ?? .sharp
            unrecognisedBand = Difficulty(rawValue: raw) == nil ? raw : nil
            carriedWireBand = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(isDaily, forKey: .isDaily)
        try c.encode(seconds, forKey: .seconds)
        try c.encode(points, forKey: .points)
        try c.encodeIfPresent(errors, forKey: .errors)
        if let band = unrecognisedBand {
            try c.encode(carriedWireBand ?? difficulty.wireBand.rawValue, forKey: .difficulty)
            try c.encode(band, forKey: .band)
        } else {
            try c.encode(difficulty.wireBand.rawValue, forKey: .difficulty)
            if let sibling = difficulty.bandSibling { try c.encode(sibling, forKey: .band) }
        }
    }
}

extension Difficulty {
    /// The band an older build should see this one as. Every band that shipped
    /// in 1.5 is its own wire band; bands added since degrade to the nearest
    /// one below them, so no shipped decoder ever meets a raw value it cannot
    /// resolve. Deliberately not `CaseIterable`-driven — a band's downgrade
    /// target is a product decision, not a position in a list.
    var wireBand: Difficulty {
        switch self {
        case .gentle, .steady, .sharp: return self
        // Nocturne, Tempest and Abyss all degrade to Sharp, and all three for
        // the same reason: Sharp is the deepest band every *shipped* decoder
        // knows. Degrading Tempest to Nocturne would be truer and would take
        // the history down on any build from before PRD-17, which is most of
        // them. The stand-in is bounded by what is in the wild, not by what is
        // in this file.
        case .nocturne, .tempest, .abyss: return .sharp
        }
    }

    /// The band id to write into the `band` sibling, or nil when `difficulty`
    /// already carries the truth.
    var bandSibling: String? { wireBand == self ? nil : rawValue }
}

/// One day's worth of solves, for the History heat grid. `hasDaily` lights
/// the cell at full accent strength (a daily solve is the streak-worthy one).
public struct DaySolves: Sendable, Equatable {
    public let count: Int
    public let hasDaily: Bool
    public init(count: Int, hasDaily: Bool) {
        self.count = count
        self.hasDaily = hasDaily
    }
}

/// The rolling log of finished boards, newest first, capped so the value
/// stays small enough to mirror through iCloud KVS alongside the streak.
/// 1000 records ≈ 110 KB — a daily solver fills 200 in ~7 months and the
/// heat grid would silently truncate, so the ceiling is generous (PRD-9 §3).
///
/// **The persistence covenant, extended to `nine.history`.** `BoardLibrary` got
/// this in Phase 0 and this type did not, which made the history the softest
/// blob Nine persists: it is `cloudSynced`, so it is the one a mixed-version
/// player's two devices fight over, and its synthesized decode threw the whole
/// log on a single unreadable record. It now follows the same two rules —
/// *never throw out of a container decode, never delete what you cannot read* —
/// with the same machinery: elements this build cannot type are quarantined
/// verbatim and re-emitted into the same `records` array, and unknown siblings
/// of `records` are carried. See `SolveRecord` for the separate, wire-level
/// problem that a new `Difficulty` case creates for builds already shipped.
public struct SolveHistory: Sendable, Codable, Equatable {
    public static let capacity = 1000

    public private(set) var records: [SolveRecord]

    /// Elements of the persisted `records` array this build could not decode,
    /// held verbatim. Invisible to every query and to `capacity` — nothing here
    /// can read their date or their points, so counting them would be a lie.
    public private(set) var quarantined: [QuarantinedEntry]

    /// Unknown siblings of `records` at the top level of the blob, carried so an
    /// older build's rewrite does not strip a newer build's key.
    private var carriedTopLevel: [String: RawJSON]

    public init() {
        records = []
        quarantined = []
        carriedTopLevel = [:]
    }

    /// `==` is `records` only. The carried trees are an encoding detail, not
    /// identity, and every test and caller builds a `SolveHistory()` by hand.
    public static func == (lhs: SolveHistory, rhs: SolveHistory) -> Bool {
        lhs.records == rhs.records
    }

    public mutating func record(_ record: SolveRecord) {
        records.insert(record, at: 0)
        if records.count > Self.capacity {
            records.removeLast(records.count - Self.capacity)
        }
    }

    // MARK: - Coding (the persistence covenant)

    private enum CodingKeys: String, CodingKey { case records }

    /// Version-tolerant, element-preserving decode. Nothing in here throws.
    public init(from decoder: Decoder) throws {
        records = []
        quarantined = []
        carriedTopLevel = [:]
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        if let anyKey = try? decoder.container(keyedBy: RawJSON.RawKey.self) {
            for key in anyKey.allKeys where key.stringValue != CodingKeys.records.stringValue {
                carriedTopLevel[key.stringValue] = (try? anyKey.decode(RawJSON.self, forKey: key)) ?? .null
            }
        }
        guard let raw = try? container.decode([RawSolveRecord].self, forKey: .records) else { return }
        for element in raw {
            if let record = element.record {
                records.append(record)
            } else {
                quarantined.append(QuarantinedEntry(element.raw ?? .null))
            }
        }
        // Newest-first is a contract, not a convention: `capacity` prunes the
        // tail as the oldest, `trend(window:)` reads `prefix` as the most
        // recent, and both the History sheet and `WidgetBridge` take the head.
        // A build that could not read some elements re-emits them *after* the
        // ones it could — it has no way to read their dates — so the build that
        // gets them back has to restore the order. `BoardLibrary.init(from:)`
        // closes the same loop for the same reason.
        records.sort { $0.date > $1.date }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RawJSON.RawKey.self)
        for key in carriedTopLevel.keys.sorted() {
            try container.encode(carriedTopLevel[key]!, forKey: RawJSON.RawKey(key))
        }
        var array = container.nestedUnkeyedContainer(
            forKey: RawJSON.RawKey(CodingKeys.records.stringValue)
        )
        for record in records { try array.encode(record) }
        for element in quarantined { try array.encode(element) }
    }

    public var totalPoints: Int {
        records.reduce(0) { $0 + $1.points }
    }

    public func count(of difficulty: Difficulty) -> Int {
        records.count(where: { $0.difficulty == difficulty })
    }

    /// Fastest recorded solve of this difficulty, nil when none exist.
    public func bestSeconds(for difficulty: Difficulty) -> TimeInterval? {
        records.lazy.filter { $0.difficulty == difficulty }.map(\.seconds).min()
    }

    /// Mean solve time for this difficulty, nil when none exist.
    public func averageSeconds(for difficulty: Difficulty) -> TimeInterval? {
        let times = records.lazy.filter { $0.difficulty == difficulty }.map(\.seconds)
        var sum: TimeInterval = 0
        var n = 0
        for t in times { sum += t; n += 1 }
        return n == 0 ? nil : sum / TimeInterval(n)
    }

    /// Buckets solves by their local day ordinal within `ordinalRange`. Days
    /// with no solves are absent; the caller defaults them to an empty cell.
    public func solvesByDay(
        ordinalRange: ClosedRange<Int>,
        calendar: Calendar = .current
    ) -> [Int: DaySolves] {
        var byDay: [Int: (count: Int, hasDaily: Bool)] = [:]
        for record in records {
            let ordinal = DailySeed.dayOrdinal(for: record.date, calendar: calendar)
            guard ordinalRange.contains(ordinal) else { continue }
            var entry = byDay[ordinal] ?? (0, false)
            entry.count += 1
            entry.hasDaily = entry.hasDaily || record.isDaily
            byDay[ordinal] = entry
        }
        return byDay.mapValues { DaySolves(count: $0.count, hasDaily: $0.hasDaily) }
    }

    /// Rolling-mean solve-time trend over the most recent `window` solves,
    /// oldest→newest, for the History sparkline. Smoothed by a trailing
    /// sub-window so one fast solve nudges the line rather than spiking it.
    /// Empty below two solves (nothing to trend).
    public func trend(window: Int) -> [TimeInterval] {
        // records is newest-first; take the last `window`, chronological.
        let recent = Array(records.prefix(max(0, window)).reversed()).map(\.seconds)
        guard recent.count >= 2 else { return [] }
        let sub = max(1, recent.count / 4)
        return recent.indices.map { i in
            let lower = max(0, i - sub + 1)
            let slice = recent[lower...i]
            return slice.reduce(0, +) / TimeInterval(slice.count)
        }
    }
}

/// One element of the persisted `records` array, decoded twice from the same
/// decoder: once as the real type (which can fail) and, only then, as the
/// untyped tree the quarantine needs. Same shape and the same laziness as
/// `RawLibraryEntry` — see its header for the measurement behind the ordering.
/// A `SolveRecord` is five scalars rather than a `NineGame`'s ~250 numbers, so
/// the cost here is far below the library's, but the rule is the rule.
private struct RawSolveRecord: Decodable {
    /// nil when this build cannot read the element.
    let record: SolveRecord?
    /// The untyped tree — built **only** when the typed decode failed.
    let raw: RawJSON?

    init(from decoder: Decoder) throws {
        if let record = try? SolveRecord(from: decoder) {
            self.record = record
            self.raw = nil
        } else {
            self.record = nil
            self.raw = (try? RawJSON(from: decoder)) ?? .null
        }
    }
}
