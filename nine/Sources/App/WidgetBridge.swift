// WidgetBridge.swift — app-side snapshot publisher (PRD-3 §3a). Builds a
// WidgetSnapshot from the model, writes it atomically into the app group,
// and asks WidgetKit to reload — but only when a coarse digest changed,
// because `place()` publishes on every move and the system reload budget
// is finite. iOS only: tvOS has no widgets and no app group.
#if os(iOS)
import Foundation
import WidgetKit

@MainActor
enum WidgetBridge {
    /// Digest of the last snapshot that triggered a reload; nil forces the
    /// first publish of the process to reload (cheap, covers midnight
    /// rollovers that happened while the app was dead).
    private static var lastReloadDigest: String?

    static func publish(from model: AppModel) {
        let now = Date()
        let snapshot = snapshot(from: model, at: now)
        try? WidgetSnapshotStore.save(snapshot)
        let digest = snapshot.reloadDigest(today: WidgetSnapshotStore.dayOrdinal(for: now))
        guard digest != lastReloadDigest else { return }
        lastReloadDigest = digest
        WidgetCenter.shared.reloadAllTimelines()
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
