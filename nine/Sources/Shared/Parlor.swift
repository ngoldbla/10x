// Parlor.swift — the same board on everyone's device (PRD-28).
//
// **The one idea: the seed is the message.** `(seed, difficulty) → puzzle` is a
// pure function the golden corpus has frozen since Phase 0, so a parlor is N
// devices independently composing byte-identical grids from eight bytes and a
// tier. No board crosses the wire, there is no shared document, no authority and
// no state to reconcile — the hardest problem in multiplayer is deleted rather
// than solved, and what is left to send is a small number saying how far along
// somebody is.
//
// Two things follow that are worth saying out loud:
//
//   * The corpus is now load-bearing in a **second** direction. It has always
//     meant "a quiet change re-rolls every future daily"; it now also means "a
//     quiet change hands two friends different boards under the same invite",
//     silently, with both of them believing they are racing.
//   * Nothing here is persisted. There is no `nine.parlor`. A parlor is a live
//     session and its boards are ordinary library boards, so when the call ends
//     what survives is exactly what would have survived if you had played alone.
//
// Pure Foundation plus the Engine's two frozen identities (`Difficulty`'s raw
// values and `GameKind`), like every other file in this tree. No GroupActivities,
// no GameKit, no clock read, nothing Darwin-only — which is what lets the whole
// protocol be tested with no session, on a platform that has no FaceTime.
import Foundation

#if canImport(NineEngine)
import NineEngine
#endif

// MARK: - The invite

/// Which board, and nothing else.
///
/// This is the entire protocol on the way in, and it has **two envelopes with
/// one meaning**: `Codable` over SharePlay's `GroupSessionMessenger`, and a flat
/// `[String: String]` for `GKGameActivity.properties`. The second is the
/// load-bearing half — it is what makes "Game Center challenges wrap the same
/// primitive" true in code rather than in a sentence, because a flat string
/// dictionary is the only payload GameKit will carry.
public struct ParlorInvite: Codable, Equatable, Sendable {

    /// Bumped when the meaning of any field changes. A receiver refuses a wire
    /// it cannot see all of, because the failure mode of guessing is two friends
    /// solving different boards under one invite.
    public static let wireVersion = 1

    public let seed: UInt64
    public let difficulty: Difficulty
    /// Non-nil when the sender was playing a daily. Only ever *opens* a daily
    /// under §3's guard.
    public let day: Int?

    public init(seed: UInt64, difficulty: Difficulty, day: Int? = nil) {
        self.seed = seed
        self.difficulty = difficulty
        self.day = day
    }

    // MARK: The property-dictionary envelope

    public enum PropertyKey {
        public static let version = "nine.v"
        public static let seed = "nine.seed"
        public static let band = "nine.band"
        public static let day = "nine.day"
    }

    /// The invite as GameKit will carry it. Decimal, because a property
    /// dictionary is also what a human debugging an activity in App Store
    /// Connect has to read.
    public var properties: [String: String] {
        var out = [
            PropertyKey.version: "\(Self.wireVersion)",
            PropertyKey.seed: "\(seed)",
            PropertyKey.band: difficulty.rawValue,
        ]
        // Absent rather than empty: a free board has no day, and "" is a value
        // that has to be special-cased on the way back in.
        if let day { out[PropertyKey.day] = "\(day)" }
        return out
    }

    /// Total, and refusing is the common case rather than the exceptional one.
    ///
    /// **Unknown keys are ignored on purpose.** Strictness there is the obvious
    /// choice and it is wrong: `GKGameActivityDefinition.defaultProperties`
    /// merges App-Store-Connect-owned keys into every activity, so a dictionary
    /// containing something we did not write is the normal case. The *version*
    /// is what protects the board — a build that adds a rules key must bump it.
    public init?(properties: [String: String]) {
        guard let stamp = properties[PropertyKey.version], let version = Int(stamp),
              version <= Self.wireVersion else { return nil }
        guard let raw = properties[PropertyKey.seed], let seed = UInt64(raw) else { return nil }
        guard let band = properties[PropertyKey.band],
              let difficulty = Difficulty(rawValue: band) else { return nil }
        // A band this build cannot compose is refused rather than approximated:
        // the whole point of the invite is that both devices get the same grid,
        // and the nearest band is a different grid.
        self.init(
            seed: seed,
            difficulty: difficulty,
            day: properties[PropertyKey.day].flatMap(Int.init)
        )
    }

