// NineApp.swift — entry point. Full-bleed void, two screens, no chrome that
// isn't glass. Launches straight to the shelf: zero onboarding.
//
// The model is owned here at the App level (not inside RootView) so that on
// macOS the extra scenes — the Settings scene (⌘,), the History window (⌘Y)
// and the menu-bar Commands — all share the one @Observable AppModel. On
// tvOS/iOS there is a single WindowGroup, so behavior is identical.
import SwiftUI
import CouchKit

@main
struct NineApp: App {
    @State private var model = AppModel()

    #if os(macOS)
    init() {
        // One board, one window — tabbing a sudoku makes no sense, and
        // dropping it clears the stock Show Tab Bar rows from the View menu.
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    #endif

    var body: some Scene {
        #if os(macOS)
        // 720×820 default, 480×560 minimum (PRD-4 §2.1); desk mode overrides
        // the constraints live via the window configurator.
        WindowGroup {
            RootView(model: model)
        }
        .defaultSize(width: 720, height: 820)
        .windowResizability(.contentMinSize)
        .commands { NineCommands(model: model) }

        // ⌘, — the standard Settings scene, iOS-parity rows minus touch-only.
        Settings {
            MacSettingsView(model: model)
        }

        // ⌘Y — the History window (points, best times, recent solves, Game
        // Center), opened from the Game menu.
        Window("History", id: "history") {
            MacHistoryWindow(model: model)
        }
        .defaultSize(width: 440, height: 660)
        #else
        WindowGroup {
            RootView(model: model)
        }
        #endif
    }
}

struct RootView: View {
    let model: AppModel
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif
    @Environment(\.colorScheme) private var colorScheme

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
        // Auto follows the device; every theme pins its own leaning so
        // materials and secondary text follow — both platforms.
        .preferredColorScheme(model.prefs.theme.colorScheme)
        .environment(\.nineTheme, model.prefs.theme)
        #if os(macOS)
        // Drive the NSWindow (desk mode size/level, frame autosave) and host
        // the keyboard-gestured tutorial from Help ▸ How to Play.
        .background(MacWindowConfigurator(model: model))
        .overlay {
            if model.macShowTutorial {
                TutorialView(accent: accent, grammar: .keyboard) {
                    model.macShowTutorial = false
                }
                .transition(.opacity)
            }
        }
        .animation(.couchFast, value: model.macShowTutorial)
        .onAppear { GameCenter.shared.authenticate() }
        #endif
        #if os(iOS)
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
        // tvOS deliberately does NOT authenticate at launch: while signed out,
        // GameKit re-presents its full-screen welcome sheet on every launch —
        // an app-opening takeover on the calmest screen in the house (observed
        // in validation). The History sheet authenticates on open instead;
        // solve reporting stays fire-and-forget and simply no-ops until then.
    }

    /// The accent resolved for the theme's leaning (themes pin the scheme).
    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    // One model, three grammars: the TV screens speak remote (RemoteKit), the
    // touch screens speak fingers, the Mac screens speak keyboard + pointer.
    // Everything below them — engine, persistence, board and rose rendering —
    // is shared.
    @ViewBuilder
    private var homeScreen: some View {
        #if os(tvOS)
        HomeView(model: model)
        #elseif os(macOS)
        MacHomeView(model: model)
        #else
        TouchHomeView(model: model)
        #endif
    }

    @ViewBuilder
    private var gameScreen: some View {
        #if os(tvOS)
        GameScreen(model: model)
        #elseif os(macOS)
        MacGameScreen(model: model)
        #else
        TouchGameScreen(model: model)
        #endif
    }
}

/// The player's theme, planted once at the root so leaf views (board,
/// backgrounds) pick it up without prop-threading.
private struct NineThemeKey: EnvironmentKey {
    static let defaultValue: ThemeChoice = .auto
}

extension EnvironmentValues {
    var nineTheme: ThemeChoice {
        get { self[NineThemeKey.self] }
        set { self[NineThemeKey.self] = newValue }
    }
}

/// The resting background: each theme's flat backdrop. Void (true black)
/// remains the dark default; Paper, Camel, Blueprint and Forest tint the
/// whole plane so glass and shadows still have something to catch.
struct VoidBackground: View {
    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        theme.tones(for: colorScheme).background
            .ignoresSafeArea()
    }
}

/// The almost-subliminal background luminance breath (PRD §6): 8%–10% peak
/// luminance on a 60-second period, so long sessions never feel static.
/// On light-leaning themes the breath inverts — a whisper of shadow
/// instead of light.
struct BreathingVoid: View {
    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breath = 0.09 + 0.01 * sin(t * 2 * .pi / 60)
            RadialGradient(
                colors: [
                    theme.tones(for: colorScheme).isLight
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
