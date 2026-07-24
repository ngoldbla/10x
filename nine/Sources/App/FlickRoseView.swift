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

    /// Classify a pointer/finger drag as one of eight petal directions
    /// (screen +y is down; the rose keypad thinks in +y up, matching
    /// CouchCore's flick math). Returns nil for a stroke shorter than
    /// `minimumDistance` — the never-misfire rule: an ambiguous nudge places
    /// nothing. Shared by the iOS touch rose and the macOS pointer rose
    /// (PRD-4 §2.3), so a trackpad drag and a finger flick classify
    /// identically.
    static func flickDirection(
        _ translation: CGSize, minimumDistance: CGFloat = 24
    ) -> Direction8OrCenter? {
        let dx = translation.width
        let dy = -translation.height
        guard hypot(dx, dy) >= minimumDistance else { return nil }
        let sector = Int((atan2(dy, dx) / (.pi / 4)).rounded())
        switch sector {
        case 0: return .right
        case 1: return .upRight
        case 2: return .up
        case 3: return .upLeft
        case 4, -4: return .left
        case -1: return .downRight
        case -2: return .down
        case -3: return .downLeft
        default: return nil
        }
    }
}

struct FlickRoseView: View {
    let state: RoseState
    let accent: Color
    let completedDigits: Set<Int>
    /// Show the d-pad focus ring (always on — the click path's preview).
    let showsFocusRing: Bool
    /// Multiplier on every petal metric. 1.0 is the TV rose; the touch rose
    /// passes something near 0.45 so petals sit finger-sized over the board.
    var scale: CGFloat = 1.0
    /// Per-digit count of that digit still to place (index 0 = digit 1). When
    /// nil the rose draws no counts — the shared TV/Mac/tutorial default.
    var remainingCounts: [Int]? = nil
    /// Adds a tenth "erase" petal below the ring. Off for givens/empty cells
    /// and every non-iOS surface.
    var showsErase: Bool = false

    @State private var bloomed = false

    private var petalSize: CGFloat { (state.pencil ? 88 : 116) * scale }
    private var spacing: CGFloat { (state.pencil ? 96 : 126) * scale }
    /// Center-to-center drop from the bottom petal row to the erase glyph.
    private var eraseDrop: CGFloat { spacing * 0.92 }
    /// Extra height below the ring when the erase petal is present.
    private var eraseAllowance: CGFloat { showsErase ? eraseDrop : 0 }

    var body: some View {
        CouchGlassContainer(spacing: 12) {
            ZStack {
                ForEach(1...9, id: \.self) { digit in
                    petal(for: digit)
                }
                if !state.pencil, let counts = remainingCounts {
                    ForEach(1...9, id: \.self) { digit in
                        countCaption(for: digit, remaining: counts[digit - 1])
                    }
                }
                if showsErase, !state.pencil {
                    erasePetal
                }
            }
        }
        // Grow the frame *symmetrically* for the erase petal so the drawn
        // petals stay centered — TouchRose's tap targets are centered on this
        // same frame, and any asymmetry (e.g. `.top`) desyncs touch from paint.
        .frame(width: spacing * 2 + petalSize,
               height: spacing * 2 + petalSize + eraseAllowance * 2)
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
            .font(.system(size: (state.pencil ? 38 : 52) * scale, weight: .semibold, design: .rounded))
            .foregroundStyle(complete ? Color.white.opacity(0.28) : Color.primary)
            .frame(width: petalSize, height: petalSize)
            .couchGlassInteractive(in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(accent.opacity(focused ? 0.95 : 0), lineWidth: max(2, 4 * scale))
            }
            .scaleEffect(focused ? 1.1 : 1.0)
            .modifier(ShimmerPulse(active: shimmering, accent: accent))
            .offset(x: offset.x * spacing, y: offset.y * spacing)
            .animation(.couchFast, value: focused)
    }

    /// "N left" (or "done" in the accent) tucked under a petal. iOS-only —
    /// pencil roses and non-iOS surfaces pass `remainingCounts == nil`.
    private func countCaption(for digit: Int, remaining: Int) -> some View {
        let offset = RoseGeometry.offset(forDigit: digit)
        let complete = remaining <= 0
        return Text(complete ? "done" : "\(remaining) left")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(complete ? accent : Color.secondary)
            .fixedSize()
            .offset(x: offset.x * spacing,
                    y: offset.y * spacing + petalSize / 2 + 4)
    }

    /// The tenth petal: an eraser glyph directly below the 7-8-9 row.
    private var erasePetal: some View {
        Image(systemName: "eraser.fill")
            .font(.system(size: (state.pencil ? 26 : 34) * scale, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: petalSize, height: petalSize)
            .couchGlassInteractive(in: Circle())
            .offset(y: spacing + eraseDrop)
    }
}

// MARK: - Pointer / touch rose

#if os(iOS) || os(macOS)
/// The flick rose with pointer input: tap (or click) a petal to place its
/// digit, or drag from anywhere in the rose toward a petal — the same 3×3
/// keypad mapping the Siri Remote uses (RoseGeometry), so the muscle memory
/// transfers between couch, pocket and desk. Shared by the iOS touch screen
/// and the macOS pointer screen (PRD-4 §2.3); on the Mac a click is a tap and
/// a trackpad drag is a flick, both routed through `RoseGeometry.flickDirection`.
struct TouchRose: View {
    let state: RoseState
    let accent: Color
    let completedDigits: Set<Int>
    let scale: CGFloat
    let onDigit: @MainActor (Int) -> Void
    var remainingCounts: [Int]? = nil
    var showsErase: Bool = false
    var onErase: (@MainActor () -> Void)? = nil

    private var petalSize: CGFloat { (state.pencil ? 88 : 116) * scale }
    private var spacing: CGFloat { (state.pencil ? 96 : 126) * scale }
    /// Minimum downward travel that means "flick past the 7-8-9 row, through
    /// the erase petal." Anything shorter falls through to the digit keypad,
    /// so a normal down-flick still places 8.
    private var eraseFlickThreshold: CGFloat { spacing * 0.92 + petalSize / 2 }

    var body: some View {
        FlickRoseView(
            state: state,
            accent: accent,
            completedDigits: completedDigits,
            showsFocusRing: false,
            scale: scale,
            remainingCounts: remainingCounts,
            showsErase: showsErase
        )
        .overlay {
            // Invisible pointer targets aligned with the drawn petals.
            ZStack {
                ForEach(1...9, id: \.self) { digit in
                    let offset = RoseGeometry.offset(forDigit: digit)
                    Color.clear
                        .contentShape(Circle())
                        .frame(width: max(44, petalSize), height: max(44, petalSize))
                        .onTapGesture { onDigit(digit) }
                        .offset(x: offset.x * spacing, y: offset.y * spacing)
                }
                if showsErase, let onErase {
                    Color.clear
                        .contentShape(Circle())
                        .frame(width: max(44, petalSize), height: max(44, petalSize))
                        .onTapGesture { onErase() }
                        .offset(y: spacing + spacing * 0.92)
                }
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    // Erase: a long, predominantly-downward flick that reaches
                    // the erase petal below the ring (iOS filled cells only).
                    if let onErase, showsErase,
                       value.translation.height >= eraseFlickThreshold,
                       value.translation.height >= abs(value.translation.width) {
                        onErase()
                        return
                    }
                    if let direction = RoseGeometry.flickDirection(value.translation) {
                        onDigit(RoseGeometry.digit(for: direction))
                    }
                }
        )
    }
}
#endif

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
