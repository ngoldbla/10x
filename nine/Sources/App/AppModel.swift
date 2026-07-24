// AppModel.swift — the one @MainActor view model behind both screens.
// Owns the current game, prefs, streaks and the autosave slot; every value
// persists through CouchStored (debounced JSON under Application Support,
// streaks mirrored to iCloud KVS).
//
// Note: the engine sources compile inside this app target (see project.yml),
// so engine types are used directly — no `import NineEngine`.
import SwiftUI
import Observation
import CouchKit

// MARK: - Persisted value types

/// Accent tints offered in prefs. Vivid, mutually distinct hues; never pure
/// red or green (colorblind-safe rule: errors pair a coral underline with a
/// dot — crimson sits at rose ~345°, far from the coral marker's ~9°).
/// Light-leaning themes get a deepened variant of each hue: the vivid values
/// wash out on high-luminance backgrounds.
enum AccentChoice: String, Codable, Sendable, CaseIterable {
    case glacier, ember, meadow, lilac, crimson, gold, teal, magenta

    var title: String {
        switch self {
        case .glacier: return "Glacier"
        case .ember: return "Ember"
        case .meadow: return "Meadow"
        case .lilac: return "Lilac"
        case .crimson: return "Crimson"
        case .gold: return "Gold"
        case .teal: return "Teal"
        case .magenta: return "Magenta"
        }
    }

    /// The vivid base tint — right on dark themes and in picker swatches.
    var color: Color {
        switch self {
        case .glacier: return Color(red: 0.33, green: 0.68, blue: 0.98)
        case .ember: return Color(red: 1.00, green: 0.56, blue: 0.20)
        case .meadow: return Color(red: 0.36, green: 0.84, blue: 0.48)
        case .lilac: return Color(red: 0.66, green: 0.50, blue: 0.98)
        case .crimson: return Color(red: 0.93, green: 0.29, blue: 0.50)
        case .gold: return Color(red: 0.98, green: 0.75, blue: 0.18)
        case .teal: return Color(red: 0.15, green: 0.80, blue: 0.76)
        case .magenta: return Color(red: 0.88, green: 0.42, blue: 0.90)
        }
    }

    /// The vivid base tint as raw components, for the DualSense light bar
    /// (PRD-5 Phase 3). Kept parallel to `color` rather than extracted from it —
    /// SwiftUI `Color` → RGB round-tripping is unreliable on tvOS.
    var lightBarRGB: (red: Double, green: Double, blue: Double) {
        switch self {
        case .glacier: return (0.33, 0.68, 0.98)
        case .ember: return (1.00, 0.56, 0.20)
        case .meadow: return (0.36, 0.84, 0.48)
        case .lilac: return (0.66, 0.50, 0.98)
        case .crimson: return (0.93, 0.29, 0.50)
        case .gold: return (0.98, 0.75, 0.18)
        case .teal: return (0.15, 0.80, 0.76)
        case .magenta: return (0.88, 0.42, 0.90)
        }
    }

    /// The tint resolved for the surface it sits on.
    func color(isLight: Bool) -> Color {
        guard isLight else { return color }
        switch self {
        case .glacier: return Color(red: 0.10, green: 0.45, blue: 0.85)
        case .ember: return Color(red: 0.82, green: 0.38, blue: 0.05)
        case .meadow: return Color(red: 0.13, green: 0.58, blue: 0.30)
        case .lilac: return Color(red: 0.48, green: 0.32, blue: 0.85)
        case .crimson: return Color(red: 0.78, green: 0.13, blue: 0.33)
        case .gold: return Color(red: 0.76, green: 0.53, blue: 0.02)
        case .teal: return Color(red: 0.04, green: 0.55, blue: 0.53)
        case .magenta: return Color(red: 0.70, green: 0.20, blue: 0.70)
        }
    }
}

/// The board's tonal palette, resolved from a `ThemeChoice`. Flat colors
/// only — box borders stay luminance steps in `gridTone`, never hard lines.
struct ThemeTones {
    /// Full-bleed backdrop behind the glass.
    let background: Color
    /// Box washes, hairlines, pencil digits (at reduced opacity).
    let gridTone: Color
    /// Given digits.
    let digitTone: Color
    /// Light-leaning themes flip the wash opacities and deepen the accent.
    let isLight: Bool
}

