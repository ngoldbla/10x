// BoardWidget.swift — the playable widget (PRD-3 §4): the app's most recent
// in-progress classic board, one tap at a time. 81 cell buttons + 9 digit
// buttons, all routed through App Intents; givens semibold, entries in
// glacier, heavier 3×3 strokes, no pencil marks. Pitched as "sneak in a move
// while waiting for coffee" — the app remains the primary way to play.
// Repointed off the daily on 2026-08-02: the board is keyed to a library
// entry, not to the calendar.
import SwiftUI
import WidgetKit

struct NineBoardWidget: Widget {
    var body: some WidgetConfiguration {
        // `AppIntentConfiguration`, not `StaticConfiguration` (PRD-33). The `kind`
        // is unchanged on purpose — an already-placed widget keeps its slot and
        // adopts a default-initialised configuration — and that migration is the
        // risk in this change rather than the feature, so it is driven on a
        // simulator with a widget placed by the previous build.
        AppIntentConfiguration(
            kind: "NineBoardWidget",
            intent: BoardWidgetConfiguration.self,
            provider: BoardProvider()
        ) { entry in
            BoardWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    BoardWidgetBackground(appearance: entry.appearance)
                }
        }
        .configurationDisplayName(Strings.resource("widget.board.name"))
        .description(Strings.resource("widget.board.description"))
        // systemMedium joins systemLarge (PRD-33). Medium is where a couple of
        // moves happen — board beside the pad, so a placement is a tap after a
        // tap instead of a reach across a tall tile.
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct BoardWidgetBackground: View {
    let appearance: SharedAppearance
    /// Read *here* rather than passed in. The first version resolved the look on
    /// `BoardEntry` with `systemIsLight: false` hardcoded, which draws a black
    /// ground for an `auto`-theme phone in light mode — `containerBackground`'s
    /// closure is inside the widget's environment, so it can simply ask.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WidgetLook.resolve(appearance, colorScheme: colorScheme).ground
    }
}

// MARK: - Provider

struct BoardEntry: TimelineEntry {
    let date: Date
    let board: SharedDailyBoard?
    let selectedCell: Int?
    /// The player's theme and accent (PRD-30) — the board widget draws real
    /// digits, so this is the surface where a wrong accent was most visible.
    let appearance: SharedAppearance
    /// Which side the digit pad sits on (PRD-33).
    let railSide: RailSide

    init(
        date: Date,
        board: SharedDailyBoard?,
        selectedCell: Int?,
        appearance: SharedAppearance = SharedAppearance(),
        railSide: RailSide = .trailing
    ) {
        self.date = date
        self.board = board
        self.selectedCell = selectedCell
        self.appearance = appearance
        self.railSide = railSide
    }

    var today: Int { WidgetSnapshotStore.dayOrdinal(for: date) }

    /// A board written by an older build carries no `entryID` and cannot be
    /// joined back to the app's library, so it is not offered for play.
    var currentBoard: SharedDailyBoard? {
        guard let board, board.entryID != nil else { return nil }
        return board
    }

    var isSolved: Bool {
        guard let currentBoard else { return false }
        return currentBoard.game.isSolved || currentBoard.pendingSolve != nil
    }
}

struct BoardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: Date(), board: nil, selectedCell: nil)
    }

    func snapshot(
        for configuration: BoardWidgetConfiguration, in context: Context
    ) async -> BoardEntry {
        entry(at: Date(), configuration: configuration)
    }

    func timeline(
        for configuration: BoardWidgetConfiguration, in context: Context
    ) async -> Timeline<BoardEntry> {
        // One entry, no schedule: the board only changes when someone plays
        // it, and both players (the app's publish and the widget's own
        // intents) reload the timeline explicitly.
        Timeline(
            entries: [entry(at: Date(), configuration: configuration)],
            policy: .never
        )
    }

    private func entry(
        at date: Date, configuration: BoardWidgetConfiguration
    ) -> BoardEntry {
        let today = WidgetSnapshotStore.dayOrdinal(for: date)
        return BoardEntry(
            date: date,
            board: SharedDailyBoardStore.load(),
            selectedCell: SharedDailyBoardStore.selectedCell(today: today),
            appearance: WidgetSnapshotStore.load()?.appearance ?? SharedAppearance(),
            railSide: configuration.railSide
        )
    }
}

