import XCTest
import CouchCore
@testable import DarkroomEngine

final class CompilerTests: XCTestCase {

    static let dateSeed: UInt64 = 20260710
    static let sizes = GridSize.allCases.map(\.rawValue)

    /// The anti-fragility claim (PRD §5.3), actually tested: run the
    /// compiler over EVERY CouchCore DemoArt recipe × all three grid sizes.
    /// Every puzzle that ships must be fully resolvable by the line solver
    /// and land exactly on its stored solution.
    func testEveryCompiledDemoPuzzleIsLineSolvable() {
        var accepted = 0
        var perSize = [Int: Int]()
        for recipe in DemoArt.recipes {
            let buffer = DemoArt.render(recipe, width: 640, height: 360)
            for size in Self.sizes {
                let outcome = PuzzleCompiler.compileDetailed(
                    photoID: "demo-\(recipe.id)",
                    buffer: buffer,
                    size: size,
                    dateSeed: Self.dateSeed
                )
                XCTAssertLessThanOrEqual(outcome.attempts, PuzzleCompiler.maxAttempts)
                guard let puzzle = outcome.puzzle else { continue }
                accepted += 1
                perSize[size, default: 0] += 1

                // Independent re-verification: line logic alone reaches the
                // exact stored solution.
                XCTAssertTrue(
                    GridSolver.verify(puzzle),
                    "\(recipe.id) @ \(size) shipped a puzzle the line solver can't finish"
                )
                // Structural sanity.
                XCTAssertEqual(puzzle.solution.count, size * size)
                XCTAssertEqual(puzzle.colors.count, size * size)
                let ratio = Double(puzzle.filledCount) / Double(size * size)
                XCTAssertTrue(
                    PuzzleCompiler.fillRatioRange.contains(ratio),
                    "\(recipe.id) @ \(size) fill ratio \(ratio) out of range"
                )
                // Clue bookkeeping: row and column clue sums both equal the
                // fill count.
                let rowSum = puzzle.rowClues.flatMap { $0 }.reduce(0, +)
                let colSum = puzzle.colClues.flatMap { $0 }.reduce(0, +)
                XCTAssertEqual(rowSum, puzzle.filledCount)
                XCTAssertEqual(colSum, puzzle.filledCount)
                XCTAssertGreaterThanOrEqual(puzzle.difficulty, 1)
            }
        }
        // The demo channel must actually feed the app: every size playable.
        for size in Self.sizes {
            XCTAssertGreaterThan(
                perSize[size, default: 0], 0,
                "no demo recipe compiled at \(size)×\(size)"
            )
        }
        // And acceptance shouldn't be anecdotal.
        XCTAssertGreaterThanOrEqual(
            accepted, DemoArt.recipes.count,
            "acceptance rate too low: \(accepted)/\(DemoArt.recipes.count * Self.sizes.count)"
        )
        print("[compiler] accepted \(accepted)/\(DemoArt.recipes.count * Self.sizes.count) — per size: \(perSize.sorted { $0.key < $1.key })")
    }

    /// Determinism (PRD §5.5): (photoID, gridSize, dateSeed) ⇒ byte-identical
    /// puzzle, run to run.
    func testCompilerIsDeterministic() {
        let recipe = DemoArt.recipes[0]
        let buffer = DemoArt.render(recipe, width: 640, height: 360)
        let a = PuzzleCompiler.compile(
            photoID: "demo-\(recipe.id)", buffer: buffer, size: 15, dateSeed: Self.dateSeed
        )
        let b = PuzzleCompiler.compile(
            photoID: "demo-\(recipe.id)", buffer: buffer, size: 15, dateSeed: Self.dateSeed
        )
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
    }

    func testCompileSeedIsStableAndInputSensitive() {
        let s1 = PuzzleCompiler.seed(photoID: "p", size: 10, dateSeed: 20260710)
        let s2 = PuzzleCompiler.seed(photoID: "p", size: 10, dateSeed: 20260710)
        XCTAssertEqual(s1, s2)
        XCTAssertNotEqual(s1, PuzzleCompiler.seed(photoID: "q", size: 10, dateSeed: 20260710))
        XCTAssertNotEqual(s1, PuzzleCompiler.seed(photoID: "p", size: 15, dateSeed: 20260710))
        XCTAssertNotEqual(s1, PuzzleCompiler.seed(photoID: "p", size: 10, dateSeed: 20260711))
    }

    func testPuzzleIdentityEncodesInputs() {
        let recipe = DemoArt.recipes[0]
        let buffer = DemoArt.render(recipe, width: 640, height: 360)
        let puzzle = PuzzleCompiler.compile(
            photoID: "demo-\(recipe.id)", buffer: buffer, size: 10, dateSeed: Self.dateSeed
        )
        XCTAssertEqual(puzzle?.id, "demo-\(recipe.id)|10|\(Self.dateSeed)")
    }

    func testFlatImageIsRejected() {
        // A featureless gray card can't become a puzzle: fill ratio explodes
        // to ~all-in or ~all-out under any threshold.
        let flat = PixelBuffer(width: 64, height: 64, fill: RGB(128, 128, 128))
        let outcome = PuzzleCompiler.compileDetailed(
            photoID: "flat", buffer: flat, size: 10, dateSeed: Self.dateSeed
        )
        XCTAssertNil(outcome.puzzle)
        XCTAssertEqual(outcome.attempts, PuzzleCompiler.maxAttempts)
    }

    func testPuzzleRoundTripsThroughJSON() throws {
        let recipe = DemoArt.recipes[1]
        let buffer = DemoArt.render(recipe, width: 640, height: 360)
        let puzzle = try XCTUnwrap(PuzzleCompiler.compile(
            photoID: "demo-\(recipe.id)", buffer: buffer, size: 10, dateSeed: Self.dateSeed
        ))
        let data = try CouchJSON.encode(puzzle)
        let decoded = try CouchJSON.decode(Puzzle.self, from: data)
        XCTAssertEqual(decoded, puzzle)
    }
}