    // MARK: The provenance guard (PRD-28 §3)

    /// What this invite is allowed to open.
    ///
    /// Today's daily is today's daily. **Everything else is a free board**, even
    /// a daily — including one dated tomorrow, which is what a friend one
    /// timezone east is playing right now. Without this a friend can hand you
    /// Thursday on Saturday and you take streak credit for a day you did not
    /// play; it is the same shape as the archive's `day < todayOrdinal` guard
    /// and `ChannelLedger`'s `openedOn` provenance, and it lives here so no
    /// surface can forget it.
    public func opens(today: Int) -> GameKind {
        day == today ? .daily(day: today) : .free(difficulty)
    }
}

// MARK: - Presence

/// How far along somebody is. **There is no time in here, and that is the
/// feature.**
///
/// No elapsed, no seconds, no score, no cell, no digit, no name. "No times until
/// everyone finishes" is therefore not a rule the UI obeys — it is a fact about
/// the bytes, sealed by `ParlorSealTests` over the *encoded keys* the way PRD-30
/// sealed the Live Activity's missing clock. A payload with no clock in it
/// cannot grow one by accident.
///
/// The denominator is free and never sent: everyone composed the same puzzle, so
/// `81 − givens` is identical on every device. The wire carries a count and the
/// percentage is computed locally — determinism paying for a second thing after
/// it has already paid for the board.
public struct ParlorPresence: Codable, Equatable, Sendable {

    /// 81, the whole grid. A clamp rather than a precondition: this arrives from
    /// another device, and a hostile or hand-edited number must cost a wrong dot
    /// rather than a trap.
    public static let maxFill = 81

    public let fill: Int
    public let done: Bool

    public init(fill: Int, done: Bool) {
        self.fill = min(Self.maxFill, max(0, fill))
        self.done = done
    }

    enum CodingKeys: String, CodingKey { case fill, done }

    /// `try?` per field rather than `try … ?? default`, for the reason PRD-30
    /// found the hard way: the second spelling survives an absent key and still
    /// throws on a key of the wrong *type*.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fill: (try? c.decode(Int.self, forKey: .fill)) ?? 0,
            done: (try? c.decode(Bool.self, forKey: .done)) ?? false
        )
    }
}

/// What a solve was, sent **only** once the room agrees everyone has finished.
///
/// The seconds and the comet travel together because they are revealed together;
/// splitting them would create an instant where one is known and the other is
/// not, and that instant is the whole thing this design is avoiding.
public struct ParlorFinish: Codable, Equatable, Sendable {
    public let seconds: Int
    /// `SolveReplay.packed` — 1288 bytes at 300 moves, which is why the comet
    /// can ride a message at all.
    public let packed: Data

    public init(seconds: Int, packed: Data) {
        self.seconds = max(0, seconds)
        self.packed = packed
    }

    enum CodingKeys: String, CodingKey { case seconds, packed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            seconds: (try? c.decode(Int.self, forKey: .seconds)) ?? 0,
            packed: (try? c.decode(Data.self, forKey: .packed)) ?? Data()
        )
    }
}

/// One message on the wire.
///
/// A struct of two optionals rather than an enum with two cases, for the reason
/// every tolerant type in this repo is shaped that way: an enum decode throws on
/// a discriminator it has never heard of, and a message from a newer build must
/// cost one message rather than the participant who sent it.
public struct ParlorEnvelope: Codable, Equatable, Sendable {
    public var presence: ParlorPresence?
    public var finish: ParlorFinish?

    public init(presence: ParlorPresence? = nil, finish: ParlorFinish? = nil) {
        self.presence = presence
        self.finish = finish
    }

    enum CodingKeys: String, CodingKey { case presence, finish }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        presence = try? c.decodeIfPresent(ParlorPresence.self, forKey: .presence)
        finish = try? c.decodeIfPresent(ParlorFinish.self, forKey: .finish)
    }
}

// MARK: - The room

