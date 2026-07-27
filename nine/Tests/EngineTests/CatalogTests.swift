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

            // …and unconditionally. Counting the call is not enough, and this
            // codebase has already been bitten by exactly the difference:
            // `NineApp.init` was `#if os(macOS)`-gated, which is *why* iOS and
            // tvOS had no install site at all while every build stayed green.
            // A `#if` around this line puts the count at one and the install at
            // zero on the platforms the fence excludes — and there is no
            // legitimate reason for one, because `Sources/Strings` is compiled
            // into both bundles on every platform (`project.yml`).
            XCTAssertEqual(Self.conditionalDepth(of: "Strings.install()", in: source), 0, """
                `Strings.install()` in \(path) is inside a `#if`. On every \
                platform that fence excludes, the call does not exist and \
                `Phrasebook.current` stays `.english` for the life of the \
                process — which is precisely how iOS and tvOS shipped with no \
                install at all, behind an `init` that was `#if os(macOS)`.
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

    // MARK: - Plurals

    /// **The gate Apple's tooling does not give you.**
    ///
    /// Measured on this machine, at the head of this task: a plural entry
    /// missing the CLDR `other` category compiles clean —
    /// `xcstringstool compile`, **exit 0, no warning** — and the compiled
    /// `.stringsdict` then renders `(null)` for every count that is not 1.
    /// Not the key, which at least reads like a bug report: the four
    /// characters `(null)`, on the share card, in German, with every build
    /// green and every platform building. (The brief expected the key; the
    /// measurement said `(null)`, and `(null)` is worse.)
    ///
    /// So the tool cannot be the gate, and this is. It runs in the cheap lane,
    /// before any simulator exists, over the catalog as a file.
    ///
    /// **What a hole actually does**, pinned against Foundation rather than
    /// assumed, because the two cases are not the same failure. It resolves the
    /// computed category, else `other`, else nothing:
    ///
    ///     fr/noOther:  n=2       -> "(null)"   a blank on screen
    ///     fr/noMany:   n=10^6    -> the `other` form, silently
    ///
    /// A missing `other` goes blank; a missing minority category degrades to
    /// `other` and reads as wrong grammar. Both are required below and the
    /// failure message says which is which, because a reviewer told to expect
    /// `(null)` and shown a plural form will conclude the gate is broken.
    ///
    /// The categories below are the CLDR **cardinal** rules for the nine launch
    /// locales plus the source language, and they are the categories a
    /// translation MUST carry — not the ones it may. A locale is allowed to
    /// carry more (a translator who writes `few` for a language whose rules
    /// never select it is harmless); it is never allowed to carry fewer.
    ///
    /// **Read out of CLDR, not remembered.** Every row below was checked
    /// against babel 2.18.0 by evaluating each locale's rule over
    /// `0...29, 100, 1000, 10^6, 2×10^6, 10^7, 10^9` and collecting the
    /// categories that came back. That is how the `many` row below stopped
    /// being pt-BR alone: the brief's table gave `it`, `es` and `fr` only
    /// `{one, other}`, and all three select `many` at multiples of 1,000,000
    /// exactly as pt-BR does.
    static let requiredPluralCategories: [String: Set<String>] = [
        "en": ["one", "other"],
        // `one` is exactly n == 1 here, and n = 0 is `other`.
        "de": ["one", "other"],
        "nl": ["one", "other"],
        // These four all select `many` at multiples of 1,000,000, and Foundation
        // really does select it — driven, not assumed:
        //
        //     fr/complete:  0=ONE  1=ONE  2=OTHER  1000000=MANY
        //
        // **A missing `many` is not the same failure as a missing `other`**, and
        // the difference is measured rather than reasoned. Foundation resolves
        // the computed category, else `other`, else nothing:
        //
        //     fr/noMany:   1000000=OTHER      ← silent, wrong grammar
        //     fr/noOther:  2=(null)           ← blank
        //
        // So a hole in `many` degrades to the plural form instead of going
        // blank. It is still required, for two reasons. Nine has counts that
        // are not bounded by the board — `shelf.points.chip` and
        // `widget.daily.points` print a lifetime points total — so a French
        // player who reaches a million points reads the wrong grammar rather
        // than a truncated one. And "the app cannot reach it" is a fact about
        // this month's code, while the catalog is frozen into nine languages.
        //
        // `fr` and `pt-BR` additionally select `one` at n = **0** as well as 1
        // (`fr/complete: 0=ONE` above). That does not change what they must
        // carry; it is recorded here and at `BoardSpeech.digitNoun` because it
        // is the difference between "the ternary is CLDR's rule" and "the
        // ternary is safe because of a guard".
        "it": ["one", "many", "other"],
        "es": ["one", "many", "other"],
        "fr": ["one", "many", "other"],
        "pt-BR": ["one", "many", "other"],
        // The three that inflect nothing. `other` alone, and asserting it is
        // not ceremony: an entry that carries only `one` in Japanese renders
        // `(null)` for every count on earth, because ja never selects `one`.
        "ja": ["other"],
        "ko": ["other"],
        "zh-Hans": ["other"],
    ]

    func testEveryPluralHasTheCategoriesItsLanguageRequires() throws {
        let url = Self.nineRoot.appendingPathComponent("Sources/Strings/Localizable.xcstrings")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                                 as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        var checked = 0
        for (key, value) in strings.sorted(by: { $0.key < $1.key }) {
            let localizations = (value as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for (locale, body) in localizations.sorted(by: { $0.key < $1.key }) {
                let body = body as? [String: Any] ?? [:]
                let required = try XCTUnwrap(Self.requiredPluralCategories[locale], """
                    \(key) carries a locale this test has no CLDR rule for: \
                    \(locale). Add its cardinal categories to \
                    `requiredPluralCategories` — an unknown locale must fail \
                    loudly rather than be waved through, because "no rule" and \
                    "no requirement" look identical from here.
                    """)

                // Two shapes carry plurals: a whole-string variation, and one
                // per axis inside `substitutions`. Both are checked, because a
                // hole in either fails the same way.
                var axes: [(String, [String: Any])] = []
                if let plural = Self.pluralCategories(in: body) {
                    axes.append(("the whole string", plural))
                }
                for (name, substitution) in
                        (body["substitutions"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
                    if let plural = Self.pluralCategories(in: substitution as? [String: Any] ?? [:]) {
                        axes.append(("substitution \"\(name)\"", plural))
                    }
                }

                for (where_, plural) in axes {
                    checked += 1
                    let present = Set(plural.keys)
                    let absent = required.subtracting(present).sorted()
                    XCTAssertTrue(present.isSuperset(of: required), """
                        \(key) [\(locale)], \(where_): has \(present.sorted()) and \
                        needs \(required.sorted()) — missing \(absent).
                        `xcstringstool compile` accepts this, exit 0, no warning, so \
                        nothing between here and the player disagrees with it.
                        \(Self.holeEffect(absent))
                        """)

                    // …and every category present has to be a real one. A typo
                    // ("ohter") is a category nothing selects and a category
                    // nothing misses, so it is invisible from both sides.
                    let known: Set<String> = ["zero", "one", "two", "few", "many", "other"]
                    XCTAssertTrue(present.isSubset(of: known), """
                        \(key) [\(locale)], \(where_): \
                        \(present.subtracting(known).sorted()) is not a CLDR \
                        plural category. It will never be selected and never be \
                        reported missing.
                        """)
                }
            }
        }

        // The gate has to have something to gate. Zero plural entries passes
        // every assertion above and says nothing at all — which is exactly the
        // state this task found the catalog in.
        XCTAssertGreaterThan(checked, 0,
                             "no plural variation anywhere in the catalog — either the "
                             + "generator stopped writing them or this reader stopped "
                             + "seeing them, and both look like a green test")
    }

    /// What a hole in these categories does at runtime, measured against
    /// Foundation rather than assumed. It resolves the computed category, else
    /// `other`, else nothing — so the two cases fail differently and a message
    /// that promised `(null)` for both would send the next reader looking for a
    /// blank that is not there.
    static func holeEffect(_ absent: [String]) -> String {
        if absent.contains("other") {
            return "`other` is the one that goes BLANK: every count whose category "
                + "is absent renders \"(null)\", because `other` is what Foundation "
                + "falls back to and there is nothing behind it."
        }
        let names = absent.joined(separator: "/")
        return "This one does not go blank — Foundation falls back to `other`, so "
            + "the player reads the plural form where the \(names) form belongs. "
            + "Wrong grammar, silently, rather than a hole."
    }

    /// `localizations.<locale>.variations.plural`, or nil if this body has no
    /// whole-string plural. Also reads a substitution body, which nests the
    /// same `variations.plural` one level in.
    static func pluralCategories(in body: [String: Any]) -> [String: Any]? {
        (body["variations"] as? [String: Any])?["plural"] as? [String: Any]
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
            let english = localizations["en"] as? [String: Any] ?? [:]
            let (value, state) = sentence(in: english)
            entries[key] = Entry(comment: body["comment"] as? String ?? "",
                                 english: value,
                                 englishState: state,
                                 locales: localizations.keys.sorted())
        }
        return entries
    }

    /// One localization body, reduced to the sentence a reader sees at counts
    /// greater than one — which is exactly the row in `EnglishPhrases.table`.
    ///
    /// Three shapes since PRD-20 Task 8, and this reader has to understand all
    /// three or `testEveryEnglishPhraseHasACatalogEntry` reads `nil` for the
    /// nineteen pluralised keys and passes by comparing nothing:
    ///
    ///   • a plain `stringUnit`;
    ///   • `variations.plural`, where the `other` category IS the table row;
    ///   • a frame plus `substitutions`, where the table row is the frame with
    ///     each `%N$#@name@` spliced back to that axis's `other`.
    ///
    /// The third is the load-bearing one. `scripts/strings.py` *derives* the
    /// frame from the table row, so this is the same round trip run backwards,
    /// in a different language, from the file rather than from the generator —
    /// which is the only way it can catch a hand-edited catalog.
    static func sentence(in localization: [String: Any]) -> (String?, String?) {
        if let plural = pluralCategories(in: localization) {
            let unit = (plural["other"] as? [String: Any])?["stringUnit"] as? [String: Any]
            return (unit?["value"] as? String, unit?["state"] as? String)
        }

        let unit = localization["stringUnit"] as? [String: Any]
        guard var frame = unit?["value"] as? String,
              let substitutions = localization["substitutions"] as? [String: Any],
              !substitutions.isEmpty else {
            return (unit?["value"] as? String, unit?["state"] as? String)
        }

        for (name, axis) in substitutions {
            let axis = axis as? [String: Any] ?? [:]
            guard let argNum = axis["argNum"] as? Int,
                  let plural = pluralCategories(in: axis),
                  let other = ((plural["other"] as? [String: Any])?["stringUnit"]
                                as? [String: Any])?["value"] as? String else { continue }
            frame = frame.replacingOccurrences(
                of: "%\(argNum)$#@\(name)@",
                with: other.replacingOccurrences(of: "%arg", with: "%\(argNum)$lld"))
        }
        return (frame, unit?["state"] as? String)
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

    /// How many `#if` blocks enclose the first occurrence of `needle`, or -1 if
    /// it is not there at all.
    ///
    /// A line scanner rather than a real preprocessor, because the question is
    /// deliberately coarse: *is this line conditional on anything*. `#elseif`
    /// and `#else` do not change the depth — they are still inside the block
    /// they belong to — and `#if` is matched as a whole directive so
    /// `#endif`, which also begins with `#e`, cannot open one.
    ///
    /// Comments are already blanked by `codeOnly`, so a `#if` inside prose (and
    /// this file's own doc comments discuss several) cannot skew the count.
    static func conditionalDepth(of needle: String, in source: String) -> Int {
        var depth = 0
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.contains(needle) { return depth }
            let text = line.trimmingCharacters(in: .whitespaces)
            if text == "#if" || text.hasPrefix("#if ") {
                depth += 1
            } else if text == "#endif" {
                depth -= 1
            }
        }
        return -1
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
