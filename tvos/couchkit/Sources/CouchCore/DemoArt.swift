import Foundation

/// A procedural placeholder "photo". When the photo library is unauthorized
/// or empty, every Couch Suite app renders these instead — so the suite demos
/// beautifully with zero permissions (also the App Review path).
/// Rendering is a pure function of the recipe: same recipe ⇒ same pixels.
public struct DemoArtRecipe: Sendable, Identifiable, Equatable, Hashable {
    public enum Kind: String, Sendable, Codable, Hashable {
        /// Smooth multi-stop gradient washes with grain (and optional stars).
        case gradient
        /// Interference/plasma fields mapped through a color ramp.
        case plasma
        /// Signed-distance landscape: sun, ridge lines, optional sea.
        case landscape
    }

    public let id: String
    /// Display title, e.g. `"Demo · Dunes"`.
    public let title: String
    /// A plausible fake capture date, so date chips look real.
    public let displayDate: Date
    /// A fake location label, e.g. `"Mojave"`.
    public let locationLabel: String
    public let kind: Kind
    public let seed: UInt64
}

/// The bundled recipe book and its renderer.
public enum DemoArt {

    /// All shipped recipes (9 — a full channel's worth).
    public static let recipes: [DemoArtRecipe] = [
        DemoArtRecipe(
            id: "dunes", title: "Demo · Dunes",
            displayDate: date(2019, 6, 14), locationLabel: "Mojave",
            kind: .landscape, seed: 0xD00E_5001),
        DemoArtRecipe(
            id: "cold-harbor", title: "Demo · Cold Harbor",
            displayDate: date(2021, 11, 2), locationLabel: "Reykjavík",
            kind: .landscape, seed: 0xC01D_5002),
        DemoArtRecipe(
            id: "paper-sun", title: "Demo · Paper Sun",
            displayDate: date(2020, 8, 30), locationLabel: "Kyoto",
            kind: .landscape, seed: 0x9A9E_5003),
        DemoArtRecipe(
            id: "ember-sky", title: "Demo · Ember Sky",
            displayDate: date(2018, 9, 21), locationLabel: "Lisbon",
            kind: .gradient, seed: 0xE3BE_5004),
        DemoArtRecipe(
            id: "deep-field", title: "Demo · Deep Field",
            displayDate: date(2022, 1, 9), locationLabel: "Atacama",
            kind: .gradient, seed: 0xDEEF_5005),
        DemoArtRecipe(
            id: "terraces", title: "Demo · Terraces",
            displayDate: date(2017, 4, 18), locationLabel: "Sa Pa",
            kind: .gradient, seed: 0x7E88_5006),
        DemoArtRecipe(
            id: "neon-tide", title: "Demo · Neon Tide",
            displayDate: date(2023, 7, 4), locationLabel: "Tokyo Bay",
            kind: .plasma, seed: 0x0E01_5007),
        DemoArtRecipe(
            id: "signal-bloom", title: "Demo · Signal Bloom",
            displayDate: date(2016, 12, 31), locationLabel: "Berlin",
            kind: .plasma, seed: 0x51B1_5008),
        DemoArtRecipe(
            id: "aurora", title: "Demo · Aurora",
            displayDate: date(2024, 2, 23), locationLabel: "Tromsø",
            kind: .plasma, seed: 0xA060_5009),
    ]

    public static func recipe(id: String) -> DemoArtRecipe? {
        recipes.first { $0.id == id }
    }

    /// Render a recipe to pixels. 640×360 is plenty for a 160-column ascii
    /// grid; pass a larger size for direct full-screen display.
    public static func render(_ recipe: DemoArtRecipe, width: Int = 640, height: Int = 360) -> PixelBuffer {
        switch recipe.kind {
        case .gradient: return renderGradient(recipe, width: width, height: height)
        case .plasma: return renderPlasma(recipe, width: width, height: height)
        case .landscape: return renderLandscape(recipe, width: width, height: height)
        }
    }

    // MARK: - Gradient

