// BoardView.swift — the 81-cell grid, drawn in a single Canvas on one glass
// plane (PRD §4.2). Box borders are luminance steps, never hard lines.
// Givens in rounded semibold, entries in the accent tint, errors get a coral
// underline paired with a dot marker (colorblind-safe). Completion rolls a
// luminance wave across the grid.
import SwiftUI
import CouchKit

// `CoachFocus` lives here rather than in `CoachCard.swift` because it is
// board-render input, and PRD-6 puts this file on the watch target's source
// list while the card — an iOS panel — stays off it.
/// The cells a hint lights, by the part each plays in it.
///
/// Arrays rather than a `[Int: Role]` dictionary: where two roles land on one
/// cell the draw order decides what the player sees, and dictionary iteration
/// order is not defined.
struct CoachFocus: Equatable, Sendable {
    /// The cells forming the pattern — an accent wash.
    let pattern: [Int]
    /// The cell the step resolves, if any — a stronger ring.
    let target: Int?
    /// Cells losing a candidate — a dashed, dimmer border.
    let victims: [Int]
    /// The digit under discussion, when the step is about exactly one.
    let digit: Int?
    /// The single cell a deduction turns on — an XY-wing's pivot. Drawn as a
    /// thin inner ring, so a pattern cell that is *also* the pivot reads as
    /// both rather than as neither. Trace schema v2's `.pivot` role, and the
    /// fourth of the four this file's header predicted would arrive.
    let pivot: Int?
    /// The cell the player asked about, held for the whole chain so a
    /// three-beat narration never loses its subject. Nil for a plain hint,
    /// which has no subject to hold.
    let asked: Int?

    init(pattern: [Int], target: Int?, victims: [Int], digit: Int?,
         pivot: Int? = nil, asked: Int? = nil) {
        self.pattern = pattern
        self.target = target
        self.victims = victims
        self.digit = digit
        self.pivot = pivot
        self.asked = asked
    }

    /// Nil for a solved board: the Afterglow owns that moment and nothing
    /// should wash over it.
    init?(_ advice: CoachAdvice) {
        switch advice {
        case .solved:
            return nil
        case .exhausted:
            self.init(pattern: [], target: nil, victims: [], digit: nil)
        case .contradiction(let cells):
            self.init(pattern: cells, target: nil, victims: [], digit: nil)
        case .step(let coach):
            self.init(coach.step, asked: nil)
        }
    }

    /// One beat of a why-chain (PRD-25). Same wash, same dashes, same ring —
    /// the narration is this file's existing vocabulary driven from an array
    /// instead of a single value, which is what `CoachCard`'s header said it
    /// would be.
    init(_ beat: DerivedStep, asked: Int) {
        self.init(beat.coach.step, asked: asked)
    }

    private init(_ step: SolveStep, asked: Int?) {
        pattern = step.cells
        target = step.placement?.cell
        victims = Set(step.eliminations.map(\.cell)).sorted()
        digit = step.digits.count == 1 ? step.digits.first : nil
        // Read off `roles` rather than off the technique, so a technique that
        // grows a pivot later gets the ring without touching this file.
        pivot = step.roles?.firstIndex(of: .pivot).map { step.cells[$0] }
        self.asked = asked
    }
}

/// Shared geometry so the game screens can position the flick rose over a
/// cell. The TV board is a fixed 900pt plane; the touch board passes its own
/// side length, so every drawing constant scales off `side / 900`.
enum BoardMetrics {
    static let side: CGFloat = 900
    static let cell: CGFloat = side / 9

    /// Center of a cell in board-local coordinates (tvOS fixed board).
    static func center(of cell: Int) -> CGPoint {
        center(of: cell, side: side)
    }

    /// Center of a cell in a board of arbitrary side length.
    static func center(of cell: Int, side: CGFloat) -> CGPoint {
        let unit = side / 9
        let row = CGFloat(cell / 9)
        let col = CGFloat(cell % 9)
        return CGPoint(x: (col + 0.5) * unit, y: (row + 0.5) * unit)
    }

    /// The full square a cell occupies, in board-local coordinates. Drawing
    /// sites rebuild this inline off `size.width`; the accessibility layer
    /// needs it in view coordinates, so it lives here once and both agree.
    static func rect(of cell: Int, side: CGFloat) -> CGRect {
        let unit = side / 9
        return CGRect(
            x: CGFloat(cell % 9) * unit,
            y: CGFloat(cell / 9) * unit,
            width: unit,
            height: unit
        )
    }

