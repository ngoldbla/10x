// NineApp.swift — entry point. Full-bleed void, two screens, no chrome that
// isn't glass. Launches straight to the shelf: zero onboarding.
import SwiftUI
import CouchKit

@main
struct NineApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        ZStack {
            CouchPalette.void.ignoresSafeArea()
            BreathingVoid()
            switch model.screen {
            case .home:
                HomeView(model: model)
                    .transition(.opacity)
            case .game:
                GameScreen(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.couchAmbient, value: model.screen)
    }
}

/// The almost-subliminal background luminance breath (PRD §6): 8%–10% peak
/// luminance on a 60-second period, so long sessions never feel static.
struct BreathingVoid: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breath = 0.09 + 0.01 * sin(t * 2 * .pi / 60)
            RadialGradient(
                colors: [Color.white.opacity(breath * 0.5), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 1600
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
