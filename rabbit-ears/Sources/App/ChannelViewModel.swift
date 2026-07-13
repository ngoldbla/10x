// ChannelViewModel — the thin bridge between the pure ChannelDirector and
// CouchKit (photos, persistence). Owns the double-buffered display layers the
// view crossfades between; the director decides *when*, this decides *what
// pixels*.
import SwiftUI
import Observation
import CouchKit

@MainActor @Observable
final class ChannelViewModel {

    /// One display-ready photo: source pixels + caption + a stable seed for
    /// drift and render noise.
    struct Frame: Identifiable, Equatable {
        let id: String
        let image: CGImage
        let caption: String
        let seed: UInt64

        static func == (lhs: Frame, rhs: Frame) -> Bool { lhs.id == rhs.id }
    }

    struct Chip: Equatable {
        let text: String
        let symbol: String
    }

    // MARK: Display state (observed by ChannelView)

    /// Double buffer: the *staging* layer sits on top and fades in during a
    /// crossfade; on landing, roles swap (z-order flip — no re-render flash).
    private(set) var layerA: Frame?
    private(set) var layerB: Frame?
    private(set) var stagingIsA = true
    var stagingOpacity: Double = 0
    private(set) var morphActive = false

    private(set) var style: AsciiStyle = .terminal
    private(set) var lane: Lane = .allMemories
    private(set) var isFrozen = false
    private(set) var isPaused = false
    private(set) var laneChip: String?
    private(set) var playbackChip: Chip?
    private(set) var connectChip: String?
    private(set) var settingsChip: String?
    var showPrefs = false
    /// First-run help overlay (design §6): shown until dismissed once, ever.
    private(set) var showHelp = false
    private(set) var prefs = ChannelPrefs.default
    /// Library counts for the prefs sheet's Photos status line; nil until the
    /// sheet first asks (census is a Photos fetch — don't pay it at launch).
    private(set) var photoCensus: (photos: Int, favorites: Int)?

    var currentFrame: Frame? { stagingIsA ? layerB : layerA }
    private var stagingFrame: Frame? { stagingIsA ? layerA : layerB }

    static let fineCols = 160

    // MARK: Persistence

    @ObservationIgnored
    @CouchStored("channel-state") private var storedState = ChannelDirector.SavedState.initial
    @ObservationIgnored
    @CouchStored("prefs") private var storedPrefs = ChannelPrefs.default
    @ObservationIgnored
    @CouchStored("help.seen") private var helpSeen = false

    // MARK: Internals

    @ObservationIgnored private var director = ChannelDirector(seed: 0xAB81_7EA5)
    @ObservationIgnored private var photosByID: [String: CuratedPhoto] = [:]
    @ObservationIgnored private var imageCache: [String: CGImage] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var laneChipTask: Task<Void, Never>?
    @ObservationIgnored private var playbackChipTask: Task<Void, Never>?
    @ObservationIgnored private var shownConnectChip = false
    @ObservationIgnored private var shownSettingsChip = false

    private var now: TimeInterval { Date.timeIntervalSinceReferenceDate }

    // MARK: Lifecycle

