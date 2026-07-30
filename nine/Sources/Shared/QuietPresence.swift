// QuietPresence.swift — PRD-30. What a Live Activity, a Dynamic Island and a
// StandBy face are allowed to know about your board.
//
// The headline requirement of PRD-30 is a negative one: **no timers, no
// countdowns, no streak-endangered nagging ever**. That is easy to honour on
// the day it is written and hard to honour in a year, so it is enforced by the
// shape of the payload rather than by a comment. `DailyPresence` carries no
// `Date`, no `TimeInterval`, no streak field and no count of anything. A
// payload with no clock in it cannot grow a countdown by accident, and
// `Tests/SharedTests/QuietPresenceTests.swift` fails if one appears.
//
// What it carries instead is the board's own portrait — the same idea as
// `BoardFingerprint` (PRD-22): the givens are a constellation and your entries
// light up beside them, so progress is a picture that fills in rather than a
// number that judges. Two 81-bit masks, 22 bytes, which matters because
// ActivityKit caps attributes plus content state at 4KB.
//
// Pure Foundation, like every other file in this tree. The one Engine-shaped
// convenience (`init(_ game:)`) needs `import NineEngine` behind
// `canImport(NineEngine)` for the SwiftPM build, exactly as `SharedDailyBoard`
// does — the *import* only, never the declaration. See the note above it.
import Foundation

#if canImport(NineEngine)
import NineEngine
#endif

// MARK: - The glyph

/// A board reduced to "which squares have something in them, and which of those
/// were printed" — the smallest thing that still looks like *your* board.
///
/// Two bitmasks rather than 81 bytes or a full `NineGame`: a Live Activity's
/// content state is re-encoded on every update and delivered through the
/// system, so its size is a running cost rather than a one-off.
public struct BoardGlyph: Codable, Equatable, Hashable, Sendable {
    public static let cellCount = 81
    /// ceil(81 / 8). Named so the two arrays cannot disagree about their length.
    public static let maskBytes = 11

    /// Bit *i* set = cell *i* is a printed given.
    public let given: [UInt8]
    /// Bit *i* set = cell *i* holds something the player put there.
    ///
    /// Deliberately "something" and not "a digit": a pencil mark is progress
    /// too, and the glyph is a picture of effort, not of correctness. It never
    /// distinguishes a right entry from a wrong one — that would leak the
    /// solution onto a Lock Screen anyone walking past can read, which is the
    /// same rule `showErrors == false` enforces inside the app.
    public let filled: [UInt8]

    /// Both masks are clamped to `maskBytes` on the way in, so a decode of a
    /// hand-edited or future-shaped blob cannot make a reader index off the end.
    public init(given: [UInt8], filled: [UInt8]) {
        self.given = Self.normalise(given)
        self.filled = Self.normalise(filled)
    }

    public init(givenCells: some Sequence<Int>, filledCells: some Sequence<Int>) {
        self.given = Self.mask(from: givenCells)
        self.filled = Self.mask(from: filledCells)
    }

    /// The empty board — what a glyph decodes to when there is nothing to show.
    public static let blank = BoardGlyph(
        given: [UInt8](repeating: 0, count: maskBytes),
        filled: [UInt8](repeating: 0, count: maskBytes)
    )

    public func isGiven(_ cell: Int) -> Bool { Self.bit(cell, in: given) }
    public func isFilled(_ cell: Int) -> Bool { Self.bit(cell, in: filled) }

    /// A cell is empty when neither mask claims it. Both claiming it is
    /// impossible from the Engine and harmless here — `isGiven` wins in the
    /// draw order, because a printed digit is not something you did.
    public func isEmpty(_ cell: Int) -> Bool { !isGiven(cell) && !isFilled(cell) }

    public var givenCount: Int { given.reduce(0) { $0 + $1.nonzeroBitCount } }
    public var filledCount: Int { filled.reduce(0) { $0 + $1.nonzeroBitCount } }

    /// True once the player has put anything at all on the board.
    ///
    /// This is the gate PRD-30 hangs the whole feature on: an untouched board is
    /// not a bookmark, it is an advert. See `PresencePolicy.decide`.
    public var isTouched: Bool { filledCount > 0 }

    /// Every square accounted for — a solved board, or one filled wrongly. The
    /// glyph cannot tell those apart and does not try.
    public var isComplete: Bool { givenCount + filledCount >= Self.cellCount }

    // MARK: Bit plumbing

    private static func normalise(_ bytes: [UInt8]) -> [UInt8] {
        if bytes.count == maskBytes { return bytes }
        var out = Array(bytes.prefix(maskBytes))
        out.append(contentsOf: [UInt8](repeating: 0, count: maskBytes - out.count))
        return out
    }

    private static func mask(from cells: some Sequence<Int>) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: maskBytes)
        for cell in cells where (0..<cellCount).contains(cell) {
            bytes[cell / 8] |= UInt8(1 << (cell % 8))
        }
        return bytes
    }

    private static func bit(_ cell: Int, in bytes: [UInt8]) -> Bool {
        guard (0..<cellCount).contains(cell), bytes.count == maskBytes else { return false }
        return bytes[cell / 8] & UInt8(1 << (cell % 8)) != 0
    }
}

// Outside the `canImport` fence, and that distinction is load-bearing: only the
// *import* is conditional. In the Xcode targets `Sources/Engine` compiles into the
// same module, so `canImport(NineEngine)` is **false** there — fencing the
// extension as well would have made this initialiser exist in `swift test` and
// vanish from the app, which is exactly how the first build of this file failed.
// `SharedDailyBoard.swift` has the same one-line fence for the same reason.
extension BoardGlyph {
    /// A glyph of a live board. Pencil marks count as filled — see `filled`.
    public init(_ game: NineGame) {
        var given: [Int] = []
        var filled: [Int] = []
        for cell in 0..<BoardGlyph.cellCount {
            if game.isGiven(cell) {
                given.append(cell)
            } else if game.entry(at: cell) != 0 || !game.pencilDigits(at: cell).isEmpty {
                filled.append(cell)
            }
        }
        self.init(givenCells: given, filledCells: filled)
    }
}

