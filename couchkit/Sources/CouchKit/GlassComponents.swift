// The CouchUI component set (PRD §5.1). All chrome is transient glass:
// it appears on remote touch and recedes after ~3s of stillness, driven by
// a shared `ChromeVisibility` that RemoteKit pokes on every gesture.
// On iOS and macOS the same components render at handheld / desk scale
// (CouchScale.chrome); focus-engine affordances (FocusHalo) degrade to
// no-ops there. On macOS a GlassSheet dismisses on a scrim click, as iOS.
#if os(tvOS) || os(iOS) || os(macOS) || os(watchOS)
import SwiftUI
import CouchCore
import Observation
// `ContentTransition.symbolEffect(_:)` takes a `Symbols.SymbolEffect`, and
// SwiftUI imports that module without re-exporting it — so `.replace` does not
// resolve on a bare `import SwiftUI`. Present on every SDK this file compiles
// for (iOS/tvOS 17, macOS 14, watchOS 10; every deployment target here is above
// that floor).
import Symbols

// MARK: - ChromeVisibility

/// Single source of truth for "is the chrome awake?". Create one per screen,
/// pass it to `.couchRemote(chrome:)` and to every glass component. Any
/// remote activity calls `touch()`; after `idleDelay` seconds of stillness
/// the chrome recedes and `IdleAttract` may begin drifting the content.
@MainActor @Observable
public final class ChromeVisibility {
    public private(set) var isVisible = false
    public private(set) var lastInteraction = Date.distantPast
    public var idleDelay: TimeInterval

    @ObservationIgnored private var recedeTask: Task<Void, Never>?

    public init(idleDelay: TimeInterval = 3) {
        self.idleDelay = idleDelay
    }

    /// Note remote activity: reveal chrome and restart the recede timer.
    public func touch() {
        lastInteraction = Date()
        withAnimation(.couchFast) { isVisible = true }
        recedeTask?.cancel()
        recedeTask = Task { [idleDelay] in
            try? await Task.sleep(nanoseconds: UInt64(idleDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.couchAmbient) { self.isVisible = false }
        }
    }

    /// Hide immediately (e.g. when ambient playback starts).
    public func hide() {
        recedeTask?.cancel()
        withAnimation(.couchAmbient) { isVisible = false }
    }
}

// MARK: - The shared edge
//
// **Every glass component in this file shipped without a rim**, which is the
// component-level half of the round-2 blocker recorded in `CouchGlass.swift`:
// a capsule of `.regular` glass over a near-black ground composites to a flat
// grey pill, and ten of fourteen critics said so in the same words. The rungs
// gained specular articulation; the components have to actually ask for it.
//
// `couchRim` rather than `couchElevated` because a chip is *flush* — it is a
// caption sitting on the page, not a card floating above it — and giving every
// toast a drop shadow is how a screen starts looking like a pile of stickers.
//
// tvOS is excluded, not by taste but by rule: Rabbit Ears, Darkroom, Blockhead
// and Cartridge render these exact components and must be byte-identical.
#if !os(tvOS)
extension View {
    /// The rim a shared component applies to itself, resolved from the
    /// environment rather than from a parameter.
    ///
    /// A component cannot take `isLight:` — `GlassChip`'s initialisers are
    /// public API in four shipped apps and adding an argument every call site
    /// would have to pass defeats the point. It reads `\.colorScheme` instead,
    /// which is correct here for a specific reason: every app in the suite pins
    /// the scheme its theme leans to (Nine's `RootView` calls
    /// `.preferredColorScheme(theme.colorScheme)`), so the resolved scheme *is*
    /// the ground's leaning, on Camel in a dark-mode phone as much as anywhere.
    fileprivate func couchComponentRim(in shape: some InsettableShape) -> some View {
        modifier(CouchComponentRim(shape: shape))
    }
}

private struct CouchComponentRim<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let shape: S

    func body(content: Content) -> some View {
        content.couchRim(in: shape, isLight: colorScheme == .light)
    }
}
#else
extension View {
    /// tvOS: a no-op, so the call sites below need no `#if` of their own.
    fileprivate func couchComponentRim(in shape: some InsettableShape) -> some View {
        self
    }
}
#endif

