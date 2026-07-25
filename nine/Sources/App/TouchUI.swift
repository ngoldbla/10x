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
    @State private var showBoards = false
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
                    boardsSection
                    freePlayRow
                    // UX audit home-inline prototypes (rec 10, rec 9).
                    if UXDemo.active == .nocturne { nocturneCard }
                    if UXDemo.active == .variants { variantsTeaser }
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
        .overlay { GlassSheet(isPresented: $showBoards) { BoardsSheetContent(model: model, onClose: { showBoards = false }) } }
        .overlay {
            if showTutorial {
                TutorialView(accent: accent) {
                    showTutorial = false
                }
                .transition(.opacity)
            }
        }
        .animation(.couchFast, value: showTutorial)
        // UX audit prototypes: a no-op unless a -uxdemo.* launch flag is set.
        .overlay { UXDemoLayer(model: model) }
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
                BoardFingerprint(game: daily, accent: accent, side: 34)
                Text("Continue · \(BoardProgressCaption.text(for: daily))")
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
                    BoardFingerprint(game: game, accent: accent, side: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Continue")
                            .font(CouchTypography.body)
                        Text("\(difficulty.title) · \(BoardProgressCaption.text(for: game))"
                             + (model.extraPartialCount > 0 ? " · +\(model.extraPartialCount) more" : ""))
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

    // MARK: Boards tracker

    /// Partials not already surfaced by the Today card (in-progress daily) or
    /// the Continue card (newest free partial) — the "extra" boards.
    private var extraPartials: [LibraryEntry] {
        let today = model.todayOrdinal
        let continueID = model.freePartials.first?.id
        return model.partials.filter { entry in
            if entry.id == continueID { return false }
            if case .daily(let day) = entry.kind, day == today { return false }
            return true
        }
    }

    @ViewBuilder
    private var boardsSection: some View {
        if !extraPartials.isEmpty || !model.playedBoards.isEmpty {
            VStack(spacing: 10) {
                HStack {
                    Text("Boards")
                        .font(CouchTypography.body)
                    Spacer()
                    Button { showBoards = true } label: {
                        Text("See all")
                            .font(CouchTypography.caption)
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all boards")
                }
                ForEach(extraPartials.prefix(3)) { entry in
                    TouchCard(action: { model.resumeEntry(id: entry.id) }) {
                        HStack(spacing: 14) {
                            BoardFingerprint(game: entry.game, accent: accent, side: 34)
                            Text(boardTitle(entry))
                                .font(CouchTypography.caption)
                            Spacer()
                            Text(BoardProgressCaption.text(for: entry.game))
                                .font(CouchTypography.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func boardTitle(_ entry: LibraryEntry) -> String {
        switch entry.kind {
        case .daily: return "Daily · \(entry.createdAt.formatted(date: .abbreviated, time: .omitted))"
        case .free(let difficulty): return difficulty.title
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

    // MARK: UX audit prototypes (home-inline)

    /// rec 10 — a fourth difficulty (X-wings and worse), a calm equal to the
    /// other three cards; identity comes from a moon glyph, not a lock.
    private var nocturneCard: some View {
        TouchCard(action: {}) {
            HStack(spacing: 16) {
                DemoNocturneBoard(accent: accent)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nocturne")
                        .font(CouchTypography.body)
                    Text("X-wings, chains — the deep end.")
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "moon.stars")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// rec 9 — a calm teaser for upcoming variant modes.
    private var variantsTeaser: some View {
        TouchCard(action: {}) {
            HStack(spacing: 16) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Killer · Thermo")
                        .font(CouchTypography.body)
                    Text("New variants, coming soon.")
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
    /// Pull-down stats drawer (PRD-10 follow-up). Snapped-open state, the
    /// live finger offset on top of it, and the panel's measured height —
    /// the three together give `drawerProgress`, which drives every pixel.
    @State private var drawerOpen = false
    /// Gesture-owned, not `@State`: SwiftUI restores it on cancellation as
    /// well as on end, and a pull-down that starts at the screen edge is
    /// exactly the stroke Notification Center likes to steal mid-flight —
    /// which delivers no `onEnded` and would strand a half-open scrim.
    @GestureState private var drawerDrag: CGFloat = 0
    /// Placeholder until the panel reports its real height. Only read while
    /// the drawer is visible, and by then the measurement has landed.
    @State private var drawerHeight: CGFloat = 220
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
            // The grabber sits *under* the drawer it advertises, so the panel
            // slides over it rather than the hairline floating on the glass.
            .overlay(alignment: .top) { drawerGrabber }
            // Above the board and its chips, below the prefs sheet — Settings
            // must always stack over the drawer, never under it.
            .overlay(alignment: .top) { statsDrawer }
            // Attached *above* the drawer overlay, so the drawer's own scrim
            // is a child of the gesture rather than a lid over it — one
            // gesture drives both the pull-down and the drag-up dismiss.
            // The flexible bands around the board are `Color.clear`, which
            // SwiftUI does not hit-test, so without a content shape the whole
            // reveal band is a hole and the pull-down never starts. Claiming
            // the frame costs nothing: children (board, control bar, scrim)
            // are hit-tested first, and nothing else wants the empty space.
            .contentShape(Rectangle())
            // Simultaneous, not a blocking strip across the top: a hit-testing
            // overlay there would swallow control-bar taps whenever the bar is
            // the top row (`controlsAtBottom == false`).
            .simultaneousGesture(drawerRevealGesture)
            // The drawer is otherwise reachable only by an unhinted pull-down,
            // so VoiceOver gets a named action. It must honour the same guards
            // as the drag: opening it under the prefs sheet would scrim the
            // screen from below, and opening it with no game would measure a
            // height off an empty panel.
            .accessibilityAction(named: drawerOpen ? "Hide board stats" : "Show board stats") {
                guard drawerOpen || (rose == nil && !showPrefs && model.game != nil) else { return }
                if !drawerOpen { model.noteDrawerFound() }
                withAnimation(.couchFast) { drawerOpen.toggle() }
            }
            .overlay {
                // PRD-34: no `onNewGame` — the next board lives on the shelf,
                // in the Boards sheet, and in the post-solve "Another" chip.
                GlassSheet(isPresented: $showPrefs) {
                    PrefsSheetContent(model: model)
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

    /// PRD-34. "New game" used to live only at the bottom of Settings, which
    /// is nobody's guess for where the next board is. One of its three new
    /// homes is right here: once the Afterglow has settled — never during it —
    /// the solved chip is joined by an "Another" that starts a fresh board at
    /// the difficulty you just finished. Free-play boards only; the daily is
    /// one a day, and offering "another" one would be a lie.
    @ViewBuilder
    private var completionChip: some View {
        if let solvedAt = model.solvedAt {
            TimelineView(.periodic(from: solvedAt, by: 0.5)) { timeline in
                if timeline.date.timeIntervalSince(solvedAt) > 2.4 {
                    HStack(spacing: 10) {
                        GlassChip(completionText, systemImage: "checkmark")
                        if case .free(let difficulty)? = model.kind {
                            Button {
                                highlightedDigit = nil
                                model.startFree(difficulty)
                            } label: {
                                GlassChip("Another", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Another \(difficulty.title) board")
                        }
                    }
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

    // MARK: Stats drawer

    /// 0 = hidden, 1 = fully open. The snapped state plus whatever the finger
    /// is currently adding, clamped — so the panel tracks the drag one-to-one
    /// and every derived value (scrim alpha, panel offset) reads from here.
    private var drawerProgress: CGFloat {
        guard drawerHeight > 0 else { return 0 }
        return min(1, max(0, ((drawerOpen ? drawerHeight : 0) + drawerDrag) / drawerHeight))
    }

    /// Height of the band at the top of the screen a pull-down may start in.
    /// Deep enough to catch a deliberate downward drag, shallow enough that
    /// the board's first row is mostly clear of it.
    private static let drawerRevealBand: CGFloat = 100
    /// Projected-open fraction past which the drawer snaps open on release.
    private static let drawerSnapThreshold: CGFloat = 0.35

    /// May this stroke steer the drawer? `startLocation` is fixed for the
    /// whole drag, so this answers identically on every update and again at
    /// the end — which is why the gesture needs no "already claimed" flag.
    private func acceptsDrawerDrag(_ value: DragGesture.Value) -> Bool {
        guard rose == nil, !showPrefs, model.game != nil else { return false }
        // Once open, the whole screen steers it (that is the drag-up
        // dismiss); closed, the stroke has to begin in the top band.
        return drawerOpen || value.startLocation.y <= Self.drawerRevealBand
    }

    private var drawerRevealGesture: some Gesture {
        // 12pt so a sloppy tap on a board cell never twitches the drawer open;
        // the board is tap-only, so nothing else on this screen wants a drag.
        DragGesture(minimumDistance: 12)
            .updating($drawerDrag) { value, offset, _ in
                guard acceptsDrawerDrag(value) else { return }
                offset = value.translation.height
            }
            .onEnded { value in
                guard acceptsDrawerDrag(value) else { return }
                // Project the flick so a fast short swipe still opens it.
                let projected = ((drawerOpen ? drawerHeight : 0)
                                 + value.predictedEndTranslation.height) / drawerHeight
                let opening = projected > Self.drawerSnapThreshold
                if opening { model.noteDrawerFound() }
                withAnimation(.couchFast) { drawerOpen = opening }
            }
    }

    private func closeDrawer() {
        withAnimation(.couchFast) { drawerOpen = false }
    }

    /// PRD-34. The drawer was shipped deliberately unhinted, and the live sim
    /// audit found the predictable result: nothing on screen suggests it
    /// exists, so nobody pulls. The compromise that keeps the calm is a 3pt
    /// hairline — the smallest mark that reads as a handle — shown for the
    /// first three sessions, and retired the moment the player opens the
    /// drawer once. After that the top of the screen is bare again forever.
    ///
    /// It is decoration only: it is not a button, and it is hidden from
    /// VoiceOver, which has had a named action for the drawer since PRD-10.
    @ViewBuilder
    private var drawerGrabber: some View {
        if model.showsDrawerGrabber, model.game != nil, rose == nil, !showPrefs {
            Capsule()
                .fill(.secondary)
                .frame(width: 36, height: 3)
                .opacity(0.35 * (1 - drawerProgress))
                .padding(.top, 6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Mirrors `GlassSheet`'s grammar — 0.45 black scrim, `couchGlass` on a
    /// 28pt continuous rounded rect — but presented off an interactive offset
    /// instead of a boolean transition, so it follows the finger.
    @ViewBuilder
    private var statsDrawer: some View {
        let progress = drawerProgress
        if progress > 0 {
            ZStack(alignment: .top) {
                Color.black.opacity(0.45 * progress)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeDrawer() }
                StatsDrawerContent(model: model)
                    .padding(18)
                    .frame(maxWidth: 480)
                    .couchGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, 10)
                    // Measured before the offset — the panel's real height is
                    // what the drag maps onto, whatever the stats add up to.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        drawerHeight = max(1, height)
                    }
                    .offset(y: -drawerHeight * (1 - progress))
            }
        }
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
                inset: inset,
                axActions: axActions
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
                        onDigit: { commit(digit: $0) },
                        showsErase: !rose.pencil
                            && !game.isGiven(cursor)
                            && game.entry(at: cursor) != 0,
                        onErase: { eraseCurrentCell() }
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
        let showsErase = model.game.map {
            !$0.isGiven(cursor) && $0.entry(at: cursor) != 0
                && !(pencilMode && $0.entry(at: cursor) == 0)
        } ?? false
        let bottomExtra = showsErase ? 126 * scale * 0.92 : 0
        let frameSide = side + 2 * inset
        let clampX: (CGFloat) -> CGFloat = { value in
            min(max(value, radius - 6), frameSide - radius + 6)
        }
        let clampY: (CGFloat) -> CGFloat = { value in
            min(max(value, radius - 6), frameSide - radius - bottomExtra + 6)
        }
        return CGPoint(x: clampX(center.x + inset), y: clampY(center.y + inset))
    }

    // MARK: Accessibility grammar (PRD-19)

    /// The board's VoiceOver actions, mirroring the touch grammar exactly:
    /// the same nine digits the rose offers, the same pencil toggle from the
    /// control bar, the same erase that only appears on a filled cell. Nil
    /// action closures once the board is solved, which turns the 81 elements
    /// read-only rather than offering moves `AppModel` would refuse.
    private var axActions: BoardAXActions {
        guard model.solvedAt == nil else {
            return BoardAXActions(select: { cursor = $0 })
        }
        return BoardAXActions(
            pencilMode: pencilMode,
            select: { cursor = $0 },
            place: { digit, cell in axCommit(digit, at: cell, pencil: false) },
            note: { digit, cell in axCommit(digit, at: cell, pencil: true) },
            erase: { cell in
                guard let game = model.game, game.entry(at: cell) != 0 else { return }
                let digit = game.entry(at: cell)
                cursor = cell
                closeRose()
                if model.erase(at: cell) { announce(BoardSpeech.eraseAnnouncement(digit: digit)) }
            }
        )
    }

    /// One digit, committed the way the rose would commit it. Announcing the
    /// result is the whole point: without it VoiceOver re-reads the focused
    /// cell and a player never learns that the fourth 4 was their last.
    private func axCommit(_ digit: Int, at cell: Int, pencil: Bool) {
        guard let game = model.game, model.solvedAt == nil, !game.isGiven(cell) else { return }
        cursor = cell
        closeRose()
        if pencil {
            let wasSet = game.pencilDigits(at: cell).contains(digit)
            model.togglePencil(digit, at: cell)
            announce(BoardSpeech.noteAnnouncement(digit: digit, added: !wasSet))
        } else {
            model.place(digit, at: cell)
            hapticsAfterPlacing(at: cell)
            guard let after = model.game else { return }
            announce(model.solvedAt != nil
                     ? BoardSpeech.solvedAnnouncement
                     : BoardSpeech.placementAnnouncement(digit: digit, in: after))
        }
    }

    private func announce(_ message: String) {
        guard !message.isEmpty else { return }
        AccessibilityNotification.Announcement(message).post()
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
            hapticsAfterPlacing(at: cursor)
        }
        closeRose()
    }

    /// The in-play haptic mark for a placement (PRD-21). Both commit paths —
    /// the rose and the VoiceOver actions rotor — funnel through here so the
    /// two grammars feel identical in the hand.
    ///
    /// Two suppressions matter. On the solving placement the crescendo is
    /// already queued by `onChange(of: model.solvedAt)`, and a tick under its
    /// first beat just muddies it. And the error knock is gated on the error
    /// *highlight* pref: a knock the screen is not also showing would leak,
    /// through the fingertips, an answer the player asked not to be told.
    private func hapticsAfterPlacing(at cell: Int) {
        guard model.prefs.touchHaptics, model.solvedAt == nil,
              let game = model.game else { return }
        if model.prefs.errorHighlight, game.isError(at: cell) {
            haptics.playError()
        } else {
            haptics.playPlacement()
        }
    }

    private func eraseCurrentCell() {
        _ = model.erase(at: cursor)
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
                // Non-interactive glass: the Button + TouchCardStyle press-scale
                // already gives feedback. Interactive Liquid Glass ran its own
                // touch handling that competed with the Button's tap recognizer,
                // making Home/pencil/undo/gear unresponsive (mirrors the working
                // macOS chip pattern). At rest the two variants look identical.
                .couchGlass(in: Circle())
                .overlay {
                    Circle().strokeBorder(accent.opacity(active ? 0.8 : 0), lineWidth: 2)
                }
                // PRD-19 / craft charter: without this, SwiftUI derives the
                // accessibility frame from the SF Symbol's tight glyph bounds,
                // not the 44pt button — the live audit measured the Home
                // chevron at 9×15pt. Switch Control and Voice Control target
                // that rectangle literally, so the visual hit area and the
                // assistive one have to be the same 44pt circle.
                .contentShape(.accessibility, Circle())
        }
        .buttonStyle(TouchCardStyle())
        .accessibilityLabel(label)
    }
}
#endif
