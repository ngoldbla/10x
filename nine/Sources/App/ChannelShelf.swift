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

    /// A compose is running, so `AppModel.composeChannel` will refuse another.
    /// Surfaced rather than swallowed, for `TouchHomeView.composeInFlight`'s
    /// reason — though a variant compose is far cheaper than Nocturne's: thermo's
    /// Release p95 is 0.01–0.03 s and killer's 0.02–0.14 s.
    private var composeInFlight: Bool { model.composing != nil }

    private var isComposingThisChannel: Bool {
        if case .channel(let c, _, _)? = model.composing { return c == channel.channel }
        return false
    }

    var body: some View {
        VStack(spacing: 20) {
            todayCard
            statsSlice
            boardsSection
            tierRow
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
            VStack(alignment: .leading, spacing: 8) {
                Text(Strings.string("channel.stats.title"))
                    .couchText(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(rows, id: \.0) { tier, count, best in
                    HStack(spacing: 8) {
                        Text(Strings.variantTier(tier)).couchText(CouchTypography.caption)
                        Spacer()
                        Text(Strings.string(
                            "channel.stats.row",
                            .int(count), .text(SolveCardFacts.elapsedText(best))))
                            .couchText(CouchTypography.caption)
                            .foregroundStyle(.secondary)
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
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .couchGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    // MARK: Today

    /// This channel's daily. Four mutually-exclusive states in the same order
    /// `TouchHomeView.todayStatus` uses, so the two pages behave identically:
    /// composing, solved, in progress, untouched.
    private var todayCard: some View {
        TouchCard(action: { model.openChannelToday(channel) }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Strings.channel(channel.channel))
                    .couchText(CouchTypography.title)
                Text(Strings.channelBlurb(channel.channel))
                    .couchText(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                todayStatus
            }
            // Matches Classic's Today card exactly. `minHeight` with no maximum is
            // the shape PRD-31 found inflating to half the screen in a second
            // column — safe only because the pager's columns carry
            // `fixedSize(vertical:)`, which is the same fix and the same reason.
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        }
        .disabled(composeInFlight && !isComposingThisChannel)
        .accessibilityLabel(Strings.string(
            "channel.today.label",
            .text(Strings.channel(channel.channel)),
            .text(todayStatusText)))
    }

    @ViewBuilder
    private var todayStatus: some View {
        if isComposingThisChannel {
            statusLabel("status.composing", symbol: "sparkles")
        } else if model.todaySolved(on: channel) {
            statusLabel("status.solved", symbol: "checkmark.circle.fill")
        } else if let entry = model.savedDaily(on: channel) {
            HStack(spacing: 10) {
                BoardFingerprint(game: entry.game, accent: accent, side: 34)
                Text(Strings.string(
                    "shelf.today.continueProgress",
                    .text(BoardProgressCaption.text(for: entry.game))))
                    .couchText(CouchTypography.caption)
            }
        } else {
            // "One a day, per channel" rather than Classic's "One a day": the
            // whole point of a channel is that today's Thermo does not use up
            // today's Classic, and this card is where a player learns it.
            statusLabel("channel.today.oneADay", symbol: "sun.max")
        }
    }

    /// The same sentence the card's accessibility label folds in, so VoiceOver
    /// hears one utterance rather than a title and an orphaned status.
    private var todayStatusText: String {
        if isComposingThisChannel { return Strings.string("status.composing") }
        if model.todaySolved(on: channel) { return Strings.string("status.solved") }
        if let entry = model.savedDaily(on: channel) {
            return Strings.string(
                "shelf.today.continueProgress",
                .text(BoardProgressCaption.text(for: entry.game)))
        }
        return Strings.string("channel.today.oneADay")
    }

    private func statusLabel(_ key: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(accent)
            Text(Strings.string(key)).couchText(CouchTypography.caption)
        }
    }

    // MARK: This channel's boards

    /// In-progress free-play boards on this channel. Absent entirely when there
    /// are none — an honest zero-state is a missing section, not an empty one
    /// (PRD-22's rule, and the reason the shelf has no blank grey rings any more).
    @ViewBuilder
    private var boardsSection: some View {
        let partials = model.partials(on: channel)
        if !partials.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(Strings.string("boards.title"))
                    .couchText(CouchTypography.caption)
                    .foregroundStyle(.secondary)
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
            HStack(spacing: 12) {
                BoardFingerprint(game: entry.game, accent: accent, side: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tierName(entry.kind)).couchText(CouchTypography.body)
                    // A board whose rules this build cannot enforce says so
                    // plainly rather than failing on tap. `openChannelBoard`
                    // refuses it either way; this is what stops the refusal being
                    // a dead tap the player has to guess at.
                    Text(playable
                            ? BoardProgressCaption.text(for: entry.game)
                            : Strings.string("channel.unavailable"))
                        .couchText(CouchTypography.caption)
                        .foregroundStyle(.secondary)
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
    private var tierRow: some View {
        HStack(spacing: 14) {
            ForEach(VariantTier.allCases, id: \.self) { tier in
                TouchCard(action: { model.startChannelFree(channel, tier: tier) }) {
                    VStack(spacing: 10) {
                        Image(systemName: glyph(for: tier))
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(accent)
                        Text(Strings.variantTier(tier))
                            .couchText(CouchTypography.caption)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96)
                    // **The accessibility frame is the card, not the glyph.**
                    // Without this the first `channel.txt` baseline recorded
                    // `Gentle, Thermo (55,439 41x48)` — 41pt wide, under the
                    // charter's 44pt floor — because SwiftUI derives the frame
                    // from the tight content bounds when the content is only a
                    // symbol and a caption. Classic's difficulty cards escape it
                    // by accident: their `MiniBoard` is 64pt and forces the width.
                    // Invisible in a screenshot, since the card *looks* full-width;
                    // `ax-snapshot.py` is the only thing that disagrees
                    // (EXECUTING-A-PRD §4).
                    .contentShape(
                        .accessibility,
                        RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .disabled(composeInFlight)
                .accessibilityLabel(Strings.string(
                    "shelf.difficulty.label",
                    .text(Strings.variantTier(tier)),
                    .text(Strings.channel(channel.channel))))
            }
        }
    }

    /// One glyph per tier, rising. Reuses the SF Symbols vocabulary the classic
    /// bands already established rather than inventing a variant one.
    private func glyph(for tier: VariantTier) -> String {
        switch tier {
        case .gentle: return "leaf"
        case .steady: return "circle.grid.2x2"
        case .sharp: return "bolt"
        }
    }
}

/// The pager's affordance: chevrons, the channel's name, and three dots.
///
/// **A swipe alone is not an affordance**, which is the lesson PRD-34 records about
/// the stats drawer ("no affordance by design comment, but it fails in practice" —
/// the reason a grabber exists at all). So the page-turn ships paired: the gesture
/// for the hand that already knows, and this for everyone else. It is modelled on
/// `ArchiveSheet.pager`, which is this app's one existing accessible pager, down to
/// the 0.2-opacity disabled edges and `contentShape(.accessibility, Circle())` on a
/// glyph-only button — SwiftUI derives an image button's accessibility frame from
/// the tight glyph bounds, not from `.frame(44, 44)` (PRD-19).
///
/// The dots are **not** buttons. Three tappable 8pt dots would be three targets
/// below the 44pt floor sitting next to two that clear it, and the chevrons already
/// reach every page in at most two taps.
struct ChannelPagerRail: View {
    let model: AppModel
    let accent: Color

    private var pages: [Channel] { Channel.allCases }
    private var index: Int { pages.firstIndex(of: model.channel) ?? 0 }

    var body: some View {
        HStack(spacing: 10) {
            // The label is resolved at the call site rather than passed as a key,
            // so `scripts/strings.py --audit` can see it. The audit greps for
            // `Strings.string("…")`, and a key threaded through a parameter is a
            // key it reports as dead — which is exactly what it did on the first
            // run of this file.
            chevron("chevron.left", pages: -1, enabled: index > 0,
                    label: Strings.string("channel.previous"))
            VStack(spacing: 6) {
                Text(Strings.channel(model.channel))
                    .couchText(CouchTypography.body)
                dots
            }
            .frame(maxWidth: .infinity)
            // The *indicator* is one element, so it is heard as "Classic, page 1
            // of 3" rather than as a name followed by three unlabelled dots.
            //
            // **The label goes here and not on the enclosing `HStack`, and driving
            // the app is what settled that.** The first draft put
            // `.accessibilityElement(children: .contain)` plus this label on the
            // row, and SwiftUI merged the leading chevron into the labelled
            // container: `describe-ui` showed "Next channel" but **no** "Previous
            // channel" on every page — including page 3, where Next is disabled and
            // Previous is the only one that works. Nothing on screen changed, all
            // three platform builds passed, and the board's 81 cells still
            // enumerated. It is the same trap the Today card carries a comment
            // about (`TouchUI.swift:308`), where a nested `Button` collapsed an
            // 89×129 element to 44×44 in a live dump.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(Strings.string(
                "channel.pager.label",
                .text(Strings.channel(model.channel)),
                .int(index + 1),
                .int(pages.count)))
            chevron("chevron.right", pages: 1, enabled: index < pages.count - 1,
                    label: Strings.string("channel.next"))
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(pages, id: \.self) { page in
                Circle()
                    .fill(page == model.channel ? accent : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func chevron(
        _ symbol: String, pages: Int, enabled: Bool, label: String
    ) -> some View {
        Button {
            withAnimation(.couchFast) { model.turnShelf(by: pages) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(.accessibility, Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.2)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
#endif
