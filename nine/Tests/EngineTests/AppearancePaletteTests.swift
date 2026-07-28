// AppearancePaletteTests — the appearance palette as a contract (PRD-16).
//
// `ThemeChoice` and `AccentChoice` live in `Sources/App`, which `swift test`
// does not compile: the SwiftPM package covers `Sources/Engine` and
// `Sources/Shared` only (Package.swift), because Lane 1 is Linux and those two
// trees are SwiftUI-free. So the palette is pinned the way this repo already
// pins things it cannot link against:
//
//   • the numbers live here, as a table, and a source-literal check fails if
//     `Theme.swift` ever disagrees with the table (the
//     `VariantChannelSealTests` pattern — a source check fires on the line that
//     introduces the drift, in the PR that introduces it);
//   • the *properties* those numbers must have — WCAG contrast against the
//     board, and separation from every sibling under three kinds of colorblind
//     vision — are asserted on the table.
//
// Why bother: the second property is a knife-edge that eyeballing cannot find.
// A periwinkle at (0.45, 0.55, 0.99) looks like an obvious ninth accent and
// collapses the palette's worst pair from ΔE 5.98 to **2.11** — indistinguishable
// from Lilac for a protanope. That is the number this file exists to catch.
//
// **Scope, so this is not mistaken for something it is not.** PRD-16 §5 asks for
// a *manual* check that coral and the accents stay legible on the three new
// themes. This file is more than that and less than the real thing: it measures
// the **raw theme constants**, while the board draws them under a glass plane
// that lifts the void. Measuring the *composited* surface — the 96-cell
// theme×accent matrix, sampled from screenshots — is PRD-22's contrast harness
// and is not started. A green run here means "no worse than what shipped",
// never "the board meets contrast".
import XCTest
import Foundation

final class AppearancePaletteTests: XCTestCase {

    // MARK: - The palette, as shipped

    typealias RGB = (r: Double, g: Double, b: Double)

    /// The coral error marker (`BoardView.swift:153`). Not an accent — the
    /// colorblind-safe rule is that no accent may be confusable with it.
    static let coral: RGB = (1.0, 0.45, 0.38)

    /// Every accent's vivid base tint, in declaration order.
    static let accents: [(name: String, rgb: RGB)] = [
        ("glacier", (0.33, 0.68, 0.98)),
        ("ember",   (1.00, 0.56, 0.20)),
        ("meadow",  (0.36, 0.84, 0.48)),
        ("lilac",   (0.66, 0.50, 0.98)),
        ("crimson", (1.00, 0.36, 0.56)),
        ("gold",    (0.98, 0.75, 0.18)),
        ("teal",    (0.15, 0.80, 0.76)),
        ("magenta", (0.88, 0.42, 0.90)),
        ("moss",    (0.62, 0.85, 0.30)),
        ("orchid",  (0.94, 0.38, 0.68)),
    ]

    /// Every accent's *light-ground* variant, in declaration order. New in
    /// PRD-22: these existed since 1.1 and nothing measured them, because the
    /// floors below were written against the vivid set. The contrast harness
    /// measured them on the composited glass and found every one of them below
    /// WCAG AA on Paper and Camel — Gold at **2.24:1**. These are the retuned
    /// values.
    static let lightAccents: [(name: String, rgb: RGB)] = [
        ("glacier", (0.07, 0.34, 0.66)),
        ("ember",   (0.57, 0.25, 0.02)),
        ("meadow",  (0.08, 0.40, 0.20)),
        ("lilac",   (0.39, 0.26, 0.70)),
        ("crimson", (0.67, 0.11, 0.28)),
        ("gold",    (0.46, 0.32, 0.01)),
        ("teal",    (0.02, 0.39, 0.37)),
        ("magenta", (0.58, 0.16, 0.58)),
        ("moss",    (0.27, 0.38, 0.04)),
        ("orchid",  (0.66, 0.08, 0.39)),
    ]

    /// The coral error marker's light-ground twin (PRD-22). The vivid coral is
    /// 1.92:1 on Camel's composited board — an error marker nobody can see.
    static let coralOnLight: RGB = (0.72, 0.13, 0.06)

