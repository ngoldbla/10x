// Duel.swift — two people, one board, alternating timed turns (PRD-27).
//
// **The one idea: a turn is a window on the board's own clock.** There is no
// second clock anywhere in this feature. `NineGame.timer` already pauses for
// sheets and for scene backgrounding, and already stamps every `LoggedMove.at`,
// so a turn is three numbers against that one axis — who, from which move, from
// which elapsed second.
//
// Both facts the feature needs fall out of that:
//
//   * the deadline is `turnLength - (elapsed - startedAt)`, which inherits every
//     pause the board clock already takes, so backgrounding the app mid-turn
//     cannot eat a turn;
//   * attribution is a search over turn boundaries, because turns are
//     *contiguous ranges* of the move log.
//
// That second consequence is what keeps this file out of the Engine. Undo is
// logged as an event and never pops the log (a 1.0 decision PRD-26 spent), so
// move indices are monotone forever and a range is never invalidated by a later
// move. `LoggedMove` gains nothing, `NineGame`'s bytes do not move, and
// `SolveReplay.packed` keeps its version byte — so nothing the golden corpus
// hashes is in this diff, which is a stronger statement than "the corpus was
// run and passed".
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

/// How long one turn lasts, chosen when the duel starts.
///
/// A per-duel setup choice and deliberately **not** a settings row: the covenant
/// makes those expensive (PRD-31 deferred a handedness pref on exactly this
/// ground), and a choice made on the way into a mode costs nothing, the same way
/// picking a difficulty does.
public enum DuelTurnLength: Int, Codable, Sendable, CaseIterable {
    case brisk = 60
    case standard = 90
    case unhurried = 180
}

/// One turn: who took it, where in the move log it starts, and when on the
/// board's clock it began.
///
/// There is no end index and no end time, on purpose. A turn ends exactly where
/// the next one begins and the last turn is open-ended — storing both ends would
/// be two places for one fact to be written and one place for them to disagree.
public struct DuelTurn: Codable, Equatable, Sendable {
    public let player: Int
    public let firstMoveIndex: Int
    public let startedAt: TimeInterval

    public init(player: Int, firstMoveIndex: Int, startedAt: TimeInterval) {
        self.player = player
        self.firstMoveIndex = firstMoveIndex
        self.startedAt = startedAt
    }
}

/// Everything a duel is, and nothing else.
///
/// No `Date` anywhere in here: every time is board-elapsed seconds, which is
/// what makes this type as replayable as the move log it indexes and what stops
/// a duel resumed after midnight believing a turn ran for nine hours.
public struct DuelState: Codable, Equatable, Sendable {

    /// Two, and the type says so rather than a comment. "Pass the remote" means
    /// two hands, and a tint pair is only separable across three dichromacies
    /// because there are two of them (PRD-27 §12).
    public static let seats = 2

    /// The two players' accent raw values, player 0 first.
    public let accents: [String]
    public let turnLength: DuelTurnLength
    public private(set) var turns: [DuelTurn]

    public init(accents: [String], turnLength: DuelTurnLength, turns: [DuelTurn] = []) {
        self.accents = DuelState.seated(accents)
        self.turnLength = turnLength
        self.turns = turns
    }

    /// Player One is the player's own accent; Player Two is derived (§6).
    public init(accent: String, isLight: Bool, turnLength: DuelTurnLength) {
        self.init(
            accents: [accent, DuelTint.partner(for: accent, isLight: isLight)],
            turnLength: turnLength
        )
    }

    /// A duel is always two seats. A state arriving with a different number — a
    /// newer build with a third player, a truncated blob — is *repaired* rather
    /// than rejected, because the board it belongs to is fine and the
    /// alternative is losing a ledger over a cosmetic field.
    private static func seated(_ raw: [String]) -> [String] {
        var seats = Array(raw.prefix(DuelState.seats))
        while seats.count < DuelState.seats {
            seats.append(DuelTint.partner(for: seats.first ?? "glacier", isLight: false))
        }
        return seats
    }

    public var currentPlayer: Int { turns.last?.player ?? 0 }

    public func accent(forPlayer player: Int) -> String {
        accents.indices.contains(player) ? accents[player] : accents[0]
    }

    /// Whose digit this is. Nil only before the first turn has begun.
    ///
    /// A linear reverse scan rather than a binary search, and that is a measured
    /// non-decision rather than an oversight: turn counts are in the tens, and
    /// the hot call site builds a whole cell→owner map once per board draw
    /// instead of asking 81 times. Binary search here would be a cleverness with
    /// no number behind it.
    public func player(forMoveIndex index: Int) -> Int? {
        for turn in turns.reversed() where turn.firstMoveIndex <= index {
            return turn.player
        }
        return nil
    }

    /// Seconds left in the current turn, clamped at zero, or nil before the
    /// first turn begins. Never negative: a chip does not show -04:12.
    public func remaining(atElapsed elapsed: TimeInterval) -> TimeInterval? {
        guard let turn = turns.last else { return nil }
        return max(0, Double(turnLength.rawValue) - (elapsed - turn.startedAt))
    }

    /// Close the open turn and open the next.
    ///
    /// The caller applies the quiet correction *first* — see `DuelSession` and
    /// PRD-27 §5. The order is load-bearing: an erase logged after this index is
    /// taken lands inside the incoming player's range and is credited to the
    /// wrong hand.
    public mutating func beginTurn(player: Int, firstMoveIndex: Int, startedAt: TimeInterval) {
        turns.append(DuelTurn(player: player, firstMoveIndex: firstMoveIndex, startedAt: startedAt))
    }

