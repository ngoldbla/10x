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
#if os(macOS)
// `SecTask` — the only way to ask this binary what its own signature entitles it
// to. macOS only, because the header is macOS only. See `mayBuildCloudContainer`.
import Security
#endif

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
    /// iOS: the Live Activity that bookmarks a daily you started and left
    /// (PRD-30).
    ///
    /// **On by default, and that is a covenant judgement rather than an
    /// oversight.** The anti-bloat constitution's rule is about *notifications* —
    /// "a single opt-in silent daily reminder at most, off by default" — and
    /// three properties keep this on the other side of that line: it exists only
    /// because the player started a board and walked away, it is never given an
    /// `AlertConfiguration` so it cannot buzz or ring, and it ends itself on
    /// solve and at midnight. iOS already owns a global off switch and a
    /// swipe-to-dismiss, which is the real opt-in gate. Off by default would have
    /// shipped a feature that effectively does not exist, behind a settings row
    /// the covenant makes expensive.
    ///
    /// macOS and tvOS decode it and ignore it: ActivityKit exists on neither.
    var livePresence = true

    init() {}

    enum CodingKeys: String, CodingKey {
        case showTimer, errorHighlight, accent, numberHighlight
        case controlsAtBottom, resumeOnLaunch, boardAnchor, ambientSlot
        case controllerHaptics, touchHaptics, livePresence
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
        livePresence = try c.decodeIfPresent(Bool.self, forKey: .livePresence) ?? true
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
            #if os(iOS)
            // Turning the Live Activity off should clear the Lock Screen in the
            // same gesture, not at the next backgrounding (PRD-30). Turning it on
            // deliberately does *not* start one: an activity is something the
            // player's own play creates, and starting one from a settings toggle
            // would make the toggle the trigger.
            if oldValue.livePresence, !prefs.livePresence { PresenceBridge.endAll() }
            // Theme and accent now reach the widget process, so a palette change
            // has to reload it (PRD-30). `publish` is digest-gated, so a pref
            // change that is not a look change costs nothing.
            if oldValue.theme != prefs.theme || oldValue.accent != prefs.accent {
                WidgetBridge.publish(from: self)
            }
            #endif
        }
    }

    /// The quiet a Focus filter is asking for (PRD-33). Written by
    /// `QuietShelfFilter` when the system activates or deactivates a Focus; read
    /// by the shelf, the Mac and — through `WidgetSnapshot` — the widget.
    ///
    /// A sibling top-level blob rather than a field on `nine.prefs`, and
    /// **deliberately not cloud-synced**, for two separate reasons. It is machine
    /// state the system writes rather than a preference the player set, so it does
    /// not belong beside their settings; and a Focus is a property of the device
    /// in front of you, so an iPhone entering Work Focus must not quiet an Apple
    /// TV in another room. (EXECUTING-A-PRD §2 supplies the third reason for the
    /// sibling key: an older build's next write would erase a new field on
    /// `nine.prefs`.)
    private(set) var focus: QuietFocus {
        didSet { focusStore.wrappedValue = focus }
    }

    /// Adopt a Focus filter's state. The only writer is `QuietShelfFilter`.
    func applyFocus(_ next: QuietFocus) {
        guard focus != next else { return }
        focus = next
        try? focusStore.flushNow()
        #if os(iOS)
        // The Home Screen has to go quiet in the same breath or the filter is a
        // lie two inches from the app icon.
        WidgetBridge.publish(from: self)
        #endif
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
    /// Which techniques this player has met (PRD-25). The other axis from
    /// `coach`: that one is per board and local, this one is per *person* and
    /// follows them to the iPad. Never gates anything, and is never shown as a
    /// score — see `CoachProgress`'s header for the three readers it has.
    private(set) var coachProgress: CoachProgress {
        didSet { coachProgressStore.wrappedValue = coachProgress }
    }
    /// PRD-26's replays, keyed by board id. Written only by `mintReplay` and
    /// pruned with the library — a replay is about a board, so when the board
    /// goes it has nothing left to be about. (The opposite call from
    /// `coachProgress`, which is about the *person* and must outlive every
    /// board they played.)
    private(set) var replays: ReplayVault {
        didSet { replaysStore.wrappedValue = replays }
    }
    /// PRD-27's duels, keyed by board.
    private(set) var duels: DuelLedger {
        didSet { duelsStore.wrappedValue = duels }
    }
    /// PRD-31's handwriting: one accepted glyph per digit, the specimen every
    /// pencil mark on the board is drawn with.
    ///
    /// A property of the *person*, like `coachProgress` and unlike `replays` —
    /// so it is cloud-synced, and so writing a 4 on the iPad makes the phone's
    /// notes wear it too. Its own top-level key rather than a field on
    /// `nine.prefs`, for the reason every blob added since 1.1 has been: an
    /// older build's next write erases a field it has no property for
    /// (EXECUTING-A-PRD §2). Nine glyphs pack to well under 4 KB, measured by
    /// `testAFullHandFitsTheKeyValueBudget`, which is what makes KVS the right
    /// home rather than a CloudKit record.
    private(set) var hand: HandGlyphs {
        didSet { handStore.wrappedValue = hand }
    }

    /// Adopt this ink as the player's glyph for `digit`. Called only when the
    /// reading cleared `DigitHand.adoptScore`, which is the stricter of the two
    /// bars — see `HandGlyphs`.
    func learnHand(_ glyph: InkGlyph, as digit: Int) {
        var updated = hand
        updated.learn(glyph, as: digit)
        guard updated != hand else { return }
        hand = updated
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

    // MARK: - Channels (PRD-24)

    /// Every channel's own streak and solves. Classic's are `streak` and
    /// `history` above and stay there — see `ChannelLedger`, where the fact that
    /// this type cannot hold a classic slot is the whole "the classic streak is
    /// never diluted" proof.
    private(set) var channels: ChannelLedger {
        didSet { channelsStore.wrappedValue = channels }
    }

    /// Each variant board's rules, keyed by library entry. Its own blob for
    /// `nine.replays`'s reason, and never a field on `LibraryEntry`.
    private(set) var channelRules: ChannelRuleStore {
        didSet { channelRulesStore.wrappedValue = channelRules }
    }

    /// The shelf page the player is on.
    ///
    /// **Deliberately not persisted, and it is a calm decision rather than a
    /// saving.** Coming back to the app should put you where the app is, which is
    /// Classic; a shelf that remembers you were on Killer last Tuesday greets a
    /// player who opened the app to do the daily with a page they have to turn
    /// back. It also means the channels can never strand someone: there is no
    /// state to be stuck in.
    var channel: Channel = .classic

    /// Turn the shelf's page. Bounded rather than wrapping: a pager that wraps
    /// has no edges, and the edges are what tell the player there are three of
    /// these and they are at one end.
    func turnShelf(by pages: Int) {
        let all = Channel.allCases
        guard let current = all.firstIndex(of: channel) else { return }
        let next = min(all.count - 1, max(0, current + pages))
        channel = all[next]
    }

    /// Independent reasons the clock is not allowed to run right now (Task 4).
    /// `.scene` is the app not being looked at at all (backgrounded/inactive);
    /// `.sheet` is a board-covering overlay up while the app IS foreground
    /// (prefs, the stats drawer, a coach hint, a why-chain). A `Set` rather
    /// than a bool because the two are independent and can overlap — the app
    /// can be backgrounded while the prefs sheet is showing underneath, and
    /// the clock must stay held until BOTH clear, not whichever cleared last.
    enum ClockHold { case scene, sheet }
    private var clockHolds: Set<ClockHold> = []
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
    /// The Focus filter (PRD-33). Local, never `cloudSynced` — see `focus`.
    @ObservationIgnored private let focusStore =
        CouchStored(wrappedValue: QuietFocus.none, QuietFocus.storeKey)
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
    /// PRD-25's progress blob. Cloud-synced, unlike `nine.coach`: which
    /// techniques you have met is a property of *you*, and meeting the X-wing
    /// on the phone should not leave the iPad thinking you never have.
    /// Its own key rather than a field on `nine.coach`, because that ledger is
    /// pruned to the live library on every write — a technique learned six
    /// months ago must not be forgotten when the board it was learned on is
    /// deleted (EXECUTING-A-PRD §2's placement rule, one layer up).
    @ObservationIgnored private let coachProgressStore =
        CouchStored(wrappedValue: CoachProgress(), "nine.coachProgress", cloudSynced: true)
    /// PRD-26's replays. Its own blob, **local-only**, and both halves are
    /// decisions.
    ///
    /// Its own blob rather than a field on `LibraryEntry`, for the measurement
    /// that killed field-level preservation (1515 ms against a 49 ms baseline).
    /// Local-only rather than KVS-synced because a full vault is ~60 × 1.5 KB
    /// and iCloud key-value storage is 1 MB *total* — the same arithmetic that
    /// keeps `nine.library` off it. The cloud copy is a CloudKit record in the
    /// `NineLibrary` zone, beside the board it belongs to.
    @ObservationIgnored private let replaysStore =
        CouchStored(wrappedValue: ReplayVault(), "nine.replays")
    /// PRD-27's duel attribution: which seat placed which digit, as a list of
    /// turn boundaries into each board's move log.
    ///
    /// Its own blob, and a **sibling top-level key** rather than a field on
    /// `LibraryEntry` — EXECUTING-A-PRD §2's rule satisfied structurally, since
    /// an older build never reads or writes this key and so can never erase it
    /// on its next autosave. Local-only, like `nine.replays` and for the same
    /// reason plus one more: a duel is a couch, not a cloud, and carrying
    /// attribution across devices would need a CloudKit record type and a
    /// production schema deploy (PRD-27 §12).
    @ObservationIgnored private let duelsStore =
        CouchStored(wrappedValue: DuelLedger(), "nine.duel")
    /// PRD-31's handwriting specimens. Cloud-synced for `coachProgress`'s
    /// reason: your hand is yours, not the device's.
    @ObservationIgnored private let handStore =
        CouchStored(wrappedValue: HandGlyphs(), "nine.hand", cloudSynced: true)
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
    /// PRD-24's per-channel streaks and stats slices. Cloud-synced beside
    /// `nine.streak` and `nine.history`, for their reason: a streak the player
    /// earned is a streak on every device.
    ///
    /// A **new** blob rather than a widening of `nine.streak` or `nine.history`,
    /// and that placement is the whole safety argument. Those two are already on
    /// TestFlight with decoders that predate channels, and both are `cloudSynced`
    /// — so a mixed-version player's two devices fight over them under
    /// last-writer-wins. `nine.history` needed the `band`-sibling wire bridge for
    /// exactly one added `Difficulty` case. A key no shipped build has ever
    /// written needs no bridge at all: an old build does not read it, does not
    /// write it, and cannot strip it.
    ///
    /// Its KVS cost is bounded by `ChannelLedger.historyCapacity` (200 per
    /// channel, ~44 KB for both) rather than by hope — the store gives the whole
    /// app 1 MB.
    @ObservationIgnored private let channelsStore =
        CouchStored(wrappedValue: ChannelLedger(), "nine.channels", cloudSynced: true)
    /// PRD-24's per-board variant rules. Its own blob, **local-only**, both for
    /// `nine.replays`'s reasons: never a field on `LibraryEntry` (1515 ms against
    /// a 49 ms baseline), and off KVS because it rides with `nine.library`, which
    /// is also local.
    ///
    /// The consequence is that a variant board does not reach another device yet.
    /// `LibraryCloudStore` syncs per-entry CloudKit records, so carrying the rules
    /// across needs a new record type and a production schema deploy — the human
    /// gate PRD-26's replays also had. Deferred rather than half-built, and
    /// `ChannelRules.isPlayable` is false for a board whose rules did not arrive,
    /// so the failure mode is a board that will not open rather than one opened
    /// under the wrong rules.
    @ObservationIgnored private let channelRulesStore =
        CouchStored(wrappedValue: ChannelRuleStore(), "nine.channelRules")
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
    /// Menu-driven request to open the Technique School (PRD-25). `SchoolView` has
    /// compiled for macOS since PRD-25 — its fence is `#if os(iOS) || os(macOS)` —
    /// and has been unreachable there the whole time, because nothing presented
    /// it. The cheapest patch in the repo, and PRD-33's menu bar is where it lands.
    var macShowSchool = false

    /// The board the Mac window is showing, remembered across launches (PRD-33).
    ///
    /// `resumeOnLaunch` already returns you to `mostRecentInProgress`, which is
    /// *usually* the board you were on and is not the same claim: open an older
    /// board out of the Boards window, quit, and the app comes back to a different
    /// puzzle. This remembers the one the window actually had.
    ///
    /// Its own tiny local blob rather than `@SceneStorage`, because the restore has
    /// to happen inside `AppModel.init` — before any view exists to read scene
    /// storage — and rather than a field on `nine.prefs` for EXECUTING-A-PRD §2's
    /// reason. Local and never `cloudSynced`: which window showed what is a fact
    /// about this Mac.
    @ObservationIgnored private let macWindowBoardStore =
        CouchStored(wrappedValue: "", "nine.mac.windowBoard")

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
        focus = focusStore.wrappedValue
        streak = streakStore.wrappedValue
        graceSeenDay = graceSeenStore.wrappedValue
        library = libraryStore.wrappedValue
        helpSeen = helpSeenStore.wrappedValue
        welcomeSeen = welcomeSeenStore.wrappedValue
        tips = tipsStore.wrappedValue
        coach = coachStore.wrappedValue
        coachProgress = coachProgressStore.wrappedValue
        replays = replaysStore.wrappedValue
        duels = duelsStore.wrappedValue
        hand = handStore.wrappedValue
        archive = archiveStore.wrappedValue
        history = historyStore.wrappedValue
        channels = channelsStore.wrappedValue
        channelRules = channelRulesStore.wrappedValue
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
        //
        // PRD-33 adds the window's own memory in front of it: the board this
        // window was showing, if it is still in progress, and `mostRecentInProgress`
        // otherwise. The order matters and the fallback matters — a remembered id
        // that has since been solved, archived, pruned or lost to a cloud merge
        // must not leave the Mac on the shelf when there is a board to return to.
        if prefs.resumeOnLaunch {
            let remembered = UUID(uuidString: macWindowBoardStore.wrappedValue)
                .flatMap { library.entry(id: $0) }
                .flatMap { $0.status == .inProgress ? $0 : nil }
            if let entry = remembered ?? library.mostRecentInProgress {
                startEntry(entry.id)
            }
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

    /// Whether *this binary* is allowed to build a `CKContainer`.
    ///
    /// **The bug this fixes has been recorded as a standing gap since PRD-20 and
    /// re-quoted by PRD-31: "a locally-built Nine cannot launch on macOS at all on
    /// an iCloud-signed-in host, trapping in `CKContainer.init` because the
    /// entitlement-free build passes an account check it should not."** PRD-33's
    /// whole Mac half is undriveable until it is fixed, so it is fixed here.
    ///
    /// The old guard asked the *operating system* whether there is an iCloud
    /// account (`ubiquityIdentityToken`), which is true on any signed-in Mac
    /// whether or not the binary in front of it carries the CloudKit entitlement.
    /// `CKContainer(identifier:)` then traps — not throws, traps — because an
    /// unentitled container request is a programmer error as far as CloudKit is
    /// concerned. The right question is about the binary, so this asks the binary:
    /// its own code signature, through `SecTask`.
    ///
    /// macOS only, and the scope is honest rather than lazy: `SecTask` is not in
    /// the public iOS or tvOS SDK, and the trap has only ever been observed on
    /// macOS, because it needs the combination of a signed-in host and a build
    /// signed without the entitlement — which on iOS and tvOS means a simulator,
    /// where there is no iCloud account to find. On those platforms the account
    /// check alone remains correct and this returns true unchanged.
    private var mayBuildCloudContainer: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        // Either key is enough to prove the signature carries CloudKit; asking
        // for both would fail a future entitlement file that drops one.
        for key in ["com.apple.developer.icloud-services",
                    "com.apple.developer.icloud-container-identifiers"] {
            if SecTaskCopyValueForEntitlement(task, key as CFString, nil) != nil {
                return true
            }
        }
        return false
        #else
        return true
        #endif
    }

    /// Construct and start the cloud store, but only when an iCloud account is
    /// signed in **and** this binary is entitled to reach CloudKit. Idempotent —
    /// safe to call repeatedly (e.g. on foreground).
    private func setUpCloudSyncIfAvailable() {
        guard cloudStore == nil, mayBuildCloudContainer,
              FileManager.default.ubiquityIdentityToken != nil else { return }
        let store = LibraryCloudStore()
        store.onRemoteEntry = { [weak self] synced in self?.applyRemoteEntry(synced) }
        store.onRemoteReplay = { [weak self] replay in self?.applyRemoteReplay(replay) }
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

    var todaySolved: Bool { hasSolved(day: todayOrdinal) }

    /// Whether a given day's daily has been finished.
    ///
    /// A thin accessor over `streak`, and it earns its line: *where a solve is
    /// recorded* is a fact about streak bookkeeping, and a caller that only wants to
    /// know whether a board is done should not have to know it. `PresenceBridge`
    /// (PRD-30) is the caller that made this obvious — it asks the question for an
    /// injected date rather than for "now", so `todaySolved` was not enough, and
    /// `QuietPresenceSealTests` forbids a quiet surface from naming the streak at
    /// all. Both wanted the same thing.
    func hasSolved(day: Int) -> Bool { streak.hasCompleted(day: day) }

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

    // MARK: - Derived, per channel (PRD-24)

    /// Every accessor below is the classic one with a channel argument, reading
    /// the channel's own `StreakState` and `SolveHistory` instead of the top-level
    /// ones. None of them re-derives anything: per-channel grace is PRD-13's rule
    /// and per-channel stats are `SolveHistory`'s aggregation, both inherited.
    ///
    /// They take `Channel.Ledgered` rather than `Channel`, so a caller cannot ask
    /// them about classic — the answers for classic are `displayedStreak`,
    /// `todaySolved` and `history`, which read the blobs classic has always used.

    func displayedStreak(on channel: Channel.Ledgered) -> Int {
        channels.displayedStreak(for: channel, today: todayOrdinal)
    }

    /// A channel streak standing on a grace bridge, so its chip wears a shield.
    /// Guarded on the displayed value as well as the state, for `streakHeld`'s
    /// reason: a lapsed bridge must not put a shield on a chip nobody draws.
    func streakHeld(on channel: Channel.Ledgered) -> Bool {
        displayedStreak(on: channel) > 0 && channels.state(for: channel).streak.standsOnGrace
    }

    /// Whether this channel's daily for `day` is done. One per day per channel.
    func hasSolved(_ channel: Channel.Ledgered, day: Int) -> Bool {
        channels.hasSolved(channel, day: day)
    }

    func todaySolved(on channel: Channel.Ledgered) -> Bool {
        hasSolved(channel, day: todayOrdinal)
    }

    /// This channel's stats slice.
    func history(on channel: Channel.Ledgered) -> SolveHistory {
        channels.state(for: channel).history
    }

    /// This channel's in-progress daily for today, if there is one.
    func savedDaily(on channel: Channel.Ledgered) -> LibraryEntry? {
        library.partials.first {
            if case .channel(let c, _, let day) = $0.kind {
                return c == channel.channel && day == todayOrdinal
            }
            return false
        }
    }

    /// This channel's in-progress free-play boards, newest first.
    func partials(on channel: Channel.Ledgered) -> [LibraryEntry] {
        library.partials.filter {
            if case .channel(let c, _, let day) = $0.kind {
                return c == channel.channel && day == nil
            }
            return false
        }
    }

    /// The variant rules for the board on screen, or nil when it is classic.
    ///
    /// This is what `BoardView` draws cages and tubes from, and what
    /// `GameScreen` gates on: a `.channel` board whose rules are missing or
    /// unenforceable returns nil here, and a nil that reaches the board means the
    /// board renders as classic. That would be wrong, so `openChannelBoard`
    /// refuses to *start* such an entry — the check is at the door rather than at
    /// the renderer, because by the time the renderer sees it there is nothing
    /// good left to do.
    var currentRules: ChannelRules? {
        guard case .channel? = kind, let id = currentEntryID else { return nil }
        guard let rules = channelRules.rules(for: id), rules.isPlayable else { return nil }
        return rules
    }

    /// The channel the board on screen belongs to — `.classic` for a classic
    /// board, which is what every pre-PRD-24 surface keeps getting.
    var currentChannel: Channel {
        if case .channel(let c, _, _)? = kind { return c }
        return .classic
    }

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

    // MARK: - Pass the Remote (PRD-27)

    /// The duel this board belongs to, or nil — which is every board on every
    /// surface but the Apple TV and the drafting table.
    var duelState: DuelState? {
        guard let id = currentEntryID else { return nil }
        return duels[id]
    }

    var isDuel: Bool { duelState != nil }

    /// Park a duel until its board exists.
    ///
    /// `startFree` composes on a detached task, so `currentEntryID` is seconds
    /// away when `startDuel` returns. Session-scoped and deliberately not
    /// persisted: a duel that never got a board is not a duel.
    @ObservationIgnored private var pendingDuel: DuelState?

    /// Start a two-player board.
    ///
    /// **Always a fresh free board and never the daily.** Two people on a sofa
    /// cannot spend the streak of whoever owns the device, and the way that is
    /// guaranteed is that there is no door from here to `.daily` at all
    /// (PRD-27 §7).
    func startDuel(difficulty: Difficulty, turnLength: DuelTurnLength, isLight: Bool) {
        pendingDuel = DuelState(
            accent: prefs.accent.rawValue, isLight: isLight, turnLength: turnLength
        )
        startFree(difficulty)
    }

    /// Adopt a parked duel once its entry exists. Called from `startEntry`,
    /// which is the single funnel every board-opening path goes through.
    private func adoptPendingDuelIfAny() {
        guard let pending = pendingDuel, let id = currentEntryID else { return }
        pendingDuel = nil
        var ledger = duels
        ledger.set(pending, for: id)
        duels = ledger
    }

    /// Open a turn for `player`.
    ///
    /// The caller has already applied the quiet correction, and that ordering is
    /// load-bearing: an erase logged *after* this index is taken lands inside the
    /// incoming player's range and is credited to the wrong hand (PRD-27 §5).
    func recordDuelTurn(player: Int, startedAt: TimeInterval) {
        guard let id = currentEntryID, var state = duels[id] else { return }
        state.beginTurn(
            player: player, firstMoveIndex: game?.moveLog.count ?? 0, startedAt: startedAt
        )
        var ledger = duels
        ledger.set(state, for: id)
        duels = ledger
    }

    /// Erase every wrong digit on the board, silently. Returns how many.
    ///
    /// Through `NineGame.erase`, so each correction is an ordinary logged move
    /// inside the outgoing player's range rather than a mutation nothing can
    /// see or replay. No haptic, no toast, no announcement, and no coral before
    /// or after — the whole point is that nobody is told off in front of the
    /// other player (PRD-27 §5).
    @discardableResult
    func clearDuelErrors() -> Int {
        guard var g = game else { return 0 }
        let wrong = g.errorCells
        guard !wrong.isEmpty else { return 0 }
        let stamp = moveStamp(g)
        var cleared = 0
        for cell in wrong where g.erase(at: cell, autoNotes: false, elapsed: stamp) {
            cleared += 1
        }
        guard cleared > 0 else { return 0 }
        game = g
        persistProgress()
        return cleared
    }

    /// The debrief's credits for a board, or nil if it was not a duel.
    func duelCredits(for boardID: UUID) -> DuelCredits? {
        guard let state = duels[boardID], let entry = library.entry(id: boardID) else { return nil }
        // The replay's log where there is one, the live entry's otherwise —
        // the same two-source rule `debrief(for:)` already follows, and the
        // reason a board solved before its replay was minted still credits.
        let moves = replays.replay(for: boardID)?.moves ?? entry.game.moveLog
        return DuelCredits(state: state, moves: moves, solution: entry.game.puzzle.solution.cells)
    }

    /// The two players' names — their tints' names, which cost nothing to
    /// translate because `AccentChoice.title` already goes through the catalog.
    func duelNames(for boardID: UUID) -> [String] {
        guard let state = duels[boardID] else { return [] }
        return state.accents.map { AccentChoice(rawValue: $0)?.title ?? "" }
    }

    // MARK: - Starting channel games (PRD-24)

    /// Open a channel's daily: resume today's in-progress board, or compose it.
    ///
    /// Mirrors `openToday` and drops the two things that are classic-only. No
    /// widget ingestion — `SharedDailyBoard` is a single slot keyed on the day
    /// ordinal alone with no channel axis, so a channel daily is structurally
    /// invisible to the widget and needs no merge. And no `PhoneWatchLink`
    /// publish: the watch is classic-only, which `VariantInputSealTests` enforces
    /// from the source side.
    func openChannelToday(_ channel: Channel.Ledgered) {
        let day = todayOrdinal
        if let entry = savedDaily(on: channel) {
            openChannelBoard(entry.id)
        } else {
            composeChannel(
                channel: channel, tier: VariantChannel.dailyTier, day: day,
                seed: DailySeed.seed(forDayOrdinal: day))
        }
    }

    /// Start a fresh free-play board on a channel at a chosen tier.
    func startChannelFree(_ channel: Channel.Ledgered, tier: VariantTier) {
        composeChannel(
            channel: channel, tier: tier, day: nil,
            seed: .random(in: UInt64.min...UInt64.max))
    }

    /// Resume a stored channel board, **refusing the ones whose rules this build
    /// cannot enforce.**
    ///
    /// This is the door `currentRules` documents. A `.channel` entry with missing,
    /// unreadable or future rules must not open, because a board rendered without
    /// its cages is not a harder board — it is a board whose correct entries get
    /// marked as errors, since `NineGame.isError` compares against a solution that
    /// is only *the* solution under the rules.
    ///
    /// Returns whether it opened, so the caller can say something rather than
    /// present a dead tap. Silence here would be the worst of the three options.
    @discardableResult
    func openChannelBoard(_ id: UUID) -> Bool {
        guard let entry = library.entry(id: id),
              case .channel = entry.kind,
              let rules = channelRules.rules(for: id), rules.isPlayable
        else { return false }
        startEntry(id)
        return true
    }

    /// Compose a variant board and adopt it.
    ///
    /// The interesting three lines are the ones that turn a `VariantPuzzle` into a
    /// `NineGame`. A variant board's play state — entries, pencil marks, undo
    /// stack, timer, move log — is *the classic play state*, which is PRD-24 §1's
    /// claim restated as a data structure and what makes the rose, the coach, the
    /// replay, the debrief and the share card work on a thermo board with no new
    /// code at all.
    ///
    /// `NineGame` needs a `GeneratedPuzzle`, so the variant board lends its grid,
    /// solution, seed and trace to one, with the tier mapped onto the `Difficulty`
    /// the wire wants. That mapping is lossy in one direction only and harmlessly:
    /// the authoritative tier lives in `GameKind.channel` and in `ChannelRules`,
    /// both of which are read in preference to it, and `Difficulty` is what
    /// `SolveScore` and the stats slice need in order to work unchanged.
    ///
    /// **Nil compose is a first-class outcome and it is handled visibly.** A tier
    /// that exhausted its attempt budget clears `composing` and does nothing else,
    /// so the shelf card returns to its resting state rather than spinning
    /// forever. Both shipped rulesets compose 200/200 per tier in Release, so this
    /// is the branch that should never run — which is exactly why it must not be a
    /// `try!`.
    private func composeChannel(
        channel: Channel.Ledgered, tier: VariantTier, day: Int?, seed: UInt64
    ) {
        guard composing == nil else { return }
        let kind = GameKind.channel(channel: channel.channel, tier: tier, day: day)
        composing = kind
        Task.detached(priority: .userInitiated) {
            // Pure, Sendable, deterministic — safe off the main actor, exactly as
            // classic composition is.
            let composed = VariantChannel.compose(
                seed: seed, variant: channel.variant, tier: tier)
            await MainActor.run {
                self.composing = nil
                guard let composed else { return }
                let now = Date()
                let newGame = NineGame(puzzle: composed.asGeneratedPuzzle)
                let id = self.library.create(kind: kind, game: newGame, now: now)
                // The rules before the board goes on screen, so nothing can ever
                // observe a `.channel` entry that has none.
                var rules = self.channelRules
                rules.store(ChannelRules(composed), for: id)
                self.channelRules = rules
                self.startEntry(id)
                self.persistProgress()
                try? self.channelRulesStore.flushNow()
            }
        }
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
        // A deleted board takes its replay with it, here rather than at the
        // next mint: "delete this board" has to mean the memory is gone now,
        // not eventually. `remove` and not `prune` — see `ReplayVault.remove`;
        // this is the one call that can empty the library, which is exactly the
        // input `prune` refuses.
        var vault = replays
        vault.remove(id)
        if vault != replays {
            replays = vault
            try? replaysStore.flushNow()
        }
        // …and its duel, through the same door and for the same reason.
        var duelLedger = duels
        duelLedger.remove(id)
        if duelLedger != duels {
            duels = duelLedger
            try? duelsStore.flushNow()
        }
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
        // Belt-and-braces: the library decode seam already closes a stale
        // open run, but an entry can also go stale purely in memory (loaded
        // once, left alone while another entry played) without ever passing
        // back through decode. Cap it here too before trusting `start`.
        g.timer.closeOpenRun(notLaterThan: entry.updatedAt)
        // The gate is load-bearing here, not decorative. The synchronous
        // callers (`continueSaved`, `resumeEntry`, launch's resume-on-launch)
        // do all run with `clockHolds` empty — but `compose()` reaches this
        // from a `Task.detached` → `MainActor.run` continuation (:903) that
        // lands seconds after the tap, and `startFree`, `openToday`'s compose
        // branch and `openArchiveDay`'s compose branch all route through it.
        // Background the app while a board is composing and `clockHolds` is
        // `[.scene]` by the time this line runs: the new board must land
        // paused, and `.active`'s `releaseClock` is what starts it. Without
        // this gate a board would begin timing itself unwatched.
        startClockIfUnheld(&g)
        self.game = g
        self.kind = entry.kind
        self.solvedAt = nil
        self.lastPlacedCell = nil
        self.screen = .game
        // PRD-27: a duel started before its board existed is adopted here,
        // because this is the single funnel every opening path goes through.
        adoptPendingDuelIfAny()
        #if os(macOS)
        // Which board this window is showing (PRD-33). Written here rather than in
        // each of the six callers, because this is the single funnel every one of
        // them goes through.
        macWindowBoardStore.wrappedValue = id.uuidString
        #endif
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
                case .channel:
                    // Unreachable: this is classic composition and its callers all
                    // pass `.daily` or `.free`. A channel board is composed by
                    // `composeChannel`, which is a different function because it
                    // calls a different generator and has to store rules alongside
                    // the entry. Asserted rather than silently created, because a
                    // `.channel` entry arriving here would be a board with no
                    // rules — the exact state `ChannelRules.isPlayable` exists to
                    // refuse, reached from the one direction that could bypass it.
                    assertionFailure("a channel board must go through composeChannel")
                    return
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

    // MARK: - Why must this be a seven? (PRD-25)

    /// The chain that forces one cell, or why the board declines to say.
    ///
    /// Same two rules as `requestCoachAdvice`, for the same reasons: capped at
    /// the board's own difficulty ceiling so a Gentle board is never lectured
    /// about swordfish, and fed the **player's** grid rather than the puzzle's,
    /// so it reasons about the position actually on screen — including the
    /// digits they have placed, right or wrong.
    ///
    /// Not counted as a hint. `CoachLedger.hints` feeds one line of the stats
    /// drawer, and a derivation is a different act from being handed the next
    /// move — folding the two together would make that line mean two things.
    /// What it *does* record is that the technique has been met.
    func requestDerivation(forCell cell: Int) -> Result<Derivation, DerivationRefusal>? {
        guard let game, solvedAt == nil else { return nil }
        let grid = SudokuGrid(cells: (0..<81).map { game.entry(at: $0) })
        let outcome = LogicSolver.derivation(
            forCell: cell, in: grid,
            allowed: game.puzzle.difficulty.allowedTechniques)
        if case .success(let derivation) = outcome {
            noteTechniquesExplained(derivation.narrated.map(\.coach.step.technique))
        }
        return outcome
    }

    /// Remember that these techniques have been narrated. Quiet by
    /// construction: nothing reads the count as a threshold, and the only
    /// effects are which lesson School floats to the top and one sentence in
    /// the stats drawer.
    func noteTechniquesExplained(_ techniques: [Technique]) {
        guard !techniques.isEmpty else { return }
        var progress = coachProgress
        for technique in techniques { progress.recordExplanation(of: technique) }
        coachProgress = progress
    }

    func noteLessonFinished(_ technique: Technique) {
        var progress = coachProgress
        progress.recordLessonFinished(technique)
        coachProgress = progress
    }

    /// How many of the techniques Nine can teach this player has met, and how
    /// many there are. The stats drawer's one sentence; nothing else reads it.
    var techniquesMet: (met: Int, total: Int) {
        let taught = TechniqueSchool.lessons.map(\.technique)
        return (coachProgress.metCount(of: taught), taught.count)
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

    /// Seconds this board's timer has run, which is what `LoggedMove.at`
    /// means (PRD-26 §3.1).
    ///
    /// **The app layer reads the clock and the engine does not**, which is the
    /// same division `ElapsedTimer` has had since 1.0 — every `Date` in the
    /// Engine arrives as an argument. Elapsed rather than wall-clock, so a
    /// replay is a timeline and not a diary: nothing in a `SolveReplay` says
    /// what hour of the night anybody was playing.
    private func moveStamp(_ game: NineGame) -> TimeInterval {
        game.timer.elapsed(at: Date())
    }

    func place(_ digit: Int, at cell: Int) {
        guard solvedAt == nil, var g = game else { return }
        guard g.place(digit, at: cell, autoNotes: autoNotes, elapsed: moveStamp(g)) else { return }
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
        guard g.togglePencil(digit, at: cell, elapsed: moveStamp(g)) else { return }
        game = g
        persistProgress()
    }

    /// Clear a user entry (Delete / 0 on the Mac keyboard, PRD-4 §2.2).
    /// No-op on givens and empty cells; never completes a board.
    @discardableResult
    func erase(at cell: Int) -> Bool {
        guard solvedAt == nil, var g = game else { return false }
        guard g.erase(at: cell, autoNotes: autoNotes, elapsed: moveStamp(g)) else { return false }
        game = g
        persistProgress()
        return true
    }

    @discardableResult
    func undoMove() -> NineMove? {
        guard solvedAt == nil, var g = game else { return nil }
        guard let move = g.undo(elapsed: moveStamp(g)) else { return nil }
        game = g
        // Undoing the bulk fill without clearing the flag would let the very
        // next placement refill exactly what the player just took back.
        if move.isBulkNotes, let id = currentEntryID {
            writeCoach { $0.setAutoNotes(false, for: id.uuidString) }
        }
        persistProgress()
        return move
    }

    // MARK: - Clock holds (Task 4)

    /// Pause the clock for `reason`. Only the FIRST hold to land actually does
    /// anything to the timer — a second, independent reason piling on top of
    /// one already held changes nothing observable, which is the whole reason
    /// this is a set and not a bool.
    ///
    /// The pause is always persisted, but only a `.scene` hold *flushes*. The
    /// flush exists for one reason — a backgrounded process can be killed by
    /// the OS with no further chance to write, so leaving the pause to the
    /// ordinary per-move `persistProgress()` would lose exactly what this
    /// method records. A `.sheet` hold has no such deadline: the app is
    /// foreground and alive, and the next move (or the eventual background,
    /// which does flush) writes it through. Flushing there would put a full
    /// `BoardLibrary` encode + write, a KVS flush, a CloudKit push and
    /// `WidgetCenter.reloadAllTimelines()` on the main actor *inside* the
    /// drawer's opening animation — a dropped frame on a user-visible
    /// animation, paid on every prefs open and every drawer pull. Note the
    /// flush is keyed on the REASON, not on whether this call did the pausing:
    /// see the comment in the body for the sheet-then-background pair that
    /// would otherwise never reach disk.
    ///
    /// Gated on `screen == .game` (mirroring `refreshOnScreenBoardAfterMerge`'s
    /// guard): the app can background while sitting on Home with the last
    /// board already paused and non-nil, and re-pausing/re-persisting THAT
    /// board on every background would bump its `updatedAt` — and so its
    /// tracker position — for a board nobody is playing. The insert happens
    /// before the guard, so set membership stays symmetric with `releaseClock`
    /// whether or not the guard lets the timer work through.
    func holdClock(_ reason: ClockHold) {
        let firstHold = clockHolds.isEmpty
        clockHolds.insert(reason)
        if firstHold, screen == .game, solvedAt == nil, var g = game {
            g.timer.pause(at: Date())
            game = g
            persistProgress()
        }
        // Deliberately outside the `firstHold` block, and after it rather than
        // hoisted above: every `.scene` hold must flush whether or not THIS
        // call is the one that paused, but a flush that ran first would write
        // the pre-pause state and miss exactly what it is here to save.
        //
        // The case that needs it: a sheet is already up (`.sheet` paused and
        // persisted, correctly not flushing inside an animation), then the app
        // backgrounds. That `holdClock(.scene)` is not the first hold, so the
        // block above no-ops — and gating the flush on `firstHold` too would
        // mean the pause never reached disk before the OS could kill us.
        if reason == .scene {
            try? libraryStore.flushNow()
            try? streakStore.flushNow()
        }
    }

    /// Release `reason`. The clock resumes only once every hold has cleared —
    /// releasing one of two simultaneous holds must not restart it out from
    /// under the other — and only onto a board actually on screen mid-play;
    /// a hold outliving the board it was raised for (a solve landing while
    /// backgrounded, say) must not resurrect a finished or departed game.
    func releaseClock(_ reason: ClockHold) {
        clockHolds.remove(reason)
        guard clockHolds.isEmpty, screen == .game, solvedAt == nil, var g = game else { return }
        g.timer.start(at: Date())
        game = g
    }

    /// The one gate every resume path funnels through instead of calling
    /// `ElapsedTimer.start` directly. `startEntry`, `refreshOnScreenBoardAfterMerge`
    /// and `ingestSharedDailyBoard` all land a board on screen and want its
    /// clock ticking — but if a hold is currently up (app backgrounded, a
    /// board-covering overlay showing) starting it here would silently
    /// override that hold; only the matching `releaseClock` may resume play
    /// once the surface is actually being looked at again. Leaving the timer
    /// paused (rather than not swapping the board in at all) is correct: the
    /// player still sees the right board the instant the hold lifts.
    private func startClockIfUnheld(_ g: inout NineGame) {
        guard clockHolds.isEmpty else { return }
        g.timer.start(at: Date())
    }

    func goHome() {
        if solvedAt == nil, var g = game {
            g.timer.pause(at: Date())
            game = g
            persistProgress()
        }
        // A hold is scoped to the board it was raised over — a stale one
        // (say, the prefs sheet's `.sheet` hold, if some future overlay path
        // ever left it set) must never survive the trip to Home and wedge the
        // NEXT board's clock off before it has even started.
        clockHolds.removeAll()
        try? libraryStore.flushNow()
        try? streakStore.flushNow()
        // Keep `game`/`solvedAt` untouched so the departing GameScreen stays
        // visually stable through the crossfade; the next start replaces them.
        screen = .home
        #if os(macOS)
        // Desk mode is a board posture; home always gets the full window.
        windowMode = .full
        // Going to the shelf is a decision about where you want to be, so the
        // window forgets its board (PRD-33). Without this, quitting from the shelf
        // and relaunching would drag you back onto a board you had just left —
        // which is `resumeOnLaunch`'s job to decide, not a stale id's.
        macWindowBoardStore.wrappedValue = ""
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
        // Same reasoning as `goHome`: a hold is scoped to one board's clock,
        // and this board's clock is now stopped for good (solved). Clearing
        // here rather than trusting every hold's own release path means a
        // solve landing mid-hold (backgrounded, or under an overlay) can never
        // leave a stale hold to wedge the NEXT board started after this one.
        clockHolds.removeAll()
        // **A duel solve is nobody's solve** (PRD-27 §7). Two people filled that
        // board in, so every ledger that records *your* progress is skipped: the
        // classic streak, the classic history, the archive, the channel ledger
        // and every Game Center submission.
        //
        // What still happens is everything that belongs to the *board* rather
        // than to a player — the library marks it solved and the replay is
        // minted, because a duel has a comet and a debrief and that is the whole
        // of §10.
        let isDuel = self.isDuel
        var isDaily = false
        if !isDuel, case .daily(let day)? = kind {
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
        // A channel board's streak and solve log go to `nine.channels` and
        // nowhere else (PRD-24). Resolved before the record is built because the
        // channel's own streak is what its points are scored against.
        var channelSlot: Channel.Ledgered?
        var channelDay: Int?
        if !isDuel, case .channel(let c, _, let day)? = kind, let slot = c.ledgered {
            channelSlot = slot
            channelDay = day
            isDaily = day != nil
        }

        let difficulty: Difficulty
        switch kind {
        case .free(let d)?: difficulty = d
        case .channel(_, let tier, _)?: difficulty = tier.wireDifficulty
        default: difficulty = .steady // the daily composes at steady
        }
        // The streak the points are scored against is the *board's* channel's, so
        // a first-ever killer solve is not paid a bonus earned on classic.
        let scoringStreak = channelSlot.map { channels.state(for: $0).streak.current }
            ?? streak.current
        let record = SolveRecord(
            date: now,
            difficulty: difficulty,
            isDaily: isDaily,
            seconds: g.timer.elapsed(at: now),
            points: SolveScore.points(
                difficulty: difficulty, isDaily: isDaily,
                streak: scoringStreak, seconds: g.timer.elapsed(at: now)
            ),
            errors: g.errorCount
        )
        if let channelSlot {
            // The channel's streak and its history move together or not at all —
            // `ChannelLedger.record` is the only door, and it takes a type that
            // cannot name classic. `nine.streak`, `nine.history` and
            // `nine.archive` are untouched on this path, which is what "the
            // classic streak is never diluted" means in practice.
            var ledger = channels
            if let channelDay {
                // `openedOn`-equivalent provenance: a channel board created on an
                // earlier day must not extend today's streak. There is no channel
                // archive yet, so the created-on day is the only past a channel
                // board can have.
                let opened = currentEntryID
                    .flatMap { library.entry(id: $0) }
                    .map { DailySeed.dayOrdinal(for: $0.createdAt) } ?? channelDay
                ledger.record(record, on: channelSlot, day: channelDay, openedOn: opened)
            } else {
                ledger.recordFreePlay(record, on: channelSlot)
            }
            channels = ledger
            try? channelsStore.flushNow()
        } else if !isDuel {
            history.record(record)
            try? historyStore.flushNow()
        }
        // The board is done; keep it as a "previously played" entry.
        if let id = currentEntryID {
            library.markSolved(id: id, at: now)
            if let solvedEntry = library.entry(id: id) { cloudStore?.push(solvedEntry) }
            // After `markSolved`, so the prune inside sees the library the
            // solve leaves behind rather than the one it arrived in.
            mintReplay(
                boardID: id, game: g, difficulty: difficulty, isDaily: isDaily,
                solvedAt: now, seconds: record.seconds
            )
        }
        try? libraryStore.flushNow()
        // GameKit is native on iOS, macOS and tvOS (PRD-5 §2.3 parity ledger);
        // widgets are iOS-only.
        #if os(iOS) || os(macOS) || os(tvOS)
        // A channel solve reports the channel's own history and streak to the
        // channel's own boards (PRD-24). Reading them off the ledger here rather
        // than passing the top-level pair keeps the "never diluted" rule true on
        // this surface too: the classic leaderboard cannot receive a killer score
        // because the arguments it would need are not the ones in scope.
        if let channelSlot {
            let state = channels.state(for: channelSlot)
            GameCenter.shared.reportSolve(
                record: record, history: state.history, streak: state.streak,
                channel: channelSlot)
        } else if !isDuel {
            // A duel reports nothing. A leaderboard entry naming one Apple ID
            // for a board two people filled in is the same untruth as a history
            // record, and it is the one that would be public.
            GameCenter.shared.reportSolve(record: record, history: history, streak: streak)
        }
        #endif
        #if os(iOS)
        WidgetBridge.publish(from: self)
        #endif
    }

    // MARK: - Replays (PRD-26)

    /// Mint the immutable record of a solve, and let the analysis quietly
    /// update what the coach knows.
    ///
    /// Everything here is best-effort by construction. A board with no move
    /// log — every widget solve, every watch solve, every board that arrived
    /// over CloudKit with its log stripped by `SyncedEntry` — mints nothing,
    /// and the share chip falls back to PRD-12's still card rather than
    /// vanishing (PRD-26 §2.4). Nothing on the solve path may fail because a
    /// replay could not be made.
    private func mintReplay(
        boardID: UUID, game: NineGame, difficulty: Difficulty,
        isDaily: Bool, solvedAt: Date, seconds: TimeInterval
    ) {
        guard let replay = SolveReplay(
            boardID: boardID, game: game, band: difficulty.rawValue,
            isDaily: isDaily, solvedAt: solvedAt, seconds: seconds
        ) else { return }

        var vault = replays
        vault.store(replay)
        vault.prune(to: Set(library.entries.map { $0.id.uuidString }))
        replays = vault
        try? replaysStore.flushNow()
        cloudStore?.push(replay)

        // PRD-27's duels prune on the same beat and against the same live set,
        // because a duel board is a library board and the two blobs therefore
        // have identical lifetimes.
        var duelLedger = duels
        duelLedger.prune(to: Set(library.entries.map(\.id)))
        if duelLedger != duels {
            duels = duelLedger
            try? duelsStore.flushNow()
        }

        // **A technique you found on your own board is a technique you have
        // met** (PRD-26 §3.4). This is the only writer, it sets a bool, and it
        // feeds `hasMet` — so PRD-25's one line in the stats drawer got truer
        // and no new pixel appeared anywhere.
        let analysis = ReplayAnalysis.analyze(
            puzzle: game.puzzle.puzzle.cells,
            solution: game.puzzle.solution.cells,
            moves: game.moveLog
        )
        let used = analysis.techniquesUsed
        guard !used.isEmpty else { return }
        var progress = coachProgress
        for technique in used { progress.recordUse(of: technique) }
        coachProgress = progress
    }

    /// The debrief for a solved board, or nil when it has no replay. The one
    /// door every surface goes through — the game screen's pull-up, the
    /// archive, and the Mac all ask this and none of them holds the rule.
    func debrief(for boardID: UUID) -> SolveDebrief? {
        guard let replay = replays.replay(for: boardID),
              let puzzle = replay.puzzle,
              let entry = library.entry(id: boardID) else { return nil }
        return SolveDebrief(
            replay: replay,
            analysis: ReplayAnalysis.analyze(
                puzzle: puzzle,
                solution: entry.game.puzzle.solution.cells,
                moves: replay.moves
            ),
            // PRD-27 §10. Nil on every solo board, which is what keeps every
            // other surface — the archive, the Mac, the boards sheet — printing
            // exactly what it printed before.
            duel: duelCredits(for: boardID),
            names: duelNames(for: boardID)
        )
    }

    /// The replay for the board on screen, if it has one.
    var currentReplay: SolveReplay? {
        currentEntryID.flatMap { replays.replay(for: $0) }
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

    /// A solve that happened on another device (PRD-26 §4).
    ///
    /// **`ReplayVault.store` is the whole merge rule**, and that is what
    /// immutability buys: two devices cannot disagree about a record neither of
    /// them may edit, so the newer `solvedAt` wins and there is nothing to
    /// reconcile. Contrast `LibrarySync.apply`, which needs real merge rules
    /// because a board is mutable and both sides may have moved it.
    ///
    /// Not pruned here. A replay can legitimately arrive *before* the board it
    /// belongs to — CloudKit does not order two record types against each
    /// other — and pruning on arrival would delete it for being early.
    private func applyRemoteReplay(_ replay: SolveReplay) {
        var vault = replays
        vault.store(replay)
        guard vault != replays else { return }
        replays = vault
        try? replaysStore.flushNow()
    }

    private func applyRemoteDeletion(_ id: UUID) {
        LibrarySync.applyDeletion(id: id, into: &library)
        if currentEntryID == id { currentEntryID = nil }
        var vault = replays
        vault.remove(id)
        if vault != replays {
            replays = vault
            try? replaysStore.flushNow()
        }
        try? libraryStore.flushNow()
        #if os(iOS)
        WidgetBridge.publish(from: self)
        #endif
    }

    /// If a merge changed the board on screen, swap it in calmly (keep the
    /// timer running, never yank progress out from under an active hand — only
    /// adopt a board that is further along). Re-points the persist target if a
    /// daily merge re-homed the entry's id.
    ///
    /// This fires from `syncOnForeground`/CloudKit delivery, which can land
    /// while a hold is up — the merge itself may be exactly what's happening
    /// WHILE the app is backgrounded. Swapping the board data in is still
    /// correct (the player should see the further-along board the instant
    /// they look), but starting its clock is not: `startClockIfUnheld` leaves
    /// it paused under a hold, and the matching `releaseClock` resumes it once
    /// the surface is actually being looked at again.
    private func refreshOnScreenBoardAfterMerge() {
        guard screen == .game, solvedAt == nil else { return }
        if let id = currentEntryID, library.entry(id: id) == nil,
           case .daily(let day)? = kind, let daily = library.dailyEntry(day: day) {
            currentEntryID = daily.id
        }
        guard let id = currentEntryID, let entry = library.entry(id: id) else { return }
        if let shown = game, entry.game.fillFraction > shown.fillFraction {
            var g = entry.game
            startClockIfUnheld(&g)
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
            ),
            // No NineGame in scope here — only a PendingSolve — so there is no
            // moveLog to read an error count from. Widget and watch solves
            // both route through this one path, so both record nil.
            errors: nil
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
            // Close the widget's run at the instant it solved, before ANY of
            // the three consumers below see this board.
            //
            // `BoardIntents` sets `pendingSolve` and saves without ever pausing
            // the timer, so a widget-solved board reaches us with
            // `runningSince` still set and keeps accruing wall-clock forever.
            // `markSolved`/`adoptDaily` don't touch timers (they only move
            // status/dates), so nothing downstream would have closed it either.
            //
            // `pending.solvedAt` is the honest cap and not a write- or
            // ingest-time stamp: `BoardIntents.swift:53` takes `let now =
            // Date()` at the top of `perform()`, places the winning digit at
            // :62, then stamps BOTH `PendingSolve.solvedAt` and its `seconds`
            // from that same `now` (:74-75). Capping here therefore lands the
            // timer on exactly `pending.seconds` — the very number
            // `recordSolveMadeElsewhere` just wrote into history and points —
            // so the share card, the drawer and the tracker now agree with the
            // record instead of drifting past it. (Deliberately NOT
            // `cleared.updatedAt`, which is stamped at ingest time below and
            // would credit the gap between the widget solve and this launch.)
            var solvedGame = shared.game
            solvedGame.timer.closeOpenRun(notLaterThan: pending.solvedAt)
            // Adopt the finished board into the one day entry and mark it solved
            // (free-play entries structurally untouched — the clobber fix).
            let id = library.adoptDaily(game: solvedGame, day: shared.dayOrdinal, now: Date())
            library.markSolved(id: id, at: pending.solvedAt)
            try? libraryStore.flushNow()
            var cleared = shared
            // The capped board goes back to the shared file too, so the widget
            // and a later re-ingest read a closed run rather than this one.
            cleared.game = solvedGame
            cleared.pendingSolve = nil
            cleared.revision += 1
            cleared.updatedAt = Date()
            WidgetBridge.knownBoardRevision = cleared.revision
            try? SharedDailyBoardStore.save(cleared)
            // Mid-play on the same daily? Show the finished board calmly.
            //
            // `solvedGame`, not `shared.game`. The beneficiary is the stats
            // drawer's elapsed tile (`StatsDrawer.swift:119`), which is NOT
            // gated on `solvedAt` the way the three timer chips are and reads
            // `elapsed(at: timeline.date)` — so an open run there ticks upward
            // on a finished board. The share card is explicitly *not* a victim:
            // `shareFacts` builds `SolveCardFacts` `at: model.solvedAt`
            // (TouchUI.swift:1099, MacUI.swift:513), and `solvedAt` is
            // `pending.solvedAt` here, so `elapsed(at:)` returned
            // `pending.seconds` exactly even before this cap. Same for the
            // library copy above, whose victim is `BoardsSheet.swift:159`/`:287`
            // (`elapsed(at: Date())`).
            if screen == .game, case .daily(let day)? = kind, day == shared.dayOrdinal {
                game = solvedGame
                solvedAt = pending.solvedAt
            }
        } else if !shared.game.isSolved {
            // Cap the shared board's run BEFORE it reaches the library, not
            // just before it reaches the screen. This is load-bearing, not
            // belt-and-braces: the shared file normally carries
            // `runningSince != nil` mid-play (`WidgetBridge.publishDailyBoard`
            // writes `model.game` unmodified, and `persistProgress()` publishes
            // on every move), and `BoardIntents` only ever reads that timer,
            // never closes it. So a jetsam mid-daily — killed with no
            // `.background` transition, hence no `holdClock` pause — leaves the
            // run open, and adopting it verbatim credits the entire dead-app
            // absence. `startClockIfUnheld` cannot save us either:
            // `ElapsedTimer.start` is a no-op on an already-running timer, so
            // without this the hold is bypassed rather than enforced.
            //
            // **Above `adoptDaily`, and that placement is the whole fix.**
            // Capping only inside the `screen == .game` block below covers just
            // the case where the app is already foreground on this daily.
            // Launch is the common one and it is not that case: `init` calls
            // `ingestSharedDailyBoard()` while `screen` is still `.home`, so
            // the on-screen branch is skipped entirely — then `adoptDaily`
            // stamps `updatedAt = now` (the INGEST instant), that entry becomes
            // `mostRecentInProgress` (newest-first), resume-on-launch runs
            // `startEntry`, and its own cap closes the run against the ingest
            // instant — crediting the absence it was meant to refuse. With
            // resume-on-launch off it is merely deferred: `BoardsSheet` renders
            // `elapsed(at: Date())` on a still-open run as a growing tile.
            //
            // `shared.updatedAt` is the right cap: both writers
            // (`WidgetBridge.swift:83`, `BoardIntents.swift:65`) set it to
            // `now` at write time, so it is precisely the last instant this
            // board's state is known to be current — the same reading
            // `LibraryEntry.updatedAt` gets at the other two seams.
            var capped = shared.game
            capped.timer.closeOpenRun(notLaterThan: shared.updatedAt)
            // Widget moves flow into the day entry only — free-play untouched.
            let id = library.adoptDaily(game: capped, day: shared.dayOrdinal, now: Date())
            try? libraryStore.flushNow()
            if screen == .game, solvedAt == nil,
               case .daily(let day)? = kind, day == shared.dayOrdinal {
                var g = capped
                // Same reasoning as `refreshOnScreenBoardAfterMerge`: `openToday`
                // and the URL-open route can call this while the game screen's
                // own `.sheet` hold is up (a widget board can arrive at any
                // time, independent of scene activation). Adopt the board, but
                // only start its clock if nothing is holding it; `releaseClock`
                // resumes it once the hold actually lifts.
                startClockIfUnheld(&g)
                game = g
                currentEntryID = id // keep the persist target on the day entry
            }
        } else if library.dailyEntry(day: shared.dayOrdinal)?.status != .solved {
            // Solved with no pendingSolve → already recorded elsewhere; make
            // sure the day entry reflects solved (repair; keeps solvedAt if set).
            //
            // Capped for the same reason as the two branches above, and it is
            // not academic here: this entry is `markSolved`, so nothing will
            // ever resume it and close its run in passing. An open run left
            // here is permanent — `BoardsSheet.swift:159`/`:287` render
            // `elapsed(at: Date())` for "previously played", so the board would
            // show a time that grows forever. `shared.updatedAt` again: there
            // is no `PendingSolve` on this path to take a solve instant from.
            var capped = shared.game
            capped.timer.closeOpenRun(notLaterThan: shared.updatedAt)
            let id = library.adoptDaily(game: capped, day: shared.dayOrdinal, now: Date())
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
