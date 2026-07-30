// PrefsSheet.swift — the one allowed secondary surface (suite rule): timer
// on/off (off is the default and the statement), error-highlight on/off,
// same-number highlight, haptics, the theme and accent swatches, and on iOS
// control placement and launch resume. Lives inside CouchKit's GlassSheet.
//
// PRD-34 changed two things here. The rows are grouped into four named
// sections — Play / Feel / Appearance / Layout — because the flat list had
// drifted into an order
// nobody could hold in their head (theme at row six, accent at row ten). And
// "New game" left entirely: a live sim audit found it buried at the bottom of
// Settings, which is the last place anyone looks for the next board. Its
// three new homes are the shelf's difficulty cards, the "Fresh board" row at
// the top of the Boards sheet, and an "Another" chip after the Afterglow
// settles.
import SwiftUI
import CouchKit

struct PrefsSheetContent: View {
    let model: AppModel
    /// tvOS only, and only in-game. The TV has no in-game route to the Boards
    /// sheet — it is reachable from the shelf alone — so the couch keeps its
    /// escape hatch here until the TV gets an IA pass of its own. iOS and
    /// macOS pass nil: they have Home in the control bar and the menu bar.
    var onNewGame: (@MainActor (Difficulty) -> Void)? = nil

    var body: some View {
        #if os(tvOS)
        content
        #else
        ScrollView(showsIndicators: false) { content }
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 36 * CouchScale.chrome) {
            // The wordmark, not a word — see `ShareCardMetrics.wordmark`.
            Text(verbatim: Phrase.wordmark)
                .couchText(CouchTypography.title)
                .padding(.bottom, 8)

            // The manual lives here after first run (suite rule: the prefs
            // sheet doubles as the help page).
            #if os(tvOS)
            // Keyed on padSession, not padConnected: the sim's phantom pad
            // reports connected but never adopts, so remote players (and the
            // sim) keep the remote legend.
            ControlLegend(rows: model.padSession ? NineLegend.padCompact : NineLegend.compact)
                .padding(.bottom, 8)
            #elseif os(macOS)
            ControlLegend(rows: NineLegend.keyboardCompact)
                .padding(.bottom, 8)
            #else
            ControlLegend(rows: NineLegend.touchCompact)
                .padding(.bottom, 8)
            #endif

            // PRD-34: five named groups — Play, Feel, Appearance, Layout,
            // About — replacing the flat list the live audit walked, where
            // theme and accent sat four rows apart with resume, haptics and
            // the whole Layout block wedged between them.
            sectionLabel(Strings.string("prefs.section.play"))

            prefRow(
                title: Strings.string("prefs.timer.title"),
                detail: Strings.string(model.prefs.showTimer
                                       ? "prefs.timer.shown" : "prefs.timer.hidden"),
                symbol: model.prefs.showTimer ? "clock.fill" : "clock"
            ) {
                model.prefs.showTimer.toggle()
            }

            prefRow(
                title: Strings.string("prefs.errorHighlight.title"),
                detail: Phrase.onOff(model.prefs.errorHighlight),
                symbol: model.prefs.errorHighlight ? "checkmark.circle.fill" : "circle"
            ) {
                model.prefs.errorHighlight.toggle()
            }

            prefRow(
                title: Strings.string("prefs.numberHighlight.title"),
                detail: Phrase.onOff(model.prefs.numberHighlight),
                symbol: model.prefs.numberHighlight ? "9.square.fill" : "9.square"
            ) {
                model.prefs.numberHighlight.toggle()
            }

            // Resume-on-launch ships on iOS, macOS and tvOS (PRD-4 §2.6,
            // PRD-5 §2.3 parity).
            #if os(iOS) || os(macOS) || os(tvOS)
            prefRow(
                title: Strings.string("prefs.resume.title"),
                detail: Phrase.onOff(model.prefs.resumeOnLaunch),
                symbol: model.prefs.resumeOnLaunch ? "play.circle.fill" : "play.circle"
            ) {
                model.prefs.resumeOnLaunch.toggle()
            }
            #endif

            // Feel — everything the board does to your hands. One row today
            // (PRD-21 haptics); PRD-21's audio identity lands beside it.
            #if os(iOS) || os(tvOS)
            sectionLabel(Strings.string("prefs.section.feel"))
            #endif

            #if os(iOS)
            prefRow(
                title: Strings.string("prefs.haptics.title"),
                detail: Phrase.onOff(model.prefs.touchHaptics),
                symbol: model.prefs.touchHaptics ? "hand.tap.fill" : "hand.tap"
            ) {
                model.prefs.touchHaptics.toggle()
            }

            // PRD-30. In Feel rather than Layout because what it decides is not
            // where something sits but whether the app is present when you are
            // not looking at it — which is the same kind of question as whether
            // the board answers your hands.
            prefRow(
                title: Strings.string("prefs.livePresence.title"),
                detail: Phrase.onOff(model.prefs.livePresence),
                symbol: model.prefs.livePresence ? "lock.iphone" : "iphone"
            ) {
                model.prefs.livePresence.toggle()
            }
            #endif

            #if os(tvOS)
            // Controller haptics — the Afterglow score in hand, and the ticks
            // during play (PRD-5 §2.2). Silences all of it in a pad session.
            prefRow(
                title: Strings.string("prefs.controllerHaptics.title"),
                detail: Phrase.onOff(model.prefs.controllerHaptics),
                symbol: model.prefs.controllerHaptics ? "gamecontroller.fill" : "gamecontroller"
            ) {
                model.prefs.controllerHaptics.toggle()
            }
            #endif

            // Appearance — the two colour controls, finally adjacent.
            sectionLabel(Strings.string("prefs.section.appearance"))
            themeRow
            accentRow
            #if os(iOS)
            // PRD-16. iOS only — a tvOS icon is a layered brand asset and macOS
            // has no alternate-icon API.
            AppIconRow()
            #endif

            #if os(iOS)
            // PRD-2: board anchor + ambient slot, grouped with the existing
            // control-placement pref — all three decide where things sit.
            sectionLabel(Strings.string("prefs.section.layout"))

            prefRow(
                title: Strings.string("prefs.controls.title"),
                detail: Strings.string(model.prefs.controlsAtBottom
                                       ? "prefs.controls.bottom" : "prefs.controls.top"),
                symbol: model.prefs.controlsAtBottom
                    ? "inset.filled.bottomthird.square"
                    : "inset.filled.topthird.square"
            ) {
                model.prefs.controlsAtBottom.toggle()
            }

            prefRow(
                title: Strings.string("prefs.boardPosition.title"),
                detail: model.prefs.boardAnchor.title,
                symbol: boardAnchorSymbol
            ) {
                let all = BoardAnchor.allCases
                let index = all.firstIndex(of: model.prefs.boardAnchor) ?? 0
                model.prefs.boardAnchor = all[(index + 1) % all.count]
            }

            prefRow(
                title: Strings.string("prefs.ambient.title"),
                detail: model.prefs.ambientSlot.title,
                symbol: ambientSlotSymbol
            ) {
                let all = AmbientSlot.allCases
                let index = all.firstIndex(of: model.prefs.ambientSlot) ?? 0
                model.prefs.ambientSlot = all[(index + 1) % all.count]
            }
            #endif

            #if os(tvOS)
            if let onNewGame {
                newGameSection(onNewGame)
            }
            #endif

            Spacer(minLength: 12)

            #if os(tvOS)
            Text(Strings.string("sheet.dismiss.remote"))
                .font(CouchTypography.caption)
                .foregroundStyle(.tertiary)
            #elseif os(macOS)
            // The Settings window has its own chrome — no dismissal hint.
            EmptyView()
            #else
            Text(Strings.string("sheet.dismiss.touch"))
                .font(CouchTypography.caption)
                .foregroundStyle(.tertiary)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    #if os(iOS)
    // PRD-2 suggested inset.filled.tophalf.square — that name doesn't exist
    // in the SF catalog; the square.*half.filled family does.
    private var boardAnchorSymbol: String {
        switch model.prefs.boardAnchor {
        case .top: return "square.tophalf.filled"
        case .center: return "square.inset.filled"
        case .bottom: return "square.bottomhalf.filled"
        }
    }

    private var ambientSlotSymbol: String {
        switch model.prefs.ambientSlot {
        case .none: return "circle.slash"
        case .clock: return "clock"
        case .streak: return "flame"
        }
    }
    #endif

    // MARK: - New game (tvOS only — see `onNewGame`)

    #if os(tvOS)
    private func newGameSection(_ start: @escaping @MainActor (Difficulty) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Strings.string("prefs.newGame.title"))
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28 * CouchScale.chrome)
            HStack(spacing: 10) {
                ForEach(Difficulty.allCases, id: \.self) { difficulty in
                    Button {
                        start(difficulty)
                    } label: {
                        Text(Strings.difficulty(difficulty))
                            .font(CouchTypography.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .couchGlassInteractive(in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28 * CouchScale.chrome)
            // Corrected in PRD-34: `startFree` calls `library.create`, which
            // mints a *new* entry — the board you are on stays a partial and
            // is resumable from the shelf. The old copy said it was abandoned,
            // which scared people off a non-destructive action.
            Text(Strings.string("prefs.newGame.note"))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 28 * CouchScale.chrome)
        }
    }
    #endif

    // MARK: - Grouping

    /// A group heading. Deliberately the same quiet caption weight as a row's
    /// detail text — the sheet is a list you scan, not a form you navigate.
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(CouchTypography.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28 * CouchScale.chrome)
            .accessibilityAddTraits(.isHeader)
    }

