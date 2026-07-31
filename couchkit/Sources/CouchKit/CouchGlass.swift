// CouchGlass — THE Liquid Glass shim.
//
// This is the ONLY file in the entire Couch Suite allowed to reference the
// Liquid Glass API directly. Every component and every app goes through
// `couchGlass(in:)` / `CouchGlassContainer`, so:
//
//   ⚠️ If Liquid Glass API names differ in your SDK, fix them HERE only.
//
// On tvOS/iOS/macOS/watchOS 26+ we use `.glassEffect(.regular, in:)` and
// `GlassEffectContainer`. Below 26 (deployment targets tvOS 18 / macOS 15 /
// watchOS 11) we fall back to `.ultraThinMaterial` plus a subtle stroke — same
// silhouette, no lensing. The material path carries the macOS build until
// Liquid Glass ships there.
//
// **Every `#available` here must name every platform this file compiles for.**
// The trailing `*` means "at the deployment target on anything not listed", so
// omitting watchOS did not read as "fall back on the watch" — it read as
// "available on watchOS 11", and the fallback branch became unreachable. The
// compiler caught it on `GlassEffectContainer` (PRD-6 Task 1); it would not
// have caught a modifier that merely does nothing.
#if os(tvOS) || os(iOS) || os(macOS) || os(watchOS)
import SwiftUI

extension View {
    /// The suite's glass treatment clipped to `shape`.
    /// Use instead of any direct material/glass call.
    @ViewBuilder
    public func couchGlass(in shape: some Shape) -> some View {
        if #available(tvOS 26.0, iOS 26.0, macOS 26.0, watchOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    /// Capsule glass — the default silhouette for pills and chips.
    public func couchGlass() -> some View {
        couchGlass(in: Capsule())
    }

    /// Interactive glass for focusable elements: same treatment, but on
    /// tvOS 26 the glass responds to focus with specular movement.
    @ViewBuilder
    public func couchGlassInteractive(in shape: some Shape) -> some View {
        if #available(tvOS 26.0, iOS 26.0, macOS 26.0, watchOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
    }
}

// MARK: - The material ladder
//
// Two rungs is not a ladder. Everything above shipped as `.regular` or
// `.regular.interactive()`, so a board, a sheet, a chip and a stat tile *inside*
// that sheet all asked the system for the same material and all got it — which
// is why Nine has twelve sites nesting `.regular` glass inside `.regular` glass,
// and why a card measures 1.03:1 against the page it floats on. Glass is a
// lens: two lenses stacked do not read as two surfaces, they read as one
// slightly murkier one.
//
// The four rungs below are the whole ladder, from "barely there" to "this is
// the object":
//
//   L1  couchGlassOverContent  .clear     chrome floating over live content
//   L1½ couchGlassBar          .clear + specular top rim + sheen, no hard edge
//   L2  couchGlass             .regular   a surface (the shipped default)
//   L3  couchGlassTinted       .regular.tint(_)  a surface with primacy
//   L4  couchInset             .identity + tint  content INSIDE a surface
//
// L1½ is round 2's addition. It is L1 plus articulation, and it exists because
// every floating bar in the suite was being hand-built as a rectangle of
// material with a full-bleed hairline along its boundary — which is a *rule*,
// not the edge of a slab of glass. See `couchGlassBar(in:isLight:)`.
//
// L4 is the odd one and the important one: `.identity` glass registers the
// shape with the enclosing `GlassEffectContainer` — so it still morphs and
// merges with its siblings — while adding **no second material**. A tile inside
// a panel gets shape and tint and nothing else, which is the correct answer to
// every one of those twelve nesting sites.
//
// `couchElevated` is orthogonal to all of them: it is the rim and the shadow,
// not a material, and it is applied *after* whichever rung the surface picked.
// `couchRim` is the same thing minus the shadow, for a surface that is flush
// rather than floating (a key, a chip, a tile) — and most surfaces are flush.
//
// Every rung honours **Reduce Transparency**, which had zero hits app-wide
// before this. Under that setting a lens is exactly the wrong thing to draw, so
// each rung falls back to an opaque-enough backing and a solid rim.

/// The Reduce Transparency backing shared by every rung. Not a material and not
/// a fixed colour: `BackgroundStyle` is the system's own surface colour, so it
/// follows the resolved colour scheme without this file knowing the theme.
private struct CouchOpaqueBacking<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var rimOpacity: Double = 0.28

