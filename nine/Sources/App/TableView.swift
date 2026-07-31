// TableView.swift — PRD-29's twenty seats, drawn in the History sheet's own
// hand-inked language.
//
// `Canvas` and `Path`, no Swift Charts, themed through `ThemeTones` and scaled
// by the sheet's `s` factor — `StatsViews.swift`'s vocabulary, deliberately
// reused rather than extended. The week glyph is the heat grid's mark: this is
// the same measurement the grid above already draws, for other people, so
// inventing an eighth shape for it would say they were different things.
//
// **Everything this file refuses is listed here, because a refusal that is only
// in a spec is a refusal until the next reviewer suggests otherwise:**
//
//   * No rank numbers. The order of the rows *is* the standing; printing it
//     invites arithmetic.
//   * No deltas, no arrows, no "moved up". Nothing anywhere in Nine stores a
//     previous position, so one cannot be computed (PRD-29 §2). This is the
//     "no demotion shame" clause, and it is a property of the data rather than
//     a choice made here.
//   * No podium, no medal, no colour above seat three, no highlight on the
//     leader. Your own row wears the accent; that is the only emphasis.
//   * No avatars. `GKPlayer` will load one, and it is an image of a stranger on
//     a surface about your own week.
//   * No total-player count and no "top 4%". `loadEntries` returns the total
//     and drawing it turns a window back into a position in a hierarchy.
//   * No notification, ever. `TableSealTests` greps this file for the four APIs
//     that could make one.
//
// **Round 2 added a surface under the standings and nothing else.** The blind
// panel's complaint about this sheet was material, not information: *"flat
// opaque fill plus a hairline, not a material"*, and the twenty seats were not
// even that — they were type on bare glass. They are one `historyInset` card
// now, so the section has an edge that catches light, and your own row carries a
// tinted band rather than only a colour change on two glyphs. Every refusal
// above survives it: the card is not a podium, the band is not a rank, and
// nothing about it can be read as a position in a hierarchy.
//
// **Round 3 changed nothing here on purpose.** Every finding that touches this
// section is a property of `historyInset` and `HistoryMetrics` — the card is
// lighter than the sheet on paper now rather than darker, its corner is derived
// from the sheet's own radius and padding, and a light ground gets an ambient
// shadow instead of an outline stroke — so all three arrive through the two
// helpers this file already reads. A local override would have been a fourth
// opinion about a surface that finally has one. The only edit is the note on the
// band's radius below, which those changes made exact.
#if os(iOS) || os(macOS) || os(tvOS)
import SwiftUI
import CouchKit

// MARK: - The week glyph

/// Seven marks, `days` of them inked.
///
/// **A count, drawn as a count — not a calendar.** A leaderboard entry carries
/// `DailyTable.score`, which packs how many days and how long, and nothing about
/// *which* days. Filling marks left to right is therefore the honest drawing;
/// placing them Monday-to-Sunday would be a fabrication for every row but one,
/// and drawing your own row differently from everybody else's would make the
/// section two charts.
///
/// One `Canvas` per row rather than seven views: at twenty seats that is the
/// difference between 20 layers and 140, and it is the same argument the board
/// itself is a single `Canvas` for.
struct WeekMarks: View {
    let days: Int
    let accent: Color
    let track: Color
    let s: CGFloat

    private var mark: CGFloat { 7 * s }
    private var gap: CGFloat { 3 * s }
    private var width: CGFloat { mark * 7 + gap * 6 }

    var body: some View {
        Canvas(opaque: false) { context, size in
            let inked = max(0, min(DailyTable.daysInWeek, days))
            let y = (size.height - mark) / 2
            for index in 0..<DailyTable.daysInWeek {
                let rect = CGRect(
                    x: CGFloat(index) * (mark + gap), y: y, width: mark, height: mark)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 2 * s, style: .continuous),
                    with: .color(index < inked ? accent : track))
            }
        }
        .frame(width: width, height: mark)
        // The marks are inside the row's own accessibility element — the day
        // count is spoken in `table.seat.label`, in the LABEL and not the hint,
        // because a hint can be turned off and PRD-24 shipped nine silent
        // thermometers learning that.
        .accessibilityHidden(true)
    }
}

// MARK: - The section

