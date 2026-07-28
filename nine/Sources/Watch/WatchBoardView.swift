// WatchBoardView.swift — the map and the lens, one Canvas (PRD-6 §2.1–2.2).
//
// The whole board at ~190pt with ~13pt digits: readable, deliberately not
// tappable per cell. Tapping dives into the 3×3 box you touched, where cells
// are ~56pt and the targets are honest.
//
// **The lens is the same view.** PRD-6 §4 Step 2 asks for "one drawing surface,
// two camera positions — no second board implementation", and that is literal
// here: `BoardView` is rendered once and the box view is the same instance
// scaled 3× and offset, inside a clip. Same-number highlight, error underlines
// and the completion wave therefore work at both zoom levels for free, and a
// change to the board cannot make the two disagree — there is nothing to
// disagree with.
#if os(watchOS)
import SwiftUI
import CouchKit

struct WatchBoardView: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.isLuminanceReduced) private var dimmed

    /// The box currently under the lens, or nil on the overview map.
    private var box: Int? {
        if case .box(let b) = model.screen { return b }
        return nil
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                if let game = model.game {
                    board(game, side: side, in: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // NOT `ignoresSafeArea`. The first build did, and the board drew
        // underneath the clock and the title — rows 1 and 2 sat behind them,
        // which on a board where every cell matters is not a cosmetic problem.
        // The watch's safe area is the readable area; the board takes exactly
        // it (PRD-6 Task 7).
        .toolbar { fillArc }
    }

    @ViewBuilder
    private func board(_ game: NineGame, side: CGFloat, in size: CGSize) -> some View {
        // Always-On: the silhouette and the fill arc, never the digits. A
        // lowered wrist is a screen someone else can read (PRD-6 §2.4).
        let showDigits = !dimmed
        let zoom: CGFloat = box == nil ? 1 : 3

        BoardView(
            game: showDigits ? game : NineGame(puzzle: game.puzzle),
            cursor: model.selection ?? -1,
            accent: model.accentChoice.color,
            showErrors: showDigits,
            solvedAt: model.solvedAt,
            roseOpen: false,
            previewDigit: showDigits ? model.preview.digit : nil,
            previewPencil: false,
            // The petal lens and the Afterglow shaders do not exist on
            // watchOS; `waveOrigin: nil` is what routes the celebration down
            // the Canvas-drawn diagonal wave (PRD-6 §2.4).
            waveOrigin: nil,
            side: side * 0.94,
            inset: 3
        )
        .scaleEffect(zoom, anchor: .center)
        .offset(boxOffset(side: side * 0.94))
        .frame(width: size.width, height: size.height)
        .clipped()
        // A named token, never an inline literal (craft charter). The dive is
        // a chrome response, not weather, so it takes `couchFast`.
        .animation(.couchFast, value: box)
        .contentShape(Rectangle())
        .onTapGesture { point in handleTap(point, side: side, in: size) }
    }

    /// Slide the scaled board so `box` sits in the middle of the screen.
    private func boxOffset(side: CGFloat) -> CGSize {
        guard let box else { return .zero }
        let third = side / 3
        // Box centre in board coordinates, relative to the board's own centre,
        // then multiplied by the zoom because the offset is applied after it.
        let dx = (CGFloat(box % 3) - 1) * third
        let dy = (CGFloat(box / 3) - 1) * third
        return CGSize(width: -dx * 3, height: -dy * 3)
    }

    private func handleTap(_ point: CGPoint, side: CGFloat, in size: CGSize) {
        guard let game = model.game, model.solvedAt == nil else { return }
        let drawn = side * 0.94
        if let box {
            // In the lens: pick the cell. The scaled board's on-screen
            // geometry is one third of the box, laid over the whole screen.
            let cell = lensCell(at: point, box: box, in: size)
            guard let cell, !game.isGiven(cell) else { return }
            model.selection = model.selection == cell ? nil : cell
            model.preview = .empty
        } else {
            // On the map: dive. Box targets are ~63pt; cells are not offered.
            let origin = CGPoint(x: (size.width - drawn) / 2, y: (size.height - drawn) / 2)
            let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
            guard local.x >= 0, local.y >= 0, local.x < drawn, local.y < drawn else { return }
            let col = min(2, max(0, Int(local.x / (drawn / 3))))
            let row = min(2, max(0, Int(local.y / (drawn / 3))))
            model.selection = nil
            model.preview = .empty
            model.screen = .box(row * 3 + col)
        }
    }

    /// Which of the box's nine cells a screen point lands on.
    private func lensCell(at point: CGPoint, box: Int, in size: CGSize) -> Int? {
        let step = min(size.width, size.height) / 3
        let origin = CGPoint(x: (size.width - step * 3) / 2, y: (size.height - step * 3) / 2)
        let col = Int((point.x - origin.x) / step)
        let row = Int((point.y - origin.y) / step)
        guard (0..<3).contains(col), (0..<3).contains(row) else { return nil }
        return (box / 3) * 27 + row * 9 + (box % 3) * 3 + col
    }

    /// The one piece of chrome PRD-6 §2.1 allows in the toolbar: a thin
    /// progress arc. No timer, no move count, nothing that asks for attention
    /// while the player is thinking.
    @ToolbarContentBuilder
    private var fillArc: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let game = model.game {
                // System-sized. A `scaleEffect` here shrank the drawing but not
                // the slot, so the arc floated in a circle twice its size.
                Gauge(value: game.fillFraction) { EmptyView() }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(model.accentChoice.color)
                    .accessibilityLabel(Text(BoardSpeech.progressSummary(game)))
            }
        }
    }
}
#endif
