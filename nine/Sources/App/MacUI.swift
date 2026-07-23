// MacUI.swift — Nine's keyboard-native macOS layer (PRD-4). Same AppModel,
// same engine, same board and rose rendering as the TV and touch apps; the
// input grammar is the keyboard first, the pointer second:
//
//   arrow keys           move the cursor (wraps at edges)
//   1–9                  place the digit under the cursor
//   ⇧1–9 / P             pencil a note / sticky pencil mode
//   Delete / 0           erase a user entry
//   Space                same-number highlight of the digit under the cursor
//   Tab / ⇧Tab           jump to the next / previous empty cell
//   ⌘Z                   undo (glass toast shows the reverted digit)
//   Esc                  close the rose · else back to the shelf
//   hover                halo the cell under the pointer (first hover in the suite)
//   click                select · click a selected empty cell blooms the rose
//   petal click / drag   place that digit (shared flick math)
//
// The menu bar and Settings scene (in NineApp) carry everything a control bar
// would, so the game screen shows only the board and right-aligned chips.
#if os(macOS)
import SwiftUI
import AppKit
import CouchKit

// MARK: - Keyboard grammar

/// One decoded keystroke over the board. Pure classification (no state), so
/// the game screen and the tutorial share it.
enum BoardKeyAction {
    case move(Direction4)
    case place(Int)
    case pencil(Int)
    case erase
    case toggleStickyPencil
    case highlight
    case nextEmpty(forward: Bool)
    case escape
}

enum MacBoardKeys {
    /// Classify a `KeyPress` into a board action, or nil to pass it through
    /// (⌘-shortcuts belong to the menus). The never-misfire rule is trivial
    /// here: a keystroke is unambiguous.
    static func action(for press: KeyPress) -> BoardKeyAction? {
        switch press.key {
        case .upArrow: return .move(.up)
        case .downArrow: return .move(.down)
        case .leftArrow: return .move(.left)
        case .rightArrow: return .move(.right)
        case .escape: return .escape
        case .space: return .highlight
        case .tab: return .nextEmpty(forward: !press.modifiers.contains(.shift))
        case .delete, .deleteForward: return .erase
        default: break
        }
        let ch = press.key.character
        if ch == "p" || ch == "P" { return .toggleStickyPencil }
        if ch == "0" { return .erase }
        // The hardware delete (backspace) key can arrive as a raw control
        // character rather than KeyEquivalent.delete (observed in validation).
        if ch == "\u{7F}" || ch == "\u{08}" { return .erase }
        if let digit = digitValue(press), (1...9).contains(digit) {
            return press.modifiers.contains(.shift) ? .pencil(digit) : .place(digit)
        }
        return nil
    }

    /// The digit a key stands for, tolerating layouts that deliver ⇧1 as its
    /// shifted symbol rather than the base digit.
    private static func digitValue(_ press: KeyPress) -> Int? {
        if let value = press.key.character.wholeNumberValue, (0...9).contains(value) {
            return value
        }
        switch press.key.character {
        case "!": return 1
        case "@": return 2
        case "#": return 3
        case "$": return 4
        case "%": return 5
        case "^": return 6
        case "&": return 7
        case "*": return 8
        case "(": return 9
        default: return nil
        }
    }
}

// MARK: - Menu ↔ focused view actions

/// Actions the menu bar routes back into the focused game screen (so the
/// Undo toast, which lives in view state, still shows). Published via
/// `focusedSceneValue`; a nil value greys the menu item out.
struct NineFocusActions {
    var performUndo: (@MainActor () -> Void)? = nil
}

struct NineFocusActionsKey: FocusedValueKey {
    typealias Value = NineFocusActions
}

extension FocusedValues {
    var nineActions: NineFocusActions? {
        get { self[NineFocusActionsKey.self] }
        set { self[NineFocusActionsKey.self] = newValue }
    }
}

// MARK: - Home

