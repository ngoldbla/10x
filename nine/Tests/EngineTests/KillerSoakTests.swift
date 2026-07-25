// KillerSoakTests — the killer distribution, and the compose numbers PRD-23
// reports. Opt-in, because it cannot live in `swift test`.
//
// **Every number here is a Release number, and that is not optional.** `swift
// test` builds Debug and generation runs ~50× slower there (measured, PRD-17:
// sharp seed 3004, 0.428 s release against 30.8 s debug). A Debug compose figure
// is off by more than an order of magnitude, which is the difference between a
// tier shipping and not. `scripts/killer-scan.sh` forces the configuration.
//
//     nine/scripts/killer-scan.sh 200          # the p95 table, per tier
//     NINE_KILLER_SOAK=200 swift test -c release --filter KillerSoak
//     NINE_KILLER_DIAG=200 swift test -c release --filter KillerSoak
//
// The diagnostic lane exists because "Sharp does not compose" is a claim that
// needs a cause attached: it separates *is the zero-given board even uniquely
// determined by its cages* from *can our technique chain close it*. Those want
// different fixes, and guessing which one it is would be how a tier gets shipped
// on a hope.
import XCTest
import Foundation
import CouchCore
@testable import NineEngine

final class KillerSoakTests: XCTestCase {

    private var soakSeeds: Int {
        Int(ProcessInfo.processInfo.environment["NINE_KILLER_SOAK"] ?? "0") ?? 0
    }

    private var diagSeeds: Int {
        Int(ProcessInfo.processInfo.environment["NINE_KILLER_DIAG"] ?? "0") ?? 0
    }

    /// Compose every tier over the same seeds, hold each board to everything its
    /// band claims, and print the distribution. Assertions are on the **product**
    /// — a compose-time threshold in a test is a flake on shared CI hardware,
    /// and worse, it is a metric that improves when the feature breaks (PRD-17's
    /// attempt-budget bug is the whole story).
    func testEveryKillerBoardMeetsTheBandItClaims() throws {
        let count = soakSeeds
        try XCTSkipIf(count == 0, "set NINE_KILLER_SOAK=<n> (release config) to run the soak")

        for tier in VariantTier.allCases {
            let band = tier.killerBand
            var seconds: [Double] = []
            var failures = 0
            var givens: [Int] = []
            var cageCells: [Int] = []
            var techniqueUse: [Technique: Int] = [:]
            var boardsUsing: [Technique: Int] = [:]

            for seed in 1...UInt64(count) {
                let started = Date()
                let composed = VariantGenerator.generate(seed: seed, variant: .killer, tier: tier)
                let elapsed = Date().timeIntervalSince(started)
                guard let puzzle = composed else {
                    failures += 1
                    continue
                }
                seconds.append(elapsed)
                givens.append(puzzle.givenCount)

                let context = puzzle.context
                cageCells.append(contentsOf: context.cages.map(\.cells.count))
                for technique in Set(puzzle.steps.map(\.technique)) {
                    boardsUsing[technique, default: 0] += 1
                }
                for step in puzzle.steps { techniqueUse[step.technique, default: 0] += 1 }
                XCTAssertEqual(
                    ConstraintBacktrackSolver.countSolutions(of: puzzle.puzzle, context: context),
                    .unique(puzzle.solution), "\(tier) seed \(seed): not unique under its cages")

                let outcome = LogicSolver.solve(
                    puzzle.puzzle, allowed: band.allowed, context: context)
                XCTAssertTrue(outcome.solved, "\(tier) seed \(seed): outside its chain")
                XCTAssertEqual(outcome.steps, puzzle.steps, "\(tier) seed \(seed): trace drifted")
                XCTAssertLessThanOrEqual(puzzle.givenCount, band.maxGivens, "\(tier) seed \(seed)")
                XCTAssertTrue(band.admits(steps: puzzle.steps, givens: puzzle.givenCount),
                              "\(tier) seed \(seed): the cages are decoration")

                for cage in context.cages {
                    let digits = cage.cells.map { puzzle.solution[$0] }
                    XCTAssertEqual(Set(digits).count, digits.count, "\(tier) seed \(seed)")
                    XCTAssertEqual(digits.reduce(0, +), cage.sum, "\(tier) seed \(seed)")
                }
            }
            report(tier, seconds: seconds, failures: failures, attempted: count)
            reportShape(tier, givens: givens, cageCells: cageCells,
                        techniqueUse: techniqueUse, boardsUsing: boardsUsing,
                        boards: seconds.count)
        }
    }

