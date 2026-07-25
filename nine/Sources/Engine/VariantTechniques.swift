// VariantTechniques.swift — cage and thermometer reasoning, as ordinary
// `Technique` cases emitting ordinary `SolveStep`s.
//
// That framing is the point of PRD-23 rather than an implementation detail: the
// Coach (PRD-25), the hint substrate (PRD-11) and the replay classifier
// (PRD-26) all consume `[SolveStep]`, so a variant that expresses itself in the
// same records is spoken by all three for free. Nothing here is a new kind of
// object.
//
// **The soundness rule every function in this file obeys.** A technique may only
// place a digit that is forced and may only eliminate a candidate that is
// impossible. The asymmetry matters: over-approximating what is possible costs
// eliminations we could have made, while under-approximating places wrong digits
// that then sail through the uniqueness prover, because the prover would have to
// be wrong in the same way to disagree. So every feasibility filter below is a
// strictly *necessary* condition — when in doubt, keep the possibility.
import Foundation
import CouchCore

extension LogicSolver {

    // MARK: - Cage single

    /// A cage with exactly one unsolved cell forces that cell: the digit is the
    /// cage sum minus what is already in it. The killer analogue of a naked
    /// single, and just as trivial for a player to see.
    static func cageSingle(_ state: CandidateState) -> SolveStep? {
        let context = state.context
        for cage in context.cages {
            var remaining = cage.sum
            var open = -1
            var openCount = 0
            for cell in cage.cells {
                let value = state.values[cell]
                if value == 0 {
                    open = cell
                    openCount += 1
                    if openCount > 1 { break }
                } else {
                    remaining -= value
                }
            }
            guard openCount == 1, (1...9).contains(remaining) else { continue }
            // A digit outside the cell's candidates means the position is
            // already contradictory. Placing it anyway would hand the verifier a
            // grid that disagrees with the solution; leave the contradiction for
            // `isStuckDead` to report.
            guard state.candidates[open] & Sudoku.bit(remaining) != 0 else { continue }
            return SolveStep(
                technique: .cageSingle,
                cells: cage.cells,
                digits: [remaining],
                placement: Placement(cell: open, digit: remaining)
            )
        }
        return nil
    }

    // MARK: - Thermometer bounds

    /// A thermometer is strictly increasing bulb→tip, so each cell is bounded
    /// below by everything before it and above by everything after it. Two
    /// sweeps — forward for the floor, backward for the ceiling — and anything
    /// outside the resulting window is impossible.
    ///
    /// The *static* half of this (the bulb of a 3-cell thermo cannot exceed 7)
    /// is already baked into `context.initialCandidates`; what this adds is the
    /// dynamic half, which tightens as the solve proceeds.
    static func thermoBound(_ state: CandidateState) -> SolveStep? {
        for thermo in state.context.thermometers {
            let cells = thermo.cells
            var low = [Int](repeating: 0, count: cells.count)
            var high = [Int](repeating: 0, count: cells.count)

            var floor = 0
            var dead = false
            for (index, cell) in cells.enumerated() {
                let value = state.values[cell]
                let smallest: Int
                if value != 0 {
                    smallest = value
                } else {
                    let mask = state.candidates[cell]
                    if mask == 0 { dead = true; break }
                    smallest = mask.trailingZeroBitCount
                }
                floor = max(floor + 1, smallest)
                low[index] = floor
            }
            if dead { continue }

            var ceiling = 10
            for index in stride(from: cells.count - 1, through: 0, by: -1) {
                let cell = cells[index]
                let value = state.values[cell]
                let largest: Int
                if value != 0 {
                    largest = value
                } else {
                    let mask = state.candidates[cell]
                    largest = 15 - mask.leadingZeroBitCount // highest set bit
                }
                ceiling = min(ceiling - 1, largest)
                high[index] = ceiling
            }

            var eliminations: [Elimination] = []
            var digits: Set<Int> = []
            for (index, cell) in cells.enumerated() where state.values[cell] == 0 {
                let window = low[index] <= high[index]
                    ? ConstraintContext.rangeMask(low[index]...high[index])
                    : 0
                let doomed = state.candidates[cell] & ~window
                for digit in Sudoku.digits(in: doomed) {
                    eliminations.append(Elimination(cell: cell, digit: digit))
                    digits.insert(digit)
                }
            }
            if !eliminations.isEmpty {
                return SolveStep(
                    technique: .thermoBound,
                    cells: cells,
                    digits: digits.sorted(),
                    eliminations: eliminations
                )
            }
        }
        return nil
    }

    // MARK: - Rule of 45 (innies and outies)

