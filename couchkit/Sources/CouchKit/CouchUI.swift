// CouchUI foundations: typography, palette, accent derivation, springs.
// Art direction: "Pixels under glass" — dark-first, content full-bleed,
// chrome transient. No component in this file draws an opaque background.
#if os(tvOS) || os(iOS) || os(macOS) || os(watchOS)
import SwiftUI
@_exported import CouchCore

// MARK: - Typography

/// The suite type ramp. SF Rounded everywhere; sizes are per-platform —
/// tvOS is set for a 3-meter viewing distance, iOS for handheld.
///
/// **Seven rungs, and on handheld platforms they scale.** The ramp shipped with
/// four fixed `Font.system(size:)` steps, which meant `relativeTo:`,
/// `@ScaledMetric` and `dynamicTypeSize` appeared exactly zero times in the
/// whole suite and Dynamic Type did literally nothing: a player who set Larger
/// Text to an accessibility size saw no pixel move. The non-tvOS rungs are now
/// `Font.system(_ style:design:weight:)` — the same SF Rounded faces at the same
/// default sizes, resolved against the environment's text style, so they grow
/// and shrink with the system setting.
///
/// **tvOS and watchOS stay fixed on purpose.** A television is read at three
/// metres by whoever is in the room, and tvOS has no per-app Dynamic Type
/// control worth reacting to; the watch's 198pt-wide screen is authored to the
/// pixel and a two-step growth overflows it. Four sibling apps (Rabbit Ears,
/// Darkroom, Blockhead, Cartridge) are tvOS-only and render byte-identically to
/// what they shipped: every tvOS constant below is unchanged.
///
/// Three rungs are new, and each one existed already as a hand-inlined literal:
///
/// | rung | was |
/// |---|---|
/// | `heading` | `Font.system(size: 15, …)` inlined 8 times |
/// | `label` | the old `caption` — 13pt semibold, 88 sites |
/// | `caption` | `Font.system(size: 11, …)` inlined 19 times |
/// | `numeral` | nothing — the live timer had no tabular figures at all |
///
/// **`caption` changed meaning.** It is now the 11pt tier; the 13pt tier it used
/// to be is `label`. On tvOS and watchOS the two are the same font, so no
/// existing tvOS call site moves; on iOS and macOS a site that means "footnote"
/// must say `label`.
public enum CouchTypography {
    #if os(tvOS)
    /// Hero numerals, scores, the one huge word. 96pt heavy.
    public static let display = Font.system(size: 96, weight: .heavy, design: .rounded)
    /// Screen titles and big answers. 64pt bold.
    public static let title = Font.system(size: 64, weight: .bold, design: .rounded)
    /// A section head — between a title and body copy. 46pt semibold.
    public static let heading = Font.system(size: 46, weight: .semibold, design: .rounded)
    /// Everything readable. 38pt medium.
    public static let body = Font.system(size: 38, weight: .medium, design: .rounded)
    /// Chips, dates, footnotes. 29pt semibold (small type needs weight on TV).
    public static let label = Font.system(size: 29, weight: .semibold, design: .rounded)
    /// Identical to `label` on tvOS: a screen read across a room has no room
    /// for a tier below the footnote, and holding it here keeps every shipped
    /// tvOS call site rendering exactly what it rendered before.
    public static let caption = Font.system(size: 29, weight: .semibold, design: .rounded)
    /// A number that changes while you are looking at it. Tabular figures, so
    /// a ticking clock does not re-measure its own capsule every second.
    public static let numeral = Font.system(size: 38, weight: .semibold, design: .rounded)
        .monospacedDigit()
    #elseif os(watchOS)
    // A 45mm screen is ~198pt wide, so the handheld ramp below overflows it:
    // `title` at 30pt fits four characters. These are the handheld sizes taken
    // down roughly a third, with `caption` held at 12 rather than 11 because
    // below that SF Rounded stops being legible at arm's length in sunlight
    // (PRD-6 §5's outdoor-readability risk). `display` is unused on the wrist
    // and kept only so the ramp stays total.
    public static let display = Font.system(size: 34, weight: .heavy, design: .rounded)
    public static let title = Font.system(size: 22, weight: .bold, design: .rounded)
    public static let heading = Font.system(size: 17, weight: .semibold, design: .rounded)
    public static let body = Font.system(size: 15, weight: .medium, design: .rounded)
    public static let label = Font.system(size: 12, weight: .semibold, design: .rounded)
    /// Held equal to `label` for the same sunlight reason the 12 is: there is
    /// no legible rung below this one on a wrist.
    public static let caption = Font.system(size: 12, weight: .semibold, design: .rounded)
    public static let numeral = Font.system(size: 15, weight: .semibold, design: .rounded)
        .monospacedDigit()
    #else
    /// Hero numerals, scores, the one huge word. `.largeTitle` heavy.
    public static let display = Font.system(.largeTitle, design: .rounded, weight: .heavy)
    /// Screen titles and big answers. `.title` bold.
    public static let title = Font.system(.title, design: .rounded, weight: .bold)
    /// A section head inside a screen — the tier between a title and body copy.
    /// `.title3` semibold.
    public static let heading = Font.system(.title3, design: .rounded, weight: .semibold)
    /// Everything readable. `.body` medium.
    public static let body = Font.system(.body, design: .rounded, weight: .medium)
    /// Chips, row labels, footnotes — the workhorse. `.footnote` semibold.
    public static let label = Font.system(.footnote, design: .rounded, weight: .semibold)
    /// The tier below a label: metadata, units, a card's secondary line.
    /// `.caption` medium.
    public static let caption = Font.system(.caption, design: .rounded, weight: .medium)
    /// A number that changes while you are looking at it — a clock, a score, a
    /// countdown. `.headline` with **tabular figures**, so the capsule around it
    /// stops re-measuring on every tick.
    public static let numeral = Font.system(.headline, design: .rounded, weight: .semibold)
        .monospacedDigit()
    #endif
}