/// Color scheme for the whole app — both platforms. `auto` follows the
/// system; the tinted themes (camel, blueprint, forest) pin their leaning so
/// materials and secondary text follow along.
enum ThemeChoice: String, Codable, Sendable, CaseIterable {
    case auto, dark, light, camel, blueprint, forest

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .dark: return "Void"
        case .light: return "Paper"
        case .camel: return "Camel"
        case .blueprint: return "Blueprint"
        case .forest: return "Forest"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light, .camel: return .light
        case .dark, .blueprint, .forest: return .dark
        }
    }

    /// Tones for this theme; `resolved` decides only for `auto`, where the
    /// system's scheme picks Void or Paper.
    func tones(for resolved: ColorScheme) -> ThemeTones {
        switch self {
        case .auto:
            return (resolved == .light ? ThemeChoice.light : .dark).tones(for: resolved)
        case .dark:
            return ThemeTones(
                background: CouchPalette.void,
                gridTone: .white,
                digitTone: CouchPalette.paper,
                isLight: false
            )
        case .light:
            return ThemeTones(
                background: Color(red: 0.94, green: 0.93, blue: 0.90),
                gridTone: .black,
                digitTone: Color(red: 0.17, green: 0.16, blue: 0.14),
                isLight: true
            )
        case .camel:
            return ThemeTones(
                background: Color(red: 0.80, green: 0.70, blue: 0.55),
                gridTone: Color(red: 0.20, green: 0.13, blue: 0.06),
                digitTone: Color(red: 0.23, green: 0.15, blue: 0.07),
                isLight: true
            )
        case .blueprint:
            return ThemeTones(
                background: Color(red: 0.05, green: 0.14, blue: 0.33),
                gridTone: Color(red: 0.75, green: 0.85, blue: 1.00),
                digitTone: Color(red: 0.86, green: 0.92, blue: 1.00),
                isLight: false
            )
        case .forest:
            return ThemeTones(
                background: Color(red: 0.05, green: 0.13, blue: 0.09),
                gridTone: Color(red: 0.80, green: 0.92, blue: 0.84),
                digitTone: Color(red: 0.89, green: 0.94, blue: 0.88),
                isLight: false
            )
        }
    }
}

/// Where the board parks vertically on iOS (PRD-2). Anchoring to an edge
/// collects all free space in one contiguous band — room for a system
/// Picture-in-Picture window to sit without covering the grid. tvOS ignores
/// this (the enum is platform-neutral only so prefs decode everywhere).
enum BoardAnchor: String, Codable, Sendable, CaseIterable {
    case top, center, bottom

    var title: String {
        switch self {
        case .top: return "Top"
        case .center: return "Center"
        case .bottom: return "Bottom"
        }
    }
}

/// The optional ambient chip parked in the band opposite the board (PRD-2):
/// a clock, or points + streak. Off is the default and the statement.
enum AmbientSlot: String, Codable, Sendable, CaseIterable {
    case none, clock, streak

    var title: String {
        switch self {
        case .none: return "Off"
        case .clock: return "Clock"
        case .streak: return "Streak"
        }
    }
}

struct NinePrefs: Codable, Sendable, Equatable {
    /// Off is the statement (PRD §3).
    var showTimer = false
    var errorHighlight = true
    var accent: AccentChoice = .glacier
    /// Tap a placed digit to light up every cell holding it, notes included.
    var numberHighlight = true
    /// Touch controls sit at the bottom edge, in thumb reach; false = top.
    var controlsAtBottom = true
    /// Color scheme for the whole app; stored under the pre-theme key
    /// "appearance" so 1.x blobs (auto/dark/light) decode unchanged.
    var theme: ThemeChoice = .auto
    /// Launch straight back into a board in progress.
    var resumeOnLaunch = true
    /// iOS board position; an edge anchor frees one contiguous band for PiP.
    var boardAnchor: BoardAnchor = .center
    /// iOS ambient chip in the free band; off by default.
    var ambientSlot: AmbientSlot = .none
    /// tvOS: haptics in the controller's hands during a pad session (PRD-5
    /// §2.2). On by default — the whole point is the Afterglow score in hand;
    /// the "Controller haptics" row silences all of it.
    var controllerHaptics = true

    init() {}

    enum CodingKeys: String, CodingKey {
        case showTimer, errorHighlight, accent, numberHighlight
        case controlsAtBottom, resumeOnLaunch, boardAnchor, ambientSlot
        case controllerHaptics
        case theme = "appearance"
    }

    /// Tolerant decoding: CouchStored discards the whole blob when decode
    /// throws, so any field added after 1.0 must fall back to its default
    /// instead of resetting a player's settings. Enum fields decode with
    /// `try?` — an unknown raw value (a downgrade meeting a newer accent or
    /// theme) resets that one field, not the whole blob.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showTimer = try c.decodeIfPresent(Bool.self, forKey: .showTimer) ?? false
        errorHighlight = try c.decodeIfPresent(Bool.self, forKey: .errorHighlight) ?? true
        accent = (try? c.decodeIfPresent(AccentChoice.self, forKey: .accent)) ?? .glacier
        numberHighlight = try c.decodeIfPresent(Bool.self, forKey: .numberHighlight) ?? true
        controlsAtBottom = try c.decodeIfPresent(Bool.self, forKey: .controlsAtBottom) ?? true
        theme = (try? c.decodeIfPresent(ThemeChoice.self, forKey: .theme)) ?? .auto
        resumeOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .resumeOnLaunch) ?? true
        boardAnchor = (try? c.decodeIfPresent(BoardAnchor.self, forKey: .boardAnchor)) ?? .center
        ambientSlot = (try? c.decodeIfPresent(AmbientSlot.self, forKey: .ambientSlot)) ?? .none
        controllerHaptics = try c.decodeIfPresent(Bool.self, forKey: .controllerHaptics) ?? true
    }
}

