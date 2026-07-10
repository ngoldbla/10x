// Episode engine: deterministic nightly draws, the difficulty curve,
// scoring with speed-bonus dots, and the run state machine.
// Pure Swift: Foundation + CouchCore only.
import Foundation
import CouchCore

// MARK: - Calendar

/// Maps wall-clock dates to episode day numbers. Day 0 = January 1, 2026;
/// tonight's episode number is `day + 1`, so launch night is Episode #1.
public enum EpisodeCalendar {
    static let epochYear = 2026

    private static func epochStart(in calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = epochYear
        components.month = 1
        components.day = 1
        let epoch = calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
        return calendar.startOfDay(for: epoch)
    }

    /// Days since the epoch, in the given calendar's local midnight terms.
    public static func dayNumber(for date: Date, calendar: Calendar = .current) -> Int {
        let start = epochStart(in: calendar)
        let day = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: day).day ?? 0
    }

    /// Midnight local time of the given day number.
    public static func date(forDay day: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: day, to: epochStart(in: calendar))
            ?? epochStart(in: calendar)
    }

    public static func episodeNumber(forDay day: Int) -> Int {
        max(1, day + 1)
    }

    /// Deterministic nightly seed — everyone gets the same episode.
    public static func seed(forDay day: Int) -> UInt64 {
        var rng = SplitMix64(seed: 0xB10C_4EAD_0000_0000 ^ UInt64(bitPattern: Int64(day)))
        _ = rng.next()
        return rng.next()
    }
}

// MARK: - Episode shape

public enum SlotKind: String, Sendable, Equatable, Hashable {
    case trivia, picture, oddOneOut
}

public struct EpisodeSlot: Sendable, Equatable, Hashable {
    public let kind: SlotKind
    public let difficulty: Int

    public init(kind: SlotKind, difficulty: Int) {
        self.kind = kind
        self.difficulty = difficulty
    }
}

/// One night's show: ten questions in the fixed warm → hard → cool shape.
public struct Episode: Sendable, Equatable {
    public let number: Int
    public let dayNumber: Int
    public let seed: UInt64
    public let questions: [Question]

    public init(number: Int, dayNumber: Int, seed: UInt64, questions: [Question]) {
        self.number = number
        self.dayNumber = dayNumber
        self.seed = seed
        self.questions = questions
    }
}

public enum EpisodePlanner {
    /// The fixed show grammar: 6 trivia, 2 picture, 2 odd-one-out, with a
    /// warm → hard → cool-down difficulty curve (PRD §4.2, §5).
    public static let slotPlan: [EpisodeSlot] = [
        EpisodeSlot(kind: .trivia, difficulty: 1),
        EpisodeSlot(kind: .trivia, difficulty: 1),
        EpisodeSlot(kind: .picture, difficulty: 2),
        EpisodeSlot(kind: .trivia, difficulty: 2),
        EpisodeSlot(kind: .oddOneOut, difficulty: 2),
        EpisodeSlot(kind: .trivia, difficulty: 3),
        EpisodeSlot(kind: .trivia, difficulty: 3),
        EpisodeSlot(kind: .oddOneOut, difficulty: 3),
        EpisodeSlot(kind: .picture, difficulty: 2),
        EpisodeSlot(kind: .trivia, difficulty: 1),
    ]

    public static func kind(of question: Question) -> SlotKind {
        if question.isPicture { return .picture }
        if question.category == .oddOneOut { return .oddOneOut }
        return .trivia
    }

    /// Tonight's (or any archive day's) episode — a pure function of the day.
    public static func episode(forDay day: Int, from pack: [Question] = QuestionPack.all) -> Episode {
        episode(
            seed: EpisodeCalendar.seed(forDay: day),
            number: EpisodeCalendar.episodeNumber(forDay: day),
            dayNumber: day,
            from: pack
        )
    }

