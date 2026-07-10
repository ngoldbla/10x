// The PRD's verifier idea, actually enforced: for every shipped game the
// bot must survive ≥ 10 seconds of fixed-step ticks on default difficulty —
// proof the game is winnable under its own input scheme.
import XCTest
@testable import CartridgeEngine

final class BotWinnabilityTests: XCTestCase {
    private let tenSeconds = Int(CartridgeClock.tickRate * 10)

    private func botRun(_ id: GameID, seed: UInt64, ticks: Int) -> Session {
        var session = CartridgeCatalog.session(for: id, seed: seed)
        for _ in 0..<ticks where !session.isGameOver {
            session.tickWithBot()
        }
        return session
    }

    func testBotSurvivesTenSecondsInEveryGame() {
        for id in GameID.allCases {
            for seed: UInt64 in [1, 99, 0xABCD] {
                let session = botRun(id, seed: seed, ticks: tenSeconds)
                XCTAssertFalse(
                    session.isGameOver,
                    "\(id) bot died before 10 s (seed \(seed), score \(session.score))"
                )
            }
        }
    }

    func testFlapBotScores() {
        let session = botRun(.flap, seed: 5, ticks: tenSeconds)
        XCTAssertGreaterThanOrEqual(session.score, 2, "Flap bot should clear pipes in 10 s")
    }

    func testNoodleBotEats() {
        let session = botRun(.noodle, seed: 5, ticks: tenSeconds)
        XCTAssertGreaterThanOrEqual(session.score, 2, "Noodle bot should reach food in 10 s")
    }

    func testQuadrantBotCatches() {
        let session = botRun(.quadrant, seed: 5, ticks: tenSeconds)
        XCTAssertGreaterThanOrEqual(session.score, 1, "Quadrant bot should catch a pickup in 10 s")
    }

    func testPuttBotSinksHoles() {
        let session = botRun(.putt, seed: 5, ticks: tenSeconds * 3)
        XCTAssertGreaterThanOrEqual(session.score, 2, "Putt bot should sink holes")
        XCTAssertFalse(session.isGameOver)
    }

    func testBotsSurviveThirtySeconds() {
        // Attract mode runs long; the demo shouldn't visibly die young.
        for id in GameID.allCases {
            let session = botRun(id, seed: 2026, ticks: tenSeconds * 3)
            XCTAssertFalse(session.isGameOver, "\(id) bot died before 30 s")
        }
    }
}
