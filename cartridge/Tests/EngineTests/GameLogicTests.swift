// Game-over detection, scoring, and collision-math edge cases.
import XCTest
import CouchCore
@testable import CartridgeEngine

final class GameLogicTests: XCTestCase {
    private let dt = CartridgeClock.dt

    // MARK: Game over

    func testFlapDiesWithoutInput() {
        let game = FlapGame()
        var s = game.newRound(seed: 1)
        var ticks = 0
        while !s.isGameOver && ticks < 600 {
            s = game.tick(s, input: nil, dt: dt)
            ticks += 1
        }
        XCTAssertTrue(s.isGameOver, "an unflapped hero must hit the floor")
        XCTAssertLessThan(s.elapsed, 3, "the fall should take about a second")
    }

    func testNoodleDiesOnWall() {
        let game = NoodleGame()
        var s = game.newRound(seed: 1)
        // Head starts at x=8 heading right; the wall is 24 cells away.
        var ticks = 0
        while !s.isGameOver && ticks < 60 * 30 {
            s = game.tick(s, input: nil, dt: dt)
            ticks += 1
        }
        XCTAssertTrue(s.isGameOver, "steering into the wall must end the round")
    }

    func testNoodleRejectsReversal() {
        let game = NoodleGame()
        var s = game.newRound(seed: 1)
        // Heading right; a left swipe is a 180° reversal and must be ignored.
        s = game.tick(s, input: .swipe(.left), dt: dt)
        XCTAssertNil(s.pendingDirection)
        s = game.tick(s, input: .swipe(.up), dt: dt)
        XCTAssertEqual(s.pendingDirection, .up)
    }

    func testQuadrantHazardKillsOnlyInItsZone() {
        let game = QuadrantGame()
        var s = game.newRound(seed: 1)
        s.fallers = [
            QuadrantState.Faller(id: 1, zone: 0, isHazard: true, timeLeft: dt / 2, fallTime: 1.7, spriteSlot: 1)
        ]
        // Standing in zone 0: dead.
        var dead = s
        dead.zone = 0
        dead = game.tick(dead, input: nil, dt: dt)
        XCTAssertTrue(dead.isGameOver)
        // Standing in zone 3: alive.
        var alive = s
        alive.zone = 3
        alive = game.tick(alive, input: nil, dt: dt)
        XCTAssertFalse(alive.isGameOver)
    }

    func testQuadrantPickupScoresOnlyWhenCaught() {
        let game = QuadrantGame()
        var s = game.newRound(seed: 1)
        s.fallers = [
            QuadrantState.Faller(id: 1, zone: 2, isHazard: false, timeLeft: dt / 2, fallTime: 1.7, spriteSlot: 1)
        ]
        var caught = s
        caught.zone = 2
        caught = game.tick(caught, input: nil, dt: dt)
        XCTAssertEqual(caught.score, 1)
        var missed = s
        missed.zone = 1
        missed = game.tick(missed, input: nil, dt: dt)
        XCTAssertEqual(missed.score, 0)
        XCTAssertFalse(missed.isGameOver, "missed pickups never punish")
    }

    func testQuadrantSnapMapping() {
        XCTAssertEqual(QuadrantGame.snapped(from: 0, by: .right), 1)
        XCTAssertEqual(QuadrantGame.snapped(from: 1, by: .down), 3)
        XCTAssertEqual(QuadrantGame.snapped(from: 3, by: .left), 2)
        XCTAssertEqual(QuadrantGame.snapped(from: 2, by: .up), 0)
        XCTAssertEqual(QuadrantGame.snapped(from: 0, by: .up), 0, "snapping off the board stays put")
    }

    func testPuttStrokeExhaustionEndsRound() {
        let game = PuttGame()
        var s = game.newRound(seed: 1)
        // Pin the hole far off the aim-0 line so every shot is a real miss.
        s.holeX = 2.0
        s.holeY = 8.2
        // Fire three deliberate duds: hold + instant release at whatever aim.
        for _ in 0..<3 {
            XCTAssertFalse(s.isGameOver)
            s = game.tick(s, input: .holdBegan, dt: dt)
            s = game.tick(s, input: .holdEnded, dt: dt)
            var guard_ = 0
            while s.phase == .rolling && guard_ < 60 * 20 {
                s = game.tick(s, input: nil, dt: dt)
                guard_ += 1
            }
        }
        XCTAssertTrue(s.isGameOver, "three misses must end the round")
        XCTAssertEqual(s.score, 0)
    }

