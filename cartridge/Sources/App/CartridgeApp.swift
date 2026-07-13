// Cartridge — channel-surf a bottomless feed of one-input micro-games
// starring sprites made from your own photos. Couch Suite / tvOS.
import SwiftUI
import CouchKit

@main
struct CartridgeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var model = FeedModel()
    @State private var locker = SpriteLocker()
    @State private var chrome = ChromeVisibility()
    /// One "Hold ▶︎ for settings" flash per session — @State resets on
    /// relaunch, which is exactly the lifetime we want.
    @State private var showSettingsHint = false
    @State private var settingsHintFlashed = false

    var body: some View {
        // Exactly one remote owner at a time (the Nine sheet pattern, one
        // state wider): the first-run overlay owns the remote while unseen;
        // while the prefs sheet is up the surface detaches so the tvOS focus
        // engine can walk the sheet's Buttons; otherwise the feed listens.
        Group {
            if !model.helpSeen {
                core.overlay {
                    HelpOverlay(
                        title: "Cartridge",
                        tagline: "Micro-games starring your photos.",
                        rows: CartridgeLegend.full
                    ) {
                        model.helpSeen = true
                    }
                }
            } else if model.showPrefs {
                core
            } else {
                core.couchRemote(
                    chrome: chrome,
                    eightWay: true,                       // enables playPauseLongPress
                    interceptsBack: model.mode != .feed   // Back exits app only from the feed
                ) { gesture in
                    model.handle(gesture)
                }
            }
        }
        .background(CouchPalette.void.ignoresSafeArea())
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .task {
            // The one allowed system prompt; DemoArt covers a "no".
            if PhotoAccess.canPrompt {
                _ = await PhotoAccess.request()
            }
        }
        .task(id: lockerKey) {
            await locker.build(day: model.day, lane: model.spriteLane)
        }
        .task(id: model.helpSeen) {
            await flashSettingsHint()
        }
    }

    private var core: some View {
        FeedView(model: model, locker: locker, chrome: chrome)
            .overlay { PrefsSheetView(model: model) }
            .overlay(alignment: .top) { settingsHintChip }
    }

    /// Rebuild the sprite locker when the lane pref changes.
    private var lockerKey: String {
        model.spriteLane.rawValue
    }

    // MARK: Settings discoverability

    @ViewBuilder
    private var settingsHintChip: some View {
        if showSettingsHint, model.mode == .feed {
            GlassChip("Hold ▶︎ for settings", systemImage: "gearshape")
                .padding(.top, 48)
                .transition(.opacity)
        }
    }

    /// Flash the settings hint once per session, and only after the help
    /// gate clears — first-run players read the overlay, not a chip race.
    private func flashSettingsHint() async {
        guard model.helpSeen, !settingsHintFlashed else { return }
        settingsHintFlashed = true
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.couchFast) { showSettingsHint = true }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        withAnimation(.couchAmbient) { showSettingsHint = false }
    }
}
