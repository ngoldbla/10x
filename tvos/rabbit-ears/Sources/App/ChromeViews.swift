// The chrome inventory (PRD §5): the style pill's dots and the prefs sheet
// content. All glass goes through CouchKit's couchGlass — never .glassEffect.
import SwiftUI
import CouchKit

// MARK: - StyleDotsPill

/// The one GlassPill of the app: five style dots plus the current style's
/// name. Dots are passive indicators — swipe ←/→ conducts the change — so the
/// channel never shows a focus ring (PRD §6).
struct StyleDotsPill: View {
    let current: AsciiStyle

    var body: some View {
        HStack(spacing: 26) {
            HStack(spacing: 22) {
                ForEach(AsciiStyle.allCases, id: \.self) { style in
                    dot(for: style)
                }
            }
            Text(current.displayName)
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 22)
        .couchGlass(in: Capsule())
        .animation(.couchFast, value: current)
    }

    private func dot(for style: AsciiStyle) -> some View {
        let isCurrent = style == current
        return Circle()
            .fill(color(for: style))
            .frame(width: isCurrent ? 20 : 13, height: isCurrent ? 20 : 13)
            .opacity(isCurrent ? 1 : 0.45)
            .overlay {
                if isCurrent {
                    Circle()
                        .strokeBorder(.white.opacity(0.65), lineWidth: 2)
                        .padding(-5)
                }
            }
    }

    private func color(for style: AsciiStyle) -> Color {
        switch style {
        case .terminal: return Color(red: 0.86, green: 0.89, blue: 0.82)
        case .phosphor: return Color(red: 0.24, green: 0.94, blue: 0.42)
        case .pixel: return Color(red: 0.98, green: 0.62, blue: 0.24)
        case .inkline: return CouchPalette.paper
        case .mosaic: return Color(red: 0.42, green: 0.62, blue: 0.96)
        }
    }
}

// MARK: - PrefsSheetContent

/// The single GlassSheet: crossfade speed (3 choices) + start-on-wake.
/// Reached via play/pause long-press; Back dismisses.
struct PrefsSheetContent: View {
    let model: ChannelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            Text("Rabbit Ears")
                .couchText(CouchTypography.title)

            VStack(alignment: .leading, spacing: 20) {
                Text("CROSSFADE")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                ForEach(CrossfadeSpeed.allCases, id: \.self) { speed in
                    Button {
                        model.setSpeed(speed)
                    } label: {
                        HStack {
                            Text(speed.displayName)
                                .font(CouchTypography.body)
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 30, weight: .semibold))
                                .opacity(model.prefs.speed == speed ? 1 : 0)
                        }
                    }
                }
            }

            Button {
                model.setStartOnWake(!model.prefs.startOnWake)
            } label: {
                HStack {
                    Text("Start on wake")
                        .font(CouchTypography.body)
                    Spacer()
                    Image(systemName: model.prefs.startOnWake ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 34, weight: .semibold))
                }
            }

            Spacer()

            Text("Swipe for styles · Click to freeze · Hold to morph")
                .font(CouchTypography.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
