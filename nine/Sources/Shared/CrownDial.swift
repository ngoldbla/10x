// CrownDial.swift — the Crown rose's grammar (PRD-6 §2.3).
//
// The rose unrolled. On tvOS a flick picks one of nine directions; on the
// wrist the same nine digits become a run you turn through, because a crown
// has detents and precision that a finger on a 45mm screen never will.
//
// The whole rule is here, in Shared, rather than inside the SwiftUI view,
// because the one property that matters cannot be checked by looking at a
// watch: **the run is bounded and does not wrap.** Overshooting past ✕ must
// stop at ✕. If it looped back to ∅ and on to 1, a player spinning
// enthusiastically past the end would arrive at a *placement* — and "nothing
// ever places without an explicit commit" is the covenant the rose was built
// to keep (PRD §4.1, PRD-6 §2.3).
//
// Position 0 is ∅ (nothing dialled), 1…9 are the digits, 10 is ✕ (erase).
import Foundation

public enum CrownDial: Equatable, Sendable {
    /// Nothing dialled — the resting position, and what every navigation
    /// event returns the dial to.
    case empty
    /// A digit previewing in the selected cell.
    case digit(Int)
    /// The erase stop at the far end of the run.
    case erase

    public static let lowerBound = 0
    public static let upperBound = 10

    /// Read a crown position into a dial value, clamping rather than wrapping.
    ///
    /// SwiftUI's `digitalCrownRotation(from:through:)` clamps too, so this is
    /// the second lock on the same door — and the only one that a test can
    /// reach.
    public init(position: Int) {
        let clamped = min(max(position, Self.lowerBound), Self.upperBound)
        switch clamped {
        case Self.upperBound: self = .erase
        case Self.lowerBound: self = .empty
        default: self = .digit(clamped)
        }
    }

    public var position: Int {
        switch self {
        case .empty: return Self.lowerBound
        case .digit(let d): return d
        case .erase: return Self.upperBound
        }
    }

    /// The digit this dial would place, or nil for the two ends.
    public var digit: Int? {
        if case .digit(let d) = self { return d }
        return nil
    }

    /// Is there anything to commit at all? `.empty` is not a move, which is
    /// what makes "spin to the end and let go" cost nothing.
    public var isCommittable: Bool { self != .empty }
}