    /// Every dark-leaning theme's board tones. Light-leaning themes (Paper,
    /// Camel) are still excluded from the *raw* contrast floors below, and now
    /// for a sharper reason than before: PRD-22 measured them on the composited
    /// glass and fixed them there. `Tests/ContrastBaselines/matrix.txt` is where
    /// their numbers live, because the raw constants were never the thing the
    /// board draws.
    static let darkThemes: [(name: String, background: RGB, gridTone: RGB, digitTone: RGB)] = [
        ("dark",      (0.00, 0.00, 0.00), (1.00, 1.00, 1.00), (0.93, 0.90, 0.84)),
        ("blueprint", (0.05, 0.14, 0.33), (0.75, 0.85, 1.00), (0.86, 0.92, 1.00)),
        ("forest",    (0.05, 0.13, 0.09), (0.80, 0.92, 0.84), (0.89, 0.94, 0.88)),
        ("ember",     (0.14, 0.05, 0.03), (0.98, 0.86, 0.78), (0.99, 0.91, 0.85)),
        ("tide",      (0.02, 0.12, 0.14), (0.76, 0.93, 0.94), (0.86, 0.96, 0.96)),
        ("mono",      (0.11, 0.11, 0.12), (0.88, 0.88, 0.89), (0.95, 0.95, 0.96)),
    ]

    /// The floors the shipped palette already clears, so a new theme may not
    /// come in under them. Blueprint sets every one of these.
    static let digitFloor = 12.0
    static let gridFloor = 10.0
    static let coralFloor = 5.5

    /// The palette's worst pair under any of the three dichromacies. Set by
    /// Meadow/Teal under tritanopia and unchanged since 1.1 — a new accent must
    /// not become the new worst pair.
    static let separationFloor = 5.9

    /// PRD-16 shipped one grandfathered sub-AA pair — crimson on blueprint at
    /// 4.23:1 — and explicitly handed it to PRD-22. **PRD-22 retired it.**
    ///
    /// It was worse than 4.23 suggested. On the composited glass the shipped
    /// crimson measured below AA on *five* of the six dark themes, not one, and
    /// the raw number had simply never been the number the board drew. Crimson
    /// moved to (1.00, 0.36, 0.56): the closest value to the shipped tint (CIE76
    /// ΔE 5.84) that clears 4.5 on Blueprint — the binding ground for all ten
    /// accents — without becoming the palette's new worst dichromat pair. The
    /// obvious brighter candidate, (0.98, 0.40, 0.58), collides with Orchid
    /// under tritanopia at **ΔE 3.77**, which is the separation floor below
    /// doing exactly the job PRD-16 built it for.
    ///
    /// There is no exception now. A pair below AA is a regression.

    /// The light variants' worst dichromat pair, pinned rather than floored.
    /// They have never been under `separationFloor` and they are not now:
    /// deepening a palette compresses it, and the shipped light set was at ΔE
    /// **1.44** (glacier/lilac, deuteranopia). PRD-22's retune moves the worst
    /// pair to 3.17 — strictly better, still short of the vivid palette's 5.98,
    /// and recorded rather than closed because closing it is a palette redesign
    /// and not a contrast retune. Tighten this when it improves.
    static let lightSeparationFloor = 3.1

    // MARK: - Source parity

    private static var themeSource: String {
        get throws {
            let nine = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // EngineTests
                .deletingLastPathComponent()   // Tests
                .deletingLastPathComponent()   // nine
            return try String(
                contentsOf: nine.appendingPathComponent("Sources/App/Theme.swift"),
                encoding: .utf8)
        }
    }

    /// Swift source writes `0.33`, not `0.330000`. Two decimals is what every
    /// literal in `Theme.swift` uses; `1.0` is written `1.00`.
    private func lit(_ value: Double) -> String { String(format: "%.2f", value) }

    func testEveryAccentLiteralMatchesTheTable() throws {
        let source = try Self.themeSource
        for (name, rgb) in Self.accents {
            let expected =
                "case .\(name): return Color(red: \(lit(rgb.r)), green: \(lit(rgb.g)), blue: \(lit(rgb.b)))"
            XCTAssertTrue(
                source.contains(expected),
                "AccentChoice.\(name) no longer reads `\(expected)`. If the tint moved "
                    + "deliberately, move it in this table too — the contrast and "
                    + "separation floors below are asserted on the table, not on the app.")
        }
    }

    /// The table must be *complete*, not merely correct: a ninth accent added to
    /// the enum and forgotten here would ship unmeasured.
    func testAccentTableNamesEveryCase() throws {
        let source = try Self.themeSource
        let declared = try declaredCases(of: "AccentChoice", in: source)
        XCTAssertEqual(
            declared, Self.accents.map(\.name),
            "AccentChoice's cases and this test's table have diverged.")
    }

