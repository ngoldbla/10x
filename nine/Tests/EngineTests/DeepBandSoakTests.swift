// DeepBandSoakTests — the Tempest and Abyss generation soak, and the compose
// numbers PRD-25 quotes. Opt-in, for `NocturneSoakTests`' reasons exactly:
// `swift test` builds Debug, generation runs ~50× slower there than in the
// Release configuration that ships, and a compose figure gathered in Debug is
// not a figure about anything a player experiences.
//
//     nine/scripts/compose-scan.sh                   # every band, p95 table
//     NINE_SOAK=100 swift test -c release --filter DeepBandSoak
//
// **A band ships at a measured p95 or it does not ship.** That is PRD-23's rule
// for variant tiers, applied here to difficulty bands, and it is why this file
// existed before the two bands had a card on the shelf.
//
// What is asserted is the *product*, never the clock: a compose-time threshold
// in a test is a flake on shared CI hardware, and — the lesson that cost
// PRD-17 a bug — a generator that gets faster by handing out boards below the
// band it claims makes a timing test go green. `attemptBudget` was 500 once,
// fired on nearly every seed, dropped the wall-clock p95 from 4.7 s to 0.44 s,
// and was silently shipping Sharp boards labelled Nocturne.
import XCTest
import Foundation
@testable import NineEngine

final class DeepBandSoakTests: XCTestCase {

    private var seedCount: Int {
        Int(ProcessInfo.processInfo.environment["NINE_SOAK"] ?? "0") ?? 0
    }

    func testEveryTempestBoardMeetsTheBandItClaims() throws {
        try soak(.tempest)
    }

    func testEveryAbyssBoardMeetsTheBandItClaims() throws {
        try soak(.abyss)
    }

    /// Both bands, one body: they differ only in their floor, which is the
    /// point of defining them by floor rather than by generator parameters.
    private func soak(_ band: Difficulty) throws {
        let count = seedCount
        try XCTSkipIf(count == 0, "set NINE_SOAK=<n> (release config) to run the soak")
        let floor = try XCTUnwrap(band.floor)

        var seconds: [Double] = []
        var hardest = [Technique: Int]()
        var givens: [Int] = []
        for seed in 1...UInt64(count) {
            let started = Date()
            let p = PuzzleGenerator.generate(seed: seed, difficulty: band)
            seconds.append(Date().timeIntervalSince(started))
            givens.append(p.givenCount)

            guard case .unique(let proven) = BacktrackSolver.countSolutions(of: p.puzzle) else {
                XCTFail("\(band) seed \(seed): not unique"); continue
            }
            XCTAssertEqual(proven, p.solution, "\(band) seed \(seed)")

            let outcome = LogicSolver.solve(p.puzzle, allowed: band.allowedTechniques)
            XCTAssertTrue(outcome.solved, "\(band) seed \(seed): outside the chain")
            XCTAssertEqual(outcome.steps, p.steps, "\(band) seed \(seed): trace drifted")

            // The band's whole claim. A Tempest board that can be finished with
            // an X-wing is a Sharp board with a different label on it, and that
            // is the failure mode this file exists to make impossible.
            let top = try XCTUnwrap(p.hardestTechnique, "\(band) seed \(seed): no steps")
            XCTAssertGreaterThanOrEqual(top, floor, "\(band) seed \(seed): below its floor")
            hardest[top, default: 0] += 1

            // The trace has to be *readable*, not just correct: PRD-25 narrates
            // it. A board proven by a technique the coach has no sentence for
            // would be a board Nine can solve and cannot explain.
            for step in p.steps {
                XCTAssertTrue(step.technique.isClassic,
                              "\(band) seed \(seed): variant technique on a classic board")
            }

            for cell in 0..<81 {
                XCTAssertEqual(p.puzzle[cell] == 0, p.puzzle[80 - cell] == 0,
                               "\(band) seed \(seed): asymmetric hole at \(cell)")
            }
        }
        report(band, seconds: seconds, hardest: hardest, givens: givens)
    }

    /// Printed, never asserted on. The distribution of *hardest technique* is
    /// reported beside the timings because it is the thing that tells a reader
    /// whether the band is one technique wearing a name or a real spread.
    private func report(
        _ band: Difficulty, seconds: [Double], hardest: [Technique: Int], givens: [Int]
    ) {
        let sorted = seconds.sorted()
        func percentile(_ q: Double) -> Double {
            sorted[min(sorted.count - 1, Int(q * Double(sorted.count)))]
        }
        var line = String(
            format: "%@ compose n=%d p50=%.2fs p90=%.2fs p95=%.2fs p99=%.2fs max=%.2fs mean=%.2fs",
            band.rawValue, sorted.count, percentile(0.5), percentile(0.9),
            percentile(0.95), percentile(0.99), sorted.last ?? 0,
            sorted.reduce(0, +) / Double(max(1, sorted.count)))
        let spread = hardest.sorted { $0.key.rank < $1.key.rank }
            .map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: " ")
        let clues = givens.sorted()
        line += "\n\(band.rawValue) hardest: \(spread)"
        line += String(format: "\n%@ givens: min=%d median=%d max=%d",
                       band.rawValue, clues.first ?? 0,
                       clues.isEmpty ? 0 : clues[clues.count / 2], clues.last ?? 0)
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
