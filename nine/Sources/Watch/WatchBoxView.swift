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

    @ViewBuilder
    private var furniture: some View {
        if let game {
            HStack(spacing: 0) {
                rail(PeerRails.column(of: model.selection ?? box * 3, in: game),
                     axis: .vertical,
                     label: Strings.string("watch.rail.column"))
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
                .frame(width: 22 * CouchScale.chrome / 0.42)
            }
            VStack(spacing: 0) {
                rail(PeerRails.row(of: model.selection ?? box * 3, in: game),
                     axis: .horizontal,
                     label: Strings.string("watch.rail.row"))
                Spacer(minLength: 0)
            }
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
        .padding(2)
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
