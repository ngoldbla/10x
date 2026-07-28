// CometView.swift — the comet retracing a solve (PRD-26 §2.1).
//
// Deliberately **not** `BoardView`. The live board carries a Metal pipeline,
// the rose, selection, error state, pencil marks and 81 accessibility children,
// none of which belongs in a picture of a solve that already finished — the same
// argument `ShareCardView` makes, and the reason this shares `SolvedGridThumb`'s
// geometry rather than `BoardMetrics`.
//
// Every decision about *what* to draw already happened in `CometTimeline`,
// which is pure and tests on Linux. What is left here is geometry with no
// branching in it, plus one thing the timeline cannot know: the accent.
import SwiftUI
import CouchKit
#if canImport(NineEngine)
import NineEngine
#endif

/// A board replaying its own solve, looping forever.
///
/// One view at three sizes: the debrief's card, the share card's 888 pt body,
/// and the Apple TV's full screen. Everything scales off `size.width`, so there
/// is no second layout to keep in step.
struct CometView: View {
    let puzzle: [Int]
    let moves: [LoggedMove]
    let tones: ThemeTones
    let accent: Color
    /// The instant the loop began. Passed in rather than read here so the share
    /// card's frame-by-frame export can drive the same view off a synthetic
    /// clock — an exporter that could not choose its own time would have to
    /// reimplement this.
    var start: Date = .now
    /// Freeze on one frame instead of animating. Reduce Motion's answer, and
    /// the export's.
    var frozenPhase: Double?

    var body: some View {
        if let frozenPhase {
            canvas(CometTimeline.frame(at: frozenPhase, puzzle: puzzle, moves: moves))
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
                canvas(CometTimeline.frame(
                    at: timeline.date, since: start, puzzle: puzzle, moves: moves
                ))
            }
        }
    }

    /// 30 fps rather than 120. The comet is a slow object crossing a small
    /// board, ProMotion buys nothing the eye can find, and the craft charter's
    /// idle-pixel rule is about exactly this kind of always-on surface — this
    /// one can run for hours on a television.
    private func canvas(_ frame: CometFrame) -> some View {
        Canvas { context, size in
            let boxGap = size.width * 0.018
            let cell = (size.width - boxGap * 2) / 9
            let digitSize = cell * 0.62

            func centre(_ index: Int) -> CGPoint {
                let column = index % 9, row = index / 9
                return CGPoint(
                    x: CGFloat(column) * cell + CGFloat(column / 3) * boxGap + cell / 2,
                    y: CGFloat(row) * cell + CGFloat(row / 3) * boxGap + cell / 2
                )
            }

            // 1 — the plane. Same wash and the same gap-read 3×3 structure as
            // `SolvedGridThumb`, so the still card and the loop are visibly the
            // same object.
            for index in 0..<81 {
                let column = index % 9, row = index / 9
                let box = CGRect(
                    x: CGFloat(column) * cell + CGFloat(column / 3) * boxGap,
                    y: CGFloat(row) * cell + CGFloat(row / 3) * boxGap,
                    width: cell, height: cell
                )
                context.fill(
                    Path(roundedRect: box.insetBy(dx: cell * 0.035, dy: cell * 0.035),
                         cornerRadius: cell * 0.16),
                    with: .color(tones.gridTone.opacity(tones.isLight ? 0.07 : 0.10))
                )
            }

            // 2 — the trail, **under** the digits. It was a dot on top of them
            // first, and the exported card is what showed the problem: at
            // 888 pt a translucent disc over a numeral reads as a smudge on
            // the digit rather than as a path through the cell. A cell-shaped
            // wash behind the glyph says the comet passed through here and
            // leaves the digit legible, which is the whole picture.
            //
            // Drawn *forward* on an ordinary beat and *reversed* on a
            // retrograde one — the same path run the other way, which is the
            // whole of "erasures loop retrograde": a correction reads as the
            // comet backing out of a cell rather than as a second object.
            let tail = frame.isRetrograde ? Array(frame.tail.reversed()) : frame.tail
            for (rank, index) in tail.enumerated() {
                let fade = 1 - Double(rank + 1) / Double(CometTimeline.tailLength + 1)
                let column = index % 9, row = index / 9
                let box = CGRect(
                    x: CGFloat(column) * cell + CGFloat(column / 3) * boxGap,
                    y: CGFloat(row) * cell + CGFloat(row / 3) * boxGap,
                    width: cell, height: cell
                )
                context.fill(
                    Path(roundedRect: box.insetBy(dx: cell * 0.035, dy: cell * 0.035),
                         cornerRadius: cell * 0.16),
                    with: .color(accent.opacity(fade * 0.30))
                )
            }

            // 3 — the digits standing at this instant. Givens in the theme's
            // digit tone and the player's own in the accent: the same rule the
            // shelf's fingerprints already taught this player to read, so the
            // loop shows how much of the board was theirs while it fills.
            for index in 0..<81 where frame.entries[index] != 0 {
                let isGiven = puzzle.indices.contains(index) && puzzle[index] != 0
                var text = context.resolve(
                    Text("\(frame.entries[index])")
                        .font(.system(size: digitSize,
                                      weight: isGiven ? .medium : .semibold,
                                      design: .rounded))
                )
                text.shading = .color(isGiven ? tones.digitTone.opacity(0.72) : accent)
                context.draw(text, at: centre(index), anchor: .center)
            }

            // 4 — the head, between the two cells it is flying across. A
            // retrograde head is dimmer and smaller: the covenant has no room
            // for a correction that draws more attention than a placement.
            guard let from = frame.from, let to = frame.to else { return }
            let a = centre(from), b = centre(to)
            let head = CGPoint(x: a.x + (b.x - a.x) * frame.t, y: a.y + (b.y - a.y) * frame.t)
            let radius = cell * (frame.isRetrograde ? 0.16 : 0.22)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: head.x - radius * 2.2, y: head.y - radius * 2.2,
                    width: radius * 4.4, height: radius * 4.4
                )),
                with: .radialGradient(
                    Gradient(colors: [accent.opacity(frame.isRetrograde ? 0.18 : 0.32), .clear]),
                    center: head, startRadius: 0, endRadius: radius * 2.2
                )
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2
                )),
                with: .color(accent.opacity(frame.isRetrograde ? 0.45 : 0.9))
            )
        }
        // One picture, one sentence — `SolvedGridThumb`'s rule. 81 cells in the
        // tree of an animation would be unreadable *and* would change under a
        // VoiceOver user mid-swipe; the debrief's prose is the accessible
        // version of this, and it is a sibling rather than a child.
        .accessibilityHidden(true)
    }
}