// GameKind moved to the Engine (BoardLibrary.swift) so the library can key on
// it; the app target compiles the Engine sources directly, so it's used here
// unqualified as before.

/// The legacy single autosave slot. Retained for one-time migration decode of
/// a pre-library `nine.save` blob (and to write an empty slot back on migrate,
/// so a downgrade sees "no save", never a stale board).
struct SaveSlot: Codable, Sendable, Equatable {
    var game: NineGame?
    var kind: GameKind?

    init(game: NineGame? = nil, kind: GameKind? = nil) {
        self.game = game
        self.kind = kind
    }
}

// MARK: - Model

@MainActor @Observable
final class AppModel {
    enum Screen: Equatable { case home, game }

    // Observable state.
    private(set) var screen: Screen = .home
    private(set) var game: NineGame?
    private(set) var kind: GameKind?
    /// Set the instant the last correct digit lands; drives the luminance
    /// wave and the calm completion chip.
    private(set) var solvedAt: Date?
    /// The cell of the most recent placement — at `finishSolve()` this is
    /// the winning cell by definition, and the Afterglow wave's origin.
    private(set) var lastPlacedCell: Int?
    /// A puzzle is being composed off-main (Sharp can take a few seconds).
    private(set) var composing: GameKind?

    var prefs: NinePrefs {
        didSet { prefsStore.wrappedValue = prefs }
    }
    /// First-run help overlay: flips true (forever) once dismissed.
    var helpSeen: Bool {
        didSet { helpSeenStore.wrappedValue = helpSeen }
    }
    /// The settings-discoverability chip has flashed this session. Never
    /// persisted — the gentle reminder returns once per launch by design.
    @ObservationIgnored var hintFlashed = false
    private(set) var streak: StreakState {
        didSet { streakStore.wrappedValue = streak }
    }
    /// The full board library: the daily (one per day) plus unlimited free-play
    /// partials, solved boards retained for the "previously played" log.
    /// Local-only — iCloud KVS is 1 MB total and already carries the streak and
    /// the 200-record solve history; `nine.save` was never synced either.
    private(set) var library: BoardLibrary {
        didSet { libraryStore.wrappedValue = library }
    }
    /// The library entry the on-screen game reads from and persists back into.
    private(set) var currentEntryID: UUID?
    /// Every finished board: date, difficulty, time, points (capped log).
    private(set) var history: SolveHistory {
        didSet { historyStore.wrappedValue = history }
    }

    // Persistence (streaks and the solve log are precious → cloud-synced).
    @ObservationIgnored private let prefsStore =
        CouchStored(wrappedValue: NinePrefs(), "nine.prefs")
    @ObservationIgnored private let streakStore =
        CouchStored(wrappedValue: StreakState(), "nine.streak", cloudSynced: true)
    @ObservationIgnored private let libraryStore =
        CouchStored(wrappedValue: BoardLibrary(), "nine.library")
    /// Legacy single-slot store — read once for migration, then blanked so a
    /// downgrade sees "no save" rather than a stale board.
    @ObservationIgnored private let legacySaveStore =
        CouchStored(wrappedValue: SaveSlot(), "nine.save")
    @ObservationIgnored private let helpSeenStore =
        CouchStored(wrappedValue: false, "help.seen")
    @ObservationIgnored private let historyStore =
        CouchStored(wrappedValue: SolveHistory(), "nine.history", cloudSynced: true)

    /// The CloudKit boundary (PRD-8). Nil when the store isn't created; when
    /// present but no iCloud account exists the app stays purely local — sync
    /// is ambient or absent, never a modal.
    @ObservationIgnored private var cloudStore: LibraryCloudStore?

    #if os(macOS)
    // MARK: - Mac window state (PRD-4 §2.5)

    /// The Mac window's posture: the full 720×820 window, or the compact
    /// board-only desk pane.
    enum MacWindowMode: String, Sendable { case full, desk }
    private(set) var windowMode: MacWindowMode = .full
    /// Whether the desk pane floats above other windows. Opt-in, but the
    /// choice is remembered across launches (PRD-4 §7 open question resolved).
    var deskFloating: Bool {
        didSet { deskFloatingStore.wrappedValue = deskFloating }
    }
    @ObservationIgnored private let deskFloatingStore =
        CouchStored(wrappedValue: false, "nine.mac.deskFloating")
    /// Menu-driven request to open the interactive tutorial (Help ▸ How to
    /// Play). RootView observes and presents the overlay; reset on dismiss.
    var macShowTutorial = false
    /// Menu-driven request to open the board tracker (Game ▸ Boards…). The home
    /// view presents a GlassSheet bound to this; reset on dismiss.
    var macShowBoards = false

    func enterDeskMode() { windowMode = .desk }
    func exitDeskMode() { windowMode = .full }
    func toggleDeskMode() { windowMode = windowMode == .full ? .desk : .full }
    #endif

    #if os(tvOS)
    // MARK: - Pad session (PRD-5 §4 Step 2)

