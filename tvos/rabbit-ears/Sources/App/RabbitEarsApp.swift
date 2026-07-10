// Rabbit Ears — your photo library as a living, conductable ASCII/pixel-art
// channel. One screen, zero onboarding, dark-first.
import SwiftUI
import CouchKit

@main
struct RabbitEarsApp: App {
    var body: some Scene {
        WindowGroup {
            ChannelView()
                .preferredColorScheme(.dark)
        }
    }
}
