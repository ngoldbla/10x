import Foundation

/// Per-cell samples after downsampling: average color and luminance.
public struct CellField: Sendable, Equatable {
    public let cols: Int
    public let rows: Int
    public var colors: [RGB]
    /// Rec. 709 luminance per cell, `[0, 1]`.
    public var luminance: [Double]

    public init(cols: Int, rows: Int, colors: [RGB], luminance: [Double]) {
        precondition(colors.count == cols * rows && luminance.count == cols * rows)
        self.cols = cols
        self.rows = rows
        self.colors = colors
        self.luminance = luminance
    }
}

/// Sobel edge response per cell.
public struct EdgeField: Sendable, Equatable {
    public let cols: Int
    public let rows: Int
    /// Edge magnitude normalized to `[0, 1]` (0 everywhere on flat images).
    public var magnitude: [Double]
    /// Gradient direction in radians, `atan2(gy, gx)`; meaningful only where
    /// magnitude is non-trivial.
    public var angle: [Double]
}

/// The stage functions of the render pipeline (PRD §5.3), mirroring the
/// asciify-them pipeline: Downsample → Quantize → EdgeField → Render.
/// All pure, all deterministic.
public enum AsciiPipeline {

    // MARK: Downsample

    /// Box-filter the image into a `cols × rows` cell field. Regions are
    /// computed with integer boundaries covering the full image, so every
    /// source pixel contributes to exactly one cell.
    public static func downsample(_ buffer: PixelBuffer, cols: Int, rows: Int) -> CellField {
        precondition(cols > 0 && rows > 0)
        var colors = [RGB]()
        colors.reserveCapacity(cols * rows)
        var luminance = [Double]()
        luminance.reserveCapacity(cols * rows)

        for cy in 0..<rows {
            let y0 = cy * buffer.height / rows
            let y1 = max(y0 + 1, (cy + 1) * buffer.height / rows)
            for cx in 0..<cols {
                let x0 = cx * buffer.width / cols
                let x1 = max(x0 + 1, (cx + 1) * buffer.width / cols)
                var sr = 0, sg = 0, sb = 0
                for y in y0..<min(y1, buffer.height) {
                    var i = (y * buffer.width + x0) * 4
                    for _ in x0..<min(x1, buffer.width) {
                        sr += Int(buffer.rgba[i])
                        sg += Int(buffer.rgba[i + 1])
                        sb += Int(buffer.rgba[i + 2])
                        i += 4
                    }
                }
                let n = max(1, (min(y1, buffer.height) - y0) * (min(x1, buffer.width) - x0))
                let c = RGB(UInt8(sr / n), UInt8(sg / n), UInt8(sb / n))
                colors.append(c)
                luminance.append(c.luminance)
            }
        }
        return CellField(cols: cols, rows: rows, colors: colors, luminance: luminance)
    }

    // MARK: Edge field

    /// 3×3 Sobel over the cell luminance grid with clamped borders.
    /// Operating on the downsampled grid (not the source pixels) is both
    /// cheaper and closer to what the glyph resolution can express.
    public static func edgeField(of field: CellField) -> EdgeField {
        let cols = field.cols, rows = field.rows
        var magnitude = [Double](repeating: 0, count: cols * rows)
        var angle = [Double](repeating: 0, count: cols * rows)

        @inline(__always) func lum(_ x: Int, _ y: Int) -> Double {
            field.luminance[max(0, min(rows - 1, y)) * cols + max(0, min(cols - 1, x))]
        }

        var maxMag = 0.0
        for y in 0..<rows {
            for x in 0..<cols {
                let gx = -lum(x - 1, y - 1) - 2 * lum(x - 1, y) - lum(x - 1, y + 1)
                       + lum(x + 1, y - 1) + 2 * lum(x + 1, y) + lum(x + 1, y + 1)
                let gy = -lum(x - 1, y - 1) - 2 * lum(x, y - 1) - lum(x + 1, y - 1)
                       + lum(x - 1, y + 1) + 2 * lum(x, y + 1) + lum(x + 1, y + 1)
                let m = (gx * gx + gy * gy).squareRoot()
                magnitude[y * cols + x] = m
                angle[y * cols + x] = atan2(gy, gx)
                if m > maxMag { maxMag = m }
            }
        }
        if maxMag > 0 {
            for i in magnitude.indices { magnitude[i] /= maxMag }
        }
        return EdgeField(cols: cols, rows: rows, magnitude: magnitude, angle: angle)
    }

