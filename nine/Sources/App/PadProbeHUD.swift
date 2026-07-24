// PadProbeHUD.swift — a DEBUG-only diagnostics overlay for the PRD-5 tvOS
// controller track. Renders `PadReader.debugSnapshot()` on `TimelineView(.animation)`
// so a REAL DualSense forwarded into the simulator (Simulator ▸ I/O ▸ Send Game
// Controller to Device) can be observed end-to-end: which buttons light *right
// now*, whether the poll-edge counter ticks on a physical press, the last
// gesture the reader emitted, and which surface its stream is pointed at.
//
// This is the instrument the plan's Phase 1 observation session reads. It never
// compiles into Release (`#if DEBUG`) and only mounts under `--pad-probe`.
#if os(tvOS) && DEBUG
import SwiftUI
import CouchKit

struct PadProbeHUD: View {
    let model: AppModel

    private static let buttons: [(PadButton, String)] = [
        (.cross, "✕"), (.circle, "○"), (.square, "□"), (.triangle, "△"),
        (.l1, "L1"), (.r1, "R1"), (.l2, "L2"), (.r2, "R2"),
        (.r3, "R3"), (.options, "Opt"),
    ]

    var body: some View {
        TimelineView(.animation) { _ in
            let snap = model.padReader.debugSnapshot()
            VStack(alignment: .leading, spacing: 4) {
                Text("PAD PROBE").font(.system(size: 22, weight: .bold, design: .monospaced))
                Divider().overlay(.white.opacity(0.3))
                row("adopted", snap.adopted ? (snap.vendorName ?? "yes") : "no")
                row("controllers", "\(snap.extendedCount)/\(snap.controllerCount) extended")
                row("session", "\(model.padSession ? "PAD" : "remote") · \(model.padConnected ? "connected" : "—")")
                row("routing", model.padRoutingLabel)
                row("gestures", "\(snap.gestureCount)  last: \(snap.lastGesture ?? "—")")
                buttonsGrid(snap)
                row("L-stick", fmt(snap.leftStick))
                row("R-stick", fmt(snap.rightStick))
                row("d-pad", fmt(snap.dpad))
            }
            .font(.system(size: 20, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(16)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            .padding(28)
        }
        .allowsHitTesting(false)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.white.opacity(0.6)).frame(width: 150, alignment: .leading)
            Text(value)
        }
    }

    private func buttonsGrid(_ snap: PadDebugSnapshot) -> some View {
        HStack(spacing: 12) {
            ForEach(Self.buttons, id: \.0) { button, glyph in
                let lit = snap.pressed[button] ?? false
                VStack(spacing: 2) {
                    Text(glyph).foregroundStyle(lit ? .green : .white.opacity(0.5))
                    // The poll-edge counter: the honest proof a physical press
                    // reached the 60 Hz sampler (Phase 2.1).
                    Text("\(snap.edgeCounts[button] ?? 0)")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private func fmt(_ v: SIMD2<Double>) -> String {
        String(format: "%+.2f, %+.2f", v.x, v.y)
    }
}
#endif
