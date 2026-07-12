// Putt — scheme D (hold-and-release). Charge-shot mini-golf: the aim line
// sweeps on its own (single-axis), hold charges power, release putts.
import Foundation
import CouchCore

public struct PuttState: CartridgeState, Equatable {
    public enum Phase: String, Sendable, Equatable {
        case aiming     // aim angle sweeps automatically
        case charging   // hold began; power ping-pongs 0…1
        case rolling    // ball in motion
    }

    public var phase: Phase
    public var ballX: Double
    public var ballY: Double
    public var velX: Double
    public var velY: Double
    public var aimAngle: Double       // degrees CCW from +x
    public var power: Double          // 0…1
    public var powerRising: Bool
    public var holeX: Double
    public var holeY: Double
    public var strokesLeft: Int
    public var sweepSpeed: Double     // deg/s
    public var noise: NoiseStream

    public var score: Int
    public var isGameOver: Bool
    public var elapsed: Double

    public var entities: [Entity] {
        var list: [Entity] = [
            Entity(
                id: 1, kind: .goal,
                x: holeX, y: holeY,
                width: PuttGame.holeRadius * 2.4, height: PuttGame.holeRadius * 2.4
            ),
        ]
        if phase != .rolling {
            // Aim sweep + charge meter, one indicator anchored on the ball.
            list.append(Entity(
                id: 2, kind: .indicator,
                x: ballX, y: ballY,
                width: 2.6, height: 2.6,
                rotation: aimAngle, value: phase == .charging ? power : 0
            ))
        }
        list.append(Entity(
            id: 0, kind: .hero,
            x: ballX, y: ballY,
            width: PuttGame.ballRadius * 2.6, height: PuttGame.ballRadius * 2.6,
            rotation: 0, spriteSlot: 0,
            value: Double(strokesLeft)
        ))
        return list
    }
}

public struct PuttGame: Cartridge {
    public let id: GameID = .putt
    public let scheme: Scheme = .holdRelease

    static let ballRadius: Double = 0.28
    static let holeRadius: Double = 0.42
    /// Ball only drops when slow enough — blasting over the cup rolls on.
    static let captureSpeed: Double = 6.0
    static let friction: Double = 3.2          // u/s² decel
    static let minShotSpeed: Double = 3.0
    static let maxShotSpeed: Double = 10.0
    static let baseSweepSpeed: Double = 75      // deg/s
    static let powerRate: Double = 0.9          // charge per second, ping-pong
    static let restitution: Double = 0.72
    static let inset: Double = 0.6              // course walls
    static let strokesPerHole = 3
    static let holeDistance: ClosedRange<Double> = 3.5...8.5

    public init() {}

    public func newRound(seed: UInt64, mutator: Mutator) -> PuttState {
        var noise = NoiseStream(seed: seed)
        let ballX = World.width * 0.28
        let ballY = World.height * 0.5
        let hole = Self.spawnHole(awayFrom: (ballX, ballY), noise: &noise)
        return PuttState(
            phase: .aiming,
            ballX: ballX, ballY: ballY,
            velX: 0, velY: 0,
            aimAngle: 0,
            power: 0,
            powerRising: true,
            holeX: hole.x, holeY: hole.y,
            strokesLeft: Self.strokesPerHole,
            sweepSpeed: Self.baseSweepSpeed * mutator.speed,
            noise: noise,
            score: 0,
            isGameOver: false,
            elapsed: 0
        )
    }

    public func tick(_ state: PuttState, input: SchemeInput?, dt: Double) -> PuttState {
        guard !state.isGameOver else { return state }
        var s = state
        s.elapsed += dt

        switch s.phase {
        case .aiming:
            if case .holdBegan = input {
                // Freeze the aim exactly where the player (or bot) caught it.
                s.phase = .charging
                s.power = 0
                s.powerRising = true
            } else {
                s.aimAngle = Angle.normalized(s.aimAngle + s.sweepSpeed * dt)
            }

        case .charging:
            // Ping-pong 0…1 — release timing is the whole skill.
            var p = s.power + (s.powerRising ? 1 : -1) * Self.powerRate * dt
            if p >= 1 { p = 1; s.powerRising = false }
            if p <= 0 { p = 0; s.powerRising = true }
            s.power = p
            if case .holdEnded = input {
                let speed = Self.minShotSpeed + s.power * (Self.maxShotSpeed - Self.minShotSpeed)
                let radians = s.aimAngle * .pi / 180
                s.velX = cos(radians) * speed
                s.velY = sin(radians) * speed
                s.phase = .rolling
                s.strokesLeft -= 1
            }

        case .rolling:
            roll(&s, dt: dt)
        }

        if s.elapsed >= CartridgeClock.lifeCap { s.isGameOver = true }
        return s
    }

