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

public enum ArchiveCalendar {

    /// The month Nine's first daily existed (first `nine/` commit: 2026-07-11).
    ///
    /// `DailySeed` will happily produce a seed for 2019, and the pager could
    /// scroll back forever on that alone — but a day before Nine shipped was
    /// never anybody's daily. Offering it would be content dressed as history,
    /// so the floor is a launch date rather than an absence of one (PRD-14 §2,
    /// "a sane floor … no infinite scroll").
    public static let floor = ArchiveMonth(year: 2026, month: 7)

    /// See the file header. Every conversion out of an ordinal reads it here.
    private static var calendar: Calendar { DailySeed.utcCalendar }

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

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone   // the whole point — see the file header
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
