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

/// One variant channel's page: its Today, its streak, its boards, its tiers.
///
/// Structurally the same order Classic asks its questions in — what is today, what
/// was I in the middle of, what could I start — because a player turning the page
/// should find the same shelf with different rules on it, not a different app.
struct ChannelShelfContent: View {
    let model: AppModel
    let channel: Channel.Ledgered
    let accent: Color

    /// `TouchCard`'s corner and its padding, restated once here rather than
    /// eleven times.
    ///
    /// The card chrome on this page is `TouchCard`'s (`TouchUI.swift`), which
    /// hard-codes a 24pt continuous radius and 18pt of padding. Two surfaces
    /// here are *not* buttons — the stats slice and the primer — and have to
    /// draw that chrome themselves; a third (the accessibility content shape on
    /// a tier card) has to match its silhouette. When `TouchCard` grows a
    /// `radius:` parameter these become the argument rather than a copy.
    private static let cardRadius: CGFloat = 24
    private static let cardPadding: CGFloat = 18

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
    }

    /// A compose is running, so `AppModel.composeChannel` will refuse another.
    /// Surfaced rather than swallowed, for `TouchHomeView.composeInFlight`'s
    /// reason — though a variant compose is far cheaper than Nocturne's: thermo's
    /// Release p95 is 0.01–0.03 s and killer's 0.02–0.14 s.
    private var composeInFlight: Bool { model.composing != nil }

    /// **This channel's *daily* is composing** — not any board on it.
    ///
    /// It used to match `.channel(c, _, _)` and so fired for a free-play compose
    /// too, which made the Today card announce "Composing…" for a board that is
    /// not its own and left it tappable while a foreign compose ran. That is the
    /// exact defect `TouchHomeView.isComposingDaily` carries a comment about
    /// (PRD-14, "a `.daily(day:)` compose may be for 12 July"); a channel daily
    /// is the `.channel` case with a non-nil `day`, and a tier card is the same
    /// case with a nil one — `AppModel.openChannelToday` / `startChannelFree`.
    private var isComposingThisDaily: Bool {
        if case .channel(let c, _, let day)? = model.composing {
            return c == channel.channel && day != nil
        }
        return false
    }

    /// One tier card's own compose, for the caption that replaces its blurb.
    private func isComposing(_ tier: VariantTier) -> Bool {
        if case .channel(let c, let t, let day)? = model.composing {
            return c == channel.channel && t == tier && day == nil
        }
        return false
    }

    var body: some View {
        VStack(spacing: Space.xl) {
            todayCard
            statsSlice
            boardsSection
            tierRow
            channelPrimer
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
                    .couchText(CouchTypography.label, .secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(rows, id: \.0) { tier, count, best in
                    HStack(spacing: Space.s) {
                        Text(Strings.variantTier(tier)).couchText(CouchTypography.label)
                        Spacer()
                        Text(Strings.string(
                            "channel.stats.row",
                            .int(count), .text(SolveCardFacts.elapsedText(best))))
                            .couchText(CouchTypography.label, .secondary)
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
            .couchGlass(in: cardShape)
        }
    }

    // MARK: Today

    /// This channel's daily. Four mutually-exclusive states in the same order
    /// `TouchHomeView.todayStatus` uses, so the two pages behave identically:
    /// composing, solved, in progress, untouched.
    ///
    /// **The title is "Today", not the channel's name** — Classic's word, in
    /// Classic's slot. The name was here twice at two sizes: 17pt in the pager
    /// rail and 30pt on this card 40pt below it, which spent the page's largest
    /// type on information the reader had just been given and left the card with
    /// no line saying what it was *for*. The ramp now runs
    /// title / heading / label / caption with a distinct role on each rung.
    private var todayCard: some View {
        TouchCard(action: { model.openChannelToday(channel) }) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Strings.string("shelf.today.title"))
                    .couchText(CouchTypography.title)
                // Classic's date line, which this card dropped. Same formatter,
                // same rung, same position under the title.
                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .couchText(CouchTypography.caption, .secondary)
                Text(Strings.channelBlurb(channel.channel))
                    .couchText(CouchTypography.heading, .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                todayStatus
            }
            // Matches Classic's Today card exactly. `minHeight` with no maximum is
            // the shape PRD-31 found inflating to half the screen in a second
            // column — safe only because the pager's columns carry
            // `fixedSize(vertical:)`, which is the same fix and the same reason.
            //
            // The 54pt void this used to hold between the blurb and the status
            // line is gone because the card now has enough in it to fill 130:
            // a date, a subtitle at `heading`, and a 34pt picture in *every*
            // status — not just the resumable one.
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        }
        .disabled(composeInFlight && !isComposingThisDaily)
        .accessibilityLabel(Strings.string(
            "channel.today.label",
            .text(Strings.channel(channel.channel)),
            .text(todayStatusText)))
    }

    @ViewBuilder
    private var todayStatus: some View {
        if isComposingThisDaily {
            statusLabel("status.composing", symbol: "sparkles")
        } else if model.todaySolved(on: channel) {
            statusLabel("status.solved", symbol: "checkmark.circle.fill")
        } else if let entry = model.savedDaily(on: channel) {
            HStack(spacing: Space.m) {
                BoardFingerprint(game: entry.game, accent: accent, side: 34)
                Text(Strings.string(
                    "shelf.today.continueProgress",
                    .text(BoardProgressCaption.text(for: entry.game))))
                    .couchText(CouchTypography.label, .secondary)
            }
        } else {
            // "One a day, per channel" rather than Classic's "One a day": the
            // whole point of a channel is that today's Thermo does not use up
            // today's Classic, and this card is where a player learns it.
            //
            // **With the channel's own motif in the fingerprint's slot**, at the
            // fingerprint's size and on the fingerprint's side. An untouched
            // channel is the state a new player meets first and it was the one
            // state of the four with no picture in it at all — a sun glyph that
            // said nothing about thermometers or cages.
            HStack(spacing: Space.m) {
                ChannelMotif(channel: channel, side: 34)
                Text(Strings.string("channel.today.oneADay"))
                    .couchText(CouchTypography.label, .secondary)
            }
        }
    }

    /// The same sentence the card's accessibility label folds in, so VoiceOver
    /// hears one utterance rather than a title and an orphaned status.
    private var todayStatusText: String {
        if isComposingThisDaily { return Strings.string("status.composing") }
        if model.todaySolved(on: channel) { return Strings.string("status.solved") }
        if let entry = model.savedDaily(on: channel) {
            return Strings.string(
                "shelf.today.continueProgress",
                .text(BoardProgressCaption.text(for: entry.game)))
        }
        return Strings.string("channel.today.oneADay")
    }

    /// A glyph and a sentence, secondary throughout.
    ///
    /// **The whole row is `.secondary`, including the glyph**, which is what
    /// `TouchHomeView.statusLabel` does. This one tinted its symbol `accent`,
    /// and on a shelf whose thesis is that the two pages behave identically a
    /// coloured checkmark on one page and a grey one on the other is visible
    /// drift. The `Text` resolves its own `.secondary` through
    /// `couchText(_:_:)` because the outer `foregroundStyle` cannot reach
    /// inside it (that is this file's whole colour bug); the outer one is what
    /// colours the `Image`.
    private func statusLabel(_ key: String, symbol: String) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
            Text(Strings.string(key)).couchText(CouchTypography.label, .secondary)
        }
        .foregroundStyle(.secondary)
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
                    .couchText(CouchTypography.label, .secondary)
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
        return TouchCard(action: { model.openChannelBoard(entry.id) }) {
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
                        .couchText(CouchTypography.label, .secondary)
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
    /// `spacing: 14` and `spacing: 10` are Classic's numbers, off the 4pt grid
    /// and kept anyway: this row has to be the same object as the one on the
    /// page next door, and a 2pt disagreement between two rows a swipe apart is
    /// exactly the kind of drift the page-turn makes visible.
    private var tierRow: some View {
        HStack(spacing: 14) {
            ForEach(VariantTier.allCases, id: \.self) { tier in
                TouchCard(action: { model.startChannelFree(channel, tier: tier) }) {
                    VStack(spacing: 10) {
                        // `MiniBoard`'s default corner is `Radius.inner(24,
                        // inset: 18)` — concentric with `TouchCard` exactly as
                        // it stands. If `TouchCard` ever takes a radius and this
                        // row passes 20, this call has to pass
                        // `Radius.inner(20, inset: 18)` with it.
                        MiniBoard(difficulty: tier.wireDifficulty, accent: accent)
                            .frame(width: 64, height: 64)
                        if isComposing(tier) {
                            // The composing caption replaces the name and the
                            // blurb rather than stacking under them — Classic's
                            // rule, for Classic's reason: a card that grows a
                            // line mid-compose shoves the rest of the shelf
                            // down while the player watches.
                            statusLabel("status.composing", symbol: "sparkles")
                        } else {
                            Text(Strings.variantTier(tier))
                                .couchText(CouchTypography.label)
                                .multilineTextAlignment(.center)
                            Text(tier.blurb)
                                .couchText(CouchTypography.caption, .secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 124)
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
                    .contentShape(.accessibility, cardShape)
                }
                .disabled(composeInFlight)
                .accessibilityLabel(Strings.string(
                    "shelf.difficulty.label",
                    .text(Strings.variantTier(tier)),
                    .text(Strings.channel(channel.channel))))
            }
        }
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
    @ViewBuilder
    private var channelPrimer: some View {
        if model.history(on: channel).records.isEmpty {
            HStack(alignment: .top, spacing: Space.l) {
                ChannelPrimerArt(channel: channel, accent: accent, side: 132)
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(Strings.string("tutorial.title"))
                        .couchText(CouchTypography.label, .secondary)
                        .accessibilityAddTraits(.isHeader)
                    // Prose at `body`, which is the rung's own definition
                    // ("everything readable") and the only paragraph on the
                    // page. `label` is semibold, and five semibold lines read
                    // as a warning rather than as an explanation.
                    Text(primerRule)
                        .couchText(CouchTypography.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Self.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .couchGlass(in: cardShape)
        }
    }

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
private struct ChannelPrimerArt: View {
    let channel: Channel.Ledgered
    let accent: Color
    var side: CGFloat = 132

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
            for index in 0..<9 {
                let frame = Self.rect(index, cell: cell)
                    .insetBy(dx: cell * BoardArt.cellInset, dy: cell * BoardArt.cellInset)
                context.fill(
                    Path(roundedRect: frame, cornerRadius: cell * BoardArt.cellCorner),
                    with: .color(tones.gridTone.opacity(tones.isLight ? 0.14 : 0.09)))
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
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
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

/// The channel's constraint at glyph size — a bulb and a tube, or a dashed cage.
///
/// **Not an SF Symbol, and that is the point.** The Today card's untouched state
/// had `sun.max` on it, which is a picture of "daily" on a page whose whole
/// argument is that this daily is a *different ruleset*. This is the same art
/// the board draws, at 34pt.
///
/// The opacities are higher than the board's and than the primer's, because this
/// is 34pt: the tube's shipped `0.17` body is invisible at a fifth of a cell's
/// width. Same colours — `gridTone` for the tube and `digitTone` for the cage,
/// the way `BoardView` assigns them — and same construction.
private struct ChannelMotif: View {
    let channel: Channel.Ledgered
    var side: CGFloat = 34

    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var tones: ThemeTones { theme.tones(for: colorScheme) }

    var body: some View {
        let tones = self.tones
        let channel = self.channel
        Canvas { context, size in
            switch channel {
            case .thermo:
                // One straight tube on the diagonal: at 34pt a bend costs more
                // legibility than it buys meaning.
                let bulb = CGPoint(x: size.width * 0.27, y: size.height * 0.73)
                let tip = CGPoint(x: size.width * 0.78, y: size.height * 0.24)
                var spine = Path()
                spine.move(to: bulb)
                spine.addLine(to: tip)
                context.stroke(
                    spine, with: .color(tones.gridTone.opacity(0.34)),
                    style: StrokeStyle(lineWidth: size.width * 0.26, lineCap: .round))
                context.stroke(
                    spine, with: .color(tones.gridTone.opacity(0.62)),
                    style: StrokeStyle(lineWidth: size.width * 0.08, lineCap: .round))
                let radius = size.width * 0.19
                let disc = Path(ellipseIn: CGRect(
                    x: bulb.x - radius, y: bulb.y - radius,
                    width: radius * 2, height: radius * 2))
                context.fill(disc, with: .color(tones.gridTone.opacity(0.34)))
                context.stroke(disc, with: .color(tones.gridTone.opacity(0.62)), lineWidth: 1)

            case .killer:
                // Three cells of a 2×2, so the outline has an inside corner in
                // it — a plain square would read as a border, not as a cage.
                let cell = size.width * 0.34
                let origin = CGPoint(x: (size.width - cell * 2) / 2,
                                     y: (size.height - cell * 2) / 2)
                let members: Set<Int> = [0, 1, 2]
                context.stroke(
                    cageOutline(members: members, across: 2, cell: cell,
                                origin: origin, inset: cell * 0.08),
                    with: .color(tones.digitTone.opacity(0.78)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 1.6]))
                for index in members.sorted() {
                    let centre = CGPoint(
                        x: origin.x + (CGFloat(index % 2) + 0.5) * cell,
                        y: origin.y + (CGFloat(index / 2) + 0.5) * cell)
                    let radius = cell * 0.15
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: centre.x - radius, y: centre.y - radius,
                            width: radius * 2, height: radius * 2)),
                        with: .color(tones.digitTone.opacity(0.62)))
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
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
struct ChannelPagerRail: View {
    let model: AppModel
    let accent: Color

    private var pages: [Channel] { Channel.allCases }
    private var index: Int { pages.firstIndex(of: model.channel) ?? 0 }

    /// The narrowest the name's slot gets. Wide enough for every shipped
    /// channel name and for the pseudolocale, and a *minimum* rather than a
    /// fixed width so a long translation grows the cluster instead of
    /// truncating the word.
    private static let nameSlot: CGFloat = 132
    private static let chevronFont = Font.system(size: 15, weight: .semibold)

    var body: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.m) {
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
    /// Two branches rather than a ternary inside `foregroundStyle` because
    /// `.primary` and `.tertiary` are both leading-dot members resolved against
    /// the generic `some ShapeStyle`, and a ternary of two of those is a shape
    /// the type-checker has no reason to solve.
    @ViewBuilder
    private func chevronGlyph(_ symbol: String, enabled: Bool) -> some View {
        if enabled {
            Image(systemName: symbol).font(Self.chevronFont).foregroundStyle(.primary)
        } else {
            Image(systemName: symbol).font(Self.chevronFont).foregroundStyle(.tertiary)
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
