import Foundation

// Coordinate convention for all of RemoteKit's math: +x is right, +y is UP
// (matching GCMicroGamepad's dpad axes). Angles are degrees counterclockwise
// from +x, normalized to [0, 360).

/// Discrete four-way swipe.
public enum Direction4: String, CaseIterable, Sendable, Codable, Hashable {
    case right, up, left, down
}

/// The 3×3 flick rose: eight directions plus center (tap). Load-bearing for
/// Nine's digit entry — 1..9 map onto this.
public enum Direction8OrCenter: String, CaseIterable, Sendable, Codable, Hashable {
    case center
    case right, upRight, up, upLeft, left, downLeft, down, downRight
}

/// What a given remote can express. First-gen remotes lack reliable analog
/// dpad data, so apps must offer a degraded path when this is `.fourWay`.
public enum RemoteCapability: String, Sendable, Codable, Hashable {
    case fourWay, eightWay
}

/// Outcome of classifying one stroke.
/// `.ambiguous` means the vector fell inside the forgiveness cone around a
/// sector boundary — apps should ignore it rather than misfire.
/// `.rest` means the touch was rejected as a resting/repositioning thumb.
public enum FlickClassification<Direction: Sendable & Hashable>: Sendable, Hashable {
    case direction(Direction)
    case ambiguous
    case rest
}

/// Tunable gates for accepting a stroke as intentional.
public struct FlickThresholds: Sendable, Equatable {
    /// Minimum travel (normalized clickpad units; full pad ≈ 2.0 across).
    public var minDistance: Double
    /// Minimum mean speed in units/second — a slow long drag is a thumb
    /// repositioning, not a flick.
    public var minVelocity: Double
    /// Touches shorter than this with sub-threshold travel are taps
    /// (`.center` on the rose); longer ones are rest touches.
    public var tapMaxDuration: TimeInterval
    /// Half-width of the forgiveness cone around sector boundaries, degrees.
    public var ambiguityCone: Double

    public init(
        minDistance: Double = 0.25,
        minVelocity: Double = 1.2,
        tapMaxDuration: TimeInterval = 0.30,
        ambiguityCone: Double = 8
    ) {
        self.minDistance = minDistance
        self.minVelocity = minVelocity
        self.tapMaxDuration = tapMaxDuration
        self.ambiguityCone = ambiguityCone
    }

    public static let standard = FlickThresholds()
}

/// Pure stroke-classification math. The SwiftUI/GameController layer feeds
/// vectors in; nothing here touches an event API.
public enum FlickClassifier {

    /// Angle of `(dx, dy)` in degrees, `[0, 360)`.
    public static func angleDegrees(dx: Double, dy: Double) -> Double {
        var deg = atan2(dy, dx) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg.truncatingRemainder(dividingBy: 360)
    }

    // MARK: Geometry only (assumes the stroke was already accepted)

    /// Four-way classification. Sector centers at 0/90/180/270; boundaries on
    /// the diagonals. Within `cone` degrees of a boundary → `.ambiguous`.
    public static func direction4(
        dx: Double, dy: Double, cone: Double = FlickThresholds.standard.ambiguityCone
    ) -> FlickClassification<Direction4> {
        let deg = angleDegrees(dx: dx, dy: dy)
        let m = deg.truncatingRemainder(dividingBy: 90)
        if abs(m - 45) < cone { return .ambiguous }
        let sectors: [Direction4] = [.right, .up, .left, .down]
        return .direction(sectors[Int((deg / 90).rounded()) % 4])
    }

    /// Eight-way classification. Sector centers every 45°; boundaries at
    /// 22.5° + k·45°. Within `cone` degrees of a boundary → `.ambiguous`.
    public static func direction8(
        dx: Double, dy: Double, cone: Double = FlickThresholds.standard.ambiguityCone
    ) -> FlickClassification<Direction8OrCenter> {
        let deg = angleDegrees(dx: dx, dy: dy)
        let m = deg.truncatingRemainder(dividingBy: 45)
        if abs(m - 22.5) < cone { return .ambiguous }
        let sectors: [Direction8OrCenter] = [
            .right, .upRight, .up, .upLeft, .left, .downLeft, .down, .downRight,
        ]
        return .direction(sectors[Int((deg / 45).rounded()) % 8])
    }