    /// The reader for a paired extended gamepad. Owned here so the shelf can
    /// observe `padConnected` at launch; the active screen sets its `onGesture`.
    @ObservationIgnored let padReader = PadReader()
    /// An extended gamepad is paired. Adoption is on gesture traffic, not this
    /// flag (the sim's phantom pad reports paired but emits nothing); a drop
    /// while `padSession` is on triggers the remote-grammar fallback.
    private(set) var padConnected = false
    /// The board is under controller grammar: RemoteKit gestures are ignored,
    /// the pad drives every mutation. Entered automatically on the first real
    /// pad gesture; Menu still exits (save + home).
    var padSession = false
    #if DEBUG
    /// The `--pad-probe` HUD is mounted and `padReader.diagnosticsEnabled` is on
    /// (os.Logger traces + poll-edge counters). Presentation/observation rig
    /// only, never compiled into Release (PRD-5 Phase 0).
    var padProbe = false
    /// Which surface the reader's gesture stream is pointed at, for the HUD:
    /// "adoption-listener" / "tutorial" / "pad-grammar".
    var padRoutingLabel = "—"
    #endif
    /// The interactive pad tutorial has run once. Persisted — it plays on the
    /// first pad session ever, then never nags again.
    var padTutorialSeen: Bool {
        didSet { padTutorialSeenStore.wrappedValue = padTutorialSeen }
    }
    @ObservationIgnored private let padTutorialSeenStore =
        CouchStored(wrappedValue: false, "nine.pad.tutorialSeen")

    /// Begin observing controller connection (call once at launch). PadKit is
    /// inert until a device pairs, so this is free on a remote-only household.
    func startPadReader() {
        padReader.onConnectionChange = { [weak self] connected in
            self?.padConnected = connected
        }
        padReader.start()
    }

    // Pad sessions are entered automatically by GameScreen when a real pad
    // gesture arrives (the Pad Play card and its explicit start are retired);
    // a mid-game drop falls back to the remote grammar in place, so the timer
    // never pauses — the reconnect veil is gone too (PRD-5 revised).

