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
                // `CouchTypography.label` is the ramp's footnote rung and on
                // handheld it resolves to the same 13pt semibold SF Rounded
                // this line used to spell out by hand — the difference is that
                // the token scales with Dynamic Type and the literal never did.
                // The ring stays 30pt (`DraftingTable` sizes the rail off it),
                // so the digit is allowed to shrink rather than burst its ring
                // at the accessibility sizes.
                .couchText(CouchTypography.label,
                           complete ? Color.primary.opacity(0.28) : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: ringSize, height: ringSize)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(complete ? Strings.string("board.stats.digitDone", .int(digit))
                                     : Strings.string("board.stats.digitLeft",
                                                      .int(digit), .int(left)))
    }
}

// MARK: - Drawer content

/// Ring row + four to six tiles of current-board stats. Everything here is
/// derived from `NineGame` on the fly — the drawer persists nothing.
///
/// **This view is L4 content and never draws its own surface.** It is composed
/// into two `Radius.sheet` glass panels (`TouchUI.statsDrawer` on the phone,
/// `TouchUI.statsRail` on the iPad) and both of those are themselves inside a
/// glass sheet, so anything here that asked for `.couchGlass` was the third
/// pane in a stack of three. The tiles use wave 1's `couchInset` rung instead —
/// see `tileWash` — and register with a `CouchGlassContainer` so the row merges
/// as one instrument rather than lighting itself six times.
struct StatsDrawerContent: View {
    let model: AppModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }
    private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }
    /// The unlit segments and tile chrome, themed so the drawer reads on
    /// Paper and the tinted themes rather than only on Void.
    private var track: Color { tones.gridTone.opacity(0.14) }

    // MARK: Tile metrics
    //
    // Both surfaces that host this content are `Radius.sheet` panels: the
    // pull-down sheet (`TouchUI.statsDrawer`) and the iPad drafting-table rail
    // (`TouchUI.statsRail`). Until now the tiles inside them asked for
    // `.couchGlass` at a hand-picked r=14, which is wrong twice over.

    /// **Shape, not a third material.** `.regular` glass inside `.regular`
    /// glass inside a `.regular` sheet has nothing left to refract: on the
    /// pre-26 fallback each layer only stacks another white 0.12 hairline, and
    /// on 26 the tile has no boundary at all because both panes resolve to the
    /// same lens. `couchInset` is wave 1's L4 rung — `.identity` glass, so the
    /// tile still merges with its siblings inside a `CouchGlassContainer`, plus
    /// a tint and nothing else.
    ///
    /// The wash is the theme's own `gridTone`, which is white on the dark
    /// grounds and near-black on Paper and Camel, so the step goes *away* from
    /// the rail in whichever direction the ground is leaning.
    ///
    /// **0.10, not the 0.08 the order named.** The pre-26 path draws this tint
    /// with no material under it at all, and 8% white over a rail that
    /// composites to roughly (40,40,45) lands at ≈1.30:1 — under the 1.35:1
    /// step the order asks for. 0.10 clears it and still sits a rung below this
    /// file's own `track` (0.14), which is right: a fill should be quieter than
    /// a stroke. The contrast harness is the arbiter; see `notesForCritic`.
    private static let tileWash: Double = 0.10

    /// Concentric with the panel, derived rather than declared. The panel is
    /// `Radius.sheet` and pads its content by roughly `Space.l` (the rail pads
    /// 16, the pull-down 18), so the nested curve is `outer − inset`. The
    /// shipped 14 was a fresh literal that happened to be neither. Expressed as
    /// the token so that if the panel's padding is retuned in `TouchUI.swift`
    /// — which this order does not own — the relationship stays true rather
    /// than the number staying true.
    private static let tileCorner = Radius.inner(Radius.sheet, inset: Space.l)

    /// A floor, so a four-tile row and a six-tile row are the same object at
    /// two widths rather than two differently proportioned rows. Sized for two
    /// lines (`numeral` over `caption`) with air, which is what the tiles that
    /// happened to wrap their label already measured — the others sat 20pt
    /// shorter beside them.
    private static let tileMinHeight: CGFloat = 64

    var body: some View {
        if let game = model.game {
            // The clock and the pace derived from it have to tick while the
            // drawer is open — same treatment as the timer chip.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VStack(spacing: Space.l) {
                    DigitRingRow(
                        remaining: (1...9).map { 9 - game.count(of: $0) },
                        accent: accent,
                        track: track
                    )
                    // **One container for the whole rank.** Four to six
                    // adjacent glass shapes sitting loose in an `HStack` get no
                    // merge and no shared specular pass on 26 — each one lights
                    // itself, which is what made the row read as six stickers
                    // rather than as one instrument panel. Now that the tiles
                    // are `.identity` glass (`couchInset`), registering them
                    // with a container is exactly what that rung is for.
                    CouchGlassContainer(spacing: Space.s) {
                        HStack(spacing: Space.s) {
                            tile(SolveCardFacts.elapsedText(game.timer.elapsed(at: timeline.date)),
                                 Strings.string("board.stats.time"))
                            tile(paceText(game, at: timeline.date),
                                 Strings.string("board.stats.pace"))
                            tile("\(game.pencilMarkCount)", Strings.string("board.stats.notes"))
                            tile("\(game.undoCount)", Strings.string("board.stats.undos"))
                            // Wrong digits placed on this board (Task 3, PRD-26 —
                            // the debrief's `SolveDebrief.errors` has the same
                            // source-of-truth split from `undoCount`/`corrections`
                            // that `NineGame.errorCount` documents). Same
                            // honest-absence idiom as the hints tile below: a
                            // board nobody has slipped on shows no tile rather
                            // than one reading "0".
                            if game.errorCount > 0 {
                                tile("\(game.errorCount)", Strings.string("board.stats.errors"))
                            }
                            // Only once a hint has actually been spent (PRD-11 §6).
                            // A player who never opens the coach never sees coach
                            // chrome, and a fifth tile reading "0" would be a
                            // reproach rather than a fact — honest absence over
                            // fake data, per the craft charter.
                            if model.coachHints > 0 {
                                tile("\(model.coachHints)", Strings.string("board.stats.hints"))
                            }
                        }
                    }
                    // PRD-25's one number, in a sentence rather than a tile —
                    // and only once the player has met something. A tile would
                    // make it a score sitting beside four measurements of this
                    // board; a sentence, shown only when it is non-zero, is a
                    // fact about the person. It is the ONLY place the count
                    // appears anywhere in Nine (`CoachProgress`'s header).
                    if model.techniquesMet.met > 0 {
                        Text(Strings.string("stats.techniquesMet",
                                            .int(model.techniquesMet.met),
                                            .int(model.techniquesMet.total)))
                            .couchText(CouchTypography.caption, .secondary)
                            // The one figure in the drawer that was still
                            // proportional. It is an "n of m" sentence, so the
                            // digits want the same tabular treatment the tiles
                            // get — a 1 that is narrower than a 0 re-centres
                            // the whole line when the count goes up.
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .snappy(duration: 0.24),
                                       value: model.techniquesMet.met)
                            .padding(.top, Space.hair)
                    }
                }
            }
        }
    }

    /// One tile of the rank. Every tile is the same object at the same size:
    /// the row is a measuring instrument, and an instrument whose dials are
    /// different sizes is a collage.
    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: Space.xs) {
            Text(value)
                // `numeral` carries `.monospacedDigit()` by construction, so
                // the hand-applied one this line used to chain is gone rather
                // than duplicated.
                .couchText(CouchTypography.numeral)
                // Every value here changes *while the drawer is open* — the
                // whole content is inside a one-second `TimelineView` — so the
                // elapsed and pace figures used to cut frame to frame. Tabular
                // figures hold the width; `.numericText()` rolls the digit that
                // actually moved. The transition needs an animation to ride on,
                // which is what the `.animation` below supplies: a `TimelineView`
                // tick is not itself an animated transaction.
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: value)
            Text(label)
                .couchText(CouchTypography.caption, .secondary)
                // Single line on purpose. The label is what decides a tile's
                // height, and a six-tile row on a 393pt phone is narrow enough
                // that a translated label ("Rückgängig", "取り消し") would wrap
                // in one tile and not in the other five — which is precisely
                // the ragged rank the `minHeight` above exists to end. Shrink
                // rather than wrap; the floor keeps the shrink from mattering.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Space.xs)
        .padding(.vertical, Space.s)
        // Frame *before* the material, so the tint fills the whole tile rather
        // than only the text's own bounds.
        .frame(maxWidth: .infinity, minHeight: Self.tileMinHeight)
        .couchInset(in: RoundedRectangle(cornerRadius: Self.tileCorner, style: .continuous),
                    tint: tones.gridTone.opacity(Self.tileWash))
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
        return seconds >= 60 ? SolveCardFacts.elapsedText(seconds)
            : Strings.string("board.stats.paceSeconds", .int(Int(seconds.rounded())))
    }
}
#endif
