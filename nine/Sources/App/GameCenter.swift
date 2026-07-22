// GameCenter.swift — the thinnest possible GameKit shim. Authenticates once
// at launch, mirrors points/streaks to leaderboards and flips achievements
// after each solve. Everything is fire-and-forget: Game Center being signed
// out, offline, or not yet configured in App Store Connect must never cost
// the player anything (points and history are local-first in SolveHistory).
//
// GameKit is native on macOS too (PRD-4 §2.6): the same leaderboard /
// achievement IDs, the same fire-and-forget reporting. Only the sign-in
// presentation and the dashboard invocation branch per platform — the Mac
// triggers `GKAccessPoint` (no UIKit view-controller surface).
#if os(iOS) || os(macOS)
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
    enum ID {
        static let pointsBoard = "com.couchsuite.nine.points"
        static let streakBoard = "com.couchsuite.nine.streak"
        static let firstSolve = "com.couchsuite.nine.solve.first"
        static let tenSolves = "com.couchsuite.nine.solve.ten"
        static let fiftySolves = "com.couchsuite.nine.solve.fifty"
        static let firstSharp = "com.couchsuite.nine.sharp.first"
        static let weekStreak = "com.couchsuite.nine.streak.seven"
        static let monthStreak = "com.couchsuite.nine.streak.thirty"
        static let speedSolve = "com.couchsuite.nine.swift"
    }

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            Task { @MainActor in
                guard let self else { return }
                if let viewController { Self.present(viewController) }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            }
        }
    }

    /// Mirror one finished board into leaderboards + achievements.
    func reportSolve(record: SolveRecord, history: SolveHistory, streak: StreakState) {
        guard isAuthenticated else { return }
        Task {
            try? await GKLeaderboard.submitScore(
                history.totalPoints, context: 0, player: GKLocalPlayer.local,
                leaderboardIDs: [ID.pointsBoard]
            )
            try? await GKLeaderboard.submitScore(
                streak.best, context: 0, player: GKLocalPlayer.local,
                leaderboardIDs: [ID.streakBoard]
            )
            let solves = history.records.count
            var achievements: [GKAchievement] = [
                progress(ID.firstSolve, fraction: Double(solves)),
                progress(ID.tenSolves, fraction: Double(solves) / 10),
                progress(ID.fiftySolves, fraction: Double(solves) / 50),
                progress(ID.weekStreak, fraction: Double(streak.best) / 7),
                progress(ID.monthStreak, fraction: Double(streak.best) / 30),
            ]
            if history.count(of: .sharp) >= 1 {
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

#if os(iOS)
extension GameCenter: GKGameCenterControllerDelegate {
    nonisolated func gameCenterViewControllerDidFinish(_ controller: GKGameCenterViewController) {
        Task { @MainActor in
            controller.dismiss(animated: true)
        }
    }
}
#endif
#endif
