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
        // The player's accent, planted as the environment tint (PRD-35).
        //
        // Nine has offered ten accents since 1.0 and `.tint` appeared exactly
        // once in the whole tree — on the watch — so every system control in the
        // app (toggles, steppers, pickers, the sheet's own affordances) was
        // rendering in the stock system blue while the board beside it was
        // Orchid. Planting it here is also what makes `GlassChip`'s new `.hero`
        // emphasis resolve to *this* app's accent without CouchKit having to
        // know Nine's palette.
        //
        // Resolved for the theme's leaning, not the system's, for the reason
        // `SharedPalette.resolve` exists: Camel is a light theme on a phone in
        // dark mode, and the vivid accent on Camel is PRD-22's 3.36:1.
        .tint(accent)
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
        // PRD-28 §7. A board somebody sent arrives here, is refused or accepted
        // by `ParlorInvite(properties:)` alone, and is *offered* rather than
        // opened: yanking a player off the board in front of them because a
        // friend's invitation landed is the least calm thing this app could do.
        .onAppear {
            GameCenter.shared.onInvite = { [model] invite in model.parlor.offer(invite) }
        }
        // PRD-28 §2. Every SharePlay session for the life of the process. The
        // invite is the activity's whole payload, so the board is composed
        // locally from eight bytes and a tier and no grid crosses the wire.
        .task {
            for await session in NineParlorActivity.sessions() {
                let invite = session.activity.invite
                model.openParlorInvite(invite)
                model.parlor.join(
                    invite: invite,
                    fillable: model.parlorFillable,
                    over: GroupParlorTransport(session: session)
                )
            }
        }
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

/// Where the light comes from.
///
/// **One key light, named once, shared by the ground and by the breath.**
/// `.glassEffect` is a lens, and a lens with nothing behind it draws nothing:
/// over `VoidBackground`'s old single flat fill of pure black, every pane of
/// glass in the app collapsed to a tint (shelf cards 1.07:1 against their page,
/// the board card 1.03:1, the rose petals 1.026:1 — see `ThemeChoice.dark`). A
/// ground that is uniform is the same problem one level up: even lifted off
/// black, a *flat* ground gives the material the same value everywhere, so the
/// glass still has no gradient to bend and no edge to catch.
///
/// So the ground is lit, from an off-centre **key** near the top-trailing
/// corner. Off-centre because a centred light is the one arrangement that
/// produces a symmetric — and therefore invisible — falloff on a rectangular
/// screen, and near the top because that is where every physical light a person
/// has ever looked at a screen under happens to be.
///
/// Round 2 added a **fill** and a **mottle** beneath it. That is not a second
/// sun — a room has one light and several bounces — and the reason is in the
/// round-2 section below: a single source produces a plane with one slope, and
/// a lens displacing a single slope produces the same slope back. See
/// `counterAnchor`.
private enum GroundLight {
    /// Just inside the top-trailing corner. Not *at* the corner: a source
    /// exactly on the corner puts its brightest pixel where nothing is drawn.
    static let anchor = UnitPoint(x: 0.88, y: 0.08)

    /// The falloff radius for a surface of this size. Slightly under the
    /// diagonal, so the opposite corner is genuinely unlit rather than merely
    /// dimmer — that difference is the whole gradient.
    static func radius(for size: CGSize) -> CGFloat {
        max(max(size.width, size.height) * 0.92, 1)
    }

    /// The static peak, before the breath is added. Light grounds get less
    /// because white on paper is an operation with nowhere to go — their plane
    /// is shaped by the diagonal's dark end instead.
    static func peak(isLight: Bool) -> Double { isLight ? 0.06 : 0.09 }

    // MARK: Round 2 — a second source, a hue split, and a vignette
    //
    // **One light is not enough to refract.** A single source plus a diagonal
    // gives the plane a monotonic ramp: brightest at one corner, darkest at the
    // opposite one, and *linear in between*. A lens bends a gradient by
    // displacing it, and displacing a linear ramp yields another linear ramp —
    // which is exactly why fourteen critics looked at correctly-called
    // `.glassEffect` and wrote "the glass refracts nothing". The eye reads
    // refraction from **inflections**: places where the field's slope changes,
    // so the displaced version is visibly *not* the background behind it.
    //
    // Three additions, none of which is readable as content:
    //
    //   • a **counter-light** at the opposite corner — larger, fainter, and
    //     *cool* where the primary is warm, so the field has two slopes meeting
    //     in the middle and glass edges pick up a hue shift as well as a
    //     luminance one. A hue shift is the single most legible refraction cue
    //     there is; it is why a real bevel shows colour at its edge.
    //   • a **mottle**: one more low, wide, off-axis source that keeps the two
    //     slopes from meeting in a straight line. This is the "large-scale
    //     noise" of the brief, done deterministically — real noise would mean a
    //     `ShaderLibrary` pass on the one layer in the app that should cost
    //     nothing, and three radials already break the plane's symmetry, which
    //     is the only property the noise was wanted for.
    //   • a **vignette**, drawn *under* all three so the corners fall away and
    //     the sources still read. It is also the luminance budget: the two new
    //     sources add roughly what the vignette takes back, which is what keeps
    //     the composited board where `Tests/ContrastBaselines` measured it.
    //
    // The two colours are barely colours. `warm` is 1.000/0.972/0.925 and
    // `cool` is 0.804/0.870/1.000 — at the alphas below they move the ground by
    // one or two levels per channel. That is the correct amount: enough for the
    // material's edge sampling to find, far too little to see as a tint.