    func testThemeTableNamesEveryDarkCase() throws {
        let source = try Self.themeSource
        let declared = try declaredCases(of: "ThemeChoice", in: source)
        // `auto` resolves to Void or Paper and has no tones of its own; `light`
        // and `camel` are light-leaning (see `darkThemes`' doc comment).
        let expected = declared.filter { !["auto", "light", "camel"].contains($0) }
        XCTAssertEqual(
            expected, Self.darkThemes.map(\.name),
            "ThemeChoice's dark cases and this test's table have diverged.")
    }

    /// Reads `case a, b, c` off the first case line in the named enum's body.
    private func declaredCases(of enumName: String, in source: String) throws -> [String] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.hasPrefix("enum \(enumName):") }) else {
            XCTFail("enum \(enumName) not found in Theme.swift — did it move?")
            return []
        }
        guard let caseLine = lines[start...].first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("case ")
        }) else {
            XCTFail("enum \(enumName) declares no cases")
            return []
        }
        return caseLine
            .trimmingCharacters(in: .whitespaces)
            .dropFirst("case ".count)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Contrast (WCAG 2.1 relative luminance)

    func testEveryDarkThemeClearsTheContrastFloors() {
        for theme in Self.darkThemes {
            XCTAssertGreaterThanOrEqual(
                contrast(theme.digitTone, theme.background), Self.digitFloor,
                "\(theme.name): given digits fall below the floor Blueprint sets")
            XCTAssertGreaterThanOrEqual(
                contrast(theme.gridTone, theme.background), Self.gridFloor,
                "\(theme.name): grid tone falls below the floor Blueprint sets")
            XCTAssertGreaterThanOrEqual(
                contrast(Self.coral, theme.background), Self.coralFloor,
                "\(theme.name): the coral error marker is not legible on this ground")
        }
    }

    func testEveryAccentIsLegibleOnEveryDarkTheme() {
        for theme in Self.darkThemes {
            for accent in Self.accents {
                let ratio = contrast(accent.rgb, theme.background)
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    "\(accent.name) on \(theme.name) is \(String(format: "%.2f", ratio)):1, "
                        + "below WCAG AA for text. PRD-22 retired the one grandfathered "
                        + "exception this palette used to carry; there is no precedent to "
                        + "appeal to. Note this measures the *raw* constants — "
                        + "nine/scripts/contrast-harness.py measures what the board draws.")
            }
        }
    }

    /// The light variants are not measurable against a theme constant the way
    /// the vivid ones are — Paper and Camel reach the board through the glass,
    /// and that is `contrast-harness.py`'s job. What *is* checkable here is that
    /// they stayed deep: the retune's whole mechanism on light grounds is
    /// luminance, so a light variant drifting brighter is the regression.
    func testEveryLightAccentStaysDeep() {
        for accent in Self.lightAccents {
            let luminance = relativeLuminance(accent.rgb)
            XCTAssertLessThanOrEqual(
                luminance, 0.105,
                "\(accent.name)'s light variant is \(String(format: "%.3f", luminance)) "
                    + "relative luminance. PRD-22 solved these to 0.098 so the worst cell of "
                    + "the composited matrix (Camel) clears WCAG AA; brighter than 0.105 and "
                    + "it does not. See Tests/ContrastBaselines/matrix.txt.")
        }
        XCTAssertLessThanOrEqual(relativeLuminance(Self.coralOnLight), 0.13,
                                 "the light coral is the error marker on Paper and Camel")
    }

    func testLightVariantsAreNoLessSeparableThanTheyWere() {
        var palette = Self.lightAccents
        palette.append((name: "CORAL", rgb: Self.coralOnLight))
        for mode in Simulation.allCases {
            let seen = palette.map { (name: $0.name, rgb: simulate($0.rgb, mode)) }
            for i in seen.indices {
                for j in seen.indices where j > i {
                    XCTAssertGreaterThanOrEqual(
                        deltaE(seen[i].rgb, seen[j].rgb), Self.lightSeparationFloor,
                        "\(seen[i].name)/\(seen[j].name) under \(mode) — see "
                            + "`lightSeparationFloor`, which is a pin, not a target.")
                }
            }
        }
    }

    func testEveryLightAccentLiteralMatchesTheTable() throws {
        let source = try Self.themeSource
        for (name, rgb) in Self.lightAccents {
            let expected =
                "case .\(name): return Color(red: \(lit(rgb.r)), green: \(lit(rgb.g)), blue: \(lit(rgb.b)))"
            XCTAssertTrue(
                source.contains(expected),
                "AccentChoice.color(isLight:)'s \(name) no longer reads `\(expected)`.")
        }
    }

    // MARK: - Colorblind separation

    func testNoTwoAccentsCollideUnderAnyDichromacy() {
        var palette = Self.accents
        palette.append((name: "CORAL", rgb: Self.coral))
        for mode in Simulation.allCases {
            let seen = palette.map { (name: $0.name, rgb: simulate($0.rgb, mode)) }
            for i in seen.indices {
                for j in seen.indices where j > i {
                    let separation = deltaE(seen[i].rgb, seen[j].rgb)
                    XCTAssertGreaterThanOrEqual(
                        separation, Self.separationFloor,
                        "\(seen[i].name)/\(seen[j].name) are ΔE "
                            + "\(String(format: "%.2f", separation)) apart under \(mode) — at or "
                            + "below the palette's floor. Nudge the new tint's saturation or "
                            + "value, not its hue.")
                }
            }
        }
    }

    // MARK: - Color math

    private func linearize(_ channel: Double) -> Double {
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private func luminance(_ c: RGB) -> Double {
        0.2126 * linearize(c.r) + 0.7152 * linearize(c.g) + 0.0722 * linearize(c.b)
    }

    func relativeLuminance(_ c: RGB) -> Double { luminance(c) }

    func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Machado (2009) dichromat simulation matrices at full severity, applied in
    /// linear RGB. Deliberately the published constants, not an approximation:
    /// the whole point is that the numbers are reproducible off-repo.
    enum Simulation: CaseIterable, CustomStringConvertible {
        case normal, protanopia, deuteranopia, tritanopia

        var description: String {
            switch self {
            case .normal: return "normal vision"
            case .protanopia: return "protanopia"
            case .deuteranopia: return "deuteranopia"
            case .tritanopia: return "tritanopia"
            }
        }

        var matrix: [[Double]]? {
            switch self {
            case .normal:
                return nil
            case .protanopia:
                return [[0.152286, 1.052583, -0.204868],
                        [0.114503, 0.786281, 0.099216],
                        [-0.003882, -0.048116, 1.051998]]
            case .deuteranopia:
                return [[0.367322, 0.860646, -0.227968],
                        [0.280085, 0.672501, 0.047413],
                        [-0.011820, 0.042940, 0.968881]]
            case .tritanopia:
                return [[1.255528, -0.076749, -0.178779],
                        [-0.078411, 0.930809, 0.147602],
                        [0.004733, 0.691367, 0.303900]]
            }
        }
    }

    func simulate(_ c: RGB, _ mode: Simulation) -> RGB {
        guard let m = mode.matrix else { return c }
        let v = [linearize(c.r), linearize(c.g), linearize(c.b)]
        func encode(_ value: Double) -> Double {
            let clamped = min(max(value, 0), 1)
            return clamped <= 0.0031308
                ? 12.92 * clamped
                : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        }
        func row(_ i: Int) -> Double { (0..<3).reduce(0) { $0 + m[i][$1] * v[$1] } }
        return (encode(row(0)), encode(row(1)), encode(row(2)))
    }

    /// CIE76 ΔE in Lab (D65). CIE76 rather than CIEDE2000 on purpose: the
    /// threshold here is "are these two swatches obviously different", not
    /// "is this a just-noticeable difference", and CIE76 is the formula the
    /// published dichromat-palette literature quotes.
    func deltaE(_ a: RGB, _ b: RGB) -> Double {
        func lab(_ c: RGB) -> (Double, Double, Double) {
            let (r, g, bl) = (linearize(c.r), linearize(c.g), linearize(c.b))
            let x = 0.4124 * r + 0.3576 * g + 0.1805 * bl
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * bl
            let z = 0.0193 * r + 0.1192 * g + 0.9505 * bl
            func f(_ t: Double) -> Double {
                t > 0.008856 ? pow(t, 1.0 / 3.0) : 7.787 * t + 16.0 / 116.0
            }
            let (fx, fy, fz) = (f(x / 0.95047), f(y / 1.0), f(z / 1.08883))
            return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
        }
        let (la, aa, ba) = lab(a)
        let (lb, ab, bb) = lab(b)
        return ((la - lb) * (la - lb) + (aa - ab) * (aa - ab) + (ba - bb) * (ba - bb))
            .squareRoot()
    }
}
