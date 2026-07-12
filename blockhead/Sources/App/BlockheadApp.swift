// Blockhead — the nightly living-room game show.
// Launches straight onto the stage: no onboarding, no permissions needed
// (picture rounds render CouchCore DemoArt, not photos).
import SwiftUI
import CouchKit

@main
struct BlockheadApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
