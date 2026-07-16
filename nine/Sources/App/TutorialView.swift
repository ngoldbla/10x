// TutorialView.swift — "How to play", playable. Not a slideshow: a real
// (nearly finished) board with the real flick rose, walked through five
// beats — the goal, placing a digit, pencil notes, the same-number
// highlight, and what the difficulty names mean. Each beat advances when
// the player actually does the thing.
#if os(iOS)
import SwiftUI
import CouchKit

struct TutorialView: View {
    let accent: Color
    let onDismiss: @MainActor () -> Void

    private enum Step: Int, CaseIterable {
        case goal, place, pencil, highlight, difficulty
    }

    @State private var step: Step = .goal
    @State private var game: NineGame?
    @State private var targetCell = 0
    @State private var cursor = 0
    @State private var rose: RoseState?
    @State private var pencilMode = false
    @State private var highlighted: Int?
    @State private var stepDone = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { } // swallow — dismissal is the ✕ / Done

                VStack(spacing: 16) {
                    header
                    instruction
                    if step != .difficulty {
                        boardArea(geo: geo)
                    } else {
                        difficultyGuide
                    }
                    footer
                }
                .padding(20)
                .frame(maxWidth: 560)
                .couchGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await composePracticeBoard() }
        .onChange(of: game) { checkProgress() }
        .onChange(of: highlighted) { checkProgress() }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Text("How to play")
                .couchText(CouchTypography.title)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tutorial")
        }
    }

    private var instruction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(instructionTitle)
                .font(CouchTypography.body)
            Text(instructionDetail)
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.couchFast, value: step)
    }

    private var instructionTitle: String {
        switch step {
        case .goal: return "The goal"
        case .place: return "Place a digit"
        case .pencil: return "Pencil notes"
        case .highlight: return "Find every 9 (or 5, or 2…)"
        case .difficulty: return "Pick your poison"
        }
    }

    private var instructionDetail: String {
        switch step {
        case .goal:
            return "Fill every row, column and 3×3 box with 1–9 — each digit exactly once. This board is nearly done; you'll finish a piece of it."
        case .place:
            return "Tap the glowing cell, then tap the \(targetDigitName) in the rose. (You can also flick toward it — the rose is a 3×3 keypad.)"
        case .pencil:
            return "Pencil is on. Tap an empty cell and note a digit you're considering — notes sit small in the corner until a real digit lands."
        case .highlight:
            return "Tap any placed digit on the board. Every copy of it lights up — pencil notes too. Tap one again to switch the lights off."
        case .difficulty:
            return "Every difficulty is provably solvable by logic alone — no guessing, ever. Solves earn points; faster and harder earns more."
        }
    }

    private var targetDigitName: String {
        guard let game else { return "digit" }
        return "\(game.puzzle.solution.cells[targetCell])"
    }

    @ViewBuilder
    private var footer: some View {
        if step == .goal {
            tutorialButton("Try it") { advance() }
        } else if step == .difficulty {
            tutorialButton("Done") { onDismiss() }
        } else if stepDone {
            GlassChip("Nice", systemImage: "checkmark")
        } else {
            // Escape hatch so nobody is ever stuck in a lesson.
            Button("Skip this step") { advance() }
                .font(CouchTypography.caption)
                .foregroundStyle(.tertiary)
                .buttonStyle(.plain)
        }
    }

    private func tutorialButton(_ title: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CouchTypography.body)
                .padding(.horizontal, 40)
                .padding(.vertical, 12)
                .couchGlassInteractive(in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Practice board

    @ViewBuilder
    private func boardArea(geo: GeometryProxy) -> some View {
        if let game {
            let inset: CGFloat = 10
            let side = max(200, min(geo.size.width - 104, geo.size.height * 0.52))
            BoardView(
                game: game,
                cursor: cursor,
                accent: accent,
                showErrors: true,
                solvedAt: nil,
                roseOpen: rose != nil,
                previewDigit: nil,
                previewPencil: false,
                highlightDigit: highlighted,
                side: side,
                inset: inset
            )
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, side: side, inset: inset)
            }
            .overlay {
                if let rose {
                    let scale = min(0.62, ((side / 9) * 1.15) / 116)
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.couchFast) { self.rose = nil } }
                    TouchRose(
                        state: rose,
                        accent: accent,
                        completedDigits: Set((1...9).filter { game.isDigitComplete($0) }),
                        scale: scale,
                        onDigit: { commit(digit: $0) }
                    )
                    .position(rosePosition(side: side, inset: inset, scale: scale))
                }
            }
        } else {
            GlassChip("Composing…", systemImage: "sparkles")
                .frame(minHeight: 220)
        }
    }

    /// Same clamping as the game screen: the rose never leaves the board.
    private func rosePosition(side: CGFloat, inset: CGFloat, scale: CGFloat) -> CGPoint {
        let center = BoardMetrics.center(of: cursor, side: side)
        let radius = 126 * scale + (116 * scale) / 2
        let frameSide = side + 2 * inset
        let clamp: (CGFloat) -> CGFloat = { value in
            min(max(value, radius - 6), frameSide - radius + 6)
        }
        return CGPoint(x: clamp(center.x + inset), y: clamp(center.y + inset))
    }

    private func handleTap(at location: CGPoint, side: CGFloat, inset: CGFloat) {
        guard let game, rose == nil else { return }
        let boardPoint = CGPoint(x: location.x - inset, y: location.y - inset)
        guard let cell = BoardMetrics.cellIndex(at: boardPoint, side: side) else { return }
        cursor = cell
        let digit = game.entry(at: cell)
        if digit != 0 {
            // Same grammar as the real game: filled cells toggle the lights.
            withAnimation(.couchFast) {
                highlighted = (highlighted == digit) ? nil : digit
            }
        }
        guard !game.isGiven(cell) else { return }
        let pencil = pencilMode && digit == 0
        withAnimation(.couchFast) {
            rose = RoseState(pencil: pencil)
        }
    }

    private func commit(digit: Int) {
        guard let state = rose, var g = game else { return }
        if state.pencil {
            g.togglePencil(digit, at: cursor)
        } else {
            g.place(digit, at: cursor)
        }
        game = g
        withAnimation(.couchFast) { rose = nil }
    }

    /// A gentle board with all but five cells already resolved, so the goal
    /// reads at a glance and the lesson's target is unmissable.
    private func composePracticeBoard() async {
        guard game == nil else { return }
        let puzzle = await Task.detached(priority: .userInitiated) {
            PuzzleGenerator.generate(seed: 0x9109, difficulty: .gentle)
        }.value
        var g = NineGame(puzzle: puzzle)
        let empties = (0..<81).filter { g.entry(at: $0) == 0 }
        for cell in empties.dropLast(5) {
            g.place(puzzle.solution.cells[cell], at: cell)
        }
        let remaining = Array(empties.suffix(5))
        targetCell = remaining.first ?? 40
        cursor = targetCell
        game = g
    }

    // MARK: - Progress

    private func checkProgress() {
        guard !stepDone else { return }
        let done: Bool
        switch step {
        case .place:
            done = game.map { $0.entry(at: targetCell) == $0.puzzle.solution.cells[targetCell] } ?? false
        case .pencil:
            done = game.map { g in (0..<81).contains { !g.pencilDigits(at: $0).isEmpty } } ?? false
        case .highlight:
            done = highlighted != nil
        case .goal, .difficulty:
            return
        }
        guard done else { return }
        withAnimation(.couchFast) { stepDone = true }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            advance()
        }
    }

    private func advance() {
        withAnimation(.couchFast) {
            stepDone = false
            step = Step(rawValue: step.rawValue + 1) ?? .difficulty
            pencilMode = (step == .pencil)
            if step == .highlight { highlighted = nil }
        }
    }

    // MARK: - Difficulty guide

    private var difficultyGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Difficulty.allCases, id: \.self) { difficulty in
                HStack(alignment: .top, spacing: 14) {
                    MiniBoard(difficulty: difficulty, accent: accent)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(difficulty.title)
                            .font(CouchTypography.body)
                        Text(difficulty.explainer)
                            .font(CouchTypography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sun.max")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Today")
                        .font(CouchTypography.body)
                    Text("One shared Steady board a day. Solve it daily to grow your streak — streaks multiply your points.")
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
