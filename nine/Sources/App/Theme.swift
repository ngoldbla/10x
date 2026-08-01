// Theme.swift — the board's palette, and nothing else.
//
// **Round 4 widened that by exactly two tones and one pair of functions**, and
// the header line above is left standing because `DesignTokens.swift` quotes it
// as the argument for its own existence. What is new is not a second scale
// layer: it is `ThemeTones.surfaceHue` / `.wellHue` — the colour a *surface* is
// made of, as opposed to the colour a *mark* is drawn with — and
// `AccentChoice.actionFill` / `.actionInk`, the fill and label of a filled
// primary action. Both are palette questions that the palette had no answer to,
// which is why every surface in the app was a white wash and every primary
// button was a deepened accent that read as disabled. The *amounts* still live
// in `DesignTokens.Elevation`; only the hues are here.
//
// `AccentChoice`, `ThemeTones`, `ThemeChoice` and the `nineTheme` environment
// key were cut verbatim out of `AppModel.swift` and `NineApp.swift` by PRD-6.
// Not a refactor for tidiness: `BoardView` reads `@Environment(\.nineTheme)`
// and `ThemeTones`, so as long as those lived in `AppModel.swift` the board
// could only be compiled into a target that also compiled the whole 1200-line
// model — its CloudKit store, its Game Center calls, its widget bridge.
//
// The watch app must not compile that model. `LibraryCloudStore` constructs a
// `CKContainer(identifier:)`, which traps on a binary that has the iCloud
// *account* but not the CloudKit *entitlement* — the live defect that means a
// locally-built Nine cannot launch on macOS at all (DEVIATIONS, PRD-20). The
// watch carries KVS and no CloudKit container, so importing `AppModel` would
// have shipped that trap to the wrist. Moving three value types is cheaper
// than either forking the board or widening that guard under a watch PRD.
//
// This file is on the `NineWatch` target's source list by name. Nothing here
// may reach for the model, the library, or a platform API.
import SwiftUI
import CouchKit

/// Accent tints offered in prefs. Vivid, mutually distinct hues; never pure
/// red or green (colorblind-safe rule: errors pair a coral underline with a
/// dot — crimson sits at rose ~345°, far from the coral marker's ~9°).
/// Light-leaning themes get a deepened variant of each hue: the vivid values
/// wash out on high-luminance backgrounds.
///
/// PRD-16 added Moss and Orchid. Their exact values are load-bearing rather
/// than decorative, and `Tests/EngineTests/AppearancePaletteTests.swift` pins
/// them: an accent has to stay legible on all six dark grounds *and* stay
/// separable from its eight siblings and from coral under three kinds of
/// colorblind vision, and those two pull against each other. The obvious
/// candidate for the glacier→lilac gap — a periwinkle indigo — cannot satisfy
/// both: dark enough to stay clear of Lilac, it falls to 4.08:1 on Blueprint's
/// blue ground; light enough to read on Blueprint, it collapses to ΔE 2.05
/// against Lilac under deuteranopia. That gap is closed in practice, so the two
/// hues here fill the gold→meadow gap and the magenta→crimson one instead.
enum AccentChoice: String, Codable, Sendable, CaseIterable {
    case glacier, ember, meadow, lilac, crimson, gold, teal, magenta, moss, orchid

    /// Written out rather than built from `rawValue` on purpose: an
    /// interpolated key is invisible to `scripts/strings.py`, which is the only
    /// thing that would notice a case added here with no row in the catalog.
    var title: String {
        switch self {
        case .glacier: return Strings.string("accent.glacier")
        case .ember: return Strings.string("accent.ember")
        case .meadow: return Strings.string("accent.meadow")
        case .lilac: return Strings.string("accent.lilac")
        case .crimson: return Strings.string("accent.crimson")
        case .gold: return Strings.string("accent.gold")
        case .teal: return Strings.string("accent.teal")
        case .magenta: return Strings.string("accent.magenta")
        case .moss: return Strings.string("accent.moss")
        case .orchid: return Strings.string("accent.orchid")
        }
    }