// MARK: - Views

struct BoardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: BoardEntry

    private var look: WidgetLook {
        WidgetLook.resolve(entry.appearance, colorScheme: colorScheme)
    }

    var body: some View {
        if let board = entry.currentBoard {
            if family == .systemMedium {
                medium(board)
            } else {
                large(board)
            }
        } else {
            // No board in progress: the widget never generates (Sharp takes
            // seconds; extension budget ~30MB). Deep link; the app starts a
            // board and publishes.
            startCTA
                .widgetURL(URL(string: "nine://board"))
        }
    }

    // MARK: - systemLarge (the shape PRD-3 shipped)

    private func large(_ board: SharedDailyBoard) -> some View {
        VStack(spacing: 10) {
            BoardGridView(
                game: board.game,
                selectedCell: entry.isSolved ? nil : entry.selectedCell,
                playable: !entry.isSolved,
                look: look
            )
            if entry.isSolved {
                solvedFooter(board)
            } else {
                DigitStripView(game: board.game, look: look)
            }
        }
    }

    // MARK: - systemMedium (PRD-33)

    /// Board on one side, a 3×3 pad on the other.
    ///
    /// A medium tile is roughly half as tall as it is wide, so the large family's
    /// board-over-strip stack would leave a board about 60pt across with 7pt
    /// cells — far under the 44pt target floor and unhittable in practice. Side by
    /// side, the board takes the full height and the pad takes the rest, which is
    /// the same reasoning `DraftingTable` applies to an iPad (PRD-31): the
    /// composition follows the shape of what you were handed, not the family name.
    ///
    /// **On the "three moves" framing.** PROGRAM-2.0 §Pillar E writes this as a
    /// systemMedium *"three moves" mode*, and a literal cap of three was
    /// considered and refused. A widget that silently stops accepting taps after
    /// the third is input that breaks with no explanation — it fails the
    /// first-flick test outright, and to anyone who has met one it reads as a
    /// paywall, which the covenant forbids the *shape* of as well as the
    /// substance. What "three moves" actually asserts is a claim about **scale**:
    /// a widget is for a couple of moves at a bus stop, not for a session. The
    /// honest way to say that is a surface small enough to make it obvious, with
    /// the app one tap away — not a counter the player cannot see.
    private func medium(_ board: SharedDailyBoard) -> some View {
        HStack(spacing: 10) {
            if entry.railSide == .leading {
                mediumPad(board)
                mediumBoard(board)
            } else {
                mediumBoard(board)
                mediumPad(board)
            }
        }
    }

    private func mediumBoard(_ board: SharedDailyBoard) -> some View {
        BoardGridView(
            game: board.game,
            selectedCell: entry.isSolved ? nil : entry.selectedCell,
            playable: !entry.isSolved,
            look: look,
            digitSize: 12
        )
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func mediumPad(_ board: SharedDailyBoard) -> some View {
        if entry.isSolved {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(look.accent)
                Text(solvedText(board))
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        } else {
            DigitPadView(game: board.game, look: look)
        }
    }

    private var startCTA: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.largeTitle)
                .foregroundStyle(look.accent)
            Text(Strings.string("widget.board.cta"))
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func solvedFooter(_ board: SharedDailyBoard) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(look.accent)
            Text(solvedText(board))
                .font(.subheadline.weight(.semibold))
                // PRD-36's finding, fixed where it was found: a `.subheadline`
                // growing with Dynamic Type inside a `height: 34` box with no
                // `lineLimit` clips silently. The box stays — it reserves the
                // strip's height so the board does not jump when the state
                // changes — and the text is now allowed to shrink inside it
                // rather than be cut off.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
    }

    private func solvedText(_ board: SharedDailyBoard) -> String {
        if let pending = board.pendingSolve {
            return Strings.string("widget.status.solvedIn",
                                  .text(WidgetFormat.time(pending.seconds)))
        }
        return Strings.string("widget.status.solved")
    }
}

