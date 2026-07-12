// Episode summary: the score, the dots, the flame. One click back to the stage.
import SwiftUI
import CouchKit

struct SummaryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 44) {
            Text("THAT'S THE SHOW")
                .font(CouchTypography.caption)
                .kerning(8)
                .foregroundStyle(.secondary)
            if let result = model.lastResult {
                Text("\(result.score)")
                    .couchText(CouchTypography.display)
                HStack(spacing: 24) {
                    GlassChip("\(result.correctCount) of 10 correct", systemImage: "checkmark.circle")
                    GlassChip("Speed dots · \(result.dots)", systemImage: "bolt.fill")
                    if result.isLate {
                        GlassChip("Played late", systemImage: "moon.zzz")
                    }
                }
                if model.streakDisplay > 0 && !result.isLate {
                    GlassChip("Streak · \(model.streakDisplay)", systemImage: "flame.fill")
                }
            }
            GlassChip("Click — back to the stage", systemImage: "hand.tap")
                .opacity(0.65)
        }
        .padding(.horizontal, 130)
        .padding(.vertical, 90)
        .couchGlass(in: RoundedRectangle(cornerRadius: 60, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .couchRemote(interceptsBack: true) { gesture in
            model.handleSummary(gesture)
        }
    }
}
