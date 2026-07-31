// SharedPalette.swift — Nine's palette as numbers, for the processes that
// cannot have SwiftUI.
//
// `SharedAppearance` has carried the player's theme and accent as raw strings
// since PRD-6, and `Sources/App/Theme.swift` has been the only thing able to
// turn those strings into colour. That is fine for the watch, which compiles
// `Theme.swift` by name, and it is why `Sources/Widgets/DailyWidgetViews.swift`
// has a private `WidgetPalette` holding one hardcoded blue: the widget
// extension does not compile the App tree, so on a Camel-and-Orchid phone the
// Home Screen has always been glacier on paper.
//
// Nobody noticed because the three shipped widgets are small and glanceable.
// PRD-30 is where it becomes obvious — a StandBy face is the biggest thing Nine
// draws on any screen, and a Lock Screen board glyph sits next to the app icon.
//
// **These numbers are a second copy and that is deliberate**, for the reason
// `AccentChoice.lightBarRGB` already gives at `Theme.swift:76-78`: SwiftUI
// `Color` → RGB round-tripping is unreliable, so the components are written out
// in parallel rather than extracted. The protection against drift is a test, not
// a compiler — `Tests/EngineTests/SharedPaletteTests.swift` reads `Theme.swift`
// as text and fails if any triple here disagrees with the one there, in either
// direction, including a case added to one and not the other.
import Foundation

/// An RGB triple in the same 0…1 space `SwiftUI.Color(red:green:blue:)` takes.
public struct PaletteRGB: Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Theme and accent resolved from `SharedAppearance`'s raw strings.
///
/// Every lookup is total: an unrecognised string resolves to the same thing an
/// unpublished one does. A widget meeting a theme from a newer build renders in
/// the default rather than not rendering, which is the rule every other
/// cross-version reader in this tree follows.
public enum SharedPalette {

    // MARK: Accents

    /// The vivid tint, for dark grounds. Parallel to `AccentChoice.color`.
    public static let accentsOnDark: [String: PaletteRGB] = [
        "glacier": PaletteRGB(0.33, 0.68, 0.98),
        "ember": PaletteRGB(1.00, 0.56, 0.20),
        "meadow": PaletteRGB(0.36, 0.84, 0.48),
        "lilac": PaletteRGB(0.66, 0.50, 0.98),
        "crimson": PaletteRGB(1.00, 0.36, 0.56),
        "gold": PaletteRGB(0.98, 0.75, 0.18),
        "teal": PaletteRGB(0.15, 0.80, 0.76),
        "magenta": PaletteRGB(0.88, 0.42, 0.90),
        "moss": PaletteRGB(0.62, 0.85, 0.30),
        "orchid": PaletteRGB(0.94, 0.38, 0.68),
    ]

    /// The deepened tint, for light grounds. Parallel to
    /// `AccentChoice.color(isLight:)`'s `guard isLight else` arm. PRD-22 measured
    /// what the vivid values cost on paper; these are the numbers that fixed it.
    public static let accentsOnLight: [String: PaletteRGB] = [
        "glacier": PaletteRGB(0.07, 0.34, 0.66),
        "ember": PaletteRGB(0.57, 0.25, 0.02),
        "meadow": PaletteRGB(0.08, 0.40, 0.20),
        "lilac": PaletteRGB(0.39, 0.26, 0.70),
        "crimson": PaletteRGB(0.67, 0.11, 0.28),
        "gold": PaletteRGB(0.46, 0.32, 0.01),
        "teal": PaletteRGB(0.02, 0.39, 0.37),
        "magenta": PaletteRGB(0.58, 0.16, 0.58),
        "moss": PaletteRGB(0.27, 0.38, 0.04),
        "orchid": PaletteRGB(0.66, 0.08, 0.39),
    ]

    public static let defaultAccent = "glacier"

    public static func accent(_ raw: String, isLight: Bool) -> PaletteRGB {
        let table = isLight ? accentsOnLight : accentsOnDark
        return table[raw] ?? table[defaultAccent]!
    }

    // MARK: Themes

