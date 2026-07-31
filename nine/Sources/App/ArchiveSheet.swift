// ArchiveSheet.swift — the daily archive (PRD-14): a month grid of every daily
// Nine has served, all of it regenerated from `DailySeed` rather than stored.
//
// The view holds no date arithmetic and no wording. `ArchiveCalendar` owns both,
// in `Sources/Shared`, for two reasons that are really one: a day ordinal is a
// UTC midnight (render it in the device's zone and every label west of
// Greenwich is a day early), and this is the one screen that can never have an
// AX baseline, because every label in it is derived from today's date and would
// rot overnight. Both facts want a Linux unit test, and neither can have one
// from inside a SwiftUI body.
//
// The grid's one deliberate move: **a solved day loses its number**. The
// checkmark replaces the date rather than sitting beside it, so the month reads
// at a glance as a record of what you have done rather than as a calendar
// wearing badges. Everything else stays quiet — no counts, no fills, no streaks
// (the archive is the one surface that must not imply a past day is owed).
//
// iOS and macOS. It was iOS-only when PRD-14 shipped — "the TV and the Mac still
// see archive boards in their board trackers, as ordinary `.daily` library
// entries" — which was true and was also the reason the Mac had no calendar at
// all. PRD-33 gives it one, as a **window** rather than a sheet, and widening this
// fence was the whole cost: `ArchiveSheetContent` needed no change, because
// `ArchiveCalendar` already owned every date and every word from
// `Sources/Shared`.
//
// tvOS stays out. A month grid is a pointer or a fingertip surface, and driving
// seven columns of days with a Siri Remote is the interaction PRD-14 declined in
// the first place.
#if os(iOS) || os(macOS)
import SwiftUI
import CouchKit

struct ArchiveSheetContent: View {
    let model: AppModel
    let onClose: () -> Void

    @State private var month: ArchiveMonth
    @Environment(\.colorScheme) private var colorScheme

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _month = State(initialValue: ArchiveCalendar.month(ofDayOrdinal: model.todayOrdinal))
    }

    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }
    private var firstWeekday: Int { Calendar.current.firstWeekday }
    /// `max(floor, month(of: today))` directly — `months(through:)` computes
    /// exactly this on its first line and then allocates a month-per-element
    /// array we would throw away, on every evaluation of the pager's enabled
    /// state, growing by one for the life of the product.
    private var newestMonth: ArchiveMonth {
        max(ArchiveCalendar.floor, ArchiveCalendar.month(ofDayOrdinal: model.todayOrdinal))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            header
            pager
            VStack(spacing: Space.hair) {
                weekdayHeader
                grid
            }
            Spacer(minLength: 8)
            Text(Phrase.footnote)
                .font(CouchTypography.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Phrase.title)
                .couchText(CouchTypography.title)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: Hit.min, height: Hit.min)
                    // SwiftUI derives an image button's AX frame from the
                    // symbol's tight glyph bounds, not the frame around it
                    // (PRD-19). Without this the target measures ~15pt.
                    .contentShape(.accessibility, Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Phrase.close)
        }
    }

    private var pager: some View {
        HStack(spacing: Space.s) {
            pagerButton(Phrase.previousMonth, "chevron.left",
                        by: -1, enabled: month > ArchiveCalendar.floor)
            Text(ArchiveCalendar.title(for: month))
                .font(CouchTypography.body)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            pagerButton(Phrase.nextMonth, "chevron.right",
                        by: 1, enabled: month < newestMonth)
        }
    }

    private func pagerButton(
        _ label: String, _ symbol: String, by step: Int, enabled: Bool
    ) -> some View {
        Button {
            withAnimation(.couchFast) { month = month.advanced(by: step) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                // Disabled is a *tone*, not a dimmer. A 17pt semibold glyph
                // held at `.opacity(0.2)` measures 1.24:1 on a near-black
                // ground — that is not "unavailable", that is gone — and the
                // two other disabled sites in the app used 0.25, so the state
                // did not even mean one thing. `.tertiary` is the system's own
                // name for it, it survives Increase Contrast, and it leaves
                // opacity for what opacity is good at: dimming a whole
                // container at once.
                .foregroundStyle(enabled ? AnyShapeStyle(.secondary)
                                         : AnyShapeStyle(.tertiary))
                .frame(width: Hit.min, height: Hit.min)
                .contentShape(.accessibility, Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var weekdayHeader: some View {
        HStack(spacing: Space.hair) {
            ForEach(
                Array(ArchiveCalendar.weekdayInitials(firstWeekday: firstWeekday).enumerated()),
                id: \.offset
            ) { _, initial in
                Text(initial)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: Hit.min, height: 22)
            }
        }
        // Decoration: every cell already announces its own full date, so a row
        // of seven bare letters is seven stops that say nothing.
        .accessibilityHidden(true)
    }

    /// Six rows of 44pt cells with 2pt gaps is 320pt wide. The iOS `GlassSheet`
    /// is `maxWidth: 380` with 22pt of content padding, leaving 336 — so the
    /// craft charter's 44pt floor survives at the narrowest width, which is
    /// what fixes the cell size rather than taste.
    private var grid: some View {
        // Both hoisted out of the per-cell path: `todayOrdinal` builds a `Date`
        // and reads calendar components, and `inProgressDaily(day:)` is a
        // linear scan of up to 60 entries — 42 of each, per body evaluation and
        // per frame of the pager animation, when one of each will do.
        let today = model.todayOrdinal
        let inProgress = Set(model.library.partials.compactMap { entry -> Int? in
            if case .daily(let day) = entry.kind { return day }
            return nil
        })
        return VStack(spacing: Space.hair) {
            ForEach(
                Array(ArchiveCalendar.grid(for: month, firstWeekday: firstWeekday).enumerated()),
                id: \.offset
            ) { _, row in
                HStack(spacing: Space.hair) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, ordinal in
                        if let ordinal {
                            ArchiveDayCell(
                                ordinal: ordinal,
                                state: state(of: ordinal, today: today, inProgress: inProgress),
                                accent: accent,
                                // A compose in flight would either be refused
                                // outright or land on top of this board a few
                                // seconds later, so the grid stands down rather
                                // than offering a tap that cannot be honoured.
                                composing: model.composing != nil,
                                action: { open(ordinal) }
                            )
                        } else {
                            Color.clear.frame(width: Hit.min, height: Hit.min)
                        }
                    }
                }
            }
        }
    }

    private func open(_ ordinal: Int) {
        onClose()
        model.openArchiveDay(ordinal)
    }

    /// Two orthogonal reads, never collapsed into one: what the player did with
    /// the board, and where the day sits relative to now.
    private func state(of ordinal: Int, today: Int, inProgress: Set<Int>) -> ArchiveDayState {
        let position: ArchiveDayState.Position
        if ordinal > today {
            position = .future
        } else if ordinal == today {
            position = .today
        } else if ordinal < ArchiveCalendar.floorDayOrdinal {
            // Inside the floor month but before Nine's first daily: shown, so
            // the month is a whole month, but never playable.
            position = .beforeLaunch
        } else {
            position = .past
        }
        let progress: ArchiveDayState.Progress
        if model.archive.isSolved(day: ordinal) {
            progress = .solved
        } else if inProgress.contains(ordinal) {
            progress = .inProgress
        } else {
            progress = .untouched
        }
        return ArchiveDayState(progress: progress, position: position)
    }

    /// This sheet's copy, in one block — the seam PRD-20 converts to
    /// `LocalizedStringResource`.
    private enum Phrase {
        static let title = Strings.string("archive.title")
        static let close = Strings.string("archive.close")
        static let previousMonth = Strings.string("archive.previousMonth")
        static let nextMonth = Strings.string("archive.nextMonth")
        /// Answers the one question a player actually has before tapping a past
        /// day, and answers it before they have to wonder.
        static let footnote = Strings.string("archive.footnote")
    }
}