/// The roster, the reveal, and the ordering — as a value, so the rule is a
/// property of the type rather than a discipline in a view.
///
/// The one thing to understand about this type: **`Member.finish` is nil until
/// the room is complete.** A view cannot draw a time it should not have, because
/// it is not handed one. That is the same move `ParlorPresence` makes on the
/// wire, one layer up, and both are needed — PRD-30's lesson is that a surface
/// can render a clock the payload never carried.
public struct ParlorRoom: Equatable, Sendable {

    /// One participant as a view should see them.
    public struct Member: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let isMe: Bool
        public let presence: ParlorPresence
        /// 0…1 of the board's fillable cells.
        public let fraction: Double
        /// Nil unless the room has completed. Not "nil unless they finished".
        public let finish: ParlorFinish?
    }

    /// This device's participant id. Always sorted first, because your own dot
    /// having a fixed home is the difference between a row you can read at a
    /// glance and one you have to search.
    public let me: UUID

    /// Cells that can be filled on this board — `81 − givens`, known locally
    /// because everyone composed the same puzzle.
    ///
    /// A `var` for one reason, and it is a sequencing fact rather than a design
    /// preference: a session can be joined before its board has finished
    /// composing, so the room exists for a moment before this is knowable.
    /// Zero until then, which `fraction(of:)` reads as zero rather than as
    /// infinite.
    public private(set) var fillable: Int

    private var presence: [UUID: ParlorPresence] = [:]
    private var finishes: [UUID: ParlorFinish] = [:]

    public init(me: UUID, fillable: Int) {
        self.me = me
        self.fillable = max(0, fillable)
    }

    // MARK: Mutation

    public mutating func update(_ value: ParlorPresence, from id: UUID) {
        presence[id] = value
    }

    /// Tell the room how big the board turned out to be. Nothing else changes:
    /// every fill already received is a count, and a count does not go stale
    /// when its denominator arrives.
    public mutating func rebase(fillable: Int) {
        self.fillable = max(0, fillable)
    }

    /// Hold a finish. Whether it is ever *shown* is `isComplete`'s decision, not
    /// the sender's, and not this method's.
    public mutating func record(_ value: ParlorFinish, from id: UUID) {
        finishes[id] = value
    }

    /// Keep exactly these participants — the roster the session reports.
    ///
    /// A departure can **complete** a room, and that is correct rather than
    /// lenient: a parlor of people who have all finished, plus one who hung up,
    /// is a parlor that is finished.
    public mutating func retain(_ ids: Set<UUID>) {
        presence = presence.filter { ids.contains($0.key) }
        finishes = finishes.filter { ids.contains($0.key) }
    }

    public mutating func remove(_ id: UUID) {
        presence[id] = nil
        finishes[id] = nil
    }

    // MARK: Reading

    /// Everyone who has said anything, **you first, then by id** — stable on
    /// every device and every redraw. Never by progress: a row that re-orders as
    /// people fill cells is a leaderboard with soft edges.
    public var members: [Member] {
        let reveal = isComplete
        return presence.keys
            .sorted { lhs, rhs in
                if (lhs == me) != (rhs == me) { return lhs == me }
                return lhs.uuidString < rhs.uuidString
            }
            .map { id in
                let value = presence[id] ?? ParlorPresence(fill: 0, done: false)
                return Member(
                    id: id,
                    isMe: id == me,
                    presence: value,
                    fraction: fraction(of: value),
                    finish: reveal ? finishes[id] : nil
                )
            }
    }

    /// Non-empty, and everybody done. The same predicate on every device, so the
    /// moment the last person finishes everyone reaches the same conclusion in
    /// the same instant — nobody is waiting on a host, because there isn't one.
    public var isComplete: Bool {
        !presence.isEmpty && presence.values.allSatisfy(\.done)
    }

    /// A device may publish its own `ParlorFinish` only when this is true. It is
    /// `isComplete` under a name that says what it is for, because the rule it
    /// enforces is about sending and the predicate is about the room.
    public var mayPublishFinish: Bool { isComplete }

    /// Whether anybody else is here at all. A parlor of one is a solitary board
    /// that happens to know it could have had company.
    public var isShared: Bool { presence.count > 1 }

    /// Zero rather than infinite when the denominator is unknown: the wire never
    /// carries one, so a room told nothing about the board must not divide by it.
    private func fraction(of value: ParlorPresence) -> Double {
        guard fillable > 0 else { return 0 }
        return min(1, max(0, Double(value.fill) / Double(fillable)))
    }
}
