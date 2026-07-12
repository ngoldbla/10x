import XCTest
@testable import CouchCore

final class CoreSupportTests: XCTestCase {

    // MARK: SequencePlanner

    func testNoRepeatWithinWindow() {
        var planner = SequencePlanner(count: 10, window: 4, seed: 99)
        var recent = [Int]()
        for _ in 0..<500 {
            let pick = planner.next()
            XCTAssertTrue((0..<10).contains(pick))
            XCTAssertFalse(recent.suffix(4).contains(pick), "repeat inside the window")
            recent.append(pick)
        }
        // Everything gets airtime.
        XCTAssertEqual(Set(recent).count, 10)
    }

    func testPlannerIsDeterministicAndWindowClamps() {
        var a = SequencePlanner(count: 5, window: 50, seed: 7)
        var b = SequencePlanner(count: 5, window: 50, seed: 7)
        let seqA = (0..<40).map { _ in a.next() }
        let seqB = (0..<40).map { _ in b.next() }
        XCTAssertEqual(seqA, seqB)
        // window clamps to count-1, so consecutive picks never collide and
        // every element appears.
        for i in 1..<seqA.count {
            XCTAssertNotEqual(seqA[i], seqA[i - 1])
        }
        XCTAssertEqual(Set(seqA).count, 5)

        var single = SequencePlanner(count: 1, window: 3, seed: 0)
        XCTAssertEqual(single.next(), 0)
        XCTAssertEqual(single.next(), 0)
    }

    // MARK: DemoArt

    func testDemoArtCatalog() {
        XCTAssertGreaterThanOrEqual(DemoArt.recipes.count, 8)
        XCTAssertEqual(Set(DemoArt.recipes.map(\.id)).count, DemoArt.recipes.count)
        XCTAssertTrue(DemoArt.recipes.allSatisfy { $0.title.hasPrefix("Demo · ") })
        let kinds = Set(DemoArt.recipes.map(\.kind))
        XCTAssertEqual(kinds, [.gradient, .plasma, .landscape])
    }

    func testDemoArtIsDeterministic() {
        for recipe in DemoArt.recipes {
            let a = DemoArt.render(recipe, width: 96, height: 54)
            let b = DemoArt.render(recipe, width: 96, height: 54)
            XCTAssertEqual(a, b, "\(recipe.id) must render identically every time")
        }
    }

    func testDemoArtRecipesAreDistinct() {
        let renders = DemoArt.recipes.map { DemoArt.render($0, width: 48, height: 27) }
        for i in 0..<renders.count {
            for j in (i + 1)..<renders.count {
                XCTAssertNotEqual(renders[i], renders[j], "recipes \(i) and \(j) look identical")
            }
        }
    }

    func testDemoArtHasTonalRange() {
        // Asciified art needs shadows and highlights; a demo photo that is
        // all midtones would render as mush.
        for recipe in DemoArt.recipes {
            let buffer = DemoArt.render(recipe, width: 96, height: 54)
            let field = AsciiPipeline.downsample(buffer, cols: 48, rows: 27)
            let minLum = field.luminance.min() ?? 0
            let maxLum = field.luminance.max() ?? 0
            XCTAssertGreaterThan(maxLum - minLum, 0.25, "\(recipe.id) is tonally flat")
        }
    }

    // MARK: DriftPath

    func testDriftIsDeterministicAndBounded() {
        let a = DriftPath(seed: 5)
        let b = DriftPath(seed: 5)
        for t in stride(from: 0.0, through: 240.0, by: 7.3) {
            XCTAssertEqual(a.state(at: t), b.state(at: t))
            let s = a.state(at: t)
            XCTAssertLessThanOrEqual(abs(s.offsetX), a.maxOffset + 0.0001)
            XCTAssertLessThanOrEqual(abs(s.offsetY), a.maxOffset + 0.0001)
            XCTAssertTrue(a.zoomRange.contains(min(max(s.zoom, a.zoomRange.lowerBound), a.zoomRange.upperBound)))
            XCTAssertGreaterThanOrEqual(s.zoom, a.zoomRange.lowerBound - 0.0001)
            XCTAssertLessThanOrEqual(s.zoom, a.zoomRange.upperBound + 0.0001)
        }
        XCTAssertNotEqual(DriftPath(seed: 6).state(at: 10), a.state(at: 10))
    }

    // MARK: SplitMix64