    /// A theme's ground and the ink its givens are drawn in — the two tones a
    /// glanceable surface needs. Parallel to `ThemeChoice.tones(for:)`'s
    /// `background` and `digitTone`. The four other `ThemeTones` members
    /// (`gridTone`, `coral`, `plane`, `hairline`) are board-drawing concerns and
    /// are deliberately absent: a widget draws no grid, marks no errors and lays
    /// down no wash, and copying tones nothing renders is how two palettes start
    /// to drift.
    public struct ThemeGround: Equatable, Sendable {
        public let background: PaletteRGB
        public let digit: PaletteRGB
        public let isLight: Bool

        public init(background: PaletteRGB, digit: PaletteRGB, isLight: Bool) {
            self.background = background
            self.digit = digit
            self.isLight = isLight
        }
    }

    /// Void's ground. **Not `CouchPalette.void` and not pure black** — see the
    /// comment above `case .dark` in `Theme.swift` for why: `.glassEffect` has
    /// nothing to refract over #000000, so the app's every glass card measured
    /// between 1.005:1 and 1.08:1 against the page it floated on. #0C0C0F is the
    /// smallest lift that gives the material something to bend.
    ///
    /// It matters here and not only in the App layer because the widget process
    /// draws this ground too, and a Home Screen tile that is pure black beside
    /// an app that is not is a visible seam.
    static let darkGround = PaletteRGB(0.047, 0.047, 0.059)
    /// `CouchPalette.paper`, written out because CouchKit is a SwiftUI package
    /// and this file may not import it.
    static let couchPaper = PaletteRGB(0.93, 0.9, 0.84)

    public static let themes: [String: ThemeGround] = [
        "dark": ThemeGround(background: darkGround, digit: couchPaper, isLight: false),
        "light": ThemeGround(
            background: PaletteRGB(0.94, 0.93, 0.90),
            digit: PaletteRGB(0.17, 0.16, 0.14),
            isLight: true
        ),
        "camel": ThemeGround(
            background: PaletteRGB(0.80, 0.70, 0.55),
            digit: PaletteRGB(0.23, 0.15, 0.07),
            isLight: true
        ),
        "blueprint": ThemeGround(
            background: PaletteRGB(0.05, 0.14, 0.33),
            digit: PaletteRGB(0.86, 0.92, 1.00),
            isLight: false
        ),
        "forest": ThemeGround(
            background: PaletteRGB(0.05, 0.13, 0.09),
            digit: PaletteRGB(0.89, 0.94, 0.88),
            isLight: false
        ),
        "ember": ThemeGround(
            background: PaletteRGB(0.14, 0.05, 0.03),
            digit: PaletteRGB(0.99, 0.91, 0.85),
            isLight: false
        ),
        "tide": ThemeGround(
            background: PaletteRGB(0.02, 0.12, 0.14),
            digit: PaletteRGB(0.86, 0.96, 0.96),
            isLight: false
        ),
        "mono": ThemeGround(
            background: PaletteRGB(0.11, 0.11, 0.12),
            digit: PaletteRGB(0.95, 0.95, 0.96),
            isLight: false
        ),
    ]

    /// `auto` is not in the table on purpose: it has no tones of its own and
    /// `ThemeChoice.tones(for:)` delegates it to `light` or `dark` by the
    /// resolved system scheme. A caller in another process has that scheme from
    /// its own environment, so it answers the same question the same way.
    public static let autoTheme = "auto"

    /// - Parameter systemIsLight: the *resolved* colour scheme of the surface
    ///   asking. Only consulted for `auto`, exactly as in the App layer.
    public static func theme(_ raw: String, systemIsLight: Bool) -> ThemeGround {
        if raw == autoTheme || raw.isEmpty || themes[raw] == nil {
            return themes[systemIsLight ? "light" : "dark"]!
        }
        return themes[raw]!
    }

    /// The pair, resolved together — the only call most surfaces need. The
    /// accent's light/dark variant follows the *theme's* leaning and not the
    /// system's, which is the bug this function exists to make unrepeatable:
    /// Camel is a light theme on a phone in dark mode, and a vivid accent on
    /// Camel is PRD-22's 3.36:1.
    public static func resolve(
        _ appearance: SharedAppearance,
        systemIsLight: Bool
    ) -> (ground: ThemeGround, accent: PaletteRGB) {
        let ground = theme(appearance.theme, systemIsLight: systemIsLight)
        return (ground, accent(appearance.accent, isLight: ground.isLight))
    }
}
