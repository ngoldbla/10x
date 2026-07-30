// VariantConstraint.swift — the wire form of everything a variant adds on top
// of classic sudoku, and nothing else.
//
// **This file deliberately touches nothing that classic generation reads.**
// `SudokuGrid`, `Sudoku`, `BacktrackSolver` and `GeneratedPuzzle` are all
// unchanged by PRD-23: the golden corpus freezes the encoded bytes of
// `GeneratedPuzzle`, so a `constraints: []` field on it would move all 56
// classic hashes — every future daily re-rolled, every shared seed broken — for
// a field that is empty on every classic board. A variant board is a *sibling
// type* (`VariantPuzzle`) that carries a grid plus its constraints, which is the
// same shape as the `band` sibling key `nine.history` grew in PRD-17 and for the
// same reason.
//
// Decoding is tolerant end to end. Nothing here throws: an unreadable
// constraint becomes `.unrecognized`, holding its raw tree verbatim so a build
// that cannot interpret a future `.arrow` still round-trips it byte-for-byte
// rather than silently dropping it on the next write.
import Foundation
import CouchCore

/// A killer cage: a set of distinct cells whose digits are distinct and sum to
/// `sum`. Normalized on construction (cells sorted ascending) so two cages built
/// from the same set are `==` and hash alike.
public struct Cage: Sendable, Equatable, Hashable, Codable {
    /// Sorted ascending, distinct, all in `0..<81`. 1…9 cells.
    public let cells: [Int]
    public let sum: Int

    /// Fails rather than trapping on anything a cage cannot be: out-of-range or
    /// repeated cells, an empty or over-long region, or a sum no set of that
    /// many distinct digits can reach. The failability is what lets the decoder
    /// route a malformed future payload to `.unrecognized` instead of throwing.
    public init?(cells: [Int], sum: Int) {
        let sorted = Set(cells).sorted()
        guard sorted.count == cells.count,
              (1...9).contains(sorted.count),
              sorted.allSatisfy({ (0..<81).contains($0) }),
              (Cage.minimumSum(size: sorted.count)...Cage.maximumSum(size: sorted.count)).contains(sum)
        else { return nil }
        self.cells = sorted
        self.sum = sum
    }

    /// 1+2+…+n — the smallest sum `n` distinct digits can make.
    static func minimumSum(size: Int) -> Int { size * (size + 1) / 2 }
    /// 9+8+… — the largest.
    static func maximumSum(size: Int) -> Int { size * (19 - size) / 2 }
}

/// A thermometer: cells in bulb→tip order, strictly increasing.
public struct Thermometer: Sendable, Equatable, Hashable, Codable {
    /// Ordered bulb→tip. Order is meaning here, so unlike `Cage` this is *not*
    /// sorted — only checked for distinctness.
    public let cells: [Int]

    public init?(cells: [Int]) {
        guard (2...9).contains(cells.count),
              Set(cells).count == cells.count,
              cells.allSatisfy({ (0..<81).contains($0) })
        else { return nil }
        self.cells = cells
    }
}

/// One rule a variant adds. Codable with a `kind` discriminator; an unknown
/// discriminator — or a known one whose payload this build cannot validate —
/// decodes to `.unrecognized` carrying the raw tree, and re-encodes it verbatim.
///
/// The `.unrecognized` case is the whole reason this is hand-decoded. A
/// synthesized `Codable` enum throws on an unknown case, and `CouchStored`
/// discards the *entire blob* when a decode throws (see `BoardLibrary`'s
/// header) — so the day PRD-24 ships `.arrow`, an older build reading a shared
/// variant board would lose the board rather than the arrow.
public enum VariantConstraint: Sendable, Equatable, Hashable {
    case cage(Cage)
    case thermometer(Thermometer)
    /// A constraint this build cannot interpret, held verbatim. `kind` is the
    /// discriminator it announced (empty when the payload was not even an
    /// object with a string `kind`).
    case unrecognized(kind: String, payload: RawJSON)

    /// The wire discriminator. Stable — this is the l10n/coach identity too, in
    /// the same way `Technique`'s raw value is.
    public var kind: String {
        switch self {
        case .cage: return "cage"
        case .thermometer: return "thermometer"
        case .unrecognized(let kind, _): return kind
        }
    }

