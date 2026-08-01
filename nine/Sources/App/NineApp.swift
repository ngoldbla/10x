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
    ///
    /// **0.09 → 0.20 on dark, and the number is not the interesting part** —
    /// see the round-4 section below. Raising a peak on a linear falloff raises
    /// the *whole* plane, board included, which is why round 3's version could
    /// not go past 0.09 without turning Void grey. `keyStops` is what makes 0.20
    /// affordable: the light is now concentrated near its own anchor and the
    /// screen's centre sits *lower* than it did at 0.09.
    static func peak(isLight: Bool) -> Double { isLight ? 0.10 : 0.20 }

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
    ///
    /// **The two leanings converged at round 4 and the parameter stays.** They
    /// were 0.05/0.055, and raising the plane's amplitude pushed both to the
    /// same 0.13 — which is a coincidence of two different arguments, not one
    /// argument. On Void this is a cool *glow* and its ceiling is where the
    /// bottom-leading corner stops being dark; on paper it is a cool *shade*
    /// (`coolShade`, not `cool`) and its ceiling is where the page stops being
    /// paper. Collapsing the signature would merge two ceilings that will move
    /// apart again the moment either ground does.
    static func counterPeak(isLight: Bool) -> Double { isLight ? 0.13 : 0.13 }

    /// The third inflection, mid-plane and off both axes.
    static let mottleAnchor = UnitPoint(x: 0.30, y: 0.46)

    static func mottleRadius(for size: CGSize) -> CGFloat {
        max(max(size.width, size.height) * 0.55, 1)
    }

    static func mottlePeak(isLight: Bool) -> Double { isLight ? 0.055 : 0.075 }

    /// How dark the corners fall — and, since round 4, **the budget that pays
    /// for the sources above**. The vignette is the only layer that can take
    /// luminance back off the plane, so tripling the sources without tripling
    /// this would simply have made the app grey.
    ///
    /// Dark grounds can still afford three times what paper can, for the
    /// original reason: on `#0C0C0F` a 30% black corner is a fall to ~9/255 and
    /// is still above zero, while on paper anything past ~12% starts reading as
    /// a photographic effect rather than as a lit room.
    static func vignette(isLight: Bool) -> Double { isLight ? 0.10 : 0.30 }

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

    // MARK: Round 4 — amplitude, shaped falloff, and something to blur
    //
    // **The plane was right and far too quiet to matter.** Round 3's ground is
    // three correctly-placed radials with a vignette under them, and measured
    // off the shipped pixels it moves Void by about **14 levels across an
    // entire screen** — brightest ~34, darkest ~20. A pane of glass displacing
    // a field that flat displaces nothing you can see, so 78 of 301 panel
    // findings said "nothing refracts / flat opaque fill" *about an app that
    // calls `couchGlass` at 20 files and 18 sites in `TouchUI` alone*. The glass
    // was never the problem. There was nothing behind it.
    //
    // Three changes, and only the first is a number:
    //
    //   1. **Amplitude ×2–3.** Key 0.09→0.20, fill 0.055→0.13, mottle
    //      0.026→0.075, vignette 0.13→0.30.
    //
    //      Solved on a 1024×768 plane, layer by layer, at the two extreme
    //      points — the key's own anchor and the opposite corner:
    //
    //        | Void          | before | after |
    //        |---------------|--------|-------|
    //        | key anchor    |     35 |    60 |
    //        | far corner    |     19 |    14 |
    //        | **range**     | **16** |**46** |
    //
    //      "Roughly 14/255 of modulation across an entire screen" is what the
    //      brief measured off the shipped build, and the middle column is that
    //      number reproduced from the constants. The right-hand column is what
    //      a pane of glass now has to work with.
    //
    //   2. **Shaped falloff, which is what makes (1) affordable.** A SwiftUI
    //      `RadialGradient` with two stops is *linear in the radius*, so half of
    //      a source's peak is still sitting on the middle of the screen — the
    //      board's own ground. Raising the peak on a linear falloff raises the
    //      board with it, and that is the wall round 3 hit. `keyStops` and its
    //      siblings put a knee in the ramp (0.44 of peak at 28% of the radius,
    //      0.12 at 58%) so the light collapses toward its anchor. Measured at
    //      the screen's centre the new key contributes **less** than the old one
    //      did — **0.033 against 0.042** on a 4:3 plane, 0.042 against 0.046 on
    //      a 390×844 phone — while its own corner is nearly twice as bright.
    //      Range up, centre flat or lower: exactly the trade a lens wants, and
    //      the reason the board's ground does not move with the page's.
    //
    //   3. **Something for the blur to erase** — `GroundGrain`. Points 1 and 2
    //      give the field slope and inflection, which is what *refraction*
    //      (displacement) reads from. They give **blur** nothing: a Gaussian of
    //      a smooth ramp is the same ramp, so the blurred region inside a pane
    //      is pixel-identical to the ground beside it. Blur is only visible
    //      where there is detail *finer than its radius*, so the ground now
    //      carries a deterministic speckle at ~1–3pt against a glass blur an
    //      order of magnitude wider. Outside the pane it is texture at the edge
    //      of visibility; inside it, it is gone. That difference is the pane.
    //
    // None of it is legible as content, which is the standing constraint: the
    // caustics move the plane by two or three levels and the speckle by five at
    // its brightest, on features too small to resolve as shapes.

    /// The key's falloff, with a knee. See point 2 above — the reason the peak
    /// could triple without the board's ground moving.
    ///
    /// Stops rather than a `startRadius` trick because `startRadius` produces a
    /// *plateau* (a visible disc of flat colour) and this wants a curve. The
    /// zero stop is the source's own colour at zero alpha, never `.clear`, for
    /// the unpremultiplied-interpolation reason `VoidBackground` records.
    static func keyStops(_ color: Color, peak: Double) -> Gradient {
        Gradient(stops: [
            .init(color: color.opacity(peak), location: 0),
            .init(color: color.opacity(peak * 0.44), location: 0.28),
            .init(color: color.opacity(peak * 0.12), location: 0.58),
            .init(color: color.opacity(0), location: 1),
        ])
    }

    /// The fill's falloff. A gentler knee than the key's: this is a bounce, and
    /// a bounce that collapses as fast as the source it bounced off reads as a
    /// second lamp — the note on `counterRadius`, restated in the ramp.
    static func fillStops(_ color: Color, peak: Double) -> Gradient {
        Gradient(stops: [
            .init(color: color.opacity(peak), location: 0),
            .init(color: color.opacity(peak * 0.42), location: 0.30),
            .init(color: color.opacity(peak * 0.11), location: 0.65),
            .init(color: color.opacity(0), location: 1),
        ])
    }

    /// The mottle's falloff — the tightest of the three, because its whole job
    /// is to put a *local* inflection mid-plane and a wide one would simply
    /// raise the middle of the screen.
    static func mottleStops(_ color: Color, peak: Double) -> Gradient {
        Gradient(stops: [
            .init(color: color.opacity(peak), location: 0),
            .init(color: color.opacity(peak * 0.36), location: 0.35),
            .init(color: color.opacity(0), location: 1),
        ])
    }

    // MARK: The grain

    /// One speckle per this many square points. ~23pt apart, which is chosen
    /// against the *glass*, not against the eye: a system blur samples a radius
    /// far wider than this, so every one of these disappears under a pane and
    /// none of them disappears beside it.
    static let grainDensity: Double = 520

    /// A ceiling, so a 4K TV plane does not cost 6,000 draw calls for texture
    /// nobody is close enough to resolve. The `Canvas` renders once per size
    /// change — `BreathingVoid` is a separate view, so the breath does not
    /// re-run it.
    static let grainCap = 1400

    /// Speckle radii. Under `CouchSpecular.width`'s 1pt at the small end and
    /// under 3pt at the large one: the range where a mark is texture rather
    /// than a dot.
    static let grainMin: CGFloat = 0.7
    static let grainMax: CGFloat = 2.6

    /// The speckle's peak alpha, before its own per-mark jitter. Five levels at
    /// its brightest on Void, two on paper — where the speckle also inverts to
    /// shadow, for the reason every other layer here inverts on paper.
    static func grainAlpha(isLight: Bool) -> Double { isLight ? 0.026 : 0.042 }

    /// The mid-frequency layer under the speckle: nine wide, soft blobs that
    /// keep the three named sources from being the only inflections on the
    /// plane. Deliberately few and deliberately huge — this is the scale a lens
    /// *displaces* visibly, where the speckle is the scale a lens *erases*.
    static let causticCount = 9

    static func causticPeak(isLight: Bool) -> Double { isLight ? 0.016 : 0.030 }
}