/// Shared transient-chrome treatment: fade + blur + slide as chrome recedes.
struct TransientChrome: ViewModifier {
    let chrome: ChromeVisibility
    var hiddenOffsetY: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .opacity(chrome.isVisible ? 1 : 0)
            .blur(radius: chrome.isVisible ? 0 : 12)
            .offset(y: chrome.isVisible ? 0 : hiddenOffsetY)
            .animation(chrome.isVisible ? .couchFast : .couchAmbient, value: chrome.isVisible)
    }
}

// MARK: - GlassPill

/// One action in a `GlassPill`.
public struct GlassAction: Identifiable {
    public let id: String
    public let symbol: String
    public let label: String
    public let action: @MainActor () -> Void

    public init(id: String? = nil, symbol: String, label: String, action: @escaping @MainActor () -> Void) {
        self.id = id ?? symbol
        self.symbol = symbol
        self.label = label
        self.action = action
    }
}

/// The suite's floating control strip: a capsule of 1–5 actions near the
/// bottom edge. Appears on remote touch, recedes after the chrome idles.
public struct GlassPill: View {
    private let actions: [GlassAction]
    private let chrome: ChromeVisibility

    public init(actions: [GlassAction], chrome: ChromeVisibility) {
        precondition(!actions.isEmpty && actions.count <= 5, "GlassPill hosts 1–5 actions")
        self.actions = actions
        self.chrome = chrome
    }

    public var body: some View {
        CouchGlassContainer(spacing: 28 * CouchScale.chrome) {
            HStack(spacing: 34 * CouchScale.chrome) {
                ForEach(actions) { item in
                    Button(action: item.action) {
                        Label(item.label, systemImage: item.symbol)
                            .labelStyle(.iconOnly)
                            .font(.system(size: 34 * CouchScale.chrome, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.label)
                }
            }
            .padding(.horizontal, 44 * CouchScale.chrome)
            .padding(.vertical, 22 * CouchScale.chrome)
            .couchGlass(in: Capsule())
            .couchComponentRim(in: Capsule())
        }
        .modifier(TransientChrome(chrome: chrome))
    }
}

// MARK: - GlassChip

/// Small caption capsule, e.g. "June 2019 · Lake Tahoe". One line, vibrant.
///
/// **Its numbers are tabular and its symbol replaces in place.** The chip is the
/// suite's only ticking surface — Nine parks the live game clock in one — and it
/// shipped with proportional figures, so a `1` was narrower than a `0` and the
/// capsule visibly re-measured itself every second. `.monospacedDigit()` plus
/// `.contentTransition(.numericText())` fixes both halves of that: the width
/// stops moving and the digit that changed rolls rather than cutting.
public struct GlassChip: View {
    /// How loudly the chip speaks.
    ///
    /// `.secondary` is the shipped treatment and stays byte-identical: the
    /// footnote tier in `.secondary`, neutral glass. `.hero` is for the one chip
    /// on screen that is an *announcement* rather than a caption — Nine's
    /// completion chip reported twenty minutes of work in the same grey
    /// footnote as an undo toast.
    public enum Emphasis: Equatable, Sendable {
        /// The default. A caption.
        case secondary
        /// An announcement, in the environment's resolved tint. Set `.tint(_:)`
        /// on an ancestor (Nine's `RootView` plants the player's accent there)
        /// or use `heroTint(_:)` to pass a colour directly.
        case hero
        /// `.hero` with an explicit colour, for a call site with a resolved
        /// accent in hand and no ancestor tint.
        case heroTint(Color)

        var isHero: Bool { self != .secondary }

        var font: Font {
            switch self {
            case .secondary: return CouchTypography.label
            // `heading` is `.title3` semibold on handheld — ~20pt at the default
            // Dynamic Type size — and `.bold()` takes it the last step.
            case .hero, .heroTint(_): return CouchTypography.heading.bold()
            }
        }

        var symbolFont: Font {
            switch self {
            case .secondary:
                return .system(size: 24 * CouchScale.chrome, weight: .semibold)
            case .hero, .heroTint(_):
                return .system(size: 30 * CouchScale.chrome, weight: .bold)
            }
        }

        var foreground: AnyShapeStyle {
            switch self {
            case .secondary: return AnyShapeStyle(HierarchicalShapeStyle.secondary)
            // `TintShapeStyle()` rather than `.tint`: the shorthand only exists
            // on a constrained protocol extension, and spelling the concrete
            // type is the form that cannot become ambiguous inside an
            // `AnyShapeStyle` initialiser.
            case .hero: return AnyShapeStyle(TintShapeStyle())
            case .heroTint(let color): return AnyShapeStyle(color)
            }
        }
    }

    private let text: String
    private let systemImage: String?
    private let emphasis: Emphasis

    public init(
        _ text: String,
        systemImage: String? = nil,
        emphasis: Emphasis = .secondary
    ) {
        self.text = text
        self.systemImage = systemImage
        self.emphasis = emphasis
    }

    public var body: some View {
        HStack(spacing: 12 * CouchScale.chrome) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(emphasis.symbolFont)
                    // A chip whose symbol swaps (pause → play, cloud → check)
                    // used to hard-cut. `.replace` is the system's own symbol
                    // crossfade and costs nothing when the symbol never changes.
                    .contentTransition(.symbolEffect(.replace))
            }
            Text(text)
                .font(emphasis.font)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
        }
        .foregroundStyle(emphasis.foreground)
        .padding(.horizontal, (emphasis.isHero ? 34 : 28) * CouchScale.chrome)
        .padding(.vertical, (emphasis.isHero ? 18 : 14) * CouchScale.chrome)
        .couchGlass(in: Capsule())
        .couchComponentRim(in: Capsule())
    }
}

