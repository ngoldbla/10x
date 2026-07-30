// DailyPresenceActivity.swift — the ActivityKit shape of PRD-30's payload.
//
// Split off from `QuietPresence.swift` because this is the one file in
// `Sources/Shared` that cannot compile everywhere. `Sources/Shared` is on four
// source lists (the universal app, the widget extension, the watch app, and the
// `NineShared` SwiftPM target that `swift test` builds), and ActivityKit exists
// on exactly one of the platforms those cover.
//
// **The fence is `#if os(iOS)` and not `#if canImport(ActivityKit)`, which is
// the obvious choice and is wrong.** Probed with `swiftc -typecheck` per target:
// `canImport(ActivityKit)` is **true on macOS** and false on tvOS/watchOS. But
// every type in the module — `ActivityAttributes` included — is annotated
// `@available(macOS, unavailable)`, so on macOS the import succeeds and then the
// conformance below fails to compile. `canImport` answers "is there a module",
// which is not the question.
//
// The rest of `Sources/Shared` has no platform fence at all, and this comment is
// here so the next person adding one knows which of the two spellings survives a
// macOS build.
import Foundation

#if os(iOS)
import ActivityKit

/// The Live Activity behind today's daily.
///
/// The split between attributes and content state is the split between *which
/// board* and *how it looks now*: a daily's day and band are fixed for the life
/// of the activity, and the glyph is the only thing that changes. So the dynamic
/// half — the bytes ActivityKit re-encodes and re-delivers on every update —
/// contains a picture and a sequence number, and nothing else. No elapsed time,
/// no remaining count, no streak. See `QuietPresence.swift`.
public struct NineDailyActivity: ActivityAttributes {

    /// The dynamic half. Two fields, and both of them have to be here: the glyph
    /// is what is drawn, and the revision is what lets a late update be dropped
    /// without asking the clock what time it is.
    public struct ContentState: Codable, Hashable, Sendable {
        public var glyph: BoardGlyph
        public var revision: Int

        public init(glyph: BoardGlyph, revision: Int) {
            self.glyph = glyph
            self.revision = revision
        }

        /// Tolerant for the same reason `DailyPresence`'s decode is: ActivityKit
        /// restores a running activity's *previously encoded* state into a
        /// freshly updated app, so this type meets its own past shape.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            glyph = ((try? c.decodeIfPresent(BoardGlyph.self, forKey: .glyph)) ?? nil) ?? .blank
            revision = ((try? c.decodeIfPresent(Int.self, forKey: .revision)) ?? nil) ?? 0
        }
    }

    /// Day ordinal of the daily this activity is about. An activity whose day is
    /// not today is stale by definition and gets ended, which is how a phone that
    /// was asleep at midnight catches up without a timer.
    public let dayOrdinal: Int
    /// `Difficulty.rawValue` — the stable identity, never the translated word.
    /// The renderer is in the widget extension with its own bundle and looks the
    /// name up itself (PRD-20: raw values *are* the frozen identity).
    public let bandID: String

    public init(dayOrdinal: Int, bandID: String) {
        self.dayOrdinal = dayOrdinal
        self.bandID = bandID
    }
}

extension DailyPresence {
    /// The static half of this payload.
    public var activityAttributes: NineDailyActivity {
        NineDailyActivity(dayOrdinal: dayOrdinal, bandID: bandID)
    }

    /// The dynamic half.
    public var activityState: NineDailyActivity.ContentState {
        NineDailyActivity.ContentState(glyph: glyph, revision: revision)
    }
}
#endif
