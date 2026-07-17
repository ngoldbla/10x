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
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    var body: some View {
        ZStack {
            VoidBackground()
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
        // Auto follows the device; dark stays the brand default feel, but a
        // sunny-couch player can pin light. tvOS remains void-dark always.
        .preferredColorScheme(model.prefs.appearance.colorScheme)
        .onAppear { GameCenter.shared.authenticate() }
        // Widget taps land on today's daily. openToday() is already safe
        // mid-composition (compose() guards on `composing`).
        .onOpenURL { url in
            guard url.scheme == "nine" else { return }
            let target = url.host() ?? url.pathComponents.dropFirst().first
            if target == "daily" {
                model.openToday()
            }
        }
        // Coming forward: merge any widget moves first (PRD-3 §4). Going
        // back: belt-and-braces publish so the Home Screen is fresh the
        // moment the app leaves it.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.ingestSharedDailyBoard()
            case .background:
                WidgetBridge.publish(from: model)
            default:
                break
            }
        }
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

/// The resting background. Dark is the void (true black, the brand); light
/// mode — iOS only, opted into via prefs or the system — swaps in a warm
/// paper tone so glass and shadows still have something to catch.
struct VoidBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme == .light ? Color(red: 0.94, green: 0.93, blue: 0.90) : CouchPalette.void)
            .ignoresSafeArea()
    }
}

/// The almost-subliminal background luminance breath (PRD §6): 8%–10% peak
/// luminance on a 60-second period, so long sessions never feel static.
/// In light mode the breath inverts — a whisper of shadow instead of light.
struct BreathingVoid: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breath = 0.09 + 0.01 * sin(t * 2 * .pi / 60)
            RadialGradient(
                colors: [
                    colorScheme == .light
                        ? Color.black.opacity(breath * 0.25)
                        : Color.white.opacity(breath * 0.5),
                    .clear,
                ],
                center: .center,
                startRadius: 0,
                endRadius: 1600
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
