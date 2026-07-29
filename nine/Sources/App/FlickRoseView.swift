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
    /// The digit already sitting in this cell, placement mode only — nil for
    /// an empty cell, and always nil for a given (the rose never opens on
    /// one). That digit's own petal renders the dashed erase rim instead of
    /// the tenth petal the rose used to grow: "this digit is here", never
    /// "this is wrong" (a wrongness signal would leak the solution).
    var currentDigit: Int? = nil
    /// The digits already pencilled into this cell, pencil mode only. Same
    /// rim, one petal per noted digit — `togglePencil`'s own XOR already
    /// erases a note on a second tap; this only makes that visible.
    var notedDigits: Set<Int> = []

    @State private var bloomed = false

    private var petalSize: CGFloat { (state.pencil ? 88 : 116) * scale }
    private var spacing: CGFloat { (state.pencil ? 96 : 126) * scale }

    var body: some View {
        CouchGlassContainer(spacing: 12) {
            ZStack {
                ForEach(1...9, id: \.self) { digit in
                    petal(for: digit)
                }
            }
        }
        .frame(width: spacing * 2 + petalSize,
               height: spacing * 2 + petalSize)
        // The ring is spatial, not textual, and must not follow the writing
        // direction (PRD-20 decision 3). `.offset(x:)` *is* direction-aware, so
        // under `-NSForceRightToLeftWritingDirection` the petals laid out
        // 3 2 1 / 6 5 4 / 9 8 7 — measured, on screen, not inferred. An Arabic
        // player reaching for the 3 would have found the 1.
        //
        // The flick path is the second half of the argument: `flickDirection`
        // reads `DragGesture`'s raw translation, which is *not* mirrored. Pin
        // the petals and the two agree again; leave them mirrored and a
        // rightward flick places the digit drawn on the left.
        .environment(\.layoutDirection, .leftToRight)
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
        // "This digit is here" — the placed digit in placement mode, or a
        // noted digit in pencil mode. Never "this is wrong": that would leak
        // the solution, which is exactly what the removed tenth petal did
        // not do either.
        let erasable = state.pencil ? notedDigits.contains(digit) : currentDigit == digit

        return Text("\(digit)")
            .font(.system(size: (state.pencil ? 38 : 52) * scale, weight: .semibold, design: .rounded))
            .foregroundStyle(complete ? Color.primary.opacity(0.30) : erasable ? accent : Color.primary)
            .frame(width: petalSize, height: petalSize)
            .couchGlassInteractive(in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(accent.opacity(focused ? 0.95 : 0), lineWidth: max(2, 4 * scale))
            }
            .modifier(EraseIndicator(active: erasable, accent: accent, scale: scale, petalSize: petalSize))
            .scaleEffect(focused ? 1.1 : 1.0)
            .modifier(ShimmerPulse(active: shimmering, accent: accent))
            .offset(x: offset.x * spacing, y: offset.y * spacing)
            .animation(.couchFast, value: focused)
    }
}

/// The erase indicator: a dashed ring inside the petal's own disc, composed as
/// an `.overlay` the same way the focus ring and `ShimmerPulse` are, so it
/// never fights either. It says "this digit is here" — not "this is wrong" —
/// which is why it never reads as a warning color: a wrongness signal would
/// leak the solution, and this petal is the correct one exactly as often as
/// any other.
///
/// Dash pattern and line weight are named constants rather than folded into
/// the `StrokeStyle` call — easy to retune, without being parameters nobody
/// else needs yet.
private struct EraseIndicator: ViewModifier {
    static let dash: [CGFloat] = [3, 5]
    static let lineWidth: CGFloat = 2.5
    /// Floored for the same reason the focus ring is `max(2, 4 * scale)`: the
    /// touch rose runs near 0.4, where the unfloored weight computes to about
    /// a point and the ring reads as a hairline rather than as a mark.
    static let minimumLineWidth: CGFloat = 1.5
    /// Pulled in off the petal's edge. What is *measured* is the symptom: in
    /// `A-pencil-paper.png` from the Task 6 grid, captured against this same
    /// opaque-glass surface, the ring is simply absent on all three pencilled
    /// petals while the erasable digit still reads accent-coloured — so colour
    /// is left as the only cue, which Differentiate Without Colour does not
    /// accept. The presumed cause is that `couchGlassInteractive` is
    /// `.glassEffect` on iOS 26 and Liquid Glass draws its own specular
    /// highlight at the rim of the shape, where this ring used to sit.
    ///
    /// That cause is inferred, not proven, and **this inset has not been seen
    /// on a device or simulator** — the lane that would have photographed it
    /// would not drive (see DEVIATIONS). Treat the 8% as a first guess to be
    /// confirmed or retuned against a real rose, not as a measured number.
    ///
    /// Expressed against `petalSize` rather than `scale` because the petal is
    /// 88pt in pencil mode and 116pt in placement (`FlickRoseView.petalSize`),
    /// and an inset that reads on one is a different number on the other.
    static let insetFraction: CGFloat = 0.08

