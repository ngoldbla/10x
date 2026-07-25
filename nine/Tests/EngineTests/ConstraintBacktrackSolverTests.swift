// ConstraintBacktrackSolverTests — the proof side, under variant rules.
//
// The load-bearing test is `testTheCountMatchesAnIndependentEnumeration`: it
// enumerates *every* classic completion of a lightly-dug grid with a brute-force
// filler written here rather than in the engine, filters that list with a
// constraint checker also written here, and compares the count against the
// solver's. Two implementations that share no code have to agree, which is the
// only kind of evidence worth having about a prover — a prover that is wrong in
// the same way as the technique it is checking will happily confirm it.
import XCTest
import Foundation
import CouchCore
@testable import NineEngine

final class ConstraintBacktrackSolverTests: XCTestCase {

    // MARK: - Classic delegation

    /// Classic does not get a second prover. `BacktrackSolver` is frozen — it
    /// proved every puzzle Nine has ever shipped — and this one hands straight
    /// back to it.
    func testClassicDelegatesToTheFrozenOriginal() {
        for seed in UInt64(1)...25 {
            let generated = PuzzleGenerator.generate(seed: seed, difficulty: .gentle)
            XCTAssertEqual(
                ConstraintBacktrackSolver.countSolutions(of: generated.puzzle, context: .classic),
                BacktrackSolver.countSolutions(of: generated.puzzle),
                "seed \(seed)")
        }
        // Including the degenerate ends: empty (many) and contradictory (none).
        XCTAssertEqual(
            ConstraintBacktrackSolver.countSolutions(of: SudokuGrid(), context: .classic),
            .multiple)
        var broken = SudokuGrid()
        broken[0] = 5
        broken[1] = 5
        XCTAssertEqual(
            ConstraintBacktrackSolver.countSolutions(of: broken, context: .classic), SolutionCount.none)
    }

    // MARK: - Refusing what it cannot prove

    /// A rule this build cannot interpret means the count would be of a
    /// *different* puzzle. Answering anyway is how a board from a future build
    /// gets scored and put on a leaderboard under rules nobody here understands.
    func testItRefusesToAnswerForARuleItCannotEnforce() {
        let context = ConstraintContext.compile([
            .cage(Cage(cells: [0, 1], sum: 5)!),
            .unrecognized(kind: "arrow", payload: .null),
        ])
        XCTAssertNil(ConstraintBacktrackSolver.countSolutions(of: SudokuGrid(), context: context))
        XCTAssertFalse(ConstraintBacktrackSolver.isUnique(SudokuGrid(), context: context),
                       "unprovable reads as not-unique everywhere it is used")
    }

    // MARK: - Killer boards

    /// A solved grid with cages read off it is trivially unique, and the answer
    /// has to be that grid.
    func testASolvedKillerGridIsUniqueAndIsItself() {
        for seed in UInt64(1)...15 {
            let solution = BacktrackSolver.completeGrid(seed: seed)
            var rng = SplitMix64(seed: seed)
            let context = ConstraintContext.compile(
                CageTiling.cages(of: solution, using: &rng).map(VariantConstraint.cage))
            XCTAssertEqual(
                ConstraintBacktrackSolver.countSolutions(of: solution, context: context),
                .unique(solution), "seed \(seed)")
        }
    }

    /// Cage sums really are enforced: change one given so a cage can no longer
    /// make its sum and the board has no solutions at all.
    func testAViolatedCageSumHasNoSolutions() {
        let solution = BacktrackSolver.completeGrid(seed: 3)
        var rng = SplitMix64(seed: 3)
        let cages = CageTiling.cages(of: solution, using: &rng)
        let context = ConstraintContext.compile(cages.map(VariantConstraint.cage))
        // Bend one cage's sum by one, keeping it inside the legal range.
        let target = cages.first { $0.cells.count >= 2 && $0.sum + 1 <= Cage.maximumSum(size: $0.cells.count) }!
        var bent = cages.map(VariantConstraint.cage)
        bent[cages.firstIndex(of: target)!] = .cage(Cage(cells: target.cells, sum: target.sum + 1)!)
        XCTAssertEqual(
            ConstraintBacktrackSolver.countSolutions(of: solution, context: .compile(bent)),
            SolutionCount.none)
        XCTAssertEqual(
            ConstraintBacktrackSolver.countSolutions(of: solution, context: context),
            .unique(solution), "…and the unbent one still proves")
    }

