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
                    title: "Nine",
                    tagline: "Couch sudoku.",
                    rows: NineLegend.full + (model.padConnected ? [
                        LegendRow(
                            symbol: "gamecontroller",
                            gesture: "Controller",
                            action: "Just start playing — the guide appears in-game"
                        )
                    ] : [])
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
            Text("Nine")
                .couchText(CouchTypography.title)
            Spacer()
            if model.displayedStreak > 0 {
                GlassChip("\(model.displayedStreak) day streak", systemImage: "flame")
            }
        }
    }

    // MARK: - Today

    private var todayCard: some View {
        ShelfCard(width: 620, height: 360, isPrimary: true, action: { model.openToday() }) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Today")
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
            statusLabel("Composing…", symbol: "sparkles")
        } else if model.todaySolved {
            statusLabel("Solved", symbol: "checkmark.circle.fill")
        } else if let daily = model.savedDaily {
            HStack(spacing: 20) {
                GlassRing(progress: daily.fillFraction)
                    .frame(width: 64, height: 64)
                Text("Continue")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            statusLabel("One a day", symbol: "sun.max")
        }
    }

    // MARK: - Continue (free play in progress)

    @ViewBuilder
    private var continueCard: some View {
        if let (game, difficulty) = model.savedFree {
            ShelfCard(width: 460, height: 360, action: { model.continueSaved() }) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Continue")
                        .couchText(CouchTypography.title)
                    Text(difficulty.title)
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
                extraTile(symbol: "square.stack.3d.up", title: "Boards",
                          subtitle: boardsSubtitle)
            }
            ShelfCard(width: 440, height: 150, action: {
                // Authenticate here, not at launch: opening History is the
                // player choosing to engage Game Center, so the system sheet
                // is expected — at launch it was an unprompted takeover.
                GameCenter.shared.authenticate()
                showHistory = true
            }) {
                extraTile(symbol: "trophy", title: "History", subtitle: "Points & best times")
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
        return n == 0 ? "Resume, archive, replay" : "\(n) in progress"
    }

    private func difficultyCard(_ difficulty: Difficulty) -> some View {
        ShelfCard(width: 360, height: 300, action: { model.startFree(difficulty) }) {
            VStack(spacing: 20) {
                MiniBoard(difficulty: difficulty, accent: accent)
                    .frame(width: 132, height: 132)
                if model.composing == .free(difficulty) {
                    statusLabel("Composing…", symbol: "sparkles")
                } else {
                    Text(difficulty.title)
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

    private var isComposingDaily: Bool {
        if case .daily? = model.composing { return true }
        return false
    }
}

#endif

/// What each difficulty demands, in player language — shown on the home
/// cards and in the tutorial's difficulty guide (both platforms share it).
extension Difficulty {
    var blurb: String {
        switch self {
        case .gentle: return "Singles & scans"
        case .steady: return "Pairs & box lines"
        case .sharp: return "X-wings & deep logic"
        }
    }

    /// The longer explainer for the difficulty guide.
    var explainer: String {
        switch self {
        case .gentle: return "Every step is a single: one place a digit can go. A calm first board."
        case .steady: return "Needs naked pairs and box-line eliminations. Pencil marks start to pay."
        case .sharp: return "Demands X-wings and layered deductions. Bring notes and patience."
        }
    }
}

/// The remote grammar, spelled out once. The full set feeds the first-run
/// HelpOverlay; the compact set tops the prefs sheet, so the sheet doubles
/// as the manual ever after.
enum NineLegend {
    static let full: [LegendRow] = [
        LegendRow(
            symbol: "arrow.up.and.down.and.arrow.left.and.right",
            gesture: "Swipe", action: "Move around the board"
        ),
        LegendRow(symbol: "hand.tap", gesture: "Click", action: "Open the digit rose"),
        LegendRow(
            symbol: "circle.grid.3x3",
            gesture: "Swipe + Click (in rose)", action: "Preview, then place"
        ),
        LegendRow(symbol: "arrow.up.right", gesture: "Flick (8-way remote)", action: "Place instantly"),
        LegendRow(symbol: "playpause", gesture: "▶︎", action: "Undo"),
        LegendRow(symbol: "playpause.fill", gesture: "Hold ▶︎", action: "Settings"),
        LegendRow(symbol: "arrow.backward", gesture: "Back", action: "Save + home"),
    ]

    /// The four rows a player actually reaches for, for the prefs sheet.
    static let compact: [LegendRow] = [full[0], full[1], full[4], full[5]]

    /// The touch grammar (iOS/iPadOS): same concepts, finger-native verbs.
    static let touch: [LegendRow] = [
        LegendRow(symbol: "hand.tap", gesture: "Tap a cell", action: "Open the digit rose"),
        LegendRow(symbol: "circle.grid.3x3", gesture: "Tap a petal", action: "Place that digit"),
        LegendRow(symbol: "arrow.up.right", gesture: "Flick in the rose", action: "Place instantly"),
        LegendRow(symbol: "9.square", gesture: "Tap a placed digit", action: "Light up all of its kind"),
        LegendRow(symbol: "pencil", gesture: "Pencil toggle", action: "Corner notes instead"),
        LegendRow(symbol: "arrow.uturn.backward", gesture: "Undo button", action: "Take back a move"),
    ]

    /// The rows the touch prefs sheet keeps as its manual.
    static let touchCompact: [LegendRow] = [touch[0], touch[1], touch[3], touch[4]]

    /// The keyboard grammar (macOS, PRD-4 §2.2): the keyboard is the
    /// superpower — arrows walk, digits type straight in.
    static let keyboard: [LegendRow] = [
        LegendRow(symbol: "arrow.up.arrow.down", gesture: "Arrow keys", action: "Move the cursor (wraps at edges)"),
        LegendRow(symbol: "1.square", gesture: "1–9", action: "Place the digit"),
        LegendRow(symbol: "shift", gesture: "⇧1–9 · P", action: "Pencil a note · sticky pencil"),
        LegendRow(symbol: "9.square", gesture: "Space", action: "Light up the digit under the cursor"),
        LegendRow(symbol: "arrow.right.to.line", gesture: "Tab / ⇧Tab", action: "Next / previous empty cell"),
        LegendRow(symbol: "arrow.uturn.backward", gesture: "⌘Z", action: "Undo"),
    ]

    /// The rows the macOS Settings scene keeps as its manual.
    static let keyboardCompact: [LegendRow] = [keyboard[0], keyboard[1], keyboard[3], keyboard[5]]

    /// The controller grammar (tvOS pad session, PRD-5): the right stick *is*
    /// the rose (one deflection per digit), Circle taps undo and holds erase.
    /// Symbols are gamecontroller glyphs available at the tvOS deployment floor.
    static let pad: [LegendRow] = [
        LegendRow(symbol: "l.joystick", gesture: "Left stick / d-pad", action: "Move around the board"),
        LegendRow(symbol: "r.joystick", gesture: "Right stick flick", action: "Place a digit (R3 = 5)"),
        LegendRow(symbol: "xmark", gesture: "Cross", action: "Open the rose · confirm a petal"),
        LegendRow(symbol: "arrow.uturn.backward", gesture: "Circle tap · hold", action: "Undo · hold to erase the cell"),
        LegendRow(symbol: "square", gesture: "Square", action: "Sticky pencil"),
        LegendRow(symbol: "triangle", gesture: "Triangle", action: "Light up all of a digit"),
        LegendRow(symbol: "eye", gesture: "Hold L2 · R2", action: "Peek — dim all but one kind"),
        LegendRow(symbol: "gamecontroller", gesture: "Create", action: "Settings"),
        LegendRow(symbol: "arrow.backward", gesture: "Menu", action: "Save + home"),
    ]

    /// The rows the pad prefs sheet keeps as its manual.
    static let padCompact: [LegendRow] = [pad[0], pad[1], pad[3], pad[7]]
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
