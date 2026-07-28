// CrownRose.swift — the rose, unrolled along the bezel (PRD-6 §2.3).
//
// This release's one new input concept, and the craft charter allows exactly
// one. Everything it does is a restatement of the flick rose's grammar in a
// vocabulary the wrist has and the TV does not:
//
//   • nine digits, arranged so the hand can reach them without looking;
//   • a live preview in the cell, dimmed, so you see the move before you own it;
//   • complete digits dimmed on the arc, the same rule the petals follow;
//   • **nothing places without an explicit commit.**
//
// The last one is the covenant, and on a dial it has a specific shape: the run
// is bounded, so overshooting stops at an end rather than looping back toward a
// placement. `CrownDial` holds that rule and a test asserts it, because it is
// the one property you cannot check by turning a crown.
#if os(watchOS)
import SwiftUI
import CouchKit
import WatchKit

/// The digit arc hugging the crown-side bezel, plus the crown binding itself.
struct CrownRose: View {
    let game: NineGame
    let accent: Color
    /// Nil disables the dial — no cell selected, or the board is solved.
    let cell: Int?
    @Binding var dial: CrownDial
    /// Tap the arc directly. The crown is the signature, never the only way in.
    let onPick: (CrownDial) -> Void

    @State private var crown: Double = 0
    @Environment(\.isLuminanceReduced) private var dimmed

    private var enabled: Bool { cell != nil }

    var body: some View {
        arc
            .focusable(enabled)
            .digitalCrownRotation(
                $crown,
                from: Double(CrownDial.lowerBound),
                through: Double(CrownDial.upperBound),
                by: 1,
                sensitivity: .medium,
                // The bounded run. `isContinuous: false` is what makes an
                // enthusiastic spin past ✕ stop at ✕ instead of arriving back
                // at a placement.
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .onChange(of: crown) { _, position in
                guard enabled else { return }
                dial = CrownDial(position: Int(position.rounded()))
            }
            // Selecting a different cell cancels the preview (PRD-6 §2.3), and
            // the crown has to be walked back with it or the next detent would
            // resume from a position the player can no longer see.
            .onChange(of: cell) { _, _ in
                dial = .empty
                crown = 0
            }
            .onChange(of: dial) { _, value in
                if Int(crown.rounded()) != value.position { crown = Double(value.position) }
            }
    }

    /// The arc. Hidden in the Always-On dimmed state along with every other
    /// digit on screen — a bystander should not be able to read the board off
    /// a wrist that has been lowered.
    @ViewBuilder
    private var arc: some View {
        if dimmed {
            Color.clear
        } else {
            VStack(spacing: 1 * CouchScale.chrome) {
                ForEach(CrownDial.lowerBound...CrownDial.upperBound, id: \.self) { position in
                    stop(CrownDial(position: position))
                }
            }
            .frame(maxHeight: .infinity)
            .opacity(enabled ? 1 : 0.25)
            .animation(.couchFast, value: enabled)
        }
    }

    @ViewBuilder
    private func stop(_ value: CrownDial) -> some View {
        let isCurrent = value == dial
        Group {
            switch value {
            case .empty:
                Circle().stroke(lineWidth: 1).frame(width: 5, height: 5)
            case .erase:
                Image(systemName: "multiply")
            case .digit(let d):
                // `format: .number`, not a string: a numeral is locale data,
                // and this is also how it stays out of `strings.py --audit`'s
                // bare-literal net without an exemption.
                Text(d, format: .number)
            }
        }
        .font(.system(size: isCurrent ? 15 : 11, weight: isCurrent ? .bold : .medium,
                      design: .rounded))
        // Complete digits dim, exactly as petals do — the same fact, said the
        // same way, on a third platform.
        .foregroundStyle(tone(for: value, isCurrent: isCurrent))
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onPick(value) }
        .accessibilityLabel(BoardSpeech.dialStopName(value))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    private func tone(for value: CrownDial, isCurrent: Bool) -> Color {
        if let d = value.digit, game.isDigitComplete(d) { return .secondary.opacity(0.35) }
        return isCurrent ? accent : .secondary
    }
}

// MARK: - Commit

extension WatchModel {
    /// Place the dialled value. The three commit paths — tapping the cell,
    /// Double Tap, and tapping the arc — all land here, so none of them can
    /// drift from the others.
    func commitDial(pencil: Bool = false) {
        guard let cell = selection, preview.isCommittable, solvedAt == nil else { return }
        switch preview {
        case .empty:
            return
        case .erase:
            erase(at: cell)
        case .digit(let digit):
            if pencil { self.pencil(digit, at: cell) } else { place(digit, at: cell) }
        }
        WKInterfaceDevice.current().play(.click)
    }
}
#endif