struct MacHomeView: View {
    let model: AppModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                todayCard
                if let (game, difficulty) = model.savedFree {
                    continueCard(game: game, difficulty: difficulty)
                }
                freePlayRow
                learnRow
            }
            .padding(28)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        // The board tracker, opened from the Boards card or Game ▸ Boards…
        // (a GlassSheet overlay, the Mac's one secondary surface on home).
        .overlay {
            GlassSheet(isPresented: Binding(
                get: { model.macShowBoards },
                set: { model.macShowBoards = $0 }
            )) {
                BoardsSheetContent(model: model, onClose: { model.macShowBoards = false })
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Nine")
                .couchText(CouchTypography.title)
            Spacer()
            if model.totalPoints > 0 {
                GlassChip("\(model.totalPoints) pts", systemImage: "star.fill")
            }
            if model.displayedStreak > 0 {
                GlassChip("\(model.displayedStreak) day streak", systemImage: "flame")
            }
        }
        .padding(.top, 8)
    }

    private var todayCard: some View {
        MacCard(action: { model.openToday() }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today")
                    .couchText(CouchTypography.title)
                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                todayStatus
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var todayStatus: some View {
        if isComposingDaily {
            statusLabel("Composing…", symbol: "sparkles")
        } else if model.todaySolved {
            statusLabel("Solved", symbol: "checkmark.circle.fill")
        } else if let daily = model.savedDaily {
            HStack(spacing: 12) {
                GlassRing(progress: daily.fillFraction, lineWidth: 5)
                    .frame(width: 34, height: 34)
                Text("Continue")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            statusLabel("One a day", symbol: "sun.max")
        }
    }

    private func continueCard(game: NineGame, difficulty: Difficulty) -> some View {
        MacCard(action: { model.continueSaved() }) {
            HStack(spacing: 16) {
                GlassRing(progress: game.fillFraction, lineWidth: 5)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue")
                        .font(CouchTypography.body)
                    Text("\(difficulty.title) · \(Int(game.fillFraction * 100))%"
                         + (model.extraPartialCount > 0 ? " · +\(model.extraPartialCount) more" : ""))
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.couchFast) { model.discardSaved() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Discard saved game")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var freePlayRow: some View {
        HStack(spacing: 14) {
            ForEach(Difficulty.allCases, id: \.self) { difficulty in
                MacCard(action: { model.startFree(difficulty) }) {
                    VStack(spacing: 10) {
                        MiniBoard(difficulty: difficulty, accent: accent)
                            .frame(width: 64, height: 64)
                        if model.composing == .free(difficulty) {
                            statusLabel("Composing…", symbol: "sparkles")
                        } else {
                            Text(difficulty.title)
                                .font(CouchTypography.caption)
                            Text(difficulty.blurb)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 124)
                }
            }
        }
    }

    private var learnRow: some View {
        HStack(spacing: 14) {
            MacCard(action: { model.macShowTutorial = true }) {
                learnTile(symbol: "questionmark.circle", title: "How to play")
            }
            MacCard(action: { model.macShowBoards = true }) {
                learnTile(symbol: "square.stack.3d.up", title: "Boards")
            }
            MacCard(action: { openWindow(id: "history") }) {
                learnTile(symbol: "trophy", title: "History")
            }
        }
    }

    private func learnTile(symbol: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(CouchTypography.caption)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
    }

    private func statusLabel(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
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

/// A clickable glass slab — the Mac counterpart of the TV shelf card and the
/// touch card. A Button so it is keyboard-focusable (Tab) and pointer-clickable.
private struct MacCard<Content: View>: View {
    let action: @MainActor () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .padding(18)
                .couchGlassInteractive(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(MacCardStyle())
    }
}

private struct MacCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.couchFast, value: configuration.isPressed)
    }
}

// MARK: - Game

struct MacGameScreen: View {
    let model: AppModel

    @State private var cursor = 40
    @FocusState private var boardFocused: Bool
    @State private var rose: RoseState?
    @State private var pencilMode = false
    @State private var toast: UndoToastState?
    @State private var toastDismissal: Task<Void, Never>?
    @State private var highlightedDigit: Int?
    @State private var hoverCell: Int?
    @State private var deskHovering = false
    /// The Mac's trophy tilt: the pointer steers the sheen (PRD-4 §2.6).
    @State private var pointer = AfterglowPointer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }
    private var isDesk: Bool { model.windowMode == .desk }

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = isDesk ? 6 : 16
            let chrome: CGFloat = isDesk ? 8 : 24
            let side = max(220, min(geo.size.width - 2 * inset - chrome,
                                    geo.size.height - 2 * inset - chrome))
            ZStack {
                boardArea(side: side, inset: inset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) { if !isDesk { homeChip.padding(20) } }
            .overlay(alignment: .topTrailing) { if !isDesk { statusChips.padding(20) } }
            .overlay(alignment: .bottom) { toastView.padding(.bottom, isDesk ? 12 : 28) }
            .overlay(alignment: .bottom) { completionChip.padding(.bottom, isDesk ? 40 : 72) }
            .overlay(alignment: .top) { composingChip.padding(.top, isDesk ? 8 : 16) }
            .overlay(alignment: .bottomTrailing) { if isDesk { deskCornerGlyph.padding(10) } }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($boardFocused)
        .focusedSceneValue(\.nineActions, NineFocusActions(performUndo: performUndo))
        .onKeyPress { press in handleKey(press) ? .handled : .ignored }
        .onHover { deskHovering = $0 }
        // The keyboard is the superpower (PRD-4 §2.2): the board claims key
        // focus the moment it appears — and again when the window swaps
        // between full and desk chrome — so digits always type. Without this
        // the surface is focusable but never focused, and every plain key
        // falls through (the §5 "focus wars" risk, observed in validation).
        .onAppear { boardFocused = true }
        .onChange(of: isDesk) { boardFocused = true }
    }

    // MARK: Chrome

    private var homeChip: some View {
        Button { model.goHome() } label: {
            // "Home", not "Shelf" — the shelf is TV vocabulary; the Mac home
            // is a card grid in a window.
            GlassChip("Home", systemImage: "chevron.left")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to home")
    }

    @ViewBuilder
    private var statusChips: some View {
        HStack(spacing: 10) {
            if pencilMode {
                GlassChip("Pencil", systemImage: "pencil")
            }
            timerChip
        }
    }

    @ViewBuilder
    private var timerChip: some View {
        if model.prefs.showTimer, let game = model.game, model.solvedAt == nil {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                GlassChip(Self.format(game.timer.elapsed(at: timeline.date)), systemImage: "clock")
            }
        }
    }

    @ViewBuilder
    private var composingChip: some View {
        if model.composing != nil, model.game != nil {
            GlassChip("Composing…", systemImage: "sparkles")
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            GlassChip(toast.text, systemImage: "arrow.uturn.backward")
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .id(toast.id)
        }
    }

    @ViewBuilder
    private var completionChip: some View {
        if let solvedAt = model.solvedAt {
            TimelineView(.periodic(from: solvedAt, by: 0.5)) { timeline in
                if timeline.date.timeIntervalSince(solvedAt) > 2.4 {
                    GlassChip(completionText, systemImage: "checkmark")
                        .transition(.opacity)
                }
            }
        }
    }

    private var completionText: String {
        if case .daily? = model.kind, model.displayedStreak > 0 {
            return "Solved · \(model.displayedStreak) day streak"
        }
        return "Solved"
    }

    /// A small restore glyph that fades in when the pointer is over the desk
    /// pane — the pointer path back to the full window (Esc / ⌘⇧D also work).
    @ViewBuilder
    private var deskCornerGlyph: some View {
        Button { model.exitDeskMode() } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .couchGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .opacity(deskHovering ? 0.9 : 0.0)
        .animation(.couchFast, value: deskHovering)
        .accessibilityLabel("Exit desk mode")
    }

    // MARK: Board + rose

    @ViewBuilder
    private func boardArea(side: CGFloat, inset: CGFloat) -> some View {
        if let game = model.game {
            BoardView(
                game: game,
                cursor: cursor,
                accent: accent,
                showErrors: model.prefs.errorHighlight,
                solvedAt: model.solvedAt,
                roseOpen: rose != nil,
                previewDigit: nil,
                previewPencil: false,
                highlightDigit: model.prefs.numberHighlight ? highlightedDigit : nil,
                hoverCell: model.solvedAt == nil ? hoverCell : nil,
                waveOrigin: model.lastPlacedCell,
                afterglowTilt: { pointer.tilt(at: $0) },
                side: side,
                inset: inset
            )
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    let point = CGPoint(x: location.x - inset, y: location.y - inset)
                    hoverCell = BoardMetrics.cellIndex(at: point, side: side)
                    if model.solvedAt != nil { pointer.update(hover: point, boardSide: side) }
                case .ended:
                    hoverCell = nil
                }
            }
            .onTapGesture { location in
                handleClick(at: location, side: side, inset: inset)
            }
            .overlay {
                if let rose, model.solvedAt == nil {
                    let scale = roseScale(side: side)
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { closeRose() }
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
                .frame(width: side, height: side)
        }
    }

    private func roseScale(side: CGFloat) -> CGFloat {
        let cell = side / 9
        return min(0.62, (cell * 1.15) / 116)
    }

    private func rosePosition(side: CGFloat, inset: CGFloat, scale: CGFloat) -> CGPoint {
        let center = BoardMetrics.center(of: cursor, side: side)
        let radius = 126 * scale + (116 * scale) / 2
        let frameSide = side + 2 * inset
        let clamp: (CGFloat) -> CGFloat = { value in
            min(max(value, radius - 6), frameSide - radius + 6)
        }
        return CGPoint(x: clamp(center.x + inset), y: clamp(center.y + inset))
    }

    // MARK: Pointer grammar

    private func handleClick(at location: CGPoint, side: CGFloat, inset: CGFloat) {
        guard let game = model.game, model.solvedAt == nil, rose == nil else { return }
        let point = CGPoint(x: location.x - inset, y: location.y - inset)
        guard let cell = BoardMetrics.cellIndex(at: point, side: side) else { return }
        let digit = game.entry(at: cell)
        let wasSelected = (cursor == cell)
        cursor = cell
        // Click a placed digit → same-number highlight (as touch/tvOS).
        if digit != 0 {
            if model.prefs.numberHighlight {
                withAnimation(.couchFast) {
                    highlightedDigit = (highlightedDigit == digit) ? nil : digit
                }
            }
            return
        }
        // Click a selected empty (non-given) cell → bloom the rose.
        guard !game.isGiven(cell) else { return }
        if wasSelected {
            withAnimation(.couchFast) {
                rose = RoseState(pencil: pencilMode)
            }
        }
    }

    private func closeRose() {
        withAnimation(.couchFast) { rose = nil }
    }

    private func commit(digit: Int) {
        guard let state = rose else { return }
        if state.pencil {
            model.togglePencil(digit, at: cursor)
        } else {
            model.place(digit, at: cursor)
        }
        closeRose()
    }

    // MARK: Keyboard grammar

    private func handleKey(_ press: KeyPress) -> Bool {
        // On a solved board only Esc (back to the shelf) is live.
        if model.solvedAt != nil {
            if press.key == .escape { model.goHome(); return true }
            return false
        }
        guard model.game != nil else { return false }
        // ⌘-shortcuts belong to the menus (Undo, New Game, Desk, Settings…).
        if press.modifiers.contains(.command) { return false }
        guard let action = MacBoardKeys.action(for: press) else { return false }

        switch action {
        case .move(let direction):
            if rose != nil { closeRose() }
            cursor = BoardMetrics.moveCursor(cursor, direction, wrap: true)
        case .place(let digit):
            if rose != nil { closeRose() }
            // Sticky pencil mode (P) reroutes plain digits to corner marks,
            // exactly as the iOS chip does; ⇧digit stays a one-off mark.
            if pencilMode {
                model.togglePencil(digit, at: cursor)
            } else {
                model.place(digit, at: cursor)
            }
        case .pencil(let digit):
            if rose != nil { closeRose() }
            model.togglePencil(digit, at: cursor)
        case .erase:
            if rose != nil { closeRose() }
            _ = model.erase(at: cursor)
        case .toggleStickyPencil:
            pencilMode.toggle()
        case .highlight:
            let digit = model.game?.entry(at: cursor) ?? 0
            if digit != 0, model.prefs.numberHighlight {
                withAnimation(.couchFast) {
                    highlightedDigit = (highlightedDigit == digit) ? nil : digit
                }
            }
        case .nextEmpty(let forward):
            if let game = model.game {
                cursor = BoardMetrics.nextEmptyCell(from: cursor, in: game, forward: forward)
            }
        case .escape:
            // Esc closes the rose, then restores the full window from desk
            // mode (PRD-4 §2.5), and only then leaves for home.
            if rose != nil {
                closeRose()
            } else if isDesk {
                model.exitDeskMode()
            } else {
                model.goHome()
            }
        }
        return true
    }

    private func performUndo() {
        guard let move = model.undoMove() else { return }
        let text: String
        switch move.kind {
        case .place: text = "Undid \(move.digit)"
        case .erase: text = "Restored \(move.digit)"
        case .pencil: text = "Undid note \(move.digit)"
        }
        let next = UndoToastState(text: text)
        withAnimation(.couchFast) { toast = next }
        toastDismissal?.cancel()
        toastDismissal = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.couchAmbient) {
                if toast?.id == next.id { toast = nil }
            }
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Settings scene (⌘,)

struct MacSettingsView: View {
    let model: AppModel

    var body: some View {
        PrefsSheetContent(model: model)
            .frame(width: 420)
            .frame(minHeight: 480)
            .padding(24)
            .environment(\.nineTheme, model.prefs.theme)
            .preferredColorScheme(model.prefs.theme.colorScheme)
    }
}

// MARK: - History window (⌘Y)

struct MacHistoryWindow: View {
    let model: AppModel

    var body: some View {
        ZStack {
            VoidBackground()
            HistorySheetContent(model: model)
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 380, minHeight: 460)
        .environment(\.nineTheme, model.prefs.theme)
        .preferredColorScheme(model.prefs.theme.colorScheme)
    }
}

// MARK: - Menu bar

struct NineCommands: Commands {
    let model: AppModel
    @FocusedValue(\.nineActions) private var actions

    var body: some Commands {
        // Game
        CommandMenu("Game") {
            Menu("New Game") {
                Button("Gentle") { model.startFree(.gentle) }
                Button("Steady") { model.startFree(.steady) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Sharp") { model.startFree(.sharp) }
            }
            Button("Today's Puzzle") { model.openToday() }
                .keyboardShortcut("t", modifiers: .command)
            Divider()
            HistoryMenuButton()
            Button("Boards…") { model.macShowBoards = true }
                .keyboardShortcut("b", modifiers: .command)
            Divider()
            Button("Discard Board") { model.discardSaved() }
                .disabled(model.savedFree == nil)
        }

        // Edit — replace the stock Undo/Redo so ⌘Z drives the game's toast.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { actions?.performUndo?() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(actions?.performUndo == nil || !model.canUndo)
        }

        // View — fold our rows into the *system* View menu rather than adding
        // a CommandMenu("View"), which macOS renders as a second menu titled
        // View beside the stock one (observed in validation).
        CommandGroup(after: .toolbar) {
            Picker("Appearance", selection: bind(\.theme)) {
                ForEach(ThemeChoice.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Show Timer", isOn: bind(\.showTimer))
            Toggle("Error Highlight", isOn: bind(\.errorHighlight))
            Toggle("Number Highlight", isOn: bind(\.numberHighlight))
            Divider()
            Picker("Accent", selection: bind(\.accent)) {
                ForEach(AccentChoice.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Divider()
            Button(model.windowMode == .desk ? "Exit Desk Mode" : "Enter Desk Mode") {
                model.toggleDeskMode()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            Toggle("Float Desk on Top", isOn: Binding(
                get: { model.deskFloating },
                set: { model.deskFloating = $0 }
            ))
        }

        // Help
        CommandGroup(replacing: .help) {
            Button("How to Play") { model.macShowTutorial = true }
        }
    }

    /// A binding into `model.prefs` — assigning the field mutates the struct
    /// in place, tripping its `didSet` and persisting.
    private func bind<V>(_ keyPath: WritableKeyPath<NinePrefs, V>) -> Binding<V> {
        Binding(
            get: { model.prefs[keyPath: keyPath] },
            set: { model.prefs[keyPath: keyPath] = $0 }
        )
    }
}

/// Extracted so it can read `openWindow` from the environment (menu item
/// content is a real View builder).
private struct HistoryMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("History") { openWindow(id: "history") }
            .keyboardShortcut("y", modifiers: .command)
    }
}

// MARK: - Window configuration (desk mode)

/// Drives the host `NSWindow` from the model: the full-window constraints,
/// the compact desk pane, the optional float-on-top level, and per-mode frame
/// autosave so each posture remembers its own corner (PRD-4 §2.5).
struct MacWindowConfigurator: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let mode = model.windowMode
        let floating = model.deskFloating
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            switch mode {
            case .full:
                window.level = .normal
                window.collectionBehavior = [.fullScreenPrimary]
                window.titleVisibility = .visible
                window.titlebarAppearsTransparent = false
                window.isMovableByWindowBackground = false
                window.minSize = NSSize(width: 480, height: 560)
                window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                        height: CGFloat.greatestFiniteMagnitude)
                window.setFrameAutosaveName("nine.main")
                // Leaving desk mode (or launching with a stale desk frame):
                // grow back to a real window. Prefer the remembered full
                // frame; fall back to the default size, keeping the top-left
                // corner put (observed stuck at desk size in validation).
                if window.frame.width < 480 || window.frame.height < 560 {
                    let top = window.frame.maxY
                    let restored = window.setFrameUsingName("nine.main")
                    if !restored || window.frame.width < 480 || window.frame.height < 560 {
                        var frame = window.frame
                        frame.size = NSSize(width: 720, height: 820)
                        frame.origin.y = top - frame.height
                        window.setFrame(frame, display: true, animate: true)
                    }
                }
            case .desk:
                // ~340pt board-only pane — no header, chromeless, optionally
                // floating above other windows and joining every Space.
                window.level = floating ? .floating : .normal
                window.collectionBehavior = floating
                    ? [.canJoinAllSpaces, .fullScreenAuxiliary]
                    : [.fullScreenAuxiliary]
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                let desk: CGFloat = 340
                window.minSize = NSSize(width: desk, height: desk)
                window.maxSize = NSSize(width: desk + 160, height: desk + 160)
                window.setFrameAutosaveName("nine.desk")
                if window.frame.width > desk + 160 || window.frame.height > desk + 160 {
                    var frame = window.frame
                    let top = frame.maxY
                    frame.size = NSSize(width: desk, height: desk)
                    frame.origin.y = top - desk // keep the top-left corner put
                    window.setFrame(frame, display: true, animate: true)
                }
            }
        }
    }
}
#endif
