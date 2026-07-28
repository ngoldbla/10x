import Foundation
import Testing
@testable import NineShared
import NineEngine

@Suite("PeerRails")
struct PeerRailsTests {

    private var game: NineGame {
        NineGame(puzzle: PuzzleGenerator.generate(
            seed: DailySeed.seed(forDayOrdinal: 9_400), difficulty: .steady
        ))
    }

    // MARK: - Geometry, for all 81 cells

    /// PRD-6 §6 item 2 asks for "peer rails correct for every cell", so this
    /// checks every cell rather than a sample.
    @Test func everyCellsRowAndColumnAgreeWithTheEnginesOwnGeometry() {
        for cell in 0..<81 {
            let rowCells = PeerRails.rowCells(of: cell)
            let columnCells = PeerRails.columnCells(of: cell)
            #expect(rowCells.count == 9)
            #expect(columnCells.count == 9)
            #expect(rowCells.contains(cell))
            #expect(columnCells.contains(cell))
            #expect(rowCells.allSatisfy { Sudoku.row(of: $0) == Sudoku.row(of: cell) })
            #expect(columnCells.allSatisfy { Sudoku.col(of: $0) == Sudoku.col(of: cell) })
        }
    }

    @Test func aRowAndAColumnMeetOnlyAtTheirOwnCell() {
        for cell in 0..<81 {
            let shared = Set(PeerRails.rowCells(of: cell))
                .intersection(PeerRails.columnCells(of: cell))
            #expect(shared == [cell])
        }
    }

    // MARK: - Contents

    @Test func aRailShowsEveryStandingDigitOnceAndInOrder() {
        let g = game
        for cell in 0..<81 {
            let rail = PeerRails.row(of: cell, in: g)
            #expect(rail == rail.sorted())
            #expect(Set(rail).count == rail.count)
            let expected = Set(PeerRails.rowCells(of: cell).map { g.entry(at: $0) }).subtracting([0])
            #expect(Set(rail) == expected)
        }
    }

    /// A rail reads placed entries only. Pencil marks are a guess, and a rail
    /// that showed them would eliminate candidates on the strength of the
    /// player's own uncertainty.
    @Test func pencilMarksNeverReachARail() {
        var g = game
        let empty = (0..<81).first { g.entry(at: $0) == 0 }!
        let before = PeerRails.row(of: empty, in: g)
        // Pencil a digit that is definitely not already standing in the row.
        let candidate = (1...9).first { !before.contains($0) }!
        let noted = g.togglePencil(candidate, at: empty)
        #expect(noted)
        #expect(PeerRails.row(of: empty, in: g) == before)
    }

    /// The rails restate what the full board would show; they never know
    /// more than it does. Placing a digit is the only thing that adds one.
    @Test func placingADigitIsWhatAddsItToTheRail() throws {
        var g = game
        let cell = try #require((0..<81).first { g.entry(at: $0) == 0 })
        let truth = g.puzzle.solution.cells[cell]
        #expect(!PeerRails.row(of: cell, in: g).contains(truth))
        let placed = g.place(truth, at: cell)
        #expect(placed)
        #expect(PeerRails.row(of: cell, in: g).contains(truth))
        #expect(PeerRails.column(of: cell, in: g).contains(truth))
    }

    @Test func ruledOutIsTheUnionOfTheTwoRails() {
        let g = game
        for cell in 0..<81 {
            let union = Set(PeerRails.row(of: cell, in: g))
                .union(PeerRails.column(of: cell, in: g))
            #expect(PeerRails.ruledOut(for: cell, in: g) == union)
        }
    }

    /// The rails must never rule out the cell's own answer, or the lens would
    /// be lying to the player about a digit they are about to need.
    @Test func aRailNeverRulesOutTheCellsOwnSolution() {
        let g = game
        for cell in 0..<81 where g.entry(at: cell) == 0 {
            #expect(!PeerRails.ruledOut(for: cell, in: g).contains(g.puzzle.solution.cells[cell]))
        }
    }
}