    func body(content: Content) -> some View {
        content
            .background(tint ?? .clear, in: shape)
            .background(.background, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(rimOpacity), lineWidth: 1))
    }
}

extension View {
    // MARK: L1 — chrome over live content

    /// `.clear` glass: the lightest rung. For chrome that floats *over* moving
    /// or content-bearing pixels — a toolbar over the board, a chip over a
    /// photo — where `.regular` would fog the thing the player is looking at.
    ///
    /// Content inside it must supply its own contrast (a symbol, a bold label);
    /// `.clear` deliberately does not.
    @ViewBuilder
    public func couchGlassOverContent(in shape: some Shape) -> some View {
        if #available(tvOS 26.0, iOS 26.0, macOS 26.0, watchOS 26.0, *) {
            self.modifier(CouchClearGlass(shape: shape))
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
    }

    /// Capsule `.clear` glass — the default silhouette for floating chrome.
    public func couchGlassOverContent() -> some View {
        couchGlassOverContent(in: Capsule())
    }

    // MARK: L3 — a surface with primacy

    /// `.regular` glass carrying a tint: the rung for the one surface on screen
    /// that outranks the others — a primary action, the active tier card, the
    /// cell the cursor is in.
    ///
    /// The tint is the caller's resolved accent, not a hue name: CouchKit does
    /// not know whether the ground is light (Nine deepens every accent on
    /// paper — see `AccentChoice.color(isLight:)`).
    @ViewBuilder
    public func couchGlassTinted(_ tint: Color, in shape: some Shape) -> some View {
        if #available(tvOS 26.0, iOS 26.0, macOS 26.0, watchOS 26.0, *) {
            self.modifier(CouchTintedGlass(shape: shape, tint: tint))
        } else {
            self
                .background(tint.opacity(0.22), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(tint.opacity(0.45), lineWidth: 1))
        }
    }

    /// Capsule tinted glass.
    public func couchGlassTinted(_ tint: Color) -> some View {
        couchGlassTinted(tint, in: Capsule())
    }

    // MARK: L4 — content inside a surface

    /// **Shape and tint, never a second material.** The rung for anything drawn
    /// *inside* a panel that is already glass: a stat tile in a drawer, a key in
    /// a digit pad, a row in a sheet, a swatch in a picker.
    ///
    /// `.identity` glass keeps the element in the enclosing
    /// `GlassEffectContainer` — so it still merges and morphs with its siblings
    /// — while contributing no lensing of its own. That is the entire fix for
    /// glass-on-glass: the inner element reads as a *region of* the panel rather
    /// than as a second pane floating a millimetre above it.
    ///
    /// `tint` defaults to a 6% white wash, which is the smallest step that
    /// separates a tile from its panel on a dark ground. Pass the theme's own
    /// tone (`tones.gridTone.opacity(…)`) where one is in hand.
    @ViewBuilder
    public func couchInset(
        in shape: some Shape,
        tint: Color = Color.white.opacity(0.06)
    ) -> some View {
        if #available(tvOS 26.0, iOS 26.0, macOS 26.0, watchOS 26.0, *) {
            self.modifier(CouchIdentityGlass(shape: shape, tint: tint))
        } else {
            self.background(tint, in: shape)
        }
    }

    /// Capsule inset.
    public func couchInset(tint: Color = Color.white.opacity(0.06)) -> some View {
        couchInset(in: Capsule(), tint: tint)
    }

    // MARK: Elevation — the rim and the shadow

    /// The lift, applied **after** whichever material rung the surface chose.
    ///
    /// Nothing in Nine was lit: `grep '.shadow(' nine/Sources/App` returned zero
    /// hits, so every glass card sat flush against the page and the material had
    /// no edge to catch. Two marks fix it, and both are physical rather than
    /// decorative:
    ///
    /// * **A gradient rim.** A real pane of glass catches the light source on
    ///   one edge and loses it on the opposite one, so the border runs bright at
    ///   `.topLeading` and near-nothing at `.bottomTrailing`. A uniform stroke
    ///   reads as a drawn outline; a gradient reads as a bevel. On a light
    ///   ground the rim has to work much harder (0.9 → 0.2) than on a dark one
    ///   (0.20 → 0.04), because white-on-white is the hardest edge there is.
    /// * **A silhouette shadow**, drawn as a blurred fill of the caller's own
    ///   shape rather than as a plain `.shadow` modifier. That is `FocusHalo`'s
    ///   recorded fix restated: a `.shadow` silhouettes whatever opaque geometry
    ///   it finds, and a glass layer's alpha is not that — the tvOS "black
    ///   rectangle" artifact was exactly this mistake. Filling the shape hugs
    ///   the rounded card exactly.
    public func couchElevated(
        in shape: some InsettableShape,
        isLight: Bool = false
    ) -> some View {
        modifier(CouchElevation(shape: shape, isLight: isLight))
    }

    /// **The rim on its own, with no shadow under it.**
    ///
    /// `couchElevated` is two claims — "this is glass" and "this is floating
    /// above the page" — and half the surfaces in the suite only want the
    /// first. A key in a digit pad, a chip in a row, a swatch in a picker and a
    /// tile inside a card are all *flush*: they are part of the surface they sit
    /// on, and giving each of them a drop shadow is how a control panel starts
    /// looking like a pile of stickers. They still need the edge, because
    /// without it they are flat fills again.
    ///
    /// Identical to `couchElevated` minus the shadow, and it honours Reduce
    /// Transparency the same way.
    public func couchRim(
        in shape: some InsettableShape,
        isLight: Bool = false
    ) -> some View {
        modifier(CouchRim(shape: shape, isLight: isLight))
    }

    /// The common case: `.regular` glass plus the rim and the shadow, in one
    /// call. Equivalent to `.couchGlass(in: shape).couchElevated(in: shape,
    /// isLight: isLight)`.
    public func couchGlassElevated(
        in shape: some InsettableShape,
        isLight: Bool = false
    ) -> some View {
        couchGlass(in: shape).couchElevated(in: shape, isLight: isLight)
    }

    // MARK: L1½ — a bar of chrome floating over live content

    /// A **bar**, not a panel: clear-leaning glass with a specular top rim that
    /// dies away at both ends, an interior sheen, and deliberately **no hard
    /// bottom edge**.
    ///
    /// The rung exists because every floating bar in the suite was being built
    /// the same wrong way — a rectangle of material with a full-bleed 1pt
    /// hairline along the boundary — and a full-bleed hairline is not what a bar
    /// of glass looks like. It is what a *rule* looks like. Critics reading the
    /// round-1 frames called it "a hard seam" on five separate surfaces.
    ///
    /// Three marks, each with a physical reason:
    ///
    /// * **A specular glint, masked to fade at the ends.** Light lands on the
    ///   top arc of a bar in the middle, where the surface faces the source, and
    ///   slides off toward the corners. A gradient that reaches zero before
    ///   either edge means the bar has no line to end on, which is the entire
    ///   difference between "seam" and "edge".
    /// * **An interior sheen**: lit along the top few points, occluded along the
    ///   bottom few. That is thickness — it is what tells the eye the bar is a
    ///   slab rather than a window cut in the page.
    /// * **`.clear` glass, never `.regular`.** A bar sits over the thing the
    ///   player is looking at (the board, the shelf), and `.regular` fogs it.
    ///
    /// - Parameters:
    ///   - shape: usually `Rectangle()` for an edge-to-edge bar, or a `Capsule`
    ///     for a floating one. The rim and the sheen both follow it.
    ///   - isLight: whether the ground behind is light-leaning. On paper the
    ///     glint has almost nowhere to go and the *occlusion* carries the edge,
    ///     so the two ends of the treatment swap importance.
    public func couchGlassBar(
        in shape: some InsettableShape,
        isLight: Bool = false
    ) -> some View {
        modifier(CouchBarGlass(shape: shape, isLight: isLight))
    }

    /// The edge-to-edge case: a full-width bar.
    public func couchGlassBar(isLight: Bool = false) -> some View {
        couchGlassBar(in: Rectangle(), isLight: isLight)
    }
}

