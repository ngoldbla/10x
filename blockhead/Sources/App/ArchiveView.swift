// The archive: past nights, playable but streak-honest — late plays are
// marked. Swipe up/down, click to open a past episode.
import SwiftUI
import CouchKit

struct ArchiveView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries = model.archiveEntries
        VStack(spacing: 28) {
            Text("THE ARCHIVE")
                .font(CouchTypography.caption)
                .kerning(8)
                .foregroundStyle(.secondary)
            if entries.isEmpty {
                Text("Tonight is the first show.")
                    .couchText(CouchTypography.body)
                    .padding(.vertical, 60)
            } else {
                VStack(spacing: 16) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        ArchiveRow(entry: entry, isSelected: index == model.archiveSelection)
                    }
                }
            }
            GlassChip("Late plays are marked — streak-honest", systemImage: "flame")
                .opacity(0.55)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ArchiveRow: View {
    let entry: ArchiveEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 28) {
            Text("#\(entry.episodeNumber)")
                .font(CouchTypography.body)
                .foregroundStyle(.primary)
            Text(EpisodeCalendar.date(forDay: entry.dayNumber), format: .dateTime.month(.wide).day())
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let result = entry.result {
                if entry.isLate {
                    GlassChip("Late", systemImage: "moon.zzz")
                }
                GlassChip("Score \(result.score)", systemImage: "checkmark")
            } else {
                GlassChip("Sealed", systemImage: "sparkles")
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .frame(width: 1040)
        .couchGlassInteractive(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .selectionHalo(isSelected, cornerRadius: 28)
    }
}
