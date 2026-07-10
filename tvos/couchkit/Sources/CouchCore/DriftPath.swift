import Foundation

/// A drift sample: normalized pan offsets (fractions of the view size) and a
/// zoom factor.
public struct DriftState: Sendable, Equatable {
    public var offsetX: Double
    public var offsetY: Double
    public var zoom: Double

    public init(offsetX: Double, offsetY: Double, zoom: Double) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.zoom = zoom
    }

    public static let identity = DriftState(offsetX: 0, offsetY: 0, zoom: 1)
}

/// Deterministic Ken Burns: a seeded pair of incommensurate Lissajous
/// oscillators for pan plus a slow breathing zoom. Pure function of time, so
/// an ambient session can resume mid-drift after relaunch and land on the
/// exact same frame.
public struct DriftPath: Sendable, Equatable {
    public let seed: UInt64
    /// Peak pan as a fraction of the view dimension (0.04 ≈ 4% of width).
    public let maxOffset: Double
    public let zoomRange: ClosedRange<Double>
    /// Nominal loop period in seconds; actual axis periods are seeded
    /// perturbations of it so the path never visibly repeats.
    public let period: TimeInterval

    private let freqX: Double
    private let freqY: Double
    private let freqZ: Double
    private let phaseX: Double
    private let phaseY: Double
    private let phaseZ: Double

    public init(
        seed: UInt64,
        maxOffset: Double = 0.045,
        zoomRange: ClosedRange<Double> = 1.03...1.12,
        period: TimeInterval = 48
    ) {
        self.seed = seed
        self.maxOffset = maxOffset
        self.zoomRange = zoomRange
        self.period = max(1, period)
        var rng = SplitMix64(seed: seed)
        freqX = 1 / (self.period * rng.nextDouble(in: 0.8...1.25))
        freqY = 1 / (self.period * rng.nextDouble(in: 1.15...1.7))
        freqZ = 1 / (self.period * rng.nextDouble(in: 1.6...2.3))
        phaseX = rng.nextDouble(in: 0...(2 * .pi))
        phaseY = rng.nextDouble(in: 0...(2 * .pi))
        phaseZ = rng.nextDouble(in: 0...(2 * .pi))
    }

    /// The drift state at time `t` (seconds; any monotonic origin works).
    public func state(at t: TimeInterval) -> DriftState {
        let ox = maxOffset * sin(2 * .pi * freqX * t + phaseX)
        let oy = maxOffset * 0.7 * sin(2 * .pi * freqY * t + phaseY)
        let zt = 0.5 + 0.5 * sin(2 * .pi * freqZ * t + phaseZ)
        let zoom = zoomRange.lowerBound + zt * (zoomRange.upperBound - zoomRange.lowerBound)
        return DriftState(offsetX: ox, offsetY: oy, zoom: zoom)
    }
}
