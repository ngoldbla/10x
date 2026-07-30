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

    // MARK: - The three bundles

    func testEveryTargetListsTheStringsTree() throws {
        let yml = try String(contentsOf: Self.nineRoot.appendingPathComponent("project.yml"),
                            encoding: .utf8)
        // Per target, not file-wide. Counting `- Sources/Strings` across the
        // whole file said 2 whether or not the two lived in the two targets
        // that need them: drop it from NineWidgets, add a second copy anywhere
        // under Nine, and the count, the test and all three platform builds
        // stay green while the widget ships permanently English.
        for target in ["Nine", "NineWidgets", "NineWatch"] {
            let block = try XCTUnwrap(Self.targetBlock(target, in: yml),
                                      "project.yml has no target named \(target) at "
                                      + "two-space indent — this test is reading the "
                                      + "wrong shape of file, not measuring anything.")
            XCTAssertTrue(block.contains("- Sources/Strings"), """
                \(target) does not list Sources/Strings. All three targets must: \
                NineWidgets and NineWatch compile Sources/Shared and \
                Sources/Engine in, so they ask for the same keys — but against \
                their OWN bundle, because in an app extension and in a watch app \
                `Bundle.main` is that bundle. A widget or a watch app without the \
                catalog renders English on a localized phone, and every platform \
                build stays green.
                """)

            // Sources/Shared is the tree whose presence in both targets is the
            // whole reason the catalog has to be in both. If that ever stops
            // being true, the assertion above is measuring nothing.
            XCTAssertTrue(block.contains("- Sources/Shared"),
                          "\(target) no longer lists Sources/Shared — re-derive why "
                          + "the catalog needs to be in three bundles, before trusting "
                          + "the assertion above.")
        }
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
        let expected = (["en"] + Self.launchLocales).sorted()
        XCTAssertEqual(translated, expected, """
            The catalog carries \(translated); PRD-20's launch set is \(expected). \
            This expectation is derived from `requiredPluralCategories` rather \
            than retyped, so adding a tenth language means adding its CLDR rule \
            — which is the thing that would otherwise be forgotten — and both \
            CFBundleLocalizations lists move in the same commit.
            """)

        let yml = try String(contentsOf: Self.nineRoot.appendingPathComponent("project.yml"),
                            encoding: .utf8)
        let declared = yml.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("CFBundleLocalizations:") }

        // Three: the app's Info.plist, the widget extension's, and the watch
        // app's. Each is a separate bundle with a separate Info.plist, so "the
        // app declares it" is a fact about none of the others — and an
        // extension or a watch app resolves against its OWN `Bundle.main`.
        XCTAssertEqual(declared.count, 3, """
            CFBundleLocalizations must be declared by ALL THREE bundles — \
            Nine.app, NineWidgets.appex and NineWatch.app. Found \(declared.count).
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

        XCTAssertEqual(Self.occurrences(of: "CFBundleDevelopmentRegion: en", in: yml), 3,
                       "English is the source language; all three bundles must say so.")
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

    /// Every locale carries the same *shape* English does.
    ///
    /// `testEveryPluralHasTheCategoriesItsLanguageRequires` builds its work
    /// list out of the plurals it finds in each locale body, so a locale that
    /// carries **no** plural block contributes no assertions and is waved
    /// through in silence. The global `checked > 0` floor cannot see it either:
    /// it stands at 180 axes across 17 keys, so losing one leaves it far from
    /// zero. Every other catalog gate has the same blind spot from a different
    /// angle — presence checks see a body, and the argument-index check sees a
    /// flattened body as one string using `{1}`, which is what English's frame
    /// uses too.
    ///
    /// Measured on a clean `2a17ce7`: replacing French's three-category
    /// `board.streak.plain` with a flat unit passed `strings.py --audit`,
    /// passed `xcstringstool compile` at exit 0 with no warning, and passed
    /// every test in this file. French would then read "série de 1 jours" at
    /// every count on the streak chip, the widget and the share card — French
    /// `one` covers 0 and 1 — silently and forever.
    ///
    /// This is the same defect PR #43 closed one level down: it drilled
    /// *removing a category from* a plural, and could not see *removing the
    /// plural*. So the shape is derived from English and compared, rather than
    /// read out of the data being judged.
    func testEveryLocaleCarriesTheSameShapeAsItsEnglish() throws {
        let url = Self.nineRoot.appendingPathComponent("Sources/Strings/Localizable.xcstrings")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                                 as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        var pluralised = 0
        var substituted = 0
        for (key, value) in strings.sorted(by: { $0.key < $1.key }) {
            let localizations = (value as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            guard let english = localizations["en"] as? [String: Any] else { continue }
            let englishShape = Self.shape(of: english)
            if englishShape.isPlural { pluralised += 1 }
            if !englishShape.substitutions.isEmpty { substituted += 1 }

            for (locale, body) in localizations.sorted(by: { $0.key < $1.key }) where locale != "en" {
                let shape = Self.shape(of: body as? [String: Any] ?? [:])
                XCTAssertEqual(shape.isPlural, englishShape.isPlural, """
                    \(key) [\(locale)] is \(shape.isPlural ? "a plural" : "a flat string") \
                    where English is \(englishShape.isPlural ? "a plural" : "a flat string"). \
                    A flattened plural compiles at exit 0 and renders one \
                    grammatical form for every count — "1 days" or "série de 1 \
                    jours" — and no other gate in this repo can see it.
                    """)
                XCTAssertEqual(shape.substitutions, englishShape.substitutions, """
                    \(key) [\(locale)] declares substitutions \
                    \(shape.substitutions.sorted()) where English declares \
                    \(englishShape.substitutions.sorted()). The frame still \
                    names `%N$#@axis@`, so a missing axis is an unresolved \
                    token on screen and a spare one is dead weight a translator \
                    was paid for.
                    """)
            }
        }

        // Floors on what was compared, not on what was found. Each names its
        // own number so that "the reader stopped seeing them" and "the
        // generator stopped writing them" cannot both read as green.
        //
        // 14 → 17 for PRD-26: the debrief's three counts (`placements`,
        // `corrections`, `notes`) all inflect on a number, and English's `one`
        // and `other` genuinely differ for each — "1 digit placed" against "2
        // digits placed" — which is not true of most rows in this table.
        //
        // 17 → 18 for Task 3 of the four-fixes program: `debrief.errors`
        // joins them, the wrongness count the debrief had no number for
        // before ("1 error" against "2 errors").
        XCTAssertEqual(pluralised, 20,
                       "English carries a different number of whole-string plurals than "
                       + "the 20 this catalog was built with — if that is deliberate, "
                       + "move the number; if it is not, a plural has been flattened at "
                       + "the source and every locale followed it")
        XCTAssertEqual(substituted, 3,
                       "English carries a different number of substituted keys than the "
                       + "3 this catalog was built with")
    }

    /// The structural shape of one locale body: is it a plural, and which
    /// substitution axes does it declare. Deliberately not the *contents* —
    /// those are `testEveryPluralHasTheCategoriesItsLanguageRequires`'s job.
    static func shape(of body: [String: Any]) -> (isPlural: Bool, substitutions: Set<String>) {
        (pluralCategories(in: body) != nil,
         Set((body["substitutions"] as? [String: Any] ?? [:]).keys))
    }

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

    // MARK: - The nine languages

    /// The nine PRD-20 launch locales, derived from the CLDR table above rather
    /// than listed again. A second remembered locale list is the exact failure
    /// this PRD spent eight tasks removing — `strings.py` carried one, and its
    /// comment named a test that had never existed.
    static var launchLocales: [String] {
        requiredPluralCategories.keys.filter { $0 != "en" }.sorted()
    }

    /// **Nobody on this project reads these nine languages.**
    ///
    /// They are machine drafts, and `state: "needs_review"` is the only honest
    /// record of that. `xcstringstool compile` throws it away — measured, not
    /// assumed: a catalog marked `needs_review` throughout and the same catalog
    /// marked `translated` compile to byte-identical output (`ja.lproj`
    /// `.strings` sha256 `6a874df5…ba35` both ways, `.stringsdict`
    /// `285b4548…9678` both ways), and the token appears zero times in any
    /// compiled artifact. So nothing downstream of the source catalog can carry
    /// this claim, and a comment saying "these are drafts" is not a mechanism.
    ///
    /// When a human actually reviews a language, they flip that locale's states
    /// and this test moves with them — deliberately, in a diff, one locale at a
    /// time. It is not a rule that translations must stay unreviewed; it is a
    /// rule that "reviewed" has to be earned in a commit.
    func testEveryMachineDraftIsMarkedNeedsReview() throws {
        let catalog = try Self.rawStrings()
        var drafted = 0

        for (key, value) in catalog.sorted(by: { $0.key < $1.key }) {
            let localizations = (value as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for (locale, body) in localizations.sorted(by: { $0.key < $1.key }) {
                let isSource = locale == "en"
                let expected = isSource ? "translated" : "needs_review"
                let why = isSource
                    ? "English is the source language and is translated by definition."
                    : """
                      This locale is a machine draft that no human on this project can read. \
                      If it has genuinely been reviewed, flip the whole locale and move this \
                      test's expectation for it — one locale, one commit, so that "reviewed" \
                      is something somebody did rather than something that drifted.
                      """
                for (label, state) in Self.states(in: body as? [String: Any] ?? [:]) {
                    if !isSource { drafted += 1 }
                    XCTAssertEqual(state, expected, """
                        \(key) [\(locale)], \(label): state is "\(state)", expected \
                        "\(expected)". \(why)
                        """)
                }
            }
        }

        XCTAssertGreaterThan(drafted, 0, """
            no non-English string units at all — this test passes vacuously on an \
            English-only catalog, which is exactly the state it was written in, so \
            it needs this floor to mean anything once the languages land.
            """)
    }

    /// Decision 2, as PRD-25 widened it: `Nocturne`, `Tempest` and `Abyss` are
    /// **coined names** and do not translate; `Gentle`, `Steady` and `Sharp` are
    /// **descriptions** and do.
    ///
    /// Pinned rather than commented, because the next translation pass will not
    /// have read the plan and "Nocturne" looks exactly like an untranslated
    /// string that somebody forgot. The catalog comment on each entry says the
    /// same thing to a human; this says it to CI.
    ///
    /// The two lists are written out rather than derived from `Difficulty`,
    /// **and that is the point**: which side a band falls on is a naming
    /// decision, not a property of the enum, so adding a case must fail here
    /// until someone makes it. The count check below is what makes "fail" true
    /// rather than "silently gets ignored".
    func testCoinedBandNamesAreIdenticalInEveryLocale() throws {
        let catalog = try Self.rawStrings()
        let coined = ["nocturne": "Nocturne", "tempest": "Tempest", "abyss": "Abyss"]
        let described = ["gentle", "steady", "sharp"]

        XCTAssertEqual(
            Set(coined.keys).union(described),
            Set(Difficulty.allCases.map(\.rawValue)), """
            a difficulty band is on neither list. Every band is either a coined \
            name that stays in English everywhere or a description that must be \
            translated — decide which, add it above, and say so in its catalog \
            comment. A band on neither list is one no test has an opinion about.
            """)

        for (band, name) in coined.sorted(by: { $0.key < $1.key }) {
            let key = "difficulty.\(band).title"
            let entry = try XCTUnwrap(catalog[key] as? [String: Any],
                                      "\(key) is gone from the catalog")

            let comment = entry["comment"] as? String ?? ""
            XCTAssertTrue(comment.lowercased().contains("do not translate")
                          || comment.lowercased().contains("does not translate"), """
                \(key)'s catalog comment no longer tells a translator to leave it \
                alone. This test is the CI half of that instruction; the comment is \
                the half a human reads, and a translator who only sees "\(name)" with \
                no note will helpfully fix it.
                """)

            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for (locale, body) in localizations.sorted(by: { $0.key < $1.key }) {
                let value = ((body as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
                XCTAssertEqual(value, name, """
                    \(key) [\(locale)] is "\(value ?? "nil")". \(name) is a coined name \
                    and stays "\(name)" in every locale — unlike gentle/steady/sharp, \
                    which are descriptions and must translate.
                    """)
            }
        }

        // The other half of the decision: if the describable ones stopped being
        // translated, this file would still be green and the rule would have
        // quietly become "difficulty names do not translate".
        for band in described {
            let key = "difficulty.\(band).title"
            let entry = try XCTUnwrap(catalog[key] as? [String: Any])
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let english = ((localizations["en"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            for locale in Self.launchLocales where localizations[locale] != nil {
                let value = ((localizations[locale] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
                XCTAssertNotEqual(value, english, """
                    \(key) [\(locale)] is still the English "\(english ?? "")". Gentle, \
                    Steady and Sharp describe a band and translate; only the coined \
                    names are pinned. If this locale genuinely borrows the English \
                    word, say so in the catalog comment and exempt it here by name.
                    """)
            }
        }
    }

    /// A locale that is missing a key does not fail — Foundation falls back to
    /// the development language and the player reads one English line in the
    /// middle of their own. Which is exactly the shape of bug that survives a
    /// screenshot pass, because whoever takes the screenshots reads English.
    func testNoLocaleIsMissingAKeyThePlayerCanReach() throws {
        let catalog = try Self.rawStrings()
        var holes: [String] = []

        for (key, value) in catalog.sorted(by: { $0.key < $1.key }) {
            let localizations = (value as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            guard localizations["en"] != nil else { continue }
            for locale in Self.launchLocales where localizations[locale] == nil {
                holes.append("\(key) [\(locale)]")
            }
        }

        XCTAssertTrue(holes.isEmpty, """
            \(holes.count) key/locale pair(s) have no translation and will render in \
            English inside a translated screen: \(holes.prefix(12).joined(separator: ", "))\
            \(holes.count > 12 ? ", …" : "").
            Nothing reports this at build time and nothing reports it at runtime.
            """)
    }

    /// The catalog's `strings` object, read as JSON.
    static func rawStrings() throws -> [String: Any] {
        let url = nineRoot.appendingPathComponent("Sources/Strings/Localizable.xcstrings")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                                 as? [String: Any])
        return try XCTUnwrap(root["strings"] as? [String: Any])
    }

    /// Every `stringUnit.state` in one locale body, labelled by where it lives.
    /// All three shapes, because a state check that only reads the top-level
    /// unit would pass a plural whose every form says `translated`.
    static func states(in body: [String: Any]) -> [(String, String)] {
        var out: [(String, String)] = []
        if let unit = body["stringUnit"] as? [String: Any], let state = unit["state"] as? String {
            out.append(("the whole string", state))
        }
        if let plural = pluralCategories(in: body) {
            for (category, unit) in plural.sorted(by: { $0.key < $1.key }) {
                if let state = ((unit as? [String: Any])?["stringUnit"] as? [String: Any])?["state"] as? String {
                    out.append(("plural.\(category)", state))
                }
            }
        }
        for (name, substitution) in (body["substitutions"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let plural = pluralCategories(in: substitution as? [String: Any] ?? [:]) else { continue }
            for (category, unit) in plural.sorted(by: { $0.key < $1.key }) {
                if let state = ((unit as? [String: Any])?["stringUnit"] as? [String: Any])?["state"] as? String {
                    out.append(("substitution \"\(name)\".\(category)", state))
                }
            }
        }
        return out
    }

    // MARK: - Arguments

    /// **A translation that omits an argument is invisible to every other gate.**
    ///
    /// `Phrasebook.specifierMismatch` (`Sources/Shared/Phrasebook.swift:205`)
    /// scans the *format* and checks each specifier it finds against the
    /// arguments it was handed. Nothing walks the other way. So an index above
    /// `args.count` is caught, a wrong conversion is caught, and a translation
    /// that simply never mentions `%2$@` validates, compiles, formats, and drops
    /// half the sentence on the floor. "Four and Seven pair in row 3" becomes
    /// "Four pair in row 3" — which is not a truncation a player can recognise
    /// as one, because it is a grammatical English sentence about the wrong
    /// thing. `xcstringstool compile` does not check it either; it checks shape,
    /// not meaning.
    ///
    /// **The exposure is 32 keys, not the four this task's brief names**
    /// (`board.announce.pair`, `board.cell.hintPair`, `coach.card.label`,
    /// `shelf.continue.caption` are a sample of it). Every key carrying two or
    /// more positional indices is exposed — the whole `coach.*.sentence.*`
    /// family, most of `board.*`, `shelf.*`, `firstrun.*`. The count is derived
    /// below rather than listed, so it tracks the catalog instead of this
    /// comment.
    ///
    /// The 32nd is `board.progress.filled`, and it is worth naming because it
    /// is the one a script finds last. Its top-level unit is
    /// `%1$#@filled@ filled.` — one index — and `%2$lld` lives inside the
    /// substitution's plural forms. A reader that examines each stored value on
    /// its own counts 31 and is wrong by exactly the key whose second argument
    /// is hardest to see. That is not hypothetical: the first pass at this
    /// number, written to justify the assertion below, returned 31.
    ///
    /// The comparison is **per rendering, not per key**. A rendering is one
    /// string a player can actually be shown, and each plural category is a
    /// separate one: dropping `%2$lld` from the `one` form alone breaks exactly
    /// the counts that select `one` and leaves every other count correct, which
    /// is the hardest version of this to see from a diff. Comparing each
    /// rendering against the key's full English argument set is safe rather than
    /// over-fitted, and that was measured: of 425 English keys, **0** vary their
    /// argument usage between plural categories. The English self-check below
    /// keeps that true rather than trusting this sentence.
    func testEveryLocaleUsesEveryArgumentIndexTheEnglishValueUses() throws {
        let url = Self.nineRoot.appendingPathComponent("Sources/Strings/Localizable.xcstrings")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                                 as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        var keysCarryingArguments = 0
        var keysCarryingTwoOrMore = 0
        var renderingsChecked = 0

        for (key, value) in strings.sorted(by: { $0.key < $1.key }) {
            let localizations = (value as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            guard let english = localizations["en"] as? [String: Any] else { continue }

            let englishRenderings = Self.renderings(in: english)
            let expected = englishRenderings.reduce(into: Set<Int>()) { $0.formUnion($1.indices) }
            guard !expected.isEmpty else { continue }
            keysCarryingArguments += 1
            if expected.count > 1 { keysCarryingTwoOrMore += 1 }

            for (locale, body) in localizations.sorted(by: { $0.key < $1.key }) {
                guard let body = body as? [String: Any] else { continue }
                for rendering in Self.renderings(in: body) {
                    renderingsChecked += 1
                    let missing = expected.subtracting(rendering.indices).sorted()
                    let extra = rendering.indices.subtracting(expected).sorted()
                    XCTAssertEqual(rendering.indices, expected, """
                        \(key) [\(locale)], \(rendering.label): uses arguments \
                        \(rendering.indices.sorted()) where English uses \
                        \(expected.sorted())\
                        \(missing.isEmpty ? "" : " — dropped \(missing)")\
                        \(extra.isEmpty ? "" : " — invented \(extra)").
                        A dropped index is the silent one: `Phrasebook` validates \
                        the format against the arguments and never the arguments \
                        against the format, so this formats without a warning and \
                        the clause it belonged to simply is not on screen. An \
                        invented index is the loud one — `Phrasebook` traps it at \
                        runtime, which on a translated build means a Debug \
                        assertion in a language nobody here reads.
                        """)
                }
            }
        }

        // The floor. With `en` alone in the catalog every assertion above is
        // vacuous except the English self-check, so the thing worth pinning is
        // that there is real exposure to protect — 31 keys at the time of
        // writing. A catalog that stopped carrying multi-argument strings, or a
        // reader that stopped seeing them, both arrive here as a green test.
        XCTAssertGreaterThan(keysCarryingArguments, 0,
                             "no key in the catalog takes an argument — either the "
                             + "catalog changed shape or `renderings` stopped reading it")
        // 32 → 36 for PRD-25, and the four are named rather than counted so the
        // next person can check the move instead of trusting it:
        // `coach.xyWing.sentence` (three indices), `why.position`,
        // `why.effect.rulesOutTwo` and `stats.techniquesMet` (two each).
        // Every other key this PRD added carries one index or none — the
        // swordfish and skyscraper sentences repeat `%1$lld`, which is one
        // argument used twice, not two arguments.
        //
        // 36 → 37 for PRD-26, and it is one key: `debrief.headline` ("You
        // found the %1$@ at move %2$lld"). Its ten siblings carry one index or
        // none.
        //
        // 37 → 48 for PRD-24, and it is eleven, in three groups. The shelf:
        // `shelf.channel.daily` and `shelf.channel.free` (both "%1$@ · %2$@" — a
        // channel name and either a date or a tier), `channel.today.label` (a
        // channel name plus a whole status sentence, joined for VoiceOver) and
        // `channel.pager.label` (the only three-argument key the PRD added). The
        // board's spoken rules: `board.cell.withRule` and `board.rule.thermo`. And
        // the four variant techniques' sentences, of which `innieOutie` is three
        // because it splits on unit kind: `coach.cageSingle.sentence`,
        // `coach.cageCombination.sentence` and `coach.innieOutie.sentence.{row,
        // col,box}`. Every other key the PRD added is a single noun or takes one
        // number — a channel name, a blurb, a tier name, a cage sum, a tube length.
        XCTAssertEqual(keysCarryingTwoOrMore, 48, """
            \(keysCarryingTwoOrMore) keys carry two or more positional arguments, \
            not the 48 this test was calibrated against. That is fine and the \
            number should move with the catalog — update it deliberately, in a \
            diff, having checked that `renderings` still reads all three shapes. \
            It is pinned because it dropping to 0 is what a silently-broken \
            reader looks like from here.
            """)
        XCTAssertGreaterThan(renderingsChecked, keysCarryingArguments,
                             "fewer renderings than argument-carrying keys — the plural "
                             + "and substitution shapes are not being expanded")
    }

    /// The other half of the same hole, one level down.
    ///
    /// A substitution's plural units name their count as `%arg`, not as a
    /// positional index — `%arg of %2$lld`. So dropping `%arg` costs the player
    /// the number without changing any positional index, and the test above
    /// cannot see it. `xcstringstool` accepts a substitution variation with no
    /// `%arg` in it: the axis is still declared, still selected, still renders,
    /// and the count it exists to print is gone.
    func testEverySubstitutionVariationStillNamesItsCount() throws {
        let url = Self.nineRoot.appendingPathComponent("Sources/Strings/Localizable.xcstrings")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                                 as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        var checked = 0
        for (key, value) in strings.sorted(by: { $0.key < $1.key }) {
            let localizations = (value as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for (locale, body) in localizations.sorted(by: { $0.key < $1.key }) {
                let substitutions = (body as? [String: Any])?["substitutions"] as? [String: Any] ?? [:]
                for (name, substitution) in substitutions.sorted(by: { $0.key < $1.key }) {
                    guard let plural = Self.pluralCategories(in: substitution as? [String: Any] ?? [:])
                    else { continue }
                    for (category, unit) in plural.sorted(by: { $0.key < $1.key }) {
                        let text = ((unit as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                        checked += 1
                        XCTAssertTrue(text.contains("%arg"), """
                            \(key) [\(locale)], substitution "\(name)".\(category): \
                            "\(text)" does not name `%arg`. That axis exists to print \
                            a count and this form of it prints none — and because \
                            `%arg` is not a positional index, no specifier check \
                            anywhere disagrees.
                            """)
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 0,
                             "no substitution variations found — the catalog has three "
                             + "shapes and this test just stopped seeing one of them")
    }

    /// Every string a player can be shown for one locale of one key, paired
    /// with the positional argument indices it uses.
    ///
    /// The three catalog shapes do not nest the same way and the difference is
    /// load-bearing:
    ///
    ///   • plain — one `stringUnit`, one rendering.
    ///   • whole-string plural — one rendering per category, and **no top-level
    ///     unit at all**, so anything reading `stringUnit.value` first sees
    ///     nothing here.
    ///   • substitution — a top-level unit holding `%N$#@name@`, and the real
    ///     text one level in. A rendering is the two combined, which is the
    ///     whole point: `board.progress.filled` is `%1$#@filled@ filled.` up top
    ///     and `%arg of %2$lld` inside, so a reader that stops at the top level
    ///     concludes it is a one-argument key and waves through a translation
    ///     that dropped the total.
    static func renderings(in body: [String: Any]) -> [(label: String, indices: Set<Int>)] {
        let top = argumentIndices(in: (body["stringUnit"] as? [String: Any])?["value"] as? String ?? "")

        if let plural = pluralCategories(in: body) {
            return plural.sorted(by: { $0.key < $1.key }).map { category, unit in
                let text = ((unit as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                return ("plural.\(category)", top.union(argumentIndices(in: text)))
            }
        }

        let substitutions = body["substitutions"] as? [String: Any] ?? [:]
        var expanded: [(label: String, indices: Set<Int>)] = []
        for (name, substitution) in substitutions.sorted(by: { $0.key < $1.key }) {
            guard let plural = pluralCategories(in: substitution as? [String: Any] ?? [:]) else { continue }
            for (category, unit) in plural.sorted(by: { $0.key < $1.key }) {
                let text = ((unit as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                expanded.append(("substitution \"\(name)\".\(category)",
                                 top.union(argumentIndices(in: text))))
            }
        }
        return expanded.isEmpty ? [("the whole string", top)] : expanded
    }

    /// The positional indices `%N$…` names, including the `%N$#@name@` form.
    ///
    /// Deliberately not `Phrasebook.specifierMismatch`: that answers "is this
    /// format compatible with these arguments", which is the question that
    /// cannot see an omission. This answers "which arguments does this format
    /// mention", which is the one that can. `%%` is an escaped percent and
    /// names nothing; a bare `%@` names nothing either, and shows up here as an
    /// index that went missing rather than as its own diagnosis.
    static func argumentIndices(in format: String) -> Set<Int> {
        var found: Set<Int> = []
        var digits = ""
        var inSpecifier = false

        for character in format {
            guard inSpecifier else {
                if character == "%" { inSpecifier = true; digits = "" }
                continue
            }
            if character.isNumber {
                digits.append(character)
            } else if character == "$" {
                if let index = Int(digits) { found.insert(index) }
                inSpecifier = false
            } else {
                // Anything else ends it: a conversion (`%@`), a modifier that
                // never reached a `$` (`%lld`), or `%%`. None of them name a
                // position, and `%%` must not leave us mid-specifier or the
                // next literal digit reads as an index.
                inSpecifier = false
            }
        }
        return found
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

    /// The lines of one `targets:` entry in `project.yml`, or nil if there is
    /// no such target.
    ///
    /// Targets sit at two-space indent (`  Nine:`), so the block runs from that
    /// line to the next line at two-space indent or less. Crude, and
    /// deliberately so: the alternative is a YAML parser in a test whose whole
    /// job is to notice that a one-line list entry moved between two targets.
    static func targetBlock(_ target: String, in yml: String) -> String? {
        let lines = yml.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "  \(target):") else { return nil }
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex { line in
            guard let first = line.first(where: { !$0.isWhitespace }) else { return false }
            let indent = line.distance(from: line.startIndex,
                                       to: line.firstIndex(of: first) ?? line.startIndex)
            return indent <= 2
        } ?? lines.endIndex
        return lines[start..<end].joined(separator: "\n")
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
