// NineWidgetBundle.swift — entry point of the NineWidgets extension
// (PRD-3). One widget since the daily's removal (2026-08-02): the playable
// board, mirroring the app's most recent in-progress classic board. The
// glanceable daily widget, the streak accessory and the daily-presence Live
// Activity were all built around the daily and went with it.
import SwiftUI
import WidgetKit

@main
struct NineWidgetBundle: WidgetBundle {

    /// The appex's own `Strings.install()` (PRD-20).
    ///
    /// **A second process, not a second call.** `NineWidgets.appex` never runs
    /// `NineApp`, so without this line `Phrasebook.current` would stay
    /// permanently English *in the one bundle whose existence is half the
    /// argument for the seam existing* — `Sources/Shared` compiles into both,
    /// and inside an extension `Bundle.main` IS the extension. A Japanese phone
    /// would show a Japanese app beside an English Home Screen widget, and all
    /// three platform builds would stay green while it did.
    ///
    /// A stored property rather than an `init` for symmetry with `NineApp`,
    /// where the position is load-bearing (see the comment there).
    private let phrasebook: Void = Strings.install()

    var body: some Widget {
        NineBoardWidget()
    }
}