// MARK: - Specular articulation
//
// **A material is not a fill, and round 1 shipped fills.** Fourteen critics
// compared the round-0 and round-1 frames blind; ten of them wrote the same
// sentence, almost verbatim — *"flat opaque fill plus a hairline, not a
// material"*. They were right, and the cause is not too few `.glassEffect`
// calls. It is that a lens needs two things the suite was not giving it:
//
//   1. **something to refract** — luminance structure in the ground. That half
//      belongs to the app (Nine's `VoidBackground`), not to this file.
//   2. **an articulated edge** — and that half is here.
//
// Real glass has *thickness*, and thickness on screen is two bright lines a
// hair apart: the outer bevel where the light first catches, and a second,
// slightly softer highlight one point inside it, along the top arc only. Below
// them the surface turns away from the light and the rim goes dark. Nine's
// shipped rim was a single stroke running `white 0.20 → 0.04` on dark — at its
// *brightest* that is 5/255 over a `#0C0C0F` ground, which after compositing is
// not there at all. Every number below is the raised one.
//
// **tvOS keeps the shipped values exactly.** Four sibling apps (Rabbit Ears,
// Darkroom, Blockhead, Cartridge) draw on `CouchPalette.void` at ten feet,
// where a 0.45 hairline is a glare rather than an edge, and the suite rule is
// that they render byte-identically. Every raise is behind `#if !os(tvOS)`;
// this type is merely *available* there, unused.
//
// The stop sets are published as `Gradient` rather than only as
// `LinearGradient` because Nine draws its board, its rose and its fingerprint
// into a `Canvas`, and `GraphicsContext.Shading.linearGradient(_:)` takes the
// former. A rim a `Canvas` cannot draw is a rim half the app cannot have.
public enum CouchSpecular {
    /// One point, on every platform and at every scale. A rim is a *lighting*
    /// artifact, not a border: it does not thicken with the surface, and a 2pt
    /// version of it stops reading as light and starts reading as a frame.
    public static let width: CGFloat = 1

