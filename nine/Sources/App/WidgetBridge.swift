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
    /// Highest SharedDailyBoard revision the app has written or ingested. A
    /// file revision above this means un-ingested widget moves — the app must
    /// never overwrite those (PRD-3 §4). Now persisted in the app group: an
    /// in-memory counter reset to 0 every process, so a cold launch re-ingested
    /// the same widget moves over a fresh free-play game (the launch clobber).
    static var knownBoardRevision: Int {
        get { SharedDailyBoardStore.knownRevision() }
        set { SharedDailyBoardStore.setKnownRevision(newValue) }
    }

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
        // Fold in the exact daily revision: a within-decile daily move now
        // reloads the playable BoardWidget (foreground reloads are budget-exempt),
        // where the decile bucket alone used to lag it.
        let digest = snapshot.reloadDigest(
            today: WidgetSnapshotStore.dayOrdinal(for: now),
            boardRevision: knownBoardRevision
        )
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
            // On-screen daily (covers the just-solved board). Off the game
            // screen, `kind`/`game` linger only for the crossfade.
            current = (game, day)
        } else if let daily = model.library.inProgressDaily(day: today) {
            // Even while a free-play board is on screen, keep the widget current
            // with the library's in-progress daily.
            current = (daily.game, today)
        }
        guard let (game, day) = current, day == today else { return }
        let existing = SharedDailyBoardStore.load()
        if let existing, existing.isCurrent(today: today) {
            if existing.revision > knownBoardRevision {
                // The widget wrote moves the app hasn't ingested yet; writing
                // now would drop them. ingestSharedDailyBoard runs first on
                // every activation, so this is a rare mid-flight race.
                return
            }
            if existing.game == game, existing.pendingSolve == nil {
                // Board content unchanged (e.g. a free-play move just published):
                // don't bump the revision, so free-play moves cost no reload.
                return
            }
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
        let today = WidgetSnapshotStore.dayOrdinal(for: now)
        var dailyDay: Int?
        var fill: Double?
        var solvedSeconds: TimeInterval?
        if let daily = model.library.inProgressDaily(day: today) {
            // The one in-progress daily entry (persistProgress upserts it on
            // every accepted move).
            dailyDay = today
            fill = daily.game.fillFraction
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
