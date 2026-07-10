// Darkroom — the develop (PRD §4.5). Signature Moment #1.
//
// On the final fill the board holds one beat, then liquefies from
// logic-squares into the photograph: solved grid → chunky pixel render →
// soft mosaic → the full image, ~4 seconds, a reversed AsciiKit ramp.
import SwiftUI
import CouchKit

struct DevelopOverlay: View {
    let phase: DevelopPhase
    let pixel: CGImage?
    let mosaic: CGImage?
    let photo: CGImage?
    let caption: String

    var body: some View {
        ZStack {
            CouchPalette.void
                .ignoresSafeArea()
                .opacity(phase >= .pixel ? 1 : 0)
                .animation(.easeInOut(duration: 1.0), value: phase)

            stage(pixel, visible: phase == .pixel)
            stage(mosaic, visible: phase == .mosaic)
            stage(photo, visible: phase >= .photo)
        }
        .overlay(alignment: .bottom) {
            if phase >= .photo, !caption.isEmpty {
                GlassChip(caption, systemImage: "sparkles")
                    .padding(.bottom, 80)
                    .transition(.opacity)
            }
        }
        .animation(.couchAmbient, value: phase)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func stage(_ image: CGImage?, visible: Bool) -> some View {
        GeometryReader { geo in
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
        .ignoresSafeArea()
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 1.1), value: visible)
    }
}
