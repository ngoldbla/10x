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

/// Accent tints offered in prefs. Muted, glass-safe hues; never pure red or
/// green (colorblind-safe rule: errors pair a coral underline with a dot).
enum AccentChoice: String, Codable, Sendable, CaseIterable {
    case glacier, ember, meadow, lilac

    var title: String {
        switch self {
        case .glacier: return "Glacier"
        case .ember: return "Ember"
        case .meadow: return "Meadow"
        case .lilac: return "Lilac"
        }
    }

    var color: Color {
        switch self {
        case .glacier: return Color(red: 0.56, green: 0.78, blue: 0.92)
        case .ember: return Color(red: 0.96, green: 0.71, blue: 0.51)
        case .meadow: return Color(red: 0.62, green: 0.86, blue: 0.70)
        case .lilac: return Color(red: 0.76, green: 0.70, blue: 0.94)
        }
    }
}

/// iOS appearance override. `auto` follows the system; tvOS ignores this
/// entirely (the TV void is always dark — that's the brand at 3 meters).
enum AppearanceChoice: String, Codable, Sendable, CaseIterable {
    case auto, dark, light

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .dark: return .dark
        case .light: return .light
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
    /// iOS color scheme override.
    var appearance: AppearanceChoice = .auto
    /// Launch straight back into a board in progress.
    var resumeOnLaunch = true

    init() {}

    /// Tolerant decoding: CouchStored discards the whole blob when decode
    /// throws, so any field added after 1.0 must fall back to its default
    /// instead of resetting a player's settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showTimer = try c.decodeIfPresent(Bool.self, forKey: .showTimer) ?? false
        errorHighlight = try c.decodeIfPresent(Bool.self, forKey: .errorHighlight) ?? true
        accent = try c.decodeIfPresent(AccentChoice.self, forKey: .accent) ?? .glacier
        numberHighlight = try c.decodeIfPresent(Bool.self, forKey: .numberHighlight) ?? true
        controlsAtBottom = try c.decodeIfPresent(Bool.self, forKey: .controlsAtBottom) ?? true
        appearance = try c.decodeIfPresent(AppearanceChoice.self, forKey: .appearance) ?? .auto
        resumeOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .resumeOnLaunch) ?? true
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

    init() {
        prefs = prefsStore.wrappedValue
        streak = streakStore.wrappedValue
        saved = saveStore.wrappedValue
        helpSeen = helpSeenStore.wrappedValue
        history = historyStore.wrappedValue
        #if os(iOS)
        // Fewer taps to the board: a launch with a board in progress goes
        // straight back to it. The home chevron is one tap away.
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

    // MARK: - Starting games

    func openToday() {
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
        saved = SaveSlot()
        try? saveStore.flushNow()
        #if os(iOS)
        WidgetBridge.publish(from: self)
        #endif
    }

    private func resume(_ game: NineGame, kind: GameKind) {
        var g = game
        g.timer.start(at: Date())
        self.game = g
        self.kind = kind
        self.solvedAt = nil
        self.screen = .game
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
        #if os(iOS)
        GameCenter.shared.reportSolve(record: record, history: history, streak: streak)
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
