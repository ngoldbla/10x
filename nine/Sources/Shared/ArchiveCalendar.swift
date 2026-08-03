// ArchiveCalendar.swift — day-ordinal date arithmetic and labels, as pure
// functions with no clock of their own.
//
// This began as the daily archive's calendar (PRD-14). The archive surface —
// the month grid, its pager, its day states — was removed with the daily
// system (product decision, 2026-08-02); what stays is the arithmetic other
// surfaces still lean on: the board tracker titles legacy `.daily` entries by
// their day, and the History sheet's heat figure labels its rows and columns
// off the same ordinals.
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

/// A calendar month — what the heat figure's caps row is keyed on.
public struct ArchiveMonth: Sendable, Equatable, Hashable, Comparable {
    public let year: Int
    /// 1...12.
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public static func < (lhs: ArchiveMonth, rhs: ArchiveMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

public enum ArchiveCalendar {

    /// See the file header. Every conversion out of an ordinal reads it here —
    /// several times per render, which is why it is a `let`: rebuilding a
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

    // MARK: - Weekday initials (the heat figure's rail)

    /// One letter per column, in the given column order.
    ///
    /// **Ask the locale; do not spell them.** This returned
    /// `["S","M","T","W","T","F","S"]` until PRD-20 — the column *order* has
    /// always respected `firstWeekday`, and the letters were English on every
    /// locale on earth. It is the one unambiguous live locale bug in Nine, and
    /// nothing could see it because nothing ran in a non-English locale: hence
    /// the `locale` argument, which exists so a test can be German
    /// (`ArchiveCalendarTests.testWeekdayInitialsComeFromTheLocale`).
    ///
    /// `veryShortWeekdaySymbols` is always Sunday-first regardless of the
    /// locale's own `firstWeekday`, which is exactly the array this rotation
    /// was already written against.
    public static func weekdayInitials(firstWeekday: Int, locale: Locale = .current) -> [String] {
        let sundayFirst = formatter("", locale: locale).veryShortWeekdaySymbols ?? []
        // Seven or nothing. A short array would index-crash the header, and
        // padding it with English letters would restore the bug quietly — an
        // empty header row is at least visibly wrong.
        guard sundayFirst.count == 7 else { return [] }
        return (0..<7).map { sundayFirst[($0 + firstWeekday - 1) % 7] }
    }

    // MARK: - Labels

    /// "Jul 12, 2026" — the board tracker's row for a legacy `.daily` entry,
    /// which needs the year because the entry can be from any month.
    ///
    /// **Rendered in the player's own calendar system**, because it replaced
    /// `entry.createdAt.formatted(date: .abbreviated)`, which used
    /// `Calendar.current`. Forcing Gregorian here would silently re-render the
    /// tracker for anyone on a Japanese, Buddhist, Hebrew or Islamic calendar.
    public static func mediumLabel(forDayOrdinal ordinal: Int) -> String {
        displayFormatter("MMMdy").string(from: date(forDayOrdinal: ordinal))
    }

    /// Cached, because a `DateFormatter` is expensive to build and a list can
    /// ask for one per row: re-deriving a localized format string each time is
    /// pure waste.
    ///
    /// Keyed on the locale as well as the template, so a player who changes
    /// language mid-session does not keep the old one — the reason this is a
    /// dictionary rather than a handful of `static let`s. `DateFormatter` is
    /// documented thread-safe for formatting, and the lock covers the cache.
    private static let formatterLock = NSLock()
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]

    /// Gregorian labels, pinned to UTC — see the file header.
    private static func formatter(_ template: String, locale: Locale = .current) -> DateFormatter {
        cachedFormatter(template, calendar: calendar, locale: locale)
    }

    /// The player's calendar system, with the clock still pinned to UTC so the
    /// day never slips (see the file header).
    private static func displayFormatter(_ template: String) -> DateFormatter {
        var display = Calendar.current
        display.timeZone = calendar.timeZone
        return cachedFormatter(template, calendar: display, locale: .current)
    }

    private static func cachedFormatter(_ template: String, calendar: Calendar,
                                        locale: Locale) -> DateFormatter {
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
