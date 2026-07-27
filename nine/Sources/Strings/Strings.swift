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
// from its own copy of this file. "The main bundle" is correct in both, and
// that is the whole reason neither lookup names a bundle by identifier.
//
// **The two accessors spell that differently, and the difference is not
// cosmetic** (PRD-20 Task 6). `install()` resolves eagerly, in this process, so
// `bundle: .main` reads the right bundle at the moment it is asked.
// `resource(_:)` returns a `LocalizedStringResource`, which is `Codable` and
// resolves LATER — possibly in another process, which is the entire reason that
// type exists rather than `String(localized:)`. Nine's uses of it are the three
// widgets' `.configurationDisplayName` / `.description`: the widget GALLERY,
// drawn by the Home Screen and the Lock Screen editor, not by `NineWidgets`.
// `.main` in a resource that is decoded over there means SpringBoard's main
// bundle, which has no `widget.daily.name`. `.atURL(Bundle.main.bundleURL)`
// captures the appex's own URL here, while `Bundle.main` still means the appex,
// and carries it across. Verified on screen, in German (task report).
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

    /// The same key as a `LocalizedStringResource`, for the call sites whose
    /// parameter genuinely is one.
    ///
    /// **Six call sites, all of them the widget gallery**: the
    /// `.configurationDisplayName` and `.description` of `NineDailyWidget`,
    /// `NineStreakWidget` and `NineBoardWidget`. Everything else in Nine goes
    /// through `string(_:)`, because `Sources/Shared` cannot produce a
    /// `LocalizedStringResource` at all (Linux) and a view that takes a `String`
    /// gains nothing from one. This function was dead code with zero references
    /// from Task 4 until Task 6 landed those six, which is worth saying out
    /// loud: it had never been executed when the bundle argument below was
    /// chosen.
    ///
    /// `.atURL(Bundle.main.bundleURL)`, NOT `.main`, and the file header
    /// explains why at length: this value is `Codable` and is resolved by
    /// whoever draws the gallery — SpringBoard — rather than by us. `.main`
    /// evaluated over there is SpringBoard's bundle. The URL is read here,
    /// inside the appex, and travels with the value.
    ///
    /// No English fallback here, deliberately: a `LocalizedStringResource`
    /// resolves at render time and in someone else's process, so there is no
    /// moment at which this function could compare the answer to the key. The
    /// generated catalog always carries `en`, so the only way to reach a missing
    /// entry is a key that is in no locale at all — which `strings.py --audit`
    /// fails on before it can ship, now including these six (`PHRASEBOOK_KEY_RE`
    /// reads `.resource(` as well as `.string(`).
    public static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key), bundle: .atURL(Bundle.main.bundleURL))
    }
}
