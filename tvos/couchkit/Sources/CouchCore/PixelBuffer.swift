import Foundation

/// An 8-bit sRGB color triple — the currency of the CouchCore pipeline.
public struct RGB: Hashable, Sendable, Codable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(255, 255, 255)

    /// Rec. 709 relative luminance in `[0, 1]` (gamma-space approximation —
    /// good enough for glyph ramps, cheap enough for full frames).
    public var luminance: Double {
        (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
    }

    /// Component-wise scale, clamped to `[0, 255]`.
    public func scaled(by factor: Double) -> RGB {
        func s(_ v: UInt8) -> UInt8 { UInt8(max(0, min(255, (Double(v) * factor).rounded()))) }
        return RGB(s(r), s(g), s(b))
    }

    /// Linear mix toward `other` by `t` in `[0, 1]`.
    public func mixed(with other: RGB, t: Double) -> RGB {
        let t = max(0, min(1, t))
        func m(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8(max(0, min(255, (Double(a) + (Double(b) - Double(a)) * t).rounded())))
        }
        return RGB(m(r, other.r), m(g, other.g), m(b, other.b))
    }

    /// Squared distance in RGB space (avoids the sqrt in hot loops).
    public func distanceSquared(to other: RGB) -> Int {
        let dr = Int(r) - Int(other.r)
        let dg = Int(g) - Int(other.g)
        let db = Int(b) - Int(other.b)
        return dr * dr + dg * dg + db * db
    }
}

/// A CPU-side RGBA8 image. Row-major, 4 bytes per pixel, no padding.
/// This is the interchange type between platform images (CGImage on device,
/// procedural DemoArt everywhere) and the render pipeline.
public struct PixelBuffer: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        precondition(width > 0 && height > 0, "PixelBuffer must be non-empty")
        precondition(rgba.count == width * height * 4, "rgba must be width*height*4 bytes")
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    public init(width: Int, height: Int, fill: RGB = .black) {
        precondition(width > 0 && height > 0, "PixelBuffer must be non-empty")
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = fill.r
            bytes[i + 1] = fill.g
            bytes[i + 2] = fill.b
        }
        self.rgba = bytes
    }

    @inlinable
    public func pixel(x: Int, y: Int) -> RGB {
        let i = (y * width + x) * 4
        return RGB(rgba[i], rgba[i + 1], rgba[i + 2])
    }

    @inlinable
    public mutating func setPixel(x: Int, y: Int, _ color: RGB) {
        let i = (y * width + x) * 4
        rgba[i] = color.r
        rgba[i + 1] = color.g
        rgba[i + 2] = color.b
        rgba[i + 3] = 255
    }
}
