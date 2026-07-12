// Root: the hall (StageBackground) is always full-bleed underneath; screens
// swap on top; the pause curtain and the one prefs GlassSheet float above.
import SwiftUI
import CouchKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
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
