# PRD — Darkroom

**Status:** Draft v1 · **Thread:** `darkroom/` · **Remote-fit:** 9/10
**One-liner:** Picross puzzles compiled from your own photo library — solving a
puzzle *develops* the photograph like film in a darkroom.

## 1. Product thesis

Nonograms (picross) are the perfect couch puzzle: pure logic, grid-cursor input
that the clickpad was born for, and a picture reveal as the payoff. Darkroom's
twist is that the picture is *yours*. The asciify pipeline (downsample → quantize →
edge-extract) is already a puzzle compiler: any photo becomes a solvable grid, and
completing it develops the memory from blank paper to pixel art to the full
photograph. The emotional reveal — “oh, that's our old dog” — is a moat no puzzle
app on the platform can copy, and the content pipeline is the user's own library:
infinite, personal, free, on-device.

## 2. Goals

- The most beautiful puzzle app on tvOS; every board state passes the screenshot test.
- The reveal must land emotionally: the develop animation is the product's soul.
- Content is 100% local and deterministic. No server, no AI, in the critical path.

## 3. Non-goals (v1)

- No Game Center, no leaderboards, no multiplayer.
- No color nonograms (binary fill only; color arrives in the reveal, not the logic).
- No user photo picking UI beyond lane selection — the app curates; users don't browse.
- No hint *purchases* or economy of any kind. Hints are free and rate-limited by design.

## 4. Core experience

### 4.1 The daily roll (home)

Launch lands on a full-bleed dark tableau: three “undeveloped plates” — frosted
glass rectangles floating over a pitch-black darkroom, each faintly glowing with
an extreme blur of its hidden photo (unrecognizable, just a color aura). These are
today's three puzzles: **Small 10×10 · Medium 15×15 · Large 20×20**, curated by
`PhotoKitPlus` (`onThisDay()` preferred, with the date whispered on the plate:
“From five years ago this week”). Swipe between plates, click to begin. Solved
plates hang developed on the same wall. That is the entire home screen.

A `GlassChip` shows the current streak (consecutive days with ≥ 1 develop).

### 4.2 The board (the only other screen)

- The grid floats center-screen as a glass plane over the darkroom black; row/column
  clue numbers live on two glass rails (top, left) that lens the void behind them.
- Filled cells are luminous “silver halide” squares whose color is sampled from the
  *actual hidden photo cell* — the image is literally developing as you solve.
  Wrong-fill is impossible to see coming, so there is no wrong-fill state: fills
  that contradict the clues are rejected with a soft shake + brief red glow of the
  violated clue (mistake counting, not mistake placing — keeps boards serene).
- Completed rows/columns: their clue numbers gently extinguish (dim to 20%).

### 4.3 Remote grammar (complete)

| Gesture | Effect |
|---|---|
| Swipe ↑↓←→ | Move cell cursor (with edge-resistance rubber band) |
| Hold + swipe | Drag-fill a run (RemoteKit drag-stream); release ends the run |
| Click | Fill / clear focused cell |
| Play/Pause | Mark ✕ (impossible) / clear mark |
| Long-press click | Hint: the *coach ray* — see 4.4 |
| Play/Pause long-press | Prefs sheet (cursor speed, colorblind-safe clue palette) |
| Back | Return to the wall (board state auto-saved instantly) |

Cursor movement uses momentum swiping (fast flick travels multiple cells) to solve
the 20×20 travel-tedium problem flagged in concept review.

### 4.4 Hints — the coach ray

Long-press sweeps a soft light beam across the board that settles on one line
where progress is provable, and the relevant clue numbers pulse. It never fills
cells and never explains in words — it points where to *look*. Rate limit: one
ray per 90 seconds (a glass ring around the cursor refills). Free forever.

### 4.5 The develop (the reveal)

On final fill: input locks, clue rails dissolve, the pixel grid holds one beat —
then performs the **develop**: cells liquefy from logic-squares into the true
photograph over ~4 seconds (pixel → mosaic → full image, a reversed AsciiKit
style ramp), while a `GlassChip` fades in with date and place (“October 2016 ·
Portland”). The developed photo hangs on the wall (home) with a subtle glass
frame. This animation is Signature Moment #1 and gets a milestone of its own.

## 5. Puzzle compiler (the asciify inheritance)

1. `Downsample` the curated photo to the target grid (10/15/20).
2. Threshold via luminance + `EdgeField` weighting into a binary solution grid
   (edges bias toward “fill” so subjects keep silhouettes).
3. **Verify with a line-solver:** the puzzle must be solvable by pure single-line
   logic chains (human-solvable, no guessing). If not, auto-adjust: re-crop toward
   the photo's saliency center, re-threshold, retry (≤ 8 attempts), else discard
   photo and pick another. Broken puzzles are unshippable by construction.
4. Difficulty score = solver pass count; the daily roll targets easy/medium/hard.
5. Deterministic: (photoID, gridSize, date) ⇒ identical puzzle. Enables resume and
   makes bug reports reproducible.

Empty/unauthorized library: compiler runs on the bundled CC0 set; the app remains
fully playable forever without permissions (also the App Review path).

## 6. Visual & Liquid Glass specification

- Chrome inventory: two glass clue rails, one streak chip, one hint ring, one
  prefs sheet, plate frames on the wall. Nothing else.
- The board plane uses `.glassEffect(.regular)` with content-derived tint — as the
  photo develops, the glass warms with it (`AccentDerivation`).
- All motion on `couchAmbient` except cursor (instant) and fill (120ms pop).
- Type: clue numbers in SF Pro Rounded semibold, 29pt minimum (3m legibility).

## 7. tvOS native integration

- **Top Shelf:** the developed wall — last 6 develops as a carousel; deep-click
  opens that memory full-screen.
- **Multi-user:** streaks, wall, and in-progress boards per profile; streaks
  cloud-synced (`CouchStore .cloudSynced`) so a TV reset can't kill a streak.
- **Focus engine:** the cell cursor is a custom focus representation (one
  focusable board view, cursor drawn in-canvas) — never 400 focusable cells.

## 8. Success metrics

- D7 streak retention ≥ 25% of users who complete one develop.
- Median develops per active day ≥ 2 (of 3 offered).
- Hint usage present in < 40% of solves (difficulty is honest).

## 9. Milestones

- **M1:** Compiler + verifier CLI-testable; board playable with placeholder art.
- **M2:** Full board visual language, momentum cursor, coach ray, auto-save.
- **M3:** The develop animation, the wall, daily roll curation, streaks.
- **M4:** Top Shelf, multi-user, colorblind palette, performance + App Store pass.

## 10. Open questions

- 20×20 legibility at 3m on 55" panels: may need to cap Large at 18×18 after a
  living-room test in M2.
- Should the develop be skippable? Leaning no (4s, it *is* the product) — revisit
  only if playtests demand.
