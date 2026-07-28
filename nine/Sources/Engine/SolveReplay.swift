// SolveReplay.swift — the immutable record of how one board actually went
// (PRD-26 §3.2), and the vault that holds them.
//
// The move log has been append-only since 1.0 and logs undo as an *event*
// rather than popping it (`Game.swift`). That decision is what makes this
// possible at all: a log that pops its undos records a tidied path nobody
// walked, and the whole point of a replay is that it shows the path that was.
//
// **Immutable, and the type enforces it rather than asking.** Every field is a
// `let`, there is no mutating member and no setter. A replay is a record of
// something that already happened; there is no correct reason to edit one.
// `ReplayVault.store` will *replace* a board's record when a genuinely newer
// solve arrives (a daily replayed after solving reuses its day slot —
// `BoardLibrary.adoptDaily`), which is not the same thing: the old record is
// discarded whole, never amended.
//
// Pure Foundation plus the Engine's own types, so it tests on Linux.
import Foundation
import CouchCore

/// One solve, packed.
///
/// The split between "metadata as ordinary `Codable` fields" and "the log as an
/// opaque `Data`" is the design, not a convenience. Metadata has to survive
/// schema evolution — a band raw value this build has never heard of must be
/// carried, not choked on — and JSON with tolerant decoding is what this repo
/// already knows how to do that with. The log is pure bounded integers with no
/// schema risk at all, and it is the part that is 40× too big in JSON: 1.1
/// spells one `LoggedMove` in ~48 bytes and a long Nocturne runs past 400 moves.
public struct SolveReplay: Sendable, Equatable, Codable {

    /// The `LibraryEntry` this replay is about. The vault is keyed on it and
    /// pruned against the library by it.
    public let boardID: UUID
    public let solvedAt: Date
    /// `Difficulty.rawValue`, **as a string, deliberately**.
    ///
    /// A replay is a record, so an unknown band is data it should carry
    /// verbatim rather than a decode it should fail. Keeping the raw value also
    /// costs nothing at the point of use: PRD-20 found the raw values *are* the
    /// localization identity, so the caption is
    /// `difficulty.\(band).title` either way and a `Difficulty` round-trip
    /// would only add a way to lose one.
    public let band: String
    public let isDaily: Bool
    /// Wall-clock seconds the solve took, from the board's own timer.
    public let seconds: TimeInterval
    /// Puzzle grid + move log, in the format `pack`/`unpack` below define.
    public let packed: Data

    public init(
        boardID: UUID,
        solvedAt: Date,
        band: String,
        isDaily: Bool,
        seconds: TimeInterval,
        packed: Data
    ) {
        self.boardID = boardID
        self.solvedAt = solvedAt
        self.band = band
        self.isDaily = isDaily
        self.seconds = seconds
        self.packed = packed
    }

    /// Mint a replay from a finished board. Returns nil when there is nothing
    /// to replay — a board whose log is empty, which is the ordinary state of
    /// every board that arrived over CloudKit (`SyncedEntry` strips the log by
    /// design) and every widget or watch solve.
    ///
    /// Nil is the honest answer there, and PRD-26 §2.4 is what the share chip
    /// does about it: it falls back to the still card rather than vanishing.
    public init?(
        boardID: UUID,
        game: NineGame,
        band: String,
        isDaily: Bool,
        solvedAt: Date,
        seconds: TimeInterval
    ) {
        guard !game.moveLog.isEmpty else { return nil }
        self.init(
            boardID: boardID,
            solvedAt: solvedAt,
            band: band,
            isDaily: isDaily,
            seconds: seconds,
            packed: SolveReplay.pack(puzzle: game.puzzle.puzzle.cells, moves: game.moveLog)
        )
    }

    /// The board as it was handed to the player: 81 cells, 0 for a hole.
    /// Held inside the replay rather than looked up, so a record is
    /// self-contained — which is the property an immutable record is for.
    public var puzzle: [Int]? { SolveReplay.unpack(packed)?.puzzle }

    /// The path, in order.
    public var moves: [LoggedMove] { SolveReplay.unpack(packed)?.moves ?? [] }

    /// Did the player's device record timing? False for every board solved
    /// before PRD-26 and every board whose log came from somewhere else.
    public var isTimed: Bool { SolveReplay.unpack(packed)?.timed ?? false }

    // MARK: - The packed format

