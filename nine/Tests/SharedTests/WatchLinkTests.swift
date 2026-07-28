import Foundation
import Testing
@testable import NineShared
import NineEngine

/// The watch link, tested where it is cheapest to test: the whole adoption
/// rule and the whole wire are pure functions in `Sources/Shared`, so none of
/// this needs a simulator, a paired device, or WatchConnectivity itself.
@Suite("WatchLink")
struct WatchLinkTests {

    private func handoff(day: Int, revision: Int) -> WatchDailyHandoff {
        WatchDailyHandoff(
            dayOrdinal: day,
            puzzle: PuzzleGenerator.generate(
                seed: DailySeed.seed(forDayOrdinal: day), difficulty: .steady
            ),
            revision: revision,
            updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    // MARK: - The wire

    @Test func theWireSurvivesARoundTrip() throws {
        let sent = handoff(day: 9_400, revision: 3)
        let got = try #require(WatchLinkWire.decodeHandoff(WatchLinkWire.encode(sent)))
        #expect(got == sent)
    }

    @Test func aSolveReportSurvivesARoundTrip() throws {
        let report = WatchSolveReport(
            dayOrdinal: 9_400,
            solve: PendingSolve(solvedAt: Date(timeIntervalSinceReferenceDate: 10), seconds: 212)
        )
        let got = try #require(WatchLinkWire.decodeReport(WatchLinkWire.encode(report)))
        #expect(got == report)
    }

    /// WCSession throws — it does not warn — when handed a dictionary holding
    /// anything but property-list types. One `Data` under one key is the whole
    /// contract, and this is the only place it can be checked without a device.
    @Test func theWireIsPlistSafe() {
        let payloads = [
            WatchLinkWire.encode(handoff(day: 9_400, revision: 1)),
            WatchLinkWire.encode(WatchSolveReport(
                dayOrdinal: 9_400,
                solve: PendingSolve(solvedAt: Date(), seconds: 1)
            ))
        ]
        for payload in payloads {
            #expect(payload.count == 1)
            #expect(payload.values.allSatisfy { $0 is Data })
        }
    }

    /// The whole daily fits in one application context with room to spare.
    /// `updateApplicationContext` rejects oversized payloads at runtime on a
    /// real watch and nowhere else, so the budget is asserted here.
    @Test func todaysDailyIsSmallEnoughToBeAnApplicationContext() {
        let bytes = (WatchLinkWire.encode(handoff(day: 9_400, revision: 1))
            .values.first as? Data)?.count ?? .max
        #expect(bytes < 32_768)
    }

    @Test func garbageDecodesToNilRatherThanThrowing() {
        #expect(WatchLinkWire.decodeHandoff([WatchLinkWire.handoffKey: Data([0x00, 0x01])]) == nil)
        #expect(WatchLinkWire.decodeHandoff([:]) == nil)
        #expect(WatchLinkWire.decodeHandoff([WatchLinkWire.handoffKey: 7]) == nil)
        #expect(WatchLinkWire.decodeReport([WatchLinkWire.reportKey: Data("{}".utf8)]) == nil)
        #expect(WatchLinkWire.decodeReport([:]) == nil)
    }

    /// A payload from a build that knows more than this one is refused whole
    /// rather than half-read — `WidgetSnapshot`'s doctrine, for the same
    /// reason: a partially understood board is worse than no board.
    @Test func aNewerSchemaIsRefusedRatherThanMisread() {
        var future = handoff(day: 9_400, revision: 1)
        future.schemaVersion = WatchDailyHandoff.currentSchemaVersion + 1
        #expect(WatchLinkWire.decodeHandoff(WatchLinkWire.encode(future)) == nil)
    }

    /// A handoff and a report never share a key, so a delegate callback that
    /// receives one can never decode it as the other.
    @Test func theTwoDirectionsDoNotShareAKey() {
        #expect(WatchLinkWire.handoffKey != WatchLinkWire.reportKey)
        #expect(WatchLinkWire.decodeReport(WatchLinkWire.encode(handoff(day: 1, revision: 1))) == nil)
    }

    // MARK: - The adoption rule

    @Test func onlyAStrictlyHigherRevisionForTodayIsAdopted() {
        let h = handoff(day: 9_400, revision: 5)
        #expect(h.supersedes(known: 4, today: 9_400))
        #expect(!h.supersedes(known: 5, today: 9_400))   // equal is not newer
        #expect(!h.supersedes(known: 6, today: 9_400))
        #expect(!h.supersedes(known: 0, today: 9_401))   // yesterday's, never
        #expect(!h.supersedes(known: 0, today: 9_399))   // tomorrow's, never
    }

    @Test func theDayGuardIsTheSameShapeAsTheWidgetsBoard() {
        let h = handoff(day: 9_400, revision: 1)
        #expect(h.isCurrent(today: 9_400))
        #expect(!h.isCurrent(today: 9_401))
    }

    // MARK: - The compose ceiling

    @Test func theWatchMayComposeGentleAndNothingHarder() {
        #expect(WatchComposePolicy.ceiling == .gentle)
        #expect(WatchComposePolicy.mayComposeLocally(.gentle))
        for band in [Difficulty.steady, .sharp, .nocturne] {
            #expect(!WatchComposePolicy.mayComposeLocally(band))
        }
    }

    /// The rule is only worth having if the daily is on the wrong side of it.
    /// If the daily ever composes at gentle, the link stops being load-bearing
    /// and this test is where that shows up.
    @Test func theDailyIsAboveTheCeilingSoTheLinkIsLoadBearing() {
        #expect(!WatchComposePolicy.mayComposeLocally(WatchComposePolicy.dailyBand))
    }

    // MARK: - The courier is not an authority

    /// The link delivers the daily; it does not define it. Every device must
    /// still be able to derive the identical board from the day alone
    /// (PRD-6 §6 item 6), so a corrupted or malicious context cannot make one
    /// device play a different puzzle from the rest.
    @Test func theHandedOffPuzzleIsTheOneTheDayDefines() {
        let day = 9_400
        let sent = handoff(day: day, revision: 1)
        let localTruth = PuzzleGenerator.generate(
            seed: DailySeed.seed(forDayOrdinal: day), difficulty: WatchComposePolicy.dailyBand
        )
        #expect(sent.puzzle == localTruth)
        #expect(sent.matchesTheDayItClaims)
    }

    @Test func aHandoffCarryingSomeoneElsesBoardIsRejected() {
        var forged = handoff(day: 9_400, revision: 1)
        forged.puzzle = PuzzleGenerator.generate(
            seed: DailySeed.seed(forDayOrdinal: 9_401), difficulty: .steady
        )
        #expect(!forged.matchesTheDayItClaims)
    }

    /// The seed and band can both be right and the grids still garbage — a
    /// truncated transfer, a partially written context. The givens must agree
    /// with the solution they claim to come from.
    @Test func aHandoffWhoseGivensContradictItsSolutionIsRejected() throws {
        // Garbled on the wire rather than in Swift: `GeneratedPuzzle` has no
        // public memberwise init (every field is `let`), and corrupting the
        // JSON is the more faithful simulation of a truncated transfer anyway.
        let sound = handoff(day: 9_400, revision: 1)
        let data = try #require(WatchLinkWire.encode(sound)[WatchLinkWire.handoffKey] as? Data)
        var json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var puzzle = try #require(json["puzzle"] as? [String: Any])
        var grid = try #require(puzzle["puzzle"] as? [String: Any])
        var cells = try #require(grid["cells"] as? [Int])
        let firstGiven = try #require(cells.firstIndex { $0 != 0 })
        cells[firstGiven] = cells[firstGiven] % 9 + 1     // any other digit
        grid["cells"] = cells
        puzzle["puzzle"] = grid
        json["puzzle"] = puzzle

        let garbled = try #require(WatchLinkWire.decodeHandoff([
            WatchLinkWire.handoffKey: try JSONSerialization.data(withJSONObject: json)
        ]))
        #expect(sound.matchesTheDayItClaims)
        #expect(!garbled.matchesTheDayItClaims)
    }

    @Test func aHandoffAtTheWrongDifficultyIsRejected() {
        var wrongBand = handoff(day: 9_400, revision: 1)
        wrongBand.puzzle = PuzzleGenerator.generate(
            seed: DailySeed.seed(forDayOrdinal: 9_400), difficulty: .sharp
        )
        #expect(!wrongBand.matchesTheDayItClaims)
    }
}
