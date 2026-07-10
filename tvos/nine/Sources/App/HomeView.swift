// HomeView.swift — the shelf (PRD §4.1). Full-bleed void, floating glass
// cards: Today, Continue (only when a free-play board is in progress), and
// three Free Play difficulty slabs rendered as increasingly dense
// mini-boards. A GlassChip shows the daily streak. Nothing else.
import SwiftUI
import CouchKit

struct HomeView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 64) {
            header
            HStack(alignment: .top, spacing: 56) {
                todayCard
                if model.savedFree != nil {
                    continueCard
                }
            }
            freePlayRow
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 28) {
            Text("Nine")
                .couchText(CouchTypography.title)
            Spacer()
            if model.displayedStreak > 0 {
                GlassChip("\(model.displayedStreak) day streak", systemImage: "flame")
            }
        }
    }

    // MARK: - Today

    private var todayCard: some View {
        ShelfCard(width: 620, height: 360, action: { model.openToday() }) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Today")
                    .couchText(CouchTypography.title)
                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                todayStatus
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var todayStatus: some View {
        if isComposing(kindMatches: { if case .daily = $0 { return true }; return false }) {
            statusLabel("Composing…", symbol: "sparkles")
        } else if model.todaySolved {
            statusLabel("Solved", symbol: "checkmark.circle.fill")
        } else if let daily = model.savedDaily {
            HStack(spacing: 20) {
                GlassRing(progress: daily.fillFraction)
                    .frame(width: 64, height: 64)
                Text("Continue")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            statusLabel("One a day", symbol: "sun.max")
        }
    }

    // MARK: - Continue (free play in progress)

    @ViewBuilder
    private var continueCard: some View {
        if let (game, difficulty) = model.savedFree {
            ShelfCard(width: 460, height: 360, action: { model.continueSaved() }) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Continue")
                        .couchText(CouchTypography.title)
                    Text(difficulty.title)
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 20) {
                        GlassRing(progress: game.fillFraction)
                            .frame(width: 64, height: 64)
                        Text("\(Int(game.fillFraction * 100))%")
                            .font(CouchTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    // MARK: - Free play

    private var freePlayRow: some View {
        HStack(spacing: 44) {
            ForEach(Difficulty.allCases, id: \.self) { difficulty in
                difficultyCard(difficulty)
            }
        }
    }

    private func difficultyCard(_ difficulty: Difficulty) -> some View {
        ShelfCard(width: 360, height: 300, action: { model.startFree(difficulty) }) {
            VStack(spacing: 20) {
                MiniBoard(difficulty: difficulty, accent: model.prefs.accent.color)
                    .frame(width: 132, height: 132)
                if isComposing(kindMatches: { $0 == .free(difficulty) }) {
                    statusLabel("Composing…", symbol: "sparkles")
                } else {
                    Text(difficulty.title)
                        .font(CouchTypography.body)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func statusLabel(_ text: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
            Text(text)
                .font(CouchTypography.caption)
        }
        .foregroundStyle(.secondary)
    }

    private func isComposing(kindMatches: (GameKind) -> Bool) -> Bool {
        guard let composing = model.composing else { return false }
        return kindMatches(composing)
    }
}

/// A floating glass slab with the suite focus treatment. Focusable through
/// `focusHalo`; a clickpad press fires `action`.
private struct ShelfCard<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let action: @MainActor () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(36)
            .frame(width: width, height: height)
            .couchGlassInteractive(in: RoundedRectangle(cornerRadius: 40, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            .focusHalo()
            .onTapGesture { action() }
    }
}

/// A difficulty preview: a 9×9 field of dots whose density grows with the
/// difficulty. Deterministic (CouchHash), so the shelf never flickers.
private struct MiniBoard: View {
    let difficulty: Difficulty
    let accent: Color

    private var density: Double {
        switch difficulty {
        case .gentle: return 0.30
        case .steady: return 0.48
        case .sharp: return 0.68
        }
    }

    var body: some View {
        Canvas { context, size in
            let cell = size.width / 9
            let seed: UInt64 = 0x91
            for y in 0..<9 {
                for x in 0..<9 {
                    guard CouchHash.noise(x, y, seed: seed) < density else { continue }
                    let rect = CGRect(
                        x: CGFloat(x) * cell + cell * 0.3,
                        y: CGFloat(y) * cell + cell * 0.3,
                        width: cell * 0.4,
                        height: cell * 0.4
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(accent.opacity(0.85)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
