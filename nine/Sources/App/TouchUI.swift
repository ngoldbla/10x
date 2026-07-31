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
    /// Preferences, from the shelf. Until now the *only* door to them was the
    /// gear in the game screen's control bar, so a player who had not started a
    /// board could not reach their own theme, accent or timer pref at all.
    @State private var showPrefs = false
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

    /// The ground the shelf's chrome has to agree with — the bar's fade, the
    /// hero card's ink, the scrims.
    private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }

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
                // PRD-31, retuned in round 2. The shelf used to ask
                // `BoardCompositionRules.resolve` — the *game screen's*
                // question — and so drew one 560pt ribbon down the middle of an
                // 834pt iPad in portrait with 137pt of dead ground on each
                // side, which two critics reported independently as "a phone
                // layout stretched". A portrait iPad genuinely cannot seat a
                // 360pt stats rail beside a full board, and just as genuinely
                // can seat two columns of cards. `resolveShelf` is that second
                // question; `theTableIsAlwaysAlsoAShelfPair` pins that the two
                // can still never disagree in the direction that would matter.
                let shelf = BoardCompositionRules.resolveShelf(
                    width: Double(geo.size.width), height: Double(geo.size.height))
                ScrollView {
                    if let pair = shelf.pair {
                        shelfPair(pair)
                    } else {
                        shelfColumn
                    }
                }
                // The last card cleared the home indicator by nothing at all:
                // measured on `iphone-light-home.png`, the bottom bar printed
                // straight across the Tempest row's subtitle. The scroll edge
                // fades the pixels; only a content inset moves them.
                .contentMargins(.bottom, Space.hero, for: .scrollContent)
                // The status bar used to sit on bare card fill: measured on
                // `iphone-dark-home-bottom.png`, the Continue card's 28/255 fill
                // ran to y = 0 and its white "Continue" glyph read at 244/255
                // directly behind the 8:52 clock. `scrollEdgeEffect`,
                // `safeAreaInset` and `contentMargins` returned zero hits across
                // the whole iOS layer. Both edges: the bottom one is what keeps
                // the last card from colliding with the home indicator.
                .nineSoftScrollEdges()
                // The wordmark and the pager come out of the scrolling content
                // and become a bar that is always there. They were the first two
                // rows of a `VStack` — so on the second screenful of a long
                // shelf there was nothing on screen naming the app or saying
                // which channel page you were on.
                .safeAreaInset(edge: .top, spacing: 0) {
                    shelfBar(width: CGFloat(shelf.contentWidth))
                }
                // Above the `ScrollView`'s own content and simultaneous with it, so
                // the shelf still scrolls vertically and the six cards still take
                // taps. See `pageTurnGesture` for the three traps.
                //
                // **After `safeAreaInset`, not before.** A modifier applied to
                // the inset view's parent covers the inset content too, and the
                // pager rail is the one surface where a sideways stroke is most
                // obviously a page turn — attached to the `ScrollView` itself it
                // would have stopped working the moment the rail moved out of it.
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
        .overlay { GlassSheet(isPresented: $showPrefs) { PrefsSheetContent(model: model) } }
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
    ///
    /// The eight slabs it used to be are now three named groups — what you have
    /// (grace · today · continue · boards), what you could start (the free-play
    /// section and the parlor), and the ways to learn — with `Space.xxl` between
    /// groups and `Space.xl` inside one, so the eye is told where a section ends
    /// by the layout instead of having to read every card to find out.
    ///
    /// **The rhythm is two rungs and only two**, which it was not: the audit
    /// measured ~45pt between the three mode cards, ~85pt before "Play
    /// together" and then ~40pt before the utility row — a gap *between* groups
    /// that was tighter than the gap *inside* one, so the bottom trio read as
    /// attached to the card above it. `Space.l` inside a group, `Space.xxl`
    /// between groups, nothing else.
    private var shelfColumn: some View {
        VStack(spacing: Space.xxl) {
            if let ledgered = model.channel.ledgered {
                ChannelShelfContent(model: model, channel: ledgered, accent: accent)
            } else {
                VStack(spacing: Space.l) {
                    graceCard
                    todayCard
                    continueCard
                }
                boardsSection
                freePlaySection
                parlorCard
                learnRow
            }
        }
        .padding(CGFloat(BoardCompositionRules.shelfOuterPadding))
        .frame(maxWidth: CGFloat(BoardCompositionRules.shelfColumnWidth))
        .frame(maxWidth: .infinity) // center the column on a window with room
    }

    /// The persistent top bar: the wordmark, the streak and points, the two
    /// utilities, and the channel pager under them.
    ///
    /// It is a `safeAreaInset` rather than the first rows of the scrolling
    /// column, which is what lets its glass run *under* the status bar — the
    /// background ignores the top safe area while the content does not, so the
    /// clock has a blurred plane to sit on and the shelf scrolls beneath it.
    ///
    /// **Two things about it were the round-1 blocker, reported on four
    /// separate frames, and both were the background.**
    ///
    ///  * `couchGlassOverContent(in: Rectangle())` painted an L1 plate whose
    ///    bottom edge is a razor-straight full-bleed line across the whole
    ///    window — measured on `iphone-dark-home-bottom.png` bisecting the
    ///    Gentle/Steady/Sharp titles and orphaning their subtitles below it.
    ///    That plate was also drawn *on top of* the `.scrollEdgeEffectStyle`
    ///    that is already applied two modifiers up, so the system's own fade
    ///    was covered by a hard-terminated rectangle. `couchGlassBar` is the
    ///    rung for a bar over live content: a specular top rim and no hard
    ///    bottom edge.
    ///  * There was nothing between the bar and the content, so a section head
    ///    scrolling under it read *through* it — the "two large titles at once,
    ///    ghosted Play behind Nine" finding. The tail below is the progressive
    ///    fade Weather and Fitness use: the ground's own colour at half
    ///    strength, dissolving to nothing over `Space.xxl`, drawn *past* the
    ///    bar's own bounds so the boundary has a gradient instead of an edge.
    ///
    /// The width is the *shelf's* width, not 1080. The bar clamped to one
    /// number and the cards to another, which is two of the "three competing
    /// alignment origins in the top 300pt" the audit measured; now the wordmark
    /// and the first card share one leading margin by construction.
    private func shelfBar(width: CGFloat) -> some View {
        VStack(spacing: Space.m) {
            header
            ChannelPagerRail(model: model, accent: accent)
        }
        .padding(.horizontal, CGFloat(BoardCompositionRules.shelfOuterPadding))
        .padding(.bottom, Space.m)
        .frame(maxWidth: width)
        .frame(maxWidth: .infinity)
        .background {
            Color.clear
                // The bar's *plane* reaches the top of the display; its content
                // does not. Without this the material starts below the status
                // bar and the clock is back on bare card fill, which is the
                // whole defect this bar exists to fix.
                .couchGlassBar(in: Rectangle(), isLight: tones.isLight)
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .bottom) { shelfBarTail }
        }
    }

    /// The bar's dissolve. Deliberately the theme's own ground rather than
    /// black: on Blueprint or Ember a black tail is a bruise, and the whole
    /// point of the mark is that the eye should not be able to find where the
    /// bar stops.
    private var shelfBarTail: some View {
        LinearGradient(
            colors: [tones.background.opacity(0.55), tones.background.opacity(0)],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: Space.xxl)
        // Below the bar's own bounds, not inside them — inside, it would be a
        // second plate on the plate it is supposed to be softening.
        .offset(y: Space.xxl)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
    /// The header used to span both, because a wordmark that sat in one column
    /// would read as that column's title; it is now the floating `shelfBar`
    /// above both, which says the same thing permanently.
    /// **`fixedSize(vertical:)` on each column is load-bearing, and driving the
    /// iPad is what found that.** `todayCard` carries `minHeight: 130` with no
    /// maximum, which makes it flexible *upward* — it accepts any height it is
    /// offered. On the phone that has never shown, because a `ScrollView`
    /// proposes nil and every child settles at its ideal size. Put the card in
    /// an `HStack` beside a taller column and the column is suddenly given a
    /// concrete height, `VStack` divides the surplus between the card and the
    /// trailing `Spacer`, and Today inflates to half the screen. A latent
    /// property of shipped code that only a second column could expose.
    ///
    /// **Round 2 measures the columns rather than dividing the window.** Both
    /// columns took `maxWidth: .infinity` inside a 1080pt clamp, which is fine
    /// at 1194pt and wrong at 2560: an external display drew two 500pt-plus
    /// bands of card. `ShelfPair` hands over the width it decided on, and
    /// `testTheShelfPairFitsAndStopsGrowing` sweeps every window for it.
    private func shelfPair(_ pair: ShelfPair) -> some View {
        let column = CGFloat(pair.columnWidth)
        let gutter = CGFloat(pair.gutter)
        return VStack(spacing: gutter) {
            if let ledgered = model.channel.ledgered {
                // A channel page is one column's worth of cards, so in the
                // two-column composition it takes the leading column and the
                // trailing one holds the ways to learn — which are channel-agnostic
                // and belong on every page. `fixedSize(vertical:)` on both for
                // PRD-31's reason: Today carries `minHeight` with no maximum and
                // inflates to half the screen without it.
                HStack(alignment: .top, spacing: gutter) {
                    ChannelShelfContent(model: model, channel: ledgered, accent: accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: column, alignment: .top)
                    VStack(spacing: Space.xxl) { learnRow }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: column, alignment: .top)
                }
            } else {
                HStack(alignment: .top, spacing: gutter) {
                    VStack(spacing: Space.xxl) {
                        VStack(spacing: Space.l) {
                            graceCard
                            todayCard
                            continueCard
                        }
                        boardsSection
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: column, alignment: .top)
                    VStack(spacing: Space.xxl) {
                        freePlaySection
                        parlorCard
                        learnRow
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: column, alignment: .top)
                }
            }
        }
        .padding(CGFloat(pair.outerPadding))
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
            // The utilities. Every other door to these was inside something
            // else: the archive hid behind a 20pt glyph in the Today card's
            // corner, and Preferences existed only in the *game* screen's
            // control bar — so a player who had not opened a board could not
            // reach their own theme or accent at all. Two 44pt discs in the one
            // bar that is always on screen.
            //
            // **They are one capsule now, and three separate findings said so.**
            // *"The calendar and gear circles intersect by ~10pt, so both
            // outlines cut through each other and form a lens shape between
            // them"*; *"tangent with ~1pt of air; the two ambient shadows fuse
            // into a single grey smear"*; *"the discs are DARKER than the bar
            // they sit in, so they read as punched holes rather than raised
            // controls"*. All three are the same mistake: two standalone
            // `.regular` discs, each with its own rim and its own shadow,
            // 4pt apart on a bar that is itself glass. The fix is the one the
            // game toolbar already took in round 2 — one capsule of bar
            // material with both tools *inset* into it (`inBar: true` drops each
            // disc's own pane and its shadow), at the 12pt gutter that stops
            // rings touching. Which is also, as the finding says, how iOS 26
            // groups toolbar glass.
            CouchGlassContainer(spacing: Space.m) {
                HStack(spacing: Space.m) {
                    GlassIconButton(symbol: "calendar",
                                    label: Strings.string("archive.title"),
                                    inBar: true) {
                        showArchive = true
                    }
                    // The hint travels with the label — the archive's AX
                    // identity moved off the Today card, it did not evaporate.
                    .accessibilityHint(Strings.string("shelf.archive.hint"))
                    GlassIconButton(symbol: "gearshape",
                                    label: Strings.string("game.control.settings"),
                                    inBar: true) {
                        showPrefs = true
                    }
                }
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xs)
                .couchGlassBar(in: Capsule(), isLight: tones.isLight)
            }
        }
        .padding(.top, Rhythm.dock)
    }

    // MARK: Learn + records

    /// Three across, matching the free-play row above it. School joins the
    /// tutorial and the records rather than hiding inside the tutorial: it is
    /// a place a player returns to, and the tutorial is a thing you do once.
    ///
    /// **The three tiles are one row now, and they were not.** Measured on a
    /// 402pt phone the cards came out 104.7 / 106.0 / 110.0 pt tall with tops at
    /// 712.3 / 711.7 / 709.7 — neither edge aligned, on three cards that are
    /// deliberately identical. Nothing in the layout said so: the glyphs were
    /// sized only by `.font`, so each tile's height was set by its own SF
    /// Symbol's tight bounds (a trophy is taller than a question mark), and the
    /// one two-line title added a line the others did not reserve. An explicit
    /// glyph box and a reserved second text line make the row's geometry the
    /// layout's decision instead of the typeface's.
    private var learnRow: some View {
        HStack(spacing: Space.m) {
            learnTile("questionmark.circle", Strings.string("tutorial.title")) {
                showTutorial = true
            }
            learnTile("trophy", Strings.string("history.title")) { showHistory = true }
            learnTile("graduationcap", Strings.string("school.title")) { showSchool = true }
        }
    }

    private func learnTile(
        _ symbol: String, _ title: String, action: @escaping @MainActor () -> Void
    ) -> some View {
        TouchCard(action: action, radius: Radius.card) {
            VStack(spacing: Space.s) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
                    // The box, not the glyph: 30×26 is the widest and tallest of
                    // the three at 24pt, so every tile now starts its title on
                    // the same baseline.
                    .frame(width: 30, height: 26)
                Text(title)
                    .font(CouchTypography.caption)
                    .multilineTextAlignment(.center)
                    // Reserved, so the two one-line titles hold the space the
                    // two-line one takes and all three cards end level.
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, minHeight: 66)
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
                // `Radius.sheet`, the same rung as the full-width cards it sits
                // above — this card is one of them in every way but its type.
                .couchGlass(in: RoundedRectangle(cornerRadius: Radius.sheet,
                                                 style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Phrase.graceLabel)
            .accessibilityHint(Phrase.graceHint)
            .transition(.opacity)
        }
    }

    // MARK: Today

    /// The front door's one primary action, and now visibly one.
    ///
    /// Three things made it a peer of the seven slabs under it rather than the
    /// thing you came here to press:
    ///
    ///  * **It was the same glass as everything else.** It is `.regular` **with
    ///    the player's accent in it** now — CouchKit's L3 rung exists for "the
    ///    one surface on screen that outranks the others", and if the daily is
    ///    not that surface then nothing is.
    ///  * **It stated a status where a button states a verb.** `todayStatus` was
    ///    inert grey text — "One a day", "Continue · 64%" — so the card said
    ///    what it *is* and never what pressing it *does*. The verb now rides a
    ///    filled accent capsule, which is also the only filled shape on the
    ///    shelf: Begin, Continue, Solved, Composing.
    ///  * **It had a hole in the middle.** Title 36 + 8 + date 16 + status 20 is
    ///    80pt of content inside a `minHeight: 130`, so `Spacer(minLength: 12)`
    ///    resolved to a **50pt void** down the centre of the primary call to
    ///    action. The minimum is gone and the card is the height of what is in
    ///    it. The `.padding(.trailing, 44)` went with it — it reserved a 62pt
    ///    dead gutter down 166pt of card for a 20pt glyph that has moved to the
    ///    permanent bar, where the archive is reachable from every page instead
    ///    of only from this card's corner.
    /// How much accent goes *into* Today's glass.
    ///
    /// Not 1.0, and the first build at 1.0 is the argument: `.regular.tint()`
    /// takes the colour's own alpha, so a full-strength accent stops being a
    /// tinted material and becomes a flat opaque slab — the card lost every
    /// trace of glass, became the loudest thing on the screen by a wide margin,
    /// and swallowed the filled accent capsule sitting on it, so the one verb
    /// on the shelf read as plain text on blue. A tint is supposed to say
    /// "this one is primary", not "this one is a system alert".
    ///
    /// At this weight the glass still refracts the ground behind it, the hue is
    /// unmistakable next to seven untinted siblings, and the capsule — the only
    /// *filled* accent shape on the shelf — reads as a step above the card it
    /// sits on rather than as a hole in it.
    private static let todayTint = 0.28

    /// Where the light on the hero card is coming from.
    ///
    /// **The card was reported as "a flat, desaturated navy ramp fenced by a
    /// hard 1px blue stroke" — a bordered web panel, not lit glass.** A tint is
    /// a filter, and a filter applied evenly across 300×130pt has no gradient in
    /// it at all, so the one primary surface on the shelf had less luminance
    /// structure than the untinted cards beside it. This is the lamp: a radial
    /// anchored near the verb capsule (the thing the eye is going to), bright
    /// where the action is and gone by the opposite corner.
    ///
    /// Deliberately **not** `.blendMode(.plusLighter)`, which is what a lamp
    /// like this wants and what a `.background` cannot safely have: a blend mode
    /// composites against the whole backdrop group, so on a glass card it
    /// reaches past the card and lights the page behind it. A plain white
    /// radial inside the card's own clip is the version that stays where it is
    /// put.
    private var todayHighlight: some View {
        RadialGradient(
            colors: [.white.opacity(tones.isLight ? 0.28 : 0.16), .white.opacity(0)],
            center: UnitPoint(x: 0.84, y: 0.12),
            startRadius: 0,
            endRadius: 260
        )
        .allowsHitTesting(false)
    }

    private var todayCard: some View {
        TouchCard(action: { model.openToday() },
                  radius: Radius.sheet,
                  tint: accent.opacity(Self.todayTint)) {
            HStack(alignment: .top, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(Strings.string("shelf.today.title"))
                        .couchText(CouchTypography.title)
                    Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                        .couchText(CouchTypography.caption, .secondary)
                    todayStatus
                }
                Spacer(minLength: Space.s)
                todayVerb
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // `padding(-18)` cancels `TouchCard`'s own 18pt inset so the lamp
            // reaches the card's edges, and the clip is the card's own corner —
            // without both, the gradient is still bright where its frame stops
            // and draws the hard rectangle it exists to replace.
            //
            // **Clip first, then expand.** The other order clips at the
            // *content's* bounds and throws the 36pt the negative padding just
            // bought away, which is the whole point of the pair; a modifier's
            // frame is its child's, and here the child has to be the expanded
            // one.
            .background {
                todayHighlight
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sheet,
                                                style: .continuous))
                    .padding(-18)
            }
        }
        // Composing the daily is its own state on this card, so only a *foreign*
        // compose disables it.
        .disabled(composeInFlight && !isComposingDaily)
    }

    /// The filled capsule: what pressing this card will do, in a word.
    ///
    /// Deliberately **not** a `Button` — it is the label of the card it sits on,
    /// and a Button nested in `TouchCard`'s Button is merged by SwiftUI, which
    /// takes the inner frame with it (PRD-14 measured the Today card's own
    /// accessibility element collapsing from 89×129 to a 44×44 glyph). It is
    /// hidden from VoiceOver because the card's own label already carries the
    /// same words.
    ///
    /// **It was blue on blue and it was the weakest contrast on the screen.**
    /// The pill filled with `accent` while the card behind it is `accent` at
    /// 0.28 through glass — the same hue a few steps apart — so the shelf's only
    /// primary action had less separation from its own background than any
    /// caption on the page. The pill is now the ground's *opposite*: paper-white
    /// on a dark theme with the accent as ink, and the deepened accent with
    /// white ink on a light one, which is the direction that has a 4.5:1 answer
    /// on both.
    ///
    /// The silhouette changed with it. A `Capsule` inside a `Radius.sheet` card
    /// with 18pt of inset is a 15pt curve where the concentric answer is 10, so
    /// the pill read as pasted on rather than as nested. `Radius.inner` is that
    /// arithmetic, and it is the same call the mini-boards two cards down make.
    @ViewBuilder
    private var todayVerb: some View {
        if let text = todayVerbText {
            let shape = RoundedRectangle(
                cornerRadius: Radius.inner(Radius.sheet, inset: 18), style: .continuous)
            Text(text)
                .font(CouchTypography.label)
                .foregroundStyle(verbInk)
                .lineLimit(1)
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.s)
                .background(verbFill, in: shape)
                .accessibilityHidden(true)
        }
    }

    /// The pill's fill: the loudest legible shape the ground allows.
    private var verbFill: Color { tones.isLight ? accent : .white }

    /// …and its ink, which is the fill's opposite rather than `.primary` —
    /// `.primary` is white on a dark theme, and this pill is white there.
    private var verbInk: Color { tones.isLight ? .white : accent }

    /// Nil in the two states that are not an action. A capsule reading "Solved"
    /// beside a status line reading "Solved" is not emphasis, it is an echo —
    /// and a filled accent shape is the loudest thing on the shelf, which it
    /// should not spend on a board there is nothing left to do to.
    private var todayVerbText: String? {
        if isComposingDaily || model.todaySolved { return nil }
        if model.savedDaily != nil { return Strings.string("shelf.continue.title") }
        return Strings.string("firstrun.begin")
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
                    // The bare progress, not `shelf.today.continueProgress`'s
                    // "Continue · 64%": the verb capsule two inches to the right
                    // now says Continue, and a card that says it twice reads as
                    // a template that was filled in by two different people.
                    Text(BoardProgressCaption.text(for: daily))
                        .couchText(CouchTypography.caption, .secondary)
                        // A percentage that ticks while you watch it, in
                        // proportional figures, re-measures its own line on
                        // every change.
                        .monospacedDigit()
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
            TouchCard(action: { model.continueSaved() }, radius: Radius.sheet) {
                HStack(spacing: Space.l) {
                    BoardFingerprint(game: game, accent: accent, side: 44)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(Strings.string("shelf.continue.title"))
                            .couchText(CouchTypography.body)
                        Text(Phrase.continueCaption(
                            difficulty: Strings.difficulty(difficulty),
                            progress: BoardProgressCaption.text(for: game),
                            others: model.extraPartialCount))
                            .couchText(CouchTypography.caption, .secondary)
                            .monospacedDigit()
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
            VStack(spacing: Space.s) {
                sectionHeader(Strings.string("boards.title")) {
                    Button { showBoards = true } label: {
                        Text(Strings.string("shelf.boards.seeAll"))
                            .couchText(CouchTypography.caption, accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Strings.string("shelf.boards.seeAllLabel"))
                }
                ForEach(extraPartials.prefix(3)) { entry in
                    TouchCard(action: { model.resumeEntry(id: entry.id) },
                              radius: Radius.card) {
                        HStack(spacing: Space.m) {
                            BoardFingerprint(game: entry.game, accent: accent, side: 34)
                            Text(boardTitle(entry))
                                .font(CouchTypography.caption)
                            Spacer()
                            Text(BoardProgressCaption.text(for: entry.game))
                                .couchText(CouchTypography.caption, .secondary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// A section head, so a group of cards reads as a group.
    ///
    /// This *is* the Boards header, generalised rather than restyled — it was
    /// the shelf's only one, so every other block simply began and eight cards
    /// arrived as one undifferentiated list. Same rung, same weight: a new
    /// heading that looked different from the shipped one would say the two
    /// sections were different kinds of thing.
    private func sectionHeader(_ title: String) -> some View {
        sectionHeader(title) { EmptyView() }
    }

    private func sectionHeader<Trailing: View>(
        _ title: String, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            // `heading`, not `body`: the ramp's `.title3` semibold rung is what
            // a section head is for, and at `body` the head sat at the same
            // size and weight as the card titles underneath it — which is the
            // "sectioning is half-applied" finding, half of it. (The other half
            // is that the free-play block's deep bands want a head of their
            // own; there is no catalog row for one, so it is in `crossFileNeeds`
            // rather than invented here.)
            Text(title)
                .couchText(CouchTypography.heading)
            Spacer()
            trailing()
        }
        .padding(.horizontal, Space.xs)
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

    /// The free-play block, under a name.
    ///
    /// `parlorCard` used to be the last row of this stack, which made "Play
    /// together" read as a seventh difficulty — a band between Nocturne and
    /// nothing. It is a different *kind* of thing (a way to start a board with
    /// somebody, at any difficulty), so it now sits outside the section it was
    /// visually a member of.
    private var freePlaySection: some View {
        // `Space.s` head-to-content, `Space.l` between the cards, `Space.xxl`
        // between this section and the next — the two-step scale, with the
        // head deliberately closer to what it names than the rows are to each
        // other. The shipped rhythm had the head at 8 and the rows at 12,
        // which is a step too small to read as a step.
        VStack(spacing: Space.s) {
            sectionHeader(Strings.string("prefs.section.play"))
            freePlayRow
        }
    }

    private var freePlayRow: some View {
        // Three across, then the deep end on its own lines (PRD-17 §3, widened
        // by PRD-25). Not a hierarchy — a fourth column on a 393pt iPhone
        // leaves each card ~90pt for a title plus a two-line blurb, which
        // truncates all four rather than just the new one. Full width is what
        // lets a deep band keep the same blurb the three above it get, and it
        // is why three of them stack rather than becoming a second row.
        VStack(spacing: Space.l) {
            HStack(spacing: Space.m) {
                ForEach(Difficulty.rowBands, id: \.self) { difficulty in
                    difficultyCard(difficulty)
                }
            }
            ForEach(Difficulty.deepBands, id: \.self) { difficulty in
                deepEndCard(difficulty)
            }
        }
    }

    /// PRD-28 §9. One card, the shape of a deep-end card, at the bottom of the
    /// free-play block — where "another way to start a board" belongs, beside
    /// the other ways to start one.
    ///
    /// It carries no dot, no roster and no state: a parlor that has not begun
    /// is not a thing to look at, and the shelf is the calmest surface in the
    /// app. When a friend has sent a board the caption is the only thing that
    /// changes, and tapping opens theirs instead of today's.
    private var parlorCard: some View {
        let pending = model.parlor.pendingInvite
        return TouchCard(action: {
            let invite = pending ?? model.todayInvite
            model.parlor.takePendingInvite()
            Task {
                // The board opens either way. On success the session loop in
                // `NineApp` opens and joins it; on failure — no call, or the
                // player declined the system sheet — this opens it alone.
                if await ParlorSession.activate(invite) == false {
                    model.openParlorInvite(invite)
                }
            }
        }, radius: Radius.sheet) {
            HStack(spacing: Space.m) {
                // **No `.contentShape(.accessibility, …)` on the glyph**, which
                // was here first and cost the card its own frame: driving the
                // AX lane measured this card at **64×64** — the icon alone —
                // against 176–212 pt for its three siblings, because pinning an
                // accessibility shape onto a child is what SwiftUI then derives
                // the button's frame from. PRD-19's fix belongs on a *leaf*
                // control; a card is not one.
                // **A tile, not a loose glyph.** The audit found the icon
                // "optically unanchored, sitting low-left with its optical
                // centre well below the title baseline": a bare SF Symbol in a
                // 64pt box centres on the *glyph's* tight bounds, and
                // `shareplay` is a wide, short mark, so it floated in the box
                // while the two mini-boards on the cards above it filled theirs
                // edge to edge. Giving it the same 64pt inset surface those
                // boards have makes the three left-hand columns one column.
                Image(systemName: "shareplay")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(accent)
                    .frame(width: 64, height: 64)
                    .couchInset(
                        in: RoundedRectangle(
                            cornerRadius: Radius.inner(Radius.sheet, inset: 18),
                            style: .continuous),
                        tint: accent.opacity(0.14))
                VStack(alignment: .leading, spacing: Space.xs) {
                    // `body`, not `caption`. A card title set at the same rung
                    // as its own blurb has no hierarchy inside it, and all three
                    // card families shipped that way.
                    Text(ParlorPhrase.start)
                        .couchText(CouchTypography.body)
                    Text(pending == nil ? ParlorPhrase.startCaption : ParlorPhrase.inviteAccepted)
                        .couchText(CouchTypography.caption, .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            // **On the card, not on the glyph.** Without it the AX lane measured
            // this card at 298×**33** — the two text lines alone, with the SF
            // Symbol contributing nothing, because SwiftUI derives an image-only
            // element's frame from the symbol's tight glyph bounds
            // (EXECUTING-A-PRD §4). 33 pt is under the craft charter's 44 pt
            // floor, which is the same defect PRD-24's tier cards shipped at
            // 41 pt and the same fix.
            .contentShape(.accessibility, Rectangle())
        }
        .disabled(composeInFlight)
        .accessibilityLabel(Strings.string(
            "shelf.difficulty.label",
            .text(ParlorPhrase.start),
            .text(pending == nil ? ParlorPhrase.startCaption : ParlorPhrase.inviteAccepted)))
    }

    /// The full-width Nocturne card: same tap target, same MiniBoard, laid out
    /// along the row instead of down a column. No lock, no badge, no price —
    /// it is a peer of the three above it and reads like one.
    private func deepEndCard(_ difficulty: Difficulty) -> some View {
        TouchCard(action: { model.startFree(difficulty) }, radius: Radius.sheet) {
            HStack(spacing: Space.m) {
                MiniBoard(difficulty: difficulty, accent: accent,
                          corner: Radius.inner(Radius.sheet, inset: 18))
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Label {
                        Text(Strings.difficulty(difficulty))
                    } icon: {
                        if let glyph = difficulty.glyph { Image(systemName: glyph) }
                    }
                    .couchText(CouchTypography.body)
                    // The composing caption replaces the blurb rather than
                    // stacking under it: a card that grows a line mid-compose
                    // shoves the rest of the shelf down while the player watches.
                    Text(model.composing == .free(difficulty)
                         ? (difficulty.composeCaption ?? Strings.string("status.composing"))
                         : difficulty.blurb)
                        .couchText(CouchTypography.caption, .secondary)
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
        TouchCard(action: { model.startFree(difficulty) }, radius: Radius.card) {
            VStack(spacing: Space.s) {
                // Concentric with the card it is dropped into: a 22pt corner
                // with 18pt of padding wants `Radius.inner`, not the 24pt
                // default `MiniBoard` carries for a card that is no longer 24.
                MiniBoard(difficulty: difficulty, accent: accent,
                          corner: Radius.inner(Radius.card, inset: 18))
                    .frame(width: 64, height: 64)
                if model.composing == .free(difficulty) {
                    statusLabel(Strings.string("status.composing"), symbol: "sparkles")
                } else {
                    Text(Strings.difficulty(difficulty))
                        .couchText(CouchTypography.body)
                    Text(difficulty.blurb)
                        .couchText(CouchTypography.caption, .secondary)
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
    /// The card's own corner.
    ///
    /// **One radius across a 111pt → 362pt size range is not one radius**, it is
    /// 22% of a small tile and 6.6% of the hero — two different shapes wearing
    /// the same number. Callers pick a rung from `Radius`: `card` (22) for the
    /// tiles and the tracker rows, `sheet` (28) for Today, Continue and the
    /// full-width bands. Defaulted, so `ChannelShelf`'s three call sites and
    /// every other existing one compile and render exactly as they did.
    var radius: CGFloat = 24
    /// The one surface on screen that outranks the others gets the player's
    /// accent *in* its glass (CouchKit's L3 rung). Nil is the shipped
    /// `.regular.interactive()` treatment, which is what every card but Today
    /// still wants: a shelf where everything is primary has no primary.
    var tint: Color? = nil
    @ViewBuilder let content: Content

    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Button(action: action) {
            content
                .padding(18)
                .modifier(TouchCardSurface(shape: shape, tint: tint,
                                           isLight: theme.tones(for: colorScheme).isLight))
        }
        .buttonStyle(TouchCardStyle())
    }
}

/// The card's material and its lift, factored out only because the tinted and
/// untinted rungs are two different modifiers and a `some View` body cannot
/// return both from an `if` without one.
private struct TouchCardSurface: ViewModifier {
    let shape: RoundedRectangle
    let tint: Color?
    let isLight: Bool

    func body(content: Content) -> some View {
        Group {
            if let tint {
                content.couchGlassTinted(tint, in: shape)
            } else {
                content.couchGlassInteractive(in: shape)
            }
        }
        // **The `.clipShape` that used to be here is gone.** `glassEffect(in:)`
        // already clips to the shape it is given, so the second clip was
        // redundant — and it was not free: a clip is a mask, and a mask cuts off
        // the elevation shadow, which is why every card on this shelf sat flush
        // against the page with no edge for the material to catch.
        .couchElevated(in: shape, isLight: isLight)
    }
}

struct TouchCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CardBody(configuration: configuration)
    }

    /// A nested `View`, and that is the whole trick.
    ///
    /// `ButtonStyle.makeBody` is not a `View` body, so `@Environment` declared
    /// on the style itself is never updated — which is why this style read
    /// `isPressed` and nothing else while **four card families** call
    /// `.disabled(composeInFlight)`. During a Nocturne compose (p99 ~34s on a
    /// phone, DEVIATIONS) five cards therefore looked completely alive and ate
    /// every tap: exactly the failure the doc comment on `composeInFlight`
    /// promises is fixed. Dimmed *and* desaturated, because a dim card on a
    /// dark ground is a weak signal on its own and the accent is the loudest
    /// thing on the shelf.
    /// **Not named `Body`**, and internal rather than `private`. `ButtonStyle`
    /// declares `associatedtype Body: View`, so a nested type called `Body` is
    /// taken as that witness and collides with `makeBody`'s opaque return;
    /// and an opaque return type may not be less accessible than the
    /// requirement it satisfies, which rules out `private`. Nesting is what
    /// keeps it namespaced.
    struct CardBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .opacity(isEnabled ? 1 : 0.4)
                .saturation(isEnabled ? 1 : 0)
                .animation(.couchFast, value: configuration.isPressed)
                .animation(.couchFast, value: isEnabled)
        }
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
    /// The digit an in-flight flick is currently aimed at, drawn as a ghost in
    /// the header (W2B's `TouchRose.onLiveFocus`). Nil the instant the stroke
    /// becomes unclassifiable or the finger lifts — a preview that lingered
    /// after the commit would be describing a stroke that is over.
    @State private var liveFlickDigit: Int?
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
    /// PRD-28 §7's party URL, once an activity has been started for this board.
    @State private var sentBoard: SentBoard?
    /// The Afterglow has had its 2.4s and the completion chip may land. Real
    /// state, so the chip's `.transition` has a change to animate — see
    /// `completionChip`.
    @State private var afterglowSettled = false
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

    /// The board's palette, for the chrome that has to agree with it — the
    /// header's error coral, the pad's digit tone, the rose's backdrop.
    private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }

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
        // The completion chip's gate. Shaped exactly like `BoardView`'s
        // `runEventWindow`, and for the reason recorded on `renderShareCard`:
        // `Task.sleep` returns *immediately* when a task is cancelled, so a
        // sleep whose only outcome is a flag can strand that flag forever if
        // anything re-runs the task mid-wait. Recomputing the remaining time
        // from `solvedAt` on every run means a cancelled wait is repaired by
        // the next one instead of losing the chip.
        .task(id: model.solvedAt) {
            guard let solvedAt = model.solvedAt else {
                afterglowSettled = false
                return
            }
            let remaining = Self.afterglowHold - Date().timeIntervalSince(solvedAt)
            guard remaining > 0 else {
                withAnimation(.couchFast) { afterglowSettled = true }
                return
            }
            afterglowSettled = false
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.couchFast) { afterglowSettled = true }
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

        /// **The bottom insets are measured now, not tabulated.**
        ///
        /// They used to be four literals per fork — 150 / 196 / 174 — chosen
        /// against a bottom cluster that was always a 58pt key row plus a 60pt
        /// bar. Round 3 makes the pad the elastic member of the composition (it
        /// is what absorbs the height a square board cannot use, and it ranges
        /// from an 82pt one-row tray to a 308pt 3×3 block), so a literal that
        /// clears the cluster on an iPhone 17 Pro prints straight across the
        /// keys on a Pro Max. The caller measures the cluster and every bottom
        /// inset is that number plus a rung.
        ///
        /// The top still forks at the toolbar, and for the reason it always
        /// did: the header occupies 8…52, so 64 clears it, and a control bar
        /// parked above the board adds its own 68.
        static func column(controlsAtBottom: Bool, cluster: CGFloat) -> ChromeInsets {
            ChromeInsets(chip: cluster + Space.s,
                         completion: cluster + Space.hero + Space.s,
                         top: controlsAtBottom
                            ? 64
                            : 64 + CGFloat(BoardCompositionRules.columnToolbarBlock),
                         debriefGrabber: cluster + Space.xxl)
        }

        /// The table's board is its own column, so the only chrome any of this
        /// has to dodge is the outer padding.
        static let table = ChromeInsets(chip: 20, completion: 64, top: 12, debriefGrabber: 44)
    }

    /// The phone's stack: a permanent header, the board, a nine-key digit pad,
    /// a flexible band and the control bar — plus the stats drawer you find by
    /// pulling down.
    ///
    /// **What used to be here was a board and two empty bands.** Measured on a
    /// 402×874 phone the board card ran y≈227→613, leaving 168pt above it and
    /// 174 below — 342 of 874 points, roughly 137,500pt² of a 351,000pt² canvas
    /// showing nothing at all, because the bands' only two possible occupants (a
    /// timer chip and an ambient chip) both ship off. Meanwhile the difficulty
    /// appeared nowhere on this screen, the mistake count only inside a drawer
    /// reached by an unhinted pull-down, and there was no persistent digit entry
    /// anywhere in the frame: the rose exists solely as an overlay that is there
    /// while `rose != nil`.
    ///
    /// So the free space is now the screen's chrome rather than its absence.
    /// The header and the pad are unconditional rows rather than band occupants
    /// — `band(_:)` collapses whichever edge the board is anchored to, and a
    /// header that vanished on `boardAnchor == .top` (the default since wave 1)
    /// would be a header nobody has.
    ///
    /// **The pad has moved out from under the board and into the bottom
    /// cluster, which reverses a decision this comment used to defend.**
    ///
    /// What it said was: *"the pad sits directly under the board, above the
    /// flexible band — put the band between them and the surplus opens up
    /// inside the composition"*. That reasoning is sound and the frame it
    /// produced was still wrong, because it only moved the hole. With the pad
    /// welded to the board, `boardAnchor == .center` split the residual into a
    /// gap above the board **and** a gap between the pad and the toolbar, and
    /// then the toolbar itself floated clear of the home indicator: three
    /// unequal voids, reported on the phone as "three unrelated islands" and on
    /// the iPad as "~130pt between the pad and the toolbar and ~90pt below it".
    ///
    /// A screen has one bottom edge. The pad and the toolbar are now one
    /// cluster with a single `Rhythm.cluster` gap inside it, docked to the
    /// bottom safe area.
    ///
    /// **And round 3 stops giving the chrome parking spaces.** Two blind panels
    /// measured the frame this comment used to describe and reported the same
    /// two blockers on it: *"~200pt dead band between board and keypad; board
    /// undersized for the canvas"* and *"the glass is a flat gray fill — nothing
    /// refracts"*. Those are one defect. A lens has nothing to show over a void,
    /// and Nine was putting its bars over 200pt of empty ground and then asking
    /// the material to perform.
    ///
    /// Three changes, and they only work together:
    ///
    ///  * **The board takes the width.** `boardInset` went 12 → 8 and the height
    ///    term stopped charging the column's left-and-right gutters against its
    ///    height, so the grid is 370 of a 402pt phone rather than 362 — and,
    ///    more to the point, the board card's ring stopped reading as a bezel.
    ///  * **The chrome sits *on* the board.** The header capsule and the bottom
    ///    cluster each reach `columnChromeOverlap` (12pt) onto the plane —
    ///    8 of ring and 4 of a row's dead margin, so nothing legible is ever
    ///    covered — which is what finally puts a card rim, a grid rule and two
    ///    cell fills behind every pane of glass on this screen.
    ///  * **The digit pad spends the surplus.** A square board cannot use the
    ///    height a 9:19.5 canvas has spare; the pad deepens until the residual is
    ///    gone. On a 402×781 safe area that is a 3×3 block of 113×84 keys and
    ///    **zero** points of dead band, against 37×58 keys and ~170 before.
    ///    `DraftingTableTests.testNoPhoneLeavesADeadBandBiggerThanTheRhythmCeiling`
    ///    pins it on five phones rather than on the one someone opened.
    ///
    /// The two flexible bands stay, because `boardAnchor` is a preference and a
    /// pref that silently stops doing anything is worse than one that does
    /// little. On a phone they resolve to nothing; on an iPad in portrait, where
    /// a square board genuinely cannot spend the height, they are what centres
    /// the board between the two docked clusters — which is exactly the escape
    /// `Rhythm`'s own rule names.
    private func boardColumn(side: CGFloat, in size: CGSize) -> some View {
        let controlsAtBottom = model.prefs.controlsAtBottom
        let inset = CGFloat(BoardCompositionRules.boardInset)
        let plane = side + 2 * inset
        let overlap = CGFloat(BoardCompositionRules.columnChromeOverlap)
        // The pad's share, and the shape it takes with it.
        let budget = BoardCompositionRules.columnPadBudget(
            height: Double(size.height), plane: Double(plane))
        let rows = BoardCompositionRules.padRows(planeWidth: Double(plane), budget: budget)
        let keyHeight = CGFloat(BoardCompositionRules.padKeyHeight(
            planeWidth: Double(plane), budget: budget))
        let padHeight = CGFloat(BoardCompositionRules.padHeight(
            planeWidth: Double(plane), budget: budget))
        // What the bottom cluster occupies, for the chips that have to clear it
        // and for the pull-up that must not start inside it.
        let cluster = padHeight + (controlsAtBottom
            ? Space.l + CGFloat(BoardCompositionRules.columnToolbarBlock)
            : Rhythm.dock)
        // Whatever the pad could not use. Zero on every phone; on an iPad in
        // portrait it is the air the board is centred in.
        let freeSpace = max(0, size.height - plane - padHeight
                            - CGFloat(BoardCompositionRules.columnChromeFixed))
        return chromed(
            // `spacing: 0`, and every gap below is explicit — because two of
            // them are *negative*. A `VStack` cannot be told to overlap; it can
            // only be handed children whose frames already do.
            VStack(spacing: 0) {
                // The header is the one piece of chrome that does *not* recede
                // under an open rose: it is carrying the live-flick ghost, and
                // dimming the preview the player is steering by would be the
                // scrim undoing the feature it was added beside.
                //
                // `zIndex`, because a `VStack` paints in declaration order and
                // the board is declared after this — without it the capsule
                // would be the thing being overlapped rather than the thing
                // doing the overlapping.
                gameHeader
                    .padding(.bottom, -overlap)
                    .zIndex(2)
                if !controlsAtBottom {
                    controlBar.opacity(chromeDim).zIndex(2)
                }
                band(.top, freeSpace: freeSpace)
                boardArea(side: side, inset: inset)
                band(.bottom, freeSpace: freeSpace)
                bottomCluster(planeWidth: plane,
                              columns: BoardCompositionRules.padColumns(rows: rows),
                              keyHeight: keyHeight,
                              controlsAtBottom: controlsAtBottom)
                    .padding(.top, -overlap)
                    .zIndex(2)
            }
            .padding(.horizontal, CGFloat(BoardCompositionRules.columnHorizontalPadding) / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity),
            insets: .column(controlsAtBottom: controlsAtBottom, cluster: cluster),
            revealHeight: size.height,
            // The pull-up may not begin inside the bottom cluster, and the
            // cluster is no longer a fixed height — see `controlBarReserve`,
            // which survives as the floor rather than as the answer.
            controlBarReserve: max(Self.controlBarReserve, cluster)
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

    /// The column's one bottom edge: entry, then tools, and nothing between
    /// them but a single spacing rung.
    ///
    /// **The pad is exactly as wide as the board's glass plane**, which is the
    /// cheapest structural fix available for the "stretched full-width ribbon
    /// of squat pills" the iPad audit reported. On a 402pt phone the plane is
    /// 386 and the keys land at 37×58 — the shipped shape, unmoved. On an 834pt
    /// iPad the plane is 818, the keys land at 85 wide, and the height follows
    /// the width up to a square: 85×84 keys in a cluster that lines up with the
    /// grid above it instead of running past it to both screen edges.
    ///
    /// One `CouchGlassContainer` around both, so the tray and the toolbar are
    /// in the same glass system and merge as one pane. They were two separate
    /// material treatments a `Space.m` apart — a rounded tray with keys in it,
    /// and five bare stroked circles on the page — which the phone audit called
    /// "the single most non-native element in the frame".
    ///
    /// **The tray is `padTrayInset` narrower than the board's plane on each
    /// side**, and that is what makes the 12pt overlap above it read as one
    /// surface lying on another rather than as two slabs butted together: the
    /// board's bottom corners come out past the tray on both sides, so the eye
    /// can see which object is in front.
    private func bottomCluster(
        planeWidth: CGFloat, columns: Int, keyHeight: CGFloat, controlsAtBottom: Bool
    ) -> some View {
        CouchGlassContainer(spacing: Space.m) {
            VStack(spacing: Rhythm.cluster) {
                digitPad(
                    planeWidth: planeWidth
                        - 2 * CGFloat(BoardCompositionRules.padTrayInset),
                    columns: columns,
                    keyHeight: keyHeight
                )
                .opacity(chromeDim)
                if controlsAtBottom { controlBar.opacity(chromeDim) }
            }
        }
        // The toolbar carries its own dock to the safe area; without it at the
        // bottom the pad would be the thing sitting on the home indicator.
        .padding(.bottom, controlsAtBottom ? 0 : Rhythm.dock)
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

    /// How wide a digit key gets in the table's rail.
    ///
    /// Three across at the rail's 360pt, less its 16pt padding and two 12pt
    /// gutters, is (360 − 32 − 24) / 3 ≈ **101pt**, which the audit's "roughly
    /// 84×84 at 12pt gutters" is asking for and slightly better than.
    private static let railPadColumns = 3

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
            // PRD-28 §5's dot row, stacked with the composing chip rather than
            // fighting it for the same inset. Both are top-of-board chrome and
            // both can be up at once — a parlor board composes like any other.
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    composingChip
                    parlorRow
                }
                .padding(.top, insets.top)
            }
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
    ///
    /// **Round 2 gave the rail the two things the landscape frame was missing
    /// and took away the one it had twice.**
    ///
    ///  * *The readouts.* The drafting table had no header at all — no
    ///    difficulty, no mistake count, no squares-left — because those live in
    ///    `gameHeader`, which only the column draws. The rail carries
    ///    `railHeader` now, so the iPad knows what board it is on.
    ///  * *Entry.* There was no digit pad on this composition. The audit's
    ///    blocker was that ~35% of the landscape canvas was empty black below
    ///    the rail, with the fix stated exactly: *"fill the right column with
    ///    the 1-9 entry pad (with per-digit remaining counts, which the dashed
    ///    rings are already trying to convey)"*. Same `DigitPadRow`, three
    ///    across.
    ///  * *The second clock.* `timerChip` sat here **and** `StatsDrawerContent`
    ///    draws a `time` tile, so the elapsed time was on screen twice — and
    ///    the chip was the one that clipped, rendering "0:2" with a half-cut
    ///    "4" past its own edge. The chip is gone; the promoted, tabular clock
    ///    in `railHeader` is the one that stays. (The stats tile is
    ///    `StatsDrawer.swift`'s to retire — see `crossFileNeeds`.)
    private func statsRail(width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
        return VStack(spacing: Space.l) {
            railHeader
            digitPad(columns: Self.railPadColumns, keyHeight: 84)
            StatsDrawerContent(model: model)
            // The chip the phone parks in its free bands has no band here, and
            // the rail is where it belongs. Last rather than first: it is the
            // one thing in this column that is not about the board.
            if model.prefs.ambientSlot != .none, model.composing == nil {
                AmbientSlotView(model: model)
            }
        }
        .padding(Space.l)
        // **As tall as it has to be, and no taller.** The first version was a
        // full-height slab, and driving an 11" iPad showed what that is: 200 pt
        // of stats above 700 pt of empty glass, which reads as a panel that
        // failed to load rather than as a rail. A drawer is the height of what
        // is in it; leaving it open should not change that.
        .frame(width: width, alignment: .top)
        // `couchGlassElevated`, not `couchGlass`: on a near-black ground a pane
        // with no rim and no shadow has no boundary, which is the whole of the
        // "flat opaque fill plus a hairline, not a material" finding. The rim
        // is what tells the eye where the rail stops and the board field starts.
        .couchGlassElevated(in: shape, isLight: tones.isLight)
        // One container, so Switch Control's group scan treats the rail as a
        // place rather than as fourteen loose elements between the board and
        // the edge of the screen (PRD-19's grouping rule).
        .accessibilityElement(children: .contain)
    }

    // MARK: Chrome

    /// Five tools, centred, in one glass group.
    ///
    /// Six buttons (PRD-11 added the lightbulb and the wand) is two past what
    /// PROGRAM-2.0's anti-bloat constitution allows — a deliberate override,
    /// recorded in DEVIATIONS.md — and it cost the timer its seat here: six 44pt
    /// targets are 264pt, the timer chip measures ~82, and with gaps the row
    /// wanted ~422pt, measured clipping `Settings` 20pt off a 375pt SE. The
    /// timer is in the header now, where a game's primary readout belongs.
    ///
    /// **Two things about this row were wrong and both were arrangement.**
    /// `HStack { home; Spacer(); …five tools }` put the tool group's optical
    /// centre 65pt right of the screen's, with an 86pt hole beside a bare back
    /// chevron — a row that is neither centred nor edge-to-edge reads as a
    /// layout that gave up. And Home does not belong in a *tool* group at all:
    /// iOS puts back top-left, so it went to the header, beside the name of the
    /// board it leaves. What is left is five peers, centred, wrapped in a
    /// `CouchGlassContainer` so they participate in one glass system instead of
    /// reading as six isolated pebbles measured at 1.08:1 against the page.
    ///
    /// **Round 2: it is a bar, and it was five circles.** Every frame in the
    /// audit that showed this row said the same thing — "five detached circles
    /// with no bar", "bare stroked circles floating on black is the single most
    /// non-native element in the frame", "their stroke rings visually kiss".
    /// Five glass discs sitting loose on the page is not a toolbar; it is five
    /// objects that happen to be adjacent.
    ///
    /// The row is now one capsule of bar material with the five tools *inset*
    /// into it (`GlassIconButton(inBar: true)` drops each disc's own `.regular`
    /// pane, because `.regular` inside `.regular` is the glass-on-glass mistake
    /// CouchKit's L4 rung exists to end). The gutter goes from `Space.xs` to
    /// `Space.m`, which is the 12pt that stops the rings touching.
    private var controlBar: some View {
        // Container spacing > the row's own gap, so adjacent discs are inside
        // each other's merge distance and the group flows as one pane.
        CouchGlassContainer(spacing: Space.m) {
            HStack(spacing: Space.m) {
                hintButton
                pencilButton
                autoNotesButton
                undoButton
                settingsButton
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .couchGlassBar(in: Capsule(), isLight: tones.isLight)
        }
        .frame(maxWidth: .infinity)
        // `Rhythm.dock` — the same 8 it always was, said in the token that
        // `BoardCompositionRules.columnToolbarBlock` (44 + 2·`Space.s` + this)
        // is made of, so the two cannot drift apart by a point.
        .padding(model.prefs.controlsAtBottom ? .bottom : .top, Rhythm.dock)
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
    ///
    /// **Round 2 gives the five a container, exactly as the bar got one.** The
    /// landscape audit: *"six naked circular buttons float unbounded on the
    /// left edge… the chevron is ~800px from the cluster with no container
    /// tying either to the board"*. Home stays where it is — separated, which
    /// is the navigation slot — and the five tools become one vertical capsule
    /// of bar material at a 12pt rhythm.
    private var controlColumn: some View {
        VStack(spacing: Space.m) {
            homeButton(seated: true)
            Spacer(minLength: Space.m)
            CouchGlassContainer(spacing: Space.m) {
                VStack(spacing: Space.m) {
                    hintButton
                    pencilButton
                    autoNotesButton
                    undoButton
                    settingsButton
                }
                .padding(.vertical, Space.m)
                .padding(.horizontal, Space.s)
                .couchGlassBar(in: Capsule(), isLight: tones.isLight)
            }
        }
        .padding(.vertical, Space.xs)
    }

    // The six, factored so the bar and the column cannot come to disagree
    // about what a control does — the failure mode a second copy invites.
    //
    // `inBar: true` on all six is not a style flag, it is the L4 rung: every
    // one of them is drawn *inside* a glass bar now (the toolbar capsule, the
    // control column's capsule, or the game header's), and a `.regular` disc
    // nested in a `.regular` bar is two lenses stacked, which reads as one
    // murkier surface rather than as a control on a bar.

    /// Back, and whether it wears a seat.
    ///
    /// **In the header it does not, and that is a reported blocker rather than a
    /// preference.** The finding was *"a nested circular back chip inside the
    /// capsule — button-in-a-button, radii not concentric"*, and it is right: a
    /// tinted disc drawn inside a glass bar is a second shape claiming to be a
    /// control on a surface that is already one. iOS puts back at the top-left
    /// as a bare chevron. The 44pt target, the label and the accessibility hit
    /// shape are all untouched; only the disc under the glyph is gone.
    ///
    /// The drafting table keeps its seat, because there the chevron is *not*
    /// inside a bar — it stands alone at the top of the control column, and an
    /// unseated glyph floating on the edge of an iPad is the "six naked circular
    /// buttons" finding coming back one button at a time.
    private func homeButton(seated: Bool) -> some View {
        GlassIconButton(symbol: "chevron.left",
                        label: Strings.string("game.control.home"),
                        inBar: true,
                        seated: seated) {
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
            accent: accent,
            inBar: true
        ) {
            toggleCoach()
        }
    }

    private var pencilButton: some View {
        GlassIconButton(
            symbol: "pencil",
            label: Strings.string("game.control.pencil"),
            active: pencilMode,
            accent: accent,
            inBar: true
        ) {
            pencilMode.toggle()
            pencilEverToggled = true
            dismissTip()
        }
    }

    /// **Not `wand.and.stars`.** At the row's 17pt its three sparkles render at
    /// roughly 2pt each and mush at 3×, and it sat two slots from `lightbulb` —
    /// so a first-timer met two magic buttons and no way to tell which one gives
    /// answers away. A filled corner of a 3×3 grid says "marks in the squares",
    /// which is what the wand actually does.
    private var autoNotesButton: some View {
        GlassIconButton(
            symbol: "square.grid.3x3.topleft.filled",
            label: Strings.string("game.control.autoNotes"),
            active: model.autoNotes,
            accent: accent,
            inBar: true
        ) {
            toggleAutoNotes()
        }
    }

    /// **Undo is the one tool with a real off state, and it had none.** Both
    /// panels wrote the same finding — *"add a disabled state for undo when the
    /// stack is empty"* — and it is not decoration: a control that looks
    /// pressable and does nothing is the cheapest possible way to make an app
    /// feel broken, and this one looks pressable on the first move of every
    /// board. `AppModel.canUndo` has existed since PRD-4 with no caller on this
    /// screen; `.disabled` routes it through `TouchCardStyle`'s own dim-and-
    /// desaturate, which is the same treatment four card families already use,
    /// and VoiceOver says "dimmed" for free.
    ///
    /// The DEBUG long-press rig goes quiet with it on a board with no moves yet;
    /// `--debug-fill` at launch is the route that still works there, and is what
    /// the tvOS build has always used.
    private var undoButton: some View {
        GlassIconButton(symbol: "arrow.uturn.backward",
                        label: Strings.string("game.control.undo"),
                        inBar: true) { performUndo() }
            .disabled(!model.canUndo)
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
                        label: Strings.string("game.control.settings"),
                        inBar: true) { showPrefs = true }
            .keyboardShortcut(",", modifiers: .command)
    }

    /// One of the two flexible bands around the board (PRD-2). The band on
    /// the anchored edge collapses and all free space collects in the other one,
    /// where a system PiP window can park. The board anchors to screen edges;
    /// the control bar never moves.
    ///
    /// **Round 3 leaves these bands with almost nothing to hold on a phone**,
    /// and that is the point rather than a side effect: the height a square
    /// board cannot use now goes to the digit pad, so `freeSpace` resolves to 0
    /// on every iPhone. They still exist because `boardAnchor` is a preference,
    /// and because an iPad in portrait genuinely does have height that nothing
    /// but air can spend — there, centring the board between two docked clusters
    /// is the "flexible spacer doing deliberate compositional work" that
    /// `Rhythm`'s own ceiling rule names as its one exception.
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
                    //
                    // **No clock chip here any more.** It was a 13pt
                    // `.secondary` chip parked in an empty band — the primary
                    // readout of a timed game, set as a footnote, in the one
                    // place on screen that nothing else claimed. It is the
                    // header's centre column now, in both compositions: the
                    // drafting table grew a `railHeader` in round 2 and the
                    // chip it used to carry is deleted.
                    HStack(spacing: Space.s) {
                        if showAmbient(in: edge, freeSpace: freeSpace) {
                            AmbientSlotView(model: model)
                        }
                    }
                }
        }
    }

    // MARK: The header (the readouts that were nowhere)

    /// Difficulty, clock, mistakes and squares left — the four things a sudoku
    /// player looks up, on screen permanently.
    ///
    /// Every one of them was missing or buried. `difficulty` appeared nowhere in
    /// this screen at all; `errorCount` rendered only inside `StatsDrawer`,
    /// behind a pull-down whose only hint is a 3pt capsule at 0.35 opacity that
    /// retires after three sessions; the clock was a footnote chip in a band.
    ///
    /// A `ZStack`, not an `HStack` with two spacers: the clock is centred on the
    /// *screen* rather than in whatever room the flanking groups leave, so it
    /// does not slide sideways when the mistake count appears or the difficulty
    /// name changes length. Its height is pinned so that swapping it for the
    /// live-flick ghost cannot move the board.
    ///
    /// **Round 2 gave it a material and a ramp, and it had neither.** Two
    /// findings, both about this row:
    ///
    ///  * *"Top bar has no material, no hairline, no scroll-edge treatment…
    ///    the chevron is a bubble and the counters are naked text at unequal
    ///    optical margins."* One glass bar around the whole row, with the
    ///    chevron inset into it rather than sitting on it as a second pane, is
    ///    the "unify the vocabulary: either every item is a glass capsule or
    ///    none is" half of the fix. A capsule and not a full-bleed plate,
    ///    because a plate's bottom edge is the hard seam this round exists to
    ///    delete — a floating bar has no edge to be hard.
    ///  * *"Header type ramp is flat — four peers, no primary."* The difficulty
    ///    drops a rung to `caption`, the clock stays the single `numeral`
    ///    anchor, and the two counters bind their glyph to their number at
    ///    `Space.hair` instead of `Space.xs` so each icon+number reads as one
    ///    unit rather than as four floating things at one size.
    private var gameHeader: some View {
        ZStack {
            headerCentre
            HStack(spacing: Space.s) {
                homeButton(seated: false)
                headerDifficulty
                Spacer(minLength: Space.s)
                headerMistakes
                headerRemaining
            }
        }
        .frame(height: Hit.min)
        .padding(.horizontal, Space.s)
        .couchGlassBar(in: Capsule(), isLight: tones.isLight)
        // The capsule is inset from the board's plane on both sides, so the
        // board comes out past it at the top corners and the 12pt overlap below
        // reads as a bar lying *on* the board rather than as a butt joint.
        .padding(.horizontal, Space.s)
        // `Rhythm.dock`, and it was `Space.xs`. A docked cluster's gap to the
        // safe area is a named rung now, and `columnHeaderBlock` (52 = this 8
        // plus the 44pt capsule) is the arithmetic the board's height term is
        // made of — so a 4 here would be a 4pt lie in `DraftingTable`.
        .padding(.top, Rhythm.dock)
        // One element per group for Switch Control's scan, and the same rule
        // PRD-19 puts on the stats rail: a header is a place, not five loose
        // readouts between the back button and the edge of the screen.
        .accessibilityElement(children: .contain)
    }

    /// The drafting table's header, which is the same four readouts without the
    /// back chevron — the table's Home lives at the top of the control column,
    /// where "out of here" belongs on a screen whose navigation is a column.
    ///
    /// Two lines rather than one because the rail is 360pt wide and a single row
    /// would squeeze the difficulty against the counters; and no bar material,
    /// because unlike the column's header this one is already *inside* a glass
    /// panel and a second pane in there is the nesting L4 exists to end.
    private var railHeader: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            headerDifficulty
            HStack(spacing: Space.s) {
                headerCentre
                Spacer(minLength: Space.s)
                headerMistakes
                headerRemaining
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// The clock — or, while a flick is in flight, the digit it is aimed at.
    ///
    /// The rose blooms *on* the cell it writes into and covers it, so a player
    /// mid-stroke cannot see the ghost `BoardView` is drawing under the petals.
    /// W2B's `onLiveFocus` hands the digit out for exactly this: the header is
    /// the one place on screen the rose never occludes.
    @ViewBuilder
    private var headerCentre: some View {
        if let liveFlickDigit {
            Text("\(liveFlickDigit)")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .transition(.opacity)
                // The board is where this digit is about to land, and VoiceOver
                // is not flicking — it commits through the actions rotor.
                .accessibilityHidden(true)
        } else {
            headerClock
        }
    }

    @ViewBuilder
    private var headerClock: some View {
        if model.prefs.showTimer, let game = model.game {
            if let solvedAt = model.solvedAt {
                // Stopped. A 1Hz timeline that redraws the same string would
                // only be competing with the Afterglow for frames.
                clockText(game, at: solvedAt)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    clockText(game, at: timeline.date)
                }
            }
        }
    }

    private func clockText(_ game: NineGame, at date: Date) -> some View {
        let elapsed = SolveCardFacts.elapsedText(game.timer.elapsed(at: date))
        // Label *and* value, not label alone: `accessibilityLabel` on a `Text`
        // replaces what it speaks, so naming this "time" without the value
        // would leave a VoiceOver player with a clock that never says a time.
        return Text(elapsed)
            // `numeral` is the ramp's tabular-figures rung — `.headline`
            // semibold rounded, which is the 17pt the audit asked for and
            // scales with Dynamic Type, and `.primary` because this is the
            // readout the screen is about. `couchText(_:)` sets that foreground
            // itself; chaining one after it would be dead code.
            .couchText(CouchTypography.numeral)
            .contentTransition(.numericText())
            .accessibilityLabel(Strings.string("board.stats.time"))
            .accessibilityValue(elapsed)
    }

    /// `caption`, a rung below the counters and two below the clock.
    ///
    /// It was `label` — the same rung the mistake count and the squares-left
    /// count are set at — so "Steady", "0:07", the red "1" and the "49" were
    /// four peers at one size, and the audit's finding was that the eye has to
    /// read the *icons* to work out which number is which. What this board is
    /// does not change while you play it; the numbers do.
    @ViewBuilder
    private var headerDifficulty: some View {
        if let title = boardKindTitle {
            Text(title)
                .couchText(CouchTypography.caption, .secondary)
                .lineLimit(1)
        }
    }

    /// What this board is: its difficulty, or its channel and tier, or the fact
    /// that it is a daily. Assembled from the same keys the shelf's own
    /// `boardTitle` uses, minus the date — the archive chip already says which
    /// day an archive board is.
    private var boardKindTitle: String? {
        switch model.kind {
        case .daily: return Strings.string("shelf.today.title")
        case .free(let difficulty): return Strings.difficulty(difficulty)
        case .channel(let channel, let tier, _):
            return Strings.string("shelf.channel.free",
                                  .text(Strings.channel(channel)),
                                  .text(Strings.variantTier(tier)))
        case nil: return nil
        }
    }

    /// Wrong digits placed on this board, in the board's own error colour.
    ///
    /// Absent at zero rather than showing "0", which is the same honest-absence
    /// idiom the stats drawer's own error tile uses: a board nobody has slipped
    /// on should not carry a mistake counter at all.
    @ViewBuilder
    private var headerMistakes: some View {
        if let game = model.game, model.prefs.errorHighlight, game.errorCount > 0 {
            headerReadout("xmark.circle", "\(game.errorCount)",
                          tint: AnyShapeStyle(tones.coral))
                .accessibilityLabel(Strings.string("board.stats.errors"))
                .accessibilityValue("\(game.errorCount)")
                .transition(.opacity)
        }
    }

    /// Squares still empty. The same arithmetic the digit pad's counts are made
    /// of, summed — so the two can never disagree about how much board is left.
    @ViewBuilder
    private var headerRemaining: some View {
        if let game = model.game, model.solvedAt == nil {
            let left = digitsRemaining(game).reduce(0, +)
            headerReadout("square.grid.3x3", "\(left)",
                          tint: AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .accessibilityLabel(Strings.string("presence.remaining", .int(left)))
        }
    }

    /// `Space.hair`, not `Space.xs`: a glyph and the number it counts are one
    /// unit, and at 4pt they read as two. The optical-separator rung is exactly
    /// the "touching, but not one thing" gap this wants.
    private func headerReadout(
        _ symbol: String, _ value: String, tint: AnyShapeStyle
    ) -> some View {
        HStack(spacing: Space.hair) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(value)
                .font(CouchTypography.label)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
    }

    // MARK: The digit pad (the entry that was nowhere)

    /// Nine keys, each carrying how many of that digit are still unplaced.
    ///
    /// **There was no persistent digit entry anywhere in this frame.** The rose
    /// is an `.overlay` that exists only while `rose != nil`, so a player who
    /// has not yet discovered that tapping a cell blooms a ring has no visible
    /// way to enter a number at all — on a screen whose entire purpose is
    /// entering numbers. The rose stays exactly as it is and remains the fast
    /// path; this is the discoverable one, and it is also the only surface that
    /// answers "how many 7s are left" without opening anything.
    ///
    /// Both routes end in the same `commit(digit:)`, so pencil mode, the erase
    /// rim, the haptics and the tip budget cannot come to disagree.
    ///
    /// **The shape is entirely the caller's**, and the callers want different
    /// ones. The drafting table's rail asks for three across at 84pt tall, which
    /// is what turns a 360pt column of empty glass into the entry surface the
    /// landscape frame did not have at all. The column asks for whatever shape
    /// closes its composition — nine across on an iPad in portrait, 5 + 4 on a
    /// short phone, and a 3×3 block on a tall one, resolved by
    /// `BoardCompositionRules.padRows` off the height the board could not use.
    ///
    /// **The 3×3 case is the one worth naming.** This file's own header says the
    /// rose commits by "the same 3×3 keypad mapping as tvOS", and the board is
    /// made of 3×3 boxes; until round 3 the one surface that could have taught
    /// either was a nine-across ribbon of 37×58 slivers that taught neither. The
    /// discoverable grammar and the fast one now have the same geometry.
    @ViewBuilder
    private func digitPad(
        planeWidth: CGFloat? = nil, columns: Int = 9, keyHeight: CGFloat
    ) -> some View {
        if let game = model.game {
            DigitPadRow(
                remaining: digitsRemaining(game),
                pencil: pencilMode,
                tint: accent,
                tones: tones,
                columns: columns,
                keyHeight: keyHeight,
                maxWidth: planeWidth,
                onDigit: { commit(digit: $0) }
            )
            // A solved board takes no input — `AppModel.place` refuses it — and
            // the pull-up debrief wants this whole region as a drag surface.
            // Dimmed rather than removed: taking a 68pt row out of the stack on
            // the winning placement would shove the board mid-Afterglow.
            .disabled(model.solvedAt != nil)
            .opacity(model.solvedAt != nil ? 0.35 : 1)
        }
    }

    // **`padKeyHeight` has moved and changed its question.** It used to derive a
    // key's height from its own width, which is the right rule for a row that
    // has already been told how wide it is and the wrong one for a pad that is
    // now the composition's shock absorber. It is
    // `BoardCompositionRules.padKeyHeight(planeWidth:budget:)`, it takes the
    // height the board could not use, and `DraftingTableTests` sweeps it.

    /// How many of each digit 1…9 are still to be placed, index 0 = digit 1.
    /// The same expression `StatsDrawerContent` feeds its ring row.
    private func digitsRemaining(_ game: NineGame) -> [Int] {
        (1...9).map { max(0, 9 - game.count(of: $0)) }
    }

    /// The rose's backdrop, for everything that is not the board.
    ///
    /// The scrim itself lives inside `boardArea`'s overlay, because that is the
    /// only place it can be *under* the petals and over the grid — and the grid
    /// is where the bug was. But a screen whose board dims while its pad and
    /// toolbar stay at full strength reads as a bug of its own, so those recede
    /// by roughly the same amount. The header is exempt: it is showing the
    /// live-flick ghost, and dimming that would be the backdrop undoing the
    /// feature it landed beside.
    ///
    /// It is one `.opacity` rather than a fourth scrim view: the surrounding
    /// pixels are the theme's ground, and dimming chrome *toward* the ground is
    /// what a scrim over it would have done anyway, without the compositing pass
    /// or the hit-testing question.
    private var chromeDim: Double { rose == nil ? 1 : 0.45 }

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
        // **`Hit.min`, and it was 100.** The threshold was measured against a
        // composition with 170pt bands in it; round 3 spends that height on the
        // board and the pad, so a 100pt gate would have quietly turned an opt-in
        // preference into a no-op on every phone. A `GlassChip` is ~32pt tall
        // and the touch floor is the honest question — *is there room for it* —
        // rather than a number left over from a layout that no longer exists.
        // On a phone the answer is now usually no, which is the deliberate
        // trade: the ambient chip lived in the void this round deleted.
        return bandHeight >= Hit.min
    }

    /// PRD-28 §5. Present only inside a parlor, and silent the rest of the time
    /// — there is no empty state, because a row of nobody is not a thing to
    /// draw. A solo room (`isShared == false`) draws nothing either: one dot,
    /// yours, telling you what your own board already says.
    @ViewBuilder
    private var parlorRow: some View {
        if let room = model.parlor.room, room.isShared, model.game != nil, rose == nil {
            ParlorPresenceRow(room: room, accent: accent)
                .transition(.opacity)
        }
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

    // **`timerChip` is gone, and its absence is the fix.** It was the drafting
    // table rail's only caller, sitting directly above a `StatsDrawerContent`
    // that draws a `time` tile of its own — so the landscape frame showed the
    // elapsed time twice, and the chip was the copy that clipped: measured
    // rendering "0:2" with a smeared, half-cut "4" past its own edge, because a
    // `GlassChip` sizes to proportional figures and a clock re-measures every
    // second. The promoted, tabular clock in `railHeader` is the one that
    // stays.

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
    ///
    /// **The wait is a `.task`, not a `TimelineView`.** It was a
    /// `TimelineView(.periodic(from: solvedAt, by: 0.5))` whose body carried
    /// `if timeline.date.timeIntervalSince(solvedAt) > 2.4`, which is a
    /// *re-evaluation* rather than a state change — so the `.transition` on it
    /// had nothing to animate from and the chip that announces the end of a
    /// twenty-minute solve simply appeared. One `@State` flipped inside
    /// `withAnimation` gives the same 2.4s gate an actual transition, and stops
    /// a 2Hz timeline running for the whole time the solved board is on screen.
    ///
    /// The chip is `.hero` now: it reported that solve in the same grey 13pt
    /// footnote as the undo toast.
    @ViewBuilder
    private var completionChip: some View {
        if model.solvedAt != nil, afterglowSettled {
            // Read the card **here**, in the body, and pass it in. Read inside
            // an escaping closure instead and it is always nil: the closure
            // captures a copy of this view struct whose `@State` is a snapshot
            // from when the closure was made — and this one is made before the
            // render lands, 70 ms after the solve. Driving the app found it: the
            // renderer logged "assigned, shareCard=set" once and every
            // subsequent evaluation of the button logged "shareCard=nil", 30
            // times running, with the PNG sitting on disk the whole time.
            let card = shareCard
            HStack(spacing: Space.s) {
                GlassChip(completionText, systemImage: "checkmark",
                          emphasis: .heroTint(accent))
                shareButton(card)
                sendBoardButton
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
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// How long the Afterglow owns the screen. The chip waits it out rather
    /// than landing on top of the luminance wave.
    private static let afterglowHold: TimeInterval = 2.4

    private var completionText: String {
        if case .daily? = model.kind, model.displayedStreak > 0 {
            return Strings.string("game.completion.streak", .int(model.displayedStreak))
        }
        return Strings.string("status.solved")
    }

    // MARK: Send this board (PRD-28 §7)

    /// The asynchronous half of the parlor: the board you just solved, sent to
    /// somebody to play whenever they like.
    ///
    /// **Absent unless App Store Connect has the activity definition.** That
    /// record does not exist yet and creating it is a human gate, so on every
    /// build shipped before it lands this is simply not there — which is the
    /// right failure mode for a social affordance and the same one PRD-24's
    /// per-channel leaderboards ship with.
    ///
    /// A variant board has no invite (`currentInvite` is nil for `.channel`),
    /// because the seed alone would hand the receiver a grid without its cages.
    @ViewBuilder
    private var sendBoardButton: some View {
        if #available(iOS 26.0, *), GameCenter.shared.canSendBoard,
           let invite = model.currentInvite {
            Button {
                sentBoard = GameCenter.shared.sendBoard(invite).map(SentBoard.init)
            } label: {
                GlassChip(ParlorPhrase.challenge, systemImage: "person.2")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ParlorPhrase.challenge)
            // The party URL exists only once the activity has started, so it
            // cannot be a `ShareLink`'s item the way the share card's PNG is —
            // `ShareLink` needs its item before the tap. The system sheet is
            // presented instead, which is also what makes this one tap rather
            // than two.
            .sheet(item: $sentBoard) { board in
                SystemShareSheet(items: [board.url])
                    .presentationDetents([.medium])
            }
        }
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
                    parlor: model.parlor.room?.members ?? [],
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
                axActions: axActions,
                // W2B wrote the placement settle, the erase echo and the error
                // shake and nothing fed them — three animations, all dead code,
                // because `lastEvent` had no caller. `AppModel` sets it beside
                // the move it describes, so the picture and the haptic fire off
                // the same event rather than off two guesses at it. Identity
                // under Reduce Motion, inside `BoardView`.
                lastEvent: model.lastCellEvent
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
                    // **The backdrop, at last.** This was
                    // `Color.black.opacity(0.001)` — a hit-test shim, three
                    // levels of nothing — and `BoardView`'s own
                    // `.opacity(roseOpen ? 0.82 : 1.0)` was a 3-RGB-level no-op
                    // over the ground, so the board under the petals was
                    // effectively undimmed. What that costs is not subtlety, it
                    // is *false information*: the accent cursor ring and a coral
                    // error mark refract up through petals 2 and 3 and fabricate
                    // "selected" and "error" states the rose never rendered.
                    //
                    // Clipped to the board card's own corner rather than drawn
                    // as a rectangle: the overlay's frame is the padded plane, so
                    // a square scrim would print four hard corners onto the
                    // ground around a rounded card. The radius is `BoardView`'s
                    // `cardRadius`, restated — that property is private and the
                    // file is on the watch target, so this is the same
                    // deliberate second copy `BoardInk` is.
                    RoundedRectangle(cornerRadius: max(28, 36 * side / BoardMetrics.side),
                                     style: .continuous)
                        .fill(tones.isLight ? Color.white.opacity(0.38)
                                            : Color.black.opacity(0.34))
                        // The whole plane still cancels, corners included.
                        .contentShape(Rectangle())
                        .onTapGesture { closeRose() }
                        .transition(.opacity)
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
                        notedDigits: Set(game.pencilDigits(at: cursor)),
                        // The petals' numerals in the theme's own digit tone,
                        // so a rose over Blueprint stops being off-palette.
                        digitTone: tones.digitTone,
                        // The rose covers the cell it writes into; the header
                        // shows what the stroke is currently aimed at.
                        onLiveFocus: { digit in
                            withAnimation(.couchFast) { liveFlickDigit = digit }
                        }
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
        // The ghost describes a stroke, and there is no stroke once the ring is
        // gone. `onLiveFocus(nil)` fires on lift as well, so this is the
        // belt-and-braces half for the paths that close the rose without one —
        // Esc, a cursor move, the coach, going home.
        liveFlickDigit = nil
    }

    /// One digit, committed — from a petal, from a pad key, or from the
    /// keyboard's own path.
    ///
    /// **The rose is no longer the precondition, only a source of one.** This
    /// opened `guard let state = rose else { return }`, so routing the digit pad
    /// through it — which is what stops the two entry grammars drifting — would
    /// have made every pad key a silent no-op. Where the rose is open its
    /// `pencil` still decides, exactly as before; where it is not, the rule is
    /// the one `openRose` would have applied at this cell, so a pad key in
    /// pencil mode notes and a pad key on a filled cell writes.
    private func commit(digit: Int) {
        guard let game = model.game, model.solvedAt == nil else { return }
        let pencil = rose?.pencil ?? (pencilMode && game.entry(at: cursor) == 0)
        if pencil {
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
            // The same glyph the button now wears — a feature whose chip and
            // whose control show different symbols is two features.
            GlassChip(autoNotesChip, systemImage: "square.grid.3x3.topleft.filled")
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
    /// This button is drawn **inside** a glass bar (the game toolbar, the
    /// drafting table's control column, the game header's capsule).
    ///
    /// Defaulted false, so every call site that predates round 2 renders exactly
    /// what it rendered — the shelf's calendar and gear are still standalone
    /// discs on the page, which is correct: they sit on the shelf bar's own
    /// material and are the only two controls there.
    ///
    /// Inside a bar it matters, and it is the L4 rung again: a `.regular` disc
    /// nested in a `.regular` bar is two lenses stacked, which reads as one
    /// murkier surface. Worse, each disc was carrying its own drop shadow — five
    /// shadows *inside* a toolbar, which is a shadow cast onto the thing casting
    /// it. In a bar the disc is shape and tint and nothing else, and the state
    /// ring is what does the talking.
    var inBar = false
    /// Whether this button draws a seat under its glyph at all.
    ///
    /// Defaulted true, so every call site that predates round 3 is unchanged.
    /// The one caller that passes false is the game header's back chevron, and
    /// the finding it answers is *"a nested circular back chip inside the
    /// capsule — button-in-a-button, radii not concentric"*. An unseated button
    /// is still a 44pt target with a 44pt accessibility shape and a label; it
    /// simply stops claiming to be a second surface on a surface.
    ///
    /// Only meaningful with `inBar` — outside a bar the seat *is* the button.
    var seated = true
    let action: @MainActor () -> Void

    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { theme.tones(for: colorScheme).isLight }

    /// An active tool inside a bar gets a tinted seat, not just a ring — the
    /// audit asked for "a tinted glass state so the toolbar shows state, not
    /// just five identical shapes". Low alpha on purpose: at full strength a
    /// tint stops being a material and becomes a flat slab, which is the same
    /// lesson `todayTint` records.
    private var seatTint: Color {
        if active { return accent.opacity(0.24) }
        // An unseated button still lights up when it is the active mode — a
        // pencil that cannot show it is on would be a worse bug than a chip in
        // a bar — it simply has no resting shape.
        guard seated else { return .clear }
        return .white.opacity(isLight ? 0.14 : 0.07)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                // One symbol weight for the whole row: the discs are peers, and
                // a monochrome rendering keeps a multicolour SF Symbol from
                // being the loudest thing in a group of five.
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(active ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                .frame(width: Hit.min, height: Hit.min)
                // Non-interactive glass: the Button + TouchCardStyle press-scale
                // already gives feedback. Interactive Liquid Glass ran its own
                // touch handling that competed with the Button's tap recognizer,
                // making Home/pencil/undo/gear unresponsive (mirrors the working
                // macOS chip pattern). At rest the two variants look identical.
                //
                // **Nothing below changes what this Button's label *is*** — the
                // rim and the shadow are `.overlay`/`.background` on the same
                // image, not a new interactive layer — so the unresponsiveness
                // that comment records cannot come back through them.
                .modifier(GlassIconSeat(inBar: inBar, isLight: isLight, tint: seatTint))
                .overlay {
                    Circle().strokeBorder(accent.opacity(active ? 0.8 : 0), lineWidth: 2)
                        // The ring used to pop on and off. Toggling pencil is
                        // the most-used control on the bar and its only feedback
                        // was a hard cut.
                        .animation(.couchFast, value: active)
                        .allowsHitTesting(false)
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

/// A `GlassIconButton`'s surface, factored out for the reason `TouchCardSurface`
/// is: the two rungs are two different modifier chains and a `some View` body
/// cannot return both from an `if` without one.
private struct GlassIconSeat: ViewModifier {
    let inBar: Bool
    let isLight: Bool
    let tint: Color

    func body(content: Content) -> some View {
        if inBar {
            // Shape and tint, no second pane and no shadow. The bar around it
            // is the material; this is a region of it.
            content.couchInset(in: Circle(), tint: tint)
        } else {
            content
                .couchGlass(in: Circle())
                // The measurement that made these discs look unfinished: 1.08:1
                // against the page on dark and 1.13:1 on light. A glass pane
                // with no rim has no edge for a light source to catch, so six
                // of them read as smudges rather than as controls. Under the
                // active ring, so a lit tool still shows its accent cleanly.
                .background {
                    Circle()
                        .fill(.black.opacity(isLight ? 0.10 : 0.42))
                        .blur(radius: 8)
                        .offset(y: 3)
                        .allowsHitTesting(false)
                }
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(isLight ? 0.6 : 0.22),
                                     .white.opacity(isLight ? 0.15 : 0.06)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
    }
}

/// Nine keys under the board, each carrying how many of that digit are left.
///
/// **On a phone the keys are not square, and that is arithmetic.**
/// Nine 44pt targets plus eight gaps need 396 + 48 = 444pt; a 402pt phone leaves
/// this row 386 once the column's 8pt gutters are taken, and 338 once the tray's
/// own 12pt padding and the eight 4pt gaps are. So the keys take the width they
/// are given — ≈ 36.7 —
/// and buy the touch floor back in the other axis at 58pt tall. That is the
/// standard shape of a nine-across numeric row on a phone and the only one that
/// does not force a second row; the rose remains the full-size grammar, and
/// every digit is also a first-class VoiceOver action on the cell itself
/// (PRD-19), so nothing here is the sole route to a digit.
///
/// `couchInset` rather than `couchGlass`: the keys sit inside a tray that is
/// already glass, and `.regular` nested in `.regular` is the glass-on-glass
/// mistake CouchKit's L4 rung exists to end.
///
/// **Round 2 makes the shape the caller's and the tray a card rather than a
/// ribbon.** Three findings, all about the same component:
///
///  * *"Number pad is a stretched full-width ribbon of squat pills."* On an
///    iPad the row ran edge to edge at 100×78, which is not a keypad, it is a
///    ribbon. `maxWidth` ties the tray to the board plane's width and
///    `keyHeight` follows the key's own width up to square, so the same nine
///    keys are 37×58 on a phone and 85×84 on an iPad.
///  * *"~26pt tray around ~10pt keys reads as pasted-on."* The tray was
///    `Radius.control` (16) with `Space.s` (8) padding, which makes the
///    concentric answer 8 — correct, and both curves too tight for a surface
///    that is now the width of the board. The tray is `Radius.card` at
///    `Space.m`, and the key follows it by the same `Radius.inner` call, so
///    the relationship holds at either size instead of the numbers holding.
///  * *"11pt near-invisible count subscripts… a digit at 0 remaining needs a
///    visibly dimmed/struck state."* The count is a filled pip now — the
///    audit's own suggestion, and the one that survives sunlight — and an
///    exhausted key loses the pip entirely rather than printing a "0" nobody
///    can read.
private struct DigitPadRow: View {
    /// Index 0 is the digit 1.
    let remaining: [Int]
    let pencil: Bool
    let tint: Color
    let tones: ThemeTones
    /// Nine across for the column, three across for the drafting table's rail.
    /// Anything that does not divide nine simply leaves a short last row.
    var columns: Int = 9
    var keyHeight: CGFloat = 58
    /// The tray's clamp. Nil is the shipped elastic behaviour.
    var maxWidth: CGFloat? = nil
    let onDigit: @MainActor (Int) -> Void

    private var rows: [[Int]] {
        stride(from: 0, to: 9, by: max(1, columns)).map { start in
            Array((start + 1)...min(start + max(1, columns), 9))
        }
    }

    var body: some View {
        let tray = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        CouchGlassContainer(spacing: Space.s) {
            VStack(spacing: Space.xs) {
                ForEach(rows, id: \.first) { row in
                    HStack(spacing: Space.xs) {
                        ForEach(row, id: \.self) { digit in
                            key(digit, left: remaining[digit - 1])
                        }
                    }
                }
            }
            .padding(Space.m)
            .couchGlass(in: tray)
            .couchElevated(in: tray, isLight: tones.isLight)
        }
        .frame(maxWidth: maxWidth ?? .infinity)
        .frame(maxWidth: .infinity)
        // One place for Switch Control's group scan, exactly as the stats rail
        // is — nine keys are a keypad, not nine loose controls under a board.
        .accessibilityElement(children: .contain)
    }

    private func key(_ digit: Int, left: Int) -> some View {
        Button { onDigit(digit) } label: {
            VStack(spacing: Space.hair) {
                Text("\(digit)")
                    .font(.system(size: keyHeight >= 72 ? 34 : 22,
                                  weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    // In pencil mode the pad writes notes, so it says so in the
                    // same accent the rose's note petals use — a mode you can
                    // only discover by pressing a key is not a mode.
                    .foregroundStyle(pencil ? tint : tones.digitTone)
                countPip(left)
            }
            .frame(maxWidth: .infinity, minHeight: keyHeight)
            // Concentric with the tray, derived rather than declared: a 22pt
            // corner with 12pt of padding wants a 10pt inner corner. Stated as
            // the arithmetic so that retuning the tray retunes the keycap.
            .couchInset(in: RoundedRectangle(
                cornerRadius: Radius.inner(Radius.card, inset: Space.m),
                style: .continuous),
                        tint: tones.gridTone.opacity(0.10))
            // The whole key, for Switch Control and Voice Control — without it
            // SwiftUI derives the frame from the numeral's glyph bounds, which
            // is the 9×15pt defect PRD-19 recorded on the Home chevron.
            .contentShape(.accessibility, Rectangle())
        }
        .buttonStyle(TouchCardStyle())
        // Every one of this digit is placed. Dimmed, never disabled: nine on the
        // board can still include a wrong one, and a key you cannot press is a
        // key you cannot correct with.
        .opacity(left == 0 ? 0.3 : 1)
        .animation(.couchFast, value: left)
        .accessibilityLabel(left == 0
                            ? Strings.string("board.stats.digitDone", .int(digit))
                            : Strings.string("board.stats.digitLeft",
                                             .int(digit), .int(left)))
    }

    /// How many of this digit are left, as a filled pip rather than a 10pt grey
    /// numeral. The numeral measured near-invisible outdoors; a pip carries its
    /// own ground, so the count survives the sun and reads at thumbnail size.
    ///
    /// Nothing at all when the digit is exhausted: the key is already at 0.3
    /// opacity, and a "0" in a pip is a count that has to be read to learn that
    /// there is nothing to count.
    @ViewBuilder
    private func countPip(_ left: Int) -> some View {
        if left > 0 {
            Text("\(left)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(tones.digitTone.opacity(0.85))
                .padding(.horizontal, Space.xs)
                .padding(.vertical, 1)
                .background(tones.gridTone.opacity(0.18), in: Capsule())
        } else {
            // A zero-height placeholder, so an exhausted key is the same height
            // as its neighbours and the row does not re-measure as the board
            // fills. `Color.clear` alone would take the flexible height.
            Color.clear.frame(height: 0)
        }
    }
}

private extension View {
    /// iOS 26's soft scroll-edge effect on both edges, and nothing at all below
    /// it — the deployment target is 18.0 and this is the whole of the
    /// `#available` dance, in one place, so no call site has to carry it.
    @ViewBuilder
    func nineSoftScrollEdges() -> some View {
        if #available(iOS 26.0, *) {
            self
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self
        }
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
