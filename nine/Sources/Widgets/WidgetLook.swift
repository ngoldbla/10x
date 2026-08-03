// WidgetLook.swift — the widget extension's colours, resolved from the
// player's own theme instead of guessed (PRD-30).
//
// `WidgetPalette` used to be three constants and a comment saying "the in-app
// tinted themes don't reach the extension (it can't read nine's prefs)". That
// was true and it was not a law: `nine.prefs` is local-only and does not sync,
// but `SharedAppearance` has carried theme and accent across a process boundary
// since PRD-6 — just not this one, because it travels by KVS and the widget
// extension reads KVS no more than it reads Application Support.
//
// PRD-30 moves the two raw strings into `WidgetSnapshot`, which the extension
// already reads on every timeline pass, and this is where they become colour.
// The numbers live in `Sources/Shared/SharedPalette.swift` and are pinned
// against `Sources/App/Theme.swift` by test.
import SwiftUI
import WidgetKit

/// The three tones a glanceable surface draws with, resolved together.
struct WidgetLook {
    let ground: Color
    /// Given digits and the constellation's printed dots.
    let digit: Color
    let accent: Color
    /// The theme's own leaning, which is not the system's — Camel is a light
    /// theme on a phone in dark mode.
    let isLight: Bool

    static func resolve(
        _ appearance: SharedAppearance,
        colorScheme: ColorScheme
    ) -> WidgetLook {
        let (ground, accent) = SharedPalette.resolve(
            appearance, systemIsLight: colorScheme == .light
        )
        return WidgetLook(
            ground: Color(ground.background),
            digit: Color(ground.digit),
            accent: Color(accent),
            isLight: ground.isLight
        )
    }
}

extension Color {
    init(_ rgb: PaletteRGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

// MARK: - Shared formatting

/// One formatter, shared by the board widget's solved footer.
enum WidgetFormat {
    /// "4:12" — matches the app's completion chip, because it now *is* the
    /// app's completion chip (`SolveCardFacts.elapsedText`).
    ///
    /// `.rounded()` stays here rather than moving into the shared function: the
    /// widget's seconds come off a `TimelineEntry` minted at a whole second and
    /// the in-app clocks truncate a live timer. Two different questions,
    /// one format.
    static func time(_ seconds: TimeInterval) -> String {
        SolveCardFacts.elapsedText(seconds.rounded())
    }
}
