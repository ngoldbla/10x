// HomeView.swift — the shelf (PRD §4.1). Full-bleed void, floating glass
// cards: Today, Continue (only when a free-play board is in progress), and
// three Free Play difficulty slabs rendered as increasingly dense
// mini-boards. A GlassChip shows the daily streak. Nothing else.
import SwiftUI
import CouchKit

#if os(tvOS)
struct HomeView: View {
    let model: AppModel

    @State private var showHistory = false
    @State private var showBoards = false
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
    }

    private var shelf: some View {
        // Scrolls so the added History row never crowds the void off the
        // bottom on a 1080p panel; the focus engine still centers cards.
        ScrollView(showsIndicators: false) {
            VStack(spacing: 64) {
                header
                HStack(alignment: .top, spacing: 56) {
                    todayCard
                    if model.savedFree != nil {
                        continueCard
                    }
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
            if model.displayedStreak > 0 {
                StreakChip(days: model.displayedStreak, held: model.streakHeld)
            }
        }
    }

    // MARK: - Today

    private var todayCard: some View {
        ShelfCard(width: 620, height: 360, isPrimary: true, action: { model.openToday() }) {
            VStack(alignment: .leading, spacing: 18) {
                Text(Strings.string("shelf.today.title"))
                    .couchText(CouchTypography.title)
                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                todayStatus
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var todayStatus: some View {
        if isComposingDaily {
            statusLabel(Strings.string("status.composing"), symbol: "sparkles")
        } else if model.todaySolved {
            statusLabel(Strings.string("status.solved"), symbol: "checkmark.circle.fill")
        } else if let daily = model.savedDaily {
            HStack(spacing: 20) {
                GlassRing(progress: daily.fillFraction)
                    .frame(width: 64, height: 64)
                Text(Strings.string("shelf.continue.title"))
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            statusLabel(Strings.string("shelf.today.oneADay"), symbol: "sun.max")
        }
    }

    // MARK: - Continue (free play in progress)

    @ViewBuilder
    private var continueCard: some View {
        if let (game, difficulty) = model.savedFree {
            ShelfCard(width: 460, height: 360, action: { model.continueSaved() }) {
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
                        Text("\(Int(game.fillFraction * 100))%")
                            .font(CouchTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    // MARK: - Free play

    private var freePlayRow: some View {
        HStack(spacing: 44) {
            ForEach(Difficulty.allCases, id: \.self) { difficulty in
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
        // Four cards at 360 + three 44pt gaps is 1572pt inside a 1920pt shelf's
        // 1800pt safe area, so the row still fits and stays centred. Focus
        // travel is unchanged — it follows the HStack.
        ShelfCard(width: 360, height: 300, action: { model.startFree(difficulty) }) {
            VStack(spacing: 20) {
                MiniBoard(difficulty: difficulty, accent: accent)
                    .frame(width: 132, height: 132)
                if model.composing == .free(difficulty) {
                    statusLabel(difficulty.composeCaption ?? Strings.string("status.composing"),
                                symbol: "sparkles")
                } else {
                    Label {
                        Text(Strings.difficulty(difficulty))
                    } icon: {
                        if let glyph = difficulty.glyph { Image(systemName: glyph) }
                    }
                    .font(CouchTypography.body)
                    .foregroundStyle(.primary)
                    .labelStyle(.titleAndIcon)
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

    private var isComposingDaily: Bool {
        if case .daily? = model.composing { return true }
        return false
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
extension Difficulty {
    var blurb: String {
        switch self {
        case .gentle: return Strings.string("difficulty.gentle.blurb")
        case .steady: return Strings.string("difficulty.steady.blurb")
        case .sharp: return Strings.string("difficulty.sharp.blurb")
        // PRD-17 §3's blurb was "X-wings, chains — the deep end", and chains are
        // exactly what Nocturne does not have: §1 of the same PRD rules new
        // solver techniques out of scope. A band that advertises a technique the
        // verifier cannot prove is a claim the engine would have to break, so
        // the catalog entry says the two things that *are* true of every
        // Nocturne board: it is dug to 26 clues or fewer, and its proof needs at
        // least three deductions at box-line or above.
        case .nocturne: return Strings.string("difficulty.nocturne.blurb")
        }
    }

    /// The longer explainer for the difficulty guide.
    var explainer: String {
        switch self {
        case .gentle: return Strings.string("difficulty.gentle.explainer")
        case .steady: return Strings.string("difficulty.steady.explainer")
        case .sharp: return Strings.string("difficulty.sharp.explainer")
        // Kept to the length of its three peers on purpose: the tvOS difficulty
        // guide is a fixed-height beat with no ScrollView, and a fourth row
        // carrying a three-line explainer is what would push it off the screen.
        // The length budget is in the translator comment for the same reason.
        case .nocturne: return Strings.string("difficulty.nocturne.explainer")
        }
    }

    /// The bands that share the free-play row on touch. Nocturne sits below
    /// them as its own full-width card (PRD-17 §3) — a peer presented apart,
    /// not a fourth column squeezed into an iPhone's width.
    static var rowBands: [Difficulty] { allCases.filter { $0 != .nocturne } }

    /// The SF Symbol that stands for the band, where one is wanted. Only the
    /// deep end has one: the moon is Nocturne's identity, and handing the other
    /// three a glyph each would turn a calm row into a badge collection.
    var glyph: String? { self == .nocturne ? "moon.stars" : nil }

    /// Composing honesty (PRD-17 §3). A band whose compose is measured in
    /// seconds rather than milliseconds says so *while* the player waits.
    /// Driven off `demands`, not off the case, so the next deep band inherits
    /// the caption by being expensive rather than by being remembered.
    /// A whole-sentence key with the band's name as an argument, not a name
    /// glued to a suffix: "Nocturne takes a moment to compose" has a subject,
    /// and a subject is the part a language may want to move.
    var composeCaption: String? {
        demands == nil ? nil
            : Strings.string("difficulty.composeCaption", .text(Strings.difficulty(self)))
    }
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

/// A difficulty preview: a 9×9 field of dots whose density grows with the
/// difficulty. Deterministic (CouchHash), so the shelf never flickers.
/// Shared by the TV shelf and the touch home.
struct MiniBoard: View {
    let difficulty: Difficulty
    let accent: Color

    private var density: Double {
        switch difficulty {
        case .gentle: return 0.30
        case .steady: return 0.48
        case .sharp: return 0.68
        // Above Sharp, but not saturated: at 1.0 the field stops reading as a
        // board and starts reading as a solid square, which loses the one thing
        // the preview is for. 0.84 is the last step that still shows holes.
        case .nocturne: return 0.84
        }
    }

    var body: some View {
        Canvas { context, size in
            let cell = size.width / 9
            let seed: UInt64 = 0x91
            for y in 0..<9 {
                for x in 0..<9 {
                    guard CouchHash.noise(x, y, seed: seed) < density else { continue }
                    let rect = CGRect(
                        x: CGFloat(x) * cell + cell * 0.3,
                        y: CGFloat(y) * cell + cell * 0.3,
                        width: cell * 0.4,
                        height: cell * 0.4
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(accent.opacity(0.85)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
