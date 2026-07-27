// StreakWidget.swift — Lock Screen streak accessories (PRD-3 §3a):
// accessoryCircular (flame + day count, a Gauge while today's daily is in
// progress) and accessoryInline ("Nine · 12 day streak"). Hierarchical
// foregrounds so vibrant/tinted rendering doesn't wash out.
import SwiftUI
import WidgetKit

struct NineStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NineStreakWidget", provider: DailyProvider()) { entry in
            StreakWidgetView(entry: entry)
                .widgetURL(URL(string: "nine://daily"))
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName(Strings.resource("widget.streak.name"))
        .description(Strings.resource("widget.streak.description"))
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(inlineText, systemImage: entry.displayedStreak > 0 ? "flame.fill" : "flame")
        default:
            circular
        }
    }

    @ViewBuilder
    private var circular: some View {
        switch entry.state {
        case .inProgress(let fill):
            Gauge(value: fill) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(entry.displayedStreak)")
                    .font(.title3.weight(.semibold))
            }
            .gaugeStyle(.accessoryCircular)
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: entry.displayedStreak > 0 ? "flame.fill" : "flame")
                        .font(.caption)
                        .widgetAccentable()
                    Text("\(entry.displayedStreak)")
                        .font(.title3.weight(.semibold))
                }
            }
        }
    }

    private var inlineText: String {
        let streak = entry.displayedStreak
        guard streak > 0 else { return Strings.string("widget.streak.ready") }
        return Strings.string("widget.streak.inline", .int(streak))
    }
}
