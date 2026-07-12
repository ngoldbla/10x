// The hall: true black, a floor pool of light, and a slow volumetric light
// sweep. Verdicts are choreographed lighting — the room warms gold on
// correct, cools and dims on wrong. No badges.
import SwiftUI
import CouchKit

struct StageBackground: View {
    let mood: AppModel.Mood
    let reduceFlash: Bool
    var sweepPaused = false

    var body: some View {
        ZStack {
            CouchPalette.void

            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: sweepPaused)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let x = 0.5 + 0.42 * sin(t * 2 * .pi / 26) // one sweep ≈ 26s
                ZStack {
                    // Floor glow — deep ink pooling at the stage apron.
                    EllipticalGradient(
                        colors: [Color(red: 0.08, green: 0.085, blue: 0.12), .clear],
                        center: UnitPoint(x: 0.5, y: 1.08),
                        startRadiusFraction: 0,
                        endRadiusFraction: 0.9
                    )
                    // The light sweep.
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(reduceFlash ? 0.035 : 0.06),
                            .clear,
                        ],
                        startPoint: UnitPoint(x: x - 0.28, y: -0.2),
                        endPoint: UnitPoint(x: x + 0.28, y: 1.2)
                    )
                }
            }

            // Verdict lighting.
            Color(red: 1.0, green: 0.72, blue: 0.25)
                .opacity(mood == .gold ? (reduceFlash ? 0.10 : 0.18) : 0)
            Color(red: 0.16, green: 0.25, blue: 0.5)
                .opacity(mood == .cool ? (reduceFlash ? 0.07 : 0.14) : 0)
            Color.black
                .opacity(mood == .cool ? (reduceFlash ? 0.15 : 0.28) : 0)
        }
        .animation(reduceFlash ? .couchAmbient : .couchFast, value: mood)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