    /// The vivid base tint — right on dark themes and in picker swatches.
    var color: Color {
        switch self {
        case .glacier: return Color(red: 0.33, green: 0.68, blue: 0.98)
        case .ember: return Color(red: 1.00, green: 0.56, blue: 0.20)
        case .meadow: return Color(red: 0.36, green: 0.84, blue: 0.48)
        case .lilac: return Color(red: 0.66, green: 0.50, blue: 0.98)
        case .crimson: return Color(red: 1.00, green: 0.36, blue: 0.56)
        case .gold: return Color(red: 0.98, green: 0.75, blue: 0.18)
        case .teal: return Color(red: 0.15, green: 0.80, blue: 0.76)
        case .magenta: return Color(red: 0.88, green: 0.42, blue: 0.90)
        case .moss: return Color(red: 0.62, green: 0.85, blue: 0.30)
        case .orchid: return Color(red: 0.94, green: 0.38, blue: 0.68)
        }
    }

    /// The vivid base tint as raw components, for the DualSense light bar
    /// (PRD-5 Phase 3). Kept parallel to `color` rather than extracted from it —
    /// SwiftUI `Color` → RGB round-tripping is unreliable on tvOS.
    var lightBarRGB: (red: Double, green: Double, blue: Double) {
        switch self {
        case .glacier: return (0.33, 0.68, 0.98)
        case .ember: return (1.00, 0.56, 0.20)
        case .meadow: return (0.36, 0.84, 0.48)
        case .lilac: return (0.66, 0.50, 0.98)
        case .crimson: return (1.00, 0.36, 0.56)
        case .gold: return (0.98, 0.75, 0.18)
        case .teal: return (0.15, 0.80, 0.76)
        case .magenta: return (0.88, 0.42, 0.90)
        case .moss: return (0.62, 0.85, 0.30)
        case .orchid: return (0.94, 0.38, 0.68)
        }
    }

    /// The tint resolved for the surface it sits on.
    func color(isLight: Bool) -> Color {
        guard isLight else { return color }
        switch self {
        case .glacier: return Color(red: 0.07, green: 0.34, blue: 0.66)
        case .ember: return Color(red: 0.57, green: 0.25, blue: 0.02)
        case .meadow: return Color(red: 0.08, green: 0.40, blue: 0.20)
        case .lilac: return Color(red: 0.39, green: 0.26, blue: 0.70)
        case .crimson: return Color(red: 0.67, green: 0.11, blue: 0.28)
        case .gold: return Color(red: 0.46, green: 0.32, blue: 0.01)
        case .teal: return Color(red: 0.02, green: 0.39, blue: 0.37)
        case .magenta: return Color(red: 0.58, green: 0.16, blue: 0.58)
        case .moss: return Color(red: 0.27, green: 0.38, blue: 0.04)
        case .orchid: return Color(red: 0.66, green: 0.08, blue: 0.39)
        }
    }
}

extension AccentChoice {
    /// **The fill of a filled primary action, and it is not the tint.**
    ///
    /// Two blind panels running looked at the tutorial's "Try it" button and
    /// wrote the same defect from opposite rounds: *"reads as disabled"*,
    /// *"desaturated slate"*, sampled at about `#4A79A8` with white text at
    /// 4.1:1. The cause is a habit that is correct everywhere else in the app
    /// and wrong here — `color(isLight:)` deepens the accent so a *mark* stays
    /// legible **on** the ground, and a filled button is not a mark on the
    /// ground, it **is** the ground for its own label. Deepening it a second
    /// time is how a primary action ends up the colour of a disabled control.
    ///
    /// So on a dark theme the fill is the **vivid** tint at full chroma, and on
    /// paper it is the deepened one — the same rule as everywhere else, applied
    /// to the right surface. The label follows in `actionInk`.
    func actionFill(isLight: Bool) -> Color {
        isLight ? color(isLight: true) : color
    }

    /// The label on `actionFill`, and the reason the fill can afford full
    /// chroma.
    ///
    /// Measured across all ten accents (WCAG 2.1 relative luminance):
    ///
    /// * On the **vivid** set, white lands at 2.4–2.9:1 and near-black at
    ///   **6.5–12.6:1**. Glacier is the worst case at 6.5. A vivid accent is a
    ///   *bright* colour — the ink that goes on it is dark, exactly as it is on
    ///   Apple's own tinted prominent buttons.
    /// * On the **deepened** set the ordering flips and white lands at
    ///   **7.1:1** almost uniformly, because those values were solved against a
    ///   luminance target in PRD-22.
    ///
    /// Near-black rather than pure black for the reason `CouchPalette.ink`
    /// exists: a hard #000 against a saturated fill rings. It costs ~0.3 of a
    /// contrast point and the floor holds with room.
    func actionInk(isLight: Bool) -> Color {
        isLight ? Color(red: 0.99, green: 0.99, blue: 1.00)
                : Color(red: 0.055, green: 0.055, blue: 0.07)
    }
}

