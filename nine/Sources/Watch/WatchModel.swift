// WatchModel.swift — the wrist's whole state (PRD-6).
//
// Deliberately not `AppModel`. That class is 1200 lines of phone/TV/Mac, and
// one of them is `LibraryCloudStore`, which builds a `CKContainer(identifier:)`
// — a call that traps outright on a binary holding the iCloud account but not
// the CloudKit entitlement. The watch carries KVS and no CloudKit container,
// so importing the model would have shipped it to the wrist. What the watch
// actually needs is: the appearance (mirrored), one board, and where the eye
// left it.
//
// The daily, the streak and the phone link went with the daily system
// (product decision, 2026-08-02). The watch composes its own boards — at
// `WatchComposePolicy.ceiling`, the one band it is allowed — and plays them
// standalone. A solve is its own reward: nothing is reported anywhere.
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
    /// Frozen wire key: this used to mark the daily the saved board was.
    /// Decoded and ignored — a board is a board now — but kept in the shape so
    /// a pre-removal slot still decodes and the board in it still opens.
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
    /// Published by the phone, read here. Never written from the wrist — a
    /// watch that wrote it would fight the phone under last-writer-wins.
    @ObservationIgnored private let appearanceStore =
        CouchStored(wrappedValue: SharedAppearance(), SharedAppearance.storeKey, cloudSynced: true)
    @ObservationIgnored private let slotStore =
        CouchStored(wrappedValue: WatchSaveSlot(), "nine.watch.board")

    private var slot: WatchSaveSlot {
        didSet { slotStore.wrappedValue = slot }
    }

    var screen: WatchScreen = .home
    private(set) var game: NineGame?
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

    init() {
        slot = slotStore.wrappedValue
        restore()
    }

    // MARK: - Resume

    /// Put the wrist back exactly where it was.
    private func restore() {
        guard let saved = slot.game else { return }
        game = saved
        selection = slot.cell
        solvedAt = saved.isSolved ? Date() : nil
        screen = slot.box.map { WatchScreen.box($0) } ?? .board
    }

    private func persist() {
        slot.game = game
        slot.dayOrdinal = nil
        slot.cell = selection
        if case .box(let box) = screen { slot.box = box } else { slot.box = nil }
    }

    // MARK: - Opening a board

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

    /// The wrist's half of a solve: pause and celebrate. Nothing is recorded
    /// anywhere — a watch board is a moment, not a ledger entry.
    private func finishSolve() {
        guard var g = game else { return }
        let now = Date()
        g.timer.pause(at: now)
        game = g
        solvedAt = now
        persist()
        try? slotStore.flushNow()
    }
}
#endif
