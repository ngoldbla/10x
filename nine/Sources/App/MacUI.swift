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

// The keyboard grammar itself now lives in `BoardKeys.swift`, compiled for iOS
// as well: a Magic Keyboard on an iPad had none of the table above, and the
// cheapest way to give it all of them was to delete the platform fence rather
// than write a second copy that would drift.

// MARK: - Menu ↔ focused view actions

/// Actions the menu bar routes back into the focused game screen (so the
/// Undo toast, which lives in view state, still shows). Published via
/// `focusedSceneValue`; a nil value greys the menu item out.
///
/// PRD-33 asks for "a real menu bar with every command", and every command means
/// the *board's* commands too — which are all view state, not model state. The
/// cursor lives in `MacGameScreen`, so a Board menu cannot reach it any other
/// way, and a nil closure greying the row out is exactly right when no board is
/// on screen. This is the same channel the Undo row has used since PRD-4, widened
/// rather than replaced.
struct NineFocusActions {
    var performUndo: (@MainActor () -> Void)? = nil
    /// ⌥-click's twin (PRD-25's Mac door, PRD-33's keyboard one). Pointer idioms
    /// are not discoverable and a menu row with a shortcut beside it is.
    var askWhy: (@MainActor () -> Void)? = nil
    /// PRD-11's coach hint. The Mac has never had one — `MacUI` says so at the
    /// top of `MacGameScreen` — and a menu row is the cheapest surface that does
    /// not add chrome to a board someone is thinking over.
    var showHint: (@MainActor () -> Void)? = nil
    var toggleAutoNotes: (@MainActor () -> Void)? = nil
    var toggleStickyPencil: (@MainActor () -> Void)? = nil
    var erase: (@MainActor () -> Void)? = nil
    var nextEmpty: (@MainActor (Bool) -> Void)? = nil
    /// Whether sticky pencil is on, so the menu can show a checkmark rather than
    /// a verb whose current state you have to guess.
    var pencilOn: Bool = false
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
            // The wordmark, not a word — see `ShareCardMetrics.wordmark`.
            Text(verbatim: Phrase.wordmark)
                .couchText(CouchTypography.title)
            Spacer()
            if model.totalPoints > 0 {
                GlassChip(Phrase.points(model.totalPoints), systemImage: "star.fill")
            }
            if model.displayedStreak > 0 {
                // A Focus filter can take the count away entirely (PRD-33).
                // `if` rather than `.opacity(0)`: an invisible chip still holds
                // its space and still speaks to VoiceOver.
                if !model.focus.hidesStreak {
                    StreakChip(days: model.displayedStreak, held: model.streakHeld)
                }
            }
        }
        .padding(.top, 8)
    }

    private var todayCard: some View {
        MacCard(action: { model.openToday() }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Strings.string("shelf.today.title"))
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
            statusLabel(Strings.string("status.composing"), symbol: "sparkles")
        } else if model.todaySolved {
            statusLabel(Strings.string("status.solved"), symbol: "checkmark.circle.fill")
        } else if let daily = model.savedDaily {
            HStack(spacing: 12) {
                GlassRing(progress: daily.fillFraction, lineWidth: 5)
                    .frame(width: 34, height: 34)
                Text(Strings.string("shelf.continue.title"))
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            statusLabel(Strings.string("shelf.today.oneADay"), symbol: "sun.max")
        }
    }

    private func continueCard(game: NineGame, difficulty: Difficulty) -> some View {
        MacCard(action: { model.continueSaved() }) {
            HStack(spacing: 16) {
                GlassRing(progress: game.fillFraction, lineWidth: 5)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.string("shelf.continue.title"))
                        .font(CouchTypography.body)
                    Text(Phrase.continueCaption(
                        difficulty: Strings.difficulty(difficulty),
                        progress: BoardProgressCaption.text(for: game),
                        others: model.extraPartialCount))
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
                .accessibilityLabel(Strings.string("shelf.continue.discard"))
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
                            statusLabel(difficulty.composeCaption
                                            ?? Strings.string("status.composing"),
                                        symbol: "sparkles")
                        } else {
                            Label {
                                Text(Strings.difficulty(difficulty))
                            } icon: {
                                if let glyph = difficulty.glyph { Image(systemName: glyph) }
                            }
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
                // A compose in flight makes `AppModel.compose` refuse the next
                // request. Sub-second that was invisible; at Nocturne's measured
                // tail it is a shelf that ignores clicks. Same rule as iOS.
                .disabled(model.composing != nil && model.composing != .free(difficulty))
            }
        }
    }

    private var learnRow: some View {
        HStack(spacing: 14) {
            MacCard(action: { model.macShowTutorial = true }) {
                learnTile(symbol: "questionmark.circle",
                          title: Strings.string("tutorial.title"))
            }
            MacCard(action: { model.macShowBoards = true }) {
                learnTile(symbol: "square.stack.3d.up",
                          title: Strings.string("boards.title"))
            }
            MacCard(action: { openWindow(id: "history") }) {
                learnTile(symbol: "trophy", title: Strings.string("history.title"))
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
    /// The rendered share card (PRD-12); nil while rendering, and nil for
    /// good if it failed — in which case the button never appears.
    @State private var shareCard: ShareCardExport?
    @State private var highlightedDigit: Int?
    @State private var hoverCell: Int?
    /// PRD-25's why-chain, and its refusal. The Mac's first coach surface of
    /// any kind — PRD-11 §3 deferred the hint card here, and this arrives
    /// instead because ⌥-click is a pointer idiom that needs no chrome.
    @State private var why: WhyNarration?
    @State private var whyRefusal: WhyRefusal?
    /// PRD-11's coach hint, reaching the Mac with PRD-33's menu bar.
    @State private var coachAdvice: CoachAdvice?
    @State private var deskHovering = false
    /// The Mac's trophy tilt: the pointer steers the sheen (PRD-4 §2.6).
    @State private var pointer = AfterglowPointer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    /// The board's own ink, so the rose's petal numerals are the same colour as
    /// the digits they will become (PRD-22's `digitTone`). Computed here rather
    /// than threaded, exactly as `accent` above is.
    private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }
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
            .overlay(alignment: .bottom) { whyView.padding(.bottom, isDesk ? 12 : 28) }
            .overlay(alignment: .bottom) { coachView.padding(.bottom, isDesk ? 12 : 28) }
            .overlay(alignment: .bottom) { completionChip.padding(.bottom, isDesk ? 40 : 72) }
            .onChange(of: model.solvedAt) { renderShareCard() }
            .overlay(alignment: .top) { composingChip.padding(.top, isDesk ? 8 : 16) }
            .overlay(alignment: .bottomTrailing) { if isDesk { deskCornerGlyph.padding(10) } }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($boardFocused)
        // The whole Board menu, routed through the one channel that can reach view
        // state (PRD-33). Each closure is nil-able at the source rather than
        // guarded at the call site, because a nil closure is what greys the row.
        .focusedSceneValue(\.nineActions, NineFocusActions(
            performUndo: performUndo,
            askWhy: askWhyAtCursor,
            showHint: toggleCoach,
            toggleAutoNotes: toggleAutoNotes,
            toggleStickyPencil: { pencilMode.toggle() },
            erase: { _ = model.erase(at: cursor) },
            nextEmpty: { forward in
                guard let game = model.game else { return }
                cursor = BoardMetrics.nextEmptyCell(from: cursor, in: game, forward: forward)
            },
            pencilOn: pencilMode
        ))
        .onKeyPress { press in handleKey(press) ? .handled : .ignored }
        .onHover { deskHovering = $0 }
        // The keyboard is the superpower (PRD-4 §2.2): the board claims key
        // focus the moment it appears — and again when the window swaps
        // between full and desk chrome — so digits always type. Without this
        // the surface is focusable but never focused, and every plain key
        // falls through (the §5 "focus wars" risk, observed in validation).
        .onAppear { boardFocused = true }
        .onChange(of: isDesk) { boardFocused = true }
        // A derivation describes one position, and its whole subject is what a
        // square's candidates are right now. Any move makes it stale.
        .onChange(of: model.game?.entries) { _, _ in dismissWhy() }
        .onDisappear {
            why = nil
            whyRefusal = nil
        }
    }

    // MARK: Chrome

    private var homeChip: some View {
        Button { model.goHome() } label: {
            // "Home", not "Shelf" — the shelf is TV vocabulary; the Mac home
            // is a card grid in a window.
            GlassChip(Strings.string("game.control.home"), systemImage: "chevron.left")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.string("game.mac.homeLabel"))
    }

    @ViewBuilder
    private var statusChips: some View {
        HStack(spacing: 10) {
            if pencilMode {
                GlassChip(Strings.string("game.chip.pencil"), systemImage: "pencil")
            }
            timerChip
        }
    }

    @ViewBuilder
    private var timerChip: some View {
        if model.prefs.showTimer, let game = model.game, model.solvedAt == nil {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                GlassChip(SolveCardFacts.elapsedText(game.timer.elapsed(at: timeline.date)), systemImage: "clock")
            }
        }
    }

    @ViewBuilder
    private var composingChip: some View {
        if model.composing != nil, model.game != nil {
            GlassChip(Strings.string("status.composing"), systemImage: "sparkles")
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
            // Read in the body, never inside the closure — see
            // `TouchUI.completionChip` for the 30-evaluations-of-nil this cost.
            let card = shareCard
            TimelineView(.periodic(from: solvedAt, by: 0.5)) { timeline in
                if timeline.date.timeIntervalSince(solvedAt) > 2.4 {
                    HStack(spacing: 10) {
                        GlassChip(completionText, systemImage: "checkmark")
                        shareButton(card)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private var completionText: String {
        if case .daily? = model.kind, model.displayedStreak > 0 {
            return Strings.string("game.completion.streak", .int(model.displayedStreak))
        }
        return Strings.string("status.solved")
    }

    // MARK: Share (PRD-12)

    /// PRD-12 §3 scopes the share to iOS and allows macOS "if free". It is:
    /// `ShareLink` presents the standard `NSSharingServicePicker` here, and the
    /// card, its facts and its renderer are all cross-platform already — this
    /// file supplies a button and a temp-file URL and nothing else. A Mac
    /// player finishing a board on the same $4.99 purchase would have had no
    /// reason to understand why the phone could share and the Mac could not.
    @ViewBuilder
    private func shareButton(_ card: ShareCardExport?) -> some View {
        if let card {
            ShareLink(item: card.url, preview: SharePreview(shareTitle)) {
                GlassChip(ShareCardPhrase.share, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ShareCardPhrase.shareLabel)
        }
    }

    private var shareTitle: String { shareFacts?.shareTitle ?? ShareCardPhrase.shareLabel }

    /// See `TouchUI.shareFacts` — the same rules, including the archive one:
    /// an archive board never touched the streak, so its card never prints one.
    private var shareFacts: SolveCardFacts? {
        guard let game = model.game, let solvedAt = model.solvedAt else { return nil }
        let isDaily: Bool
        let difficulty: Difficulty
        switch model.kind {
        case .daily?:
            isDaily = true
            difficulty = .steady
        case .free(let d)?:
            isDaily = false
            difficulty = d
        case .channel(_, let tier, let day)?:
            isDaily = day != nil
            difficulty = tier.wireDifficulty
        case nil:
            return nil
        }
        return SolveCardFacts(
            game: game, difficulty: difficulty, isDaily: isDaily,
            streak: model.archiveDay == nil ? model.displayedStreak : 0,
            at: solvedAt
        )
    }

    /// Rendered synchronously on the solve, exactly as on iOS — and see
    /// `TouchUI.renderShareCard` for why it is not a `Task` with a delay in it.
    private func renderShareCard() {
        guard let facts = shareFacts else {
            shareCard = nil
            return
        }
        let tones = model.prefs.theme.tones(for: colorScheme)
        // The same one-chip-two-payloads rule as the phone (PRD-26 §2.4). The
        // Mac has no debrief — a pull-up is a touch gesture and the Mac's
        // answer is a window, which is PRD-33's — but the *card* is the same
        // artifact leaving the same app, and a Mac share that stayed a still
        // while the phone's moved would be two products.
        if let replay = model.currentReplay,
           let loop = ShareCardRenderer.exportLoop(
               facts: facts, replay: replay, tones: tones, accent: accent
           ) {
            shareCard = loop
            return
        }
        shareCard = ShareCardRenderer.export(facts: facts, tones: tones, accent: accent)
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
        .accessibilityLabel(Strings.string("game.mac.exitDesk"))
    }

    // MARK: Board + rose

    @ViewBuilder
    private func boardArea(side: CGFloat, inset: CGFloat) -> some View {
        if let game = model.game {
            let lens = rose.map { roseLens(side: side, inset: inset, rose: $0) }
            BoardView(
                game: game,
                cursor: cursor,
                accent: accent,
                showErrors: model.prefs.errorHighlight,
                solvedAt: model.solvedAt,
                roseOpen: rose != nil,
                roseLens: reduceMotion || model.solvedAt != nil ? nil : lens,
                previewDigit: nil,
                previewPencil: false,
                highlightDigit: model.prefs.numberHighlight ? highlightedDigit : nil,
                coachFocus: why?.focus ?? whyRefusal?.focus,
                hoverCell: model.solvedAt == nil ? hoverCell : nil,
                channelRules: model.currentRules,
                waveOrigin: model.lastPlacedCell,
                afterglowTilt: { pointer.tilt(at: $0) },
                side: side,
                inset: inset,
                axActions: axActions
            )
            .contentShape(Rectangle())
            // ⌥-click asks "why must this be a 7?" (PRD-25 §2.1, and PRD-33's
            // "Mac: ⌥-click why" line). `SpatialTapGesture().modifiers(.option)`
            // is the only gesture in SwiftUI that reports **both** a location
            // and a modifier — `onTapGesture(location:)` reports no modifiers
            // at all, which is why the plain click path below cannot tell the
            // two apart on its own.
            //
            // `highPriorityGesture`, not `simultaneousGesture`: with the option
            // key down this must be the *only* thing that happens, or the click
            // also moves the cursor and blooms the rose over the answer.
            .highPriorityGesture(
                SpatialTapGesture()
                    .modifiers(.option)
                    .onEnded { value in askWhy(at: value.location, side: side, inset: inset) }
            )
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
                if let rose, let lens, model.solvedAt == nil {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { closeRose() }
                    TouchRose(
                        state: rose,
                        accent: accent,
                        completedDigits: Set((1...9).filter { game.isDigitComplete($0) }),
                        scale: lens.scale,
                        onDigit: { commit(digit: $0) },
                        // `currentDigit` is nil in practice — `handleClick`
                        // returns on a filled cell, so the Mac rose only ever
                        // opens over an empty one — and `commit` carries the
                        // matching erase branch anyway, so the rim and the tap
                        // cannot come apart if that ever changes.
                        //
                        // `notedDigits` is the half that really fires here:
                        // the rose opens in pencil mode on an empty cell
                        // (`handleClick`), that cell can already carry marks,
                        // and `commit`'s `togglePencil` erases one on a second
                        // tap. Without this the Mac would toggle notes off with
                        // no indication which ones were on.
                        currentDigit: game.isGiven(cursor) || game.entry(at: cursor) == 0
                            ? nil : game.entry(at: cursor),
                        notedDigits: Set(game.pencilDigits(at: cursor)),
                        digitTone: tones.digitTone
                    )
                    .position(x: lens.viewCentre.x, y: lens.viewCentre.y)
                }
            }
        } else {
            GlassChip(Strings.string("status.composing"), systemImage: "sparkles")
                .frame(width: side, height: side)
        }
    }

    /// Where the petals are drawn, and — through `BoardView.roseLens` — where
    /// the board bends under them (PRD-22). The Mac rose never opens on a
    /// filled cell at all (`handleClick` below returns on one instead), so ⌫
    /// stays the way a placed digit is cleared here; the erase-your-own-petal
    /// grammar reaches this surface through *pencil* mode, where the rose does
    /// open and a noted digit's petal toggles itself off. See the `TouchRose`
    /// mount above for which half of it is live.
    private func roseLens(side: CGFloat, inset: CGFloat, rose: RoseState) -> RoseLens {
        RoseLens(
            cursor: cursor,
            side: Double(side),
            inset: Double(inset),
            pencil: rose.pencil,
            scale: RoseLens.scale(forSide: Double(side))
        )
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

    // MARK: Why must this be a seven? (PRD-25)

    /// Empty cells only, exactly as on touch: a filled square has no candidates
    /// left to argue about, and the gesture stays silent rather than saying so.
    private func askWhy(at location: CGPoint, side: CGFloat, inset: CGFloat) {
        guard let game = model.game, model.solvedAt == nil, rose == nil else { return }
        let point = CGPoint(x: location.x - inset, y: location.y - inset)
        guard let cell = BoardMetrics.cellIndex(at: point, side: side),
              game.entry(at: cell) == 0 else { return }
        cursor = cell
        askWhy(atCell: cell)
    }

    /// The same question from the keyboard or the Board menu (PRD-33). ⌥-click has
    /// worked since PRD-25 and is undiscoverable by construction — a pointer idiom
    /// with a modifier has no affordance anywhere — so the derivation now also has
    /// a menu row with a shortcut printed beside it.
    private func askWhyAtCursor() {
        askWhy(atCell: cursor)
    }

    private func askWhy(atCell cell: Int) {
        guard let game = model.game, model.solvedAt == nil, rose == nil,
              game.entry(at: cell) == 0 else { return }
        cursor = cell
        guard let outcome = model.requestDerivation(forCell: cell) else { return }
        dismissCoach()
        withAnimation(.couchFast) {
            switch outcome {
            case .success(let derivation):
                why = WhyNarration(derivation)
                whyRefusal = nil
            case .failure(let refusal):
                why = nil
                whyRefusal = WhyRefusal(refusal: refusal)
            }
        }
        announceWhy()
    }

    /// VoiceOver hears the beat it cannot see the board light up. iOS has done
    /// this since PRD-25 (`TouchUI.announceWhy`) and the Mac has not — the half of
    /// ⌥-click that was genuinely missing rather than merely undiscoverable. Same
    /// join, through the same keys, so a screen reader is told the sentence the
    /// card shows rather than a second spelling of it.
    private func announceWhy() {
        if let beat = why?.beat {
            announce(CoachCardLabel.spoken(
                title: BoardSpeech.coachTitle(.step(beat.coach)),
                sentence: BoardSpeech.coachSentence(.step(beat.coach))))
        } else if let whyRefusal {
            announce(CoachCardLabel.spoken(title: whyRefusal.title,
                                           sentence: whyRefusal.sentence))
        }
    }

    // MARK: The coach (PRD-11, arriving on the Mac with PRD-33)

    /// The Mac's hint. No lightbulb button: the sixth control the touch bar has
    /// would be a fifth button here, and the covenant forbids one. A menu row and
    /// a shortcut cost the board no pixels at all.
    private func toggleCoach() {
        guard model.game != nil, model.solvedAt == nil else { return }
        guard coachAdvice == nil else { return dismissCoach() }
        guard let advice = model.requestCoachAdvice() else { return }
        dismissWhy()
        withAnimation(.couchFast) { coachAdvice = advice }
        announce(CoachCardLabel.spoken(title: BoardSpeech.coachTitle(advice),
                                       sentence: BoardSpeech.coachSentence(advice)))
    }

    private func dismissCoach() {
        guard coachAdvice != nil else { return }
        withAnimation(.couchFast) { coachAdvice = nil }
    }

    @ViewBuilder
    private var coachView: some View {
        if let coachAdvice {
            CoachCardContent(
                advice: coachAdvice,
                accent: accent,
                actionTitle: coachAdvice.actionTitle(autoNotes: model.autoNotes)
            ) {
                if case .step(let step) = coachAdvice { model.applyCoachStep(step) }
                dismissCoach()
            }
        }
    }

    /// Auto-notes, the wand's Mac twin. No chip: the touch chip exists because a
    /// thumb cannot see the whole board at once, and a Mac window can.
    private func toggleAutoNotes() {
        guard model.game != nil, model.solvedAt == nil else { return }
        model.autoNotes = !model.autoNotes
    }

    private func advanceWhy() {
        guard var running = why else { return }
        running.advance()
        withAnimation(.couchFast) { why = running }
        announceWhy()
    }

    private func dismissWhy() {
        guard why != nil || whyRefusal != nil else { return }
        withAnimation(.couchFast) {
            why = nil
            whyRefusal = nil
        }
    }

    @ViewBuilder
    private var whyView: some View {
        if let why {
            WhyCardContent(narration: why, accent: accent, onNext: advanceWhy) {
                model.place($0.digit, at: $0.cell)
                dismissWhy()
            }
        } else if let whyRefusal {
            WhyRefusalContent(refusal: whyRefusal, accent: accent)
        }
    }

    private func closeRose() {
        withAnimation(.couchFast) { rose = nil }
    }

    private func commit(digit: Int) {
        guard let state = rose else { return }
        if state.pencil {
            model.togglePencil(digit, at: cursor)
        } else if model.game?.entry(at: cursor) == digit {
            // Same branch `TouchGameScreen.commit` carries: a petal whose digit
            // is already in the cell draws the dashed rim and says "Erase 5",
            // so it has to erase. Unreachable today — `handleClick` returns on
            // a filled cell, so the Mac rose never opens over one — but the
            // petal's label and the petal's effect must not be able to
            // disagree, and leaving this out is what would let them.
            _ = model.erase(at: cursor)
        } else {
            model.place(digit, at: cursor)
        }
        closeRose()
    }

    // MARK: Accessibility grammar (PRD-19)

    /// The same nine digits the keyboard and the rose offer, exposed to
    /// VoiceOver as per-cell actions. Full Keyboard Access already reaches the
    /// board through `handleKey`; this is the screen-reader half.
    ///
    /// Activation stays cursor-only for *every* assistive technology here,
    /// unlike iOS: macOS Voice Control can say "Press 5" and `handleKey` places
    /// it, so the Mac already has a non-rotor door to the digits and does not
    /// need activation to bloom the rose. See `TouchGameScreen.axActivate` for
    /// the iOS case, where the rose is the only door there is.
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
        guard let action = BoardKeys.action(for: press) else { return false }

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
        let next = UndoToastState(text: UndoPhrase.forMove(move))
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

// MARK: - Archive window (⌥⌘A) and School window (⇧⌘E) — PRD-33

/// The daily archive, in a window. Tapping a day routes through the same
/// `openArchiveDay` the iOS sheet uses and the board appears in the *main*
/// window — which is the point of it being a second window rather than a sheet.
struct MacArchiveWindow: View {
    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack {
            VoidBackground()
            ArchiveSheetContent(model: model, onClose: { dismissWindow(id: "archive") })
                .padding(20)
        }
        .frame(minWidth: 380, minHeight: 460)
        .environment(\.nineTheme, model.prefs.theme)
        .preferredColorScheme(model.prefs.theme.colorScheme)
    }
}

/// The Technique School (PRD-25), which has compiled for macOS since it shipped
/// and had no presenter anywhere.
struct MacSchoolWindow: View {
    let model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack {
            VoidBackground()
            SchoolView(
                model: model,
                accent: model.prefs.accent.color(isLight: colorScheme == .light),
                onDismiss: { dismissWindow(id: "school") }
            )
        }
        .frame(minWidth: 460, minHeight: 520)
        .environment(\.nineTheme, model.prefs.theme)
        .preferredColorScheme(model.prefs.theme.colorScheme)
    }
}

// MARK: - Menu-bar extra (PRD-33)

/// The mini board that lives behind the menu-bar glyph.
///
/// **It is deliberately not playable.** A full rose in a 240pt popover would be a
/// worse rose than the one in the window — the petals would be under the minimum
/// target size and the flick would have nowhere to travel — and it would be a
/// second input concept, against a budget of one that this release has otherwise
/// spent nothing of. What it is instead is a *glance* and two doors: how today's
/// board looks, and the two ways back into it.
///
/// The board is drawn with `BoardFingerprint`, the same constellation the shelf
/// uses, for the same reason PRD-22 gave: at this size a grid of digits is a smudge
/// and a constellation is a portrait.
struct MacMenuBarBoard: View {
    let model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let daily = model.savedDaily {
                    BoardFingerprint(game: daily, accent: accent, side: 64)
                } else if let (game, _) = model.savedFree {
                    BoardFingerprint(game: game, accent: accent, side: 64)
                } else {
                    // The honest zero-state (craft charter), not a fake board.
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.tertiary)
                        .frame(width: 64, height: 64)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(Phrase.wordmark)
                        .font(.headline)
                    Text(menuBarStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Divider()
            Button(Strings.string("menu.game.today")) { model.openToday() }
            Button(Strings.string("menu.game.continue")) {
                if let entry = model.library.mostRecentInProgress {
                    model.resumeEntry(id: entry.id)
                }
            }
            .disabled(model.library.mostRecentInProgress == nil)
        }
        .buttonStyle(.plain)
        .padding(16)
        .frame(width: 260)
        .environment(\.nineTheme, model.prefs.theme)
    }

    /// One line, and never a count of days. The menu bar is the surface a player
    /// sees most often without choosing to, so a streak here would be the closest
    /// thing to nagging this app could build — and a Focus filter takes it away
    /// everywhere else already.
    private var menuBarStatus: String {
        if model.todaySolved { return Strings.string("status.solved") }
        if let daily = model.savedDaily, !model.focus.hidesDaily {
            return Strings.string("shelf.today.continueProgress",
                                  .text(BoardProgressCaption.text(for: daily)))
        }
        if model.savedDaily != nil { return Strings.string("shelf.today.title") }
        return Strings.string("shelf.today.oneADay")
    }
}

// MARK: - Menu bar

struct NineCommands: Commands {
    let model: AppModel
    @FocusedValue(\.nineActions) private var actions
    /// The App's own `@State`, threaded down rather than re-read. `@AppStorage`
    /// here would reintroduce the spin the long note at
    /// `NineApp.menuBarExtraShown` records — the loop is closed by *any* source
    /// that republishes while the main menu is being rebuilt, and this menu is
    /// part of that rebuild.
    @Binding var menuBarExtraShown: Bool

    var body: some Commands {
        // Game
        CommandMenu(Strings.string("menu.game.title")) {
            // Driven off `allCases`, not written out: the hand-written list this
            // replaces would have silently shipped a Mac with no way to start a
            // Nocturne board from the menu bar, because a missing `Button` is
            // not a compile error the way a missing `switch` case is.
            Menu(Strings.string("menu.game.newGame")) {
                ForEach(Difficulty.allCases, id: \.self) { difficulty in
                    // ⌘N stays on Steady — it is the "just give me a board"
                    // default, and moving it would retrain a shipped habit.
                    // `.keyboardShortcut` takes no optional, so the branch is on
                    // the modifier rather than on the key.
                    if difficulty == .steady {
                        Button(Strings.difficulty(difficulty)) { model.startFree(difficulty) }
                            .keyboardShortcut("n", modifiers: .command)
                    } else {
                        Button(Strings.difficulty(difficulty)) { model.startFree(difficulty) }
                    }
                }
            }
            Button(Strings.string("menu.game.today")) { model.openToday() }
                .keyboardShortcut("t", modifiers: .command)
            // PRD-33: "continue" is the one door the Mac never had. ⌘N gives you a
            // new board and ⌘T gives you today's; the board you were actually on
            // took a trip through the Boards sheet.
            Button(Strings.string("menu.game.continue")) {
                if let entry = model.library.mostRecentInProgress {
                    model.resumeEntry(id: entry.id)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.library.mostRecentInProgress == nil)
            Divider()
            HistoryMenuButton()
            Button(Strings.string("menu.game.boards")) { model.macShowBoards = true }
                .keyboardShortcut("b", modifiers: .command)
            ArchiveMenuButton()
            Button(Strings.string("school.title")) { model.macShowSchool = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button(Strings.string("menu.game.discard")) { model.discardSaved() }
                .disabled(model.savedFree == nil)
        }

        // Board — the commands that belong to the grid rather than to the app
        // (PRD-33). Its own menu, not rows bolted onto Game: Game is about which
        // board, and this is about what you do to one. Every row routes through
        // `NineFocusActions`, so all of them grey out on the shelf, which is
        // correct and free.
        CommandMenu(Strings.string("menu.board.title")) {
            Button(Strings.string("menu.board.why")) { actions?.askWhy?() }
                .keyboardShortcut("y", modifiers: [.command, .shift])
                .disabled(actions?.askWhy == nil)
            Button(Strings.string("menu.board.hint")) { actions?.showHint?() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(actions?.showHint == nil)
            Divider()
            // A Toggle rather than a verb: "Pencil" with a checkmark says what is
            // true, where "Turn on pencil" makes you remember what you last did.
            Toggle(Strings.string("menu.board.pencil"), isOn: Binding(
                get: { actions?.pencilOn ?? false },
                set: { _ in actions?.toggleStickyPencil?() }
            ))
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(actions?.toggleStickyPencil == nil)
            Toggle(Strings.string("menu.board.autoNotes"), isOn: Binding(
                get: { model.autoNotes },
                set: { _ in actions?.toggleAutoNotes?() }
            ))
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(actions?.toggleAutoNotes == nil)
            Divider()
            Button(Strings.string("menu.board.erase")) { actions?.erase?() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(actions?.erase == nil)
            Button(Strings.string("menu.board.nextEmpty")) { actions?.nextEmpty?(true) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(actions?.nextEmpty == nil)
            Button(Strings.string("menu.board.previousEmpty")) { actions?.nextEmpty?(false) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(actions?.nextEmpty == nil)
        }

        // Edit — replace the stock Undo/Redo so ⌘Z drives the game's toast.
        CommandGroup(replacing: .undoRedo) {
            Button(Strings.string("menu.edit.undo")) { actions?.performUndo?() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(actions?.performUndo == nil || !model.canUndo)
        }

        // View — fold our rows into the *system* View menu rather than adding
        // a CommandMenu("View"), which macOS renders as a second menu titled
        // View beside the stock one (observed in validation).
        CommandGroup(after: .toolbar) {
            Picker(Strings.string("menu.view.appearance"), selection: bind(\.theme)) {
                ForEach(ThemeChoice.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle(Strings.string("menu.view.showTimer"), isOn: bind(\.showTimer))
            Toggle(Strings.string("menu.view.errorHighlight"), isOn: bind(\.errorHighlight))
            Toggle(Strings.string("menu.view.numberHighlight"), isOn: bind(\.numberHighlight))
            Divider()
            Picker(Strings.string("menu.view.accent"), selection: bind(\.accent)) {
                ForEach(AccentChoice.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Divider()
            Button(Strings.string(model.windowMode == .desk
                                  ? "menu.view.exitDesk" : "menu.view.enterDesk")) {
                model.toggleDeskMode()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            Toggle(Strings.string("menu.view.floatDesk"), isOn: Binding(
                get: { model.deskFloating },
                set: { model.deskFloating = $0 }
            ))
            Divider()
            // PRD-33's menu-bar extra, and it is **off by default** — a permanent
            // glyph in the menu bar is the idle-pixel test's most literal subject,
            // and the one surface where a pixel Nine draws is on screen even when
            // Nine is not running.
            Toggle(Strings.string("menu.view.menuBar"), isOn: Binding(
                get: { menuBarExtraShown },
                set: { on in
                    menuBarExtraShown = on
                    // Written here rather than by a property wrapper, so nothing
                    // observes `UserDefaults` during a menu rebuild.
                    UserDefaults.standard.set(on, forKey: NineApp.menuBarExtraKey)
                }
            ))
        }

        // Help
        CommandGroup(replacing: .help) {
            Button(Strings.string("menu.help.howToPlay")) { model.macShowTutorial = true }
            Button(Strings.string("school.title")) { model.macShowSchool = true }
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
        Button(Strings.string("history.title")) { openWindow(id: "history") }
            .keyboardShortcut("y", modifiers: .command)
    }
}

/// The daily archive, which had no Mac surface at all before PRD-33 — and could
/// not have had one, because `ArchiveSheet.swift` was `#if os(iOS)` and did not
/// compile for the Mac. A window rather than an overlay, for the reason PRD-26 and
/// PRD-31 both deferred to this PRD: **the Mac's answer to a second pane is a
/// window.** A calendar you consult while looking at a board is exactly the case.
private struct ArchiveMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(Strings.string("archive.title")) { openWindow(id: "archive") }
            .keyboardShortcut("a", modifiers: [.command, .option])
    }
}

/// Every user-facing literal in this file that is not a menu item, in one
/// block (PRD-20's seam). `MacUI` predates the `Phrase` convention entirely —
/// it was the one file in `Sources/App` with no block at all.
private enum Phrase {
    /// Nine's name, never translated — see `ShareCardMetrics.wordmark`.
    static let wordmark = "Nine"

    static func points(_ total: Int) -> String {
        Strings.string("shelf.points.chip", .int(total))
    }

    /// The same two keys the touch shelf uses. The Mac used to print a bare
    /// `Int(fillFraction * 100)%` where iOS printed `BoardProgressCaption` —
    /// so an untouched board read "Steady · 0%" on the Mac and "Steady ·
    /// Untouched" on the phone, from the same saved board. One caption now.
    static func continueCaption(difficulty: String, progress: String, others: Int) -> String {
        others > 0
            ? Strings.string("shelf.continue.captionMore",
                             .text(difficulty), .text(progress), .int(others))
            : Strings.string("shelf.continue.caption", .text(difficulty), .text(progress))
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