    static func renderGradient(_ recipe: DemoArtRecipe, width: Int, height: Int) -> PixelBuffer {
        var rng = SplitMix64(seed: recipe.seed)
        let stops = gradientStops(for: recipe.id, rng: &rng)
        let warpFreq = rng.nextDouble(in: 1.2...2.6)
        let warpAmp = rng.nextDouble(in: 0.05...0.14)
        let warpPhase = rng.nextDouble(in: 0...(2 * .pi))
        let banding = recipe.id == "terraces" ? 9.0 : 0.0
        let stars = recipe.id == "deep-field"

        var buffer = PixelBuffer(width: width, height: height)
        for y in 0..<height {
            let v = Double(y) / Double(height - 1)
            for x in 0..<width {
                let u = Double(x) / Double(width - 1)
                var t = v + warpAmp * sin(u * .pi * warpFreq + warpPhase)
                if banding > 0 {
                    // Soft terraced steps: quantize, then ease back a little.
                    let stepped = (t * banding).rounded(.down) / banding
                    t = stepped * 0.75 + t * 0.25
                }
                var c = sample(stops: stops, at: t)
                let grain = (CouchHash.noise(x, y, seed: recipe.seed) - 0.5) * 0.035
                c = c.offset(by: grain)
                if stars {
                    // 2×2-pixel stars so they survive downsampling to cells.
                    let twinkle = CouchHash.noise(x / 2, y / 2, seed: recipe.seed ^ 0xABCD)
                    if twinkle > 0.9982 {
                        let brightness = 0.55 + 0.45 * CouchHash.noise(x / 2, y / 2, seed: recipe.seed ^ 0x57A4)
                        c = c.mixed(with: RGBF(1, 1, 0.96), t: brightness)
                    }
                }
                buffer.setPixel(x: x, y: y, c.rgb8)
            }
        }
        return buffer
    }

    static func gradientStops(for id: String, rng: inout SplitMix64) -> [(Double, RGBF)] {
        switch id {
        case "ember-sky":
            return [
                (0.00, RGBF(hex: 0x1B0B2E)), (0.35, RGBF(hex: 0x64264B)),
                (0.62, RGBF(hex: 0xC94F2E)), (0.82, RGBF(hex: 0xF2A54A)),
                (1.00, RGBF(hex: 0x2A0F1E)),
            ]
        case "deep-field":
            return [
                (0.00, RGBF(hex: 0x02030A)), (0.45, RGBF(hex: 0x101B45)),
                (0.75, RGBF(hex: 0x27406E)), (1.00, RGBF(hex: 0x060919)),
            ]
        case "terraces":
            return [
                (0.00, RGBF(hex: 0x27401F)), (0.40, RGBF(hex: 0x4E7434)),
                (0.70, RGBF(hex: 0x8FA84C)), (1.00, RGBF(hex: 0x1C2B18)),
            ]
        default:
            // Seeded fallback for future recipes: three random deep stops.
            return [
                (0.0, RGBF(rng.nextDouble(in: 0...0.2), rng.nextDouble(in: 0...0.2), rng.nextDouble(in: 0.1...0.4))),
                (0.5, RGBF(rng.nextDouble(in: 0.2...0.7), rng.nextDouble(in: 0.1...0.5), rng.nextDouble(in: 0.2...0.7))),
                (1.0, RGBF(rng.nextDouble(in: 0...0.15), rng.nextDouble(in: 0...0.15), rng.nextDouble(in: 0...0.2))),
            ]
        }
    }

    // MARK: - Plasma

    static func renderPlasma(_ recipe: DemoArtRecipe, width: Int, height: Int) -> PixelBuffer {
        var rng = SplitMix64(seed: recipe.seed)
        let f1 = rng.nextDouble(in: 2.0...4.5)
        let f2 = rng.nextDouble(in: 3.0...6.0)
        let f3 = rng.nextDouble(in: 4.0...9.0)
        let p1 = rng.nextDouble(in: 0...(2 * .pi))
        let p2 = rng.nextDouble(in: 0...(2 * .pi))
        let p3 = rng.nextDouble(in: 0...(2 * .pi))
        let cx = rng.nextDouble(in: 0.3...0.7)
        let cy = rng.nextDouble(in: 0.3...0.7)
        let ramp = plasmaRamp(for: recipe.id)

        var buffer = PixelBuffer(width: width, height: height)
        for y in 0..<height {
            let v = Double(y) / Double(height - 1)
            for x in 0..<width {
                let u = Double(x) / Double(width - 1)
                let radial = ((u - cx) * (u - cx) + (v - cy) * (v - cy)).squareRoot()
                var s = sin(u * .pi * f1 + p1)
                s += sin(v * .pi * f2 + p2)
                s += sin((u + v) * .pi * f2 * 0.6 + p3)
                s += sin(radial * .pi * f3)
                let t = max(0, min(1, (s / 4 + 1) / 2))
                var c = sample(stops: ramp, at: t)
                let grain = (CouchHash.noise(x, y, seed: recipe.seed) - 0.5) * 0.03
                c = c.offset(by: grain)
                buffer.setPixel(x: x, y: y, c.rgb8)
            }
        }
        return buffer
    }

