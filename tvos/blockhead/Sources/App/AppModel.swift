// The one view model. All remote gestures funnel here (each screen's
// `.couchRemote` closure calls a handler), all timing flows through Date()
// at this boundary and into the pure engine as injected instants.
import SwiftUI
import Observation
import CoreGraphics
import CouchKit

@MainActor @Observable
final class AppModel {

    // MARK: Types

    enum Route: Equatable {
        case stage, archive, question, summary
        case partySetup, handoff, partyQuestion, podium
    }

    /// Hall lighting. The room reacts to verdicts — never a badge.
    enum Mood: Equatable { case neutral, gold, cool }

    /// Phase of the question moment.
    enum Moment: Equatable { case countdown, locked, verdict }

    enum TonightState: Equatable { case sealed, inProgress, done(score: Int) }

    struct TokenSlot: Identifiable, Equatable {
        let id: Int
        var claimed = false
        var symbolIndex: Int
    }

    // MARK: Persistence (CouchStored; mirrored into observable state)

    private let timerStore = CouchStored(wrappedValue: 12, "prefs.timerSeconds")
    private let flashStore = CouchStored(wrappedValue: false, "prefs.reduceFlash")
    private let streakStore = CouchStored(
        wrappedValue: StreakState(), "progress.streak", cloudSynced: true)
    private let resultsStore = CouchStored(
        wrappedValue: [String: EpisodeResult](), "progress.results", cloudSynced: true)

    // MARK: Observable state

    private(set) var route: Route = .stage
    private(set) var mood: Mood = .neutral
    private(set) var moment: Moment = .countdown
    var showPrefs = false
    private(set) var isPaused = false

    private(set) var timerSeconds: Int
    private(set) var reduceFlash: Bool
    private(set) var streak: StreakState
    private(set) var results: [String: EpisodeResult]

    /// Stage focus: 0 = tonight (marquee), 1 = party, 2 = archive.
    private(set) var stageSelection = 0
    private(set) var archiveSelection = 0

    private(set) var run: EpisodeRun?
    private(set) var lastOutcome: QuestionOutcome?
    private(set) var lastResult: EpisodeResult?
    private(set) var questionStartDate: Date?
    private(set) var frozenRing: Double?
    private(set) var revealPicture = false
    private(set) var pictureMosaic: CGImage?
    private(set) var pictureSharp: CGImage?

    private(set) var tokens: [TokenSlot]
    /// Setup focus: 0…5 = tokens, 6 = the start slab.
    private(set) var setupSelection = 0
    private(set) var match: PartyMatch?

    // MARK: Internals

    private var timerTask: Task<Void, Never>?
    private var flowTask: Task<Void, Never>?
    private var pictureTask: Task<Void, Never>?
    private var generation = 0
    private var pauseBegan: Date?
    private var suspendedAt: Date?

    init() {
        timerSeconds = timerStore.wrappedValue
        reduceFlash = flashStore.wrappedValue
        streak = streakStore.wrappedValue
        results = resultsStore.wrappedValue
        tokens = (0..<6).map { TokenSlot(id: $0, symbolIndex: $0) }
    }

    // MARK: Derived

    var todayDay: Int { EpisodeCalendar.dayNumber(for: Date()) }
    var tonightNumber: Int { EpisodeCalendar.episodeNumber(forDay: todayDay) }
    var streakDisplay: Int { streak.current(asOf: todayDay) }

    var tonightState: TonightState {
        if let result = results[String(todayDay)] { return .done(score: result.score) }
        if let run, run.episode.dayNumber == todayDay, run.phase != .finished {
            return .inProgress
        }
        return .sealed
    }