// MARK: - The payload

/// Everything the quiet surfaces are told. Read the field list as the spec: the
/// absences are the feature.
public struct DailyPresence: Codable, Equatable, Hashable, Sendable {
    /// Which day's daily this is, so a stale activity can be recognised without
    /// consulting a clock the payload does not carry.
    public var dayOrdinal: Int
    /// Stable identity of the band, never the translated name — the renderer is
    /// in another process with another bundle and looks the word up itself.
    /// `Difficulty.rawValue` (PRD-20: raw values *are* the frozen identity).
    public var bandID: String
    public var glyph: BoardGlyph
    /// Monotonic, mirrored from `SharedDailyBoard.revision`. Lets an update
    /// arriving out of order be dropped without asking what time it is.
    public var revision: Int

    public init(dayOrdinal: Int, bandID: String, glyph: BoardGlyph, revision: Int) {
        self.dayOrdinal = dayOrdinal
        self.bandID = bandID
        self.glyph = glyph
        self.revision = revision
    }

    /// Tolerant decode. Not because this one is persisted — it is not — but
    /// because ActivityKit hands a *previous build's* encoded content state back
    /// to a freshly updated app when it restores a running activity, so this
    /// type meets its own past shape exactly the way a `CouchStored` blob does.
    /// Every field is `try?`, not just the composite one. The first draft used a
    /// plain `try … ?? default` for the three scalars — which tolerates an
    /// *absent* key and throws on a key of the wrong *type*, so a field that
    /// changed shape between builds would have taken the whole payload with it.
    /// `NinePrefs` and `SharedAppearance` both got this right already;
    /// `testAPayloadFromAnOlderShapeDecodesToADrawableDefault` is what noticed
    /// that this one had not.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayOrdinal = ((try? c.decodeIfPresent(Int.self, forKey: .dayOrdinal)) ?? nil) ?? 0
        bandID = ((try? c.decodeIfPresent(String.self, forKey: .bandID)) ?? nil) ?? ""
        glyph = ((try? c.decodeIfPresent(BoardGlyph.self, forKey: .glyph)) ?? nil) ?? .blank
        revision = ((try? c.decodeIfPresent(Int.self, forKey: .revision)) ?? nil) ?? 0
    }
}

// MARK: - The lifecycle, as a pure function

public enum PresenceDecision: Equatable, Sendable {
    /// No activity should exist, and any that does must go.
    case end
    /// Begin one carrying this payload.
    case start(DailyPresence)
    /// One already exists; hand it this payload.
    case update(DailyPresence)
    /// Leave whatever is there exactly as it is.
    case leave
}

/// The rules, in one place, testable by `swift test` with no simulator — the
/// same reason `RoseLens` and `DraftingTable` are shaped this way.
public enum PresencePolicy {

    /// - Parameters:
    ///   - enabled: the player's pref. Off ends any live activity immediately.
    ///   - presence: the payload today's daily would carry, or nil if there is
    ///     no daily today at all.
    ///   - solved: today's daily is recorded as done.
    ///   - foreground: the app is on screen being looked at. An activity is a
    ///     bookmark for when you are *not* here, so this is what gates `start`.
    ///   - live: an activity is currently running.
    ///   - today: the day ordinal *now*, passed in — this module reads no clock.
    public static func decide(
        enabled: Bool,
        presence: DailyPresence?,
        solved: Bool,
        foreground: Bool,
        live: Bool,
        today: Int
    ) -> PresenceDecision {
        // The pref is a hard stop, not a preference about styling.
        guard enabled else { return live ? .end : .leave }

        // A solved daily has nothing left to bookmark, and a congratulation on
        // the Lock Screen is the celebration asking to be seen by someone who
        // did not open the app. The afterglow is inside.
        guard !solved else { return live ? .end : .leave }

        guard let presence, presence.dayOrdinal == today else {
            // Yesterday's activity meeting today: end it. It is never replaced
            // in the same breath, because "here is a new puzzle" at midnight is
            // precisely the nag PRD-13's grace exists so we never have to send.
            return live ? .end : .leave
        }

        // A finished-but-unrecorded board (the widget solved it, the app has not
        // ingested yet) is the same case as solved.
        guard !presence.glyph.isComplete else { return live ? .end : .leave }

        // **The gate.** Start-and-leave: the player has to have put something on
        // the board. Without this, opening the daily and immediately deciding not
        // to play would leave a Lock Screen artefact nobody asked for. An already
        // running activity still tracks an emptied board rather than vanishing
        // mid-erase — disappearance is a louder event than a dimmer glyph.
        guard presence.glyph.isTouched else { return live ? .update(presence) : .leave }

        // Foreground gates `start` only. Once one exists it keeps tracking while
        // the app is open, because the player may lock the phone mid-move and the
        // glyph they then see should be the board they actually left.
        //
        // Note what is deliberately *not* here: a check that the daily is the
        // board on screen. A `PresenceScreen` parameter was written first and
        // removed — `isTouched` already proves the player started the daily, so
        // requiring it to also be the last board they looked at would drop the
        // bookmark for someone who plays the daily at breakfast and a free board
        // at lunch. The narrower rule was more code and worse behaviour.
        if foreground, !live { return .leave }

        return live ? .update(presence) : .start(presence)
    }
}
