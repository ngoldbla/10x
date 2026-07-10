// Flap — scheme A (click-only). Your pet flaps through gaps.
import Foundation
import CouchCore

public struct FlapState: CartridgeState, Equatable {
    public struct Pipe: Sendable, Equatable {
        public var id: Int
        public var x: Double        // center x, world units
        public var gapY: Double     // gap center y
        public var passed: Bool
    }

    // Tuning resolved at newRound (mutator applied once, then frozen).
    public var pipeSpeed: Double
    public var gravity: Double
    public var spawnInterval: Double

    public var heroY: Double
    public var heroVY: Double
    public var pipes: [Pipe]
    public var spawnCountdown: Double
    public var nextID: Int
    public var noise: NoiseStream

    public var score: Int
    public var isGameOver: Bool
    public var elapsed: Double

    public var entities: [Entity] {
        var list: [Entity] = []
        for pipe in pipes {
            let gapHalf = FlapGame.gapHeight / 2
            let topHeight = World.height - (pipe.gapY + gapHalf)
            if topHeight > 0.01 {
                list.append(Entity(
                    id: pipe.id * 2, kind: .obstacle,
                    x: pipe.x, y: pipe.gapY + gapHalf + topHeight / 2,
                    width: FlapGame.pipeWidth, height: topHeight
                ))
            }
            let bottomHeight = pipe.gapY - gapHalf
            if bottomHeight > 0.01 {
                list.append(Entity(
                    id: pipe.id * 2 + 1, kind: .obstacle,
                    x: pipe.x, y: bottomHeight / 2,
                    width: FlapGame.pipeWidth, height: bottomHeight
                ))
            }
        }
        // Hero last (on top); tilt with vertical velocity, like the classic.
        let tilt = max(-40, min(35, heroVY * 6))
        list.append(Entity(
            id: 0, kind: .hero,
            x: FlapGame.heroX, y: heroY,
            width: FlapGame.heroRadius * 2.4, height: FlapGame.heroRadius * 2.4,
            rotation: tilt, spriteSlot: 0
        ))
        return list
    }
}

public struct FlapGame: Cartridge {
    public let id: GameID = .flap
    public let scheme: Scheme = .clickOnly

    // Base tuning (world units, seconds).
    static let heroX: Double = 4.2
    static let heroRadius: Double = 0.34
    static let pipeWidth: Double = 1.35
    static let gapHeight: Double = 3.2
    static let flapVelocity: Double = 7.2
    static let terminalVelocity: Double = -10.5
    static let gapRange: ClosedRange<Double> = 2.3...6.7
    static let baseGravity: Double = 20
    static let basePipeSpeed: Double = 3.4
    static let baseSpawnInterval: Double = 2.1

    public init() {}

    public func newRound(seed: UInt64, mutator: Mutator) -> FlapState {
        FlapState(
            pipeSpeed: Self.basePipeSpeed * mutator.speed,
            gravity: Self.baseGravity * mutator.gravity,
            spawnInterval: Self.baseSpawnInterval / mutator.spawn,
            heroY: World.height / 2,
            heroVY: 0,
            pipes: [],
            spawnCountdown: 1.0,
            nextID: 1,
            noise: NoiseStream(seed: seed),
            score: 0,
            isGameOver: false,
            elapsed: 0
        )
    }

    public func tick(_ state: FlapState, input: SchemeInput?, dt: Double) -> FlapState {
        guard !state.isGameOver else { return state }
        var s = state
        s.elapsed += dt

        if case .click = input, scheme.accepts(.click) {
            s.heroVY = Self.flapVelocity
        }

        // Integrate hero.
        s.heroVY = max(Self.terminalVelocity, s.heroVY - s.gravity * dt)
        s.heroY += s.heroVY * dt
        // Soft ceiling: clamp, kill upward velocity.
        if s.heroY > World.height - Self.heroRadius {
            s.heroY = World.height - Self.heroRadius
            s.heroVY = min(s.heroVY, 0)
        }

        // Scroll pipes, score passes.
        for i in s.pipes.indices {
            s.pipes[i].x -= s.pipeSpeed * dt
            if !s.pipes[i].passed, s.pipes[i].x + Self.pipeWidth / 2 < Self.heroX - Self.heroRadius {
                s.pipes[i].passed = true
                s.score += 1
            }
        }
        s.pipes.removeAll { $0.x < -Self.pipeWidth }

        // Spawn.
        s.spawnCountdown -= dt
        if s.spawnCountdown <= 0 {
            s.spawnCountdown += s.spawnInterval
            let gapY = s.noise.next(in: Self.gapRange)
            s.pipes.append(FlapState.Pipe(
                id: s.nextID, x: World.width + Self.pipeWidth, gapY: gapY, passed: false
            ))
            s.nextID += 1
        }

        // Death: floor, or circle vs pipe rects. Photo content never matters —
        // the hero is a fixed-radius circle.
        if s.heroY - Self.heroRadius <= 0 {
            s.isGameOver = true
            return s
        }
        let gapHalf = Self.gapHeight / 2
        for pipe in s.pipes {
            let minX = pipe.x - Self.pipeWidth / 2
            let maxX = pipe.x + Self.pipeWidth / 2
            let hitTop = Hit.circleOverlapsRect(
                cx: Self.heroX, cy: s.heroY, r: Self.heroRadius,
                minX: minX, minY: pipe.gapY + gapHalf, maxX: maxX, maxY: World.height
            )
            let hitBottom = Hit.circleOverlapsRect(
                cx: Self.heroX, cy: s.heroY, r: Self.heroRadius,
                minX: minX, minY: 0, maxX: maxX, maxY: pipe.gapY - gapHalf
            )
            if hitTop || hitBottom {
                s.isGameOver = true
                return s
            }
        }

        if s.elapsed >= CartridgeClock.lifeCap { s.isGameOver = true }
        return s
    }

    /// Bot: aim at the nearest gap; flap when sinking below the aim point.
    public func bot(_ state: FlapState) -> SchemeInput? {
        guard !state.isGameOver else { return nil }
        let ahead = state.pipes
            .filter { $0.x + Self.pipeWidth / 2 >= Self.heroX - Self.heroRadius }
            .min { $0.x < $1.x }
        let target = ahead?.gapY ?? World.height / 2
        if state.heroY < target - 0.2 && state.heroVY < 0.8 {
            return .click
        }
        return nil
    }
}
