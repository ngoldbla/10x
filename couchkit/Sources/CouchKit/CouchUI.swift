// CouchUI foundations: typography, palette, accent derivation, springs.
// Art direction: "Pixels under glass" — dark-first, content full-bleed,
// chrome transient. No component in this file draws an opaque background.
#if os(tvOS)
import SwiftUI
@_exported import CouchCore

// MARK: - Typography

/// The suite type ramp, sized for a 3-meter viewing distance. SF Rounded.
public enum CouchTypography {
    /// Hero numerals, scores, the one huge word. 96pt heavy.
    public static let display = Font.system(size: 96, weight: .heavy, design: .rounded)
    /// Screen titles and big answers. 64pt bold.
    public static let title = Font.system(size: 64, weight: .bold, design: .rounded)
    /// Everything readable. 38pt medium.
    public static let body = Font.system(size: 38, weight: .medium, design: .rounded)
    /// Chips, dates, footnotes. 29pt semibold (small type needs weight on TV).
    public static let caption = Font.system(size: 29, weight: .semibold, design: .rounded)
}

extension View {
    /// Apply a ramp font with the suite's default vibrant foreground.
    public func couchText(_ font: Font) -> some View {
        self.font(font).foregroundStyle(.primary)
    }
}

// MARK: - Palette

/// Dark-first color tokens. Content supplies the color; chrome stays neutral.
public enum CouchPalette {
    /// True black — the resting background of every app.
    public static let void = Color(red: 0, green: 0, blue: 0)
    /// Near-black with a breath of blue, for layered dark surfaces.
    public static let ink = Color(red: 0.055, green: 0.06, blue: 0.08)
    /// Warm off-white for text on dark and inkline art.
    public static let paper = Color(red: 0.93, green: 0.9, blue: 0.84)
    /// Accent used before any content has been analyzed.
    public static let fallbackAccent = Color(red: 0.77, green: 0.75, blue: 0.71)
}

extension Color {
    /// Bridge a CouchCore color into SwiftUI.
    public init(_ rgb: RGB) {
        self.init(
            red: Double(rgb.r) / 255,
            green: Double(rgb.g) / 255,
            blue: Double(rgb.b) / 255
        )
    }
}

/// Extracts a display-safe accent from content so glass tints follow the art.
/// The math (dominant hue, clamped saturation/luminance) lives in
/// `CouchCore.AccentMath`; this is only the `Color` adapter.
public enum AccentDerivation {
    public static func accent(from buffer: PixelBuffer) -> Color {
        Color(AccentMath.accent(for: buffer))
    }

    public static func accent(from grid: CellGrid) -> Color {
        // Cell foregrounds are already content-representative samples.
        guard !grid.cells.isEmpty else { return CouchPalette.fallbackAccent }
        var buffer = PixelBuffer(width: grid.cols, height: grid.rows)
        for y in 0..<grid.rows {
            for x in 0..<grid.cols {
                buffer.setPixel(x: x, y: y, grid[x, y].background)
            }
        }
        return Color(AccentMath.accent(for: buffer))
    }
}

// MARK: - Motion

extension Animation {
    /// Focus and chrome response: quick, physical, never bouncing twice.
    public static let couchFast = Animation.spring(response: 0.18, dampingFraction: 0.86)
    /// Ambient drift and crossfades: slow enough to feel like weather.
    public static let couchAmbient = Animation.spring(response: 2.4, dampingFraction: 1.0)
}
#endif
