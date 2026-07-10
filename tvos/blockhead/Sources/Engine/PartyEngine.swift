// Party engine: 2–6 players, pass-the-remote turn rotation, per-player
// scores, podium ranking with ties, one-click rematch. Pure Swift.
import Foundation
import CouchCore

/// A claimed couch identity: avatar tile + color, never a name.
public struct PartyPlayer: Sendable, Equatable, Hashable, Identifiable, Codable {
    /// Token slot (0…5) the player claimed during setup.
    public let id: Int
    /// Index into the app's avatar symbol set.
    public var symbolIndex: Int
    /// Index into the app's player color set.
    public var colorIndex: Int

    public init(id: Int, symbolIndex: Int, colorIndex: Int) {
        self.id = id
        self.symbolIndex = symbolIndex
        self.colorIndex = colorIndex
    }
}

/// Final-tally position. Standard competition ranking: tied scores share a
/// rank and the next rank is skipped (1, 1, 3, …).
public struct PodiumPlace: Sendable, Equatable {
    public let rank: Int
    public let playerIndex: Int
    public let score: Int

    public init(rank: Int, playerIndex: Int, score: Int) {
        self.rank = rank
        self.playerIndex = playerIndex
        self.score = score
    }
}

/// One party match. Turn `t` belongs to player `t % players.count`; a round
/// is one question for everyone, and round difficulty ramps 1 → 2 → 3.
public struct PartyMatch: Sendable, Equatable {
    public static let playerRange = 2...6
    public static let defaultRounds = 3

    public let seed: UInt64
    public let rounds: Int
    public let players: [PartyPlayer]
    public let questions: [Question]
    public private(set) var scores: [Int]
    public private(set) var turn: Int = 0

    public init?(
        players: [PartyPlayer],
        rounds: Int = PartyMatch.defaultRounds,
        seed: UInt64,
        pack: [Question] = QuestionPack.all
    ) {
        guard Self.playerRange.contains(players.count) else { return nil }
        self.players = players
        self.rounds = max(1, rounds)
        self.seed = seed
        self.questions = EpisodePlanner.partyQuestions(
            players: players.count,
            rounds: max(1, rounds),
            seed: seed,
            from: pack
        )
        self.scores = Array(repeating: 0, count: players.count)
    }

    public var isFinished: Bool { turn >= questions.count }

    public var currentPlayerIndex: Int? {
        isFinished ? nil : turn % players.count
    }

    public var currentPlayer: PartyPlayer? {
        currentPlayerIndex.map { players[$0] }
    }

    public var currentQuestion: Question? {
        isFinished ? nil : questions[turn]
    }

    /// 1-based round for the current turn (clamps to the last round when done).
    public var currentRound: Int {
        isFinished ? rounds : turn / players.count + 1
    }

    /// Meter ceiling: every question can pay 1 point + 2 dots.
    public var maxScorePerPlayer: Int { rounds * (1 + Scoring.maxDots) }

    /// Score the current turn and rotate to the next player.
    public mutating func record(correct: Bool, dots: Int) {
        guard let player = currentPlayerIndex else { return }
        let earnedDots = correct ? max(0, min(Scoring.maxDots, dots)) : 0
        scores[player] += (correct ? 1 : 0) + earnedDots
        turn += 1
    }

    /// Final tally, best first. Ties share a rank.
    public func podium() -> [PodiumPlace] {
        let order = scores.indices.sorted {
            scores[$0] == scores[$1] ? $0 < $1 : scores[$0] > scores[$1]
        }
        var places: [PodiumPlace] = []
        for (position, playerIndex) in order.enumerated() {
            let score = scores[playerIndex]
            let rank = (places.last?.score == score) ? places.last!.rank : position + 1
            places.append(PodiumPlace(rank: rank, playerIndex: playerIndex, score: score))
        }
        return places
    }

    /// One-click rematch: same couch, fresh deterministic reseed.
    public func rematch(pack: [Question] = QuestionPack.all) -> PartyMatch {
        var rng = SplitMix64(seed: seed &+ 0x9E37_79B9_7F4A_7C15)
        // Force-unwrap is safe: players already passed the range check.
        return PartyMatch(players: players, rounds: rounds, seed: rng.next(), pack: pack)!
    }
}
