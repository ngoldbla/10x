// ChannelDirector — Rabbit Ears' logic core. A pure, time-stepped state
// machine: the app feeds it wall-clock instants and gestures; it answers with
// events (start a crossfade, land on a photo, freeze, …). Deterministic for a
// given seed + call sequence: every stochastic choice flows through SplitMix64
// and CouchCore's SequencePlanner.
//
// Imports: Foundation + CouchCore only. No SwiftUI, no clocks — time is
// injected, which is what makes the dwell/fade scheduling unit-testable.
import Foundation
import CouchCore

public struct ChannelDirector: Sendable {

    // MARK: - Config

    public struct Config: Sendable, Equatable {
        /// PRD envelope: every dwell lands inside 20–40 s.
        public var minDwell: TimeInterval
        public var maxDwell: TimeInterval
        /// No-repeat window fed to `SequencePlanner` (PRD: 200; the planner
        /// clamps to pool-size − 1).
        public var noRepeatWindow: Int
        /// Duration of the hold-to-morph dissolve.
        public var morphDuration: TimeInterval

        public init(
            minDwell: TimeInterval = 20,
            maxDwell: TimeInterval = 40,
            noRepeatWindow: Int = 200,
            morphDuration: TimeInterval = 1.5
        ) {
            self.minDwell = minDwell
            self.maxDwell = maxDwell
            self.noRepeatWindow = noRepeatWindow
            self.morphDuration = morphDuration
        }
    }

    // MARK: - Phase & events

    public enum Phase: Sendable, Equatable {
        /// No photos available (empty pool).
        case idle
        /// Showing the current photo until `until` (unless frozen/paused).
        case dwelling(until: TimeInterval)
        /// Mid-crossfade toward `upNext`.
        case crossfading(started: TimeInterval, duration: TimeInterval, isMorph: Bool)
    }

    public enum Event: Sendable, Equatable {
        /// The fully-visible photo changed (initial load, crossfade landing,
        /// lane switch).
        case photoChanged(id: String)
        /// Begin blending `fromID` → `toID` over `duration` seconds.
        case crossfadeStarted(fromID: String, toID: String, duration: TimeInterval, isMorph: Bool)
        case laneChanged(Lane)
        case styleChanged(AsciiStyle)
        case froze(id: String)
        case unfroze
        case paused
        case resumed
    }

    // MARK: - Persistence

    /// What survives relaunch (PRD §10 open question resolved: freeze
    /// persists — the TV stays a picture frame).
    public struct SavedState: Codable, Sendable, Equatable {
        public var lane: Lane
        public var style: AsciiStyle
        public var frozenPhotoID: String?

        public init(
            lane: Lane = .allMemories,
            style: AsciiStyle = .terminal,
            frozenPhotoID: String? = nil
        ) {
            self.lane = lane
            self.style = style
            self.frozenPhotoID = frozenPhotoID
        }

        public static let initial = SavedState()
    }

    // MARK: - State

    public let seed: UInt64
    public let config: Config
    public private(set) var lane: Lane
    public private(set) var style: AsciiStyle
    public private(set) var speed: CrossfadeSpeed
    public private(set) var phase: Phase = .idle
    public private(set) var isFrozen = false
    public private(set) var isPaused = false

    private var pools: [Lane: [String]] = [:]
    private var planner: SequencePlanner?
    private var currentIndex: Int?
    private var upNextIndex: Int?
    private var rng: SplitMix64
    private var pausedRemaining: TimeInterval?
    /// Freeze restored from disk but not yet matched against a pool.
    private var pendingFrozenID: String?

    public init(
        seed: UInt64,
        lane: Lane = .allMemories,
        style: AsciiStyle = .terminal,
        speed: CrossfadeSpeed = .standard,
        config: Config = Config()
    ) {
        self.seed = seed
        self.lane = lane
        self.style = style
        self.speed = speed
        self.config = config
        self.rng = SplitMix64(seed: seed ^ 0xD1EC7)
    }

    // MARK: - Derived accessors

    public var activePool: [String] { pools[lane] ?? [] }