    #if DEBUG
    /// Replay a comma-separated PadGesture script through the reader's OWN
    /// callback, so adoption → routing → grammar → UI all run exactly as they
    /// would for a real controller. Honest boundary: this validates everything
    /// ABOVE the GCController layer, never the poll/sampler hardware read
    /// itself (that needs a forwarded physical pad — PRD-5 Phase 4.2).
    ///
    /// Tokens: `cross`/`circle`/`square`/…/`options` (press only), `<btn>.tap`
    /// (quick release → undo/place), `<btn>.hold` (past the 400 ms gate →
    /// erase/peek), `flick.<dir8>` (e.g. `flick.upLeft`), `move.<dir4>`.
    private func replayPadGestures(_ spec: String) {
        let tokens = spec.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000) // let GameScreen install its listener
            for token in tokens {
                await playPadToken(token)
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    @MainActor
    private func playPadToken(_ token: String) async {
        func fire(_ g: PadGesture) { padReader.onGesture?(g) }
        let parts = token.split(separator: ".").map(String.init)
        let head = parts.first ?? ""
        let mod = parts.count > 1 ? parts[1] : nil
        switch head {
        case "flick":
            if let d = mod.flatMap(Direction8OrCenter.init(rawValue:)) { fire(.flick(d)) }
        case "move":
            if let d = mod.flatMap(Direction4.init(rawValue:)) { fire(.move(d, glide: false)) }
        default:
            guard let button = Self.padButton(head) else { return }
            fire(.button(button))
            switch mod {
            case "tap":
                try? await Task.sleep(nanoseconds: 150_000_000) // release before the hold gate
                fire(.buttonUp(button))
            case "hold":
                try? await Task.sleep(nanoseconds: 600_000_000) // release past the 400 ms hold gate
                fire(.buttonUp(button))
            default:
                break // press only
            }
        }
    }

    private static func padButton(_ name: String) -> PadButton? {
        switch name {
        case "cross": return .cross
        case "circle": return .circle
        case "square": return .square
        case "triangle": return .triangle
        case "l1": return .l1
        case "r1": return .r1
        case "l2": return .l2
        case "r2": return .r2
        case "r3": return .r3
        case "options", "create": return .options
        default: return nil
        }
    }
    #endif
    #endif

    init() {
        prefs = prefsStore.wrappedValue
        streak = streakStore.wrappedValue
        library = libraryStore.wrappedValue
        helpSeen = helpSeenStore.wrappedValue
        history = historyStore.wrappedValue
        // Initialize every platform-specific stored property before the
        // migration below uses `self` (Swift requires all stored props set).
        #if os(tvOS)
        padTutorialSeen = padTutorialSeenStore.wrappedValue
        #endif
        #if os(macOS)
        deskFloating = deskFloatingStore.wrappedValue
        #endif

        // One-time migration: seed the library from a legacy `nine.save` board,
        // then blank that slot (a downgrade sees "no save", never a stale one).
        // Runs on every platform; order stays migrate → ingest → resume → publish.
        if library.entries.isEmpty {
            let legacy = legacySaveStore.wrappedValue
            if let game = legacy.game, let kind = legacy.kind {
                library = BoardLibrary.migrating(game: game, kind: kind, now: Date())
                try? libraryStore.flushNow()
            }
            legacySaveStore.wrappedValue = SaveSlot()
            try? legacySaveStore.flushNow()
        }

        #if os(tvOS)
        startPadReader()
        // Resume straight into a board in progress (PRD-5 §2.3 parity). A fresh
        // launch is a remote surface; the controller grammar is adopted in
        // place the moment a real pad gesture arrives.
        if prefs.resumeOnLaunch, let entry = library.mostRecentInProgress {
            startEntry(entry.id)
        }
        #endif
        #if os(macOS)
        // Resume straight into a board in progress, as iOS — the Mac equivalent
        // of "fewer taps to the board" (PRD-4 §2.6 resume-on-launch parity).
        if prefs.resumeOnLaunch, let entry = library.mostRecentInProgress {
            startEntry(entry.id)
        }
        #endif
        #if os(iOS)
        // Fewer taps to the board: a launch with a board in progress goes
        // straight back to it. The home chevron is one tap away.
        // Widget moves made while the app was dead merge into the day entry
        // before resume reads the library (and before the publish below can
        // write a stale board over them). Free-play partials are untouched.
        ingestSharedDailyBoard()
        if prefs.resumeOnLaunch, let entry = library.mostRecentInProgress {
            startEntry(entry.id)
        }
        // Post-load publish covers state that changed without the widget
        // hearing about it (reinstall, iCloud KVS sync, midnight).
        WidgetBridge.publish(from: self)
        #endif

        // Cloud library (PRD-8). Ambient or absent: no iCloud account →
        // purely local, no modal, no error surfaced (and no CKContainer, which
        // hard-traps when the app isn't iCloud-entitled). An account appearing
        // later starts sync on the next foreground.
        setUpCloudSyncIfAvailable()
    }

    /// Construct and start the cloud store, but only when an iCloud account is
    /// signed in. Idempotent — safe to call repeatedly (e.g. on foreground).
    private func setUpCloudSyncIfAvailable() {
        guard cloudStore == nil, FileManager.default.ubiquityIdentityToken != nil else { return }
        let store = LibraryCloudStore()
        store.onRemoteEntry = { [weak self] synced in self?.applyRemoteEntry(synced) }
        store.onRemoteDeletion = { [weak self] id in self?.applyRemoteDeletion(id) }
        store.onAccountReset = { [weak self] in self?.repushEntireLibrary() }
        cloudStore = store
        store.start()
        // Seed the cloud from whatever this device already has on a first run
        // (idempotent). Ongoing per-mutation pushes keep it current thereafter;
        // a re-sign-in re-seeds via onAccountReset.
        if !store.hasSyncedBefore { repushEntireLibrary() }
    }

    // MARK: - Derived

    var todayOrdinal: Int { DailySeed.dayOrdinal(for: Date()) }

    var todaySolved: Bool { streak.hasCompleted(day: todayOrdinal) }

    /// The saved board, when it is today's daily and still in progress.
    var savedDaily: NineGame? {
        library.inProgressDaily(day: todayOrdinal)?.game
    }

    /// The most recent free-play partial (drives the Continue card).
    var savedFree: (game: NineGame, difficulty: Difficulty)? {
        guard let entry = library.mostRecentFreePartial,
              case .free(let difficulty) = entry.kind else { return nil }
        return (entry.game, difficulty)
    }

    /// In-progress boards, newest first (tracker "In progress" section).
    var partials: [LibraryEntry] { library.partials }

    /// Solved/archived boards, newest first ("Previously played").
    var playedBoards: [LibraryEntry] { library.played }

    /// Free-play partials only (the Continue card shows the newest).
    var freePartials: [LibraryEntry] {
        library.partials.filter { if case .free = $0.kind { return true }; return false }
    }

    /// Free-play partials beyond the one on the Continue card ("+N more").
    var extraPartialCount: Int { max(0, freePartials.count - 1) }

    var displayedStreak: Int { streak.displayedStreak(today: todayOrdinal) }

    var totalPoints: Int { history.totalPoints }

    /// Whether Undo would do anything right now — drives the Mac Edit ▸ Undo
    /// menu item's enabled state (PRD-4 §2.4).
    var canUndo: Bool { solvedAt == nil && !(game?.undoStack.isEmpty ?? true) }

    // MARK: - Starting games

    func openToday() {
        #if os(iOS)
        // A widget move can be seconds old; merge before resuming.
        ingestSharedDailyBoard()
        #endif
        let day = todayOrdinal
        if let entry = library.inProgressDaily(day: day) {
            startEntry(entry.id)
        } else {
            // No in-progress daily (fresh, or replay-after-solve): compose one.
            // adoptDaily replaces the day slot; recordCompletion is idempotent.
            compose(kind: .daily(day: day), seed: DailySeed.seed(for: Date()), difficulty: .steady)
        }
    }

    func continueSaved() {
        guard let entry = library.mostRecentFreePartial else { return }
        startEntry(entry.id)
    }

    func startFree(_ difficulty: Difficulty) {
        compose(kind: .free(difficulty), seed: .random(in: UInt64.min...UInt64.max), difficulty: difficulty)
    }

    /// Drop the most-recent free partial without playing it (the Continue
    /// card's discard control). The current on-screen game is untouched.
    func discardSaved() {
        guard let entry = library.mostRecentFreePartial else { return }
        library.delete(id: entry.id)
        cloudStore?.delete(entry.id)
        if currentEntryID == entry.id { currentEntryID = nil }
        try? libraryStore.flushNow()
        #if os(iOS)
        WidgetBridge.publish(from: self)
        #endif
    }

    // MARK: - Tracker actions (BoardsSheet)

    /// Resume a specific in-progress entry (a tracker row tap).
    func resumeEntry(id: UUID) { startEntry(id) }

    /// Archive a partial out of the active list (kept as "previously played").
    func archiveEntry(id: UUID) {
        library.archive(id: id)
        if let archived = library.entry(id: id) { cloudStore?.push(archived) }
        if currentEntryID == id { currentEntryID = nil }
        try? libraryStore.flushNow()
        #if os(iOS)
        WidgetBridge.publish(from: self)
        #endif
    }

    /// Delete an entry entirely. Deleting today's daily also clears the shared
    /// board file so the widget offers "tap to start" instead of resurrecting it.
    func deleteEntry(id: UUID) {
        #if os(iOS)
        let wasTodayDaily = isTodayDaily(id)
        #endif
        library.delete(id: id)
        cloudStore?.delete(id)
        if currentEntryID == id { currentEntryID = nil }
        try? libraryStore.flushNow()
        #if os(iOS)
        if wasTodayDaily { WidgetBridge.clearDailyBoard(today: todayOrdinal) }
        WidgetBridge.publish(from: self)
        #endif
    }

    #if os(iOS)
    private func isTodayDaily(_ id: UUID) -> Bool {
        guard let entry = library.entry(id: id) else { return false }
        if case .daily(let day) = entry.kind { return day == todayOrdinal }
        return false
    }
    #endif

    /// Put a library entry on screen and mark it the current persist target.
    private func startEntry(_ id: UUID) {
        guard let entry = library.entry(id: id) else { return }
        currentEntryID = id
        var g = entry.game
        g.timer.start(at: Date())
        self.game = g
        self.kind = entry.kind
        self.solvedAt = nil
        self.lastPlacedCell = nil
        self.screen = .game
        #if DEBUG
        // Simulator rig (never compiled into Release): launching with
        // --debug-fill brings any board one digit from the win, so the
        // completion flow is testable on tvOS too, where the long-press-Undo
        // rig doesn't exist. The final digit is still placed by hand.
        if ProcessInfo.processInfo.arguments.contains("--debug-fill") {
            debugFillAlmostAll()
        }
        #if os(tvOS)
        // Presentation-only rig: the sim's virtual remote never emits pad
        // gestures, so it can never adopt on its own. --debug-pad forces the
        // pad session on so the pad legend, hint chip and toast surfaces can be
        // screenshotted in the simulator (no real controller needed).
        if ProcessInfo.processInfo.arguments.contains("--debug-pad") {
            padSession = true
        }
        // --pad-probe: mount the diagnostics HUD and turn on PadKit's logging +
        // poll-edge counters. Adoption stays organic (do NOT force padSession) so
        // the probe can watch a REAL controller adopt when forwarded from the Mac
        // (Simulator ▸ I/O ▸ Send Game Controller to Device) — PRD-5 Phase 0/1.
        if ProcessInfo.processInfo.arguments.contains("--pad-probe") {
            padProbe = true
            padReader.diagnosticsEnabled = true
        }
        // --debug-pad-gestures "square,flick.up,circle.tap,l2.hold": replay a
        // scripted gesture stream so run-couch-suite can screenshot the pencil
        // chip / undo toast / ghost-rose shimmer / peek in the sim (Phase 4.2).
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--debug-pad-gestures"), idx + 1 < args.count {
            replayPadGestures(args[idx + 1])
        }
        #endif
        #endif
    }

