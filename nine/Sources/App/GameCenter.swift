// GameCenter.swift — the thinnest possible GameKit shim. Authenticates once
// at launch, mirrors points/streaks to leaderboards and flips achievements
// after each solve. Everything is fire-and-forget: Game Center being signed
// out, offline, or not yet configured in App Store Connect must never cost
// the player anything (points and history are local-first in SolveHistory).
//
// GameKit is native on macOS and tvOS too (PRD-4 §2.6, PRD-5 §2.3): the same
// leaderboard / achievement IDs, the same fire-and-forget reporting. Only the
// sign-in presentation and the dashboard invocation branch per platform — the
// Mac triggers `GKAccessPoint` (no UIKit view-controller surface); tvOS uses
// the same `GKGameCenterViewController` UIKit path as iOS.
#if os(iOS) || os(macOS) || os(tvOS)
import GameKit
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor @Observable
final class GameCenter: NSObject {
    static let shared = GameCenter()

    private(set) var isAuthenticated = false

    /// Leaderboard / achievement IDs (must match App Store Connect).
    ///
    /// The streak boards, the streak achievements and the weekly table were
    /// removed with the daily system (2026-08-02). Their App Store Connect
    /// records, where they exist, simply stop receiving submissions.
    enum ID {
        static let pointsBoard = "com.couchsuite.nine.points"

        /// A channel's own two boards (PRD-24). Built by interpolation off the
        /// frozen `Channel` raw value, for `Strings.channel(_:)`'s reason: a
        /// `switch` is a second list that can disagree with the enum, and adding a
        /// channel would compile.
        ///
        /// **These need App Store Connect records that do not exist yet, and that
        /// is a human gate of exactly the kind PRD-7 §5 describes** — like the
        /// CloudKit container, and like PRD-26's production schema deploy. No
        /// entitlement is involved (Game Center is already on all three GameKit
        /// platforms) so **no `match` re-mint is implied**. Submission is
        /// fire-and-forget `try?` by design, so until the records exist a channel
        /// solve submits into silence rather than crashing — which is the right
        /// failure mode for a leaderboard and the reason this can ship ahead of
        /// the portal work.
        static func channelPoints(_ channel: Channel.Ledgered) -> String {
            "com.couchsuite.nine.points.\(channel.rawValue)"
        }

        static let firstSolve = "com.couchsuite.nine.solve.first"
        static let tenSolves = "com.couchsuite.nine.solve.ten"
        static let fiftySolves = "com.couchsuite.nine.solve.fifty"
        static let firstSharp = "com.couchsuite.nine.sharp.first"
        static let speedSolve = "com.couchsuite.nine.swift"

        /// PRD-28 §7 — the App Store Connect **game activity definition** a
        /// sent board rides on.
        ///
        /// This is not a leaderboard and not an achievement, and it is not a
        /// `GKChallenge` either: **every classic Game Center challenge API is
        /// deprecated as of iOS/tvOS/macOS 26** and its replacement,
        /// `GKChallengeDefinition`, is leaderboard-backed and carries no payload
        /// at all. `GKGameActivity.properties` is the only flat `[String: String]`
        /// GameKit will carry, which is why `ParlorInvite` has a property
        /// dictionary envelope and why that envelope is a tested type.
        ///
        /// **Like the per-channel leaderboards, this record does not exist yet**
        /// and creating it is a human gate of exactly the kind PRD-7 §5
        /// describes. No entitlement is involved, so no `match` re-mint is
        /// implied. Until it exists `loadGameActivityDefinitions` returns
        /// nothing, `canSendBoard` stays false, and the action is *absent*
        /// rather than broken — the same fire-and-forget failure mode that let
        /// PRD-24 ship ahead of its portal work.
        static let parlorActivity = "com.couchsuite.nine.parlor"
    }

    /// A board somebody sent, waiting to be opened. Set from the Game Center
    /// listener; `NineApp` hands it to the model.
    @ObservationIgnored var onInvite: ((ParlorInvite) -> Void)?

