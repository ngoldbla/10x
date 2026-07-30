// QuietFocus.swift — PRD-33. What a Focus filter is allowed to change about
// Nine.
//
// Focus filters normally do one of two things: silence an app's notifications,
// or switch an account. Nine sends no notifications (the covenant: one opt-in
// silent daily reminder at most, off by default) and has no accounts, so
// `FocusFilterAppContext` has nothing to say and the filter's entire job is to
// take the *pull* out of the app's own surfaces. That is the point PROGRAM-2.0
// makes with "Focus that *adds* calm".
//
// Two independent switches, because they answer different questions. Hiding the
// streak removes the thing that makes a missed day feel like a cost. Hiding the
// daily removes the thing that makes an unstarted board feel like a task. A
// player who wants one rarely wants both — during Work you might want the
// streak gone and a board still one tap away; during Sleep the reverse.
//
// Pure Foundation, and deliberately *not* on `NinePrefs`: this is machine state
// the system writes, not a preference the player set, and it must never sync —
// a Focus is a property of the device in front of you. See `nine.focus` in
// `AppModel`.
import Foundation

/// The quiet a Focus filter is currently asking for.
public struct QuietFocus: Codable, Equatable, Sendable {
    /// The Today card keeps its board and loses its urgency: no fill ring, no
    /// percentage, no "Today" framing. A board, when you want one.
    ///
    /// Not "hide the card". A shelf with a hole in it is a surface that looks
    /// broken, and PRD-34 spent real effort making the shelf's zero-states
    /// honest rather than absent (the craft charter's "honest absence over fake
    /// data" cuts both ways — an absence nobody asked for is its own lie).
    public var hidesDaily: Bool
    /// The streak chip is not rendered: not on the shelf, not on the Mac, not in
    /// the widget. PRD-13's grace made the streak forgiving; this makes it
    /// invisible, which is the only thing left to offer someone who has told the
    /// system they do not want to be counted right now.
    public var hidesStreak: Bool

    public init(hidesDaily: Bool = false, hidesStreak: Bool = false) {
        self.hidesDaily = hidesDaily
        self.hidesStreak = hidesStreak
    }

    /// Tolerant decode, per EXECUTING-A-PRD §2: `CouchStored` discards the whole
    /// blob when a decode throws, and the value this one falls back to has to be
    /// "no filter" rather than "some filter".
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `try?` on a `decodeIfPresent` yields `Bool??` — the outer nil is "the
        // value was the wrong type", the inner is "the key was absent". Both
        // mean "no filter" here, so both flatten to false. Same shape as
        // `SharedAppearance.init(from:)`.
        hidesDaily = ((try? c.decodeIfPresent(Bool.self, forKey: .hidesDaily)) ?? nil) ?? false
        hidesStreak = ((try? c.decodeIfPresent(Bool.self, forKey: .hidesStreak)) ?? nil) ?? false
    }

    /// Nothing hidden — what every reader falls back to.
    public static let none = QuietFocus()

    public var isQuiet: Bool { hidesDaily || hidesStreak }

    public static let storeKey = "nine.focus"
}
