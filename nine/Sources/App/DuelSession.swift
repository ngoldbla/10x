// DuelSession.swift — the live half of a duel (PRD-27 §4, §5).
//
// The rule about *when* a turn ends is `DuelHandoff.decide`, which is pure and
// lives in `Sources/Shared` so both surfaces share one answer instead of each
// re-deriving it in a view. This type is the plumbing around it: it reads the
// board clock, applies the quiet correction, moves the ledger on, and holds the
// one piece of state the views need — whether the hand-off card is up.
//
// **It reads no clock of its own.** `remaining` is a function of the board's
// `ElapsedTimer`, which is what makes a backgrounded app cost nobody their turn
// and what keeps the deadline on the same axis as `LoggedMove.at`.
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class DuelSession {

    /// Up between turns. While true the board's remote surface detaches on
    /// tvOS — the prefs-sheet pattern `GameScreen` already uses in both its
    /// bodies — so the card owns the focus engine rather than fighting it.
    private(set) var handoffPending = false

    /// How many digits the quiet correction removed at the last hand-off.
    /// Zero prints nothing: honest absence, not "0 cells cleared" (PRD-27 §5).
    private(set) var clearedCount = 0

    /// Placements in the current turn — the untimed turn's end condition.
    private(set) var placementsThisTurn = 0

    /// PRD-27 §4.2. **Detected, never configured**: there is no row to find and
    /// no way to be in the wrong state.
    ///
    /// Traversing 81 accessibility elements and opening a modal rose cannot be
    /// done in ninety seconds, so an assistive technology suspends the deadline
    /// entirely and the turn ends on a placement instead.
    var isUntimed: Bool {
        #if canImport(UIKit)
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
        #else
        false
        #endif
    }

    /// Seconds left in the current turn, or nil when there is no deadline —
    /// either because no turn has begun or because §4.2 suspended it.
    func remaining(in model: AppModel, now: Date) -> TimeInterval? {
        guard !isUntimed, let game = model.game, let state = model.duelState else { return nil }
        return state.remaining(atElapsed: game.timer.elapsed(at: now))
    }

    /// Ask what this instant means. Driven from the 1 Hz `TimelineView` that
    /// already redraws the timer chip, and again after every placement.
    @discardableResult
    func evaluate(model: AppModel, roseOpen: Bool, now: Date) -> DuelHandoff.Decision {
        guard let game = model.game, model.duelState != nil, !handoffPending else { return .continue }
        let decision = DuelHandoff.decide(
            DuelHandoff.Input(
                remaining: remaining(in: model, now: now),
                isUntimed: isUntimed,
                roseOpen: roseOpen,
                boardSolved: game.isSolved,
                placementsThisTurn: placementsThisTurn
            )
        )
        switch decision {
        case .handOff, .closeRoseThenHandOff:
            beginHandoff(model: model, now: now)
        case .continue, .finish:
            break
        }
        return decision
    }

    func notePlacement() { placementsThisTurn += 1 }

    /// Begin the first turn of a fresh duel.
    func begin(model: AppModel, now: Date) {
        guard let game = model.game else { return }
        placementsThisTurn = 0
        clearedCount = 0
        model.recordDuelTurn(player: 0, startedAt: game.timer.elapsed(at: now))
        handoffPending = true
        model.holdClock(.sheet)
    }

    /// Re-entering a duel board always shows the card, whoever picks the device
    /// up and however long it has been (PRD-27 §8.3).
    func resume(model: AppModel) {
        guard model.duelState != nil, !handoffPending else { return }
        placementsThisTurn = 0
        clearedCount = 0
        handoffPending = true
        model.holdClock(.sheet)
    }

    /// PRD-27 §5. **The order is load-bearing.**
    ///
    /// Clear first, so the erases land in the move log *before* the next turn's
    /// `firstMoveIndex` is taken and are therefore credited to the player who
    /// made them rather than the one arriving. Then close the turn and open the
    /// next. Then hold the clock, so a slow pass across a sofa costs the
    /// incoming player nothing.
    private func beginHandoff(model: AppModel, now: Date) {
        guard let state = model.duelState else { return }
        clearedCount = model.clearDuelErrors()                       // 1. clear, quietly
        let next = (state.currentPlayer + 1) % DuelState.seats
        let elapsed = model.game?.timer.elapsed(at: now) ?? 0
        model.recordDuelTurn(player: next, startedAt: elapsed)       // 2. close, then open
        placementsThisTurn = 0
        handoffPending = true                                        // 3. show the card
        model.holdClock(.sheet)                                      // 4. stop the clock
    }

    /// The incoming player is ready.
    ///
    /// Their turn was opened at the elapsed second the card appeared and the
    /// board clock has been held ever since, so the seconds spent passing a
    /// remote across a room come out of nobody's turn.
    func confirmHandoff(model: AppModel) {
        guard handoffPending else { return }
        handoffPending = false
        clearedCount = 0
        model.releaseClock(.sheet)
    }

    /// Forget everything. Called when the board goes away, so a duel's state
    /// cannot leak onto the next board opened in the same session.
    func reset() {
        handoffPending = false
        clearedCount = 0
        placementsThisTurn = 0
    }
}
