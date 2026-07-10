// Episode engine: deterministic nightly draws, curve shape, calendar math.
import XCTest
import CouchCore
@testable import BlockheadEngine

final class EpisodeTests: XCTestCase {

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 21   // showtime
        return utcCalendar.date(from: components)!
    }

    // MARK: Calendar

    func testDayNumberEpoch() {
        XCTAssertEqual(EpisodeCalendar.dayNumber(for: utcDate(2026, 1, 1), calendar: utcCalendar), 0)
        XCTAssertEqual(EpisodeCalendar.dayNumber(for: utcDate(2026, 1, 11), calendar: utcCalendar), 10)
        XCTAssertEqual(EpisodeCalendar.dayNumber(for: utcDate(2026, 7, 10), calendar: utcCalendar), 190)
    }

    func testEpisodeNumberIsDayPlusOne() {
        XCTAssertEqual(EpisodeCalendar.episodeNumber(forDay: 0), 1)
        XCTAssertEqual(EpisodeCalendar.episodeNumber(forDay: 141), 142)
        XCTAssertEqual(EpisodeCalendar.episodeNumber(forDay: -3), 1, "pre-epoch clocks clamp to #1")
    }

    func testNightlySeedIsStableAndDayDependent() {
        XCTAssertEqual(EpisodeCalendar.seed(forDay: 5), EpisodeCalendar.seed(forDay: 5))
        XCTAssertNotEqual(EpisodeCalendar.seed(forDay: 5), EpisodeCalendar.seed(forDay: 6))
    }

    // MARK: Determinism

    func testSameDayProducesIdenticalEpisode() {
        let a = EpisodePlanner.episode(forDay: 190)
        let b = EpisodePlanner.episode(forDay: 190)
        XCTAssertEqual(a.questions.map(\.id), b.questions.map(\.id))
        XCTAssertEqual(a.seed, b.seed)
        XCTAssertEqual(a.number, 191)
    }

    func testDifferentDaysProduceDifferentEpisodes() {
        let a = EpisodePlanner.episode(forDay: 190)
        let b = EpisodePlanner.episode(forDay: 191)
        XCTAssertNotEqual(a.questions.map(\.id), b.questions.map(\.id))
    }

    // MARK: Shape

    func testEpisodeHasTenUniqueQuestions() {
        for day in [0, 7, 100, 365] {
            let episode = EpisodePlanner.episode(forDay: day)
            XCTAssertEqual(episode.questions.count, 10, "day \(day)")
            XCTAssertEqual(Set(episode.questions.map(\.id)).count, 10, "day \(day) drew a duplicate")
        }
    }

    func testDifficultyCurveMatchesWarmHardCoolPlan() {
        let expected = EpisodePlanner.slotPlan.map(\.difficulty)
        XCTAssertEqual(expected, [1, 1, 2, 2, 2, 3, 3, 3, 2, 1], "the curve is the brand")
        for day in 0..<30 {
            let episode = EpisodePlanner.episode(forDay: day)
            XCTAssertEqual(episode.questions.map(\.difficulty), expected, "day \(day)")
        }
    }

    func testEpisodeCompositionIsSixTriviaTwoPictureTwoOdd() {
        for day in 0..<30 {
            let kinds = EpisodePlanner.episode(forDay: day).questions.map { EpisodePlanner.kind(of: $0) }
            XCTAssertEqual(kinds.filter { $0 == .trivia }.count, 6, "day \(day)")
            XCTAssertEqual(kinds.filter { $0 == .picture }.count, 2, "day \(day)")
            XCTAssertEqual(kinds.filter { $0 == .oddOneOut }.count, 2, "day \(day)")
        }
    }

    func testNightsVaryAcrossAWeek() {
        // Consecutive nights should not lean on the same questions.
        let week = (0..<7).map { EpisodePlanner.episode(forDay: 50 + $0) }
        let allIDs = week.flatMap { $0.questions.map(\.id) }
        XCTAssertGreaterThan(Set(allIDs).count, 45, "seven nights should draw a wide spread")
    }

    func testDrawWithThinPackFallsBackInsteadOfCrashing() {
        // A pack with no odd-one-out and no pictures still fills 10 slots.
        let thin = PackGeneral.questions
        let episode = EpisodePlanner.episode(seed: 42, number: 1, dayNumber: 0, from: thin)
        XCTAssertEqual(episode.questions.count, 10)
        XCTAssertEqual(Set(episode.questions.map(\.id)).count, 10)
    }
}
