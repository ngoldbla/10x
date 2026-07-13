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
                homeScreen
                    .transition(.opacity)
            case .game:
                gameScreen
                    .transition(.opacity)
            }
        }
        .animation(.couchFast, value: model.screen) // navigation is a response, not weather
        #if os(iOS)
        .preferredColorScheme(.dark) // the void is the brand; never white-room it
        #endif
    }

    // One model, two grammars: the TV screens speak remote (RemoteKit), the
    // touch screens speak fingers. Everything below them — engine, persistence,
    // board and rose rendering — is shared.
    @ViewBuilder
    private var homeScreen: some View {
        #if os(tvOS)
        HomeView(model: model)
        #else
        TouchHomeView(model: model)
        #endif
    }

    @ViewBuilder
    private var gameScreen: some View {
        #if os(tvOS)
        GameScreen(model: model)
        #else
        TouchGameScreen(model: model)
        #endif
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