    public var currentPhotoID: String? {
        guard let index = currentIndex, index < activePool.count else { return nil }
        return activePool[index]
    }

    /// Chosen at dwell start so the app can pre-render the next frame.
    public var upNextPhotoID: String? {
        guard let index = upNextIndex, index < activePool.count else { return nil }
        return activePool[index]
    }

    /// Blend progress of an in-flight crossfade, `nil` otherwise.
    public func crossfadeProgress(at now: TimeInterval) -> Double? {
        guard case .crossfading(let started, let duration, _) = phase, duration > 0 else {
            return nil
        }
        return min(1, max(0, (now - started) / duration))
    }

    public var savedState: SavedState {
        SavedState(lane: lane, style: style, frozenPhotoID: isFrozen ? currentPhotoID : nil)
    }

    // MARK: - Setup

    /// Restore lane/style/freeze from a saved snapshot. Call before pools
    /// arrive; the frozen photo re-freezes when its pool first contains it.
    public mutating func restore(_ state: SavedState) {
        lane = state.lane
        style = state.style
        pendingFrozenID = state.frozenPhotoID
    }

    public mutating func setSpeed(_ newSpeed: CrossfadeSpeed) {
        speed = newSpeed
    }

    /// Install (or replace) a lane's photo pool. Activates immediately when
    /// it is the on-screen lane; a frozen current photo that survives the new
    /// pool stays frozen.
    @discardableResult
    public mutating func setPool(_ ids: [String], for poolLane: Lane, at now: TimeInterval) -> [Event] {
        let previousID = (poolLane == lane) ? currentPhotoID : nil
        pools[poolLane] = ids
        guard poolLane == lane else { return [] }
        var events: [Event] = []
        if isFrozen {
            if let id = previousID, ids.contains(id) {
                pendingFrozenID = id      // re-freeze on the same photo below
            } else {
                events.append(.unfroze)   // frozen photo vanished with the pool
            }
            isFrozen = false
        }
        return events + activateLane(at: now, emitLaneChange: false)
    }

    // MARK: - Time stepping

    /// Advance the machine to `now`. Call at any cadence; the machine only
    /// reacts to threshold crossings, so tick frequency never changes what
    /// happens — only how promptly it is observed.
    @discardableResult
    public mutating func advance(to now: TimeInterval) -> [Event] {
        switch phase {
        case .idle:
            guard !activePool.isEmpty else { return [] }
            return activateLane(at: now, emitLaneChange: false)
        case .dwelling(let until):
            guard !isFrozen, !isPaused, now >= until else { return [] }
            return beginCrossfade(at: now, duration: speed.fadeDuration, isMorph: false)
        case .crossfading(let started, let duration, _):
            guard now >= started + duration else { return [] }
            return completeCrossfade(at: now)
        }
    }

    // MARK: - Gestures

    /// Swipe ← / → : cycle the five styles with wrap-around.
    @discardableResult
    public mutating func cycleStyle(forward: Bool) -> [Event] {
        let all = AsciiStyle.allCases
        guard let index = all.firstIndex(of: style) else { return [] }
        style = all[(index + (forward ? 1 : all.count - 1)) % all.count]
        return [.styleChanged(style)]
    }

    /// Swipe ↑ / ↓ : cycle lanes. Leaving a frozen frame unfreezes it —
    /// the user asked for new content.
    @discardableResult
    public mutating func switchLane(forward: Bool, at now: TimeInterval) -> [Event] {
        var events: [Event] = []
        if isFrozen {
            isFrozen = false
            events.append(.unfroze)
        }
        pendingFrozenID = nil
        lane = forward ? lane.next : lane.previous
        events += activateLane(at: now, emitLaneChange: true)
        return events
    }

    /// Click: freeze / unfreeze the current frame. Freezing mid-crossfade
    /// snaps to the incoming photo first so the frozen frame is whole.
    @discardableResult
    public mutating func toggleFreeze(at now: TimeInterval) -> [Event] {
        if isFrozen {
            isFrozen = false
            if currentIndex != nil {
                phase = .dwelling(until: now + drawDwell())
            }
            return [.unfroze]
        }
        var events: [Event] = []
        if case .crossfading = phase {
            events += completeCrossfade(at: now)
        }
        guard let id = currentPhotoID else { return events }
        isFrozen = true
        events.append(.froze(id: id))
        return events
    }

