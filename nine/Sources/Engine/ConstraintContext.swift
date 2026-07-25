// ConstraintContext.swift — a puzzle's variant rules, compiled once, in the
// shape the solver's inner loops already want.
//
// The architectural claim PRD-23 makes, and the one the golden corpus is the
// proof of: **classic does not get a second code path.** `CandidateState` and
// every technique read `context.peers`, `context.units` and
// `context.initialCandidates` unconditionally, and for a classic board those
// properties return the exact static arrays from `Sudoku` that the same code
// used to name directly. Same arrays, same order, same bytes out. A killer board
// hands the identical loops a wider peer table and a set of cage tables, and
// nothing above them changes.
//
// Two design choices are load-bearing:
//
//  • **This is a `final class`, not a struct.** The context is passed to every
//    technique on every step; a struct of eight arrays costs eight
//    retain/releases per pass, a class costs one pointer. `isClassic` is then a
//    single pointer compare rather than an array walk.
//  • **`compile` returns the shared `classic` singleton for empty input**, and
//    `init` is private. That makes `isClassic` *total* — there is no way to
//    hold an empty-but-not-identical context — so an optimisation keyed on it
//    can never silently miss.
import Foundation
import CouchCore

public final class ConstraintContext: Sendable {

    /// The rules this context was compiled from, verbatim (including any
    /// `.unrecognized` ones).
    public let constraints: [VariantConstraint]

    // MARK: - The tables every technique reads

    /// For each cell, the cells that may not repeat its digit. Classic peers,
    /// plus cage-mates and thermometer-mates. Sorted ascending, like
    /// `Sudoku.peers`, and **identical to it** for a classic context.
    public let peers: [[Int]]

    /// The units a "one of each digit 1…9" argument may be made about.
    ///
    /// Always exactly `Sudoku.units`, including for killer — a cage is *not* a
    /// unit. `hiddenSingle` reasons "this digit must go somewhere in this unit",
    /// which is true of a row and false of a three-cell cage; adding cages here
    /// would place wrong digits that still pass the uniqueness prover, because
    /// the prover would be wrong in the same way. Cages enter as peers (above)
    /// and as their own tables (below). The property exists so the seam is here
    /// when a variant that *does* add a unit arrives — windoku, jigsaw.
    public let units: [[Int]]

    /// For each cell, the indices into `units` it belongs to.
    public let unitsOfCell: [[Int]]

    /// Starting candidate mask per cell before peer elimination. All nine digits
    /// everywhere for classic and killer; narrowed by position along a
    /// thermometer (the bulb cannot be a 9, the tip cannot be a 1).
    public let initialCandidates: [UInt16]

    // MARK: - Killer tables

    public let cages: [Cage]
    /// Cage index per cell, or -1.
    public let cageOfCell: [Int]
    /// For each cage, every set of distinct digits of the right size and sum, as
    /// a candidate bitmask. Precomputed because the count is tiny (≤ 42 for the
    /// worst size) and the alternative is re-deriving it inside the solve loop.
    public let cageCombinations: [[UInt16]]
    /// For each unit index, the cages lying entirely inside it (rule-of-45's
    /// innie half).
    public let cagesInsideUnit: [[Int]]
    /// For each unit index, the cages with at least one cell in it (the outie
    /// half needs the ones that poke out).
    public let cagesTouchingUnit: [[Int]]

    // MARK: - Thermometer tables

    public let thermometers: [Thermometer]
    /// For each cell, the `(thermometer index, position along it)` pairs it
    /// appears in. A cell can sit on more than one thermometer.
    public let thermoPositions: [[ThermoPosition]]

    public struct ThermoPosition: Sendable, Equatable, Hashable {
        public let thermometer: Int
        public let position: Int
    }

    // MARK: - Identity

    /// The shared empty context every classic board runs against. One instance
    /// for the whole process, so `isClassic` is a pointer compare.
    public static let classic = ConstraintContext()

    /// True for the shared classic context and *only* for it — `compile` funnels
    /// every empty constraint list here, and `init` is private.
    public var isClassic: Bool { self === ConstraintContext.classic }

    /// False when any constraint decoded as `.unrecognized`. A board carrying a
    /// rule this build cannot enforce must not be solved, proven unique or
    /// scored: the answer would be about a different puzzle. Callers gate on
    /// this rather than ignoring the rule.
    public let canEnforceEveryConstraint: Bool

    // MARK: - Construction

    /// Compile a rule set. Empty input returns the shared `classic` singleton.
    public static func compile(_ constraints: [VariantConstraint]) -> ConstraintContext {
        constraints.isEmpty ? .classic : ConstraintContext(constraints)
    }

    /// The classic context: every table is the static `Sudoku` original.
    private init() {
        constraints = []
        peers = Sudoku.peers
        units = Sudoku.units
        unitsOfCell = Sudoku.unitsOfCell
        initialCandidates = [UInt16](repeating: Sudoku.allDigitsMask, count: 81)
        cages = []
        cageOfCell = [Int](repeating: -1, count: 81)
        cageCombinations = []
        cagesInsideUnit = [[Int]](repeating: [], count: Sudoku.units.count)
        cagesTouchingUnit = [[Int]](repeating: [], count: Sudoku.units.count)
        thermometers = []
        thermoPositions = [[ThermoPosition]](repeating: [], count: 81)
        canEnforceEveryConstraint = true
    }

