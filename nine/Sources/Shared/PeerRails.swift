// PeerRails.swift — the lens's context strips (PRD-6 §2.2).
//
// Diving into a 3×3 box buys finger-scale targets and costs the cross-hatching
// that is most of how sudoku is actually played. The peer rails buy it back in
// the watch's own idiom: two slim strips along the top and left edges showing
// which digits already stand in the selected cell's full row and column, so
// you can eliminate without leaving the lens.
//
// Row and column only, not box-remaining. PRD-6 §7 leans that way and the
// reason is a measurement, not a taste: a third strip is a third thing to read
// on a screen 198pt wide, and the box's own digits are already on screen —
// you are looking at them.
//
// Pure Engine + Foundation so the answer can be asserted for all 81 cells
// without a watch (PRD-6 §6 item 2: "peer rails correct for every cell").
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

public enum PeerRails {

    /// The digits standing in `cell`'s row, sorted. Placed entries only —
    /// pencil marks are a guess, and a rail that showed them would eliminate
    /// candidates on the strength of your own uncertainty.
    public static func row(of cell: Int, in game: NineGame) -> [Int] {
        digits(at: rowCells(of: cell), in: game)
    }

    /// The digits standing in `cell`'s column, sorted.
    public static func column(of cell: Int, in game: NineGame) -> [Int] {
        digits(at: columnCells(of: cell), in: game)
    }

    /// Everything `cell` cannot be, from its row and column alone.
    ///
    /// Not a solver and not a hint: this is the same information the phone's
    /// board shows by simply being visible all at once, restated for a screen
    /// that can only show a ninth of it. The coach never places a digit, and
    /// this never suggests one.
    public static func ruledOut(for cell: Int, in game: NineGame) -> Set<Int> {
        Set(row(of: cell, in: game)).union(column(of: cell, in: game))
    }

    static func rowCells(of cell: Int) -> [Int] {
        let first = (cell / 9) * 9
        return Array(first..<(first + 9))
    }

    static func columnCells(of cell: Int) -> [Int] {
        let col = cell % 9
        return (0..<9).map { $0 * 9 + col }
    }

    private static func digits(at cells: [Int], in game: NineGame) -> [Int] {
        var seen = Set<Int>()
        for cell in cells where game.entry(at: cell) != 0 {
            seen.insert(game.entry(at: cell))
        }
        return seen.sorted()
    }
}
