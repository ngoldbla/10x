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
        for day in 0..<(SolveHistory.capacity + 25) {
            history.record(record(daysAgo: day))
        }
        #expect(history.records.count == SolveHistory.capacity)
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
