import Foundation

/// The full photo → cell-grid pipeline as one deterministic pure function.
/// Platform layers (AsciiEngine in CouchKit) only adapt images in and draw
/// the resulting `CellGrid` out; every visual decision happens here, where
/// it can be unit-tested byte-for-byte.
public enum AsciiRenderer {

    /// Density-ranked charset for `.terminal` and `.phosphor` (dark → bright).
    public static let densityRamp: [String] =
        [" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"]

    /// Render `buffer` in `style`. Same buffer + grid + seed ⇒ identical grid.
    public static func render(
        _ buffer: PixelBuffer,
        style: AsciiStyle,
        grid: GridSpec = .fit(cols: 120),
        seed: UInt64 = 0
    ) -> CellGrid {
        let cols = grid.cols
        let rows = grid.rows(imageWidth: buffer.width, imageHeight: buffer.height, style: style)
        let field = AsciiPipeline.downsample(buffer, cols: cols, rows: rows)
        switch style {
        case .terminal: return renderTerminal(field, seed: seed)
        case .phosphor: return renderPhosphor(field)
        case .pixel:    return renderPixel(field)
        case .inkline:  return renderInkline(field, edges: AsciiPipeline.edgeField(of: field))
        case .mosaic:   return renderMosaic(field)
        }
    }

    // MARK: Styles

    /// Colored ASCII: 16-color k-means palette for foregrounds, glyph by
    /// luminance, true-black background (the CRT glow is a draw-time effect).
    static func renderTerminal(_ field: CellField, seed: UInt64) -> CellGrid {
        let (palette, assignment) = AsciiPipeline.quantize(field.colors, paletteSize: 16, seed: seed)
        var cells = [Cell]()
        cells.reserveCapacity(field.colors.count)
        for i in field.colors.indices {
            let lum = field.luminance[i]
            let symbol = rampSymbol(for: lum)
            // Lift very dark foregrounds a touch so glyphs never vanish.
            var fg = palette.isEmpty ? field.colors[i] : palette[assignment[i]]
            if fg.luminance < 0.08 && lum > 0.04 {
                fg = fg.mixed(with: RGB(70, 70, 76), t: 0.5)
            }
            cells.append(Cell(symbol: symbol, foreground: fg, background: .black))
        }
        return CellGrid(cols: field.cols, rows: field.rows, cells: cells)
    }

    /// Monochrome green phosphor: glyph by luminance, brightness-scaled tint,
    /// alternate rows dimmed 18% for a scanline feel.
    static func renderPhosphor(_ field: CellField) -> CellGrid {
        let phosphor = RGB(110, 255, 160)
        var cells = [Cell]()
        cells.reserveCapacity(field.colors.count)
        for i in field.colors.indices {
            let row = i / field.cols
            let lum = field.luminance[i]
            var glow = 0.22 + 0.78 * lum
            if row % 2 == 1 { glow *= 0.82 }
            cells.append(Cell(
                symbol: rampSymbol(for: lum),
                foreground: phosphor.scaled(by: glow),
                background: RGB(2, 8, 4)
            ))
        }
        return CellGrid(cols: field.cols, rows: field.rows, cells: cells)
    }

    /// Pure pixel art: nearest chunky-16 color, no glyphs.
    static func renderPixel(_ field: CellField) -> CellGrid {
        var cells = [Cell]()
        cells.reserveCapacity(field.colors.count)
        for c in field.colors {
            let p = AsciiPipeline.chunky16[AsciiPipeline.nearest(in: AsciiPipeline.chunky16, to: c)]
            cells.append(Cell(symbol: " ", foreground: p, background: p))
        }
        return CellGrid(cols: field.cols, rows: field.rows, cells: cells)
    }

    /// Edge-only line art: glyph chosen by edge *direction* (perpendicular to
    /// the Sobel gradient), paper ink on a near-black warm ground.
    static func renderInkline(_ field: CellField, edges: EdgeField) -> CellGrid {
        let paper = RGB(235, 228, 210)
        let ground = RGB(14, 13, 12)
        let threshold = 0.24
        var cells = [Cell]()
        cells.reserveCapacity(field.colors.count)
        for i in field.colors.indices {
            let m = edges.magnitude[i]
            guard m > threshold else {
                cells.append(Cell(symbol: " ", foreground: ground, background: ground))
                continue
            }
            // Edge runs perpendicular to the gradient.
            let edgeDeg = (edges.angle[i] * 180 / .pi) + 90
            let bucket = Int(((edgeDeg.truncatingRemainder(dividingBy: 180) + 180)
                .truncatingRemainder(dividingBy: 180) + 22.5) / 45) % 4
            let symbol = ["-", "/", "|", "\\"][bucket]
            let ink = paper.scaled(by: 0.55 + 0.45 * min(1, m / 0.6))
            cells.append(Cell(symbol: symbol, foreground: ink, background: ground))
        }
        return CellGrid(cols: field.cols, rows: field.rows, cells: cells)
    }

    /// Soft photographic tiles: each cell is its box color blended 4:1 with
    /// its cross neighbors — a one-pass gentle blur.
    static func renderMosaic(_ field: CellField) -> CellGrid {
        let cols = field.cols, rows = field.rows
        @inline(__always) func color(_ x: Int, _ y: Int) -> RGB {
            field.colors[max(0, min(rows - 1, y)) * cols + max(0, min(cols - 1, x))]
        }
        var cells = [Cell]()
        cells.reserveCapacity(field.colors.count)
        for y in 0..<rows {
            for x in 0..<cols {
                let c = color(x, y)
                let n = color(x, y - 1), s = color(x, y + 1)
                let w = color(x - 1, y), e = color(x + 1, y)
                let soft = RGB(
                    UInt8((Int(c.r) * 4 + Int(n.r) + Int(s.r) + Int(w.r) + Int(e.r)) / 8),
                    UInt8((Int(c.g) * 4 + Int(n.g) + Int(s.g) + Int(w.g) + Int(e.g)) / 8),
                    UInt8((Int(c.b) * 4 + Int(n.b) + Int(s.b) + Int(w.b) + Int(e.b)) / 8)
                )
                cells.append(Cell(symbol: " ", foreground: soft, background: soft))
            }
        }
        return CellGrid(cols: cols, rows: rows, cells: cells)
    }

    @inline(__always)
    static func rampSymbol(for luminance: Double) -> String {
        let clamped = max(0, min(1, luminance))
        let index = min(densityRamp.count - 1, Int(clamped * Double(densityRamp.count)))
        return densityRamp[index]
    }
}
