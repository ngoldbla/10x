// ArchiveCalendar.swift — every date computation the daily archive needs
// (PRD-14), as pure functions with no clock of their own.
//
// One rule runs through all of it, and it is the reason this is a Linux-tested
// unit rather than arithmetic inlined into a SwiftUI view.
//
// **A day ordinal is a UTC midnight.** `DailySeed.dayOrdinal` takes the *local*
// y/m/d and reinterprets it as a UTC midnight, so an ordinal already is the
// player's calendar day, re-encoded. Read one back in the device's own timezone
// and every player west of Greenwich sees the day before: 12 July renders as
// "Jul 11" in Los Angeles. It never crashes, never warns, and is invisible to
// anyone developing in UTC+0. So every calendar and every formatter here is
// pinned to UTC, and `testDayLabelsAreStableAcrossTimezones` is what keeps them
// that way.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

/// A calendar month — what the archive pages through.
public struct ArchiveMonth: Sendable, Equatable, Hashable, Comparable {
    public let year: Int
    /// 1...12.
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public func advanced(by months: Int) -> ArchiveMonth {
        let total = year * 12 + (month - 1) + months
        return ArchiveMonth(year: total / 12, month: total % 12 + 1)
    }

    public static func < (lhs: ArchiveMonth, rhs: ArchiveMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// What the grid knows about one day.
///
/// Two orthogonal facts rather than one flat list of states, because they *are*
/// orthogonal — a flat enum cannot say "today, and already solved", which is
/// what every player sees for most of every evening. `progress` is what the
/// player did with the board; `position` is where the day sits relative to now.
/// The cell renders one on each channel: position as the background, progress
/// as the mark.
public struct ArchiveDayState: Sendable, Equatable {

    public enum Progress: Sendable, Equatable { case solved, inProgress, untouched }

    /// `beforeLaunch` is not decoration. The floor month contains ten days that
    /// precede Nine's first daily, and they are not "past days you could have
    /// played" — nothing was ever served on them. Rendered exactly like
    /// `future`: present, unplayable, and making no claim either way.
    public enum Position: Sendable, Equatable { case beforeLaunch, past, today, future }

    public var progress: Progress
    public var position: Position

    public init(progress: Progress, position: Position) {
        self.progress = progress
        self.position = position
    }

    /// Only days Nine actually served, and only up to today.
    public var isPlayable: Bool { position == .past || position == .today }
}

public enum ArchiveCalendar {

    /// The month Nine's first daily existed (first `nine/` commit: 2026-07-11).
    ///
    /// `DailySeed` will happily produce a seed for 2019, and the pager could
    /// scroll back forever on that alone — but a day before Nine shipped was
    /// never anybody's daily. Offering it would be content dressed as history,
    /// so the floor is a launch date rather than an absence of one (PRD-14 §2,
    /// "a sane floor … no infinite scroll").
    public static let floor = ArchiveMonth(year: 2026, month: 7)

    /// Nine's first daily: 11 July 2026, the day of the first `nine/` commit.
    /// The floor *month* is where the pager stops; this is what is actually
    /// playable, and the two differ by the ten days at the head of that month
    /// on which Nine served nothing at all.
    public static let floorDayOrdinal = dayOrdinal(year: 2026, month: 7, day: 11)

    /// See the file header. Every conversion out of an ordinal reads it here —
    /// several times per grid cell, which is why it is a `let`: rebuilding a
    /// `Calendar` and re-resolving `TimeZone(identifier: "UTC")` per access is
    /// pure waste on a render path. `Calendar` is a Sendable value type.
    private static let calendar: Calendar = DailySeed.utcCalendar

    // MARK: - Ordinals

    public static func dayOrdinal(year: Int, month: Int, day: Int) -> Int {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return Int((date.timeIntervalSinceReferenceDate / 86_400).rounded(.down))
    }

    public static func date(forDayOrdinal ordinal: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(ordinal) * 86_400)
    }

    public static func month(ofDayOrdinal ordinal: Int) -> ArchiveMonth {
        let components = calendar.dateComponents([.year, .month], from: date(forDayOrdinal: ordinal))
        return ArchiveMonth(year: components.year!, month: components.month!)
    }

    /// The day-of-month a cell prints, 1...31.
    public static func dayNumber(forDayOrdinal ordinal: Int) -> Int {
        calendar.component(.day, from: date(forDayOrdinal: ordinal))
    }

    // MARK: - Paging

    /// Every month the pager may reach, oldest first: the floor through the
    /// month holding `today`. Never empty, and never below the floor even on a
    /// device whose clock is set before Nine shipped.
    public static func months(through today: Int) -> [ArchiveMonth] {
        let last = max(floor, month(ofDayOrdinal: today))
        var months: [ArchiveMonth] = []
        var cursor = floor
        while cursor <= last {
            months.append(cursor)
            cursor = cursor.advanced(by: 1)
        }
        return months
    }

    // MARK: - The grid

    /// Six rows of seven, oldest first, `nil` outside the month.
    ///
    /// Six rows *always*: a 31-day month beginning in the last column needs 37
    /// slots, and a fixed height keeps the sheet from resizing under the finger
    /// as the pager moves.
    ///
    /// `firstWeekday` is the caller's locale convention (1 = Sunday), passed in
    /// rather than read, so this stays a pure function.
    public static func grid(for month: ArchiveMonth, firstWeekday: Int) -> [[Int?]] {
        let start = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1))!
        let first = dayOrdinal(year: month.year, month: month.month, day: 1)
        let dayCount = calendar.range(of: .day, in: .month, for: start)!.count
        // Calendar weekdays are 1 = Sunday; the offset is how far the 1st sits
        // from the column this locale starts its weeks on.
        let leading = ((calendar.component(.weekday, from: start) - firstWeekday) + 7) % 7
        var slots = [Int?](repeating: nil, count: 42)
        for day in 0..<dayCount { slots[leading + day] = first + day }
        return (0..<6).map { Array(slots[($0 * 7)..<($0 * 7 + 7)]) }
    }

    /// One letter per grid column, in the grid's own column order.
    public static func weekdayInitials(firstWeekday: Int) -> [String] {
        let sundayFirst = ["S", "M", "T", "W", "T", "F", "S"]
        return (0..<7).map { sundayFirst[($0 + firstWeekday - 1) % 7] }
    }

    // MARK: - Labels

    /// "July 2026" — the pager's heading.
    public static func title(for month: ArchiveMonth) -> String {
        let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1))!
        return formatter("MMMMy").string(from: date)
    }

    /// "Jul 12" — the in-game chip.
    public static func shortLabel(forDayOrdinal ordinal: Int) -> String {
        formatter("MMMd").string(from: date(forDayOrdinal: ordinal))
    }

    /// "July 12" — the date half of a grid cell's accessibility label.
    public static func longLabel(forDayOrdinal ordinal: Int) -> String {
        formatter("MMMMd").string(from: date(forDayOrdinal: ordinal))
    }

    /// "Jul 12, 2026" — the board tracker's row, which needs the year because
    /// it lists boards from any month the archive reaches.
    ///
    /// **The one label rendered in the player's own calendar system**, because
    /// it replaced `entry.createdAt.formatted(date: .abbreviated)`, which used
    /// `Calendar.current`. Forcing Gregorian here would silently re-render the
    /// tracker for anyone on a Japanese, Buddhist, Hebrew or Islamic calendar —
    /// and leave that row disagreeing with the `statusLine` two lines below it,
    /// which still formats in their calendar. The archive's own surfaces stay
    /// Gregorian: the grid *is* a Gregorian month, and titling it otherwise
    /// would describe a shape it does not have.
    public static func mediumLabel(forDayOrdinal ordinal: Int) -> String {
        displayFormatter("MMMdy").string(from: date(forDayOrdinal: ordinal))
    }

    /// What VoiceOver says on a grid cell.
    ///
    /// It lives here, not in the view, for the reason PRD-19 put the Voice
    /// Control input labels in `BoardSpeechTests`: the archive is the one
    /// screen that can never have an AX baseline, because every label in it is
    /// derived from today's date and would rot overnight. A unit test is the
    /// only coverage this wording can have, so the wording has to be reachable
    /// from one.
    ///
    /// Both channels are spoken, and in that order — the date first because it
    /// is what the player is navigating by.
    public static func accessibilityLabel(
        forDayOrdinal ordinal: Int, state: ArchiveDayState
    ) -> String {
        var parts = [longLabel(forDayOrdinal: ordinal)]
        if state.position == .today { parts.append(Phrase.today) }
        switch state.progress {
        case .solved: parts.append(Phrase.solved)
        case .inProgress: parts.append(Phrase.inProgress)
        case .untouched:
            // A day you cannot play is not "not played" — a future day is not
            // here yet and a pre-launch day never had a puzzle. Either way,
            // saying "not played" invites a player to go and play it.
            if state.isPlayable { parts.append(Phrase.notPlayed) }
        }
        return parts.joined(separator: ", ")
    }

    /// The archive's spoken vocabulary, in one block — the seam PRD-20 converts
    /// to `LocalizedStringResource`.
    private enum Phrase {
        static let today = "today"
        static let solved = "solved"
        static let inProgress = "in progress"
        static let notPlayed = "not played"
    }

    /// Cached, because a `DateFormatter` is expensive to build and the grid
    /// asks for one **per cell**: `accessibilityLabel` runs 42 times on every
    /// body evaluation, and re-deriving a localized format string each time is
    /// pure waste.
    ///
    /// Keyed on the locale as well as the template, so a player who changes
    /// language mid-session does not keep the old one — the reason this is a
    /// dictionary rather than four `static let`s. `DateFormatter` is documented
    /// thread-safe for formatting, and the lock covers the cache itself.
    private static let formatterLock = NSLock()
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]

    /// The archive's own labels: Gregorian, because the grid is a Gregorian
    /// month and its captions have to describe the shape on screen.
    private static func formatter(_ template: String) -> DateFormatter {
        cachedFormatter(template, calendar: calendar)
    }

    /// The player's calendar system, with the clock still pinned to UTC so the
    /// day never slips (see the file header). For labels that replaced an
    /// existing `Calendar.current` rendering.
    private static func displayFormatter(_ template: String) -> DateFormatter {
        var display = Calendar.current
        display.timeZone = calendar.timeZone
        return cachedFormatter(template, calendar: display)
    }

    private static func cachedFormatter(_ template: String, calendar: Calendar) -> DateFormatter {
        let locale = Locale.current
        let key = "\(template)|\(locale.identifier)|\(calendar.identifier)"
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let cached = formatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone   // the whole point — see the file header
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = formatter
        return formatter
    }
}
