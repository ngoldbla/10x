// PrefsDowngradeTests — what a build that has never heard of Ember does with a
// prefs blob that names it (PRD-16 §4.1, §5).
//
// `NinePrefs` lives in `Sources/App` and cannot be linked here (Package.swift
// covers Engine + Shared only), so the two builds are modelled by mirrors —
// the `DowngradeDrillTests` pattern. A mirror is a claim about code that is not
// in this tree, so both mirrors are checked against the real `AppModel.swift`
// by `testMirrorsMatchTheShippingDecoder` below rather than trusted.
//
// The asymmetry that matters, and why this is a one-field risk rather than
// PRD-17's data-loss risk:
//
//   • `nine.prefs` is NOT `cloudSynced` (AppModel.swift:378). A downgrade
//     resets one field on one device and never propagates to another. That is
//     the whole difference from `nine.history`, which is cloudSynced and
//     last-writer-wins, and which is why PRD-17 needed a wire bridge and this
//     does not.
//   • `NinePrefs.init(from:)` already decodes every enum with `(try? …) ?? d`,
//     so an unknown raw value costs that field's default and nothing else —
//     the other nine preferences survive verbatim. That is what is asserted
//     here, field by field, rather than asserted in a comment.
import XCTest
import Foundation

final class PrefsDowngradeTests: XCTestCase {

    // MARK: - The two builds, as they decode

    /// `ThemeChoice` as shipped before PRD-16: six cases.
    enum LegacyTheme: String, Codable { case auto, dark, light, camel, blueprint, forest }
    /// `AccentChoice` as shipped before PRD-16: eight cases.
    enum LegacyAccent: String, Codable {
        case glacier, ember, meadow, lilac, crimson, gold, teal, magenta
    }
    /// `ThemeChoice` as of PRD-16: nine.
    enum CurrentTheme: String, Codable {
        case auto, dark, light, camel, blueprint, forest, ember, tide, mono
    }
    /// `AccentChoice` as of PRD-16: ten.
    enum CurrentAccent: String, Codable {
        case glacier, ember, meadow, lilac, crimson, gold, teal, magenta, moss, orchid
    }

    /// `NinePrefs`, generic over its two enum fields so one mirror models both
    /// builds. Every field, every default and the exact `(try? …) ?? default`
    /// shape are copied from `AppModel.swift`. `boardAnchor` and `ambientSlot`
    /// are modelled as `String` rather than as their own enums: PRD-16 does not
    /// touch them, and what matters here is only that they survive intact.
    ///
    /// **The defaults are the *current* build's.** One struct models both
    /// builds, so the two enum case lists are what vary and the defaults are
    /// not — which is sound because the only test a default can reach is
    /// `testNewBuildReadsA1xBlobWithMissingKeys`, and that one models the new
    /// build by construction. `showTimer` and `boardAnchor` are copied down
    /// from `AppModel.swift` here for that reason: the AAA layout work moved
    /// both, and a mirror whose header claims to be a copy while holding the
    /// previous values is worse than no mirror, because it keeps asserting a
    /// default the app no longer has.
    struct Prefs<Theme: Codable, Accent: Codable>: Codable {
        var showTimer = true
        var errorHighlight = true
        var accent: Accent
        var numberHighlight = true
        var controlsAtBottom = true
        var theme: Theme
        var resumeOnLaunch = true
        var boardAnchor = "center"
        var ambientSlot = "none"
        var controllerHaptics = true
        var touchHaptics = true

        enum CodingKeys: String, CodingKey {
            case showTimer, errorHighlight, accent, numberHighlight
            case controlsAtBottom, resumeOnLaunch, boardAnchor, ambientSlot
            case controllerHaptics, touchHaptics
            case theme = "appearance"
        }

