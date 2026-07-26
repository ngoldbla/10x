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
            creditLine = "\(difficulty.title) · \(Phrase.streak(streak))"
        } else {
            creditLine = difficulty.title
        }
        dailyLine = isDaily ? Phrase.dailyLine : nil
        shareTitle = "\(Phrase.wordmark) · \(timeLine)"
    }

    /// `m:ss`, with the minutes field allowed to run past 60 rather than growing
    /// an hours field — an hour-long Nocturne is a real thing, and "1:02:05"
    /// reads like a video timestamp on a card this size.
    public static func elapsedText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // PRD-20 seam: these become `LocalizedStringResource` lookups.
    private enum Phrase {
        static let wordmark = "NINE"
        static let dailyLine = "Nine · daily puzzle"
        static func solvedIn(_ clock: String) -> String { "Solved in \(clock)" }
        static func streak(_ days: Int) -> String { "\(days) day streak" }
    }
}
