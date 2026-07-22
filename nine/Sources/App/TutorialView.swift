// TutorialView.swift — "How to play", playable. Not a slideshow: a real
// (nearly finished) board with the real flick rose, walked through five
// beats — the goal, placing a digit, pencil notes, the same-number
// highlight, and what the difficulty names mean. Each beat advances when
// the player actually does the thing.
//
// The beat copy comes from a `TutorialGrammar` the host supplies, so the same
// view teaches the touch rose on iOS and the keyboard grammar on macOS
// (PRD-4 §2.6). On the Mac the practice board also accepts the full keyboard
// grammar — arrows walk, digits type — alongside the pointer rose.
#if os(iOS) || os(macOS)
import SwiftUI
import CouchKit

struct TutorialView: View {
    let accent: Color
    /// Per-platform beat copy (`.touch` on iOS, `.keyboard` on macOS).
    var grammar: TutorialGrammar = .touch
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
            if step == .place || step == .pencil || step == .highlight {
                Text(grammar.advanceHint)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
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
            return grammar.placeDetail(digit: targetDigitName)
        case .pencil:
            return grammar.pencilDetail
        case .highlight:
            return grammar.highlightDetail
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
            let board = BoardView(
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
            #if os(macOS)
            // The Mac practice board speaks the keyboard grammar too: arrows
            // walk, digits type, Shift-digit pencils, Space highlights.
            board
                .focusable()
                .focusEffectDisabled()
                .onKeyPress { press in handleKey(press) ? .handled : .ignored }
            #else
            board
            #endif
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

    #if os(macOS)
    /// The keyboard grammar over the practice board (mirrors MacGameScreen,
    /// but mutating the local practice game). Returns whether the key was
    /// consumed.
    private func handleKey(_ press: KeyPress) -> Bool {
        guard var g = game else { return false }
        if press.modifiers.contains(.command) { return false }
        guard let action = MacBoardKeys.action(for: press) else { return false }
        switch action {
        case .move(let direction):
            if rose == nil { cursor = BoardMetrics.moveCursor(cursor, direction, wrap: true) }
        case .place(let digit):
            guard !g.isGiven(cursor) else { return true }
            _ = g.place(digit, at: cursor)
            game = g
        case .pencil(let digit):
            guard !g.isGiven(cursor), g.entry(at: cursor) == 0 else { return true }
            _ = g.togglePencil(digit, at: cursor)
            game = g
        case .toggleStickyPencil:
            pencilMode.toggle()
        case .highlight:
            let digit = g.entry(at: cursor)
            if digit != 0 {
                withAnimation(.couchFast) { highlighted = (highlighted == digit) ? nil : digit }
            }
        case .nextEmpty(let forward):
            cursor = BoardMetrics.nextEmptyCell(from: cursor, in: g, forward: forward)
        case .erase:
            break // no erase gesture in the tutorial
        case .escape:
            if rose != nil { withAnimation(.couchFast) { rose = nil } } else { onDismiss() }
        }
        return true
    }
    #endif

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

// MARK: - Pad tutorial (tvOS, PRD-5 §2.3)

// The tvOS remote tutorial is the first-run HelpOverlay (HomeView) — unchanged.
// A pad session gets its own interactive tutorial on the first play, re-gestured
// onto the pad verbs (`TutorialGrammar.pad`) and driven by PadKit's reader. As
// on the board, an external gesture stream wants a reference model, so the beats
// live on a `@Observable` object GameScreen feeds; `PadTutorialView` renders it.
#if os(tvOS)
import SwiftUI
import Observation
import CouchKit

@MainActor
@Observable
final class PadTutorialModel {
    enum Step: Int, CaseIterable { case goal, place, pencil, highlight, difficulty }

    private(set) var step: Step = .goal
    private(set) var game: NineGame?
    private(set) var cursor = 0
    private(set) var learningRose: RoseState?
    private(set) var pencilMode = false
    private(set) var highlighted: Int?
    private(set) var stepDone = false
    /// Flips true when the last beat is dismissed; GameScreen watches this to
    /// mark the tutorial seen and hand the board to the pad grammar.
    var finished = false

    private var targetCell = 0
    @ObservationIgnored private var advanceTask: Task<Void, Never>?

    var targetDigitName: String {
        guard let game else { return "digit" }
        return "\(game.puzzle.solution.cells[targetCell])"
    }

    /// The digit a flick into the learning rose would place, ghosted.
    var previewDigit: Int? { learningRose.map { $0.focusedIndex + 1 } }

    // MARK: Board

    func composePracticeBoardIfNeeded() async {
        guard game == nil else { return }
        let puzzle = await Task.detached(priority: .userInitiated) {
            PuzzleGenerator.generate(seed: 0x9109, difficulty: .gentle)
        }.value
        var g = NineGame(puzzle: puzzle)
        let empties = (0..<81).filter { g.entry(at: $0) == 0 }
        for cell in empties.dropLast(5) {
            g.place(puzzle.solution.cells[cell], at: cell)
        }
        targetCell = Array(empties.suffix(5)).first ?? 40
        cursor = targetCell
        game = g
    }

    // MARK: Gesture entry

    func handle(_ gesture: PadGesture) {
        switch gesture {
        case .move(let direction, let glide):
            move(direction, glide: glide)
        case .flick(let direction):
            commit(digit: RoseGeometry.digit(for: direction))
        case .flickAmbiguous:
            break // the ghost rose is the board's teacher, not the tutorial's
        case .button(let button):
            press(button)
        case .buttonUp, .connect, .disconnect:
            break
        }
    }

    private func move(_ direction: Direction4, glide: Bool) {
        if var rose = learningRose {
            guard !glide else { return }
            rose.focusedIndex = RoseGeometry.moveFocus(rose.focusedIndex, direction)
            learningRose = rose
            return
        }
        cursor = BoardMetrics.moveCursor(cursor, direction, wrap: false)
    }

    private func press(_ button: PadButton) {
        switch button {
        case .cross:
            if step == .goal { advance(); return }
            if step == .difficulty { finished = true; return }
            openRose()
        case .circle:
            learningRose = nil
        case .square:
            pencilMode.toggle()
        case .triangle:
            toggleHighlight()
        case .r3:
            commit(digit: 5)
        default:
            break
        }
    }

    private func openRose() {
        guard let game, !game.isGiven(cursor) else { return }
        if pencilMode, game.entry(at: cursor) != 0 { return }
        learningRose = RoseState(pencil: pencilMode)
    }

    private func commit(digit: Int) {
        guard var g = game, !g.isGiven(cursor) else { learningRose = nil; return }
        if pencilMode, g.entry(at: cursor) == 0 {
            _ = g.togglePencil(digit, at: cursor)
        } else {
            _ = g.place(digit, at: cursor)
        }
        game = g
        learningRose = nil
        checkProgress()
    }

    private func toggleHighlight() {
        guard let digit = game?.entry(at: cursor), digit != 0 else { return }
        highlighted = (highlighted == digit) ? nil : digit
        checkProgress()
    }

    /// The "Skip this step" affordance (Options), so nobody is ever stuck.
    func skip() { advance() }

    // MARK: Progression

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
        stepDone = true
        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    private func advance() {
        stepDone = false
        step = Step(rawValue: step.rawValue + 1) ?? .difficulty
        pencilMode = (step == .pencil)
        if step == .highlight { highlighted = nil }
    }
}

struct PadTutorialView: View {
    let model: PadTutorialModel
    let accent: Color
    var grammar: TutorialGrammar = .pad

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 28) {
                header
                instruction
                if model.step != .difficulty {
                    boardArea
                } else {
                    PadDifficultyGuide(accent: accent)
                }
                footer
            }
            .padding(48)
            .frame(maxWidth: 1180)
            .couchGlass(in: RoundedRectangle(cornerRadius: 48, style: .continuous))
            .padding(48)
        }
        // The tutorial owns the remote while shown: Menu/Back skips out of it.
        .couchRemote(interceptsBack: true) { gesture in
            if case .back = gesture { model.finished = true }
        }
        .task { await model.composePracticeBoardIfNeeded() }
    }

