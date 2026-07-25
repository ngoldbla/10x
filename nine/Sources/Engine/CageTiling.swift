// CageTiling.swift — seeded polyomino cage tilings of a solved grid, the shape
// a killer board's cages come in.
//
// Separated from generation on purpose: it is a pure function of (grid, seed),
// so it is testable on its own and the soundness fuzz in `VariantTechniqueTests`
// runs the variant techniques against the *same* tilings the generator will hand
// them rather than against an artificial stand-in. Two things that fuzz taught
// this file, both of them findings rather than polish:
//
//  • **The tiling has to be grid-aware.** A cage holds *distinct* digits, so a
//    region may only grow into a neighbour whose solution digit it does not
//    already hold. The first version grew on pure geometry, produced cages with
//    a repeated digit, and made two cells that legitimately share a digit into
//    mutual peers — after which the true digit was eliminated and `hiddenSingle`,
//    which had done nothing wrong, placed a contradiction two steps later.
//  • **Growth has to prefer staying inside a box**, or the rule of 45 never
//    fires. It keys on "the cages covering this unit spill over by exactly one
//    cell", which only happens when cages mostly respect unit boundaries.
import Foundation
import CouchCore

public enum CageTiling {

    /// Orthogonal neighbours of each cell, precomputed. Cages are connected
    /// regions, which is what makes them drawable as one outline.
    static let neighbours: [[Int]] = (0..<81).map { cell in
        let row = Sudoku.row(of: cell), col = Sudoku.col(of: cell)
        var result: [Int] = []
        if row > 0 { result.append(cell - 9) }
        if col > 0 { result.append(cell - 1) }
        if col < 8 { result.append(cell + 1) }
        if row < 8 { result.append(cell + 9) }
        return result
    }

    /// Partition all 81 cells into orthogonally-connected cages of 1…`maxSize`
    /// cells, each holding distinct digits, with sums read off `grid`.
    /// Deterministic in `rng`.
    ///
    /// Every cage is satisfied by `grid` **by construction**, which is what
    /// leaves uniqueness as the only thing generation has left to prove.
    public static func cages(
        of grid: SudokuGrid, using rng: inout SplitMix64, maxSize: Int = 5
    ) -> [Cage] {
        precondition((2...9).contains(maxSize), "a cage holds 1…9 distinct digits")
        var owner = [Int](repeating: -1, count: 81)
        var regions: [[Int]] = []
        var digits: [UInt16] = []   // digit mask per region

        var order = Array(0..<81)
        for i in stride(from: order.count - 1, to: 0, by: -1) {
            let j = rng.nextInt(below: i + 1)
            if i != j { order.swapAt(i, j) }
        }

        for start in order where owner[start] == -1 {
            let index = regions.count
            var region = [start]
            var mask = Sudoku.bit(grid[start])
            owner[start] = index
            let target = 2 + rng.nextInt(below: maxSize - 1)

            while region.count < target {
                var sameBox: [Int] = []
                var elsewhere: [Int] = []
                for cell in region {
                    for neighbour in neighbours[cell]
                    where owner[neighbour] == -1 && mask & Sudoku.bit(grid[neighbour]) == 0 {
                        if Sudoku.box(of: neighbour) == Sudoku.box(of: cell) {
                            sameBox.append(neighbour)
                        } else {
                            elsewhere.append(neighbour)
                        }
                    }
                }
                // 4 in 5 growths stay inside the box when they can.
                let pool = (!sameBox.isEmpty && rng.nextInt(below: 5) != 0)
                    ? sameBox : (sameBox + elsewhere)
                guard !pool.isEmpty else { break }
                let picked = pool[rng.nextInt(below: pool.count)]
                owner[picked] = index
                mask |= Sudoku.bit(grid[picked])
                region.append(picked)
            }

            regions.append(region.sorted())
            digits.append(mask)
        }

        mergeSingletons(&regions, digits: &digits, owner: &owner, grid: grid, maxSize: maxSize)
        return regions.compactMap { cells in
            Cage(cells: cells, sum: cells.reduce(0) { $0 + grid[$1] })
        }
    }

    /// Fold every one-cell region into an adjacent region that has room and does
    /// not already hold its digit. A singleton cage is a given wearing a circle:
    /// legal, but it hands the player a digit for free. Some survive when no
    /// neighbour can take them; that is rare and harmless.
    private static func mergeSingletons(
        _ regions: inout [[Int]],
        digits: inout [UInt16],
        owner: inout [Int],
        grid: SudokuGrid,
        maxSize: Int
    ) {
        for (index, region) in regions.enumerated() where region.count == 1 {
            let cell = region[0]
            let bit = Sudoku.bit(grid[cell])
            let host = neighbours[cell]
                .map { owner[$0] }
                // `!isEmpty` matters: a region emptied by an earlier merge in
                // this same loop still looks like it has room.
                .filter {
                    $0 != index && !regions[$0].isEmpty
                        && regions[$0].count < maxSize && digits[$0] & bit == 0
                }
                .min()
            guard let host else { continue }
            regions[host] = (regions[host] + [cell]).sorted()
            digits[host] |= bit
            regions[index] = []
            owner[cell] = host
        }
        let survivors = regions.indices.filter { !regions[$0].isEmpty }
        regions = survivors.map { regions[$0] }
        digits = survivors.map { digits[$0] }
    }
}
