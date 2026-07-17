// WidgetBridge.swift — app-side snapshot publisher (PRD-3 §3a). Builds a
// WidgetSnapshot from the model, writes it atomically into the app group,
// and asks WidgetKit to reload — but only when a coarse digest changed,
// because `place()` publishes on every move and the system reload budget
// is finite. iOS only: tvOS has no widgets and no app group.
#if os(iOS)
import Foundation
import OSLog
import WidgetKit

@MainActor
enum WidgetBridge {
    /// Digest of the last snapshot that triggered a reload; nil forces the
    /// first publish of the process to reload (cheap, covers midnight
    /// rollovers that happened while the app was dead).
    private static var lastReloadDigest: String?
    /// Highest SharedDailyBoard revision this process has written or
    /// ingested. A file revision above this means un-ingested widget moves —
    /// the app must never overwrite those (PRD-3 §4).
    static var knownBoardRevision = 0

    static func publish(from model: AppModel) {
        let now = Date()
        publishDailyBoard(from: model, at: now)
        let snapshot = snapshot(from: model, at: now)
        do {
            try WidgetSnapshotStore.save(snapshot)
        } catch {
            Logger(subsystem: "com.couchsuite.nine", category: "widget-bridge")
                .error("snapshot save failed: \(error, privacy: .public)")
        }
        let digest = snapshot.reloadDigest(today: WidgetSnapshotStore.dayOrdinal(for: now))
        guard digest != lastReloadDigest else { return }
        lastReloadDigest = digest
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Mirror the current daily (on-screen or autosaved) into the shared
    /// board file, revision++. No daily today → leave the file alone (the
    /// widget's stale-day guard handles yesterday's leftovers).
    private static func publishDailyBoard(from model: AppModel, at now: Date) {
        let today = WidgetSnapshotStore.dayOrdinal(for: now)
        var current: (game: NineGame, day: Int)?
        if model.screen == .game, case .daily(let day)? = model.kind, let game = model.game {
            // On-screen daily (covers the just-solved board, whose autosave
            // slot is already cleared). Off the game screen, `kind`/`game`
            // linger only for the crossfade — the autosave slot is truth.
            current = (game, day)
        } else if case .daily(let day)? = model.saved.kind, let game = model.saved.game {
            current = (game, day)
        }
        guard let (game, day) = current, day == today else { return }
        let existing = SharedDailyBoardStore.load()
        if let existing, existing.isCurrent(today: today), existing.revision > knownBoardRevision {
            // The widget wrote moves the app hasn't ingested yet; writing
            // now would drop them. ingestSharedDailyBoard runs first on
            // every activation, so this is a rare mid-flight race.
            return
        }
        let revision = max(existing?.revision ?? 0, knownBoardRevision) + 1
        knownBoardRevision = revision
        do {
            try SharedDailyBoardStore.save(SharedDailyBoard(
                dayOrdinal: day, game: game, revision: revision, updatedAt: now
            ))
        } catch {
            Logger(subsystem: "com.couchsuite.nine", category: "widget-bridge")
                .error("board save failed: \(error, privacy: .public)")
        }
    }

    /// The app dropped today's board (discard control): clear the shared
    /// file so the widget offers "tap to start" instead of resurrecting it.
    static func clearDailyBoard(today: Int) {
        if let existing = SharedDailyBoardStore.load(), existing.isCurrent(today: today) {
            SharedDailyBoardStore.delete()
        }
        knownBoardRevision = 0
    }

    /// Raw facts only — display state is re-derived per timeline entry.
    static func snapshot(from model: AppModel, at now: Date) -> WidgetSnapshot {
        var dailyDay: Int?
        var fill: Double?
        var solvedSeconds: TimeInterval?
        if case .daily(let day)? = model.saved.kind, let game = model.saved.game {
            // An in-progress daily always lives in the autosave slot
            // (persistProgress runs on every accepted move).
            dailyDay = day
            fill = game.fillFraction
        } else if let last = model.streak.lastCompletedDay {
            dailyDay = last
            fill = 1
            solvedSeconds = model.history.records.first {
                $0.isDaily && WidgetSnapshotStore.dayOrdinal(for: $0.date) == last
            }?.seconds
        }
        return WidgetSnapshot(
            dailyDayOrdinal: dailyDay,
            dailyFillFraction: fill,
            dailySolvedSeconds: solvedSeconds,
            streakCurrent: model.streak.current,
            streakBest: model.streak.best,
            lastCompletedDay: model.streak.lastCompletedDay,
            totalPoints: model.totalPoints,
            generatedAt: now
        )
    }
}
#endif
