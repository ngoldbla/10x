// TouchUI.swift — Nine's touch-native layer (iPhone + iPad). Same AppModel,
// same engine, same board and rose rendering as the TV app; only the input
// grammar changes:
//
//   tap a cell            open the flick rose on that cell
//   tap a petal           place that digit
//   flick (in the rose)   place instantly — same 3×3 keypad mapping as tvOS
//   tap outside the rose  cancel
//   pencil toggle         rose places corner notes instead
//   undo button           take back a move (glass toast shows what reverted)
//   gear                  prefs sheet · chevron: save + home
#if os(iOS)
import SwiftUI
import CouchKit

// MARK: - Home

struct TouchHomeView: View {
    let model: AppModel

    @State private var showHistory = false
    @State private var showTutorial = false
    @State private var showSchool = false
    @State private var showBoards = false
    @State private var showArchive = false
    /// The variants teaser's answer, swapped in place of its own subtitle so
    /// the shelf never grows a floating chip nobody asked for.
    @Environment(\.colorScheme) private var colorScheme
    /// Read rather than pinned: `DragGesture.translation` is not RTL-mirrored
    /// (`FlickRoseView:128`), and unlike the rose — whose petal order must NOT
    /// mirror, decision 3 of PRD-20 — a pager genuinely should. See
    /// `pageTurnGesture`.
    @Environment(\.layoutDirection) private var layoutDirection

    /// The accent resolved for the theme's leaning (themes pin the scheme).
    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    /// Either half of the first run is still owed (PRD-34 + PRD-18).
    private var showsFirstRun: Bool { !model.welcomeSeen || !model.helpSeen }

