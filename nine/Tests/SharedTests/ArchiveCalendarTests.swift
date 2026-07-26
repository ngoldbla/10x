import XCTest
@testable import NineShared
import NineEngine

final class ArchiveCalendarTests: XCTestCase {

    // MARK: - Ordinals

    /// The grid addresses days the same way the streak and the seed do, or a
    /// checkmark lands on the wrong square.
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

    // MARK: - The grid

    func testGridIsSixRowsOfSeven() {
        let grid = ArchiveCalendar.grid(for: ArchiveMonth(year: 2026, month: 7), firstWeekday: 1)
        XCTAssertEqual(grid.count, 6)
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })
    }

    /// 1 July 2026 is a Wednesday, so a Sunday-first grid leads with three
    /// blanks and a Monday-first grid with two.
    func testLeadingBlanksFollowTheFirstWeekday() {
        let july = ArchiveMonth(year: 2026, month: 7)
        let sundayFirst = ArchiveCalendar.grid(for: july, firstWeekday: 1).flatMap { $0 }
        let mondayFirst = ArchiveCalendar.grid(for: july, firstWeekday: 2).flatMap { $0 }
        XCTAssertEqual(sundayFirst.prefix(4).map { $0 == nil }, [true, true, true, false])
        XCTAssertEqual(mondayFirst.prefix(3).map { $0 == nil }, [true, true, false])
    }

    func testGridHoldsEveryDayOfTheMonthInOrderAndNothingElse() {
        for (year, month, days) in [(2026, 7, 31), (2026, 2, 28), (2028, 2, 29), (2026, 4, 30)] {
            let filled = ArchiveCalendar
                .grid(for: ArchiveMonth(year: year, month: month), firstWeekday: 1)
                .flatMap { $0 }
                .compactMap { $0 }
            XCTAssertEqual(filled.count, days, "\(year)-\(month)")
            XCTAssertEqual(filled, filled.sorted(), "\(year)-\(month)")
            XCTAssertEqual(
                filled.first, ArchiveCalendar.dayOrdinal(year: year, month: month, day: 1),
                "\(year)-\(month)"
            )
        }
    }

    /// Six rows always, whatever the shape — a 31-day month starting on the
    /// last column needs 37 slots, and a fixed height keeps the sheet from
    /// resizing under the finger as the pager moves.
    func testASixRowMonthStillFits() {
        // 1 August 2026 is a Saturday: the last Sunday-first column.
        let grid = ArchiveCalendar.grid(for: ArchiveMonth(year: 2026, month: 8), firstWeekday: 1)
        XCTAssertEqual(grid.count, 6)
        XCTAssertEqual(grid.flatMap { $0 }.compactMap { $0 }.count, 31)
        XCTAssertNil(grid[0][5], "the 1st sits in the last column")
        XCTAssertNotNil(grid[0][6])
    }

    // MARK: - Paging

    func testMonthsRunFromTheFloorToTheMonthContainingToday() {
        let today = ArchiveCalendar.dayOrdinal(year: 2026, month: 9, day: 15)
        let months = ArchiveCalendar.months(through: today)
        XCTAssertEqual(months.first, ArchiveCalendar.floor)
        XCTAssertEqual(months.last, ArchiveMonth(year: 2026, month: 9))
        XCTAssertEqual(months.count, 3)
    }

    /// A device whose clock is set before Nine shipped still gets a usable
    /// pager rather than an empty one.
    func testMonthsNeverRunBelowTheFloor() {
        let beforeLaunch = ArchiveCalendar.dayOrdinal(year: 2026, month: 1, day: 1)
        XCTAssertEqual(ArchiveCalendar.months(through: beforeLaunch), [ArchiveCalendar.floor])
    }

    func testMonthsCrossAYearBoundary() {
        let today = ArchiveCalendar.dayOrdinal(year: 2027, month: 2, day: 3)
        let months = ArchiveCalendar.months(through: today)
        XCTAssertEqual(months.count, 8) // Jul 2026 … Feb 2027
        XCTAssertEqual(months.last, ArchiveMonth(year: 2027, month: 2))
        XCTAssertEqual(months, months.sorted())
    }

    func testAdvancingAMonthCrossesTheYearInBothDirections() {
        XCTAssertEqual(
            ArchiveMonth(year: 2026, month: 12).advanced(by: 1), ArchiveMonth(year: 2027, month: 1)
        )
        XCTAssertEqual(
            ArchiveMonth(year: 2027, month: 1).advanced(by: -1), ArchiveMonth(year: 2026, month: 12)
        )
        XCTAssertEqual(
            ArchiveMonth(year: 2026, month: 7).advanced(by: -12), ArchiveMonth(year: 2025, month: 7)
        )
    }

    // MARK: - Labels

    /// The highest-value test in this file, and the reason every formatter in
    /// `ArchiveCalendar` is UTC-pinned. A day ordinal is a UTC midnight, so a
    /// formatter left on the device's timezone renders 12 July as "Jul 11"
    /// everywhere west of Greenwich — silently, off by one, with no crash and
    /// no warning, and invisible to anyone developing in UTC+0.
    ///
    /// Asserts stability rather than wording, so it holds under any CI locale;
    /// the wording is pinned separately below.
    func testDayLabelsAreStableAcrossTimezones() {
        let ordinal = ArchiveCalendar.dayOrdinal(year: 2026, month: 7, day: 12)
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        var short: Set<String> = []
        var long: Set<String> = []
        for identifier in ["UTC", "America/Los_Angeles", "Pacific/Kiritimati", "Asia/Tokyo"] {
            NSTimeZone.default = TimeZone(identifier: identifier)!
            short.insert(ArchiveCalendar.shortLabel(forDayOrdinal: ordinal))
            long.insert(ArchiveCalendar.longLabel(forDayOrdinal: ordinal))
            XCTAssertEqual(ArchiveCalendar.dayNumber(forDayOrdinal: ordinal), 12, identifier)
        }
        XCTAssertEqual(short.count, 1, "short label moved with the device timezone: \(short)")
        XCTAssertEqual(long.count, 1, "long label moved with the device timezone: \(long)")
        XCTAssertTrue(short.first!.contains("12"), short.first!)
        XCTAssertTrue(long.first!.contains("12"), long.first!)
    }

    /// The English wording, pinned where the locale makes that meaningful.
    /// `Locale.current` on a Linux CI container is not the developer's, and a
    /// red lane over a month name would say nothing true about the code.
    func testLabelWordingInEnglish() throws {
        try XCTSkipUnless(Locale.current.identifier.hasPrefix("en"), "non-English locale")
        let ordinal = ArchiveCalendar.dayOrdinal(year: 2026, month: 7, day: 12)
        XCTAssertEqual(ArchiveCalendar.title(for: ArchiveMonth(year: 2026, month: 7)), "July 2026")
        XCTAssertEqual(ArchiveCalendar.shortLabel(forDayOrdinal: ordinal), "Jul 12")
        XCTAssertEqual(ArchiveCalendar.longLabel(forDayOrdinal: ordinal), "July 12")
    }

    func testWeekdayInitialsMatchTheGridColumns() {
        XCTAssertEqual(ArchiveCalendar.weekdayInitials(firstWeekday: 1),
                       ["S", "M", "T", "W", "T", "F", "S"])
        XCTAssertEqual(ArchiveCalendar.weekdayInitials(firstWeekday: 2),
                       ["M", "T", "W", "T", "F", "S", "S"])
    }
}
