// HomeView.swift — the shelf (PRD §4.1). Full-bleed void, floating glass
// cards: Continue (the hero, only when a free-play board is in progress) and
// three Free Play difficulty slabs rendered as increasingly dense
// mini-boards. Nothing else. The Today card and the streak chip left with the
// daily system (product decision, 2026-08-02).
import SwiftUI
import CouchKit

#if os(tvOS)
struct HomeView: View {
    let model: AppModel

    @State private var showHistory = false
    @State private var showBoards = false
    /// PRD-26's ambient surface, reached two ways: a card, and the shelf
    /// sitting untouched. Both routes set this one flag.
    @State private var showAmbient = false
    /// The last time the remote said anything. Reset by every move command and
    /// every card tap, so "idle" means the room is idle rather than that the
    /// player is reading slowly.
    @State private var lastActivity = Date.now
    @Environment(\.colorScheme) private var colorScheme

    /// The accent resolved for the theme's leaning (themes pin the scheme).
    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    var body: some View {
        ZStack {
            shelf
            // History is the suite's one secondary surface on the shelf, opened
            // from a card and reachable by remote and pad alike (PRD-5 §2.3).
            GlassSheet(isPresented: $showHistory) {
                HistorySheetContent(model: model, onClose: { showHistory = false })
            }
            // The board tracker — the second door on the shelf (still one sheet
            // open at a time; a card opens exactly one).
            GlassSheet(isPresented: $showBoards) {
                BoardsSheetContent(model: model, onClose: { showBoards = false })
            }
            // First-run manual. The shelf cards use native focus (no
            // couchRemote surface), so the overlay simply sits on top and
            // owns the remote while shown; on dismiss the cards regain
            // focus naturally.
            // Above the sheets and below the first-run manual: an ambient
            // surface must never cover a thing the player asked for, and must
            // never cover the one screen that explains the remote.
            if showAmbient {
                AmbientReplaysView(model: model) {
                    showAmbient = false
                    lastActivity = .now
                }
                .transition(.opacity)
            }
            if !model.helpSeen {
                HelpOverlay(
                    // The wordmark, not a word: `ShareCardMetrics.wordmark` is
                    // the same decision on the share card.
                    title: Phrase.wordmark,
                    tagline: Strings.string("help.tv.tagline"),
                    rows: NineLegend.full
                        + (model.padConnected ? [NineLegend.padConnectedRow] : [])
                ) {
                    model.helpSeen = true
                }
            }
        }
        // Every remote gesture on the shelf is activity. `onMoveCommand` fires
        // on focus movement, which is the only thing a player does here that
        // is not a tap — and the taps reset it themselves, because they all
        // open something.
        .onMoveCommand { _ in lastActivity = .now }
        // One wake-up a second rather than a `TimelineView`, which would
        // re-evaluate the whole shelf at display rate to read a clock. The
        // shelf is the idle-pixel test's own screen.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            // Only from a shelf with nothing on top of it: an ambient takeover
            // over an open sheet or the first-run manual would be the app
            // interrupting the player rather than filling a silence.
            guard hasReplays, !showAmbient, !showHistory, !showBoards, model.helpSeen else {
                lastActivity = now
                return
            }
            if now.timeIntervalSince(lastActivity) >= AmbientIdle.seconds {
                withAnimation(.couchFast) { showAmbient = true }
            }
        }
    }

    /// Whether there is anything to be ambient *about*. A television that
    /// blanks to an empty board after ninety seconds is worse than one that
    /// does nothing, so a player with no solves never meets this at all —
    /// which is also every player's first evening.
    private var hasReplays: Bool {
        model.library.played.contains { model.replays.replay(for: $0.id) != nil }
    }

    private var shelf: some View {
        // Scrolls so the added History row never crowds the void off the
        // bottom on a 1080p panel; the focus engine still centers cards.
        ScrollView(showsIndicators: false) {
            VStack(spacing: 64) {
                header
                if model.savedFree != nil {
                    continueCard
                }
                freePlayRow
                extrasRow
            }
            .padding(80)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 28) {
            Text(verbatim: Phrase.wordmark)
                .couchText(CouchTypography.title)
            Spacer()
        }
    }

    // MARK: - Continue (free play in progress)

    /// The hero when present: with the Today card gone this is the shelf's one
    /// board-in-hand card, so it takes the primary width and default focus.
    @ViewBuilder
    private var continueCard: some View {
        if let (game, difficulty) = model.savedFree {
            ShelfCard(width: 620, height: 300, isPrimary: true,
                      action: { model.continueSaved() }) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(Strings.string("shelf.continue.title"))
                        .couchText(CouchTypography.title)
                    Text(Strings.difficulty(difficulty))
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 20) {
                        GlassRing(progress: game.fillFraction)
                            .frame(width: 64, height: 64)
                        // `.formatted(.percent)`, not `"\(n)%"`: Turkish leads
                        // with the sign, French spaces it, and Arabic wants its
                        // own numerals (PRD-20 Task 8).
                        Text(Int(game.fillFraction * 100).formatted(.percent))
                            .font(CouchTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    // MARK: - Free play

    /// One row of three. Three cards at 360 + two 44pt gaps is 1168pt inside a
    /// 1920pt shelf's 1800pt safe area, so the row fits and stays centred.
    /// The deep-end row (Nocturne/Tempest/Abyss) was removed on 2026-08-02:
    /// the shelf offers exactly three difficulties. The engine keeps all six
    /// bands — boards already saved at the deep bands still decode and open.
    private var freePlayRow: some View {
        HStack(spacing: 44) {
            ForEach(Difficulty.rowBands, id: \.self) { difficulty in
                difficultyCard(difficulty)
            }
        }
    }

    // MARK: - Extras (History)

    private var extrasRow: some View {
        HStack(spacing: 44) {
            // Pad Play is retired: a gamepad drives shelf focus natively and the
            // controller grammar is adopted in-game on the first real gesture.
            ShelfCard(width: 440, height: 150, action: { showBoards = true }) {
                extraTile(symbol: "square.stack.3d.up",
                          title: Strings.string("boards.title"),
                          subtitle: boardsSubtitle)
            }
            ShelfCard(width: 440, height: 150, action: {
                // Authenticate here, not at launch: opening History is the
                // player choosing to engage Game Center, so the system sheet
                // is expected — at launch it was an unprompted takeover.
                GameCenter.shared.authenticate()
                showHistory = true
            }) {
                extraTile(symbol: "trophy",
                          title: Strings.string("history.title"),
                          subtitle: Strings.string("shelf.history.subtitle"))
            }
            // PRD-26. Shown only when there is something to replay — a card
            // that opens an empty screen is worse than no card, and the shelf
            // already refuses to render a 0% ring for the same reason.
            if hasReplays {
                ShelfCard(width: 440, height: 150, action: {
                    lastActivity = .now
                    withAnimation(.couchFast) { showAmbient = true }
                }) {
                    extraTile(symbol: "sparkles",
                              title: DebriefPhrase.replay,
                              subtitle: Strings.string("shelf.replays.subtitle"))
                }
            }
        }
    }

    private func extraTile(symbol: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(CouchTypography.body)
                Text(subtitle)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var boardsSubtitle: String {
        let n = model.partials.count
        return n == 0
            ? Strings.string("shelf.boards.subtitleEmpty")
            : Strings.string("shelf.boards.subtitleCount", .int(n))
    }

    private func difficultyCard(_ difficulty: Difficulty) -> some View {
        // Three cards at 360 + two 44pt gaps is 1168pt inside a 1920pt shelf's
        // 1800pt safe area, so each row fits and stays centred. Focus travel is
        // unchanged — it follows the stacks.
        ShelfCard(width: 360, height: 300, action: { model.startFree(difficulty) }) {
            VStack(spacing: 20) {
                // Concentric with the slab it is dropped into: `ShelfCard` is a
                // 40pt corner with 36pt of padding, which is `Radius.inner` of
                // those two and not `MiniBoard`'s 24/18 default.
                MiniBoard(difficulty: difficulty, accent: accent,
                          corner: Radius.inner(40, inset: 36))
                    .frame(width: 132, height: 132)
                if model.composing == .free(difficulty) {
                    statusLabel(Strings.string("status.composing"), symbol: "sparkles")
                } else {
                    Text(Strings.difficulty(difficulty))
                        .font(CouchTypography.body)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func statusLabel(_ text: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
            Text(text)
                .font(CouchTypography.caption)
        }
        .foregroundStyle(.secondary)
    }

}

/// The one string on this screen that is never translated.
private enum Phrase {
    /// Nine's name, not a numeral and not the English word — the same rule the
    /// share card's `ShareCardMetrics.wordmark` states, so the two cannot drift.
    static let wordmark = "Nine"
}

#endif

/// What each difficulty demands, in player language — shown on the home
/// cards and in the tutorial's difficulty guide (both platforms share it).
///
/// Only the three offered bands carry copy now (2026-08-02: the UI offers
/// exactly Gentle/Steady/Sharp). The deep-end cases stay in the engine — raw
/// values are frozen persistence identity — and a stats row may still *name*
/// them through `Strings.difficulty`, but no choice surface describes them.
extension Difficulty {
    var blurb: String {
        switch self {
        case .gentle: return Strings.string("difficulty.gentle.blurb")
        case .steady: return Strings.string("difficulty.steady.blurb")
        case .sharp: return Strings.string("difficulty.sharp.blurb")
        // Unreachable from any choice surface — `rowBands` is the only list
        // the UI iterates — but the switch stays total so a stray call cannot
        // trap. The sharp copy is the honest nearest description.
        case .nocturne, .tempest, .abyss:
            return Strings.string("difficulty.sharp.blurb")
        }
    }

    /// The longer explainer for the difficulty guide.
    var explainer: String {
        switch self {
        case .gentle: return Strings.string("difficulty.gentle.explainer")
        case .steady: return Strings.string("difficulty.steady.explainer")
        case .sharp: return Strings.string("difficulty.sharp.explainer")
        case .nocturne, .tempest, .abyss:
            return Strings.string("difficulty.sharp.explainer")
        }
    }

    /// The three bands every choice surface offers. An explicit list rather
    /// than `allCases`: the engine keeps six cases for persistence identity,
    /// and which of them are *offered* is a product decision this constant
    /// states once.
    static var rowBands: [Difficulty] { [.gentle, .steady, .sharp] }
}

/// The remote grammar, spelled out once. The full set feeds the first-run
/// HelpOverlay; the compact set tops the prefs sheet, so the sheet doubles
/// as the manual ever after.
enum NineLegend {
    static var full: [LegendRow] { [
        row("arrow.up.and.down.and.arrow.left.and.right", "legend.remote.swipe"),
        row("hand.tap", "legend.remote.click"),
        row("circle.grid.3x3", "legend.remote.rose"),
        row("arrow.up.right", "legend.remote.flick"),
        row("playpause", "legend.remote.playPause"),
        row("playpause.fill", "legend.remote.holdPlayPause"),
        row("arrow.backward", "legend.remote.back"),
    ] }

    /// One legend row from one catalog scope. Every row is the same shape — a
    /// glyph, a gesture, what it does — so the two keys are derived from one
    /// scope rather than written out twice per row, which is 58 chances to
    /// paste the wrong half.
    ///
    /// `.gesture` and `.action` are appended here rather than passed in, so a
    /// scope with only one of the two is a missing-key fallback the audit sees
    /// rather than a row that silently reads its own identifier.
    private static func row(_ symbol: String, _ scope: String) -> LegendRow {
        LegendRow(symbol: symbol,
                  gesture: Strings.string(scope + ".gesture"),
                  action: Strings.string(scope + ".action"))
    }

    /// The four rows a player actually reaches for, for the prefs sheet.
    static var compact: [LegendRow] { let all = full; return [all[0], all[1], all[4], all[5]] }

    /// The touch grammar (iOS/iPadOS): same concepts, finger-native verbs.
    static var touch: [LegendRow] { [
        row("hand.tap", "legend.touch.tapCell"),
        row("circle.grid.3x3", "legend.touch.tapPetal"),
        row("arrow.up.right", "legend.touch.flick"),
        row("9.square", "legend.touch.highlight"),
        row("pencil", "legend.touch.pencil"),
        row("arrow.uturn.backward", "legend.touch.undo"),
    ] }

    /// The rows the touch prefs sheet keeps as its manual.
    static var touchCompact: [LegendRow] { let all = touch; return [all[0], all[1], all[3], all[4]] }

    /// The keyboard grammar (macOS, PRD-4 §2.2): the keyboard is the
    /// superpower — arrows walk, digits type straight in.
    static var keyboard: [LegendRow] { [
        row("arrow.up.arrow.down", "legend.keyboard.arrows"),
        row("1.square", "legend.keyboard.digits"),
        row("shift", "legend.keyboard.pencil"),
        row("9.square", "legend.keyboard.highlight"),
        row("arrow.right.to.line", "legend.keyboard.tab"),
        row("arrow.uturn.backward", "legend.keyboard.undo"),
    ] }

    /// The rows the macOS Settings scene keeps as its manual.
    static var keyboardCompact: [LegendRow] { let all = keyboard; return [all[0], all[1], all[3], all[5]] }

    /// The controller grammar (tvOS pad session, PRD-5): the right stick *is*
    /// the rose (one deflection per digit), Circle taps undo and holds erase.
    /// Symbols are gamecontroller glyphs available at the tvOS deployment floor.
    static var pad: [LegendRow] { [
        row("l.joystick", "legend.pad.move"),
        row("r.joystick", "legend.pad.place"),
        row("xmark", "legend.pad.cross"),
        row("arrow.uturn.backward", "legend.pad.circle"),
        row("square", "legend.pad.square"),
        row("triangle", "legend.pad.triangle"),
        row("eye", "legend.pad.peek"),
        row("gamecontroller", "legend.pad.create"),
        row("arrow.backward", "legend.pad.menu"),
    ] }

    /// The extra first-run row on Apple TV, shown only with a controller
    /// attached. Built by the same helper so it cannot drift from the nine
    /// above it.
    static var padConnectedRow: LegendRow { row("gamecontroller", "legend.pad.controller") }

    /// The rows the pad prefs sheet keeps as its manual.
    static var padCompact: [LegendRow] { let all = pad; return [all[0], all[1], all[3], all[7]] }
}

#if os(tvOS)
/// A floating glass slab with the suite focus treatment. Focusable through
/// `focusHalo`; a clickpad press fires `action`.
private struct ShelfCard<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    var isPrimary = false
    let action: @MainActor () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(36)
            .frame(width: width, height: height)
            .couchGlassInteractive(in: RoundedRectangle(cornerRadius: 40, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            .focusHalo(
                in: RoundedRectangle(cornerRadius: 40, style: .continuous),
                claimsDefaultFocus: isPrimary
            )
            .onTapGesture { action() }
    }
}

#endif

/// A difficulty preview: a 9×9 board whose *picture* is the band's ruleset.
/// Deterministic (CouchHash), so the shelf never flickers. Shared by the TV
/// shelf, the touch home, the Mac shelf and the tutorial's difficulty guide.
///
/// **Three things this used to get wrong, all of them measured.**
///
/// 1. There was no box gutter: dots sat at `x * cell + cell * 0.3` on a
///    perfectly uniform lattice, so at 64 pt the tile was a QR-code fragment
///    rather than a sudoku. Two seams per axis is the whole difference, and it
///    costs one multiply per dot (`BoardArt.cellRect`).
/// 2. Nocturne, Tempest and Abyss were **one picture repeated three times** —
///    density 0.84 for all three, only the noise seed differing. Measured off
///    the shipped dark frame they came out at 12.5% / 12.3% / 11.3% ink and
///    6.5–10/255 mean absolute difference from one another: three cards a buyer
///    knows least about, stacked in a column, showing the same swatch. Density
///    genuinely stops carrying information above Sharp, so above Sharp the
///    *ruleset* is what is drawn — a void field, an X-wing, a two-colour
///    split — and each one matches the sentence printed beside it.
/// 3. Every band drew in `accent.opacity(0.85)`, so difficulty — the one axis a
///    sudoku shelf exists to communicate — carried no colour at all.
///
/// **Round 4 rewrote all three answers, because a blind panel read the shipped
/// tiles and got the opposite of what they meant.** Three findings, and each
/// one is a different half of the same picture:
///
/// * *"Gentle / Steady / Sharp are three identical grey tiles. The only
///   saturated pixels in the frame are the page dot and the pencil marks."*
///   The ramp was one hue with only saturation moving (peaks measured at
///   133,171,205 / 105,162,212 / 75,151,216), which at tile size is one colour.
///   The tint is now `Difficulty.bandTone` — six *different* accents off the
///   palette `AppearancePaletteTests` already pins at ≥4.5:1 on every dark
///   ground and ΔE ≥ 5.9 apart under all three dichromacies. Six ranks, six
///   hues, and none of them invented.
/// * *"The count runs backwards: Sharp is the densest board, which reads as the
///   most givens, i.e. the easiest."* Dead right, and it had been true since
///   the first version: 0.30 → 0.48 → 0.68 going **up** the ladder. A sudoku
///   with more clues is an easier sudoku, and this is the one picture in the
///   app whose whole job is to say which is which. The ramp is inverted, and
///   the numbers are now roughly the clue counts the generator actually digs
///   to (45 / 36 / 27 at the row, 24 at Nocturne's floor).
/// * *"The dots wander off the implied 9×9 cell centres — they clump in pairs,
///   leave irregular holes, and in Sharp they cross the 3×3 box rules."* Half
///   wrong and half right, and the right half is the interesting one. The dots
///   were already on exact cell centres (`BoardArt.cellRect`); what wandered
///   was the *selection*. Thresholding independent noise per cell is a Poisson
///   scatter, so at any density some boxes get eight dots and some get one, and
///   the eye reads that as a broken lattice rather than as a board. `lattice`
///   now stratifies **by box**: every box receives the same count, chosen by
///   noise rank within it. Same determinism, same seeds, and the picture reads
///   as nine boxes of a sudoku instead of as dither.
///
/// The last change is material rather than pattern: the art sits in a **well**
/// now — nine `Elevation.fill(.track,…)` plates with a recessed rim over them —
/// so the thumbnail is a surface cut into the card rather than dots floating on
/// it. That is the answer to "nothing refracts" at the one size where a full
/// pane of glass would be a smudge.
struct MiniBoard: View {
    let difficulty: Difficulty
    /// The player's own accent. Since round 4 the band's identity comes from
    /// `Difficulty.bandTone`, so this is no longer the tile's colour — it is
    /// the *second* colour in the one picture that needs two (Abyss's
    /// "one digit, two colours"), which is the only place a player's own choice
    /// still belongs on a tile whose subject is the band and not the player.
    let accent: Color
    /// The art's own corner, concentric with the card it is dropped into.
    /// `TouchCard` is a 24 pt radius with 18 pt of padding, so the default is
    /// `Radius.inner` of those two — 6. A caller in a differently-curved card
    /// passes its own; nobody has to, which is why it is defaulted.
    var corner: CGFloat = Radius.inner(24, inset: 18)

    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var tones: ThemeTones { theme.tones(for: colorScheme) }

    /// What the preview draws, with the one number that shapes it. One switch
    /// rather than a `pattern` and a `density` keyed on the same enum, because
    /// only one combination of the two is ever legal and two switches is two
    /// things to keep in step.
    private enum Pattern {
        /// A field whose density *is* the difficulty. The three-across row.
        case field(Double)
        /// A sparse field with whole boxes left empty — "fewer clues".
        case voids(Double)
        /// Both diagonals lit over a dim field: the X-wing the band is named
        /// for. The argument is the density of the field behind it.
        case wing(Double)
        /// One field split by box parity into two colours — "colouring".
        case split(Double)
    }

    /// **The ramp descends now.** A density is a clue count, a clue count is
    /// how much of the board you are given, and being given more of it is
    /// easier — so the hardest band cannot be the busiest picture. Read as
    /// dots-per-box (the stratifier rounds `9 × density`): 5, 4, 3 across the
    /// row, then 4 in six boxes at Nocturne, and figures rather than fields
    /// above that.
    ///
    /// The absolute values track the generator: Gentle digs to the high
    /// thirties/low forties, Sharp to the mid twenties, Nocturne to 26 or
    /// fewer. A player who counts the dots gets the truth.
    private var pattern: Pattern {
        switch difficulty {
        case .gentle: return .field(0.55)   // 5 per box — 45 clues
        case .steady: return .field(0.42)   // 4 per box — 36
        case .sharp: return .field(0.30)    // 3 per box — 27
        // "Fewer clues, deeper logic." Sparse *and* three of the nine boxes
        // empty — 24 clues, below Sharp on both counts — a picture of a board
        // dug past where a scan will reach.
        case .nocturne: return .voids(0.42)
        // "Wings & swordfish." The figure is the technique, and the field
        // behind it drops to two a box so the X is unmistakably the subject.
        case .tempest: return .wing(0.20)
        // "One digit, two colours." Literally that, at Sharp's own density
        // because above Sharp density has stopped saying anything.
        case .abyss: return .split(0.30)
        }
    }

    /// The boxes Nocturne leaves empty: top-right, centre, bottom-left. An
    /// anti-diagonal of three voids, which is a composition rather than a
    /// scatter, and reads at 64 pt.
    private static let voidBoxes: Set<Int> = [2, 4, 6]

    /// The two diagonals — Tempest's figure. Hoisted out of the draw loop so
    /// the field can be selected *around* it: a wing dot and a field dot in the
    /// same cell used to double-draw, which is why the shipped X had a handful
    /// of cells reading a third brighter than the rest of it.
    private static let wingCells: Set<Int> = {
        var cells: Set<Int> = []
        for step in 0..<9 {
            cells.insert(step * 9 + step)
            cells.insert(step * 9 + (8 - step))
        }
        return cells
    }()

    /// The noise seed. Constant at 0x91 for the four bands that shipped before
    /// PRD-25, so their previews are the pixels they have always been; the two
    /// new ones stay offset. Unchanged — the shelf must not flicker, and a
    /// reseed would repaint four cards for nothing.
    private var seed: UInt64 {
        switch difficulty {
        case .gentle, .steady, .sharp, .nocturne: return 0x91
        case .tempest: return 0x92
        case .abyss: return 0x93
        }
    }

    /// The band's own hue (`Difficulty.bandTone`, Theme.swift), deepened on
    /// paper the way every accent in the app is.
    private var tint: Color { difficulty.bandTone(isLight: tones.isLight) }

    /// **The clue field, stratified by box.**
    ///
    /// The one non-obvious line in this view. Selecting each cell independently
    /// (`noise < density`) is binomial per box, so with 81 draws at p = 0.3 a
    /// box lands anywhere from 0 to 7 dots — and nine boxes of visibly
    /// different weight is exactly the "clumps in pairs, leaves irregular
    /// holes" the panel measured. Taking the `round(9 · density)` lowest-ranked
    /// cells *within each box* keeps the arrangement random and the weight
    /// constant, which is what a real sudoku's clue distribution looks like and
    /// what makes the 3×3 structure read at 64 pt.
    ///
    /// Deterministic in the same way the old form was — same hash, same seed,
    /// same input — so the shelf still never flickers.
    private static func lattice(
        density: Double, seed: UInt64,
        skipBoxes: Set<Int> = [], skipCells: Set<Int> = []
    ) -> Set<Int> {
        var chosen: Set<Int> = []
        for box in 0..<9 where !skipBoxes.contains(box) {
            let baseRow = (box / 3) * 3
            let baseColumn = (box % 3) * 3
            var ranked: [(index: Int, rank: Double)] = []
            for row in baseRow..<(baseRow + 3) {
                for column in baseColumn..<(baseColumn + 3) {
                    let index = row * 9 + column
                    guard !skipCells.contains(index) else { continue }
                    ranked.append((index, CouchHash.noise(column, row, seed: seed)))
                }
            }
            let wanted = Int((9 * density).rounded())
            guard wanted > 0 else { continue }
            for cell in ranked.sorted(by: { $0.rank < $1.rank }).prefix(wanted) {
                chosen.insert(cell.index)
            }
        }
        return chosen
    }

    /// The cells this band's field lights, resolved once per render.
    private var field: Set<Int> {
        switch pattern {
        case .field(let density):
            return Self.lattice(density: density, seed: seed)
        case .voids(let density):
            return Self.lattice(density: density, seed: seed, skipBoxes: Self.voidBoxes)
        case .wing(let density):
            return Self.lattice(density: density, seed: seed, skipCells: Self.wingCells)
        case .split(let density):
            return Self.lattice(density: density, seed: seed)
        }
    }

    var body: some View {
        let tones = self.tones
        let tint = self.tint
        let accent = self.accent
        let field = self.field
        let pattern = self.pattern
        // **The well the board is cut into — and `Elevation.fill(.track,…)` is
        // deliberately not what cuts it.** The ladder's fills composite over
        // *the ground*, where a dark `track` is a white wash that lands below a
        // `card`'s. This plate composites over a card, and a white wash on a
        // card is a lift rather than a recess: `Elevation`'s own second rule,
        // running the other way round ("the direction of 'up' changes"). So the
        // substance here is `ThemeTones.wellHue`, which is the tone the ladder
        // cuts *every* groove with — black on a dark theme, the theme's own deep
        // tone on paper, so Camel's board sits in a warm well rather than a grey
        // one. The light value is `Elevation`'s own `track` alpha exactly.
        let plate = tones.wellHue.opacity(tones.isLight ? 0.05 : 0.30)
        // **Neutral, and dimmer than the dots.** The rules used to be drawn in
        // the tint at 0.25, so the one mark that is supposed to be structure was
        // the same colour as the marks that are supposed to be data — "the box
        // lines are drawn at a bluish low contrast that competes with the dots".
        // Structure is the theme's grid tone, at half the dots' weight.
        let rule = tones.gridTone.opacity(tones.isLight ? 0.30 : 0.20)
        Canvas { context, size in
            let gutter = size.width * BoardArt.thumbGutter
            let cell = BoardArt.cell(side: size.width, gutter: gutter)

            /// The dot for one cell, `scale` of the cell across, centred in it.
            /// A function returning a rect rather than one that draws, so
            /// nothing captures the Canvas's `inout` context.
            func dot(_ index: Int, _ scale: CGFloat) -> CGRect {
                let frame = BoardArt.cellRect(
                    column: index % 9, row: index / 9, cell: cell, gutter: gutter)
                let d = cell * scale
                return CGRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d)
            }

            // Nine plates rather than one, so the gutter is a *gap in the
            // surface* and not just a gap in the dots. This is the whole of the
            // "give it a material" answer at thumbnail size: a pane of glass at
            // 64 pt is a grey smudge, a recess is legible.
            for box in 0..<9 {
                let first = BoardArt.cellRect(
                    column: (box % 3) * 3, row: (box / 3) * 3, cell: cell, gutter: gutter)
                let last = BoardArt.cellRect(
                    column: (box % 3) * 3 + 2, row: (box / 3) * 3 + 2, cell: cell, gutter: gutter)
                context.fill(
                    Path(roundedRect: first.union(last),
                         cornerRadius: cell * BoardArt.cellCorner * 1.5),
                    with: .color(plate))
            }

            // The two box rules, under the dots. The gutter alone carries the
            // structure at 34 pt (`BoardFingerprint`); at 64 pt and up there is
            // room for a hairline in the seam, and it is what turns "the dots
            // are unevenly spaced" into "that is a sudoku".
            BoardArt.strokeBoxRules(
                in: context, side: size.width, cell: cell, gutter: gutter,
                color: rule, lineWidth: 1
            )

            for index in field.sorted() {
                switch pattern {
                case .field, .voids:
                    context.fill(Path(ellipseIn: dot(index, 0.4)),
                                 with: .color(tint.opacity(0.92)))
                case .wing:
                    // Ground, not competition: the X is the subject and the
                    // field behind it is the board it is drawn on.
                    context.fill(Path(ellipseIn: dot(index, 0.34)),
                                 with: .color(tint.opacity(0.30)))
                case .split:
                    // Split by box parity, so the two colours land on the same
                    // 3×3 structure the seams already draw — five boxes one
                    // colour, four the other. The second colour is the player's
                    // accent, which makes this the one tile their choice still
                    // appears on and the only one where a second hue *means*
                    // something.
                    let parity = (index / 9 / 3) + (index % 9 / 3)
                    context.fill(Path(ellipseIn: dot(index, 0.4)),
                                 with: .color((parity % 2 == 1 ? tint : accent).opacity(0.92)))
                }
            }

            // The figure last and over everything, a quarter larger than a field
            // dot, so the X reads as one continuous mark.
            if case .wing = pattern {
                for index in Self.wingCells.sorted() {
                    context.fill(Path(ellipseIn: dot(index, 0.5)),
                                 with: .color(tint.opacity(0.95)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        // A recess is lit the opposite way round from a raised card: the light
        // catches the *bottom* of a groove and the top edge is the lip casting
        // into it. Inverting `CouchSpecular`'s ramp by hand rather than calling
        // `couchRim` is the entire difference between "cut in" and "sitting on".
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
        .allowsHitTesting(false)
    }
}
