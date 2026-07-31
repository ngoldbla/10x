// DailyTable.swift — twenty people, one week, and the arithmetic that makes
// "completion-consistency first, time second" fit in the one integer a
// leaderboard carries (PRD-29).
//
// **The one idea: a table is a window, not a cohort.** GameKit cannot partition
// players — there is no API that assigns you to table 47 and remembers it — but
// `GKLeaderboard.loadEntries(for:timeScope:range:)` takes a range of absolute
// rank positions and hands back the local player's own entry alongside. So the
// twenty people around you are two loads: one that tells you your rank, and one
// that asks for the twenty seats centred on it.
//
// Everything the covenant wants falls out of that as a property rather than a
// promise:
//
//   * There is no Table 3 and no Table 4, so **there is nothing to be relegated
//     from**. "No demotion shame" is a sentence that cannot be spelled here,
//     because the noun it needs does not exist.
//   * A delta needs two observations and Nine keeps one. Nothing in this file,
//     and nothing persisted anywhere by this PRD beyond a single `Bool`, records
//     a previous position — so "you dropped four places" is a message no code
//     path can construct. `DailyTableTests` reflects over `Seat` and `Week` and
//     fails if either grows a field that would let it.
//
// Pure Foundation plus the Engine's `SolveHistory`, like every other file in
// this tree. No GameKit, no clock read, nothing Darwin-only — which is what lets
// the whole ranking rule be tested with no leaderboard, on a platform that has
// no Game Center.
import Foundation

#if canImport(NineEngine)
import NineEngine
#endif

public enum DailyTable {

    // MARK: - The week

    public static let daysInWeek = 7

    /// The Monday that opens the week containing `ordinal`.
    ///
    /// Day ordinal 0 is 2001-01-01, which was a Monday (`DailySeed.dayOrdinal`
    /// builds every ordinal off that reference date), so this is exact with no
    /// `Calendar`, no `Locale`, no `TimeZone` and no branch. The floor-mod is
    /// load-bearing rather than defensive: Swift's `%` keeps the sign of the
    /// dividend, and ordinals before 2001 are negative.
    ///
    /// **`Calendar.firstWeekday` is deliberately not consulted**, and it is the
    /// one place in Nine where the player's own settings are overruled on
    /// purpose. A US player whose week starts on Sunday and a German player whose
    /// week starts on Monday, counting against one leaderboard occurrence, are
    /// two people playing different games and neither of them can tell. The week
    /// is a property of the league. The *day* boundary is still local midnight,
    /// because `DailySeed.dayOrdinal` is what defines a daily and a league about
    /// dailies has to agree with them.
    public static func weekStart(containing ordinal: Int) -> Int {
        ordinal - ((ordinal % daysInWeek) + daysInWeek) % daysInWeek
    }

    /// The seven ordinals of `ordinal`'s week, Monday through Sunday.
    public static func week(containing ordinal: Int) -> ClosedRange<Int> {
        let start = weekStart(containing: ordinal)
        return start...(start + daysInWeek - 1)
    }

    // MARK: - A week, as the leaderboard carries it

    /// How many of the week's dailies you finished, and how long they took
    /// altogether.
    ///
    /// **Total seconds rather than an average, and the two induce the identical
    /// order.** Time only ever breaks a tie; a tie is by definition an equal day
    /// count; an equal day count is an equal denominator. The cheaper one is
    /// therefore the correct one, and it is also the one with no division and no
    /// nil-when-empty case.
    public struct Week: Equatable, Sendable {
        /// 0…7, clamped on the way in.
        public let days: Int
        /// Total seconds across those days, never negative.
        public let seconds: Int

        public init(days: Int, seconds: Int) {
            self.days = min(max(0, days), DailyTable.daysInWeek)
            self.seconds = max(0, seconds)
        }

        /// A week nobody played. Never submitted — a player who opted in and has
        /// not started is not a row anybody needs to see.
        public var isEmpty: Bool { days == 0 }
    }

    /// Count this week off the player's own history.
    ///
    /// Nothing new is persisted to make this work: `nine.history` has held every
    /// solve's date, `isDaily` and `seconds` since 1.0.
    ///
    /// Three rules, each of which is a hole if it is not there:
    ///
    ///   * **Dailies only.** Free boards are unbounded, so a league scored on
    ///     them is a league scored on volume.
    ///   * **The first solve of a day, not the fastest.** A daily can be replayed
    ///     (`BoardLibrary.adoptDaily` reuses the day's slot) and "fastest" pays
    ///     for repetition, which is the grinding a covenant that bans
    ///     gamification is trying not to buy.
    ///   * **A day with no recorded time does not count at all.** `score` clamps
    ///     a week to at least one second, so an untimed day would rank as the
    ///     fastest solve possible. Dropping it is the only reading that neither
    ///     invents a number nor rewards the absence of one.
    ///
    /// `trusting` is PRD-29 §5's gate, keyed by day ordinal because that is what
    /// the caller can resolve to a board and then to a replay — `SolveRecord`
    /// carries no board id. An untrusted day is dropped and the rest of the week
    /// survives, deliberately: poisoning six honest days for one unreadable
    /// record punishes a bug far more often than a person.
    ///
    /// Classic only, because `nine.channels` exists precisely so a killer streak
    /// cannot dilute a classic one (PRD-24) — and this reads `nine.history`,
    /// which no channel solve has ever touched. The separation needs no argument
    /// here; it was made a type one layer down.
    public static func tally(
        _ history: SolveHistory,
        over week: ClosedRange<Int>,
        calendar: Calendar = .current,
        trusting: (Int) -> Bool = { _ in true }
    ) -> Week {
        var firstPerDay: [Int: SolveRecord] = [:]
        for record in history.records {
            guard record.isDaily, record.seconds > 0 else { continue }
            let ordinal = DailySeed.dayOrdinal(for: record.date, calendar: calendar)
            guard week.contains(ordinal), trusting(ordinal) else { continue }
            if let held = firstPerDay[ordinal], held.date <= record.date { continue }
            firstPerDay[ordinal] = record
        }
        let seconds = firstPerDay.values.reduce(0.0) { $0 + $1.seconds }
        return Week(days: firstPerDay.count, seconds: Int(seconds.rounded()))
    }

