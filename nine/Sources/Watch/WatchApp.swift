// WatchApp.swift — Nine on the wrist (PRD-6), entry point.
//
// Two screens and one link. Everything the watch persists is a top-level
// `CouchStored` key; everything it decides about the link is in
// `Sources/Shared/WatchLink.swift` where it is tested without a device.
#if os(watchOS)
import SwiftUI
import CouchKit

@main
struct NineWatchApp: App {
    /// The third `Strings.install()` site in the repo, and it has to be here
    /// for the same reason `NineWidgetBundle` has one: this is a separate
    /// *process* with its own `Bundle.main`, and `Phrasebook`'s resolver is
    /// per-process. Declared above any state so it runs first — position is
    /// the mechanism, exactly as in `NineApp.swift`. `Phrasebook.install` is a
    /// `precondition`, so a second call in one process traps rather than
    /// silently overwriting.
    private let phrasebook: Void = Strings.install()

    @State private var model = WatchModel()
    @State private var link: WatchLinkSession?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .task {
                    let session = link ?? WatchLinkSession(model: model)
                    link = session
                    session.activate()
                }
                .onChange(of: scenePhase) { _, phase in
                    // A solve made out of range is parked in the ledger; every
                    // return to the foreground is another chance to hand it
                    // over. Re-sending is free — the phone's ingest is
                    // idempotent per day.
                    if phase == .active { link?.flushPendingSolve() }
                }
        }
    }
}

struct WatchRootView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        NavigationStack {
            switch model.screen {
            case .home:
                WatchHomeView()
            case .board:
                WatchBoardView()
                    .toolbar { homeButton }
            case .box(let box):
                WatchBoxView(box: box)
                    .toolbar { mapButton }
            }
        }
        // The watch has no appearance settings of its own — it wears whatever
        // the phone published (`SharedAppearance`). Same two lines as
        // `NineApp`, so a tinted theme pins its leaning here too.
        .environment(\.nineTheme, model.theme)
        .preferredColorScheme(model.theme.colorScheme)
        // Deliberately no app-wide `.tint`. watchOS 26 draws a toolbar button
        // as a filled glass disc, so tinting the root made the back chevron a
        // vivid accent-coloured circle that out-shouted the board — an
        // idle-pixel-test failure on the one screen the player is thinking on.
        // The accent is applied where it carries meaning: the progress arc,
        // the cursor, the entries the player placed.
        .task(id: model.solvedAt) {
            guard model.solvedAt != nil else { return }
            await WatchCelebration.play()
        }
    }

    @ToolbarContentBuilder
    private var homeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { model.goHome() }) {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(Text(Strings.string("watch.nav.home")))
        }
    }

    /// Backing out of the lens returns to the map and cancels the preview —
    /// "selecting a different cell or leaving the box cancels the preview"
    /// (PRD-6 §2.3). Dialling then navigating must place nothing.
    @ToolbarContentBuilder
    private var mapButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: {
                model.preview = .empty
                model.selection = nil
                model.screen = .board
            }) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text(Strings.string("watch.nav.map")))
        }
    }
}
#endif
