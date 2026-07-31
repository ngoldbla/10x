// DuelTintTests.swift — the second tint is derived, and these are the
// properties that make it safe rather than merely different (PRD-27 §6).
import XCTest
@testable import NineShared

final class DuelTintTests: XCTestCase {

    /// `AppearancePaletteTests.separationFloor` — the shipped palette's own
    /// worst sibling pair under any dichromacy. Named here rather than
    /// imported because that constant lives on an XCTestCase in another target;
    /// if it ever moves, this number moving with it is a deliberate act.
    static let floor = 5.9

    func testEveryAccentGetsAPartnerThatIsNotItself() {
        for accent in SharedPalette.accentsOnDark.keys {
            for isLight in [true, false] {
                let partner = DuelTint.partner(for: accent, isLight: isLight)
                XCTAssertNotEqual(partner, accent, "\(accent) partnered with itself")
                XCTAssertNotNil(SharedPalette.accentsOnDark[partner], "\(partner) is not an accent")
            }
        }
    }

    func testEveryPartnerPairClearsTheSeparationFloorAgainstEachOtherAndCoral() {
        for accent in SharedPalette.accentsOnDark.keys.sorted() {
            for isLight in [true, false] {
                let partner = DuelTint.partner(for: accent, isLight: isLight)
                let mine = SharedPalette.accent(accent, isLight: isLight)
                let theirs = SharedPalette.accent(partner, isLight: isLight)
                let coral = DuelTint.coral(isLight: isLight)

                let pair = DuelTint.separation(mine, theirs)
                XCTAssertGreaterThanOrEqual(
                    pair, Self.floor,
                    "\(accent)/\(partner) only \(String(format: "%.2f", pair)) apart (isLight: \(isLight))")

                let vsCoral = DuelTint.separation(theirs, coral)
                XCTAssertGreaterThanOrEqual(
                    vsCoral, Self.floor,
                    "\(partner) only \(String(format: "%.2f", vsCoral)) from coral (isLight: \(isLight))")
            }
        }
    }

    /// Deterministic, because it is persisted: a duel resumed tomorrow must
    /// come back in the same two colours it was played in today. `String`'s
    /// hash is seeded per process in Swift, so an unsorted candidate walk would
    /// pass this test on most runs and fail it on some.
    func testThePartnerIsDeterministic() {
        for accent in SharedPalette.accentsOnDark.keys {
            let first = DuelTint.partner(for: accent, isLight: false)
            for _ in 0..<20 {
                XCTAssertEqual(DuelTint.partner(for: accent, isLight: false), first)
            }
        }
    }

    /// Total, like every other `SharedPalette` lookup: a duel state written by
    /// a newer build naming an accent this one has never heard of still opens.
    func testAnUnknownAccentResolvesRatherThanTrapping() {
        let partner = DuelTint.partner(for: "chartreuse", isLight: false)
        XCTAssertNotNil(SharedPalette.accentsOnDark[partner])
    }

    /// Pins the maths itself, so a refactor of `simulate` cannot quietly turn
    /// the separation function into a constant and keep every test above green.
    func testSeparationCollapsesForIdenticalColoursAndIsLargeForOpposites() {
        let blue = PaletteRGB(0.33, 0.68, 0.98)
        XCTAssertEqual(DuelTint.separation(blue, blue), 0, accuracy: 0.001)
        XCTAssertGreaterThan(DuelTint.separation(PaletteRGB(0, 0, 0), PaletteRGB(1, 1, 1)), 50)
    }

    /// The dichromat simulation must actually *do* something, or every
    /// "separation under three dichromacies" claim above reduces to one
    /// ordinary ΔE wearing a hat. Red and green are the pair protanopia and
    /// deuteranopia are named for.
    func testTheDichromatSimulationCollapsesRedAndGreenForTheModesThatShould() {
        let red = PaletteRGB(0.90, 0.10, 0.10), green = PaletteRGB(0.10, 0.90, 0.10)
        let normal = DuelTint.deltaE(red, green)
        for mode in [DuelTint.Simulation.protanopia, .deuteranopia] {
            let seen = DuelTint.deltaE(DuelTint.simulate(red, mode), DuelTint.simulate(green, mode))
            XCTAssertLessThan(seen, normal / 2, "\(mode) should bring red and green together")
        }
    }
}
