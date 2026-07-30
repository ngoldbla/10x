// NineApp.swift — entry point. Full-bleed void, two screens, no chrome that
// isn't glass. Launches straight to the shelf: zero onboarding.
//
// The model is owned here at the App level (not inside RootView) so that on
// macOS the extra scenes — the Settings scene (⌘,), the History window (⌘Y)
// and the menu-bar Commands — all share the one @Observable AppModel. On
// tvOS/iOS there is a single WindowGroup, so behavior is identical.
import SwiftUI
import CouchKit
import AppIntents

@main
struct NineApp: App {
    /// Nine's words, installed before anything can ask for one (PRD-20).
    ///
    /// **A stored property declared above `model`, not a line in `init` — the
    /// position is the mechanism.** Swift applies a struct's stored-property
    /// defaults in declaration order *before* the `init` body runs, so this
    /// resolves first and `AppModel()` second. That ordering is the point:
    /// `@State private var model = AppModel()` below is itself a
    /// stored-property default, so an install written into `init` would already
    /// be one `AppModel` change away from being too late. `AppModel` builds no
    /// phrases today; putting the install here makes "early enough" a fact
    /// about the language rather than a fact about `AppModel`. (Measured, not
    /// assumed: a struct with two `Probe` stored properties and a printing
    /// `init` prints `first-stored`, `second-stored`, `init body`.)
    ///
    /// It is also the only install site that exists on iOS and tvOS — the
    /// `init` below is inside `#if os(macOS)`, so on two of the three platforms
    /// `NineApp` has no `init` at all and there is nowhere for the call to be.
    /// `NineWidgets.appex` never runs `NineApp` and makes its own call from
    /// `NineWidgetBundle`: two `@main`s, two processes, one install each
    /// (controller ruling, 2026-07-26). `Phrasebook.install` is a
    /// `precondition` that survives `-O`, so a second call in one process traps
    /// in the shipping app rather than silently overwriting.
    ///
    /// Typed `Void` because the value is never read — the initializer's side
    /// effect is the whole payload.
    private let phrasebook: Void = Strings.install()

    @State private var model = AppModel()

    /// The menu-bar extra's `@AppStorage` key (PRD-33). Named once so the App and
    /// the View menu cannot come to disagree about which flag they are toggling —
    /// a typo here is silent, because `@AppStorage` simply starts a new key.
    static let menuBarExtraKey = "nine.mac.menuBarExtra"

