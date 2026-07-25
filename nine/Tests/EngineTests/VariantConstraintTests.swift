// VariantConstraintTests — the wire form and the compiled form.
//
// Two properties carry most of the weight here. First, **tolerance**: nothing in
// the constraint decode may throw, because `CouchStored` discards the whole blob
// when a decode throws and a shared variant board would take the player's
// library with it. Second, **the classic identity**: `ConstraintContext.classic`
// must hand back the literal `Sudoku` tables, because that is the mechanism by
// which the golden corpus stays byte-identical through the variant refactor.
import XCTest
import Foundation
@testable import NineEngine

final class VariantConstraintTests: XCTestCase {

    private func encoded(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Cage validation

    func testCageNormalizesAndValidates() {
        let cage = Cage(cells: [10, 1, 0], sum: 12)
        XCTAssertEqual(cage?.cells, [0, 1, 10], "cells sort so two cages of the same set are equal")

        XCTAssertNil(Cage(cells: [0, 0, 1], sum: 6), "repeated cell")
        XCTAssertNil(Cage(cells: [], sum: 0), "empty region")
        XCTAssertNil(Cage(cells: Array(0...9), sum: 45), "ten cells cannot hold distinct digits")
        XCTAssertNil(Cage(cells: [0, 81], sum: 5), "cell out of range")
        XCTAssertNil(Cage(cells: [0, 1], sum: 2), "two distinct digits cannot sum to 2")
        XCTAssertNil(Cage(cells: [0, 1], sum: 18), "two distinct digits cannot sum to 18")
        XCTAssertNotNil(Cage(cells: [0, 1], sum: 3), "1+2")
        XCTAssertNotNil(Cage(cells: [0, 1], sum: 17), "8+9")
    }

    func testThermometerKeepsItsOrder() {
        XCTAssertEqual(Thermometer(cells: [40, 4, 8])?.cells, [40, 4, 8],
                       "bulb-to-tip order is the meaning; it must not sort")
        XCTAssertNil(Thermometer(cells: [5]), "a one-cell thermometer constrains nothing")
        XCTAssertNil(Thermometer(cells: [5, 5]), "repeated cell")
    }

    // MARK: - Tolerant decode

    func testKnownConstraintsRoundTrip() throws {
        let cage = VariantConstraint.cage(Cage(cells: [0, 1, 9], sum: 15)!)
        XCTAssertEqual(try encoded(cage), #"{"cells":[0,1,9],"kind":"cage","sum":15}"#)
        XCTAssertEqual(try decode(VariantConstraint.self, try encoded(cage)), cage)

        let thermo = VariantConstraint.thermometer(Thermometer(cells: [40, 41, 42])!)
        XCTAssertEqual(try encoded(thermo), #"{"cells":[40,41,42],"kind":"thermometer"}"#)
        XCTAssertEqual(try decode(VariantConstraint.self, try encoded(thermo)), thermo)
    }

    /// The case the whole hand-written decode exists for: PRD-24 ships `.arrow`,
    /// this build meets one, and must hand it back untouched rather than throw
    /// (which would discard the blob) or drop it (which would silently change
    /// the rules of somebody's board).
    func testAnUnknownDiscriminatorSurvivesAWholeRoundTrip() throws {
        let json = #"{"cells":[3,4,5],"head":3,"kind":"arrow"}"#
        let decoded = try decode(VariantConstraint.self, json)
        guard case .unrecognized(let kind, _) = decoded else {
            return XCTFail("expected .unrecognized, got \(decoded)")
        }
        XCTAssertEqual(kind, "arrow")
        XCTAssertEqual(try encoded(decoded), json, "re-encoded verbatim, every key kept")
    }

    /// A *known* discriminator whose payload this build rejects is also carried,
    /// not dropped. A future build's stricter or looser cage is still its cage.
    func testAMalformedKnownConstraintIsCarriedNotDropped() throws {
        for json in [
            #"{"cells":[0,0,1],"kind":"cage","sum":6}"#,   // repeated cell
            #"{"cells":[0,1],"kind":"cage","sum":2}"#,     // impossible sum
            #"{"kind":"cage","sum":6}"#,                   // no cells at all
            #"{"cells":[5],"kind":"thermometer"}"#,        // too short
        ] {
            let decoded = try decode(VariantConstraint.self, json)
            guard case .unrecognized = decoded else {
                return XCTFail("\(json) should not have validated: \(decoded)")
            }
            XCTAssertEqual(try encoded(decoded), json, "carried verbatim")
        }
    }

    func testNoConstraintShapeThrows() throws {
        for json in ["null", "42", #""cage""#, "[1,2,3]", "{}", #"{"kind":7}"#] {
            XCTAssertNoThrow(try decode(VariantConstraint.self, json), "\(json) must not throw")
        }
    }

    func testAnUnknownVariantNameIsCarried() throws {
        XCTAssertEqual(try decode(Variant.self, #""sandwich""#), .unrecognized("sandwich"))
        XCTAssertEqual(try encoded(Variant.unrecognized("sandwich")), #""sandwich""#)
        XCTAssertEqual(try decode(Variant.self, "17"), .classic, "a non-string never throws")
    }

    // MARK: - The classic context

    /// The mechanism the whole refactor rests on. If any of these four drift,
    /// the golden corpus is going to fail and this test says why first.
    func testTheClassicContextIsTheStaticSudokuTables() {
        let context = ConstraintContext.classic
        XCTAssertTrue(context.isClassic)
        XCTAssertEqual(context.peers, Sudoku.peers)
        XCTAssertEqual(context.units, Sudoku.units)
        XCTAssertEqual(context.unitsOfCell, Sudoku.unitsOfCell)
        XCTAssertEqual(context.initialCandidates,
                       [UInt16](repeating: Sudoku.allDigitsMask, count: 81))
        XCTAssertTrue(context.canEnforceEveryConstraint)
    }

    /// `isClassic` is a pointer compare, so it is only trustworthy if there is
    /// no way to build an empty context that is not the singleton.
    func testCompilingNothingReturnsTheSharedSingleton() {
        XCTAssertTrue(ConstraintContext.compile([]) === ConstraintContext.classic)
        XCTAssertFalse(ConstraintContext.compile([.cage(Cage(cells: [0, 1], sum: 5)!)]).isClassic)
    }

    func testAnUnenforceableRuleIsFlagged() {
        let context = ConstraintContext.compile([
            .cage(Cage(cells: [0, 1], sum: 5)!),
            .unrecognized(kind: "arrow", payload: .null),
        ])
        XCTAssertFalse(context.canEnforceEveryConstraint,
                       "a board with a rule we cannot enforce must not be solved or proven")
        XCTAssertEqual(context.cages.count, 1, "the rules we do understand still compile")
    }

    // MARK: - Compiled tables

    func testCageCellsBecomeMutualPeersOnTopOfTheClassicOnes() {
        // Cells 0 and 80 share no row, column or box.
        XCTAssertFalse(Sudoku.peers[0].contains(80))
        let context = ConstraintContext.compile([.cage(Cage(cells: [0, 80], sum: 5)!)])
        XCTAssertTrue(context.peers[0].contains(80))
        XCTAssertTrue(context.peers[80].contains(0))
        XCTAssertEqual(context.peers[0], context.peers[0].sorted(), "peers stay sorted")
        XCTAssertEqual(Set(context.peers[0]), Set(Sudoku.peers[0]).union([80]),
                       "classic peers are added to, never replaced")
        // Untouched cells keep the classic table exactly.
        XCTAssertEqual(context.peers[40], Sudoku.peers[40])
    }

    /// A thermometer is strictly increasing, so its cells are pairwise distinct
    /// — the ordering is `thermoBound`'s job, the distinctness is a peer.
    func testThermometerCellsBecomeMutualPeers() {
        let context = ConstraintContext.compile([.thermometer(Thermometer(cells: [0, 80, 40])!)])
        XCTAssertTrue(context.peers[0].contains(80))
        XCTAssertTrue(context.peers[80].contains(0))
    }

    /// Cages are not units, and this is the assertion that says so out loud.
    /// `hiddenSingle` argues "this digit must appear somewhere in this unit",
    /// which is true of a row and false of a three-cell cage.
    func testCagesAreNeverAddedAsUnits() {
        let context = ConstraintContext.compile([.cage(Cage(cells: [0, 1, 2], sum: 6)!)])
        XCTAssertEqual(context.units, Sudoku.units)
    }

    func testThermometerNarrowsTheStartingCandidates() {
        let context = ConstraintContext.compile([.thermometer(Thermometer(cells: [0, 1, 2])!)])
        // Three cells, strictly increasing: bulb ≤ 7, middle in 2…8, tip ≥ 3.
        XCTAssertEqual(Sudoku.digits(in: context.initialCandidates[0]), Array(1...7))
        XCTAssertEqual(Sudoku.digits(in: context.initialCandidates[1]), Array(2...8))
        XCTAssertEqual(Sudoku.digits(in: context.initialCandidates[2]), Array(3...9))
        XCTAssertEqual(context.initialCandidates[40], Sudoku.allDigitsMask, "untouched cells")
    }

    func testCagesInsideAndTouchingUnits() {
        // Row 0 is cells 0…8. This cage is entirely inside it; that one is not.
        let inside = Cage(cells: [0, 1, 2], sum: 6)!
        let straddling = Cage(cells: [7, 8, 17], sum: 15)!
        let context = ConstraintContext.compile([.cage(inside), .cage(straddling)])
        XCTAssertEqual(context.cagesInsideUnit[0], [0])
        XCTAssertEqual(context.cagesTouchingUnit[0], [0, 1])
    }

    // MARK: - Cage combinations

    func testCageCombinationsAreTheClassicKillerTables() {
        // The tables every killer player has memorised.
        func sets(_ size: Int, _ sum: Int) -> [[Int]] {
            ConstraintContext.combinations(size: size, sum: sum).map { Sudoku.digits(in: $0) }
        }
        XCTAssertEqual(sets(2, 3), [[1, 2]])
        XCTAssertEqual(sets(2, 17), [[8, 9]])
        XCTAssertEqual(sets(3, 6), [[1, 2, 3]])
        XCTAssertEqual(sets(3, 24), [[7, 8, 9]])
        XCTAssertEqual(Set(sets(2, 10).map(Set.init)),
                       Set([[1, 9], [2, 8], [3, 7], [4, 6]].map(Set.init)))
        XCTAssertEqual(sets(1, 5), [[5]])
        XCTAssertEqual(sets(9, 45).count, 1, "a nine-cell cage is the whole digit set")

        // Nothing outside the reachable range, ever.
        XCTAssertTrue(sets(2, 2).isEmpty)
        XCTAssertTrue(sets(2, 18).isEmpty)
        XCTAssertTrue(sets(10, 45).isEmpty)

        // And every set really is distinct digits of the right size and sum.
        for size in 1...9 {
            for sum in Cage.minimumSum(size: size)...Cage.maximumSum(size: size) {
                for mask in ConstraintContext.combinations(size: size, sum: sum) {
                    let digits = Sudoku.digits(in: mask)
                    XCTAssertEqual(digits.count, size)
                    XCTAssertEqual(digits.reduce(0, +), sum)
                }
            }
        }
    }

    /// Counting them is the cheap way to prove the enumeration is complete as
    /// well as sound: the number of `size`-subsets of 1…9 over all sums is
    /// exactly C(9, size).
    func testEveryCombinationIsFound() {
        func choose(_ n: Int, _ k: Int) -> Int {
            (0..<k).reduce(1) { $0 * (n - $1) / ($1 + 1) }
        }
        for size in 1...9 {
            let total = (Cage.minimumSum(size: size)...Cage.maximumSum(size: size))
                .reduce(0) { $0 + ConstraintContext.combinations(size: size, sum: $1).count }
            XCTAssertEqual(total, choose(9, size), "size \(size)")
        }
    }
}
