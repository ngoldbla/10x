// ScoringTests.swift — points and solve-history bookkeeping (pure, no UI).
import Testing
import Foundation
@testable import NineEngine

@Suite("SolveScore")
struct SolveScoreTests {
    @Test func baseRisesWithDifficulty() {
        #expect(SolveScore.points(difficulty: .gentle, isDaily: false, streak: 0, seconds: 600) == 100)
        #expect(SolveScore.points(difficulty: .steady, isDaily: false, streak: 0, seconds: 600) == 250)
        #expect(SolveScore.points(difficulty: .sharp, isDaily: false, streak: 0, seconds: 600) == 500)
        #expect(SolveScore.points(difficulty: .nocturne, isDaily: false, streak: 0, seconds: 600) == 800)
    }

    /// The table has to stay monotone in `allCases` order, because that is the
    /// order every picker renders: a band inserted out of order would show a
    /// harder-looking card worth fewer points, which is the kind of thing nobody
    /// notices until a player does.
    @Test func everyBandIsWorthMoreThanTheOneBeforeIt() {
        let points = Difficulty.allCases.map {
            SolveScore.points(difficulty: $0, isDaily: false, streak: 0, seconds: 600)
        }
        #expect(points == points.sorted())
        #expect(Set(points).count == points.count, "two bands share a base score")
    }

    @Test func dailyAddsStreakBonus() {
        let noStreak = SolveScore.points(difficulty: .steady, isDaily: true, streak: 1, seconds: 600)
        #expect(noStreak == 250 + 50 + 25)
        let week = SolveScore.points(difficulty: .steady, isDaily: true, streak: 7, seconds: 600)
        #expect(week == 250 + 50 + 175)
    }

    @Test func streakBonusCapsAtThirtyDays() {
        let capped = SolveScore.points(difficulty: .steady, isDaily: true, streak: 90, seconds: 600)
        let atCap = SolveScore.points(difficulty: .steady, isDaily: true, streak: 30, seconds: 600)
        #expect(capped == atCap)
    }

    @Test func speedBonusUnderFiveMinutes() {
        let quick = SolveScore.points(difficulty: .gentle, isDaily: false, streak: 0, seconds: 299)
        let slow = SolveScore.points(difficulty: .gentle, isDaily: false, streak: 0, seconds: 301)
        #expect(quick == 150)
        #expect(slow == 100)
    }

    @Test func zeroSecondsEarnsNoSpeedBonus() {
        // A zero elapsed time means the timer never ran — don't reward it.
        #expect(SolveScore.points(difficulty: .gentle, isDaily: false, streak: 0, seconds: 0) == 100)
    }
}

@Suite("SolveHistory")
struct SolveHistoryTests {
    private func record(daysAgo: Int = 0, difficulty: Difficulty = .steady,
                        isDaily: Bool = false, seconds: TimeInterval = 400) -> SolveRecord {
        SolveRecord(
            date: Date(timeIntervalSince1970: 1_000_000 - TimeInterval(daysAgo) * 86_400),
            difficulty: difficulty,
            isDaily: isDaily,
            seconds: seconds,
            points: SolveScore.points(difficulty: difficulty, isDaily: isDaily, streak: 0, seconds: seconds)
        )
    }

    @Test func recordsNewestFirst() {
        var history = SolveHistory()
        history.record(record(daysAgo: 2))
        history.record(record(daysAgo: 0))
        #expect(history.records.count == 2)
        #expect(history.records[0].date > history.records[1].date)
    }

    @Test func capsAtCapacity() {
        var history = SolveHistory()
        // Oldest first, which is the only order a real player produces: a solve
        // is recorded as it happens. `record(_:)` inserts at the head, so this
        // builds the newest-first array the type documents — and it is the order
        // the cap depends on, since it prunes the tail as the oldest.
        for day in stride(from: SolveHistory.capacity + 25, through: 1, by: -1) {
            history.record(record(daysAgo: day))
        }
        #expect(history.records.count == SolveHistory.capacity)
    }

    @Test func capacityIsOneThousand() {
        #expect(SolveHistory.capacity == 1000)
    }

    @Test func legacyTwoHundredRecordBlobDecodesUnchanged() throws {
        // A blob written under the old 200 cap must decode intact under the new
        // cap (append-only change, no migration — PRD-9 §3).
        var history = SolveHistory()
        for day in stride(from: 200, through: 1, by: -1) { history.record(record(daysAgo: day)) }
        #expect(history.records.count == 200)
        #expect(history.records.map(\.date) == history.records.map(\.date).sorted(by: >),
                "the fixture must be newest-first, like a real log")