    static func plasmaRamp(for id: String) -> [(Double, RGBF)] {
        switch id {
        case "neon-tide":
            return [
                (0.00, RGBF(hex: 0x050514)), (0.35, RGBF(hex: 0x14306E)),
                (0.65, RGBF(hex: 0x0FB6B0)), (0.85, RGBF(hex: 0xE84393)),
                (1.00, RGBF(hex: 0xFBE6F0)),
            ]
        case "signal-bloom":
            return [
                (0.00, RGBF(hex: 0x03110A)), (0.40, RGBF(hex: 0x0E5A2B)),
                (0.72, RGBF(hex: 0x7FC941)), (1.00, RGBF(hex: 0xF3F7C4)),
            ]
        default: // aurora
            return [
                (0.00, RGBF(hex: 0x02030F)), (0.35, RGBF(hex: 0x0B2C4F)),
                (0.62, RGBF(hex: 0x1B8A6B)), (0.85, RGBF(hex: 0x7ED4A6)),
                (1.00, RGBF(hex: 0x5B4A9E)),
            ]
        }
    }

    // MARK: - Landscape

    struct LandscapePalette {
        var skyTop: RGBF, skyBottom: RGBF, sun: RGBF
        var ridges: [RGBF] // far → near
        var sea: (far: RGBF, near: RGBF)?
    }

    static func landscapePalette(for id: String) -> LandscapePalette {
        switch id {
        case "cold-harbor":
            return LandscapePalette(
                skyTop: RGBF(hex: 0x14202E), skyBottom: RGBF(hex: 0x8FA6B5),
                sun: RGBF(hex: 0xE8ECEA),
                ridges: [RGBF(hex: 0x3C4E5C), RGBF(hex: 0x22303B)],
                sea: (far: RGBF(hex: 0x5C7484), near: RGBF(hex: 0x1B2833)))
        case "paper-sun":
            return LandscapePalette(
                skyTop: RGBF(hex: 0xF2E8D8), skyBottom: RGBF(hex: 0xE8C9A8),
                sun: RGBF(hex: 0xD9634A),
                ridges: [RGBF(hex: 0xB89B7E), RGBF(hex: 0x6E5643), RGBF(hex: 0x3A2E26)],
                sea: nil)
        default: // dunes
            return LandscapePalette(
                skyTop: RGBF(hex: 0x2A1A3E), skyBottom: RGBF(hex: 0xE8955C),
                sun: RGBF(hex: 0xFCE9C8),
                ridges: [RGBF(hex: 0xC97B4A), RGBF(hex: 0x8E4E33), RGBF(hex: 0x4A2A22)],
                sea: nil)
        }
    }