    /// Whether App Store Connect has the activity definition §7 needs. False
    /// until proven otherwise, so the surface is absent by default.
    private(set) var canSendBoard = false

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            Task { @MainActor in
                guard let self else { return }
                if let viewController { Self.present(viewController) }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                guard self.isAuthenticated else { return }
                self.registerParlorListener()
                await self.loadParlorDefinition()
            }
        }
    }

    // MARK: - Sending a board (PRD-28 §7)

    /// The activity definition, loaded once per authentication, and the
    /// listener that receives one. Both `AnyObject`, because their real types
    /// are iOS 26 and a stored property cannot be `@available`.
    @ObservationIgnored private var parlorDefinition: AnyObject?
    @ObservationIgnored private var parlorListener: AnyObject?

    private func registerParlorListener() {
        guard #available(iOS 26.0, macOS 26.0, tvOS 26.0, *), parlorListener == nil else { return }
        let listener = ParlorActivityListener { [weak self] invite in
            self?.onInvite?(invite)
        }
        parlorListener = listener
        GKLocalPlayer.local.register(listener)
    }

    private func loadParlorDefinition() async {
        guard #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) else { return }
        let definitions = try? await GKGameActivityDefinition.loadGameActivityDefinitions(
            IDs: [ID.parlorActivity])
        guard let definition = definitions?.first else { return }
        parlorDefinition = definition
        canSendBoard = true
    }

    /// Start a game activity carrying this board and hand back the URL that
    /// invites somebody to it, or nil when App Store Connect has no definition.
    ///
    /// The URL is shared through the ordinary share sheet rather than through a
    /// Game Center compose controller, because the compose controllers are the
    /// deprecated API and their replacement is a party invitation.
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, *)
    func sendBoard(_ invite: ParlorInvite) -> URL? {
        guard isAuthenticated, let definition = parlorDefinition as? GKGameActivityDefinition
        else { return nil }
        let activity = GKGameActivity(definition: definition)
        // The seed, the band, the day and the wire version — eight bytes and
        // two words. The board itself is a pure function of them, so nothing
        // larger has to travel.
        activity.properties = invite.properties
        activity.start()
        return activity.partyURL
    }

    /// Mirror one finished board into leaderboards + achievements.
    ///
    /// `channel` is the board's channel, non-nil only for a variant board
    /// (PRD-24). When it is set, `history` is **that channel's**, and the
    /// score goes to that channel's own board — so a killer solve never
    /// lands on the classic leaderboard, which is the same separation
    /// `ChannelLedger` enforces one layer down.
    ///
    /// Achievements are deliberately **classic-only**: they are counted against the
    /// classic history and a channel solve does not advance them. Splitting them
    /// per channel would triple a set the covenant already calls the outer edge of
    /// what it tolerates, and "first killer solve" is a badge — which
    /// `EXECUTING-A-PRD` §1 rules out by name.
    func reportSolve(
        record: SolveRecord, history: SolveHistory,
        channel: Channel.Ledgered? = nil
    ) {
        guard isAuthenticated else { return }
        Task {
            try? await GKLeaderboard.submitScore(
                history.totalPoints, context: 0, player: GKLocalPlayer.local,
                leaderboardIDs: [channel.map(ID.channelPoints) ?? ID.pointsBoard]
            )
            // A channel solve stops here. Everything below counts classic solves.
            guard channel == nil else { return }
            let solves = history.records.count
            var achievements: [GKAchievement] = [
                progress(ID.firstSolve, fraction: Double(solves)),
                progress(ID.tenSolves, fraction: Double(solves) / 10),
                progress(ID.fiftySolves, fraction: Double(solves) / 50),
            ]
            // Nocturne counts toward the Sharp badge. It is Sharp's chain with a
            // clue floor, so a player who cleared one has demonstrably done the
            // thing this badge is for, and gating on `.sharp` alone would leave
            // a Nocturne-only player unable to earn it. No `nocturne.first` of
            // its own: that needs an App Store Connect record, and PRD-17 §4
            // rules separate prestige surfaces out of scope.
            if history.count(of: .sharp) + history.count(of: .nocturne) >= 1 {
                achievements.append(progress(ID.firstSharp, fraction: 1))
            }
            if record.seconds > 0, record.seconds < SolveScore.speedBonusThreshold {
                achievements.append(progress(ID.speedSolve, fraction: 1))
            }
            try? await GKAchievement.report(achievements)
        }
    }

    /// The full Game Center dashboard (leaderboards + achievements). On iOS
    /// this is a modally-presented `GKGameCenterViewController`; on macOS the
    /// `GKAccessPoint` trigger opens the same dashboard without a UIKit host.
    func showDashboard() {
        guard isAuthenticated else { return }
        #if os(macOS)
        GKAccessPoint.shared.trigger(state: .dashboard) {}
        #else
        let dashboard = GKGameCenterViewController(state: .dashboard)
        dashboard.gameCenterDelegate = self
        Self.rootViewController?.present(dashboard, animated: true)
        #endif
    }

    // MARK: - Internals

    private nonisolated func progress(_ id: String, fraction: Double) -> GKAchievement {
        let achievement = GKAchievement(identifier: id)
        achievement.percentComplete = max(0, min(100, fraction * 100))
        achievement.showsCompletionBanner = true
        return achievement
    }

    #if os(macOS)
    /// Present the sign-in view controller macOS-style: as a sheet on the key
    /// window (GameKit hands back an `NSViewController` on the Mac).
    private static func present(_ viewController: NSViewController) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        window.contentViewController?.presentAsSheet(viewController)
    }
    #else
    private static func present(_ viewController: UIViewController) {
        rootViewController?.present(viewController, animated: true)
    }

    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
    #endif
}

