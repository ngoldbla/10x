// The two catalogs `scripts/strings.py` cannot own (PRD-33).
//
// `Localizable.xcstrings` is *generated* from `EnglishPhrases.table`, and
// `strings.py --audit` fails on any row no Swift file reaches through the
// accessors it knows how to read. Neither of the catalogs here can live in it:
//
//   • `Sources/Shortcuts/Intents.xcstrings` — App Intents titles, descriptions and
//     enum case names. `appintentsmetadataprocessor` is a **static** extractor and
//     rejects `Strings.resource(_:)` outright ("must be initialized with a call to
//     its initializer or a string literal"), so these have to be
//     `LocalizedStringResource` literals rather than runtime lookups.
//   • `Sources/App/AppShortcuts.xcstrings` — the spoken phrases. Its keys are
//     English sentences, not dotted identifiers, and its schema belongs to a build
//     phase (`appshortcutstringsprocessor`).
//
// So they are hand-authored, and this file is the mechanism that keeps them
// honest. It applies the same four rules `CatalogTests` applies to the big
// catalog — bijection with the source, every launch locale present, every machine
// draft marked `needs_review`, coined names left alone — by a different route:
// reading the Swift as text, because these targets are not on this one's source
// list.
//
// The build already checks two things this cannot, and they are the reason the
// phrase file is only half-checked here: `appshortcutstringsprocessor` verifies
// every phrase matches a real App Shortcut and that every locale keeps
// `${applicationName}`. Falsified by hand — dropping it from the German of one
// phrase fails the build with "Invalid Utterance".
import XCTest

final class IntentCatalogTests: XCTestCase {

    static let nineRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // EngineTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // nine

    /// The nine launch locales, in `CatalogTests`'s order.
    static let launchLocales = ["ja", "de", "fr", "es", "it", "pt-BR", "ko", "zh-Hans", "nl"]

    // MARK: Reading

    private struct Catalog {
        let strings: [String: [String: Any]]

        init(_ path: String) throws {
            let url = IntentCatalogTests.nineRoot.appendingPathComponent(path)
            let data = try Data(contentsOf: url)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let raw = (object?["strings"] as? [String: Any]) ?? [:]
            strings = raw.compactMapValues { $0 as? [String: Any] }
        }

        func localizations(_ key: String) -> [String: Any] {
            (strings[key]?["localizations"] as? [String: Any]) ?? [:]
        }

        func state(_ key: String, _ locale: String) -> String? {
            let unit = (localizations(key)[locale] as? [String: Any])?["stringUnit"]
            return (unit as? [String: Any])?["state"] as? String
        }

