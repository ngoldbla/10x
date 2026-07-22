// TouchUI.swift — Nine's touch-native layer (iPhone + iPad). Same AppModel,
// same engine, same board and rose rendering as the TV app; only the input
// grammar changes:
//
//   tap a cell            open the flick rose on that cell
//   tap a petal           place that digit
//   flick (in the rose)   place instantly — same 3×3 keypad mapping as tvOS
//   tap outside the rose  cancel
//   pencil toggle         rose places corner notes instead
//   undo button           take back a move (glass toast shows what reverted)
//   gear                  prefs sheet · chevron: save + home
#if os(iOS)
import SwiftUI
import CouchKit

// MARK: - Home

struct TouchHomeView: View {
    let model: AppModel

    @State private var showHistory = false
    @State private var showTutorial = false
    @Environment(\.colorScheme) private var colorScheme

    /// The accent resolved for the theme's leaning (themes pin the scheme).
    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    todayCard
                    continueCard
                    freePlayRow
                    learnRow
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity) // center the column on iPad
            }
            if !model.helpSeen {
                HelpOverlay(
                    title: "Nine",
                    tagline: "Couch sudoku.",
                    rows: NineLegend.touch
                ) {
                    model.helpSeen = true
                }
            }
        }
        .overlay { GlassSheet(isPresented: $showHistory) { HistorySheetContent(model: model) } }
        .overlay {
            if showTutorial {
                TutorialView(accent: accent) {
                    showTutorial = false
                }
                .transition(.opacity)
            }
        }
        .animation(.couchFast, value: showTutorial)
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

    // MARK: Learn + records

    private var learnRow: some View {
        HStack(spacing: 14) {
            TouchCard(action: { showTutorial = true }) {
                VStack(spacing: 10) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("How to play")
                        .font(CouchTypography.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 74)
            }
            TouchCard(action: { showHistory = true }) {
                VStack(spacing: 10) {
                    Image(systemName: "trophy")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("History")
                        .font(CouchTypography.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 74)
            }
        }
    }

    // MARK: Today

    private var todayCard: some View {
        TouchCard(action: { model.openToday() }) {
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

    // MARK: Continue (free play in progress)

    @ViewBuilder
    private var continueCard: some View {
        if let (game, difficulty) = model.savedFree {
            TouchCard(action: { model.continueSaved() }) {
                HStack(spacing: 16) {
                    GlassRing(progress: game.fillFraction, lineWidth: 5)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Continue")
                            .font(CouchTypography.body)
                        Text("\(difficulty.title) · \(Int(game.fillFraction * 100))%")
                            .font(CouchTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Abandon the board: frees the slot so a fresh difficulty
                    // doesn't feel like a betrayal of this one.
                    Button {
                        withAnimation(.couchFast) { model.discardSaved() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Discard saved game")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Free play

    private var freePlayRow: some View {
        HStack(spacing: 14) {
            ForEach(Difficulty.allCases, id: \.self) { difficulty in
                difficultyCard(difficulty)
            }
        }
    }

    private func difficultyCard(_ difficulty: Difficulty) -> some View {
        TouchCard(action: { model.startFree(difficulty) }) {
            VStack(spacing: 10) {
                MiniBoard(difficulty: difficulty, accent: accent)
                    .frame(width: 64, height: 64)
                if model.composing == .free(difficulty) {
                    statusLabel("Composing…", symbol: "sparkles")
                } else {
                    Text(difficulty.title)
                        .font(CouchTypography.caption)
                        .foregroundStyle(.primary)
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

    // MARK: Helpers

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

/// A tappable glass slab: the touch counterpart of the TV shelf card.
/// A Button (not a bare tap gesture) so it gets pressed feedback and the
/// full accessibility treatment for free.
private struct TouchCard<Content: View>: View {
    let action: @MainActor () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .padding(18)
                .couchGlassInteractive(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(TouchCardStyle())
    }
}

private struct TouchCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.couchFast, value: configuration.isPressed)
    }
}

// MARK: - Game

struct TouchGameScreen: View {
    let model: AppModel

    @State private var cursor = 40
    @State private var rose: RoseState?
    @State private var pencilMode = false
    @State private var showPrefs = false
    @State private var toast: UndoToastState?
    @State private var toastDismissal: Task<Void, Never>?
    /// Same-number highlight: the digit currently lit across the board.
    /// Sticky on purpose — it survives placements so you can chase one
    /// number around the grid; tapping a cell of the same digit clears it.
    @State private var highlightedDigit: Int?
    /// Afterglow: the haptic score and the gravity-tilt source live in the
    /// view layer — AppModel is platform-shared logic; this is presentation.
    @State private var haptics = AfterglowHaptics()
    @State private var motion = AfterglowMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    /// The accent resolved for the theme's leaning (themes pin the scheme).
    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    var body: some View {
        GeometryReader { geo in
            let boardInset: CGFloat = 12
            let controlsAtBottom = model.prefs.controlsAtBottom
            let side = max(200, min(geo.size.width - 2 * boardInset - 16,
                                    geo.size.height - 76 - 2 * boardInset - 16))
            let freeSpace = geo.size.height - (side + 2 * boardInset + 16) - 76

            VStack(spacing: 12) {
                if controlsAtBottom {
                    band(.top, freeSpace: freeSpace)
                    boardArea(side: side, inset: boardInset)
                    band(.bottom, freeSpace: freeSpace)
                    controlBar
                } else {
                    controlBar
                    band(.top, freeSpace: freeSpace)
                    boardArea(side: side, inset: boardInset)
                    band(.bottom, freeSpace: freeSpace)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { toastView.padding(.bottom, controlsAtBottom ? 84 : 20) }
            .overlay(alignment: .bottom) { completionChip.padding(.bottom, controlsAtBottom ? 128 : 64) }
            .overlay(alignment: .top) { composingChip.padding(.top, controlsAtBottom ? 12 : 64) }
            .overlay {
                GlassSheet(isPresented: $showPrefs) {
                    PrefsSheetContent(model: model) { difficulty in
                        showPrefs = false
                        highlightedDigit = nil
                        model.startFree(difficulty)
                    }
                }
            }
        }
        .onChange(of: model.solvedAt) { _, solved in
            guard solved != nil else { return }
            // The haptic score plays even under Reduce Motion (haptics are
            // not motion; platform convention) — the gyro trophy does not.
            haptics.playSolveScore()
            if !reduceMotion { motion.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if model.solvedAt != nil, !reduceMotion { motion.start() }
            } else {
                haptics.stop()
                motion.stop()
            }
        }
        .onDisappear {
            haptics.stop()
            motion.stop()
        }
    }

    // MARK: Chrome

    private var controlBar: some View {
        HStack(spacing: 10) {
            GlassIconButton(symbol: "chevron.left", label: "Home") {
                haptics.stop()
                motion.stop()
                model.goHome()
            }
            Spacer()
            timerChip
            Spacer()
            GlassIconButton(
                symbol: "pencil",
                label: "Pencil marks",
                active: pencilMode,
                accent: accent
            ) {
                pencilMode.toggle()
            }
            GlassIconButton(symbol: "arrow.uturn.backward", label: "Undo") { performUndo() }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 1.2).onEnded { _ in
                        #if DEBUG
                        model.debugFillAlmostAll() // test rig; no-op in Release
                        #endif
                    }
                )
            GlassIconButton(symbol: "gearshape", label: "Settings") { showPrefs = true }
        }
        .padding(model.prefs.controlsAtBottom ? .bottom : .top, 8)
        .padding(.horizontal, 6)
    }

    /// One of the two flexible bands around the board (PRD-2). The band on
    /// the anchored edge collapses — a zero-height element rather than
    /// nothing, so the VStack's 12pt spacing stays symmetric — and all free
    /// space collects in the other band, where a system PiP window can park.
    /// The board anchors to screen edges; the control bar never moves.
    @ViewBuilder
    private func band(_ edge: VerticalEdge, freeSpace: CGFloat) -> some View {
        let anchor = model.prefs.boardAnchor
        if (anchor == .top && edge == .top) || (anchor == .bottom && edge == .bottom) {
            Spacer().frame(height: 0)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if showAmbient(in: edge, freeSpace: freeSpace) {
                        AmbientSlotView(model: model)
                    }
                }
        }
    }

    /// The ambient chip lives in the band opposite the anchor — opposite the
    /// control bar when centered, so turning it on is never a silent no-op —
    /// and only when the band is tall enough and the composing chip (which
    /// overlays at .top) is down.
    private func showAmbient(in edge: VerticalEdge, freeSpace: CGFloat) -> Bool {
        guard model.prefs.ambientSlot != .none, model.composing == nil else { return false }
        let anchor = model.prefs.boardAnchor
        let ambientEdge: VerticalEdge
        switch anchor {
        case .top: ambientEdge = .bottom
        case .bottom: ambientEdge = .top
        case .center: ambientEdge = model.prefs.controlsAtBottom ? .top : .bottom
        }
        guard edge == ambientEdge else { return false }
        // Centered boards split the free space between both bands.
        let bandHeight = anchor == .center ? freeSpace / 2 : freeSpace
        return bandHeight >= 100
    }

    /// While a replacement board is composed (New game in the sheet), the
    /// old board stays up — this chip is the only sign work is happening,
    /// so it matters on Sharp, which can take tens of seconds.
    @ViewBuilder
    private var composingChip: some View {
        if model.composing != nil, model.game != nil {
            GlassChip("Composing…", systemImage: "sparkles")
                .transition(.opacity)
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
                previewDigit: nil, // touch petals are direct — nothing to preview
                previewPencil: false,
                highlightDigit: model.prefs.numberHighlight ? highlightedDigit : nil,
                // Afterglow: the wave detonates from the winning cell, and
                // after the sweep the gyro steers the trophy sheen.
                waveOrigin: model.lastPlacedCell,
                afterglowTilt: { motion.tilt(at: $0) },
                side: side,
                inset: inset
            )
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleBoardTap(at: location, side: side, inset: inset)
            }
            .overlay {
                if let rose, model.solvedAt == nil {
                    let scale = roseScale(side: side)
                    // Scrim: any touch beside the rose cancels it — and blocks
                    // board taps from landing under an open rose.
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
            // Momentary state while a puzzle is composed.
            GlassChip("Composing…", systemImage: "sparkles")
                .frame(height: side)
        }
    }

    /// Petals sized for fingers: a hair wider than a board cell, whatever the
    /// board's size on this screen.
    private func roseScale(side: CGFloat) -> CGFloat {
        let cell = side / 9
        return min(0.62, (cell * 1.15) / 116)
    }

    /// The rose blooms on the selected cell, nudged inward so no petal ever
    /// leaves the board frame (screen edges would otherwise clip it).
    private func rosePosition(side: CGFloat, inset: CGFloat, scale: CGFloat) -> CGPoint {
        let center = BoardMetrics.center(of: cursor, side: side)
        let radius = 126 * scale + (116 * scale) / 2
        let frameSide = side + 2 * inset
        let clamp: (CGFloat) -> CGFloat = { value in
            min(max(value, radius - 6), frameSide - radius + 6)
        }
        return CGPoint(x: clamp(center.x + inset), y: clamp(center.y + inset))
    }

    // MARK: Touch grammar

    private func handleBoardTap(at location: CGPoint, side: CGFloat, inset: CGFloat) {
        guard let game = model.game, model.solvedAt == nil, rose == nil else { return }
        let boardPoint = CGPoint(x: location.x - inset, y: location.y - inset)
        guard let cell = BoardMetrics.cellIndex(at: boardPoint, side: side) else { return }
        cursor = cell
        // Tap a placed digit → light up all of its kind (notes included).
        // Tap it again → lights off. Givens are finally tappable: they're
        // the natural handles for "show me every 9".
        let digit = game.entry(at: cell)
        if digit != 0, model.prefs.numberHighlight {
            withAnimation(.couchFast) {
                highlightedDigit = (highlightedDigit == digit) ? nil : digit
            }
        }
        openRose()
    }

    private func openRose() {
        guard let game = model.game, !game.isGiven(cursor) else { return }
        // Notes only make sense in empty cells; a filled cell opens the
        // normal rose even in pencil mode (same rule as tvOS hold-click).
        let pencil = pencilMode && game.entry(at: cursor) == 0
        withAnimation(.couchFast) {
            rose = RoseState(pencil: pencil)
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

// MARK: - Chrome atoms

/// The one optional ambient element (PRD-2): a dim, non-interactive chip
/// centered in the free band. Deliberately inert — no transitions, taps pass
/// through to whatever is behind; the minute tick is a plain text swap and
/// the streak text only changes on solve, so nothing moves during play.
private struct AmbientSlotView: View {
    let model: AppModel

    var body: some View {
        Group {
            switch model.prefs.ambientSlot {
            case .none:
                EmptyView()
            case .clock:
                TimelineView(.everyMinute) { timeline in
                    GlassChip(
                        timeline.date.formatted(date: .omitted, time: .shortened),
                        systemImage: "clock"
                    )
                }
            case .streak:
                GlassChip(streakText, systemImage: "flame")
            }
        }
        .opacity(0.5)
        .allowsHitTesting(false)
    }

    /// Mirrors the home header: each part appears once it's nonzero.
    private var streakText: String {
        var parts: [String] = []
        if model.totalPoints > 0 { parts.append("\(model.totalPoints) pts") }
        if model.displayedStreak > 0 { parts.append("\(model.displayedStreak) day streak") }
        return parts.isEmpty ? "No solves yet" : parts.joined(separator: " · ")
    }
}

/// A circular glass icon button sized for fingers (44pt minimum hit target).
struct GlassIconButton: View {
    let symbol: String
    let label: String
    var active = false
    var accent: Color = .white
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                .frame(width: 44, height: 44)
                .couchGlassInteractive(in: Circle())
                .overlay {
                    Circle().strokeBorder(accent.opacity(active ? 0.8 : 0), lineWidth: 2)
                }
        }
        .buttonStyle(TouchCardStyle())
        .accessibilityLabel(label)
    }
}
#endif
