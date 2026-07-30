// IntentStrings.swift — why App Intents do not use `Strings.resource(_:)`, and
// what they use instead (PRD-33).
//
// `Sources/Strings/Strings.swift` is described in `EXECUTING-A-PRD.md` §4 as "the
// single seam" every user-facing string goes through, and every intent title,
// enum case name and parameter label in this PRD was written against it first.
// It does not compile:
//
//     error: 'LocalizedStringResource' must be initialized with a call to its
//            initializer or a string literal
//     error: 'TypeDisplayRepresentation' must be initialized with a call to its
//            initializer
//     error: At least one halting error produced during export. No AppIntents
//            metadata have been exported and this target is not usable with
//            AppIntents until errors are resolved.
//
// `appintentsmetadataprocessor` is a **static extractor**. It reads the source
// for the strings the system will show in Shortcuts, Spotlight, Siri and the
// widget-configuration sheet, without running anything — so a value produced by
// a function call is, to it, no value at all. `Strings.resource(_:)` is a
// function call. There is no runtime lookup available here at any price.
//
// Note the failure mode, because it is the dangerous part: the processor's error
// is **not fatal to the Swift compile**. It says "this target is not usable with
// AppIntents" and the build carries on. Written a little differently — a `var`
// that the type-checker accepts — this ships an app whose Shortcuts entries are
// simply absent, with no red anywhere. Same family as PRD-16's alternate icons,
// where three green platform builds emitted no `CFBundleAlternateIcons`.
//
// So intent strings are literal keys in their own catalog table:
//
//   * A **separate table** (`Intents.xcstrings`, this directory) rather than rows
//     in `Localizable.xcstrings`, because that catalog is *generated* from
//     `EnglishPhrases.table` by `scripts/strings.py --build-catalog`, and
//     `--audit` fails on any row no Swift file references through the accessors
//     it knows how to read. A hand-added row there would be reported as a dead
//     string on the next audit and deleted by the next regeneration.
//   * **Dotted keys**, matching the rest of the app's key scheme, rather than the
//     English sentence as its own key — which is what Xcode's automatic
//     extraction would have produced.
//   * Policed by `Tests/EngineTests/IntentCatalogTests.swift` instead of by
//     `strings.py`: every key named here has a row, every row is named here,
//     every launch locale is present, and every non-English unit is
//     `needs_review`. The same four rules `CatalogTests` applies to the big
//     catalog, applied to a small one by a different mechanism.
//
// `Sources/Shortcuts` is on **two** source lists, the app's and the widget
// extension's, for exactly the reason `project.yml` gives for listing
// `Sources/Strings` three times: a bundle resolves a catalog against its own
// `Bundle.main`, and the widget's configuration sheet is drawn from strings the
// appex has to be able to find. The watch declares no intents and does not get it.
import Foundation

/// The table name, in one place so no call site can misspell it. A misspelled
/// table does not fail the build; it renders the key.
enum IntentStrings {
    static let table = "Intents"
}
