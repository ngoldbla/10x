// WatchCelebration.swift — the haptic mini-score (PRD-6 §2.4).
//
// watchOS has no SwiftUI shaders, so the Afterglow's three-layer celebration
// cannot follow the board onto the wrist. What does follow is the Canvas-drawn
// luminance wave (`BoardView` draws it whenever `waveOrigin` is nil, which is
// always here) — and the wrist has one thing no other Nine surface has, which
// is a haptic engine touching skin.
//
// So the celebration is the wave plus a mini-score riding it: three rising
// clicks through the crest, `.success` as the Solved chip lands. The timings
// are read from `AfterglowScoreTiming`, the same shared table the iOS solve
// score already uses, rather than re-typed here — the two celebrations are the
// same event and should stay the same length.
#if os(watchOS)
import Foundation
import SwiftUI
import WatchKit

@MainActor
enum WatchCelebration {

    /// Play the score for a solve that happened `at`.
    ///
    /// Cancellable by construction: it is a `Task` the caller owns, and every
    /// step checks. A player who taps away mid-celebration must not feel a
    /// buzz from a screen they have left — the same defect PRD-12 found in
    /// the share card's 2.4s sleep.
    static func play() async {
        var elapsed: TimeInterval = 0
        for beat in beats {
            try? await Task.sleep(for: .milliseconds(Int((beat.time - elapsed) * 1000)))
            guard !Task.isCancelled else { return }
            elapsed = beat.time
            WKInterfaceDevice.current().play(beat.haptic)
        }
    }

    /// Three rising clicks and the thump, at times taken from the shared table
    /// rather than chosen again.
    ///
    /// `WKHaptic` has no intensity or sharpness — it is a fixed vocabulary of
    /// named feelings, where the iPhone's engine takes a curve. So the wrist
    /// cannot play the nine-tick crescendo; what it can do is keep the same
    /// *shape* and the same *length*. Ticks 0, 4 and 8 are the crest's first,
    /// middle and last, so three clicks span exactly the interval nine would,
    /// and `.success` lands on the thump at 2.40s with the Solved chip — the
    /// value PRD-1 froze and every platform has shipped since.
    static let beats: [(time: TimeInterval, haptic: WKHapticType)] = {
        let ticks = AfterglowScoreTiming.solveTicks
        let crest = [ticks[0], ticks[ticks.count / 2], ticks[ticks.count - 1]]
        return crest.map { ($0.time, WKHapticType.click) }
            + [(AfterglowScoreTiming.solveThump.time, .success)]
    }()

    /// When the Solved chip lands, in seconds after the solve. Shared with
    /// every other platform rather than chosen again.
    static let chipDelay = AfterglowScoreTiming.solveThump.time
}
#endif