/// The resting background: each theme's backdrop, **lit**.
///
/// Seven layers, and every one of them is a contrast or a refraction fix rather
/// than a decoration:
///
/// 1. The theme's ground (Void is now #0C0C0F rather than #000000 — the lift
///    that gives the material something to refract at all).
/// 2. A diagonal `LinearGradient`: +10% white at `.topLeading`, −11% black at
///    `.bottomTrailing`. On a dark theme that is roughly a 3× luminance range
///    across the plane, which is what makes a card's own edge visible against
///    the page *wherever* on the page it happens to sit.
/// 3. A **vignette**, under the sources rather than over them, so the corners
///    fall away without eating the key light that sits near one of them.
/// 4. The off-centre `RadialGradient` key light, now warm.
/// 5. A wider, fainter, **cool counter-light** at the opposite corner.
/// 6. A mid-plane **mottle** so the two slopes do not meet along a straight
///    line.
/// 7. `GroundGrain` — caustics and a fine deterministic speckle, the only layer
///    a *blur* can see.
///
/// Layers 3–6 are round 2's answer to the one blocker ten of fourteen critics
/// wrote independently — "the glass refracts nothing". `GroundLight`'s comment
/// carries the argument: a lens displaces the field behind it, so a field with
/// a single slope refracts to a field with a single slope and the material
/// disappears. What survives displacement is an *inflection*, and layers 5 and
/// 6 exist to put two of them on the plane.
///
/// **Round 4 is why that argument was right and did not work.** Round 2's
/// inflections were correct and roughly 14 levels tall, which is under the
/// threshold at which a displacement is a thing anyone can see; and *all* of
/// layers 2–6 are smooth, so the blur half of the material had nothing to act
/// on at any amplitude. So: the sources roughly tripled (paid for by the
/// vignette, and made affordable by the falloff knee in `GroundLight.keyStops`,
/// which drops the *centre* while raising the corner), and layer 7 adds the
/// high-frequency term. Still nothing visible as content — the biggest single
/// mark on the plane is about five levels, on a feature 2pt wide.
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
                        //
                        // Round 4 roughly doubled both ends. The diagonal is the
                        // one layer with no falloff knee available to it — a
                        // linear ramp has nowhere to put a knee — so it is also
                        // the one layer that unavoidably lifts the middle of the
                        // screen, which is why its raise is the smallest here
                        // and the key light's is the largest.
                        //
                        // The dark end is the same on both leanings now. Paper
                        // still has less room at the top (0.085 against 0.10)
                        // and the asymmetry the original note describes is still
                        // there; it is simply carried by the bright end alone,
                        // because a 0.11 black is the point on *either* ground
                        // where the corner stops reading as shade and starts
                        // reading as dirt.
                        .init(color: .white.opacity(isLight ? 0.085 : 0.10), location: 0),
                        .init(color: .white.opacity(0), location: 0.45),
                        .init(color: .black.opacity(0), location: 0.55),
                        .init(color: .black.opacity(0.11), location: 1),
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
                    gradient: GroundLight.keyStops(
                        GroundLight.warm,
                        peak: GroundLight.peak(isLight: isLight)),
                    center: GroundLight.anchor,
                    startRadius: 0,
                    endRadius: GroundLight.radius(for: geo.size)
                )
                // 5 — the fill, opposite and cool.
                RadialGradient(
                    gradient: GroundLight.fillStops(
                        fill,
                        peak: GroundLight.counterPeak(isLight: isLight)),
                    center: GroundLight.counterAnchor,
                    startRadius: 0,
                    endRadius: GroundLight.counterRadius(for: geo.size)
                )
                // 6 — the mottle.
                RadialGradient(
                    gradient: GroundLight.mottleStops(
                        mottle,
                        peak: GroundLight.mottlePeak(isLight: isLight)),
                    center: GroundLight.mottleAnchor,
                    startRadius: 0,
                    endRadius: GroundLight.mottleRadius(for: geo.size)
                )
                // 7 — the caustics and the grain, on top of everything so the
                // texture survives the vignette's own corners. This is the only
                // layer a *blur* can see; layers 2–6 are all smooth enough that
                // a Gaussian returns them unchanged.
                GroundGrain(isLight: isLight, warm: mottle, cool: fill)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// A deterministic 64-bit generator, so the ground is the same ground on every
