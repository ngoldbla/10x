// Darkroom — the one allowed prefs surface: a glass sheet reached by
// long-pressing play/pause (suite rule). The manual up top, two
// preferences, and the photo census.
import SwiftUI
import CouchKit

struct PrefsSheet: View {
    @Bindable var model: AppModel

    /// Library census, refetched each time the sheet opens (design §5).
    @State private var census: (photos: Int, favorites: Int)?

    private let speeds: [(name: String, value: Int)] = [
        ("Gentle", 1), ("Standard", 2), ("Swift", 3),
    ]

    var body: some View {
        GlassSheet(isPresented: $model.showPrefs) {
            VStack(alignment: .leading, spacing: 40) {
                Text("Darkroom")
                    .font(CouchTypography.title)
                    .foregroundStyle(.primary)

                // The sheet doubles as the manual after first launch
                // (design §6) — the essential four rows only.
                ControlLegend(rows: Array(AppModel.legendRows.prefix(4)))

                VStack(alignment: .leading, spacing: 20) {
                    Text("Cursor speed")
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 18) {
                        ForEach(speeds, id: \.value) { option in
                            let selected = model.prefs.cursorMomentum == option.value
                            Button {
                                model.prefs.cursorMomentum = option.value
                            } label: {
                                Text(option.name)
                                    .font(CouchTypography.caption)
                                    .padding(.horizontal, 26)
                                    .padding(.vertical, 12)
                                    .background(
                                        Color.white.opacity(selected ? 0.18 : 0.04),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 20) {
                    Text("Clue palette")
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        model.prefs.colorblindClues.toggle()
                    } label: {
                        Label(
                            model.prefs.colorblindClues
                                ? "Colorblind-safe · On"
                                : "Colorblind-safe · Off",
                            systemImage: model.prefs.colorblindClues
                                ? "eye.fill" : "eye"
                        )
                        .font(CouchTypography.caption)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(
                            Color.white.opacity(model.prefs.colorblindClues ? 0.18 : 0.04),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 20) {
                    Text("Photos")
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                    Text(censusLine)
                        .font(CouchTypography.caption)
                }
                .task { census = await CouchPhotos.census() }

                Spacer()

                Text("Photos never leave this Apple TV.")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var censusLine: String {
        guard let census else { return "Counting photos…" }
        return PhotoStatusLine.text(photos: census.photos, favorites: census.favorites)
    }
}
