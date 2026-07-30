// DailyWidgetViews.swift — the glanceable daily widget (PRD-3 §3a):
// systemSmall (status + flame), systemMedium (status + fill ring + flame +
// points), accessoryRectangular (Lock Screen line). Void-black in dark,
// paper in light — the widget is a tiny window into the same room.
import SwiftUI
import WidgetKit

// `WidgetPalette` used to live here, holding three hardcoded constants under a
// comment saying "the in-app tinted themes don't reach the extension (it can't
// read nine's prefs)". PRD-30 made that false: theme and accent now travel in
// `WidgetSnapshot`, and `WidgetLook.swift` resolves them. What is left of
// `WidgetPalette` there is the two tones that are Nine's brand rather than the
// player's choice.

struct NineDailyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NineDailyWidget", provider: DailyProvider()) { entry in
            DailyWidgetView(entry: entry)
                .widgetURL(URL(string: "nine://daily"))
        }
        .configurationDisplayName(Strings.resource("widget.daily.name"))
        .description(Strings.resource("widget.daily.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct DailyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    /// **This is how StandBy is detected, because there is no way to ask.**
    ///
    /// StandBy is a `WidgetLocation`, and the only API that takes one is
    /// `disfavoredLocations(_:for:)` — an opt-out. There is no
    /// `\.widgetLocation` to read. What is available is this: StandBy renders
    /// `systemSmall` with the container background *removed*, and nothing else
    /// does. Lock Screen widgets are the `accessory*` families; iOS 18's tinted
    /// Home Screen keeps its background and only moves `widgetRenderingMode` to
    /// `.accented`.
    ///
    /// So `family == .systemSmall && !showsWidgetContainerBackground` is an
    /// inference rather than a fact, and it is named here rather than hidden
    /// behind a `var isStandBy` so the next person knows it is one. If it ever
    /// stops holding, the failure is benign: the ambient face appears somewhere
    /// else that also took the background away.
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    /// `.vibrant` in StandBy's Night Mode, `.accented` on a tinted Home Screen.
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: DailyEntry

    /// The player's theme and accent, which reached this process for the first
    /// time in PRD-30. An older snapshot, or the gallery, yields the defaults.
    private var look: WidgetLook {
        WidgetLook.resolve(
            entry.snapshot?.appearance ?? SharedAppearance(), colorScheme: colorScheme
        )
    }

    /// The Focus filter (PRD-33). A quiet shelf and a loud Home Screen would not
    /// be a filter.
    private var focus: QuietFocus { entry.snapshot?.focus ?? .none }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .systemMedium:
            Group {
                if focus.hidesDaily { quietMedium } else { medium }
            }
            .containerBackground(for: .widget) { look.ground }
        default:
            // The container background is applied on both arms even though
            // StandBy removes it: WidgetKit requires one on every iOS 17+ widget,
            // and whether it is drawn is the system's decision, not ours.
            Group {
                // A Focus filter hiding the daily reaches the same view StandBy
                // does, and that is the design rather than a shortcut: "Focus
                // that adds calm" (PROGRAM-2.0 §Pillar E) and "a nightstand glass
                // object" turn out to want exactly the same thing — the board
                // without a single number on it. One view, two reasons.
                if showsBackground, !focus.hidesDaily {
                    small
                } else {
                    ambient
                }
            }
            .containerBackground(for: .widget) { look.ground }
        }
    }

    // MARK: - StandBy: the nightstand face

    /// Today's board as an object on a bedside table (PRD-30).
    ///
    /// **The glyph and nothing else.** Every candidate caption was tried against
    /// the 11pm-in-bed test and lost: a percentage is a number to read at
    /// midnight, a streak is a reason to feel something, and "Today's board" is a
    /// label on the only thing on the screen. What is left is legible at three
    /// feet in the dark and asks for nothing, which is the whole brief.
    ///
    /// Zero animation, deliberately — the idle-pixel test's most literal case is
    /// a widget that is on screen for eight hours next to someone asleep.
    private var ambient: some View {
        GeometryReader { geo in
            BoardGlyphView(
                glyph: entry.glyph ?? .blank,
                look: look,
                side: min(geo.size.width, geo.size.height) * 0.86,
                // Night Mode hands us `.vibrant` and desaturates whatever it is
                // given; drawing in hierarchical greys is what makes the red tint
                // look chosen instead of survived.
                monochrome: renderingMode != .fullColor
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - systemSmall

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Strings.string("widget.daily.header"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                statusGlyph
                    .font(.caption)
            }
            Spacer(minLength: 0)
            Text(statusLine)
                .font(.title2.weight(.semibold))
                .minimumScaleFactor(0.6)
            Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            flameChip
        }
    }

    // MARK: - systemMedium

    private var medium: some View {
        HStack(spacing: 16) {
            fillRing
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.string("widget.brand.daily"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(statusLine)
                    .font(.title2.weight(.semibold))
                    .minimumScaleFactor(0.7)
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    flameChip
                    if entry.totalPoints > 0 {
                        Label(Strings.string("widget.daily.points", .int(entry.totalPoints)),
                              systemImage: "star.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The medium family under a Focus filter: the constellation and the
    /// wordmark, and nothing that counts.
    private var quietMedium: some View {
        HStack(spacing: 16) {
            BoardGlyphView(
                glyph: entry.glyph ?? .blank, look: look, side: 72,
                monochrome: renderingMode != .fullColor
            )
            Text(Strings.string("widget.brand.daily"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - accessoryRectangular

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Strings.string("widget.brand.daily"))
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            Text(rectangularLine)
                .font(.headline)
            if !focus.hidesStreak, entry.displayedStreak > 0 {
                Label(Strings.string("widget.daily.streak", .int(entry.displayedStreak)),
                      systemImage: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    /// Fill ring: progress arc mid-solve, full glacier ring + check when
    /// solved, faint empty ring before the first move.
    private var fillRing: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, lineWidth: 6)
            switch entry.state {
            case .inProgress(let fill):
                Circle()
                    .trim(from: 0, to: max(0.02, fill))
                    .stroke(look.accent, style: .init(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(WidgetFormat.percent(fill))
                    .font(.callout.weight(.semibold))
            case .solved:
                Circle()
                    .stroke(look.accent, lineWidth: 6)
                Image(systemName: "checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(look.accent)
            case .notStarted, .noSnapshot:
                Image(systemName: "square.grid.3x3")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch entry.state {
        case .solved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(look.accent)
        case .inProgress:
            Image(systemName: "circle.dotted.circle")
                .foregroundStyle(look.accent)
        case .notStarted, .noSnapshot:
            Image(systemName: "square.grid.3x3")
                .foregroundStyle(.secondary)
        }
    }

    private var statusLine: String {
        switch entry.state {
        case .noSnapshot: return Strings.string("widget.status.openNine")
        case .notStarted: return Strings.string("widget.status.ready")
        case .inProgress(let fill): return WidgetFormat.percent(fill)
        case .solved(let seconds):
            if let seconds { return WidgetFormat.time(seconds) }
            return Strings.string("widget.status.solved")
        }
    }

    private var statusDetail: String {
        switch entry.state {
        case .noSnapshot: return Strings.string("widget.caption.awaits")
        case .notStarted: return Strings.string("widget.caption.waiting")
        case .inProgress: return Strings.string("widget.caption.inProgress")
        case .solved(let seconds):
            return Strings.string(seconds == nil ? "widget.caption.done"
                                                 : "widget.status.solved")
        }
    }

    private var rectangularLine: String {
        switch entry.state {
        case .noSnapshot: return Strings.string("widget.status.openNine")
        case .notStarted: return Strings.string("widget.status.notStarted")
        // Whole sentences, not a word glued to a number. "64% filled" and
        // "Solved 4:12" both put the figure first in English and both languages
        // that front the verb would have to move it, which a Swift
        // interpolation cannot express — the same reason `BoardProgressCaption`
        // stopped interpolating a trailing "%" in Task 5.
        case .inProgress(let fill):
            return Strings.string("widget.status.filled", .text(WidgetFormat.percent(fill)))
        case .solved(let seconds):
            if let seconds {
                return Strings.string("widget.status.solvedIn",
                                      .text(WidgetFormat.time(seconds)))
            }
            return Strings.string("widget.status.solved")
        }
    }

    @ViewBuilder
    private var flameChip: some View {
        if focus.hidesStreak {
            // Nothing, not a placeholder. "Start a streak" is the very invitation
            // a player who turned this filter on asked not to be given.
            EmptyView()
        } else if entry.displayedStreak > 0 {
            Label("\(entry.displayedStreak)", systemImage: "flame.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetPalette.ember)
        } else {
            Label(Strings.string("widget.daily.startStreak"), systemImage: "flame")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