/// Per-platform chrome scale: paddings, icon sizes and hit targets in shared
/// components multiply by this instead of forking every literal.
public enum CouchScale {
    #if os(tvOS)
    public static let chrome: CGFloat = 1.0
    #elseif os(macOS)
    // Desk viewing distance sits between the couch (1.0) and the hand
    // (0.55): a pointer-scale chrome that still reads across a room (PRD-4
    // §0). First-guess per PRD; tune on screenshot review.
    public static let chrome: CGFloat = 0.70
    #elseif os(watchOS)
    // PRD-6 §4 Step 0 fixes this number. Wrist distance is closer than the
    // hand (0.55), but the screen is a quarter the size, so chrome has to give
    // up more than viewing distance alone would ask.
    public static let chrome: CGFloat = 0.42
    #else
    public static let chrome: CGFloat = 0.55
    #endif
}

extension View {
    /// Apply a ramp font with the suite's default vibrant foreground.
    ///
    /// **This hard-sets `.primary`, which makes chaining a foreground *after*
    /// it a no-op** — and five sites in Nine's channel shelf do exactly that
    /// (`.couchText(CouchTypography.caption).foregroundStyle(.secondary)`
    /// renders primary, because the last `foregroundStyle` in the chain wins
    /// only when it is applied to a view that has not already resolved one, and
    /// here it is applied *outside* the one this modifier planted). Rather than
    /// change what this overload does to its 40-odd existing call sites, the
    /// overload below makes the trap unenterable: a caller who wants a
    /// hierarchy says so in the same call.
    public func couchText(_ font: Font) -> some View {
        self.font(font).foregroundStyle(.primary)
    }

    /// Apply a ramp font with an explicit foreground — `.secondary`, `.tint`, a
    /// resolved accent, a gradient. Use this instead of chaining a foreground
    /// after `couchText(_:)`, which silently does nothing.
    public func couchText(_ font: Font, _ style: some ShapeStyle) -> some View {
        self.font(font).foregroundStyle(style)
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
