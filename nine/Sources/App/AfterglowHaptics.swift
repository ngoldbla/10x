// AfterglowHaptics.swift — the win celebration's haptic score (PRD-1 §3).
// Nine soft transient ticks crescendo as the shockwave crest crosses the
// board, landing one warm thump at 2.40s — exactly when the Solved chip
// fades in. iPhone only: the capabilities gate is false on iPad and in the
// simulator. First use of CoreHaptics in the Couch Suite.
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

            // Nine ticks riding the crest (0.25s → 2.15s), rising from a
            // whisper to nearly full, growing crisper as they build…
            var events = (0..<9).map { i -> CHHapticEvent in
                let progress = Float(i) / 8.0
                return CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.30 + 0.65 * progress),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35 + 0.35 * progress),
                    ],
                    relativeTime: 0.25 + Double(i) * 0.2375
                )
            }
            // …then one warm, round thump as the Solved chip lands.
            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15),
                ],
                relativeTime: 2.40,
                duration: 0.35
            ))

            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            engine.notifyWhenPlayersFinished { _ in
                // CoreHaptics calls this on its own queue; hop back to the
                // main actor before touching our state.
                Task { @MainActor [weak self] in self?.engine = nil }
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