    private func compose(kind: GameKind, seed: UInt64, difficulty: Difficulty) {
        guard composing == nil else { return }
        composing = kind
        Task.detached(priority: .userInitiated) {
            // Pure, Sendable, deterministic — safe off the main actor.
            let puzzle = PuzzleGenerator.generate(seed: seed, difficulty: difficulty)
            await MainActor.run {
                self.composing = nil
                // Create/adopt the entry first so currentEntryID is set before
                // the game goes on screen and persistProgress upserts it.
                let now = Date()
                let newGame = NineGame(puzzle: puzzle)
                let id: UUID
                switch kind {
                case .daily(let day):
                    id = self.library.adoptDaily(game: newGame, day: day, now: now)
                case .free:
                    id = self.library.create(kind: kind, game: newGame, now: now)
                }
                self.startEntry(id)
                self.persistProgress()
            }
        }
    }

    // MARK: - Play actions (GameScreen calls these)

    func place(_ digit: Int, at cell: Int) {
        guard solvedAt == nil, var g = game else { return }
        guard g.place(digit, at: cell) else { return }
        game = g
        lastPlacedCell = cell
        if g.isSolved {
            finishSolve()
        } else {
            persistProgress()
        }
    }

    func togglePencil(_ digit: Int, at cell: Int) {
        guard solvedAt == nil, var g = game else { return }
        guard g.togglePencil(digit, at: cell) else { return }
        game = g
        persistProgress()
    }

