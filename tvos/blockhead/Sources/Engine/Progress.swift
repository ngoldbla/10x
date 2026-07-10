// Solo streak logic and the archive model. Pure Swift.
import Foundation

// MARK: - Streak

/// Wordle-shaped streak: only *on-time* completions (played on the episode's
/// own day) count. Late archive plays are welcome but streak-honest — they
/// never extend the flame.
public struct StreakState: Sendable, Equatable, Codable {
    public private(set) var length: Int
    public private(set) var lastOnTimeDay: Int?

    public init(length: Int = 0, lastOnTimeDay: Int? = nil) {
        self.length = length
        self.lastOnTimeDay = lastOnTimeDay
    }

    /// Record a completed episode. No-op unless it was played on its own day.
    public mutating func recordCompletion(day: Int, playedDay: Int) {
        guard day == playedDay else { return }
        if let last = lastOnTimeDay {
            if day == last { return }                    // replaying tonight
            length = (day == last + 1) ? length + 1 : 1  // extend or restart
        } else {
            length = 1
        }
        lastOnTimeDay = day
    }

    /// The streak as it should read today: yesterday's flame still burns
    /// (tonight is playable); older flames are out.
    public func current(asOf today: Int) -> Int {
        guard let last = lastOnTimeDay else { return 0 }
        return today <= last + 1 ? length : 0
    }

    /// True when tonight's episode has already been completed on time.
    public func completedTonight(_ today: Int) -> Bool {
        lastOnTimeDay == today
    }
}

// MARK: - Archive

/// One past night on the archive shelf.
public struct ArchiveEntry: Sendable, Equatable, Identifiable {
    public let dayNumber: Int
    public let episodeNumber: Int
    public let result: EpisodeResult?

    public init(dayNumber: Int, episodeNumber: Int, result: EpisodeResult?) {
        self.dayNumber = dayNumber
        self.episodeNumber = episodeNumber
        self.result = result
    }

    public var id: Int { dayNumber }
    public var isCompleted: Bool { result != nil }
    /// Completed, but not on its own night.
    public var isLate: Bool { result?.isLate ?? false }
}

public enum Archive {
    /// Past episodes, newest first (yesterday at the top). Tonight's episode
    /// is never in the archive — it lives on the marquee.
    public static func entries(
        today: Int,
        limit: Int = 10,
        results: [Int: EpisodeResult]
    ) -> [ArchiveEntry] {
        guard today > 0, limit > 0 else { return [] }
        let firstDay = max(0, today - limit)
        return stride(from: today - 1, through: firstDay, by: -1).map { day in
            ArchiveEntry(
                dayNumber: day,
                episodeNumber: EpisodeCalendar.episodeNumber(forDay: day),
                result: results[day]
            )
        }
    }
}
