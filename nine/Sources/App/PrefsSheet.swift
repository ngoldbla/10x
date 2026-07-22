// PrefsSheet.swift — the one allowed secondary surface (suite rule): timer
// on/off (off is the default and the statement), error-highlight on/off,
// same-number highlight, the theme and accent swatches — and on iOS: control
// placement, launch resume, plus a "New game" escape hatch so a difficulty
// is a choice, not a commitment. Lives inside CouchKit's GlassSheet.
import SwiftUI
import CouchKit

struct PrefsSheetContent: View {
    let model: AppModel
    /// In-game only (iOS): starts a fresh board at the chosen difficulty,
    /// abandoning the current one. Nil hides the section (tvOS, or no host).
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
            Text("Nine")
                .couchText(CouchTypography.title)
                .padding(.bottom, 8)

            // The manual lives here after first run (suite rule: the prefs
            // sheet doubles as the help page).
            #if os(tvOS)
            ControlLegend(rows: NineLegend.compact)
                .padding(.bottom, 8)
            #elseif os(macOS)
            ControlLegend(rows: NineLegend.keyboardCompact)
                .padding(.bottom, 8)
            #else
            ControlLegend(rows: NineLegend.touchCompact)
                .padding(.bottom, 8)
            #endif

            prefRow(
                title: "Timer",
                detail: model.prefs.showTimer ? "Shown" : "Hidden",
                symbol: model.prefs.showTimer ? "clock.fill" : "clock"
            ) {
                model.prefs.showTimer.toggle()
            }

            prefRow(
                title: "Error highlight",
                detail: model.prefs.errorHighlight ? "On" : "Off",
                symbol: model.prefs.errorHighlight ? "checkmark.circle.fill" : "circle"
            ) {
                model.prefs.errorHighlight.toggle()
            }

            prefRow(
                title: "Number highlight",
                detail: model.prefs.numberHighlight ? "On" : "Off",
                symbol: model.prefs.numberHighlight ? "9.square.fill" : "9.square"
            ) {
                model.prefs.numberHighlight.toggle()
            }

            themeRow

            // Resume-on-launch ships on iOS and macOS (PRD-4 §2.6 parity).
            #if os(iOS) || os(macOS)
            prefRow(
                title: "Resume on launch",
                detail: model.prefs.resumeOnLaunch ? "On" : "Off",
                symbol: model.prefs.resumeOnLaunch ? "play.circle.fill" : "play.circle"
            ) {
                model.prefs.resumeOnLaunch.toggle()
            }
            #endif

            #if os(iOS)
            // PRD-2: board anchor + ambient slot, grouped with the existing
            // control-placement pref — all three decide where things sit.
            Text("Layout")
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28 * CouchScale.chrome)

            prefRow(
                title: "Controls",
                detail: model.prefs.controlsAtBottom ? "Bottom" : "Top",
                symbol: model.prefs.controlsAtBottom
                    ? "inset.filled.bottomthird.square"
                    : "inset.filled.topthird.square"
            ) {
                model.prefs.controlsAtBottom.toggle()
            }

            prefRow(
                title: "Board position",
                detail: model.prefs.boardAnchor.title,
                symbol: boardAnchorSymbol
            ) {
                let all = BoardAnchor.allCases
                let index = all.firstIndex(of: model.prefs.boardAnchor) ?? 0
                model.prefs.boardAnchor = all[(index + 1) % all.count]
            }

            prefRow(
                title: "Ambient display",
                detail: model.prefs.ambientSlot.title,
                symbol: ambientSlotSymbol
            ) {
                let all = AmbientSlot.allCases
                let index = all.firstIndex(of: model.prefs.ambientSlot) ?? 0
                model.prefs.ambientSlot = all[(index + 1) % all.count]
            }
            #endif

            accentRow

            if let onNewGame {
                newGameSection(onNewGame)
            }

            Spacer(minLength: 12)

            #if os(tvOS)
            Text("Press Back to return")
                .font(CouchTypography.caption)
                .foregroundStyle(.tertiary)
            #elseif os(macOS)
            // The Settings window has its own chrome — no dismissal hint.
            EmptyView()
            #else
            Text("Tap outside to return")
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

    // MARK: - New game

    private func newGameSection(_ start: @escaping @MainActor (Difficulty) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New game")
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28 * CouchScale.chrome)
            HStack(spacing: 10) {
                ForEach(Difficulty.allCases, id: \.self) { difficulty in
                    Button {
                        start(difficulty)
                    } label: {
                        Text(difficulty.title)
                            .font(CouchTypography.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .couchGlassInteractive(in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28 * CouchScale.chrome)
            Text("Starts fresh — the current board is abandoned")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 28 * CouchScale.chrome)
        }
    }

    private var accentRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Accent")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.prefs.accent.title)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28 * CouchScale.chrome)
            HStack(spacing: 14 * CouchScale.chrome) {
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
                    .accessibilityLabel(choice.title)
                }
            }
            .padding(.horizontal, 22 * CouchScale.chrome)
        }
        .padding(.vertical, 6 * CouchScale.chrome)
    }

    private var themeRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Theme")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.prefs.theme.title)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28 * CouchScale.chrome)
            HStack(spacing: 14 * CouchScale.chrome) {
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
                    .accessibilityLabel(choice.title)
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
            Text("9")
                .font(.system(size: 22 * CouchScale.chrome, weight: .semibold, design: .rounded))
                .foregroundStyle(choice == .auto ? .gray : dark.digitTone)
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
