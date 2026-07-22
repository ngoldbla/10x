// AfterglowScoreTiming.swift — the Afterglow haptic score as pure numbers
// (PRD-1 §3, refactored for PRD-5 §4 Step 3).
//
// The *timing* of the celebration lives here, in plain Foundation with no
// CoreHaptics import, for two reasons:
//   • It compiles and unit-tests anywhere (Linux CI, the simulator, a Mac with
//     no haptic hardware) — the pattern builders in `AfterglowScore` turn these
//     numbers into `CHHapticPattern`s only where CoreHaptics exists.
//   • It is the single source of truth the iPhone `AfterglowHaptics` and the
//     tvOS controller haptics both build from, so the crescendo can never drift
//     between the two (the refactor's load-bearing invariant — see the
//     `AfterglowScoreTimingTests` that pin every value).
//
// Do not "clean up" the magic numbers: the nine-tick crescendo (0.25s → 2.15s)
// and the warm 2.40s thump are the exact values iPhones have shipped since
// PRD-1, matched frame-for-frame to the on-screen shockwave.
import Foundation

enum AfterglowScoreTiming {
    /// One transient tap: when it fires and how it feels.
    struct Tick: Equatable {
        let time: TimeInterval
        let intensity: Double
        let sharpness: Double
    }

    /// A warm continuous swell (the solve thump).
    struct Swell: Equatable {
        let time: TimeInterval
        let duration: TimeInterval
        let intensity: Double
        let sharpness: Double
    }

    // MARK: Solve — the signature crescendo (must match PRD-1 exactly)

    /// Nine transient ticks riding the shockwave crest (0.25s → 2.15s), rising
    /// from a whisper to nearly full and growing crisper as they build.
    static let solveTicks: [Tick] = (0..<9).map { i in
        let progress = Double(i) / 8.0
        return Tick(
            time: 0.25 + Double(i) * 0.2375,
            intensity: 0.30 + 0.65 * progress,
            sharpness: 0.35 + 0.35 * progress
        )
    }

    /// One warm, round thump as the Solved chip lands at 2.40s.
    static let solveThump = Swell(time: 2.40, duration: 0.35, intensity: 0.6, sharpness: 0.15)

    // MARK: In-play ticks (PRD-5 §2.2) — quiet by design

    /// A whisper on every digit placement.
    static let placementTick = Tick(time: 0, intensity: 0.32, sharpness: 0.55)

    /// A soft double-knock on an error placement (only when error highlight is
    /// on). Two close taps so it reads as a distinct "that's wrong".
    static let errorKnock: [Tick] = [
        Tick(time: 0, intensity: 0.55, sharpness: 0.30),
        Tick(time: 0.11, intensity: 0.55, sharpness: 0.30),
    ]

    /// One crisp detent per box crossed while gliding the cursor.
    static let boxDetent = Tick(time: 0, intensity: 0.40, sharpness: 0.70)
}