/// launch and in every screenshot.
///
/// SplitMix64: three multiply-xorshift rounds off a counter. Written out rather
/// than reached for because `SystemRandomNumberGenerator` would re-scatter the
/// speckle on every relaunch — which would make the app's own background
/// unreviewable by a frame-by-frame panel, and would make
/// `Tests/ContrastBaselines` sample a different plane every time it is
/// re-recorded. `&+` and `&*` throughout: the algorithm is *defined* on
/// wrapping arithmetic and a trap here would be a crash in a background view.
private struct GroundNoise {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0…1. The top 53 bits, which is the whole mantissa of a `Double` and the
    /// standard way of doing this without a modulo bias.
    mutating func unit() -> Double { Double(next() >> 11) * 0x1p-53 }
}

/// **The layer that makes the blur visible.**
///
/// Everything else in `VoidBackground` is smooth, and smoothness is invisible
/// to a Gaussian: blur a linear ramp and you get the linear ramp back, so the
/// region behind a pane of glass renders pixel-for-pixel identical to the
/// ground beside it and the pane has no edge. That is the mechanism behind 78
/// separate "nothing refracts" findings — not a missing `.glassEffect`, a
/// missing *high-frequency term*.
///
/// Two scales, because refraction and blur read different ones:
///
/// * **Caustics** — nine blobs at 10–32% of the short edge, alternating warm and
///   cool. Wide enough to survive a blur, so what they give the glass is
///   *displacement*: the field inside the pane is visibly not the field outside
///   it, and it shifts hue at the rim, which is the single most legible
///   refraction cue there is.
/// * **Speckle** — up to 1,400 marks at 0.7–2.6pt. Far finer than any system
///   blur radius, so every one of them is erased under glass and none of them
///   is erased beside it. It is also the fix for the banding a critic counted
///   on the shipped frame ("10 discrete luminance steps between y=20 and
///   y=330"): a dither is what a smooth 8-bit ramp needs, and this is a dither
///   that happens to also be doing the work above.
///
/// Drawn in one `Canvas` rather than as stacked views: ~1,409 fill operations
/// in a single pass that re-runs only when the size or the leaning changes.
/// `BreathingVoid` is a sibling view, so the 60-second breath does not
/// invalidate this.
private struct GroundGrain: View {
    let isLight: Bool
    /// The warm source's colour at this leaning — `GroundLight.warm` on a dark
    /// ground and `warmShade` on paper, resolved by the caller so the two
    /// layers cannot disagree about which way the light goes.
    let warm: Color
    /// The cool one, likewise.
    let cool: Color

