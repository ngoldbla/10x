// ThermoSoakTests — the thermo distribution, and the compose numbers PRD-24
// reports. Opt-in, because it cannot live in `swift test`.
//
// **Every number here is a Release number, and that is not optional.** `swift
// test` builds Debug and generation runs ~50× slower there (measured, PRD-17:
// sharp seed 3004, 0.428 s release against 30.8 s debug). A Debug compose figure
// is off by more than an order of magnitude, which is the difference between a
// tier shipping and not. `scripts/thermo-scan.sh` forces the configuration.
//
//     nine/scripts/thermo-scan.sh 200          # the p95 table, per tier
//     NINE_THERMO_SOAK=200 swift test -c release --filter ThermoSoak
//     NINE_THERMO_DIAG=200 swift test -c release --filter ThermoSoak
//
// The diagnostic lane is the part worth reading twice, and it is **not** a copy
// of killer's. Killer's diag separates two causes — *is the zero-given board even
// unique* versus *can the chain close it* — because those were the only two ways
// a killer tier could fail.
//
// Thermo has a **third**, and it is the one the ruleset makes likely rather than
// unlikely. A thermo band's clue ceiling has to stay well above zero (a tube
// layout covers the board partially by construction and cannot determine a grid
// on its own), and a board with two dozen givens is a board the *classic* chain
// may well close on its own — in which case the tubes are decoration, `admits`
// rejects on `minVariantSteps`, and the tier fails for a reason that looks
// nothing like "not unique" and nothing like "chain too weak". Guessing between
// three causes is worse than guessing between two, so this lane counts the
// rejection reason directly instead of inferring it.
import XCTest
import Foundation
import CouchCore
@testable import NineEngine

final class ThermoSoakTests: XCTestCase {

    private var soakSeeds: Int {
        Int(ProcessInfo.processInfo.environment["NINE_THERMO_SOAK"] ?? "0") ?? 0
    }

    private var diagSeeds: Int {
        Int(ProcessInfo.processInfo.environment["NINE_THERMO_DIAG"] ?? "0") ?? 0
    }

    /// Compose every tier over the same seeds, hold each board to everything its
    /// band claims, and print the distribution. Assertions are on the **product**
    /// — a compose-time threshold in a test is a flake on shared CI hardware,
    /// and worse, it is a metric that improves when the feature breaks (PRD-17's
    /// attempt-budget bug is the whole story).
    func testEveryThermoBoardMeetsTheBandItClaims() throws {
        let count = soakSeeds
        try XCTSkipIf(count == 0, "set NINE_THERMO_SOAK=<n> (release config) to run the soak")

        for tier in VariantTier.allCases {
            let band = tier.thermoBand
            var seconds: [Double] = []
            var failures = 0
            var givens: [Int] = []
            var tubeCells: [Int] = []
            var tubes: [Int] = []
            var techniqueUse: [Technique: Int] = [:]
            var boardsUsing: [Technique: Int] = [:]

            for seed in 1...UInt64(count) {
                let started = Date()
                let composed = VariantGenerator.generate(seed: seed, variant: .thermo, tier: tier)
                let elapsed = Date().timeIntervalSince(started)
                guard let puzzle = composed else {
                    failures += 1
                    continue
                }
                seconds.append(elapsed)
                givens.append(puzzle.givenCount)

                let context = puzzle.context
                XCTAssertTrue(context.cages.isEmpty, "\(tier) seed \(seed): a thermo board has no cages")
                tubes.append(context.thermometers.count)
                tubeCells.append(contentsOf: context.thermometers.map(\.cells.count))
                for technique in Set(puzzle.steps.map(\.technique)) {
                    boardsUsing[technique, default: 0] += 1
                }
                for step in puzzle.steps { techniqueUse[step.technique, default: 0] += 1 }

                XCTAssertEqual(
                    ConstraintBacktrackSolver.countSolutions(of: puzzle.puzzle, context: context),
                    .unique(puzzle.solution), "\(tier) seed \(seed): not unique under its tubes")

                let outcome = LogicSolver.solve(
                    puzzle.puzzle, allowed: band.allowed, context: context)
                XCTAssertTrue(outcome.solved, "\(tier) seed \(seed): outside its chain")
                XCTAssertEqual(outcome.steps, puzzle.steps, "\(tier) seed \(seed): trace drifted")
                XCTAssertLessThanOrEqual(puzzle.givenCount, band.maxGivens, "\(tier) seed \(seed)")
                XCTAssertTrue(band.admits(steps: puzzle.steps, givens: puzzle.givenCount),
                              "\(tier) seed \(seed): the tubes are decoration")

                // Every tube increases along the solution it was read off. This
                // is the constraint itself, and the one whose violation would be
                // invisible: a wrong tube eliminates the true digit and every
                // later proof is correct reasoning about an impossible board.
                for thermo in context.thermometers {
                    let digits = thermo.cells.map { puzzle.solution[$0] }
                    XCTAssertEqual(digits, digits.sorted(), "\(tier) seed \(seed): tube not increasing")
                    XCTAssertEqual(Set(digits).count, digits.count, "\(tier) seed \(seed)")
                }
            }
            report(tier, seconds: seconds, failures: failures, attempted: count)
            reportShape(tier, givens: givens, tubes: tubes, tubeCells: tubeCells,
                        techniqueUse: techniqueUse, boardsUsing: boardsUsing,
                        boards: seconds.count)
        }
    }

