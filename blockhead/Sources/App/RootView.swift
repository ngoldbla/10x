// Root: the hall (StageBackground) is always full-bleed underneath; screens
// swap on top; the pause curtain and the one prefs GlassSheet float above.
// The remote surface lives HERE — one persistent focusable for the whole
// app, never torn down on route swaps (the party loop swaps constantly),
// so the first click after any screen change always lands.
import SwiftUI
import CouchKit

/// The app's control vocabulary — the first-run overlay shows all of it;
/// the prefs sheet embeds the compact cut so it doubles as the manual.
enum BlockheadLegend {
    static let rows = [
        LegendRow(
            symbol: "arrow.up.and.down.and.arrow.left.and.right",
            gesture: "Swipe",
            action: "Answer (each direction is one choice)"),
        LegendRow(symbol: "hand.tap", gesture: "Click", action: "Choose / advance"),
        LegendRow(symbol: "playpause.fill", gesture: "Play/Pause", action: "Pause the show"),
        LegendRow(symbol: "gearshape.fill", gesture: "Hold ▶︎", action: "Settings"),
        LegendRow(symbol: "arrow.uturn.backward", gesture: "Back", action: "Leave / the stage"),
    ]
    static var compact: [LegendRow] { Array(rows.prefix(4)) }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // The help overlay owns the remote while shown, so the root surface
        // detaches for exactly that window and reattaches on dismiss.
        if model.showHelp {
            core.overlay {
                HelpOverlay(
                    title: "Blockhead",
                    tagline: "The nightly quiz show.",
                    rows: BlockheadLegend.rows
                ) {
                    model.dismissHelp()
                }
            }
        } else {
            // interceptsBack only away from the stage (suite rule: Menu
            // exits the app at the root) or while the prefs sheet is up.
            core.couchRemote(
                eightWay: true,
                interceptsBack: model.route != .stage || model.showPrefs
            ) { gesture in
                model.handle(gesture)
            }
        }
    }

    private var core: some View {
        @Bindable var model = model
        return ZStack {
            StageBackground(
                mood: model.mood,
                reduceFlash: model.reduceFlash,
                sweepPaused: model.moment == .locked || model.isPaused
            )
            screen
            if model.isPaused {
                PauseCurtain()
                    .transition(.opacity)
            }
        }
        .overlay {
            GlassSheet(isPresented: $model.showPrefs) {
                PrefsPanel()
            }
        }
        .animation(.couchFast, value: model.isPaused)
        .background(CouchPalette.void)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var screen: some View {
        switch model.route {
        case .stage:
            StageView()
        case .archive:
            ArchiveView()
        case .question, .partyQuestion:
            QuestionMomentView()
        case .summary:
            SummaryView()
        case .partySetup:
            PartySetupView()
        case .handoff:
            HandoffView()
        case .podium:
            PodiumView()
        }
    }
}
