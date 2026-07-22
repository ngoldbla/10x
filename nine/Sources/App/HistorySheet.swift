// HistorySheet.swift — the record of every solved board: totals, best times
// per difficulty, the recent log, and the door into Game Center. Lives in
// the same GlassSheet shell as prefs (the suite's one secondary surface —
// only ever one open at a time).
#if os(iOS)
import SwiftUI
import CouchKit

struct HistorySheetContent: View {
    let model: AppModel

    @Environment(\.colorScheme) private var colorScheme

    /// The accent resolved for the theme's leaning (themes pin the scheme).
    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text("History")
                    .couchText(CouchTypography.title)
                    .padding(.bottom, 4)

                totalsRow

                bestTimes

                gameCenterRow

                if model.history.records.isEmpty {
                    Text("Solve a board and it lands here — time, difficulty and points.")
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    recentSolves
                }

                Spacer(minLength: 12)

                Text("Tap outside to return")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.tertiary)
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
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .couchGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Best times

    @ViewBuilder
    private var bestTimes: some View {
        let bests = Difficulty.allCases.compactMap { difficulty in
            model.history.bestSeconds(for: difficulty).map { (difficulty, $0) }
        }
        if !bests.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Best times")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                ForEach(bests, id: \.0) { difficulty, seconds in
                    HStack {
                        Text(difficulty.title)
                            .font(CouchTypography.body)
                        Spacer()
                        Text(Self.format(seconds))
                            .font(CouchTypography.body)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Game Center

    private var gameCenterRow: some View {
        Button {
            GameCenter.shared.showDashboard()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 19, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Game Center")
                        .font(CouchTypography.body)
                    Text(GameCenter.shared.isAuthenticated
                         ? "Leaderboards & achievements"
                         : "Sign in via Settings to compete")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if GameCenter.shared.isAuthenticated {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .couchGlassInteractive(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                HStack(spacing: 10) {
                    Image(systemName: record.isDaily ? "sun.max" : "square.grid.3x3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(record.isDaily ? "Daily · \(record.difficulty.title)" : record.difficulty.title)
                            .font(CouchTypography.caption)
                        Text(record.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
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
