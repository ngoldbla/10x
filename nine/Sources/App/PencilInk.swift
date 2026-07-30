// PencilInk.swift — the Apple Pencil half of PRD-31: stroke capture, the live
// trail, and the one rule that keeps a second input concept from appearing.
//
// **The Pencil writes notes. That is the whole grammar.**
//
// It was tempting to give the Pencil a full vocabulary — write to place, scribble
// to erase, double-tap to switch. Every one of those is a second concept, and
// the craft charter allows exactly one per release. What ships instead falls out
// of a rule the app already has: `NineGame.togglePencil` *toggles*, so writing a
// 4 into a cell that already notes a 4 takes it away again. Erase needs no
// gesture, no mode and no glyph of its own; it is the same act done twice, which
// is also what the rose's dashed-rim petal means. A Pencil tap is left alone
// entirely and blooms the rose like any other tap, so nothing the player already
// knows stops working when they pick up a pen.
//
// Placed digits are never ink. Your hand is what *tentative* looks like in this
// app and the typeface is what *committed* looks like, which is why writing
// cannot place a digit even though the recognizer would happily allow it.
#if os(iOS)
import SwiftUI

/// Collects Pencil strokes into one glyph and hands it over once the pen has
/// been up long enough to mean it.
///
/// Multi-stroke digits are the reason this needs a clock at all: a 4 is two
/// strokes for most people, a 5 is two, a 7 with a crossbar is two. Committing
/// on the first pen-up would read the vertical of a 4 as a 1 and then read the
/// crossbar as nothing, which is both wrong answers in a row.
@MainActor
@Observable
final class PencilScribe {

    /// How long the pen may be up before the glyph is considered finished.
    ///
    /// 0.45 s is the same figure `TouchGameScreen` already uses for the
    /// long-press that asks "why must this be a seven" — not a coincidence
    /// worth chasing, but a useful sanity check that it sits in the range a
    /// hand reads as "still doing the same thing".
    static let multiStrokeGrace = Duration.milliseconds(450)

    /// Strokes in the board's *padded view* space, as delivered.
    private(set) var strokes: [[CGPoint]] = []
    /// True from the first contact until the glyph commits or is dropped.
    private(set) var isActive = false
    /// When a Pencil event last arrived, for the tap suppression below.
    private(set) var lastEvent: Date = .distantPast

    private var open: [SpatialEventCollection.Event.ID: Int] = [:]
    private var commitTask: Task<Void, Never>?

    /// A finger tap that lands within this of a Pencil event is the Pencil's
    /// own stroke leaking into the tap recogniser, not a tap.
    ///
    /// `SpatialEventGesture` runs alongside the board's `onTapGesture` and
    /// `LongPressGesture` rather than instead of them — which is what keeps
    /// finger play untouched, and what makes this window necessary: a slow
    /// stroke would otherwise trip the 0.45 s long press and open a why-chain
    /// in the middle of writing a 4.
    static let suppressionWindow: TimeInterval = 0.8

    /// Is a Pencil currently mid-glyph, or was one a moment ago? Read by the
    /// board's tap and long-press handlers, which stand down while it is true.
    var suppressesTouch: Bool {
        isActive || Date.now.timeIntervalSince(lastEvent) < Self.suppressionWindow
    }

    /// Feed one update of the gesture's event collection.
    ///
    /// Only `.pencil` events are looked at. `.touch` arrives here too and is
    /// ignored on purpose: the finger's grammar is already complete, and a
    /// second reading of it would be a second implementation of the rose.
    func handle(_ events: SpatialEventCollection, commit: @escaping (InkGlyph) -> Void) {
        var sawPencil = false
        for event in events where event.kind == .pencil {
            sawPencil = true
            switch event.phase {
            case .active:
                if let index = open[event.id] {
                    strokes[index].append(event.location)
                } else {
                    // A new stroke joining an unfinished glyph cancels the
                    // pending commit — that is the multi-stroke rule.
                    commitTask?.cancel()
                    strokes.append([event.location])
                    open[event.id] = strokes.count - 1
                    isActive = true
                }
            case .ended:
                if let index = open.removeValue(forKey: event.id) {
                    strokes[index].append(event.location)
                }
            case .cancelled:
                open.removeValue(forKey: event.id)
            @unknown default:
                open.removeValue(forKey: event.id)
            }
        }
        guard sawPencil else { return }
        lastEvent = .now
        if open.isEmpty, !strokes.isEmpty { scheduleCommit(commit) }
    }

    /// The gesture ended: every event is over whatever the collection says.
    func finish(commit: @escaping (InkGlyph) -> Void) {
        guard isActive else { return }
        open.removeAll()
        if !strokes.isEmpty { scheduleCommit(commit) }
    }

    /// Drop the glyph without reading it — the board went away, the rose
    /// opened, the app went to the background.
    func cancel() {
        commitTask?.cancel()
        commitTask = nil
        open.removeAll()
        strokes = []
        isActive = false
    }

    private func scheduleCommit(_ commit: @escaping (InkGlyph) -> Void) {
        commitTask?.cancel()
        // `Task.sleep` returns *immediately* when cancelled rather than
        // continuing — PRD-12 lost a share button to exactly that. Here
        // cancellation is the intent (another stroke arrived), so the guard
        // below is the whole mechanism rather than a defensive afterthought.
        // The task is owned by this object and not by a `.task` modifier, so
        // ordinary view churn cannot cancel it out from under a real glyph.
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: Self.multiStrokeGrace)
            guard !Task.isCancelled, let self else { return }
            let ink = self.strokes
            self.strokes = []
            self.isActive = false
            self.commitTask = nil
            guard !ink.isEmpty else { return }
            commit(InkGlyph(strokes: ink.map { $0.map { InkPoint(x: $0.x, y: $0.y) } }))
        }
    }
}

/// The wet ink, drawn over the board while the glyph is still being written.
///
/// A plain `Canvas` above the board's own, in the accent at half weight: it has
/// to read as *not yet a mark*, because until the grace window closes it is not
/// one. When it commits the trail vanishes and a note appears in its slot; when
/// it is refused the trail vanishes and nothing does, which is the only tell
/// that a stroke was not understood. That silence is deliberate — see
/// `DigitHand.commitScore` for what the alternative costs.
struct WetInkView: View {
    let strokes: [[CGPoint]]
    let accent: Color
    let side: CGFloat

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes where stroke.count >= 2 {
                var path = Path()
                path.move(to: stroke[0])
                for point in stroke.dropFirst() { path.addLine(to: point) }
                context.stroke(
                    path,
                    with: .color(accent.opacity(0.55)),
                    style: StrokeStyle(lineWidth: max(2, side / 240),
                                       lineCap: .round, lineJoin: .round)
                )
            }
        }
        .allowsHitTesting(false)
        // The ink is a transient of the player's own hand; VoiceOver hears
        // about the mark it becomes, through the cell's value, and never about
        // the stroke.
        .accessibilityHidden(true)
    }
}
#endif