    /// The 3×3 block a box occupies, in board-local coordinates. Only the
    /// accessibility layer needs it — the Canvas draws box borders as
    /// luminance steps rather than framed regions — but Switch Control's group
    /// scan highlights a real rectangle, so the nine groups need real frames
    /// (PRD-19). Boxes are numbered in reading order, matching `Sudoku.box`.
    static func boxRect(of box: Int, side: CGFloat) -> CGRect {
        let unit = side / 9
        return CGRect(
            x: CGFloat(box % 3) * 3 * unit,
            y: CGFloat(box / 3) * 3 * unit,
            width: 3 * unit,
            height: 3 * unit
        )
    }

    /// The nine cells of a box, in reading order — the order Switch Control
    /// steps them once the group is entered.
    static func cells(inBox box: Int) -> [Int] {
        let firstRow = (box / 3) * 3, firstCol = (box % 3) * 3
        return (0..<3).flatMap { dr in
            (0..<3).map { dc in (firstRow + dr) * 9 + firstCol + dc }
        }
    }

    /// The cell index under a board-local point, or nil when outside.
    static func cellIndex(at point: CGPoint, side: CGFloat) -> Int? {
        let unit = side / 9
        let col = Int(floor(point.x / unit)), row = Int(floor(point.y / unit))
        guard (0..<9).contains(col), (0..<9).contains(row) else { return nil }
        return row * 9 + col
    }

    /// Move a cursor one step. `wrap` toggles edge-wrapping (the Mac keyboard
    /// grammar, PRD-4 §2.2) versus clamping (the TV/touch cursor).
    static func moveCursor(_ cell: Int, _ direction: Direction4, wrap: Bool) -> Int {
        var row = cell / 9, col = cell % 9
        switch direction {
        case .up: row = wrap ? (row + 8) % 9 : max(0, row - 1)
        case .down: row = wrap ? (row + 1) % 9 : min(8, row + 1)
        case .left: col = wrap ? (col + 8) % 9 : max(0, col - 1)
        case .right: col = wrap ? (col + 1) % 9 : min(8, col + 1)
        }
        return row * 9 + col
    }

    /// The next (or previous) empty cell, searched cyclically — Tab / ⇧Tab on
    /// the Mac. Givens are filled, so they're skipped for free. Falls back to
    /// the starting cell when the board has no empties left.
    static func nextEmptyCell(from cell: Int, in game: NineGame, forward: Bool) -> Int {
        let step = forward ? 1 : -1
        for i in 1...81 {
            let idx = ((cell + step * i) % 81 + 81) % 81
            if game.entry(at: idx) == 0 { return idx }
        }
        return cell
    }
}