        let data = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(SolveHistory.self, from: data)
        #expect(decoded.records.count == 200)
        #expect(decoded == history)
    }

    @Test func totalPointsSumsAllRecords() {
        var history = SolveHistory()
        history.record(record(difficulty: .gentle, seconds: 600)) // 100
        history.record(record(difficulty: .sharp, seconds: 600))  // 500
        #expect(history.totalPoints == 600)
    }

    @Test func bestTimePerDifficulty() {
        var history = SolveHistory()
        history.record(record(difficulty: .gentle, seconds: 500))
        history.record(record(difficulty: .gentle, seconds: 320))
        history.record(record(difficulty: .sharp, seconds: 900))
        #expect(history.bestSeconds(for: .gentle) == 320)
        #expect(history.bestSeconds(for: .sharp) == 900)
        #expect(history.bestSeconds(for: .steady) == nil)
    }

    // The `record(daysAgo:)` helper anchors dates at 1970 + 1_000_000s minus
    // whole days, so a fixed gregorian calendar gives deterministic ordinals.
    private func dayOrdinal(daysAgo: Int, calendar cal: Calendar) -> Int {
        DailySeed.dayOrdinal(
            for: Date(timeIntervalSince1970: 1_000_000 - TimeInterval(daysAgo) * 86_400),
            calendar: cal)
    }

    @Test func solvesByDayBucketsAndFlagsDaily() {
        var history = SolveHistory()
        history.record(record(daysAgo: 0, isDaily: false))
        history.record(record(daysAgo: 0, isDaily: true))
        history.record(record(daysAgo: 3, isDaily: false))

        let cal = Calendar(identifier: .gregorian)
        let today = dayOrdinal(daysAgo: 0, calendar: cal)
        let buckets = history.solvesByDay(ordinalRange: (today - 6)...today, calendar: cal)

        #expect(buckets[today]?.count == 2)
        #expect(buckets[today]?.hasDaily == true)
        #expect(buckets[today - 3]?.count == 1)
        #expect(buckets[today - 3]?.hasDaily == false)
        #expect(buckets[today - 5] == nil)          // no solve → absent
    }

    @Test func solvesByDayExcludesOutsideRange() {
        var history = SolveHistory()
        history.record(record(daysAgo: 0))
        history.record(record(daysAgo: 40))
        let cal = Calendar(identifier: .gregorian)
        let today = dayOrdinal(daysAgo: 0, calendar: cal)
        let buckets = history.solvesByDay(ordinalRange: (today - 6)...today, calendar: cal)
        #expect(buckets.count == 1)                 // the 40-day-old solve is dropped
        #expect(buckets[today]?.count == 1)
    }

    @Test func trendIsEmptyBelowTwoSolves() {
        var history = SolveHistory()
        #expect(history.trend(window: 20).isEmpty)
        history.record(record(seconds: 400))
        #expect(history.trend(window: 20).isEmpty)   // one solve is not a trend
    }

    @Test func trendConstantTimesIsFlat() {
        var history = SolveHistory()
        for _ in 0..<10 { history.record(record(seconds: 300)) }
        let series = history.trend(window: 20)
        #expect(series.count == 10)
        #expect(series.allSatisfy { abs($0 - 300) < 0.0001 })
    }

    @Test func trendImprovesWhenSolvesGetFaster() {
        var history = SolveHistory()
        // record() inserts at the front, so recording oldest-first leaves the
        // newest (fastest) solve at records[0], matching the live app.
        for i in 0..<12 {
            history.record(record(daysAgo: 12 - i, seconds: TimeInterval(600 - i * 30)))
        }
        let series = history.trend(window: 12)
        #expect(series.count == 12)
        #expect(series.last! < series.first!)        // newest rolling mean is faster
    }

    @Test func trendRespectsWindow() {
        var history = SolveHistory()
        for i in 0..<30 { history.record(record(daysAgo: 30 - i, seconds: 400)) }
        #expect(history.trend(window: 20).count == 20)
    }

    @Test func averageSecondsPerDifficulty() {
        var history = SolveHistory()
        history.record(record(difficulty: .gentle, seconds: 300))
        history.record(record(difficulty: .gentle, seconds: 500))
        history.record(record(difficulty: .sharp, seconds: 900))
        #expect(history.averageSeconds(for: .gentle) == 400)
        #expect(history.averageSeconds(for: .sharp) == 900)
        #expect(history.averageSeconds(for: .steady) == nil)
    }

    @Test func solveCountsByDifficulty() {
        var history = SolveHistory()
        history.record(record(difficulty: .gentle))
        history.record(record(difficulty: .gentle))
        history.record(record(difficulty: .sharp, isDaily: false))
        #expect(history.count(of: .gentle) == 2)
        #expect(history.count(of: .sharp) == 1)
        #expect(history.records.count == 3)
    }
}

/// `SolveRecord.errors` (Task 2 — PRD-26's debrief count) is a plain optional,
/// deliberately not built like the band above it: there is no unrecognised
/// *value* for a downgraded build to preserve, so it needs none of that
/// machinery — just `decodeIfPresent` / conditional-encode, same as any other
/// optional this record persists.
@Suite("SolveRecord.errors coding")
struct SolveRecordErrorsCodingTests {
    private func t(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_000_000 + seconds)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test func errorsRoundTripsThroughEncodeAndDecode() throws {
        let record = SolveRecord(date: t(0), difficulty: .steady, isDaily: false,
                                  seconds: 400, points: 250, errors: 3)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SolveRecord.self, from: data)
        #expect(decoded == record)
        #expect(decoded.errors == 3)
    }

    /// A record from before this field existed — the shape every solve in a
    /// player's history was, until now — must decode with `errors == nil`
    /// rather than throwing over the missing key.
    @Test func aRecordWhoseJSONLacksTheKeyDecodesWithNilErrors() throws {
        let record = SolveRecord(date: t(0), difficulty: .gentle, isDaily: false,
                                  seconds: 300, points: 100)
        let blob = try object(JSONEncoder().encode(record))
        #expect(blob["errors"] == nil, "the fixture must not already carry the key")

        let data = try JSONSerialization.data(withJSONObject: blob)
        let decoded = try JSONDecoder().decode(SolveRecord.self, from: data)
        #expect(decoded.errors == nil)
    }

    /// The write side of the same contract: a nil `errors` must not spend a
    /// byte on the wire at all. A round-trip assertion alone would still pass
    /// even if this always wrote `"errors":null` — a nil that decodes back to
    /// nil — so this checks the JSON itself for the key's absence.
    @Test func encodingANilErrorsEmitsNoKeyAtAll() throws {
        let record = SolveRecord(date: t(0), difficulty: .sharp, isDaily: false,
                                  seconds: 500, points: 500)
        let blob = try object(JSONEncoder().encode(record))
        #expect(blob["errors"] == nil)
    }
}