    /// A compose is running, so `AppModel.compose` will refuse another one.
    ///
    /// This is shown rather than silently swallowed, and PRD-17 is why. The
    /// guard is old — `compose` has always dropped a second request — but until
    /// Nocturne every compose was sub-second in Release, so the dead window was
    /// invisible. Nocturne's p99 is ~11 s on a Mac and an estimated ~34 s on a
    /// phone (DEVIATIONS), and a shelf where Today and three other cards look
    /// live and ignore taps for half a minute is not a calm app, it is a broken
    /// one. Dimming makes the wait legible instead of making the app feel dead.
    private var composeInFlight: Bool { model.composing != nil }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                ScrollView {
                    // PRD-31. On a window wide enough for the drafting table,
                    // the shelf splits rather than sitting as a 560pt ribbon in
                    // the middle of 800pt of nothing. The split is decided by
                    // the *same* function the game screen uses — one answer to
                    // "is this a regular-width window", so the two screens can
                    // never disagree about whether a window is one, and Stage
                    // Manager gets the composition right on both at once.
                    if BoardCompositionRules
                        .resolve(width: Double(geo.size.width),
                                 height: Double(geo.size.height)).table != nil {
                        shelfPair
                    } else {
                        shelfColumn
                    }
                }
                // Above the `ScrollView`'s own content and simultaneous with it, so
                // the shelf still scrolls vertically and the six cards still take
                // taps. See `pageTurnGesture` for the three traps.
                .simultaneousGesture(pageTurnGesture)
            }
            // The scrim swallows touches, but a hit-test is not the whole
            // story: left in the tree, the shelf's six buttons interleave with
            // the lesson's own sentences by y-position (measured), and a
            // VoiceOver or Switch Control activation of "Today" would start a
            // board out from under a first run that is still owed.
            .accessibilityHidden(showsFirstRun)
            // PRD-34 + PRD-18: one first run, two beats at most — the welcome
            // ledger and the playable first flick. The old legend card is gone;
            // the touch grammar it listed lives in Settings ▸ How to play.
            if showsFirstRun {
                FirstRunFlow(model: model, accent: accent)
                    .transition(.opacity)
            }
        }
        .animation(.couchFast, value: model.welcomeSeen)
        .animation(.couchFast, value: model.helpSeen)
        .animation(.couchFast, value: model.pendingGraceDay)
        .overlay { GlassSheet(isPresented: $showHistory) { HistorySheetContent(model: model) } }
        .overlay { GlassSheet(isPresented: $showBoards) { BoardsSheetContent(model: model, onClose: { showBoards = false }) } }
        .overlay {
            GlassSheet(isPresented: $showArchive) {
                ArchiveSheetContent(model: model, onClose: { showArchive = false })
            }
        }
        .overlay {
            if showTutorial {
                TutorialView(accent: accent) {
                    showTutorial = false
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if showSchool {
                SchoolView(model: model, accent: accent) { showSchool = false }
                    .transition(.opacity)
            }
        }
        .animation(.couchFast, value: showTutorial)
        .animation(.couchFast, value: showSchool)
    }

    /// The phone's shelf. Classic's page is unchanged below the pager rail.
    private var shelfColumn: some View {
        VStack(spacing: 20) {
            header
            ChannelPagerRail(model: model, accent: accent)
            if let ledgered = model.channel.ledgered {
                ChannelShelfContent(model: model, channel: ledgered, accent: accent)
            } else {
                graceCard
                todayCard
                continueCard
                boardsSection
                freePlayRow
                learnRow
            }
        }
        .padding(20)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity) // center the column on iPad
    }

    // MARK: The page-turn (PRD-24)

    /// **This release's one new input concept, and the only one it spends.**
    ///
    /// `Sources/` contained zero `TabView`s, zero horizontal `ScrollView`s and zero
    /// `scrollTargetBehavior`s before this, so a page-turn is genuinely new — and it
    /// is paid for by the rose being untouched across every variant, which
    /// `VariantInputSealTests` now enforces permanently. It is on the *shelf* only,
    /// where nothing is at stake: no gesture is added to the game screen and there
    /// is no fifth control button.
    ///
    /// Three traps, each of them documented elsewhere in this file or the next one
    /// by someone who hit it:
    ///
    ///  1. **`.simultaneousGesture`, not `.gesture`.** A `DragGesture` that claims
    ///     the stroke exclusively takes the vertical scroll with it and the shelf
    ///     stops scrolling. Attached in the same position and for the same reason
    ///     the game screen attaches its drawer gesture above its own scrim
    ///     (`boardColumn`, "so the drawer's own scrim is a child").
    ///  2. **Horizontal dominance is checked, not assumed.** A stroke is a page-turn
    ///     only when it is more sideways than not; anything else is left to the
    ///     `ScrollView` untouched. Without this, scrolling the shelf at a slight
    ///     angle turns the page.
    ///  3. **`DragGesture.translation` is not RTL-mirrored** — `FlickRoseView:128`
    ///     is where that was found, and it cost PRD-20 a rose that read
    ///     `3 2 1 / 6 5 4 / 9 8 7` in Arabic. Pages are laid out in reading order,
    ///     so under RTL a leftward stroke moves *back*. Resolved against the
    ///     environment rather than pinned, because a pager genuinely should mirror
    ///     — unlike the rose, whose petal order must not.
    private static let pageTurnDistance: CGFloat = 24

    private var pageTurnGesture: some Gesture {
        DragGesture(minimumDistance: Self.pageTurnDistance)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy), abs(dx) >= Self.pageTurnDistance else { return }
                let backwards = layoutDirection == .rightToLeft ? dx > 0 : dx < 0
                withAnimation(.couchFast) { model.turnShelf(by: backwards ? 1 : -1) }
            }
    }

    /// Two columns for a regular-width window (PRD-31).
    ///
    /// The split is by *kind*, not by height: the leading column is the boards
    /// you have — today, the grace card, what you were in the middle of, the
    /// tracker — and the trailing column is the boards you could start plus the
    /// ways to learn. So the eye goes left for "where was I" and right for
    /// "what now", which is the same question order the phone asks by scrolling.
    ///
    /// The header spans both, because a wordmark that sat in one column would
    /// read as that column's title.
    /// **`fixedSize(vertical:)` on each column is load-bearing, and driving the
    /// iPad is what found that.** `todayCard` carries `minHeight: 130` with no
    /// maximum, which makes it flexible *upward* — it accepts any height it is
    /// offered. On the phone that has never shown, because a `ScrollView`
    /// proposes nil and every child settles at its ideal size. Put the card in
    /// an `HStack` beside a taller column and the column is suddenly given a
    /// concrete height, `VStack` divides the surplus between the card and the
    /// trailing `Spacer`, and Today inflates to half the screen. A latent
    /// property of shipped code that only a second column could expose.
    private var shelfPair: some View {
        VStack(spacing: 20) {
            header
            ChannelPagerRail(model: model, accent: accent)
            if let ledgered = model.channel.ledgered {
                // A channel page is one column's worth of cards, so in the
                // two-column composition it takes the leading column and the
                // trailing one holds the ways to learn — which are channel-agnostic
                // and belong on every page. `fixedSize(vertical:)` on both for
                // PRD-31's reason: Today carries `minHeight` with no maximum and
                // inflates to half the screen without it.
                HStack(alignment: .top, spacing: 20) {
                    ChannelShelfContent(model: model, channel: ledgered, accent: accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .top)
                    VStack(spacing: 20) { learnRow }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 20) {
                        graceCard
                        todayCard
                        continueCard
                        boardsSection
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .top)
                    VStack(spacing: 20) {
                        freePlayRow
                        learnRow
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 1080)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            // The wordmark, not a word — see `ShareCardMetrics.wordmark`.
            Text(verbatim: Phrase.wordmark)
                .couchText(CouchTypography.title)
            Spacer()
            if model.totalPoints > 0 {
                GlassChip(Phrase.points(model.totalPoints), systemImage: "star.fill")
            }
            // The streak belongs to the page you are on (PRD-24). Classic reads
            // `nine.streak`; a channel reads its own slot in `nine.channels`, and
            // there is no argument that would make either read the other.
            if let ledgered = model.channel.ledgered {
                if model.displayedStreak(on: ledgered) > 0, !model.focus.hidesStreak {
                    StreakChip(days: model.displayedStreak(on: ledgered),
                               held: model.streakHeld(on: ledgered))
                }
            } else if model.displayedStreak > 0 {
                // A Focus filter can take the count away entirely (PRD-33).
                // `if` rather than `.opacity(0)`: an invisible chip still holds
                // its space and still speaks to VoiceOver.
                if !model.focus.hidesStreak {
                    StreakChip(days: model.displayedStreak, held: model.streakHeld)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: Learn + records

    /// Three across, matching the free-play row above it. School joins the
    /// tutorial and the records rather than hiding inside the tutorial: it is
    /// a place a player returns to, and the tutorial is a thing you do once.
    private var learnRow: some View {
        HStack(spacing: 14) {
            TouchCard(action: { showTutorial = true }) {
                VStack(spacing: 10) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(Strings.string("tutorial.title"))
                        .font(CouchTypography.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 74)
            }
            TouchCard(action: { showHistory = true }) {
                VStack(spacing: 10) {
                    Image(systemName: "trophy")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(Strings.string("history.title"))
                        .font(CouchTypography.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 74)
            }
            TouchCard(action: { showSchool = true }) {
                VStack(spacing: 10) {
                    Image(systemName: "graduationcap")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(Strings.string("school.title"))
                        .font(CouchTypography.caption)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 74)
            }
        }
    }

    // MARK: Streak grace

    /// PRD-13 §3. The morning after a bridged miss: one sentence, once ever per
    /// bridge, and then gone forever.
    ///
    /// It sits directly under the header on purpose — the shield it is
    /// explaining is one row above it, and the adjacency *is* the explanation.
    ///
    /// Deliberately not a card that starts a board. An action here would turn
    /// the missed day into a prompt to play, which is the nagging PRD-13 exists
    /// so the app never has to do; PRD-30 cites this feature by name as the
    /// reason Live Activities will never carry a streak-endangered warning.
    /// Tapping it only makes it go away.
    @ViewBuilder
    private var graceCard: some View {
        if model.pendingGraceDay != nil {
            Button {
                withAnimation(.couchFast) { model.acknowledgeGrace() }
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(accent)
                        .accessibilityHidden(true) // decoration; the sentence says it
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Phrase.graceTitle)
                            .font(CouchTypography.body)
                        Text(Phrase.graceBody)
                            .font(CouchTypography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .couchGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Phrase.graceLabel)
            .accessibilityHint(Phrase.graceHint)
            .transition(.opacity)
        }
    }

    // MARK: Today

    private var todayCard: some View {
        TouchCard(action: { model.openToday() }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Strings.string("shelf.today.title"))
                    .couchText(CouchTypography.title)
                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                todayStatus
            }
            // Room for the archive glyph, so a long status line never runs
            // under it.
            .padding(.trailing, 44)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        }
        // Composing the daily is its own state on this card, so only a *foreign*
        // compose disables it.
        .disabled(composeInFlight && !isComposingDaily)
        // PRD-14. An **overlay on** the card, never a button **inside** it: a
        // Button nested in `TouchCard`'s Button is merged by SwiftUI, and the
        // merge takes the inner frame — measured live, the Today card's own
        // accessibility element collapsed from 89×129 to the glyph's 44×44 and
        // the archive button disappeared from the tree entirely. Nothing on
        // screen changes when that happens, which is exactly the failure
        // EXECUTING-A-PRD §4 exists for. As an overlay the two are siblings.
        //
        // (The Continue card's discard ✕ is nested and has the same defect —
        // its own element is absent from `home.txt` too. Out of scope here, and
        // recorded in DEVIATIONS.)
        .overlay(alignment: .topTrailing) {
            Button { showArchive = true } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(.accessibility, Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.string("archive.title"))
            .accessibilityHint(Strings.string("shelf.archive.hint"))
            .padding(.trailing, 8)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var todayStatus: some View {
        if isComposingDaily {
            statusLabel(Strings.string("status.composing"), symbol: "sparkles")
        } else if model.todaySolved {
            statusLabel(Strings.string("status.solved"), symbol: "checkmark.circle.fill")
        } else if let daily = model.savedDaily {
            HStack(spacing: 12) {
                BoardFingerprint(game: daily, accent: accent, side: 34)
                // The constellation stays and the number goes (PRD-33). What
                // `hidesDaily` is for is the *urgency* of an unfinished board,
                // and "64%" is where the urgency lives — the fingerprint says
                // "there is a board here" without saying how much you owe it.
                if !model.focus.hidesDaily {
                    Text(Strings.string("shelf.today.continueProgress",
                                        .text(BoardProgressCaption.text(for: daily))))
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            statusLabel(Strings.string("shelf.today.oneADay"), symbol: "sun.max")
        }
    }

    // MARK: Continue (free play in progress)

    @ViewBuilder
    private var continueCard: some View {
        if let (game, difficulty) = model.savedFree {
            TouchCard(action: { model.continueSaved() }) {
                HStack(spacing: 16) {
                    BoardFingerprint(game: game, accent: accent, side: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Strings.string("shelf.continue.title"))
                            .font(CouchTypography.body)
                        Text(Phrase.continueCaption(
                            difficulty: Strings.difficulty(difficulty),
                            progress: BoardProgressCaption.text(for: game),
                            others: model.extraPartialCount))
                            .font(CouchTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Abandon the board: frees the slot so a fresh difficulty
                    // doesn't feel like a betrayal of this one.
                    Button {
                        withAnimation(.couchFast) { model.discardSaved() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Strings.string("shelf.continue.discard"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Boards tracker

    /// Partials not already surfaced by the Today card (in-progress daily) or
    /// the Continue card (newest free partial) — the "extra" boards.
    private var extraPartials: [LibraryEntry] {
        let today = model.todayOrdinal
        let continueID = model.freePartials.first?.id
        return model.partials.filter { entry in
            if entry.id == continueID { return false }
            if case .daily(let day) = entry.kind, day == today { return false }
            return true
        }
    }

    @ViewBuilder
    private var boardsSection: some View {
        if !extraPartials.isEmpty || !model.playedBoards.isEmpty {
            VStack(spacing: 10) {
                HStack {
                    Text(Strings.string("boards.title"))
                        .font(CouchTypography.body)
                    Spacer()
                    Button { showBoards = true } label: {
                        Text(Strings.string("shelf.boards.seeAll"))
                            .font(CouchTypography.caption)
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Strings.string("shelf.boards.seeAllLabel"))
                }
                ForEach(extraPartials.prefix(3)) { entry in
                    TouchCard(action: { model.resumeEntry(id: entry.id) }) {
                        HStack(spacing: 14) {
                            BoardFingerprint(game: entry.game, accent: accent, side: 34)
                            Text(boardTitle(entry))
                                .font(CouchTypography.caption)
                            Spacer()
                            Text(BoardProgressCaption.text(for: entry.game))
                                .font(CouchTypography.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func boardTitle(_ entry: LibraryEntry) -> String {
        switch entry.kind {
        // The daily's own day, not `createdAt` — the second of the two places
        // that made the same assumption (PRD-14; see `BoardsSheet.title`).
        case .daily(let day):
            return Strings.string("shelf.daily.date",
                                  .text(ArchiveCalendar.mediumLabel(forDayOrdinal: day)))
        case .free(let difficulty): return Strings.difficulty(difficulty)
        // A channel board names its channel first, because that is what makes it a
        // different board rather than a harder one. A channel daily gets the date
        // treatment its classic sibling gets; free play gets its tier.
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

    // MARK: Free play

    private var freePlayRow: some View {
        // Three across, then the deep end on its own lines (PRD-17 §3, widened
        // by PRD-25). Not a hierarchy — a fourth column on a 393pt iPhone
        // leaves each card ~90pt for a title plus a two-line blurb, which
        // truncates all four rather than just the new one. Full width is what
        // lets a deep band keep the same blurb the three above it get, and it
        // is why three of them stack rather than becoming a second row.
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ForEach(Difficulty.rowBands, id: \.self) { difficulty in
                    difficultyCard(difficulty)
                }
            }
            ForEach(Difficulty.deepBands, id: \.self) { difficulty in
                deepEndCard(difficulty)
            }
        }
    }

    /// The full-width Nocturne card: same tap target, same MiniBoard, laid out
    /// along the row instead of down a column. No lock, no badge, no price —
    /// it is a peer of the three above it and reads like one.
    private func deepEndCard(_ difficulty: Difficulty) -> some View {
        TouchCard(action: { model.startFree(difficulty) }) {
            HStack(spacing: 14) {
                MiniBoard(difficulty: difficulty, accent: accent)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(Strings.difficulty(difficulty))
                    } icon: {
                        if let glyph = difficulty.glyph { Image(systemName: glyph) }
                    }
                    .font(CouchTypography.caption)
                    .foregroundStyle(.primary)
                    // The composing caption replaces the blurb rather than
                    // stacking under it: a card that grows a line mid-compose
                    // shoves the rest of the shelf down while the player watches.
                    Text(model.composing == .free(difficulty)
                         ? (difficulty.composeCaption ?? Strings.string("status.composing"))
                         : difficulty.blurb)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .disabled(composeInFlight && model.composing != .free(difficulty))
        .accessibilityLabel(Strings.string("shelf.difficulty.label",
                                           .text(Strings.difficulty(difficulty)),
                                           .text(difficulty.blurb)))
    }

    private func difficultyCard(_ difficulty: Difficulty) -> some View {
        TouchCard(action: { model.startFree(difficulty) }) {
            VStack(spacing: 10) {
                MiniBoard(difficulty: difficulty, accent: accent)
                    .frame(width: 64, height: 64)
                if model.composing == .free(difficulty) {
                    statusLabel(Strings.string("status.composing"), symbol: "sparkles")
                } else {
                    Text(Strings.difficulty(difficulty))
                        .font(CouchTypography.caption)
                        .foregroundStyle(.primary)
                    Text(difficulty.blurb)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 124)
        }
        .disabled(composeInFlight && model.composing != .free(difficulty))
    }

    // MARK: Helpers

    private func statusLabel(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(CouchTypography.caption)
        }
        .foregroundStyle(.secondary)
    }

    /// **Today's** daily, not any daily. Since PRD-14 a `.daily(day:)` compose
    /// may be for 12 July, and matching the case alone made the Today card
    /// announce "Composing…" for a board that is not its own — then hand the
    /// player a different day when it landed.
    private var isComposingDaily: Bool {
        if case .daily(let day)? = model.composing { return day == model.todayOrdinal }
        return false
    }
}

/// A tappable glass slab: the touch counterpart of the TV shelf card.
/// A Button (not a bare tap gesture) so it gets pressed feedback and the
/// full accessibility treatment for free.
///
/// Internal rather than private since PRD-24: the channel shelf lives in
/// `ChannelShelf.swift` (a new file, because `TouchUI.swift` is the file-contention
/// hotspot `EXECUTING-A-PRD` §7 names) and uses the same chrome. Sharing the type
/// is strictly better than a second copy of it — a shelf where one page's cards
/// press differently from another's is the kind of drift nobody notices in review
/// and everybody feels.
struct TouchCard<Content: View>: View {
    let action: @MainActor () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .padding(18)
                .couchGlassInteractive(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(TouchCardStyle())
    }
}

struct TouchCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.couchFast, value: configuration.isPressed)
    }
}

// MARK: - Game

struct TouchGameScreen: View {
    let model: AppModel

    @State private var cursor = 40
    @State private var rose: RoseState?
    @State private var pencilMode = false
    @State private var showPrefs = false
    @State private var toast: UndoToastState?
    @State private var toastDismissal: Task<Void, Never>?
    /// The one tip this session may spend (PRD-34), and the two "they already
    /// know this" latches that keep it from teaching what the player is doing.
    @State private var tip: NineTip?
    @State private var tipDismissal: Task<Void, Never>?
    @State private var pencilEverToggled = false
    @State private var highlightEverUsed = false
    /// The hint on screen, if any (PRD-11). Held here rather than in AppModel
    /// because a card is a presentation: dismissing it changes no board state,
    /// and nothing about it should survive leaving the screen.
    @State private var coachAdvice: CoachAdvice?
    /// The why-chain on screen (PRD-25), held here for `coachAdvice`'s reason:
    /// a narration is a presentation. Two states rather than one enum, because
    /// a refusal has no beats to page through and folding them together would
    /// give every read site an emptiness check it would eventually forget.
    @State private var why: WhyNarration?
    @State private var whyRefusal: WhyRefusal?
    /// Where the finger last went down, for the long press.
    ///
    /// **`LongPressGesture` reports no location** — it is the one gesture in
    /// SwiftUI that tells you *that* it happened and not *where* — so the point
    /// has to come from a zero-distance `DragGesture` running beside it.
    ///
    /// The first version sequenced the two (`longPress.sequenced(before: drag)`)
    /// and read `startLocation` off the sequence's second phase. It never
    /// fired: a press-and-hold that does not move produces `.second(true, nil)`
    /// and no drag value at all, so the point stayed `.zero` and `askWhy` was
    /// asked about a cell off the top-left corner of the board. Found by
    /// long-pressing a real board on a simulator, and by nothing else — it
    /// compiles, it type-checks, and it silently does nothing.
    ///
    /// Plain `@State`, and the ordering is what makes it safe: the drag's
    /// `onChanged` fires at touch-down, ~0.45 s before the long press can
    /// succeed, so the point a completed press reads is always that press's
    /// own. An abandoned press leaves a stale point that nothing reads.
    @State private var pressPoint: CGPoint = .zero
    /// The one chip auto notes shows when it fills a board.
    @State private var autoNotesChip: String?
    @State private var chipDismissal: Task<Void, Never>?
    /// Same-number highlight: the digit currently lit across the board.
    /// Sticky on purpose — it survives placements so you can chase one
    /// number around the grid; tapping a cell of the same digit clears it.
    @State private var highlightedDigit: Int?
    /// Pull-down stats drawer (PRD-10 follow-up). Snapped-open state, the
    /// live finger offset on top of it, and the panel's measured height —
    /// the three together give `drawerProgress`, which drives every pixel.
    @State private var drawerOpen = false
    /// Gesture-owned, not `@State`: SwiftUI restores it on cancellation as
    /// well as on end, and a pull-down that starts at the screen edge is
    /// exactly the stroke Notification Center likes to steal mid-flight —
    /// which delivers no `onEnded` and would strand a half-open scrim.
    @GestureState private var drawerDrag: CGFloat = 0
    /// Placeholder until the panel reports its real height. Only read while
    /// the drawer is visible, and by then the measurement has landed.
    @State private var drawerHeight: CGFloat = 220
    /// PRD-26's debrief. The exact mirror of the drawer above — snapped state,
    /// live finger offset, measured height — pulled from the **opposite** edge
    /// on purpose: the drawer comes down from the top, so an upward drag from
    /// the bottom cannot be confused with it and cannot fire it by accident.
    @State private var debriefOpen = false
    @GestureState private var debriefDrag: CGFloat = 0
    @State private var debriefHeight: CGFloat = 420
    /// Afterglow: the haptic score and the gravity-tilt source live in the
    /// view layer — AppModel is platform-shared logic; this is presentation.
    /// The rendered share card (PRD-12), written once per solve.
    ///
    /// Nil while it renders, and nil forever if rendering failed — in which
    /// case the button simply never appears. That is the right failure for a
    /// feature whose whole discipline is that it waits and never asks: an
    /// error toast about a share nobody requested would be worse than silence.
    @State private var shareCard: ShareCardExport?
    /// PRD-31. The cell under the pointer or the hovering Pencil tip, drawn as
    /// the halo `BoardView` has had since PRD-4 and the Mac has been the only
    /// caller of. An iPad with a trackpad or a hovering Pencil is the same
    /// situation the Mac was in and got the same answer.
    @State private var hoverCell: Int?
    /// The petal the tip is over, previewed as a ghost digit in the cursor
    /// cell. `BoardView.previewDigit` has existed since tvOS's pad rose and has
    /// been dead on iOS — hover is what finally arms it.
    @State private var hoverDigit: Int?
    /// Apple Pencil handwriting (PRD-31), the release's one new input concept.
    @State private var scribe = PencilScribe()
    @FocusState private var boardFocused: Bool
    @State private var haptics = AfterglowHaptics()
    @State private var motion = AfterglowMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    /// The accent resolved for the theme's leaning (themes pin the scheme).
    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    /// Is one of the four surfaces that cover the board up right now (Task 4;
    /// user-confirmed set)? Drives the `.sheet` clock hold from one place
    /// instead of eight scattered `holdClock`/`releaseClock` calls at each
    /// flag's own toggle site.
    ///
    /// Deliberately **not** `rose`, `toast`, `tip` or `autoNotesChip`: the rose
    /// is ordinary digit entry, and pausing there would stop the clock during
    /// normal play; the other three are transient chrome that never covers
    /// the board. Also deliberately not `debriefOpen`: the debrief is
    /// post-solve, where the timer is already stopped by `finishSolve`, so
    /// holding for it would just be a no-op that has to be reasoned about.
    private var boardCoveringSurfaceUp: Bool {
        showPrefs || drawerOpen || coachAdvice != nil || why != nil || whyRefusal != nil
    }

    var body: some View {
        GeometryReader { geo in
            // PRD-31. The composition is a function of the *window*, never of
            // the device: a size class calls a 1000pt Stage Manager tile and a
            // 1366pt full-screen iPad by the same name, and only one of them
            // can seat a rail beside a full board. `DraftingTableTests` sweeps
            // the whole decision on Linux.
            let composition = BoardCompositionRules.resolve(
                width: Double(geo.size.width), height: Double(geo.size.height))
            Group {
                if let table = composition.table {
                    draftingTable(table, in: geo.size)
                } else {
                    boardColumn(side: CGFloat(composition.boardSide), in: geo.size)
                }
            }
            .onChange(of: model.solvedAt) { renderShareCard() }
            // Above the board and its chips, below the prefs sheet.
            .overlay { coachView }
            .overlay { whyView }
            .overlay {
                // PRD-34: no `onNewGame` — the next board lives on the shelf,
                // in the Boards sheet, and in the post-solve "Another" chip.
                GlassSheet(isPresented: $showPrefs) {
                    PrefsSheetContent(model: model)
                }
            }
        }
        // PRD-31 keyboard parity. An iPad in a Magic Keyboard had none of the
        // Mac's grammar — no arrows, no digits, no ⇧-digit note, no
        // Tab-to-next-empty — and `BoardKeys` is now compiled for both, so this
        // is the whole of it. `.focusEffectDisabled` because a focus ring
        // belongs on a control and this is a whole screen.
        //
        // **Outside the `GeometryReader`, and that is not cosmetic.** Inside,
        // the focusable surface is rebuilt on every geometry change and the
        // `@FocusState` set in `onAppear` never survives to see a keystroke:
        // the log shows `Keyboard receives keyEvent` and the cursor does not
        // move. `MacUI` has carried the same three lines outside its own
        // `GeometryReader` since PRD-4, under a comment about "focus wars",
        // and this is that comment being right a second time.
        .focusable()
        .focusEffectDisabled()
        .focused($boardFocused)
        .onKeyPress { press in handleKey(press) ? .handled : .ignored }
        .onAppear { boardFocused = true }
        // A hint describes one position, so any move makes it stale. Retiring
        // it beats leaving a card on screen that is quietly no longer true.
        .onChange(of: model.game?.entries) { _, _ in
            if coachAdvice != nil { dismissCoach() }
            // A derivation describes one position too, and more sharply: its
            // whole subject is what a square's candidates are right now.
            if why != nil || whyRefusal != nil { dismissWhy() }
        }
        .onChange(of: model.solvedAt) { _, solved in
            guard solved != nil else { return }
            // The haptic score plays even under Reduce Motion (haptics are
            // not motion; platform convention) — the gyro trophy does not.
            haptics.playSolveScore()
            if !reduceMotion { motion.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if model.solvedAt != nil, !reduceMotion { motion.start() }
            } else {
                haptics.stop()
                motion.stop()
            }
        }
        // Task 4c: the clock must run only while the board is actually
        // visible. One `onChange` on the folded Bool rather than a
        // hold/release pair at each of the four flags' own toggle sites —
        // whichever of them opens or closes, this is the one place that
        // reacts.
        .onChange(of: boardCoveringSurfaceUp) { _, covering in
            if covering {
                model.holdClock(.sheet)
            } else {
                model.releaseClock(.sheet)
            }
        }
        .onDisappear {
            haptics.stop()
            motion.stop()
            // A half-written glyph must not survive the screen it was written
            // on: the pending commit holds a cell index, and the next board has
            // a different digit in it.
            scribe.cancel()
            hoverCell = nil
            hoverDigit = nil
            // Cleared, not just cancelled: the timer that would have retired
            // this chip is gone, so leaving `tip` set would strand it on the
            // next appearance of this screen with nothing left to dismiss it.
            tipDismissal?.cancel()
            tip = nil
            chipDismissal?.cancel()
            autoNotesChip = nil
            coachAdvice = nil
            why = nil
            whyRefusal = nil
        }
    }

    // MARK: The two compositions (PRD-31)

    /// Where the floating chrome parks. Column mode dodges the horizontal
    /// control bar; the drafting table has none to dodge, because its controls
    /// are a column off to the side.
    private struct ChromeInsets {
        var chip: CGFloat
        var completion: CGFloat
        var top: CGFloat
        var debriefGrabber: CGFloat

        static func column(controlsAtBottom: Bool) -> ChromeInsets {
            ChromeInsets(chip: controlsAtBottom ? 84 : 20,
                         completion: controlsAtBottom ? 128 : 64,
                         top: controlsAtBottom ? 12 : 64,
                         debriefGrabber: controlsAtBottom ? 108 : 44)
        }

        static let table = ChromeInsets(chip: 20, completion: 64, top: 12, debriefGrabber: 44)
    }

    /// The phone's stack, unchanged: bands around the board, a horizontal
    /// control bar at one edge, and a stats drawer you find by pulling down.
    private func boardColumn(side: CGFloat, in size: CGSize) -> some View {
        let controlsAtBottom = model.prefs.controlsAtBottom
        let inset = CGFloat(BoardCompositionRules.boardInset)
        let freeSpace = size.height - (side + 2 * inset + 16) - 76
        return chromed(
            VStack(spacing: 12) {
                if controlsAtBottom {
                    band(.top, freeSpace: freeSpace)
                    boardArea(side: side, inset: inset)
                    band(.bottom, freeSpace: freeSpace)
                    controlBar
                } else {
                    controlBar
                    band(.top, freeSpace: freeSpace)
                    boardArea(side: side, inset: inset)
                    band(.bottom, freeSpace: freeSpace)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity),
            insets: .column(controlsAtBottom: controlsAtBottom),
            revealHeight: size.height,
            controlBarReserve: controlsAtBottom ? Self.controlBarReserve : 0
        )
        // The grabber sits *under* the drawer it advertises, so the panel
        // slides over it rather than the hairline floating on the glass.
        .overlay(alignment: .top) { drawerGrabber }
        // Above the board and its chips, below the prefs sheet — Settings
        // must always stack over the drawer, never under it.
        .overlay(alignment: .top) { statsDrawer }
        // Attached *above* the drawer overlay, so the drawer's own scrim
        // is a child of the gesture rather than a lid over it — one
        // gesture drives both the pull-down and the drag-up dismiss.
        //
        // Simultaneous, not a blocking strip across the top: a hit-testing
        // overlay there would swallow control-bar taps whenever the bar is
        // the top row (`controlsAtBottom == false`).
        .simultaneousGesture(drawerRevealGesture)
        // The drawer is otherwise reachable only by an unhinted pull-down,
        // so VoiceOver gets a named action. It must honour the same guards
        // as the drag: opening it under the prefs sheet would scrim the
        // screen from below, and opening it with no game would measure a
        // height off an empty panel.
        //
        // **This lives here rather than beside the debrief's action**, so the
        // drafting table does not carry it. An action named "Show board stats"
        // on a screen where the stats are already on screen, permanently, does
        // nothing — which is exactly the defect `ax-snapshot.py` found in
        // PRD-26's rotor and the reason that one is an `accessibilityActions`
        // builder. The cheapest way not to register a useless action is not to
        // be in the composition that would.
        .accessibilityAction(named: Text(Strings.string(
            drawerOpen ? "game.drawer.hide" : "game.drawer.show"))) {
            guard drawerOpen || (rose == nil && !showPrefs && model.game != nil) else { return }
            if !drawerOpen { model.noteDrawerFound() }
            withAnimation(.couchFast) { drawerOpen.toggle() }
        }
    }

    /// PRD-31's drafting table: controls in a column at the leading edge, the
    /// board centre stage, the stats as a rail that is simply *there*.
    ///
    /// Controls lead and stats trail, and the sides are not interchangeable.
    /// The rail is the thing you glance at, and glancing is cheaper on the side
    /// your writing hand is not covering; the controls are the thing you reach
    /// for, and reaching across the board with a Pencil in your hand drags your
    /// wrist over the grid you are reading. (Left-handed players get the worse
    /// half of that, which is recorded in DEVIATIONS rather than solved: a
    /// handedness pref is a settings row, and the covenant makes those
    /// expensive.)
    private func draftingTable(_ table: DraftingTable, in size: CGSize) -> some View {
        let padding = CGFloat(table.outerPadding)
        let inset = CGFloat(BoardCompositionRules.boardInset)
        // `.top`, so the rail can be as tall as its own content. Both other
        // columns claim `maxHeight: .infinity` and so fill regardless.
        return HStack(alignment: .top, spacing: CGFloat(table.gutter)) {
            controlColumn
                .frame(width: CGFloat(table.controlColumnWidth))
                .frame(maxHeight: .infinity)
            chromed(
                boardArea(side: CGFloat(table.boardSide), inset: inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity),
                insets: .table,
                revealHeight: size.height - 2 * padding,
                // No horizontal control bar to keep the pull-up away from —
                // this is the reserve that PRD-26 discovered *was* the whole
                // gesture band on the phone.
                controlBarReserve: 0
            )
            statsRail(width: CGFloat(table.railWidth))
        }
        .padding(padding)
    }

    /// Everything that floats over the board, in whichever composition is up.
    ///
    /// One stack shared by both arms rather than two lists that would drift:
    /// the toast, the tip, the completion chip, the auto-notes chip, the
    /// composing/archive chip and PRD-26's whole pull-up are identical in
    /// meaning on a phone and on a drafting table, and only their insets differ.
    private func chromed(
        _ content: some View,
        insets: ChromeInsets,
        revealHeight: CGFloat,
        controlBarReserve: CGFloat
    ) -> some View {
        content
            .overlay(alignment: .bottom) { toastView.padding(.bottom, insets.chip) }
            .overlay(alignment: .bottom) { tipView.padding(.bottom, insets.chip) }
            .overlay(alignment: .bottom) { completionChip.padding(.bottom, insets.completion) }
            .overlay(alignment: .bottom) { autoNotesChipView.padding(.bottom, insets.chip) }
            .overlay(alignment: .top) { composingChip.padding(.top, insets.top) }
            // The debrief's twin at the drawer's other edge, in the same order
            // and for the same reason: the hint under the panel it advertises.
            .overlay(alignment: .bottom) {
                debriefGrabber.padding(.bottom, insets.debriefGrabber)
            }
            .overlay(alignment: .bottom) { debriefPanel }
            // The flexible bands around the board are `Color.clear`, which
            // SwiftUI does not hit-test, so without a content shape the whole
            // reveal band is a hole and the pull-up never starts. Claiming
            // the frame costs nothing: children (board, control bar, scrim)
            // are hit-tested first, and nothing else wants the empty space.
            .contentShape(Rectangle())
            .simultaneousGesture(debriefRevealGesture(height: revealHeight,
                                                      reserve: controlBarReserve))
            // The debrief's named action, because a 3 pt hairline is not an
            // accessibility affordance and a pull-up with no keyboard or
            // VoiceOver route would be a feature only sighted touch users have.
            //
            // **`accessibilityActions` (plural), and that is not a style
            // choice.** `accessibilityAction(named:)` registers the action
            // whatever the view's state, so a guard inside the closure is a
            // guard on the *effect* and not on the action's existence — which
            // put "Show your solve" in the rotor of all 81 cells of every
            // unsolved board, doing nothing. Invisible to every screenshot and
            // every unit test; `ax-snapshot.py` is what found it. The plural
            // form takes a `ViewBuilder`, so the `if` is real.
            .accessibilityActions {
                if debrief != nil {
                    Button(debriefOpen ? DebriefPhrase.close : DebriefPhrase.open) {
                        withAnimation(.couchFast) { debriefOpen.toggle() }
                    }
                }
            }
    }

    /// The stats drawer with the drawer taken off it (PRD-31).
    ///
    /// This is the same `StatsDrawerContent` the pull-down shows, at the same
    /// width, in the same glass — the panel is not redesigned for the iPad, it
    /// is simply left open. PRD-34 spent a hairline grabber and three sessions
    /// of its budget teaching people that the drawer exists; at this width the
    /// geometry says it instead, for free and permanently, which is the whole
    /// argument for the composition.
    private func statsRail(width: CGFloat) -> some View {
        VStack(spacing: 14) {
            // The chips the phone parks in its free bands have no bands here,
            // and the rail is where they belong: the timer is already one of
            // the drawer's own tiles, and the ambient slot is ambient.
            if model.prefs.ambientSlot != .none, model.composing == nil {
                AmbientSlotView(model: model)
            }
            timerChip
            StatsDrawerContent(model: model)
        }
        .padding(16)
        // **As tall as it has to be, and no taller.** The first version was a
        // full-height slab, and driving an 11" iPad showed what that is: 200 pt
        // of stats above 700 pt of empty glass, which reads as a panel that
        // failed to load rather than as a rail. A drawer is the height of what
        // is in it; leaving it open should not change that.
        .frame(width: width, alignment: .top)
        .couchGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        // One container, so Switch Control's group scan treats the rail as a
        // place rather than as fourteen loose elements between the board and
        // the edge of the screen (PRD-19's grouping rule).
        .accessibilityElement(children: .contain)
    }

    // MARK: Chrome

    /// Six buttons now (PRD-11 added the lightbulb and the wand), which is two
    /// past what PROGRAM-2.0's anti-bloat constitution allows — a deliberate
    /// override, recorded in DEVIATIONS.md.
    ///
    /// It cost the timer its seat. The rule turns out not to be only an
    /// aesthetic one: six 44pt targets are 264pt, the timer chip measures ~82,
    /// and with gaps and padding the row wanted ~422pt — wider than any iPhone,
    /// and measured clipping `Settings` 20pt off a 375pt SE *and* 2pt off a
    /// 393pt iPhone 17. Shrinking the targets was never an option (the craft
    /// charter's 44pt floor), so the timer moved to the free band, which PRD-2
    /// sized for exactly this kind of ambient chrome. The bar is now controls
    /// only, and 6×44 + 5×6 + padding = 322pt fits the smallest phone with
    /// 53pt to spare.
    private var controlBar: some View {
        HStack(spacing: 6) {
            homeButton
            Spacer()
            hintButton
            pencilButton
            autoNotesButton
            undoButton
            settingsButton
        }
        .padding(model.prefs.controlsAtBottom ? .bottom : .top, 8)
        .padding(.horizontal, 6)
    }

    /// The same six controls stood on end, for the drafting table (PRD-31).
    ///
    /// The arrangement is not the bar rotated. Home pins to the top, where
    /// "out of here" belongs and where a stray reach cannot find it; the five
    /// tools group at the bottom, in the arc a hand resting on the glass
    /// already sweeps. Same buttons, same labels, same 44pt targets — so
    /// VoiceOver, Voice Control and Full Keyboard Access all read a control
    /// column exactly as they read the bar.
    private var controlColumn: some View {
        VStack(spacing: 10) {
            homeButton
            Spacer(minLength: 12)
            hintButton
            pencilButton
            autoNotesButton
            undoButton
            settingsButton
        }
        .padding(.vertical, 4)
    }

    // The six, factored so the bar and the column cannot come to disagree
    // about what a control does — the failure mode a second copy invites.

    private var homeButton: some View {
        GlassIconButton(symbol: "chevron.left", label: Strings.string("game.control.home")) {
            haptics.stop()
            motion.stop()
            model.goHome()
        }
    }

    private var hintButton: some View {
        GlassIconButton(
            symbol: "lightbulb",
            label: Strings.string("game.control.hint"),
            active: coachAdvice != nil,
            accent: accent
        ) {
            toggleCoach()
        }
    }

    private var pencilButton: some View {
        GlassIconButton(
            symbol: "pencil",
            label: Strings.string("game.control.pencil"),
            active: pencilMode,
            accent: accent
        ) {
            pencilMode.toggle()
            pencilEverToggled = true
            dismissTip()
        }
    }

    private var autoNotesButton: some View {
        GlassIconButton(
            symbol: "wand.and.stars",
            label: Strings.string("game.control.autoNotes"),
            active: model.autoNotes,
            accent: accent
        ) {
            toggleAutoNotes()
        }
    }

    private var undoButton: some View {
        GlassIconButton(symbol: "arrow.uturn.backward",
                        label: Strings.string("game.control.undo")) { performUndo() }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 1.2).onEnded { _ in
                    #if DEBUG
                    model.debugFillAlmostAll() // test rig; no-op in Release
                    #endif
                }
            )
            // The one shortcut worth spending on a hardware keyboard beside the
            // `BoardKeys` grammar: ⌘Z is muscle memory everywhere else, and
            // `BoardKeys` deliberately passes ⌘-chords through untouched.
            .keyboardShortcut("z", modifiers: .command)
    }

    private var settingsButton: some View {
        GlassIconButton(symbol: "gearshape",
                        label: Strings.string("game.control.settings")) { showPrefs = true }
            .keyboardShortcut(",", modifiers: .command)
    }

    /// One of the two flexible bands around the board (PRD-2). The band on
    /// the anchored edge collapses — a zero-height element rather than
    /// nothing, so the VStack's 12pt spacing stays symmetric — and all free
    /// space collects in the other band, where a system PiP window can park.
    /// The board anchors to screen edges; the control bar never moves.
    @ViewBuilder
    private func band(_ edge: VerticalEdge, freeSpace: CGFloat) -> some View {
        let anchor = model.prefs.boardAnchor
        if (anchor == .top && edge == .top) || (anchor == .bottom && edge == .bottom) {
            Spacer().frame(height: 0)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    // The coach card parks in this same band, so the band's
                    // own chrome stands down while it is up rather than
                    // showing through the glass behind it.
                    HStack(spacing: 10) {
                        if edge == chromeEdge, coachAdvice == nil { timerChip }
                        if showAmbient(in: edge, freeSpace: freeSpace) {
                            AmbientSlotView(model: model)
                        }
                    }
                }
        }
    }

    /// The band the optional chrome lives in: opposite the anchor, and
    /// opposite the control bar on a centered board, so turning a chip on is
    /// never a silent no-op behind the controls.
    private var chromeEdge: VerticalEdge {
        switch model.prefs.boardAnchor {
        case .top: return .bottom
        case .bottom: return .top
        case .center: return model.prefs.controlsAtBottom ? .top : .bottom
        }
    }

    /// The ambient chip lives in the band opposite the anchor — opposite the
    /// control bar when centered, so turning it on is never a silent no-op —
    /// and only when the band is tall enough and the composing chip (which
    /// overlays at .top) is down.
    private func showAmbient(in edge: VerticalEdge, freeSpace: CGFloat) -> Bool {
        guard model.prefs.ambientSlot != .none, model.composing == nil,
              coachAdvice == nil else { return false }
        guard edge == chromeEdge else { return false }
        // PRD-14: the archive chip takes the same `.top` overlay slot, and
        // unlike a compose — which lasts seconds — it is up for the whole
        // board. It only stands the ambient chip down when the two would
        // actually share the top band, rather than for every archive session.
        if model.archiveDay != nil, chromeEdge == .top { return false }
        // Centered boards split the free space between both bands.
        let bandHeight = model.prefs.boardAnchor == .center ? freeSpace / 2 : freeSpace
        return bandHeight >= 100
    }

    /// While a replacement board is composed (New game in the sheet), the
    /// old board stays up — this chip is the only sign work is happening,
    /// so it matters on Sharp, which can take tens of seconds.
    @ViewBuilder
    private var composingChip: some View {
        if model.composing != nil, model.game != nil {
            GlassChip(Strings.string("status.composing"), systemImage: "sparkles")
                .transition(.opacity)
        } else if let day = model.archiveDay, model.game != nil, coachAdvice == nil {
            // PRD-14. A past day is pixel-identical to today's board, so this
            // is the only thing on screen telling the player which one they are
            // on — and, by saying "Archive" rather than a bare date, that this
            // one is not the daily their streak depends on.
            //
            // `coachAdvice == nil` for the same reason the timer chip carries
            // it: the coach card parks in the band directly under this overlay,
            // and driving the app caught the chip printed straight across the
            // card's title. A persistent chip has to yield to a card the player
            // just asked for.
            GlassChip(Strings.string("game.chip.archive",
                                     .text(ArchiveCalendar.shortLabel(forDayOrdinal: day))),
                      systemImage: "calendar")
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var timerChip: some View {
        if model.prefs.showTimer, let game = model.game, model.solvedAt == nil {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                GlassChip(SolveCardFacts.elapsedText(game.timer.elapsed(at: timeline.date)), systemImage: "clock")
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            GlassChip(toast.text, systemImage: "arrow.uturn.backward")
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .id(toast.id)
        }
    }

    /// One of three sentences a Nine install may ever say unprompted (PRD-34).
    /// A sentence, not a coach mark: nothing points at the control, nothing
    /// blocks the board, and a tap makes it go away early.
    @ViewBuilder
    private var tipView: some View {
        if let tip {
            HStack(spacing: 10) {
                Image(systemName: tip.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true) // decoration; the sentence says it
                Text(tip.message)
                    .font(CouchTypography.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 340)
            .couchGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
            .onTapGesture { dismissTip() }
            .transition(.opacity)
        }
    }

    /// PRD-34. "New game" used to live only at the bottom of Settings, which
    /// is nobody's guess for where the next board is. One of its three new
    /// homes is right here: once the Afterglow has settled — never during it —
    /// the solved chip is joined by an "Another" that starts a fresh board at
    /// the difficulty you just finished. Free-play boards only; the daily is
    /// one a day, and offering "another" one would be a lie.
    @ViewBuilder
    private var completionChip: some View {
        if let solvedAt = model.solvedAt {
            // Read the card **here**, in the body, and pass it in. Read inside
            // the closure instead and it is always nil: `TimelineView`'s
            // content closure escapes, so it captures a copy of this view
            // struct whose `@State` is a snapshot from when the closure was
            // made — and this one is made before the render lands, 70 ms after
            // the solve. Driving the app found it: the renderer logged
            // "assigned, shareCard=set" once and every subsequent evaluation of
            // the button logged "shareCard=nil", 30 times running, with the PNG
            // sitting on disk the whole time. Nothing about it is visible to a
            // green test suite or to a code reading.
            let card = shareCard
            TimelineView(.periodic(from: solvedAt, by: 0.5)) { timeline in
                if timeline.date.timeIntervalSince(solvedAt) > 2.4 {
                    HStack(spacing: 10) {
                        GlassChip(completionText, systemImage: "checkmark")
                        shareButton(card)
                        if case .free(let difficulty)? = model.kind {
                            Button {
                                highlightedDigit = nil
                                model.startFree(difficulty)
                            } label: {
                                GlassChip(Strings.string("game.another.title"),
                                          systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Strings.string(
                                "game.another.label", .text(Strings.difficulty(difficulty))))
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private var completionText: String {
        if case .daily? = model.kind, model.displayedStreak > 0 {
            return Strings.string("game.completion.streak", .int(model.displayedStreak))
        }
        return Strings.string("status.solved")
    }

    // MARK: Share (PRD-12)

    /// The share button waits and never asks: no prompt, no badge, no "share
    /// your streak!" — it sits beside the chip and costs nothing to ignore.
    ///
    /// Beside the completion chip rather than in the control bar, and that is
    /// not taste: the bar has held six 44 pt buttons since PRD-11, measured at
    /// 322 pt against a 375 pt iPhone SE. A seventh does not fit at the craft
    /// charter's touch floor, whatever the argument for it.
    @ViewBuilder
    private func shareButton(_ card: ShareCardExport?) -> some View {
        if let card {
            ShareLink(item: card.url, preview: SharePreview(shareTitle)) {
                GlassChip(ShareCardPhrase.share, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ShareCardPhrase.shareLabel)
        }
    }

    private var shareTitle: String { shareFacts?.shareTitle ?? ShareCardPhrase.shareLabel }

    /// The facts behind the card, or nil when there is no solved board to
    /// describe.
    ///
    /// `model.solvedAt` is the instant the timer was paused, so the card's time
    /// is the same number the completion chip is showing rather than a fresh
    /// read of a clock that has moved on since.
    private var shareFacts: SolveCardFacts? {
        guard let game = model.game, let solvedAt = model.solvedAt else { return nil }
        let isDaily: Bool
        let difficulty: Difficulty
        switch model.kind {
        case .daily?:
            isDaily = true
            difficulty = .steady   // the daily composes at steady
        case .free(let d)?:
            isDaily = false
            difficulty = d
        // A channel solve shares as the tier it was, which is honest as far as it
        // goes and no further: the card says "Steady" where it should say "Killer ·
        // Steady", because `SolveCardFacts` and `ShareCard` are laid out around a
        // single band caption and widening them is a share-card change rather than
        // a channel one. Recorded in DEVIATIONS; the alternative was shipping a
        // card that claims a classic solve.
        case .channel(_, let tier, let day)?:
            isDaily = day != nil
            difficulty = tier.wireDifficulty
        case nil:
            return nil
        }
        return SolveCardFacts(
            game: game,
            difficulty: difficulty,
            isDaily: isDaily,
            // An archive board is a real solve and shares like one, but PRD-14
            // is explicit that it never touched the streak — so it must not
            // print one either, or the card claims credit the ledger refused.
            streak: model.archiveDay == nil ? model.displayedStreak : 0,
            at: solvedAt
        )
    }

    /// Render the card once per solve.
    ///
    /// **Synchronous, in `onChange`, and deliberately not a `Task`.** The first
    /// version slept 2.4 s inside `.task(id: model.solvedAt)` so the render
    /// would land after the Afterglow — and driving the app caught what that
    /// costs: `Task.sleep` returns immediately when the task is cancelled, so
    /// any view churn inside that 2.4 s window left `shareCard` nil with no
    /// restart to repair it, and the Share chip silently never appeared. It
    /// reproduced on a real solve: the PNG was on disk, timestamped, and the
    /// button was not on screen. A feature that works four times out of five is
    /// worse than one that is not there, because nobody can report it.
    ///
    /// Nothing was gained by the wait either. The button lives *inside* the
    /// completion chip's own `> 2.4 s` gate, so rendering early cannot show it
    /// early — the gate was always doing the work the sleep was credited with.
    private func renderShareCard() {
        guard let facts = shareFacts else {
            shareCard = nil
            return
        }
        let tones = model.prefs.theme.tones(for: colorScheme)
        // **One chip, two payloads** (PRD-26 §2.4). The loop when this solve
        // left a replay, the still when it did not — a widget solve, a watch
        // solve, or a board that arrived over CloudKit with its log stripped.
        // The player never sees two buttons and PRD-12's behaviour never
        // disappears.
        if let replay = model.currentReplay,
           let loop = ShareCardRenderer.exportLoop(
               facts: facts, replay: replay, tones: tones, accent: accent
           ) {
            shareCard = loop
            return
        }
        shareCard = ShareCardRenderer.export(facts: facts, tones: tones, accent: accent)
    }

    // MARK: Stats drawer

    /// 0 = hidden, 1 = fully open. The snapped state plus whatever the finger
    /// is currently adding, clamped — so the panel tracks the drag one-to-one
    /// and every derived value (scrim alpha, panel offset) reads from here.
    private var drawerProgress: CGFloat {
        guard drawerHeight > 0 else { return 0 }
        return min(1, max(0, ((drawerOpen ? drawerHeight : 0) + drawerDrag) / drawerHeight))
    }

    /// Height of the band at the top of the screen a pull-down may start in.
    /// Deep enough to catch a deliberate downward drag, shallow enough that
    /// the board's first row is mostly clear of it.
    private static let drawerRevealBand: CGFloat = 100
    /// Projected-open fraction past which the drawer snaps open on release.
    private static let drawerSnapThreshold: CGFloat = 0.35

    /// May this stroke steer the drawer? `startLocation` is fixed for the
    /// whole drag, so this answers identically on every update and again at
    /// the end — which is why the gesture needs no "already claimed" flag.
    private func acceptsDrawerDrag(_ value: DragGesture.Value) -> Bool {
        // The coach card parks in the same band the drawer slides over, so the
        // two must never be on screen together. The debrief scrims the whole
        // screen from the other edge, so it is the same rule again — a
        // pull-down landing on an open debrief would put two panels and two
        // scrims on one board.
        guard rose == nil, !showPrefs, coachAdvice == nil, !debriefOpen,
              model.game != nil else { return false }
        // Once open, the whole screen steers it (that is the drag-up
        // dismiss); closed, the stroke has to begin in the top band.
        return drawerOpen || value.startLocation.y <= Self.drawerRevealBand
    }

    private var drawerRevealGesture: some Gesture {
        // 12pt so a sloppy tap on a board cell never twitches the drawer open;
        // the board is tap-only, so nothing else on this screen wants a drag.
        DragGesture(minimumDistance: 12)
            .updating($drawerDrag) { value, offset, _ in
                guard acceptsDrawerDrag(value) else { return }
                offset = value.translation.height
            }
            .onEnded { value in
                guard acceptsDrawerDrag(value) else { return }
                // Project the flick so a fast short swipe still opens it.
                let projected = ((drawerOpen ? drawerHeight : 0)
                                 + value.predictedEndTranslation.height) / drawerHeight
                let opening = projected > Self.drawerSnapThreshold
                if opening { model.noteDrawerFound() }
                withAnimation(.couchFast) { drawerOpen = opening }
            }
    }

    private func closeDrawer() {
        withAnimation(.couchFast) { drawerOpen = false }
    }

    // MARK: The debrief (PRD-26)

    /// A debrief exists only for a board that was solved *and* left a replay.
    /// Nil for every widget solve, every watch solve, and every board that
    /// arrived over CloudKit with its log stripped — and nil is silent: no
    /// grabber, no gesture, nothing on screen that could be pulled at and not
    /// answer.
    private var debrief: SolveDebrief? {
        guard model.solvedAt != nil, let id = model.currentEntryID else { return nil }
        return model.debrief(for: id)
    }

    private var debriefProgress: CGFloat {
        guard debriefHeight > 0 else { return 0 }
        // Upward drags are negative, so the sign flips against the drawer's.
        return min(1, max(0, ((debriefOpen ? debriefHeight : 0) - debriefDrag) / debriefHeight))
    }

    /// How much of the bottom edge the control bar owns when it is down there.
    ///
    /// **The first version of this was a bottom-120 pt reveal band, and driving
    /// it is the only way that shows what is wrong with it: that band *is* the
    /// control bar.** The one place the gesture listened was a row of six 44 pt
    /// buttons, so every pull-up either did nothing or fought Undo.
    private static let controlBarReserve: CGFloat = 96

    private func acceptsDebriefDrag(
        _ value: DragGesture.Value, in height: CGFloat, reserve: CGFloat
    ) -> Bool {
        guard debrief != nil, rose == nil, !showPrefs, !drawerOpen else { return false }
        // Open, the whole screen steers it — that is the drag-down dismiss.
        if debriefOpen { return true }
        // Closed: anywhere that is not somebody else's. The board is the drag
        // surface, and it can be, because a solved board takes no input —
        // `AppModel.place` guards `solvedAt == nil`, so there is nothing here
        // for an upward stroke to steal.
        guard value.startLocation.y > Self.drawerRevealBand else { return false }
        // The reserve is passed in rather than read off the pref, because the
        // drafting table has no horizontal control bar to reserve for (PRD-31)
        // — its six buttons are a column beside the board, outside this
        // gesture's view entirely.
        return value.startLocation.y <= height - reserve
    }

    private func debriefRevealGesture(height: CGFloat, reserve: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($debriefDrag) { value, offset, _ in
                guard acceptsDebriefDrag(value, in: height, reserve: reserve) else { return }
                offset = value.translation.height
            }
            .onEnded { value in
                guard acceptsDebriefDrag(value, in: height, reserve: reserve) else { return }
                let projected = ((debriefOpen ? debriefHeight : 0)
                                 - value.predictedEndTranslation.height) / debriefHeight
                withAnimation(.couchFast) { debriefOpen = projected > Self.drawerSnapThreshold }
            }
    }

    private func closeDebrief() {
        withAnimation(.couchFast) { debriefOpen = false }
    }

    /// The pull-up's only hint, and it is the drawer grabber's twin at the
    /// other edge — 3 pt, decoration, hidden from VoiceOver, which gets a named
    /// action instead.
    ///
    /// Unlike the drawer's, this one does **not** retire after three sessions.
    /// The drawer is a permanent fixture the player learns once; a debrief
    /// appears only in the seconds after a solve, so a mark that faded forever
    /// would leave the affordance genuinely undiscoverable on the tenth board.
    @ViewBuilder
    private var debriefGrabber: some View {
        if debrief != nil, rose == nil, !showPrefs, !drawerOpen {
            Capsule()
                .fill(.secondary)
                .frame(width: 36, height: 3)
                .opacity(0.35 * (1 - debriefProgress))
                // The inset comes from `ChromeInsets` now — under the
                // completion chip, never on the screen's bottom edge: that edge
                // belongs to the control bar and to the home indicator, and a
                // hairline drawn there is invisible against one and confusable
                // with the other. Measured on an iPhone 17 Pro, where the first
                // version landed on both.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var debriefPanel: some View {
        let progress = debriefProgress
        if progress > 0, let debrief, let replay = model.currentReplay {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.45 * progress)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeDebrief() }
                DebriefCardContent(
                    debrief: debrief,
                    replay: replay,
                    tones: model.prefs.theme.tones(for: colorScheme),
                    accent: accent,
                    onClose: { closeDebrief() }
                )
                .padding(.horizontal, 10)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    debriefHeight = max(1, height)
                }
                .offset(y: debriefHeight * (1 - progress))
            }
        }
    }

    /// PRD-34. The drawer was shipped deliberately unhinted, and the live sim
    /// audit found the predictable result: nothing on screen suggests it
    /// exists, so nobody pulls. The compromise that keeps the calm is a 3pt
    /// hairline — the smallest mark that reads as a handle — shown for the
    /// first three sessions, and retired the moment the player opens the
    /// drawer once. After that the top of the screen is bare again forever.
    ///
    /// It is decoration only: it is not a button, and it is hidden from
    /// VoiceOver, which has had a named action for the drawer since PRD-10.
    @ViewBuilder
    private var drawerGrabber: some View {
        if model.showsDrawerGrabber, model.game != nil, rose == nil, !showPrefs {
            Capsule()
                .fill(.secondary)
                .frame(width: 36, height: 3)
                .opacity(0.35 * (1 - drawerProgress))
                .padding(.top, 6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Mirrors `GlassSheet`'s grammar — 0.45 black scrim, `couchGlass` on a
    /// 28pt continuous rounded rect — but presented off an interactive offset
    /// instead of a boolean transition, so it follows the finger.
    @ViewBuilder
    private var statsDrawer: some View {
        let progress = drawerProgress
        if progress > 0 {
            ZStack(alignment: .top) {
                Color.black.opacity(0.45 * progress)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeDrawer() }
                StatsDrawerContent(model: model)
                    .padding(18)
                    .frame(maxWidth: 480)
                    .couchGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, 10)
                    // Measured before the offset — the panel's real height is
                    // what the drag maps onto, whatever the stats add up to.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        drawerHeight = max(1, height)
                    }
                    .offset(y: -drawerHeight * (1 - progress))
            }
        }
    }

    // MARK: Board + rose

    @ViewBuilder
    private func boardArea(side: CGFloat, inset: CGFloat) -> some View {
        if let game = model.game {
            let lens = rose.map { roseLens(side: side, inset: inset, rose: $0) }
            BoardView(
                game: game,
                cursor: cursor,
                accent: accent,
                showErrors: model.prefs.errorHighlight,
                solvedAt: model.solvedAt,
                roseOpen: rose != nil,
                roseLens: reduceMotion || model.solvedAt != nil ? nil : lens,
                // A finger on a petal is direct — it lands where it lands, and
                // a preview of a digit already committing is noise. A *hovering*
                // Pencil tip is the opposite: it is asking what would happen,
                // and this is the answer (PRD-31).
                previewDigit: hoverDigit,
                previewPencil: rose?.pencil ?? false,
                highlightDigit: model.prefs.numberHighlight ? highlightedDigit : nil,
                coachFocus: boardFocus,
                hoverCell: hoverCell,
                // Cages and tubes when the board is a channel board, nil when it
                // is classic — which is every board that existed before PRD-24, so
                // classic renders byte-identically.
                channelRules: model.currentRules,
                hand: model.hand,
                // Afterglow: the wave detonates from the winning cell, and
                // after the sweep the gyro steers the trophy sheen.
                waveOrigin: model.lastPlacedCell,
                afterglowTilt: { motion.tilt(at: $0) },
                side: side,
                inset: inset,
                axActions: axActions
            )
            .contentShape(Rectangle())
            .onTapGesture { location in
                // A Pencil stroke also reaches the tap recogniser; the window
                // in `PencilScribe` is what tells the two apart. A Pencil *tap*
                // is unaffected — it produces no stroke, so nothing suppresses
                // it and the rose blooms exactly as it does under a finger.
                guard !scribe.isActive else { return }
                handleBoardTap(at: location, side: side, inset: inset)
            }
            // PRD-25's one gesture. Additive by construction: a plain tap still
            // opens the rose, so the first-flick covenant is untouched, and the
            // long press only ever *asks a question* — it never writes.
            //
            // Two gestures, not one composed one — see `pressPoint` for the
            // composition that looked right and did nothing. The drag records
            // where the finger is; the long press says when to ask.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { pressPoint = $0.startLocation }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        // Writing a 4 takes longer than 0.45 s, and without
                        // this a why-chain opens over the ink every time.
                        guard !scribe.suppressesTouch else { return }
                        askWhy(at: pressPoint, side: side, inset: inset)
                    }
            )
            // PRD-31's one new input concept. `.pencil` events only — finger
            // and pointer events arrive here too and are dropped, so every
            // gesture above still behaves exactly as it did.
            .simultaneousGesture(
                SpatialEventGesture(coordinateSpace: .local)
                    .onChanged { events in
                        scribe.handle(events) { glyph in
                            commitInk(glyph, side: side, inset: inset)
                        }
                    }
                    .onEnded { _ in
                        scribe.finish { glyph in
                            commitInk(glyph, side: side, inset: inset)
                        }
                    }
            )
            .overlay { WetInkView(strokes: scribe.strokes, accent: accent, side: side) }
            // The halo the Mac has had since PRD-4, now on the iPad: a trackpad
            // pointer and a hovering Apple Pencil deliver the same phases, so
            // one modifier serves both.
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    let local = CGPoint(x: point.x - inset, y: point.y - inset)
                    hoverCell = BoardMetrics.cellIndex(at: local, side: side)
                    hoverDigit = lens.flatMap { petalDigit(at: point, lens: $0) }
                case .ended:
                    hoverCell = nil
                    hoverDigit = nil
                }
            }
            .overlay {
                if let rose, let lens, model.solvedAt == nil {
                    // Scrim: any touch beside the rose cancels it — and blocks
                    // board taps from landing under an open rose.
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { closeRose() }
                    TouchRose(
                        state: rose,
                        accent: accent,
                        completedDigits: Set((1...9).filter { game.isDigitComplete($0) }),
                        scale: lens.scale,
                        onDigit: { commit(digit: $0) },
                        // Never a given — `openRose` refuses to bloom the rose
                        // on one — so "filled" is the only guard this needs.
                        currentDigit: game.isGiven(cursor) || game.entry(at: cursor) == 0
                            ? nil : game.entry(at: cursor),
                        notedDigits: Set(game.pencilDigits(at: cursor))
                    )
                    .position(x: lens.viewCentre.x, y: lens.viewCentre.y)
                }
            }
        } else {
            // Momentary state while a puzzle is composed.
            GlassChip(Strings.string("status.composing"), systemImage: "sparkles")
                .frame(height: side)
        }
    }

    // MARK: Keyboard (PRD-31)

    /// The Mac's board grammar, on an iPad with a keyboard attached.
    ///
    /// Deliberately a *reuse* of `BoardKeys` rather than a second table:
    /// keyboard parity means the two platforms cannot disagree about what `P`
    /// does, and the only way to guarantee that is for there to be one answer.
    /// Where the two screens legitimately differ they differ here, in the
    /// handling, not in the classification — `pencilMode` is this screen's
    /// state, `Esc` closes this screen's rose, and the touch app has a control
    /// bar the Mac replaces with menus.
    ///
    /// ⌘-chords fall through untouched, so the system's own shortcuts and the
    /// two `keyboardShortcut` buttons in the control bar keep working.
    private func handleKey(_ press: KeyPress) -> Bool {
        guard let game = model.game else { return false }
        if press.modifiers.contains(.command) { return false }
        // A solved board takes no input, exactly as `AppModel.place` insists;
        // the one key that still means something is the way out.
        if model.solvedAt != nil {
            guard case .escape = press.key else { return false }
            model.goHome()
            return true
        }
        guard let action = BoardKeys.action(for: press) else { return false }
        switch action {
        case .move(let direction):
            closeRose()
            cursor = BoardMetrics.moveCursor(cursor, direction, wrap: true)
        case .place(let digit):
            closeRose()
            if pencilMode {
                model.togglePencil(digit, at: cursor)
            } else {
                model.place(digit, at: cursor)
                hapticsAfterPlacing(at: cursor)
            }
        case .pencil(let digit):
            closeRose()
            model.togglePencil(digit, at: cursor)
        case .erase:
            closeRose()
            _ = model.erase(at: cursor)
        case .toggleStickyPencil:
            pencilMode.toggle()
            pencilEverToggled = true
            dismissTip()
        case .highlight:
            guard model.prefs.numberHighlight else { return true }
            let digit = game.entry(at: cursor)
            guard digit != 0 else { return true }
            highlightedDigit = highlightedDigit == digit ? nil : digit
            highlightEverUsed = true
        case .nextEmpty(let forward):
            closeRose()
            cursor = BoardMetrics.nextEmptyCell(from: cursor, in: game, forward: forward)
        case .escape:
            if rose != nil { closeRose() } else { model.goHome() }
        }
        return true
    }

    // MARK: Pencil (PRD-31)

    /// Which petal a hovering tip is over, in the board's padded view space, or
    /// nil if it is between petals or outside the ring.
    ///
    /// The radius is the petal's own, not the 44pt hit target `TouchRose` uses:
    /// a tap has to be forgiving because a fingertip is 10mm across and lands
    /// blind, and a hover is neither — the tip is 1mm, it is visible, and a
    /// generous radius would make the preview flicker between neighbours in the
    /// gaps where the honest answer is "none of them".
    private func petalDigit(at point: CGPoint, lens: RoseLens) -> Int? {
        guard rose != nil, model.solvedAt == nil else { return nil }
        for digit in 1...9 {
            let centre = lens.petalCentre(digit: digit)
            let dx = point.x - CGFloat(centre.x + lens.inset)
            let dy = point.y - CGFloat(centre.y + lens.inset)
            if hypot(dx, dy) <= CGFloat(lens.petalRadius) { return digit }
        }
        return nil
    }

    /// A finished glyph: find the cell it was written in, read it, and toggle
    /// the note.
    ///
    /// Every refusal below is silent, and that is the design. A stroke the app
    /// cannot use leaves no mark, no toast and no shake — the ink simply is not
    /// there any more, and the player writes it again. The alternative is a
    /// message about handwriting on a board someone is thinking over, which the
    /// idle-pixel test rejects on its own.
    private func commitInk(_ glyph: InkGlyph, side: CGFloat, inset: CGFloat) {
        guard let game = model.game, model.solvedAt == nil, rose == nil,
              let bounds = glyph.bounds else { return }
        // Board-local: the strokes arrive in the padded frame the board draws
        // into, and every geometry helper below speaks the Canvas's space.
        let local = InkGlyph(strokes: glyph.strokes.map { stroke in
            stroke.map { InkPoint(x: $0.x - Double(inset), y: $0.y - Double(inset)) }
        })
        let cellSide = Double(side) / 9
        let extent = max(bounds.maxX - bounds.minX, bounds.maxY - bounds.minY)
        // Bigger than a dot, smaller than a doodle. The upper bound is what
        // stops a resting wrist or a stray drag across three boxes from being
        // read as an enormous 1; the lower stops a Pencil tap that jittered.
        guard extent >= cellSide * 0.22, extent <= cellSide * 2.2 else { return }
        let centre = CGPoint(x: (bounds.minX + bounds.maxX) / 2 - Double(inset),
                             y: (bounds.minY + bounds.maxY) / 2 - Double(inset))
        guard let cell = BoardMetrics.cellIndex(at: centre, side: side),
              !game.isGiven(cell), game.entry(at: cell) == 0,
              let reading = DigitHand.read(local), DigitHand.commits(reading) else { return }
        // **Toggle, not set.** Writing a digit that is already noted takes it
        // away — so erase costs no gesture, no mode and no second concept, and
        // it reads the same as the rose's dashed-rim petal.
        model.togglePencil(reading.digit, at: cell)
        cursor = cell
        // The specimen updates only on the stricter reading. `learnHand` is a
        // no-op when the glyph is unchanged, so a steady hand writes no blob.
        if DigitHand.adopts(reading) { model.learnHand(local, as: reading.digit) }
        if model.prefs.touchHaptics { haptics.playPlacement() }
        dismissTip()
    }

    /// The rose's geometry: where the petals are drawn, and — through
    /// `BoardView.roseLens` — where the board bends under them (PRD-22). It
    /// blooms on the selected cell, nudged inward so no petal ever leaves the
    /// board frame (screen edges would otherwise clip it). One value rather
    /// than the pair of `roseScale`/`rosePosition` helpers this replaced,
    /// because paint and lens disagreeing by four points is visible.
    private func roseLens(side: CGFloat, inset: CGFloat, rose: RoseState) -> RoseLens {
        RoseLens(
            cursor: cursor,
            side: Double(side),
            inset: Double(inset),
            pencil: rose.pencil,
            scale: RoseLens.scale(forSide: Double(side))
        )
    }

    // MARK: Accessibility grammar (PRD-19)

    /// The board's VoiceOver actions, mirroring the touch grammar exactly:
    /// the same nine digits the rose offers, the same pencil toggle from the
    /// control bar, the same erase that only appears on a filled cell. Nil
    /// action closures once the board is solved, which turns the 81 elements
    /// read-only rather than offering moves `AppModel` would refuse.
    private var axActions: BoardAXActions {
        guard model.solvedAt == nil else {
            return BoardAXActions(select: { cursor = $0 })
        }
        return BoardAXActions(
            pencilMode: pencilMode,
            select: { axActivate($0) },
            place: { digit, cell in axCommit(digit, at: cell, pencil: false) },
            note: { digit, cell in axCommit(digit, at: cell, pencil: true) },
            erase: { cell in
                guard let game = model.game, game.entry(at: cell) != 0 else { return }
                let digit = game.entry(at: cell)
                cursor = cell
                closeRose()
                if model.erase(at: cell) { announce(BoardSpeech.eraseAnnouncement(digit: digit)) }
            }
        )
    }

    /// Activating a cell, for whichever assistive technology is driving.
    ///
    /// Under VoiceOver this is unchanged and deliberately dull: move the
    /// cursor, touch nothing else. The petals are a spatial flick grammar with
    /// no screen-reader equivalent worth having, and VoiceOver's door to the
    /// same nine digits is the actions rotor on the cell.
    ///
    /// Voice Control ("Tap cell 3 5"), Switch Control's select and Full
    /// Keyboard Access all activate through the very same AX action — and none
    /// of them can reach a custom action. Without this branch the board is
    /// perfectly addressable and completely unplayable for all three: you can
    /// name any of 81 cells and then do nothing to it. So for them, activation
    /// runs the finger-tap path itself — `tapCell`, the same function the
    /// gesture calls, highlight and all. Not a parallel implementation that
    /// will drift: the same door.
    private func axActivate(_ cell: Int) {
        guard !UIAccessibility.isVoiceOverRunning else {
            // The cursor ring follows VoiceOver focus and nothing else moves.
            cursor = cell
            return
        }
        tapCell(cell)
    }

    /// One digit, committed the way the rose would commit it. Announcing the
    /// result is the whole point: without it VoiceOver re-reads the focused
    /// cell and a player never learns that the fourth 4 was their last.
    private func axCommit(_ digit: Int, at cell: Int, pencil: Bool) {
        guard let game = model.game, model.solvedAt == nil, !game.isGiven(cell) else { return }
        cursor = cell
        closeRose()
        if pencil {
            let wasSet = game.pencilDigits(at: cell).contains(digit)
            model.togglePencil(digit, at: cell)
            announce(BoardSpeech.noteAnnouncement(digit: digit, added: !wasSet))
        } else {
            model.place(digit, at: cell)
            hapticsAfterPlacing(at: cell)
            guard let after = model.game else { return }
            announce(model.solvedAt != nil
                     ? BoardSpeech.solvedAnnouncement
                     : BoardSpeech.placementAnnouncement(digit: digit, in: after))
        }
    }

    private func announce(_ message: String) {
        guard !message.isEmpty else { return }
        AccessibilityNotification.Announcement(message).post()
    }

    // MARK: Touch grammar

    private func handleBoardTap(at location: CGPoint, side: CGFloat, inset: CGFloat) {
        let boardPoint = CGPoint(x: location.x - inset, y: location.y - inset)
        guard let cell = BoardMetrics.cellIndex(at: boardPoint, side: side) else { return }
        tapCell(cell)
    }

    /// Everything a tap on a cell does. Shared with `axActivate`, which is what
    /// Voice Control and Switch Control reach the board through — a second
    /// implementation of "what a tap does" would drift within one release.
    private func tapCell(_ cell: Int) {
        guard let game = model.game, model.solvedAt == nil, rose == nil else { return }
        cursor = cell
        // Tap a placed digit → light up all of its kind (notes included).
        // Tap it again → lights off. Givens are finally tappable: they're
        // the natural handles for "show me every 9".
        let digit = game.entry(at: cell)
        if digit != 0, model.prefs.numberHighlight {
            highlightEverUsed = true
            dismissTip()
            withAnimation(.couchFast) {
                highlightedDigit = (highlightedDigit == digit) ? nil : digit
            }
        }
        openRose(at: cell)
    }

    /// `cell` must be the cursor — the rose is positioned off `cursor` at
    /// render time — but taking it explicitly keeps the caller from depending
    /// on the ordering of a `@State` write it made two lines earlier.
    private func openRose(at cell: Int) {
        guard let game = model.game, !game.isGiven(cell) else { return }
        // The rose and the Pencil want the same square inches. Whatever was
        // half-written is dropped rather than committed into a cell the player
        // has just aimed a ring at.
        scribe.cancel()
        // Notes only make sense in empty cells; a filled cell opens the
        // normal rose even in pencil mode (same rule as tvOS hold-click).
        let pencil = pencilMode && game.entry(at: cell) == 0
        withAnimation(.couchFast) {
            rose = RoseState(pencil: pencil)
        }
    }

    private func closeRose() {
        withAnimation(.couchFast) { rose = nil }
        hoverDigit = nil
    }

    private func commit(digit: Int) {
        guard let state = rose else { return }
        if state.pencil {
            model.togglePencil(digit, at: cursor)
        } else if model.game?.entry(at: cursor) == digit {
            // The rose opened on a cell that already holds this digit — its
            // own petal carries the dashed erase rim (`FlickRoseView.petal`),
            // and tapping (or flicking to) it erases rather than re-placing
            // the same digit.
            _ = model.erase(at: cursor)
        } else {
            model.place(digit, at: cursor)
            hapticsAfterPlacing(at: cursor)
        }
        closeRose()
        considerTip()
    }

    // MARK: Why must this be a seven? (PRD-25)

    /// What the board is lit with. The narration wins when one is running —
    /// the two are never opened at once (each dismisses the other), and a
    /// single source here is what makes that structural rather than a rule the
    /// next person has to remember.
    private var boardFocus: CoachFocus? {
        if let why { return why.focus }
        if let whyRefusal { return whyRefusal.focus }
        return coachAdvice.flatMap(CoachFocus.init)
    }

    /// The long press landed. Empty cells only — a filled square has no
    /// candidates left to argue about, and the gesture stays silent rather
    /// than explaining that.
    private func askWhy(at point: CGPoint, side: CGFloat, inset: CGFloat) {
        guard let game = model.game, model.solvedAt == nil, rose == nil else { return }
        let local = CGPoint(x: point.x - inset, y: point.y - inset)
        guard let cell = BoardMetrics.cellIndex(at: local, side: side),
              game.entry(at: cell) == 0 else { return }
        guard why == nil, whyRefusal == nil else { return }

        dismissTip()
        closeDrawer()
        dismissCoach()
        cursor = cell
        guard let outcome = model.requestDerivation(forCell: cell) else { return }
        // No haptic. The board lighting up *is* the feedback, and a buzz for a
        // question the player asked — rather than for a change they made —
        // spends the sensory budget on an event that has no consequence.
        withAnimation(.couchFast) {
            switch outcome {
            case .success(let derivation): why = WhyNarration(derivation)
            case .failure(let refusal): whyRefusal = WhyRefusal(refusal: refusal)
            }
        }
        announceWhy()
    }

    private func advanceWhy() {
        guard var running = why else { return }
        running.advance()
        withAnimation(.couchFast) { why = running }
        announceWhy()
    }

    private func dismissWhy() {
        withAnimation(.couchFast) {
            why = nil
            whyRefusal = nil
        }
    }

    /// VoiceOver hears the beat it cannot see the board light up. Same join as
    /// the hint card's, through the same key, so a screen reader is told the
    /// same sentence the card shows rather than a second spelling of it.
    private func announceWhy() {
        if let beat = why?.beat {
            announce(CoachCardLabel.spoken(
                title: BoardSpeech.coachTitle(.step(beat.coach)),
                sentence: BoardSpeech.coachSentence(.step(beat.coach))))
        } else if let whyRefusal {
            announce(CoachCardLabel.spoken(title: whyRefusal.title,
                                           sentence: whyRefusal.sentence))
        }
    }

    /// The card, in the same free band the hint uses and dismissed the same
    /// way. Never auto-advances: a player reading a proof sets the pace.
    @ViewBuilder
    private var whyView: some View {
        if why != nil || whyRefusal != nil {
            ZStack(alignment: model.prefs.controlsAtBottom ? .top : .bottom) {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissWhy() }
                Group {
                    if let why {
                        WhyCardContent(narration: why, accent: accent, onNext: advanceWhy) {
                            // Through the ordinary door, so the wave, the error
                            // rules, the haptics and persistence are exactly
                            // what the rose would have left. The player asked.
                            model.place($0.digit, at: $0.cell)
                            hapticsAfterPlacing(at: $0.cell)
                            dismissWhy()
                        }
                    } else if let whyRefusal {
                        WhyRefusalContent(refusal: whyRefusal, accent: accent)
                    }
                }
                .padding(.horizontal, 20)
                .padding(model.prefs.controlsAtBottom ? .top : .bottom, 8)
                .transition(.opacity.combined(
                    with: .move(edge: model.prefs.controlsAtBottom ? .top : .bottom)
                ))
            }
        }
    }

    // MARK: Coach (PRD-11)

    /// The lightbulb is a toggle, not a dispenser: pressing it again puts the
    /// card away rather than spending another hint on the same position.
    private func toggleCoach() {
        guard model.game != nil, model.solvedAt == nil else { return }
        guard coachAdvice == nil else { return dismissCoach() }
        guard let advice = model.requestCoachAdvice() else { return }
        dismissWhy()
        dismissTip()
        closeDrawer()
        withAnimation(.couchFast) { coachAdvice = advice }
        announce(CoachCardLabel.spoken(title: BoardSpeech.coachTitle(advice),
                                       sentence: BoardSpeech.coachSentence(advice)))
    }

    private func dismissCoach() {
        withAnimation(.couchFast) { coachAdvice = nil }
    }

    /// The wand. Turning it on fills every empty cell's notes; turning it off
    /// clears nothing at all, which is the promise that makes it safe to try.
    private func toggleAutoNotes() {
        guard let before = model.game?.pencilMarkCount, model.solvedAt == nil else { return }
        let turningOn = !model.autoNotes
        model.autoNotes = turningOn
        dismissTip()
        guard turningOn, let after = model.game?.pencilMarkCount else { return }
        showChip(Phrase.autoNotesChip(max(0, after - before)))
    }

    private func showChip(_ text: String) {
        withAnimation(.couchFast) { autoNotesChip = text }
        chipDismissal?.cancel()
        chipDismissal = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.couchAmbient) { autoNotesChip = nil }
        }
    }

    /// The card, parked in the free band opposite the controls — PRD-2 sized
    /// that band precisely so a panel could appear there without the board
    /// moving a pixel. A tap anywhere else dismisses it, through the same
    /// near-invisible scrim the rose uses.
    @ViewBuilder
    private var coachView: some View {
        if let coachAdvice {
            ZStack(alignment: model.prefs.controlsAtBottom ? .top : .bottom) {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissCoach() }
                CoachCardContent(
                    advice: coachAdvice,
                    accent: accent,
                    actionTitle: coachAdvice.actionTitle(autoNotes: model.autoNotes)
                ) {
                    if case .step(let step) = coachAdvice { model.applyCoachStep(step) }
                    dismissCoach()
                }
                .padding(.horizontal, 20)
                .padding(model.prefs.controlsAtBottom ? .top : .bottom, 8)
                .transition(.opacity.combined(
                    with: .move(edge: model.prefs.controlsAtBottom ? .top : .bottom)
                ))
            }
        }
    }

    @ViewBuilder
    private var autoNotesChipView: some View {
        if let autoNotesChip {
            GlassChip(autoNotesChip, systemImage: "wand.and.stars")
                .transition(.opacity)
        }
    }

    // MARK: Tips (PRD-34)

    /// The whole of Nine's unprompted teaching, gathered in one call site so
    /// the budget cannot be spent from somewhere nobody remembers.
    ///
    /// Two suppressions are not about the budget. A tip never lands on top of
    /// the undo toast — two glass slabs in the same place read as a pile-up.
    /// And nothing fires while VoiceOver is running: every sentence here is in
    /// the *finger* grammar ("tap the pencil, then flick"), which is not how a
    /// VoiceOver player reaches any of it — they have the cell's actions rotor
    /// and its hint, both of which say the true thing for them (PRD-19).
    private func considerTip() {
        guard let game = model.game, tip == nil, toast == nil,
              !UIAccessibility.isVoiceOverRunning else { return }
        let showErrors = model.prefs.errorHighlight
        let moment = TipMoment(
            placements: game.placementCount,
            undosTaken: game.undoCount,
            pencilMarks: game.pencilMarkCount,
            pencilUsed: pencilEverToggled,
            highlightUsed: highlightEverUsed,
            highlightAvailable: model.prefs.numberHighlight,
            // Gated on the pref, not on the board: a hint that appears the
            // instant a wrong digit lands would announce the mistake to a
            // player who switched mistake-marking off.
            visibleMistake: showErrors && (0..<81).contains { game.isError(at: $0) },
            solved: model.solvedAt != nil
        )
        guard let next = TipCoach.next(
            for: moment,
            ledger: model.tips,
            shownThisSession: model.tipShownThisSession
        ) else { return }
        model.noteTipShown(next)
        withAnimation(.couchFast) { tip = next }
        tipDismissal?.cancel()
        tipDismissal = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            dismissTip()
        }
    }

    private func dismissTip() {
        tipDismissal?.cancel()
        withAnimation(.couchAmbient) { tip = nil }
    }

    /// The in-play haptic mark for a placement (PRD-21). Both commit paths —
    /// the rose and the VoiceOver actions rotor — funnel through here so the
    /// two grammars feel identical in the hand.
    ///
    /// Two suppressions matter. On the solving placement the crescendo is
    /// already queued by `onChange(of: model.solvedAt)`, and a tick under its
    /// first beat just muddies it. And the error knock is gated on the error
    /// *highlight* pref: a knock the screen is not also showing would leak,
    /// through the fingertips, an answer the player asked not to be told.
    private func hapticsAfterPlacing(at cell: Int) {
        guard model.prefs.touchHaptics, model.solvedAt == nil,
              let game = model.game else { return }
        if model.prefs.errorHighlight, game.isError(at: cell) {
            haptics.playError()
        } else {
            haptics.playPlacement()
        }
    }

    private func performUndo() {
        guard let move = model.undoMove() else { return }
        // The player found undo on their own; whatever the tip was about to
        // say, the toast is the more useful thing in that spot right now.
        dismissTip()
        let next = UndoToastState(text: UndoPhrase.forMove(move))
        withAnimation(.couchFast) { toast = next }
        toastDismissal?.cancel()
        toastDismissal = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.couchAmbient) {
                if toast?.id == next.id { toast = nil }
            }
        }
    }
}

// MARK: - Chrome atoms

/// The one optional ambient element (PRD-2): a dim, non-interactive chip
/// centered in the free band. Deliberately inert — no transitions, taps pass
/// through to whatever is behind; the minute tick is a plain text swap and
/// the streak text only changes on solve, so nothing moves during play.
private struct AmbientSlotView: View {
    let model: AppModel

    var body: some View {
        Group {
            switch model.prefs.ambientSlot {
            case .none:
                EmptyView()
            case .clock:
                TimelineView(.everyMinute) { timeline in
                    GlassChip(
                        timeline.date.formatted(date: .omitted, time: .shortened),
                        systemImage: "clock"
                    )
                }
            case .streak where model.focus.hidesStreak:
                // The ambient slot is opt-in already; a Focus filter still
                // outranks it, because the player asked the *system* and the
                // system asked us (PRD-33).
                EmptyView()
            case .streak:
                // Its own capsule (points ride along here), so it takes the
                // symbol rule from `StreakChip` rather than the whole view.
                GlassChip(streakText, systemImage: StreakChip.symbol(held: model.streakHeld))
            }
        }
        .opacity(0.5)
        .allowsHitTesting(false)
    }

    /// Mirrors the home header: each part appears once it's nonzero.
    private var streakText: String {
        var parts: [String] = []
        if model.totalPoints > 0 { parts.append(Phrase.points(model.totalPoints)) }
        if model.displayedStreak > 0 {
            parts.append(BoardSpeech.streakChip(days: model.displayedStreak, held: model.streakHeld))
        }
        return parts.isEmpty ? Strings.string("shelf.ambient.empty")
                             : parts.joined(separator: " · ")
    }
}

/// A circular glass icon button sized for fingers (44pt minimum hit target).
struct GlassIconButton: View {
    let symbol: String
    let label: String
    var active = false
    var accent: Color = .white
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                .frame(width: 44, height: 44)
                // Non-interactive glass: the Button + TouchCardStyle press-scale
                // already gives feedback. Interactive Liquid Glass ran its own
                // touch handling that competed with the Button's tap recognizer,
                // making Home/pencil/undo/gear unresponsive (mirrors the working
                // macOS chip pattern). At rest the two variants look identical.
                .couchGlass(in: Circle())
                .overlay {
                    Circle().strokeBorder(accent.opacity(active ? 0.8 : 0), lineWidth: 2)
                }
                // PRD-19 / craft charter: without this, SwiftUI derives the
                // accessibility frame from the SF Symbol's tight glyph bounds,
                // not the 44pt button — the live audit measured the Home
                // chevron at 9×15pt. Switch Control and Voice Control target
                // that rectangle literally, so the visual hit area and the
                // assistive one have to be the same 44pt circle.
                .contentShape(.accessibility, Circle())
        }
        .buttonStyle(TouchCardStyle())
        // PRD-31: an iPad with a trackpad has a pointer, and a 44pt glass disc
        // that does not answer one reads as decoration. `.automatic` takes the
        // system's own shape-aware effect rather than inventing a highlight;
        // it is inert with no pointer attached, so the phone is unchanged.
        .hoverEffect()
        .accessibilityLabel(label)
    }
}

/// The strings PRD-11 added, plus the undo toast's, gathered in one block —
/// the seam PRD-20 converts to `LocalizedStringResource`. This file predates
/// that discipline and still has literals elsewhere; sweeping all of them is
/// PRD-20's job and would bury this diff.
private enum Phrase {
    /// Nine's name, never translated — the same rule as the share card's
    /// `ShareCardMetrics.wordmark`.
    static let wordmark = "Nine"

    static func points(_ total: Int) -> String {
        Strings.string("shelf.points.chip", .int(total))
    }

    static func autoNotesChip(_ count: Int) -> String {
        Strings.string("game.autoNotes.chip", .int(count))
    }

    // PRD-13 §3. "Won't cost you" rather than "you're safe": nothing was at
    // risk, because nothing here is a resource. No count, no "1 of 1 used", and
    // no naming the day that was missed.
    static let graceTitle = Strings.string("shelf.grace.title")
    static let graceBody = Strings.string("shelf.grace.body")
    static let graceHint = Strings.string("shelf.grace.hint")
    /// The card as VoiceOver hears it — one utterance, so the join between the
    /// two sentences is the translator's to place.
    static let graceLabel = Strings.string("shelf.grace.label",
                                           .text(graceTitle), .text(graceBody))

    /// Difficulty · progress, and the count of other unfinished boards when
    /// there are any. Two whole-sentence keys rather than a sentence plus a
    /// glued-on " · +2 more" fragment: the suffix was unattachable in any
    /// language that puts the count first.
    static func continueCaption(difficulty: String, progress: String, others: Int) -> String {
        others > 0
            ? Strings.string("shelf.continue.captionMore",
                             .text(difficulty), .text(progress), .int(others))
            : Strings.string("shelf.continue.caption", .text(difficulty), .text(progress))
    }
}
#endif
