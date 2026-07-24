// StatsViews.swift — the three hand-rolled stat views the History sheet
// composes (PRD-9): a completion heat grid, average-vs-best twin bars, and a
// solve-time trend sparkline. Ported from the -uxdemo.stats prototype and
// re-themed via ThemeTones so they read right on Void, Paper and the tinted
// themes, scaled by the sheet's `s` factor. No Swift Charts — Canvas/Path only.
#if os(iOS) || os(macOS) || os(tvOS)
import SwiftUI
import CouchKit

/// One day in the heat grid. `count` is solves that day (0…3+ intensity);
/// `hasDaily` lights the cell at full accent — the daily is the one that
/// grows the streak, so it earns the strongest tint.
struct HeatCell: Identifiable {
    let id: Int          // day ordinal
    let count: Int
    let hasDaily: Bool
}

/// Last-12-weeks completion grid: 12 columns (weeks) × 7 rows (a rolling
/// 7-day cadence, today at the bottom-right), GitHub-contribution style.
struct HeatGrid: View {
    let columns: [[HeatCell]]   // 12 columns, each 7 cells, oldest→newest
    let accent: Color
    let emptyTrack: Color
    let s: CGFloat

    var body: some View {
        HStack(spacing: 4 * s) {
            ForEach(columns.indices, id: \.self) { col in
                VStack(spacing: 4 * s) {
                    ForEach(columns[col]) { cell in
                        RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                            .fill(fill(cell))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func fill(_ cell: HeatCell) -> Color {
        if cell.count == 0 { return emptyTrack }
        if cell.hasDaily { return accent }                 // full strength
        let level = min(cell.count, 3)                     // 1, 2, 3+
        return accent.opacity([0, 0.4, 0.65, 0.9][level])
    }
}

/// Average-vs-best capsule pair for one difficulty: a muted avg bar with the
/// full-accent best bar drawn over it (best ≤ avg always, so it nests inside).
struct TwinBar: View {
    let title: String
    let avg: Double        // 0…1 fraction of the track
    let best: Double       // 0…1 fraction of the track
    let bestLabel: String
    let avgLabel: String
    let accent: Color
    let track: Color
    let s: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            HStack {
                Text(title).font(CouchTypography.caption)
                Spacer()
                Text("\(bestLabel) · \(avgLabel)")
                    .font(.system(size: 12 * s, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(track).frame(height: 8 * s)
                    Capsule().fill(accent.opacity(0.35))
                        .frame(width: geo.size.width * clamp(avg), height: 8 * s)
                    Capsule().fill(accent)
                        .frame(width: geo.size.width * clamp(best), height: 8 * s)
                }
            }
            .frame(height: 8 * s)
        }
    }

    private func clamp(_ v: Double) -> CGFloat { CGFloat(min(1, max(0, v))) }
}

/// A tiny filled sparkline for the solve-time trend. `points` run oldest→
/// newest, 0 (fast) at the top … 1 (slow) at the bottom.
struct Sparkline: View {
    let points: [Double]
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let step = points.count > 1 ? w / CGFloat(points.count - 1) : w
            let pt: (Int) -> CGPoint = { i in
                CGPoint(x: CGFloat(i) * step, y: h * CGFloat(points[i]))
            }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    for i in points.indices { p.addLine(to: pt(i)) }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [accent.opacity(0.35), accent.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                Path { p in
                    p.move(to: pt(0))
                    for i in points.indices.dropFirst() { p.addLine(to: pt(i)) }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
#endif
