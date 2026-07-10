// Same seed + same input script ⇒ byte-identical states, for every game.
import XCTest
import CouchCore
@testable import CartridgeEngine

final class DeterminismTests: XCTestCase {
    private let dt = CartridgeClock.dt

    /// A deterministic, scheme-legal input script keyed by tick index.
    private func scriptedInput(for scheme: Scheme, tick: Int) -> SchemeInput? {
        switch scheme {
        case .clickOnly:
            return tick % 23 == 0 ? .click : nil
        case .swipeSteer, .fourWaySnap:
            guard tick % 17 == 0 else { return nil }
            let dirs: [Direction4] = [.up, .right, .down, .left]
            return .swipe(dirs[(tick / 17) % dirs.count])
        case .holdRelease:
            if tick % 61 == 0 { return .holdBegan }
            if tick % 61 == 30 { return .holdEnded }
            return nil
        }
    }

    private func runTwice<C: Cartridge>(_ game: C, seed: UInt64, ticks: Int) -> (C.State, C.State) {
        func run() -> C.State {
            var state = game.newRound(seed: seed, mutator: .identity)
            for t in 0..<ticks {
                state = game.tick(state, input: scriptedInput(for: game.scheme, tick: t), dt: dt)
            }
            return state
        }
        return (run(), run())
    }

    func testFlapDeterminism() {
        let (a, b) = runTwice(FlapGame(), seed: 0xF00D, ticks: 900)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.entities, b.entities)
    }

    func testNoodleDeterminism() {
        let (a, b) = runTwice(NoodleGame(), seed: 0xBEEF, ticks: 900)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.entities, b.entities)
    }

    func testQuadrantDeterminism() {
        let (a, b) = runTwice(QuadrantGame(), seed: 0xCAFE, ticks: 900)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.entities, b.entities)
    }

    func testPuttDeterminism() {
        let (a, b) = runTwice(PuttGame(), seed: 0xD1CE, ticks: 900)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.entities, b.entities)
    }

    func testBotRunsAreDeterministicThroughErasedSessions() {
        for id in GameID.allCases {
            var s1 = CartridgeCatalog.session(for: id, seed: 42)
            var s2 = CartridgeCatalog.session(for: id, seed: 42)
            for _ in 0..<600 {
                s1.tickWithBot()
                s2.tickWithBot()
            }
            XCTAssertEqual(s1.score, s2.score, "\(id) bot run diverged (score)")
            XCTAssertEqual(s1.entities, s2.entities, "\(id) bot run diverged (entities)")
        }
    }

    func testDifferentSeedsDifferentRounds() {
        let game = FlapGame()
        var a = game.newRound(seed: 1)
        var b = game.newRound(seed: 2)
        for t in 0..<600 {
            let input = scriptedInput(for: .clickOnly, tick: t)
            a = game.tick(a, input: input, dt: dt)
            b = game.tick(b, input: input, dt: dt)
        }
        XCTAssertNotEqual(a.pipes.map(\.gapY), b.pipes.map(\.gapY))
    }

    func testSchemeGateDropsForeignInputInsideSession() {
        // A swipe fed to click-only Flap must change nothing.
        var withSwipe = CartridgeCatalog.session(for: .flap, seed: 7)
        var without = CartridgeCatalog.session(for: .flap, seed: 7)
        for _ in 0..<300 {
            withSwipe.tick(input: .swipe(.up))
            without.tick(input: nil)
        }
        XCTAssertEqual(withSwipe.entities, without.entities)

        // And the tick function itself ignores foreign verbs (double gate).
        let game = NoodleGame()
        var a = game.newRound(seed: 3)
        var b = game.newRound(seed: 3)
        for _ in 0..<300 {
            a = game.tick(a, input: .click, dt: dt)
            b = game.tick(b, input: nil, dt: dt)
        }
        XCTAssertEqual(a, b)
    }
}