    private var header: some View {
        HStack {
            Text("How to play — controller")
                .couchText(CouchTypography.title)
            Spacer()
        }
    }

    private var instruction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(instructionTitle)
                .font(CouchTypography.body)
            Text(instructionDetail)
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.step == .place || model.step == .pencil || model.step == .highlight {
                Text(grammar.advanceHint)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instructionTitle: String {
        switch model.step {
        case .goal: return "The goal"
        case .place: return "Place a digit"
        case .pencil: return "Pencil notes"
        case .highlight: return "Find every 9 (or 5, or 2…)"
        case .difficulty: return "Pick your poison"
        }
    }

    private var instructionDetail: String {
        switch model.step {
        case .goal:
            return "Fill every row, column and 3×3 box with 1–9 — each digit exactly once. This board is nearly done; you'll finish a piece of it. Press Cross to begin."
        case .place:
            return grammar.placeDetail(digit: model.targetDigitName)
        case .pencil:
            return grammar.pencilDetail
        case .highlight:
            return grammar.highlightDetail
        case .difficulty:
            return "Every difficulty is provably solvable by logic alone — no guessing, ever. Solves earn points; faster and harder earns more. Press Cross when you're ready."
        }
    }

    @ViewBuilder
    private var boardArea: some View {
        if let game = model.game {
            let side: CGFloat = 560
            BoardView(
                game: game,
                cursor: model.cursor,
                accent: accent,
                showErrors: true,
                solvedAt: nil,
                roseOpen: model.learningRose != nil,
                previewDigit: model.previewDigit,
                previewPencil: model.learningRose?.pencil ?? false,
                highlightDigit: model.highlighted,
                side: side,
                inset: 20
            )
            .overlay {
                if let rose = model.learningRose {
                    let center = BoardMetrics.center(of: model.cursor, side: side)
                    FlickRoseView(
                        state: rose,
                        accent: accent,
                        completedDigits: Set((1...9).filter { game.isDigitComplete($0) }),
                        showsFocusRing: true,
                        scale: 0.6
                    )
                    .position(x: center.x + 20, y: center.y + 20)
                }
            }
            .frame(width: side + 40, height: side + 40)
        } else {
            GlassChip("Composing…", systemImage: "sparkles")
                .frame(minHeight: 300)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.stepDone {
            GlassChip("Nice", systemImage: "checkmark")
        } else if model.step == .goal {
            GlassChip("Press Cross to try it", systemImage: "circle")
        } else if model.step == .difficulty {
            GlassChip("Press Cross — done", systemImage: "checkmark.circle")
        } else {
            GlassChip("Press Menu to skip the tutorial", systemImage: "forward")
                .opacity(0.7)
        }
    }
}

/// The difficulty guide at TV scale (the tutorial's last beat).
private struct PadDifficultyGuide: View {
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Difficulty.allCases, id: \.self) { difficulty in
                HStack(alignment: .top, spacing: 20) {
                    MiniBoard(difficulty: difficulty, accent: accent)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(difficulty.title)
                            .font(CouchTypography.body)
                        Text(difficulty.explainer)
                            .font(CouchTypography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
