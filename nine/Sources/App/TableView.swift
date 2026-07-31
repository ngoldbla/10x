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
        VStack(alignment: .leading, spacing: 10 * s) {
            Text(Strings.string("history.section.table"))
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)

            switch face {
            case .invitation:
                note(Strings.string("table.invitation"))
                control(Strings.string("table.join")) { model.setJoinsTable(true) }
            case .signedOut:
                note(Strings.string("history.gameCenter.out"))
                leaveControl
            case .waiting:
                note(Strings.string("table.waiting"))
                leaveControl
            case .seats(let seats):
                VStack(alignment: .leading, spacing: 8 * s) {
                    ForEach(seats) { seat in row(seat) }
                }
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
        return HStack(spacing: 10 * s) {
            WeekMarks(days: seat.week.days, accent: seat.isMe ? accent : accent.opacity(0.55),
                      track: tones.gridTone.opacity(0.10), s: s)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            seat.isMe
                ? Strings.string("table.seat.mine", .int(seat.week.days), .text(elapsed))
                : Strings.string("table.seat.label", .text(seat.name),
                                 .int(seat.week.days), .text(elapsed)))
    }

    // MARK: Chrome

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12 * s, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Leaving is quiet and it is honest about its reach: GameKit has no
    /// delete-my-score call, so what has gone up stays until the occurrence ages
    /// out. Saying that in one line is cheaper than a player discovering it.
    private var leaveControl: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            control(Strings.string("table.leave")) { model.setJoinsTable(false) }
            note(Strings.string("table.leave.note"))
        }
    }

    private var controlShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
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
    private func control(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13 * s, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .padding(.horizontal, 16 * s)
                .frame(minHeight: 44 * s)
                .couchGlassInteractive(in: controlShape)
        }
        .buttonStyle(.plain)
        .contentShape(.accessibility, controlShape)
    }
}
#endif
