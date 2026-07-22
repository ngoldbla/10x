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

    init() {}

    enum CodingKeys: String, CodingKey {
        case showTimer, errorHighlight, accent, numberHighlight
        case controlsAtBottom, resumeOnLaunch, boardAnchor, ambientSlot
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
    }
}

/// What kind of board is (or was) being played.
enum GameKind: Codable, Sendable, Equatable, Hashable {
    case daily(day: Int)
    case free(Difficulty)
}

/// The single autosave slot: one in-progress board at a time.
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
    private(set) var saved: SaveSlot {
        didSet { saveStore.wrappedValue = saved }
    }
    /// Every finished board: date, difficulty, time, points (capped log).
    private(set) var history: SolveHistory {
        didSet { historyStore.wrappedValue = history }
    }

    // Persistence (streaks and the solve log are precious → cloud-synced).
    @ObservationIgnored private let prefsStore =
        CouchStored(wrappedValue: NinePrefs(), "nine.prefs")
    @ObservationIgnored private let streakStore =
        CouchStored(wrappedValue: StreakState(), "nine.streak", cloudSynced: true)
    @ObservationIgnored private let saveStore =
        CouchStored(wrappedValue: SaveSlot(), "nine.save")
    @ObservationIgnored private let helpSeenStore =
        CouchStored(wrappedValue: false, "help.seen")
    @ObservationIgnored private let historyStore =
        CouchStored(wrappedValue: SolveHistory(), "nine.history", cloudSynced: true)

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

    func enterDeskMode() { windowMode = .desk }
    func exitDeskMode() { windowMode = .full }
    func toggleDeskMode() { windowMode = windowMode == .full ? .desk : .full }
    #endif

    init() {
        prefs = prefsStore.wrappedValue
        streak = streakStore.wrappedValue
        saved = saveStore.wrappedValue
        helpSeen = helpSeenStore.wrappedValue
        history = historyStore.wrappedValue
        #if os(macOS)
        deskFloating = deskFloatingStore.wrappedValue
        // Resume straight into a board in progress, as iOS — the Mac equivalent
        // of "fewer taps to the board" (PRD-4 §2.6 resume-on-launch parity).
        if prefs.resumeOnLaunch, let game = saved.game, let kind = saved.kind {
            resume(game, kind: kind)
        }
        #endif
        #if os(iOS)
        // Fewer taps to the board: a launch with a board in progress goes
        // straight back to it. The home chevron is one tap away.
        // Widget moves made while the app was dead merge in before anything
        // reads the autosave slot (and before the publish below can write a
        // stale board over them).
        ingestSharedDailyBoard()
        if prefs.resumeOnLaunch, let game = saved.game, let kind = saved.kind {
            resume(game, kind: kind)
        }
        // Post-load publish covers state that changed without the widget
        // hearing about it (reinstall, iCloud KVS sync, midnight).
        WidgetBridge.publish(from: self)
        #endif
    }

    // MARK: - Derived

    var todayOrdinal: Int { DailySeed.dayOrdinal(for: Date()) }

    var todaySolved: Bool { streak.hasCompleted(day: todayOrdinal) }

    /// The saved board, when it is today's daily.
    var savedDaily: NineGame? {
        guard case .daily(let day)? = saved.kind, day == todayOrdinal else { return nil }
        return saved.game
    }

    /// The saved board, when it is a free-play game (drives the Continue card).
    var savedFree: (game: NineGame, difficulty: Difficulty)? {
        guard case .free(let difficulty)? = saved.kind, let game = saved.game else { return nil }
        return (game, difficulty)
    }

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
        if let inProgress = savedDaily {
            resume(inProgress, kind: .daily(day: day))
        } else {
            compose(kind: .daily(day: day), seed: DailySeed.seed(for: Date()), difficulty: .steady)
        }
    }

    func continueSaved() {
        guard let game = saved.game, let kind = saved.kind else { return }
        resume(game, kind: kind)
    }

    func startFree(_ difficulty: Difficulty) {
        compose(kind: .free(difficulty), seed: .random(in: UInt64.min...UInt64.max), difficulty: difficulty)
    }

    /// Drop the saved in-progress board without playing it (the Continue
    /// card's discard control). The current on-screen game is untouched.
    func discardSaved() {
        #if os(iOS)
        let wasDaily = if case .daily? = saved.kind { true } else { false }
        #endif
        saved = SaveSlot()
        try? saveStore.flushNow()
        #if os(iOS)
        // A discarded daily must not resurrect from the shared board file.
        if wasDaily {
            WidgetBridge.clearDailyBoard(today: todayOrdinal)
        }
        WidgetBridge.publish(from: self)
        #endif
    }

    private func resume(_ game: NineGame, kind: GameKind) {
        var g = game
        g.timer.start(at: Date())
        self.game = g
        self.kind = kind
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
                self.resume(NineGame(puzzle: puzzle), kind: kind)
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
        try? saveStore.flushNow()
        try? streakStore.flushNow()
        // Keep `game`/`solvedAt` untouched so the departing GameScreen stays
        // visually stable through the crossfade; the next start replaces them.
        screen = .home
        #if os(macOS)
        // Desk mode is a board posture; home always gets the full window.
        windowMode = .full
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
        saved = SaveSlot() // the board is done; free the slot
        try? saveStore.flushNow()
        // GameKit is native on iOS and macOS (PRD-4 §2.6); widgets are iOS-only.
        #if os(iOS) || os(macOS)
        GameCenter.shared.reportSolve(record: record, history: history, streak: streak)
        #endif
        #if os(iOS)
        WidgetBridge.publish(from: self)
        #endif
    }

    private func persistProgress() {
        guard let game, let kind else { return }
        saved = SaveSlot(game: game, kind: kind)
        #if os(iOS)
        // Fires per move; WidgetBridge digest-gates the actual reloads.
        WidgetBridge.publish(from: self)
        #endif
    }

    #if os(iOS)
    // MARK: - Widget board ingestion (PRD-3 §4)

    /// Adopt the shared daily board when the widget moved it forward. Runs
    /// on launch, on scene activation and before opening today's daily, so
    /// the app never plays over widget moves. A solve made in the widget is
    /// recorded here — exactly once — into streak/history/Game Center.
    func ingestSharedDailyBoard() {
        // Invariant repair: a solved, already-recorded daily never lives in
        // the autosave slot (finishSolve frees it). Clear one if found so
        // resumeOnLaunch/openToday can't land on a finished board.
        if let game = saved.game, game.isSolved,
           case .daily(let day)? = saved.kind, streak.hasCompleted(day: day) {
            saved = SaveSlot()
            try? saveStore.flushNow()
        }
        guard let shared = SharedDailyBoardStore.load(),
              shared.isCurrent(today: todayOrdinal),
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
            // The board is done; free the slot and clear the pending flag.
            if case .daily? = saved.kind { saved = SaveSlot() }
            try? saveStore.flushNow()
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
            // Widget moves flow into the autosave, undo stack included.
            saved = SaveSlot(game: shared.game, kind: .daily(day: shared.dayOrdinal))
            try? saveStore.flushNow()
            if screen == .game, solvedAt == nil,
               case .daily(let day)? = kind, day == shared.dayOrdinal {
                var g = shared.game
                g.timer.start(at: Date())
                game = g
            }
        }
        // (A solved board with no pendingSolve is already recorded — nothing
        // to adopt; the autosave slot stays free, per finishSolve.)
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
