import XCTest
@testable import NineShared
import NineEngine

/// The calendar shrank with the daily archive's removal (2026-08-02): what
/// remains is the ordinal arithmetic, the tracker's date label and the heat
/// figure's weekday rail, and these are their tests.
final class ArchiveCalendarTests: XCTestCase {

    // MARK: - Ordinals

    /// The label addresses days the same way the seed does, or a date lands on
    /// the wrong square of the heat figure.
    func testDayOrdinalAgreesWithDailySeed() {
        let utc = DailySeed.utcCalendar
        for (year, month, day) in [(2026, 7, 12), (2026, 12, 31), (2027, 3, 1)] {
            let date = utc.date(from: DateComponents(year: year, month: month, day: day))!
            XCTAssertEqual(
                ArchiveCalendar.dayOrdinal(year: year, month: month, day: day),
                DailySeed.dayOrdinal(for: date, calendar: utc),
                "\(year)-\(month)-\(day)"
            )
        }
    }

    func testMonthOfDayOrdinalRoundTrips() {
        for (year, month, day) in [(2026, 7, 1), (2026, 7, 31), (2026, 12, 31), (2027, 1, 1)] {
            let ordinal = ArchiveCalendar.dayOrdinal(year: year, month: month, day: day)
            XCTAssertEqual(
                ArchiveCalendar.month(ofDayOrdinal: ordinal),
                ArchiveMonth(year: year, month: month),
                "\(year)-\(month)-\(day)"
            )
        }
    }

    func testConsecutiveOrdinalsAreConsecutiveDays() {
        let first = ArchiveCalendar.dayOrdinal(year: 2026, month: 7, day: 1)
        let last = ArchiveCalendar.dayOrdinal(year: 2026, month: 7, day: 31)
        XCTAssertEqual(last - first, 30)
    }

    // MARK: - Labels

    /// The highest-value test in this file, and the reason every formatter in
    /// `ArchiveCalendar` is UTC-pinned. A day ordinal is a UTC midnight, so a
    /// formatter left on the device's timezone renders 12 July as "Jul 11"
    /// everywhere west of Greenwich — silently, off by one, with no crash and
    /// no warning, and invisible to anyone developing in UTC+0.
    func testDayLabelsAreStableAcrossTimezones() {
        let ordinal = ArchiveCalendar.dayOrdinal(year: 2026, month: 7, day: 12)
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        var medium: Set<String> = []
        for identifier in ["UTC", "America/Los_Angeles", "Pacific/Kiritimati", "Asia/Tokyo"] {
            NSTimeZone.default = TimeZone(identifier: identifier)!
            medium.insert(ArchiveCalendar.mediumLabel(forDayOrdinal: ordinal))
        }
        XCTAssertEqual(medium.count, 1, "medium label moved with the device timezone: \(medium)")
        XCTAssertTrue(medium.first!.contains("12"), medium.first!)
    }

    /// The English wording, pinned where the locale makes that meaningful.
    func testLabelWordingInEnglish() throws {
        try XCTSkipUnless(Locale.current.identifier.hasPrefix("en"), "non-English locale")
        let ordinal = ArchiveCalendar.dayOrdinal(year: 2026, month: 7, day: 12)
        XCTAssertEqual(ArchiveCalendar.mediumLabel(forDayOrdinal: ordinal), "Jul 12, 2026")
    }

    // MARK: - Weekday initials

    func testWeekdayInitialsRotateWithTheFirstWeekday() throws {
        try XCTSkipUnless(Locale.current.identifier.hasPrefix("en"), "non-English locale")
        XCTAssertEqual(ArchiveCalendar.weekdayInitials(firstWeekday: 1),
                       ["S", "M", "T", "W", "T", "F", "S"])
        XCTAssertEqual(ArchiveCalendar.weekdayInitials(firstWeekday: 2),
                       ["M", "T", "W", "T", "F", "S", "S"])
    }

    /// The letters come from the locale, not from a spelled-out array.
    ///
    /// This is the one unambiguous live locale bug PRD-20 found. The column
    /// *order* has always respected `firstWeekday`; the letters were
    /// `["S","M","T","W","T","F","S"]` on every locale on earth. German is the
    /// sharpest case available: Dienstag and Donnerstag are both "D" and
    /// Mittwoch is "M", so `["M","D","M","D","F","S","S"]` is a sequence no
    /// English array can be mistaken for.
    func testWeekdayInitialsComeFromTheLocale() {
        let german = Locale(identifier: "de_DE")
        XCTAssertEqual(ArchiveCalendar.weekdayInitials(firstWeekday: 2, locale: german),
                       ["M", "D", "M", "D", "F", "S", "S"],
                       "Monday-first German: Montag Dienstag Mittwoch Donnerstag Freitag Samstag Sonntag")
        XCTAssertEqual(ArchiveCalendar.weekdayInitials(firstWeekday: 1, locale: german),
                       ["S", "M", "D", "M", "D", "F", "S"],
                       "the same seven letters, rotated — the order was never the bug")

        // A language whose weekday letters are not letters at all. If this ever
        // reads back as Latin initials, the formatter is not being asked.
        XCTAssertEqual(ArchiveCalendar.weekdayInitials(firstWeekday: 1,
                                                      locale: Locale(identifier: "ja_JP")),
                       ["日", "月", "火", "水", "木", "金", "土"])
    }
}
