// DailyWidgetViews.swift — the glanceable daily widget (PRD-3 §3a):
// systemSmall (status + flame), systemMedium (status + fill ring + flame +
// points), accessoryRectangular (Lock Screen line). Void-black in dark,
// paper in light — the widget is a tiny window into the same room.
import SwiftUI
import WidgetKit

/// Nine's palette, restated: the extension must not link CouchKit
/// (PRD-3 §2), so the three colors the widgets need live here. glacier and
/// ember mirror `AccentChoice`'s vivid base values (AppModel.swift) — retune
/// both together. Widgets stay system light/dark; the in-app tinted themes
/// don't reach the extension (it can't read nine's prefs).
enum WidgetPalette {
    static let paper = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let glacier = Color(red: 0.33, green: 0.68, blue: 0.98)
    static let ember = Color(red: 1.00, green: 0.56, blue: 0.20)
}

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
    let entry: DailyEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .systemMedium:
            medium
                .containerBackground(for: .widget) {
                    colorScheme == .light ? WidgetPalette.paper : Color.black
                }
        default:
            small
                .containerBackground(for: .widget) {
                    colorScheme == .light ? WidgetPalette.paper : Color.black
                }
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

    // MARK: - accessoryRectangular

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Strings.string("widget.brand.daily"))
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            Text(rectangularLine)
                .font(.headline)
            if entry.displayedStreak > 0 {
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
                    .stroke(WidgetPalette.glacier, style: .init(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(WidgetFormat.percent(fill))
                    .font(.callout.weight(.semibold))
            case .solved:
                Circle()
                    .stroke(WidgetPalette.glacier, lineWidth: 6)
                Image(systemName: "checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WidgetPalette.glacier)
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
                .foregroundStyle(WidgetPalette.glacier)
        case .inProgress:
            Image(systemName: "circle.dotted.circle")
                .foregroundStyle(WidgetPalette.glacier)
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
        if entry.displayedStreak > 0 {
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
