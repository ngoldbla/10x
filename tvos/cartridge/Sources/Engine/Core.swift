// Cartridge engine core — pure Swift, deterministic, platform-free.
// Games are pure functions of (state, input, dt); rendering is somebody
// else's problem (entities are abstract).
import Foundation
import CouchCore

// MARK: - Clock

/// The suite's fixed timestep. Every session ticks at 60 Hz; the UI layer
/// accumulates wall time and calls `tick` in whole steps only.
public enum CartridgeClock {
    public static let tickRate: Double = 60
    public static let dt: Double = 1.0 / 60.0
    /// Hard cap from the PRD: no game lasts longer than 90 s per life.
    public static let lifeCap: Double = 90
}

// MARK: - World

/// Games play in a fixed 16×9 world. +x right, +y up (GCMicroGamepad
/// convention, same as CouchCore's flick math). The UI maps world → screen.
public enum World {
    public static let width: Double = 16
    public static let height: Double = 9
}

// MARK: - Input schemes (the law — PRD §4)

/// The four sanctioned input schemes. There is no scheme five.
public enum Scheme: String, CaseIterable, Sendable, Codable, Hashable {
    /// A — click and nothing else.
    case clickOnly
    /// B — discrete 4-way swipes steer.
    case swipeSteer
    /// C — 4-way swipes snap between positions.
    case fourWaySnap
    /// D — hold to charge, release to act.
    case holdRelease

    public var displayName: String {
        switch self {
        case .clickOnly: return "Click"
        case .swipeSteer: return "Swipe"
        case .fourWaySnap: return "Snap"
        case .holdRelease: return "Hold & release"
        }
    }
}

/// The only verbs a game can ever see. The shell routes remote gestures into
/// these; anything outside the game's declared scheme must be dropped before
/// `tick` — and `accepts(_:)` lets both layers enforce that.
public enum SchemeInput: Sendable, Equatable, Hashable {
    case click
    case swipe(Direction4)
    case holdBegan
    case holdEnded
}

extension Scheme {
    /// Scheme scoping: does this scheme admit the given verb at all?
    public func accepts(_ input: SchemeInput) -> Bool {
        switch (self, input) {
        case (.clickOnly, .click): return true
        case (.swipeSteer, .swipe): return true
        case (.fourWaySnap, .swipe): return true
        case (.holdRelease, .holdBegan), (.holdRelease, .holdEnded): return true
        default: return false
        }
    }
}

// MARK: - Games

/// The launch lineup — one game per scheme (sanctioned reduction to four).
public enum GameID: String, CaseIterable, Sendable, Codable, Hashable {
    case flap, noodle, quadrant, putt

    public var title: String {
        switch self {
        case .flap: return "Flap"
        case .noodle: return "Noodle"
        case .quadrant: return "Quadrant"
        case .putt: return "Putt"
        }
    }

    public var scheme: Scheme {
        switch self {
        case .flap: return .clickOnly
        case .noodle: return .swipeSteer
        case .quadrant: return .fourWaySnap
        case .putt: return .holdRelease
        }
    }

    /// One-line attract hint shown on the cartridge label.
    public var hint: String {
        switch self {
        case .flap: return "Click to flap"
        case .noodle: return "Swipe to steer"
        case .quadrant: return "Swipe to snap zones"
        case .putt: return "Hold to charge, release to putt"
        }
    }
}

// MARK: - Entities (abstract render list)

/// What a game asks the UI to draw. Positions/sizes in world units; the UI
/// maps `spriteSlot` into the photo-sprite locker (slot 0 is always the
/// hero). Sprites are art, not physics — hitboxes live inside game states
/// as circles/capsules and never depend on photo content.
public struct Entity: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Codable, Hashable {
        case hero       // the player's photo-sprite actor
        case segment    // trailing body (Noodle's photo strip)
        case obstacle   // neutral solid (pipes, walls)
        case hazard     // touch = death
        case pickup     // touch = score
        case goal       // Putt's hole
        case indicator  // aim sweep / charge meter (value + rotation)
    }

    public var id: Int
    public var kind: Kind
    /// Center position, world units, +y up.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// Degrees, counterclockwise from +x.
    public var rotation: Double
    /// Index into the sprite locker; -1 = draw as a shape.
    public var spriteSlot: Int
    /// Kind-specific scalar (charge 0…1, arrival progress, …).
    public var value: Double

    public init(
        id: Int, kind: Kind, x: Double, y: Double,
        width: Double, height: Double,
        rotation: Double = 0, spriteSlot: Int = -1, value: Double = 0
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.spriteSlot = spriteSlot
        self.value = value
    }
}

