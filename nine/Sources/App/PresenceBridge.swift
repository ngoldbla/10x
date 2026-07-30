// PresenceBridge.swift — the app side of PRD-30. Turns `PresencePolicy`'s
// decision into ActivityKit calls, and does nothing else.
//
// The decision itself is a pure function in `Sources/Shared/QuietPresence.swift`
// so that `swift test` can hold PRD-30's promises to account without a
// simulator. What is left here is the impedance layer, and it earns its own file
// because it is where three things live that a pure function cannot know:
// whether the player has allowed Live Activities at all, what to do about an
// activity that is running for the *wrong day*, and how to touch ActivityKit
// without tripping strict concurrency.
//
// **On that last one.** `Activity<Attributes>` is not `Sendable` and its
// `update`/`end` are `nonisolated async`, so calling either from `@MainActor`
// hands a non-Sendable value across an isolation boundary:
//
//     error: sending 'live' risks causing data races
//
// The shape below is what falls out of that: the model is read on the main actor
// and reduced to Sendable facts, and then **every** `Activity` value is created,
// inspected and mutated inside one `nonisolated` async function, so none of them
// ever crosses a boundary. The memo comes back as a return value rather than
// being written from the task.
//
// iOS only. ActivityKit is `@available(macOS/tvOS/watchOS, unavailable)`, and the
// app target is one universal target, so the fence is not optional.
#if os(iOS)
import ActivityKit
import Foundation
import OSLog

@MainActor
enum PresenceBridge {
    /// `nonisolated` because `reconcile` is, and a `Logger` is `Sendable`.
    private nonisolated static let log =
        Logger(subsystem: "com.couchsuite.nine", category: "presence")

    /// The last content handed to ActivityKit. `place()` publishes on every move
    /// and most moves leave the glyph identical (a pencil mark in an already
    /// marked cell), so this is the same idea as `WidgetBridge.lastReloadDigest`:
    /// spend a system call only when the picture actually changed.
    private static var lastState: NineDailyActivity.ContentState?

    /// Reconcile the Lock Screen with the model.
    ///
    /// - Parameter foreground: the app is on screen. This is the whole "and
    ///   leave" half of "start-and-leave" — see `PresencePolicy.decide`.
    static func sync(from model: AppModel, foreground: Bool, at now: Date = Date()) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            // The player turned Live Activities off in Settings, which is the
            // OS-level version of the pref. Nothing to end: the system already
            // did, and `Activity.request` would throw.
            lastState = nil
            return
        }

        let today = WidgetSnapshotStore.dayOrdinal(for: now)
        let request = Request(
            enabled: model.prefs.livePresence,
            presence: presence(from: model, today: today),
            solved: model.hasSolved(day: today),
            foreground: foreground,
            today: today,
            staleDate: WidgetSnapshotStore.nextLocalMidnight(after: now),
            memo: lastState
        )
        Task { lastState = await reconcile(request) }
    }

    /// Called when the player turns the pref off, so the Lock Screen clears in
    /// the same gesture rather than at the next backgrounding.
    static func endAll() {
        lastState = nil
        Task { await endEveryActivity() }
    }

    // MARK: - Everything the main actor can know

    /// The Sendable reduction of the model that `reconcile` runs on.
    private struct Request: Sendable {
        let enabled: Bool
        let presence: DailyPresence?
        let solved: Bool
        let foreground: Bool
        let today: Int
        let staleDate: Date
        let memo: NineDailyActivity.ContentState?
    }

    /// The payload for today's daily, or nil if there isn't one.
    ///
    /// Board selection is deliberately identical to `WidgetBridge`'s: the
    /// on-screen daily when there is one, otherwise the library's in-progress
    /// daily. Two surfaces bookmarking the same board must agree about which
    /// board that is, and the way to guarantee that is one helper.
    private static func presence(from model: AppModel, today: Int) -> DailyPresence? {
        guard let (game, day) = WidgetBridge.currentDaily(from: model, today: today) else {
            return nil
        }
        return DailyPresence(
            dayOrdinal: day,
            // Every daily composes at `.steady` and a `LibraryEntry`'s `kind` is
            // `.daily(day:)` with no band in it, so there is nothing to read —
            // `AppModel.openToday`, `finishSolve` and `recordSolveMadeElsewhere`
            // all hardcode the same constant, and this is a fourth site rather
            // than a lookup dressed up as one.
            bandID: Difficulty.steady.rawValue,
            glyph: BoardGlyph(game),
            revision: WidgetBridge.knownBoardRevision
        )
    }

    // MARK: - Everything only ActivityKit can know

    /// - Returns: the content now on screen, or nil if there is none. The caller
    ///   stores it as the memo; nothing here writes shared state.
    private nonisolated static func reconcile(
        _ request: Request
    ) async -> NineDailyActivity.ContentState? {
        // **An activity for a day that is not this one cannot be updated into
        // shape.** `dayOrdinal` and `bandID` are attributes, and attributes are
        // frozen for an activity's life, so a phone that slept through midnight
        // wakes holding an activity whose static half says yesterday. Ending the
        // wrong-day ones here — before the policy is asked — is what lets the
        // policy stay a function of the model instead of also being a function of
        // whatever ActivityKit happens to be holding.
        var live: Activity<NineDailyActivity>?
        for activity in Activity<NineDailyActivity>.activities {
            if activity.attributes.dayOrdinal == request.today, live == nil {
                live = activity
            } else {
                await end(activity)
            }
        }

        let decision = PresencePolicy.decide(
            enabled: request.enabled,
            presence: request.presence,
            solved: request.solved,
            foreground: request.foreground,
            live: live != nil,
            today: request.today
        )

        switch decision {
        case .leave:
            return request.memo

        case .end:
            if let live { await end(live) }
            return nil

        case .start(let payload):
            do {
                _ = try Activity.request(
                    attributes: payload.activityAttributes,
                    content: content(payload, staleDate: request.staleDate),
                    // No push token, no APNs plumbing, no server. Nine has none
                    // of the three and PRD-30 needs none of the three.
                    pushType: nil
                )
                return payload.activityState
            } catch {
                // A refusal here is ordinary — the budget is the system's, not
                // ours — and it is never surfaced. Same posture as cloud sync:
                // ambient or absent, no modal (AppModel.swift's `setUpCloudSync`).
                log.info("live activity refused: \(error, privacy: .public)")
                return nil
            }

        case .update(let payload):
            guard let live else { return request.memo }
            let next = payload.activityState
            guard next != request.memo else { return request.memo }
            await live.update(content(payload, staleDate: request.staleDate))
            return next
        }
    }

    private nonisolated static func endEveryActivity() async {
        for activity in Activity<NineDailyActivity>.activities { await end(activity) }
    }

    private nonisolated static func content(
        _ payload: DailyPresence, staleDate: Date
    ) -> ActivityContent<NineDailyActivity.ContentState> {
        ActivityContent(
            state: payload.activityState,
            // Midnight, not a duration. `staleDate` is the one `Date` ActivityKit
            // needs and it is not a countdown: nothing renders it, and the view's
            // only response is to fade. It exists so a phone that is asleep at the
            // rollover shows a dimmed yesterday instead of a confident one.
            staleDate: staleDate,
            relevanceScore: 0
        )
    }

    private nonisolated static func end(_ activity: Activity<NineDailyActivity>) async {
        // `.immediate`, not `.after` or `.default`: a bookmark to a board you have
        // finished should not linger for four hours on the Lock Screen being a
        // trophy. `nil` content keeps whatever was last shown for the instant
        // before it goes, which is quieter than pushing a final frame.
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
#endif