/// The whole of PRD-29 on screen: an invitation, or twenty seats, or the honest
/// nothing in between.
struct TableSection: View {
    let model: AppModel
    let accent: Color
    let tones: ThemeTones
    let s: CGFloat

    /// Every state this section has, named once, so the body is a `switch` over
    /// a decision rather than a nest of `if let`s that can produce two of them.
    /// PRD-34's rule is one designed zero-state per surface; this surface has
    /// three distinguishable nothings and they must not collapse into one.
    private enum Face {
        case invitation          // opted out — the default
        case signedOut           // opted in, but Game Center is not
        case waiting             // opted in and signed in, nothing to show yet
        case seats([DailyTable.Seat])
    }

    /// Seats first, and that ordering is deliberate rather than convenient.
    ///
    /// In production it changes nothing: `refreshTable` clears the seats when the
    /// player leaves and `loadTable` returns none when Game Center is signed out,
    /// so a non-empty array already implies both. Asking "do we have something to
    /// draw" before asking "are we allowed to" is the shorter total function, and
    /// it is what lets the DEBUG standing be *driven* — the two conditions below
    /// it cannot both be arranged in a simulator, which is the whole reason
    /// PRD-29 §10 admits a real table has never been on a screen.
    private var face: Face {
        if !model.tableSeats.isEmpty { return .seats(model.tableSeats) }
        guard model.joinsTable else { return .invitation }
        guard GameCenter.shared.isAuthenticated else { return .signedOut }
        return .waiting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m * s) {
            // The sheet's one section-label treatment, shared with
            // `HistorySheet` rather than re-typeset here. "The Table" and the
            // sentence under it both used to sample rgb(98,98,98) one point
            // apart, so the header read as the first line of the invitation.
            HistorySectionHeader(text: Strings.string("history.section.table"), s: s)

            switch face {
            case .invitation:
                note(Strings.string("table.invitation"))
                // The one accented control in the sheet: this is the door into
                // PRD-29 and it shipped as bare text on bare glass, measuring
                // 220 interior against a 221 exterior.
                control(Strings.string("table.join"), accented: true) {
                    model.setJoinsTable(true)
                }
            case .signedOut:
                note(Strings.string("history.gameCenter.out"))
                leaveControl
            case .waiting:
                note(Strings.string("table.waiting"))
                leaveControl
            case .seats(let seats):
                // **The standings are a card, like everything else in this
                // sheet.** Twenty rows of unbacked text sitting directly on the
                // panel was the one place in History where a *list* had no
                // surface under it, while the three stat tiles beside it, the
                // Game Center row above it and the join pill below it were all
                // cards. `historyInset` gives it the same L4 rung, the same
                // `childRadius`, the same themed hairline and — round 2 — the
                // same specular rim, so the section has a top edge that catches
                // the light and a bottom lip that does not.
                VStack(alignment: .leading, spacing: Space.xs * s) {
                    ForEach(seats) { seat in row(seat) }
                }
                .padding(.vertical, Space.s * s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .historyInset(tones,
                              radius: HistoryMetrics.childRadius * s,
                              hairline: HistoryMetrics.hairlineWidth * s)
                // One container so Switch Control's group scan treats the
                // standings as a group and steps into it, rather than putting
                // twenty rows in the sheet's top-level scan (PRD-19 §Switch
                // Control: nesting is the only lever there is).
                .accessibilityElement(children: .contain)
                leaveControl
            }
        }
        .task(id: model.joinsTable) { await model.refreshTable() }
    }

    // MARK: One seat

