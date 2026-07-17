// Scoring.swift — points and the solve-history log. Pure and Codable like
// the rest of the engine: the app persists a SolveHistory value as-is and
// mirrors totals into Game Center; nothing here touches UI or wall clocks.
import Foundation

/// Points awarded for one solved board. The values are deliberately chunky
/// (100-point base steps) so a session's total feels like a score, not a
/// checksum.
public enum SolveScore {
    /// Longest streak that still grows the daily bonus (30 days).
    public static let streakBonusCap = 30
    /// Solves faster than this earn the speed bonus.
    public static let speedBonusThreshold: TimeInterval = 300

    public static func points(
        difficulty: Difficulty,
        isDaily: Bool,
        streak: Int,
        seconds: TimeInterval
    ) -> Int {
        var points: Int
        switch difficulty {
        case .gentle: points = 100
        case .steady: points = 250
        case .sharp: points = 500
        }
        if isDaily {
            points += 50 + 25 * max(0, min(streak, streakBonusCap))
        }
        if seconds > 0, seconds < speedBonusThreshold {
            points += 50
        }
        return points
    }
}

/// One finished board.
public struct SolveRecord: Sendable, Codable, Equatable, Identifiable {
    public var id: Double { date.timeIntervalSinceReferenceDate }
    public let date: Date
    public let difficulty: Difficulty
    public let isDaily: Bool
    public let seconds: TimeInterval
    public let points: Int

    public init(date: Date, difficulty: Difficulty, isDaily: Bool, seconds: TimeInterval, points: Int) {
        self.date = date
        self.difficulty = difficulty
        self.isDaily = isDaily
        self.seconds = seconds
        self.points = points
    }
}

/// The rolling log of finished boards, newest first, capped so the value
/// stays small enough to mirror through iCloud KVS alongside the streak.
public struct SolveHistory: Sendable, Codable, Equatable {
    public static let capacity = 200

    public private(set) var records: [SolveRecord]

    public init() {
        records = []
    }

    public mutating func record(_ record: SolveRecord) {
        records.insert(record, at: 0)
        if records.count > Self.capacity {
            records.removeLast(records.count - Self.capacity)
        }
    }

    public var totalPoints: Int {
        records.reduce(0) { $0 + $1.points }
    }

    public func count(of difficulty: Difficulty) -> Int {
        records.count(where: { $0.difficulty == difficulty })
    }

    /// Fastest recorded solve of this difficulty, nil when none exist.
    public func bestSeconds(for difficulty: Difficulty) -> TimeInterval? {
        records.lazy.filter { $0.difficulty == difficulty }.map(\.seconds).min()
    }
}
