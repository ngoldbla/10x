// The stage (home): tonight's marquee slab center, Party and Archive slabs
// flanking, streak chip floating top-right. Swipe to choose, click to play.
import SwiftUI
import CouchKit

struct StageView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 64) {
                SideSlab(
                    title: "Party",
                    symbol: "person.2.fill",
                    caption: "Pass the remote",
                    isSelected: model.stageSelection == 1
                )
                MarqueeSlab(isSelected: model.stageSelection == 0)
                SideSlab(
                    title: "Archive",
                    symbol: "clock.arrow.circlepath",
                    caption: "Past nights",
                    isSelected: model.stageSelection == 2
                )
            }
            Spacer()
            GlassChip("Swipe to choose · Click to play", systemImage: "arrow.left.and.right")
                .opacity(0.65)
                .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if model.streakDisplay > 0 {
                GlassChip("Streak · \(model.streakDisplay)", systemImage: "flame.fill")
                    .padding(56)
            }
        }
        .couchRemote(eightWay: true) { gesture in
            model.handleStage(gesture)
        }
    }
}

// MARK: - Marquee

private struct MarqueeSlab: View {
    @Environment(AppModel.self) private var model
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("TONIGHT'S EPISODE")
                .font(CouchTypography.caption)
                .kerning(6)
                .foregroundStyle(.secondary)
            Text("#\(model.tonightNumber)")
                .couchText(CouchTypography.display)
            statusChip
        }
        .padding(.horizontal, 90)
        .padding(.vertical, 60)
        .couchGlassInteractive(in: RoundedRectangle(cornerRadius: 48, style: .continuous))
        .selectionHalo(isSelected, cornerRadius: 48)
    }

    @ViewBuilder
    private var statusChip: some View {
        switch model.tonightState {
        case .sealed:
            GlassChip("Sealed · 10 questions", systemImage: "sparkles")
        case .inProgress:
            GlassChip("Resume", systemImage: "play.fill")
        case .done(let score):
            GlassChip("Score \(score) · Encore", systemImage: "checkmark")
        }
    }
}

// MARK: - Side slabs

private struct SideSlab: View {
    let title: String
    let symbol: String
    let caption: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.primary)
            Text(title)
                .couchText(CouchTypography.body)
            Text(caption)
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 54)
        .padding(.vertical, 46)
        .couchGlassInteractive(in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        .selectionHalo(isSelected, cornerRadius: 40)
    }
}
