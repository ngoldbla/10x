// Darkroom — the board plane and its two clue rails.
//
// One Canvas draws every cell and the cursor (never 400 focusable views —
// PRD §7). Filled cells are luminous "silver halide" squares in the hidden
// photo's actual colors, so the image develops as you solve.
import SwiftUI
import CouchKit

struct BoardCanvas: View {
    let session: PuzzleSession
    let cursorX: Int
    let cursorY: Int
    let showCursor: Bool
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let n = session.size
            let cell = size.width / CGFloat(n)

            // Cells.
            for y in 0..<n {
                for x in 0..<n {
                    let rect = CGRect(
                        x: CGFloat(x) * cell,
                        y: CGFloat(y) * cell,
                        width: cell,
                        height: cell
                    ).insetBy(dx: cell * 0.07, dy: cell * 0.07)
                    let path = Path(roundedRect: rect, cornerRadius: cell * 0.16)

                    switch session.mark(x: x, y: y) {
                    case .filled:
                        context.fill(path, with: .color(halide(session.puzzle.color(x: x, y: y))))
                    case .xMark:
                        context.fill(path, with: .color(.white.opacity(0.03)))
                        var cross = Path()
                        let r = rect.insetBy(dx: cell * 0.26, dy: cell * 0.26)
                        cross.move(to: CGPoint(x: r.minX, y: r.minY))
                        cross.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                        cross.move(to: CGPoint(x: r.maxX, y: r.minY))
                        cross.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                        context.stroke(
                            cross,
                            with: .color(.white.opacity(0.35)),
                            style: StrokeStyle(lineWidth: max(2, cell * 0.06), lineCap: .round)
                        )
                    case .none:
                        context.fill(path, with: .color(.white.opacity(0.05)))
                    }
                }
            }

            // Every-fifth guide lines for countability.
            var guides = Path()
            for i in stride(from: 5, to: n, by: 5) {
                let offset = CGFloat(i) * cell
                guides.move(to: CGPoint(x: offset, y: 0))
                guides.addLine(to: CGPoint(x: offset, y: size.height))
                guides.move(to: CGPoint(x: 0, y: offset))
                guides.addLine(to: CGPoint(x: size.width, y: offset))
            }
            context.stroke(guides, with: .color(.white.opacity(0.14)), lineWidth: 1)

            // The cursor, drawn in-canvas (instant, no focus engine).
            if showCursor {
                let rect = CGRect(
                    x: CGFloat(cursorX) * cell,
                    y: CGFloat(cursorY) * cell,
                    width: cell,
                    height: cell
                ).insetBy(dx: cell * 0.02, dy: cell * 0.02)
                let ring = Path(roundedRect: rect, cornerRadius: cell * 0.18)
                context.stroke(ring, with: .color(.white.opacity(0.25)), lineWidth: max(5, cell * 0.16))
                context.stroke(ring, with: .color(accent), lineWidth: max(2.5, cell * 0.07))
            }
        }
    }

    /// Lift dark photo cells so fills always read as luminous halide.
    private func halide(_ rgb: RGB) -> Color {
        let lift = rgb.luminance < 0.16 ? 0.22 : 0.08
        return Color(rgb.mixed(with: .white, t: lift))
    }
}

// MARK: - Clue rails

/// Shared appearance math for one line's clue stack.
private struct ClueStyle {
    let dimmed: Bool
    let violated: Bool
    let coached: Bool

    func color(violation: Color) -> Color? {
        violated ? violation : nil
    }
}

/// Top rail: column clues, bottom-aligned above each column.
struct ColumnClueRail: View {
    let session: PuzzleSession
    let cellSize: CGFloat
    let font: CGFloat
    let railHeight: CGFloat
    let violatedLine: Violation.Line?
    let violationColor: Color
    let coachTarget: CoachHint.Target?
    let shakePulse: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(0..<session.size, id: \.self) { x in
                let clues = session.puzzle.colClues[x]
                let style = ClueStyle(
                    dimmed: session.isColumnComplete(x),
                    violated: violatedLine == .column(x),
                    coached: coachTarget == .column(x)
                )
                VStack(spacing: 2) {
                    if clues.isEmpty {
                        clueText("0", style: style)
                    } else {
                        ForEach(Array(clues.enumerated()), id: \.offset) { _, run in
                            clueText("\(run)", style: style)
                        }
                    }
                }
                .frame(width: cellSize)
                .modifier(ShakeEffect(animatableData: style.violated ? CGFloat(shakePulse) : 0))
            }
        }
        .padding(.bottom, 8)
        .frame(height: railHeight, alignment: .bottom)
        .couchGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func clueText(_ text: String, style: ClueStyle) -> some View {
        Text(text)
            .font(.system(size: font, weight: .semibold, design: .rounded))
            .foregroundStyle(style.color(violation: violationColor) ?? (style.coached ? .white : .primary))
            .opacity(style.dimmed && !style.violated ? 0.2 : 1)
            .shadow(color: shadowColor(style), radius: 10)
            .animation(.couchFast, value: style.dimmed)
    }

    private func shadowColor(_ style: ClueStyle) -> Color {
        if style.violated { return violationColor.opacity(0.8) }
        if style.coached { return .white.opacity(0.7) }
        return .clear
    }
}

/// Left rail: row clues, right-aligned beside each row.
struct RowClueRail: View {
    let session: PuzzleSession
    let cellSize: CGFloat
    let font: CGFloat
    let railWidth: CGFloat
    let violatedLine: Violation.Line?
    let violationColor: Color
    let coachTarget: CoachHint.Target?
    let shakePulse: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<session.size, id: \.self) { y in
                let clues = session.puzzle.rowClues[y]
                let style = ClueStyle(
                    dimmed: session.isRowComplete(y),
                    violated: violatedLine == .row(y),
                    coached: coachTarget == .row(y)
                )
                HStack(spacing: font * 0.35) {
                    if clues.isEmpty {
                        clueText("0", style: style)
                    } else {
                        ForEach(Array(clues.enumerated()), id: \.offset) { _, run in
                            clueText("\(run)", style: style)
                        }
                    }
                }
                .frame(height: cellSize)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .modifier(ShakeEffect(animatableData: style.violated ? CGFloat(shakePulse) : 0))
            }
        }
        .padding(.trailing, 14)
        .frame(width: railWidth)
        .couchGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func clueText(_ text: String, style: ClueStyle) -> some View {
        Text(text)
            .font(.system(size: font, weight: .semibold, design: .rounded))
            .foregroundStyle(style.color(violation: violationColor) ?? (style.coached ? .white : .primary))
            .opacity(style.dimmed && !style.violated ? 0.2 : 1)
            .shadow(color: shadowColor(style), radius: 10)
            .animation(.couchFast, value: style.dimmed)
    }

    private func shadowColor(_ style: ClueStyle) -> Color {
        if style.violated { return violationColor.opacity(0.8) }
        if style.coached { return .white.opacity(0.7) }
        return .clear
    }
}

/// The soft refusal shake (PRD §4.2: soft shake + brief glow, never harsh).
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 6
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(animatableData * .pi * 3),
            y: 0
        ))
    }
}
