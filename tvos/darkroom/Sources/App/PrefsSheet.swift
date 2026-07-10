// Darkroom — the one allowed prefs surface: a glass sheet reached by
// long-pressing play/pause (suite rule). Two preferences, no more.
import SwiftUI
import CouchKit

struct PrefsSheet: View {
    @Bindable var model: AppModel

    private let speeds: [(name: String, value: Int)] = [
        ("Gentle", 1), ("Standard", 2), ("Swift", 3),
    ]

    var body: some View {
        GlassSheet(isPresented: $model.showPrefs) {
            VStack(alignment: .leading, spacing: 44) {
                Text("Darkroom")
                    .font(CouchTypography.title)
                    .foregroundStyle(.primary)

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

                Spacer()

                Text("Photos never leave this Apple TV.")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
