// Daily mutators, feed ordering, and score bookkeeping.
import XCTest
@testable import CartridgeEngine

final class DailyTests: XCTestCase {
    private func day(_ offset: Int) -> DayStamp {
        // Walk across month/year boundaries deterministically.
        let base = Date(timeIntervalSince1970: 1_760_000_000) // Oct 2025
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = base.addingTimeInterval(Double(offset) * 86_400)
        return DayStamp(date: date, calendar: calendar)
    }

    func testMutatorIsDeterministicPerGameAndDay() {
        for id in GameID.allCases {
            let d = day(3)
            XCTAssertEqual(
                DailyChallenge.mutator(for: id, on: d),
                DailyChallenge.mutator(for: id, on: d)
            )
        }
    }

    func testMutatorVariesAcrossDaysAndGames() {
        let a = DailyChallenge.mutator(for: .flap, on: day(0))
        let b = DailyChallenge.mutator(for: .flap, on: day(1))
        XCTAssertNotEqual(a, b, "consecutive days should differ")
        let c = DailyChallenge.mutator(for: .noodle, on: day(0))
        XCTAssertNotEqual(a, c, "same day, different games should differ")
    }

    func testMutatorStaysInBounds() {
        for offset in 0..<200 {
            for id in GameID.allCases {
                let m = DailyChallenge.mutator(for: id, on: day(offset))
                XCTAssertTrue(Mutator.speedRange.contains(m.speed))
                XCTAssertTrue(Mutator.gravityRange.contains(m.gravity))
                XCTAssertTrue(Mutator.spawnRange.contains(m.spawn))
                XCTAssertTrue((0..<Mutator.paletteCount).contains(m.paletteID))
            }
        }
    }

    func testFeedOrderIsDeterministicAndComplete() {
        for offset in 0..<60 {
            let d = day(offset)
            let order = DailyChallenge.feedOrder(on: d)
            XCTAssertEqual(order, DailyChallenge.feedOrder(on: d))
            XCTAssertEqual(Set(order), Set(GameID.allCases), "every game exactly once")
            XCTAssertEqual(order.count, GameID.allCases.count)
            XCTAssertEqual(order.first, DailyChallenge.featuredGame(on: d), "daily challenge leads the feed")
        }
    }

    func testFeaturedGameRotates() {
        let featured = Set((0..<30).map { DailyChallenge.featuredGame(on: day($0)) })
        XCTAssertGreaterThan(featured.count, 1, "the marquee should rotate over a month")
    }

    func testDayStampSeedStable() {
        XCTAssertEqual(DayStamp(year: 2026, month: 7, day: 10).seed,
                       DayStamp(year: 2026, month: 7, day: 10).seed)
        XCTAssertNotEqual(DayStamp(year: 2026, month: 7, day: 10).seed,
                          DayStamp(year: 2026, month: 7, day: 11).seed)
    }

    func testScoreBook() {
        var book = ScoreBook()
        XCTAssertEqual(book.best(for: .flap), 0)
        XCTAssertTrue(book.record(5, for: .flap))
        XCTAssertFalse(book.record(3, for: .flap), "lower score is not a new best")
        XCTAssertTrue(book.record(9, for: .flap))
        XCTAssertEqual(book.best(for: .flap), 9)
        XCTAssertEqual(book.best(for: .putt), 0, "games are tracked independently")
    }

    func testMutatorLabelIsHumane() {
        XCTAssertEqual(Mutator.identity.label, "Classic day")
        let turbo = Mutator(speed: 1.2, gravity: 1, spawn: 1, paletteID: 0)
        XCTAssertEqual(turbo.label, "Turbo day")
        let floaty = Mutator(speed: 1, gravity: 0.85, spawn: 1, paletteID: 0)
        XCTAssertEqual(floaty.label, "Floaty day")
    }

    func testDailySessionAppliesMutator() {
        let d = day(4)
        let session = CartridgeCatalog.dailySession(for: .flap, on: d, seed: 1)
        XCTAssertEqual(session.mutator, DailyChallenge.mutator(for: .flap, on: d))
    }
}