    // MARK: The edge

    /// The outer bevel: bright at `.topLeading` where the light lands, through
    /// nothing in the middle, to genuinely *dark* at `.bottomTrailing`.
    ///
    /// The dark end is the half that was missing. A rim that fades from bright
    /// to transparent describes a surface lit from one side; a rim that goes
    /// bright → nothing → **black** describes a surface with a bottom lip that
    /// the light cannot reach, which is what a raised object actually has.
    ///
    /// The ramp passes through explicit zero-alpha stops of each colour rather
    /// than through `.clear`: `Color.clear` is black at zero alpha and SwiftUI
    /// interpolates in unpremultiplied space, so a `white → .clear` leg travels
    /// through grey. At these opacities that muddiness is the same size as the
    /// effect.
    public static func rimStops(isLight: Bool) -> Gradient {
        Gradient(stops: [
            .init(color: .white.opacity(isLight ? 0.95 : 0.45), location: 0),
            .init(color: .white.opacity(isLight ? 0.34 : 0.15), location: 0.38),
            .init(color: .white.opacity(0), location: 0.60),
            .init(color: .black.opacity(0), location: 0.64),
            .init(color: .black.opacity(isLight ? 0.16 : 0.24), location: 1),
        ])
    }

    /// `rimStops` as a `.topLeading → .bottomTrailing` gradient — the form a
    /// `strokeBorder` wants.
    public static func rim(isLight: Bool) -> LinearGradient {
        LinearGradient(
            gradient: rimStops(isLight: isLight),
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }

    /// The inner highlight: one point inside the bevel, along the **top arc
    /// only**, and vertical rather than diagonal.
    ///
    /// Vertical because this line is not describing the light's direction — the
    /// outer bevel already did that — it is describing the *thickness* of the
    /// pane, and thickness is uniform across the top edge. It reaches zero by
    /// 34% of the height so the sides and bottom of the stroke draw nothing.
    public static func innerHighlightStops(isLight: Bool) -> Gradient {
        Gradient(stops: [
            .init(color: .white.opacity(isLight ? 0.70 : 0.30), location: 0),
            .init(color: .white.opacity(isLight ? 0.18 : 0.09), location: 0.16),
            .init(color: .white.opacity(0), location: 0.34),
        ])
    }

    /// `innerHighlightStops` as a `.top → .bottom` gradient.
    public static func innerHighlight(isLight: Bool) -> LinearGradient {
        LinearGradient(
            gradient: innerHighlightStops(isLight: isLight),
            startPoint: .top,
            endPoint: .bottom)
    }

    // MARK: The lift

    /// One layer of a two-layer shadow. Not `Sendable`-conformed on purpose:
    /// the values are read on the main actor during layout and nothing here
    /// crosses an isolation boundary.
    public struct Shadow {
        public let color: Color
        public let blur: CGFloat
        public let y: CGFloat

        public init(color: Color, blur: CGFloat, y: CGFloat) {
            self.color = color
            self.blur = blur
            self.y = y
        }
    }

    /// The wide, soft half: the surface's presence in the room.
    ///
    /// **Two layers, because one cannot be both.** A single wide blur is the
    /// 2018 Material idiom and every critic named it ("generic diffuse grey",
    /// "muddies the ground"); a single tight one leaves the card looking
    /// stickered on. Real occlusion is a near-black contact band a couple of
    /// points under the object plus a much wider, much fainter ambient falloff.
    public static func ambient(isLight: Bool) -> Shadow {
        Shadow(
            color: .black.opacity(isLight ? 0.13 : 0.50),
            blur: 22,
            y: 10)
    }

    /// The tight, dark half: where the surface actually touches.
    public static func contact(isLight: Bool) -> Shadow {
        Shadow(
            color: .black.opacity(isLight ? 0.10 : 0.38),
            blur: 6,
            y: 2)
    }

    // MARK: Bars

    /// A bar's interior: lit across the top few points, occluded across the
    /// bottom few, nothing in between. Filled *into the bar's own shape*, so it
    /// cannot paint outside a rounded or capsule silhouette.
    ///
    /// **The two leanings are not mirror images.** On a dark ground the *glint*
    /// tells you where the bar starts and the occlusion is a grace note; on
    /// paper a white glint against a white page is invisible and the whole
    /// delineation falls to the occlusion, so its dark end nearly doubles. The
    /// ramp is 28% of the bar's height rather than a hairline for the reason
    /// this rung exists at all: a soft ramp has no line to end on.
    public static func barSheen(isLight: Bool) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(isLight ? 0.22 : 0.07), location: 0),
                .init(color: .white.opacity(0), location: 0.22),
                .init(color: .black.opacity(0), location: 0.72),
                .init(color: .black.opacity(isLight ? 0.08 : 0.13), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom)
    }

    /// A bar's rim: the top arc only, and nothing anywhere else. Masked by
    /// `barGlintFalloff` before it is drawn.
    public static func barRim(isLight: Bool) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(isLight ? 0.75 : 0.42), location: 0),
                .init(color: .white.opacity(isLight ? 0.20 : 0.10), location: 0.10),
                .init(color: .white.opacity(0), location: 0.26),
            ],
            startPoint: .top,
            endPoint: .bottom)
    }

    /// **The reason a bar does not read as a seam.** A mask that is fully
    /// opaque across the middle 40% of the bar and zero at both ends, so the
    /// specular line has nowhere to terminate — it simply runs out of light.
    ///
    /// The plateau is off-centre (0.30…0.66 rather than 0.32…0.68) because the
    /// suite's ground light is off-centre too; a glint centred to the pixel on a
    /// symmetric bar is the one arrangement that reads as drawn rather than lit.
    public static var barGlintFalloff: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white, location: 0.30),
                .init(color: .white, location: 0.66),
                .init(color: .white.opacity(0), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing)
    }
}

