// Strings.swift — the App layer's single mapping from stable ID to human words
// (PRD-20 "Nine Languages").
//
// The Engine emits `Technique.nakedSingle` and `Difficulty.gentle`; nothing in
// `Sources/Engine` or `Sources/Shared` knows what those are called, and after
// Task 2 nothing in `Sources/Engine` even *can* — it compiles on Linux, so it
// must never reach a bundle. This file is where IDs get names, and it is the
// only file in Nine that imports the localization machinery.
//
// **It lives in `Sources/Strings` rather than `Sources/App` because two bundles
// need it.** `NineWidgets.appex` compiles `Sources/Shared` and `Sources/Engine`
// in (`project.yml`), and inside an app extension `Bundle.main` IS the
// extension — so the widget must resolve the same keys against its own bundle,
// from its own copy of this file. `.main` is correct in both, and that is the
// whole reason the lookup is written against `.main` rather than against a
// named bundle.
//
// `Sources/Strings` is deliberately NOT a SwiftPM target. `LocalizedStringResource`
// does not exist on Linux, and `Package.swift` must stay Linux-clean, so this
// tree builds only through the generated Xcode project. That is also why
// `CatalogTests` reads the catalog and `project.yml` as *files*: nothing in
// `swift test` can link this.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

public enum Strings {

    /// Installs the catalog-backed resolver into `Phrasebook`.
    ///
    /// **Called once per process, from each `@main` entry point, and as early
    /// as the language allows.** There are two entry points and they are two
    /// different processes: `NineApp` (the app) and `NineWidgetBundle` (the
    /// appex, which never runs `NineApp`). `Phrasebook.install` is a
    /// `precondition`, not an `assert` — it survives `-O` — so a second call in
    /// one process traps in the shipping app rather than silently overwriting.
    ///
    /// Not self-installing on first read, and not lazy from `string(_:)`. The
    /// first would make `Sources/Shared` name `Strings`, i.e. depend on its own
    /// Darwin-only consumer, which is the cycle the seam exists to prevent; the
    /// second puts a branch on a read path Task 3 measured at 44-47 ns/label
    /// across 81 labels per AX dump. (Controller ruling, 2026-07-26.)
    public static func install() {
        Phrasebook.install(Phrasebook { key, args in
            let format = String(localized: String.LocalizationValue(key),
                                bundle: .main,
                                comment: "")
            // A key that resolves to itself is a missing entry — a row a
            // translator deleted, or a locale that has not caught up. Fall back
            // to the English the catalog was generated from rather than showing
            // the player a dotted identifier on a share card.
            if format == key, let english = EnglishPhrases.table[key] {
                return Phrasebook.format(english, args)
            }
            return Phrasebook.format(format, args)
        })
    }

    /// One phrase, by key. The App-layer equivalent of what `BoardSpeech` does
    /// through `Phrasebook.current` directly.
    public static func string(_ key: String, _ args: PhraseArg...) -> String {
        Phrasebook.current.string(key, args: args)
    }

    /// A technique's name. Built by interpolation off the frozen raw value, not
    /// by a `switch`: a `switch` is a second list that can disagree with the
    /// enum, and appending a `Technique` case would compile. `CatalogTests`
    /// asserts one catalog entry per case instead.
    public static func technique(_ technique: Technique) -> String {
        Phrasebook.current.string("technique.\(technique.rawValue).name")
    }

    /// A difficulty band's name, keyed the same way for the same reason. The
    /// raw values here are frozen inside 56 golden-corpus hashes, so the ID
    /// side of this lookup is the half that cannot drift.
    public static func difficulty(_ difficulty: Difficulty) -> String {
        Phrasebook.current.string("difficulty.\(difficulty.rawValue).title")
    }

    /// The same key as a `LocalizedStringResource`, for the SwiftUI call sites
    /// that want one — `Text(_:)`, `Button(_:)`, `.navigationTitle(_:)` — so
    /// Tasks 5-8 can extract a view without routing every label through a
    /// `String` first.
    ///
    /// No English fallback here, deliberately: a `LocalizedStringResource`
    /// resolves at render time inside SwiftUI, so there is no moment at which
    /// this function could compare the answer to the key. The generated catalog
    /// always carries `en`, so the only way to reach a missing entry is a key
    /// that is in no locale at all — which `strings.py --audit` fails on before
    /// it can ship.
    public static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key), bundle: .atURL(Bundle.main.bundleURL))
    }
}