    private init(_ constraints: [VariantConstraint]) {
        self.constraints = constraints
        self.units = Sudoku.units
        self.unitsOfCell = Sudoku.unitsOfCell

        var cages: [Cage] = []
        var thermometers: [Thermometer] = []
        var enforceable = true
        for constraint in constraints {
            switch constraint {
            case .cage(let cage): cages.append(cage)
            case .thermometer(let thermo): thermometers.append(thermo)
            case .unrecognized: enforceable = false
            }
        }
        self.cages = cages
        self.thermometers = thermometers
        self.canEnforceEveryConstraint = enforceable

        // Cage membership. A cell in two cages is malformed input rather than a
        // rule — the later cage wins for the lookup table, but both still
        // contribute peers below, so the solve stays sound either way.
        var cageOfCell = [Int](repeating: -1, count: 81)
        for (index, cage) in cages.enumerated() {
            for cell in cage.cells { cageOfCell[cell] = index }
        }
        self.cageOfCell = cageOfCell
        self.cageCombinations = cages.map {
            ConstraintContext.combinations(size: $0.cells.count, sum: $0.sum)
        }

        // Peers: classic, plus every cell that may not repeat this one's digit.
        // A cage forbids repeats by definition. A thermometer is strictly
        // increasing, so its cells are pairwise distinct too — the ordering
        // itself is handled by `thermoBound`, but the distinctness belongs here
        // where every technique already benefits from it.
        var peerSets = (0..<81).map { Set(Sudoku.peers[$0]) }
        for group in cages.map(\.cells) + thermometers.map(\.cells) {
            for cell in group {
                peerSets[cell].formUnion(group)
                peerSets[cell].remove(cell)
            }
        }
        self.peers = peerSets.map { $0.sorted() }

        // Per-unit cage indices, for rule-of-45.
        var inside = [[Int]](repeating: [], count: Sudoku.units.count)
        var touching = [[Int]](repeating: [], count: Sudoku.units.count)
        for (unitIndex, unit) in Sudoku.units.enumerated() {
            let members = Set(unit)
            for (cageIndex, cage) in cages.enumerated() {
                let hits = cage.cells.count(where: { members.contains($0) })
                if hits == 0 { continue }
                touching[unitIndex].append(cageIndex)
                if hits == cage.cells.count { inside[unitIndex].append(cageIndex) }
            }
        }
        self.cagesInsideUnit = inside
        self.cagesTouchingUnit = touching

        // Thermometer positions, and the static bound they put on each cell:
        // the cell at index i has at least i cells strictly below it and
        // (count-1-i) strictly above, so it cannot be smaller than i+1 nor
        // larger than 9-(count-1-i).
        var thermoPositions = [[ThermoPosition]](repeating: [], count: 81)
        var initial = [UInt16](repeating: Sudoku.allDigitsMask, count: 81)
        for (index, thermo) in thermometers.enumerated() {
            for (position, cell) in thermo.cells.enumerated() {
                thermoPositions[cell].append(
                    ThermoPosition(thermometer: index, position: position))
                let low = position + 1
                let high = 9 - (thermo.cells.count - 1 - position)
                initial[cell] &= ConstraintContext.rangeMask(low...high)
            }
        }
        self.thermoPositions = thermoPositions
        self.initialCandidates = initial
    }

    // MARK: - Helpers

    /// Bitmask of the digits in `range`.
    static func rangeMask(_ range: ClosedRange<Int>) -> UInt16 {
        var mask: UInt16 = 0
        for d in range where (1...9).contains(d) { mask |= Sudoku.bit(d) }
        return mask
    }

    /// Every set of `size` distinct digits from 1…9 summing to `sum`, as
    /// candidate bitmasks, in the DFS order the digits are chosen. Small by
    /// construction: the largest bucket is 42 sets (size 4 or 5).
    static func combinations(size: Int, sum: Int) -> [UInt16] {
        guard (1...9).contains(size),
              (Cage.minimumSum(size: size)...Cage.maximumSum(size: size)).contains(sum)
        else { return [] }
        var result: [UInt16] = []
        func walk(_ digit: Int, _ remaining: Int, _ left: Int, _ mask: UInt16) {
            if left == 0 {
                if remaining == 0 { result.append(mask) }
                return
            }
            // Prune on the smallest and largest totals still reachable from
            // here: `left` distinct digits, none below `digit`, none above 9.
            guard digit + left - 1 <= 9 else { return }
            let smallest = (digit...(digit + left - 1)).reduce(0, +)
            let largest = ((10 - left)...9).reduce(0, +)
            guard remaining >= smallest, remaining <= largest else { return }
            for d in digit...9 where d <= remaining {
                walk(d + 1, remaining - d, left - 1, mask | Sudoku.bit(d))
            }
        }
        walk(1, sum, size, 0)
        return result
    }
}
