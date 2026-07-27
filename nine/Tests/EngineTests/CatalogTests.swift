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

    /// **The declaration is derived, not remembered** (controller ruling,
    /// 2026-07-26, at the head of Task 9).
    ///
    /// `CFBundleLocalizations` is authoritative when present, so it must equal
    /// the set of locales that actually carry translations, and it must do so
    /// in *both* directions:
    ///
    ///   • A declared locale with no translations is not harmless optimism.
    ///     Merging to `main` triggers `beta_all`, and a Japanese TestFlight
    ///     tester on a `ja`-declaring build gets Japanese system UI and
    ///     Japanese month names — `ArchiveCalendar`'s formatter follows
    ///     `Locale.current` on purpose — wrapped around English prose. App
    ///     Store Connect would also list the app as localized into ten
    ///     languages on the strength of the plist alone.
    ///   • A translated locale nobody declared is worse in the other direction:
    ///     the translation ships in the binary and no player is ever shown it.
    ///
    /// Task 9 adds the nine locales to the catalog and flips this list in the
    /// same commit. This test is what makes that atomic; "remember to flip it
    /// later" is not a mechanism.
    ///
    /// Read out of `project.yml` rather than the built `Info.plist`s, and that
    /// is deliberate: xcodegen *generates* `Info.plist` and `WidgetsInfo.plist`
    /// and `.gitignore` excludes both, so the fast lane — which runs `swift
    /// test` with no `xcodegen` step — has no plist to read. `project.yml` is
    /// the source both are generated from, and the built artifact is checked
    /// separately with `plutil` in the task report.
    func testDeclaredLocalizationsMatchTranslatedLocales() throws {
        let catalog = try Self.catalog()
        let translated = Set(catalog.values.flatMap(\.locales)).sorted()
        XCTAssertEqual(translated, ["en"], """
            The catalog now carries \(translated) — if that is Task 9 landing, \
            this expectation and both CFBundleLocalizations lists move together, \
            in one commit.
            """)

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
                .sorted()
            XCTAssertEqual(list, translated, """
                The declared locales and the translated locales disagree. \
                Declared \(list); the catalog carries \(translated).
                A declared locale with no translations ships a TestFlight build \
                that says it speaks a language it does not. A translated locale \
                nobody declared ships work no player is ever shown.
                """)
        }

        XCTAssertEqual(Self.occurrences(of: "CFBundleDevelopmentRegion: en", in: yml), 2,
                       "English is the source language; both bundles must say so.")
    }

    // MARK: - The two entry points

    /// Every `@main` installs the catalog, exactly once, and early enough.
    ///
    /// **This is the check whose absence would be invisible to everything
    /// else.** Delete the `Strings.install()` line from `NineWidgetBundle` and:
    /// the whole suite passes, three platform builds go green, and both bundles
    /// still ship 84 keys and their declared locales — while the widget is
    /// permanently English, because `Phrasebook.current` falls back to
    /// `.english` when nothing is installed. That is the same shape as PRD-16's
    /// alternate icons compiling green with no `CFBundleAlternateIcons` at all,
    /// which is the lesson this file's header already cites.
    ///
    /// Two entry points, two processes, one install each (controller ruling,
    /// 2026-07-26). `Phrasebook.install` is a `precondition` that survives
    /// `-O`, so a *second* call in one process traps in the shipping app —
    /// which is why "exactly one" is asserted rather than "at least one".
    ///
    /// The ordering clause is the part an editor breaks without noticing. The
    /// whole argument for the install being a stored property rather than a
    /// line in `init` is that Swift applies stored-property defaults in
    /// declaration order, ahead of the `init` body — so it resolves before
    /// `@State private var model = AppModel()`, which is itself such a default.
    /// Move the line below `model` and nothing complains; the install is simply
    /// second, and `AppModel` is one change away from asking for a phrase
    /// first.
    func testEachEntryPointInstallsTheCatalog() throws {
        let entryPoints = ["Sources/App/NineApp.swift", "Sources/Widgets/NineWidgetBundle.swift"]

        for path in entryPoints {
            let source = try Self.codeOnly(at: path)
            XCTAssertEqual(Self.occurrences(of: "@main", in: source), 1,
                           "\(path) is expected to be an entry point")
            XCTAssertEqual(Self.occurrences(of: "Strings.install()", in: source), 1, """
                \(path) must call `Strings.install()` exactly once. Zero leaves \
                `Phrasebook.current` as `.english` for the life of that process \
                — the app or the widget stays English in every language, and \
                nothing else in this repo notices. Two trips the `precondition` \
                in `Phrasebook.install`, in Release, at launch.
                """)
        }

        // …and in NineApp, before the model.
        let app = try Self.codeOnly(at: entryPoints[0])
        let install = try XCTUnwrap(app.range(of: "Strings.install()"),
                                    "no install in NineApp.swift")
        let model = try XCTUnwrap(app.range(of: "var model = AppModel()"),
                                  "NineApp no longer builds its AppModel as a stored-property default "
                                  + "— re-derive what the install has to precede before editing this test")
        XCTAssertLessThan(install.lowerBound, model.lowerBound, """
            `Strings.install()` must be declared ABOVE `var model = AppModel()` \
            in NineApp.swift. Stored-property defaults are applied in \
            declaration order, before the `init` body — that ordering is the \
            entire reason the install is a stored property here rather than a \
            line in `init`, and it is invisible at every other level. Below the \
            model it still compiles, still passes every other test, and is \
            simply one `AppModel` change away from being too late.
            """)
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

    /// The App layer builds the same two keys the Shared layer does, and this
    /// is the only thing that says so.
    ///
    /// `testEveryEngineIdentifierIsNamed` above pins the *catalog*, not the
    /// caller. The formula lives in four places across a layer boundary —
    /// `Strings.technique(_:)` and `Strings.difficulty(_:)` in
    /// `Sources/Strings`, `BoardSpeech.Phrase.techniqueName` and
    /// `SolveCardFacts.Phrase.difficulty` in `Sources/Shared` — and only the
    /// Shared pair is reachable from `swift test` at all: `Sources/Strings` is
    /// not a SwiftPM target, because `LocalizedStringResource` does not exist
    /// on Linux.
    ///
    /// So typo `Strings.difficulty`'s key to `difficulty.\(raw).name` and every
    /// difficulty label on all three platforms renders the literal string
    /// `difficulty.gentle.name`, with a green suite, a green
    /// `testEveryEngineIdentifierIsNamed`, and three green builds. Read the
    /// file, the way this class already reads `project.yml`.
    ///
    /// Exact strings rather than a shape, because the interesting failure is a
    /// key that is still well-formed.
    func testTheAppLayerBuildsTheSameKeysAsShared() throws {
        let strings = try String(contentsOf: Self.nineRoot.appendingPathComponent("Sources/Strings/Strings.swift"),
                                 encoding: .utf8)

        for (formula, shared) in [
            (#""technique.\(technique.rawValue).name""#, "BoardSpeech.Phrase.techniqueName"),
            (#""difficulty.\(difficulty.rawValue).title""#, "SolveCardFacts.Phrase.difficulty"),
        ] {
            XCTAssertEqual(Self.occurrences(of: formula, in: strings), 1, """
                Strings.swift must build the key as \(formula), exactly as \
                \(shared) does. `swift test` cannot compile Sources/Strings — it \
                is not a SwiftPM target — so a typo there is a well-formed key \
                that resolves to itself, printed on every platform, with every \
                test in this repo still green.
                """)
        }
    }

    // MARK: - Readers

    struct Entry {
        let comment: String
        let english: String?
        let englishState: String?
        /// Every locale this entry carries. The union across entries is what
        /// `CFBundleLocalizations` has to equal.
        let locales: [String]
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
            let localizations = body["localizations"] as? [String: Any] ?? [:]
            let unit = (localizations["en"] as? [String: Any])?["stringUnit"] as? [String: Any]
            entries[key] = Entry(comment: body["comment"] as? String ?? "",
                                 english: unit?["value"] as? String,
                                 englishState: unit?["state"] as? String,
                                 locales: localizations.keys.sorted())
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

    /// A Swift file with its comments blanked out, offsets preserved.
    ///
    /// Necessary rather than tidy, and it caught itself: the doc comments on
    /// `NineApp.phrasebook` and `NineWidgetBundle.phrasebook` *explain* the
    /// install, so they contain the literal `Strings.install()` — and the first
    /// version of the entry-point test counted two of everything and failed on
    /// its own prose. `StringSealTests.stripComments` replaces comment bodies
    /// with spaces and keeps every newline, so a byte offset into the result is
    /// still a byte offset into the file: which is what the ordering assertion
    /// needs.
    static func codeOnly(at path: String) throws -> String {
        let raw = try String(contentsOf: nineRoot.appendingPathComponent(path), encoding: .utf8)
        return String(StringSealTests.stripComments(Array(raw)))
    }

    static let nineRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // EngineTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // nine
}
