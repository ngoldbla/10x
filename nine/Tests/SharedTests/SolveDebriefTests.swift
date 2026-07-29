import Testing
import Foundation
import NineEngine
@testable import NineShared

/// PRD-26 §2.2/§2.3 — what the debrief says, and what it refuses to say.
@Suite("SolveDebrief") struct SolveDebriefTests {

    private static let board = PuzzleGenerator.generate(seed: 26_260_728, difficulty: .steady)

    private func replay(_ moves: [LoggedMove]) -> SolveReplay {
        SolveReplay(
            boardID: UUID(), solvedAt: Date(timeIntervalSince1970: 0), band: "steady",
            isDaily: false, seconds: 300,
            packed: SolveReplay.pack(puzzle: Self.board.puzzle.cells, moves: moves)
        )
    }

    private func debrief(_ moves: [LoggedMove], analysis: ReplayAnalysis = ReplayAnalysis(placements: [])) -> SolveDebrief {
        SolveDebrief(replay: replay(moves), analysis: analysis)
    }

    // MARK: - The counts, which are true for every log

    @Test func theCountsCountWhatTheyAreNamedFor() {
        let result = debrief([
            LoggedMove(kind: .place, cell: 1, digit: 1, at: 1),
            LoggedMove(kind: .place, cell: 2, digit: 2, at: 2),
            LoggedMove(kind: .erase, cell: 2, digit: 2, at: 3),
            LoggedMove(kind: .undo, cell: 2, digit: 2, at: 4),
            LoggedMove(kind: .pencil, cell: 3, digit: 5, at: 5)
        ])
        #expect(result.placements == 2)
        #expect(result.corrections == 2)
        #expect(result.notes == 1)
        // No analysis was supplied, so there is nothing to be wrong about —
        // this is the "the bug was that wrongness had no number" case, not
        // "there were no wrong digits to report".
        #expect(result.errors == 0)
    }

    /// PRD-20's plural lesson: English's `one` and `other` differ here, so a
    /// single placement must not read "1 digits placed".
    @Test func theCountsInflect() {
        let one = debrief([LoggedMove(kind: .place, cell: 1, digit: 1, at: 1)])
        #expect(one.countsLine.contains("1 digit placed"))
        #expect(!one.countsLine.contains("1 digits"))

        let two = debrief([
            LoggedMove(kind: .place, cell: 1, digit: 1, at: 1),
            LoggedMove(kind: .place, cell: 2, digit: 2, at: 2)
        ])
        #expect(two.countsLine.contains("2 digits placed"))
    }

    // MARK: - The wrongness count (Task 3): a number where there used to be none

    /// `errors` reads `ReplayAnalysis`'s `.slip` classification rather than
    /// recomputing anything from `moves` — a wrong digit is a fact about the
    /// solved grid, which only the analysis has. Two slips among otherwise
    /// clean placements is 2, not the move count or the correction count.
    @Test func errorsCountsSlipsFromTheAnalysisNotFromMoves() {
        let moves = [
            LoggedMove(kind: .place, cell: 0, digit: 1, at: 1),
            LoggedMove(kind: .place, cell: 1, digit: 2, at: 2),
            LoggedMove(kind: .place, cell: 2, digit: 3, at: 3)
        ]
        let analysis = ReplayAnalysis(placements: [
            ClassifiedPlacement(moveIndex: 0, cell: 0, digit: 1, kind: .forced, technique: nil),
            ClassifiedPlacement(moveIndex: 1, cell: 1, digit: 2, kind: .slip, technique: nil),
            ClassifiedPlacement(moveIndex: 2, cell: 2, digit: 3, kind: .slip, technique: nil)
        ])
        let result = debrief(moves, analysis: analysis)
        #expect(result.errors == 2)
        #expect(result.countsLine.contains("2 errors"))
    }

    /// PRD-20's plural lesson again, for the new count: one slip reads
    /// "1 error", not "1 errors".
    @Test func theErrorsCountInflects() {
        let moves = [LoggedMove(kind: .place, cell: 0, digit: 1, at: 1)]
        let analysis = ReplayAnalysis(placements: [
            ClassifiedPlacement(moveIndex: 0, cell: 0, digit: 1, kind: .slip, technique: nil)
        ])
        let result = debrief(moves, analysis: analysis)
        #expect(result.errors == 1)
        #expect(result.countsLine.contains("1 error"))
        #expect(!result.countsLine.contains("1 errors"))
    }

    /// The honesty rule `StatsDrawer`'s hints tile already set: a solve with
    /// no slips gets no errors segment on the card at all — not a "0 errors"
    /// that reads as a reproach. `placements`/`corrections`/`notes` still
    /// print, unconditionally, either side of the gap it leaves.
    @Test func errorsIsOmittedFromTheCountsLineAtZero() {
        let result = debrief([LoggedMove(kind: .place, cell: 0, digit: 1, at: 1)])
        #expect(result.errors == 0)
        #expect(!result.countsLine.contains("error"))
        #expect(result.countsLine.contains("digit placed"))
        #expect(result.countsLine.contains("correction"))
        #expect(result.countsLine.contains("note"))
    }