    func testSplitMixKnownSequence() {
        var rng = SplitMix64(seed: 0)
        // Reference values for SplitMix64(0) — guards against accidental
        // algorithm changes, which would silently re-shuffle every app.
        XCTAssertEqual(rng.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(rng.next(), 0x6E78_9E6A_A1B9_65F4)
        var other = SplitMix64(seed: 123)
        let d = other.nextDouble()
        XCTAssertTrue(d >= 0 && d < 1)
        XCTAssertTrue((0..<7).contains(other.nextInt(below: 7)))
    }

    // MARK: CouchJSON + WriteDebouncer + Keyspace

    private struct Prefs: Codable, Equatable {
        var streak: Int
        var style: AsciiStyle
        var lastPlayed: Date
    }

    func testJSONRoundTripAndStableBytes() throws {
        let prefs = Prefs(
            streak: 12, style: .phosphor,
            lastPlayed: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try CouchJSON.encode(prefs)
        let back = try CouchJSON.decode(Prefs.self, from: data)
        XCTAssertEqual(back, prefs)
        // Sorted keys ⇒ identical bytes for identical values.
        XCTAssertEqual(data, try CouchJSON.encode(prefs))
        XCTAssertTrue(String(data: data, encoding: .utf8)!.contains("phosphor"))
    }

    func testWriteDebouncer() {
        var debouncer = WriteDebouncer(interval: 0.5, maxLatency: 3)
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(debouncer.isDirty)
        XCTAssertFalse(debouncer.shouldFlush(at: t0))

        debouncer.recordChange(at: t0)
        XCTAssertTrue(debouncer.isDirty)
        XCTAssertFalse(debouncer.shouldFlush(at: t0.addingTimeInterval(0.3)))
        XCTAssertTrue(debouncer.shouldFlush(at: t0.addingTimeInterval(0.6)))
        XCTAssertFalse(debouncer.isDirty, "flush must mark clean")

        // Continuous changes: the max-latency backstop still flushes.
        var t = Date(timeIntervalSince1970: 2000)
        debouncer.recordChange(at: t)
        var flushed = false
        for _ in 0..<40 {
            t = t.addingTimeInterval(0.2) // always inside the quiet window
            debouncer.recordChange(at: t)
            if debouncer.shouldFlush(at: t) { flushed = true; break }
        }
        XCTAssertTrue(flushed, "maxLatency backstop never fired")
    }

    func testKeyspaceNamespacing() {
        XCTAssertEqual(CouchKeyspace.namespacedKey("streak", profile: "kai"), "couch.kai.streak")
        XCTAssertEqual(
            CouchKeyspace.namespacedKey("high score/9", profile: "Player One"),
            "couch.Player-One.high-score-9"
        )
        XCTAssertEqual(CouchKeyspace.filename(forKey: "streak"), "default.streak.json")
        XCTAssertEqual(CouchKeyspace.sanitize(""), "unnamed")
    }

    // MARK: AccentMath

    func testAccentDerivation() {
        let red = PixelBuffer(width: 20, height: 20, fill: RGB(220, 30, 30))
        let hue = AccentMath.dominantHue(in: red)
        XCTAssertNotNil(hue)
        // Red sits at hue ≈ 0 (or wraps near 1).
        let h = hue!
        XCTAssertTrue(h < 0.06 || h > 0.94, "red hue was \(h)")

        let accent = AccentMath.accent(for: red)
        let hsv = AccentMath.rgbToHSV(accent)
        XCTAssertEqual(hsv.s, 0.5, accuracy: 0.02)
        XCTAssertEqual(hsv.v, 0.82, accuracy: 0.02)

        // Achromatic content falls back to the neutral accent.
        let gray = PixelBuffer(width: 20, height: 20, fill: RGB(128, 128, 128))
        XCTAssertNil(AccentMath.dominantHue(in: gray))
        XCTAssertEqual(AccentMath.accent(for: gray), RGB(196, 190, 180))
    }

    func testHSVRoundTrip() {
        for c in [RGB(255, 0, 0), RGB(0, 255, 0), RGB(30, 90, 200), RGB(240, 200, 40)] {
            let back = AccentMath.hsvToRGB(AccentMath.rgbToHSV(c))
            XCTAssertLessThanOrEqual(c.distanceSquared(to: back), 9, "\(c) round-tripped badly")
        }
    }
}
