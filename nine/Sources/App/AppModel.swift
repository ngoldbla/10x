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

/// Where the board parks vertically on iOS (PRD-2). Anchoring to an edge
/// collects all free space in one contiguous band — room for a system
/// Picture-in-Picture window to sit without covering the grid. tvOS ignores
/// this (the enum is platform-neutral only so prefs decode everywhere).
enum BoardAnchor: String, Codable, Sendable, CaseIterable {
    case top, center, bottom

    var title: String {
        switch self {
        case .top: return Strings.string("boardAnchor.top")
        case .center: return Strings.string("boardAnchor.center")
        case .bottom: return Strings.string("boardAnchor.bottom")
        }
    }
}

/// The optional ambient chip parked in the band opposite the board (PRD-2):
/// a clock, or points + streak. Off is the default and the statement.
enum AmbientSlot: String, Codable, Sendable, CaseIterable {
    case none, clock, streak

    var title: String {
        switch self {
        // The same "Off" every other settings row shows — one key, so a
        // translator cannot make this row disagree with the toggles above it.
        case .none: return Strings.string("prefs.toggle.off")
        case .clock: return Strings.string("ambientSlot.clock")
        case .streak: return Strings.string("ambientSlot.streak")
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
    /// iOS: the in-play haptic marks (PRD-21) — a whisper as a digit lands, a
    /// soft double-knock when it contradicts the solution. On by default; the
    /// solve crescendo is deliberately *not* gated by this, being a once-a-
    /// board celebration rather than a per-move texture.
    var touchHaptics = true

    init() {}

    enum CodingKeys: String, CodingKey {
        case showTimer, errorHighlight, accent, numberHighlight
        case controlsAtBottom, resumeOnLaunch, boardAnchor, ambientSlot
        case controllerHaptics, touchHaptics
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
        touchHaptics = try c.decodeIfPresent(Bool.self, forKey: .touchHaptics) ?? true
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
        didSet {
            prefsStore.wrappedValue = prefs
            publishAppearance()
        }
    }

    /// Mirror theme + accent into the cloud-synced sibling key the watch reads
    /// (PRD-6). `nine.prefs` itself stays local — a Mac has no business
    /// inheriting an iPhone's thumb reach — but what Nine *looks like* should
    /// follow the player onto their wrist, and a watch with its own appearance
    /// settings would be a settings screen on a watch.
    ///
    /// Written on every platform, not just iOS: the value travels by KVS, so a
    /// player who only ever changes their theme on the Apple TV should still
    /// see it on the wrist.
    private func publishAppearance() {
        let published = SharedAppearance(
            theme: prefs.theme.rawValue, accent: prefs.accent.rawValue
        )
        guard appearanceStore.wrappedValue != published else { return }
        appearanceStore.wrappedValue = published
    }
    /// First-run lesson seen: flips true (forever) once the playable first
    /// beat is finished or skipped. On tvOS and macOS this still gates the
    /// old legend overlay; on iOS it gates the beat (PRD-34).
    var helpSeen: Bool {
        didSet { helpSeenStore.wrappedValue = helpSeen }
    }
    /// The one-time welcome ledger has been shown (PRD-18). Deliberately a
    /// *separate* flag from `helpSeen`: a 1.1 player updating into this build
    /// has `helpSeen` true already, and should still get the welcome once —
    /// and must not be handed a beginner's lesson they finished last year.
    var welcomeSeen: Bool {
        didSet { welcomeSeenStore.wrappedValue = welcomeSeen }
    }
    /// Which of the three lifetime tips have been spent (PRD-34).
    private(set) var tips: TipLedger {
        didSet { tipsStore.wrappedValue = tips }
    }
    /// What the coach remembers per board (PRD-11): hints shown, auto notes on.
    /// Nothing is ever gated on it — §3 rules hint quotas out forever.
    private(set) var coach: CoachLedger {
        didSet { coachStore.wrappedValue = coach }
    }
    /// Which dailies are solved (PRD-14) — the archive grid's checkmarks.
    /// Written only by `finishSolve` and the launch backfill; the library
    /// cannot hold this, because `prune()` caps solved boards at 20.
    private(set) var archive: ArchiveLedger {
        didSet { archiveStore.wrappedValue = archive }
    }
    /// A tip has already been shown during this launch. Never persisted: the
    /// "one per session" half of the budget is a property of the launch, and
    /// the lifetime half is what the ledger is for.
    @ObservationIgnored var tipShownThisSession = false

    /// Spend one tip, from both budgets at once.
    func noteTipShown(_ tip: NineTip) {
        tipShownThisSession = true
        tips.record(tip)
    }
    /// The settings-discoverability chip has flashed this session. Never
    /// persisted — the gentle reminder returns once per launch by design.
    @ObservationIgnored var hintFlashed = false
    /// Launches counted so far, capped (PRD-34). The stats drawer is opened by
    /// an unhinted pull-down; a 3pt hairline grabber appears for the first
    /// few sessions and then fades forever, so the affordance teaches itself
    /// once and never becomes furniture. Counting stops at the cap so the
    /// number cannot drift into something else's decision.
    private(set) var sessionCount: Int {
        didSet { sessionCountStore.wrappedValue = sessionCount }
    }
    /// Sessions during which the drawer grabber is drawn.
    static let grabberSessions = 3
    /// Show the one-time drawer affordance? Stops early once the player has
    /// actually opened the drawer — they know; stop pointing.
    var showsDrawerGrabber: Bool { sessionCount <= Self.grabberSessions && !drawerFound }
    /// The drawer has been opened at least once, ever.
    private(set) var drawerFound: Bool {
        didSet { drawerFoundStore.wrappedValue = drawerFound }
    }

    /// Called the first time the drawer opens, by any route.
    func noteDrawerFound() {
        guard !drawerFound else { return }
        drawerFound = true
    }
    private(set) var streak: StreakState {
        didSet { streakStore.wrappedValue = streak }
    }
    /// The bridged day whose card has been acknowledged (PRD-13 §3).
    private(set) var graceSeenDay: Int {
        didSet { graceSeenStore.wrappedValue = graceSeenDay }
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
    /// Theme + accent, mirrored for the watch (PRD-6). A sibling top-level key
    /// rather than a field on `nine.prefs`, because `nine.prefs` ships in every
    /// released build and an older one's next write erases a field it has no
    /// property for (EXECUTING-A-PRD §2).
    @ObservationIgnored private let appearanceStore =
        CouchStored(wrappedValue: SharedAppearance(), SharedAppearance.storeKey, cloudSynced: true)
    @ObservationIgnored private let libraryStore =
        CouchStored(wrappedValue: BoardLibrary(), "nine.library")
    /// Legacy single-slot store — read once for migration, then blanked so a
    /// downgrade sees "no save" rather than a stale board.
    @ObservationIgnored private let legacySaveStore =
        CouchStored(wrappedValue: SaveSlot(), "nine.save")
    @ObservationIgnored private let helpSeenStore =
        CouchStored(wrappedValue: false, "help.seen")
    @ObservationIgnored private let welcomeSeenStore =
        CouchStored(wrappedValue: false, "welcome.seen")
    /// Its own top-level blob, never a field on a library entry — a new field
    /// inside `LibraryEntry` is erased by the next autosave of any older build
    /// (EXECUTING-A-PRD §2).
    @ObservationIgnored private let tipsStore =
        CouchStored(wrappedValue: TipLedger(), "nine.tips")
    /// Its own top-level blob for the same reason `nine.tips` is (PRD-11 §6):
    /// a new field inside `LibraryEntry` is erased by the next autosave of any
    /// older build (EXECUTING-A-PRD §2). Local-only — a hint count belongs to
    /// the hand that played the board, not to the board, exactly as `undoCount`
    /// does (PRD-8 §2).
    @ObservationIgnored private let coachStore =
        CouchStored(wrappedValue: CoachLedger(), "nine.coach")
    @ObservationIgnored private let sessionCountStore =
        CouchStored(wrappedValue: 0, "nine.sessionCount")
    @ObservationIgnored private let drawerFoundStore =
        CouchStored(wrappedValue: false, "nine.drawerFound")
    @ObservationIgnored private let historyStore =
        CouchStored(wrappedValue: SolveHistory(), "nine.history", cloudSynced: true)
    /// Which dailies are solved (PRD-14). Its own blob for the reason above,
    /// and *not* a sibling key of `nine.history`: `SolveHistory` is an ordered
    /// record array with a capacity prune and a quarantine, and a set of day
    /// ordinals shares none of that. Cloud-synced unlike `nine.coach` — a
    /// checkmark is a property of the player, not of the hand that earned it.
    @ObservationIgnored private let archiveStore =
        CouchStored(wrappedValue: ArchiveLedger(), "nine.archive", cloudSynced: true)
    /// The `lastGraceDay` whose "your streak held" card has already been seen,
    /// or 0 for none (PRD-13 §3).
    ///
    /// A bare `Int` rather than a ledger, because PRD-13's non-stacking rule
    /// guarantees there is exactly one live bridge at a time — so the ordinal
    /// *is* the whole state, and `CouchStored` already falls back to the
    /// default when an `Int` fails to decode, which is the tolerance a richer
    /// type would have had to hand-write. Cloud-synced beside `nine.streak`:
    /// the card is a thing said to the player once, not once per device.
    @ObservationIgnored private let graceSeenStore =
        CouchStored(wrappedValue: 0, "nine.graceSeen", cloudSynced: true)

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
        graceSeenDay = graceSeenStore.wrappedValue
        library = libraryStore.wrappedValue
        helpSeen = helpSeenStore.wrappedValue
        welcomeSeen = welcomeSeenStore.wrappedValue
        tips = tipsStore.wrappedValue
        coach = coachStore.wrappedValue
        archive = archiveStore.wrappedValue
        history = historyStore.wrappedValue
        drawerFound = drawerFoundStore.wrappedValue
        // Counted here rather than on scene activation: a launch is the unit
        // the affordance is budgeted in, and `AppModel` is built exactly once
        // per launch. Saturates at the cap + 1 so the stored number stays
        // small and monotone forever.
        sessionCount = min(Self.grabberSessions + 1, sessionCountStore.wrappedValue + 1)
        // Initialize every platform-specific stored property before the
        // migration below uses `self` (Swift requires all stored props set).
        #if os(tvOS)
        padTutorialSeen = padTutorialSeenStore.wrappedValue
        #endif
        #if os(macOS)
        deskFloating = deskFloatingStore.wrappedValue
        #endif
        // `didSet` does not fire for assignments inside `init`, so the bumped
        // session count is written through by hand — otherwise the counter
        // would reset every launch and the grabber would never fade.
        sessionCountStore.wrappedValue = sessionCount

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

        // After the migration, so a legacy board's solved daily is seen too.
        backfillArchiveLedger()

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
        PhoneWatchLink.shared.activate(model: self)
        publishDailyToWatch()
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

    /// The past day the board on screen belongs to — nil for today's daily and
    /// for free play. Drives the in-game "Archive · Jul 12" chip, which is the
    /// only thing telling the player they are not on today's board.
    ///
    /// Keyed on provenance rather than on the clock, for the same reason the
    /// streak guard is: `day < todayOrdinal` alone would grow an "Archive ·
    /// Jul 25" chip on the board a player is *actively finishing* the moment
    /// local midnight passes under them.
    var archiveDay: Int? {
        guard case .daily(let day)? = kind, day < todayOrdinal,
              openedOn(day: day) > day else { return nil }
        return day
    }

    /// The day ordinal the board on screen was created on, which is what tells
    /// an archive board from an ordinary daily. Falls back to `day` — "not an
    /// archive board" — when there is no entry to ask, so a missing record can
    /// never invent one.
    private func openedOn(day: Int) -> Int {
        guard let id = currentEntryID, let entry = library.entry(id: id) else { return day }
        return DailySeed.dayOrdinal(for: entry.createdAt)
    }

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

    /// The streak on screen is standing on a grace bridge right now (PRD-13
    /// §3) — which is exactly when the chip wears a shield instead of a flame.
    ///
    /// Guarded on `displayedStreak` as well as on the state, so a bridge that
    /// has since lapsed cannot put a shield on a chip that is no longer drawn.
    var streakHeld: Bool { displayedStreak > 0 && streak.standsOnGrace }

    /// The bridged day still owed its card, or nil.
    ///
    /// One card per bridge, ever: the day ordinal is the identity, so a
    /// relaunch, a re-solve and a second device all resolve to the same one and
    /// the player is told once. Nothing here is a count, and nothing renders it
    /// as one — PRD-13 §3 rules out "shields remaining" everywhere.
    var pendingGraceDay: Int? {
        guard streakHeld, let day = streak.lastGraceDay, day != graceSeenDay else { return nil }
        return day
    }

    /// Dismiss the card for the current bridge. Idempotent.
    func acknowledgeGrace() {
        guard let day = streak.lastGraceDay else { return }
        graceSeenDay = day
        try? graceSeenStore.flushNow()
    }

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

    /// Open any past daily from the archive (PRD-14).
    ///
    /// Mirrors `openToday` without its two today-only concerns. No widget
    /// ingestion: `WidgetBridge.publishDailyBoard` reads
    /// `inProgressDaily(day: todayOrdinal)`, so an archive board is
    /// structurally invisible to the widget and needs no guard. And no streak
    /// write — `finishSolve` passes `today:` to the guarded overload.
    ///
    /// Today routes back through `openToday` rather than composing its own
    /// board, so "today via the archive" and "today via the Today card" are the
    /// same library entry: one daily a day, no duplicates (PRD-14 §5).
    ///
    /// Resume needs nothing new. `inProgressDaily(day:)` is keyed on an
    /// arbitrary day, so a half-finished 12 July is a partial like any other,
    /// and it syncs through PRD-8 as an ordinary `.daily` entry.
    func openArchiveDay(_ day: Int) {
        guard day <= todayOrdinal else { return }   // the future is not offered
        // Nine served no daily before it shipped, so the days before the first
        // one are not "past days you could have played" — they are content
        // dressed as history. The floor is a day, not a month, because the
        // first daily landed mid-month.
        guard day >= ArchiveCalendar.floorDayOrdinal else { return }
        // A compose already in flight calls `startEntry` when it lands, so
        // resuming a partial underneath one yanks the player off this board
        // mid-move seconds later; and `compose` itself refuses a second
        // request, so the other branch would be a silent dead tap. The sheet
        // disables its cells for the same window.
        guard composing == nil else { return }
        guard day != todayOrdinal else { return openToday() }
        if let entry = library.inProgressDaily(day: day) {
            startEntry(entry.id)
        } else {
            compose(kind: .daily(day: day),
                    seed: DailySeed.seed(forDayOrdinal: day),
                    difficulty: .steady)
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
                    #if os(iOS)
                    // The watch may not compose above gentle and the daily is
                    // steady, so this is the only route today's board has to
                    // the wrist (PRD-6). Publishing here rather than on every
                    // move is deliberate: the payload is the immutable puzzle,
                    // so nothing but midnight can change it.
                    if day == self.todayOrdinal {
                        PhoneWatchLink.shared.publishDaily(puzzle, day: day)
                    }
                    #endif
                case .free:
                    id = self.library.create(kind: kind, game: newGame, now: now)
                }
                self.startEntry(id)
                self.persistProgress()
            }
        }
    }

    // MARK: - Coach (PRD-11)

    /// Hints shown on the board currently on screen. Surfaced in the stats
    /// drawer and nowhere else; nothing anywhere is gated on it.
    var coachHints: Int {
        guard let id = currentEntryID else { return 0 }
        return coach.board(id.uuidString).hints
    }

    /// Auto notes for the board on screen. Setting it true fills the marks;
    /// setting it false clears nothing at all (PRD-11 §2.2).
    var autoNotes: Bool {
        get {
            guard let id = currentEntryID else { return false }
            return coach.board(id.uuidString).autoNotes
        }
        set {
            guard let id = currentEntryID else { return }
            writeCoach { $0.setAutoNotes(newValue, for: id.uuidString) }
            guard newValue, solvedAt == nil, var g = game, g.applyAutoNotes() else { return }
            game = g
            persistProgress()
        }
    }

    /// What the coach has to say about the board on screen, or nil when there
    /// is no board to speak about.
    ///
    /// Capped at the board's own difficulty ceiling, so a Gentle board is never
    /// lectured about X-wings (PRD-11 §2.1) — and fed the *player's* grid, not
    /// the puzzle's, so it reasons about the position actually on screen.
    func requestCoachAdvice() -> CoachAdvice? {
        guard let game, solvedAt == nil else { return nil }
        let grid = SudokuGrid(cells: (0..<81).map { game.entry(at: $0) })
        let advice = LogicSolver.advice(
            for: grid, allowed: game.puzzle.difficulty.allowedTechniques
        )
        if let id = currentEntryID {
            writeCoach { $0.recordHint(id.uuidString) }
        }
        return advice
    }

    /// Commit a coach step. The *player* asked for this — nothing here ever
    /// runs unprompted, which is what keeps "the coach never places a digit"
    /// true in the sense that matters: Nine never solves itself.
    ///
    /// A placement goes through the ordinary `place` path, so the wave, the
    /// error rules, the haptics and persistence are all exactly as the rose
    /// would have left them.
    func applyCoachStep(_ step: CoachStep) {
        if let placement = step.step.placement {
            place(placement.digit, at: placement.cell)
            return
        }
        // Eliminations are only offered while auto notes is off — with it on
        // the marks are the machine's and the next placement would recompute
        // these away, so the button is suppressed rather than allowed to lie.
        guard solvedAt == nil, !autoNotes, var g = game else { return }
        var changed = false
        for elimination in step.step.eliminations
        where g.pencilDigits(at: elimination.cell).contains(elimination.digit) {
            changed = g.togglePencil(elimination.digit, at: elimination.cell) || changed
        }
        guard changed else { return }
        game = g
        persistProgress()
    }

    // MARK: - Archive (PRD-14)

    /// Seed the checkmark ledger from what is still knowable, every launch.
    ///
    /// Idempotent (`markSolved` is a set insert), O(library), and self-healing:
    /// a solved daily that arrives later from CloudKit picks up its check on
    /// the next launch. It cannot recover days the library pruned before this
    /// build shipped — nothing can, and the alternative to saying so is holes
    /// in the grid that look exactly like unplayed days.
    ///
    /// `.solved` only, not `status != .inProgress`: `archiveEntry(id:)` archives
    /// *partials* too, and an abandoned board is not a solved one.
    private func backfillArchiveLedger() {
        var ledger = archive
        var changed = false
        if let last = streak.lastCompletedDay {
            changed = ledger.markSolved(day: last) || changed
        }
        for entry in library.entries where entry.status == .solved {
            if case .daily(let day) = entry.kind {
                changed = ledger.markSolved(day: day) || changed
            }
        }
        guard changed else { return }
        archive = ledger
        // Called from `init`, where `didSet` observers are unreliable — the
        // same reason `sessionCountStore` is written through by hand above.
        // A redundant write if the observer did fire; a lost backfill if not.
        archiveStore.wrappedValue = ledger
    }

    /// Every ledger write prunes to the live library, so the blob tracks it
    /// rather than accumulating the ids of boards deleted months ago.
    private func writeCoach(_ mutate: (inout CoachLedger) -> Void) {
        var ledger = coach
        mutate(&ledger)
        ledger.prune(to: Set(library.entries.map { $0.id.uuidString }))
        coach = ledger
    }

    // MARK: - Play actions (GameScreen calls these)

    func place(_ digit: Int, at cell: Int) {
        guard solvedAt == nil, var g = game else { return }
        guard g.place(digit, at: cell, autoNotes: autoNotes) else { return }
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
        guard g.erase(at: cell, autoNotes: autoNotes) else { return false }
        game = g
        persistProgress()
        return true
    }

    @discardableResult
    func undoMove() -> NineMove? {
        guard solvedAt == nil, var g = game else { return nil }
        guard let move = g.undo() else { return nil }
        game = g
        // Undoing the bulk fill without clearing the flag would let the very
        // next placement refill exactly what the player just took back.
        if move.isBulkNotes, let id = currentEntryID {
            writeCoach { $0.setAutoNotes(false, for: id.uuidString) }
        }
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
            // A past-day solve must never rewrite streak state (PRD-14 §2).
            // The guard lives in the Engine because the one-argument form
            // cannot enforce it: its `day > last` check does nothing while
            // `lastCompletedDay` is nil, so a fresh install solving yesterday
            // from the archive would come away with a streak nobody earned.
            //
            // `openedOn`, not `todayOrdinal`: a clock read here is wrong on the
            // ORDINARY path, throwing away the streak of anyone who opens the
            // daily at 23:55 and finishes it at 00:03.
            streak.recordCompletion(day: day, openedOn: openedOn(day: day))
            try? streakStore.flushNow()
            // Every daily solve, not only archive ones — a day solved from the
            // Today card has to carry a check in the grid too, or the archive
            // is right about the past and wrong about the present.
            var ledger = archive
            if ledger.markSolved(day: day) {
                archive = ledger
                try? archiveStore.flushNow()
            }
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
    // MARK: - Solves made somewhere that isn't this app

    /// Record a daily solved on another surface — the widget (PRD-3) or the
    /// watch (PRD-6) — into streak, archive, history and Game Center.
    ///
    /// **Idempotent per day, and that is the whole design.** `hasCompleted`
    /// gates every write, so a re-ingested widget board, a re-sent watch
    /// report and a phone that also solved today all converge on one record.
    /// Both callers rely on that rather than on delivering exactly once, which
    /// is not a guarantee either transport can make.
    ///
    /// Extracted rather than copied. `BoardIntents.swift` records what a
    /// second hand-written copy of the streak rule cost the last time: it went
    /// out of sync with PRD-13's grace bridge and shamed the player.
    private func recordSolveMadeElsewhere(day: Int, solve: PendingSolve) {
        guard !streak.hasCompleted(day: day) else { return }
        // Callers pin `day` to today, so this can never be an archive board —
        // but say so in the call rather than leaving it to a guard elsewhere.
        streak.recordCompletion(day: day, openedOn: day)
        try? streakStore.flushNow()
        // The archive's checkmark, which `finishSolve` writes for every other
        // solve. Without it a daily finished entirely off-app shows no check
        // until the next COLD LAUNCH's backfill — and `BoardLibrary.prune()`'s
        // 20-entry cap can eat the library entry that backfill reads before
        // that launch ever happens, losing the day permanently.
        var ledger = archive
        if ledger.markSolved(day: day) {
            archive = ledger
            try? archiveStore.flushNow()
        }
        let record = SolveRecord(
            date: solve.solvedAt,
            difficulty: .steady, // the daily composes at steady
            isDaily: true,
            seconds: solve.seconds,
            points: SolveScore.points(
                difficulty: .steady, isDaily: true,
                streak: streak.current, seconds: solve.seconds
            )
        )
        history.record(record)
        try? historyStore.flushNow()
        GameCenter.shared.reportSolve(record: record, history: history, streak: streak)
    }

    /// Hand today's daily to the watch if this phone already has it composed.
    ///
    /// `compose` publishes the board it just made; this covers the far commoner
    /// case where the daily was composed yesterday's-tomorrow, or on another
    /// device and synced in, so no compose runs today at all. Called from the
    /// same two places as widget publication — launch and scene activation —
    /// because "the watch came into range" is not an event the phone can hear.
    func publishDailyToWatch() {
        let day = todayOrdinal
        guard let entry = library.dailyEntry(day: day) else { return }
        PhoneWatchLink.shared.publishDaily(entry.game.puzzle, day: day)
    }

    /// A daily solved on the wrist (PRD-6).
    ///
    /// The board itself does not come back — PRD-6 §2.5 keeps play state off
    /// the link — so unlike a widget solve there is no game to adopt. The
    /// library's day entry is left alone: it holds whatever this phone last
    /// played, which is the honest thing to show, and the streak is what the
    /// player actually cares about having crossed over.
    func ingestWatchSolve(_ report: WatchSolveReport) {
        guard report.dayOrdinal == todayOrdinal else { return }
        recordSolveMadeElsewhere(day: report.dayOrdinal, solve: report.solve)
        WidgetBridge.publish(from: self)
    }

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
            recordSolveMadeElsewhere(day: shared.dayOrdinal, solve: pending)
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
