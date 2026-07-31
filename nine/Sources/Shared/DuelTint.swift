// DuelTint.swift — which two tints two people can share a board in (PRD-27 §6).
//
// Player One is the player's own accent. Player Two is *derived*, and deriving
// it rather than offering it is the covenant choice: a colour picker for the
// second player is a settings surface, and PRD-16 already established that the
// obvious free hue in the wheel is usually not a usable one — a periwinkle in
// the glacier→lilac gap cannot clear Blueprint's blue ground and stay clear of
// Lilac at once, so a gap on the hue wheel is not a usable gap.
//
// The numbers come from `SharedPalette`, which already carries all ten accents
// as triples and is already pinned to `Theme.swift` by a test that reads that
// file as text. So this is not a third copy of the palette; it is arithmetic on
// the second one.
//
// The dichromat matrices below *are* a second copy of the ones in
// `Tests/EngineTests/AppearancePaletteTests.swift`, and the alternative was
// worse: extracting them would edit a test that pins nine properties of the
// shipped palette, to save fifty lines of pure arithmetic that cannot drift
// without `DuelTintTests.testSeparationCollapsesForIdenticalColoursAndIsLargeForOpposites`
// failing. A copy with a test on it beats a refactor of a load-bearing test.
import Foundation

public enum DuelTint {

    /// The accent a second player gets when the first is playing in `accent`.
    ///
    /// The winner is the accent whose *worst* showing is best: maximise the
    /// minimum separation from the first player's tint and from coral, across
    /// normal vision and all three dichromacies. Ties break on the accent's
    /// name so the answer is stable across launches — this value is persisted,
    /// and a duel resumed tomorrow must come back in the colours it was played
    /// in today.
    ///
    /// Coral is in the comparison because it is not decoration: it is the error
    /// mark, and a second player whose digits look like mistakes is a worse
    /// outcome than a second player who looks like the first.
    public static func partner(for accent: String, isLight: Bool) -> String {
        let mine = SharedPalette.accent(accent, isLight: isLight)
        let coral = self.coral(isLight: isLight)
        // Sorted, so the tie-break is deterministic rather than whatever order
        // a Dictionary happened to hash into this launch. `String.hashValue` is
        // seeded per process in Swift — the same trap EXECUTING-A-PRD §3 records
        // about folding a hash into a seed.
        let candidates = SharedPalette.accentsOnDark.keys.sorted().filter { $0 != accent }
        var best: (name: String, score: Double)?
        for name in candidates {
            let rgb = SharedPalette.accent(name, isLight: isLight)
            let score = min(separation(rgb, mine), separation(rgb, coral))
            if score > (best?.score ?? -1) { best = (name, score) }
        }
        // Total by construction: `candidates` is non-empty for every input,
        // including an accent string this build has never heard of.
        return best?.name ?? SharedPalette.defaultAccent
    }

    /// `ThemeTones.coralOnDark` / `.coralOnLight`, verbatim.
    ///
    /// Only the error mark is copied here — the rest of `ThemeTones` is
    /// board-drawing and copying tones nothing in this file compares against is
    /// how two palettes start to drift (`SharedPalette`'s own stated rule about
    /// `gridTone`, `plane` and `hairline`).
    public static func coral(isLight: Bool) -> PaletteRGB {
        isLight ? PaletteRGB(0.72, 0.13, 0.06) : PaletteRGB(1.00, 0.45, 0.38)
    }

    /// The worst separation between two colours across normal vision and the
    /// three dichromacies — the number that decides whether two players can
    /// tell their own digits apart.
    public static func separation(_ a: PaletteRGB, _ b: PaletteRGB) -> Double {
        var worst = deltaE(a, b)
        for mode in Simulation.allCases {
            worst = min(worst, deltaE(simulate(a, mode), simulate(b, mode)))
        }
        return worst
    }

    // MARK: - Colour maths

    public enum Simulation: CaseIterable, Sendable {
        case protanopia, deuteranopia, tritanopia
    }

    /// Machado (2009) dichromat simulation matrices at full severity, applied
    /// in linear RGB.
    static func simulate(_ c: PaletteRGB, _ mode: Simulation) -> PaletteRGB {
        let m: [[Double]]
        switch mode {
        case .protanopia:
            m = [[0.152286, 1.052583, -0.204868],
                 [0.114503, 0.786281, 0.099216],
                 [-0.003882, -0.048116, 1.051998]]
        case .deuteranopia:
            m = [[0.367322, 0.860646, -0.227968],
                 [0.280085, 0.672501, 0.047413],
                 [-0.011820, 0.042940, 0.968881]]
        case .tritanopia:
            m = [[1.255528, -0.076749, -0.178779],
                 [-0.078411, 0.930809, 0.147602],
                 [0.004733, 0.691367, 0.303900]]
        }
        let r = linear(c.red), g = linear(c.green), b = linear(c.blue)
        return PaletteRGB(
            gamma(m[0][0] * r + m[0][1] * g + m[0][2] * b),
            gamma(m[1][0] * r + m[1][1] * g + m[1][2] * b),
            gamma(m[2][0] * r + m[2][1] * g + m[2][2] * b)
        )
    }

    /// CIE76 ΔE in Lab. Chosen over ΔE2000 because it is the metric the
    /// published dichromat-palette literature quotes, so a floor expressed in
    /// it means what that literature means by it.
    static func deltaE(_ a: PaletteRGB, _ b: PaletteRGB) -> Double {
        let la = lab(a), lb = lab(b)
        return sqrt(pow(la.0 - lb.0, 2) + pow(la.1 - lb.1, 2) + pow(la.2 - lb.2, 2))
    }

    private static func linear(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func gamma(_ v: Double) -> Double {
        let c = max(0, min(1, v))
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    private static func lab(_ c: PaletteRGB) -> (Double, Double, Double) {
        let r = linear(c.red), g = linear(c.green), b = linear(c.blue)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 1.00000
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3) : (7.787 * t) + 16.0 / 116
        }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
}