    // MARK: Quantize

    /// Seeded k-means-lite color quantization. Deterministic: centroids are
    /// initialized from PRNG-chosen samples, ties in assignment break toward
    /// the lower palette index, and iteration count is fixed.
    /// - Returns: the palette and, for each input color, its palette index.
    public static func quantize(
        _ colors: [RGB], paletteSize k: Int, seed: UInt64, iterations: Int = 8
    ) -> (palette: [RGB], assignment: [Int]) {
        precondition(k > 0)
        guard !colors.isEmpty else { return ([], []) }

        var rng = SplitMix64(seed: seed)
        var centroids = [RGB]()
        var attempts = 0
        while centroids.count < k && attempts < k * 16 {
            let candidate = colors[rng.nextInt(below: colors.count)]
            if !centroids.contains(candidate) { centroids.append(candidate) }
            attempts += 1
        }
        // Fewer distinct colors than k: the palette is just what exists.
        if centroids.isEmpty { centroids = [colors[0]] }

        var assignment = [Int](repeating: 0, count: colors.count)
        for _ in 0..<iterations {
            // Assign.
            for (i, c) in colors.enumerated() {
                var best = 0
                var bestD = Int.max
                for (j, p) in centroids.enumerated() {
                    let d = c.distanceSquared(to: p)
                    if d < bestD { bestD = d; best = j }
                }
                assignment[i] = best
            }
            // Update.
            var sums = [(r: Int, g: Int, b: Int, n: Int)](repeating: (0, 0, 0, 0), count: centroids.count)
            for (i, c) in colors.enumerated() {
                let j = assignment[i]
                sums[j].r += Int(c.r); sums[j].g += Int(c.g); sums[j].b += Int(c.b); sums[j].n += 1
            }
            for j in centroids.indices where sums[j].n > 0 {
                centroids[j] = RGB(
                    UInt8(sums[j].r / sums[j].n),
                    UInt8(sums[j].g / sums[j].n),
                    UInt8(sums[j].b / sums[j].n)
                )
            }
        }
        // Final assignment against settled centroids.
        for (i, c) in colors.enumerated() {
            var best = 0
            var bestD = Int.max
            for (j, p) in centroids.enumerated() {
                let d = c.distanceSquared(to: p)
                if d < bestD { bestD = d; best = j }
            }
            assignment[i] = best
        }
        return (centroids, assignment)
    }

    /// Nearest color in a fixed palette.
    public static func nearest(in palette: [RGB], to color: RGB) -> Int {
        var best = 0
        var bestD = Int.max
        for (j, p) in palette.enumerated() {
            let d = color.distanceSquared(to: p)
            if d < bestD { bestD = d; best = j }
        }
        return best
    }

    /// The chunky 16-color palette used by `.pixel` — a dark-first 8-bit
    /// spread tuned so quantized photos still read on a living-room TV.
    public static let chunky16: [RGB] = [
        RGB(10, 10, 12),    // void
        RGB(29, 43, 83),    // deep blue
        RGB(88, 36, 82),    // plum
        RGB(0, 105, 84),    // pine
        RGB(140, 82, 50),   // umber
        RGB(85, 87, 93),    // slate
        RGB(178, 183, 182), // fog
        RGB(244, 240, 232), // paper
        RGB(214, 56, 71),   // signal red
        RGB(247, 147, 48),  // amber
        RGB(252, 222, 92),  // sun
        RGB(94, 189, 94),   // leaf
        RGB(72, 150, 226),  // sky
        RGB(112, 98, 187),  // dusk violet
        RGB(233, 137, 170), // rose
        RGB(245, 200, 158), // sand
    ]
}