    let active: Bool
    let accent: Color
    let scale: CGFloat
    let petalSize: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            Circle()
                .inset(by: petalSize * Self.insetFraction)
                .strokeBorder(
                    accent.opacity(active ? 0.9 : 0),
                    style: StrokeStyle(
                        lineWidth: max(Self.minimumLineWidth, Self.lineWidth * scale),
                        dash: Self.dash.map { $0 * scale })
                )
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
    /// See `FlickRoseView.currentDigit`.
    var currentDigit: Int? = nil
    /// See `FlickRoseView.notedDigits`.
    var notedDigits: Set<Int> = []
    /// Whether the ring traps assistive focus. True everywhere in the game —
    /// the rose is a keypad over a board and nothing else on screen applies.
    /// The first-run beat passes false: its rose sits inside a card that also
    /// carries the lesson and the **Skip** button, and a modal ring would put
    /// the only way out of the first run beyond VoiceOver, Switch Control and
    /// Full Keyboard Access (measured: `describe-ui` listed nine petals and
    /// nothing else at all).
    var isModal: Bool = true

    private var petalSize: CGFloat { (state.pencil ? 88 : 116) * scale }
    private var spacing: CGFloat { (state.pencil ? 96 : 126) * scale }

    var body: some View {
        FlickRoseView(
            state: state,
            accent: accent,
            completedDigits: completedDigits,
            showsFocusRing: false,
            scale: scale,
            currentDigit: currentDigit,
            notedDigits: notedDigits
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
                    // Same test `petal(for:)` uses to draw the dashed rim:
                    // one door, one grammar, so the label the VoiceOver user
                    // hears has to agree with the ring the sighted one sees.
                    let erasable = state.pencil ? notedDigits.contains(digit) : currentDigit == digit
                    Color.clear
                        .contentShape(Circle())
                        .frame(width: max(44, petalSize), height: max(44, petalSize))
                        .onTapGesture { onDigit(digit) }
                        .offset(x: offset.x * spacing, y: offset.y * spacing)
                        .accessibilityElement()
                        // Place/Note are the same two keys the actions rotor
                        // uses (`BoardActionPhrase`): the petals and the rotor
                        // are two doors onto one grammar, so they say one
                        // thing. `eraseDigit` is the petals' alone — the rotor
                        // reaches erase through its own `board.action.erase`
                        // button on the cell, which needs no digit in it.
                        .accessibilityLabel(erasable ? BoardActionPhrase.eraseDigit(digit)
                                            : state.pencil ? BoardActionPhrase.note(digit)
                                                           : BoardActionPhrase.place(digit))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onDigit(digit) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(state.pencil ? Strings.string("board.rose.note")
                                             : Strings.string("board.rose.digit"))
            .accessibilityAddTraits(isModal ? [.isModal] : [])
            // Pinned for the same reason the drawn ring is, and separately:
            // these targets are `.offset` from the same `RoseGeometry`, and if
            // only one of the two were pinned the tap targets would come apart
            // from the petals under them — which is worse than both mirroring,
            // because it looks correct.
            .environment(\.layoutDirection, .leftToRight)
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
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
