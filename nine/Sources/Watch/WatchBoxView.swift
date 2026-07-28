// WatchBoxView.swift — the lens's furniture (PRD-6 §2.2).
//
// The board itself is `WatchBoardView`; this is what sits around it while the
// lens is down — the peer rails, the Crown rose, and the three commit paths.
//
// The rails are the watch's answer to the cost of zooming in: diving into a
// box buys finger-scale targets and takes away the cross-hatching that is most
// of how sudoku is played. Two slim strips give it back without leaving the
// lens.
#if os(watchOS)
import SwiftUI
import CouchKit
import WatchKit

struct WatchBoxView: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.isLuminanceReduced) private var dimmed
    let box: Int

    private var game: NineGame? { model.game }

    var body: some View {
        ZStack {
            WatchBoardView()
            if !dimmed { furniture }
        }
        // Every commit path lands on `commitDial`, so none of them can drift.
        //
        // Double Tap is an *accelerator*, never the only way in (PRD-6 §5):
        // `.primaryAction` may lose to a system default in focus states we
        // cannot enumerate, and it does not exist on hardware below S9 at all.
        // Tapping the selected cell always works.
        .handGestureShortcut(.primaryAction)
        .onTapGesture(count: 2) { model.commitDial() }
        .gesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                model.commitDial(pencil: true)
            }
        )
    }

    /// How far each strip starts past the other's corner. One number, so the
    /// two cannot be tuned apart.
    private let railInset: CGFloat = 16

    /// The cell the rails describe: the selection, or — before anything is
    /// selected — the box's own top-left, so the strips are never blank and
    /// never lie about which cell they belong to.
    private var railCell: Int { model.selection ?? (box / 3) * 27 + (box % 3) * 3 }

    @ViewBuilder
    private var furniture: some View {
        if let game {
            // Pinned to the real edges rather than centred, and each inset past
            // the other's corner. Three things were measured on a 45mm screen
            // before these numbers existed (PRD-6 Task 7): centred strips run
            // off the sides, edge-flush strips lose their ends to the rounded
            // corner, and two strips both starting at (0, 0) print the row on
            // top of the column.
            VStack(spacing: 0) {
                rail(PeerRails.row(of: railCell, in: game),
                     axis: .horizontal,
                     label: Strings.string("watch.rail.row"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, railInset)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            HStack(spacing: 0) {
                rail(PeerRails.column(of: railCell, in: game),
                     axis: .vertical,
                     label: Strings.string("watch.rail.column"))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, railInset)
                Spacer(minLength: 0)
                CrownRose(
                    game: game,
                    accent: model.accentChoice.color,
                    cell: model.selection,
                    dial: Binding(get: { model.preview }, set: { model.preview = $0 }),
                    onPick: { picked in
                        model.preview = picked
                        model.commitDial()
                    }
                )
                .frame(width: 18)
            }
            .padding(.horizontal, 1)
        }
    }

    /// A rail: the digits already standing on that axis, dimmed, small, and
    /// never interactive. It is information, not a control — tapping one would
    /// be the coach placing a digit.
    @ViewBuilder
    private func rail(_ digits: [Int], axis: Axis, label: String) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 2))
            : AnyLayout(VStackLayout(spacing: 2))
        layout {
            ForEach(digits, id: \.self) { digit in
                Text(digit, format: .number)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        // A readable ground, so a strip laid over the board's own digits stays
        // a strip rather than becoming more digits.
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(.black.opacity(0.55), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(railValue(digits)))
    }

    private func railValue(_ digits: [Int]) -> String {
        digits.isEmpty
            ? Strings.string("watch.rail.empty")
            : digits.map(BoardSpeech.digitWord).joined(separator: ", ")
    }
}
#endif
