// HistorySheet.swift — the record of every solved board: totals, best times
// per difficulty, the recent log, and the door into Game Center. Lives in
// the same GlassSheet shell as prefs (the suite's one secondary surface —
// only ever one open at a time). On macOS the same content fills the History
// window opened from the Game menu (⌘Y, PRD-4 §2.6); on tvOS it opens from a
// shelf History card, reachable by remote and pad alike (PRD-5 §2.3).
#if os(iOS) || os(macOS) || os(tvOS)
import SwiftUI
import CouchKit

struct HistorySheetContent: View {
    let model: AppModel
    /// tvOS only: a focusable dismiss control so the remote/pad can always
    /// leave the sheet (the Game Center row is disabled when signed out, which
    /// would otherwise leave nothing for the focus engine to land on). Nil on
    /// iOS/macOS, where the scrim tap / window chrome dismisses.
    var onClose: (@MainActor () -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    /// The accent resolved for the theme's leaning (themes pin the scheme).
    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    /// Theme tones for re-theming the stat views (muted tracks, empty cells)
    /// so they read on Paper and the tinted themes, not just Void.
    private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }

    /// The new stat sections need a real history to be worth drawing; below
    /// this they collapse to the guidance line (PRD-9 §2 — never an empty chart).
    private var hasRichStats: Bool { model.history.records.count >= 5 }

    /// TV read distance wants everything larger; iOS/macOS keep their exact
    /// pixel sizes (`1.0`), so this widening is byte-identical off the couch.
    private var s: CGFloat {
        #if os(tvOS)
        1.7
        #else
        1.0
        #endif
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24 * s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("History")
                        .couchText(CouchTypography.title)
                    #if os(tvOS)
                    if let onClose {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 22 * s, weight: .semibold))
                                .padding(18 * s)
                                .couchGlassInteractive(in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close history")
                    }
                    #endif
                }
                .padding(.bottom, 4)

                totalsRow

                if hasRichStats {
                    heatSection
                    avgVsBestSection
                    trendSection
                } else {
                    Text("Solve a board and it lands here — time, difficulty and points.")
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                gameCenterRow

                if !model.history.records.isEmpty {
                    recentSolves
                }

                Spacer(minLength: 12)

                // On Mac this is a real window with a close button — the
                // dismissal footer is touch guidance and would read wrong.
                #if os(tvOS)
                Text("Press Back to return")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.tertiary)
                #elseif !os(macOS)
                Text("Tap outside to return")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.tertiary)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Totals

    private var totalsRow: some View {
        HStack(spacing: 10) {
            statBlock(value: "\(model.totalPoints)", label: "points")
            statBlock(value: "\(model.history.records.count)", label: "solved")
            statBlock(value: "\(model.streak.best)", label: "best streak")
        }
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 4 * s) {
            Text(value)
                .font(.system(size: 22 * s, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 11 * s, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12 * s)
        .couchGlass(in: RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
    }

    // MARK: - Heat grid (last 12 weeks)

    private var heatColumns: [[HeatCell]] {
        let today = model.todayOrdinal
        let start = today - (12 * 7 - 1)            // 84 days incl. today
        let buckets = model.history.solvesByDay(ordinalRange: start...today)
        return (0..<12).map { col in
            (0..<7).map { row in
                let ord = start + col * 7 + row
                let day = buckets[ord]
                return HeatCell(id: ord, count: day?.count ?? 0, hasDaily: day?.hasDaily ?? false)
            }
        }
    }

    private var heatSection: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            sectionHeader("Last 12 weeks")
            HeatGrid(columns: heatColumns,
                     accent: accent,
                     emptyTrack: tones.gridTone.opacity(0.10),
                     s: s)
        }
    }

    // MARK: - Average vs. best

    private var avgVsBestRows: [(Difficulty, TimeInterval, TimeInterval)] {
        Difficulty.allCases.compactMap { d in
            guard let avg = model.history.averageSeconds(for: d),
                  let best = model.history.bestSeconds(for: d) else { return nil }
            return (d, avg, best)
        }
    }

    @ViewBuilder
    private var avgVsBestSection: some View {
        let rows = avgVsBestRows
        if !rows.isEmpty {
            let maxAvg = rows.map(\.1).max() ?? 1
            VStack(alignment: .leading, spacing: 12 * s) {
                sectionHeader("Average vs. best")
                ForEach(rows, id: \.0) { difficulty, avg, best in
                    TwinBar(title: difficulty.title,
                            avg: avg / maxAvg,
                            best: best / maxAvg,
                            bestLabel: Self.format(best),
                            avgLabel: Self.format(avg),
                            accent: accent,
                            track: tones.gridTone.opacity(0.10),
                            s: s)
                }
            }
        }
    }

    // MARK: - Solve-time trend

    @ViewBuilder
    private var trendSection: some View {
        let raw = model.history.trend(window: 20)
        if raw.count >= 2 {
            let lo = raw.min() ?? 0, hi = raw.max() ?? 0
            let span = hi - lo
            let points = raw.map { span > 0 ? ($0 - lo) / span : 0.5 }
            let faster = raw.last! < raw.first!
            VStack(alignment: .leading, spacing: 10 * s) {
                sectionHeader("Solve time trend", trailing: faster ? "▼ faster" : nil)
                Sparkline(points: points, accent: accent)
                    .frame(height: 56 * s)
            }
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ text: String, trailing: String? = nil) -> some View {
        HStack {
            Text(text)
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(CouchTypography.caption)
                    .foregroundStyle(accent)
            }
        }
    }

    // MARK: - Game Center

    private var gameCenterRow: some View {
        Button {
            GameCenter.shared.showDashboard()
        } label: {
            HStack(spacing: 12 * s) {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 19 * s, weight: .semibold))
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text("Game Center")
                        .font(CouchTypography.body)
                    Text(GameCenter.shared.isAuthenticated
                         ? "Leaderboards & achievements"
                         : "Sign in via Settings to compete")
                        .font(.system(size: 11 * s, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if GameCenter.shared.isAuthenticated {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13 * s, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14 * s)
            .couchGlassInteractive(in: RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!GameCenter.shared.isAuthenticated)
    }

    // MARK: - Recent solves

    private var recentSolves: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
            ForEach(model.history.records.prefix(15)) { record in
                HStack(spacing: 10 * s) {
                    Image(systemName: record.isDaily ? "sun.max" : "square.grid.3x3")
                        .font(.system(size: 14 * s, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22 * s)
                    VStack(alignment: .leading, spacing: 1 * s) {
                        Text(record.isDaily ? "Daily · \(record.difficulty.title)" : record.difficulty.title)
                            .font(CouchTypography.caption)
                        Text(record.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11 * s, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(Self.format(record.seconds))
                        .font(CouchTypography.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text("+\(record.points)")
                        .font(CouchTypography.caption)
                        .foregroundStyle(accent)
                }
            }
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
#endif
