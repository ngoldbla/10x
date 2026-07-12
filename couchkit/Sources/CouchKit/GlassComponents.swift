// The CouchUI component set (PRD §5.1). All chrome is transient glass:
// it appears on remote touch and recedes after ~3s of stillness, driven by
// a shared `ChromeVisibility` that RemoteKit pokes on every gesture.
#if os(tvOS)
import SwiftUI
import CouchCore
import Observation

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
        CouchGlassContainer(spacing: 28) {
            HStack(spacing: 34) {
                ForEach(actions) { item in
                    Button(action: item.action) {
                        Label(item.label, systemImage: item.symbol)
                            .labelStyle(.iconOnly)
                            .font(.system(size: 34, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.label)
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 22)
            .couchGlass(in: Capsule())
        }
        .modifier(TransientChrome(chrome: chrome))
    }
}

// MARK: - GlassChip

/// Small caption capsule, e.g. "June 2019 · Lake Tahoe". One line, vibrant.
public struct GlassChip: View {
    private let text: String
    private let systemImage: String?

    public init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 24, weight: .semibold))
            }
            Text(text)
                .font(CouchTypography.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .couchGlass(in: Capsule())
    }
}

// MARK: - GlassSheet

/// The one allowed secondary surface: a full-height trailing sheet on glass.
/// Dismisses on Back. Only one may exist per app (suite rule — enforced by
/// taste, not code).
public struct GlassSheet<Content: View>: View {
    @Binding private var isPresented: Bool
    private let content: Content

    public init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isPresented = isPresented
        self.content = content()
    }

    public var body: some View {
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
    }
}

// MARK: - FocusHalo

/// The standard focus treatment for full-bleed tiles: scale 1.0 → 1.03, a
/// specular sweep, and a soft shadow lift — so all five apps focus alike.
public struct FocusHalo: ViewModifier {
    @FocusState private var isFocused: Bool

    public init() {}

    public func body(content: Content) -> some View {
        content
            .focusable()
            .focused($isFocused)
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .overlay {
                LinearGradient(
                    colors: [.white.opacity(0.16), .clear, .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(isFocused ? 0.55 : 0),
                radius: isFocused ? 34 : 0, y: isFocused ? 18 : 0
            )
            .animation(.couchFast, value: isFocused)
    }
}

extension View {
    public func focusHalo() -> some View {
        modifier(FocusHalo())
    }
}

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
