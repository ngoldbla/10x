// ChannelShelf.swift — the Thermo and Killer pages of the home shelf (PRD-24).
//
// A new file rather than another 300 lines in `TouchUI.swift`, deliberately:
// `EXECUTING-A-PRD.md` §7 names that file as the repo's contention hotspot ("it
// owns the iOS home shelf **and** the game screen, so do not run two UI-heavy PRDs
// in parallel"), and new-file work is one of the three splits it lists as safe. The
// pager *wrapper* has to stay in `TouchUI.swift` because it wraps `shelfColumn` and
// `shelfPair`; everything a variant page draws is here.
//
// **What is deliberately not here: a second input concept.** The page carries the
// same cards, the same glass, the same `TouchCard` press animation and the same
// tap-to-start as Classic. A channel is a different *ruleset*, and the release
// spends its one new input concept on turning the shelf's page and on nothing else
// (`VariantInputSealTests` is the assertion, PRD-24 §2.3 the reasoning).
//
// **What this page got wrong, and what the fix is.** Shipped, it was a strictly
// degraded copy of the Classic shelf it claims to be a peer of:
//
//  1. Five sites wrote `.couchText(…).foregroundStyle(.secondary)`, and
//     `couchText(_:)` hard-sets `.primary` *inside* itself — so the outer style
//     was dead code and the blurb, the status sentence, the section headers and
//     the tier labels all rendered at 100% primary ink. Measured on the light
//     shot: "Tubes that only rise" peaked at (0,0,0) where `.secondary` floors
//     at ~(99,98,95). Every one of them now goes through wave 1's two-argument
//     `couchText(_:_:)`, where the order cannot be got wrong.
//  2. The tier cards were a 22pt SF Symbol and one word in a 111×132 box — 58%
//     internal void — while Classic's difficulty cards carry a 64pt `MiniBoard`,
//     a name and a blurb. They are now the same card.
//  3. Content stopped at y=528 on an 874pt canvas, because two of `body`'s four
//     children are `@ViewBuilder`-absent until a channel has been lived in.
//     Honest absence removes a *stat*; it does not get to remove the page. The
//     primer card below is what stands in their place, and it *shows* the
//     ruleset rather than describing it.
#if os(iOS)
import SwiftUI
import CouchKit

/// One variant channel's page: its boards, its tiers, its primer, its records.
///
/// Structurally the same order Classic asks its questions in — what was I in
/// the middle of, what could I start — because a player turning the page
/// should find the same shelf with different rules on it, not a different app.
/// (The channel's Today card and streak left with the daily system,
/// 2026-08-02.)
struct ChannelShelfContent: View {
    let model: AppModel
    let channel: Channel.Ledgered
    let accent: Color

    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// The ground everything on this page is measured against — the card fills,
    /// the rims, the band tones, the action pill's ink.
    private var tones: ThemeTones { theme.tones(for: colorScheme) }

    /// **How wide this page has actually been given, in points.**
    ///
    /// Not a device check and not a size class: the same view is handed 560pt on
    /// a phone, ~383pt inside `TouchHomeView.shelfPair`'s leading column, and
    /// the full measure when a caller lets it span. A layout that asks "am I on
    /// an iPad" gets all three of those wrong; one that asks "how much room is
    /// there" gets all three right, and reflows the instant the answer changes.
    ///
    /// Zero until the first layout pass, which resolves to the narrow
    /// composition — the phone's — so the first frame is never the wide one
    /// collapsing.
    @State private var measuredWidth: CGFloat = 0

    /// **The area rule, in one number.** `Rhythm.maxEmptyFraction` says no more
    /// than 28% of a screen may be bare ground, and the panel measured this page
    /// at 37–50% on iPad because it was a phone column pinned to the leading
    /// rail of a 1668pt canvas. A column stops being a column and becomes a
    /// stretched phone somewhere, and the app already knows where: two
    /// `shelfMinimumColumn`s and the gutter between them is the width at which
    /// `BoardCompositionRules` itself starts splitting. Reused rather than
    /// re-guessed, so the shelf and its channel page can never disagree about
    /// what "wide" means.
    private static let wideThreshold = CGFloat(
        BoardCompositionRules.shelfMinimumColumn * 2 + BoardCompositionRules.shelfGutter)

    private var isWide: Bool { measuredWidth >= Self.wideThreshold }

    /// `TouchCard`'s padding, restated once here rather than eleven times.
    ///
    /// The card chrome on this page is `TouchCard`'s (`TouchUI.swift`), which
    /// hard-codes 18pt of padding. Two surfaces here are *not* buttons — the
    /// stats slice and the primer — and have to draw that chrome themselves;
    /// several others need it to derive a concentric inner radius.
    private static let cardPadding: CGFloat = 18

