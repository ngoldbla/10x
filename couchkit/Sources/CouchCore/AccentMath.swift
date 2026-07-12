import Foundation

/// Hue/saturation/value triple, all components in `[0, 1]`.
public struct HSV: Sendable, Equatable {
    public var h: Double
    public var s: Double
    public var v: Double

    public init(h: Double, s: Double, v: Double) {
        self.h = h
        self.s = s
        self.v = v
    }
}

/// The math behind `AccentDerivation` (PRD §5.1): extract a safe accent from
/// the current content image — dominant hue, clamped saturation/luminance —
/// so glass tints follow the art without ever going neon or muddy.
/// The SwiftUI `Color` adapter lives in CouchKit; this is pure and testable.
public enum AccentMath {

    public static func rgbToHSV(_ c: RGB) -> HSV {
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h /= 6
            if h < 0 { h += 1 }
        }
        return HSV(h: h, s: maxC == 0 ? 0 : delta / maxC, v: maxC)
    }

    public static func hsvToRGB(_ hsv: HSV) -> RGB {
        let h = (hsv.h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let s = max(0, min(1, hsv.s)), v = max(0, min(1, hsv.v))
        let i = Int(h) % 6
        let f = h - Double(Int(h))
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        let (r, g, b): (Double, Double, Double)
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return RGB(UInt8((r * 255).rounded()), UInt8((g * 255).rounded()), UInt8((b * 255).rounded()))
    }

    /// Dominant hue of the buffer in `[0, 1)`, from a 36-bin histogram
    /// weighted by chroma (saturation × value) — grays don't vote.
    /// Returns `nil` for effectively achromatic images.
    public static func dominantHue(in buffer: PixelBuffer, stride sampleStride: Int = 5) -> Double? {
        var bins = [Double](repeating: 0, count: 36)
        var totalWeight = 0.0
        var samples = 0
        var y = 0
        while y < buffer.height {
            var x = 0
            while x < buffer.width {
                let hsv = rgbToHSV(buffer.pixel(x: x, y: y))
                let weight = hsv.s * hsv.v
                if weight > 0.05 {
                    bins[min(35, Int(hsv.h * 36))] += weight
                    totalWeight += weight
                }
                samples += 1
                x += sampleStride
            }
            y += sampleStride
        }
        guard samples > 0, totalWeight / Double(samples) > 0.02 else { return nil }
        var bestBin = 0
        for i in bins.indices where bins[i] > bins[bestBin] { bestBin = i }
        // Weighted centroid of the winning bin and its neighbors for a
        // smoother pick than the raw bin center.
        let prev = bins[(bestBin + 35) % 36], own = bins[bestBin], next = bins[(bestBin + 1) % 36]
        let offset = (next - prev) / max(0.0001, prev + own + next) * 0.5
        var hue = (Double(bestBin) + 0.5 + offset) / 36
        if hue < 0 { hue += 1 }
        return hue.truncatingRemainder(dividingBy: 1)
    }

    /// A display-safe accent for the buffer: dominant hue at clamped
    /// saturation/value. Falls back to a neutral warm gray for achromatic art.
    public static func accent(for buffer: PixelBuffer) -> RGB {
        guard let hue = dominantHue(in: buffer) else {
            return RGB(196, 190, 180)
        }
        return hsvToRGB(HSV(h: hue, s: 0.5, v: 0.82))
    }
}
