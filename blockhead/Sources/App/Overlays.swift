// The pause curtain and the one prefs GlassSheet (timer length, reduce-flash).
import SwiftUI
import CouchKit

// MARK: - Pause curtain

struct PauseCurtain: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 80, weight: .heavy))
                    .foregroundStyle(.primary)
                Text("Intermission")
                    .couchText(CouchTypography.title)
                Text("Press play to continue")
                    .font(CouchTypography.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 110)
            .padding(.vertical, 80)
            .couchGlass(in: RoundedRectangle(cornerRadius: 56, style: .continuous))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Prefs (the suite's single glass sheet)

// Driven by the same RemoteKit path as every menu: the root's remote
// surface keeps focus and forwards gestures, so rows highlight via
// `model.prefsSelection` (0…2 = timer options, 3 = reduce-flash).
struct PrefsPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            Text("House Rules")
                .couchText(CouchTypography.title)

            // The sheet doubles as the manual after the first-run overlay.
            ControlLegend(rows: BlockheadLegend.compact)

            VStack(alignment: .leading, spacing: 20) {
                Text("QUESTION TIMER")
                    .font(CouchTypography.caption)
                    .kerning(4)
                    .foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    ForEach(Array(AppModel.timerOptions.enumerated()), id: \.offset) { index, seconds in
                        PrefsOption(
                            label: "\(seconds)s",
                            isActive: model.timerSeconds == seconds,
                            isCursor: model.prefsSelection == index
                        )
                    }
                }
                Text("Applies from the next show.")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 20) {
                Text("COMFORT")
                    .font(CouchTypography.caption)
                    .kerning(4)
                    .foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    Image(systemName: model.reduceFlash ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 34))
                        .foregroundStyle(.primary)
                    Text("Reduce flash")
                        .font(CouchTypography.body)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(.white.opacity(model.prefsSelection == 3 ? 0.14 : 0))
                )
                Text("Softer verdict lighting, gentler reveals.")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Swipe to choose · Click to set · Back closes")
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.couchFast, value: model.prefsSelection)
    }
}

private struct PrefsOption: View {
    let label: String
    let isActive: Bool
    let isCursor: Bool

    var body: some View {
        Text(label)
            .font(CouchTypography.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, 34)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(.white.opacity(isActive ? 0.22 : 0.06))
            )
            .overlay(
                Capsule().strokeBorder(.white.opacity(isCursor ? 0.5 : 0), lineWidth: 2)
            )
            .scaleEffect(isCursor ? 1.05 : 1.0)
    }
}