    enum CodingKeys: String, CodingKey { case accents, turnLength, turns }

    /// Tolerant in every field, because `CouchStored` discards the whole blob
    /// when a decode throws.
    ///
    /// Note `try?` on each field rather than `try … ?? default`: the second
    /// spelling survives an *absent* key and still throws on a key of the wrong
    /// *type*, which is the bug `QuietPresenceTests` found in three scalars of
    /// four (PRD-30).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accents = DuelState.seated((try? c.decode([String].self, forKey: .accents)) ?? [])
        turnLength = (try? c.decode(DuelTurnLength.self, forKey: .turnLength)) ?? .standard
        turns = (try? c.decode([DuelTurn].self, forKey: .turns)) ?? []
    }
}

/// `[boardID: DuelState]` — PRD-27's `nine.duel`.
///
/// A **sibling top-level key** rather than a field on `LibraryEntry`, which is
/// EXECUTING-A-PRD §2's rule satisfied structurally rather than by discipline:
/// nothing an older build decodes "successfully" can erase this on its next
/// autosave, because an older build never reads or writes this key at all.
///
/// Local-only. A duel is a couch, not a cloud (PRD-27 §12).
public struct DuelLedger: Codable, Equatable, Sendable {

    /// `ReplayVault.capacity`, for its reason and by no coincidence: the two
    /// blobs have identical lifetimes, because a duel board is a library board
    /// and a duel that outlives its board is unreachable.
    public static let capacity = 60

    private var states: [UUID: DuelState] = [:]
    private var order: [UUID] = []

    public init() {}

    public var count: Int { states.count }

    public subscript(boardID: UUID) -> DuelState? { states[boardID] }

    public mutating func set(_ state: DuelState, for boardID: UUID) {
        if states[boardID] == nil { order.append(boardID) }
        states[boardID] = state
        trim()
    }

    public mutating func remove(_ boardID: UUID) {
        states[boardID] = nil
        order.removeAll { $0 == boardID }
    }

    /// Drop every duel whose board is gone.
    ///
    /// Refuses an empty live set — `ReplayVault`'s rule, for its reason: an
    /// empty library is far more often one that has not finished loading than
    /// one the player emptied, and deletion has its own door above.
    public mutating func prune(to live: Set<UUID>) {
        guard !live.isEmpty else { return }
        for id in order where !live.contains(id) { states[id] = nil }
        order.removeAll { states[$0] == nil }
    }

    private mutating func trim() {
        while order.count > DuelLedger.capacity {
            states[order.removeFirst()] = nil
        }
    }

    enum CodingKeys: String, CodingKey { case states, order }

    /// Per-element quarantine, so one unreadable duel costs one duel rather
    /// than the ledger.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decode([String: DuelState].self, forKey: .states)) ?? [:]
        for (key, value) in raw {
            guard let id = UUID(uuidString: key) else { continue }
            states[id] = value
        }
        let claimed = (try? c.decode([String].self, forKey: .order)) ?? []
        order = claimed.compactMap(UUID.init(uuidString:)).filter { states[$0] != nil }
        // Repair: anything present but unordered goes to the back, so a
        // hand-edited or partially written blob still trims deterministically
        // rather than growing without bound.
        for id in states.keys.sorted(by: { $0.uuidString < $1.uuidString })
        where !order.contains(id) {
            order.append(id)
        }
        trim()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(
            Dictionary(uniqueKeysWithValues: states.map { ($0.key.uuidString, $0.value) }),
            forKey: .states
        )
        try c.encode(order.map(\.uuidString), forKey: .order)
    }
}

/// When a turn ends, as a pure function — so the rule is testable on Linux and
/// the view layer only has to obey it.
public enum DuelHandoff {

    public struct Input: Equatable, Sendable {
        /// Seconds left, or nil when the turn has no deadline.
        public let remaining: TimeInterval?
        /// PRD-27 §4.2: VoiceOver or Switch Control is running, so this turn has
        /// no deadline at all and ends on a placement instead. Traversing 81
        /// elements and opening a modal rose cannot be done in 90 seconds.
        public let isUntimed: Bool
        public let roseOpen: Bool
        public let boardSolved: Bool
        public let placementsThisTurn: Int

        public init(
            remaining: TimeInterval?,
            isUntimed: Bool,
            roseOpen: Bool,
            boardSolved: Bool,
            placementsThisTurn: Int
        ) {
            self.remaining = remaining
            self.isUntimed = isUntimed
            self.roseOpen = roseOpen
            self.boardSolved = boardSolved
            self.placementsThisTurn = placementsThisTurn
        }
    }

    public enum Decision: Equatable, Sendable {
        /// Nothing to do.
        case `continue`
        /// The turn is over. Clear, close the turn, open the next, show the card.
        case handOff
        /// The turn is over and the rose is open: dismiss it *without*
        /// committing, then hand off. A digit you did not confirm is not yours.
        case closeRoseThenHandOff
        /// The board is finished. No hand-off — Afterglow runs.
        case finish
    }

    /// Decide what this instant means for the turn.
    ///
    /// Pure and total: no clock read, no global, and every `Input` returns a
    /// `Decision`. `boardSolved` can never produce a hand-off, because a
    /// hand-off card drawn over the Afterglow celebration is the one outcome
    /// that is definitely wrong.
    public static func decide(_ input: Input) -> Decision {
        .continue
    }
}
