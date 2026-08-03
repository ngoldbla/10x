// NineIntents.swift — PRD-33. Nine in Spotlight, in Siri, on the Action button
// and in the Shortcuts app.
//
// Two App Shortcuts, well under the ten-shortcut cap, and each one is a door the
// app already has rather than a new capability: carry on with what you were
// doing, start a board at a band. The daily and streak intents left with the
// daily system (product decision, 2026-08-02). The covenant's line about the
// coach never placing a digit has a sibling here — **nothing in this file
// plays**. PROGRAM-2.0 rejected Siri voice solving as "slower than the rose =
// demo-ware" and that rejection stands: no intent takes a cell, a digit or a
// move.
//
// Every user-facing string is a `LocalizedStringResource` **literal** keyed into
// the `Intents` table, not a `Strings.resource(_:)` call. That is not a style
// choice and it is not optional — see `Sources/Shortcuts/IntentStrings.swift` for
// the build error and, more importantly, for the reason the failure is quiet.
//
// iOS and macOS. tvOS is fenced out: `AppShortcutsProvider` is available there,
// but a tvOS App Shortcut has no Spotlight, no Action button and no Siri surface
// worth the metadata, and every phrase would then have to be reviewed in nine
// languages for a place nobody can invoke it.
#if os(iOS) || os(macOS)
import AppIntents
import Foundation

// MARK: - The band

/// The difficulty bands, as something Shortcuts can offer in a list.
///
/// A parallel enum rather than making `Difficulty` an `AppEnum`: `Difficulty`
/// lives in `Sources/Engine`, which imports Foundation and CouchCore and nothing
/// else — the rule `StringSealTests.testEngineNamesNothing` enforces. Conforming
/// it here would drag AppIntents into the Engine and put English back in it.
///
/// **Exactly the three offered bands** (product decision, 2026-08-02). The
/// engine keeps six cases for persistence identity; every choice surface —
/// this one included — offers three. An old shortcut that saved a deep band's
/// raw value fails to decode and Shortcuts asks the player to pick again,
/// which is the honest outcome for a band no surface offers any more.
/// `everyOfferedBandHasAnIntentCase` in
/// `Tests/EngineTests/IntentCatalogTests.swift` pins this list to
/// `Difficulty.rowBands`'s three.
enum NineBand: String, AppEnum, CaseIterable {
    case gentle, steady, sharp

    var difficulty: Difficulty {
        // Raw values are the frozen identity on both sides (PRD-20), so this is a
        // total mapping with no default arm to rot.
        Difficulty(rawValue: rawValue) ?? .steady
    }

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent.band.title", table: IntentStrings.table)
    )

    /// Written out rather than built from `rawValue` — an interpolated key is
    /// invisible to a static extractor, and `appintentsmetadataprocessor` is one.
    static let caseDisplayRepresentations: [NineBand: DisplayRepresentation] = [
        .gentle: DisplayRepresentation(
            title: LocalizedStringResource("intent.band.gentle", table: IntentStrings.table)
        ),
        .steady: DisplayRepresentation(
            title: LocalizedStringResource("intent.band.steady", table: IntentStrings.table)
        ),
        .sharp: DisplayRepresentation(
            title: LocalizedStringResource("intent.band.sharp", table: IntentStrings.table)
        ),
    ]
}

// MARK: - The intents

/// Carry on with the most recent unfinished board.
struct ContinueBoardIntent: AppIntent {
    static let title = LocalizedStringResource(
        "intent.continue.title", table: IntentStrings.table
    )
    static let description = IntentDescription(
        LocalizedStringResource("intent.continue.description", table: IntentStrings.table)
    )
    static let openAppWhenRun = true

    @Dependency private var model: AppModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        // "Continue" means the board you actually left. Nothing in progress →
        // the shelf, which is honest.
        if let entry = model.library.mostRecentInProgress {
            model.resumeEntry(id: entry.id)
        }
        return .result()
    }
}

/// Start a fresh board at a chosen band.
struct StartABoardIntent: AppIntent {
    static let title = LocalizedStringResource(
        "intent.startBoard.title", table: IntentStrings.table
    )
    static let description = IntentDescription(
        LocalizedStringResource("intent.startBoard.description", table: IntentStrings.table)
    )
    static let openAppWhenRun = true

    @Parameter(
        title: LocalizedStringResource("intent.band.title", table: IntentStrings.table),
        default: .gentle
    )
    var band: NineBand

    @Dependency private var model: AppModel

    init() {}

    init(band: NineBand) {
        self.band = band
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        model.startFree(band.difficulty)
        return .result()
    }
}

// MARK: - The shortcuts

/// The two App Shortcuts, which is what makes any of the above appear in
/// Spotlight, in the Action button's list and in Siri without the player
/// building a shortcut first.
///
/// **Every phrase must contain `\(.applicationName)`** — the build validates it
/// (`appshortcutstringsprocessor --app-name-override` exists precisely to turn
/// that check off). Phrases are localized in `AppShortcuts.xcstrings`, a
/// *different* catalog from both `Localizable` and `Intents`, because its keys
/// are the English sentences below rather than dotted identifiers and its schema
/// belongs to the build phase rather than to `scripts/strings.py`.
///
/// Two rather than four because `StartABoardIntent` is parameterised: one phrase
/// template with `parameterPresentation` covers all three bands.
struct NineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueBoardIntent(),
            phrases: [
                "Continue my board in \(.applicationName)",
                "Carry on in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource(
                "intent.continue.short", table: IntentStrings.table
            ),
            systemImageName: "arrow.turn.down.right"
        )
        AppShortcut(
            intent: StartABoardIntent(),
            phrases: [
                "Start a \(\.$band) board in \(.applicationName)",
                "New \(\.$band) game in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource(
                "intent.startBoard.short", table: IntentStrings.table
            ),
            systemImageName: "plus.square.dashed"
        )
    }
}
#endif