    /// The counter-light, diagonally opposite `anchor` and near the bottom
    /// leading corner. Not *at* it, for the same reason `anchor` is not at its
    /// own corner.
    static let counterAnchor = UnitPoint(x: 0.10, y: 0.90)

    /// Wider than the primary — 1.35× the long edge rather than 0.92× — because
    /// a second source that falls off as fast as the first reads as a second
    /// lamp. A bounce fills the room instead.
    static func counterRadius(for size: CGSize) -> CGFloat {
        max(max(size.width, size.height) * 1.35, 1)
    }

    /// Lower than the primary at both leanings: this is the fill, not the key.
    static func counterPeak(isLight: Bool) -> Double { isLight ? 0.05 : 0.055 }

    /// The third inflection, mid-plane and off both axes.
    static let mottleAnchor = UnitPoint(x: 0.30, y: 0.46)

    static func mottleRadius(for size: CGSize) -> CGFloat {
        max(max(size.width, size.height) * 0.55, 1)
    }

    static func mottlePeak(isLight: Bool) -> Double { isLight ? 0.022 : 0.026 }

    /// How dark the corners fall. Dark grounds can afford four times what paper
    /// can: on `#0C0C0F` a 13% black corner is still above zero, while on paper
    /// anything past ~5% starts reading as a photographic effect.
    static func vignette(isLight: Bool) -> Double { isLight ? 0.05 : 0.13 }

    /// The vignette's clear radius. Under the long edge, so the corners sit
    /// past the final stop and hold its colour — a vignette that only reaches
    /// full strength *outside* the frame is a vignette nobody can see.
    static func vignetteRadius(for size: CGSize) -> CGFloat {
        max(max(size.width, size.height) * 0.78, 1)
    }

    /// The key light's colour. Every light a person reads under is warm; a pure
    /// white key is the tell of a UI that was specified rather than lit.
    static let warm = Color(red: 1.000, green: 0.972, blue: 0.925)

    /// The fill's colour on a dark ground: sky, which is what a cool bounce is.
    static let cool = Color(red: 0.804, green: 0.870, blue: 1.000)

    /// The fill's colour on a light ground. On paper an *added* light does
    /// nothing — the same argument `BreathingVoid` makes for inverting its
    /// breath — so the counter-source becomes a cool shade instead of a cool
    /// glow, and the hue split survives the inversion.
    static let coolShade = Color(red: 0.498, green: 0.549, blue: 0.659)

    /// The mottle's colour on a light ground: the warm counterpart of
    /// `coolShade`, so the mid-plane inflection leans the opposite way from the
    /// corner fill on paper exactly as it does on Void.
    static let warmShade = Color(red: 0.702, green: 0.643, blue: 0.565)
}

