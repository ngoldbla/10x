// FirstRun.swift — the first thirty seconds of Nine on iPhone and iPad
// (PRD-34 "The First Five Minutes" + PRD-18 "Welcome card").
//
// Two PRDs, one screen sequence, because a buyer does not experience them
// separately: a welcome that confirms what $4.99 just bought, and then the
// tutorial's first beat played for real — one empty cell, one flick, one 7.
// Nothing else. The old first-run legend card is gone: a list of six gestures
// is a manual, and a manual is what the app is trying not to need. (It still
// exists, verbatim, in Settings ▸ How to play, where a manual belongs.)
//
// Two flags, deliberately independent, because the update install is the case
// that gets forgotten:
//
//   welcome.seen   help.seen   what happens
//   ------------   ---------   ---------------------------------------------
//   false          false       fresh install: ledger, then the flick
//   false          true        updating from 1.1: ledger only — this player
//                              learned the rose a year ago
//   true           false       (only reachable by a hand-edited container)
//   true           true        nothing, forever
//
// Rules this screen holds itself to:
//   • One tap out, from the first frame. Skip is never more than one tap away
//     and never scrolls off.
//   • The beat teaches by doing. No arrows drawn on a screenshot, no "tap
//     here" pointer chasing a finger — the rose is open on a real board and
//     the digit really lands.
//   • It never claims a feature Nine does not ship today. The ledger counts
//     its themes and accents from the enums so the copy cannot rot.
#if os(iOS)
import SwiftUI
import CouchKit

struct FirstRunFlow: View {
    let model: AppModel
    let accent: Color

    private enum Stage { case welcome, flick }

    @State private var stage: Stage
    @Environment(\.colorScheme) private var colorScheme

    init(model: AppModel, accent: Color) {
        self.model = model
        self.accent = accent
        _stage = State(initialValue: model.welcomeSeen ? .flick : .welcome)
    }

    private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }

    var body: some View {
        ZStack {
            // Was a flat `black.opacity(0.55)`, which is the one scrim recipe
            // that cannot be right on nine themes: a player who bought Nine and
            // picked Blueprint or Ember spends their first thirty seconds
            // looking at their theme *greyed out*, because black takes the hue
            // away before it takes the luminance. `Scrim.overlay` scrims a dark
            // ground with the ground itself — which dims the backdrop and
            // pushes it behind the card at the same time — and keeps black for
            // the light themes, where scrimming a bright ground with itself
            // would brighten rather than dim.
            Scrim.overlay(for: tones)
                .ignoresSafeArea()
                // Swallow taps: dismissal is Begin, Skip, or the flick itself.
                // A stray tap must not cost a player the one welcome they get.
                .onTapGesture { }
            switch stage {
            case .welcome:
                WelcomeCard(accent: accent, tones: tones, onBegin: finishWelcome)
                    .transition(.opacity)
            case .flick:
                FirstFlickBeat(accent: accent, tones: tones, onFinish: finishBeat)
                    .transition(.opacity)
            }
        }
        .animation(.couchFast, value: stage)
    }

    private func finishWelcome() {
        model.welcomeSeen = true
        // An updating player already knows the rose; the ledger was the whole
        // of their first run.
        if model.helpSeen { return }
        withAnimation(.couchFast) { stage = .flick }
    }

    private func finishBeat() {
        model.helpSeen = true
        model.welcomeSeen = true
    }
}

// MARK: - Welcome (PRD-18)

/// The one moment Nine is allowed to talk about itself: a ledger of what the
/// purchase included, shown once and never again. No price, no upsell, no
/// "rate us" — there is nothing left to sell.
private struct WelcomeCard: View {
    let accent: Color
    let tones: ThemeTones
    let onBegin: @MainActor () -> Void

