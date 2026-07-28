// WatchApp.swift — Nine on the wrist (PRD-6), entry point.
#if os(watchOS)
import SwiftUI

@main
struct NineWatchApp: App {
    /// The third `Strings.install()` site in the repo, and it has to be here
    /// for the same reason `NineWidgetBundle` has one: this is a separate
    /// *process* with its own `Bundle.main`, and `Phrasebook`'s resolver is
    /// per-process. Declared above any state so it runs first — position is
    /// the mechanism, exactly as in `NineApp.swift`.
    private let phrasebook: Void = Strings.install()

    var body: some Scene {
        WindowGroup {
            Text(verbatim: "Nine")
        }
    }
}
#endif
