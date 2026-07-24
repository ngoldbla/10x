# PRD-17 — Nocturne (the deep end)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one PR
**One-liner:** A fourth difficulty for the hardcore — denser X-wing boards,
leaner clues, longer composes — presented as a calm equal to the other three
cards under a moon glyph. Identity, not a lock.

Prototype: `-uxdemo.nocturne` (home-inline card in `TouchUI.swift`). Production replaces it.

## 1. Why (and an honest scope note)

Sharp already advertises "X-wings & deep logic" — the solver's technique
ceiling (`Technique.xWing`) is the current frontier. **Nocturne v1 is a
generator-parameter difficulty, not a new-techniques difficulty:** it *requires*
X-wing/box-line usage (not merely allows), pushes clue count to the proven
floor, and accepts longer compose times. New solver techniques (chains, wings)
are a future engine PRD — do not attempt them here.

## 2. The critical constraint: `Difficulty` is persisted

`Difficulty` is a `String`-raw `Codable` enum stored inside `SolveRecord`,
`GameKind.free`, and library blobs. A new case means **old builds decoding new
blobs throw — and `CouchStored` discards whole blobs on throw.** History and
library must not be resettable by a downgrade. Required mitigations (TDD
before any UI):

- Tolerant decode for `Difficulty` wherever it's nested: unknown raw value maps
  to `.sharp` (never a throw) via custom `init(from:)` on the *containers*
  (`SolveRecord`, `GameKind`) or on `Difficulty` itself.
- KVS is shared across devices running different builds (streak/history sync),
  so this is not theoretical — it's the PRD-8 world's normal state.
- Fixture tests: new-blob-on-old-decoder and old-blob-on-new-decoder for
  history, library, and prefs paths.

## 3. The experience

- `Difficulty.nocturne`: title "Nocturne", blurb "X-wings, chains — the deep
  end.", points base 800, dot-field density above Sharp (the prototype's
  `DemoNocturneBoard` look folds into `MiniBoard`).
- Home: the free-play row stays three across; Nocturne is the full-width card
  below (prototype layout), moon glyph, no lock. tvOS shelf + Mac new-game
  row gain it as a fourth entry (shared `Difficulty.allCases` drives them —
  verify layouts survive four).
- Composing honesty: Nocturne composes can take tens of seconds — the existing
  composing chip covers it; add "Nocturne takes a moment to compose" caption
  under its card while composing.

## 4. Non-goals

- New solver techniques. Nocturne dailies (the daily stays `.steady`).
  Separate leaderboards (points scale covers prestige).

## 5. Implementation plan

1. Engine TDD: tolerant-decode fixtures (§2) first; then `Difficulty.nocturne`
   + generator params (required-technique constraint, clue floor, compose-time
   budget) + a generation soak test (N boards unique, technique-bounded, mirrors
   the existing 25-puzzle soak).
2. UI: home card (iOS), shelf/Mac row survival pass, `MiniBoard` density.
3. Delete the `.nocturne` demo flag + home-inline prototype hunks.

## 6. Verification checklist

- [ ] `swift test`: decode fixtures + soak green; existing 28 stay green.
- [ ] Compose-time budget measured and stated in the PR (sim, release config).
- [ ] Screenshots: home with Nocturne card; a Nocturne board mid-solve.
- [ ] tvOS + macOS: four-difficulty layouts render; focus order sane on TV.
- [ ] Downgrade drill: run the previous build against a store containing a
      Nocturne record — history intact, entry shown as Sharp.
