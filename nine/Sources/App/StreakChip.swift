// StreakChip.swift — the shelf's streak capsule, and the one place PRD-13's
// shield is drawn.
//
// Four call sites had grown the same `GlassChip("\(n) day streak", systemImage:
// "flame")` literal — the iOS header, the tvOS header, the Mac header and the
// iOS ambient slot — so the glyph rule lives here once rather than being
// remembered in four files.
//
// **The shield replaces the flame; it is not added beside it.** PRD-13 §3 asks
// for a chip that "gains" a `shield.lefthalf.filled`, and `GlassChip` renders
// exactly one `systemImage`. The two ways to obey the wording are both worse: a
// badge overlaid on a capsule clips at the top Dynamic Type sizes (the capsule
// grows, the offset does not), and a second chip beside the first is the
// accretion the craft charter's anti-bloat clause exists to refuse. Replacing
// also reads truer — the flame is the streak burning, the shield is the streak
// being held — and it keeps the header at exactly the width it had.
//
// The label comes from `BoardSpeech`, not from the glyph. Unlabelled, VoiceOver
// reads the SF Symbol's own name: "shield, left half filled, 12 day streak",
// which announces a mechanic the covenant says does not exist.
import SwiftUI
import CouchKit
// `.bounce` is a `Symbols.BounceSymbolEffect`, and SwiftUI imports that module
// without re-exporting it, so a bare `import SwiftUI` does not resolve the
// member — the same trap `CouchKit/GlassComponents.swift` records above its own
// `import Symbols`. Available on every SDK this target builds for (iOS/tvOS 17,
// macOS 14; Nine deploys to iOS/tvOS 18 and macOS 15).
import Symbols

struct StreakChip: View {
    let days: Int
    /// The streak currently stands on a grace bridge (PRD-13 §3).
    let held: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The chip's symbol, shared with the ambient slot, which draws its own
    /// capsule and so cannot use this view.
    static func symbol(held: Bool) -> String {
        held ? "shield.lefthalf.filled" : "flame"
    }

    var body: some View {
        // `board.streak.plain` is the same key `BoardSpeech.streakChip` reads
        // for the unheld case, so the capsule and the VoiceOver label behind it
        // cannot say two different numbers of days in two different ways.
        GlassChip(Strings.string("board.streak.plain", .int(days)),
                  systemImage: Self.symbol(held: held))
            // **The chip already knows how to roll; nothing was ever telling it
            // to.** `GlassChip` carries `.monospacedDigit()`,
            // `.contentTransition(.numericText())` and
            // `.contentTransition(.symbolEffect(.replace))` inside it, but a
            // content transition is a *description of how to animate*, not an
            // animation: with no transaction driving the change, 11 → 12 and
            // flame → shield both hard-cut, which is exactly what shipped. The
            // two `.animation(_:value:)`s below are the transaction. Two
            // modifiers rather than one composite value because the digit and
            // the glyph change for unrelated reasons — the streak grows at
            // midnight, the shield appears the moment a grace bridge is spent —
            // and a combined value would animate each on the other's behalf.
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: days)
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: held)
            // The one number in Nine a player is emotionally invested in, so it
            // gets the beat as well as the roll. `symbolEffect` applies to every
            // symbol image in the subtree, which is how it reaches the `Image`
            // sealed inside `GlassChip` without needing a label-generic overload
            // — one does not exist; `GlassChip`'s only initialiser is the
            // `String` one, contrary to what this order assumed.
            //
            // Reduce Motion is honoured by feeding the effect a value that
            // cannot change rather than by branching the view: a `@ViewBuilder`
            // fork here would give the chip two identities and cost it the
            // crossfade it just gained.
            .symbolEffect(.bounce, value: reduceMotion ? 0 : days)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BoardSpeech.streakChip(days: days, held: held))
    }
}