    private func row(_ seat: DailyTable.Seat) -> some View {
        let elapsed = SolveCardFacts.elapsedText(TimeInterval(seat.week.seconds))
        return HStack(spacing: Space.s * s) {
            WeekMarks(days: seat.week.days, accent: seat.isMe ? accent : accent.opacity(0.55),
                      track: HistoryMetrics.track(tones), s: s)
            Text(seat.isMe ? Strings.string("table.you") : seat.name)
                .font(.system(size: 13 * s,
                              weight: seat.isMe ? .semibold : .medium, design: .rounded))
                .foregroundStyle(seat.isMe ? accent : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8 * s)
            Text(elapsed)
                .font(.system(size: 12 * s, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Space.m * s)
        .padding(.vertical, Space.s * s)
        // Your own row, and only your own row, wears a wash.
        //
        // A **fill, not a second material** — `couchInset` inside `couchInset`
        // is the nesting this sheet's header exists to forbid, and a tint is all
        // the emphasis a row needs when it is already the only accented name in
        // the column. Inset from the card's edges by a chip's radius so its
        // corners sit inside the card's own, rather than running full-bleed and
        // squaring off where the card curves away.
        //
        // Round 3 made that inset exact rather than merely sensible.
        // `HistoryMetrics.childRadius` is 16 now — `Radius.inner(38, inset: 22)`,
        // derived from the sheet a phone actually gets — and this band sits
        // `Space.s` (8) inside it at `Radius.chip` (8). `Radius.inner(16,
        // inset: 8)` is 8, so the band's corner is concentric with the card's by
        // arithmetic instead of by eye.
        .background {
            if seat.isMe {
                RoundedRectangle(cornerRadius: Radius.chip * s, style: .continuous)
                    .fill(HistoryMetrics.accentFill(accent, tones))
                    .padding(.horizontal, Space.s * s)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            seat.isMe
                ? Strings.string("table.seat.mine", .int(seat.week.days), .text(elapsed))
                : Strings.string("table.seat.label", .text(seat.name),
                                 .int(seat.week.days), .text(elapsed)))
    }

    // MARK: Chrome

    /// Body copy — an invitation, a caveat, the honest nothing.
    ///
    /// 15pt regular in the sheet's own ink, not 12pt `.secondary`. This is the
    /// prose a player is meant to *read*, and it shipped a rung below the label
    /// above it and in the same colour, which is how a surface ends up typeset
    /// entirely in one grey.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(HistoryMetrics.bodyFont(s))
            .foregroundStyle(HistoryMetrics.bodyInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Leaving is quiet and it is honest about its reach: GameKit has no
    /// delete-my-score call, so what has gone up stays until the occurrence ages
    /// out. Saying that in one line is cheaper than a player discovering it.
    private var leaveControl: some View {
        VStack(alignment: .leading, spacing: Space.s * s) {
            control(Strings.string("table.leave")) { model.setJoinsTable(false) }
            note(Strings.string("table.leave.note"))
        }
    }

    /// `HistoryMetrics.childRadius`, not 14. Every child of the sheet's panel
    /// draws the same corner now — three near-but-not-equal radii (16 / 16 / 14)
    /// is the shape of two files guessing separately.
    private var controlShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: HistoryMetrics.childRadius * s, style: .continuous)
    }

    /// The 44 pt floor, twice, because neither half is enough on its own and
    /// this control was measured at **36 pt** before both were there.
    ///
    /// `minHeight` is what actually makes the target 44 pt — padding around a
    /// 13 pt rounded font came to 36. The accessibility shape then has to sit on
    /// the **`Button`**, not inside its label: PRD-28 measured a card at 64×64
    /// with the shape pinned to a child and 326×64 with it on the control, and
    /// the rule it landed is that pinning a shape onto a child is what SwiftUI
    /// then derives the whole element's frame from. PRD-24's tier cards shipped
    /// at 41 pt for the same reason; this is the third time.
    ///
    /// **`couchInset`, never `couchGlassInteractive`.** This control is drawn
    /// inside `GlassSheet`'s own `.couchGlass` panel, and asking for `.regular`
    /// again there is the glass-in-glass mistake wave 1 measured across twelve
    /// sites: the join pill sampled 220 interior against 221 exterior — a $4.99
    /// app's primary action rendered as a bare hyperlink. L4 gives it shape and
    /// tint and no second lens; `accented` is what makes the one control that
    /// outranks the others look like it.
    private func control(
        _ title: String, accented: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13 * s, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .padding(.horizontal, Space.l * s)
                .frame(minHeight: HistoryMetrics.control * s)
                .historyInset(
                    tones,
                    radius: HistoryMetrics.childRadius * s,
                    fill: accented ? HistoryMetrics.accentFill(accent, tones) : nil,
                    rim: accented ? HistoryMetrics.accentRim(accent) : nil,
                    hairline: HistoryMetrics.hairlineWidth * s,
                    interactive: true)
        }
        .buttonStyle(.plain)
        .contentShape(.accessibility, controlShape)
    }
}
#endif
