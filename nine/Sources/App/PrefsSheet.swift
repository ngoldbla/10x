// PrefsSheet.swift — the one allowed secondary surface (suite rule): timer
// on/off (off is the default and the statement), error-highlight on/off,
// same-number highlight, the accent tint — and on iOS: appearance, control
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

            #if os(iOS)
            prefRow(
                title: "Appearance",
                detail: model.prefs.appearance.title,
                symbol: appearanceSymbol
            ) {
                let all = AppearanceChoice.allCases
                let index = all.firstIndex(of: model.prefs.appearance) ?? 0
                model.prefs.appearance = all[(index + 1) % all.count]
            }

            prefRow(
                title: "Resume on launch",
                detail: model.prefs.resumeOnLaunch ? "On" : "Off",
                symbol: model.prefs.resumeOnLaunch ? "play.circle.fill" : "play.circle"
            ) {
                model.prefs.resumeOnLaunch.toggle()
            }

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
            #else
            Text("Tap outside to return")
                .font(CouchTypography.caption)
                .foregroundStyle(.tertiary)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    #if os(iOS)
    private var appearanceSymbol: String {
        switch model.prefs.appearance {
        case .auto: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }

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
        Button {
            let all = AccentChoice.allCases
            let index = all.firstIndex(of: model.prefs.accent) ?? 0
            model.prefs.accent = all[(index + 1) % all.count]
        } label: {
            HStack(spacing: 24 * CouchScale.chrome) {
                Circle()
                    .fill(model.prefs.accent.color)
                    .frame(width: 36 * CouchScale.chrome, height: 36 * CouchScale.chrome)
                Text("Accent")
                    .font(CouchTypography.body)
                Spacer()
                Text(model.prefs.accent.title)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28 * CouchScale.chrome)
            .padding(.vertical, 18 * CouchScale.chrome)
        }
        .buttonStyle(.plain)
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
