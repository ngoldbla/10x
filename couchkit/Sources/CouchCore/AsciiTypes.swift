import Foundation

/// The five shipped render styles. Exactly five, no more (PRD §5.3).
public enum AsciiStyle: String, CaseIterable, Sendable, Codable, Hashable {
    /// Classic colored ASCII on true black — density-ranked charset.
    case terminal
    /// Monochrome green terminal with scanline dimming.
    case phosphor
    /// Pure pixel-art quantization to a chunky 16-color palette. No glyphs.
    case pixel
    /// Edge-only line art using angle-mapped glyphs (`/ — \ |`), paper tint.
    case inkline
    /// Large soft tiles — the gentlest, most photographic style.
    case mosaic

    /// Whether cells carry a visible glyph (vs. pure color tiles).
    public var usesGlyphs: Bool {
        switch self {
        case .pixel, .mosaic: return false
        case .terminal, .phosphor, .inkline: return true
        }
    }

    /// Display aspect (width ÷ height) of one cell in this style.
    /// Monospaced terminal glyphs are roughly twice as tall as they are wide,
    /// so glyph styles use 0.5; tile styles use square cells. The downsampler
    /// uses this to stay aspect-correct end to end.
    public var preferredCellAspect: Double {
        usesGlyphs ? 0.5 : 1.0
    }
}

/// How to size the cell grid for a given source image.
public struct GridSpec: Sendable, Equatable {
    /// Number of character/tile columns.
    public var cols: Int
    /// Cell display aspect (width ÷ height). `nil` = use the style's default.
    public var cellAspect: Double?

    public init(cols: Int, cellAspect: Double? = nil) {
        precondition(cols > 0, "GridSpec.cols must be positive")
        self.cols = cols
        self.cellAspect = cellAspect
    }

    /// A grid `cols` wide whose row count is derived from the image aspect.
    public static func fit(cols: Int, cellAspect: Double? = nil) -> GridSpec {
        GridSpec(cols: cols, cellAspect: cellAspect)
    }

    /// Aspect-correct row count: `rows = cols · (h/w) · cellAspect`, so the
    /// grid displayed at the style's cell aspect matches the image aspect.
    public func rows(imageWidth: Int, imageHeight: Int, style: AsciiStyle) -> Int {
        let aspect = cellAspect ?? style.preferredCellAspect
        let rows = Double(cols) * (Double(imageHeight) / Double(imageWidth)) * aspect
        return max(1, Int(rows.rounded()))
    }
}

/// One rendered cell: a glyph plus its colors. For tile styles the symbol is
/// a space and `foreground == background`.
public struct Cell: Hashable, Sendable, Codable {
    /// Single grapheme to draw (space for pure-color tiles).
    public var symbol: String
    public var foreground: RGB
    public var background: RGB

    public init(symbol: String, foreground: RGB, background: RGB) {
        self.symbol = symbol
        self.foreground = foreground
        self.background = background
    }
}

/// The pipeline's output: a row-major grid of cells. `Equatable` so
/// determinism can be asserted exactly (same input + seed ⇒ `==`).
public struct CellGrid: Sendable, Equatable, Codable {
    public let cols: Int
    public let rows: Int
    public var cells: [Cell]

    public init(cols: Int, rows: Int, cells: [Cell]) {
        precondition(cells.count == cols * rows, "cells must be cols*rows")
        self.cols = cols
        self.rows = rows
        self.cells = cells
    }

    @inlinable
    public subscript(x: Int, y: Int) -> Cell {
        get { cells[y * cols + x] }
        set { cells[y * cols + x] = newValue }
    }
}
