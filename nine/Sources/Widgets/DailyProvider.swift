// DailyProvider.swift — the one timeline provider behind every Nine widget.
// Reads the app-written snapshot from the app group and derives display
// state per entry date, so midnight flips the widget to "new puzzle
// waiting" (and lapses the flame) without an app launch (PRD-3 §3a).
import Foundation
import WidgetKit

struct DailyEntry: TimelineEntry {
    let date: Date
    /// nil = no snapshot file yet (fresh install) → "Open Nine" placeholder.
    let snapshot: WidgetSnapshot?

    /// Display state at this entry's date, re-derived from raw facts.
    var state: DailyState {
        guard let snapshot else { return .noSnapshot }
        let today = WidgetSnapshotStore.dayOrdinal(for: date)
        if snapshot.isSolved(today: today) {
            return .solved(seconds: snapshot.dailySolvedSeconds)
        }
        if snapshot.isInProgress(today: today), let fill = snapshot.dailyFillFraction {
            return .inProgress(fill: fill)
        }
        return .notStarted
    }

    var displayedStreak: Int {
        guard let snapshot else { return 0 }
        return snapshot.displayedStreak(today: WidgetSnapshotStore.dayOrdinal(for: date))
    }

    var totalPoints: Int { snapshot?.totalPoints ?? 0 }
}

enum DailyState: Equatable {
    case noSnapshot
    case notStarted
    case inProgress(fill: Double)
    case solved(seconds: TimeInterval?)
}

struct DailyProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyEntry {
        DailyEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyEntry) -> Void) {
        // The widget gallery gets sample content; a placed widget shows truth.
        let snapshot = WidgetSnapshotStore.load() ?? (context.isPreview ? .sample : nil)
        completion(DailyEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.load()
        let midnight = WidgetSnapshotStore.nextLocalMidnight(after: now)
        // Two entries from the same facts: the second re-renders past
        // midnight as "not started" / lapsed flame. Refresh again after.
        let timeline = Timeline(
            entries: [
                DailyEntry(date: now, snapshot: snapshot),
                DailyEntry(date: midnight, snapshot: snapshot),
            ],
            policy: .after(midnight)
        )
        completion(timeline)
    }
}

extension WidgetSnapshot {
    /// Widget-gallery preview: mid-solve daily with a healthy streak.
    static var sample: WidgetSnapshot {
        let today = WidgetSnapshotStore.dayOrdinal(for: Date())
        return WidgetSnapshot(
            dailyDayOrdinal: today,
            dailyFillFraction: 0.64,
            streakCurrent: 12,
            streakBest: 21,
            lastCompletedDay: today - 1,
            totalPoints: 4_250
        )
    }
}

// MARK: - Shared formatting

enum WidgetFormat {
    /// "4:12" — matches the app's completion chip.
    static func time(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func percent(_ fill: Double) -> String {
        "\(Int((fill * 100).rounded()))%"
    }
}
