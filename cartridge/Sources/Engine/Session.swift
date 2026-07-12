// Session — a type-erased running round. The shell holds these so the feed
// can mix all four games behind one interface; tests use the concrete games.
import Foundation
import CouchCore

public struct Session: Sendable {
    public let game: GameID
    public let scheme: Scheme
    public let mutator: Mutator
    public private(set) var state: any CartridgeState
    public private(set) var ticks: Int

    private let tickFn: @Sendable (any CartridgeState, SchemeInput?, Double) -> any CartridgeState
    private let botFn: @Sendable (any CartridgeState) -> SchemeInput?
    private let newRoundFn: @Sendable (UInt64) -> any CartridgeState

    public init<C: Cartridge>(_ cartridge: C, seed: UInt64, mutator: Mutator = .identity) {
        self.game = cartridge.id
        self.scheme = cartridge.scheme
        self.mutator = mutator
        self.state = cartridge.newRound(seed: seed, mutator: mutator)
        self.ticks = 0
        self.tickFn = { state, input, dt in
            cartridge.tick(state as! C.State, input: input, dt: dt)
        }
        self.botFn = { state in
            cartridge.bot(state as! C.State)
        }
        self.newRoundFn = { seed in
            cartridge.newRound(seed: seed, mutator: mutator)
        }
    }

    public var score: Int { state.score }
    public var isGameOver: Bool { state.isGameOver }
    public var elapsed: Double { state.elapsed }
    public var entities: [Entity] { state.entities }

    /// Advance one fixed step. Inputs outside the game's scheme are dropped
    /// here as well — the scheme gate is enforced twice on purpose.
    public mutating func tick(input: SchemeInput? = nil, dt: Double = CartridgeClock.dt) {
        let gated = input.flatMap { scheme.accepts($0) ? $0 : nil }
        state = tickFn(state, gated, dt)
        ticks += 1
    }

    /// Advance one step under bot control (attract mode / verifier).
    public mutating func tickWithBot(dt: Double = CartridgeClock.dt) {
        let input = botFn(state)
        state = tickFn(state, input, dt)
        ticks += 1
    }

    /// Fresh round, same game + mutator (verdict-card retry, attract morph).
    public mutating func reset(seed: UInt64) {
        state = newRoundFn(seed)
        ticks = 0
    }
}

/// The launch catalog: one factory per shipped game.
public enum CartridgeCatalog {
    public static let lineup: [GameID] = GameID.allCases

    public static func session(
        for id: GameID, seed: UInt64, mutator: Mutator = .identity
    ) -> Session {
        switch id {
        case .flap: return Session(FlapGame(), seed: seed, mutator: mutator)
        case .noodle: return Session(NoodleGame(), seed: seed, mutator: mutator)
        case .quadrant: return Session(QuadrantGame(), seed: seed, mutator: mutator)
        case .putt: return Session(PuttGame(), seed: seed, mutator: mutator)
        }
    }

    /// A session preloaded with today's daily-challenge mutator.
    public static func dailySession(for id: GameID, on day: DayStamp, seed: UInt64) -> Session {
        session(for: id, seed: seed, mutator: DailyChallenge.mutator(for: id, on: day))
    }
}
