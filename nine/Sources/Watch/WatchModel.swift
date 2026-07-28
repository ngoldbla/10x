// WatchModel.swift — the wrist's whole state (PRD-6).
//
// Deliberately not `AppModel`. That class is 1200 lines of phone/TV/Mac, and
// one of them is `LibraryCloudStore`, which builds a `CKContainer(identifier:)`
// — a call that traps outright on a binary holding the iCloud account but not
// the CloudKit entitlement. That is the live defect keeping a locally-built
// Nine from launching on macOS at all, and the watch carries KVS and no
// CloudKit container, so importing the model would have shipped it to the
// wrist. What the watch actually needs is: the streak (shared), the appearance
// (mirrored), one board, and where the eye left it.
//
// Every persisted value is its own top-level `CouchStored` key, never a field
// on someone else's blob (EXECUTING-A-PRD §2), and every one of them decodes
// tolerantly, because `CouchStored` discards a whole blob when a decode throws.
#if os(watchOS)
import Foundation
import Observation
import SwiftUI
import CouchKit

// MARK: - Persisted

/// Where the wrist was. PRD-6 §2.4: "the board must reopen exactly where the
/// eye left it (last box, last selection)" — a watch session is twenty seconds
/// long, so landing on the home screen is landing nowhere.
struct WatchSaveSlot: Codable, Sendable, Equatable {
    var game: NineGame?
    /// The daily this board is, or nil for a free-play board.
    var dayOrdinal: Int?
    /// The box the lens was over (0…8), or nil for the overview map.
    var box: Int?
    /// The selected cell (0…80), or nil.
    var cell: Int?

    init() {}

    enum CodingKeys: String, CodingKey { case game, dayOrdinal, box, cell }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        game = try? c.decodeIfPresent(NineGame.self, forKey: .game) ?? nil
        dayOrdinal = try c.decodeIfPresent(Int.self, forKey: .dayOrdinal)
        box = try c.decodeIfPresent(Int.self, forKey: .box)
        cell = try c.decodeIfPresent(Int.self, forKey: .cell)
    }
}

/// The reader-side high-water mark, persisted rather than held in memory.
///
/// The in-memory version of this exact counter shipped once in the widget
/// bridge and reset to 0 every process, so every cold launch re-adopted the
/// same payload over whatever was already there. Same counter, same file,
/// same mistake available — so it is on disk from the first line.
struct WatchLinkLedger: Codable, Sendable, Equatable {
    /// Highest `WatchDailyHandoff.revision` already taken.
    var adoptedRevision = 0
    /// A solve the phone has not acknowledged. Held so a report survives the
    /// watch being out of range, killed, and relaunched.
    var unreportedSolve: WatchSolveReport?

    init() {}

    enum CodingKeys: String, CodingKey { case adoptedRevision, unreportedSolve }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        adoptedRevision = try c.decodeIfPresent(Int.self, forKey: .adoptedRevision) ?? 0
        unreportedSolve = try? c.decodeIfPresent(WatchSolveReport.self, forKey: .unreportedSolve) ?? nil
    }
}

// MARK: - The model

/// Which surface the watch is showing.
enum WatchScreen: Equatable {
    case home
    /// The 9×9 map.
    case board
    /// The lens, over one box.
    case box(Int)
}

@MainActor
@Observable
final class WatchModel {

    // Persisted stores.
    @ObservationIgnored private let streakStore =
        CouchStored(wrappedValue: StreakState(), "nine.streak", cloudSynced: true)
    /// Published by the phone, read here. Never written from the wrist — a
    /// watch that wrote it would fight the phone under last-writer-wins.
    @ObservationIgnored private let appearanceStore =
        CouchStored(wrappedValue: SharedAppearance(), SharedAppearance.storeKey, cloudSynced: true)
    @ObservationIgnored private let slotStore =
        CouchStored(wrappedValue: WatchSaveSlot(), "nine.watch.board")
    @ObservationIgnored private let ledgerStore =
        CouchStored(wrappedValue: WatchLinkLedger(), "nine.watch.link")

    private(set) var streak: StreakState {
        didSet { streakStore.wrappedValue = streak }
    }
    private(set) var ledger: WatchLinkLedger {
        didSet { ledgerStore.wrappedValue = ledger }
    }
    private var slot: WatchSaveSlot {
        didSet { slotStore.wrappedValue = slot }
    }

    /// Today's daily, once it has arrived. Nil means the phone has not been in
    /// range since midnight — an honest empty state, never a spinner.
    private(set) var handoff: WatchDailyHandoff?

    var screen: WatchScreen = .home
    private(set) var game: NineGame?
    private(set) var isDaily = false
    private(set) var solvedAt: Date?
    /// True while composing the one band the watch may build itself.
    private(set) var composing = false

    var selection: Int?
    /// The crown's live preview, cleared by anything that moves the eye.
    var preview: CrownDial = .empty

    var theme: ThemeChoice { ThemeChoice(rawValue: appearanceStore.wrappedValue.theme) ?? .auto }
    var accentChoice: AccentChoice {
        AccentChoice(rawValue: appearanceStore.wrappedValue.accent) ?? .glacier
    }

    var todayOrdinal: Int { DailySeed.dayOrdinal(for: Date()) }

    init() {
        streak = streakStore.wrappedValue
        ledger = ledgerStore.wrappedValue
        slot = slotStore.wrappedValue
        restore()
    }

    // MARK: - Resume

