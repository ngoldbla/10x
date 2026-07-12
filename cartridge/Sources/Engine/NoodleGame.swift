// Noodle — scheme B (swipe-steer). Snake whose tail is your photo strip.
import Foundation
import CouchCore

public struct GridPoint: Sendable, Equatable, Hashable {
    public var x: Int
    public var y: Int
    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

public struct NoodleState: CartridgeState, Equatable {
    /// Head first, tail last.
    public var body: [GridPoint]
    public var direction: Direction4
    /// Latest legal swipe, applied on the next step (prevents mid-cell
    /// double-turns and 180° reversals — remote-weakness-proof by design).
    public var pendingDirection: Direction4?
    public var stepInterval: Double
    public var stepCountdown: Double
    public var food: GridPoint
    public var growth: Int
    public var noise: NoiseStream

    public var score: Int
    public var isGameOver: Bool
    public var elapsed: Double

    public var entities: [Entity] {
        let cell = NoodleGame.cellSize
        var list: [Entity] = []
        list.append(Entity(
            id: 1, kind: .pickup,
            x: (Double(food.x) + 0.5) * cell, y: (Double(food.y) + 0.5) * cell,
            width: cell * 0.9, height: cell * 0.9,
            spriteSlot: 1 + score % 6
        ))
        // Tail → head so the head draws on top. Each segment is a different
        // sprite slot: the tail literally becomes a strip of your photos.
        for (i, p) in body.enumerated().reversed() where i > 0 {
            list.append(Entity(
                id: 100 + i, kind: .segment,
                x: (Double(p.x) + 0.5) * cell, y: (Double(p.y) + 0.5) * cell,
                width: cell * 0.92, height: cell * 0.92,
                spriteSlot: 1 + (i - 1) % 6
            ))
        }
        if let head = body.first {
            list.append(Entity(
                id: 0, kind: .hero,
                x: (Double(head.x) + 0.5) * cell, y: (Double(head.y) + 0.5) * cell,
                width: cell * 1.05, height: cell * 1.05,
                rotation: NoodleGame.angle(of: direction), spriteSlot: 0
            ))
        }
        return list
    }
}

public struct NoodleGame: Cartridge {
    public let id: GameID = .noodle
    public let scheme: Scheme = .swipeSteer

    public static let cols = 32
    public static let rows = 18
    static let cellSize = World.width / Double(cols)   // 0.5 — also fits 18 rows
    static let baseStepInterval: Double = 0.14
    static let growthPerFood = 2

    public init() {}

    public func newRound(seed: UInt64, mutator: Mutator) -> NoodleState {
        let midY = Self.rows / 2
        let body = [GridPoint(8, midY), GridPoint(7, midY), GridPoint(6, midY)]
        var noise = NoiseStream(seed: seed)
        let food = Self.spawnFood(avoiding: body, noise: &noise)
        return NoodleState(
            body: body,
            direction: .right,
            pendingDirection: nil,
            stepInterval: Self.baseStepInterval / mutator.speed,
            stepCountdown: Self.baseStepInterval / mutator.speed,
            food: food,
            growth: 0,
            noise: noise,
            score: 0,
            isGameOver: false,
            elapsed: 0
        )
    }

    public func tick(_ state: NoodleState, input: SchemeInput?, dt: Double) -> NoodleState {
        guard !state.isGameOver else { return state }
        var s = state
        s.elapsed += dt

        if case .swipe(let dir) = input, scheme.accepts(.swipe(dir)),
           dir != Self.opposite(s.direction) {
            s.pendingDirection = dir
        }

        s.stepCountdown -= dt
        while s.stepCountdown <= 0 && !s.isGameOver {
            s.stepCountdown += s.stepInterval
            step(&s)
        }

        if s.elapsed >= CartridgeClock.lifeCap { s.isGameOver = true }
        return s
    }