    /// Clear a user entry (Delete / 0 on the Mac keyboard, PRD-4 §2.2).
    /// No-op on givens and empty cells; never completes a board.
    @discardableResult
    func erase(at cell: Int) -> Bool {
        guard solvedAt == nil, var g = game else { return false }
        guard g.erase(at: cell) else { return false }
        game = g
        persistProgress()
        return true
    }

    @discardableResult
    func undoMove() -> NineMove? {
        guard solvedAt == nil, var g = game else { return nil }
        guard let move = g.undo() else { return nil }
        game = g
        persistProgress()
        return move
    }

    func goHome() {
        if solvedAt == nil, var g = game {
            g.timer.pause(at: Date())
            game = g
            persistProgress()
        }
        try? libraryStore.flushNow()
        try? streakStore.flushNow()
        // Keep `game`/`solvedAt` untouched so the departing GameScreen stays
        // visually stable through the crossfade; the next start replaces them.
        screen = .home
        #if os(macOS)
        // Desk mode is a board posture; home always gets the full window.
        windowMode = .full
        #endif
        #if os(tvOS)
        // Home is a remote surface; the pad session ends at the shelf.
        padSession = false
        #endif
        #if os(iOS)
        WidgetBridge.publish(from: self)
        #endif
    }

    // MARK: - Internals

    private func finishSolve() {
        guard var g = game else { return }
        let now = Date()
        g.timer.pause(at: now)
        game = g
        solvedAt = now
        var isDaily = false
        if case .daily(let day)? = kind {
            isDaily = true
            streak.recordCompletion(day: day)
            try? streakStore.flushNow()
        }
        let difficulty: Difficulty
        switch kind {
        case .free(let d)?: difficulty = d
        default: difficulty = .steady // the daily composes at steady
        }
        let record = SolveRecord(
            date: now,
            difficulty: difficulty,
            isDaily: isDaily,
            seconds: g.timer.elapsed(at: now),
            points: SolveScore.points(
                difficulty: difficulty, isDaily: isDaily,
                streak: streak.current, seconds: g.timer.elapsed(at: now)
            )
        )
        history.record(record)
        try? historyStore.flushNow()
        // The board is done; keep it as a "previously played" entry.
        if let id = currentEntryID {
            library.markSolved(id: id, at: now)
            if let solvedEntry = library.entry(id: id) { cloudStore?.push(solvedEntry) }
        }
        try? libraryStore.flushNow()
        // GameKit is native on iOS, macOS and tvOS (PRD-5 §2.3 parity ledger);
        // widgets are iOS-only.
        #if os(iOS) || os(macOS) || os(tvOS)
        GameCenter.shared.reportSolve(record: record, history: history, streak: streak)
        #endif
        #if os(iOS)
        WidgetBridge.publish(from: self)
        #endif
    }

    private func persistProgress() {
        guard let game, let id = currentEntryID, var entry = library.entry(id: id) else { return }
        entry.game = game
        entry.updatedAt = Date()
        library.upsert(entry)
        cloudStore?.push(entry)
        #if os(iOS)
        // Fires per move; WidgetBridge digest-gates the actual reloads.
        WidgetBridge.publish(from: self)
        #endif
    }

    // MARK: - Cloud sync (PRD-8)

    /// Ask CloudKit to fetch now (called when the app comes forward). Also the
    /// "quiet re-sync when an account appears" hook: if the user signed into
    /// iCloud since launch, start the store now. Ambient: still no account →
    /// no-op.
    func syncOnForeground() {
        setUpCloudSyncIfAvailable()
        cloudStore?.kick()
    }

    /// Seed every local board up to CloudKit (idempotent — the engine dedupes).
    private func repushEntireLibrary() {
        for entry in library.entries { cloudStore?.push(entry) }
    }

    /// A remote board arrived: merge it in (tested Engine rules), persist, push
    /// back anything the merge changed, and refresh any surface showing it.
    private func applyRemoteEntry(_ synced: SyncedEntry) {
        let effects = LibrarySync.apply(
            remote: synced, into: &library, now: Date(), makeID: { UUID() }
        )
        try? libraryStore.flushNow()
        for id in effects.reupload {
            if let entry = library.entry(id: id) { cloudStore?.push(entry) }
        }
        for id in effects.cloudDeletes { cloudStore?.delete(id) }
        refreshOnScreenBoardAfterMerge()
        #if os(iOS)
        WidgetBridge.publish(from: self)   // widgets must reflect remote moves
        #endif
    }

    private func applyRemoteDeletion(_ id: UUID) {
        LibrarySync.applyDeletion(id: id, into: &library)
        if currentEntryID == id { currentEntryID = nil }
        try? libraryStore.flushNow()
        #if os(iOS)
        WidgetBridge.publish(from: self)
        #endif
    }

