// WidgetBridge.swift — app-side snapshot publisher (PRD-3 §3a). Builds a
// WidgetSnapshot from the model, writes it atomically into the app group,
// and asks WidgetKit to reload — but only when a coarse digest changed,
// because `place()` publishes on every move and the system reload budget
// is finite. iOS only: tvOS has no widgets and no app group.
//
// Repointed 2026-08-02 with the daily's removal: the shared board file now
// mirrors the most recent in-progress classic board (the same board the
// Continue card resumes), keyed by its library entry id.
#if os(iOS)
import Foundation
import OSLog
import WidgetKit

@MainActor
enum WidgetBridge {
    /// Digest of the last snapshot that triggered a reload; nil forces the
    /// first publish of the process to reload (cheap, covers changes that
    /// happened while the app was dead).
    private static var lastReloadDigest: String?
    /// Highest SharedDailyBoard revision the app has written or ingested. A
    /// file revision above this means un-ingested widget moves — the app must
    /// never overwrite those (PRD-3 §4). Persisted in the app group: an
    /// in-memory counter reset to 0 every process, so a cold launch re-ingested
    /// the same widget moves over a fresh free-play game (the launch clobber).
    static var knownBoardRevision: Int {
        get { SharedDailyBoardStore.knownRevision() }
        set { SharedDailyBoardStore.setKnownRevision(newValue) }
    }

    static func publish(from model: AppModel) {
        let now = Date()
        publishSharedBoard(from: model, at: now)
        let snapshot = snapshot(from: model, at: now)
        do {
            try WidgetSnapshotStore.save(snapshot)
        } catch {
            Logger(subsystem: "com.couchsuite.nine", category: "widget-bridge")
                .error("snapshot save failed: \(error, privacy: .public)")
        }
        let digest = snapshot.reloadDigest(boardRevision: knownBoardRevision)
        guard digest != lastReloadDigest else { return }
        lastReloadDigest = digest
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Which board the widget shows: the on-screen classic board when there is
    /// one, otherwise the library's most recent in-progress classic partial.
    /// nil when there is nothing in progress (the widget offers "tap to
    /// start"). Channel boards are structurally excluded — the widget cannot
    /// draw cages or tubes.
    static func currentBoard(from model: AppModel) -> (game: NineGame, id: UUID)? {
        if model.screen == .game, let id = model.currentEntryID,
           let entry = model.library.entry(id: id), isClassic(entry.kind),
           let game = model.game {
            // On-screen board (covers the just-solved board). Off the game
            // screen, `kind`/`game` linger only for the crossfade.
            return (game, id)
        }
        if let entry = model.library.mostRecentInProgress, isClassic(entry.kind) {
            return (entry.game, entry.id)
        }
        return nil
    }

    private static func isClassic(_ kind: GameKind) -> Bool {
        switch kind {
        case .daily, .free: return true
        case .channel: return false
        }
    }

    /// Mirror the current board into the shared file, revision++. No board in
    /// progress → clear the file so the widget offers "tap to start".
    private static func publishSharedBoard(from model: AppModel, at now: Date) {
        guard let (game, id) = currentBoard(from: model) else {
            if SharedDailyBoardStore.load() != nil { SharedDailyBoardStore.delete() }
            return
        }
        let existing = SharedDailyBoardStore.load()
        if let existing, existing.entryID == id {
            if existing.revision > knownBoardRevision {
                // The widget wrote moves the app hasn't ingested yet; writing
                // now would drop them. ingestSharedBoard runs first on every
                // activation, so this is a rare mid-flight race.
                return
            }
            if existing.game == game, existing.pendingSolve == nil {
                // Board content unchanged: don't bump the revision, so an
                // unrelated publish costs no reload.
                return
            }
        }
        let revision = max(existing?.revision ?? 0, knownBoardRevision) + 1
        knownBoardRevision = revision
        do {
            try SharedDailyBoardStore.save(SharedDailyBoard(
                entryID: id,
                dayOrdinal: WidgetSnapshotStore.dayOrdinal(for: now),
                game: game, revision: revision, updatedAt: now
            ))
        } catch {
            Logger(subsystem: "com.couchsuite.nine", category: "widget-bridge")
                .error("board save failed: \(error, privacy: .public)")
        }
    }

    /// The app dropped the shared board (discard/delete control): clear the
    /// file so the widget offers "tap to start" instead of resurrecting it.
    static func clearSharedBoard() {
        SharedDailyBoardStore.delete()
        knownBoardRevision = 0
    }

    /// Raw facts only — display state is re-derived per timeline entry.
    static func snapshot(from model: AppModel, at now: Date) -> WidgetSnapshot {
        var fill: Double?
        if let (game, _) = currentBoard(from: model), !game.isSolved {
            fill = game.fillFraction
        }
        return WidgetSnapshot(
            boardFillFraction: fill,
            boardSolvedSeconds: nil,
            totalPoints: model.totalPoints,
            generatedAt: now,
            // The look (PRD-30): a fact about how to draw rather than about
            // the board, and in the reload digest, so changing a theme
            // refreshes the Home Screen instead of waiting for a move.
            themeRaw: model.prefs.theme.rawValue,
            accentRaw: model.prefs.accent.rawValue
        )
    }
}
#endif