        init(accent: Accent, theme: Theme) {
            self.accent = accent
            self.theme = theme
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            showTimer = try c.decodeIfPresent(Bool.self, forKey: .showTimer) ?? true
            errorHighlight = try c.decodeIfPresent(Bool.self, forKey: .errorHighlight) ?? true
            accent = (try? c.decodeIfPresent(Accent.self, forKey: .accent)) ?? Self.defaultAccent
            numberHighlight = try c.decodeIfPresent(Bool.self, forKey: .numberHighlight) ?? true
            controlsAtBottom = try c.decodeIfPresent(Bool.self, forKey: .controlsAtBottom) ?? true
            theme = (try? c.decodeIfPresent(Theme.self, forKey: .theme)) ?? Self.defaultTheme
            resumeOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .resumeOnLaunch) ?? true
            boardAnchor = (try? c.decodeIfPresent(String.self, forKey: .boardAnchor)) ?? "center"
            ambientSlot = (try? c.decodeIfPresent(String.self, forKey: .ambientSlot)) ?? "none"
            controllerHaptics = try c.decodeIfPresent(Bool.self, forKey: .controllerHaptics) ?? true
            touchHaptics = try c.decodeIfPresent(Bool.self, forKey: .touchHaptics) ?? true
        }

        static var defaultAccent: Accent { Self.raw("glacier") }
        static var defaultTheme: Theme { Self.raw("auto") }

