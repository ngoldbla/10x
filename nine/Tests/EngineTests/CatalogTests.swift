// CatalogTests — the catalog is a build input for two bundles, and every way it
// can be wrong is silent (PRD-20 "Nine Languages").
//
// `Sources/Shared` and `Sources/Engine` compile into Nine.app AND into
// NineWidgets.appex (`project.yml`, `targets.Nine.sources` vs
// `targets.NineWidgets.sources`). In an app extension `Bundle.main` IS the
// extension, so a catalog listed by only one target gives the widget an
// English-only Home Screen on a Japanese phone — and every platform build stays
// green while it does. That is PRD-16's `CFBundleAlternateIcons` lesson in a
// different file: it compiled green with the key absent from Info.plist
// entirely, and `plutil -p` on the built artifact was the only thing that
// disagreed.
//
// These tests read the catalog, `project.yml` and `EnglishPhrases.swift` as
// *files*, following `AppearancePaletteTests` and `VariantChannelSealTests`.
// They have to: `Sources/Strings` is deliberately not a SwiftPM target
// (`LocalizedStringResource` does not exist on Linux and `Package.swift` must
// stay Linux-clean), so nothing here can link `Strings` and ask it. What this
// target CAN link is `NineEngine`, which is why the Engine-identifier test
// below uses `Technique.allCases` rather than parsing an enum out of a file.
//
// Nothing here imports anything Darwin-only: EngineTests must keep running on
// Linux CI alongside the golden corpus.
import XCTest
import Foundation
@testable import NineEngine

final class CatalogTests: XCTestCase {

    /// PRD-20's launch set: English plus nine languages, in the order
    /// `project.yml` declares them.
    static let launchLocales = ["en", "ja", "de", "fr", "es", "it", "pt-BR", "ko", "zh-Hans", "nl"]

    // MARK: - The two bundles

    func testBothTargetsListTheStringsTree() throws {
        let yml = try String(contentsOf: Self.nineRoot.appendingPathComponent("project.yml"),
                            encoding: .utf8)
        XCTAssertEqual(Self.occurrences(of: "- Sources/Strings", in: yml), 2, """
            Sources/Strings must be listed by BOTH the Nine and NineWidgets \
            targets. NineWidgets compiles Sources/Shared and Sources/Engine in, \
            so it asks for the same keys — but against its OWN bundle, because \
            in an app extension `Bundle.main` is the extension. A widget \
            without the catalog renders English on a localized phone, and every \
            platform build stays green.
            """)

        // Sources/Shared is the tree whose presence in both targets is the
        // whole reason the catalog has to be in both. If that ever stops being
        // true, the assertion above is measuring nothing.
        XCTAssertEqual(Self.occurrences(of: "- Sources/Shared", in: yml), 2,
                       "Sources/Shared is no longer in two targets — re-derive why "
                       + "the catalog needs to be, before trusting the test above.")
    }

    func testDeclaredLocalizationsAreExactlyTheNineLaunchLocales() throws {
        let yml = try String(contentsOf: Self.nineRoot.appendingPathComponent("project.yml"),
                            encoding: .utf8)

        let declared = yml.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("CFBundleLocalizations:") }

        // Two: the app's Info.plist and the widget extension's. An extension is
        // a separate bundle with a separate Info.plist, so "the app declares
        // it" is not a fact about the widget.
        XCTAssertEqual(declared.count, 2, """
            CFBundleLocalizations must be declared by BOTH bundles — Nine.app \
            and NineWidgets.appex. Found \(declared.count).
            """)

