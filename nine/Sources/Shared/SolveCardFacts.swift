// SolveCardFacts.swift — everything the share card says, with nothing that
// knows how to draw it (PRD-12 §2).
//
// The card is a picture that leaves the app and is then seen only in contexts
// nobody here controls, so its words have to be *provable* rather than eyeballed
// in a preview once. Splitting them out from the view buys three things:
//
//   • they test on Linux CI, beside `BoardSpeech`, which is where the wording of
//     anything a player reads has lived since PRD-19;
//   • `ShareCardView` becomes pure geometry over a struct, with no branching of
//     its own left to get wrong;
//   • **PRD-26 gets the seam.** Its comet replaces the card's *body*, not its
//     chrome, and its debrief needs precisely these captions. A
//     `SolveCardFacts` is what both the still and the 5-second loop are
//     captioned from, so the two cannot drift apart later.
//
// Pure Foundation plus the Engine's `NineGame`, so no SwiftUI leaks into a
// module the widget extension compiles.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

public struct SolveCardFacts: Equatable, Sendable {

    /// The finished grid, row-major. Every entry is 1...9 — a card is only ever
    /// minted from a solved board.
    public let digits: [Int]
    /// Which of those 81 the puzzle supplied. The card draws these in the
    /// theme's digit tone and the player's own in the accent, so the picture
    /// shows at a glance how much of the board was theirs.
    public let givens: [Bool]

    /// "Solved in 3:40".
    public let timeLine: String
    /// "Steady · 12 day streak", or just "Steady".
    public let creditLine: String
    /// "Nine · daily puzzle" on a daily, nil otherwise.
    public let dailyLine: String?
    /// The share sheet's subject line.
    ///
    /// Deliberately carries no URL. PRD-12 §2 makes the wordmark the hook, and
    /// a link pasted into the message body is the growth-hack register the
    /// brand refuses — the card is a gift, not a referral.
    public let shareTitle: String

    public init(
        game: NineGame,
        difficulty: Difficulty,
        isDaily: Bool,
        streak: Int,
        at now: Date
    ) {
        digits = (0..<81).map { game.entry(at: $0) }
        givens = (0..<81).map { game.isGiven($0) }
        timeLine = Phrase.solvedIn(Self.elapsedText(game.timer.elapsed(at: now)))

        // The streak line is daily-only (PRD-12 §2). A free-play board solved in
        // the middle of a 30-day run has not advanced it, and a card implying
        // otherwise would be the app's first dishonest pixel — on the one
        // artifact that outlives the session and cannot be corrected.
        if isDaily, streak > 0 {
            creditLine = "\(Phrase.difficulty(difficulty)) · \(Phrase.streak(streak))"
        } else {
            creditLine = Phrase.difficulty(difficulty)
        }
        dailyLine = isDaily ? Phrase.dailyLine : nil
        shareTitle = "\(Phrase.wordmark) · \(timeLine)"
    }

    /// `m:ss`, with the minutes field allowed to run past 60 rather than growing
    /// an hours field — an hour-long Nocturne is a real thing, and "1:02:05"
    /// reads like a video timestamp on a card this size.
    ///
    /// **The one copy** (PRD-20 Task 8). `String(format: "%d:%02d", …)` was
    /// written out eight times — this line, six files in `Sources/App`, and
    /// `WidgetFormat.time` in the appex — and Task 6 declined to change one of
    /// them alone on the grounds that the widget being the odd one out would be
    /// worse than either answer. It was right; this is that change, made to all
    /// eight at once.
    ///
    /// The shape above is kept exactly. What changes is the *numerals*: `%d`
    /// emits ASCII digits, so an Arabic or Hindi player got `4:12` in the middle
    /// of a sentence set in ٤ and १. `.formatted(.number)` asks the locale, and
    /// `.integerLength(2)` is the localized spelling of `%02d` — it pads with
    /// that locale's own zero, so Arabic reads `٠٧` rather than `07`.
    ///
    /// `.grouping(.never)` on the minutes because they are allowed past 60 and
    /// past 999: a grouped `1,042:05` would read as a date. The `:` is left a
    /// literal — it is the separator in every locale CLDR has a rule for, and
    /// nothing here is a `DateComponentsFormatter` duration, which would spell
    /// this "4 min 12 sec" and not fit the card at all.
    public static func elapsedText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let minutes = (total / 60).formatted(.number.grouping(.never))
        let seconds = (total % 60).formatted(.number.precision(.integerLength(2)))
        return "\(minutes):\(seconds)"
    }

    /// The card's words, through the one seam (PRD-20). These were English
    /// literals until the catalog existed, and the same four strings were *also*
    /// sitting in `EnglishPhrases.table` as `card.*` — character-identical by
    /// inspection and by nothing else. Task 9 freezes that table into nine
    /// translations, at which point "identical by inspection" would have meant
    /// the share card stays English in every one of them. Wired rather than
    /// pinned with an equality test, because a pin keeps two lists and this
    /// keeps one.
    private enum Phrase {
        /// Never localized: it is the mark, not a word. `#"…"#` is the repo's
        /// never-localize marker (`ShareCardMetrics.wordmark`, `strings.py`),
        /// and a marker you have to type is a marker somebody had to mean.
        static let wordmark = #"NINE"#
        static var dailyLine: String { Phrasebook.current.string("card.daily") }
        static func solvedIn(_ clock: String) -> String {
            Phrasebook.current.string("card.time", .text(clock))
        }
        static func streak(_ days: Int) -> String {
            Phrasebook.current.string("card.streak", .int(days))
        }
        /// Keyed off the frozen raw value, for the reason
        /// `BoardSpeech.Phrase.techniqueName` gives: the Engine stopped naming
        /// things, and a `switch` here would be a second list.
        static func difficulty(_ difficulty: Difficulty) -> String {
            Phrasebook.current.string("difficulty.\(difficulty.rawValue).title")
        }
    }
}
