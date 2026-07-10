// CouchGlass — THE Liquid Glass shim.
//
// This is the ONLY file in the entire Couch Suite allowed to reference the
// Liquid Glass API directly. Every component and every app goes through
// `couchGlass(in:)` / `CouchGlassContainer`, so:
//
//   ⚠️ If Liquid Glass API names differ in your SDK, fix them HERE only.
//
// On tvOS 26+ we use `.glassEffect(.regular, in:)` and `GlassEffectContainer`.
// Below 26 (deployment target is tvOS 18) we fall back to
// `.ultraThinMaterial` plus a subtle stroke — same silhouette, no lensing.
#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// The suite's glass treatment clipped to `shape`.
    /// Use instead of any direct material/glass call.
    @ViewBuilder
    public func couchGlass(in shape: some Shape) -> some View {
        if #available(tvOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
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
        if #available(tvOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
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
        if #available(tvOS 26.0, *) {
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