        for line in declared {
            let list = line
                .replacingOccurrences(of: "CFBundleLocalizations:", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " []"))
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            XCTAssertEqual(list, Self.launchLocales, """
                The declared locales are not PRD-20's ten. A locale the catalog \
                carries but the bundle does not advertise is simply never \
                chosen — the app falls back to English with no error anywhere, \
                which is the failure this whole PRD exists to make impossible.
                """)
        }

        XCTAssertEqual(Self.occurrences(of: "CFBundleDevelopmentRegion: en", in: yml), 2,
                       "English is the source language; both bundles must say so.")
    }

    // MARK: - The catalog itself

    func testEveryEnglishPhraseHasACatalogEntry() throws {
        let table = try Self.englishPhrasesTable()
        let catalog = try Self.catalog()

        XCTAssertFalse(table.isEmpty, "read no phrases out of EnglishPhrases.swift — did its shape change?")

        // `EnglishPhrases.table` is the source of truth and the catalog's `en`
        // is generated from it (`scripts/strings.py --build-catalog`). Drift in
        // either direction means someone hand-edited one of the two, which is
        // the one thing generating it was supposed to make impossible.
        let missing = table.keys.filter { catalog[$0] == nil }.sorted()
        XCTAssertEqual(missing, [], """
            \(missing.count) phrase(s) in EnglishPhrases.table with no catalog \
            entry. They will resolve to their own key on every device, in every \
            language including English.
            Fix: `python3 scripts/strings.py --build-catalog`.
            """)

        let extra = catalog.keys.filter { table[$0] == nil }.sorted()
        XCTAssertEqual(extra, [], """
            \(extra.count) catalog entry/entries that EnglishPhrases.table does \
            not name. Translators are paid per string, and Task 9 freezes this \
            catalog into nine languages.
            Fix: `python3 scripts/strings.py --build-catalog`.
            """)

        for (key, english) in table.sorted(by: { $0.key < $1.key }) {
            guard let entry = catalog[key] else { continue }
            XCTAssertEqual(entry.english, english, """
                \(key) reads "\(entry.english ?? "<none>")" in the catalog and \
                "\(english)" in EnglishPhrases.table. `BoardSpeechTests` asserts \
                against the table and the player reads the catalog, so a \
                disagreement here is a test that passes about words nobody sees.
                """)

            // A comment is the translator's only context. "Sharp" is
            // unguessable without one, and `board.announce.solved` ("Solved.",
            // a spoken sentence) versus `archive.day.solved` ("solved", a
            // fragment appended to a date) are different parts of speech that
            // get confused exactly once per language.
            XCTAssertFalse(entry.comment.isEmpty,
                           "\(key) has no translator comment — see COMMENTS in scripts/strings.py.")

            // The source language is never in doubt, and a `needs_review` en
            // would quietly mean "this English is a guess".
            XCTAssertEqual(entry.englishState, "translated",
                           "\(key)'s English is marked \"\(entry.englishState ?? "<none>")\".")
        }
    }

    /// Every Engine identifier the app has to name is named.
    ///
    /// The Engine stopped naming things (`Technique.displayName` and
    /// `Difficulty.title` are gone), so the only thing standing between
    /// appending a `Technique` case and shipping the raw string
    /// "technique.myNewOne.name" on a coach card is this test. It uses
    /// `allCases` rather than a list, because a list would be the second,
    /// unfrozen copy the deletion was meant to remove.
    func testEveryEngineIdentifierIsNamed() throws {
        let catalog = try Self.catalog()

        for technique in Technique.allCases {
            let key = "technique.\(technique.rawValue).name"
            let entry = try XCTUnwrap(catalog[key], """
                \(technique) has no catalog entry. Add `\(key)` to \
                EnglishPhrases.table and run \
                `python3 scripts/strings.py --build-catalog`.
                """)
            XCTAssertNotEqual(entry.english, key, "\(key) is its own value")
        }

        for difficulty in Difficulty.allCases {
            let key = "difficulty.\(difficulty.rawValue).title"
            let entry = try XCTUnwrap(catalog[key], """
                \(difficulty) has no catalog entry. Add `\(key)` to \
                EnglishPhrases.table and run \
                `python3 scripts/strings.py --build-catalog`.
                """)
            XCTAssertNotEqual(entry.english, key, "\(key) is its own value")
        }
    }

    // MARK: - Readers

    struct Entry {
        let comment: String
        let english: String?
        let englishState: String?
    }

    /// The catalog, as key → entry. `JSONSerialization` rather than `Codable`
    /// so a shape change reads as a nil rather than a thrown decode nobody can
    /// locate.
    static func catalog() throws -> [String: Entry] {
        let url = nineRoot.appendingPathComponent("Sources/Strings/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any],
                                 "the catalog is not a JSON object")
        XCTAssertEqual(root["sourceLanguage"] as? String, "en",
                       "English is the source language everything else is generated from")
        let strings = try XCTUnwrap(root["strings"] as? [String: Any],
                                    "the catalog has no `strings` object")

        var entries: [String: Entry] = [:]
        for (key, value) in strings {
            let body = value as? [String: Any] ?? [:]
            let unit = ((body["localizations"] as? [String: Any])?["en"]
                as? [String: Any])?["stringUnit"] as? [String: Any]
            entries[key] = Entry(comment: body["comment"] as? String ?? "",
                                 english: unit?["value"] as? String,
                                 englishState: unit?["state"] as? String)
        }
        return entries
    }

    /// `EnglishPhrases.table`, read out of the Swift source.
    ///
    /// This target does not link `NineShared` (`Package.swift`:
    /// `NineEngineTests` depends on `NineEngine` alone), so the table has to be
    /// read rather than asked for. That is exactly the shape contract
    /// `EnglishPhrases.swift`'s header states and
    /// `PhrasebookTests.testTableIsOneSortedEntryPerLineSoAScriptCanReadIt`
    /// enforces from the other side, against the compiled dictionary — so this
    /// reader cannot silently drift from what the app really says.
    ///
    /// No unescaping, deliberately, and the same in the Python reader: nothing
    /// in the table contains a backslash today, and a reader that quietly
    /// un-escaped would hide the day one does.
    static func englishPhrasesTable() throws -> [String: String] {
        let url = nineRoot.appendingPathComponent("Sources/Shared/EnglishPhrases.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        var table: [String: String] = [:]
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("\""), text.hasSuffix("\","), text.count > 5 else { continue }
            let body = String(text.dropFirst().dropLast(2))
            guard let separator = body.range(of: "\": \"") else { continue }
            table[String(body[body.startIndex ..< separator.lowerBound])] =
                String(body[separator.upperBound...])
        }
        return table
    }

    static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    static let nineRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // EngineTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // nine
}
