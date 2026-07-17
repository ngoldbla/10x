// AfterglowMotion.swift — gravity-tilt source for the glass trophy pane
// (PRD-1 §4). Wraps CMMotionManager and is *polled* once per frame from
// BoardView's timeline closure — never a handler, which would invalidate
// Observation every frame and drag CoreMotion callbacks across actors.
// Gravity needs no permission and no Info.plist key. First use of
// CoreMotion in the Couch Suite.
#if os(iOS)
import CoreMotion

@MainActor
final class AfterglowMotion {
    private let manager = CMMotionManager()
    private var baseline: SIMD2<Double>?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        baseline = nil
        manager.startDeviceMotionUpdates()
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        baseline = nil
    }

    /// Current tilt as a gravity delta from the pose captured on first read
    /// — the player's natural holding pose is neutral, not flat-on-table.
    /// Clamped to ±0.35 so the sheen always feels like glass catching
    /// light, never a gimmick. Returns .zero (a calm, centered highlight)
    /// until motion data flows — including in the simulator.
    func tilt(at _: Date) -> SIMD2<Double> {
        guard let gravity = manager.deviceMotion?.gravity else { return .zero }
        let current = SIMD2(gravity.x, gravity.y)
        guard let baseline else {
            self.baseline = current
            return .zero
        }
        let delta = current - baseline
        return SIMD2(
            min(max(delta.x, -0.35), 0.35),
            min(max(delta.y, -0.35), 0.35)
        )
    }
}
#endif
