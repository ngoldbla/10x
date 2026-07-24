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

/// One day's worth of solves, for the History heat grid. `hasDaily` lights
/// the cell at full accent strength (a daily solve is the streak-worthy one).
public struct DaySolves: Sendable, Equatable {
    public let count: Int
    public let hasDaily: Bool
    public init(count: Int, hasDaily: Bool) {
        self.count = count
        self.hasDaily = hasDaily
    }
}

/// The rolling log of finished boards, newest first, capped so the value
/// stays small enough to mirror through iCloud KVS alongside the streak.
/// 1000 records ≈ 110 KB — a daily solver fills 200 in ~7 months and the
/// heat grid would silently truncate, so the ceiling is generous (PRD-9 §3).
public struct SolveHistory: Sendable, Codable, Equatable {
    public static let capacity = 1000

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

    /// Mean solve time for this difficulty, nil when none exist.
    public func averageSeconds(for difficulty: Difficulty) -> TimeInterval? {
        let times = records.lazy.filter { $0.difficulty == difficulty }.map(\.seconds)
        var sum: TimeInterval = 0
        var n = 0
        for t in times { sum += t; n += 1 }
        return n == 0 ? nil : sum / TimeInterval(n)
    }

    /// Buckets solves by their local day ordinal within `ordinalRange`. Days
    /// with no solves are absent; the caller defaults them to an empty cell.
    public func solvesByDay(
        ordinalRange: ClosedRange<Int>,
        calendar: Calendar = .current
    ) -> [Int: DaySolves] {
        var byDay: [Int: (count: Int, hasDaily: Bool)] = [:]
        for record in records {
            let ordinal = DailySeed.dayOrdinal(for: record.date, calendar: calendar)
            guard ordinalRange.contains(ordinal) else { continue }
            var entry = byDay[ordinal] ?? (0, false)
            entry.count += 1
            entry.hasDaily = entry.hasDaily || record.isDaily
            byDay[ordinal] = entry
        }
        return byDay.mapValues { DaySolves(count: $0.count, hasDaily: $0.hasDaily) }
    }

    /// Rolling-mean solve-time trend over the most recent `window` solves,
    /// oldest→newest, for the History sparkline. Smoothed by a trailing
    /// sub-window so one fast solve nudges the line rather than spiking it.
    /// Empty below two solves (nothing to trend).
    public func trend(window: Int) -> [TimeInterval] {
        // records is newest-first; take the last `window`, chronological.
        let recent = Array(records.prefix(max(0, window)).reversed()).map(\.seconds)
        guard recent.count >= 2 else { return [] }
        let sub = max(1, recent.count / 4)
        return recent.indices.map { i in
            let lower = max(0, i - sub + 1)
            let slice = recent[lower...i]
            return slice.reduce(0, +) / TimeInterval(slice.count)
        }
    }
}