    #if os(macOS)
    init() {
        // One board, one window — tabbing a sudoku makes no sense, and
        // dropping it clears the stock Show Tab Bar rows from the View menu.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    /// Whether the menu-bar extra is inserted (PRD-33).
    ///
    /// **`@State`, seeded from `UserDefaults` — and the spelling is a hang fix,
    /// not a preference.** Two obvious versions of this line wedge the app:
    ///
    /// | `isInserted:` | result |
    /// |---|---|
    /// | `Binding` reading `model.prefs.macMenuBarExtra` | **103% CPU, unresponsive** |
    /// | `@AppStorage(…)` | **99% CPU, unresponsive** |
    /// | `.constant(true)` / `.constant(false)` | quiet, 0.4% |
    /// | `@State` | quiet, 0.7% |
    ///
    /// The spin is `AppDelegate.scenesDidChange` → `makeMainMenu` →
    /// `AppKitMainMenuItem.updateMainMenu` → `MainMenuItemHost.requestUpdate` →
    /// `scenesDidChange`, forever: a `MenuBarExtra` makes the main menu part of the
    /// scene update, and a source that republishes during that update — whether
    /// `@Observable` state or `UserDefaults` change notifications — closes the
    /// loop. `MenuBarExtra` itself is innocent, which the two `.constant` rows
    /// prove.
    ///
    /// **Found by driving the Mac, not by building it.** Three platform builds and
    /// 615 tests were green; the app launched, opened a board from the menu bar,
    /// and then stopped answering AppleEvents. Nothing else in the branch could
    /// have caught it — which is the whole argument of EXECUTING-A-PRD §5.
    ///
    /// Persisting outside `NinePrefs` is what §2 asks for anyway: new state in its
    /// own key, never a new field on `nine.prefs`, which ships in every released
    /// build. Plain `UserDefaults` rather than `CouchStored` because the value is
    /// read before any view exists and must never sync — a menu bar is a property
    /// of one Mac.
    @State private var menuBarExtraShown =
        UserDefaults.standard.bool(forKey: NineApp.menuBarExtraKey)
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
        .commands { NineCommands(model: model, menuBarExtraShown: $menuBarExtraShown) }

        // ⌘, — the standard Settings scene, iOS-parity rows minus touch-only.
        Settings {
            MacSettingsView(model: model)
        }

        // ⌘Y — the History window (points, best times, recent solves, Game
        // Center), opened from the Game menu.
        Window(Strings.string("history.title"), id: "history") {
            MacHistoryWindow(model: model)
        }
        .defaultSize(width: 440, height: 660)

        // ⌥⌘A — the daily archive (PRD-33). **A window, not a sheet**, which is
        // the sentence PRD-26 and PRD-31 both deferred to this PRD: "the Mac's
        // answer to a second pane is a window". A calendar is the case that proves
        // it — you consult it *while* looking at a board, and a sheet would cover
        // the thing you are deciding about.
        //
        // `ArchiveSheetContent` needed no change to appear here; it was simply
        // fenced `#if os(iOS)` and did not compile for the Mac at all.
        Window(Strings.string("archive.title"), id: "archive") {
            MacArchiveWindow(model: model)
        }
        .defaultSize(width: 420, height: 520)

        // ⇧⌘E — the Technique School (PRD-25). It has compiled for macOS since it
        // shipped and nothing has ever presented it.
        Window(Strings.string("school.title"), id: "school") {
            MacSchoolWindow(model: model)
        }
        .defaultSize(width: 520, height: 680)

        // The menu-bar extra (PRD-33). Behind a pref that is off by default — see
        // `NinePrefs.macMenuBarExtra`. `.window` rather than `.menu` because the
        // content is a drawn board rather than a list of rows.
        MenuBarExtra(isInserted: $menuBarExtraShown) {
            MacMenuBarBoard(model: model)
        } label: {
            // The wordmark's own glyph, not a sudoku grid: the menu bar is a row of
            // other apps' marks and this has to read as Nine at 16pt.
            Image(systemName: "square.grid.3x3.fill")
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            RootView(model: model)
        }
        #endif
    }
}