    /// Deterministic draw: same seed + pack ⇒ identical episode.
    public static func episode(
        seed: UInt64,
        number: Int,
        dayNumber: Int,
        from pack: [Question]
    ) -> Episode {
        var rng = SplitMix64(seed: seed)
        var used = Set<String>()
        var drawn: [Question] = []
        for slot in slotPlan {
            let pool = candidates(kind: slot.kind, difficulty: slot.difficulty, pack: pack, used: used)
            guard !pool.isEmpty else { continue }
            let pick = pool[rng.nextInt(below: pool.count)]
            used.insert(pick.id)
            drawn.append(pick)
        }
        return Episode(number: number, dayNumber: dayNumber, seed: seed, questions: drawn)
    }

    /// Party draw: `rounds × players` questions; round difficulty ramps
    /// 1 → 2 → 3 so every couch warms up together.
    public static func partyQuestions(
        players: Int,
        rounds: Int,
        seed: UInt64,
        from pack: [Question] = QuestionPack.all
    ) -> [Question] {
        var rng = SplitMix64(seed: seed)
        var used = Set<String>()
        var drawn: [Question] = []
        for round in 0..<max(1, rounds) {
            let difficulty = min(round + 1, 3)
            for _ in 0..<max(1, players) {
                var pool: [Question] = []
                for tolerance in 0...2 {
                    pool = pack.filter {
                        !used.contains($0.id) && abs($0.difficulty - difficulty) <= tolerance
                    }
                    if !pool.isEmpty { break }
                }
                guard !pool.isEmpty else { return drawn }
                let pick = pool[rng.nextInt(below: pool.count)]
                used.insert(pick.id)
                drawn.append(pick)
            }
        }
        return drawn
    }

    /// Widening candidate search: exact difficulty first, then ±1, ±2, then
    /// any unused question at all. Pack order keeps this deterministic.
    static func candidates(
        kind: SlotKind,
        difficulty: Int,
        pack: [Question],
        used: Set<String>
    ) -> [Question] {
        let unusedOfKind = pack.filter { !used.contains($0.id) && Self.kind(of: $0) == kind }
        for tolerance in 0...2 {
            let pool = unusedOfKind.filter { abs($0.difficulty - difficulty) <= tolerance }
            if !pool.isEmpty { return pool }
        }
        return pack.filter { !used.contains($0.id) }
    }
}

// MARK: - Scoring

/// Score = correct count + speed-bonus dots. Dots come from an injectable
/// clock: callers pass elapsed time in; the engine never reads Date() itself.
public enum Scoring {
    public static let maxDots = 2

    /// 2 dots inside the first quarter of the timer, 1 dot inside the first
    /// 60%, otherwise 0. Out-of-range input earns nothing.
    public static func speedDots(elapsed: TimeInterval, limit: TimeInterval) -> Int {
        guard limit > 0, elapsed >= 0, elapsed <= limit else { return 0 }
        if elapsed <= limit * 0.25 { return 2 }
        if elapsed <= limit * 0.60 { return 1 }
        return 0
    }
}

/// What happened on one question.
public struct QuestionOutcome: Sendable, Equatable, Codable {
    public let questionID: String
    /// Answer index the player picked; nil means the timer ran out.
    public let pickedIndex: Int?
    public let correct: Bool
    public let dots: Int
    public let elapsed: TimeInterval

    public init(questionID: String, pickedIndex: Int?, correct: Bool, dots: Int, elapsed: TimeInterval) {
        self.questionID = questionID
        self.pickedIndex = pickedIndex
        self.correct = correct
        self.dots = dots
        self.elapsed = elapsed
    }
}

/// A finished episode, as stored in the archive. `isLate` marks catch-up
/// plays (streak-honest: they never extend the streak).
public struct EpisodeResult: Sendable, Equatable, Codable {
    public let episodeNumber: Int
    public let dayNumber: Int
    public let playedDay: Int
    public let correctCount: Int
    public let dots: Int