    private var accentRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Strings.string("prefs.accent.title"))
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.prefs.accent.title)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28 * CouchScale.chrome)
            SwatchFlow(spacing: 14 * CouchScale.chrome) {
                ForEach(AccentChoice.allCases, id: \.self) { choice in
                    Button {
                        model.prefs.accent = choice
                    } label: {
                        Circle()
                            .fill(choice.color)
                            .frame(width: 36 * CouchScale.chrome, height: 36 * CouchScale.chrome)
                            .overlay {
                                if choice == model.prefs.accent {
                                    Circle().strokeBorder(.primary, lineWidth: 3 * CouchScale.chrome)
                                }
                            }
                            .padding(6 * CouchScale.chrome)
                    }
                    .buttonStyle(.plain)
                    // SwiftUI derives a shape-only Button's accessibility frame
                    // from the drawn circle, so these read as 20×20 pt in
                    // Tests/AXBaselines/prefs.txt — under the craft charter's
                    // 44 pt floor. The touch target was always the padded
                    // square; this makes the AX frame agree with it.
                    .contentShape(.accessibility, Circle().size(width: 44, height: 44))
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(choice == model.prefs.accent ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 22 * CouchScale.chrome)
        }
        .padding(.vertical, 6 * CouchScale.chrome)
    }

    private var themeRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Strings.string("prefs.theme.title"))
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.prefs.theme.title)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28 * CouchScale.chrome)
            SwatchFlow(spacing: 14 * CouchScale.chrome) {
                ForEach(ThemeChoice.allCases, id: \.self) { choice in
                    Button {
                        model.prefs.theme = choice
                    } label: {
                        themeSwatch(choice)
                            .frame(width: 44 * CouchScale.chrome, height: 44 * CouchScale.chrome)
                            .clipShape(RoundedRectangle(cornerRadius: 10 * CouchScale.chrome, style: .continuous))
                            .overlay {
                                // A hairline on every swatch (Void would
                                // otherwise vanish into a dark sheet); the
                                // pick gets the full primary ring.
                                RoundedRectangle(cornerRadius: 10 * CouchScale.chrome, style: .continuous)
                                    .strokeBorder(
                                        choice == model.prefs.theme ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary),
                                        lineWidth: choice == model.prefs.theme ? 3 * CouchScale.chrome : 1
                                    )
                            }
                            .padding(6 * CouchScale.chrome)
                    }
                    .buttonStyle(.plain)
                    .contentShape(
                        .accessibility,
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .size(width: 44, height: 44))
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(choice == model.prefs.theme ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 22 * CouchScale.chrome)
        }
        .padding(.vertical, 6 * CouchScale.chrome)
    }

    /// A theme at swatch size: its backdrop with a "9" in its digit tone —
    /// auto splits Void/Paper diagonally since it could resolve to either.
    @ViewBuilder
    private func themeSwatch(_ choice: ThemeChoice) -> some View {
        let dark = choice.tones(for: .dark)
        let light = choice.tones(for: .light)
        ZStack {
            Rectangle().fill(dark.background)
            if choice == .auto {
                DiagonalHalf().fill(light.background)
            }
            // A numeral drawn as a swatch, not a word.
            Text(verbatim: "9")
                .font(.system(size: 22 * CouchScale.chrome, weight: .semibold, design: .rounded))
                .foregroundStyle(choice == .auto ? .gray : dark.digitTone)
        }
    }

    /// A left-aligned flow that wraps onto as many lines as it needs. PRD-16
    /// took the theme row from six swatches to nine and the accent row from
    /// eight to ten; a plain `HStack` still fits an iPhone by about 30 pt,
    /// which is the kind of margin that turns into a clipped swatch on the
    /// release that adds a tenth theme.
    ///
    /// A `Layout` rather than a `LazyVGrid` because the two rows use different
    /// swatch sizes (44 pt themes, 36 pt accents) and an adaptive grid would
    /// column-align them into a table; each row is a wrapped sentence, not a
    /// grid. tvOS focus is derived from geometry, so wrapping needs no focus
    /// work of its own.
    struct SwatchFlow: Layout {
        var spacing: CGFloat

        func sizeThatFits(
            proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
        ) -> CGSize {
            let width = proposal.width ?? .infinity
            let rows = rows(subviews: subviews, width: width)
            return CGSize(
                width: proposal.width ?? rows.map(\.width).max() ?? 0,
                height: rows.last.map { $0.y + $0.height } ?? 0)
        }

        func placeSubviews(
            in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
        ) {
            for row in rows(subviews: subviews, width: bounds.width) {
                var x = bounds.minX
                for index in row.range {
                    let size = subviews[index].sizeThatFits(.unspecified)
                    subviews[index].place(
                        at: CGPoint(x: x, y: bounds.minY + row.y),
                        anchor: .topLeading,
                        proposal: ProposedViewSize(size))
                    x += size.width + spacing
                }
            }
        }

        private struct Row {
            var range: Range<Int>
            var y: CGFloat
            var width: CGFloat
            var height: CGFloat
        }

        private func rows(subviews: Subviews, width: CGFloat) -> [Row] {
            var rows: [Row] = []
            var start = 0
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for index in subviews.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                if index > start, x + size.width > width {
                    rows.append(
                        Row(range: start..<index, y: y, width: x - spacing, height: lineHeight))
                    y += lineHeight + spacing
                    start = index
                    x = 0
                    lineHeight = 0
                }
                x += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            if start < subviews.count {
                rows.append(
                    Row(
                        range: start..<subviews.count, y: y, width: x - spacing,
                        height: lineHeight))
            }
            return rows
        }
    }

    /// The lower-right triangle — the light half of the Auto theme swatch.
    private struct DiagonalHalf: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    /// Every user-facing literal in this file that is not already an enum's
    /// own `title`, in one block (PRD-20's seam).
    private enum Phrase {
        /// Nine's name, never translated — see `ShareCardMetrics.wordmark`.
        static let wordmark = "Nine"

        /// The value of a plain on/off row. One pair of keys for all five of
        /// them, so a translator cannot switch registers halfway down the sheet.
        static func onOff(_ isOn: Bool) -> String {
            Strings.string(isOn ? "prefs.toggle.on" : "prefs.toggle.off")
        }
    }

    private func prefRow(
        title: String, detail: String, symbol: String, action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 24 * CouchScale.chrome) {
                Image(systemName: symbol)
                    .font(.system(size: 34 * CouchScale.chrome, weight: .semibold))
                Text(title)
                    .font(CouchTypography.body)
                Spacer()
                Text(detail)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28 * CouchScale.chrome)
            .padding(.vertical, 18 * CouchScale.chrome)
        }
        .buttonStyle(.plain)
    }
}
