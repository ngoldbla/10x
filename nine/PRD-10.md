# PRD-10 — Rose completion (erase petal + digit counts)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one small PR
**One-liner:** The rose learns two graces: filled cells get a direct **erase**
(today a wrong digit can only be Undo-walked), and every petal quietly shows
how many of its digit remain — "2 left … done" — so you chase the number
that's almost home.

Prototypes: `-uxdemo.erase`, `-uxdemo.rosecounts` (`RoseDemo`). Production replaces both.

## 1. Why

Erase is table stakes we're missing — the one "why can't I just fix this"
friction in the touch grammar, and the kind of thing 3-star reviews cite.
Counts turn the rose from a keypad into an instrument; `game.count(of:)` and
`isDigitComplete` already exist (`Game.swift:105-110`), so this is pure UI.

## 2. The experience

- **Erase:** opening the rose on a **filled, non-given** cell adds a tenth
  petal — an `eraser.fill` glyph directly below the ring (clear of the 7-8-9
  row). Tap or flick-down-through-it erases via the existing
  `model.erase(at:)`; the undo toast grammar already covers reversal
  ("Restored 4"). Givens never show it; empty cells never show it.
- **Counts:** under each petal, an 11 pt rounded caption — "3 left", or
  "done" in the accent when `isDigitComplete`. Completed petals keep their
  existing dim. Pencil-mode roses stay clean (no counts — petals are small).
- Both honor `couchFast` bloom animation and the never-misfire flick rule
  (`RoseGeometry.flickDirection` minimum distance still gates).

## 3. Non-goals

- tvOS/macOS rose parity this PR. `FlickRoseView` is shared, so all additions
  are parameterized off by default (`showsErase`, `remainingCounts:`) and only
  the iOS `TouchRose` call site opts in. TV/Mac adoption is a one-line
  follow-up decision, not silent drift.
- No long-press-to-erase on the board surface (the rose is the grammar).

## 4. Implementation plan

1. `FlickRoseView.swift`: optional `remainingCounts: [Int]?` + `showsErase`
   with the extra petal; geometry stays in `RoseGeometry`.
2. `TouchUI.swift` rose call sites: pass counts from `game`, set `showsErase`
   for filled cells, route the erase action → `model.erase(at:)` → close rose.
3. Delete `RoseDemo` + both flag cases.

## 5. Verification checklist

- [ ] iPhone sim screenshots: filled-cell rose with erase petal; counts rose
      showing a "done" digit (use `--debug-fill`).
- [ ] Erase → undo round-trip shows "Restored N" toast; givens unaffected.
- [ ] tvOS build green and TV rose pixel-identical (params off).
- [ ] `swift test` untouched-green (no engine change).
