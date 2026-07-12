// Quadrant — scheme C (four-way snap). Snap between four zones to catch
// the good fallers and dodge the bad ones.
import Foundation
import CouchCore

public struct QuadrantState: CartridgeState, Equatable {
    public struct Faller: Sendable, Equatable {
        public var id: Int
        public var zone: Int          // 0 TL, 1 TR, 2 BL, 3 BR
        public var isHazard: Bool
        public var timeLeft: Double   // seconds until impact
        public var fallTime: Double   // total flight time (for render progress)
        public var spriteSlot: Int
    }

    public var zone: Int
    public var fallers: [Faller]
    public var spawnCountdown: Double
    public var spawnInterval: Double
    public var fallTime: Double
    public var nextID: Int
    public var noise: NoiseStream

    public var score: Int
    public var isGameOver: Bool
    public var elapsed: Double

    public var entities: [Entity] {
        var list: [Entity] = []
        // Zone markers so the board reads instantly.
        for z in 0..<4 {
            let c = QuadrantGame.center(of: z)
            list.append(Entity(
                id: 10 + z, kind: .indicator,
                x: c.x, y: c.y,
                width: QuadrantGame.zoneWidth, height: QuadrantGame.zoneHeight,
                value: z == zone ? 1 : 0
            ))
        }
        // Fallers drop from above the screen to their zone center.
        for f in fallers {
            let target = QuadrantGame.center(of: f.zone)
            let progress = 1 - f.timeLeft / f.fallTime
            let startY = World.height + 1.2
            let y = startY + (target.y - startY) * progress
            let size = 0.7 + 0.5 * progress
            list.append(Entity(
                id: f.id, kind: f.isHazard ? .hazard : .pickup,
                x: target.x, y: y,
                width: size, height: size,
                rotation: progress * (f.isHazard ? 200 : 80),
                spriteSlot: f.isHazard ? -1 : f.spriteSlot,
                value: progress
            ))
        }
        let c = QuadrantGame.center(of: zone)
        list.append(Entity(
            id: 0, kind: .hero,
            x: c.x, y: c.y - 0.9,
            width: 1.5, height: 1.5,
            spriteSlot: 0
        ))
        return list
    }
}

public struct QuadrantGame: Cartridge {
    public let id: GameID = .quadrant
    public let scheme: Scheme = .fourWaySnap

    static let zoneWidth = World.width / 2
    static let zoneHeight = World.height / 2
    static let baseSpawnInterval: Double = 1.15
    static let baseFallTime: Double = 1.7
    static let hazardChance: Double = 0.45

    public init() {}

    /// Zone centers. Zones: 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right.
    static func center(of zone: Int) -> (x: Double, y: Double) {
        let col = zone % 2
        let row = zone / 2                       // 0 = top row
        return (
            x: (Double(col) + 0.5) * zoneWidth,
            y: World.height - (Double(row) + 0.5) * zoneHeight
        )
    }

    static func snapped(from zone: Int, by direction: Direction4) -> Int {
        let col = zone % 2
        let row = zone / 2
        switch direction {
        case .right: return row * 2 + 1
        case .left: return row * 2
        case .up: return col              // row 0
        case .down: return 2 + col        // row 1
        }
    }

    public func newRound(seed: UInt64, mutator: Mutator) -> QuadrantState {
        QuadrantState(
            zone: 0,
            fallers: [],
            spawnCountdown: 1.2,
            spawnInterval: Self.baseSpawnInterval / mutator.spawn,
            fallTime: Self.baseFallTime / mutator.speed,
            nextID: 100,
            noise: NoiseStream(seed: seed),
            score: 0,
            isGameOver: false,
            elapsed: 0
        )
    }

    public func tick(_ state: QuadrantState, input: SchemeInput?, dt: Double) -> QuadrantState {
        guard !state.isGameOver else { return state }
        var s = state
        s.elapsed += dt

        if case .swipe(let dir) = input, scheme.accepts(.swipe(dir)) {
            s.zone = Self.snapped(from: s.zone, by: dir)
        }

        // Advance fallers; resolve impacts.
        for i in s.fallers.indices { s.fallers[i].timeLeft -= dt }
        var landed: [QuadrantState.Faller] = []
        s.fallers.removeAll { f in
            if f.timeLeft <= 0 {
                landed.append(f)
                return true
            }
            return false
        }
        for f in landed {
            if f.zone == s.zone {
                if f.isHazard {
                    s.isGameOver = true
                    return s
                } else {
                    s.score += 1
                }
            }
            // A missed pickup just splats — no punishment, catch the next one.
        }

        // Spawn.
        s.spawnCountdown -= dt
        if s.spawnCountdown <= 0 {
            s.spawnCountdown += s.spawnInterval
            let zone = s.noise.nextInt(below: 4)
            let isHazard = s.noise.next() < Self.hazardChance
            let slot = 1 + s.noise.nextInt(below: 6)
            s.fallers.append(QuadrantState.Faller(
                id: s.nextID, zone: zone, isHazard: isHazard,
                timeLeft: s.fallTime, fallTime: s.fallTime, spriteSlot: slot
            ))
            s.nextID += 1
        }

        if s.elapsed >= CartridgeClock.lifeCap { s.isGameOver = true }
        return s
    }

    /// Bot: dodge the most imminent hazard aimed at us; otherwise chase the
    /// most imminent catchable pickup. One swipe per tick, like a human.
    public func bot(_ state: QuadrantState) -> SchemeInput? {
        guard !state.isGameOver else { return nil }

        func hazardImminence(in zone: Int) -> Double {
            state.fallers
                .filter { $0.isHazard && $0.zone == zone && $0.timeLeft < 0.55 }
                .map(\.timeLeft)
                .min() ?? .infinity
        }

        let neighbors: [Direction4] = [.left, .right, .up, .down]
        let threat = hazardImminence(in: state.zone)
        if threat.isFinite {
            // Escape to the safest reachable zone.
            let escape = neighbors
                .map { (dir: $0, zone: QuadrantGame.snapped(from: state.zone, by: $0)) }
                .filter { $0.zone != state.zone }
                .max { hazardImminence(in: $0.zone) < hazardImminence(in: $1.zone) }
            if let escape { return .swipe(escape.dir) }
            return nil
        }

        // Chase: earliest pickup we can still reach (need one swipe ≈ instant,
        // but leave slack for two-step diagonals).
        let target = state.fallers
            .filter { !$0.isHazard && $0.timeLeft > 0.1 }
            .min { $0.timeLeft < $1.timeLeft }
        guard let target, target.zone != state.zone else { return nil }
        // Step toward the target zone, but never into an imminent hazard.
        for dir in neighbors {
            let z = QuadrantGame.snapped(from: state.zone, by: dir)
            guard z != state.zone else { continue }
            let closer =
                (z % 2 == target.zone % 2 && state.zone % 2 != target.zone % 2) ||
                (z / 2 == target.zone / 2 && state.zone / 2 != target.zone / 2)
            if closer && !hazardImminence(in: z).isFinite {
                return .swipe(dir)
            }
        }
        return nil
    }
}
