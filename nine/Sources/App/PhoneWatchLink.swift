// PhoneWatchLink.swift — the phone's half of the link (PRD-6).
//
// Sibling to `WidgetBridge`: same job (publish a fact the app owns to a
// surface that cannot compute it), same discipline (a monotone revision and a
// digest so an unchanged fact costs nothing), different transport.
//
// The one asymmetry worth stating: the widget bridge republishes on every move
// because the widget renders play state. This one does not. The watch receives
// the *puzzle*, which is immutable and a pure function of the day, so the only
// event that can change what the watch should hold is midnight. Republishing
// per move would spend the link's budget saying the same sentence.
#if os(iOS)
import Foundation
import OSLog
import WatchConnectivity

@MainActor
final class PhoneWatchLink: NSObject {
    static let shared = PhoneWatchLink()

    private let log = Logger(subsystem: "com.couchsuite.nine", category: "watch-link")
    /// Set once the model exists, so a solve report that arrives before the
    /// first `publish` still has somewhere to go.
    private weak var model: AppModel?
    /// Day ordinal of the handoff already in the context slot.
    private var publishedDay: Int?

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default
    }

    func activate(model: AppModel) {
        self.model = model
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Put today's composed daily where the watch can find it.
    ///
    /// Cheap to call from anywhere: it does nothing unless a watch is paired,
    /// the app is installed on it, and the day has actually moved.
    func publishDaily(_ puzzle: GeneratedPuzzle, day: Int) {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        guard publishedDay != day else { return }
        // The revision has to survive process death or the watch's
        // strictly-newer rule would reject every handoff after a relaunch.
        // The day ordinal is itself monotone and already unique per payload,
        // so it *is* the revision — no counter to persist and no way for the
        // two to disagree.
        let handoff = WatchDailyHandoff(
            dayOrdinal: day, puzzle: puzzle, revision: day, updatedAt: Date()
        )
        do {
            try session.updateApplicationContext(WatchLinkWire.encode(handoff))
            publishedDay = day
        } catch {
            log.error("handoff publish failed: \(error, privacy: .public)")
        }
    }
}

extension PhoneWatchLink: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: (any Error)?
    ) {
        if let error {
            Logger(subsystem: "com.couchsuite.nine", category: "watch-link")
                .error("activation failed: \(error, privacy: .public)")
        }
    }

    // Required on iOS; a re-pair invalidates the context slot, so the next
    // `publishDaily` must be allowed to write again.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
        Task { @MainActor [weak self] in self?.forgetPublishedDay() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.forgetPublishedDay() }
    }

    /// A solve made on the wrist. Ingested exactly once — the guard is
    /// `StreakState.hasCompleted(day:)` inside the model, the same one a
    /// widget solve passes through — then acknowledged, so the watch can stop
    /// holding it.
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        // Decoded on the delegate's thread; only the `Sendable` struct hops.
        // The acknowledgement goes back through `WCSession.default` rather
        // than the captured `session` for the same reason — Swift 6 will not
        // let a `WCSession` cross an actor boundary.
        guard let report = WatchLinkWire.decodeReport(userInfo) else { return }
        Task { @MainActor [weak self] in
            self?.model?.ingestWatchSolve(report)
            WCSession.default.transferUserInfo(
                [WatchLinkWire.acknowledgedSolveKey: report.dayOrdinal]
            )
        }
    }
}

extension PhoneWatchLink {
    fileprivate func forgetPublishedDay() { publishedDay = nil }
}
#endif
