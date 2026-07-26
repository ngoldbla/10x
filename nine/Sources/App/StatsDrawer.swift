// StatsDrawer.swift — the pull-down board stats panel (iPhone/iPad). Where
// the rose once carried "N left" captions under every petal (PRD-10), the
// remaining-count information now lives here: a row of nine digits, each
// wearing a nine-segment ring that empties as you place that number, plus
// four tiles of current-board trivia. Deliberately unhinted — you find it by
// pulling down from the top of the game screen, and nothing on the board
// changes to tell you it's there.
#if os(iOS)
import SwiftUI
import CouchKit

// MARK: - Segmented ring

/// A ring of nine discrete arcs. `filled` of them wear the accent, the rest
/// the muted track — so a glance counts "three left" without reading a
/// number, which a single trimmed progress arc could never do.
struct SegmentedRing: View {
    /// 0…9 segments lit, clamped on the way in.
    let filled: Int
    let accent: Color
    let track: Color
    var lineWidth: CGFloat = 3

    /// Angular slice removed between neighbours so the nine arcs read as nine
    /// things and not one circle. In turns, matching `trim`'s unit. At this
    /// ring's radius one turn is only ~85pt of arc, so the gap has to be this
    /// generous to survive at 30pt — anything tighter and a run of lit
    /// segments melts into a single sweep.
    private let gap = 0.032

    var body: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                Circle()
                    .trim(from: Double(index) / 9 + gap / 2,
                          to: Double(index + 1) / 9 - gap / 2)
                    .stroke(
                        index < filled ? accent : track,
                        // Butt, not round: a round cap adds lineWidth/2 of arc
                        // at each end, which is wider than the gap itself and
                        // welds neighbouring segments into one ring.
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )
            }
        }
        // `trim` starts at 3 o'clock; the first segment belongs at 12.
        .rotationEffect(.degrees(-90))
        .padding(lineWidth / 2)
        .animation(.couchFast, value: filled)
    }
}

// MARK: - Digit row

/// Digits 1…9 in a single row, each inside its own ring. A finished digit
/// loses its lit segments and dims its label — the same "you're done with
/// this number" signal the rose petals give (`FlickRoseView.petal`).
struct DigitRingRow: View {
    /// Instances of each digit still to place, index 0 = digit 1.
    let remaining: [Int]
    let accent: Color
    let track: Color

    private let ringSize: CGFloat = 30

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...9, id: \.self) { digit in
                cell(for: digit)
            }
        }
    }

    private func cell(for digit: Int) -> some View {
        let left = max(0, min(9, remaining[digit - 1]))
        let complete = left == 0
        return ZStack {
            SegmentedRing(filled: left, accent: accent, track: track)
            Text("\(digit)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(complete ? Color.primary.opacity(0.28) : Color.primary)
        }
        .frame(width: ringSize, height: ringSize)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(complete ? "\(digit), done" : "\(digit), \(left) left")
    }
}

// MARK: - Drawer content

/// Ring row + four tiles of current-board stats. Everything here is derived
/// from `NineGame` on the fly — the drawer persists nothing.
struct StatsDrawerContent: View {
    let model: AppModel

    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }
    private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }
    /// The unlit segments and tile chrome, themed so the drawer reads on
    /// Paper and the tinted themes rather than only on Void.
    private var track: Color { tones.gridTone.opacity(0.14) }

    var body: some View {
        if let game = model.game {
            // The clock and the pace derived from it have to tick while the
            // drawer is open — same treatment as the timer chip.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VStack(spacing: 16) {
                    DigitRingRow(
                        remaining: (1...9).map { 9 - game.count(of: $0) },
                        accent: accent,
                        track: track
                    )
                    HStack(spacing: 8) {
                        tile(Self.format(game.timer.elapsed(at: timeline.date)), "time")
                        tile(paceText(game, at: timeline.date), "pace")
                        tile("\(game.pencilMarkCount)", "notes")
                        tile("\(game.undoCount)", "undos")
                        // Only once a hint has actually been spent (PRD-11 §6).
                        // A player who never opens the coach never sees coach
                        // chrome, and a fifth tile reading "0" would be a
                        // reproach rather than a fact — honest absence over
                        // fake data, per the craft charter.
                        if model.coachHints > 0 {
                            tile("\(model.coachHints)", "hints")
                        }
                    }
                }
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .couchGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Placements needed before the average means anything. At one placement
    /// the average *is* the elapsed time, so the tile would sit beside the
    /// clock showing the same number. It also covers the case where a board
    /// arrives from iCloud with its move log cleared but its timer intact
    /// (`clearLocalHistory()`, PRD-8 §2): the first placements after a merge
    /// divide a whole session's seconds by one or two, and the dash is
    /// honester than a wildly inflated pace.
    private static let paceMinimumPlacements = 3

    /// How the session's seconds-per-number average is worded: an em dash
    /// until the average is meaningful, m:ss once a number takes longer than
    /// a minute, plain seconds otherwise.
    private func paceText(_ game: NineGame, at now: Date) -> String {
        guard game.placementCount >= Self.paceMinimumPlacements,
              let seconds = game.averageSecondsPerPlacement(at: now) else { return "—" }
        return seconds >= 60 ? Self.format(seconds) : "\(Int(seconds.rounded()))s"
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
#endif
