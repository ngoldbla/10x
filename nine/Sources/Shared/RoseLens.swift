// RoseLens.swift — where the rose's petals are, in board-local points (PRD-22).
//
// This used to be six copies of the same arithmetic: TouchUI, MacUI, FirstRun,
// TutorialView (twice) and GameScreen each recomputed `126 * scale`, the
// `184 * scale` clamp and `centre + inset` by hand. That was survivable while
// only the petals read it. PRD-22 adds a second reader — the board Canvas's
// third layer effect bends and magnifies the digits under each petal — and a
// lens that disagrees with the paint by four points reads as a smear beside the
// glass rather than as glass. So the arithmetic lives once, here, in
// Sources/Shared, where Lane 1 tests it on Linux without a simulator.
//
// Coordinates are **board-local**: the origin is the Canvas's top-left corner,
// which is `inset` points inside the glass plane. That is the space the two
// Afterglow shaders already speak (`BoardMetrics.center(of:side:)` is passed
// straight into `afterglowWave`), so the lens speaks it too. `viewCentre` adds
// the inset back for `.position`, which measures in the padded frame.
//
// Linux-clean on purpose: no SwiftUI, no CoreGraphics, no CGPoint. The App
// layer converts to CGFloat at the boundary.
import Foundation

/// Cell geometry, duplicated from `BoardMetrics` because that type lives in the
/// App layer — it needs `CGPoint`/`CGRect` for the accessibility frames — and
/// this one has to compile on Linux. `RoseLensTests` reads `BoardView.swift`
/// and fails if the two formulas stop agreeing.
public enum BoardGeometry {
    /// Centre of a cell in a board of arbitrary side length.
    public static func centre(of cell: Int, side: Double) -> (x: Double, y: Double) {
        let unit = side / 9
        return ((Double(cell % 9) + 0.5) * unit, (Double(cell / 9) + 0.5) * unit)
    }
}

/// Everything the petals and the shader have to agree on.
public struct RoseLens: Equatable, Sendable {
    /// Petal diameter is `116 * scale` (88 in pencil mode); ring pitch is
    /// `126 * scale` (96). These four numbers are `FlickRoseView`'s, unchanged.
    private static let petalSide = 116.0, pencilPetalSide = 88.0
    private static let ringPitch = 126.0, pencilRingPitch = 96.0
    /// Half the ring's full span, used to keep every petal on the plane:
    /// `126 + 116/2`. The non-pencil constants deliberately, so the clamp does
    /// not shift under the player when a rose is toggled into pencil mode.
    private static let clampSpan = 184.0

    public let pencil: Bool
    public let scale: Double
    public let inset: Double
    /// Board-local centre of the ring, already clamped onto the plane. Stored
    /// as two Doubles rather than a tuple because Swift cannot synthesise
    /// `Equatable` for a struct with a tuple stored property, and `BoardView`
    /// drives the lens bloom off `onChange(of: roseLens)`.
    public let centreX: Double
    public let centreY: Double

    public init(
        cursor: Int,
        side: Double,
        inset: Double,
        pencil: Bool,
        scale: Double,
        clamped: Bool = true
    ) {
        self.pencil = pencil
        self.scale = scale
        self.inset = inset

        let raw = BoardGeometry.centre(of: cursor, side: side)
        guard clamped else {
            (self.centreX, self.centreY) = raw
            return
        }
        // The clamp works in *view* coordinates — the padded frame — because
        // that is where the six call sites wrote it and where `.position`
        // reads it. Converting back at the end keeps the stored value in the
        // board-local space the shader needs.
        let radius = Self.clampSpan * scale
        let frameSide = side + 2 * inset
        let x = min(max(raw.x + inset, radius - 6), frameSide - radius + 6)
        let y = min(max(raw.y + inset, radius - 6), frameSide - radius + 6)
        (self.centreX, self.centreY) = (x - inset, y - inset)
    }

    /// Board-local centre of the ring — the space the two Afterglow shaders
    /// already speak.
    public var centre: (x: Double, y: Double) { (centreX, centreY) }

    /// Ring pitch: centre-to-centre between neighbouring petals.
    public var spacing: Double {
        (pencil ? Self.pencilRingPitch : Self.ringPitch) * scale
    }

    /// Half a petal's drawn diameter — the radius the shader bends inside.
    public var petalRadius: Double {
        (pencil ? Self.pencilPetalSide : Self.petalSide) * scale / 2
    }

    /// Where `.position` puts the rose: the padded frame's coordinates.
    public var viewCentre: (x: Double, y: Double) {
        (centre.x + inset, centre.y + inset)
    }

    /// Digit 1…9 on the phone keypad — 1 2 3 / 4 5 6 / 7 8 9, with 5 at the
    /// centre. Same mapping as `RoseGeometry.offset(forDigit:)`, which is what
    /// paints them.
    public func petalCentre(digit: Int) -> (x: Double, y: Double) {
        let index = digit - 1
        let dx = Double(index % 3 - 1), dy = Double(index / 3 - 1)
        return (centre.x + dx * spacing, centre.y + dy * spacing)
    }

    /// Petals sized for fingers: a hair wider than a board cell, until the
    /// board is big enough that a cell-sized petal would be a dinner plate.
    public static func scale(forSide side: Double) -> Double {
        min(0.62, ((side / 9) * 1.15) / 116)
    }
}
