// Darkroom engine — daily roll planning + streaks (PRD §4.1, §5.4).
//
// Pure scheduling math: which photos each slot should try (deterministic
// per-day shuffle), which compiled puzzle best matches the slot's target
// band, and calendar-day streak accounting.
import Foundation
import CouchCore

public enum DailyRoll {

    /// Seed for a calendar day: `yyyymmdd`. Same day ⇒ same roll.
    public static func dateSeed(
        for date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> UInt64 {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let year: Int = c.year ?? 2000
        let month: Int = c.month ?? 1
        let day: Int = c.day ?? 1
        return UInt64(year * 10_000 + month * 100 + day)
    }

    /// Deterministic candidate order for one slot: a seeded Fisher–Yates
    /// shuffle of the curated photo indices, distinct per slot so the three
    /// plates prefer different photos.
    public static func photoOrder(count: Int, slot: GridSize, dateSeed: UInt64) -> [Int] {
        guard count > 0 else { return [] }
        var rng = SplitMix64(seed: dateSeed &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(slot.rawValue))
        var order = Array(0..<count)
        for i in stride(from: count - 1, to: 0, by: -1) {
            order.swapAt(i, rng.nextInt(below: i + 1))
        }
        return order
    }

    /// Among compiled candidates, the one whose band is closest to the
    /// slot's target; earlier candidates win ties (they were rolled first).
    public static func select(from puzzles: [Puzzle], target: DifficultyBand) -> Puzzle? {
        var best: Puzzle?
        var bestDistance = Int.max
        for puzzle in puzzles {
            let distance = abs(puzzle.band.rawValue - target.rawValue)
            if distance < bestDistance {
                best = puzzle
                bestDistance = distance
            }
        }
        return best
    }
}

// MARK: - Streaks

/// Consecutive days with ≥ 1 develop (PRD §4.1). Calendar-day based.
public struct StreakState: Sendable, Codable, Equatable {
    public var count: Int
    /// Day number (see `Streaks.dayNumber`) of the most recent develop.
    public var lastDay: Int?

    public init(count: Int = 0, lastDay: Int? = nil) {
        self.count = count
        self.lastDay = lastDay
    }
}

public enum Streaks {

    /// Whole calendar days since the reference date, in the calendar's zone.
    /// Consecutive dates differ by exactly 1, across months and DST.
    public static func dayNumber(
        for date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Int {
        let reference = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let day = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: reference, to: day).day ?? 0
    }

    /// State after a develop on `day`. Same-day develops are idempotent;
    /// a one-day gap extends; anything longer restarts at 1.
    public static func recordingDevelop(_ state: StreakState, day: Int) -> StreakState {
        guard let last = state.lastDay else {
            return StreakState(count: 1, lastDay: day)
        }
        if day == last { return state }
        if day == last + 1 { return StreakState(count: state.count + 1, lastDay: day) }
        if day < last { return state } // clock moved backwards: keep what's earned
        return StreakState(count: 1, lastDay: day)
    }

    /// The streak to display today: 0 once a full day has lapsed.
    public static func effectiveStreak(_ state: StreakState, today: Int) -> Int {
        guard let last = state.lastDay else { return 0 }
        return today <= last + 1 ? state.count : 0
    }
}