// MARK: - Cartridge protocol

/// Everything a shipped state must expose to the shell.
public protocol CartridgeState: Sendable {
    var score: Int { get }
    var isGameOver: Bool { get }
    /// Seconds since round start (game time, fixed steps).
    var elapsed: Double { get }
    /// Abstract render list, back-to-front.
    var entities: [Entity] { get }
}

/// A micro-game: pure tick logic. Same (state, input, dt) sequence ⇒
/// identical states, byte for byte. This conformance is also the v2 target
/// spec for generated games — nothing here may depend on platform state.
public protocol Cartridge: Sendable {
    associatedtype State: CartridgeState & Equatable

    var id: GameID { get }
    var scheme: Scheme { get }

    /// Fresh round. Deterministic in (seed, mutator).
    func newRound(seed: UInt64, mutator: Mutator) -> State
    /// Advance one step. Inputs outside `scheme` must be ignored.
    func tick(_ state: State, input: SchemeInput?, dt: Double) -> State
    /// Attract-mode/verifier bot: a pure heuristic on the visible state.
    func bot(_ state: State) -> SchemeInput?
}

extension Cartridge {
    public func newRound(seed: UInt64) -> State {
        newRound(seed: seed, mutator: .identity)
    }
}

// MARK: - Deterministic noise stream

/// A resumable, Equatable random stream for game states. Wraps
/// `CouchHash.noise` behind a counter so states stay value types (CouchCore's
/// `SplitMix64` hides its state; carrying a counter keeps ticks pure).
public struct NoiseStream: Sendable, Equatable, Hashable {
    public let seed: UInt64
    public private(set) var counter: Int

    public init(seed: UInt64) {
        self.seed = seed
        self.counter = 0
    }

    /// Uniform in [0, 1).
    public mutating func next() -> Double {
        defer { counter += 1 }
        return CouchHash.noise(counter, 0x5EED, seed: seed)
    }

    public mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + next() * (range.upperBound - range.lowerBound)
    }

    /// Uniform integer in 0..<bound (bound must be > 0).
    public mutating func nextInt(below bound: Int) -> Int {
        precondition(bound > 0, "bound must be positive")
        return min(bound - 1, Int(next() * Double(bound)))
    }
}

// MARK: - Hit math (circles & capsules only — PRD §5.3)

public enum Hit {
    public static func circleOverlapsCircle(
        _ x1: Double, _ y1: Double, _ r1: Double,
        _ x2: Double, _ y2: Double, _ r2: Double
    ) -> Bool {
        let dx = x2 - x1, dy = y2 - y1
        let rr = r1 + r2
        return dx * dx + dy * dy <= rr * rr
    }

    /// Distance from point (px,py) to segment (ax,ay)-(bx,by).
    public static func distance(
        px: Double, py: Double,
        ax: Double, ay: Double, bx: Double, by: Double
    ) -> Double {
        let abx = bx - ax, aby = by - ay
        let lengthSquared = abx * abx + aby * aby
        if lengthSquared == 0 {
            let dx = px - ax, dy = py - ay
            return (dx * dx + dy * dy).squareRoot()
        }
        let t = max(0, min(1, ((px - ax) * abx + (py - ay) * aby) / lengthSquared))
        let cx = ax + t * abx, cy = ay + t * aby
        let dx = px - cx, dy = py - cy
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Circle vs capsule (segment + radius).
    public static func circleOverlapsCapsule(
        cx: Double, cy: Double, r: Double,
        ax: Double, ay: Double, bx: Double, by: Double,
        capsuleRadius: Double
    ) -> Bool {
        distance(px: cx, py: cy, ax: ax, ay: ay, bx: bx, by: by) <= r + capsuleRadius
    }

    /// Circle vs axis-aligned rect — used for Flap's pipe halves.
    public static func circleOverlapsRect(
        cx: Double, cy: Double, r: Double,
        minX: Double, minY: Double, maxX: Double, maxY: Double
    ) -> Bool {
        let nx = max(minX, min(cx, maxX))
        let ny = max(minY, min(cy, maxY))
        let dx = cx - nx, dy = cy - ny
        return dx * dx + dy * dy <= r * r
    }
}

// MARK: - Angles

public enum Angle {
    /// Wrap to [0, 360).
    public static func normalized(_ degrees: Double) -> Double {
        var a = degrees.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        return a
    }

    /// Smallest absolute difference between two angles, in [0, 180].
    public static func difference(_ a: Double, _ b: Double) -> Double {
        let d = abs(normalized(a) - normalized(b))
        return min(d, 360 - d)
    }
}
