// BoardsSheet.swift — the board tracker (playtest fix D4). Lists every board
// the library holds: in-progress partials (resume / archive / delete) and the
// "previously played" log (solved + archived, delete only). Follows the
// HistorySheetContent pattern — a chrome-scaled GlassSheet body shared by iOS,
// macOS and tvOS, with an optional focusable close control for the TV.
#if os(iOS) || os(macOS) || os(tvOS)
import SwiftUI
import CouchKit

struct BoardsSheetContent: View {
    let model: AppModel
    /// tvOS: a focusable dismiss control so the remote/pad can always leave.
    /// On iOS/macOS the scrim tap / window chrome dismisses. Also called after
    /// a resume so the presenting binding resets.
    var onClose: (@MainActor () -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    /// PRD-26: which past solve's debrief is open over this sheet, if any.
    @State private var debriefBoard: UUID?

    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }
    private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }

    /// The one wash every element inside this sheet is drawn on.
    ///
    /// This sheet lives inside a `GlassSheet`, which is already `.regular`
    /// glass — so a pill, a row card or a round button that asks for `.regular`
    /// again gets a second lens over the first, and two lenses read as one
    /// slightly murkier pane rather than as two surfaces. Every inner element
    /// here is therefore `couchInset`: `.identity` glass (it still merges with
    /// its siblings inside the container) plus this tint, which is the whole of
    /// the separation. `gridTone` because it is the theme's own bidirectional
    /// tone — pale on the six dark grounds, dark on Paper and Camel — so one
    /// number works in both directions where a white wash works in one.
    private var insetTint: Color {
        tones.gridTone.opacity(tones.isLight ? 0.10 : 0.14)
    }

    /// TV read distance wants everything larger; iOS/macOS stay pixel-identical.
    private var s: CGFloat {
        #if os(tvOS)
        1.7
        #else
        1.0
        #endif
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24 * s) {
                header

                freshBoardSection

                if model.partials.isEmpty && model.playedBoards.isEmpty {
                    Text(Strings.string("boards.empty"))
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    if !model.partials.isEmpty { inProgressSection }
                    if !model.playedBoards.isEmpty { playedSection }
                }

                Spacer(minLength: 12)

                #if os(tvOS)
                Text(Strings.string("sheet.dismiss.remote"))
                    .font(CouchTypography.caption)
                    .foregroundStyle(.tertiary)
                #elseif !os(macOS)
                Text(Strings.string("sheet.dismiss.touch"))
                    .font(CouchTypography.caption)
                    .foregroundStyle(.tertiary)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .overlay { debriefOverlay }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Strings.string("boards.title"))
                .couchText(CouchTypography.title)
            #if os(tvOS)
            if let onClose {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 22 * s, weight: .semibold))
                        .padding(18 * s)
                        .couchInset(in: Circle(), tint: insetTint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.string("boards.close"))
            }
            #endif
        }
        .padding(.bottom, 4)
    }

    // MARK: - Fresh board (PRD-34)

    /// The second of "New game"'s three new homes. This sheet is the one place
    /// in the app that already means *boards, all of them* — so the row that
    /// makes one belongs at the top of it, above the list it will add to,
    /// rather than at the bottom of Settings where the live audit found it.
    private var freshBoardSection: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            // A section head, not a footnote. Every heading and every piece of
            // metadata in this sheet asked for `caption` and got the same size
            // twice, which is a list with no hierarchy at all; the ramp's new
            // `label` rung is what a section head means, and it leaves `caption`
            // free to be the tier below it.
            Text(Strings.string("boards.fresh.title"))
                .font(CouchTypography.label)
                .foregroundStyle(.secondary)
            // Three and three, borrowing the shelf's own split rather than a
            // new one, so the sheet groups the bands the way the home screen
            // already taught. This was one six-wide row until now: it was
            // authored for the original three, and PRD-25 appended Nocturne,
            // Tempest and Abyss to `allCases` without the layout being
            // revisited. Six across a ~336pt sheet body is ~47pt a pill, so the
            // long titles wrapped to two lines while the short ones did not and
            // the row sat at mixed heights. Iterating the band helpers instead
            // of `allCases` also puts this row back behind `isDeepEnd`'s
            // exhaustive switch, which exists to stop exactly that.
            VStack(spacing: 10 * s) {
                HStack(spacing: 10 * s) {
                    ForEach(Difficulty.rowBands, id: \.self) { freshPill($0) }
                }
                HStack(spacing: 10 * s) {
                    ForEach(Difficulty.deepBands, id: \.self) { freshPill($0) }
                }
            }
            // The board you are on is never destroyed by this: it stays in
            // the library, one row below, exactly where you left it.
            Text(Strings.string("boards.fresh.note"))
                .font(CouchTypography.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// One "start a new board" pill.
    ///
    /// There is a second copy of this row on tvOS, in `PrefsSheet`'s
    /// `newGameSection`. It is duplicated on purpose rather than factored into
    /// a shared control — the two differ in their affordance (see below) and a
    /// component that took a flag for that would be the worse artefact. Change
    /// one, go look at the other.
    ///
    /// **No stroke, and a `plus`.** Glass on glass is invisible: inside a
    /// `GlassSheet`, `couchGlassInteractive` rendered these as bare text with no
    /// affordance at all, and the tinted capsule with a hairline that replaced
    /// it is — exactly — the look of an *unselected filter chip*. Under a
    /// heading that says only "Fresh board", a playtester read the row as
    /// filters over the list below instead of six buttons that each make a
    /// board. So the outline goes, its ink moves into the fill, and the label
    /// leads with a plus: the one mark no filter chip carries. Same ink budget,
    /// spent on saying "this adds something" instead of "this is selectable".
    ///
    /// The finding above was right and was fixed one layer too low: a local
    /// `.background(accent.opacity(0.18), in: Capsule())` here left the three
    /// *other* glass-in-glass sites in this file to each invent their own
    /// recipe. The pixels are unchanged — this is the same 18% accent — but it
    /// is now the ladder's `couchInset` rung saying it, so the next element
    /// added to this sheet inherits the answer instead of re-deriving it.
    private func freshPill(_ difficulty: Difficulty) -> some View {
        Button {
            model.startFree(difficulty)
            onClose?()
        } label: {
            Label {
                Text(Strings.difficulty(difficulty))
            } icon: {
                Image(systemName: "plus")
                    .font(.system(size: 10 * s, weight: .bold, design: .rounded))
            }
            .font(CouchTypography.caption)
            .foregroundStyle(accent)
            // The longest band title in the ten shipped locales is 9 characters
            // ("Constante", "Perspicaz"), ~63pt here, inside a ~81pt content
            // box. It fits, but not by much, so cap the line and let a tight
            // locale buy the last hair by shrinking rather than by wrapping.
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            // Inset before the stretch, so 12pt is a floor the label keeps
            // while the capsule still fills its column. The other order pads
            // outside the stretched frame and shrinks the capsule instead.
            .padding(.horizontal, 12 * s)
            .frame(maxWidth: .infinity)
            // 14, not 12: measured at 40pt in the sim, and the craft charter's
            // floor for a tap target is 44.
            .padding(.vertical, 14 * s)
            .couchInset(in: Capsule(), tint: accent.opacity(0.18))
            .contentShape(.accessibility, Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.string(
            "boards.fresh.label", .text(Strings.difficulty(difficulty))))
    }

    // MARK: - In progress

    private var inProgressSection: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            Text(Strings.string("boards.section.inProgress"))
                .font(CouchTypography.label)
                .foregroundStyle(.secondary)
            ForEach(model.partials) { entry in
                partialRow(entry)
            }
        }
    }

    private func partialRow(_ entry: LibraryEntry) -> some View {
        HStack(spacing: 12 * s) {
            Button {
                model.resumeEntry(id: entry.id)
                onClose?()
            } label: {
                HStack(spacing: 12 * s) {
                    // PRD-22: the same board portrait the shelf shows, so a
                    // row here and a row there are recognisably one board.
                    BoardFingerprint(game: entry.game, accent: accent, side: 30 * s)
                    VStack(alignment: .leading, spacing: 2 * s) {
                        Text(title(for: entry))
                            .font(CouchTypography.body)
                        Text("\(BoardProgressCaption.text(for: entry.game)) · \(SolveCardFacts.elapsedText(entry.game.timer.elapsed(at: Date())))")
                            .font(CouchTypography.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                }
                .padding(14 * s)
                // 28 − 12: the panel this row sits in is `Radius.sheet`, and a
                // card one `Space.m` step inside it has to give that step back
                // or the two curves stop being concentric. It is the same 16
                // that was hand-written here, now with the derivation attached
                // — and it is the radius the rest of the app calls `control`.
                .couchInset(
                    in: RoundedRectangle(
                        cornerRadius: Radius.inner(Radius.sheet, inset: Space.m) * s,
                        style: .continuous),
                    tint: insetTint)
            }
            .buttonStyle(.plain)

            iconButton("archivebox", label: Strings.string("boards.row.archive")) {
                model.archiveEntry(id: entry.id)
            }
            iconButton("xmark.circle.fill", label: Strings.string("boards.row.delete")) {
                model.deleteEntry(id: entry.id)
            }
        }
    }

    // MARK: - Previously played

    private var playedSection: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            Text(Strings.string("boards.section.played"))
                .font(CouchTypography.label)
                .foregroundStyle(.secondary)
            ForEach(model.playedBoards) { entry in
                playedRow(entry)
            }
        }
    }

    private func playedRow(_ entry: LibraryEntry) -> some View {
        HStack(spacing: 12 * s) {
            Image(systemName: entry.status == .archived ? "archivebox" : "checkmark.circle")
                .font(.system(size: 16 * s, weight: .semibold))
                .foregroundStyle(entry.status == .archived ? AnyShapeStyle(.secondary) : AnyShapeStyle(accent))
                .frame(width: 26 * s)
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(title(for: entry))
                    .font(CouchTypography.body)
                Text(statusLine(for: entry))
                    .font(CouchTypography.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            // PRD-26. Only on a board that actually left a replay, so the
            // control is never a promise the record cannot keep — and the
            // debrief stops being a thing you can see for thirty seconds after
            // a solve and never again.
            if model.replays.replay(for: entry.id) != nil {
                iconButton("sparkles", label: DebriefPhrase.replay) {
                    debriefBoard = entry.id
                }
            }
            iconButton("xmark.circle.fill", label: Strings.string("boards.row.delete")) {
                model.deleteEntry(id: entry.id)
            }
        }
        .padding(.vertical, 4 * s)
    }

    /// The debrief for a past solve, over the sheet that opened it.
    ///
    /// An overlay rather than a nested sheet: a sheet inside a `GlassSheet` is
    /// two scrims and two dismiss gestures for one card, and on tvOS the focus
    /// engine has to be handed between them.
    @ViewBuilder
    private var debriefOverlay: some View {
        if let id = debriefBoard,
           let debrief = model.debrief(for: id),
           let replay = model.replays.replay(for: id) {
            ZStack {
                // The theme's own ground on a dark theme, not a flat black:
                // scrimming Blueprint or Ember with black desaturates the one
                // thing that made the theme a theme, and this sheet is the
                // surface a player is looking *at* while it happens.
                Scrim.overlay(for: tones)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { debriefBoard = nil }
                DebriefCardContent(
                    debrief: debrief,
                    replay: replay,
                    tones: tones,
                    accent: accent,
                    onClose: { debriefBoard = nil }
                )
            }
            .transition(.opacity)
        }
    }

    // MARK: - Bits

    private func iconButton(_ symbol: String, label: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18 * s, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Hit.min * s, height: Hit.min * s)
                .couchInset(in: Circle(), tint: insetTint)
                // Without this the AX frame collapses to the glyph's tight
                // bounds (~18pt) — see GlassIconButton for the same fix.
                .contentShape(.accessibility, Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func title(for entry: LibraryEntry) -> String {
        switch entry.kind {
        case .daily(let day):
            // The daily's own day, not `createdAt` (PRD-14). The two were the
            // same date for every board that could exist before the archive, so
            // reading `createdAt` was invisibly wrong; open 13 July from the
            // archive today and the tracker listed it as "Daily · Jul 26".
            return Strings.string("shelf.daily.date",
                                  .text(ArchiveCalendar.mediumLabel(forDayOrdinal: day)))
        case .free(let difficulty):
            return Strings.difficulty(difficulty)
        // PRD-24. The channel comes first for `TouchHomeView.boardTitle`'s reason:
        // it is what makes this a different board rather than a harder one, and the
        // tracker is exactly where two boards at the same tier need telling apart.
        case .channel(let channel, let tier, let day):
            if let day {
                return Strings.string(
                    "shelf.channel.daily",
                    .text(Strings.channel(channel)),
                    .text(ArchiveCalendar.mediumLabel(forDayOrdinal: day)))
            }
            return Strings.string(
                "shelf.channel.free",
                .text(Strings.channel(channel)), .text(Strings.variantTier(tier)))
        }
    }

    private func statusLine(for entry: LibraryEntry) -> String {
        let date = (entry.solvedAt ?? entry.updatedAt).formatted(date: .abbreviated, time: .omitted)
        if entry.status == .solved {
            return Strings.string(
                "boards.status.solved", .text(date),
                .text(SolveCardFacts.elapsedText(entry.game.timer.elapsed(at: Date()))))
        }
        return Strings.string("boards.status.archived", .text(date))
    }
}

// PRD-22 retired this file's `ProgressRing` in favour of `BoardFingerprint`.
// The ring's 0.02 floor was the right instinct — a board is never *nothing* —
// but an arc that short is indistinguishable from the next board's, and a
// portrait made of the givens tells you which board it is instead of only how
// far along it is. Deleted rather than kept dormant: dead view code drifts.
#endif
