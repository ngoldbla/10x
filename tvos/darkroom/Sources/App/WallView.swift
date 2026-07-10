// Darkroom — the wall (PRD §4.1). Three undeveloped plates floating over
// pitch black, each glowing with an unrecognizable aura of its hidden photo.
// Swipe between plates, click to begin. Solved plates hang developed.
import SwiftUI
import CouchKit

struct WallView: View {
    @Bindable var model: AppModel
    @State private var chrome = ChromeVisibility()

    private var selectedAura: Color {
        guard model.plates.indices.contains(model.selectedPlate) else {
            return CouchPalette.fallbackAccent
        }
        return model.plates[model.selectedPlate].aura
    }

    var body: some View {
        ZStack {
            // The darkroom: black, breathing faintly with the selected plate.
            RadialGradient(
                colors: [selectedAura.opacity(0.10), CouchPalette.void],
                center: .center,
                startRadius: 200,
                endRadius: 1400
            )
            .ignoresSafeArea()
            .animation(.couchAmbient, value: model.selectedPlate)

            HStack(spacing: 64) {
                ForEach(Array(model.plates.enumerated()), id: \.element.id) { index, plate in
                    PlateView(
                        plate: plate,
                        whisper: model.whisper(for: plate),
                        caption: model.caption(for: plate),
                        isSelected: index == model.selectedPlate
                    )
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.streak > 0 {
                GlassChip("\(model.streak) day streak", systemImage: "flame.fill")
                    .padding(56)
            }
        }
        .overlay(alignment: .bottom) {
            Text(model.isLoading
                 ? "Developing tonight's plates…"
                 : "Swipe to choose · Click to develop")
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
                .opacity(model.isLoading || chrome.isVisible ? 1 : 0)
                .animation(.couchAmbient, value: chrome.isVisible)
                .padding(.bottom, 64)
        }
        .overlay { PrefsSheet(model: model) }
        .couchRemote(chrome: chrome, eightWay: true) { gesture in
            guard !model.showPrefs else {
                if gesture == .playPauseLongPress || gesture == .back {
                    model.showPrefs = false
                }
                return
            }
            switch gesture {
            case .swipe(.left):
                model.selectedPlate = max(0, model.selectedPlate - 1)
            case .swipe(.right):
                model.selectedPlate = min(model.plates.count - 1, model.selectedPlate + 1)
            case .click:
                model.openSelectedPlate()
            case .playPauseLongPress:
                model.showPrefs = true
            default:
                break
            }
        }
    }
}

/// One plate: frosted glass over black, holding either a color aura
/// (undeveloped) or the developed photograph in a subtle glass frame.
struct PlateView: View {
    let plate: AppModel.Plate
    let whisper: String
    let caption: String
    let isSelected: Bool

    private let plateSize = CGSize(width: 440, height: 560)
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 36, style: .continuous)
    }

    var body: some View {
        ZStack {
            if plate.developed, let image = plate.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: plateSize.width, height: plateSize.height)
            } else if let image = plate.image {
                // The hidden photo as pure color weather: blurred beyond
                // recognition, dimmed under the glass.
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: plateSize.width, height: plateSize.height)
                    .blur(radius: 90)
                    .saturation(1.4)
                    .opacity(0.5)
            } else {
                RadialGradient(
                    colors: [plate.aura.opacity(0.45), .clear],
                    center: .center,
                    startRadius: 30,
                    endRadius: 330
                )
            }

            if !plate.developed {
                VStack(spacing: 12) {
                    Spacer()
                    if let session = plate.session, session.progress > 0 {
                        GlassRing(progress: session.progress, lineWidth: 6)
                            .frame(width: 56, height: 56)
                    }
                    Text("\(plate.slot.label) · \(plate.slot.rawValue)×\(plate.slot.rawValue)")
                        .font(CouchTypography.caption)
                        .foregroundStyle(.primary)
                    Text(whisper)
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 36)
            } else {
                VStack {
                    Spacer()
                    GlassChip(caption)
                        .padding(.bottom, 28)
                }
            }
        }
        .frame(width: plateSize.width, height: plateSize.height)
        .couchGlass(in: shape)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                .white.opacity(plate.developed ? 0.30 : 0.10),
                lineWidth: plate.developed ? 2 : 1
            )
        }
        .scaleEffect(isSelected ? 1.06 : 1.0)
        .shadow(
            color: .black.opacity(isSelected ? 0.6 : 0),
            radius: isSelected ? 40 : 0,
            y: isSelected ? 22 : 0
        )
        .animation(.couchFast, value: isSelected)
        .opacity(plate.puzzle == nil ? 0.35 : 1)
    }
}

/// A developed memory, hung full screen. Back (or click) returns to the wall.
struct MemoryView: View {
    var model: AppModel
    let slot: GridSize
    @State private var chrome = ChromeVisibility()

    var body: some View {
        ZStack {
            CouchPalette.void.ignoresSafeArea()
            if let image = model.plate(for: slot)?.image {
                GeometryReader { geo in
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .ignoresSafeArea()
                .idleAttract(chrome: chrome)
            }
        }
        .overlay(alignment: .bottom) {
            if let plate = model.plate(for: slot) {
                GlassChip(model.caption(for: plate), systemImage: "photo")
                    .opacity(chrome.isVisible ? 1 : 0)
                    .animation(.couchAmbient, value: chrome.isVisible)
                    .padding(.bottom, 64)
            }
        }
        .couchRemote(chrome: chrome, interceptsBack: true) { gesture in
            switch gesture {
            case .back, .click:
                model.returnToWall()
            default:
                break
            }
        }
    }
}