struct RootView: View {
    let model: AppModel
    // Scene phase drives the widget merge on iOS and the cloud fetch on every
    // platform (PRD-8): coming forward, pull remote boards.
    @Environment(\.scenePhase) private var scenePhase
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
        // Hand the model to App Intents (PRD-33). `@Dependency` in an intent
        // resolves through this, and a `@MainActor` class is implicitly
        // `Sendable`, which is what `AppDependencyManager` requires.
        //
        // **Here rather than in `NineApp.init`**, which is the obvious place and
        // is unsafe: `model` is `@State`, SwiftUI may build the `App` struct more
        // than once, and its storage is attached after `init` — so an `init`
        // registration can hand the intents a model instance the UI never shows.
        // The failure would be silent and awful: "Start today's board" mutating a
        // model nobody is looking at. By `onAppear` the live instance exists.
        // Registration is last-writer-wins and idempotent in practice.
        .onAppear { AppDependencyManager.shared.add(dependency: model) }
        #if os(macOS)
        // Drive the NSWindow (desk mode size/level, frame autosave) and host
        // the keyboard-gestured tutorial from Help ▸ How to Play.
        .background(MacWindowConfigurator(model: model))
        .overlay {
            if model.macShowTutorial {
                TutorialView(accent: accent, grammar: .keyboard) {
                    model.macShowTutorial = false
                }
                // PRD-22. `.environment(\.nineTheme,…)` above writes into the
                // *modified* view's subtree, and an overlay's content is a
                // sibling of that view rather than a descendant — so the Mac
                // tutorial and the BoardView inside it were reading
                // `NineThemeKey.defaultValue`, i.e. `.auto`. Symptom: on Camel
                // the app is light-pinned, `.auto` resolves to Paper, and the
                // tutorial drew a Paper board inside a Camel app. iOS and tvOS
                // were never affected — their hosts are themselves descendants
                // of the write. Re-applied here rather than reordered, because
                // the reorder also moves `preferredColorScheme` off the window.
                .environment(\.nineTheme, model.prefs.theme)
                .transition(.opacity)
            }
        }
        .animation(.couchFast, value: model.macShowTutorial)
        .onAppear { GameCenter.shared.authenticate() }
        // Game ▸ Technique School and Help ▸ Technique School (PRD-33). Presented
        // where the tutorial is, so the two coach surfaces are siblings; the
        // `.environment` re-application is the same overlay-is-a-sibling fix the
        // comment above records.
        .onChange(of: model.macShowSchool) { _, wants in
            if wants { openSchoolWindow() }
        }
        #endif
        // `nine://` is registered on the **shared** Info.plist (project.yml), so
        // macOS has advertised the scheme since PRD-3 and, until PRD-33, silently
        // dropped every open of it — the handler was inside `#if os(iOS)`. That
        // also blocked App Shortcuts' `OpenIntent`-shaped routing on the Mac. The
        // fence is gone; the body is unchanged.
        //
        // Widget taps land on today's daily. openToday() is already safe
        // mid-composition (compose() guards on `composing`).
        .onOpenURL { url in
            guard url.scheme == "nine" else { return }
            let target = url.host() ?? url.pathComponents.dropFirst().first
            if target == "daily" {
                model.openToday()
            }
        }
        #if os(iOS)
        .onAppear { GameCenter.shared.authenticate() }
        // Coming forward: merge any widget moves first (PRD-3 §4). Going
        // back: belt-and-braces publish so the Home Screen is fresh the
        // moment the app leaves it.
        //
        // The clock hold (Task 4) is released before `ingestSharedDailyBoard`
        // runs, not after: releasing first means the ingest's own
        // `startClockIfUnheld` (and any board swap inside it) sees the true
        // "are we actually being looked at" state rather than a one-tick-stale
        // one. `.inactive` holds too, not just `.background` — the app is
        // covered by the app switcher / an incoming call / Control Center
        // there just as surely, and iOS can go `.active` → `.inactive` →
        // `.background` or `.active` → `.inactive` → `.active` (a cancelled
        // switch), so both non-active phases must hold and only `.active`
        // may release.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.releaseClock(.scene)
                model.ingestSharedDailyBoard()
                // The watch coming back into range is not an event the phone
                // can hear, so today's daily is re-offered on every activation.
                model.publishDailyToWatch()
                model.syncOnForeground()
            case .inactive, .background:
                model.holdClock(.scene)
                // `foreground: false` is the "and leave" half of PRD-30's
                // start-and-leave: this is the only publish site in the app that
                // is not a move, a solve or a navigation, and it is the one
                // transition that may start a Live Activity.
                //
                // `.background` only, matching the existing publish: `.inactive`
                // is the app switcher and an incoming call, and a phone that
                // returns from either never left.
                if phase == .background {
                    WidgetBridge.publish(from: model, foreground: false)
                }
            default:
                break
            }
        }
        #endif
        #if os(tvOS) || os(macOS)
        // No widgets here, but the cloud library still pulls on foreground.
        // Same clock-hold pattern as the iOS block above: on macOS, scenePhase
        // tracks frontmost-ness, which *is* "looking at the board" there —
        // Space-switching away or losing focus to another window holds the
        // clock exactly as backgrounding does on iOS/tvOS.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.releaseClock(.scene)
                model.syncOnForeground()
            case .inactive, .background:
                model.holdClock(.scene)
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

    #if os(macOS)
    /// `openWindow` is an environment value and cannot be read from `Commands`
    /// content that has no view of its own, so the two School menu rows set a flag
    /// on the model — the `macShowTutorial`/`macShowBoards` pattern — and this
    /// turns the flag into a window and resets it.
    @Environment(\.openWindow) private var openWindow

    private func openSchoolWindow() {
        openWindow(id: "school")
        model.macShowSchool = false
    }
    #endif

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