    /// What is actually in the box today. Adding a row here is a claim; it
    /// belongs to the release that ships the thing.
    private var ledger: [(symbol: String, text: String)] {
        [
            ("checkmark.seal", Phrase.ledgerProof),
            ("chart.line.uptrend.xyaxis", Phrase.ledgerStats),
            ("paintpalette", Phrase.ledgerThemes(
                themes: ThemeChoice.allCases.count,
                accents: AccentChoice.allCases.count
            )),
            ("icloud", Phrase.ledgerSync),
            ("hand.raised", Phrase.ledgerCovenant),
        ]
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: Space.s) {
                Text(Phrase.welcomeTitle)
                    .couchText(CouchTypography.title)
                Text(Phrase.welcomeTagline)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(ledger, id: \.text) { row in
                    HStack(spacing: 14) {
                        Image(systemName: row.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(width: 26)
                            // Decoration. Left in the tree, VoiceOver prefixes
                            // every row with the SF Symbol's own description —
                            // "Brightness Higher, image. A new board every
                            // day…", "Block, image. No ads…" — which is noise
                            // in front of a sentence that already says it.
                            .accessibilityHidden(true)
                        Text(row.text)
                            .font(CouchTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Phrase.onePurchase)
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // The app's very first primary action, and it shipped as neutral
            // glass *inside* neutral glass: two `.regular` lenses stacked read
            // as one slightly murkier pane, so the one button on the first
            // screen had roughly the same presence as the card behind it. This
            // is the rung the ladder keeps for the surface that outranks the
            // others — a tint, not a second material.
            Button(action: onBegin) {
                Text(Phrase.begin)
                    .font(CouchTypography.body)
                    // White on a dark ground; the theme's own deepened accent
                    // on a light one. `AccentChoice.color(isLight:)` already
                    // darkens every accent for paper, so on Camel or Paper the
                    // label is the ink of the wash it sits in — white there
                    // would be a 22% tint carrying white text on a bright
                    // material, which is the one combination this capsule
                    // cannot survive.
                    .foregroundStyle(tones.isLight ? AnyShapeStyle(accent)
                                                   : AnyShapeStyle(Color.white))
                    // `hero` horizontally against `m` vertically: the widest
                    // rung the scale has, which is what makes a capsule read as
                    // a button rather than as a chip. The vertical 12 puts the
                    // capsule at ~44 with a body label — `Hit.min` exactly, and
                    // that is why it is not smaller.
                    .padding(.horizontal, Space.hero)
                    .padding(.vertical, Space.m)
                    .couchGlassTinted(accent.opacity(0.22), in: Capsule())
                    .contentShape(.accessibility, Capsule())
            }
            .buttonStyle(.plain)
        }
        // Space.xxl / Space.xl, and identically to `FirstFlickBeat` below.
        // These two cards are siblings a single tap apart — one replaces the
        // other in the same ZStack — and they disagreed by 6pt inside and 4pt
        // outside, which on a crossfade is a card that visibly resizes for no
        // reason a player could name.
        .padding(Space.xxl)
        .frame(maxWidth: 460)
        // `Radius.sheet`, written the same way in both cards. The two of them
        // were the app's only 32s — the exact species of unnamed radius the
        // ladder exists to end — and a modal card over a scrim is a panel by
        // every other measure in the app. Elevated, because a card floating on
        // a scrim with no rim and no shadow is a rectangle *printed on* the
        // scrim rather than a pane held above it.
        .couchGlassElevated(
            in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous),
            isLight: tones.isLight)
        .padding(Space.xl)
    }
}

// MARK: - The first beat (PRD-34)

/// First launch *is* the tutorial's first beat. One cell is empty, the rose is
/// already open on it, and the only thing left to do is the thing the whole app
/// is built around. The claim in the PRD is "superpower within 60 seconds";
/// this is the version that takes about ten.
private struct FirstFlickBeat: View {
    let accent: Color
    let tones: ThemeTones
    let onFinish: @MainActor () -> Void

