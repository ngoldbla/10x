// Darkroom engine — the puzzle compiler (PRD §5).
//
// PixelBuffer → binary nonogram, verified human-solvable by construction:
//   1. Square-crop, downsample to N×N (AsciiPipeline).
//   2. Score each cell: darkness + Sobel edge weighting (silhouette bias),
//      lightly smoothed so subjects form solvable blocks, plus a whisper of
//      seeded dither so flat regions break deterministically.
//   3. Threshold at the median (±attempt offsets) into a solution grid.
//   4. Verify with the line solver. Failing proof ⇒ re-threshold, then
//      re-crop toward the saliency center. ≤ 8 attempts, else reject.
// Deterministic: (photoID, size, dateSeed, pixels) ⇒ identical puzzle.
import Foundation
import CouchCore

public enum PuzzleCompiler {

    /// Hard cap on adjustment attempts (PRD §5.3).
    public static let maxAttempts = 8

    /// Acceptable fill ratio for a pleasant board.
    public static let fillRatioRange: ClosedRange<Double> = 0.25...0.72

    /// Blend weight of edge magnitude against darkness in the fill score.
    static let edgeWeight = 0.30

    /// Deterministic compile seed. FNV-1a over the photo ID, mixed with the
    /// grid size and the daily seed.
    public static func seed(photoID: String, size: Int, dateSeed: UInt64) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in photoID.utf8 {
            h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        h ^= UInt64(size) &* 0x9E37_79B9_7F4A_7C15
        h ^= dateSeed &* 0xC2B2_AE3D_27D4_EB4F
        return h
    }

    public struct Outcome: Sendable, Equatable {
        public let puzzle: Puzzle?
        /// Attempts consumed (1-based; == plan count when rejected).
        public let attempts: Int
    }

    /// Compile a verified puzzle, or `nil` when the photo can't yield one.
    public static func compile(
        photoID: String,
        buffer: PixelBuffer,
        size: Int,
        dateSeed: UInt64
    ) -> Puzzle? {
        compileDetailed(photoID: photoID, buffer: buffer, size: size, dateSeed: dateSeed).puzzle
    }

    /// Compile with attempt bookkeeping (exposed for tests).
    public static func compileDetailed(
        photoID: String,
        buffer: PixelBuffer,
        size: Int,
        dateSeed: UInt64
    ) -> Outcome {
        precondition(size >= 4, "grid too small to be a puzzle")
        let compileSeed = seed(photoID: photoID, size: size, dateSeed: dateSeed)
        let saliency = saliencyCenter(of: buffer)

        // 5 re-thresholds on the base crop, then 3 re-crops toward saliency.
        let plans: [(scale: Double, delta: Double)] = [
            (1.00, 0.00), (1.00, 0.05), (1.00, -0.05), (1.00, 0.10), (1.00, -0.10),
            (0.80, 0.00), (0.65, 0.00), (0.50, 0.00),
        ]
        precondition(plans.count == maxAttempts)

        for (attemptIndex, plan) in plans.enumerated() {
            let rect = cropRect(
                width: buffer.width,
                height: buffer.height,
                scale: plan.scale,
                center: plan.scale < 1 ? saliency : nil
            )
            let sub = cropped(buffer, to: rect)
            let field = AsciiPipeline.downsample(sub, cols: size, rows: size)
            let edges = AsciiPipeline.edgeField(of: field)
            let base = fillScores(field: field, edges: edges)

            // A featureless region can't carry a silhouette — thresholding
            // it would ship dithered noise as a "puzzle". Require real
            // contrast before committing.
            guard spread(of: base) >= minimumSpread else { continue }

            // A whisper of seeded dither so flat *areas* inside an otherwise
            // structured image break ties deterministically.
            var scores = base
            for y in 0..<size {
                for x in 0..<size {
                    scores[y * size + x] +=
                        (CouchHash.noise(x, y, seed: compileSeed) - 0.5) * 0.02
                }
            }

            let threshold = median(of: scores) + plan.delta
            let solution = scores.map { $0 >= threshold }

            let filled = solution.lazy.filter { $0 }.count
            let ratio = Double(filled) / Double(solution.count)
            guard fillRatioRange.contains(ratio) else { continue }

            var rowClues = [[Int]]()
            var colClues = [[Int]]()
            for y in 0..<size {
                rowClues.append(Puzzle.clues(for: (0..<size).map { solution[y * size + $0] }))
            }
            for x in 0..<size {
                colClues.append(Puzzle.clues(for: (0..<size).map { solution[$0 * size + x] }))
            }

            let report = GridSolver.solve(size: size, rowClues: rowClues, colClues: colClues)
            guard report.solved else { continue }

            let puzzle = Puzzle(
                photoID: photoID,
                size: size,
                dateSeed: dateSeed,
                solution: solution,
                colors: field.colors,
                difficulty: max(1, report.passes)
            )
            return Outcome(puzzle: puzzle, attempts: attemptIndex + 1)
        }
        return Outcome(puzzle: nil, attempts: plans.count)
    }

