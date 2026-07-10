// ChannelView — the only screen. Full-bleed art, transient glass chrome,
// the complete remote grammar via .couchRemote. Default state: zero UI.
import SwiftUI
import CouchKit

struct ChannelView: View {
    @State private var model = ChannelViewModel()
    @State private var chrome = ChromeVisibility()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        ZStack {
            CouchPalette.void.ignoresSafeArea()
            artLayers
            frozenFrameEdge
        }
        .animation(.couchFast, value: model.isFrozen)
        .overlay(alignment: .top) { statusChips }
        .overlay(alignment: .bottom) { bottomChrome }
        .overlay {
            GlassSheet(isPresented: $model.showPrefs) {
                PrefsSheetContent(model: model)
            }
        }
        .couchRemote(chrome: chrome, eightWay: true) { gesture in
            guard !model.showPrefs else { return }
            model.handle(gesture)
        }
        .background(CouchPalette.void.ignoresSafeArea())
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.sceneBecameActive() }
        }
    }

    // MARK: Art (double-buffered crossfade, z-swapped so landings never flash)

    private var artLayers: some View {
        ZStack {
            if let frame = model.layerA {
                artLayer(frame, isStaging: model.stagingIsA)
                    .opacity(model.stagingIsA ? model.stagingOpacity : 1)
                    .zIndex(model.stagingIsA ? 1 : 0)
            }
            if let frame = model.layerB {
                artLayer(frame, isStaging: !model.stagingIsA)
                    .opacity(model.stagingIsA ? 1 : model.stagingOpacity)
                    .zIndex(model.stagingIsA ? 0 : 1)
            }
        }
        .ignoresSafeArea()
    }

    private func artLayer(_ frame: ChannelViewModel.Frame, isStaging: Bool) -> some View {
        // A morph fades in through a coarser grid; landing re-renders fine,
        // so the glyphs visibly re-sort themselves. Freeze halts drift.
        let cols = (isStaging && model.morphActive)
            ? MorphGrid.coarseCols(fineCols: ChannelViewModel.fineCols)
            : ChannelViewModel.fineCols
        return AsciiArtView(
            image: frame.image,
            style: model.style,
            drift: model.isFrozen ? nil : DriftPath(seed: frame.seed),
            grid: .fit(cols: cols),
            seed: frame.seed
        )
    }

    // MARK: Freeze treatment (PRD §5: mounted, not paused)

    @ViewBuilder
    private var frozenFrameEdge: some View {
        if model.isFrozen {
            Rectangle()
                .strokeBorder(.white.opacity(0.22), lineWidth: 2)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: Transient status chips (top) — independent of resting chrome

    private var statusChips: some View {
        VStack(spacing: 16) {
            if let lane = model.laneChip {
                GlassChip(lane, systemImage: "square.stack")
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let playback = model.playbackChip {
                GlassChip(playback.text, systemImage: playback.symbol)
                    .transition(.opacity)
            }
            if let connect = model.connectChip {
                GlassChip(connect, systemImage: "icloud")
                    .transition(.opacity)
            }
        }
        .padding(.top, 64)
        .animation(.couchFast, value: model.laneChip)
        .animation(.couchFast, value: model.playbackChip)
        .animation(.couchAmbient, value: model.connectChip)
        .allowsHitTesting(false)
    }

    // MARK: Resting chrome (caption chip + style pill), recedes with idle

    private var bottomChrome: some View {
        VStack(spacing: 20) {
            if let caption = model.currentFrame?.caption {
                GlassChip(caption, systemImage: "photo.on.rectangle")
            }
            StyleDotsPill(current: model.style)
        }
        .padding(.bottom, 72)
        .opacity(chrome.isVisible ? 1 : 0)
        .blur(radius: chrome.isVisible ? 0 : 12)
        .offset(y: chrome.isVisible ? 0 : 24)
        .animation(chrome.isVisible ? .couchFast : .couchAmbient, value: chrome.isVisible)
        .allowsHitTesting(false)
    }
}
