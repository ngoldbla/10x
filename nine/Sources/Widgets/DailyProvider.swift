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
    /// Today's board as a constellation, for the StandBy face and the
    /// Focus-filtered arms (PRD-30/33). nil when there is no board for today.
    ///
    /// A second file read per timeline pass, on the same container this provider
    /// already opens, for 22 bytes. It is on the *entry* rather than derived in
    /// the view because a timeline entry is supposed to be everything the view
    /// needs — and the midnight entry has to be able to disagree with the
    /// now entry, which a view-time read could not do.
    let glyph: BoardGlyph?

    init(date: Date, snapshot: WidgetSnapshot?, glyph: BoardGlyph? = nil) {
        self.date = date
        self.snapshot = snapshot
        self.glyph = glyph
    }

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
        let now = Date()
        completion(DailyEntry(
            date: now,
            snapshot: snapshot,
            glyph: Self.glyph(at: now) ?? (context.isPreview ? .sample : nil)
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.load()
        let midnight = WidgetSnapshotStore.nextLocalMidnight(after: now)
        let glyph = Self.glyph(at: now)
        // Two entries from the same facts: the second re-renders past
        // midnight as "not started" / lapsed flame. Refresh again after.
        //
        // The midnight entry carries **no glyph**, for the same reason it carries
        // the same snapshot: today's board is not tomorrow's, and an ambient face
        // still showing last night's constellation at 00:01 would be the one
        // surface in the app that lies about the date.
        let timeline = Timeline(
            entries: [
                DailyEntry(date: now, snapshot: snapshot, glyph: glyph),
                DailyEntry(date: midnight, snapshot: snapshot, glyph: nil),
            ],
            policy: .after(midnight)
        )
        completion(timeline)
    }

    /// Today's board, or nil — reusing the shared file's own stale-day guard
    /// rather than re-deriving one.
    private static func glyph(at date: Date) -> BoardGlyph? {
        let today = WidgetSnapshotStore.dayOrdinal(for: date)
        guard let board = SharedDailyBoardStore.load(), board.isCurrent(today: today) else {
            return nil
        }
        return BoardGlyph(board.game)
    }
}

extension BoardGlyph {
    /// Widget-gallery preview: a plausible half-done board. Constructed rather
    /// than generated — the extension never runs the generator (PRD-3 §2), and a
    /// gallery tile is a picture, not a puzzle.
    static let sample: BoardGlyph = {
        var given: [Int] = []
        var filled: [Int] = []
        for cell in 0..<BoardGlyph.cellCount {
            // A scatter that reads as a sudoku's givens (~30) with about half the
            // rest filled in, and is the same every time anyone looks.
            switch (cell * 7 + cell / 9) % 11 {
            case 0, 3, 7: given.append(cell)
            case 1, 5, 8, 9: filled.append(cell)
            default: break
            }
        }
        return BoardGlyph(givenCells: given, filledCells: filled)
    }()
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
