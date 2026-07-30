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

/// The lesson's own words — the five beat titles, the two long bodies, and the
/// three chips — shared by both tutorials in this file.
///
/// **Declared above every platform fence, and that is the point.** The two tutorials live in one file
/// behind opposite `#if`s and, before PRD-20, each carried its own copy of all
/// five titles and both long bodies — identical English in two `switch`es that
/// no build ever compiles together, so a drift between them could not fail
/// anything. The controller version adds one sentence to each long beat; that
/// difference is now the only thing its `switch` says.
enum TutorialPhrase {
    static let title = Strings.string("tutorial.title")
    static let nice = Strings.string("tutorial.nice")
    static let digitPlaceholder = Strings.string("tutorial.digit.placeholder")

    static let goalTitle = Strings.string("tutorial.goal.title")
    static let goalBody = Strings.string("tutorial.goal.body")
    static let placeTitle = Strings.string("tutorial.place.title")
    static let pencilTitle = Strings.string("tutorial.pencil.title")
    static let highlightTitle = Strings.string("tutorial.highlight.title")
    static let difficultyTitle = Strings.string("tutorial.difficulty.title")
    static let difficultyBody = Strings.string("tutorial.difficulty.body")
}

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

    // PRD-22. The tutorial used to be un-themed chrome over a themed board: a
    // flat black scrim and system-grey text, whatever the app's ground was. On
    // Paper and Camel that is a black wash over a paper app; on Blueprint it is
    // the "muddy dark composite" the 1.1 audit named. Both now come off the
    // board's own tones, so the lesson looks like the game it is teaching.
    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tones: ThemeTones { theme.tones(for: colorScheme) }
    /// Secondary and tertiary text, tinted to the board rather than to the
    /// system's neutral grey — on Ember a cool grey caption over a rust ground
    /// reads as a different app's card.
    private var quiet: Color { tones.digitTone.opacity(0.72) }
    private var quieter: Color { tones.digitTone.opacity(0.5) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // A light theme needs *less* scrim, not the same amount: the
                // card is glass over paper, and a heavy wash turns the page
                // grey. A dark one needs more, because the void behind it is
                // already dark and the card has to separate from it.
                tones.background.opacity(tones.isLight ? 0.42 : 0.62)
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
            Text(TutorialPhrase.title)
                .couchText(CouchTypography.title)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(quieter)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.string("tutorial.close"))
        }
    }

    private var instruction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(instructionTitle)
                .font(CouchTypography.body)
            Text(instructionDetail)
                .font(CouchTypography.caption)
                .foregroundStyle(quiet)
                .fixedSize(horizontal: false, vertical: true)
            if step == .place || step == .pencil || step == .highlight {
                Text(grammar.advanceHint)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(quieter)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.couchFast, value: step)
    }

    private var instructionTitle: String {
        switch step {
        case .goal: return TutorialPhrase.goalTitle
        case .place: return TutorialPhrase.placeTitle
        case .pencil: return TutorialPhrase.pencilTitle
        case .highlight: return TutorialPhrase.highlightTitle
        case .difficulty: return TutorialPhrase.difficultyTitle
        }
    }

    private var instructionDetail: String {
        switch step {
        case .goal:
            return TutorialPhrase.goalBody
        case .place:
            return grammar.placeDetail(digit: targetDigitName)
        case .pencil:
            return grammar.pencilDetail
        case .highlight:
            return grammar.highlightDetail
        case .difficulty:
            return TutorialPhrase.difficultyBody
        }
    }

    private var targetDigitName: String {
        guard let game else { return TutorialPhrase.digitPlaceholder }
        return "\(game.puzzle.solution.cells[targetCell])"
    }

    @ViewBuilder
    private var footer: some View {
        if step == .goal {
            tutorialButton(Strings.string("tutorial.button.tryIt")) { advance() }
        } else if step == .difficulty {
            tutorialButton(Strings.string("tutorial.button.done")) { onDismiss() }
        } else if stepDone {
            GlassChip(TutorialPhrase.nice, systemImage: "checkmark")
        } else {
            // Escape hatch so nobody is ever stuck in a lesson.
            Button(Strings.string("tutorial.button.skipStep")) { advance() }
                .font(CouchTypography.caption)
                .foregroundStyle(quieter)
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
            let lens = rose.map { roseLens(side: side, inset: inset, rose: $0) }
            let board = BoardView(
                game: game,
                cursor: cursor,
                accent: accent,
                showErrors: true,
                solvedAt: nil,
                roseOpen: rose != nil,
                roseLens: reduceMotion ? nil : lens,
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
                if let rose, let lens {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.couchFast) { self.rose = nil } }
                    TouchRose(
                        state: rose,
                        accent: accent,
                        completedDigits: Set((1...9).filter { game.isDigitComplete($0) }),
                        scale: lens.scale,
                        onDigit: { commit(digit: $0) }
                    )
                    .position(x: lens.viewCentre.x, y: lens.viewCentre.y)
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
            GlassChip(Strings.string("status.composing"), systemImage: "sparkles")
                .frame(minHeight: 220)
        }
    }

    /// Same geometry as the game screen, from the same value: the rose never
    /// leaves the board, and the board bends where the petals are (PRD-22).
    private func roseLens(side: CGFloat, inset: CGFloat, rose: RoseState) -> RoseLens {
        RoseLens(
            cursor: cursor,
            side: Double(side),
            inset: Double(inset),
            pencil: rose.pencil,
            scale: RoseLens.scale(forSide: Double(side))
        )
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
        guard let action = BoardKeys.action(for: press) else { return false }
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
                        Text(Strings.difficulty(difficulty))
                            .font(CouchTypography.body)
                        Text(difficulty.explainer)
                            .font(CouchTypography.caption)
                            .foregroundStyle(quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sun.max")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(quiet)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Strings.string("shelf.today.title"))
                        .font(CouchTypography.body)
                    // The band's name is an argument, not part of the sentence.
                    // It used to be the hard-coded word "Steady", so the German
                    // tutorial would have explained a board called "Steady"
                    // that the German shelf calls something else.
                    Text(Strings.string("tutorial.today.body",
                                        .text(Strings.difficulty(.steady))))
                        .font(CouchTypography.caption)
                        .foregroundStyle(quiet)
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
        guard let game else { return TutorialPhrase.digitPlaceholder }
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

    // PRD-22, same as the touch tutorial: the scrim and the quiet text come
    // off the board's tones rather than off black and system grey.
    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tones: ThemeTones { theme.tones(for: colorScheme) }
    private var quiet: Color { tones.digitTone.opacity(0.72) }
    private var quieter: Color { tones.digitTone.opacity(0.5) }

    var body: some View {
        ZStack {
            tones.background.opacity(tones.isLight ? 0.46 : 0.66).ignoresSafeArea()
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
            Text(Strings.string("tutorial.titlePad"))
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
                .foregroundStyle(quiet)
                .fixedSize(horizontal: false, vertical: true)
            if model.step == .place || model.step == .pencil || model.step == .highlight {
                Text(grammar.advanceHint)
                    .font(CouchTypography.caption)
                    .foregroundStyle(quieter)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instructionTitle: String {
        switch model.step {
        case .goal: return TutorialPhrase.goalTitle
        case .place: return TutorialPhrase.placeTitle
        case .pencil: return TutorialPhrase.pencilTitle
        case .highlight: return TutorialPhrase.highlightTitle
        case .difficulty: return TutorialPhrase.difficultyTitle
        }
    }

    private var instructionDetail: String {
        switch model.step {
        // The two long beats are the shared sentences plus one controller
        // instruction. Composed through a key rather than concatenated in
        // Swift, so the translator owns the join — Japanese does not put a
        // space between sentences and would otherwise inherit an ASCII one.
        case .goal:
            return Strings.string("tutorial.pad.beginBody", .text(TutorialPhrase.goalBody))
        case .place:
            return grammar.placeDetail(digit: model.targetDigitName)
        case .pencil:
            return grammar.pencilDetail
        case .highlight:
            return grammar.highlightDetail
        case .difficulty:
            return Strings.string("tutorial.pad.readyBody",
                                  .text(TutorialPhrase.difficultyBody))
        }
    }

    @ViewBuilder
    private var boardArea: some View {
        if let game = model.game {
            let side: CGFloat = 560
            // `clamped: false` matches the TV game screen: PRD-22 is a
            // rendering change, and moving where the ring blooms is not.
            let lens = model.learningRose.map {
                RoseLens(cursor: model.cursor, side: Double(side), inset: 20,
                         pencil: $0.pencil, scale: 0.6, clamped: false)
            }
            BoardView(
                game: game,
                cursor: model.cursor,
                accent: accent,
                showErrors: true,
                solvedAt: nil,
                roseOpen: model.learningRose != nil,
                roseLens: reduceMotion ? nil : lens,
                previewDigit: model.previewDigit,
                previewPencil: model.learningRose?.pencil ?? false,
                highlightDigit: model.highlighted,
                side: side,
                inset: 20
            )
            .overlay {
                if let lens {
                    FlickRoseView(
                        state: model.learningRose ?? RoseState(pencil: false),
                        accent: accent,
                        completedDigits: Set((1...9).filter { game.isDigitComplete($0) }),
                        showsFocusRing: true,
                        scale: lens.scale
                    )
                    .position(x: lens.viewCentre.x, y: lens.viewCentre.y)
                }
            }
            .frame(width: side + 40, height: side + 40)
        } else {
            GlassChip(Strings.string("status.composing"), systemImage: "sparkles")
                .frame(minHeight: 300)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.stepDone {
            GlassChip(TutorialPhrase.nice, systemImage: "checkmark")
        } else if model.step == .goal {
            GlassChip(Strings.string("tutorial.pad.tryIt"), systemImage: "circle")
        } else if model.step == .difficulty {
            GlassChip(Strings.string("tutorial.pad.finish"), systemImage: "checkmark.circle")
        } else {
            GlassChip(Strings.string("tutorial.pad.skip"), systemImage: "forward")
                .opacity(0.7)
        }
    }
}

/// The difficulty guide at TV scale (the tutorial's last beat).
private struct PadDifficultyGuide: View {
    let accent: Color

    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var quiet: Color { theme.tones(for: colorScheme).digitTone.opacity(0.72) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Difficulty.allCases, id: \.self) { difficulty in
                HStack(alignment: .top, spacing: 20) {
                    MiniBoard(difficulty: difficulty, accent: accent)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Strings.difficulty(difficulty))
                            .font(CouchTypography.body)
                        Text(difficulty.explainer)
                            .font(CouchTypography.caption)
                            .foregroundStyle(quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