    // MARK: Full classification (rest-touch rejection + geometry)

    /// Classify a completed stroke for the four-way grammar.
    public static func classify4(
        dx: Double, dy: Double, duration: TimeInterval,
        thresholds: FlickThresholds = .standard
    ) -> FlickClassification<Direction4> {
        switch gate(dx: dx, dy: dy, duration: duration, thresholds: thresholds) {
        case .rejected: return .rest
        case .tap: return .rest // a bare tap is `.click`, not a swipe
        case .accepted: return direction4(dx: dx, dy: dy, cone: thresholds.ambiguityCone)
        }
    }

    /// Classify a completed stroke for the 3×3 rose. A quick touch with
    /// sub-threshold travel is `.center`; a lingering one is `.rest`.
    public static func classify8(
        dx: Double, dy: Double, duration: TimeInterval,
        thresholds: FlickThresholds = .standard
    ) -> FlickClassification<Direction8OrCenter> {
        switch gate(dx: dx, dy: dy, duration: duration, thresholds: thresholds) {
        case .rejected: return .rest
        case .tap: return .direction(.center)
        case .accepted: return direction8(dx: dx, dy: dy, cone: thresholds.ambiguityCone)
        }
    }

    enum Gate { case accepted, tap, rejected }

    static func gate(
        dx: Double, dy: Double, duration: TimeInterval, thresholds: FlickThresholds
    ) -> Gate {
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance < thresholds.minDistance {
            return duration <= thresholds.tapMaxDuration ? .tap : .rejected
        }
        let velocity = distance / max(duration, 0.001)
        return velocity >= thresholds.minVelocity ? .accepted : .rejected
    }
}

/// Sticky sector classification for continuous input (drag-fill streams,
/// on-screen rose highlighting). Once inside a sector, the angle must leave
/// it by `marginDegrees` beyond the boundary before the output switches —
/// no flicker while riding a boundary.
public struct SectorHysteresis: Sendable, Equatable {
    public let sectorCount: Int
    public let marginDegrees: Double
    public private(set) var current: Int?

    public init(sectorCount: Int, marginDegrees: Double = 6) {
        precondition(sectorCount > 0)
        self.sectorCount = sectorCount
        self.marginDegrees = marginDegrees
    }

    /// Sector index (0 = centered on 0°, counterclockwise) for `angle`,
    /// with stickiness toward the previously reported sector.
    public mutating func classify(angleDegrees angle: Double) -> Int {
        let width = 360.0 / Double(sectorCount)
        var deg = angle.truncatingRemainder(dividingBy: 360)
        if deg < 0 { deg += 360 }
        let naive = Int((deg / width).rounded()) % sectorCount
        guard let held = current else {
            current = naive
            return naive
        }
        let center = Double(held) * width
        var delta = abs(deg - center).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta = 360 - delta }
        if delta <= width / 2 + marginDegrees { return held }
        current = naive
        return naive
    }

    public mutating func reset() { current = nil }
}

/// Turns a continuous touch delta stream into discrete grid steps — the
/// drag-fill primitive Darkroom uses to paint runs of cells.
public struct CellStepAccumulator: Sendable, Equatable {
    /// Travel (normalized units) required per emitted cell step.
    public let cellSize: Double
    private var accX = 0.0
    private var accY = 0.0

    public init(cellSize: Double = 0.28) {
        precondition(cellSize > 0)
        self.cellSize = cellSize
    }

    /// Feed a movement delta; returns whole-cell steps to apply (may be zero).
    public mutating func accumulate(dx: Double, dy: Double) -> (x: Int, y: Int) {
        accX += dx
        accY += dy
        let sx = Int(accX / cellSize)
        let sy = Int(accY / cellSize)
        accX -= Double(sx) * cellSize
        accY -= Double(sy) * cellSize
        return (sx, sy)
    }

    public mutating func reset() {
        accX = 0
        accY = 0
    }
}
