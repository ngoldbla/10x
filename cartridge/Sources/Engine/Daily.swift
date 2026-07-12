// Daily challenge mutators + feed ordering. Deterministic per (game, date):
// the whole world sees the same "Turbo Tuesday" you do.
import Foundation
import CouchCore

// MARK: - DayStamp

/// A calendar day as a value — the only clock the engine ever sees.
public struct DayStamp: Sendable, Equatable, Hashable, Codable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 2026, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Stable seed for this day (independent of process/hashing).
    public var seed: UInt64 {
        var z = UInt64(bitPattern: Int64(year)) &* 0x9E37_79B9_7F4A_7C15
        z ^= UInt64(bitPattern: Int64(month)) &* 0xC2B2_AE3D_27D4_EB4F
        z ^= UInt64(bitPattern: Int64(day)) &* 0x1656_67B1_9E37_79F9
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        return z ^ (z >> 31)
    }
}

// MARK: - Mutator

/// Seeded per-(game, day) parameter tweaks — the feed's freshness without
/// any generation infrastructure. All factors are bounded so no mutator can
/// make a game unfair; `identity` is the default difficulty bots must beat.
public struct Mutator: Sendable, Equatable, Codable {
    /// Scroll/steer speed multiplier.
    public var speed: Double
    /// Gravity/fall multiplier.
    public var gravity: Double
    /// Spawn-rate multiplier.
    public var spawn: Double
    /// Which sprite/backdrop palette lane the UI should use today.
    public var paletteID: Int

    public init(speed: Double, gravity: Double, spawn: Double, paletteID: Int) {
        self.speed = speed
        self.gravity = gravity
        self.spawn = spawn
        self.paletteID = paletteID
    }

    public static let identity = Mutator(speed: 1, gravity: 1, spawn: 1, paletteID: 0)

    public static let speedRange: ClosedRange<Double> = 0.85...1.2
    public static let gravityRange: ClosedRange<Double> = 0.85...1.2
    public static let spawnRange: ClosedRange<Double> = 0.85...1.2
    public static let paletteCount = 8

    /// Short human label for the cartridge chip ("Turbo day").
    public var label: String {
        let deviations: [(Double, String, String)] = [
            (speed, "Turbo day", "Lazy day"),
            (gravity, "Heavy day", "Floaty day"),
            (spawn, "Crowded day", "Calm day"),
        ]
        var best = (magnitude: 0.06, label: "Classic day")
        for (value, high, low) in deviations {
            let magnitude = abs(value - 1)
            if magnitude > best.magnitude {
                best = (magnitude, value > 1 ? high : low)
            }
        }
        return best.label
    }
}

// MARK: - DailyChallenge

public enum DailyChallenge {
    /// The mutator every player sees for `game` on `day`.
    public static func mutator(for game: GameID, on day: DayStamp) -> Mutator {
        var rng = SplitMix64(seed: day.seed ^ gameSalt(game))
        return Mutator(
            speed: rng.nextDouble(in: Mutator.speedRange),
            gravity: rng.nextDouble(in: Mutator.gravityRange),
            spawn: rng.nextDouble(in: Mutator.spawnRange),
            paletteID: rng.nextInt(below: Mutator.paletteCount)
        )
    }

    /// Today's featured game — always first in the feed.
    public static func featuredGame(on day: DayStamp) -> GameID {
        var rng = SplitMix64(seed: day.seed ^ 0xFEA7)
        return GameID.allCases[rng.nextInt(below: GameID.allCases.count)]
    }

    /// Deterministic feed order for the day: featured first, the rest in a
    /// seeded shuffle. Contains every game exactly once.
    public static func feedOrder(on day: DayStamp) -> [GameID] {
        let featured = featuredGame(on: day)
        var rest = GameID.allCases.filter { $0 != featured }
        var rng = SplitMix64(seed: day.seed ^ 0x0FEE_D0)
        // Fisher–Yates
        for i in stride(from: rest.count - 1, to: 0, by: -1) {
            let j = rng.nextInt(below: i + 1)
            rest.swapAt(i, j)
        }
        return [featured] + rest
    }

    private static func gameSalt(_ game: GameID) -> UInt64 {
        switch game {
        case .flap: return 0xF1A9
        case .noodle: return 0x2900_D1E
        case .quadrant: return 0x04AD
        case .putt: return 0x9077
        }
    }
}

// MARK: - ScoreBook

/// Bests bookkeeping, Codable for @CouchStored persistence.
public struct ScoreBook: Sendable, Equatable, Codable {
    public var bests: [String: Int]

    public init(bests: [String: Int] = [:]) {
        self.bests = bests
    }

    public func best(for game: GameID) -> Int {
        bests[game.rawValue] ?? 0
    }

    /// Records a finished round. Returns true when it set a new best.
    @discardableResult
    public mutating func record(_ score: Int, for game: GameID) -> Bool {
        if score > best(for: game) {
            bests[game.rawValue] = score
            return true
        }
        return false
    }
}
