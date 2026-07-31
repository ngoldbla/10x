// DuelTests.swift — turns are contiguous ranges of the move log, and this is
// what that buys (PRD-27 §2).
import XCTest
@testable import NineShared
#if canImport(NineEngine)
import NineEngine
#endif

final class DuelTests: XCTestCase {

    private func state(_ turns: [(Int, Int, TimeInterval)]) -> DuelState {
        var s = DuelState(accents: ["glacier", "ember"], turnLength: .standard)
        for (player, index, at) in turns {
            s.beginTurn(player: player, firstMoveIndex: index, startedAt: at)
        }
        return s
    }

    // MARK: - Attribution

    func testAMoveIsOwnedByTheTurnItLandedIn() {
        let s = state([(0, 0, 0), (1, 4, 90), (0, 9, 180)])
        XCTAssertEqual(s.player(forMoveIndex: 0), 0)
        XCTAssertEqual(s.player(forMoveIndex: 3), 0)
        XCTAssertEqual(s.player(forMoveIndex: 4), 1)
        XCTAssertEqual(s.player(forMoveIndex: 8), 1)
        XCTAssertEqual(s.player(forMoveIndex: 9), 0)
        XCTAssertEqual(s.player(forMoveIndex: 900), 0, "the last turn is open-ended")
    }

    /// A time slice makes this the common case: a player who placed nothing
    /// still took a turn. A count-based turn could never produce one, which is
    /// why this case exists at all.
    func testAnEmptyTurnOwnsNoMovesAndBreaksNothing() {
        let s = state([(0, 0, 0), (1, 2, 90), (0, 2, 180)])
        XCTAssertEqual(s.player(forMoveIndex: 1), 0)
        XCTAssertEqual(s.player(forMoveIndex: 2), 0, "the later turn wins a shared boundary")
        XCTAssertEqual(s.turns.count, 3)
    }

    func testAMoveBeforeAnyTurnHasNoOwner() {
        XCTAssertNil(DuelState(accents: ["glacier", "ember"], turnLength: .brisk).player(forMoveIndex: 0))
    }

    // MARK: - The deadline

