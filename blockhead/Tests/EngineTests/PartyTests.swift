// Party engine: rotation, scoring, podium (with ties), rematch reseed.
import XCTest
@testable import BlockheadEngine

final class PartyTests: XCTestCase {

    private func makePlayers(_ count: Int) -> [PartyPlayer] {
        (0..<count).map { PartyPlayer(id: $0, symbolIndex: $0, colorIndex: $0) }
    }

    func testPlayerCountIsClampedToTwoThroughSix() {
        XCTAssertNil(PartyMatch(players: makePlayers(1), seed: 1))
        XCTAssertNil(PartyMatch(players: makePlayers(7), seed: 1))
        XCTAssertNotNil(PartyMatch(players: makePlayers(2), seed: 1))
        XCTAssertNotNil(PartyMatch(players: makePlayers(6), seed: 1))
    }

    func testMatchDrawsRoundsTimesPlayersUniqueQuestions() {
        let match = PartyMatch(players: makePlayers(4), rounds: 3, seed: 99)!
        XCTAssertEqual(match.questions.count, 12)
        XCTAssertEqual(Set(match.questions.map(\.id)).count, 12)
    }

    func testRoundDifficultyRampsOneTwoThree() {
        let players = 4
        let match = PartyMatch(players: makePlayers(players), rounds: 3, seed: 7)!
        for (index, question) in match.questions.enumerated() {
            XCTAssertEqual(question.difficulty, min(index / players + 1, 3), "turn \(index)")
        }
    }

    func testTurnRotationCyclesThroughPlayers() {
        var match = PartyMatch(players: makePlayers(3), rounds: 2, seed: 5)!
        var seen: [Int] = []
        while !match.isFinished {
            seen.append(match.currentPlayerIndex!)
            match.record(correct: false, dots: 0)
        }
        XCTAssertEqual(seen, [0, 1, 2, 0, 1, 2])
        XCTAssertNil(match.currentPlayerIndex)
        XCTAssertNil(match.currentQuestion)
    }

    func testScoresAccumulateForTheRightPlayer() {
        var match = PartyMatch(players: makePlayers(2), rounds: 2, seed: 5)!
        match.record(correct: true, dots: 2)   // player 0: 3
        match.record(correct: false, dots: 2)  // player 1: 0 (dots need correct)
        match.record(correct: true, dots: 0)   // player 0: +1 = 4
        match.record(correct: true, dots: 1)   // player 1: 2
        XCTAssertEqual(match.scores, [4, 2])
        XCTAssertTrue(match.isFinished)
        XCTAssertEqual(match.maxScorePerPlayer, 6)
    }

    func testCurrentRoundAdvancesWithFullRotations() {
        var match = PartyMatch(players: makePlayers(2), rounds: 3, seed: 5)!
        XCTAssertEqual(match.currentRound, 1)
        match.record(correct: false, dots: 0)
        match.record(correct: false, dots: 0)
        XCTAssertEqual(match.currentRound, 2)
    }

    func testPodiumRanksBestFirstAndSharesTiedRanks() {
        var match = PartyMatch(players: makePlayers(3), rounds: 1, seed: 5)!
        match.record(correct: true, dots: 0)   // player 0: 1
        match.record(correct: true, dots: 0)   // player 1: 1
        match.record(correct: false, dots: 0)  // player 2: 0
        let podium = match.podium()
        XCTAssertEqual(podium.map(\.rank), [1, 1, 3], "ties share rank; next rank skips")
        XCTAssertEqual(podium.map(\.playerIndex), [0, 1, 2])
        XCTAssertEqual(podium.map(\.score), [1, 1, 0])
    }

    func testPodiumOrdersByScore() {
        var match = PartyMatch(players: makePlayers(3), rounds: 1, seed: 5)!
        match.record(correct: false, dots: 0)  // player 0: 0
        match.record(correct: true, dots: 2)   // player 1: 3
        match.record(correct: true, dots: 0)   // player 2: 1
        let podium = match.podium()
        XCTAssertEqual(podium.map(\.playerIndex), [1, 2, 0])
        XCTAssertEqual(podium.map(\.rank), [1, 2, 3])
    }

    func testRematchReseedsDeterministicallyAndResetsState() {
        var match = PartyMatch(players: makePlayers(4), rounds: 3, seed: 1234)!
        while !match.isFinished { match.record(correct: true, dots: 1) }

        let rematch = match.rematch()
        XCTAssertNotEqual(rematch.seed, match.seed)
        XCTAssertNotEqual(rematch.questions.map(\.id), match.questions.map(\.id))
        XCTAssertEqual(rematch.players, match.players, "same couch")
        XCTAssertEqual(rematch.scores, [0, 0, 0, 0])
        XCTAssertFalse(rematch.isFinished)

        // Rematch of the same match is itself deterministic.
        XCTAssertEqual(match.rematch().seed, rematch.seed)
    }

    func testSameSeedSameMatch() {
        let a = PartyMatch(players: makePlayers(3), rounds: 3, seed: 777)!
        let b = PartyMatch(players: makePlayers(3), rounds: 3, seed: 777)!
        XCTAssertEqual(a.questions.map(\.id), b.questions.map(\.id))
    }
}
