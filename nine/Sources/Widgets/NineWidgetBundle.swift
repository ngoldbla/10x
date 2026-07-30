// NineWidgetBundle.swift — entry point of the NineWidgets extension
// (PRD-3). Three widgets: glanceable daily state, the streak accessory,
// and the playable large board.
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
    /// `WidgetBundle` has no other stored property to be ordered against today;
    /// the symmetry is so that adding one cannot quietly reintroduce that
    /// problem here.
    private let phrasebook: Void = Strings.install()

    var body: some Widget {
        NineDailyWidget()
        NineStreakWidget()
        NineBoardWidget()
        // The Live Activity (PRD-30). A bundle member like any other, with no
        // `#if` and no entitlement behind it — Live Activities are gated by the
        // app's `NSSupportsLiveActivities` Info.plist key alone, which is why
        // this is the first new surface in three PRDs that needs no `match`
        // re-mint (EXECUTING-A-PRD §6).
        NineDailyPresenceActivity()
    }
}