    /// Why a tier fails, separated into the two causes that want different
    /// fixes — and swept over the one generator knob that plausibly moves them.
    ///
    ///   • **Is the zero-given board even uniquely determined by its cages?**
    ///     If not, no technique will ever close it and the fix is cage design,
    ///     not a solver PRD.
    ///   • **If it is, how far does the chain get before stalling, and on what?**
    ///     That is the technique-coverage question, and the answer names the
    ///     technique the next PRD has to follow.
    ///
    /// The knob is cage size, because the constraint a cage carries is wildly
    /// size-dependent: a two-cell cage summing to 17 admits exactly {8,9}, while
    /// a five-cell cage summing to 25 admits most of the digit set.
    func testDiagnoseWhereTheChainStalls() throws {
        let count = diagSeeds
        try XCTSkipIf(count == 0, "set NINE_KILLER_DIAG=<n> (release config) to diagnose")

        for maxSize in [2, 3, 4, 5] {
            var unique = 0
            var chainClosed = 0
            var solutionCounts: [Int] = []
            var reached: [Int] = []
            var stalls: [Technique: Int] = [:]

            for seed in 1...UInt64(count) {
                var rng = SplitMix64(seed: VariantGenerator.attemptSeed(
                    seed, variant: .killer, tier: .sharp, attempt: 0))
                let solution = BacktrackSolver.completeGrid(seed: rng.next())
                let cages = CageTiling.cages(of: solution, using: &rng, maxSize: maxSize)
                let context = ConstraintContext.compile(cages.map(VariantConstraint.cage))

                // How ambiguous, not merely whether. "Two solutions" and "twenty"
                // are the difference between a handful of givens fixing it and
                // the layout being hopeless.
                let capped = ConstraintBacktrackSolver.countSolutions(
                    of: SudokuGrid(), context: context, limit: 20)
                switch capped {
                case .unique: unique += 1; solutionCounts.append(1)
                case .multiple: solutionCounts.append(20)
                default: solutionCounts.append(0)
                }

                let outcome = LogicSolver.solve(
                    SudokuGrid(), allowed: Technique.allCases, context: context)
                if outcome.solved { chainClosed += 1 }
                reached.append(81 - outcome.finalGrid.emptyCount)
                if let last = outcome.steps.last?.technique { stalls[last, default: 0] += 1 }
            }

            let filled = reached.sorted()
            let sizes = solutionCounts.sorted()
            let line = """
                killer diag maxSize=\(maxSize) n=\(count) \
                uniqueFromCagesAlone=\(unique) \
                solutionsAtZeroGivens p50=\(sizes[sizes.count / 2]) \
                chainClosedFromCagesAlone=\(chainClosed) \
                cellsFilled p50=\(filled[filled.count / 2]) max=\(filled.last ?? 0) \
                lastStepBeforeStall=\(stalls.map { "\($0.key.rawValue):\($0.value)" }.sorted().joined(separator: ","))
                """
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
    }

    /// What the boards are actually *made of*. A tier that composes in 20 ms and
    /// hands out a board every naked single closes is not a tier, and the timing
    /// table cannot tell you that — `boardsUsing` is the column that can.
    private func reportShape(
        _ tier: VariantTier, givens: [Int], cageCells: [Int],
        techniqueUse: [Technique: Int], boardsUsing: [Technique: Int], boards: Int
    ) {
        let sortedGivens = givens.sorted()
        let sortedCages = cageCells.sorted()
        let mix = Technique.allCases
            .filter { boardsUsing[$0] != nil }
            .map { "\($0.rawValue) \(boardsUsing[$0] ?? 0)/\(boards) boards, \(techniqueUse[$0] ?? 0) steps" }
            .joined(separator: " | ")
        let line = """
            killer \(tier.rawValue) shape             givens p50=\(sortedGivens.isEmpty ? -1 : sortedGivens[sortedGivens.count / 2])             max=\(sortedGivens.last ?? -1)             cageSize p50=\(sortedCages.isEmpty ? -1 : sortedCages[sortedCages.count / 2])             cages=\(cageCells.count / max(1, boards))             :: \(mix)
            """
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    /// Printed, never asserted on — see the header on why a clock threshold in a
    /// test is the wrong gate. The success *rate*, though, is a product fact and
    /// the number that decides whether a tier ships.
    private func report(_ tier: VariantTier, seconds: [Double], failures: Int, attempted: Int) {
        let sorted = seconds.sorted()
        func percentile(_ q: Double) -> Double {
            sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(q * Double(sorted.count)))]
        }
        let line = String(
            format: "killer %@ n=%d composed=%d failed=%d p50=%.2fs p90=%.2fs p95=%.2fs p99=%.2fs max=%.2fs mean=%.2fs",
            tier.rawValue, attempted, sorted.count, failures,
            percentile(0.5), percentile(0.9), percentile(0.95), percentile(0.99),
            sorted.last ?? 0, sorted.reduce(0, +) / Double(max(1, sorted.count)))
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