    func testRemainingCountsDownAgainstTheBoardClock() {
        let s = state([(0, 0, 10)])
        XCTAssertEqual(try XCTUnwrap(s.remaining(atElapsed: 10)), 90, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.remaining(atElapsed: 55)), 45, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.remaining(atElapsed: 100)), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.remaining(atElapsed: 5000)), 0, accuracy: 0.001,
                       "never negative — a chip does not show -04:12")
    }

    func testRemainingIsNilBeforeTheFirstTurnBegins() {
        XCTAssertNil(DuelState(accents: ["glacier", "ember"], turnLength: .brisk).remaining(atElapsed: 0))
    }

    func testTurnLengthsAreTheThreeTheSpecNames() {
        XCTAssertEqual(DuelTurnLength.brisk.rawValue, 60)
        XCTAssertEqual(DuelTurnLength.standard.rawValue, 90)
        XCTAssertEqual(DuelTurnLength.unhurried.rawValue, 180)
        XCTAssertEqual(DuelTurnLength.allCases.count, 3)
    }

    func testCurrentPlayerIsTheLastTurnsAndZeroBeforeAnyTurn() {
        XCTAssertEqual(DuelState(accents: ["glacier", "ember"], turnLength: .brisk).currentPlayer, 0)
        XCTAssertEqual(state([(0, 0, 0), (1, 3, 90)]).currentPlayer, 1)
    }

    // MARK: - Two seats, always

    func testTheSecondSeatIsDerivedFromTheFirst() {
        let s = DuelState(accent: "glacier", isLight: false, turnLength: .standard)
        XCTAssertEqual(s.accents[0], "glacier")
        XCTAssertEqual(s.accents[1], DuelTint.partner(for: "glacier", isLight: false))
        XCTAssertNotEqual(s.accents[0], s.accents[1])
    }

    func testAccentForAnOutOfRangePlayerFallsBackRatherThanTrapping() {
        let s = DuelState(accents: ["glacier", "ember"], turnLength: .brisk)
        XCTAssertEqual(s.accent(forPlayer: 7), "glacier")
        XCTAssertEqual(s.accent(forPlayer: -1), "glacier")
    }

    // MARK: - Tolerant decode: nothing throws out of a container

    func testAStateWithGarbageTurnLengthDecodesToTheDefaultRatherThanThrowing() throws {
        let json = #"{"accents":["glacier","ember"],"turnLength":9999,"turns":[]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DuelState.self, from: json)
        XCTAssertEqual(decoded.turnLength, .standard)
    }

    /// The distinction that matters: a key of the wrong *type*, not an absent
    /// one. `try … ?? default` survives absence and throws on this.
    func testATurnLengthOfTheWrongTypeDecodesRatherThanThrowing() throws {
        let json = #"{"accents":["glacier","ember"],"turnLength":"ninety","turns":[]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DuelState.self, from: json)
        XCTAssertEqual(decoded.turnLength, .standard)
    }

    func testAStateMissingItsTurnsDecodesEmptyRatherThanThrowing() throws {
        let json = #"{"accents":["glacier","ember"],"turnLength":60}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DuelState.self, from: json)
        XCTAssertEqual(decoded.turns, [])
        XCTAssertEqual(decoded.turnLength, .brisk)
    }

    func testAStateWithTheWrongNumberOfAccentsStillHasTwoSeats() throws {
        let short = #"{"accents":["glacier"],"turnLength":90,"turns":[]}"#.data(using: .utf8)!
        let one = try JSONDecoder().decode(DuelState.self, from: short)
        XCTAssertEqual(one.accents.count, 2, "a duel is always two seats")
        XCTAssertEqual(one.accents[0], "glacier")

        let long = #"{"accents":["glacier","ember","moss"],"turnLength":90,"turns":[]}"#.data(using: .utf8)!
        let three = try JSONDecoder().decode(DuelState.self, from: long)
        XCTAssertEqual(three.accents, ["glacier", "ember"], "a third seat is dropped, not honoured")
    }

    func testRoundTrip() throws {
        let s = state([(0, 0, 0), (1, 4, 90)])
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(DuelState.self, from: data), s)
    }

    // MARK: - The ledger

    func testTheLedgerStoresAndPrunesAgainstTheLiveLibrary() {
        let live = UUID(), dead = UUID()
        var ledger = DuelLedger()
        ledger.set(state([(0, 0, 0)]), for: live)
        ledger.set(state([(1, 0, 0)]), for: dead)
        XCTAssertNotNil(ledger[live])
        ledger.prune(to: [live])
        XCTAssertNotNil(ledger[live])
        XCTAssertNil(ledger[dead], "a duel outliving its board is unreachable")
    }

    /// `ReplayVault`'s rule, for its reason: an empty library is far more often
    /// one that has not loaded than one the player emptied.
    func testPruneRefusesAnEmptyLiveSetAndRemoveIsTheOtherDoor() {
        let id = UUID()
        var ledger = DuelLedger()
        ledger.set(state([(0, 0, 0)]), for: id)
        ledger.prune(to: [])
        XCTAssertNotNil(ledger[id], "an empty live set is a library that has not loaded yet")
        ledger.remove(id)
        XCTAssertNil(ledger[id])
    }

    func testTheLedgerIsCapacityBoundedLikeTheReplayVault() {
        var ledger = DuelLedger()
        var ids: [UUID] = []
        for _ in 0..<(DuelLedger.capacity + 10) {
            let id = UUID(); ids.append(id)
            ledger.set(state([(0, 0, 0)]), for: id)
        }
        XCTAssertEqual(ledger.count, DuelLedger.capacity)
        XCTAssertNil(ledger[ids[0]], "oldest evicted first")
        XCTAssertNotNil(ledger[ids.last!])
    }

    func testUpdatingAnExistingBoardDoesNotReorderOrGrowTheLedger() {
        let id = UUID()
        var ledger = DuelLedger()
        ledger.set(state([(0, 0, 0)]), for: id)
        ledger.set(state([(0, 0, 0), (1, 5, 90)]), for: id)
        XCTAssertEqual(ledger.count, 1)
        XCTAssertEqual(ledger[id]?.turns.count, 2)
    }

    func testALedgerWithOneUnreadableKeyKeepsTheOthers() throws {
        let good = UUID()
        let json = """
        {"states":{"\(good.uuidString)":{"accents":["glacier","ember"],"turnLength":90,"turns":[]},\
        "not-a-uuid":{"accents":["glacier","ember"],"turnLength":90,"turns":[]}},\
        "order":["\(good.uuidString)"]}
        """.data(using: .utf8)!
        let ledger = try JSONDecoder().decode(DuelLedger.self, from: json)
        XCTAssertNotNil(ledger[good])
        XCTAssertEqual(ledger.count, 1)
    }

    func testALedgerWhoseOrderIsMissingStillTrimsDeterministically() throws {
        let ids = (0..<3).map { _ in UUID() }
        let entries = ids.map {
            "\"\($0.uuidString)\":{\"accents\":[\"glacier\",\"ember\"],\"turnLength\":90,\"turns\":[]}"
        }.joined(separator: ",")
        let json = "{\"states\":{\(entries)}}".data(using: .utf8)!
        let ledger = try JSONDecoder().decode(DuelLedger.self, from: json)
        XCTAssertEqual(ledger.count, 3, "an absent order list is repaired, not fatal")
    }

    func testLedgerRoundTrip() throws {
        let id = UUID()
        var ledger = DuelLedger()
        ledger.set(state([(0, 0, 0), (1, 3, 90)]), for: id)
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(DuelLedger.self, from: data), ledger)
    }
}
