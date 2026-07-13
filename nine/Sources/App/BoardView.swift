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
    /// Side length of the drawing plane. The TV board is fixed at 900pt; the
    /// touch board passes whatever the screen affords, and every drawing
    /// constant below scales off `side / 900`.
    var side: CGFloat = BoardMetrics.side
    /// Padding between the grid and the glass edge.
    var inset: CGFloat = 28

    private static let coral = Color(red: 1.0, green: 0.45, blue: 0.38)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: solvedAt == nil)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, now: timeline.date)
            }
        }
        .frame(width: side, height: side)
        .padding(inset)
        .couchGlass(in: RoundedRectangle(cornerRadius: max(18, 36 * side / BoardMetrics.side), style: .continuous))
        .opacity(roseOpen ? 0.82 : 1.0)
        .animation(.couchFast, value: roseOpen)
    }

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
                    with: .color(.white.opacity(bright ? 0.055 : 0.02))
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
        context.stroke(lines, with: .color(.white.opacity(0.05)), lineWidth: 1)

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
                var color = isGiven ? CouchPalette.paper : accent
                let isError = showErrors && game.isError(at: index)
                if isError { color = Self.coral }

                // Completion wave: a diagonal luminance crest.
                if let wave {
                    let phase = Double(row + col) / 16.0
                    let boost = max(0, 1 - abs(wave - phase) * 4.5)
                    if boost > 0 {
                        color = .white.opacity(0.6 + 0.4 * boost)
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
                // Corner notes: a mini 3×3 keypad of pencil digits.
                for mark in game.pencilDigits(at: index) {
                    let mc = CGFloat((mark - 1) % 3), mr = CGFloat((mark - 1) / 3)
                    let point = CGPoint(
                        x: center.x + (mc - 1) * cell * 0.28,
                        y: center.y + (mr - 1) * cell * 0.28
                    )
                    context.draw(
                        Text("\(mark)")
                            .font(.system(size: 22 * scale, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55)),
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