    /// Put the wrist back exactly where it was, unless the board on disk is a
    /// daily from a day that has since rolled over.
    private func restore() {
        guard let saved = slot.game else { return }
        if let day = slot.dayOrdinal, day != todayOrdinal {
            // Yesterday's daily. Drop it rather than let the player pour
            // twenty seconds into a board whose streak has already passed.
            slot = WatchSaveSlot()
            return
        }
        game = saved
        isDaily = slot.dayOrdinal != nil
        selection = slot.cell
        solvedAt = saved.isSolved ? Date() : nil
        screen = slot.box.map { WatchScreen.box($0) } ?? .board
    }

    private func persist() {
        slot.game = game
        slot.dayOrdinal = isDaily ? todayOrdinal : nil
        slot.cell = selection
        if case .box(let box) = screen { slot.box = box } else { slot.box = nil }
    }

    // MARK: - Opening a board

    var todayIsSolved: Bool { streak.hasCompleted(day: todayOrdinal) }

    /// True when the daily can be played right now — i.e. the phone has been
    /// in range since midnight. The watch cannot compose it itself
    /// (`WatchComposePolicy`), so this is the honest question the home screen
    /// asks.
    var dailyIsAvailable: Bool { handoff?.isCurrent(today: todayOrdinal) == true }

    func openDaily() {
        guard let handoff, handoff.isCurrent(today: todayOrdinal) else { return }
        if isDaily, game != nil { screen = .board; return }   // already on it
        var fresh = NineGame(puzzle: handoff.puzzle)
        fresh.timer.start(at: Date())
        game = fresh
        isDaily = true
        solvedAt = nil
        selection = nil
        screen = .board
        persist()
    }

    /// The one board the watch is allowed to build for itself.
    ///
    /// Routed through `WatchComposePolicy` rather than calling the generator
    /// with a literal, so the ceiling is enforced by the type system's nearest
    /// equivalent — one function, one call site, one seal test.
    func composeSelfMade() {
        guard !composing else { return }
        composing = true
        let band = WatchComposePolicy.ceiling
        let seed = UInt64.random(in: .min ... .max)
        Task.detached(priority: .userInitiated) { [weak self] in
            let puzzle = PuzzleGenerator.generate(seed: seed, difficulty: band)
            await MainActor.run {
                guard let self else { return }
                var fresh = NineGame(puzzle: puzzle)
                fresh.timer.start(at: Date())
                self.game = fresh
                self.isDaily = false
                self.solvedAt = nil
                self.selection = nil
                self.screen = .board
                self.composing = false
                self.persist()
            }
        }
    }

    func goHome() {
        if var g = game, solvedAt == nil {
            g.timer.pause(at: Date())
            game = g
        }
        screen = .home
        persist()
    }

    // MARK: - Moves

    func place(_ digit: Int, at cell: Int) {
        guard var g = game, solvedAt == nil, g.place(digit, at: cell) else { return }
        game = g
        preview = .empty
        after(move: g)
    }

    func pencil(_ digit: Int, at cell: Int) {
        guard var g = game, solvedAt == nil, g.togglePencil(digit, at: cell) else { return }
        game = g
        preview = .empty
        persist()
    }

    func erase(at cell: Int) {
        guard var g = game, solvedAt == nil, g.erase(at: cell) else { return }
        game = g
        preview = .empty
        persist()
    }

    func undo() {
        guard var g = game, solvedAt == nil, g.undo() != nil else { return }
        game = g
        preview = .empty
        persist()
    }

    private func after(move g: NineGame) {
        if g.isSolved {
            finishSolve()
        } else {
            persist()
        }
    }

    /// The wrist's half of a solve: pause, record the streak locally (KVS
    /// carries it to every other device), and park the fact for the phone.
    ///
    /// Points, history and Game Center are **not** recorded here. `nine.history`
    /// is a last-writer-wins blob, so two devices appending to it lose one of
    /// the two appends; the phone owns it, and `WatchSolveReport` is how the
    /// fact gets there — the same shape, and the same idempotence guard, as a
    /// solve made inside the widget.
    private func finishSolve() {
        guard var g = game else { return }
        let now = Date()
        g.timer.pause(at: now)
        game = g
        solvedAt = now

        if isDaily {
            let day = todayOrdinal
            if !streak.hasCompleted(day: day) {
                var s = streak
                s.recordCompletion(day: day, openedOn: day)
                streak = s
                try? streakStore.flushNow()
            }
            let report = WatchSolveReport(
                dayOrdinal: day,
                solve: PendingSolve(solvedAt: now, seconds: g.timer.elapsed(at: now))
            )
            var l = ledger
            l.unreportedSolve = report
            ledger = l
            try? ledgerStore.flushNow()
        }
        persist()
        try? slotStore.flushNow()
    }

    // MARK: - The link

    /// Adopt a handoff, or refuse it. Every reason to refuse is in
    /// `WatchLink.swift`; this is the persistence around them.
    func adopt(_ incoming: WatchDailyHandoff) {
        guard incoming.supersedes(known: ledger.adoptedRevision, today: todayOrdinal),
              incoming.matchesTheDayItClaims
        else { return }
        // Revision first, board second. If the write below fails or the app is
        // killed between them, the cost is one missed handoff — the phone
        // republishes. The other order costs a re-adoption over live play.
        var l = ledger
        l.adoptedRevision = incoming.revision
        ledger = l
        try? ledgerStore.flushNow()
        handoff = incoming
    }

    /// Called once the phone has taken the solve off our hands.
    func clearReportedSolve() {
        guard ledger.unreportedSolve != nil else { return }
        var l = ledger
        l.unreportedSolve = nil
        ledger = l
        try? ledgerStore.flushNow()
    }
}
#endif