    private func roll(_ s: inout PuttState, dt: Double) {
        s.ballX += s.velX * dt
        s.ballY += s.velY * dt

        // Cushion bounces.
        let minX = Self.inset + Self.ballRadius
        let maxX = World.width - Self.inset - Self.ballRadius
        let minY = Self.inset + Self.ballRadius
        let maxY = World.height - Self.inset - Self.ballRadius
        if s.ballX < minX { s.ballX = minX; s.velX = abs(s.velX) * Self.restitution }
        if s.ballX > maxX { s.ballX = maxX; s.velX = -abs(s.velX) * Self.restitution }
        if s.ballY < minY { s.ballY = minY; s.velY = abs(s.velY) * Self.restitution }
        if s.ballY > maxY { s.ballY = maxY; s.velY = -abs(s.velY) * Self.restitution }

        // Friction.
        let speed = (s.velX * s.velX + s.velY * s.velY).squareRoot()
        if speed > 0 {
            let newSpeed = max(0, speed - Self.friction * dt)
            let scale = speed == 0 ? 0 : newSpeed / speed
            s.velX *= scale
            s.velY *= scale
        }

        // Cup capture: near enough and slow enough.
        let dx = s.ballX - s.holeX, dy = s.ballY - s.holeY
        if dx * dx + dy * dy <= Self.holeRadius * Self.holeRadius,
           speed <= Self.captureSpeed {
            s.score += 1
            s.strokesLeft = Self.strokesPerHole
            s.velX = 0
            s.velY = 0
            let hole = Self.spawnHole(awayFrom: (s.ballX, s.ballY), noise: &s.noise)
            s.holeX = hole.x
            s.holeY = hole.y
            s.phase = .aiming
            return
        }

        // Ball stopped without sinking: next stroke or game over.
        if speed <= 0.02 {
            s.velX = 0
            s.velY = 0
            if s.strokesLeft <= 0 {
                s.isGameOver = true
            } else {
                s.phase = .aiming
            }
        }
    }

    static func spawnHole(
        awayFrom ball: (x: Double, y: Double), noise: inout NoiseStream
    ) -> (x: Double, y: Double) {
        let pad = inset + holeRadius + 0.3
        for _ in 0..<32 {
            let x = noise.next(in: pad...(World.width - pad))
            let y = noise.next(in: pad...(World.height - pad))
            let dx = x - ball.x, dy = y - ball.y
            let d = (dx * dx + dy * dy).squareRoot()
            if holeDistance.contains(d) { return (x, y) }
        }
        // Deterministic fallback: farthest corner.
        let corners = [
            (pad, pad), (World.width - pad, pad),
            (pad, World.height - pad), (World.width - pad, World.height - pad),
        ]
        return corners.max { a, b in
            let da = (a.0 - ball.x) * (a.0 - ball.x) + (a.1 - ball.y) * (a.1 - ball.y)
            let db = (b.0 - ball.x) * (b.0 - ball.x) + (b.1 - ball.y) * (b.1 - ball.y)
            return da < db
        }.map { (x: $0.0, y: $0.1) } ?? (World.width - pad, World.height - pad)
    }

    /// Bot: wait for the sweep to cross the hole line, hold, release when the
    /// charge matches the distance (arriving at the cup under capture speed).
    public func bot(_ state: PuttState) -> SchemeInput? {
        guard !state.isGameOver else { return nil }
        let dx = state.holeX - state.ballX
        let dy = state.holeY - state.ballY
        let distance = (dx * dx + dy * dy).squareRoot()

        switch state.phase {
        case .aiming:
            let target = Angle.normalized(atan2(dy, dx) * 180 / .pi)
            if Angle.difference(state.aimAngle, target) <= 1.3 {
                return .holdBegan
            }
            return nil
        case .charging:
            // Arrive with ~4 u/s to spare: v0² = 2·a·d + v_arrive².
            let arrive = 4.0
            let v0 = (2 * Self.friction * distance + arrive * arrive).squareRoot()
            let needed = (v0 - Self.minShotSpeed) / (Self.maxShotSpeed - Self.minShotSpeed)
            let clamped = max(0.02, min(0.95, needed))
            if state.powerRising && state.power >= clamped {
                return .holdEnded
            }
            if !state.powerRising && state.power <= clamped {
                return .holdEnded
            }
            return nil
        case .rolling:
            return nil
        }
    }
}
