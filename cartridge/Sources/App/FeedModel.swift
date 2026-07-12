// FeedModel — the channel-surf shell: paging, attract/play/verdict/pause
// state machine, fixed-timestep drive, input routing (scheme-scoped),
// bests persistence. The engine stays pure; all platform time lives here.
import SwiftUI
import Observation
import CouchKit

enum SpriteLane: String, CaseIterable, Sendable, Codable {
    case photos, demo

    var title: String {
        switch self {
        case .photos: return "My photos"
        case .demo: return "Demo art"
        }
    }
}

@MainActor @Observable
final class FeedModel {
    enum Mode: Equatable {
        case feed        // attract loop, zappable
        case playing
        case verdict     // death card, already listening
        case paused
    }

    struct Prefs: Codable, Sendable, Equatable {
        var spriteLane: String = SpriteLane.photos.rawValue
        var reduceMotion: Bool = false
    }

    // MARK: State

    let day: DayStamp
    /// Today's channel order — daily-challenge game first, deterministic.
    let order: [GameID]

    private(set) var mode: Mode = .feed
    private(set) var index: Int = 0
    private(set) var attract: [GameID: Session] = [:]
    private(set) var live: Session?
    private(set) var verdictScore = 0
    private(set) var verdictIsBest = false
    private(set) var bests: [String: Int]

    var showPrefs = false

    /// Prefs are mirrored into observable stored properties (the persisted
    /// copy is @ObservationIgnored, so views must not read it directly).
    var reduceMotion: Bool {
        didSet { persistPrefs() }
    }
    var spriteLane: SpriteLane {
        didSet { persistPrefs() }
    }

    // MARK: Persistence

    @ObservationIgnored
    @CouchStored("cartridge.scorebook") private var storedBook = ScoreBook()
    @ObservationIgnored
    @CouchStored("cartridge.prefs") private var storedPrefs = Prefs()

    // MARK: Loop internals

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var lastTime: TimeInterval?
    @ObservationIgnored private var accumulator: Double = 0
    @ObservationIgnored private var pendingInputs: [SchemeInput] = []
    @ObservationIgnored private var roundCounter: UInt64 = 0

    init(day: DayStamp = DayStamp(date: Date())) {
        self.day = day
        self.order = DailyChallenge.feedOrder(on: day)
        self.bests = [:]
        self.reduceMotion = false
        self.spriteLane = .photos
        // All stored properties initialized — now hydrate from disk.
        self.bests = storedBook.bests
        self.reduceMotion = storedPrefs.reduceMotion
        self.spriteLane = SpriteLane(rawValue: storedPrefs.spriteLane) ?? .photos
    }

    private func persistPrefs() {
        storedPrefs = Prefs(
            spriteLane: spriteLane.rawValue,
            reduceMotion: reduceMotion
        )
    }

    // MARK: Derived

    var currentGame: GameID { order[index] }

    func mutator(for game: GameID) -> Mutator {
        DailyChallenge.mutator(for: game, on: day)
    }

    func best(for game: GameID) -> Int {
        bests[game.rawValue] ?? 0
    }

    /// What a channel page should draw right now.
    func displaySession(for game: GameID) -> Session? {
        if game == currentGame, mode != .feed, let live { return live }
        return attract[game]
    }

    /// Ring-relative page position: -1 above, 0 current, +1 below.
    func relativePosition(of pageIndex: Int) -> Int {
        let n = order.count
        let d = ((pageIndex - index) % n + n) % n
        return d > n / 2 ? d - n : d
    }

    // MARK: Loop

    func start() {
        guard loopTask == nil else { return }
        ensureAttractSessions()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard let self else { return }
                self.step(now: Date.timeIntervalSinceReferenceDate)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        lastTime = nil
    }

    private func step(now: TimeInterval) {
        guard !showPrefs, mode != .paused else {
            lastTime = nil
            return
        }
        let dt = lastTime.map { min(0.25, max(0, now - $0)) } ?? 0
        lastTime = now
        accumulator = min(accumulator + dt, 0.25)
        while accumulator >= CartridgeClock.dt {
            accumulator -= CartridgeClock.dt
            tickOnce()
        }
    }

