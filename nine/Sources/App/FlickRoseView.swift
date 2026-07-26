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
    /// Adds a tenth "erase" petal below the ring. Off for givens/empty cells
    /// and every non-iOS surface.
    var showsErase: Bool = false
    /// The board underneath is refracting through these petals (PRD-22), so
    /// they draw as a rim and a glyph rather than as a material. False keeps
    /// today's `.couchGlassInteractive` disc, which is what Reduce Motion and
    /// every surface without a lens get.
    var lensed: Bool = false

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
            .foregroundStyle(complete ? Color.primary.opacity(0.30) : Color.primary)
            .frame(width: petalSize, height: petalSize)
            .modifier(PetalSurface(lensed: lensed, scale: scale))
            .overlay {
                Circle()
                    .strokeBorder(accent.opacity(focused ? 0.95 : 0), lineWidth: max(2, 4 * scale))
            }
            .scaleEffect(focused ? 1.1 : 1.0)
            .modifier(ShimmerPulse(active: shimmering, accent: accent))
            .offset(x: offset.x * spacing, y: offset.y * spacing)
            .animation(.couchFast, value: focused)
    }

    /// The tenth petal: an eraser glyph directly below the 7-8-9 row.
    private var erasePetal: some View {
        Image(systemName: "eraser.fill")
            .font(.system(size: (state.pencil ? 26 : 34) * scale, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: petalSize, height: petalSize)
            .modifier(PetalSurface(lensed: lensed, scale: scale))
            .offset(y: spacing + eraseDrop)
    }
}

/// A petal's own surface.
///
/// Lensed, it is a rim and a breath of body and nothing else: the board's
/// Canvas is already bending and magnifying underneath (`rosePetalLens` in
/// Afterglow.metal), and a material on top of that would be exactly the opaque
/// disc PRD-22 exists to remove — the live audit's finding was "rose petals are
/// opaque `.glassEffect` discs, not the PRD's true glass petals lensing the
/// board beneath."
///
/// Unlensed it is byte-for-byte today's interactive glass, which is what Reduce
/// Motion gets and what every surface that does not pass a lens keeps.
private struct PetalSurface: ViewModifier {
    let lensed: Bool
    let scale: CGFloat

    /// The rim has to be drawn *against* the board, and the board is bright on
    /// Paper and Camel. A white rim there is a rim nobody can see: the contrast
    /// harness would still report the petal's glyph at 18:1 and be right, and
    /// the player would still be looking at nine floating digits with no ring
    /// around them. Glyph legibility and *shape* legibility are two claims, and
    /// only one of them is a contrast ratio.
    @Environment(\.colorScheme) private var colorScheme

    private var edge: Color { colorScheme == .light ? .black : .white }

    func body(content: Content) -> some View {
        if lensed {
            content
                // Just enough body to lift a glyph off a busy board cell
                // without becoming the disc this PRD removes.
                .background(Circle().fill(edge.opacity(0.10)))
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [edge.opacity(0.60), edge.opacity(0.14)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: max(1, 1.6 * scale))
                }
                .clipShape(Circle())
        } else {
            content.couchGlassInteractive(in: Circle())
        }
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
    var showsErase: Bool = false
    var onErase: (@MainActor () -> Void)? = nil
    /// Whether the ring traps assistive focus. True everywhere in the game —
    /// the rose is a keypad over a board and nothing else on screen applies.
    /// The first-run beat passes false: its rose sits inside a card that also
    /// carries the lesson and the **Skip** button, and a modal ring would put
    /// the only way out of the first run beyond VoiceOver, Switch Control and
    /// Full Keyboard Access (measured: `describe-ui` listed nine petals and
    /// nothing else at all).
    var isModal: Bool = true
    /// See `FlickRoseView.lensed`.
    var lensed: Bool = false

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
            showsErase: showsErase,
            lensed: lensed
        )
        .accessibilityHidden(true) // the drawn petals; the targets below speak
        .overlay {
            // Invisible pointer targets aligned with the drawn petals. They
            // are also the rose's accessibility tree (PRD-19): the drawing is
            // hidden above, and these nine carry the labels, so a mixed
            // session — VoiceOver on, a sighted hand flicking — stays sane.
            // The board goes `.accessibilityHidden` while the rose is open,
            // which together with `.isModal` traps focus inside the ring.
            ZStack {
                ForEach(1...9, id: \.self) { digit in
                    let offset = RoseGeometry.offset(forDigit: digit)
                    Color.clear
                        .contentShape(Circle())
                        .frame(width: max(44, petalSize), height: max(44, petalSize))
                        .onTapGesture { onDigit(digit) }
                        .offset(x: offset.x * spacing, y: offset.y * spacing)
                        .accessibilityElement()
                        .accessibilityLabel(state.pencil ? "Note \(digit)" : "Place \(digit)")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onDigit(digit) }
                }
                if showsErase, let onErase {
                    Color.clear
                        .contentShape(Circle())
                        .frame(width: max(44, petalSize), height: max(44, petalSize))
                        .onTapGesture { onErase() }
                        .offset(y: spacing + spacing * 0.92)
                        .accessibilityElement()
                        .accessibilityLabel("Erase")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onErase() }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(state.pencil ? "Note rose" : "Digit rose")
            .accessibilityAddTraits(isModal ? [.isModal] : [])
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
