// AfterglowPointer.swift — the Mac's answer to the glass-trophy tilt (PRD-4
// §2.6). CoreMotion has no meaning on a desktop, so on macOS the *pointer* is
// the tilt: hovering the solved board steers the specular highlight. This maps
// a hover position over the board into the same `SIMD2<Double>` seam that
// `BoardView.afterglowTilt` consumes on iOS (where `AfterglowMotion` feeds it
// gravity) — clamped to the identical ±0.35 range so the sheen reads as glass
// catching light on both platforms.
//
// Polled once per frame from BoardView's timeline closure, never a handler —
// same discipline as AfterglowMotion (no Observation invalidation per frame).
#if os(macOS)
import Foundation
import CoreGraphics

@MainActor
final class AfterglowPointer {
    /// The latest tilt, updated as the pointer moves over the solved board.
    /// Held (not zeroed) when the pointer leaves, so the highlight rests
    /// where the hand last left it rather than snapping to center.
    private var offset: SIMD2<Double> = .zero

    /// Feed a hover location in board-local points (nil when the pointer is
    /// off the board). The board center maps to a centered highlight; the
    /// edges map to the ±0.35 extremes, matching AfterglowMotion's clamp.
    func update(hover: CGPoint?, boardSide: CGFloat) {
        guard let hover, boardSide > 0 else { return }
        let nx = Double(hover.x / boardSide) * 2 - 1   // −1 … 1 across the board
        let ny = Double(hover.y / boardSide) * 2 - 1
        offset = SIMD2(
            min(max(nx * 0.35, -0.35), 0.35),
            min(max(-ny * 0.35, -0.35), 0.35)   // screen +y is down; tilt +y up
        )
    }

    /// Current tilt for the sheen shader. Signature mirrors
    /// `AfterglowMotion.tilt(at:)` so BoardView's `afterglowTilt` closure is
    /// platform-agnostic.
    func tilt(at _: Date) -> SIMD2<Double> { offset }
}
#endif