    private func step(_ s: inout NoodleState) {
        if let pending = s.pendingDirection, pending != Self.opposite(s.direction) {
            s.direction = pending
        }
        s.pendingDirection = nil

        guard let head = s.body.first else { return }
        let next = Self.moved(head, s.direction)

        // Walls.
        if next.x < 0 || next.x >= Self.cols || next.y < 0 || next.y >= Self.rows {
            s.isGameOver = true
            return
        }
        // Self collision. The tail cell vacates this step unless growing.
        let occupied = s.growth > 0 ? s.body : Array(s.body.dropLast())
        if occupied.contains(next) {
            s.isGameOver = true
            return
        }

        s.body.insert(next, at: 0)
        if s.growth > 0 {
            s.growth -= 1
        } else {
            s.body.removeLast()
        }

        if next == s.food {
            s.score += 1
            s.growth += Self.growthPerFood
            s.food = Self.spawnFood(avoiding: s.body, noise: &s.noise)
        }
    }

    /// Bot: greedy toward the food, but never into a pocket smaller than the
    /// snake (flood-fill lookahead keeps it from trapping itself).
    public func bot(_ state: NoodleState) -> SchemeInput? {
        guard !state.isGameOver, let head = state.body.first else { return nil }
        let current = state.pendingDirection ?? state.direction
        let blocked = Set(state.body.dropLast())

        func inBounds(_ p: GridPoint) -> Bool {
            p.x >= 0 && p.x < Self.cols && p.y >= 0 && p.y < Self.rows
        }
        func dist(_ p: GridPoint) -> Int {
            abs(p.x - state.food.x) + abs(p.y - state.food.y)
        }
        /// Free cells reachable from `start` — room to keep living.
        func reachable(from start: GridPoint) -> Int {
            var seen: Set<GridPoint> = [start]
            var queue = [start]
            var i = 0
            while i < queue.count {
                let p = queue[i]
                i += 1
                for d in Direction4.allCases {
                    let n = Self.moved(p, d)
                    if inBounds(n) && !blocked.contains(n) && !seen.contains(n) {
                        seen.insert(n)
                        queue.append(n)
                    }
                }
            }
            return seen.count
        }

        let candidates = Direction4.allCases
            .filter { $0 != Self.opposite(state.direction) }
            .map { (dir: $0, cell: Self.moved(head, $0)) }
            .filter { inBounds($0.cell) && !blocked.contains($0.cell) }
            .map { (dir: $0.dir, cell: $0.cell, room: reachable(from: $0.cell)) }
        guard !candidates.isEmpty else { return nil }

        let needed = state.body.count + 2
        let roomy = candidates.filter { $0.room >= needed }
        let best = roomy.min { dist($0.cell) < dist($1.cell) }
            ?? candidates.max { $0.room < $1.room }
        guard let best else { return nil }
        return best.dir == current ? nil : .swipe(best.dir)
    }

    // MARK: helpers

    static func spawnFood(avoiding body: [GridPoint], noise: inout NoiseStream) -> GridPoint {
        let taken = Set(body)
        var free: [GridPoint] = []
        free.reserveCapacity(cols * rows - taken.count)
        for y in 0..<rows {
            for x in 0..<cols {
                let p = GridPoint(x, y)
                if !taken.contains(p) { free.append(p) }
            }
        }
        guard !free.isEmpty else { return GridPoint(0, 0) }
        return free[noise.nextInt(below: free.count)]
    }

    static func moved(_ p: GridPoint, _ d: Direction4) -> GridPoint {
        switch d {
        case .right: return GridPoint(p.x + 1, p.y)
        case .left: return GridPoint(p.x - 1, p.y)
        case .up: return GridPoint(p.x, p.y + 1)     // +y up, suite convention
        case .down: return GridPoint(p.x, p.y - 1)
        }
    }

    static func opposite(_ d: Direction4) -> Direction4 {
        switch d {
        case .right: return .left
        case .left: return .right
        case .up: return .down
        case .down: return .up
        }
    }

    static func angle(of d: Direction4) -> Double {
        switch d {
        case .right: return 0
        case .up: return 90
        case .left: return 180
        case .down: return 270
        }
    }
}
