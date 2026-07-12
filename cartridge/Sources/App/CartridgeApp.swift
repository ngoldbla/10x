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

    var body: some View {
        FeedView(model: model, locker: locker, chrome: chrome)
            .overlay { PrefsSheetView(model: model) }
            .couchRemote(
                chrome: chrome,
                eightWay: true,                       // enables playPauseLongPress
                interceptsBack: model.mode != .feed   // Back exits app only from the feed
            ) { gesture in
                model.handle(gesture)
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
    }

    /// Rebuild the sprite locker when the lane pref changes.
    private var lockerKey: String {
        model.spriteLane.rawValue
    }
}