extension Difficulty {
    /// **The band's own hue.** Six difficulties, and until round 4 they were
    /// distinguished on the shelf by nothing but a mini-board's dot density —
    /// which a player cannot parse at tile size, and which a blind panel
    /// summarised as *"Gentle / Steady / Sharp are three identical grey tiles;
    /// the only saturated pixels in the frame are the page dot and the pencil
    /// marks"*. Six ranks of a game's central axis, rendered in one colour.
    ///
    /// **Mapped onto the existing accent palette rather than to six new
    /// literals, and that is the whole design.** Those ten tints are the most
    /// heavily measured colours in the app: `AppearancePaletteTests` pins each
    /// one at ≥4.5:1 on all six dark grounds *and* at ΔE ≥ 5.9 from every
    /// sibling under protanopia, deuteranopia and tritanopia. A hand-picked
    /// "difficulty red" would have to earn all of that from scratch; borrowing
    /// six of them costs nothing and inherits every proof.
    ///
    /// The ramp is green → teal → blue → lilac → magenta → crimson: a
    /// continuous hue rotation with no repeat, reading cool-to-hot in the
    /// direction the bands get harder. Deliberately **not** a green-to-red
    /// ramp — the colourblind-safe rule this palette is built on rules that
    /// out, and the rotation carries the ordering for a dichromat as luminance
    /// and hue-angle both.
    ///
    /// A player whose accent happens to *be* one of these six sees one band
    /// wearing their tint. That is acceptable and deliberate: the accent marks
    /// selection, which is transient, and the band tint marks identity, which
    /// is not — they never occupy the same pixel.
    var bandAccent: AccentChoice {
        switch self {
        case .gentle: return .meadow
        case .steady: return .teal
        case .sharp: return .glacier
        case .nocturne: return .lilac
        case .tempest: return .magenta
        case .abyss: return .crimson
        }
    }

    /// The band's hue resolved for the ground it will be drawn on — deepened on
    /// paper exactly as every accent is, via `AccentChoice.color(isLight:)`.
    ///
    /// Use it on the *label*, the mini-board's block rules and a tinted top
    /// edge. Not as a flood fill: six saturated cards in a column is a paint
    /// chart, and the tile's substance is still `Elevation.fill(.card,…)`.
    func bandTone(isLight: Bool) -> Color { bandAccent.color(isLight: isLight) }
}

/// The board's tonal palette, resolved from a `ThemeChoice`. Flat colors
/// only — box borders stay luminance steps in `gridTone`, never hard lines.
struct ThemeTones {
    /// Full-bleed backdrop behind the glass.
    let background: Color
    /// Box washes, hairlines, pencil digits (at reduced opacity).
    let gridTone: Color
    /// Given digits.
    let digitTone: Color
    /// Light-leaning themes flip the wash opacities and deepen the accent.
    let isLight: Bool
    /// The error marker (PRD-22). Was one constant on `BoardView` for four
    /// releases, and `scripts/contrast-harness.py` measured what that cost on
    /// the two light themes it had never been checked against: **1.92:1** on
    /// Camel. Deepened for light grounds exactly the way
    /// `AccentChoice.color(isLight:)` already deepens the accents.
    let coral: Color
    /// The wash the board Canvas lays down between the glass and the drawing
    /// (PRD-22).
    ///
    /// `couchGlass` is a *material*: what it draws is dominated by the system's
    /// own glass, not by the colour behind it. Solved back through the two box
    /// wash opacities from screenshots — and the nine boxes agree to within a
    /// level — Void's `(0, 0, 0)` reaches the board as `(19, 19, 19)` and
    /// Camel's `(204, 178, 140)` as `(250, 230, 200)`. So every number the
    /// palette test computed was against a ground the board never had, and the
    /// theme's own hue was barely present under it. Mono is the control: its
    /// declared `(28, 28, 31)` arrives as `(29, 29, 32)`, because it already
    /// *was* the material's luminance.
    ///
    /// This puts a measured amount of the ground back. It is drawn *beside* the
    /// Canvas rather than inside it, so the two Afterglow shaders keep sampling
    /// drawn content only and the celebration is untouched.
    let plane: Color
    /// Box borders under Increase Contrast (PRD-22). The board's borders are
    /// luminance steps by design (PRD §4.2) — a wash you read as an edge rather
    /// than a line — which is the right default and the wrong answer for
    /// someone who has asked the system for more contrast.
    let hairline: Color