    /// If a merge changed the board on screen, swap it in calmly (keep the
    /// timer running, never yank progress out from under an active hand — only
    /// adopt a board that is further along). Re-points the persist target if a
    /// daily merge re-homed the entry's id.
    private func refreshOnScreenBoardAfterMerge() {
        guard screen == .game, solvedAt == nil else { return }
        if let id = currentEntryID, library.entry(id: id) == nil,
           case .daily(let day)? = kind, let daily = library.dailyEntry(day: day) {
            currentEntryID = daily.id
        }
        guard let id = currentEntryID, let entry = library.entry(id: id) else { return }
        if let shown = game, entry.game.fillFraction > shown.fillFraction {
            var g = entry.game
            g.timer.start(at: Date())
            game = g
        }
    }

    #if os(iOS)
    // MARK: - Widget board ingestion (PRD-3 §4)

    /// Adopt the shared daily board when the widget moved it forward. Runs
    /// on launch, on scene activation and before opening today's daily, so
    /// the app never plays over widget moves. A solve made in the widget is
    /// recorded here — exactly once — into streak/history/Game Center.
    func ingestSharedDailyBoard() {
        let today = todayOrdinal
        // Invariant repair: a solved, already-recorded daily should be marked
        // solved in the library, not sitting as an in-progress entry that
        // resumeOnLaunch/openToday could land on.
        if let daily = library.inProgressDaily(day: today), daily.game.isSolved,
           streak.hasCompleted(day: today) {
            library.markSolved(id: daily.id, at: Date())
            try? libraryStore.flushNow()
        }
        guard let shared = SharedDailyBoardStore.load(),
              shared.isCurrent(today: today),
              shared.revision > WidgetBridge.knownBoardRevision
        else { return }
        WidgetBridge.knownBoardRevision = shared.revision

        if let pending = shared.pendingSolve {
            // Solved entirely in the widget. recordCompletion is idempotent
            // per day, and pendingSolve is cleared below, so a same-day
            // re-ingest no-ops.
            if !streak.hasCompleted(day: shared.dayOrdinal) {
                streak.recordCompletion(day: shared.dayOrdinal)
                try? streakStore.flushNow()
                let record = SolveRecord(
                    date: pending.solvedAt,
                    difficulty: .steady, // the daily composes at steady
                    isDaily: true,
                    seconds: pending.seconds,
                    points: SolveScore.points(
                        difficulty: .steady, isDaily: true,
                        streak: streak.current, seconds: pending.seconds
                    )
                )
                history.record(record)
                try? historyStore.flushNow()
                GameCenter.shared.reportSolve(record: record, history: history, streak: streak)
            }
            // Adopt the finished board into the one day entry and mark it solved
            // (free-play entries structurally untouched — the clobber fix).
            let id = library.adoptDaily(game: shared.game, day: shared.dayOrdinal, now: Date())
            library.markSolved(id: id, at: pending.solvedAt)
            try? libraryStore.flushNow()
            var cleared = shared
            cleared.pendingSolve = nil
            cleared.revision += 1
            cleared.updatedAt = Date()
            WidgetBridge.knownBoardRevision = cleared.revision
            try? SharedDailyBoardStore.save(cleared)
            // Mid-play on the same daily? Show the finished board calmly.
            if screen == .game, case .daily(let day)? = kind, day == shared.dayOrdinal {
                game = shared.game
                solvedAt = pending.solvedAt
            }
        } else if !shared.game.isSolved {
            // Widget moves flow into the day entry only — free-play untouched.
            let id = library.adoptDaily(game: shared.game, day: shared.dayOrdinal, now: Date())
            try? libraryStore.flushNow()
            if screen == .game, solvedAt == nil,
               case .daily(let day)? = kind, day == shared.dayOrdinal {
                var g = shared.game
                g.timer.start(at: Date())
                game = g
                currentEntryID = id // keep the persist target on the day entry
            }
        } else if library.dailyEntry(day: shared.dayOrdinal)?.status != .solved {
            // Solved with no pendingSolve → already recorded elsewhere; make
            // sure the day entry reflects solved (repair; keeps solvedAt if set).
            let id = library.adoptDaily(game: shared.game, day: shared.dayOrdinal, now: Date())
            library.markSolved(id: id, at: Date())
            try? libraryStore.flushNow()
        }
        // Re-publish so the glanceable widgets swap the widget's optimistic
        // facts for the recorded truth (points included).
        WidgetBridge.publish(from: self)
    }
    #endif

    #if DEBUG
    /// Test-only (never compiled into Release): fill every unsolved cell but
    /// one with the proven solution, so completion flows — wave, points,
    /// history, Game Center — can be exercised without solving 50 cells by
    /// hand. Reached by long-pressing Undo in DEBUG builds.
    func debugFillAlmostAll() {
        guard solvedAt == nil, var g = game else { return }
        let solution = g.puzzle.solution.cells
        let unsolved = (0..<81).filter { !g.isGiven($0) && g.entry(at: $0) != solution[$0] }
        guard unsolved.count > 1 else { return }
        for cell in unsolved.dropLast() {
            g.place(solution[cell], at: cell)
        }
        game = g
        persistProgress()
    }
    #endif
}