    var archiveEntries: [ArchiveEntry] {
        let keyed = Dictionary(uniqueKeysWithValues: results.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
        return Archive.entries(today: todayDay, limit: 10, results: keyed)
    }

    var activeQuestion: Question? {
        switch route {
        case .question: run?.currentQuestion
        case .partyQuestion: match?.currentQuestion
        default: nil
        }
    }

    /// Timer length for the live question (solo runs lock theirs at start).
    var currentLimit: TimeInterval {
        route == .partyQuestion ? TimeInterval(timerSeconds) : (run?.timeLimit ?? TimeInterval(timerSeconds))
    }

    var soloProgressLabel: String? {
        guard route == .question, let run, let index = run.currentIndex else { return nil }
        return "Q \(index + 1) / \(run.episode.questions.count)"
    }

    /// Countdown ring, 1 → 0. Frozen at lock-in; held during pause.
    func ringProgress(at date: Date) -> Double {
        if let frozenRing { return frozenRing }
        guard let start = questionStartDate, currentLimit > 0 else { return 1 }
        let reference = pauseBegan ?? date
        let elapsed = max(0, reference.timeIntervalSince(start))
        return max(0, 1 - elapsed / currentLimit)
    }

    // MARK: Prefs

    func setTimerSeconds(_ seconds: Int) {
        timerSeconds = seconds
        timerStore.wrappedValue = seconds
    }

    func toggleReduceFlash() {
        reduceFlash.toggle()
        flashStore.wrappedValue = reduceFlash
    }

    // MARK: Stage

    func handleStage(_ gesture: CouchGesture) {
        guard !showPrefs else { return }
        switch gesture {
        case .swipe(let direction): moveStageSelection(direction)
        case .click: activateStageSelection()
        case .playPauseLongPress, .holdBegan: showPrefs = true
        default: break
        }
    }

    private func moveStageSelection(_ direction: Direction4) {
        // Layout: [Party] [Tonight] [Archive]
        switch (stageSelection, direction) {
        case (0, .left): stageSelection = 1
        case (0, .right): stageSelection = 2
        case (1, .right): stageSelection = 0
        case (2, .left): stageSelection = 0
        default: break
        }
    }

    private func activateStageSelection() {
        switch stageSelection {
        case 1: openPartySetup()
        case 2: openArchive()
        default: startTonight()
        }
    }

    // MARK: Solo episode

    func startTonight() {
        let today = todayDay
        if var existing = run,
           existing.episode.dayNumber == today,
           existing.phase != .finished,
           existing.currentQuestion != nil {
            // Resume: suspended time never counts against the speed bonus.
            if let suspended = suspendedAt {
                existing.shiftClock(by: Date().timeIntervalSince(suspended))
                suspendedAt = nil
            }
            run = existing
            let remaining = max(0.5, existing.remaining(at: Date().timeIntervalSinceReferenceDate))
            resetQuestionPresentation()
            questionStartDate = Date().addingTimeInterval(remaining - existing.timeLimit)
            route = .question
            if let question = existing.currentQuestion { loadPicture(for: question) }
            scheduleTimeout(after: remaining)
            return
        }
        beginEpisode(day: today)
    }

    func playArchive(_ entry: ArchiveEntry) {
        beginEpisode(day: entry.dayNumber)
    }

    private func beginEpisode(day: Int) {
        cancelTasks()
        suspendedAt = nil
        var newRun = EpisodeRun(
            episode: EpisodePlanner.episode(forDay: day),
            timeLimit: TimeInterval(timerSeconds)
        )
        newRun.begin(at: Date().timeIntervalSinceReferenceDate)
        run = newRun
        route = .question
        prepareQuestion()
    }

    // MARK: Question flow (shared solo/party)

    func handleQuestion(_ gesture: CouchGesture) {
        switch gesture {
        case .swipe(let direction): answer(direction)
        case .playPause: togglePause()
        case .back: exitToStage()
        default: break
        }
    }

    func answer(_ direction: Direction4) {
        guard moment == .countdown, !isPaused else { return }
        switch route {
        case .question:
            let instant = Date().timeIntervalSinceReferenceDate
            guard let outcome = run?.answer(direction, at: instant) else { return }
            afterAnswer(outcome)
        case .partyQuestion:
            guard let question = match?.currentQuestion else { return }
            let elapsed = max(0, Date().timeIntervalSince(questionStartDate ?? Date()))
            let picked = Question.answerIndex(for: direction)
            let correct = picked == question.correctIndex
            let outcome = QuestionOutcome(
                questionID: question.id,
                pickedIndex: picked,
                correct: correct,
                dots: correct ? Scoring.speedDots(elapsed: elapsed, limit: currentLimit) : 0,
                elapsed: elapsed
            )
            afterAnswer(outcome)
        default:
            break
        }
    }

    private func handleTimeout() {
        guard moment == .countdown, !isPaused else { return }
        switch route {
        case .question:
            let instant = Date().timeIntervalSinceReferenceDate
            guard let outcome = run?.timeOut(at: instant) else { return }
            afterAnswer(outcome)
        case .partyQuestion:
            guard let question = match?.currentQuestion else { return }
            let outcome = QuestionOutcome(
                questionID: question.id, pickedIndex: nil,
                correct: false, dots: 0, elapsed: currentLimit
            )
            afterAnswer(outcome)
        default:
            break
        }
    }

    /// The verdict choreography: ~600ms theatrical hold (light sweep pauses),
    /// then the hall warms gold or cools and dims, then the show moves on.
    private func afterAnswer(_ outcome: QuestionOutcome) {
        timerTask?.cancel()
        generation += 1
        let gen = generation
        frozenRing = ringProgress(at: Date())
        lastOutcome = outcome
        moment = .locked
        let isParty = route == .partyQuestion
        let verdictHold: UInt64 = reduceFlash ? 1_100_000_000 : 1_500_000_000
        flowTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, self.generation == gen else { return }
            self.moment = .verdict
            self.mood = outcome.correct ? .gold : .cool
            self.revealPicture = true
            try? await Task.sleep(nanoseconds: verdictHold)
            guard self.generation == gen else { return }
            self.mood = .neutral
            if isParty {
                self.advanceParty(outcome)
            } else {
                self.advanceSolo()
            }
        }
    }

