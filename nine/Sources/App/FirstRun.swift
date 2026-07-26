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

    init(model: AppModel, accent: Color) {
        self.model = model
        self.accent = accent
        _stage = State(initialValue: model.welcomeSeen ? .flick : .welcome)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                // Swallow taps: dismissal is Begin, Skip, or the flick itself.
                // A stray tap must not cost a player the one welcome they get.
                .onTapGesture { }
            switch stage {
            case .welcome:
                WelcomeCard(accent: accent, onBegin: finishWelcome)
                    .transition(.opacity)
            case .flick:
                FirstFlickBeat(accent: accent, onFinish: finishBeat)
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
    let onBegin: @MainActor () -> Void

    /// What is actually in the box today. Adding a row here is a claim; it
    /// belongs to the release that ships the thing.
    private var ledger: [(symbol: String, text: String)] {
        [
            ("sun.max", Phrase.ledgerDaily),
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
            VStack(spacing: 8) {
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

            Button(action: onBegin) {
                Text(Phrase.begin)
                    .font(CouchTypography.body)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 12)
                    .couchGlassInteractive(in: Capsule())
                    .contentShape(.accessibility, Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(26)
        .frame(maxWidth: 460)
        .couchGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(20)
    }
}

// MARK: - The first beat (PRD-34)

/// First launch *is* the tutorial's first beat. One cell is empty, the rose is
/// already open on it, and the only thing left to do is the thing the whole app
/// is built around. The claim in the PRD is "superpower within 60 seconds";
/// this is the version that takes about ten.
private struct FirstFlickBeat: View {
    let accent: Color
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
            VStack(spacing: 16) {
                header
                instruction
                boardArea(geo: geo)
                footer
            }
            .padding(20)
            .frame(maxWidth: 560)
            .couchGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(16)
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
            Button(Phrase.skip) { finish() }
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
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
            let cardWidth = min(geo.size.width - 32, 560)
            let side = max(200, min(cardWidth - 64, geo.size.height * 0.52))
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
                        lensed: !reduceMotion
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
                .font(.system(size: 11, weight: .medium, design: .rounded))
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
            showsErase: false,
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
    static let welcomeTitle = "Welcome to Nine"
    static let welcomeTagline = "Couch sudoku — everywhere you sit."

    static let ledgerDaily = "A new board every day, and a streak that keeps count"
    static let ledgerProof = "Three difficulties, every board proved solvable by logic"
    static let ledgerStats = "Your times, points and trends — kept honestly"
    static func ledgerThemes(themes: Int, accents: Int) -> String {
        "\(themes) themes and \(accents) accents, all of them yours"
    }
    static let ledgerSync = "Boards, streak and stats follow you between devices"
    static let ledgerCovenant = "No ads, no subscription, nothing else to buy"
    static let onePurchase = "One purchase · iPhone, iPad, Mac & Apple TV"
    static let begin = "Begin"

    static let beatTitle = "Your first digit"
    static let skip = "Skip"
    static func beatPrompt(digit: Int) -> String { "Flick to the \(digit)." }
    static func beatDetail(digit: Int) -> String {
        "The rose is open on the empty cell. Drag from its middle toward the "
        + "\(digit) and let go — or just tap the \(digit). That is the whole game."
    }
    static let beatHint = "One cell, one digit. You can skip this at any time."
    static let beatDoneTitle = "That's it."
    static let beatDoneDetail =
        "Every board works exactly like that. Today's is waiting on the shelf."
    static let beatNice = "Nice"
    static let composing = "Composing…"
}
#endif
