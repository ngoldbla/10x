// BoardWidget.swift — the playable systemLarge widget (PRD-3 §4): the real
// daily board, one tap at a time. 81 cell buttons + 9 digit buttons, all
// routed through App Intents; givens semibold, entries in glacier, heavier
// 3×3 strokes, no pencil marks. Pitched as "sneak in a move while waiting
// for coffee" — the app remains the primary way to play.
import SwiftUI
import WidgetKit

struct NineBoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NineBoardWidget", provider: BoardProvider()) { entry in
            BoardWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    BoardWidgetBackground()
                }
        }
        .configurationDisplayName("Playable Daily")
        .description("Play today's puzzle right on your Home Screen.")
        .supportedFamilies([.systemLarge])
    }
}

struct BoardWidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        colorScheme == .light ? WidgetPalette.paper : Color.black
    }
}

// MARK: - Provider

struct BoardEntry: TimelineEntry {
    let date: Date
    let board: SharedDailyBoard?
    let selectedCell: Int?

    var today: Int { WidgetSnapshotStore.dayOrdinal(for: date) }

    /// Yesterday's leftover board is not playable (stale-day guard).
    var currentBoard: SharedDailyBoard? {
        guard let board, board.isCurrent(today: today) else { return nil }
        return board
    }

    var isSolved: Bool {
        guard let currentBoard else { return false }
        return currentBoard.game.isSolved || currentBoard.pendingSolve != nil
    }
}

struct BoardProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: Date(), board: nil, selectedCell: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        let now = Date()
        let midnight = WidgetSnapshotStore.nextLocalMidnight(after: now)
        // The midnight entry re-derives against the new day: the same board
        // renders as "new puzzle waiting" via the stale-day guard.
        completion(Timeline(
            entries: [entry(at: now), entry(at: midnight)],
            policy: .after(midnight)
        ))
    }

    private func entry(at date: Date) -> BoardEntry {
        let today = WidgetSnapshotStore.dayOrdinal(for: date)
        return BoardEntry(
            date: date,
            board: SharedDailyBoardStore.load(),
            selectedCell: SharedDailyBoardStore.selectedCell(today: today)
        )
    }
}

// MARK: - Views

struct BoardWidgetView: View {
    let entry: BoardEntry

    var body: some View {
        if let board = entry.currentBoard {
            VStack(spacing: 10) {
                BoardGridView(
                    game: board.game,
                    selectedCell: entry.isSolved ? nil : entry.selectedCell,
                    playable: !entry.isSolved
                )
                if entry.isSolved {
                    solvedFooter(board)
                } else {
                    DigitStripView(game: board.game)
                }
            }
        } else {
            // No board for today: the widget never generates (Sharp takes
            // seconds; extension budget ~30MB). Deep link; the app composes
            // and publishes.
            startCTA
                .widgetURL(URL(string: "nine://daily"))
        }
    }

    private var startCTA: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.largeTitle)
                .foregroundStyle(WidgetPalette.glacier)
            Text("Tap to start today's puzzle")
                .font(.headline)
            Text("Nine · Daily")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func solvedFooter(_ board: SharedDailyBoard) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(WidgetPalette.glacier)
            Text(solvedText(board))
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
    }

    private func solvedText(_ board: SharedDailyBoard) -> String {
        if let pending = board.pendingSolve {
            return "Solved \(WidgetFormat.time(pending.seconds))"
        }
        return "Solved"
    }
}

/// The 9×9 grid: 81 intent buttons (within archived-view limits, PRD-3 §4).
struct BoardGridView: View {
    let game: NineGame
    let selectedCell: Int?
    let playable: Bool

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
            .font(.system(size: 17, weight: given ? .semibold : .regular, design: .rounded))
            .foregroundStyle(given ? AnyShapeStyle(.primary) : AnyShapeStyle(WidgetPalette.glacier))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .contentShape(Rectangle())
            .overlay {
                if selectedCell == cell {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(WidgetPalette.glacier, lineWidth: 2)
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

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...9, id: \.self) { digit in
                Button(intent: PlaceDigitIntent(digit: digit)) {
                    Text("\(digit)")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
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
    }
}
