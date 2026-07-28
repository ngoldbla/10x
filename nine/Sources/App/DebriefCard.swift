// DebriefCard.swift — what the debrief looks like (PRD-26 §2.2).
//
// Every word it says came from `SolveDebrief`, which is pure and tests on
// Linux; every decision about what the comet draws came from `CometTimeline`,
// which is the same. What is left here is layout, and that is the point of the
// split — `SolveCardFacts` made the argument for the share card and this is the
// second instance of it.
//
// **Never forced, and this file cannot force it.** There is no presentation
// state in here, no `isPresented`, and no timer. It is a card somebody else
// decided to show.
import SwiftUI
import CouchKit
#if canImport(NineEngine)
import NineEngine
#endif

/// The post-solve debrief: your own solve, retraced, and what the board can
/// prove about it.
struct DebriefCardContent: View {
    let debrief: SolveDebrief
    let replay: SolveReplay
    let tones: ThemeTones
    let accent: Color
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(DebriefPhrase.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))

            comet

            // The counts are true for every log, so they are always here.
            Text(debrief.countsLine)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            // The headline and the two timing lines, each present only when it
            // is *true* — an untimed log simply produces a shorter card
            // (PRD-26 §2.3). Nothing explains the absence.
            ForEach(debrief.lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            closeButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 360, alignment: .leading)
        .couchGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var comet: some View {
        if let puzzle = replay.puzzle, !replay.moves.isEmpty {
            CometView(
                puzzle: puzzle,
                moves: replay.moves,
                tones: tones,
                accent: accent,
                // Reduce Motion gets the finished board rather than no board:
                // a still frame at the end of the loop *is* the solve, and an
                // empty slot would read as a broken card.
                frozenPhase: reduceMotion ? 1 : nil
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 280)
        } else {
            Text(DebriefPhrase.empty)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    /// **A sibling of the prose, not a child of it.** PRD-25 found this the
    /// expensive way: `.accessibilityElement(children: .contain)` around a card
    /// exposed three of six subviews and no button at all, so a VoiceOver user
    /// could read the card and had no way to dismiss it. A card's action must
    /// not depend on container semantics to exist.
    ///
    /// `minHeight: 44` *outside* the glass, so the target grows and the drawn
    /// capsule does not move — three buttons were measured at 69×36 before that
    /// line existed anywhere in this app.
    private var closeButton: some View {
        Button(action: onClose) {
            Text(DebriefPhrase.close)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .couchGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(.accessibility, Rectangle())
    }
}

/// The debrief's words. Its own enum rather than nested, so the game screen can
/// label the pull-up control with the same strings the card closes itself with
/// — `ShareCardPhrase`'s arrangement, for `ShareCardPhrase`'s reason.
enum DebriefPhrase {
    static var title: String { Strings.string("debrief.title") }
    static var empty: String { Strings.string("debrief.empty") }
    static var open: String { Strings.string("debrief.open") }
    static var close: String { Strings.string("debrief.close") }
    static var replay: String { Strings.string("debrief.replay") }
}