    private func advanceSolo() {
        guard var current = run else { return }
        current.advance(at: Date().timeIntervalSinceReferenceDate)
        run = current
        if case .finished = current.phase {
            recordIfNeeded(current)
            moment = .countdown
            revealPicture = false
            route = .summary
        } else {
            prepareQuestion()
        }
    }

    private func prepareQuestion() {
        resetQuestionPresentation()
        questionStartDate = Date()
        let question = route == .partyQuestion ? match?.currentQuestion : run?.currentQuestion
        if let question {
            loadPicture(for: question)
        } else {
            pictureMosaic = nil
            pictureSharp = nil
        }
        scheduleTimeout(after: currentLimit)
    }

    private func resetQuestionPresentation() {
        moment = .countdown
        mood = .neutral
        revealPicture = false
        frozenRing = nil
        lastOutcome = nil
    }

    private func scheduleTimeout(after interval: TimeInterval) {
        timerTask?.cancel()
        generation += 1
        let gen = generation
        timerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
            guard let self, !Task.isCancelled, self.generation == gen else { return }
            self.handleTimeout()
        }
    }

    private func recordIfNeeded(_ finished: EpisodeRun) {
        guard let result = finished.result(playedDay: todayDay) else { return }
        lastResult = result
        results[String(finished.episode.dayNumber)] = result
        resultsStore.wrappedValue = results
        streak.recordCompletion(day: finished.episode.dayNumber, playedDay: todayDay)
        streakStore.wrappedValue = streak
    }

    // MARK: Pause (glass curtain)

    func togglePause() {
        guard route == .question || route == .partyQuestion, moment == .countdown else { return }
        if isPaused {
            resumeFromPause()
        } else {
            isPaused = true
            pauseBegan = Date()
            timerTask?.cancel()
            generation += 1
        }
    }

    private func resumeFromPause() {
        defer {
            isPaused = false
            pauseBegan = nil
        }
        guard let began = pauseBegan else { return }
        let delta = Date().timeIntervalSince(began)
        run?.shiftClock(by: delta)
        questionStartDate = questionStartDate?.addingTimeInterval(delta)
        let remaining = questionStartDate.map {
            currentLimit - Date().timeIntervalSince($0)
        } ?? currentLimit
        scheduleTimeout(after: max(0.05, remaining))
    }

    // MARK: Party

    func openPartySetup() {
        cancelTasks()
        match = nil
        setupSelection = 0
        route = .partySetup
    }

    var claimedCount: Int { tokens.filter(\.claimed).count }
    var canStartParty: Bool { PartyMatch.playerRange.contains(claimedCount) }

    func handlePartySetup(_ gesture: CouchGesture) {
        switch gesture {
        case .swipe(let direction):
            moveSetupSelection(direction)
        case .click:
            if setupSelection == 6 { startParty() } else { toggleClaim(setupSelection) }
        case .holdBegan:
            if setupSelection < 6 { cycleAvatar(setupSelection) }
        case .back:
            exitToStage()
        default:
            break
        }
    }

    private func moveSetupSelection(_ direction: Direction4) {
        switch direction {
        case .left:
            if setupSelection == 6 { setupSelection = 2 } else if setupSelection > 0 { setupSelection -= 1 }
        case .right:
            if setupSelection == 6 { setupSelection = 3 } else if setupSelection < 5 { setupSelection += 1 }
        case .down:
            if setupSelection < 6 { setupSelection = 6 }
        case .up:
            if setupSelection == 6 { setupSelection = 2 }
        }
    }

    private func toggleClaim(_ index: Int) {
        guard tokens.indices.contains(index) else { return }
        tokens[index].claimed.toggle()
        if tokens[index].claimed { ensureUniqueSymbol(index) }
    }

    private func cycleAvatar(_ index: Int) {
        guard tokens.indices.contains(index), tokens[index].claimed else { return }
        tokens[index].symbolIndex = (tokens[index].symbolIndex + 1) % AvatarKit.symbols.count
        ensureUniqueSymbol(index)
    }

    private func ensureUniqueSymbol(_ index: Int) {
        let taken = Set(tokens.enumerated().compactMap { offset, token in
            offset != index && token.claimed ? token.symbolIndex : nil
        })
        var tries = 0
        while taken.contains(tokens[index].symbolIndex), tries < AvatarKit.symbols.count {
            tokens[index].symbolIndex = (tokens[index].symbolIndex + 1) % AvatarKit.symbols.count
            tries += 1
        }
    }

    func startParty() {
        guard canStartParty else { return }
        let players = tokens.filter(\.claimed).map {
            PartyPlayer(id: $0.id, symbolIndex: $0.symbolIndex, colorIndex: $0.id)
        }
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(Date().timeIntervalSince1970 * 1000)))
        guard let newMatch = PartyMatch(players: players, seed: rng.next()) else { return }
        match = newMatch
        route = .handoff
    }

    func handleHandoff(_ gesture: CouchGesture) {
        switch gesture {
        case .click: beginPartyTurn()
        case .back: exitToStage()
        default: break
        }
    }

    func beginPartyTurn() {
        guard match?.currentQuestion != nil else { return }
        route = .partyQuestion
        prepareQuestion()
    }

    private func advanceParty(_ outcome: QuestionOutcome) {
        guard var current = match else { return }
        current.record(correct: outcome.correct, dots: outcome.dots)
        match = current
        resetQuestionPresentation()
        if current.isFinished {
            route = .podium
            mood = .gold // one winner light sweep
            let gen = generation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                guard let self, self.generation == gen else { return }
                self.mood = .neutral
            }
        } else {
            route = .handoff
        }
    }

    func handlePodium(_ gesture: CouchGesture) {
        switch gesture {
        case .click: rematchParty()
        case .back: exitToStage()
        default: break
        }
    }

    func rematchParty() {
        guard let finished = match, finished.isFinished else { return }
        match = finished.rematch()
        mood = .neutral
        route = .handoff
    }

    // MARK: Archive

    func openArchive() {
        archiveSelection = 0
        route = .archive
    }

    func handleArchive(_ gesture: CouchGesture) {
        let entries = archiveEntries
        switch gesture {
        case .swipe(.up):
            if archiveSelection > 0 { archiveSelection -= 1 }
        case .swipe(.down):
            if archiveSelection < entries.count - 1 { archiveSelection += 1 }
        case .click:
            if entries.indices.contains(archiveSelection) { playArchive(entries[archiveSelection]) }
        case .back:
            exitToStage()
        default:
            break
        }
    }

    // MARK: Summary

    func handleSummary(_ gesture: CouchGesture) {
        switch gesture {
        case .click, .back: exitToStage()
        default: break
        }
    }

    // MARK: Exit

    /// Back → the stage. Solo progress is saved (resume from the marquee);
    /// a live verdict resolves silently so nothing is lost.
    func exitToStage() {
        cancelTasks()
        isPaused = false
        pauseBegan = nil
        showPrefs = false

        if route == .question, var current = run {
            if case .verdict = current.phase {
                current.advance(at: Date().timeIntervalSinceReferenceDate)
            }
            run = current
            if case .finished = current.phase {
                recordIfNeeded(current)
            } else if case .question = current.phase {
                suspendedAt = Date()
            }
        }

        switch route {
        case .partySetup, .handoff, .partyQuestion, .podium:
            match = nil
        default:
            break
        }

        resetQuestionPresentation()
        stageSelection = 0
        route = .stage
    }

    private func cancelTasks() {
        timerTask?.cancel()
        flowTask?.cancel()
        pictureTask?.cancel()
        generation += 1
    }

    // MARK: Picture rounds (DemoArt via AsciiEngine)

    private func loadPicture(for question: Question) {
        pictureTask?.cancel()
        pictureMosaic = nil
        pictureSharp = nil
        guard
            let recipeID = question.pictureRecipe,
            let recipe = DemoArt.recipe(id: recipeID)
        else { return }
        pictureTask = Task { [weak self] in
            let mosaic = try? await AsciiEngine.shared.renderDemo(
                recipe: recipe, style: .mosaic, grid: .fit(cols: 28))
            let sharp = await Self.renderSharp(recipe)
            guard let self, !Task.isCancelled else { return }
            self.pictureMosaic = mosaic
            self.pictureSharp = sharp
        }
    }

    private nonisolated static func renderSharp(_ recipe: DemoArtRecipe) async -> CGImage? {
        let buffer = DemoArt.render(recipe, width: 1280, height: 720)
        return AsciiEngine.cgImage(from: buffer)
    }
}