    /// Every row, column and box holds 1…9, so it sums to 45. When the cages
    /// covering a unit leave exactly one cell uncounted, that cell is forced.
    ///
    /// Two shapes, and they are the same equation read in two directions:
    ///   • **innie** — the cages lie entirely inside the unit and cover eight of
    ///     its nine cells; the ninth is `45 − Σcages`.
    ///   • **outie** — the cages cover the whole unit and spill over by exactly
    ///     one cell; that cell is `Σcages − 45`.
    ///
    /// Requires `cagesAreDisjoint`: the sum of overlapping cages double-counts a
    /// cell, and the digit that falls out is wrong while still looking proven.
    static func innieOutie(_ state: CandidateState) -> SolveStep? {
        let context = state.context
        guard context.cagesAreDisjoint, !context.cages.isEmpty else { return nil }

        for unitIndex in context.units.indices {
            let unit = context.units[unitIndex]
            let members = Set(unit)

            // The distinct cages covering any cell of this unit, and the cells
            // of the unit no cage covers at all.
            var covering: Set<Int> = []
            var uncaged: [Int] = []
            for cell in unit {
                let cage = context.cageOfCell[cell]
                if cage == -1 { uncaged.append(cell) } else { covering.insert(cage) }
            }
            guard !covering.isEmpty else { continue }

            var total = 0
            var spill: [Int] = []
            for cageIndex in covering.sorted() {
                let cage = context.cages[cageIndex]
                total += cage.sum
                spill.append(contentsOf: cage.cells.filter { !members.contains($0) })
            }

            // Σunit = 45 = Σcages − Σspill + Σuncaged, so exactly one unknown on
            // either side is a forced placement and anything else is not.
            let target: Int
            let cell: Int
            switch (uncaged.count, spill.count) {
            case (1, 0):
                cell = uncaged[0]
                target = 45 - total
            case (0, 1):
                cell = spill[0]
                target = total - 45
            default:
                continue
            }
            guard state.values[cell] == 0,
                  (1...9).contains(target),
                  state.candidates[cell] & Sudoku.bit(target) != 0 else { continue }

            return SolveStep(
                technique: .innieOutie,
                cells: unit,
                digits: [target],
                placement: Placement(cell: cell, digit: target)
            )
        }
        return nil
    }

    // MARK: - Cage combination

    /// A cage of *n* cells summing to *s* can only hold one of a small, fixed
    /// set of digit combinations (precomputed in `context.cageCombinations`).
    /// Discard the combinations the current position rules out, and any digit
    /// that survives in none of the rest is impossible in that cell.
    ///
    /// The two filters applied to a combination are both *necessary* conditions
    /// for it to be realisable, so rejecting on them is sound. What this
    /// deliberately does **not** do is a full bipartite matching: a combination
    /// that passes both filters and is still unassignable simply survives, which
    /// costs an elimination and never causes a wrong one.
    static func cageCombination(_ state: CandidateState) -> SolveStep? {
        let context = state.context
        for (cageIndex, cage) in context.cages.enumerated() {
            var placedMask: UInt16 = 0
            var open: [Int] = []
            for cell in cage.cells {
                let value = state.values[cell]
                if value == 0 { open.append(cell) } else { placedMask |= Sudoku.bit(value) }
            }
            guard open.count >= 2 else { continue } // one open cell is `cageSingle`'s

            // Union, over every combination the position still allows, of what
            // each open cell could take under it.
            var allowed = [UInt16](repeating: 0, count: open.count)
            for combination in context.cageCombinations[cageIndex] {
                // Everything already in the cage has to be part of it.
                guard combination & placedMask == placedMask else { continue }
                let free = combination & ~placedMask
                var usable: UInt16 = 0
                var reachable = true
                for cell in open {
                    let hit = free & state.candidates[cell]
                    if hit == 0 { reachable = false; break }
                    usable |= hit
                }
                // Necessary conditions, both ways round: every open cell can
                // take one of the free digits, and every free digit has
                // somewhere to go. A combination failing either is impossible.
                guard reachable, usable == free else { continue }
                for (slot, cell) in open.enumerated() {
                    allowed[slot] |= free & state.candidates[cell]
                }
            }

            var eliminations: [Elimination] = []
            var digits: Set<Int> = []
            for (slot, cell) in open.enumerated() {
                let doomed = state.candidates[cell] & ~allowed[slot]
                for digit in Sudoku.digits(in: doomed) {
                    eliminations.append(Elimination(cell: cell, digit: digit))
                    digits.insert(digit)
                }
            }
            if !eliminations.isEmpty {
                return SolveStep(
                    technique: .cageCombination,
                    cells: cage.cells,
                    digits: digits.sorted(),
                    eliminations: eliminations
                )
            }
        }
        return nil
    }
}