    /// ```
    /// 0   3   magic 'N' '9' 'R'
    /// 3   1   version (1)
    /// 4   1   flags — bit 0: the log carries timing
    /// 5   2   move count, little-endian UInt16
    /// 7   81  puzzle grid, one byte per cell, 0...9
    /// 88  n×2 moves, or n×4 when timed
    /// ```
    ///
    /// A move is `kind << 4 | digit` then `cell`, and when timed a
    /// little-endian UInt16 of **deciseconds since the previous move**.
    ///
    /// Delta-encoded rather than absolute, and that is the one arithmetic
    /// decision worth defending. An absolute UInt16 of deciseconds tops out at
    /// 6553 s — 109 minutes — which a leisurely Abyss can genuinely exceed, and
    /// the failure mode is every move after the ceiling collapsing onto the
    /// same instant. A *delta* of 109 minutes is a gap no session contains,
    /// because `ElapsedTimer` pauses when the app leaves the foreground, so the
    /// saturation below is unreachable in practice rather than merely unlikely.
    /// Total elapsed time is unbounded either way: it is the prefix sum.
    static let magic: [UInt8] = [0x4E, 0x39, 0x52] // "N9R"
    static let version: UInt8 = 1
    static let headerSize = 7
    static let gridSize = 81
    static let timedFlag: UInt8 = 0x01

    public static func pack(puzzle: [Int], moves: [LoggedMove]) -> Data {
        // Timed is a property of the *log*, not of a move. A log where some
        // moves carry `at` and some do not cannot be replayed at either cadence
        // honestly, so the conservative reading wins: it is timed only when
        // every move says when it happened.
        let timed = !moves.isEmpty && moves.allSatisfy { $0.at != nil }
        let count = min(moves.count, Int(UInt16.max))

        var bytes = magic
        bytes.append(version)
        bytes.append(timed ? timedFlag : 0)
        bytes.append(UInt8(count & 0xFF))
        bytes.append(UInt8((count >> 8) & 0xFF))
        bytes.append(contentsOf: (0..<gridSize).map { index in
            UInt8(clamping: index < puzzle.count ? puzzle[index] : 0)
        })

        var previous: TimeInterval = 0
        for move in moves.prefix(count) {
            bytes.append(kindCode(move.kind) << 4 | UInt8(clamping: move.digit))
            bytes.append(UInt8(clamping: move.cell))
            guard timed, let at = move.at else { continue }
            let delta = max(0, at - previous)
            let deciseconds = UInt16(clamping: Int((delta * 10).rounded()))
            bytes.append(UInt8(deciseconds & 0xFF))
            bytes.append(UInt8(deciseconds >> 8))
            previous = at
        }
        return Data(bytes)
    }

    /// Total, and nil rather than throwing. A `CouchStored` blob that throws is
    /// discarded whole, and this one holds every replay the player has.
    public static func unpack(_ data: Data) -> (puzzle: [Int], moves: [LoggedMove], timed: Bool)? {
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize + gridSize,
              Array(bytes[0..<3]) == magic,
              bytes[3] == version else { return nil }

        let timed = bytes[4] & timedFlag != 0
        let count = Int(bytes[5]) | Int(bytes[6]) << 8
        let stride = timed ? 4 : 2
        let bodyStart = headerSize + gridSize
        // Refuse a buffer that promises more moves than it carries rather than
        // returning the prefix it happens to hold: a half-read replay is a
        // drawing of a solve that did not happen.
        guard bytes.count >= bodyStart + count * stride else { return nil }

        let puzzle = (0..<gridSize).map { Int(bytes[headerSize + $0]) }
        guard puzzle.allSatisfy({ (0...9).contains($0) }) else { return nil }

        var moves: [LoggedMove] = []
        moves.reserveCapacity(count)
        var elapsed: TimeInterval = 0
        for index in 0..<count {
            let offset = bodyStart + index * stride
            guard let kind = kindValue(bytes[offset] >> 4) else { return nil }
            let digit = Int(bytes[offset] & 0x0F)
            let cell = Int(bytes[offset + 1])
            guard (0..<81).contains(cell), (0...9).contains(digit) else { return nil }
            var at: TimeInterval?
            if timed {
                elapsed += TimeInterval(Int(bytes[offset + 2]) | Int(bytes[offset + 3]) << 8) / 10
                at = elapsed
            }
            moves.append(LoggedMove(kind: kind, cell: cell, digit: digit, at: at))
        }
        return (puzzle, moves, timed)
    }

    /// The wire codes. A `switch` rather than an index into `allCases`, so
    /// appending a `LoggedMove.Kind` case stops compiling here instead of
    /// silently renumbering every replay already on disk.
    static func kindCode(_ kind: LoggedMove.Kind) -> UInt8 {
        switch kind {
        case .place: return 0
        case .erase: return 1
        case .pencil: return 2
        case .undo: return 3
        }
    }

    static func kindValue(_ code: UInt8) -> LoggedMove.Kind? {
        switch code {
        case 0: return .place
        case 1: return .erase
        case 2: return .pencil
        case 3: return .undo
        default: return nil
        }
    }

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey {
        case boardID, solvedAt, band, isDaily, seconds, packed
    }

