// Darkroom — picross puzzles compiled from your photos; solving develops
// the memory. tvOS, remote-first, pixels under glass.
import SwiftUI
import CouchKit

@main
struct DarkroomApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}

/// One dark room, three faces: the wall, a board, a hung memory.
struct RootView: View {
    var model: AppModel

    var body: some View {
        ZStack {
            CouchPalette.void.ignoresSafeArea()

            switch model.route {
            case .wall:
                WallView(model: model)
                    .transition(.opacity)
            case .board(let slot):
                BoardView(model: model, slot: slot)
                    .transition(.opacity)
            case .memory(let slot):
                MemoryView(model: model, slot: slot)
                    .transition(.opacity)
            }

            if model.showPermission {
                PhotoPermissionView { granted in
                    model.resolvePermission(granted: granted)
                }
                .transition(.opacity)
            }
        }
        .animation(.couchAmbient, value: model.route)
        .task { await model.loadDailyIfNeeded() }
    }
}