    public init(episodeNumber: Int, dayNumber: Int, playedDay: Int, correctCount: Int, dots: Int) {
        self.episodeNumber = episodeNumber
        self.dayNumber = dayNumber
        self.playedDay = playedDay
        self.correctCount = correctCount
        self.dots = dots
    }

    public var score: Int { correctCount + dots }
    public var isLate: Bool { playedDay > dayNumber }
}

// MARK: - Run state machine

/// Drives one play-through of an episode. All timing is injected (`at now:`)
/// so the whole machine is a pure, testable value type.
public struct EpisodeRun: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle
        case question(Int)
        case verdict(Int)
        case finished
    }

    public let episode: Episode
    public let timeLimit: TimeInterval
    public private(set) var phase: Phase = .idle
    public private(set) var outcomes: [QuestionOutcome] = []
    private var questionStart: TimeInterval = 0

    public init(episode: Episode, timeLimit: TimeInterval = 12) {
        self.episode = episode
        self.timeLimit = max(1, timeLimit)
    }

    public var currentIndex: Int? {
        switch phase {
        case .question(let index), .verdict(let index): index
        case .idle, .finished: nil
        }
    }

    public var currentQuestion: Question? {
        currentIndex.map { episode.questions[$0] }
    }

    public var correctCount: Int { outcomes.filter(\.correct).count }
    public var dots: Int { outcomes.reduce(0) { $0 + $1.dots } }
    public var score: Int { correctCount + dots }

    public mutating func begin(at now: TimeInterval) {
        guard case .idle = phase, !episode.questions.isEmpty else { return }
        phase = .question(0)
        questionStart = now
    }

    /// The flick. Returns nil when no question is live.
    @discardableResult
    public mutating func answer(_ direction: Direction4, at now: TimeInterval) -> QuestionOutcome? {
        guard case .question(let index) = phase else { return nil }
        let question = episode.questions[index]
        let picked = Question.answerIndex(for: direction)
        let elapsed = max(0, now - questionStart)
        let correct = picked == question.correctIndex
        let outcome = QuestionOutcome(
            questionID: question.id,
            pickedIndex: picked,
            correct: correct,
            dots: correct ? Scoring.speedDots(elapsed: elapsed, limit: timeLimit) : 0,
            elapsed: elapsed
        )
        outcomes.append(outcome)
        phase = .verdict(index)
        return outcome
    }

    /// Timer expiry — counts as wrong, zero dots.
    @discardableResult
    public mutating func timeOut(at now: TimeInterval) -> QuestionOutcome? {
        guard case .question(let index) = phase else { return nil }
        let question = episode.questions[index]
        let outcome = QuestionOutcome(
            questionID: question.id,
            pickedIndex: nil,
            correct: false,
            dots: 0,
            elapsed: max(0, now - questionStart)
        )
        outcomes.append(outcome)
        phase = .verdict(index)
        return outcome
    }

    /// Verdict → next question (or finished).
    public mutating func advance(at now: TimeInterval) {
        guard case .verdict(let index) = phase else { return }
        if index + 1 < episode.questions.count {
            phase = .question(index + 1)
            questionStart = now
        } else {
            phase = .finished
        }
    }

    /// Pause support: push the live question's clock forward by the paused
    /// duration so paused time never counts against the speed bonus.
    public mutating func shiftClock(by delta: TimeInterval) {
        questionStart += delta
    }

    public func remaining(at now: TimeInterval) -> TimeInterval {
        guard case .question = phase else { return 0 }
        return max(0, timeLimit - (now - questionStart))
    }

    /// Available once finished.
    public func result(playedDay: Int) -> EpisodeResult? {
        guard case .finished = phase else { return nil }
        return EpisodeResult(
            episodeNumber: episode.number,
            dayNumber: episode.dayNumber,
            playedDay: playedDay,
            correctCount: correctCount,
            dots: dots
        )
    }
}