    func testLifeCapEndsEveryRound() {
        // Putt with no input never dies by play — the 90 s cap must catch it.
        let game = PuttGame()
        var s = game.newRound(seed: 1)
        let cap = Int(CartridgeClock.lifeCap * CartridgeClock.tickRate) + 2
        for _ in 0..<cap where !s.isGameOver {
            s = game.tick(s, input: nil, dt: dt)
        }
        XCTAssertTrue(s.isGameOver)
    }

    func testFlapScoresWhenPipePasses() {
        let game = FlapGame()
        var s = game.newRound(seed: 1)
        s.pipes = [FlapState.Pipe(id: 9, x: FlapGame.heroX + 1.2, gapY: s.heroY, passed: false)]
        s.spawnCountdown = 999
        var ticks = 0
        while s.score == 0 && !s.isGameOver && ticks < 240 {
            // Hover through the gap with the bot so we only test scoring.
            s = game.tick(s, input: game.bot(s), dt: dt)
            ticks += 1
        }
        XCTAssertEqual(s.score, 1)
    }

    // MARK: Collision math edges

    func testCircleCircleExactTouchCounts() {
        XCTAssertTrue(Hit.circleOverlapsCircle(0, 0, 1, 2, 0, 1))
        XCTAssertFalse(Hit.circleOverlapsCircle(0, 0, 1, 2.001, 0, 1))
    }

    func testPointToSegmentDistanceEdges() {
        // Beyond endpoint A: distance to A.
        XCTAssertEqual(Hit.distance(px: -1, py: 0, ax: 0, ay: 0, bx: 2, by: 0), 1, accuracy: 1e-12)
        // Perpendicular foot inside the segment.
        XCTAssertEqual(Hit.distance(px: 1, py: 3, ax: 0, ay: 0, bx: 2, by: 0), 3, accuracy: 1e-12)
        // Degenerate zero-length segment.
        XCTAssertEqual(Hit.distance(px: 3, py: 4, ax: 0, ay: 0, bx: 0, by: 0), 5, accuracy: 1e-12)
    }

    func testCircleCapsuleOverlap() {
        XCTAssertTrue(Hit.circleOverlapsCapsule(
            cx: 1, cy: 0.9, r: 0.5, ax: 0, ay: 0, bx: 2, by: 0, capsuleRadius: 0.5
        ))
        XCTAssertFalse(Hit.circleOverlapsCapsule(
            cx: 1, cy: 1.01, r: 0.5, ax: 0, ay: 0, bx: 2, by: 0, capsuleRadius: 0.5
        ))
    }

    func testCircleRectCornerCase() {
        // Circle near a rect corner: inside only if within radius of the corner.
        let touching = Hit.circleOverlapsRect(
            cx: 3 + 0.7, cy: 4 + 0.7, r: 1, minX: 0, minY: 0, maxX: 3, maxY: 4
        )
        XCTAssertTrue(touching) // corner distance ≈ 0.99
        let missing = Hit.circleOverlapsRect(
            cx: 3 + 0.75, cy: 4 + 0.75, r: 1, minX: 0, minY: 0, maxX: 3, maxY: 4
        )
        XCTAssertFalse(missing) // corner distance ≈ 1.06
        // Center inside the rect always hits.
        XCTAssertTrue(Hit.circleOverlapsRect(cx: 1, cy: 1, r: 0.1, minX: 0, minY: 0, maxX: 3, maxY: 4))
    }

    func testAngleHelpers() {
        XCTAssertEqual(Angle.normalized(-90), 270)
        XCTAssertEqual(Angle.normalized(725), 5)
        XCTAssertEqual(Angle.difference(350, 10), 20)
        XCTAssertEqual(Angle.difference(90, 90), 0)
    }
}