    /// **The colour a surface is made of** — the hue `Elevation.fill` applies at
    /// each rung, at whatever alpha that rung asks for.
    ///
    /// A separate tone from `gridTone` and `digitTone` because it answers a
    /// different question. Those two are *ink*: what a mark is drawn with. This
    /// is *substance*: what a sheet, a tile and a key are made of. Nine had no
    /// answer to the second, so every surface in the app used a white wash — and
    /// a white wash is why the panel could describe the iPhone shelf as "seven
    /// cards, all the same 4% white on near-black" and the iPad light channel as
    /// "three identical grey tiles". A grey app with a coloured board is not a
    /// themed app; it is a themed *board*.
    ///
    /// On a dark theme it is `gridTone`, which is already the theme's own light
    /// tone — pale blue on Blueprint, warm cream on Ember, pale cyan on Tide,
    /// and plain white on Void, which is correct because Void has no hue. On a
    /// light theme it is a near-white leaning the theme's way: paper cannot be
    /// tinted upward, so the surface is the whitest the theme allows and the
    /// *lean* is all the hue there is room for.
    let surfaceHue: Color

    /// The colour a **recess** is cut with — the groove under a track, the dish
    /// under a key. `black` on a dark theme (there is nothing below the ground
    /// but shadow) and the theme's own deep tone on paper, so Camel's grooves
    /// are warm brown rather than the neutral grey every light UI defaults to.
    let wellHue: Color

    /// The shipped error coral, unchanged. Measured on the composited glass at
    /// 5.20–6.11:1 across the six dark themes — comfortably past PRD-22's 3:1.
    static let coralOnDark = Color(red: 1.00, green: 0.45, blue: 0.38)
    /// …and its light-ground twin. The vivid one is 1.92:1 on Camel, which is
    /// an error marker nobody can see; this is the same hue taken down to where
    /// it reads on paper.
    static let coralOnLight = Color(red: 0.72, green: 0.13, blue: 0.06)

    /// The three derived tones have defaults rather than nine hand-written
    /// copies: a theme that wants the usual treatment says nothing, and the one
    /// that does not is visible as an override at its own case.
    init(
        background: Color,
        gridTone: Color,
        digitTone: Color,
        isLight: Bool,
        coral: Color? = nil,
        plane: Color? = nil,
        planeOpacity: Double? = nil,
        hairline: Color? = nil,
        surfaceHue: Color? = nil,
        wellHue: Color? = nil
    ) {
        self.background = background
        self.gridTone = gridTone
        self.digitTone = digitTone
        self.isLight = isLight
        self.coral = coral ?? (isLight ? Self.coralOnLight : Self.coralOnDark)
        // Dark themes are made of their own light tone; paper is made of the
        // whitest thing the theme allows. A light theme that wants a warmer
        // white says so at its own case — Camel does.
        self.surfaceHue = surfaceHue
            ?? (isLight ? Color(red: 1.000, green: 0.996, blue: 0.988) : gridTone)
        self.wellHue = wellHue ?? (isLight ? gridTone : .black)
        // How much of the theme's own ground reaches the board. Not 1.0 on
        // purpose: the wash covers the grid square only, so the 12–28pt inset
        // stays pure material and the board still reads as a pane of glass
        // with a screen inside it rather than as a painted rectangle.
        //
        // **Zero on light themes, and that is measured, not an oversight.**
        // Every mark a light theme draws — givens, accents, the coral — is
        // *darker* than its ground, so restoring the theme's ground lowers the
        // ground's luminance and costs contrast on all three at once. On Camel
        // a 0.58 wash took givens from 10.28:1 to 8.15:1 and bought nothing.
        // Light themes are fixed by deepening the ink instead
        // (`AccentChoice.color(isLight:)` and `coralOnLight`).
        //
        // **Round 4 kept the finding and reversed the conclusion — for the two
        // light themes only, and by passing an explicit `plane` rather than by
        // changing this default.** The measurement above is about washing the
        // board with *the theme's own ground*, which on a light theme is
        // **darker** than the composited glass (Camel's (204,178,140) reaches
        // the board as (250,230,200)). Every word of it is still true. What it
        // does not cover is washing with something *lighter* than the glass,
        // which is the opposite operation: it raises the board's ground and
        // therefore raises contrast on all three marks at once, because on a
        // light theme every mark is dark.
        //
        // The panel is why it matters. `ipad-light-tutorial` measured the board
        // at **cell fill 192 inside a sheet at 215–231** — a grey slab pasted
        // into a white card, with the value order for light mode exactly
        // inverted. With `planeOpacity 0` the board has no ground of its own at
        // all: it is whatever the glass happens to composite over whatever
        // happens to be behind it, so a sheet, a scrim or a dark backdrop moves
        // the board's paper around under the player. Paper and Camel now carry
        // their own paper, at their own hue — see their two cases below.
        self.plane = (plane ?? background)
            .opacity(planeOpacity ?? (isLight ? 0 : 0.70))
        self.hairline = hairline ?? gridTone.opacity(isLight ? 0.42 : 0.34)
    }
}

