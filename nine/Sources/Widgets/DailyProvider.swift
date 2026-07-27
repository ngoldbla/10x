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
    /// "4:12" — matches the app's completion chip, because it now *is* the
    /// app's completion chip.
    ///
    /// Task 6 left this as its own `String(format: "%d:%02d", …)` and said why:
    /// six files in `Sources/App` plus `SolveCardFacts` spelled it the same
    /// way, and the widget being the odd one out would be worse than either
    /// answer. That was right, and this is the change it was waiting for — all
    /// eight at once, into `SolveCardFacts.elapsedText`, which is the copy that
    /// documents why the minutes are allowed past 60.
    ///
    /// `.rounded()` stays here rather than moving into the shared function: the
    /// widget's seconds come off a `TimelineEntry` minted at a whole second and
    /// the six in-app clocks truncate a live timer. Two different questions,
    /// one format.
    static func time(_ seconds: TimeInterval) -> String {
        SolveCardFacts.elapsedText(seconds.rounded())
    }

    /// The fill percentage.
    ///
    /// **Not a catalog key any more** (PRD-20 Task 8). Task 6 routed this
    /// through `board.progress.percent` = `"%1$lld%%"` to get the sign placed
    /// per language — right instinct, wrong lever. That row is a translation
    /// unit with no words in it, so nine translators are paid to move a `%`
    /// around a specifier, by hand, correctly, nine times.
    /// `.formatted(.percent)` is ICU answering the same question for free: it
    /// leads with the sign in Turkish, spaces it in French, and renders the
    /// numerals in the locale's own digits — which the catalog row could not
    /// do at all, because `%1$lld` is always ASCII.
    static func percent(_ fill: Double) -> String {
        Int((fill * 100).rounded()).formatted(.percent)
    }
}