/// The 9×9 grid: 81 intent buttons (within archived-view limits, PRD-3 §4).
struct BoardGridView: View {
    let game: NineGame
    let selectedCell: Int?
    let playable: Bool
    let look: WidgetLook
    /// Point size of a placed digit. The large family's 17 is unchanged; the
    /// medium family's board is about a third narrower, so it asks for less.
    var digitSize: CGFloat = 17

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<9, id: \.self) { row in
                GridRow {
                    ForEach(0..<9, id: \.self) { col in
                        cellView(row * 9 + col)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay { BoardStrokes() }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func cellView(_ cell: Int) -> some View {
        if playable && !game.isGiven(cell) {
            Button(intent: SelectCellIntent(cell: cell)) {
                cellLabel(cell)
            }
            .buttonStyle(.plain)
        } else {
            cellLabel(cell)
        }
    }

    private func cellLabel(_ cell: Int) -> some View {
        let value = game.entry(at: cell)
        let given = game.isGiven(cell)
        return Text(value == 0 ? " " : "\(value)")
            .font(.system(size: digitSize, weight: given ? .semibold : .regular,
                          design: .rounded))
            // Givens in the theme's own ink rather than `.primary`: `.primary`
            // follows the *system* scheme, so a Camel board (a light theme) on a
            // phone in dark mode drew white givens on tan.
            .foregroundStyle(given ? look.digit : look.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .contentShape(Rectangle())
            .overlay {
                if selectedCell == cell {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(look.accent, lineWidth: 2)
                        .padding(1)
                }
            }
    }
}

/// Hairline cell strokes with heavier 3×3 box lines, one Canvas pass.
struct BoardStrokes: View {
    var body: some View {
        Canvas { context, size in
            for line in 0...9 {
                let heavy = line % 3 == 0
                let width: CGFloat = heavy ? 1.5 : 0.5
                let opacity: CGFloat = heavy ? 0.55 : 0.25
                let x = size.width * CGFloat(line) / 9
                let y = size.height * CGFloat(line) / 9
                var vertical = Path()
                vertical.move(to: CGPoint(x: x, y: 0))
                vertical.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(vertical, with: .style(.primary.opacity(opacity)), lineWidth: width)
                var horizontal = Path()
                horizontal.move(to: CGPoint(x: 0, y: y))
                horizontal.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(horizontal, with: .style(.primary.opacity(opacity)), lineWidth: width)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Nine digit buttons; digits with all nine placed dim out (mirrors the
/// app's rose petals).
struct DigitStripView: View {
    let game: NineGame
    let look: WidgetLook

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...9, id: \.self) { digit in
                DigitKey(digit: digit, game: game, look: look, height: 34)
            }
        }
    }
}

/// The same nine buttons as a 3×3 pad, for the medium family (PRD-33).
///
/// Not a second control: the grammar is identical to the strip's — tap a cell,
/// tap a digit — and the buttons are built from the same `DigitKey`, so the two
/// arrangements cannot come to disagree about what a key does. (The same rule
/// PRD-31 applied to the iPad's control column: "same six buttons, same labels,
/// built from the same six factories".)
///
/// 3×3 rather than 9×1 because a medium tile's remaining width after the board is
/// about 100pt: nine keys across it would be 10pt each, and three rows of three
/// gives ~30pt keys in the space that is actually there.
struct DigitPadView: View {
    let game: NineGame
    let look: WidgetLook

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(1...3, id: \.self) { column in
                        DigitKey(
                            digit: row * 3 + column, game: game, look: look,
                            height: nil
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One digit button. Digits with all nine placed dim out (mirrors the app's rose
/// petals).
private struct DigitKey: View {
    let digit: Int
    let game: NineGame
    let look: WidgetLook
    /// Fixed height for the strip; nil lets the pad divide the space it has.
    let height: CGFloat?

    var body: some View {
        Button(intent: PlaceDigitIntent(digit: digit)) {
            Text("\(digit)")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(look.digit)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .frame(maxHeight: height == nil ? .infinity : nil)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary.opacity(0.5))
                )
                .opacity(game.isDigitComplete(digit) ? 0.3 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(game.isDigitComplete(digit))
    }
}