    private func tickOnce() {
        switch mode {
        case .feed:
            ensureAttractSessions()
            let game = currentGame
            guard var session = attract[game] else { return }
            if session.isGameOver {
                session.reset(seed: nextSeed())
            } else {
                session.tickWithBot()
            }
            attract[game] = session
        case .playing:
            guard var session = live else { return }
            let input = pendingInputs.isEmpty ? nil : pendingInputs.removeFirst()
            session.tick(input: input)
            live = session
            if session.isGameOver { finishRound(session) }
        case .verdict, .paused:
            break
        }
    }

    /// Keep attract rounds warm for the visible channel and its neighbors.
    private func ensureAttractSessions() {
        let n = order.count
        for offset in [-1, 0, 1] {
            let game = order[((index + offset) % n + n) % n]
            if attract[game] == nil {
                attract[game] = CartridgeCatalog.dailySession(
                    for: game, on: day, seed: nextSeed()
                )
            }
        }
    }

    private func nextSeed() -> UInt64 {
        roundCounter &+= 1
        return day.seed ^ (roundCounter &* 0x9E37_79B9_7F4A_7C15)
    }

    private func finishRound(_ session: Session) {
        verdictScore = session.score
        var book = storedBook
        verdictIsBest = book.record(session.score, for: session.game)
        storedBook = book
        bests = book.bests
        mode = .verdict
    }

    // MARK: Gestures → intents

    func handle(_ gesture: CouchGesture) {
        guard !showPrefs else { return } // the sheet owns input while open

        switch mode {
        case .feed:
            switch gesture {
            case .swipe(.up): zap(+1)
            case .swipe(.down): zap(-1)
            case .click: play()
            case .playPauseLongPress: openPrefs()
            default: break
            }

        case .playing:
            switch gesture {
            case .click: enqueue(.click)
            case .swipe(let d): enqueue(.swipe(d))
            case .holdBegan: enqueue(.holdBegan)
            case .holdEnded: enqueue(.holdEnded)
            case .playPause: pause()
            case .playPauseLongPress: pause(); openPrefs()
            case .back: endToFeed()
            case .flick: break
            }

        case .verdict:
            switch gesture {
            case .click: retry()
            case .swipe(.up): endToFeed(); zap(+1)   // retry-or-zap in one input
            case .swipe(.down): endToFeed(); zap(-1)
            case .back: endToFeed()
            case .playPauseLongPress: openPrefs()
            default: break
            }

        case .paused:
            switch gesture {
            case .playPause, .click: resume()
            case .back: endToFeed()
            case .playPauseLongPress: openPrefs()
            default: break
            }
        }
    }

    // MARK: Intents

    private func zap(_ direction: Int) {
        let n = order.count
        index = ((index + direction) % n + n) % n
        ensureAttractSessions()
    }

    /// Click in the feed: attract morphs into a fresh live round, instantly.
    private func play() {
        var session = attract[currentGame]
            ?? CartridgeCatalog.dailySession(for: currentGame, on: day, seed: nextSeed())
        session.reset(seed: nextSeed())
        live = session
        pendingInputs.removeAll()
        mode = .playing
    }

    private func retry() {
        guard var session = live else { return endToFeed() }
        session.reset(seed: nextSeed())
        live = session
        pendingInputs.removeAll()
        mode = .playing
    }

    private func pause() {
        guard mode == .playing else { return }
        mode = .paused
    }

    private func resume() {
        guard mode == .paused else { return }
        pendingInputs.removeAll()
        mode = .playing
    }

    private func endToFeed() {
        live = nil
        pendingInputs.removeAll()
        mode = .feed
    }

    private func openPrefs() {
        showPrefs = true
    }

    private func enqueue(_ input: SchemeInput) {
        guard live?.scheme.accepts(input) == true else { return } // scheme law
        pendingInputs.append(input)
        if pendingInputs.count > 4 { pendingInputs.removeFirst() }
    }
}
