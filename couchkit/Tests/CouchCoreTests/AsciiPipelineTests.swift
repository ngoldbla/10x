import XCTest
@testable import CouchCore

final class AsciiPipelineTests: XCTestCase {

    private func demoBuffer(_ id: String = "dunes", width: Int = 160, height: Int = 90) -> PixelBuffer {
        DemoArt.render(DemoArt.recipe(id: id)!, width: width, height: height)
    }

    // MARK: Determinism

    func testPipelineIsDeterministicForEveryStyle() {
        let buffer = demoBuffer()
        for style in AsciiStyle.allCases {
            let a = AsciiRenderer.render(buffer, style: style, grid: .fit(cols: 64), seed: 42)
            let b = AsciiRenderer.render(buffer, style: style, grid: .fit(cols: 64), seed: 42)
            XCTAssertEqual(a, b, "style \(style) must be byte-identical for the same seed")
        }
    }

    func testTerminalPaletteChangesWithSeed() {
        // Different k-means seeds are allowed to converge, but on a rich
        // demo image the grids should differ for at least one seed pair.
        let buffer = demoBuffer("neon-tide")
        let grids = [0, 1, 7, 99].map {
            AsciiRenderer.render(buffer, style: .terminal, grid: .fit(cols: 48), seed: UInt64($0))
        }
        XCTAssertTrue(
            (1..<grids.count).contains { grids[$0] != grids[0] },
            "expected at least one seed to yield a different quantization"
        )
    }

    // MARK: Grid geometry

    func testGridSpecAspectCorrection() {
        // 16:9 image, glyph cells (0.5 aspect): rows = 100 * (9/16) * 0.5 ≈ 28.
        let spec = GridSpec.fit(cols: 100)
        XCTAssertEqual(spec.rows(imageWidth: 1600, imageHeight: 900, style: .terminal), 28)
        // Tile cells are square: rows = 100 * (9/16) ≈ 56.
        XCTAssertEqual(spec.rows(imageWidth: 1600, imageHeight: 900, style: .pixel), 56)
        // Explicit cell aspect overrides the style default.
        let custom = GridSpec.fit(cols: 100, cellAspect: 1.0)
        XCTAssertEqual(custom.rows(imageWidth: 1600, imageHeight: 900, style: .terminal), 56)
    }

    func testRenderedGridHasExpectedDimensions() {
        let buffer = demoBuffer(width: 320, height: 180)
        let grid = AsciiRenderer.render(buffer, style: .mosaic, grid: .fit(cols: 40), seed: 0)
        XCTAssertEqual(grid.cols, 40)
        XCTAssertEqual(grid.rows, 23) // 40 * (180/320) * 1.0 = 22.5 → 23
        XCTAssertEqual(grid.cells.count, 40 * 23)
    }

    // MARK: Luminance + downsample

    func testLuminanceExtremes() {
        XCTAssertEqual(RGB.black.luminance, 0, accuracy: 0.0001)
        XCTAssertEqual(RGB.white.luminance, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(RGB(0, 255, 0).luminance, RGB(0, 0, 255).luminance)
    }

    func testDownsampleAveragesRegions() {
        // Left half pure red, right half pure blue.
        var buffer = PixelBuffer(width: 8, height: 4)
        for y in 0..<4 {
            for x in 0..<8 {
                buffer.setPixel(x: x, y: y, x < 4 ? RGB(255, 0, 0) : RGB(0, 0, 255))
            }
        }
        let field = AsciiPipeline.downsample(buffer, cols: 2, rows: 1)
        XCTAssertEqual(field.colors[0], RGB(255, 0, 0))
        XCTAssertEqual(field.colors[1], RGB(0, 0, 255))
    }

    // MARK: Quantization

    func testQuantizeTwoColorImageFindsBothColors() {
        let colors = Array(repeating: RGB(250, 10, 10), count: 50)
            + Array(repeating: RGB(10, 10, 250), count: 50)
        let (palette, assignment) = AsciiPipeline.quantize(colors, paletteSize: 4, seed: 7)
        XCTAssertFalse(palette.isEmpty)
        XCTAssertEqual(assignment.count, colors.count)
        // Every input must be assigned to a centroid close to itself.
        for (i, c) in colors.enumerated() {
            let d = c.distanceSquared(to: palette[assignment[i]])
            XCTAssertLessThan(d, 40 * 40, "color \(i) badly quantized")
        }
        // And the reds and blues must not share a centroid.
        XCTAssertNotEqual(assignment.first, assignment.last)
    }

    func testQuantizeIsDeterministic() {
        let buffer = demoBuffer("aurora")
        let field = AsciiPipeline.downsample(buffer, cols: 32, rows: 16)
        let a = AsciiPipeline.quantize(field.colors, paletteSize: 8, seed: 3)
        let b = AsciiPipeline.quantize(field.colors, paletteSize: 8, seed: 3)
        XCTAssertEqual(a.palette, b.palette)
        XCTAssertEqual(a.assignment, b.assignment)
    }

    func testPixelStyleUsesOnlyChunkyPalette() {
        let grid = AsciiRenderer.render(demoBuffer(), style: .pixel, grid: .fit(cols: 32), seed: 0)
        let palette = Set(AsciiPipeline.chunky16)
        for cell in grid.cells {
            XCTAssertTrue(palette.contains(cell.background))
            XCTAssertEqual(cell.foreground, cell.background)
            XCTAssertEqual(cell.symbol, " ")
        }
    }

    // MARK: Edges

    func testSobelFindsVerticalEdge() {
        // Black left half, white right half → strong horizontal gradient at
        // the seam, ~zero elsewhere.
        var buffer = PixelBuffer(width: 32, height: 16)
        for y in 0..<16 {
            for x in 16..<32 {
                buffer.setPixel(x: x, y: y, .white)
            }
        }
        let field = AsciiPipeline.downsample(buffer, cols: 16, rows: 8)
        let edges = AsciiPipeline.edgeField(of: field)
        let midRow = 4
        let seam = edges.magnitude[midRow * 16 + 8]
        let flat = edges.magnitude[midRow * 16 + 2]
        XCTAssertGreaterThan(seam, 0.9)
        XCTAssertLessThan(flat, 0.05)
        // Gradient points along +x → angle ≈ 0 at the seam.
        XCTAssertEqual(abs(edges.angle[midRow * 16 + 8]), 0, accuracy: 0.01)
    }

    func testInklineIsQuietOnFlatImages() {
        let flat = PixelBuffer(width: 64, height: 36, fill: RGB(128, 128, 128))
        let grid = AsciiRenderer.render(flat, style: .inkline, grid: .fit(cols: 32), seed: 0)
        XCTAssertTrue(grid.cells.allSatisfy { $0.symbol == " " })
    }

    func testTerminalRampOrdersByLuminance() {
        XCTAssertEqual(AsciiRenderer.rampSymbol(for: 0), " ")
        XCTAssertEqual(AsciiRenderer.rampSymbol(for: 1), "@")
        XCTAssertEqual(AsciiRenderer.rampSymbol(for: -1), " ")
        XCTAssertEqual(AsciiRenderer.rampSymbol(for: 2), "@")
    }
}
