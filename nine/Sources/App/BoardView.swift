// BoardView.swift — the 81-cell grid, drawn in a single Canvas on one glass
// plane (PRD §4.2). Box borders are luminance steps, never hard lines.
// Givens in rounded semibold, entries in the accent tint, errors get a coral
// underline paired with a dot marker (colorblind-safe). Completion rolls a
// luminance wave across the grid.
import SwiftUI
import CouchKit

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

    /// The cell index under a board-local point, or nil when outside.
    static func cellIndex(at point: CGPoint, side: CGFloat) -> Int? {
        let unit = side / 9
        let col = Int(floor(point.x / unit)), row = Int(floor(point.y / unit))
        guard (0..<9).contains(col), (0..<9).contains(row) else { return nil }
        return row * 9 + col
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

    private static let coral = Color(red: 1.0, green: 0.45, blue: 0.38)
    /// Warm near-black for givens on light glass (paper's inverse).
    private static let inkText = Color(red: 0.17, green: 0.16, blue: 0.14)

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The celebration has reached its resting state — nothing animates
    /// anymore, so the 60fps timeline can stop (tvOS and Reduce Motion; the
    /// iOS trophy keeps polling the gyro until the screen goes away).
    @State private var afterglowSettled = false

    /// Light mode flips the board's neutral tones; the accent stays put.
    private var isLight: Bool { colorScheme == .light }
    private var gridTone: Color { isLight ? .black : .white }
    private var digitTone: Color { isLight ? Self.inkText : CouchPalette.paper }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: solvedAt == nil || afterglowSettled)) { timeline in
            let phase = afterglowPhase(now: timeline.date)
            // Both layer effects apply to the Canvas only — inside couchGlass
            // — so digits and grid refract while the glass material and the
            // void behind it stay optically still.
            Canvas { context, size in
                draw(in: &context, size: size, now: timeline.date)
            }
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
        }
        .frame(width: side, height: side)
        .padding(inset)
        .couchGlass(in: RoundedRectangle(cornerRadius: max(18, 36 * side / BoardMetrics.side), style: .continuous))
        .opacity(roseOpen ? 0.82 : 1.0)
        .animation(.couchFast, value: roseOpen)
        .task(id: solvedAt) { await settleWhenDone() }
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
                    with: .color(gridTone.opacity(bright ? (isLight ? 0.07 : 0.055) : (isLight ? 0.028 : 0.02)))
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
        context.stroke(lines, with: .color(gridTone.opacity(isLight ? 0.07 : 0.05)), lineWidth: 1)

        // 2.5 Same-number highlight: an accent wash on every cell holding the
        //     digit. Pencil notes of the digit get their marker below (step 4).
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
                if isError { color = Self.coral }

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
                        width: cell * 0.48, height: max(2, 4 * scale)
                    )
                    context.fill(Path(roundedRect: underline, cornerRadius: 2 * scale), with: .color(Self.coral))
                    // …paired with a dot marker so color is never the sole signal.
                    let dot = CGRect(
                        x: center.x + cell * 0.30, y: center.y - cell * 0.38,
                        width: max(5, 10 * scale), height: max(5, 10 * scale)
                    )
                    context.fill(Path(ellipseIn: dot), with: .color(Self.coral))
                }
            } else {
                // Corner notes: a mini 3×3 keypad of pencil digits. A note of
                // the highlighted digit gets its own accent halo — penciled
                // 9s answer "where could the 9s go" at a glance.
                for mark in game.pencilDigits(at: index) {
                    let mc = CGFloat((mark - 1) % 3), mr = CGFloat((mark - 1) / 3)
                    let point = CGPoint(
                        x: center.x + (mc - 1) * cell * 0.28,
                        y: center.y + (mr - 1) * cell * 0.28
                    )
                    let highlighted = solvedAt == nil && mark == highlightDigit
                    if highlighted {
                        let halo = cell * 0.26
                        let rect = CGRect(
                            x: point.x - halo / 2, y: point.y - halo / 2,
                            width: halo, height: halo
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(accent.opacity(isLight ? 0.34 : 0.30)))
                    }
                    context.draw(
                        Text("\(mark)")
                            .font(.system(size: 22 * scale, weight: highlighted ? .bold : .medium, design: .rounded))
                            .foregroundStyle(highlighted ? accent : gridTone.opacity(0.55)),
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
