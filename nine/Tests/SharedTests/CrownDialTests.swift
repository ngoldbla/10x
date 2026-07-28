import Foundation
import Testing
@testable import NineShared

@Suite("CrownDial")
struct CrownDialTests {

    @Test func theRunIsEmptyThenNineDigitsThenErase() {
        #expect(CrownDial(position: 0) == .empty)
        for digit in 1...9 {
            #expect(CrownDial(position: digit) == .digit(digit))
        }
        #expect(CrownDial(position: 10) == .erase)
    }

    /// The rule the whole type exists for. A wrapping dial lets an
    /// enthusiastic spin past ✕ arrive back at a *placement*, and "nothing
    /// ever places without an explicit commit" is the covenant the rose keeps.
    @Test func overshootStopsAtTheEndsAndNeverLoopsBackTowardAPlacement() {
        for beyond in [11, 12, 25, 400, Int.max] {
            #expect(CrownDial(position: beyond) == .erase)
        }
        for below in [-1, -2, -37, Int.min] {
            #expect(CrownDial(position: below) == .empty)
        }
    }

    @Test func positionRoundTripsThroughTheValue() {
        for position in 0...10 {
            #expect(CrownDial(position: position).position == position)
        }
    }

    @Test func onlyTheNineDigitsCarryADigit() {
        #expect(CrownDial.empty.digit == nil)
        #expect(CrownDial.erase.digit == nil)
        for digit in 1...9 {
            #expect(CrownDial.digit(digit).digit == digit)
        }
    }

    /// Spinning to the end and letting go must cost nothing, so `.empty` is
    /// not a move — but ✕ is, because erasing is a thing you mean.
    @Test func restingAtEmptyIsNotAMoveButEraseIs() {
        #expect(!CrownDial.empty.isCommittable)
        #expect(CrownDial.erase.isCommittable)
        #expect(CrownDial.digit(4).isCommittable)
    }
}