    /// Why a tier fails, counted rather than inferred, over the three causes that
    /// want three different fixes:
    ///
    ///   • **`digExhausted`** — the chain never closed inside the clue ceiling.
    ///     The fix is a higher ceiling or a wider chain.
    ///   • **`notUnique` / `chainMissed`** — the proof stage disagreed with the
    ///     dig. Rare, and a bug rather than a tuning problem if it is common.
    ///   • **`decoration`** — the board *is* well-formed and closes, but not
    ///     enough of the trace was thermo reasoning. This is the thermo-specific
    ///     one: a two-dozen-given board is one the classic chain may close on its
    ///     own, and the fix is fewer givens or more coverage, **not** a wider
    ///     chain. A wider chain makes this cause worse.
    ///
    /// It also reports how many thermoBound steps the *accepted* traces carried,
    /// because `minVariantSteps` is only a sensible number if the distribution it
    /// cuts is known.
    func testDiagnoseWhyATierFails() throws {
        let count = diagSeeds
        try XCTSkipIf(count == 0, "set NINE_THERMO_DIAG=<n> (release config) to diagnose")

        for tier in VariantTier.allCases {
            let band = tier.thermoBand
            var digExhausted = 0, notUnique = 0, chainMissed = 0, decoration = 0, accepted = 0
            var noRules = 0
            var variantSteps: [Int] = []
            var tubeCounts: [Int] = []

            // One attempt per seed — the same first attempt `generate` would
            // make — so the reason counts are per *attempt* and comparable with
            // the budget, rather than per seed and hiding a 3,000-deep retry.
            for seed in 1...UInt64(count) {
                var rng = SplitMix64(seed: VariantGenerator.attemptSeed(
                    seed, variant: .thermo, tier: tier, attempt: 0))
                let solution = BacktrackSolver.completeGrid(seed: rng.next())
                let constraints = VariantGenerator.constraints(
                    for: band.shape, of: solution, using: &rng)
                guard !constraints.isEmpty else { noRules += 1; continue }
                tubeCounts.append(constraints.count)
                let context = ConstraintContext.compile(constraints)

                var order = Array(0..<81)
                for i in stride(from: order.count - 1, to: 0, by: -1) {
                    let j = rng.nextInt(below: i + 1)
                    if i != j { order.swapAt(i, j) }
                }

                var puzzle = SudokuGrid()
                var added: [Int] = []
                var outcome = LogicSolver.solve(puzzle, allowed: band.allowed, context: context)
                var exhausted = false
                while !outcome.solved {
                    guard added.count < band.maxGivens else { exhausted = true; break }
                    guard let cell = order.first(where: { outcome.finalGrid[$0] == 0 }) else {
                        exhausted = true; break
                    }
                    puzzle[cell] = solution[cell]
                    added.append(cell)
                    outcome = LogicSolver.solve(puzzle, allowed: band.allowed, context: context)
                }
                if exhausted { digExhausted += 1; continue }

                for cell in added.reversed() {
                    let saved = puzzle[cell]
                    puzzle[cell] = 0
                    let trimmed = LogicSolver.solve(puzzle, allowed: band.allowed, context: context)
                    if trimmed.solved { outcome = trimmed } else { puzzle[cell] = saved }
                }

                guard case .unique(let proven)? = ConstraintBacktrackSolver.countSolutions(
                    of: puzzle, context: context, limit: 2), proven == solution else {
                    notUnique += 1; continue
                }
                let final = LogicSolver.solve(puzzle, allowed: band.allowed, context: context)
                guard final.solved, final.finalGrid == solution else { chainMissed += 1; continue }
                let variant = final.steps.count(where: { !$0.technique.isClassic })
                variantSteps.append(variant)
                if band.admits(steps: final.steps, givens: puzzle.givenCount) {
                    accepted += 1
                } else {
                    decoration += 1
                }
            }

            let sortedSteps = variantSteps.sorted()
            let sortedTubes = tubeCounts.sorted()
            let line = """
                thermo diag \(tier.rawValue) n=\(count) \
                accepted=\(accepted) digExhausted=\(digExhausted) \
                notUnique=\(notUnique) chainMissed=\(chainMissed) decoration=\(decoration) \
                noRules=\(noRules) \
                minVariantSteps=\(band.minVariantSteps) \
                variantStepsInClosedBoards p50=\(sortedSteps.isEmpty ? -1 : sortedSteps[sortedSteps.count / 2]) \
                p90=\(sortedSteps.isEmpty ? -1 : sortedSteps[min(sortedSteps.count - 1, (sortedSteps.count * 9) / 10)]) \
                max=\(sortedSteps.last ?? -1) \
                tubes p50=\(sortedTubes.isEmpty ? -1 : sortedTubes[sortedTubes.count / 2])
                """
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
    }

    /// What the boards are actually *made of*. A tier that composes in 20 ms and
    /// hands out a board every naked single closes is not a tier, and the timing
    /// table cannot tell you that — `boardsUsing` is the column that can.
    private func reportShape(
        _ tier: VariantTier, givens: [Int], tubes: [Int], tubeCells: [Int],
        techniqueUse: [Technique: Int], boardsUsing: [Technique: Int], boards: Int
    ) {
        let sortedGivens = givens.sorted()
        let sortedCells = tubeCells.sorted()
        let sortedTubes = tubes.sorted()
        let mix = Technique.allCases
            .filter { boardsUsing[$0] != nil }
            .map { "\($0.rawValue) \(boardsUsing[$0] ?? 0)/\(boards) boards, \(techniqueUse[$0] ?? 0) steps" }
            .joined(separator: " | ")
        let line = """
            thermo \(tier.rawValue) shape \
            givens p50=\(sortedGivens.isEmpty ? -1 : sortedGivens[sortedGivens.count / 2]) \
            max=\(sortedGivens.last ?? -1) \
            tubes p50=\(sortedTubes.isEmpty ? -1 : sortedTubes[sortedTubes.count / 2]) \
            tubeLen p50=\(sortedCells.isEmpty ? -1 : sortedCells[sortedCells.count / 2]) \
            max=\(sortedCells.last ?? -1) \
            cellsOnATube=\(tubeCells.reduce(0, +) / max(1, boards)) \
            :: \(mix)
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
            format: "thermo %@ n=%d composed=%d failed=%d p50=%.2fs p90=%.2fs p95=%.2fs p99=%.2fs max=%.2fs mean=%.2fs",
            tier.rawValue, attempted, sorted.count, failures,
            percentile(0.5), percentile(0.9), percentile(0.95), percentile(0.99),
            sorted.last ?? 0, sorted.reduce(0, +) / Double(max(1, sorted.count)))
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