    /// Cells the constraint touches, for the ones this build understands.
    /// `.unrecognized` reports none: pretending to know its geometry would let
    /// the compiler below build peer tables out of a rule it cannot enforce.
    public var cells: [Int] {
        switch self {
        case .cage(let cage): return cage.cells
        case .thermometer(let thermo): return thermo.cells
        case .unrecognized: return []
        }
    }
}

// MARK: - Codable

extension VariantConstraint: Codable {

    private enum Key: String, CodingKey { case kind, cells, sum }

    public init(from decoder: Decoder) throws {
        // Decode the raw tree first, unconditionally. It costs a walk, and this
        // is not the classic path — no classic board ever holds a constraint —
        // so the walk buys total tolerance for free: whatever happens below,
        // `.unrecognized` already has the bytes to hand back.
        let raw = (try? RawJSON(from: decoder)) ?? .null
        guard case .object(let object) = raw,
              case .string(let kind)? = object["kind"] else {
            self = .unrecognized(kind: "", payload: raw)
            return
        }
        switch kind {
        case "cage":
            if let cells = VariantConstraint.intArray(object["cells"]),
               let sum = VariantConstraint.int(object["sum"]),
               let cage = Cage(cells: cells, sum: sum) {
                self = .cage(cage)
                return
            }
        case "thermometer":
            if let cells = VariantConstraint.intArray(object["cells"]),
               let thermo = Thermometer(cells: cells) {
                self = .thermometer(thermo)
                return
            }
        default:
            break
        }
        // A known discriminator whose payload does not validate lands here too,
        // and that is deliberate: a future build's `.cage` with an extra field
        // this one rejects is still *its* cage, and dropping it would be the
        // silent data loss the whole tolerance program exists to prevent.
        self = .unrecognized(kind: kind, payload: raw)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .cage(let cage):
            var c = encoder.container(keyedBy: Key.self)
            try c.encode("cage", forKey: .kind)
            try c.encode(cage.cells, forKey: .cells)
            try c.encode(cage.sum, forKey: .sum)
        case .thermometer(let thermo):
            var c = encoder.container(keyedBy: Key.self)
            try c.encode("thermometer", forKey: .kind)
            try c.encode(thermo.cells, forKey: .cells)
        case .unrecognized(_, let payload):
            // Verbatim, including the `kind` that is already inside the tree.
            try payload.encode(to: encoder)
        }
    }

    private static func int(_ value: RawJSON?) -> Int? {
        switch value {
        case .int(let v): return v
        case .uint(let v): return Int(exactly: v)
        default: return nil
        }
    }

    private static func intArray(_ value: RawJSON?) -> [Int]? {
        guard case .array(let items)? = value else { return nil }
        var result: [Int] = []
        result.reserveCapacity(items.count)
        for item in items {
            guard let v = int(item) else { return nil }
            result.append(v)
        }
        return result
    }
}

// MARK: - Variants

/// Which named ruleset a board is playing. Tolerant for the same reason
/// `VariantConstraint` is — a build that meets a future variant should hand it
/// back rather than lose the board.
public enum Variant: Sendable, Equatable, Hashable, Codable {
    case classic
    case killer
    case thermo
    case unrecognized(String)

    public var rawValue: String {
        switch self {
        case .classic: return "classic"
        case .killer: return "killer"
        case .thermo: return "thermo"
        case .unrecognized(let raw): return raw
        }
    }