    func testAViolatedThermometerHasNoSolutions() {
        var grid = SudokuGrid()
        grid[0] = 5
        grid[1] = 3 // decreasing along the thermometer
        let context = ConstraintContext.compile([.thermometer(Thermometer(cells: [0, 1, 2])!)])
        XCTAssertEqual(ConstraintBacktrackSolver.countSolutions(of: grid, context: context),
                       SolutionCount.none)
    }

    /// Cages carry information a classic grid does not, so a position the
    /// classic prover calls ambiguous can be unique under killer rules. If this
    /// ever stops being true the cages are not reaching the search.
    func testCagesCanMakeAnAmbiguousGridUnique() {
        var found = false
        for seed in UInt64(1)...40 where !found {
            let solution = BacktrackSolver.completeGrid(seed: seed)
            var rng = SplitMix64(seed: seed &* 31)
            let context = ConstraintContext.compile(
                CageTiling.cages(of: solution, using: &rng).map(VariantConstraint.cage))
            var grid = solution
            for cell in 0..<81 where rng.nextInt(below: 2) == 0 { grid[cell] = 0 }
            if BacktrackSolver.countSolutions(of: grid) == .multiple,
               ConstraintBacktrackSolver.countSolutions(of: grid, context: context) == .unique(solution) {
                found = true
            }
        }
        XCTAssertTrue(found, "no seed produced a grid the cages disambiguated")
    }

    // MARK: - The independent oracle

    /// Enumerate every classic completion with a brute-force filler that shares
    /// no code with the engine, filter it with a constraint checker that shares
    /// no code either, and make the two counts agree.
    func testTheCountMatchesAnIndependentEnumeration() {
        var checked = 0
        for seed in UInt64(1)...25 {
            let solution = BacktrackSolver.completeGrid(seed: seed)
            var rng = SplitMix64(seed: seed &* UInt64(0x9E37_79B9_7F4A_7C15))
            let constraints = CageTiling.cages(of: solution, using: &rng, maxSize: 4)
                .map(VariantConstraint.cage)
            let context = ConstraintContext.compile(constraints)

            // Dig lightly, so the classic completion count stays enumerable.
            var grid = solution
            var holes = 0
            while holes < 11 {
                let cell = rng.nextInt(below: 81)
                if grid[cell] != 0 { grid[cell] = 0; holes += 1 }
            }

            var all: [SudokuGrid] = []
            Self.enumerate(grid, into: &all, cap: 4000)
            guard all.count < 4000 else { continue } // not exhaustive; skip
            let legal = all.filter { Self.satisfies($0, constraints) }
            checked += 1

            let expected: SolutionCount = switch legal.count {
            case 0: .none
            case 1: .unique(legal[0])
            default: .multiple
            }
            XCTAssertEqual(
                ConstraintBacktrackSolver.countSolutions(of: grid, context: context),
                expected,
                "seed \(seed): \(all.count) classic completions, \(legal.count) legal")
        }
        XCTAssertGreaterThan(checked, 15, "the oracle skipped too many seeds to mean anything")
    }

    // MARK: - Oracle machinery (deliberately naive, deliberately separate)

    /// Every classic completion of `grid`, by plain recursive fill. No MRV, no
    /// bitmask tricks — the point is that it cannot be wrong in the same way the
    /// engine is.
    static func enumerate(_ grid: SudokuGrid, into result: inout [SudokuGrid], cap: Int) {
        var working = grid
        func fill() {
            if result.count >= cap { return }
            guard let cell = (0..<81).first(where: { working[$0] == 0 }) else {
                result.append(working)
                return
            }
            for digit in 1...9 {
                let row = Sudoku.row(of: cell), col = Sudoku.col(of: cell)
                let box = Sudoku.box(of: cell)
                var clash = false
                for other in 0..<81 where other != cell && working[other] == digit {
                    if Sudoku.row(of: other) == row || Sudoku.col(of: other) == col
                        || Sudoku.box(of: other) == box { clash = true; break }
                }
                if clash { continue }
                working[cell] = digit
                fill()
                working[cell] = 0
                if result.count >= cap { return }
            }
        }
        fill()
    }

    /// A completed grid against the rules, read straight off the constraint
    /// values rather than off any compiled table.
    static func satisfies(_ grid: SudokuGrid, _ constraints: [VariantConstraint]) -> Bool {
        for constraint in constraints {
            switch constraint {
            case .cage(let cage):
                let digits = cage.cells.map { grid[$0] }
                if Set(digits).count != digits.count { return false }
                if digits.reduce(0, +) != cage.sum { return false }
            case .thermometer(let thermo):
                for (a, b) in zip(thermo.cells, thermo.cells.dropFirst())
                where grid[a] >= grid[b] { return false }
            case .unrecognized:
                return false
            }
        }
        return true
    }
}
