// FlickRoseView.swift — the signature moment: a 3×3 glass petal ring that
// blossoms around the focused cell. Digits map onto the rose like a phone
// keypad: 1 2 3 / 4 5 6 / 7 8 9 (center = 5 = tap). Completed digits are
// dimmed. In pencil mode the petals shrink. The rose stays open while a
// focus ring walks the petals (swipes, on every remote — the click path's
// honest preview) and click places; a clean 8-way flick places instantly.
import SwiftUI
import CouchKit

/// UI state for one open rose.
struct RoseState: Equatable {
    var pencil: Bool
    /// Petal index 0…8 (digit − 1) the d-pad focus is on. Starts at center.
    var focusedIndex: Int = 4
    /// Petals to shimmer after an ambiguous flick (see COUCHKIT-ASKS.md —
    /// CouchKit currently swallows ambiguous strokes, so this stays empty
    /// until the kit can report them; the misfire guarantee holds either way).
    var shimmerDigits: Set<Int> = []
    /// When the rose opened — used to ignore the tail of the click-touch
    /// that opened it, so a click can never read back as a center flick.
    var openedAt: Date = Date()
}

/// Digit ↔ 8-way direction mapping (keypad layout, +y up per CouchCore).
enum RoseGeometry {
    static func digit(for direction: Direction8OrCenter) -> Int {
        switch direction {
        case .upLeft: return 1
        case .up: return 2
        case .upRight: return 3
        case .left: return 4
        case .center: return 5
        case .right: return 6
        case .downLeft: return 7
        case .down: return 8
        case .downRight: return 9
        }
    }

    /// Petal offset in grid steps for digit 1…9: (-1,-1) top-left … (1,1).
    static func offset(forDigit digit: Int) -> (x: CGFloat, y: CGFloat) {
        let index = digit - 1
        return (CGFloat(index % 3 - 1), CGFloat(index / 3 - 1))
    }

    /// Move the 4-way petal focus. Screen-up decreases the row.
    static func moveFocus(_ index: Int, _ direction: Direction4) -> Int {
        var row = index / 3, col = index % 3
        switch direction {
        case .up: row = max(0, row - 1)
        case .down: row = min(2, row + 1)
        case .left: col = max(0, col - 1)
        case .right: col = min(2, col + 1)
        }
        return row * 3 + col
    }
}

struct FlickRoseView: View {
    let state: RoseState
    let accent: Color
    let completedDigits: Set<Int>
    /// Show the d-pad focus ring (always on — the click path's preview).
    let showsFocusRing: Bool

    @State private var bloomed = false

    private var petalSize: CGFloat { state.pencil ? 88 : 116 }
    private var spacing: CGFloat { state.pencil ? 96 : 126 }

    var body: some View {
        CouchGlassContainer(spacing: 12) {
            ZStack {
                ForEach(1...9, id: \.self) { digit in
                    petal(for: digit)
                }
            }
        }
        .frame(width: spacing * 2 + petalSize, height: spacing * 2 + petalSize)
        .scaleEffect(bloomed ? 1.0 : 0.35)
        .opacity(bloomed ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.couchFast) { bloomed = true }
        }
    }

    private func petal(for digit: Int) -> some View {
        let offset = RoseGeometry.offset(forDigit: digit)
        let complete = completedDigits.contains(digit)
        let focused = showsFocusRing && state.focusedIndex == digit - 1
        let shimmering = state.shimmerDigits.contains(digit)

        return Text("\(digit)")
            .font(.system(size: state.pencil ? 38 : 52, weight: .semibold, design: .rounded))
            .foregroundStyle(complete ? Color.white.opacity(0.28) : Color.primary)
            .frame(width: petalSize, height: petalSize)
            .couchGlassInteractive(in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(accent.opacity(focused ? 0.95 : 0), lineWidth: 4)
            }
            .scaleEffect(focused ? 1.1 : 1.0)
            .modifier(ShimmerPulse(active: shimmering, accent: accent))
            .offset(x: offset.x * spacing, y: offset.y * spacing)
            .animation(.couchFast, value: focused)
    }
}

/// A quiet two-beat glow for ambiguous-flick candidates: "one of these two —
/// flick again, cleaner." Never fires a digit.
private struct ShimmerPulse: ViewModifier {
    let active: Bool
    let accent: Color
    @State private var phase = false

    func body(content: Content) -> some View {
        content
            .overlay {
                Circle()
                    .strokeBorder(accent.opacity(active ? (phase ? 0.85 : 0.25) : 0), lineWidth: 3)
            }
            .onChange(of: active) { _, nowActive in
                guard nowActive else { return }
                withAnimation(.easeInOut(duration: 0.35).repeatCount(4, autoreverses: true)) {
                    phase = true
                }
            }
            .onAppear { phase = false }
    }
}
