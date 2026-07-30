// DailyPresenceActivityViews.swift — PRD-30's Live Activity, and the whole of
// its Dynamic Island.
//
// Read this file for what it does not contain. There is no `Text(_:style:)`, no
// `timerInterval:`, no `ProgressView(timerInterval:)`, no `.timer`, no
// `countsDown`, no `AlertConfiguration`, and the word "streak" appears nowhere
// but in this sentence. `Tests/EngineTests/QuietPresenceSealTests.swift` greps
// for every one of those and fails if one arrives, because PRD-30's requirement
// is a negative and negatives erode without anything going red.
//
// What is here is a board you left half done, drawn as a constellation, and a
// tap that takes you back to it. A bookmark, not a dashboard.
//
// `Sources/Widgets` builds for iOS only (`project.yml:194`), which is also the
// only platform ActivityKit exists on, so this file needs no fence — the tree
// has none.
import ActivityKit
import SwiftUI
import WidgetKit

struct NineDailyPresenceActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NineDailyActivity.self) { context in
            LockScreenPresenceView(
                attributes: context.attributes,
                state: context.state,
                isStale: context.isStale
            )
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    ExpandedPresenceView(
                        attributes: context.attributes,
                        state: context.state,
                        isStale: context.isStale
                    )
                }
            } compactLeading: {
                // "Dynamic Island: tiny board glyph only" (PROGRAM-2.0 §Pillar E).
                // Taken literally: no count beside it, no percentage, no flame.
                PresenceGlyph(state: context.state, side: 18, isStale: context.isStale)
            } compactTrailing: {
                // Deliberately empty. The compact trailing slot is where every
                // other app puts a number, and a number here would be either a
                // clock or a score.
                EmptyView()
            } minimal: {
                PresenceGlyph(state: context.state, side: 16, isStale: context.isStale)
            }
            .widgetURL(URL(string: "nine://daily"))
        }
        // The watch's Smart Stack renders the same activity for free on iOS 18+.
        // `.small` only: `.medium` would ask for a second layout on a surface
        // nobody has driven, and the glyph is already the whole content.
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - The glyph, wherever it appears

/// One place that knows how a presence glyph is coloured, so the four
/// presentations cannot come to disagree.
private struct PresenceGlyph: View {
    let state: NineDailyActivity.ContentState
    let side: CGFloat
    let isStale: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        BoardGlyphView(glyph: state.glyph, look: look, side: side)
            // Stale means the day has turned over and the app has not yet had a
            // chance to end this. It fades; it does not announce. A caption
            // saying "yesterday" on a Lock Screen is the nag PRD-13's grace
            // exists so Nine never has to send.
            .opacity(isStale ? 0.35 : 1)
    }

    private var look: WidgetLook {
        WidgetLook.resolve(PresenceLook.appearance, colorScheme: colorScheme)
    }
}

/// Where a Live Activity gets the player's theme from.
///
/// Not from the content state: appearance is ambient configuration, not board
/// state, and putting it in the dynamic half would re-encode and re-deliver two
/// strings on every move for a value that changes once a month. Not from the
/// attributes either, because those are frozen for the life of the activity and
/// a theme switch mid-daily would leave the Lock Screen wearing the old one.
///
/// So it is read from the snapshot file, on the same app-group container, in the
/// same process, that the three shipped widgets already read on the Lock Screen
/// — which is what makes this safe rather than clever: if the file were
/// unreadable while locked, `NineStreakWidget` would have been blank there since
/// PRD-3.
private enum PresenceLook {
    static var appearance: SharedAppearance {
        WidgetSnapshotStore.load()?.appearance ?? SharedAppearance()
    }
}

// MARK: - Lock Screen / Notification Centre

private struct LockScreenPresenceView: View {
    let attributes: NineDailyActivity
    let state: NineDailyActivity.ContentState
    let isStale: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            PresenceGlyph(state: state, side: 54, isStale: isStale)
            VStack(alignment: .leading, spacing: 3) {
                Text(Phrase.header)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(Phrase.band(attributes.bandID))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // The one sentence, and it is about the board rather than about
                // you: how much is left to do, never how long you have taken or
                // how many days you have strung together.
                Text(Phrase.remaining(state.glyph))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .opacity(isStale ? 0.55 : 1)
    }
}

// MARK: - Dynamic Island, expanded

private struct ExpandedPresenceView: View {
    let attributes: NineDailyActivity
    let state: NineDailyActivity.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 12) {
            PresenceGlyph(state: state, side: 44, isStale: isStale)
            VStack(alignment: .leading, spacing: 2) {
                Text(Phrase.band(attributes.bandID))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(Phrase.remaining(state.glyph))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Copy

/// Every user-facing literal in this file, in one block (PRD-20's seam).
private enum Phrase {
    static let header = Strings.string("presence.header")

    /// The band by its stable id, looked up in *this* bundle — the activity is
    /// rendered by the extension, whose `Bundle.main` is the appex.
    static func band(_ bandID: String) -> String {
        bandID.isEmpty ? header : Strings.string("difficulty.\(bandID).title")
    }

    /// How many squares are still empty. A count of what is left rather than of
    /// what is done, because "51 to go" is a description of a board and "30 done"
    /// is a score.
    static func remaining(_ glyph: BoardGlyph) -> String {
        let left = max(0, BoardGlyph.cellCount - glyph.givenCount - glyph.filledCount)
        return Strings.string("presence.remaining", .int(left))
    }
}
