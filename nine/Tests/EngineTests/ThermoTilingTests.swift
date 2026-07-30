// ThermoTilingTests — the properties a thermometer layout has to have before
// anything downstream is allowed to believe it.
//
// `CageTiling`'s tests exist because a *geometrically* valid tiling was still
// unsound: a cage holding a repeated digit made two cells that legitimately
// share a digit into mutual peers, and `hiddenSingle` — which had done nothing
// wrong — placed a contradiction two steps later (see that file's header). The
// thermo analogue of that bug is worse rather than better, because a thermometer
// asserts an *order* as well as distinctness: a tube laid across cells whose
// solution digits do not strictly increase eliminates the true digit from every
// cell on it, and every technique downstream then reasons correctly about an
// impossible board.
//
// So the four assertions below are not tidiness. Each one is a way the compiled
// `ConstraintContext` would otherwise be a description of a puzzle that does not
// exist:
//
//   • strictly increasing along the solution — or the constraint is false
//   • king-move adjacent, consecutively — or it cannot be drawn as one tube
//   • no cell on two thermometers — or the peer union quietly stops being a
//     partition and `thermoBound`'s two sweeps interact
//   • length inside the band's window — or `Thermometer.init?` returns nil and
//     the tube silently vanishes from a board that was proven with it
import XCTest
import Foundation
import CouchCore
@testable import NineEngine

final class ThermoTilingTests: XCTestCase {

    /// A layout, plus the grid it was read off, checked against every claim the
    /// compiler downstream is entitled to make about it.
    private func assertWellFormed(
        _ thermometers: [Thermometer],
        of grid: SudokuGrid,
        length: ClosedRange<Int>,
        _ label: String
    ) {
        XCTAssertFalse(thermometers.isEmpty, "\(label): no tubes at all")

        var seen = Set<Int>()
        for (index, thermo) in thermometers.enumerated() {
            let cells = thermo.cells
            XCTAssertTrue(length.contains(cells.count),
                          "\(label) tube \(index): length \(cells.count) outside \(length)")

            // Strictly increasing bulb→tip in the solution. This is the whole
            // constraint; everything `thermoBound` derives is downstream of it.
            for step in 1..<cells.count {
                XCTAssertLessThan(
                    grid[cells[step - 1]], grid[cells[step]],
                    "\(label) tube \(index): not increasing at position \(step)")
            }

            // Consecutively king-move adjacent, so the tube is one connected
            // stroke on the board rather than a set of disconnected marks.
            for step in 1..<cells.count {
                let a = cells[step - 1], b = cells[step]
                let dr = abs(Sudoku.row(of: a) - Sudoku.row(of: b))
                let dc = abs(Sudoku.col(of: a) - Sudoku.col(of: b))
                XCTAssertTrue(max(dr, dc) == 1,
                              "\(label) tube \(index): \(a)→\(b) is not a king move")
            }

            // Disjoint across the whole layout, not merely within one tube.
            for cell in cells {
                XCTAssertTrue(seen.insert(cell).inserted,
                              "\(label): cell \(cell) is on two tubes")
            }
        }
    }

    func testALayoutIsIncreasingAdjacentAndDisjoint() {
        for seed in UInt64(1)...12 {
            var rng = SplitMix64(seed: seed)
            let grid = BacktrackSolver.completeGrid(seed: seed)
            let layout = ThermoTiling.thermometers(
                of: grid, using: &rng, count: 9, length: 3...6)
            assertWellFormed(layout, of: grid, length: 3...6, "seed \(seed)")
        }
    }

    /// The count is a target, not a promise — a walked-out board can run out of
    /// room — but it is never *exceeded*, because the caller sizes its budget
    /// against it.
    func testTheCountIsACeiling() {
        for count in [1, 4, 9, 14] {
            var rng = SplitMix64(seed: 7)
            let grid = BacktrackSolver.completeGrid(seed: 7)
            let layout = ThermoTiling.thermometers(
                of: grid, using: &rng, count: count, length: 3...5)
            XCTAssertLessThanOrEqual(layout.count, count, "count=\(count)")
        }
    }

    /// A nine-cell tube is the extreme case and the one most likely to be built
    /// wrong: it can only ever be 1…9 in order, so it fixes a whole line, and it
    /// is where an off-by-one in the growth bound would show up.
    func testTheLongestPossibleTubeIsStillWellFormed() {
        var found = 0
        for seed in UInt64(1)...40 {
            var rng = SplitMix64(seed: seed)
            let grid = BacktrackSolver.completeGrid(seed: seed)
            let layout = ThermoTiling.thermometers(
                of: grid, using: &rng, count: 4, length: 7...9)
            guard !layout.isEmpty else { continue }
            found += 1
            assertWellFormed(layout, of: grid, length: 7...9, "long seed \(seed)")
            for thermo in layout where thermo.cells.count == 9 {
                XCTAssertEqual(thermo.cells.map { grid[$0] }, Array(1...9),
                               "a nine-cell tube can only be 1…9 in order")
            }
        }
        XCTAssertGreaterThan(found, 0, "no long tube was ever built — the window is unreachable")
    }

    /// Deterministic in the generator's own currency. A layout that moved between
    /// launches would re-roll every future thermo daily, which is the property
    /// the golden corpus exists to protect for classic.
    func testTheLayoutIsAPureFunctionOfTheSeed() {
        let grid = BacktrackSolver.completeGrid(seed: 3)
        var a = SplitMix64(seed: 99)
        var b = SplitMix64(seed: 99)
        var c = SplitMix64(seed: 100)
        XCTAssertEqual(
            ThermoTiling.thermometers(of: grid, using: &a, count: 8, length: 3...6),
            ThermoTiling.thermometers(of: grid, using: &b, count: 8, length: 3...6))
        XCTAssertNotEqual(
            ThermoTiling.thermometers(of: grid, using: &a, count: 8, length: 3...6),
            ThermoTiling.thermometers(of: grid, using: &c, count: 8, length: 3...6))
    }

    /// The compiled context has to agree with the layout, which is the seam where
    /// a sound layout can still become an unsound puzzle. In particular every
    /// cell's true digit must survive `initialCandidates` — the position-narrowed
    /// mask is applied before any technique runs, so if it excludes the solution
    /// the board is dead on arrival and every later proof is about nothing.
    func testTheCompiledContextStillAdmitsTheSolution() {
        for seed in UInt64(1)...8 {
            var rng = SplitMix64(seed: seed)
            let grid = BacktrackSolver.completeGrid(seed: seed)
            let layout = ThermoTiling.thermometers(
                of: grid, using: &rng, count: 10, length: 3...7)
            let context = ConstraintContext.compile(layout.map(VariantConstraint.thermometer))
            XCTAssertTrue(context.canEnforceEveryConstraint, "seed \(seed)")
            XCTAssertEqual(context.thermometers, layout, "seed \(seed)")
            for cell in 0..<81 {
                XCTAssertNotEqual(
                    context.initialCandidates[cell] & Sudoku.bit(grid[cell]), 0,
                    "seed \(seed): cell \(cell) cannot hold its own solution digit")
            }
            // And the peer union stays sound: two cells on one tube are peers,
            // and their solution digits therefore differ.
            for (a, peers) in context.peers.enumerated() {
                for b in peers {
                    XCTAssertNotEqual(grid[a], grid[b],
                                      "seed \(seed): peers \(a),\(b) share digit \(grid[a])")
                }
            }
        }
    }
}