/// Color scheme for the whole app — both platforms. `auto` follows the
/// system; the tinted themes (camel, blueprint, forest, ember, tide, mono) pin
/// their leaning so materials and secondary text follow along.
enum ThemeChoice: String, Codable, Sendable, CaseIterable {
    case auto, dark, light, camel, blueprint, forest, ember, tide, mono

    /// The raw values are the persisted spelling (`dark`, `light`) and the
    /// names are not (`Void`, `Paper`), so this mapping cannot be derived.
    var title: String {
        switch self {
        case .auto: return Strings.string("theme.auto")
        case .dark: return Strings.string("theme.dark")
        case .light: return Strings.string("theme.light")
        case .camel: return Strings.string("theme.camel")
        case .blueprint: return Strings.string("theme.blueprint")
        case .forest: return Strings.string("theme.forest")
        case .ember: return Strings.string("theme.ember")
        case .tide: return Strings.string("theme.tide")
        case .mono: return Strings.string("theme.mono")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light, .camel: return .light
        case .dark, .blueprint, .forest, .ember, .tide, .mono: return .dark
        }
    }

    /// Tones for this theme; `resolved` decides only for `auto`, where the
    /// system's scheme picks Void or Paper.
    func tones(for resolved: ColorScheme) -> ThemeTones {
        switch self {
        case .auto:
            return (resolved == .light ? ThemeChoice.light : .dark).tones(for: resolved)
        // **Void's ground is no longer `CouchPalette.void`, and no longer pure
        // black.** `.glassEffect` is a lens: it refracts and blurs what is
        // behind it, and behind #000000 there is nothing to refract, so every
        // pane of glass in the app collapsed to a flat tint. Measured on the
        // shipped build: shelf cards 1.07:1 against their page, the board card
        // 1.03:1, the six toolbar discs 1.08:1, the rose petals 1.026:1, the
        // History stat cards 1.005:1 — all far under WCAG 1.4.11's 3:1 for a
        // component boundary, and none of it fixable in the card, because the
        // card was doing its job and the ground was giving it nothing to do it
        // with.
        //
        // #0C0C0F is the smallest lift that gives the material something to
        // bend while still reading as black in a dark room: 12/255 is one
        // perceptual step off zero and this is still the darkest of the nine
        // themes. The blue channel runs two levels warm of the other two for
        // the same reason `CouchPalette.ink` does — a perfectly neutral
        // near-black reads slightly green on OLED.
        //
        // `CouchPalette.void` itself is untouched: four sibling apps draw on it
        // and CouchKit is additive-only. This is Nine's ground, so Nine writes
        // the number, and `SharedPalette.darkGround` carries the same triple to
        // the widget process.
        //
        // Every floor in `AppearancePaletteTests` survives the lift — givens
        // 15.8:1 (floor 12), grid tone 19.7:1 (floor 10), coral 7.4:1 (floor
        // 5.5) — and Blueprint is still the binding ground for all ten accents,
        // which is what those floors were set against.
        case .dark:
            return ThemeTones(
                background: Color(red: 0.047, green: 0.047, blue: 0.059),
                gridTone: .white,
                digitTone: CouchPalette.paper,
                isLight: false
            )
        case .light:
            return ThemeTones(
                background: Color(red: 0.94, green: 0.93, blue: 0.90),
                gridTone: .black,
                digitTone: Color(red: 0.17, green: 0.16, blue: 0.14),
                isLight: true,
                // Paper's own paper — see the long note in `init`. A hair
                // warmer and a good deal lighter than the backdrop (240,237,230
                // → 252,250,246), so the board is the brightest object on a
                // light screen no matter what it is standing on, and every dark
                // mark on it gains rather than loses.
                plane: Color(red: 0.988, green: 0.980, blue: 0.965),
                planeOpacity: 0.62
            )
        case .camel:
            return ThemeTones(
                background: Color(red: 0.80, green: 0.70, blue: 0.55),
                gridTone: Color(red: 0.20, green: 0.13, blue: 0.06),
                digitTone: Color(red: 0.23, green: 0.15, blue: 0.07),
                isLight: true,
                // Camel's paper is *cream*, not white. The whole point of the
                // theme is a warm page, and a board washed toward neutral white
                // would delete the one surface the theme is named for. Lighter
                // than the composited glass (250,230,200 → 252,244,226) so the
                // contrast argument in `init` holds, and warmer than Paper's
                // plane by three times the red-blue split.
                plane: Color(red: 0.988, green: 0.957, blue: 0.886),
                planeOpacity: 0.62,
                // The one light theme whose ground is genuinely coloured, so
                // the default near-neutral white reads *cold* on it — a bluish
                // card on a tan page, which is the tell of a theme applied to
                // the board and not to the app. This is the same white with
                // the ground's own lean, and it is the whole reason
                // `surfaceHue` is a parameter rather than a formula.
                surfaceHue: Color(red: 1.000, green: 0.980, blue: 0.945)
            )
        case .blueprint:
            return ThemeTones(
                background: Color(red: 0.05, green: 0.14, blue: 0.33),
                gridTone: Color(red: 0.75, green: 0.85, blue: 1.00),
                digitTone: Color(red: 0.86, green: 0.92, blue: 1.00),
                isLight: false,
                // The one theme whose backdrop and whose board ground are
                // different jobs, and the only theme where the default wash
                // made things *worse*. Blueprint's backdrop is a saturated blue
                // that reads well full-bleed and is lighter than the composited
                // glass — so putting it back under the board raised the ground
                // and pulled every accent down (crimson 3.93 → 3.79). This is
                // the same hue taken to where a board wants it; Blueprint is
                // the binding ground for all ten accents in the matrix, so the
                // whole palette's worst cell is set here.
                plane: Color(red: 0.022, green: 0.065, blue: 0.165),
                planeOpacity: 0.80
            )
        case .forest:
            return ThemeTones(
                background: Color(red: 0.05, green: 0.13, blue: 0.09),
                gridTone: Color(red: 0.80, green: 0.92, blue: 0.84),
                digitTone: Color(red: 0.89, green: 0.94, blue: 0.88),
                isLight: false
            )
        // PRD-16. All three are dark-leaning and all three clear the floors
        // Blueprint set: given digits ≥12:1, grid tone ≥10:1, and the coral
        // error marker ≥5.5:1 against the ground (pinned in
        // AppearancePaletteTests). Ember is the one to watch — a rust ground
        // sits ~8° from coral's hue, so its legibility is bought with
        // luminance (6.94:1), not with hue.
        case .ember:
            return ThemeTones(
                background: Color(red: 0.14, green: 0.05, blue: 0.03),
                gridTone: Color(red: 0.98, green: 0.86, blue: 0.78),
                digitTone: Color(red: 0.99, green: 0.91, blue: 0.85),
                isLight: false
            )
        case .tide:
            return ThemeTones(
                background: Color(red: 0.02, green: 0.12, blue: 0.14),
                gridTone: Color(red: 0.76, green: 0.93, blue: 0.94),
                digitTone: Color(red: 0.86, green: 0.96, blue: 0.96),
                isLight: false
            )
        case .mono:
            return ThemeTones(
                background: Color(red: 0.11, green: 0.11, blue: 0.12),
                gridTone: Color(red: 0.88, green: 0.88, blue: 0.89),
                digitTone: Color(red: 0.95, green: 0.95, blue: 0.96),
                isLight: false
            )
        }
    }
}

/// The player's theme, planted once at the root so leaf views (board,
/// backgrounds) pick it up without prop-threading.
private struct NineThemeKey: EnvironmentKey {
    static let defaultValue: ThemeChoice = .auto
}

extension EnvironmentValues {
    var nineTheme: ThemeChoice {
        get { self[NineThemeKey.self] }
        set { self[NineThemeKey.self] = newValue }
    }
}

