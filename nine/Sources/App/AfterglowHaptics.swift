// AfterglowHaptics.swift — the win celebration's haptic score (PRD-1 §3),
// refactored into a shared pattern factory (PRD-5 §4 Step 3).
//
// Three layers, cleanly separated so the crescendo can never drift:
//   • `AfterglowScoreTiming` (Sources/Shared) — the pure numbers, testable
//     without hardware.
//   • `AfterglowScore` (here, `canImport(CoreHaptics)`) — pure `CHHapticPattern`
//     builders that turn those numbers into patterns. No engine, no device.
//   • The players — iPhone `AfterglowHaptics` runs the patterns through a
//     `CHHapticEngine`; tvOS `ControllerHaptics` runs the *same* patterns
//     through the `GCDeviceHaptics` engines PadKit vends. One score, two hands.
#if canImport(CoreHaptics)
import CoreHaptics

/// Pure `CHHapticPattern` builders shared by every player. Building a pattern
/// touches no hardware and starts no engine, so these are safe to call on any
/// device that has the CoreHaptics headers (the capabilities gate lives in the
/// players, where an engine is actually created).
enum AfterglowScore {

    /// The signature solve pattern: nine transient ticks crescendo 0.25s→2.15s,
    /// then one warm 0.35s thump at 2.40s. Values come straight from
    /// `AfterglowScoreTiming` (pinned by unit test) so iPhone and controller
    /// play the identical score.
    static func solvePattern() throws -> CHHapticPattern {
        var events = AfterglowScoreTiming.solveTicks.map { tick in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(tick.intensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(tick.sharpness)),
                ],
                relativeTime: tick.time
            )
        }
        let thump = AfterglowScoreTiming.solveThump
        events.append(CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(thump.intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(thump.sharpness)),
            ],
            relativeTime: thump.time,
            duration: thump.duration
        ))
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// A whisper transient on digit placement.
    static func placementTick() throws -> CHHapticPattern {
        try CHHapticPattern(events: [transient(AfterglowScoreTiming.placementTick)], parameters: [])
    }

    /// A soft double-knock on an error placement.
    static func errorKnock() throws -> CHHapticPattern {
        try CHHapticPattern(events: AfterglowScoreTiming.errorKnock.map(transient), parameters: [])
    }

    /// One detent tick per box crossed while gliding.
    static func boxDetent() throws -> CHHapticPattern {
        try CHHapticPattern(events: [transient(AfterglowScoreTiming.boxDetent)], parameters: [])
    }

    private static func transient(_ tick: AfterglowScoreTiming.Tick) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(tick.intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(tick.sharpness)),
            ],
            relativeTime: tick.time
        )
    }
}
#endif

// MARK: - iPhone player

#if os(iOS)
import CoreHaptics

@MainActor
final class AfterglowHaptics {
    private var engine: CHHapticEngine?

    /// Create the engine at solve time — cold start is tens of ms, hidden
    /// under a 2.6s animation, and there is no warm engine to babysit.
    /// Every throw is swallowed: haptics must never break the celebration.
    func playSolveScore() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            try engine.start()
            let player = try engine.makePlayer(with: AfterglowScore.solvePattern())
            engine.notifyWhenPlayersFinished { @Sendable [weak self] _ in
                // CoreHaptics calls this on its own queue, so the handler
                // must stay nonisolated (@Sendable) — a plain closure here
                // inherits @MainActor isolation and traps on entry under
                // Swift 6. Hop to the main actor before touching our state.
                Task { @MainActor in self?.engine = nil }
                return .stopEngine
            }
            try player.start(atTime: CHHapticTimeImmediate)
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    /// Cut the score early (backgrounding mid-pattern); safe to call twice.
    func stop() {
        engine?.stop()
        engine = nil
    }
}
#endif

// MARK: - tvOS controller player

#if os(tvOS)
import CouchKit
#if canImport(CoreHaptics)
import CoreHaptics
#endif

/// Plays the Afterglow score in the player's hands through the controller's
/// `GCDeviceHaptics` engines (PRD-5 §2.2). PadKit owns the engine lifecycle
/// (`PadHaptics`); this owns the *when* — a whisper on placement, a double-knock
/// on an error placement, a detent per box crossed gliding, the full crescendo
/// on solve. Silenced entirely by the "Controller haptics" pref.
@MainActor
final class ControllerHaptics {
    #if canImport(GameController) && canImport(CoreHaptics)
    private let provider: PadHaptics
    #endif

    /// Mirrors `NinePrefs.controllerHaptics`; when false every play is a no-op.
    var enabled = true

    #if canImport(GameController) && canImport(CoreHaptics)
    init(provider: PadHaptics) {
        self.provider = provider
    }
    #else
    init() {}
    #endif

    func placement() { play { try AfterglowScore.placementTick() } }
    func error() { play { try AfterglowScore.errorKnock() } }
    func detent() { play { try AfterglowScore.boxDetent() } }
    func solve() { play { try AfterglowScore.solvePattern() } }

    #if canImport(GameController) && canImport(CoreHaptics)
    private func play(_ build: () throws -> CHHapticPattern) {
        guard enabled, let engine = provider.engine() else { return }
        do {
            let player = try engine.makePlayer(with: build())
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Xbox pads with no CoreHaptics fidelity fail soft — CoreHaptics
            // degrades a transient to a rumble automatically; a throw means no
            // engine at all, and silence is fine.
        }
    }
    #else
    private func play(_ build: () throws -> Any) {}
    #endif
}
#endif