// MARK: - GlassSheet

/// The one allowed secondary surface. Dismisses on Back (tvOS), on a tap on the
/// scrim beside it (a trailing panel), or by dragging it down (a compact sheet).
/// Only one may exist per app (suite rule — enforced by taste, not code).
///
/// **Two presentations, chosen by width, and that is the fix.** The non-tvOS
/// path was one hand-rolled `ZStack` for every screen: a panel pinned to the
/// trailing edge at `maxWidth: 380` inside a 393pt phone, which on an iPhone
/// leaves a **6.7pt** dismiss sliver on the left against a 16pt gutter on the
/// right — an asymmetry you can see without measuring — with no detents, no
/// grabber, no interactive dismiss, and no `.isModal`, so the board's 81 cells
/// and its whole control bar stayed in the VoiceOver tree *behind* the sheet.
///
/// * **Compact width** (a phone in portrait) now presents through the system
///   `.sheet` with `[.fraction(0.72), .large]` detents, a visible drag
///   indicator and a 38pt corner radius. That buys the grabber, the drag, the
///   swipe-down dismiss and the AX containment for free, and it is what a
///   secondary surface on a phone has looked like since iOS 15.
/// * **Regular width** (iPad, Mac, and anything with room beside the content)
///   keeps the trailing panel, because the whole point there is that the board
///   stays visible and workable while you read the panel. Its gutters are now
///   symmetric and it gets `couchElevated`, so it reads as floating rather than
///   as a lighter rectangle painted on the page.
///
/// tvOS is untouched: a television has one width, no drag and no grabber, and
/// four sibling apps present their only sheet through this path.
public struct GlassSheet<Content: View>: View {
    @Binding private var isPresented: Bool
    private let content: Content
    private let scrim: Color
    private let isLight: Bool

    // iOS only: `Material` (which the compact path's presentation background
    // needs) is unavailable on watchOS, and a Mac window is a trailing-panel
    // proposition at every width. The size class is only ever consulted where
    // both presentations are real.
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// - Parameters:
    ///   - scrim: the dim behind the trailing panel. Defaults to the shipped
    ///     0.45 black so no existing call site changes; Nine passes its
    ///     theme-aware `Scrim.overlay`.
    ///   - isLight: whether the ground behind the panel is light-leaning, which
    ///     the elevation rim and shadow need (white-on-white is the hardest
    ///     edge there is). Defaults to the suite's dark-first assumption.
    public init(
        isPresented: Binding<Bool>,
        scrim: Color = Color.black.opacity(0.45),
        isLight: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self._isPresented = isPresented
        self.scrim = scrim
        self.isLight = isLight
        self.content = content()
    }