struct BoardView: View {
    let game: NineGame
    let cursor: Int
    let accent: Color
    let showErrors: Bool
    let solvedAt: Date?
    /// Dim the board content a touch while the rose is open, so the petals
    /// (true glass, lensing the board) are the brightest thing on screen.
    let roseOpen: Bool
    /// The open rose's geometry, or nil (PRD-22). Non-nil arms the third layer
    /// effect: the board's own digits bend and magnify under each petal, and
    /// `FlickRoseView` draws only a glyph and a rim above instead of an opaque
    /// disc. Every call site leaves it nil under Reduce Motion, which restores
    /// today's material exactly — the fallback is the current design, not a
    /// degraded one.
    var roseLens: RoseLens? = nil
    /// While the four-way rose walks petals, the focused digit ghosts into
    /// the selected cell — see the digit before you commit. Nil on eight-way
    /// remotes (flicks place instantly, nothing to preview).
    let previewDigit: Int?
    /// Preview at pencil scale, in the note's own keypad slot (rose opened
    /// in pencil mode).
    let previewPencil: Bool
    /// Same-number highlight: every cell holding this digit — and every
    /// pencil note of it — gets an accent wash, so tapping a 9 shows all
    /// nine 9s (and where you've penciled them).
    var highlightDigit: Int? = nil
    /// The cells a coach hint is lighting (PRD-11), or nil. Default-off, so
    /// tvOS and macOS — which have no coach this PRD — render byte-identically.
    /// One value rather than four parameters because PRD-25 narrates a
    /// *sequence* of these; see CoachCard.swift.
    var coachFocus: CoachFocus? = nil
    /// Pad peek (L2 hold, PRD-5 §2.1): while held, every digit and note that is
    /// not this kind dims to a whisper so the highlighted kind pops. Nil = off,
    /// so every non-pad caller renders byte-identically.
    var dimmedExcept: Int? = nil
    /// The cell under the pointer (macOS, PRD-4 §2.3) — the first hover
    /// affordance in the suite. Drawn as a faint accent halo, dimmer than the
    /// cursor ring, and suppressed when it coincides with the cursor. Nil on
    /// every other platform (no pointer).
    var hoverCell: Int? = nil
    /// Origin cell of the Afterglow shockwave — the winning placement.
    /// Nil (or Reduce Motion) keeps the classic diagonal luminance wave.
    var waveOrigin: Int? = nil
    /// Polled once per frame while the solved board is a glass trophy;
    /// returns device tilt (gravity delta from a baseline pose) steering the
    /// specular sheen. Nil on tvOS: the sheen settles and the loop pauses.
    var afterglowTilt: (@MainActor (Date) -> SIMD2<Double>)? = nil
    /// Side length of the drawing plane. The TV board is fixed at 900pt; the
    /// touch board passes whatever the screen affords, and every drawing
    /// constant below scales off `side / 900`.
    var side: CGFloat = BoardMetrics.side
    /// Padding between the grid and the glass edge.
    var inset: CGFloat = 28
    /// PRD-19: the grammar the 81 virtual accessibility children expose.
    /// Default-constructed it is read-only — the tutorial's boards and the
    /// solved trophy stay readable without offering moves that would be
    /// refused. See BoardAccessibility.swift.
    var axActions = BoardAXActions()

    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Increase Contrast (PRD-22). SwiftUI surfaces the setting as
    /// `colorSchemeContrast`; there is no `accessibilityContrast` key.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// The celebration has reached its resting state — nothing animates
    /// anymore, so the 60fps timeline can stop (tvOS and Reduce Motion; the
    /// iOS trophy keeps polling the gyro until the screen goes away).
    @State private var afterglowSettled = false
    /// The petal lens growing in, 0…1. Driven by the same `.couchFast` spring
    /// `FlickRoseView` blooms its petals with, so the bend arrives under the
    /// glass rather than before or after it.
    @State private var lensBloom: Double = 0

    /// How much bigger a digit reads through a petal.
    ///
    /// This one is taste, not measurement, and it is the only number in PRD-22
    /// that is. The floor is set by the covenant rather than by a ratio: at 1.0
    /// there is no lens and the petals are just transparent, and somewhere past
    /// about 1.6 the board starts *performing* under your thumb, which fails
    /// the idle-pixel test the moment you hold a rose open while thinking.
    /// 1.34 is enough that a digit under a petal is legibly bent and not enough
    /// to notice as an effect. Tune it here; the rim's compression is the other
    /// half and lives in `rosePetalLens`.
    static let lensMagnification: Double = 1.34