    /// Throws on a shape it cannot read, deliberately — the opposite of the
    /// rule everywhere else, and for the same reason `SolveRecord` throws:
    /// `ReplayVault` decodes its elements individually and drops the ones that
    /// fail, so throwing here quarantines *one* replay while swallowing the
    /// error would fabricate one.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        boardID = try c.decode(UUID.self, forKey: .boardID)
        solvedAt = try c.decode(Date.self, forKey: .solvedAt)
        band = try c.decode(String.self, forKey: .band)
        isDaily = (try? c.decode(Bool.self, forKey: .isDaily)) ?? false
        seconds = (try? c.decode(TimeInterval.self, forKey: .seconds)) ?? 0
        packed = try c.decode(Data.self, forKey: .packed)
    }
}

/// Every replay this device holds, in its own top-level `CouchStored` blob
/// (`nine.replays`) — not a field on `LibraryEntry` (PRD-26 §4).
///
/// Field-level preservation on `LibraryEntry` was implemented, measured at
/// 1515 ms against a 49 ms baseline, and reverted; a sibling blob is what that
/// measurement bought.
///
/// **Pruned with the library**, which is the opposite call from `CoachProgress`
/// and deliberately so. A replay is about a *board*: when the board goes, the
/// replay has nothing left to be about. `CoachProgress` is about the *person*,
/// so it must outlive every board they ever played. Modelled on
/// `CoachLedger.prune(to:)`, which solves the same problem for the same reason.
public struct ReplayVault: Codable, Equatable, Sendable {

    /// One per library slot, which is the most boards that can be live at once.
    public static let capacity = 60

    private var replays: [String: SolveReplay]
    /// Insertion order, for the capacity trim — the same shape and the same
    /// reason as `CoachLedger`: "which to drop" needs an order a dictionary
    /// cannot give.
    private var order: [String]

    public init() {
        replays = [:]
        order = []
    }

    public var count: Int { replays.count }

    public func replay(for boardID: UUID) -> SolveReplay? {
        replays[boardID.uuidString]
    }

    /// Keep a replay. A record already held is **not** amended — it is either
    /// left alone or replaced whole by a strictly newer solve of the same
    /// board, which is what a daily replayed after solving produces
    /// (`BoardLibrary.adoptDaily` reuses the day's slot).
    public mutating func store(_ replay: SolveReplay) {
        let key = replay.boardID.uuidString
        if let existing = replays[key] {
            guard replay.solvedAt > existing.solvedAt else { return }
        } else {
            order.append(key)
        }
        replays[key] = replay
        trim()
    }

    /// Drop every replay whose board has left the library.
    public mutating func prune(to liveIDs: Set<String>) {
        guard !liveIDs.isEmpty else { return }
        for key in order where !liveIDs.contains(key) {
            replays.removeValue(forKey: key)
        }
        order = order.filter { replays[$0] != nil }
    }

    private mutating func trim() {
        while order.count > Self.capacity {
            replays.removeValue(forKey: order.removeFirst())
        }
    }

    /// One carried element as standalone JSON, so the real type can be decoded
    /// straight out of it — `QuarantinedEntry.rawJSON`'s trick, and the same
    /// sorted-keys convention. The date inside is already an ISO-8601 *string*
    /// by the time it reaches `RawJSON`, so a plain encoder re-emits it verbatim
    /// and `CouchJSON.decode`'s `.iso8601` strategy reads it back.
    private static func standaloneJSON(_ value: RawJSON) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey { case replays, order }

    /// Nothing in here throws — `CouchStored` discards the whole blob when a
    /// decode does, and this one holds every replay the player has.
    ///
    /// **Two passes, and the second one almost never runs.** `[String:
    /// SolveReplay]` decodes as a unit, so one unreadable record would take the
    /// other fifty-nine with it — Phase 0's `BoardLibrary` lesson exactly. But
    /// the per-element walk that fixes it is the shape whose `LibraryEntry`
    /// version measured 1515 ms against a 49 ms baseline, and this decode is on
    /// the same 800 ms launch path.
    ///
    /// So the fast path is tried first and costs nothing extra when it works,
    /// which is every launch where no record is corrupt; the per-element
    /// quarantine is the fallback, and pays its cost only on the blob that
    /// needs it.
    public init(from decoder: any Decoder) throws {
        replays = [:]
        order = []
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        if let whole = try? c.decode([String: SolveReplay].self, forKey: .replays) {
            replays = whole
        } else if let raw = try? c.decode([String: RawJSON].self, forKey: .replays) {
            for (key, value) in raw {
                guard let data = try? Self.standaloneJSON(value),
                      let replay = try? CouchJSON.decode(SolveReplay.self, from: data)
                else { continue }
                replays[key] = replay
            }
        }
        order = (try? c.decode([String].self, forKey: .order)) ?? []
        // Repair, so a hand-edited or half-written blob still trims
        // deterministically — `CoachProgress`'s rule, verbatim.
        let placed = Set(order)
        order.append(contentsOf: replays.keys.filter { !placed.contains($0) }.sorted())
        order = order.filter { replays[$0] != nil }
        trim()
    }
}