    // MARK: - Scoring

    /// Minimum 10th–90th percentile spread of the fill-score field for an
    /// image region to count as having a subject at all.
    static let minimumSpread = 0.05

    /// Robust contrast measure: the 10th–90th percentile spread.
    static func spread(of values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let sorted = values.sorted()
        let lo = sorted[sorted.count / 10]
        let hi = sorted[sorted.count - 1 - sorted.count / 10]
        return hi - lo
    }

    /// Per-cell fill score: darkness blended with edge magnitude (edges bias
    /// toward fill so subjects keep silhouettes), box-smoothed 3×3 so noise
    /// doesn't shatter runs.
    static func fillScores(field: CellField, edges: EdgeField) -> [Double] {
        let cols = field.cols, rows = field.rows
        var raw = [Double](repeating: 0, count: cols * rows)
        for i in raw.indices {
            raw[i] = (1.0 - field.luminance[i]) * (1.0 - edgeWeight)
                   + edges.magnitude[i] * edgeWeight
        }
        // 3×3 tent blur (center 4, edges 2, corners 1) with clamped borders.
        var smooth = [Double](repeating: 0, count: cols * rows)
        @inline(__always) func at(_ x: Int, _ y: Int) -> Double {
            raw[max(0, min(rows - 1, y)) * cols + max(0, min(cols - 1, x))]
        }
        for y in 0..<rows {
            for x in 0..<cols {
                var sum = at(x, y) * 4
                sum += (at(x - 1, y) + at(x + 1, y) + at(x, y - 1) + at(x, y + 1)) * 2
                sum += at(x - 1, y - 1) + at(x + 1, y - 1) + at(x - 1, y + 1) + at(x + 1, y + 1)
                smooth[y * cols + x] = sum / 16
            }
        }
        return smooth
    }

    static func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    // MARK: - Cropping

    /// Edge-weighted centroid of the image — a cheap saliency center the
    /// re-crop attempts pull toward (PRD §5.3).
    static func saliencyCenter(of buffer: PixelBuffer) -> (x: Int, y: Int) {
        let probe = 24
        let field = AsciiPipeline.downsample(buffer, cols: probe, rows: probe)
        let edges = AsciiPipeline.edgeField(of: field)
        var totalW = 0.0, sumX = 0.0, sumY = 0.0
        for y in 0..<probe {
            for x in 0..<probe {
                let w = edges.magnitude[y * probe + x]
                totalW += w
                sumX += w * (Double(x) + 0.5)
                sumY += w * (Double(y) + 0.5)
            }
        }
        guard totalW > 0.0001 else { return (buffer.width / 2, buffer.height / 2) }
        return (
            Int(sumX / totalW / Double(probe) * Double(buffer.width)),
            Int(sumY / totalW / Double(probe) * Double(buffer.height))
        )
    }

    /// Square crop of side `min(w, h) · scale`, centered on `center` (or the
    /// image center), clamped inside the image.
    static func cropRect(
        width: Int,
        height: Int,
        scale: Double,
        center: (x: Int, y: Int)?
    ) -> (x: Int, y: Int, side: Int) {
        let base = min(width, height)
        let side = max(4, min(base, Int((Double(base) * scale).rounded())))
        let cx = center?.x ?? width / 2
        let cy = center?.y ?? height / 2
        let x = max(0, min(width - side, cx - side / 2))
        let y = max(0, min(height - side, cy - side / 2))
        return (x, y, side)
    }

    static func cropped(_ buffer: PixelBuffer, to rect: (x: Int, y: Int, side: Int)) -> PixelBuffer {
        if rect.x == 0 && rect.y == 0 && rect.side == buffer.width && rect.side == buffer.height {
            return buffer
        }
        var out = [UInt8]()
        out.reserveCapacity(rect.side * rect.side * 4)
        for y in rect.y..<(rect.y + rect.side) {
            let rowStart = (y * buffer.width + rect.x) * 4
            out.append(contentsOf: buffer.rgba[rowStart..<(rowStart + rect.side * 4)])
        }
        return PixelBuffer(width: rect.side, height: rect.side, rgba: out)
    }
}