// The three material rungs that need to read `accessibilityReduceTransparency`
// live as modifiers because a `View` extension has no environment of its own.

@available(tvOS 26.0, iOS 26.0, macOS 26.0, watchOS 26.0, *)
private struct CouchClearGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S

    func body(content: Content) -> some View {
        if reduceTransparency {
            // `.clear` over live content is the one rung that becomes actively
            // unreadable when the system asks for less transparency, so it
            // falls all the way to an opaque backing rather than to `.regular`.
            content.modifier(CouchOpaqueBacking(shape: shape, tint: nil))
        } else {
            content.glassEffect(.clear, in: shape)
        }
    }
}

@available(tvOS 26.0, iOS 26.0, macOS 26.0, watchOS 26.0, *)
private struct CouchTintedGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    let tint: Color

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.modifier(
                CouchOpaqueBacking(shape: shape, tint: tint.opacity(0.30), rimOpacity: 0.35))
        } else {
            content.glassEffect(.regular.tint(tint), in: shape)
        }
    }
}

@available(tvOS 26.0, iOS 26.0, macOS 26.0, watchOS 26.0, *)
private struct CouchIdentityGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    let tint: Color

    func body(content: Content) -> some View {
        if reduceTransparency {
            // Still no second material — an inset element under Reduce
            // Transparency wants a firmer tint and a visible edge, not a pane.
            content
                .background(tint.opacity(0.9), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.22), lineWidth: 1))
        } else {
            content
                .glassEffect(.identity, in: shape)
                .background(tint, in: shape)
        }
    }
}