    // MARK: - The score

    /// The width of the time field, in seconds — about 11.6 days, which a 7-day
    /// window cannot reach, which is exactly why the ceiling can be this
    /// generous.
    public static let timeSpan = 1_000_000

    /// A week packed into the one `Int64` a leaderboard carries, sorted
    /// **descending**.
    ///
    /// More days always beats fewer days by a margin no amount of speed can
    /// close; inside a day count the faster week wins.
    ///
    /// **The clamp's lower bound is 1, not 0.** At zero the second term equals
    /// `timeSpan` and the whole score equals `(days + 1) * timeSpan` — one full
    /// day of consistency, manufactured by arithmetic. `tally` already refuses to
    /// count an untimed day, so this is the second of two guards on the same
    /// hole; both are cheap and the failure they prevent is silent.
    public static func score(of week: Week) -> Int {
        let seconds = min(max(1, week.seconds), timeSpan)
        return week.days * timeSpan + (timeSpan - seconds)
    }

    /// The score read back out — which is how the drawn table gets both numbers
    /// from a leaderboard entry with no second fetch and no side channel.
    ///
    /// **`GKLeaderboard.Entry.context` is deliberately left at 0.** It is a real
    /// 64-bit payload and riding the day count in it is the obvious move; it is
    /// refused for `Strings.channel(_:)`'s reason, that a second source for a
    /// number this one already determines is a second thing that can disagree,
    /// and the one that disagrees will be the one drawn.
    /// `>= 0` and not `> 0`, which the round-trip sweep caught: a score of
    /// exactly zero is `days: 0, seconds: timeSpan` — the saturated bottom of the
    /// field, and a legal reading. A *negative* score is not: nothing this app
    /// submits can produce one, so it is a corrupt entry and the honest answer is
    /// an empty week rather than whatever truncating division makes of it.
    public static func week(fromScore score: Int) -> Week {
        guard score >= 0 else { return Week(days: 0, seconds: 0) }
        return Week(days: score / timeSpan, seconds: timeSpan - (score % timeSpan))
    }

    // MARK: - The window

    /// How many seats a table has. Twenty is PROGRAM-2.0 §97's number.
    public static let seatCount = 20

    /// The absolute rank positions a table of `size` should ask for, given where
    /// the local player sits and how many people are on the board.
    ///
    /// Three properties, and the third is the product decision:
    ///
    ///   * **Centred.** You are the tenth of twenty wherever you can be.
    ///   * **Always full.** Near the top the window slides down, near the bottom
    ///     it slides up; nobody is ever shown an empty table and nobody is ever
    ///     shown the bottom of one.
    ///   * **Never padded.** A league smaller than a table is the whole league,
    ///     with the seats it actually has — honest absence over fake data.
    ///
    /// Ranks are 1-based, which is GameKit's convention. Nonsense in gives a
    /// legal window out rather than a trap: this arithmetic runs on numbers a
    /// server chose.
    public static func window(
        around rank: Int, total: Int, size: Int = seatCount
    ) -> ClosedRange<Int> {
        let width = max(1, min(size, max(1, total)))
        let highestStart = max(1, max(1, total) - width + 1)
        let ideal = rank - (width - 1) / 2
        let start = min(max(1, ideal), highestStart)
        return start...(start + width - 1)
    }

    // MARK: - A seat

    /// One row of the table.
    ///
    /// **No rank, no previous rank, no delta, no tier, no division** — see this
    /// file's header, and `DailyTableTests.testASeatCarriesNoPositionAndNoHistory`,
    /// which reflects over this type's stored properties and fails if one
    /// appears. The order of the array *is* the rank; printing it invites
    /// arithmetic, and storing it would make a demotion computable.
    ///
    /// The week glyph a seat draws is a function of `week.days` alone — N marks
    /// of seven, in order — and that is honesty rather than economy: the score
    /// carries a *count*, not a calendar, so nobody's actual days are knowable
    /// from a leaderboard entry and drawing them positionally would be a
    /// fabrication. Your own row is drawn the same way as everybody else's for
    /// the same reason a share card never says more than it measured.
    public struct Seat: Identifiable, Equatable, Sendable {
        /// `GKPlayer.gamePlayerID`, or a synthetic id for the demo standing.
        public let id: String
        public let name: String
        public let week: Week
        public let isMe: Bool

        public init(id: String, name: String, week: Week, isMe: Bool) {
            self.id = id
            self.name = name
            self.week = week
            self.isMe = isMe
        }
    }
}