    static func renderLandscape(_ recipe: DemoArtRecipe, width: Int, height: Int) -> PixelBuffer {
        var rng = SplitMix64(seed: recipe.seed)
        let palette = landscapePalette(for: recipe.id)
        let sunX = rng.nextDouble(in: 0.25...0.75)
        let sunY = rng.nextDouble(in: 0.18...0.4)
        let sunR = rng.nextDouble(in: 0.06...0.12)
        let horizon = rng.nextDouble(in: 0.58...0.7)
        let aspect = Double(width) / Double(height)

        // Ridge lines: layered sine sums between sky and horizon.
        struct Ridge { var base: Double; var a1: Double; var f1: Double; var p1: Double
                       var a2: Double; var f2: Double; var p2: Double }
        var ridges = [Ridge]()
        let n = palette.ridges.count
        for i in 0..<n {
            let depth = Double(i) / Double(max(1, n - 1)) // 0 far → 1 near
            ridges.append(Ridge(
                base: horizon - 0.16 * (1 - depth) + 0.04 * depth,
                a1: rng.nextDouble(in: 0.02...0.06) * (0.6 + 0.6 * depth),
                f1: rng.nextDouble(in: 1.5...3.5),
                p1: rng.nextDouble(in: 0...(2 * .pi)),
                a2: rng.nextDouble(in: 0.008...0.02),
                f2: rng.nextDouble(in: 5...11),
                p2: rng.nextDouble(in: 0...(2 * .pi))))
        }
        let stripePhase = rng.nextDouble(in: 0...(2 * .pi))

        var buffer = PixelBuffer(width: width, height: height)
        for y in 0..<height {
            let v = Double(y) / Double(height - 1)
            for x in 0..<width {
                let u = Double(x) / Double(width - 1)

                // Sky wash + sun disc with soft edge and wide glow.
                var c = palette.skyTop.mixed(with: palette.skyBottom, t: smoothstep(v / max(0.0001, horizon)))
                let dx = (u - sunX) * aspect
                let dy = v - sunY
                let d = (dx * dx + dy * dy).squareRoot() - sunR
                c = c.mixed(with: palette.sun, t: 0.55 * exp(-max(0, d) * 9))
                if d < 0 {
                    c = c.mixed(with: palette.sun, t: smoothstep(min(1, -d / 0.015)))
                }

                // Sea below the horizon (drawn before ridges so headlands
                // overlap it), with a shimmering sun column.
                if let sea = palette.sea, v >= horizon {
                    let depth = (v - horizon) / max(0.0001, 1 - horizon)
                    var s = sea.far.mixed(with: sea.near, t: smoothstep(depth))
                    let stripe = max(0, sin(v * 160 + stripePhase)) * 0.5 + 0.5
                    let glint = exp(-abs(u - sunX) * 14) * (0.25 + 0.3 * stripe) * (1 - depth)
                    s = s.mixed(with: palette.sun, t: min(0.6, glint))
                    c = s
                }

                // Ridges far → near; each covers everything below its line.
                for (i, ridge) in ridges.enumerated() {
                    let line = ridge.base
                        + ridge.a1 * sin(u * .pi * ridge.f1 + ridge.p1)
                        + ridge.a2 * sin(u * .pi * ridge.f2 + ridge.p2)
                    if v >= line {
                        var tone = palette.ridges[i]
                        // Rim light near the crest, facing the sun.
                        let crest = smoothstep(min(1, (v - line) / 0.02))
                        let facing = max(0, 1 - abs(u - sunX) * 2)
                        tone = tone.mixed(with: palette.sun, t: (1 - crest) * 0.25 * facing)
                        c = tone
                    }
                }

                let grain = (CouchHash.noise(x, y, seed: recipe.seed) - 0.5) * 0.03
                buffer.setPixel(x: x, y: y, c.offset(by: grain).rgb8)
            }
        }
        return buffer
    }

    // MARK: - Shared helpers

    static func sample(stops: [(Double, RGBF)], at t: Double) -> RGBF {
        let t = max(0, min(1, t))
        guard let first = stops.first else { return RGBF(0, 0, 0) }
        if t <= first.0 { return first.1 }
        for i in 1..<stops.count {
            let (t1, c1) = stops[i]
            let (t0, c0) = stops[i - 1]
            if t <= t1 {
                let span = max(0.0001, t1 - t0)
                return c0.mixed(with: c1, t: (t - t0) / span)
            }
        }
        return stops[stops.count - 1].1
    }

    static func smoothstep(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return x * x * (3 - 2 * x)
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 17
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}

/// Internal floating-point color for procedural generation.
struct RGBF {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    func mixed(with other: RGBF, t: Double) -> RGBF {
        let t = max(0, min(1, t))
        return RGBF(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    func offset(by delta: Double) -> RGBF {
        RGBF(r + delta, g + delta, b + delta)
    }

    var rgb8: RGB {
        RGB(
            UInt8(max(0, min(255, (r * 255).rounded()))),
            UInt8(max(0, min(255, (g * 255).rounded()))),
            UInt8(max(0, min(255, (b * 255).rounded())))
        )
    }
}
