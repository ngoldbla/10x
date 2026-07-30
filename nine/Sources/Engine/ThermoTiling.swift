// ThermoTiling.swift — seeded thermometer layouts over a solved grid.
//
// Deliberately **not** `CageTiling` with a different shape, because the two are
// different kinds of object and the difference is load-bearing downstream:
//
//   • A cage tiling is a *partition*. Every cell belongs to exactly one cage,
//     which is precisely what makes the rule of 45 fire — `innieOutie` keys on
//     "the cages covering this unit spill over by exactly one cell".
//   • A thermometer layout is a set of *paths*, and it covers the board only
//     partially. There is no rule of 45 analogue, no coverage requirement, and a
//     board with nine tubes on it still has forty-odd cells no tube touches.
//
// So the termination condition is a tube count rather than "every cell owned",
// and the growth rule is an ordering rather than a distinctness one.
//
// **The soundness rule, and it is stricter than the cage one.** A cage asserts
// that its digits are distinct; a thermometer asserts that they *increase*. A
// tube laid across cells whose solution digits do not strictly increase does not
// merely lose an elimination — `ConstraintContext` narrows `initialCandidates` by
// position along the tube before any technique runs (the bulb of a 3-cell tube
// cannot exceed 7), so a wrong tube can eliminate a cell's **true digit**, and
// every technique afterwards reasons impeccably about a board that does not
// exist. The uniqueness prover agrees with it, because it is wrong in the same
// way. That is why growth reads digits off the solution as it goes instead of
// laying geometry first and validating afterwards: there is no validating
// afterwards that would catch it in time.
//
// This is the same lesson `CageTiling`'s header records — its first version grew
// on pure geometry and produced cages with a repeated digit — arriving one
// constraint kind later with higher stakes.
import Foundation
import CouchCore

public enum ThermoTiling {

    /// King-move neighbours of each cell: orthogonal **and** diagonal.
    ///
    /// Wider than `CageTiling.neighbours` on purpose, and it is a notation
    /// decision rather than a convenience. A cage is drawn as an outline around a
    /// region, so a diagonal step would make the outline ambiguous; a
    /// thermometer is drawn as a stroke from bulb to tip, and the diagonal run is
    /// standard notation in published thermo sudoku. Restricting to orthogonal
    /// steps would also cost most of the long tubes — a 9-cell increasing
    /// orthogonal walk is rare — and a long tube is where the variant's
    /// information density lives.
    static let neighbours: [[Int]] = (0..<81).map { cell in
        let row = Sudoku.row(of: cell), col = Sudoku.col(of: cell)
        var result: [Int] = []
        for dr in -1...1 {
            for dc in -1...1 where !(dr == 0 && dc == 0) {
                let r = row + dr, c = col + dc
                guard (0...8).contains(r), (0...8).contains(c) else { continue }
                result.append(r * 9 + c)
            }
        }
        return result
    }

    /// Lay up to `count` thermometers of `length` cells over `grid`, strictly
    /// increasing bulb→tip, no cell on two tubes. Deterministic in `rng`.
    ///
    /// `count` is a **ceiling, not a promise**. A board can walk out — the tubes
    /// already placed block the room the next one needed — and returning fewer is
    /// the honest answer. The caller's band is sized against the ceiling and its
    /// verifier re-proves whatever it actually got, so a short layout costs an
    /// attempt rather than shipping a thin board.
    ///
    /// Every tube is satisfied by `grid` **by construction**, exactly as every
    /// cage is in `CageTiling`, which leaves uniqueness as the only thing
    /// generation has left to prove.
    public static func thermometers(
        of grid: SudokuGrid,
        using rng: inout SplitMix64,
        count: Int,
        length: ClosedRange<Int>
    ) -> [Thermometer] {
        // `Thermometer.init?` accepts 2…9 cells. Clamping here rather than
        // trusting the caller means a band typo costs a narrower window instead
        // of silently dropping every tube it asked for.
        let low = max(2, length.lowerBound)
        let high = min(9, length.upperBound)
        guard count > 0, low <= high else { return [] }

        var used = [Bool](repeating: false, count: 81)
        var layout: [Thermometer] = []

        var order = Array(0..<81)
        for i in stride(from: order.count - 1, to: 0, by: -1) {
            let j = rng.nextInt(below: i + 1)
            if i != j { order.swapAt(i, j) }
        }

        for start in order {
            guard layout.count < count else { break }
            guard !used[start] else { continue }
            // A bulb whose digit is already too high cannot reach the shortest
            // tube in the window, so it is not worth walking.
            guard grid[start] + (low - 1) <= 9 else { continue }

            let target = low + rng.nextInt(below: high - low + 1)
            guard let path = grow(from: start, target: target, grid: grid,
                                  used: used, using: &rng),
                  path.count >= low,
                  let thermo = Thermometer(cells: path)
            else { continue }

            for cell in path { used[cell] = true }
            layout.append(thermo)
        }
        return layout
    }

    /// Walk one increasing king-move path, or nil if it never reached `target`.
    ///
    /// `used` is taken **by value**: a discarded walk must not consume the cells
    /// it touched, or one unlucky start would poison the region for every later
    /// tube. Committing is the caller's job, after the length is known.
    private static func grow(
        from start: Int,
        target: Int,
        grid: SudokuGrid,
        used: [Bool],
        using rng: inout SplitMix64
    ) -> [Int]? {
        var path = [start]
        var taken = Set([start])
        var direction: (Int, Int)?

        while path.count < target {
            let last = path[path.count - 1]
            let value = grid[last]
            // Legal continuations: unused by an earlier tube, unused by this
            // walk, and strictly larger. The last clause is the constraint.
            let pool = neighbours[last].filter {
                !used[$0] && !taken.contains($0) && grid[$0] > value
            }
            guard !pool.isEmpty else { break }

            // Two preferences, both seeded so the layout stays a pure function
            // of the rng, and both aimed at a tube that is *worth drawing*:
            //
            //  • **Keep going straight** 3 times in 4 when it is possible. A
            //    king-move walk that turns at every step is a legal thermometer
            //    and an unreadable one — it reads as a snake rather than a tube,
            //    and it is what `BoardView` has to render as a single stroke.
            //  • **Otherwise take the smallest legal digit** 3 times in 4. Every
            //    step spends headroom: from a cell holding 6 there are only three
            //    digits left above it, so a greedy jump to 9 ends the tube. The
            //    smallest step is the one that leaves the most tube ahead, which
            //    is what makes the long end of the length window reachable at all.
            //
            // The 1-in-4 escape on each is what stops every board looking the
            // same. Mirrors `CageTiling`'s "4 in 5 growths stay inside the box".
            let next: Int
            if let direction,
               let straight = pool.first(where: {
                   Sudoku.row(of: $0) - Sudoku.row(of: last) == direction.0
                       && Sudoku.col(of: $0) - Sudoku.col(of: last) == direction.1
               }),
               rng.nextInt(below: 4) != 0 {
                next = straight
            } else if rng.nextInt(below: 4) != 0 {
                next = pool.min(by: { grid[$0] < grid[$1] })!
            } else {
                next = pool[rng.nextInt(below: pool.count)]
            }

            direction = (Sudoku.row(of: next) - Sudoku.row(of: last),
                         Sudoku.col(of: next) - Sudoku.col(of: last))
            taken.insert(next)
            path.append(next)
        }
        return path
    }
}