    @State private var game: NineGame?
    @State private var targetCell = 40
    /// Pre-opened: the first gesture of a player's life in Nine should be the
    /// flick, not a tap that reveals a thing to flick.
    @State private var rose: RoseState? = RoseState(pencil: false)
    @State private var placed = false
    @State private var exitTask: Task<Void, Never>?
    /// PRD-22: the petal lens is motion, so Reduce Motion keeps the material.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var targetDigit: Int {
        game?.puzzle.solution.cells[targetCell] ?? 7
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: Space.l) {
                header
                instruction
                boardArea(geo: geo)
                footer
            }
            // The same two rungs the welcome card uses, in the same order. See
            // `WelcomeCard.body`: these are siblings and they now measure alike.
            .padding(Space.xxl)
            .frame(maxWidth: 560)
            .couchGlassElevated(
                in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous),
                isLight: tones.isLight)
            .padding(Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await composeBoard() }
        .onDisappear { exitTask?.cancel() }
    }

    private var header: some View {
        HStack {
            Text(Phrase.beatTitle)
                .couchText(CouchTypography.title)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            // The escape hatch, in the first frame and every frame after it.
            // `label`, not `caption`: the ramp's caption is the 11pt tier now,
            // and the one way out of the first run is not an 11pt word.
            Button(Phrase.skip) { finish() }
                .font(CouchTypography.label)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(minWidth: Hit.min, minHeight: Hit.min)
                .contentShape(.accessibility, Rectangle())
        }
    }

    private var instruction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(placed ? Phrase.beatDoneTitle : Phrase.beatPrompt(digit: targetDigit))
                .font(CouchTypography.body)
            Text(placed ? Phrase.beatDoneDetail : Phrase.beatDetail(digit: targetDigit))
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Swapped, not crossfaded. The two states are different lengths, so
        // animating the change dissolves a three-line paragraph through a
        // one-line one and both are legible at once for the whole beat — the
        // congratulation is only on screen for two seconds and has to read
        // cleanly from the first frame. The "Nice" chip below carries the
        // motion instead.
        .animation(nil, value: placed)
    }

    @ViewBuilder
    private func boardArea(geo: GeometryProxy) -> some View {
        if let game {
            let inset: CGFloat = 10
            // Sized against the *card*, not the screen. `BoardView` sets a hard
            // `.frame(width:height:)`, so it draws `side + 2 * inset` whatever
            // it is offered — and the card is capped at 560pt, which the screen
            // is not. Measured on an 834pt iPad: a screen-derived side drew a
            // 649pt board inside a 520pt card, hanging 65pt off both edges and
            // over the instruction's last line.
            //
            // Both subtractions are now derived from the two paddings above
            // rather than guessed at: the card is the screen less its outer
            // margin on each side, and the board is the card less its interior
            // padding on each side *and* the two insets `BoardView` adds back.
            // The old `- 64` was 20pt of padding plus 24pt of slack, and it
            // survived the padding moving to 28 only by overhanging it.
            let cardWidth = min(geo.size.width - 2 * Space.xl, 560)
            let side = max(200, min(cardWidth - 2 * (Space.xxl + inset),
                                    geo.size.height * 0.52))
            let lens = rose.map { roseLens(side: side, inset: inset, rose: $0) }
            BoardView(
                game: game,
                cursor: targetCell,
                accent: accent,
                showErrors: true,
                solvedAt: nil,
                roseOpen: rose != nil,
                roseLens: reduceMotion ? nil : lens,
                previewDigit: nil,
                previewPencil: false,
                highlightDigit: nil,
                side: side,
                inset: inset
            )
            .contentShape(Rectangle())
            // Re-open, rather than "tap outside cancels": a player who dismisses
            // the rose in the one beat that is about the rose is left with a
            // board and no lesson.
            .onTapGesture {
                guard rose == nil, !placed else { return }
                withAnimation(.couchFast) { rose = RoseState(pencil: false) }
            }
            .overlay {
                if let rose, let lens {
                    TouchRose(
                        state: rose,
                        accent: accent,
                        completedDigits: Set((1...9).filter { game.isDigitComplete($0) }),
                        scale: lens.scale,
                        onDigit: { commit(digit: $0) },
                        // Not modal here: Skip and the lesson share this card
                        // with the ring, and they have to stay reachable.
                        isModal: false,
                        // The petals' numerals in the theme's own digit tone,
                        // the same way the game screen passes it — without this
                        // the first rose a player ever sees is the one rose in
                        // the app drawn off-palette.
                        digitTone: tones.digitTone
                    )
                    .position(x: lens.viewCentre.x, y: lens.viewCentre.y)
                }
            }
        } else {
            GlassChip(Phrase.composing, systemImage: "sparkles")
                .frame(minHeight: 220)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if placed {
            GlassChip(Phrase.beatNice, systemImage: "checkmark")
                .transition(.opacity)
        } else {
            Text(Phrase.beatHint)
                // One of the 19 verbatim copies of this tier. It is the ramp's
                // `caption` now, which means it also scales with Dynamic Type —
                // a hard 11 was the smallest thing on the first screen and the
                // one piece of type on it that ignored the size the player set.
                .font(CouchTypography.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Same geometry as the game screen, from the same value: the rose never
    /// leaves the board, and the board bends where the petals are (PRD-22).
    private func roseLens(side: CGFloat, inset: CGFloat, rose: RoseState) -> RoseLens {
        RoseLens(
            cursor: targetCell,
            side: Double(side),
            inset: Double(inset),
            pencil: rose.pencil,
            scale: RoseLens.scale(forSide: Double(side))
        )
    }

    private func commit(digit: Int) {
        guard var g = game, !placed else { return }
        g.place(digit, at: targetCell)
        game = g
        withAnimation(.couchFast) { rose = nil }
        // A wrong digit is not a failure here — it marks itself coral on the
        // board, which is its own lesson. The beat ends on the right one.
        guard digit == targetDigit else {
            withAnimation(.couchFast) { rose = RoseState(pencil: false) }
            return
        }
        withAnimation(.couchFast) { placed = true }
        exitTask?.cancel()
        exitTask = Task {
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        exitTask?.cancel()
        onFinish()
    }

    /// A gentle seeded board with five cells open, one of which wants a 7 —
    /// the same practice position the full tutorial uses, targeted at the digit
    /// the PRD names. Nearly-finished, so "fill every row, column and box"
    /// reads off the screen without a paragraph explaining it.
    private func composeBoard() async {
        guard game == nil else { return }
        let puzzle = await Task.detached(priority: .userInitiated) {
            PuzzleGenerator.generate(seed: 0x9109, difficulty: .gentle)
        }.value
        var g = NineGame(puzzle: puzzle)
        let empties = (0..<81).filter { g.entry(at: $0) == 0 }
        // Prefer a 7 so the copy matches the board; fall back to whatever the
        // first hole wants rather than shipping a lesson that cannot start.
        let target = empties.first { puzzle.solution.cells[$0] == 7 } ?? empties.first ?? 40
        let openCells = Set(empties.filter { $0 != target }.suffix(4) + [target])
        for cell in empties where !openCells.contains(cell) {
            g.place(puzzle.solution.cells[cell], at: cell)
        }
        targetCell = target
        game = g
    }
}

// MARK: - Copy

/// Every user-facing string on the first run, in one block (PRD-20's seam).
private enum Phrase {
    static let welcomeTitle = Strings.string("firstrun.welcome.title")
    static let welcomeTagline = Strings.string("firstrun.welcome.tagline")

    static let ledgerProof = Strings.string("firstrun.ledger.proof")
    static let ledgerStats = Strings.string("firstrun.ledger.stats")
    static func ledgerThemes(themes: Int, accents: Int) -> String {
        Strings.string("firstrun.ledger.themes", .int(themes), .int(accents))
    }
    static let ledgerSync = Strings.string("firstrun.ledger.sync")
    static let ledgerCovenant = Strings.string("firstrun.ledger.covenant")
    static let onePurchase = Strings.string("firstrun.onePurchase")
    static let begin = Strings.string("firstrun.begin")

    static let beatTitle = Strings.string("firstrun.beat.title")
    static let skip = Strings.string("firstrun.beat.skip")
    static func beatPrompt(digit: Int) -> String {
        Strings.string("firstrun.beat.prompt", .int(digit))
    }
    /// The digit twice, as two arguments rather than one interpolated twice —
    /// a translation may reorder the two sentences, and `%1$lld`/`%2$lld` are
    /// what let it move both.
    static func beatDetail(digit: Int) -> String {
        Strings.string("firstrun.beat.detail", .int(digit), .int(digit))
    }
    static let beatHint = Strings.string("firstrun.beat.hint")
    static let beatDoneTitle = Strings.string("firstrun.beat.doneTitle")
    static let beatDoneDetail = Strings.string("firstrun.beat.doneDetail")
    /// The same chip the tutorial shows when a beat is completed.
    static let beatNice = TutorialPhrase.nice
    static let composing = Strings.string("status.composing")
}
#endif
