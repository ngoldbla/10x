import Foundation

/// Deterministic SplitMix64 PRNG.
///
/// Every stochastic decision in CouchKit flows through this generator so that
/// `same input + same seed ⇒ identical output`, which the Darkroom puzzle
/// compiler and resumable ambient sessions depend on. Never substitute
/// `SystemRandomNumberGenerator` anywhere in the render pipeline.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `[0, 1)`.
    public mutating func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform in `range`.
    public mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextDouble() * (range.upperBound - range.lowerBound)
    }

    /// Uniform integer in `0..<bound` (bound must be > 0).
    public mutating func nextInt(below bound: Int) -> Int {
        precondition(bound > 0, "bound must be positive")
        return Int(next() % UInt64(bound))
    }
}

/// Stateless deterministic 2-D hash noise in `[0, 1)`. Used for film grain,
/// dithering and star fields; cheaper than carrying a PRNG per pixel.
public enum CouchHash {
    public static func noise(_ x: Int, _ y: Int, seed: UInt64) -> Double {
        var z = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        z ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        z ^= seed &* 0x1656_67B1_9E37_79F9
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