    /// **Every corner on this page is a rung of `Radius` now, and they are
    /// Classic's rungs.** They were one number — `TouchCard`'s 24pt default,
    /// used for the hero, the tiles, the tracker rows and the two panels alike —
    /// which is 22% of a 111pt tile and 6.6% of the hero: two different shapes
    /// wearing one radius, and neither of them the one the page next door draws.
    /// `TouchUI` picks `sheet` for full-width bands and `card` for tiles; so
    /// does this, because the whole thesis of the page-turn is that a player
    /// finds the same shelf with different rules on it.
    private static let heroRadius = Radius.sheet
    private static let tileRadius = Radius.card

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.heroRadius, style: .continuous)
    }

    /// A compose is running, so `AppModel.composeChannel` will refuse another.
    /// Surfaced rather than swallowed, for `TouchHomeView.composeInFlight`'s
    /// reason — though a variant compose is far cheaper than Nocturne's: thermo's
    /// Release p95 is 0.01–0.03 s and killer's 0.02–0.14 s.
    private var composeInFlight: Bool { model.composing != nil }

    /// One tier card's own compose, for the caption that replaces its blurb.
    private func isComposing(_ tier: VariantTier) -> Bool {
        if case .channel(let c, let t, let day)? = model.composing {
            return c == channel.channel && t == tier && day == nil
        }
        return false
    }

    /// **Two compositions of the same five surfaces, chosen by measure.**
    ///
    /// Narrow is the phone's and is unchanged in order and in rhythm — the
    /// panel confirmed `iphone-dark-channel` and `iphone-light-channel` as
    /// improvements from the round before, and a page that wins from the
    /// disfavoured slot does not get rearranged for sport. What changed inside
    /// it is material and hierarchy, not sequence.
    ///
    /// Wide is the answer to the headline defect: *"the content column is
    /// pinned to x=48–813 and stops at y=1540 of 2420"*. Today becomes a hero
    /// across the whole measure, the three tiers become three real columns
    /// across the whole measure, and the tail splits — what you have on the
    /// left, what the ruleset is on the right — so the page terminates at one
    /// baseline instead of dying two-thirds of the way up a rail. Every surface
    /// also grows: `Rhythm`'s own instruction is that where slack exists you
    /// spend it on the content, so the hero gets 90pt, the tier art goes 64 →
    /// 96 and the primer's excerpt 132 → 190. An iPad frame is not a phone
    /// frame with more air in it.
    var body: some View {
        VStack(spacing: isWide ? Space.xxl : Space.xl) {
            if isWide {
                tierRow
                wideTail
            } else {
                statsSlice
                boardsSection
                tierRow
                channelPrimer
            }
        }
        // Width only — reading height here would make the measurement depend on
        // the layout it decides, which is the shape that oscillates.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredWidth = $0 }
    }

    /// The wide layout's third band: two columns that both carry weight.
    ///
    /// The split is by *availability*, not by kind, because on this page the two
    /// halves are mutually exclusive by construction — the primer retires at the
    /// exact moment the stats slice arrives (`channelPrimer`'s own rule), so a
    /// naive "stats left, primer right" pair is guaranteed to leave one side
    /// empty on every single frame. Whichever of the two the channel has earned
    /// takes the leading column; the boards you are in the middle of take the
    /// trailing one; and when there are none, the survivor spans the measure
    /// rather than sitting in half of it beside nothing.
    @ViewBuilder
    private var wideTail: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            VStack(spacing: Space.xl) {
                if showsPrimer { channelPrimer } else { statsSlice }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            if showsBoards {
                boardsSection
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    /// The primer is owed exactly while the channel has never been solved on.
    /// Hoisted out of `channelPrimer` so the wide layout can ask the question
    /// before it decides where to put the answer.
    private var showsPrimer: Bool { model.history(on: channel).records.isEmpty }

    private var showsBoards: Bool { !model.partials(on: channel).isEmpty }

    // MARK: The page's own chrome

    /// The material a **non-button** surface on this page draws for itself.
    ///
    /// It shipped as a bare `couchGlass` — the material and nothing else — and a
    /// material with no fill on a ground that composites to (19,19,19) is the
    /// panel's *"cards sit 3 RGB levels above the background, so depth is
    /// carried entirely by a soft shadow and nothing refracts"* verbatim, on
    /// both appearances and both devices.
    ///
    /// This is `Elevation`'s own recipe for a `card` standing on `ground`, in
    /// order: the lens, then the rung's fill **on** it, then the rim and the
    /// lift. `Elevation.fill(.card,…)` is a solved value rather than a taste —
    /// 55.6 against a track's 42.6 — and it is the *theme's* hue, not white, so
    /// a Blueprint panel is a blue panel and Camel's is warm. The rim comes from
    /// `couchElevated`, which draws the two-sided bevel (bright at topLeading,
    /// genuinely dark at bottomTrailing) that is the difference between a pane
    /// of glass and a rectangle with a stroke on it.
    private struct PanelSurface: ViewModifier {
        let shape: RoundedRectangle
        let tones: ThemeTones

        func body(content: Content) -> some View {
            content
                .background(Elevation.fill(.card, on: tones), in: shape)
                .couchGlass(in: shape)
                .couchElevated(in: shape, isLight: tones.isLight)
        }
    }

    // MARK: This channel's stats slice

    /// Solves, best and average — this channel's, and nothing classic's.
    ///
    /// **Every number here is `SolveHistory`'s own aggregation on the channel's
    /// own history**, which is the payoff of `ChannelLedger` holding a whole
    /// `SolveHistory` per channel rather than a bespoke summary: `count(of:)`,
    /// `bestSeconds(for:)` and `averageSeconds(for:)` arrived already written and
    /// already tested, and a channel's stats cannot drift from classic's because
    /// they are the same code reading different bytes.
    ///
    /// Absent until there is something to say, rather than showing zeroes — the
    /// honest-absence rule PRD-22 landed when it deleted the blank grey 0% rings
    /// from this shelf. A tier with no solves contributes no row, and a channel
    /// with no solves at all contributes no card.
    @ViewBuilder
    private var statsSlice: some View {
        let slice = model.history(on: channel)
        let rows = VariantTier.allCases.compactMap { tier -> (VariantTier, Int, TimeInterval)? in
            let band = tier.wireDifficulty
            let count = slice.count(of: band)
            guard count > 0, let best = slice.bestSeconds(for: band) else { return nil }
            return (tier, count, best)
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(Strings.string("channel.stats.title"))
                    .couchText(CouchTypography.label, Ink.secondary(on: tones))
                    .accessibilityAddTraits(.isHeader)
                ForEach(rows, id: \.0) { tier, count, best in
                    HStack(spacing: Space.s) {
                        // The tier's own hue, which is the same hue its tile
                        // wears twenty points below this row. A stats table that
                        // repeats the ladder in one grey is a table the eye has
                        // to read rather than scan.
                        Text(Strings.variantTier(tier))
                            .couchText(CouchTypography.label,
                                       tier.wireDifficulty.bandTone(isLight: tones.isLight))
                        Spacer()
                        // `data` outranks its own container (`Elevation`): the
                        // number is the reason the card exists, so it is the one
                        // thing on it drawn at full ink.
                        Text(Strings.string(
                            "channel.stats.row",
                            .int(count), .text(SolveCardFacts.elapsedText(best))))
                            .couchText(CouchTypography.label, Ink.label(on: tones))
                            .monospacedDigit()
                    }
                    // One utterance per row — a tier name followed by an orphaned
                    // "3 · 4:12" is the shape VoiceOver reads worst.
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Strings.string(
                        "channel.stats.label",
                        .text(Strings.variantTier(tier)),
                        .int(count), .text(SolveCardFacts.elapsedText(best))))
                }
            }
            .padding(Self.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(PanelSurface(shape: panelShape, tones: tones))
        }
    }

    /// A glyph and a sentence, secondary throughout.
    ///
    /// **The whole row is secondary, including the glyph**, which is what
    /// `TouchHomeView.statusLabel` does. This one tinted its symbol `accent`,
    /// and on a shelf whose thesis is that the two pages behave identically a
    /// coloured checkmark on one page and a grey one on the other is visible
    /// drift. The `Text` resolves its own foreground through `couchText(_:_:)`
    /// because the outer `foregroundStyle` cannot reach inside it (that is this
    /// file's whole colour bug); the outer one is what colours the `Image`.
    ///
    /// **`Ink.secondary(on:)` rather than SwiftUI's `.secondary`, and the glyph
    /// is deliberately *not* `Ink.glyph`.** The token's rule is that a symbol
    /// which is a control's **only** content goes to full strength; this symbol
    /// has a sentence beside it saying the same thing, so it is decoration on a
    /// label and takes the label's weight. What `Ink` buys here is the theme's
    /// own hue and a measured value (0.72 of `digitTone` on dark, 0.68 on
    /// paper) instead of the platform's untinted grey.
    private func statusLabel(_ key: String, symbol: String) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
            Text(Strings.string(key)).couchText(CouchTypography.label, Ink.secondary(on: tones))
        }
        .foregroundStyle(Ink.secondary(on: tones))
    }

    // MARK: This channel's boards

    /// In-progress free-play boards on this channel. Absent entirely when there
    /// are none — an honest zero-state is a missing section, not an empty one
    /// (PRD-22's rule, and the reason the shelf has no blank grey rings any more).
    @ViewBuilder
    private var boardsSection: some View {
        let partials = model.partials(on: channel)
        if !partials.isEmpty {
            VStack(alignment: .leading, spacing: Space.s + 2) {
                Text(Strings.string("boards.title"))
                    .couchText(CouchTypography.label, Ink.secondary(on: tones))
                    .accessibilityAddTraits(.isHeader)
                ForEach(partials.prefix(3)) { entry in
                    boardRow(entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func boardRow(_ entry: LibraryEntry) -> some View {
        let playable = model.channelRules.rules(for: entry.id)?.isPlayable ?? false
        // A tracker row is a `card` on the ground, so it takes the card rung's
        // corner — Classic's tracker rows do the same, and this one was drawing
        // `TouchCard`'s 24pt default beside them.
        return TouchCard(action: { model.openChannelBoard(entry.id) },
                         radius: Self.tileRadius) {
            HStack(spacing: Space.m) {
                BoardFingerprint(game: entry.game, accent: accent, side: 34)
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(tierName(entry.kind)).couchText(CouchTypography.body)
                    // A board whose rules this build cannot enforce says so
                    // plainly rather than failing on tap. `openChannelBoard`
                    // refuses it either way; this is what stops the refusal being
                    // a dead tap the player has to guess at.
                    Text(playable
                            ? BoardProgressCaption.text(for: entry.game)
                            : Strings.string("channel.unavailable"))
                        .couchText(CouchTypography.label, Ink.secondary(on: tones))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(composeInFlight || !playable)
    }

    private func tierName(_ kind: GameKind) -> String {
        if case .channel(_, let tier, _) = kind { return Strings.variantTier(tier) }
        return ""
    }

    // MARK: Tiers

    /// Three across, matching Classic's free-play row so the page reads as the
    /// same shelf. `VariantTier` has exactly three cases and both shipped rulesets
    /// compose all three at 200/200, so unlike `Difficulty` there is no deep-end
    /// split and no card that has to warn about a long compose.
    ///
    /// **The card is Classic's `difficultyCard`, not a smaller relative of it.**
    /// It shipped as a 22pt SF Symbol over one caption word inside a 111×132
    /// box: 55pt of content and 58% internal void, three times over, on the row
    /// that is the page's only way to start a board. The glyph vocabulary
    /// (`leaf` / `circle.grid.2x2` / `bolt`) is deleted rather than left lying
    /// around — a `MiniBoard` at the same 64pt Classic uses says the same thing
    /// about density and says it in the app's own material.
    ///
    /// `spacing: 14` and `spacing: 10` were Classic's numbers, off the 4pt grid
    /// and kept anyway because this row has to be the same object as the one on
    /// the page next door. Classic's row is on the scale now (`Space.m` /
    /// `Space.s`), so this one follows it there.
    ///
    /// **The three tiles carried no colour at all**, which is the defect a blind
    /// panel wrote twice on this page: *"Gentle / Steady / Sharp are three
    /// identical grey tiles"*, *"the only saturated pixels in the frame are the
    /// blue page dot and the pencil-mark dots"*. Difficulty is the axis the row
    /// exists to communicate and it was being carried entirely by dot density in
    /// a 64pt thumbnail — which is both illegible at that size and, until round
    /// 4 inverted it, backwards.
    ///
    /// Three carriers now, all of them `Difficulty.bandTone`, and the label is
    /// deliberately **not** one of them: a coloured label on a card tinted the
    /// same colour is the blue-on-blue mistake `TouchHomeView.todayVerb` carries
    /// a whole paragraph about. Instead the hue arrives as (1) the tile's own
    /// glass tint at 0.14 — the parlor card's existing weight — (2) the
    /// `MiniBoard`'s dots, and (3) a lit top edge, so a tier is identifiable
    /// from across the room and the name is still full-strength ink.
    private var tierRow: some View {
        HStack(spacing: Space.m) {
            ForEach(VariantTier.allCases, id: \.self) { tier in
                tierCard(tier)
            }
        }
    }

    /// The band's tint through the tile's glass. `TouchHomeView.parlorCard`'s
    /// number: enough to say which of six this is against the untinted cards
    /// around it, far short of the flood fill `Difficulty.bandTone`'s own note
    /// rules out ("six saturated cards in a column is a paint chart").
    private static let tierTint = 0.14

    /// The tile's art. 64pt is Classic's, and on the wide composition the three
    /// tiles are ~250pt columns rather than ~110pt ones — a 64pt picture in a
    /// 250pt card is the 58% internal void this row was rebuilt to end, one
    /// size class up.
    private var tierArtSide: CGFloat { isWide ? 96 : 64 }

    private func tierCard(_ tier: VariantTier) -> some View {
        let band = tier.wireDifficulty
        let tone = band.bandTone(isLight: tones.isLight)
        let shape = RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous)
        return TouchCard(action: { model.startChannelFree(channel, tier: tier) },
                         radius: Self.tileRadius,
                         tint: tone.opacity(Self.tierTint)) {
            VStack(spacing: Space.s) {
                // Concentric with the card it is dropped into: a 22pt corner
                // with 18pt of padding wants `Radius.inner`, not the 24/18
                // default `MiniBoard` carries. This is the line the old comment
                // here promised would be needed the moment the row stopped
                // taking `TouchCard`'s default radius, and it now is.
                MiniBoard(difficulty: band, accent: accent,
                          corner: Radius.inner(Self.tileRadius, inset: Self.cardPadding))
                    .frame(width: tierArtSide, height: tierArtSide)
                if isComposing(tier) {
                    // The composing caption replaces the name and the
                    // blurb rather than stacking under them — Classic's
                    // rule, for Classic's reason: a card that grows a
                    // line mid-compose shoves the rest of the shelf
                    // down while the player watches.
                    statusLabel("status.composing", symbol: "sparkles")
                } else {
                    Text(Strings.variantTier(tier))
                        .couchText(CouchTypography.label, Ink.label(on: tones))
                        .multilineTextAlignment(.center)
                    Text(tier.blurb)
                        .couchText(CouchTypography.caption, Ink.secondary(on: tones))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: isWide ? 190 : 124)
            .background { bandEdge(tone) }
            // **The accessibility frame is the card, not the glyph.**
            // Without this the first `channel.txt` baseline recorded
            // `Gentle, Thermo (55,439 41x48)` — 41pt wide, under the
            // charter's 44pt floor — because SwiftUI derives the frame
            // from the tight content bounds when the content is only a
            // symbol and a caption. The 64pt `MiniBoard` now forces the
            // width the way it does on Classic's cards, so this is
            // belt-and-braces rather than the fix it was; it stays
            // because the composing branch has no `MiniBoard` sibling
            // wide enough to hold the frame open on its own.
            // Invisible in a screenshot, since the card *looks* full-width;
            // `ax-snapshot.py` is the only thing that disagrees
            // (EXECUTING-A-PRD §4).
            .contentShape(.accessibility, shape)
        }
        .disabled(composeInFlight)
        .accessibilityLabel(Strings.string(
            "shelf.difficulty.label",
            .text(Strings.variantTier(tier)),
            .text(Strings.channel(channel.channel))))
    }

    /// The lit top edge of a tier tile, in the band's own hue.
    ///
    /// A physical mark rather than a badge: light lands on the top arc of a
    /// coloured slab and is gone by the time the surface has turned two percent
    /// of its own height away. Drawn as the card's *own* silhouette expanded by
    /// the 18pt `TouchCard` inset, so it reaches the real corner and is clipped
    /// by it — the same clip-then-expand pair the hero's lamp uses, and for the
    /// same reason: a gradient that stops at the content's bounds draws the hard
    /// rectangle it exists to replace.
    private func bandEdge(_ tone: Color) -> some View {
        RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous)
            .fill(LinearGradient(
                stops: [
                    .init(color: tone.opacity(0.90), location: 0),
                    .init(color: tone.opacity(0.30), location: 0.025),
                    .init(color: tone.opacity(0), location: 0.11),
                ],
                startPoint: .top, endPoint: .bottom))
            .padding(-Self.cardPadding)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: The primer

    /// **What this channel's rule actually looks like, drawn rather than
    /// described.**
    ///
    /// `body` is five children and two of them — the stats slice and the boards
    /// section — are absent until the channel has been played, which is how a
    /// page that is supposed to sell a new ruleset came to be a wordmark, a
    /// rail, one card, three chips and 346pt of flat backdrop: 44% of everything
    /// under the status bar. Honest absence is right about the *stats* (there is
    /// no honest number to print) and says nothing at all about the page, which
    /// still owes the player a reason to tap.
    ///
    /// So the frame that has the least on it gets the one thing that is worth
    /// the most on it: a 3×3 excerpt carrying the channel's own constraint art,
    /// in the channel's own colours, with the rule under it. Not a screenshot
    /// and not a second copy of the board renderer — the same construction
    /// `BoardView.drawCage` and `BoardView.drawThermometer` use, at the same
    /// fractions of a cell, so what it promises is what the board delivers.
    ///
    /// It retires once the channel has been solved on, which is the moment the
    /// stats slice arrives to take its place in the layout. A player with times
    /// on the board does not need to be told what a cage is.
    ///
    /// **The panel's complaint about it was the measure, not the size.** *"That
    /// six-line paragraph is set on a ~28-character measure inside a card with
    /// 850px of unused width beside it."* Both halves of that are one bug: a
    /// fixed 132pt picture and a `Spacer(minLength: 0)` split a 383pt column
    /// into a wide picture and a narrow gutter of prose, and on a wider card the
    /// `Spacer` ate every extra point rather than the text. The `Spacer` is
    /// gone — the text takes the remaining width — and the picture grows with
    /// the card instead of holding still on it.
    ///
    /// The finding also asked for the prose to drop to `.subheadline`/`.footnote`.
    /// It stays at `body`, and the comment below is why: this is the only
    /// paragraph on the page, `label` is the next rung down and it is *semibold*,
    /// and five semibold lines read as a warning rather than as an explanation.
    /// Fixing the measure fixes the line count, which is what made it look like
    /// a wall in the first place.
    @ViewBuilder
    private var channelPrimer: some View {
        if showsPrimer {
            HStack(alignment: .top, spacing: Space.l) {
                ChannelPrimerArt(
                    channel: channel, accent: accent, side: primerArtSide,
                    corner: Radius.inner(Self.heroRadius, inset: Self.cardPadding))
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(Strings.string("tutorial.title"))
                        .couchText(CouchTypography.label, Ink.secondary(on: tones))
                        .accessibilityAddTraits(.isHeader)
                    // Prose at `body`, which is the rung's own definition
                    // ("everything readable") and the only paragraph on the
                    // page. `label` is semibold, and five semibold lines read
                    // as a warning rather than as an explanation.
                    Text(primerRule)
                        .couchText(CouchTypography.body, Ink.label(on: tones))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // **A ceiling, not a `Spacer`.** The trailing `Spacer(minLength:
                // 0)` that used to close this row is what put a six-line
                // paragraph on a 28-character measure: a `Spacer` and a
                // horizontally-flexible `Text` are both flexible, the stack
                // splits the slack between them, and the wider the card the more
                // of it the empty half won. Capping the text column and deleting
                // the `Spacer` inverts that — the prose takes everything up to
                // `NineLayout.readable`, and the card never has an unclaimed band in
                // it at any width this page is drawn at.
                .frame(maxWidth: NineLayout.readable, alignment: .leading)
            }
            .padding(Self.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(PanelSurface(shape: panelShape, tones: tones))
        }
    }

    /// The excerpt's side. 132pt puts a cell at 44 — very nearly the size a cell
    /// is on a phone board, which is the whole claim of the picture. On the wide
    /// composition the card is two-and-a-half times as wide, so the picture goes
    /// with it and a cell lands at 63.
    private var primerArtSide: CGFloat { isWide ? 190 : 132 }

    /// The sentence under the primer art.
    ///
    /// **Both keys are the coach's**, and they are reused rather than written
    /// because a new catalog row is separately gated (`CatalogTests`,
    /// `StringSealTests`) and because these two are already the app's best
    /// English on the subject — they are what the hint card says when it proves
    /// a step on one of these boards. Each is true *of the picture beside it*,
    /// which is why the figure and the sentence are built from one set of
    /// constants (`PrimerFigure`): the thermometer really is four cells long,
    /// the cage really is three, and 15 − 9 − 4 really is 2.
    private var primerRule: String {
        switch channel {
        case .thermo:
            return Strings.string(
                "coach.thermoBound.sentence", .int(PrimerFigure.thermoCells.count))
        case .killer:
            return Strings.string(
                "coach.cageSingle.sentence",
                .int(PrimerFigure.cageCells.count), .int(PrimerFigure.cageAnswer))
        }
    }
}

// MARK: - Tier copy

extension VariantTier {
    /// The one line under a tier's name on its card, the way `Difficulty.blurb`
    /// is the one line under a band's.
    ///
    /// **Routed through `wireDifficulty`, and that is a compromise made with
    /// eyes open.** `Strings.variantTier(_:)`'s own comment argues against
    /// exactly this shape for *names*: a tier and a band are different ladders,
    /// so one key covering both hands a translator a single string for two
    /// meanings and makes a rename of either move both. The argument is weaker
    /// for a blurb — "Singles & scans" is a claim about how much work the board
    /// asks for, and the three variant tiers are cut to the same three
    /// workloads by construction (`VariantTier.wireDifficulty`) — and the
    /// alternative was worse: three `variantTier.<raw>.blurb` rows are a
    /// separately-gated catalog change, and a tier card with no second line is
    /// the downgrade this page is being fixed for. The bespoke copy is in the
    /// work order's `crossFileNeeds`; when those rows land, this switches to
    /// them and nothing else on the page moves.
    var blurb: String { wireDifficulty.blurb }
}

// MARK: - The primer figure

/// The one set of numbers the primer's picture and the primer's sentence are
/// both built from.
///
/// Two things have to agree here or the card lies to the player: the sentence
/// says "this 4-cell thermometer" and "this 3-cell cage" and quotes an answer,
/// and the art draws them. Holding both in one place is what makes that a
/// compile-time fact rather than a comment somebody has to keep true — the
/// counts *are* `count`, and the answer *is* the arithmetic.
///
/// Indices are into a 3×3 excerpt, `row * 3 + column`, so index 0 is the
/// top-left cell and index 8 the bottom-right.
private enum PrimerFigure {
    /// Bulb at the bottom-left, up one, then right along the middle row. Four
    /// cells with one bend, because a straight tube reads as a line and the
    /// bend is what says "this follows the cells, not the geometry".
    static let thermoCells = [6, 3, 4, 5]

    /// The floor and the ceiling, and nothing between them. Two digits rather
    /// than four: the sentence's claim is that the tube bounds *every* square
    /// along it, and a tube with its two ends filled shows the bound while a
    /// tube filled end to end just shows four digits.
    static let thermoDigits: [Int: Int] = [6: 2, 5: 9]

    /// An L of three cells in the top-left corner — the commonest cage shape on
    /// a killer board, and the one that shows the outline hugging the *region*
    /// rather than a bounding box.
    static let cageCells = [0, 1, 4]
    static let cageSum = 15
    static let cageDigits: [Int: Int] = [0: 9, 1: 4]

    /// The digit the cage total leaves for the one empty square. Computed, so
    /// the sentence cannot drift from the picture: 15 − 9 − 4.
    static var cageAnswer: Int { cageSum - cageDigits.values.reduce(0, +) }

    /// The cage cell with no digit in it — the square the sentence is about.
    static var cageEmptyCell: Int? { cageCells.first { cageDigits[$0] == nil } }
}

/// The dashed border of a set of cells on an `n`×`n` excerpt.
///
/// The same construction as `BoardView.drawCage`: **each cell contributes an
/// inset edge wherever its neighbour across that edge is outside the set**,
/// rather than a rounded rect around the bounding box, which would be wrong for
/// every cage that is not a rectangle — i.e. most of them, and both of the ones
/// drawn on this page. Generalised to `n` only so the 34pt motif can draw a 2×2
/// cage with the identical rule; the board's own version is unchanged and stays
/// where it is (it is on the watch target's source list, which cannot see this
/// file).
private func cageOutline(
    members: Set<Int>, across n: Int, cell: CGFloat, origin: CGPoint, inset: CGFloat
) -> Path {
    var path = Path()
    for index in members.sorted() {
        let row = index / n, column = index % n
        let x = origin.x + CGFloat(column) * cell
        let y = origin.y + CGFloat(row) * cell
        let left = x + inset, right = x + cell - inset
        let top = y + inset, bottom = y + cell - inset
        // The row/column bound is checked before the membership lookup so a cell
        // on the excerpt's rim does not wrap around to the far side and think it
        // has a neighbour.
        if row == 0 || !members.contains(index - n) {
            path.move(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: right, y: top))
        }
        if row == n - 1 || !members.contains(index + n) {
            path.move(to: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: right, y: bottom))
        }
        if column == 0 || !members.contains(index - 1) {
            path.move(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: left, y: bottom))
        }
        if column == n - 1 || !members.contains(index + 1) {
            path.move(to: CGPoint(x: right, y: top))
            path.addLine(to: CGPoint(x: right, y: bottom))
        }
    }
    return path
}

/// A 3×3 excerpt of a board on this channel, with the channel's constraint on it.
///
/// **Board-faithful geometry, primer-strength ink.** Every fraction here is the
/// one `BoardView` draws with — the tube is `0.42` of a cell wide with a `0.13`
/// spine and a `0.30` bulb, the cage is inset `3 · scale` with a
/// `[3.5, 3] · scale` dash, the sum sits at `0.13, 0.13` of its cell at
/// `BoardType.cageSum` — and `scale` is derived the way the board derives it, as
/// `cell / 100`. At the 132pt this card draws it at, a cell is 44pt against a
/// phone board's ~40pt, so the picture is very nearly life-size.
///
/// The opacities are the *Increase Contrast* pair rather than the default one
/// (0.30/0.46 for the tube, 0.62 for the cage). A card-sized excerpt has one job
/// and two seconds to do it, and unlike the board there is nothing else drawn on
/// top of this that the constraint art has to stay behind.
///
/// **Two round-4 corrections, and one finding this file disagrees with.**
///
/// The corner was `Radius.tile` — 12 — inside a card drawing a 24pt corner with
/// 18pt of padding, where the concentric answer is `Radius.inner` of those two.
/// The panel's phrasing was *"the cell corner radius is also not concentric with
/// the card's radius"*, and it is right about the outer curve even though it
/// pointed at the cells: a square picture in a curved frame is the tell that the
/// art and the frame were drawn by different people, and so is an over-round
/// one. The caller now passes the frame's own answer.
///
/// The washes are `Elevation.fill(.track,…)` rather than a hand-picked
/// `gridTone` opacity, so a cell in this excerpt is made of the same substance
/// as every other recess in the app and picks up the theme's hue on Blueprint,
/// Ember and Camel instead of a neutral grey.
///
/// The disagreement: *"the bulb circle around the 2 spills past the left and
/// bottom edges of its rounded cell, and the cap around the 9 bleeds over the
/// right cell boundary."* Measured against the code, it does not. The bulb is
/// `0.30` of a cell in radius plus a 1pt stroke, centred on the cell — 0.31 of a
/// cell from centre against the wash's own 0.465 half-width — and the tube's
/// round cap reaches 0.21. What the finding is describing is the tube *crossing
/// cell boundaries between* its four cells, which is what a thermometer is:
/// `BoardView.drawThermometer` draws exactly the same figure on the real board.
/// Clipping it to the cell rects would draw four disconnected stubs. Trusting
/// the code over the finding, per the order.
private struct ChannelPrimerArt: View {
    let channel: Channel.Ledgered
    let accent: Color
    var side: CGFloat = 132
    /// The excerpt's own corner. Defaulted to the concentric answer for the
    /// card this is drawn in — `Radius.sheet` with `TouchCard`'s 18pt inset —
    /// so a caller in a differently-curved card passes its own and nobody has
    /// to.
    var corner: CGFloat = Radius.inner(Radius.sheet, inset: 18)

    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var tones: ThemeTones { theme.tones(for: colorScheme) }

    /// One cell's frame in a 3×3 excerpt of `cell`-point cells.
    private static func rect(_ index: Int, cell: CGFloat) -> CGRect {
        CGRect(x: CGFloat(index % 3) * cell, y: CGFloat(index / 3) * cell,
               width: cell, height: cell)
    }

    private static func centre(_ index: Int, cell: CGFloat) -> CGPoint {
        let frame = rect(index, cell: cell)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    var body: some View {
        let tones = self.tones
        let accent = self.accent
        let channel = self.channel
        Canvas { context, size in
            let cell = size.width / 3
            // The board's own `scale`: `BoardView` computes `size.width / 900`
            // against a `size.width / 9` cell, so `scale == cell / 100` exactly.
            // Every constant borrowed from it below is in these units.
            let scale = cell / 100

            // The nine cell washes, so the excerpt reads as a box of a board and
            // not as a diagram floating on the card.
            //
            // **Unchanged values, and that is on purpose.** This is a picture of
            // a *board*, not a control surface: on a dark theme a board's cells
            // are lighter than the frame around them, which is why the wash is
            // `gridTone` here and `wellHue` in `MiniBoard`. Two thumbnails, two
            // subjects — one is a board and one is a well with a board in it.
            let wash = tones.gridTone.opacity(tones.isLight ? 0.14 : 0.09)
            for index in 0..<9 {
                let frame = Self.rect(index, cell: cell)
                    .insetBy(dx: cell * BoardArt.cellInset, dy: cell * BoardArt.cellInset)
                context.fill(
                    Path(roundedRect: frame, cornerRadius: cell * BoardArt.cellCorner),
                    with: .color(wash))
            }

            switch channel {
            case .thermo:
                let centres = PrimerFigure.thermoCells.map { Self.centre($0, cell: cell) }
                if let bulb = centres.first {
                    var spine = Path()
                    spine.move(to: bulb)
                    for point in centres.dropFirst() { spine.addLine(to: point) }
                    // Body then spine: wide and soft, then narrow and bright.
                    // That is how a cylinder reads without a gradient, and the
                    // round join is what makes the bend one tube rather than two
                    // segments meeting at a corner.
                    context.stroke(
                        spine, with: .color(tones.gridTone.opacity(0.30)),
                        style: StrokeStyle(
                            lineWidth: cell * 0.42, lineCap: .round, lineJoin: .round))
                    context.stroke(
                        spine, with: .color(tones.gridTone.opacity(0.46)),
                        style: StrokeStyle(
                            lineWidth: cell * 0.13, lineCap: .round, lineJoin: .round))
                    // The bulb is the only thing saying which end is the small
                    // one — without it a tube is symmetric and the constraint is
                    // unreadable — so it is drawn over the body and wider than it.
                    let radius = cell * 0.30
                    let disc = Path(ellipseIn: CGRect(
                        x: bulb.x - radius, y: bulb.y - radius,
                        width: radius * 2, height: radius * 2))
                    context.fill(disc, with: .color(tones.gridTone.opacity(0.30)))
                    context.stroke(
                        disc, with: .color(tones.gridTone.opacity(0.46)),
                        lineWidth: max(1, 1.2 * scale))
                }
                for (index, digit) in PrimerFigure.thermoDigits {
                    Self.draw(digit: digit, at: Self.centre(index, cell: cell),
                              cell: cell, tone: tones.digitTone, in: context)
                }

            case .killer:
                let members = Set(PrimerFigure.cageCells)
                context.stroke(
                    cageOutline(members: members, across: 3, cell: cell,
                                origin: .zero, inset: 3 * scale),
                    with: .color(tones.digitTone.opacity(0.62)),
                    style: StrokeStyle(
                        lineWidth: max(1, 1.4 * scale), lineCap: .round,
                        dash: [3.5 * scale, 3 * scale]))
                // The square the sentence is about, ringed in the accent — the
                // app's "this one" mark, used here for the only cell in the
                // picture the reader is asked to think about.
                if let empty = PrimerFigure.cageEmptyCell {
                    let frame = Self.rect(empty, cell: cell)
                        .insetBy(dx: cell * 0.13, dy: cell * 0.13)
                    context.stroke(
                        Path(roundedRect: frame, cornerRadius: cell * BoardArt.cellCorner),
                        with: .color(accent.opacity(0.65)),
                        lineWidth: max(1.5, 2 * scale))
                }
                // The sum, in the cage's lowest-indexed cell — which is its
                // top-left-most on every cage shape, deterministically.
                if let anchor = PrimerFigure.cageCells.min() {
                    let frame = Self.rect(anchor, cell: cell)
                    let sum = context.resolve(
                        Text(verbatim: "\(PrimerFigure.cageSum)")
                            .font(.system(size: cell * BoardType.cageSum,
                                          weight: .semibold, design: .rounded))
                            .foregroundStyle(tones.digitTone.opacity(0.95)))
                    context.draw(sum, at: CGPoint(x: frame.minX + cell * 0.13,
                                                  y: frame.minY + cell * 0.13))
                }
                for (index, digit) in PrimerFigure.cageDigits {
                    Self.draw(digit: digit, at: Self.centre(index, cell: cell),
                              cell: cell, tone: tones.digitTone, in: context)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        // Cut into the card rather than laid on it — the same recessed rim
        // `MiniBoard` wears, lit from below because that is what a groove does
        // with a light source above it.
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .black.opacity(tones.isLight ? 0.12 : 0.34),
                            .white.opacity(tones.isLight ? 0.55 : 0.10),
                        ],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: CouchSpecular.width)
        }
        // One picture, described by the sentence beside it. A Canvas has no
        // accessible children of its own, and a second element saying
        // "thermometer" would be a label VoiceOver reads before the sentence
        // that explains it.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// A given, at the board's own size and weight.
    private static func draw(
        digit: Int, at point: CGPoint, cell: CGFloat, tone: Color, in context: GraphicsContext
    ) {
        let text = context.resolve(
            Text(verbatim: "\(digit)")
                .font(.system(size: cell * BoardType.given,
                              weight: BoardType.givenWeight, design: .rounded))
                .foregroundStyle(tone))
        context.draw(text, at: point)
    }
}

// MARK: - The pager rail

/// The pager's affordance: chevrons, the channel's name, and three dots.
///
/// **A swipe alone is not an affordance**, which is the lesson PRD-34 records about
/// the stats drawer ("no affordance by design comment, but it fails in practice" —
/// the reason a grabber exists at all). So the page-turn ships paired: the gesture
/// for the hand that already knows, and this for everyone else. It is modelled on
/// `ArchiveSheet.pager`, which is this app's one existing accessible pager, down to
/// `contentShape(.accessibility, Circle())` on a glyph-only button — SwiftUI
/// derives an image button's accessibility frame from the tight glyph bounds, not
/// from `.frame(44, 44)` (PRD-19).
///
/// **Three things it inherited from that pager and should not have.** The chevrons
/// were bare 15pt glyphs with no ground under them, parked at the two extreme
/// screen edges 319pt apart and 123pt from the word they act on — so the control
/// was three objects that did not look related. The disabled one was
/// `.opacity(0.2)`, which measured **1.24:1** and is not a dimmed control but an
/// absent one. And the dots sat in the same `VStack` as the name, which dragged
/// that stack's centre down and left the chevrons' optical centre at 167.8pt
/// against the title's 162 — a 6pt sag that reads as a mistake rather than as a
/// layout.
///
/// So: 44pt glass discs, `.tertiary` for disabled, one row of
/// `chevron · name · chevron` centred as a single object, and the dots on their own
/// row underneath at UIPageControl's own metrics (7pt dots, 9pt gap). The name
/// keeps a 132pt minimum so the chevrons hold still while the pages turn — a
/// control whose buttons move when you press them is a control you have to aim at
/// twice.
///
/// The dots are **not** buttons. Three tappable 7pt dots would be three targets
/// below the 44pt floor sitting next to two that clear it, and the chevrons already
/// reach every page in at most two taps.
///
/// **On a regular width it is not a pager at all, and that is round 4's change.**
/// The panel measured the iPad header band and wrote: *"title occupies 115px on
/// the left, buttons 184px on the right, and the Classic pager 490px dead-centre
/// — leaving roughly 590px of blank lighter grey on each side. On iPad this
/// should be a segmented control or a sidebar rail aligned to the column grid,
/// not a centred iPhone pager floating in a slab."* Correct on every count. A
/// pager is a *phone* control: it exists because there is not room to show three
/// destinations at once, and on an 834pt bar there plainly is. Two chevrons and
/// a word, each reachable in up to two taps, replaced by three names each
/// reachable in one — and the 60%-empty band is filled by the thing the band is
/// for rather than by decoration.
///
/// Resolved from `horizontalSizeClass` rather than from a measured width because
/// this view is an *inset* of `TouchHomeView`'s bar and never learns its own
/// span; the size class is the one honest signal available here, and it is
/// `.compact` on every iPhone, in Slide Over, and in a narrow split view — all
/// three of which genuinely want the pager. The phone rendering is byte-identical
/// to what shipped, which is deliberate: `iphone-dark-channel` and
/// `iphone-light-channel` are confirmed wins and nothing about them is reopened.
struct ChannelPagerRail: View {
    let model: AppModel
    let accent: Color

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var tones: ThemeTones { theme.tones(for: colorScheme) }

    private var pages: [Channel] { Channel.allCases }
    private var index: Int { pages.firstIndex(of: model.channel) ?? 0 }

    /// The narrowest the name's slot gets. Wide enough for every shipped
    /// channel name and for the pseudolocale, and a *minimum* rather than a
    /// fixed width so a long translation grows the cluster instead of
    /// truncating the word.
    private static let nameSlot: CGFloat = 132
    private static let chevronFont = Font.system(size: 15, weight: .semibold)

    @ViewBuilder
    var body: some View {
        if sizeClass == .regular {
            segmented
        } else {
            pager
        }
    }

    // MARK: The regular-width form — three destinations, one tap each

    /// One glass track with three segments in it, and **one** rim around the
    /// whole thing.
    ///
    /// That is `NineLayout.controlGap`'s second clause stated as a control: *"either
    /// separate by this much, or commit to a single glass container with one
    /// continuous rim and an interior divider — never two rims kissing."* The
    /// selected segment is a `card` on a `track`, so it takes the card fill and
    /// `couchRim`, and the track itself is `couchInset` — identity glass, no
    /// second lens — because it is drawn *inside* `shelfBar`'s material and glass
    /// inside glass reads as one murkier pane.
    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(pages, id: \.self) { page in
                segment(page)
            }
        }
        .padding(Space.xs)
        .couchInset(in: Capsule(), tint: Elevation.fill(.track, on: tones))
        .couchRim(in: Capsule(), isLight: tones.isLight)
        // Wide enough to be a control rather than a chip, and capped so it does
        // not become a band on an external display. `NineLayout.readable` is the
        // width past which a single run of chrome stops reading as one object.
        .frame(maxWidth: NineLayout.readable)
    }

    private func segment(_ page: Channel) -> some View {
        let selected = page == model.channel
        return Button {
            withAnimation(.couchFast) { model.channel = page }
        } label: {
            Text(Strings.channel(page))
                .couchText(CouchTypography.body,
                           selected ? Ink.label(on: tones) : Ink.secondary(on: tones))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                // **`Hit.min` on the segment, not on the track.** The floor is a
                // property of the *target*, and a 44pt capsule holding three 36pt
                // targets is three controls under the floor inside one control
                // that clears it — which is precisely the arithmetic `Hit.min`'s
                // own comment calls "a floor that scales is not a floor". The
                // track's 4pt of padding therefore sits outside this, not inside.
                .frame(minHeight: Hit.min)
                .background {
                    if selected {
                        Capsule()
                            .fill(Elevation.fill(.card, on: tones))
                            .overlay {
                                Capsule().strokeBorder(
                                    CouchSpecular.rim(isLight: tones.isLight),
                                    lineWidth: CouchSpecular.width)
                            }
                    }
                }
                // The label is a `Text`, so unlike the chevrons its own bounds
                // already hold the frame open — but the *interaction* shape is
                // still the tight text bounds without this, which on a 44pt-tall
                // segment leaves two thirds of the target dead.
                .contentShape(Capsule())
                .contentShape(.accessibility, Capsule())
        }
        .buttonStyle(.plain)
        // A segmented control speaks as a set of selectable options, not as a
        // pager: "Thermo, selected" rather than "Thermo, page 2 of 3", because
        // there are no pages any more — all three are on screen.
        .accessibilityLabel(Strings.channel(page))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    // MARK: The compact form — unchanged

    private var pager: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: NineLayout.controlGap) {
                // The two `Spacer`s are what make the row one centred object
                // rather than two edge-parked buttons with a word between them.
                Spacer(minLength: 0)
                // The label is resolved at the call site rather than passed as a
                // key, so `scripts/strings.py --audit` can see it. The audit greps
                // for `Strings.string("…")`, and a key threaded through a
                // parameter is a key it reports as dead — which is exactly what it
                // did on the first run of this file.
                chevron("chevron.left", pages: -1, enabled: index > 0,
                        label: Strings.string("channel.previous"))
                Text(Strings.channel(model.channel))
                    .couchText(CouchTypography.body)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: Self.nameSlot)
                    // The *indicator* is one element, so it is heard as "Classic,
                    // page 1 of 3" rather than as a name followed by three
                    // unlabelled dots.
                    //
                    // **The label goes here and not on the enclosing `HStack`, and
                    // driving the app is what settled that.** The first draft put
                    // `.accessibilityElement(children: .contain)` plus this label
                    // on the row, and SwiftUI merged the leading chevron into the
                    // labelled container: `describe-ui` showed "Next channel" but
                    // **no** "Previous channel" on every page — including page 3,
                    // where Next is disabled and Previous is the only one that
                    // works. Nothing on screen changed, all three platform builds
                    // passed, and the board's 81 cells still enumerated. It is the
                    // same trap the Today card carries a comment about
                    // (`TouchUI.swift:308`), where a nested `Button` collapsed an
                    // 89×129 element to 44×44 in a live dump.
                    //
                    // It sits on the `Text` — a leaf — rather than on a container,
                    // now that the dots have moved out of the stack. There is
                    // nothing left here to merge.
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(Strings.string(
                        "channel.pager.label",
                        .text(Strings.channel(model.channel)),
                        .int(index + 1),
                        .int(pages.count)))
                chevron("chevron.right", pages: 1, enabled: index < pages.count - 1,
                        label: Strings.string("channel.next"))
                Spacer(minLength: 0)
            }
            dots
        }
    }

    /// UIPageControl's own metrics: a 7pt dot on a 9pt gap, and an inactive fill
    /// at 45% rather than the 30% this shipped with — under 30% the three dots
    /// read as one dot and two smudges on every light theme.
    private var dots: some View {
        HStack(spacing: 9) {
            ForEach(pages, id: \.self) { page in
                Circle()
                    .fill(page == model.channel ? accent : Color.secondary.opacity(0.45))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    /// The glyph, lit or unlit.
    ///
    /// **Both rungs are `Ink` now, and the enabled one is the reason the token
    /// exists.** A chevron is a control whose *only* content is a symbol, which
    /// is exactly the case `Ink.glyph` is written for: the panel sampled a glyph
    /// at L=146 on a capsule fill at L=91 — **2.15:1**, under WCAG 1.4.11's 3:1
    /// for a graphical object — and the cause is the habit of giving a symbol
    /// inside a container the weight a symbol in a list row gets. `Ink.glyph` is
    /// the theme's own `digitTone` at full strength, which is the same ink the
    /// board draws a given with and the brightest legal mark on the ground.
    ///
    /// The disabled rung moves from SwiftUI's `.tertiary` (~0.25 of the
    /// foreground) to `Ink.tertiary` (0.52 of `digitTone` on dark, 0.50 on
    /// paper). This control has already been through one round of exactly this
    /// bug — it shipped at `.opacity(0.2)`, measured **1.24:1**, and that is not
    /// a dimmed control but an absent one — and `.tertiary` was a step rather
    /// than an answer.
    ///
    /// Still two branches rather than a ternary, but now for a simpler reason:
    /// both are plain `Color`s, so a ternary would type-check — it just reads
    /// worse than the two lines it replaces.
    @ViewBuilder
    private func chevronGlyph(_ symbol: String, enabled: Bool) -> some View {
        if enabled {
            Image(systemName: symbol).font(Self.chevronFont)
                .foregroundStyle(Ink.glyph(on: tones))
        } else {
            Image(systemName: symbol).font(Self.chevronFont)
                .foregroundStyle(Ink.tertiary(on: tones))
        }
    }

    private func chevron(
        _ symbol: String, pages: Int, enabled: Bool, label: String
    ) -> some View {
        Button {
            withAnimation(.couchFast) { model.turnShelf(by: pages) }
        } label: {
            chevronGlyph(symbol, enabled: enabled)
                .frame(width: Hit.min, height: Hit.min)
                .couchGlass(in: Circle())
                // **Both content shapes, and the interaction one is not
                // optional.** `.frame` sets layout size, not hit region: a
                // `Button` whose label is a bare `Image` derives its touch area
                // from the symbol's tight glyph bounds, and `.couchGlass` draws
                // a background rather than contributing hittable content. With
                // only the `.accessibility` shape declared, this chevron
                // *reported* a 44pt target to `describe-ui` and answered taps
                // over roughly a 15pt one — so the page never turned, and the
                // AX tree said it should have. `SchoolView`'s close button
                // carries the same pair for the same reason (PRD-19).
                .contentShape(Circle())
                .contentShape(.accessibility, Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
#endif
