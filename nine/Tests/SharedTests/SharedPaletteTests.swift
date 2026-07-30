// The palette exists twice, so a test has to be the thing that keeps the two
// copies equal (PRD-30).
//
// `Sources/App/Theme.swift` holds the colours as SwiftUI `Color`s, which the
// widget extension cannot compile, and `Sources/Shared/SharedPalette.swift`
// holds the same numbers as plain `Double`s, which it can. Extracting one from
// the other is not available: `AccentChoice.lightBarRGB` already exists in the
// App layer for the DualSense light bar, under a comment saying Color → RGB
// round-tripping is unreliable, so the App layer's own second copy is written
// out by hand for the same reason this one is.
//
// So this test reads `Theme.swift` as text — the `CatalogTests` idiom, for the
// same reason: the file it is checking is not on this target's source list. It
// fails in **both** directions, because a case added to one table and not the
// other is the failure that actually happens.
import XCTest
@testable import NineShared

final class SharedPaletteTests: XCTestCase {

    static let nineRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SharedTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // nine

    private static func themeSource() throws -> String {
        try String(
            contentsOf: nineRoot.appendingPathComponent("Sources/App/Theme.swift"),
            encoding: .utf8
        )
    }

    /// `case .glacier: return (0.33, 0.68, 0.98)` → ("glacier", triple).
    /// Reads `lightBarRGB`, which is already the App layer's own numeric copy of
    /// `AccentChoice.color`, so this compares numbers to numbers rather than
    /// trying to parse a `Color(red:green:blue:)` initialiser out of source.
    private static func lightBarTable(in source: String) -> [String: PaletteRGB] {
        guard let start = source.range(of: "var lightBarRGB:") else { return [:] }
        let body = source[start.upperBound...]
        var table: [String: PaletteRGB] = [:]
        for line in body.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "}" && !table.isEmpty { break }
            guard trimmed.hasPrefix("case ."),
                  let name = trimmed.dropFirst("case .".count).split(separator: ":").first,
                  let open = trimmed.firstIndex(of: "("),
                  let close = trimmed.lastIndex(of: ")")
            else { continue }
            let numbers = trimmed[trimmed.index(after: open)..<close]
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard numbers.count == 3 else { continue }
            table[String(name)] = PaletteRGB(numbers[0], numbers[1], numbers[2])
        }
        return table
    }

    /// `case .glacier: return Color(red: 0.07, green: 0.34, blue: 0.66)` from the
    /// `color(isLight:)` switch — the deepened, light-ground variants.
    private static func lightAccentTable(in source: String) -> [String: PaletteRGB] {
        guard let start = source.range(of: "func color(isLight: Bool) -> Color {") else {
            return [:]
        }
        let body = source[start.upperBound...]
        var table: [String: PaletteRGB] = [:]
        for line in body.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "}" && !table.isEmpty { break }
            guard trimmed.hasPrefix("case ."),
                  trimmed.contains("Color(red:"),
                  let name = trimmed.dropFirst("case .".count).split(separator: ":").first,
                  let triple = Self.colorComponents(in: trimmed)
            else { continue }
            table[String(name)] = triple
        }
        return table
    }

    /// Pulls the three labelled components out of one
    /// `Color(red: a, green: b, blue: c)` on a line.
    private static func colorComponents(in line: String) -> PaletteRGB? {
        var found: [Double] = []
        for label in ["red:", "green:", "blue:"] {
            guard let at = line.range(of: label) else { return nil }
            let rest = line[at.upperBound...]
            let number = rest.prefix { $0 == " " || $0 == "." || $0 == "-" || $0.isNumber }
            guard let value = Double(number.trimmingCharacters(in: .whitespaces)) else {
                return nil
            }
            found.append(value)
        }
        return PaletteRGB(found[0], found[1], found[2])
    }

    // MARK: - Accents

    func testEveryAccentAgreesWithTheAppLayerOnDarkGrounds() throws {
        let app = Self.lightBarTable(in: try Self.themeSource())
        XCTAssertEqual(app.count, 10, "parsed \(app.count) accents out of lightBarRGB — "
                       + "the switch's shape changed and this test is reading nothing")
        XCTAssertEqual(
            Set(app.keys), Set(SharedPalette.accentsOnDark.keys),
            """
            The accent lists have drifted. Every case in `AccentChoice` needs a \
            row in `SharedPalette.accentsOnDark`, or the widget and the Live \
            Activity render an accent the player did not pick.
            """
        )
        for (name, expected) in app {
            XCTAssertEqual(SharedPalette.accentsOnDark[name], expected, "accent \(name)")
        }
    }

    func testEveryAccentAgreesWithTheAppLayerOnLightGrounds() throws {
        let app = Self.lightAccentTable(in: try Self.themeSource())
        XCTAssertEqual(app.count, 10, "parsed \(app.count) light accents — the "
                       + "`color(isLight:)` switch's shape changed")
        XCTAssertEqual(Set(app.keys), Set(SharedPalette.accentsOnLight.keys))
        for (name, expected) in app {
            XCTAssertEqual(SharedPalette.accentsOnLight[name], expected,
                           "light accent \(name)")
        }
    }

    /// PRD-22's finding, restated as a property: the deepened variants exist
    /// because the vivid ones wash out on paper, so every light variant must
    /// actually be darker than its vivid twin. A copy-paste that left a light row
    /// equal to its dark row would pass the two tests above and silently give
    /// Camel PRD-22's 3.36:1 back.
    func testEveryLightAccentIsDarkerThanItsVividTwin() {
        func luminance(_ c: PaletteRGB) -> Double {
            0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
        }
        for (name, vivid) in SharedPalette.accentsOnDark {
            let deep = try? XCTUnwrap(SharedPalette.accentsOnLight[name])
            guard let deep else { continue }
            XCTAssertLessThan(luminance(deep), luminance(vivid), "accent \(name)")
        }
    }

    // MARK: - Themes

    func testEveryThemeAgreesWithTheAppLayerOnGroundAndInk() throws {
        let source = try Self.themeSource()
        // The cases of `ThemeChoice`, from its declaration line.
        let declLine = try XCTUnwrap(
            source.split(separator: "\n").first { $0.contains("case auto, dark, light") },
            "ThemeChoice's case list moved — this test is reading nothing"
        )
        let cases = declLine.replacingOccurrences(of: "case ", with: "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(cases.count, 9)

        // `auto` has no tones of its own; `SharedPalette` documents that and
        // delegates it the same way `tones(for:)` does.
        let expected = Set(cases).subtracting([SharedPalette.autoTheme])
        XCTAssertEqual(
            expected, Set(SharedPalette.themes.keys),
            """
            The theme lists have drifted. Every `ThemeChoice` case except `auto` \
            needs a row in `SharedPalette.themes`.
            """
        )

        // And the two tones each row claims, read out of the `tones(for:)` switch.
        for name in expected {
            let ground = try XCTUnwrap(SharedPalette.themes[name])
            guard let block = Self.tonesBlock(for: name, in: source) else {
                // `dark` names CouchPalette constants rather than literals, so it
                // is pinned by the dedicated test below instead.
                XCTAssertEqual(name, "dark", "no tones block parsed for \(name)")
                continue
            }
            if let background = Self.labelledColor("background:", in: block) {
                XCTAssertEqual(ground.background, background, "\(name) background")
            }
            if let digit = Self.labelledColor("digitTone:", in: block) {
                XCTAssertEqual(ground.digit, digit, "\(name) digitTone")
            }
            let isLight = block.contains("isLight: true")
            XCTAssertEqual(ground.isLight, isLight, "\(name) isLight")
        }
    }

    /// Void is the only theme whose tones are CouchKit constants rather than
    /// literals, so it is checked against CouchKit's source instead.
    func testVoidTracksCouchPalette() throws {
        let couch = try String(
            contentsOf: Self.nineRoot
                .deletingLastPathComponent()   // repo root
                .appendingPathComponent("couchkit/Sources/CouchKit/CouchUI.swift"),
            encoding: .utf8
        )
        let dark = try XCTUnwrap(SharedPalette.themes["dark"])
        for (needle, expected) in [
            ("static let void", dark.background), ("static let paper", dark.digit),
        ] {
            let line = try XCTUnwrap(
                couch.split(separator: "\n").first { $0.contains(needle) },
                "CouchPalette has no `\(needle)` — this test is reading nothing"
            )
            XCTAssertEqual(Self.labelledColor("red:", in: String(line)) != nil, true)
            XCTAssertEqual(
                try XCTUnwrap(Self.colorComponents(in: String(line))), expected,
                needle
            )
        }
    }

    private static func tonesBlock(for theme: String, in source: String) -> String? {
        guard let at = source.range(of: "case .\(theme):\n            return ThemeTones(")
        else { return nil }
        let rest = source[at.upperBound...]
        guard let end = rest.range(of: "\n            )") else { return nil }
        return String(rest[..<end.lowerBound])
    }

    private static func labelledColor(_ label: String, in block: String) -> PaletteRGB? {
        guard let at = block.range(of: label) else { return nil }
        let line = block[at.lowerBound...].prefix { $0 != "\n" }
        return colorComponents(in: String(line))
    }

    // MARK: - Resolution

    /// The bug this API exists to make unrepeatable: the accent's light/dark
    /// variant follows the *theme's* leaning, not the system's. Camel is a light
    /// theme; a phone in dark mode showing Camel must still get the deepened
    /// accent, because PRD-22 measured the vivid one on Camel at 3.36:1.
    func testCamelInDarkModeStillGetsTheDeepenedAccent() {
        let camel = SharedAppearance(theme: "camel", accent: "orchid")
        let (ground, accent) = SharedPalette.resolve(camel, systemIsLight: false)
        XCTAssertTrue(ground.isLight)
        XCTAssertEqual(accent, SharedPalette.accentsOnLight["orchid"])
    }

    func testAutoFollowsTheSystemAndUnknownNamesFallBackRatherThanFail() {
        XCTAssertEqual(
            SharedPalette.theme("auto", systemIsLight: true).background,
            SharedPalette.themes["light"]?.background
        )
        XCTAssertEqual(
            SharedPalette.theme("auto", systemIsLight: false).background,
            SharedPalette.themes["dark"]?.background
        )
        // A theme or accent from a newer build renders in the default rather than
        // not rendering — the rule every cross-version reader here follows.
        for unknown in ["", "aurora", "not-a-theme"] {
            XCTAssertEqual(
                SharedPalette.theme(unknown, systemIsLight: false).background,
                SharedPalette.themes["dark"]?.background,
                unknown
            )
        }
        for unknown in ["", "periwinkle"] {
            XCTAssertEqual(
                SharedPalette.accent(unknown, isLight: false),
                SharedPalette.accentsOnDark[SharedPalette.defaultAccent],
                unknown
            )
        }
    }

    /// A snapshot written by a build that predates these fields resolves to the
    /// defaults rather than to nothing.
    func testAnOlderSnapshotResolvesToTheDefaultLook() {
        let old = WidgetSnapshot()
        XCTAssertEqual(old.appearance, SharedAppearance())
        XCTAssertEqual(old.focus, .none)
        let (ground, accent) = SharedPalette.resolve(old.appearance, systemIsLight: false)
        XCTAssertEqual(ground.background, SharedPalette.themes["dark"]?.background)
        XCTAssertEqual(accent, SharedPalette.accentsOnDark["glacier"])
    }
}
