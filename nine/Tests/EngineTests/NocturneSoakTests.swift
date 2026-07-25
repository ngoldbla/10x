// NocturneSoakTests — the Nocturne generation soak, and the compose-time
// measurement the PR quotes. Opt-in, because it cannot live in `swift test`.
//
// **Why this is not part of the default suite.** `swift test` builds Debug, and
// generation runs ~50× slower there than in the Release configuration that
// ships — measured on the same machine, sharp seed 3004: **0.428 s release,
// 30.8 s debug**. Nocturne's median seed is ~1 s in Release, so a 200-seed soak
// is ~5 minutes in Release and would be hours in Debug, against a suite budget
// of 120 s. Every number here is therefore a Release number, gathered the only
// way it means anything:
//
//     nine/scripts/compose-scan.sh                       # prints the p95 table
//     NINE_SOAK=200 swift test -c release --filter NocturneSoak
//
// `GeneratorTests` keeps one Debug-affordable Nocturne compose so the band is
// still exercised on every push; this is the lane that proves the distribution.
// PROGRAM-2.0.md's CI shape puts soaks and perf baselines in the nightly lane —
// this is that lane's Nocturne entry.
import XCTest
import Foundation
@testable import NineEngine

final class NocturneSoakTests: XCTestCase {

    /// Seeds to compose. Zero (the default) skips, so the file is inert in the
    /// default suite even when a filter happens to match it.
    private var seedCount: Int {
        Int(ProcessInfo.processInfo.environment["NINE_SOAK"] ?? "0") ?? 0
    }

    /// Every board the band hands out must satisfy everything it claims:
    /// unique, inside Sharp's chain, past the X-wing floor, at or under the clue
    /// ceiling, and carrying at least the demanded number of advanced steps.
    ///
    /// The last two assertions are the ones that caught a real bug. The first
    /// version of `PuzzleGenerator.attemptBudget` was 500, calibrated against
    /// wall-clock rather than against attempts; it fired on nearly every seed
    /// and handed out Sharp-grade boards wearing a Nocturne label — while the
    /// wall-clock p95 *improved* from 4.7 s to 0.44 s. A timing test would have
    /// called that a win. Assert on the product, not on the clock.
    func testEveryNocturneBoardMeetsTheBandItClaims() throws {
        let count = seedCount
        try XCTSkipIf(count == 0, "set NINE_SOAK=<n> (release config) to run the soak")
        let demands = try XCTUnwrap(Difficulty.nocturne.demands)

        var seconds: [Double] = []
        for seed in 1...UInt64(count) {
            let started = Date()
            let p = PuzzleGenerator.generate(seed: seed, difficulty: .nocturne)
            seconds.append(Date().timeIntervalSince(started))

            guard case .unique(let proven) = BacktrackSolver.countSolutions(of: p.puzzle) else {
                XCTFail("nocturne seed \(seed): not unique"); continue
            }
            XCTAssertEqual(proven, p.solution, "nocturne seed \(seed)")

            let outcome = LogicSolver.solve(p.puzzle, allowed: Difficulty.nocturne.allowedTechniques)
            XCTAssertTrue(outcome.solved, "nocturne seed \(seed): outside the chain")
            XCTAssertEqual(outcome.steps, p.steps, "nocturne seed \(seed): trace drifted")
            XCTAssertEqual(p.hardestTechnique, .xWing, "nocturne seed \(seed)")

            XCTAssertLessThanOrEqual(p.givenCount, demands.maxGivens, "nocturne seed \(seed)")
            XCTAssertTrue(demands.admits(steps: p.steps), "nocturne seed \(seed): not dense enough")

            for cell in 0..<81 {
                XCTAssertEqual(p.puzzle[cell] == 0, p.puzzle[80 - cell] == 0,
                               "nocturne seed \(seed): asymmetric hole at \(cell)")
            }
        }
        report(seconds)
    }

    /// Printed, never asserted on. A compose-time threshold inside a test is a
    /// flake on shared CI hardware; the number belongs in the PR and in
    /// DEVIATIONS, next to the machine it came from. What CI gates on is the
    /// assertions above.
    private func report(_ seconds: [Double]) {
        let sorted = seconds.sorted()
        func percentile(_ q: Double) -> Double {
            sorted[min(sorted.count - 1, Int(q * Double(sorted.count)))]
        }
        let line = String(
            format: "nocturne compose n=%d p50=%.2fs p90=%.2fs p95=%.2fs p99=%.2fs max=%.2fs mean=%.2fs",
            sorted.count, percentile(0.5), percentile(0.9), percentile(0.95),
            percentile(0.99), sorted.last ?? 0,
            sorted.reduce(0, +) / Double(max(1, sorted.count)))
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