    private static var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
    }

    @ViewBuilder
    public var body: some View {
        #if os(tvOS)
        tvPanel
        #elseif os(iOS)
        if horizontalSizeClass == .compact {
            compactSheet
        } else {
            trailingPanel
        }
        #else
        trailingPanel
        #endif
    }

    #if os(tvOS)
    private var tvPanel: some View {
        ZStack(alignment: .trailing) {
            if isPresented {
                content
                    .frame(width: 720)
                    .frame(maxHeight: .infinity)
                    .padding(40)
                    .couchGlass(in: RoundedRectangle(cornerRadius: 44, style: .continuous))
                    .padding(.trailing, 48)
                    .padding(.vertical, 48)
                    .focusSection()
                    .onExitCommand { isPresented = false }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .animation(.couchFast, value: isPresented)
    }
    #endif

    #if os(iOS)
    /// Phone-shaped: a real sheet, with everything a real sheet already knows.
    ///
    /// The host is `Color.clear` at zero size rather than `EmptyView` because a
    /// `.sheet` needs a view that is actually in the hierarchy to present from,
    /// and this component is attached through `.overlay { … }` at every call
    /// site — an empty overlay is still an overlay, but it must not claim
    /// layout or swallow taps meant for the board underneath.
    private var compactSheet: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .sheet(isPresented: $isPresented) {
                content
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 22)
                    // **0.72, not 0.55.** The smaller detent was chosen so the
                    // board stayed legible behind the sheet, and it does — but
                    // it also put more than half of Nine's Preferences below an
                    // invisible fold: the first frame reached "Feel" and stopped,
                    // so the theme swatches, all ten accents, the icon picker and
                    // the whole Layout section looked like the end of the sheet
                    // rather than the middle of it. A detent that hides the
                    // majority of a settings screen is not a smaller sheet, it is
                    // a truncated one. 0.72 clears the swatches while still
                    // leaving the board visible above, which is what the material
                    // background is for.
                    .presentationDetents([.fraction(0.72), .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(38)
                    // The suite's rule is that no component draws an opaque
                    // background; a material keeps the board legible behind the
                    // sheet at the first detent, which is the whole reason that
                    // detent is not `.large`.
                    .presentationBackground(.regularMaterial)
                    .accessibilityAddTraits(.isModal)
            }
    }
    #endif

    #if !os(tvOS)
    /// iPad, Mac, and any regular-width window: a trailing panel beside the
    /// content, with symmetric gutters and a real lift.
    private var trailingPanel: some View {
        ZStack(alignment: .trailing) {
            if isPresented {
                // Glass panels float over live content, so the board stays
                // visible but a tap anywhere beside the sheet closes it.
                scrim
                    .ignoresSafeArea()
                    .onTapGesture { isPresented = false }
                    .transition(.opacity)
                content
                    .padding(22)
                    .frame(maxWidth: 380, maxHeight: .infinity)
                    .couchGlass(in: Self.panelShape)
                    .couchElevated(in: Self.panelShape, isLight: isLight)
                    // Symmetric, and horizontal rather than trailing-only: the
                    // shipped `.padding(.trailing, 16)` let the panel's own
                    // 380pt frame eat the left gutter down to 6.7pt.
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    // The board behind is decoration while this is open.
                    .accessibilityAddTraits(.isModal)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .animation(.couchFast, value: isPresented)
    }
    #endif
}

// MARK: - GlassRing

/// Circular progress/timer ring (Blockhead's countdown, Darkroom's develop
/// progress). Stroke picks up content color via vibrancy.
public struct GlassRing: View {
    private let progress: Double
    private let lineWidth: CGFloat

    public init(progress: Double, lineWidth: CGFloat = 10) {
        self.progress = max(0, min(1, progress))
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: progress)
                .stroke(.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.couchFast, value: progress)
        }
        .padding(lineWidth / 2)
        .couchGlass(in: Circle())
        .couchComponentRim(in: Circle())
    }
}

// MARK: - FocusHalo

/// The standard focus treatment for full-bleed tiles: scale 1.0 → 1.03, a
/// specular sweep, and a soft shadow lift — so all five apps focus alike.
/// tvOS-only in effect: on iOS there is no focus engine to react to, so the
/// modifier passes content through untouched (touch feedback belongs to the
/// tappable control itself).
#if os(tvOS)
public struct FocusHalo<S: Shape>: ViewModifier {
    @FocusState private var isFocused: Bool
    private let claimsDefaultFocus: Bool
    private let shape: S

    public init(shape: S, claimsDefaultFocus: Bool = false) {
        self.shape = shape
        self.claimsDefaultFocus = claimsDefaultFocus
    }

    public func body(content: Content) -> some View {
        content
            .focusable()
            .focused($isFocused)
            .onAppear {
                // Plain focusable views don't reliably receive default focus
                // on tvOS at scene launch — remote presses then land nowhere.
                // The screen's primary tile claims it, like RemoteKit does.
                guard claimsDefaultFocus else { return }
                isFocused = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    if !isFocused { isFocused = true }
                }
            }
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .overlay {
                // The specular sweep is clipped to the tile's own silhouette by
                // filling the shape — an unclipped rectangle overlay used to
                // paint sharp corners the caller's .clipShape had already
                // rounded off (the tvOS "black rectangle" artifact).
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.16), .clear, .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(false)
            }
            .background {
                // Explicit silhouette shadow: a blurred fill of the tile's own
                // shape, so the lift never trusts the glass layer's alpha (a
                // `.shadow` silhouettes whatever opaque geometry it finds, which
                // was the pre-clip rectangle). Matches the rounded card exactly.
                shape.fill(.black.opacity(isFocused ? 0.45 : 0))
                    .blur(radius: 30)
                    .offset(y: 16)
                    .allowsHitTesting(false)
            }
            .animation(.couchFast, value: isFocused)
    }
}