/// The rim without the lift — see `couchRim(in:isLight:)`.
private struct CouchRim<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    let isLight: Bool

    /// The shipped rim, kept **only** for tvOS. See `CouchSpecular`: four
    /// sibling apps are on this path and must render byte-identically.
    private var tvRim: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(isLight ? 0.9 : 0.20),
                .white.opacity(isLight ? 0.2 : 0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func body(content: Content) -> some View {
        content.overlay { edge }
    }

    /// Under Reduce Transparency the rim collapses to a single flat stroke on
    /// every platform: a specular gradient is a lighting cue, and a player who
    /// has turned transparency down is asking for edges instead.
    @ViewBuilder
    private var edge: some View {
        if reduceTransparency {
            shape
                .strokeBorder(Color.primary.opacity(isLight ? 0.45 : 0.35), lineWidth: 1)
                .allowsHitTesting(false)
        } else {
            #if os(tvOS)
            shape
                .strokeBorder(tvRim, lineWidth: 1)
                .allowsHitTesting(false)
            #else
            ZStack {
                shape.strokeBorder(
                    CouchSpecular.rim(isLight: isLight),
                    lineWidth: CouchSpecular.width)
                // The thickness line: one point in, top arc only.
                shape
                    .inset(by: CouchSpecular.width)
                    .strokeBorder(
                        CouchSpecular.innerHighlight(isLight: isLight),
                        lineWidth: CouchSpecular.width)
            }
            .allowsHitTesting(false)
            #endif
        }
    }
}

private struct CouchElevation<S: InsettableShape>: ViewModifier {
    let shape: S
    let isLight: Bool

    func body(content: Content) -> some View {
        content
            .background { lift }
            .modifier(CouchRim(shape: shape, isLight: isLight))
    }

    /// The shadow. One layer on tvOS (unchanged), two everywhere else — see
    /// `CouchSpecular.ambient` / `.contact` for why one cannot do both jobs.
    @ViewBuilder
    private var lift: some View {
        #if os(tvOS)
        shape
            .fill(.black.opacity(isLight ? 0.14 : 0.55))
            .blur(radius: 20)
            .offset(y: 8)
            .allowsHitTesting(false)
        #else
        ZStack {
            shape
                .fill(ambient.color)
                .blur(radius: ambient.blur)
                .offset(y: ambient.y)
            shape
                .fill(contact.color)
                .blur(radius: contact.blur)
                .offset(y: contact.y)
        }
        .allowsHitTesting(false)
        #endif
    }

    private var ambient: CouchSpecular.Shadow { CouchSpecular.ambient(isLight: isLight) }
    private var contact: CouchSpecular.Shadow { CouchSpecular.contact(isLight: isLight) }
}

/// The bar rung's implementation — see `couchGlassBar(in:isLight:)`.
///
/// A modifier rather than a `View` extension because, like the three material
/// rungs above, it has to read `accessibilityReduceTransparency`, and a `View`
/// extension has no environment of its own.
private struct CouchBarGlass<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    let isLight: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            // Same reasoning as `CouchClearGlass`: `.clear` over live content is
            // the rung that becomes unreadable when the system asks for less
            // transparency, so it falls all the way to an opaque backing. A
            // player in that mode gets the hard edge the specular treatment
            // spends its whole budget avoiding, and wants it.
            content.modifier(CouchOpaqueBacking(shape: shape, tint: nil))
        } else {
            content
                .couchGlassOverContent(in: shape)
                .overlay {
                    shape
                        .fill(CouchSpecular.barSheen(isLight: isLight))
                        .allowsHitTesting(false)
                }
                .overlay {
                    shape
                        .strokeBorder(
                            CouchSpecular.barRim(isLight: isLight),
                            lineWidth: CouchSpecular.width)
                        // Without this mask the top arc is a full-bleed 1pt
                        // hairline — precisely the "hard seam" the rung exists
                        // to delete.
                        .mask { CouchSpecular.barGlintFalloff }
                        .allowsHitTesting(false)
                }
        }
    }
}

/// Wrap sibling glass elements so adjacent shapes merge fluidly on tvOS 26.
/// On earlier systems it is a plain `Group` — elements simply sit side by
/// side, which is an acceptable degradation of the same layout.
public struct CouchGlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(tvOS 26.0, iOS 26.0, macOS 26.0, watchOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            Group {
                content
            }
        }
    }
}
#endif