    func start() async {
        prefs = storedPrefs
        director.restore(storedState)
        director.setSpeed(prefs.speed)
        style = director.style
        lane = director.lane
        startTicking()

        // Demo pools land instantly (art within 2 s), then upgrade to the
        // real library after the single allowed permission prompt.
        await loadPools()
        if PhotoAccess.canPrompt {
            let granted = await PhotoAccess.request()
            if granted { await loadPools() }
        }
        if !PhotoAccess.isAuthorized {
            flashConnectChip()
        }
        // First launch gets the full overlay; every later session gets the
        // one-line nudge toward the hidden settings gesture instead.
        if helpSeen {
            flashSettingsChip()
        } else {
            showHelp = true
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        try? $storedState.flushNow()
        try? $storedPrefs.flushNow()
    }

    /// Prefs "start on wake": resume playback whenever the scene returns.
    func sceneBecameActive() {
        if prefs.startOnWake, isPaused {
            dispatch(director.togglePause(at: now))
        }
    }

    // MARK: Remote grammar

    func handle(_ gesture: CouchGesture) {
        switch gesture {
        case .swipe(.right):
            dispatch(director.cycleStyle(forward: true))
        case .swipe(.left):
            dispatch(director.cycleStyle(forward: false))
        case .swipe(.up):
            dispatch(director.switchLane(forward: true, at: now))
        case .swipe(.down):
            dispatch(director.switchLane(forward: false, at: now))
        case .click:
            dispatch(director.toggleFreeze(at: now))
        case .holdBegan:
            dispatch(director.morph(at: now))
        case .playPause:
            dispatch(director.togglePause(at: now))
        case .playPauseLongPress:
            showPrefs = true
        case .holdEnded, .back, .flick:
            break
        }
    }

    // MARK: Prefs

    func setSpeed(_ speed: CrossfadeSpeed) {
        prefs.speed = speed
        storedPrefs = prefs
        director.setSpeed(speed)
    }

    func setStartOnWake(_ enabled: Bool) {
        prefs.startOnWake = enabled
        storedPrefs = prefs
    }

    /// Prefs "Refresh photos": re-run every lane's pool query, then re-count
    /// so the status line reflects what just landed.
    func refreshPhotos() async {
        await loadPools()
        await refreshCensus()
    }

    /// Counts for the Photos status line; the sheet calls this on appear.
    func refreshCensus() async {
        photoCensus = await CouchPhotos.census()
    }

    // MARK: Help

    /// The first-run overlay was clicked away: never again — but still nudge
    /// toward the settings gesture once this session.
    func dismissHelp() {
        showHelp = false
        helpSeen = true
        flashSettingsChip()
    }

    // MARK: Pools

    private func loadPools() async {
        for poolLane in Lane.allCases {
            let photos = await fetchPhotos(for: poolLane)
            var seen = Set<String>()
            var ids: [String] = []
            for photo in photos where seen.insert(photo.id).inserted {
                photosByID[photo.id] = photo
                ids.append(photo.id)
            }
            let events = director.setPool(ids, for: poolLane, at: now)
            await apply(events)
        }
    }

    private func fetchPhotos(for poolLane: Lane) async -> [CuratedPhoto] {
        switch poolLane {
        case .allMemories:
            // PRD §4.1: on-this-day first, then the wider stream.
            let today = await CouchPhotos.onThisDay(limit: 12)
            let recent = await CouchPhotos.recentHighlights(limit: 60)
            return today + recent
        case .onThisDay:
            return await CouchPhotos.onThisDay(limit: 48)
        case .favorites:
            return await CouchPhotos.randomMemorable(limit: 60, seed: 0xFA7)
        }
    }

    // MARK: Director event loop

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let events = self.director.advance(to: self.now)
                if !events.isEmpty { await self.apply(events) }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func dispatch(_ events: [ChannelDirector.Event]) {
        guard !events.isEmpty else { return }
        Task { await apply(events) }
    }

    private func apply(_ events: [ChannelDirector.Event]) async {
        for event in events {
            switch event {
            case .photoChanged(let id):
                await land(on: id)
            case .crossfadeStarted(_, let toID, let duration, let isMorph):
                morphActive = isMorph
                if let frame = await makeFrame(id: toID) {
                    setStaging(frame)
                    withAnimation(.linear(duration: duration)) {
                        stagingOpacity = 1
                    }
                }
            case .laneChanged(let newLane):
                lane = newLane
                flashLaneChip(newLane.displayName)
            case .styleChanged(let newStyle):
                style = newStyle
            case .froze:
                isFrozen = true
            case .unfroze:
                isFrozen = false
            case .paused:
                isPaused = true
                flashPlaybackChip(Chip(text: "Paused", symbol: "pause.fill"))
            case .resumed:
                isPaused = false
                flashPlaybackChip(Chip(text: "Playing", symbol: "play.fill"))
            }
        }
        storedState = director.savedState
    }

    /// A photo became fully current: either the staged layer just finished
    /// its fade (promote it) or this is a hard cut (initial load, lane jump).
    private func land(on id: String) async {
        if let staged = stagingFrame, staged.id == id {
            promoteStaging()
        } else if let frame = await makeFrame(id: id) {
            setCurrent(frame)
        }
        morphActive = false
        prefetchUpNext()
    }

    // MARK: Layer management

    private func setStaging(_ frame: Frame) {
        stagingOpacity = 0
        if stagingIsA { layerA = frame } else { layerB = frame }
    }

    private func promoteStaging() {
        stagingIsA.toggle()          // fully-faded layer becomes current
        stagingOpacity = 0           // (applies to the new, empty staging)
        if stagingIsA { layerA = nil } else { layerB = nil }
    }

    private func setCurrent(_ frame: Frame) {
        if stagingIsA {
            layerB = frame
            layerA = nil
        } else {
            layerA = frame
            layerB = nil
        }
        stagingOpacity = 0
    }

    // MARK: Photo loading

    private func makeFrame(id: String) async -> Frame? {
        guard let photo = photosByID[id] else { return nil }
        var image = imageCache[id]
        if image == nil {
            image = try? await photo.load(maxDimension: 1920)
            if let image { cache(image, for: id) }
        }
        guard let image else { return nil }
        return Frame(
            id: id,
            image: image,
            caption: CaptionFormatter.caption(date: photo.displayDate, location: photo.locationLabel),
            seed: SeedDerivation.seed(for: id)
        )
    }

    /// Warm the source-image cache for the director's announced next photo
    /// during the current dwell (PRD §7 pre-render).
    private func prefetchUpNext() {
        guard let id = director.upNextPhotoID, imageCache[id] == nil else { return }
        Task { _ = await makeFrame(id: id) }
    }

    private func cache(_ image: CGImage, for id: String) {
        imageCache[id] = image
        cacheOrder.removeAll { $0 == id }
        cacheOrder.append(id)
        while cacheOrder.count > 8 {
            imageCache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    // MARK: Transient chips

    private func flashLaneChip(_ text: String) {
        laneChip = text
        laneChipTask?.cancel()
        laneChipTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            laneChip = nil
        }
    }

    private func flashPlaybackChip(_ chip: Chip) {
        playbackChip = chip
        playbackChipTask?.cancel()
        playbackChipTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            playbackChip = nil
        }
    }

    /// Design §5 discoverability: once per session, then never again.
    private func flashSettingsChip() {
        guard !shownSettingsChip else { return }
        shownSettingsChip = true
        settingsChip = "Hold ▶︎ for settings"
        Task {
            try? await Task.sleep(for: .seconds(6))
            settingsChip = nil
        }
    }

    /// PRD §4.1: once per session, then never again.
    private func flashConnectChip() {
        guard !shownConnectChip else { return }
        shownConnectChip = true
        connectChip = "Connect iCloud Photos for your own memories"
        Task {
            try? await Task.sleep(for: .seconds(10))
            connectChip = nil
        }
    }
}