    /// Play/Pause: suspend / resume auto-advance. Pausing preserves the
    /// remaining dwell; resuming picks it back up from `now`.
    @discardableResult
    public mutating func togglePause(at now: TimeInterval) -> [Event] {
        if isPaused {
            isPaused = false
            if case .dwelling = phase, currentIndex != nil {
                phase = .dwelling(until: now + (pausedRemaining ?? drawDwell()))
            }
            pausedRemaining = nil
            return [.resumed]
        }
        isPaused = true
        if case .dwelling(let until) = phase {
            pausedRemaining = max(0, until - now)
        }
        return [.paused]
    }

    /// Hold: morph into the next photo now — a short dissolve through a
    /// coarser grid. Ignored while frozen (freeze wins) or mid-crossfade.
    @discardableResult
    public mutating func morph(at now: TimeInterval) -> [Event] {
        guard !isFrozen, case .dwelling = phase else { return [] }
        return beginCrossfade(at: now, duration: config.morphDuration, isMorph: true)
    }

    // MARK: - Internals

    private mutating func activateLane(at now: TimeInterval, emitLaneChange: Bool) -> [Event] {
        var events: [Event] = []
        if emitLaneChange { events.append(.laneChanged(lane)) }
        pausedRemaining = nil
        let pool = activePool
        guard !pool.isEmpty else {
            planner = nil
            currentIndex = nil
            upNextIndex = nil
            phase = .idle
            return events
        }
        var freshPlanner = SequencePlanner(
            count: pool.count,
            window: config.noRepeatWindow,
            seed: laneSeed(for: lane)
        )
        var current = freshPlanner.next()
        var frozeNow = false
        if let frozenID = pendingFrozenID, let frozenIndex = pool.firstIndex(of: frozenID) {
            pendingFrozenID = nil
            current = frozenIndex
            isFrozen = true
            frozeNow = true
        }
        currentIndex = current
        if pool.count > 1 {
            var next = freshPlanner.next()
            if next == current { next = freshPlanner.next() }
            upNextIndex = next
        } else {
            upNextIndex = nil
        }
        planner = freshPlanner
        phase = .dwelling(until: now + drawDwell())
        events.append(.photoChanged(id: pool[current]))
        if frozeNow { events.append(.froze(id: pool[current])) }
        return events
    }

    private mutating func beginCrossfade(
        at now: TimeInterval,
        duration: TimeInterval,
        isMorph: Bool
    ) -> [Event] {
        guard let fromID = currentPhotoID, let toID = upNextPhotoID else { return [] }
        phase = .crossfading(started: now, duration: duration, isMorph: isMorph)
        return [.crossfadeStarted(fromID: fromID, toID: toID, duration: duration, isMorph: isMorph)]
    }

    private mutating func completeCrossfade(at now: TimeInterval) -> [Event] {
        if let next = upNextIndex {
            currentIndex = next
        }
        if var activePlanner = planner, activePool.count > 1 {
            upNextIndex = activePlanner.next()
            planner = activePlanner
        } else {
            upNextIndex = nil
        }
        phase = .dwelling(until: now + drawDwell())
        guard let id = currentPhotoID else { return [] }
        return [.photoChanged(id: id)]
    }

    /// Draw the next dwell: seeded uniform in the speed's range, biased by
    /// style pacing, clamped to the PRD's 20–40 s envelope.
    private mutating func drawDwell() -> TimeInterval {
        let base = rng.nextDouble(in: speed.dwellRange)
        return min(config.maxDwell, max(config.minDwell, base * style.dwellBias))
    }

    private func laneSeed(for lane: Lane) -> UInt64 {
        let ordinal = UInt64(Lane.allCases.firstIndex(of: lane) ?? 0)
        return seed &+ (ordinal &+ 1) &* 0x9E37_79B9_7F4A_7C15
    }
}