/// PRD-28 §7's receiving half.
///
/// **Its own class rather than a conformance on `GameCenter`**, and the reason
/// is a compiler rule rather than a design preference: every member of
/// `GKGameActivityListener` is iOS 26, the deployment target is iOS 18, and
/// Swift will not let a type whose availability is wider than a protocol
/// requirement's witness it — *even when the requirement is optional*. A whole
/// type marked `@available` is the shape that compiles, and it keeps the one
/// iOS-26-only surface in this file visibly fenced.
@available(iOS 26.0, macOS 26.0, tvOS 26.0, *)
final class ParlorActivityListener: NSObject, GKLocalPlayerListener {
    private let onInvite: @MainActor (ParlorInvite) -> Void

    init(onInvite: @escaping @MainActor (ParlorInvite) -> Void) {
        self.onInvite = onInvite
    }

    // `wantsToPlay:`, not `wantsToPlayGameActivity:` — the header's Objective-C
    // selector is renamed by the framework's own API notes, and the Swift name
    // is the shorter one.
    func player(
        _ player: GKPlayer,
        wantsToPlay activity: GKGameActivity,
        completionHandler: @escaping (Bool) -> Void
    ) {
        // Decoded here, on GameKit's thread, so nothing but a value crosses to
        // the main actor. A dictionary this build cannot read yields *no board*
        // rather than a wrong one, and says so — `handled: false` lets GameKit
        // fall back to its own affordance instead of leaving the sender's
        // invitation looking accepted.
        guard let invite = ParlorInvite(properties: activity.properties) else {
            return completionHandler(false)
        }
        completionHandler(true)
        let onInvite = self.onInvite
        Task { @MainActor in onInvite(invite) }
    }
}

#if os(iOS) || os(tvOS)
extension GameCenter: GKGameCenterControllerDelegate {
    nonisolated func gameCenterViewControllerDidFinish(_ controller: GKGameCenterViewController) {
        Task { @MainActor in
            controller.dismiss(animated: true)
        }
    }
}
#endif
#endif