        /// Both mirrors' enums are raw-string `Codable`, so a one-element JSON
        /// array is the shortest route to a value without constraining the
        /// generic parameter to `RawRepresentable`.
        private static func raw<T: Codable>(_ value: String) -> T {
            // swiftlint:disable:next force_try
            try! JSONDecoder().decode([T].self, from: Data("[\"\(value)\"]".utf8))[0]
        }
    }

    typealias LegacyPrefs = Prefs<LegacyTheme, LegacyAccent>
    typealias CurrentPrefs = Prefs<CurrentTheme, CurrentAccent>

    // MARK: - Downgrade: the new build's blob, read by the old build

    func testOldBuildKeepsEveryOtherPreferenceWhenItMeetsANewTheme() throws {
        var written = CurrentPrefs(accent: .orchid, theme: .ember)
        written.showTimer = true
        written.errorHighlight = false
        written.numberHighlight = false
        written.controlsAtBottom = false
        written.resumeOnLaunch = false
        written.boardAnchor = "top"
        written.ambientSlot = "clock"
        written.touchHaptics = false

        let blob = try JSONEncoder().encode(written)
        let read = try JSONDecoder().decode(LegacyPrefs.self, from: blob)

        // The two unknown enums fall back to their defaults …
        XCTAssertEqual(read.theme, .auto, "an unknown theme must fall back, not throw")
        XCTAssertEqual(read.accent, .glacier, "an unknown accent must fall back, not throw")
        // … and *nothing else moves*. This is the whole claim.
        XCTAssertTrue(read.showTimer)
        XCTAssertFalse(read.errorHighlight)
        XCTAssertFalse(read.numberHighlight)
        XCTAssertFalse(read.controlsAtBottom)
        XCTAssertFalse(read.resumeOnLaunch)
        XCTAssertEqual(read.boardAnchor, "top")
        XCTAssertEqual(read.ambientSlot, "clock")
        XCTAssertFalse(read.touchHaptics)
        XCTAssertTrue(read.controllerHaptics)
    }

    func testOldBuildSurvivesEveryNewThemeAndAccentIndividually() throws {
        for theme in [CurrentTheme.ember, .tide, .mono] {
            let blob = try JSONEncoder().encode(CurrentPrefs(accent: .glacier, theme: theme))
            let read = try JSONDecoder().decode(LegacyPrefs.self, from: blob)
            XCTAssertEqual(read.theme, .auto, "\(theme) did not fall back cleanly")
            XCTAssertEqual(read.accent, .glacier, "\(theme) collaterally reset the accent")
        }
        for accent in [CurrentAccent.moss, .orchid] {
            let blob = try JSONEncoder().encode(CurrentPrefs(accent: accent, theme: .dark))
            let read = try JSONDecoder().decode(LegacyPrefs.self, from: blob)
            XCTAssertEqual(read.accent, .glacier, "\(accent) did not fall back cleanly")
            XCTAssertEqual(read.theme, .dark, "\(accent) collaterally reset the theme")
        }
    }

    // MARK: - Upgrade: the old build's blob, read by the new build

    func testNewBuildReadsAnOldBlobUnchanged() throws {
        var written = LegacyPrefs(accent: .magenta, theme: .forest)
        written.showTimer = true
        written.ambientSlot = "streak"

        let blob = try JSONEncoder().encode(written)
        let read = try JSONDecoder().decode(CurrentPrefs.self, from: blob)

        XCTAssertEqual(read.theme, .forest)
        XCTAssertEqual(read.accent, .magenta)
        XCTAssertTrue(read.showTimer)
        XCTAssertEqual(read.ambientSlot, "streak")
    }

    /// A 1.x blob predates four of these keys entirely and predates `appearance`
    /// having more than three values. It must still decode field-complete.
    func testNewBuildReadsA1xBlobWithMissingKeys() throws {
        let blob = Data(#"{"showTimer":true,"appearance":"dark","accent":"gold"}"#.utf8)
        let read = try JSONDecoder().decode(CurrentPrefs.self, from: blob)
        XCTAssertEqual(read.theme, .dark)
        XCTAssertEqual(read.accent, .gold)
        XCTAssertTrue(read.showTimer)
        XCTAssertTrue(read.errorHighlight, "a missing key must take its default")
        XCTAssertEqual(read.boardAnchor, "center")
        XCTAssertTrue(read.touchHaptics)
    }

    // MARK: - The mirrors are checked, not trusted

    func testMirrorsMatchTheShippingDecoder() throws {
        let nine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: nine.appendingPathComponent("Sources/App/AppModel.swift"),
            encoding: .utf8)
        // The two enums live in `Theme.swift` since PRD-6 — the board had to be
        // compilable without the model to reach the watch. `NinePrefs` and its
        // decode did not move, so this test now reads two files rather than
        // one, and each assertion still names the file that owns its fact.
        let themeSource = try String(
            contentsOf: nine.appendingPathComponent("Sources/App/Theme.swift"),
            encoding: .utf8)

        // The current mirror's case lists must be the shipping ones.
        XCTAssertTrue(
            themeSource.contains("case auto, dark, light, camel, blueprint, forest, ember, tide, mono"),
            "ThemeChoice's cases have moved — update CurrentTheme")
        XCTAssertTrue(
            themeSource.contains(
                "case glacier, ember, meadow, lilac, crimson, gold, teal, magenta, moss, orchid"),
            "AccentChoice's cases have moved — update CurrentAccent")

        // The tolerance shape itself. If either of these lines loses its
        // `try?`, an unknown raw value throws and `CouchStored` discards the
        // *whole* prefs blob rather than one field.
        XCTAssertTrue(
            source.contains(
                "accent = (try? c.decodeIfPresent(AccentChoice.self, forKey: .accent)) ?? .glacier"),
            "NinePrefs.accent no longer decodes tolerantly")
        XCTAssertTrue(
            source.contains(
                "theme = (try? c.decodeIfPresent(ThemeChoice.self, forKey: .theme)) ?? .auto"),
            "NinePrefs.theme no longer decodes tolerantly")
        // The persisted key for theme is `appearance`, so 1.x blobs decode.
        XCTAssertTrue(
            source.contains(#"case theme = "appearance""#),
            "NinePrefs.theme's wire key moved — 1.x blobs would lose their theme")
        // And prefs must stay local. If this ever becomes cloudSynced, the
        // downgrade stops being a one-device, one-field event and this whole
        // file's reasoning needs redoing.
        XCTAssertTrue(
            source.contains(#"CouchStored(wrappedValue: NinePrefs(), "nine.prefs")"#),
            "nine.prefs gained a storage option — if it is now cloudSynced, a downgraded "
                + "device's reset theme propagates last-writer-wins to every other device")
    }
}