    /// The theme decides the board's neutral tones; callers pass an accent
    /// already resolved for the theme's leaning.
    private var tones: ThemeTones { theme.tones(for: colorScheme) }
    private var isLight: Bool { tones.isLight }
    private var gridTone: Color { tones.gridTone }
    private var digitTone: Color { tones.digitTone }
    /// The player asked the system for more contrast, so the board's borders
    /// stop being luminance steps and become lines (PRD-22).
    private var increased: Bool { colorSchemeContrast == .increased }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: solvedAt == nil || afterglowSettled)) { timeline in
            ZStack {
                plane
                refracted(now: timeline.date)
            }
        }
        .frame(width: side, height: side)
        .padding(inset)
        .couchGlass(in: RoundedRectangle(cornerRadius: max(18, 36 * side / BoardMetrics.side), style: .continuous))
        .opacity(roseOpen ? 0.82 : 1.0)
        .animation(.couchFast, value: roseOpen)
        // PRD-19. The Canvas is one opaque drawing to VoiceOver, so the tree
        // is grafted on rather than derived: 81 synthetic children laid out on
        // `BoardMetrics`, never rendered. While the rose is open the board
        // steps out of the tree entirely — the petals are modal, and a focus
        // that can wander back to the cell underneath would let you commit a
        // digit to a board you can no longer see the state of.
        .accessibilityChildren {
            BoardAXGrid(
                game: game,
                cursor: cursor,
                showErrors: showErrors,
                side: side,
                inset: inset,
                actions: axActions
            )
        }
        .accessibilityHidden(roseOpen)
        .task(id: solvedAt) { await settleWhenDone() }
        // The lens grows and shrinks with the petals, not instead of them.
        .onChange(of: roseLens) { _, lens in
            withAnimation(.couchFast) { lensBloom = lens == nil ? 0 : 1 }
        }
        .onAppear { lensBloom = roseLens == nil ? 0 : 1 }
    }

    /// The theme's own ground, put back between the glass and the drawing
    /// (PRD-22). It covers the grid square only — the 12–28pt inset stays pure
    /// material — and it is a sibling of the Canvas rather than the Canvas's
    /// first fill for one specific reason: `afterglowWave` scales its glint by
    /// `color.a` so the celebration rides drawn content and never fogs empty
    /// board. An opaque fill *inside* the Canvas makes alpha 1 everywhere, and
    /// the wave would wash the whole grid instead of lighting the digits.
    private var plane: some View {
        RoundedRectangle(cornerRadius: 18 * side / BoardMetrics.side, style: .continuous)
            .fill(tones.plane)
    }

    /// The board's drawing, and the three shaders that bend it. All three apply
    /// to the Canvas only — inside `couchGlass`, above `plane` — so digits and
    /// grid refract while the glass material, the theme wash and the void
    /// behind them stay optically still.
    ///
    /// **watchOS has no SwiftUI shaders**, so on the wrist this is the Canvas
    /// and nothing else. That costs the watch none of the board and one of the
    /// three celebrations: `waveOrigin` is nil there, which routes step 4 of
    /// `draw` down the Reduce-Motion diagonal luminance wave — already shipped,
    /// already Canvas-drawn, and PRD-6 §2.4 names it the watch's hero moment
    /// for exactly this reason. The rose never opens on a watch (the Crown is
    /// the rose there), so the petal lens has nothing to bend either.
    @ViewBuilder
    private func refracted(now: Date) -> some View {
        let phase = afterglowPhase(now: now)
        let canvas = Canvas { context, size in
            draw(in: &context, size: size, now: now)
        }
        #if os(watchOS)
        canvas
        #else
        canvas
        .layerEffect(
            ShaderLibrary.afterglowWave(
                .float2(originPoint),
                .float(phase.waveProgress ?? 0),
                .float(maxRadius),
                .float(waveAmplitude)
            ),
            maxSampleOffset: CGSize(width: waveAmplitude + 4, height: waveAmplitude + 4),
            isEnabled: phase.waveActive
        )
        .layerEffect(
            ShaderLibrary.afterglowSheen(
                .float2(side, side),
                .float(phase.sheenPos),
                .float2(phase.sheenTilt.x, phase.sheenTilt.y),
                .float(phase.sheenStrength)
            ),
            maxSampleOffset: CGSize(width: 6, height: 6),
            isEnabled: phase.sheenActive
        )
        // PRD-22, third in the chain and last on purpose: during a celebration
        // the board is a trophy and the rose is closed, so the two never
        // overlap in practice — but if they ever did, the Afterglow is the
        // thing the player is being shown.
        .layerEffect(
            ShaderLibrary.rosePetalLens(
                .float2(lensCentre),
                .float(roseLens?.spacing ?? 0),
                .float(roseLens?.petalRadius ?? 0),
                .float(Self.lensMagnification),
                .float(lensBloom)
            ),
            maxSampleOffset: CGSize(width: lensReach, height: lensReach),
            isEnabled: lensActive
        )
        #endif
    }

    // MARK: - The petal lens (PRD-22)

    /// Reduce Motion never reaches the shader — every call site already leaves
    /// `roseLens` nil there, and this is the second lock on the same door.
    private var lensActive: Bool {
        roseLens != nil && !reduceMotion && lensBloom > 0.001
    }

    private var lensCentre: CGPoint {
        guard let roseLens else { return .zero }
        return CGPoint(x: roseLens.centre.x, y: roseLens.centre.y)
    }

    /// How far the shader may sample outside a pixel's own position. The worst
    /// case is a rim pixel: `|delta| * (squeeze - 1)` with `|delta|` at the
    /// radius and `squeeze` at its 1.42 ceiling, so 0.42 radii. This is 1.9,
    /// deliberately loose — under-sizing it clips the compressed band into a
    /// hard edge, visible only where petals sit near the plane's border, which
    /// is exactly where `RoseLens`'s clamp puts them.
    private var lensReach: CGFloat {
        CGFloat((roseLens?.petalRadius ?? 0) * 1.9)
    }

    // MARK: - Afterglow choreography

    /// Everything the shaders need this frame, as a pure function of
    /// time-since-solve. Reduce Motion never reaches the shaders at all —
    /// `waveProgress(now:)` keeps today's diagonal luminance path.
    private func afterglowPhase(now: Date) -> AfterglowPhase {
        guard let solvedAt, !reduceMotion, waveOrigin != nil else { return AfterglowPhase() }
        return AfterglowPhase.at(
            now.timeIntervalSince(solvedAt),
            tilt: afterglowTilt.map { $0(now) }
        )
    }

    /// Flip `afterglowSettled` once the celebration reaches a static frame:
    /// after the wave under Reduce Motion, after the sheen settles on tvOS.
    /// The iOS trophy never settles — tilt keeps steering the light until
    /// the screen goes away. Also fixes the pre-Afterglow behavior where the
    /// solved board's timeline ran at 60fps forever.
    private func settleWhenDone() async {
        afterglowSettled = false
        guard let solvedAt else { return }
        let settleAt: TimeInterval?
        if reduceMotion || waveOrigin == nil {
            settleAt = AfterglowPhase.waveDuration + 0.1
        } else if afterglowTilt == nil {
            settleAt = AfterglowPhase.settleTime
        } else {
            settleAt = nil
        }
        guard let settleAt else { return }
        let remaining = settleAt - Date().timeIntervalSince(solvedAt)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            if Task.isCancelled { return }
        }
        afterglowSettled = true
    }

    private var originPoint: CGPoint {
        BoardMetrics.center(of: waveOrigin ?? 40, side: side)
    }

    /// Distance from the wave origin to the farthest board corner — the
    /// crest reaches it exactly at the end of the wave, wherever you win.
    private var maxRadius: CGFloat {
        let o = originPoint
        return max(hypot(o.x, o.y),
                   max(hypot(side - o.x, o.y),
                       max(hypot(o.x, side - o.y), hypot(side - o.x, side - o.y))))
    }

    /// Peak refraction displacement in points, scaled with the board.
    private var waveAmplitude: CGFloat { 16 * side / BoardMetrics.side }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, now: Date) {
        let cell = size.width / 9
        let scale = size.width / BoardMetrics.side

        // 1. Box luminance steps: alternating boxes get a slightly brighter
        //    wash — the step itself reads as the border.
        //
        //    Under Increase Contrast both washes go to **zero** and step 2.4
        //    draws the border the step was standing in for (PRD-22). The first
        //    version deepened the step instead, on the reasoning that more
        //    contrast between the boxes is more contrast — and the harness
        //    measured every single Increase Contrast cell coming out *below*
        //    its standard counterpart (Void 14.72 → 13.62, Paper's coral
        //    5.06 → 4.43). A wash is a wash toward `gridTone`, which is the
        //    ink's own end of the scale on a dark theme and the ground's on a
        //    light one; either way it moves the ground toward the digits and
        //    every ratio in the box falls. The setting that asks for more
        //    contrast has to *remove* the wash, not thicken it.
        let brightWash = increased ? 0.0 : (isLight ? 0.07 : 0.055)
        let dimWash = increased ? 0.0 : (isLight ? 0.028 : 0.02)
        for boxRow in 0..<3 {
            for boxCol in 0..<3 {
                let bright = (boxRow + boxCol) % 2 == 0
                let rect = CGRect(
                    x: CGFloat(boxCol) * 3 * cell,
                    y: CGFloat(boxRow) * 3 * cell,
                    width: 3 * cell,
                    height: 3 * cell
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 6 * scale),
                    with: .color(gridTone.opacity(bright ? brightWash : dimWash))
                )
            }
        }

        // 2. Hairline cell separators (soft, uniform).
        var lines = Path()
        for i in 1..<9 {
            let offset = CGFloat(i) * cell
            lines.move(to: CGPoint(x: offset, y: 0))
            lines.addLine(to: CGPoint(x: offset, y: size.height))
            lines.move(to: CGPoint(x: 0, y: offset))
            lines.addLine(to: CGPoint(x: size.width, y: offset))
        }
        context.stroke(
            lines,
            with: .color(gridTone.opacity(
                increased ? (isLight ? 0.20 : 0.16) : (isLight ? 0.07 : 0.05))),
            lineWidth: 1)

        // 2.4 Box borders, Increase Contrast only. The rest of the time these
        //     are the luminance step above — a wash you read as an edge, which
        //     is the calmer thing and the wrong thing for someone who has told
        //     the system they need edges to be edges.
        if increased {
            var boxes = Path()
            for i in 0...3 {
                let offset = CGFloat(i) * 3 * cell
                boxes.move(to: CGPoint(x: offset, y: 0))
                boxes.addLine(to: CGPoint(x: offset, y: size.height))
                boxes.move(to: CGPoint(x: 0, y: offset))
                boxes.addLine(to: CGPoint(x: size.width, y: offset))
            }
            context.stroke(boxes, with: .color(tones.hairline),
                           lineWidth: max(1.5, 2 * scale))
        }

        // 2.5 Same-number highlight: an accent wash on every cell holding the
        //     digit; cells whose pencil notes contain it get a quiet accent
        //     border instead — "where could the 9s go" reads at cell scale.
        if let highlightDigit, solvedAt == nil {
            for index in 0..<81 where game.entry(at: index) == highlightDigit {
                let row = index / 9, col = index % 9
                let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    .insetBy(dx: 3 * scale, dy: 3 * scale)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 12 * scale),
                    with: .color(accent.opacity(isLight ? 0.28 : 0.22))
                )
            }
            // Kept apart from the cursor on purpose: deeper inset, smaller
            // radius, thinner and dimmer stroke, no fill — when both land on
            // one cell the cursor ring draws later, brighter and outside.
            for index in 0..<81 where game.entry(at: index) == 0
                    && game.pencilDigits(at: index).contains(highlightDigit) {
                let row = index / 9, col = index % 9
                let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    .insetBy(dx: 6 * scale, dy: 6 * scale)
                let path = Path(roundedRect: rect, cornerRadius: 12 * scale)
                context.stroke(path, with: .color(accent.opacity(0.55)), lineWidth: max(1.5, 2 * scale))
            }
        }

        // 2.6 Coach wash (PRD-11): the pattern in accent, the cell the step
        //     resolves in a stronger ring, the cells losing a candidate in a
        //     dashed dimmer one. Dashed on purpose — an elimination is the
        //     absence of something, and a solid ring would read as "look here"
        //     rather than "this loses a digit". Drawn before the cursor, which
        //     stays the brightest thing on the board.
        if let coachFocus, solvedAt == nil {
            for index in coachFocus.pattern {
                let rect = BoardMetrics.rect(of: index, side: size.width)
                    .insetBy(dx: 3 * scale, dy: 3 * scale)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 12 * scale),
                    with: .color(accent.opacity(isLight ? 0.30 : 0.24))
                )
            }
            for index in coachFocus.victims {
                let rect = BoardMetrics.rect(of: index, side: size.width)
                    .insetBy(dx: 6 * scale, dy: 6 * scale)
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 12 * scale),
                    with: .color(accent.opacity(0.42)),
                    style: StrokeStyle(
                        lineWidth: max(1.5, 2 * scale),
                        dash: [4 * scale, 3 * scale]
                    )
                )
            }
            // The pivot: a thin *inner* ring, so a cell that is both pattern
            // and pivot reads as both. Drawn before the target ring, because a
            // step that has a pivot never also places, and a step that places
            // should keep the loudest mark on the board.
            if let pivot = coachFocus.pivot {
                let rect = BoardMetrics.rect(of: pivot, side: size.width)
                    .insetBy(dx: 8 * scale, dy: 8 * scale)
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 9 * scale),
                    with: .color(accent.opacity(0.85)),
                    lineWidth: max(1.5, 2 * scale)
                )
            }
            if let target = coachFocus.target {
                let rect = BoardMetrics.rect(of: target, side: size.width)
                    .insetBy(dx: 2 * scale, dy: 2 * scale)
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 15 * scale),
                    with: .color(accent),
                    lineWidth: max(2.5, 4 * scale)
                )
            }
            // The cell the player asked about, held for the whole chain
            // (PRD-25). Last, so it is never covered: a narration that loses
            // track of its own subject is a narration about nothing. Distinct
            // from the target ring by being *outside* the cell rather than
            // inside it, so the two read as different claims when a beat's
            // step finally resolves the asked cell and both land at once.
            if let asked = coachFocus.asked, asked != coachFocus.target {
                let rect = BoardMetrics.rect(of: asked, side: size.width)
                    .insetBy(dx: 1 * scale, dy: 1 * scale)
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 16 * scale),
                    with: .color(accent.opacity(0.7)),
                    style: StrokeStyle(lineWidth: max(2, 3 * scale),
                                       dash: [10 * scale, 5 * scale])
                )
            }
        }

        // 2.7 Hover halo (macOS pointer): a faint accent ring tracking the
        //     cell under the pointer. Dimmer and thinner than the cursor, and
        //     hidden when it lands on the cursor cell so the two never fight.
        if let hoverCell, solvedAt == nil, hoverCell != cursor {
            let row = hoverCell / 9, col = hoverCell % 9
            let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                .insetBy(dx: 5 * scale, dy: 5 * scale)
            let path = Path(roundedRect: rect, cornerRadius: 13 * scale)
            context.fill(path, with: .color(accent.opacity(isLight ? 0.10 : 0.08)))
            context.stroke(path, with: .color(accent.opacity(0.4)), lineWidth: max(1.5, 2 * scale))
        }

        // 3. Cursor.
        if solvedAt == nil {
            let row = cursor / 9, col = cursor % 9
            let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                .insetBy(dx: 4 * scale, dy: 4 * scale)
            let path = Path(roundedRect: rect, cornerRadius: 14 * scale)
            context.fill(path, with: .color(accent.opacity(0.16)))
            context.stroke(path, with: .color(accent.opacity(0.9)), lineWidth: max(2, 3 * scale))
        }

        // 4. Digits, pencil marks, error markers.
        let wave = waveProgress(now: now)
        for index in 0..<81 {
            let row = index / 9, col = index % 9
            let center = BoardMetrics.center(of: index, side: size.width)
            let digit = game.entry(at: index)

            if digit != 0 {
                let isGiven = game.isGiven(index)
                var color = isGiven ? digitTone : accent
                let isError = showErrors && game.isError(at: index)
                if isError { color = tones.coral }

                // Completion wave: a luminance crest. With the Afterglow
                // shader running, the phase is radial from the winning cell
                // so the brightening rides the same crest as the refraction;
                // Reduce Motion (and nil origin) keeps the classic diagonal.
                if let wave {
                    let phase: Double
                    if let waveOrigin, !reduceMotion {
                        let origin = BoardMetrics.center(of: waveOrigin, side: size.width)
                        let scaledRadius = maxRadius * size.width / side
                        phase = hypot(center.x - origin.x, center.y - origin.y) / scaledRadius
                    } else {
                        phase = Double(row + col) / 16.0
                    }
                    let boost = max(0, 1 - abs(wave - phase) * 4.5)
                    if boost > 0 {
                        color = gridTone.opacity(0.6 + 0.4 * boost)
                    }
                }

                // L2 peek: everything that isn't the peeked kind recedes.
                if let dimmedExcept, digit != dimmedExcept { color = color.opacity(0.16) }

                context.draw(
                    Text("\(digit)")
                        .font(.system(size: 56 * scale, weight: isGiven ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(color),
                    at: center
                )

                if isError {
                    // Coral underline…
                    let underline = CGRect(
                        x: center.x - cell * 0.24, y: center.y + cell * 0.30,
                        width: cell * 0.48,
                        height: increased ? max(3, 6 * scale) : max(2, 4 * scale)
                    )
                    context.fill(Path(roundedRect: underline, cornerRadius: 2 * scale), with: .color(tones.coral))
                    // …paired with a dot marker so color is never the sole signal.
                    let dot = CGRect(
                        x: center.x + cell * 0.30, y: center.y - cell * 0.38,
                        width: max(5, 10 * scale), height: max(5, 10 * scale)
                    )
                    context.fill(Path(ellipseIn: dot), with: .color(tones.coral))
                }
            } else {
                // Corner notes: a mini 3×3 keypad of pencil digits. A note of
                // the highlighted digit goes bold accent; its cell already
                // carries the border ring from step 2.5.
                for mark in game.pencilDigits(at: index) {
                    let mc = CGFloat((mark - 1) % 3), mr = CGFloat((mark - 1) / 3)
                    let point = CGPoint(
                        x: center.x + (mc - 1) * cell * 0.28,
                        y: center.y + (mr - 1) * cell * 0.28
                    )
                    let highlighted = solvedAt == nil && mark == highlightDigit
                    var noteColor = highlighted ? accent : gridTone.opacity(0.55)
                    if let dimmedExcept, mark != dimmedExcept { noteColor = noteColor.opacity(0.16) }
                    context.draw(
                        Text("\(mark)")
                            .font(.system(size: 22 * scale, weight: highlighted ? .bold : .medium, design: .rounded))
                            .foregroundStyle(noteColor),
                        at: point
                    )
                }
            }
        }

        // 5. Ghost preview: the rose's focused digit rendered in the cursor
        //    cell — accent-tinted and translucent, clearly a maybe, gone the
        //    moment the rose closes or the petal focus moves on.
        if let previewDigit, solvedAt == nil {
            let center = BoardMetrics.center(of: cursor, side: size.width)
            if previewPencil {
                // Pencil previews land where the note itself would: the
                // digit's slot in the mini 3×3 keypad. A touch more opacity
                // than the big ghost so the small glyph stays legible.
                let mc = CGFloat((previewDigit - 1) % 3), mr = CGFloat((previewDigit - 1) / 3)
                let point = CGPoint(
                    x: center.x + (mc - 1) * cell * 0.28,
                    y: center.y + (mr - 1) * cell * 0.28
                )
                context.draw(
                    Text("\(previewDigit)")
                        .font(.system(size: 26 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(accent.opacity(0.45)),
                    at: point
                )
            } else {
                context.draw(
                    Text("\(previewDigit)")
                        .font(.system(size: 62 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(accent.opacity(0.35)),
                    at: center
                )
            }
        }
    }

    /// 0…1 progress of the completion wave, nil when idle / finished.
    private func waveProgress(now: Date) -> Double? {
        guard let solvedAt else { return nil }
        let t = now.timeIntervalSince(solvedAt)
        guard t >= 0, t < 2.6 else { return nil }
        return t / 2.6
    }
}

/// One frame of the Afterglow celebration, as a pure function of
/// time-since-solve (PRD-1 §2):
///
///   0 – 2.6s   refractive shockwave from the winning cell
///   2.6 – 5.4s one slow autonomous specular sweep (teaches the affordance)
///   ≥ 5.4s     glass trophy — gyro steers the sheen (iOS); without tilt
///              the sheen settles to a faint static and the caller pauses
struct AfterglowPhase: Equatable {
    static let waveDuration: TimeInterval = 2.6
    static let sweepEnd: TimeInterval = 5.4
    /// When the no-tilt settle (≈1s fade after the sweep) is fully static.
    static let settleTime: TimeInterval = 6.5

    private static let sweepStrength = 0.35
    private static let trophyStrength = 0.30
    private static let staticStrength = 0.12

    var waveProgress: Double?
    var sheenPos: Double = 0.5
    var sheenTilt: SIMD2<Double> = .zero
    var sheenStrength: Double = 0

    var waveActive: Bool { waveProgress != nil }
    var sheenActive: Bool { sheenStrength > 0.001 }

    static func at(_ t: TimeInterval, tilt: SIMD2<Double>?) -> AfterglowPhase {
        var phase = AfterglowPhase()
        guard t >= 0 else { return phase }

        if t < waveDuration {
            phase.waveProgress = t / waveDuration
            return phase
        }

        if t < sweepEnd {
            let p = (t - waveDuration) / (sweepEnd - waveDuration)
            phase.sheenPos = smoothstep(p)
            phase.sheenStrength = sweepStrength
            if let tilt, p > 0.85 {
                // Hand off to gyro steering over the sweep's last 15% —
                // position, tilt and strength all blend so there's no jump.
                let blend = smoothstep((p - 0.85) / 0.15)
                phase.sheenPos += (trophyPos(tilt) - phase.sheenPos) * blend
                phase.sheenTilt = tilt * blend
                phase.sheenStrength += (trophyStrength - sweepStrength) * blend
            }
            return phase
        }

        if let tilt {
            phase.sheenPos = trophyPos(tilt)
            phase.sheenTilt = tilt
            phase.sheenStrength = trophyStrength
        } else {
            // No motion source: glide the light back to rest and dim it —
            // the last frame before the timeline pauses.
            let f = smoothstep((t - sweepEnd) / (settleTime - sweepEnd - 0.1))
            phase.sheenPos = 1.0 + (0.5 - 1.0) * f
            phase.sheenStrength = sweepStrength + (staticStrength - sweepStrength) * f
        }
        return phase
    }

    /// Tilt is pre-clamped to ±0.35 by AfterglowMotion, so the highlight
    /// stays within the middle of the board — glass catching light, never
    /// a gimmick.
    private static func trophyPos(_ tilt: SIMD2<Double>) -> Double {
        0.5 + tilt.x * 0.6
    }

    private static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