    /// A fixed per-variant constant folded into seed derivation, so killer seed
    /// 1 and classic seed 1 are unrelated boards. Written out rather than
    /// hashed: `String.hashValue` is seeded per process in Swift, and a board
    /// that changes between launches is not a seeded board.
    var seedSalt: UInt64 {
        switch self {
        case .classic: return 0
        case .killer: return 0x4B49_4C4C_4552_0001
        case .thermo: return 0x5448_4552_4D4F_0002
        case .unrecognized: return 0xFFFF_FFFF_FFFF_FFFF
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "classic": self = .classic
        case "killer": self = .killer
        case "thermo": self = .thermo
        default: self = .unrecognized(rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? "classic"
        self.init(rawValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// A proven variant puzzle — the sibling of `GeneratedPuzzle`, never a field on
/// it (see this file's header). Same contract: grid, solution, the seed it came
/// from, and the full `SolveStep` trace the verifier produced, so the coach
/// speaks a killer board with no new machinery.
public struct VariantPuzzle: Sendable, Codable, Equatable {
    public let variant: Variant
    public let tier: VariantTier
    public let constraints: [VariantConstraint]
    public let puzzle: SudokuGrid
    public let solution: SudokuGrid
    /// The base seed the caller asked for — regenerating with the same
    /// (seed, variant, tier) yields a byte-identical puzzle.
    public let seed: UInt64
    public let steps: [SolveStep]

    public init(
        variant: Variant,
        tier: VariantTier,
        constraints: [VariantConstraint],
        puzzle: SudokuGrid,
        solution: SudokuGrid,
        seed: UInt64,
        steps: [SolveStep]
    ) {
        self.variant = variant
        self.tier = tier
        self.constraints = constraints
        self.puzzle = puzzle
        self.solution = solution
        self.seed = seed
        self.steps = steps
    }

    public var hardestTechnique: Technique? { steps.map(\.technique).max() }
    public var givenCount: Int { puzzle.givenCount }
    /// The compiled form the solver actually runs against.
    public var context: ConstraintContext { ConstraintContext.compile(constraints) }

    /// This board's grid lent to a `GeneratedPuzzle`, so it can become an ordinary
    /// `NineGame`.
    ///
    /// **This is PRD-24 §1's claim as a data structure.** A variant board's play
    /// state is the classic play state — the same 81 entries, the same pencil
    /// bitmasks, the same undo stack, the same timer, the same move log — which is
    /// why the rose, the coach, the replay, the debrief and the share card all work
    /// on a thermo board with no new code. The constraints are not *in* here; they
    /// live beside the board in `ChannelRules`, which is the same
    /// sibling-not-a-field rule that kept them out of `GeneratedPuzzle` in PRD-23.
    ///
    /// `tier` is mapped onto `Difficulty` because `GeneratedPuzzle` requires one
    /// and `SolveScore` and the stats slice read it. The mapping is lossy in one
    /// direction and harmlessly so: the authoritative tier is in
    /// `GameKind.channel` and in `ChannelRules`, both read in preference to this.
    /// Deliberately *not* the reverse mapping — a variant tier is not a classic
    /// band, which is why `VariantTier` exists as a separate enum at all.
    public var asGeneratedPuzzle: GeneratedPuzzle {
        GeneratedPuzzle(
            puzzle: puzzle,
            solution: solution,
            difficulty: tier.wireDifficulty,
            seed: seed,
            steps: steps)
    }
}

extension VariantTier {
    /// The `Difficulty` a tier is written as when a variant board has to wear one.
    ///
    /// Only the three 1.0 bands are used, and never a deep-end one: a killer or
    /// thermo board's hardest technique is a variant technique by construction, so
    /// `Difficulty.floor` comparisons against Nocturne or Abyss would be
    /// meaningless — the reasoning `VariantTier`'s own header gives for not being
    /// `Difficulty` in the first place.
    public var wireDifficulty: Difficulty {
        switch self {
        case .gentle: return .gentle
        case .steady: return .steady
        case .sharp: return .sharp
        }
    }
}

/// Killer's difficulty ladder. Deliberately *not* `Difficulty`: that enum's
/// three bands are defined by the classic technique chain and its raw values are
/// persisted inside `GeneratedPuzzle` (and so inside the golden hash), and a
/// killer board's "hardest technique" is a cage technique by construction, which
/// would make `Difficulty.floor` comparisons meaningless.
///
/// **The raw values are frozen, and they are also the localization identity**
/// (PRD-20): a `VariantTier` is persisted inside a variant board's channel and
/// `VariantTier.gentle` would be `variantTier.gentle.title` in the catalog.
///
/// There is deliberately no `title` here. It used to sit above `index` and
/// return English; the Engine compiles on Linux and must never reach a bundle,
/// so it does not get to name things.
/// `StringSealTests.testEngineNamesNothing` is what keeps it gone. Unlike
/// `Technique` and `Difficulty` it needed no replacement key: PRD-23's variant
/// surface has no shipping UI yet, so the property had zero call sites. Whoever
/// builds that UI adds `variantTier.<raw>.title` to `EnglishPhrases.table` and
/// re-runs `scripts/strings.py --build-catalog`; naming three tiers nobody can
/// see today would just be three strings a translator is paid for.
public enum VariantTier: String, CaseIterable, Sendable, Codable, Hashable {
    case gentle, steady, sharp

    var index: UInt64 {
        switch self {
        case .gentle: return 1
        case .steady: return 2
        case .sharp: return 3
        }
    }
}