extension View {
    /// Shape-aware focus halo — the sweep and lift hug this silhouette. Pass
    /// the same shape the caller clips the tile to.
    public func focusHalo(in shape: some Shape, claimsDefaultFocus: Bool = false) -> some View {
        modifier(FocusHalo(shape: shape, claimsDefaultFocus: claimsDefaultFocus))
    }

    /// Source-compatible no-shape overload — delegates to a rectangle (the
    /// historical behavior) so existing callers keep compiling.
    public func focusHalo(claimsDefaultFocus: Bool = false) -> some View {
        focusHalo(in: Rectangle(), claimsDefaultFocus: claimsDefaultFocus)
    }
}
#else
extension View {
    /// No-op on iOS — keeps shared view code platform-agnostic.
    public func focusHalo(in shape: some Shape, claimsDefaultFocus: Bool = false) -> some View {
        self
    }

    public func focusHalo(claimsDefaultFocus: Bool = false) -> some View {
        self
    }
}
#endif

// MARK: - IdleAttract

/// Every app's default resting state: after the chrome idles, content begins
/// a slow deterministic Ken Burns drift. Pass the same `ChromeVisibility`
/// that RemoteKit updates; any input snaps the content home with `couchFast`.
public struct IdleAttract: ViewModifier {
    private let chrome: ChromeVisibility
    private let drift: DriftPath

    public init(chrome: ChromeVisibility, drift: DriftPath = DriftPath(seed: 0xCA1F)) {
        self.chrome = chrome
        self.drift = drift
    }

    public func body(content: Content) -> some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: chrome.isVisible)) { timeline in
                let idle = !chrome.isVisible
                let state = idle
                    ? drift.state(at: timeline.date.timeIntervalSinceReferenceDate)
                    : DriftState.identity
                content
                    .scaleEffect(state.zoom)
                    .offset(
                        x: state.offsetX * geo.size.width,
                        y: state.offsetY * geo.size.height
                    )
                    .animation(idle ? .couchAmbient : .couchFast, value: idle)
            }
        }
        .clipped()
    }
}

extension View {
    public func idleAttract(chrome: ChromeVisibility, drift: DriftPath = DriftPath(seed: 0xCA1F)) -> some View {
        modifier(IdleAttract(chrome: chrome, drift: drift))
    }
}
#endif
