// CageTilingTests — the properties a killer cage layout has to have before
// anything downstream is allowed to assume them.
//
// `testEveryCageHoldsDistinctDigits` is the one with a scar on it. The first
// tiler grew cages on pure geometry and produced cages with a repeated digit;
// the context then made two cells that legitimately share a digit into mutual
// peers, and the resulting unsoundness surfaced inside `hiddenSingle` two steps
// later — a classic technique that was doing nothing wrong.
import XCTest
import Foundation
import CouchCore
@testable import NineEngine

final class CageTilingTests: XCTestCase {

    private func tile(_ seed: UInt64, maxSize: Int = 5) -> (SudokuGrid, [Cage]) {
        let grid = BacktrackSolver.completeGrid(seed: seed)
        var rng = SplitMix64(seed: seed &* UInt64(0xBF58_476D_1CE4_E5B9))
        return (grid, CageTiling.cages(of: grid, using: &rng, maxSize: maxSize))
    }

    func testTheCagesPartitionAllEightyOneCellsExactlyOnce() {
        for seed in UInt64(1)...40 {
            let (_, cages) = tile(seed)
            let cells = cages.flatMap(\.cells)
            XCTAssertEqual(cells.count, 81, "seed \(seed): cells covered")
            XCTAssertEqual(Set(cells).count, 81, "seed \(seed): no cell in two cages")
        }
    }

    func testEveryCageHoldsDistinctDigits() {
        for seed in UInt64(1)...40 {
            let (grid, cages) = tile(seed)
            for cage in cages {
                let digits = cage.cells.map { grid[$0] }
                XCTAssertEqual(Set(digits).count, digits.count,
                               "seed \(seed): cage \(cage.cells) repeats a digit")
            }
        }
    }

    /// Sums come off the solution, so the solution satisfies every cage before
    /// generation proves anything at all.
    func testEveryCageSumMatchesTheSolution() {
        for seed in UInt64(1)...40 {
            let (grid, cages) = tile(seed)
            for cage in cages {
                XCTAssertEqual(cage.sum, cage.cells.reduce(0) { $0 + grid[$1] })
            }
        }
    }

    /// A cage is drawn as one outline, so it has to be one orthogonally
    /// connected region.
    func testEveryCageIsOrthogonallyConnected() {
        for seed in UInt64(1)...40 {
            let (_, cages) = tile(seed)
            for cage in cages {
                let members = Set(cage.cells)
                var reached: Set<Int> = [cage.cells[0]]
                var frontier = [cage.cells[0]]
                while let cell = frontier.popLast() {
                    for neighbour in CageTiling.neighbours[cell]
                    where members.contains(neighbour) && reached.insert(neighbour).inserted {
                        frontier.append(neighbour)
                    }
                }
                XCTAssertEqual(reached.count, cage.cells.count,
                               "cage \(cage.cells) is not connected")
            }
        }
    }

    func testCagesRespectTheSizeCeiling() {
        for maxSize in [2, 3, 5, 9] {
            for seed in UInt64(1)...10 {
                let (_, cages) = tile(seed, maxSize: maxSize)
                XCTAssertTrue(cages.allSatisfy { $0.cells.count <= maxSize },
                              "seed \(seed) maxSize \(maxSize)")
            }
        }
    }

    /// Singletons are folded into a neighbour where one will take them — a
    /// one-cell cage is a given wearing a circle. A few survive when no
    /// neighbour has room or already holds the digit, and that is fine; what is
    /// not fine is a board made of them.
    func testSingletonCagesAreRare() {
        var singletons = 0, total = 0
        for seed in UInt64(1)...40 {
            let (_, cages) = tile(seed)
            singletons += cages.count(where: { $0.cells.count == 1 })
            total += cages.count
        }
        XCTAssertLessThan(Double(singletons) / Double(total), 0.05,
                          "\(singletons)/\(total) cages are single cells")
    }

    func testTilingIsDeterministic() {
        let grid = BacktrackSolver.completeGrid(seed: 7)
        var a = SplitMix64(seed: 99), b = SplitMix64(seed: 99)
        XCTAssertEqual(CageTiling.cages(of: grid, using: &a),
                       CageTiling.cages(of: grid, using: &b))
    }

    /// Growth prefers a neighbour in the same box, and the rule of 45 depends on
    /// it: without box-alignment, no unit is ever covered by cages that spill
    /// over by exactly one cell, and `innieOutie` never fires.
    func testMostCagesStayInsideOneBox() {
        var confined = 0, total = 0
        for seed in UInt64(1)...40 {
            let (_, cages) = tile(seed)
            for cage in cages where cage.cells.count > 1 {
                total += 1
                if Set(cage.cells.map(Sudoku.box(of:))).count == 1 { confined += 1 }
            }
        }
        XCTAssertGreaterThan(Double(confined) / Double(total), 0.6,
                             "\(confined)/\(total) multi-cell cages stay in one box")
    }
}