    // MARK: - The honesty rule

    /// **The rule this type exists for.** An untimed log is replayable and its
    /// counts are true; its timing facts are not computable, so they are absent
    /// rather than invented.
    @Test func anUntimedLogPrintsNoTimingFacts() {
        let moves = (0..<12).map { LoggedMove(kind: .place, cell: $0, digit: $0 % 9 + 1) }
        let result = debrief(moves)
        #expect(!result.isTimed)
        #expect(result.fastestRegion == nil)
        #expect(result.longestCircled == nil)
        #expect(result.placements == 12, "the counts survive — only the clock is missing")
    }

    /// And it does not apologise: nothing in the card explains the absence.
    @Test func anUntimedLogSaysNothingAboutBeingUntimed() {
        let moves = (0..<12).map { LoggedMove(kind: .place, cell: $0, digit: $0 % 9 + 1) }
        #expect(debrief(moves).lines.isEmpty)
    }

    @Test func aTimedLogPrintsThem() {
        // Box 0 is cells 0,1,2 / 9,10,11 / 18,19,20 — three fast placements
        // there, three slow ones in box 8.
        var moves: [LoggedMove] = []
        var clock = 0.0
        for cell in [0, 1, 2] { clock += 1; moves.append(LoggedMove(kind: .place, cell: cell, digit: 1, at: clock)) }
        for cell in [60, 61, 62] { clock += 90; moves.append(LoggedMove(kind: .place, cell: cell, digit: 2, at: clock)) }

        let result = debrief(moves)
        #expect(result.isTimed)
        #expect(result.fastestRegion?.contains("Box 1") == true, "got \(result.fastestRegion ?? "nil")")
    }

    /// A box with one lucky digit cannot win — three placements, or it is noise.
    @Test func oneFastDigitDoesNotWinARegion() {
        var moves = [LoggedMove(kind: .place, cell: 0, digit: 1, at: 0.1)]
        var clock = 0.1
        for cell in [60, 61, 62] { clock += 5; moves.append(LoggedMove(kind: .place, cell: cell, digit: 2, at: clock)) }
        let result = debrief(moves)
        #expect(result.fastestRegion?.contains("Box 9") == true, "got \(result.fastestRegion ?? "nil")")
    }

    /// The circled cell is one the player came *back* to. A cell filled the
    /// first time it is touched has a gap of zero and can never win.
    @Test func theCircledCellIsOneComeBackTo() {
        let result = debrief([
            LoggedMove(kind: .pencil, cell: 40, digit: 3, at: 5),   // noticed early…
            LoggedMove(kind: .place, cell: 7, digit: 1, at: 10),
            LoggedMove(kind: .place, cell: 8, digit: 2, at: 20),
            LoggedMove(kind: .place, cell: 40, digit: 3, at: 200)   // …resolved late
        ])
        // Cell 40 is row 5, column 5 (0-based 4,4).
        #expect(result.longestCircled?.contains("Row 5, column 5") == true,
                "got \(result.longestCircled ?? "nil")")
    }

    @Test func aBoardFilledStraightThroughCirclesNothing() {
        let moves = (0..<9).map { LoggedMove(kind: .place, cell: $0, digit: $0 + 1, at: Double($0) * 3) }
        #expect(debrief(moves).longestCircled == nil)
    }

    // MARK: - The one sentence

    @Test func theHeadlineNamesTheTechniqueAndThePlacementNumber() {
        let moves = [
            LoggedMove(kind: .pencil, cell: 0, digit: 1, at: 1),
            LoggedMove(kind: .place, cell: 1, digit: 1, at: 2),
            LoggedMove(kind: .pencil, cell: 2, digit: 2, at: 3),
            LoggedMove(kind: .place, cell: 3, digit: 3, at: 4)
        ]
        let analysis = ReplayAnalysis(placements: [
            ClassifiedPlacement(moveIndex: 3, cell: 3, digit: 3, kind: .found, technique: .xWing)
        ])
        let headline = debrief(moves, analysis: analysis).headline
        #expect(headline?.contains("X-Wing") == true, "got \(headline ?? "nil")")
        // "Move 2", not "move 4": pencil marks are not moves a player counts.
        #expect(headline?.contains("move 2") == true, "got \(headline ?? "nil")")
    }

    /// A board solved entirely by singles says nothing, and nothing takes its
    /// place — no "no techniques found", which would be the app inventing a way
    /// to disappoint.
    @Test func aBoardOfSinglesSaysNothing() {
        let result = debrief([LoggedMove(kind: .place, cell: 1, digit: 1, at: 1)])
        #expect(result.headline == nil)
        #expect(!result.lines.contains { $0.contains("found") })
    }
}