/// One day. The background says where the day is, the mark says what you did
/// with it — and on a solved day the mark takes the number's place entirely.
private struct ArchiveDayCell: View {
    let ordinal: Int
    let state: ArchiveDayState
    let accent: Color
    let composing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                background
                mark
            }
            .frame(width: Hit.min, height: Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.isPlayable || composing)
        .accessibilityLabel(
            ArchiveCalendar.accessibilityLabel(forDayOrdinal: ordinal, state: state)
        )
    }

    /// Position, not progress: where this day sits relative to now.
    ///
    /// The radius was a magic 11 — the cell's side × 0.25, which is a ratio
    /// nothing else in the app uses — and it sat 1pt off `Radius.tile`, the
    /// rung that means exactly "a tile inside a card". Two sheets disagreeing
    /// by a point about how round the product is reads as a mistake rather than
    /// as a decision, so the day cell joins the ladder.
    ///
    /// The today fill is unchanged at 28% accent, but it is `couchInset` now
    /// rather than a bare `fill`: this grid is inside a `GlassSheet`, and the
    /// inset rung keeps the cell inside the enclosing glass container (so it
    /// still merges with its neighbours) while contributing no second lens.
    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        switch state.position {
        case .today:
            Color.clear.couchInset(in: shape, tint: accent.opacity(0.28))
        case .past, .future, .beforeLaunch:
            if state.progress == .inProgress {
                // A ring, not a fill: a partial is an invitation, not a state
                // the day is finished in.
                shape.strokeBorder(accent.opacity(0.5), lineWidth: 1.5)
            } else {
                shape.fill(.clear)
            }
        }
    }

    /// Progress, not position — and the sheet's one bold move. A solved day
    /// loses its number, so a month of them reads as a record rather than as a
    /// calendar wearing badges.
    @ViewBuilder
    private var mark: some View {
        if state.progress == .solved {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(accent)
        } else {
            // A date, drawn as a numeral — `ArchiveCalendar` owns every word
            // in this grid and this is the one thing in it that is not one.
            Text(verbatim: "\(ArchiveCalendar.dayNumber(forDayOrdinal: ordinal))")
                // `label`, not `caption`: the ramp's `caption` is the 11pt tier
                // now (it used to be 13pt semibold), and a date is not
                // metadata in a calendar — it is the cell's whole content, and
                // the only thing distinguishing 31 cells from each other.
                // Tabular, so a column of days is a column rather than a
                // ragged one point off centre at every 1.
                .font(CouchTypography.label)
                .monospacedDigit()
                .foregroundStyle(state.isPlayable ? .secondary : .tertiary)
        }
    }
}
#endif