    var body: some View {
        Canvas { context, size in
            guard size.width > 1, size.height > 1 else { return }
            // A fixed seed: the same ground every launch. See `GroundNoise`.
            var rng = GroundNoise(seed: 0x4E69_6E65_0004_0000)

            let short = min(size.width, size.height)
            let causticPeak = GroundLight.causticPeak(isLight: isLight)
            for index in 0..<GroundLight.causticCount {
                let centre = CGPoint(
                    x: CGFloat(rng.unit()) * size.width,
                    y: CGFloat(rng.unit()) * size.height)
                let radius = CGFloat(0.10 + 0.22 * rng.unit()) * short
                // Alternating rather than random, so nine blobs cannot land
                // eight-warm by chance and become a tint.
                let tint = index.isMultiple(of: 2) ? warm : cool
                let peak = causticPeak * (0.55 + 0.45 * rng.unit())
                // Through the tint's own zero-alpha stop, never through
                // `.clear` — `VoidBackground`'s recorded trap, and at these
                // opacities the grey haze would be the same size as the blob.
                let blob = Gradient(stops: [
                    .init(color: tint.opacity(peak), location: 0),
                    .init(color: tint.opacity(peak * 0.34), location: 0.45),
                    .init(color: tint.opacity(0), location: 1),
                ])
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: centre.x - radius,
                            y: centre.y - radius,
                            width: radius * 2,
                            height: radius * 2)),
                    with: .radialGradient(
                        blob,
                        center: centre,
                        startRadius: 0,
                        endRadius: radius))
            }

            let area = Double(size.width * size.height)
            let count = min(
                GroundLight.grainCap,
                max(180, Int(area / GroundLight.grainDensity)))
            // On paper an added light is an operation with nowhere to go — the
            // inversion every layer in this file makes — so the speckle is
            // shadow there and the warm key's own colour on a dark ground.
            let speck = isLight ? Color.black : GroundLight.warm
            let alpha = GroundLight.grainAlpha(isLight: isLight)
            let span = GroundLight.grainMax - GroundLight.grainMin
            for _ in 0..<count {
                let x = CGFloat(rng.unit()) * size.width
                let y = CGFloat(rng.unit()) * size.height
                let radius = GroundLight.grainMin + span * CGFloat(rng.unit())
                // Jittered per mark: a field of identically-weighted dots reads
                // as a printed halftone rather than as grain.
                let weight = alpha * (0.3 + 0.7 * rng.unit())
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: x - radius,
                            y: y - radius,
                            width: radius * 2,
                            height: radius * 2)),
                    with: .color(speck.opacity(weight)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// **What the boundary of a bar is allowed to be.**
///
/// Nine surfaces in round 4 were failed for the same mark: a full-width 1pt
/// hairline under a header, "a hard 52→24 luminance cliff in a single row",
/// "the flat-cut blur region guillotines the Nocturne card". A hairline running
/// edge to edge is not the edge of a slab of glass — it is a *rule*, and it is
/// the tell of chrome that was drawn rather than lit.
///
/// The system's own answer is a scroll-edge effect, and the part of it a view
/// can build without private API is this: a **falloff** rather than a
/// terminator. The ground's own colour, full-strength where the bar sits and
/// gone 32pt later, so content passing under the bar dissolves instead of being
/// cut. It composes with CouchKit's `couchGlassBar` — that rung supplies the
/// material and the specular top arc, this supplies the boundary — and with a
/// scroll offset, which is what `strength` is for: an edge that is *always* on
/// is chrome for a state that never happens (the panel's exact complaint about
/// a home screen that does not scroll).
///
/// The stops pass through the ground at zero alpha rather than through
/// `.clear`, for the reason `VoidBackground` records: `Color.clear` is black at
/// zero alpha and SwiftUI interpolates unpremultiplied, so a `ground → .clear`
/// ramp travels through a grey haze — and a grey haze at the bottom of a veil
/// is a soft version of the hairline this exists to delete.
struct ScrollEdgeVeil: View {
    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// Which edge of the scrolling region this veils.
    let edge: VerticalEdge
    /// How deep the falloff runs. 32 is the shallowest depth that still reads
    /// as a fade rather than as a soft line at typical scroll speeds.
    var depth: CGFloat = 32
    /// 0…1, normally driven from how far the content has scrolled under the
    /// bar. At 0 the veil is not there at all.
    var strength: Double = 1

    var body: some View {
        let ground = theme.tones(for: colorScheme).background
        let weight = max(0, min(1, strength))
        LinearGradient(
            stops: [
                .init(color: ground.opacity(0.92 * weight), location: 0),
                .init(color: ground.opacity(0.55 * weight), location: 0.34),
                .init(color: ground.opacity(0.18 * weight), location: 0.68),
                .init(color: ground.opacity(0), location: 1),
            ],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
        .frame(height: depth)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Overlay a `ScrollEdgeVeil` on one edge of this view. The common case:
    /// `content.nineScrollEdge(.top, strength: scrolledUnder ? 1 : 0)`.
    func nineScrollEdge(
        _ edge: VerticalEdge,
        depth: CGFloat = 32,
        strength: Double = 1
    ) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            ScrollEdgeVeil(edge: edge, depth: depth, strength: strength)
        }
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
/// enough to read (0 → 0.075 *on top of* the ground's static 0.20, so the
/// source swings between 20% and 27.5%), and it modulates
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
                //
                // Round 4 raised the tip with the key it modulates (0.045 →
                // 0.075 on dark), and — more importantly — put it on the key's
                // own **shaped** falloff via `GroundLight.keyStops`. It used to
                // be a two-stop linear ramp while the light underneath it was
                // not, which meant the breath was quietly widest exactly where
                // the key was weakest: a source that pulsed the middle of the
                // screen while claiming to modulate a corner. Now the thing
                // that breathes is, in shape as well as in position, the one
                // light the ground already has.
                let tip = isLight ? 0.045 : 0.075
                RadialGradient(
                    gradient: GroundLight.keyStops(breathColor, peak: breath * tip),
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
