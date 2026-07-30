// NineIntents.swift — PRD-33. Nine in Spotlight, in Siri, on the Action button
// and in the Shortcuts app.
//
// Four App Shortcuts, well under the ten-shortcut cap, and each one is a door the
// app already has rather than a new capability: start today's daily, carry on
// with what you were doing, ask about the streak, start a board at a band. The
// covenant's line about the coach never placing a digit has a sibling here —
// **nothing in this file plays**. PROGRAM-2.0 rejected Siri voice solving as
// "slower than the rose = demo-ware" and that rejection stands: no intent takes
// a cell, a digit or a move.
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
/// `everyBandHasAnIntentCase` in `Tests/EngineTests/IntentCatalogTests.swift`
/// fails if a band is added to one and not the other, which is the failure that
/// actually happens.
enum NineBand: String, AppEnum, CaseIterable {
    case gentle, steady, sharp, nocturne, tempest, abyss

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
    ///
    /// The four coined names (Nocturne, Tempest, Abyss — and Nocturne is coined
    /// too) are identical in every locale by `CatalogTests`'s rule, and these
    /// rows point at the *same* copy the app shows, keyed into the intents table
    /// so the two catalogs cannot disagree about what a band is called.
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
        .nocturne: DisplayRepresentation(
            title: LocalizedStringResource("intent.band.nocturne", table: IntentStrings.table)
        ),
        .tempest: DisplayRepresentation(
            title: LocalizedStringResource("intent.band.tempest", table: IntentStrings.table)
        ),
        .abyss: DisplayRepresentation(
            title: LocalizedStringResource("intent.band.abyss", table: IntentStrings.table)
        ),
    ]
}

// MARK: - The intents

/// Open today's daily, composing it if this is the first look.
struct StartTodaysDailyIntent: AppIntent {
    static let title = LocalizedStringResource(
        "intent.startDaily.title", table: IntentStrings.table
    )
    static let description = IntentDescription(
        LocalizedStringResource("intent.startDaily.description", table: IntentStrings.table)
    )
    static let openAppWhenRun = true

    @Dependency private var model: AppModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        // The same call the widget's deep link makes, and safe mid-composition
        // for the same reason: `compose()` guards on `composing`.
        model.openToday()
        return .result()
    }
}

/// Carry on with the most recent unfinished board — daily or free.
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
        // `resumeEntry` rather than `continueSaved`: the latter is free-play only,
        // and "continue" should mean the board you actually left, which may well
        // be today's daily. Nothing in progress → the shelf, which is honest.
        if let entry = model.library.mostRecentInProgress {
            model.resumeEntry(id: entry.id)
        }
        return .result()
    }
}

/// Answer the streak question **without opening the app**, and without ever
/// making the answer a reproach.
///
/// This is the one intent in the file that does not launch Nine, and that is the
/// point of it: a question you can ask from the Lock Screen and get an answer to
/// is a question you do not have to open an app to worry about.
struct HowsMyStreakIntent: AppIntent {
    static let title = LocalizedStringResource(
        "intent.streak.title", table: IntentStrings.table
    )
    static let description = IntentDescription(
        LocalizedStringResource("intent.streak.description", table: IntentStrings.table)
    )
    /// Deliberately false. Asking about the streak should not cost you the screen
    /// you were looking at.
    static let openAppWhenRun = false

    @Dependency private var model: AppModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let days = model.displayedStreak
        // Three answers, and none of them is a scolding. A zero streak says the
        // board is waiting — it does not say what was lost, because PRD-13's whole
        // argument is that Nine never tells you that. A streak standing on the
        // grace bridge reads exactly like one that is not: `displayedStreak`
        // already folds the bridge in, and surfacing the difference here would be
        // the shield turned into a warning.
        let dialog: IntentDialog
        if days <= 0 {
            dialog = IntentDialog(
                LocalizedStringResource("intent.streak.none", table: IntentStrings.table)
            )
        } else if model.todaySolved {
            dialog = IntentDialog(
                LocalizedStringResource("intent.streak.done", table: IntentStrings.table)
            )
        } else {
            dialog = IntentDialog(
                LocalizedStringResource("intent.streak.waiting", table: IntentStrings.table)
            )
        }
        // **No number in any of the three, on purpose.** "How's my streak" is
        // answered by whether it stands, not by how large it is — and a count is
        // the one thing that turns an answer into a stake. It also means none of
        // these sentences carries a specifier, so a translator moves whole clauses
        // rather than a `%lld` around a verb.
        return .result(dialog: dialog)
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

/// The four App Shortcuts, which is what makes any of the above appear in
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
/// Four rather than eight because `StartABoardIntent` is parameterised: one phrase
/// template with `parameterPresentation` covers all six bands.
struct NineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTodaysDailyIntent(),
            phrases: [
                "Start today's board in \(.applicationName)",
                "Open today's \(.applicationName)",
                "Play the daily in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource(
                "intent.startDaily.short", table: IntentStrings.table
            ),
            systemImageName: "square.grid.3x3"
        )
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
            intent: HowsMyStreakIntent(),
            phrases: [
                "How's my streak in \(.applicationName)",
                "Check my \(.applicationName) streak",
            ],
            shortTitle: LocalizedStringResource(
                "intent.streak.short", table: IntentStrings.table
            ),
            systemImageName: "shield.lefthalf.filled"
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
