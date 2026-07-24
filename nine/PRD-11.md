# PRD-11 — Coach (explainable hints) + auto notes

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** two PRs (11a coach, 11b auto notes)
**One-liner:** When you're stuck, Nine *teaches*: a lightbulb lights the exact
cells and names the technique — "Hidden Single: only one square in this box can
take a 7 — Place it." And a wand fills every pencil mark in one toggle. Stuck
players quit; taught players finish, streak, and stay.

Prototypes: `-uxdemo.coach` (`CoachDemo`), `-uxdemo.autonotes` (`AutoNotesDemo`).
No quotas, no upsell copy — everyone paid (PRD-7 §1).

## 1. Why

`LogicSolver.nextStep(in:allowed:)` already returns technique + cells + digit +
placement/eliminations for six named techniques, each with a `displayName`
(`LogicSolver.swift:13-46,189`). `CandidateState` already computes every legal
pencil mark. The engine knows; the UI just never asks. This is the highest
experience-per-effort item in the program.

## 2. The experience

### 2.1 Coach (11a)

- A `lightbulb` GlassIconButton joins the control bar (leading the right
  cluster). Tap while unsolved → coach card slides up from the board's free
  band (the PRD-2 band absorbs it; board never moves).
- The card: technique name, one plain-English sentence (fixed template per
  technique — six strings, no LLM), and **Place it** which commits the step's
  placement via the normal `model.place` path (wave, error rules, persistence
  all standard). Eliminating techniques (pairs, box-line, X-wing) show
  **Mark it** instead, applying the eliminations to pencil marks.
- The involved cells wash in the accent (the `highlightDigit` visual grammar);
  a stronger ring marks the placement cell. Dismiss = tap outside the card.
- `nextStep` runs with `allowed:` capped to the *board's difficulty ceiling*
  (`techniques(upTo:)`), so a Gentle board never lectures about X-wings.
- Solver-side: `nextStep` needs a `CandidateState` reflecting the player's
  entries — build from the live grid; a contradiction state (player error on
  board) makes the card say "There's a slip somewhere — check the coral cells"
  and lean on the existing error highlight instead of hinting nonsense.

### 2.2 Auto notes (11b)

- A `wand.and.stars` toggle beside pencil. On: every empty cell's pencil marks
  are set from `CandidateState`; subsequent placements keep marks live (the
  engine already prunes peers on place — verify; if not, recompute on place
  while the toggle is on). Off: marks stay as they are (no destructive clear).
- One glass chip on first enable: "Auto notes · filled N candidates".
- Persisted as a pref? No — per-board, stored in the `NineGame` via a bulk
  engine mutation `applyAutoNotes()` so it undoes/persists like any move set.

## 3. Non-goals

- tvOS/macOS coach this PR (band layout is iOS; parity is a follow-up PRD).
- New solver techniques (that's PRD-17's frontier). No hint quotas, ever.

## 4. Implementation plan

1. **11a engine:** `CandidateState(fromPlayerGrid:)` seam + template strings
   per `Technique` — TDD (six techniques × sentence + step validity on fixtures).
2. 11a UI: coach card + board wash params on `BoardView` (default-off, iOS
   call site opts in — BoardView is shared).
3. **11b engine:** `NineGame.applyAutoNotes(from:)` bulk mutation + undo
   semantics (one undoable step) — TDD.
4. 11b UI: wand toggle + chip. Delete both demo scenes + flags.

## 5. Verification checklist

- [ ] `swift test`: technique-sentence fixtures, contradiction case, auto-notes
      bulk-undo — green.
- [ ] iPhone sim: coach on a mid `--debug-fill` board shows a real step with
      lit cells; Place it advances the board; screenshots captured.
- [ ] Auto notes on a fresh Steady board fills marks; undo reverts in one step.
- [ ] tvOS + macOS builds green (shared-file params default off).
