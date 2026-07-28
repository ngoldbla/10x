// WatchLinkSession.swift — the wrist's half of the link (PRD-6).
//
// Transport only. Every rule about *whether* to adopt a payload lives in
// `Sources/Shared/WatchLink.swift`, where it is unit-tested without a paired
// device; this file is the WCSession boilerplate that hands bytes to it.
//
// The two directions use two different WatchConnectivity mechanisms on purpose:
//
//   • **down**, `applicationContext` — a single latest-value slot the system
//     redelivers whenever the watch next has a chance. Today's puzzle is a
//     latest-value fact, and an older one is worthless, so a mechanism that
//     drops superseded payloads is the correct one.
//   • **up**, `transferUserInfo` — a guaranteed FIFO queue that survives the
//     phone being unreachable, both apps being killed, and a reboot. A solve
//     is the one thing on this link that cannot be regenerated from the day,
//     so it gets the delivery guarantee. `sendMessage` would have been wrong:
//     it fails outright when the counterpart is not reachable, which on a
//     watch is most of the time.
#if os(watchOS)
import Foundation
import OSLog
import WatchConnectivity

@MainActor
final class WatchLinkSession: NSObject {
    private let model: WatchModel
    private let log = Logger(subsystem: "com.couchsuite.nine", category: "watch-link")

    init(model: WatchModel) {
        self.model = model
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        // A context that arrived while this process was dead is still sitting
        // in the slot; the delegate callback does not fire for it.
        if let handoff = WatchLinkWire.decodeHandoff(session.receivedApplicationContext) {
            adopt(handoff)
        }
        flushPendingSolve()
    }

    /// Send the parked solve, if there is one. Safe to call repeatedly: the
    /// ledger keeps it until the phone acknowledges, and `recordCompletion` is
    /// idempotent per day at the other end, so a duplicate costs nothing.
    func flushPendingSolve() {
        guard let report = model.ledger.unreportedSolve, WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(WatchLinkWire.encode(report))
    }

    private func adopt(_ handoff: WatchDailyHandoff) {
        model.adopt(handoff)
    }
}

extension WatchLinkSession: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: (any Error)?
    ) {
        if let error {
            // Never fatal. The watch is standalone-capable by design
            // (`WKRunsIndependentlyOfCompanionApp`); a dead link costs today's
            // daily, not the app.
            Logger(subsystem: "com.couchsuite.nine", category: "watch-link")
                .error("activation failed: \(error, privacy: .public)")
            return
        }
        // Decoded HERE, on the delegate's own thread, and only the decoded
        // value crosses to the main actor. `[String: Any]` is not `Sendable`
        // — Swift 6 rejects hopping one — while `WatchDailyHandoff` is, which
        // is one more reason the wire types are plain Codable structs rather
        // than dictionaries passed around.
        let handoff = WatchLinkWire.decodeHandoff(session.receivedApplicationContext)
        Task { @MainActor [weak self] in
            if let handoff { self?.adopt(handoff) }
            self?.flushPendingSolve()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let handoff = WatchLinkWire.decodeHandoff(applicationContext) else { return }
        Task { @MainActor [weak self] in self?.adopt(handoff) }
    }

    /// The phone acknowledging a solve it has ingested. Only then is the
    /// ledger cleared — an unacknowledged solve is re-sent on next activation.
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        guard let day = userInfo[WatchLinkWire.acknowledgedSolveKey] as? Int else { return }
        Task { @MainActor [weak self] in
            guard let self, self.model.ledger.unreportedSolve?.dayOrdinal == day else { return }
            self.model.clearReportedSolve()
        }
    }
}
#endif
