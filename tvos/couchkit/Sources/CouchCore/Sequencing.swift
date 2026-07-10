import Foundation

/// No-repeat shuffle with a sliding window: each `next()` returns an index in
/// `0..<count` that has not appeared in the last `window` draws. Deterministic
/// for a given seed — ambient apps (Rabbit Ears, Cartridge) use this so a
/// resumed session replays the same channel order.
public struct SequencePlanner: Sendable {
    public let count: Int
    public let window: Int
    private var rng: SplitMix64
    private var recent: [Int] = []

    /// - Parameters:
    ///   - count: size of the pool (must be ≥ 1).
    ///   - window: how many recent draws are excluded. Clamped to `count - 1`
    ///     so there is always at least one eligible index.
    public init(count: Int, window: Int = 3, seed: UInt64) {
        precondition(count >= 1, "SequencePlanner needs a non-empty pool")
        self.count = count
        self.window = max(0, min(window, count - 1))
        self.rng = SplitMix64(seed: seed)
    }

    public mutating func next() -> Int {
        guard count > 1, window > 0 else {
            return count == 1 ? 0 : rng.nextInt(below: count)
        }
        var eligible = [Int]()
        eligible.reserveCapacity(count - recent.count)
        for i in 0..<count where !recent.contains(i) {
            eligible.append(i)
        }
        let pick = eligible[rng.nextInt(below: eligible.count)]
        recent.append(pick)
        if recent.count > window {
            recent.removeFirst(recent.count - window)
        }
        return pick
    }
}