/// The resting background: each theme's backdrop, **lit**.
///
/// Six layers, and every one of them is a contrast or a refraction fix rather
/// than a decoration:
///
/// 1. The theme's ground (Void is now #0C0C0F rather than #000000 — the lift
///    that gives the material something to refract at all).
/// 2. A diagonal `LinearGradient`: +5.5% white at `.topLeading`, −4% black at
///    `.bottomTrailing`. On a dark theme that is roughly a 2× luminance range
///    across the plane, which is what makes a card's own edge visible against
///    the page *wherever* on the page it happens to sit.
/// 3. A **vignette**, under the sources rather than over them, so the corners
///    fall away without eating the key light that sits near one of them.
/// 4. The off-centre `RadialGradient` key light, now warm.
/// 5. A wider, fainter, **cool counter-light** at the opposite corner.
/// 6. A mid-plane **mottle** so the two slopes do not meet along a straight
///    line.
///
/// Layers 3–6 are round 2's answer to the one blocker ten of fourteen critics
/// wrote independently — "the glass refracts nothing". `GroundLight`'s comment
/// carries the argument: a lens displaces the field behind it, so a field with
/// a single slope refracts to a field with a single slope and the material
/// disappears. What survives displacement is an *inflection*, and layers 5 and
/// 6 exist to put two of them on the plane. Nothing here is visible as content;
/// the whole stack moves the ground by a handful of levels.
///
/// Every gradient passes through explicit zero-alpha stops of its own colour
/// rather than through `.clear`. `Color.clear` is black at zero alpha, and
/// SwiftUI interpolates gradient stops in unpremultiplied space, so a
/// `white → .clear` ramp travels through a grey haze on the way down. At these
/// opacities that is a one-or-two-level muddiness, which is exactly the scale
/// the whole change is operating at.
struct VoidBackground: View {
    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tones = theme.tones(for: colorScheme)
        let isLight = tones.isLight
        // On paper an added light is an operation with nowhere to go, so the
        // fill and the mottle invert to shades — the same inversion
        // `BreathingVoid` makes, for the same reason.
        let fill = isLight ? GroundLight.coolShade : GroundLight.cool
        let mottle = isLight ? GroundLight.warmShade : GroundLight.warm
        GeometryReader { geo in
            ZStack {
                tones.background
                LinearGradient(
                    stops: [
                        // On a light ground the bright end has almost nowhere to
                        // go — paper is already 240/255 — so a light theme's
                        // gradient is carried by its dark end instead, and the
                        // two stops are deliberately asymmetric.
                        .init(color: .white.opacity(isLight ? 0.06 : 0.055), location: 0),
                        .init(color: .white.opacity(0), location: 0.45),
                        .init(color: .black.opacity(0), location: 0.55),
                        .init(color: .black.opacity(isLight ? 0.07 : 0.040), location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 3 — the vignette. Deliberately below the three sources: a
                // vignette on top would darken the key light's own corner,
                // which is the one place the plane is supposed to be brightest.
                RadialGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: 0.42),
                        .init(
                            color: .black.opacity(GroundLight.vignette(isLight: isLight)),
                            location: 1),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: GroundLight.vignetteRadius(for: geo.size)
                )
                // 4 — the key.
                RadialGradient(
                    stops: [
                        .init(
                            color: GroundLight.warm
                                .opacity(GroundLight.peak(isLight: isLight)),
                            location: 0),
                        .init(color: GroundLight.warm.opacity(0), location: 1),
                    ],
                    center: GroundLight.anchor,
                    startRadius: 0,
                    endRadius: GroundLight.radius(for: geo.size)
                )
                // 5 — the fill, opposite and cool.
                RadialGradient(
                    stops: [
                        .init(
                            color: fill.opacity(GroundLight.counterPeak(isLight: isLight)),
                            location: 0),
                        .init(color: fill.opacity(0), location: 1),
                    ],
                    center: GroundLight.counterAnchor,
                    startRadius: 0,
                    endRadius: GroundLight.counterRadius(for: geo.size)
                )
                // 6 — the mottle.
                RadialGradient(
                    stops: [
                        .init(
                            color: mottle.opacity(GroundLight.mottlePeak(isLight: isLight)),
                            location: 0),
                        .init(color: mottle.opacity(0), location: 1),
                    ],
                    center: GroundLight.mottleAnchor,
                    startRadius: 0,
                    endRadius: GroundLight.mottleRadius(for: geo.size)
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The almost-subliminal background luminance breath (PRD §6): a 60-second
/// period, so long sessions never feel static.
///
/// **It used to be unmeasurable.** The shipped version peaked at
/// `white × 0.045` and spread it over a fixed 1600pt radius from screen centre,
/// which after falloff put **3/255** on the plane — a breath nobody could see
/// on any display, animating every half-second for the life of the session.
///
/// Two changes, and the second is the design one. Its amplitude is now large
/// enough to read (0 → 0.045 *on top of* the ground's static 0.09, so the
/// source swings between 9% and 13.5%), and it modulates
/// `GroundLight` — the same anchor, the same falloff — instead of being a second
/// light in the middle of the screen. A room does not have two suns. What
/// breathes is the one light the ground already has.
struct BreathingVoid: View {
    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = theme.tones(for: colorScheme).isLight
        // The breath modulates the *key*, so it has to be the key's colour. It
        // was pure white, which meant the one moving light on the plane pulsed
        // very slightly cooler than the light it was modulating — a hue
        // wobble at 60-second period, which is the least useful animation in
        // the app. On paper it stays a shadow, per the inversion below.
        let breathColor = isLight ? Color.black : GroundLight.warm
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 0.5)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // 0…1, one cycle a minute, starting at the trough so a launch
                // screenshot is never caught at an untypical peak.
                let breath = 0.5 - 0.5 * cos(t * 2 * .pi / 60)
                // On light-leaning themes the breath inverts: a whisper of
                // shadow rather than of light, because adding white to paper is
                // an operation with nowhere to go.
                let tip = isLight ? 0.030 : 0.045
                RadialGradient(
                    stops: [
                        .init(
                            color: breathColor.opacity(breath * tip),
                            location: 0),
                        .init(
                            color: breathColor.opacity(0),
                            location: 1),
                    ],
                    center: GroundLight.anchor,
                    startRadius: 0,
                    endRadius: GroundLight.radius(for: geo.size)
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
