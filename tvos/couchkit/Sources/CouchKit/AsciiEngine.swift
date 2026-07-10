// AsciiEngine — the platform half of AsciiKit. CouchCore decides every cell
// (deterministically); this actor only moves pixels: CGImage ↔ PixelBuffer
// adapters and CellGrid → CGImage drawing.
//
// Canvas policy: rendering is capped at 1920×1080. The tvOS compositor
// upscales to 4K for free, cell art has no detail beyond its grid anyway,
// and glyph rasterization at 3840×2160 quadruples CPU time for zero visible
// gain at a 3-meter viewing distance.
#if canImport(SwiftUI)
import SwiftUI
import CouchCore
#if canImport(CoreGraphics)
import CoreGraphics
import CoreText
#endif

public enum AsciiEngineError: Error, Sendable {
    case adapterFailed
    case emptyImage
}

/// Serializes render work off the main actor. Feed it a `CGImage` (or a
/// DemoArt recipe), get back a ready-to-display frame.
public actor AsciiEngine {
    public static let shared = AsciiEngine()

    public init() {}

    /// Maximum render canvas (see header note).
    public static let maxCanvas = CGSize(width: 1920, height: 1080)

    /// Render a photo. Deterministic: same image + grid + seed ⇒ same frame.
    public func render(
        image: CGImage,
        style: AsciiStyle,
        grid: GridSpec = .fit(cols: 160),
        seed: UInt64 = 0
    ) throws -> CGImage {
        guard let buffer = Self.pixelBuffer(from: image) else {
            throw AsciiEngineError.adapterFailed
        }
        let cellGrid = AsciiRenderer.render(buffer, style: style, grid: grid, seed: seed)
        guard let frame = Self.draw(grid: cellGrid, style: style) else {
            throw AsciiEngineError.adapterFailed
        }
        return frame
    }

    /// Render straight to a `CellGrid` when the caller draws cells itself
    /// (Darkroom's board compiler).
    public func renderGrid(
        image: CGImage,
        style: AsciiStyle,
        grid: GridSpec = .fit(cols: 160),
        seed: UInt64 = 0
    ) throws -> CellGrid {
        guard let buffer = Self.pixelBuffer(from: image) else {
            throw AsciiEngineError.adapterFailed
        }
        return AsciiRenderer.render(buffer, style: style, grid: grid, seed: seed)
    }

    /// Render a procedural demo "photo" — the zero-permission path.
    public func renderDemo(
        recipe: DemoArtRecipe,
        style: AsciiStyle,
        grid: GridSpec = .fit(cols: 160),
        seed: UInt64? = nil
    ) throws -> CGImage {
        let buffer = DemoArt.render(recipe, width: 640, height: 360)
        let cellGrid = AsciiRenderer.render(
            buffer, style: style, grid: grid, seed: seed ?? recipe.seed
        )
        guard let frame = Self.draw(grid: cellGrid, style: style) else {
            throw AsciiEngineError.adapterFailed
        }
        return frame
    }

    // MARK: - Adapters

    /// Decode a CGImage into an RGBA8 `PixelBuffer`, downscaling so the long
    /// edge is at most `maxDimension` (the grid never needs more).
    public nonisolated static func pixelBuffer(from image: CGImage, maxDimension: Int = 960) -> PixelBuffer? {
        let scale = min(1, Double(maxDimension) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        return PixelBuffer(width: width, height: height, rgba: bytes)
    }

    /// Wrap a `PixelBuffer` (e.g. raw DemoArt) as a CGImage for direct display.
    public nonisolated static func cgImage(from buffer: PixelBuffer) -> CGImage? {
        let data = Data(buffer.rgba)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: buffer.width,
            height: buffer.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: buffer.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// Draw a `CellGrid` into a bitmap: background rects always; glyphs via
    /// CoreText for the character styles. CTLines are cached per
    /// (symbol, color) within the pass — grids reuse a small set of both.
    public nonisolated static func draw(
        grid: CellGrid,
        style: AsciiStyle,
        canvas: CGSize? = nil
    ) -> CGImage? {
        guard grid.cols > 0 && grid.rows > 0 else { return nil }
        let bounds = canvas ?? maxCanvas
        let limit = CGSize(
            width: min(bounds.width, maxCanvas.width),
            height: min(bounds.height, maxCanvas.height)
        )
        let aspect = style.preferredCellAspect
        let cellH = max(2, min(
            limit.height / CGFloat(grid.rows),
            limit.width / (CGFloat(grid.cols) * CGFloat(aspect))
        ).rounded(.down))
        let cellW = max(1, (cellH * CGFloat(aspect)).rounded(.down))
        let width = Int(cellW) * grid.cols
        let height = Int(cellH) * grid.rows

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Menlo-Bold" as CFString, cellH * 0.92, nil)
        var lineCache = [Cell: CTLine]()

        for y in 0..<grid.rows {
            for x in 0..<grid.cols {
                let cell = grid[x, y]
                // CG origin is bottom-left; flip rows so cell (0,0) is top-left.
                let rect = CGRect(
                    x: CGFloat(x) * cellW,
                    y: CGFloat(grid.rows - 1 - y) * cellH,
                    width: cellW,
                    height: cellH
                )
                if cell.background != .black {
                    context.setFillColor(cgColor(cell.background))
                    context.fill(rect)
                }
                guard style.usesGlyphs, cell.symbol != " " else { continue }

                let line: CTLine
                if let cached = lineCache[cell] {
                    line = cached
                } else {
                    let attributes: [NSAttributedString.Key: Any] = [
                        NSAttributedString.Key(kCTFontAttributeName as String): font,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                            cgColor(cell.foreground),
                    ]
                    line = CTLineCreateWithAttributedString(
                        NSAttributedString(string: cell.symbol, attributes: attributes)
                    )
                    lineCache[cell] = line
                }
                let lineBounds = CTLineGetBoundsWithOptions(line, [])
                context.textPosition = CGPoint(
                    x: rect.minX + (cellW - lineBounds.width) / 2 - lineBounds.minX,
                    y: rect.minY + (cellH - lineBounds.height) / 2 - lineBounds.minY
                )
                CTLineDraw(line, context)
            }
        }
        return context.makeImage()
    }

    private nonisolated static func cgColor(_ rgb: RGB) -> CGColor {
        CGColor(
            red: CGFloat(rgb.r) / 255,
            green: CGFloat(rgb.g) / 255,
            blue: CGFloat(rgb.b) / 255,
            alpha: 1
        )
    }
}

// MARK: - AsciiArtView

/// Displays a rendered frame full-bleed and, given a `DriftPath`, drifts it
/// slowly — the resting face of every ambient app.
public struct AsciiArtView: View {
    private let image: CGImage?
    private let style: AsciiStyle
    private let drift: DriftPath?
    private let grid: GridSpec
    private let seed: UInt64

    @State private var rendered: CGImage?

    public init(
        image: CGImage?,
        style: AsciiStyle,
        drift: DriftPath? = nil,
        grid: GridSpec = .fit(cols: 160),
        seed: UInt64 = 0
    ) {
        self.image = image
        self.style = style
        self.drift = drift
        self.grid = grid
        self.seed = seed
    }

    private struct RenderKey: Hashable {
        let image: ObjectIdentifier?
        let style: AsciiStyle
        let cols: Int
        let seed: UInt64
    }

    private var renderKey: RenderKey {
        RenderKey(
            image: image.map(ObjectIdentifier.init),
            style: style,
            cols: grid.cols,
            seed: seed
        )
    }

    public var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: drift == nil)) { timeline in
                ZStack {
                    CouchPalette.void
                    if let rendered {
                        let state = drift?.state(at: timeline.date.timeIntervalSinceReferenceDate)
                            ?? .identity
                        Image(decorative: rendered, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(state.zoom)
                            .offset(
                                x: state.offsetX * geo.size.width,
                                y: state.offsetY * geo.size.height
                            )
                    }
                }
            }
        }
        .clipped()
        .ignoresSafeArea()
        .task(id: renderKey) {
            guard let image else {
                rendered = nil
                return
            }
            let frame = try? await AsciiEngine.shared.render(
                image: image, style: style, grid: grid, seed: seed
            )
            if !Task.isCancelled {
                withAnimation(.couchAmbient) { rendered = frame }
            }
        }
    }
}
#endif
