// NineFocusFilter.swift — PRD-33. Focus that *adds* calm.
//
// A Focus filter normally does one of two things: silence an app's notifications,
// or switch which account it shows. Nine has no accounts, and it sends no
// notifications — the covenant allows one opt-in silent daily reminder, off by
// default, and even that does not exist yet. So `appContext` stays at its default
// and there is no notification predicate to hand over.
//
// What is left is the only thing Nine can offer: turning down its own pull. Two
// switches, because they answer different questions. Hiding the streak removes
// what makes a missed day feel like a cost. Hiding the daily removes what makes an
// unstarted board feel like a task. A player who wants one often does not want
// both — during Work you might want the count gone and a board still one tap
// away; during Sleep, the reverse.
//
// Available on every platform Nine ships (`SetFocusFilterIntent` is iOS 16 /
// macOS 13 / tvOS 16), and compiled on all three: a Focus is a system-wide state
// and an Apple TV in a Work Focus should be as quiet as the phone.
import AppIntents
import Foundation

struct QuietShelfFilter: SetFocusFilterIntent {
    static let title = LocalizedStringResource(
        "intent.focus.title", table: IntentStrings.table
    )
    static let description = IntentDescription(
        LocalizedStringResource("intent.focus.description", table: IntentStrings.table)
    )

    @Parameter(
        title: LocalizedStringResource("intent.focus.hideDaily", table: IntentStrings.table),
        default: false
    )
    var hideDaily: Bool

    @Parameter(
        title: LocalizedStringResource("intent.focus.hideStreak", table: IntentStrings.table),
        default: true
    )
    var hideStreak: Bool

    /// What Settings ▸ Focus shows as the current state of this filter. Without it
    /// the row reads as the intent's title and nothing else, and a player cannot
    /// tell a configured filter from an unconfigured one.
    var displayRepresentation: DisplayRepresentation {
        let key: String
        switch (hideDaily, hideStreak) {
        case (true, true): key = "intent.focus.state.both"
        case (true, false): key = "intent.focus.state.daily"
        case (false, true): key = "intent.focus.state.streak"
        case (false, false): key = "intent.focus.state.none"
        }
        // The one interpolated key in the intents layer, and it is safe because
        // nothing static reads it: `displayRepresentation` is evaluated at
        // *runtime* by the system, not extracted by
        // `appintentsmetadataprocessor`. `IntentCatalogTests` still checks all
        // four rows exist, by naming them itself — the check the extractor cannot
        // do for us.
        return DisplayRepresentation(
            title: LocalizedStringResource(
                String.LocalizationValue(key), table: IntentStrings.table
            )
        )
    }

    @Dependency private var model: AppModel

    init() {}

    init(hideDaily: Bool, hideStreak: Bool) {
        self.hideDaily = hideDaily
        self.hideStreak = hideStreak
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // This runs on **both** edges: the system calls it when a Focus turns on
        // with this filter configured, and again with the filter's default state
        // when the Focus turns off. So there is no "clear" path to write — the
        // second call is the clear.
        model.applyFocus(QuietFocus(hidesDaily: hideDaily, hidesStreak: hideStreak))
        return .result()
    }
}
