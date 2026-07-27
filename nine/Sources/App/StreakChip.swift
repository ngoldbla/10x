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

struct StreakChip: View {
    let days: Int
    /// The streak currently stands on a grace bridge (PRD-13 §3).
    let held: Bool

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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BoardSpeech.streakChip(days: days, held: held))
    }
}
