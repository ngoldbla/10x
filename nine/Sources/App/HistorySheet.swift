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