        func value(_ key: String, _ locale: String) -> String? {
            let unit = (localizations(key)[locale] as? [String: Any])?["stringUnit"]
            return (unit as? [String: Any])?["value"] as? String
        }
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: Self.nineRoot.appendingPathComponent(relative), encoding: .utf8
        )
    }

    /// Every `"intent.…"` literal anywhere under `Sources/`.
    private func intentKeysInSource() throws -> Set<String> {
        var keys: Set<String> = []
        let root = Self.nineRoot.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let item = files?.nextObject() as? URL {
            guard item.pathExtension == "swift",
                  let text = try? String(contentsOf: item, encoding: .utf8) else { continue }
            var rest = Substring(text)
            while let open = rest.range(of: "\"intent.") {
                let after = rest[open.upperBound...]
                guard let close = after.firstIndex(of: "\"") else { break }
                keys.insert("intent." + String(after[..<close]))
                rest = after[close...]
            }
        }
        return keys
    }

    // MARK: - Intents.xcstrings

    func testEveryIntentKeyInSourceHasARowAndEveryRowIsUsed() throws {
        let catalog = try Catalog("Sources/Shortcuts/Intents.xcstrings")
        let used = try intentKeysInSource()
        // 15 keys since the daily/streak/focus intents left (2026-08-02).
        XCTAssertGreaterThan(used.count, 10,
                             "found \(used.count) intent keys in Sources — the literal "
                             + "shape changed and this test is reading nothing")
        XCTAssertEqual(
            used, Set(catalog.strings.keys),
            """
            `Intents.xcstrings` and the Swift have drifted. A key in the source with \
            no row renders as the dotted identifier in Shortcuts, Siri and the \
            widget-configuration sheet — and nothing fails, because \
            `appintentsmetadataprocessor` only extracts keys and never resolves \
            them. A row with no key is a string a translator is paid for and \
            nobody reads.
            """
        )
    }

    func testEveryIntentRowCarriesEveryLaunchLocaleAndAComment() throws {
        let catalog = try Catalog("Sources/Shortcuts/Intents.xcstrings")
        for key in catalog.strings.keys.sorted() {
            let comment = catalog.strings[key]?["comment"] as? String
            XCTAssertFalse((comment ?? "").isEmpty,
                           "\(key) has no translator comment. Carry three things: part "
                           + "of speech, where it appears, what the arguments are.")
            XCTAssertEqual(catalog.state(key, "en"), "translated", "\(key) [en]")
            for locale in Self.launchLocales {
                XCTAssertNotNil(catalog.value(key, locale), "\(key) [\(locale)] missing")
                XCTAssertEqual(catalog.state(key, locale), "needs_review",
                               "\(key) [\(locale)] — every machine draft is "
                               + "`needs_review` until a human has read it")
            }
        }
    }

    /// The bands the intents offer are all descriptions and must translate.
    /// (The coined deep-end names left the intent catalog with the deep bands
    /// themselves, 2026-08-02.)
    func testOfferedBandNamesAreTranslated() throws {
        let catalog = try Catalog("Sources/Shortcuts/Intents.xcstrings")
        for band in ["gentle", "steady", "sharp"] {
            let key = "intent.band.\(band)"
            let english = try XCTUnwrap(catalog.value(key, "en"), key)
            for locale in Self.launchLocales {
                XCTAssertNotEqual(catalog.value(key, locale), english,
                                  "\(key) [\(locale)] is still English")
            }
        }
    }

    /// Every *offered* band needs a case in `NineBand` and a row in the
    /// catalog. `NineBand` is a parallel enum by necessity — `Difficulty` lives in
    /// `Sources/Engine`, which may not import AppIntents — and a parallel enum is a
    /// thing that drifts. Since 2026-08-02 the offer is exactly three
    /// (gentle/steady/sharp): the engine keeps six cases for persistence
    /// identity, and this test pins the intent surface to the offered three.
    func testEveryOfferedBandHasAnIntentCaseAndARow() throws {
        let bands = ["gentle", "steady", "sharp"]

        // The engine must still carry all six cases — the raw values are
        // frozen persistence identity, and the offered three must be among
        // them. Parsed from the source so this cannot drift silently.
        let generator = try source("Sources/Engine/Generator.swift")
        var engineBands: [String] = []
        for line in generator.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("case ") else { continue }
            guard trimmed.contains("gentle") || trimmed.contains("tempest") else { continue }
            engineBands += trimmed.dropFirst("case ".count)
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if engineBands.count >= 6 { break }
        }
        XCTAssertEqual(engineBands.count, 6,
                       "parsed \(engineBands) from `Difficulty` — the case list moved and "
                       + "this test is reading nothing")
        XCTAssertTrue(Set(engineBands).isSuperset(of: bands),
                      "an offered band is not an engine band")

        // `NineBand`'s cases, parsed rather than substring-matched. The first draft
        // of this asked `intents.contains("case \(band)")`, which is false for every
        // case after the first on a comma-separated line and false for the last one
        // either way — it reported a missing `abyss` that was right there. A test
        // that measures its own labelling is the shape of failure `PRD-31`'s margin
        // bar had, so this reads the list.
        let intents = try source("Sources/App/NineIntents.swift")
        let caseLine = try XCTUnwrap(
            intents.split(separator: "\n").first { $0.contains("case gentle") },
            "`NineBand` has no case list starting `case gentle` — this test is "
            + "reading nothing"
        )
        let intentBands = Set(
            caseLine.trimmingCharacters(in: .whitespaces)
                .dropFirst("case ".count)
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        )

        let catalog = try Catalog("Sources/Shortcuts/Intents.xcstrings")
        XCTAssertEqual(
            intentBands, Set(bands),
            """
            `NineBand` and the offered-band list have drifted. A band the UI \
            offers and `NineBand` does not name is a band Shortcuts cannot \
            start; the reverse is a Shortcuts entry offering a band no other \
            surface does.
            """
        )
        for band in bands {
            XCTAssertNotNil(catalog.value("intent.band.\(band)", "en"),
                            "no catalog row for intent.band.\(band)")
        }
    }

    // MARK: - AppShortcuts.xcstrings

    func testEveryPhraseInSourceHasARowAndEveryRowIsAPhrase() throws {
        let catalog = try Catalog("Sources/App/AppShortcuts.xcstrings")
        let intents = try source("Sources/App/NineIntents.swift")

        // The Swift writes `\(.applicationName)`; the catalog's key writes
        // `${applicationName}`. Same for the band placeholder. That substitution is
        // the schema `appshortcutstringsprocessor` reads, not a convention.
        var inSource: Set<String> = []
        var rest = Substring(intents)
        while let open = rest.range(of: "\"") {
            let after = rest[open.upperBound...]
            guard let close = after.firstIndex(of: "\"") else { break }
            let literal = String(after[..<close])
            if literal.contains("\\(.applicationName)") {
                inSource.insert(
                    literal
                        .replacingOccurrences(of: "\\(.applicationName)",
                                              with: "${applicationName}")
                        .replacingOccurrences(of: "\\(\\.$band)", with: "${band}")
                )
            }
            rest = after[after.index(after: close)...]
        }

        // Four phrases across the two shortcuts since 2026-08-02.
        XCTAssertGreaterThanOrEqual(inSource.count, 4,
                                    "found \(inSource.count) phrases in NineIntents — "
                                    + "the literal shape changed")
        XCTAssertEqual(
            inSource, Set(catalog.strings.keys),
            """
            `AppShortcuts.xcstrings` and `NineShortcuts.appShortcuts` have drifted. \
            A phrase with no row ships English-only in every language; a row with no \
            phrase fails the build's own validator.
            """
        )
    }

    func testEveryPhraseRowIsFullyDraftedAndKeepsItsPlaceholders() throws {
        let catalog = try Catalog("Sources/App/AppShortcuts.xcstrings")
        for key in catalog.strings.keys.sorted() {
            XCTAssertFalse(((catalog.strings[key]?["comment"] as? String) ?? "").isEmpty,
                           "\(key) has no translator comment")
            XCTAssertEqual(catalog.state(key, "en"), "translated", "\(key) [en]")
            let wantsBand = key.contains("${band}")
            for locale in Self.launchLocales {
                let value = try XCTUnwrap(catalog.value(key, locale),
                                          "\(key) [\(locale)] missing")
                XCTAssertEqual(catalog.state(key, locale), "needs_review",
                               "\(key) [\(locale)]")
                // The build validates this one too; asserting it here means a
                // regression is caught by `swift test` in seconds rather than by a
                // simulator build in minutes.
                XCTAssertTrue(value.contains("${applicationName}"),
                              "\(key) [\(locale)] dropped ${applicationName}")
                if wantsBand {
                    XCTAssertTrue(value.contains("${band}"),
                                  "\(key) [\(locale)] dropped the ${band} placeholder — "
                                  + "the phrase would match no difficulty")
                }
            }
        }
    }
}
