# PRD — Nine

**Status:** Draft v1 · **Thread:** `tvos/nine/` · **Remote-fit:** 7.5/10
**One-liner:** Sudoku that is *faster to play on a TV remote than on a phone*,
thanks to a 3×3 flick-rose digit entry — with every puzzle proof-checked by a
deterministic solver before it can ship.

## 1. Product thesis

Everyone assumes sudoku is impossible on a TV remote because of digit entry. The
insight: sudoku's nine digits map isomorphically onto a 3×3 flick rose — click a
cell, flick one of eight directions (tap = center = 5), digit placed. One gesture
per digit. Done well, this is the fastest sudoku input on any Apple platform and
the app's entire reason to exist. Around it we build the calmest, most gorgeous
sudoku ever shipped: a single glass board floating in the void, zero clutter, and
an engine that mathematically cannot serve a broken puzzle.

Feature-limited by design: classic sudoku only in v1. The variant channel
(killer, thermo — the generator-verifier's real payoff) is the documented v2.

## 2. Goals

- The flick rose must feel like a superpower within 60 seconds of first use.
- Serenity: one board, one glass plane, no timers by default, no ads-adjacent UI.
- Anti-fragile puzzle supply: local generator + solver proof, zero network.

## 3. Non-goals (v1)

- No variants (v2), no AI-generated rulesets (v2), no daily-league/leaderboards.
- No competitive multiplayer. (Pass-the-remote duel is v2 at the earliest.)
- No timer shown by default (available in prefs; off is the statement).
- No pencil-mark automation (auto-candidates) — human solving only, keeps v1 honest.

## 4. Core experience

### 4.1 Home: the shelf

Full-bleed void. Three floating glass cards: **Today** (the daily puzzle, one per
calendar day), **Continue** (present only when a board is in progress), and
**Free Play** (difficulty chooser: Gentle / Steady / Sharp, rendered as three
increasingly dense mini-boards). A `GlassChip` shows the daily streak. Nothing else.

### 4.2 The board

An 81-cell grid on a single `.glassEffect` plane, centered, generous margins.
Givens in SF Pro Rounded semibold; entries in the user's accent tint; 3×3 box
borders as subtle luminance steps (no hard lines). The board is the only bright
object in the room.

### 4.3 The flick rose (Signature Moment #1)

Focus a cell and click: a **glass petal ring** blossoms around the cell — nine
petals in a 3×3 rose, each a small glass lens showing its digit, with petals for
digits already complete (all 9 placed) dimmed. Flick toward a petal (or tap for
5): the petal lenses light, flies into the cell, ring collapses. Total round-trip
under 400ms.

- RemoteKit's forgiveness cone handles diagonal/cardinal ambiguity; an
  `.ambiguous` flick makes the two candidate petals shimmer and awaits a cleaner
  flick — **never** a misfire. (Mis-entry is the one thing that can kill this app.)
- On `capability: .fourWay` remotes, the rose stays open for d-pad navigation +
  click — degraded but fully functional.

### 4.4 Remote grammar (complete)

| Gesture | Effect |
|---|---|
| Swipe ↑↓←→ | Move cell focus (momentum: fast flick crosses a box) |
| Click | Open flick rose (on empty/user cell) |
| Flick (in rose) | Place digit |
| Hold-click | Open rose in **pencil mode** (petals smaller, marks placed as corner notes; same grammar, zero new concepts) |
| Play/Pause | Undo (tap) — the most-reached-for button gets the best key |
| Play/Pause long-press | Prefs sheet: timer on/off, error-highlight on/off, accent tint |
| Back (in rose) | Cancel rose |
| Back (on board) | Home; board auto-saved |

Errors: with error-highlight *on* (default), a placement contradicting the
solution gets a quiet coral underline — not a modal, not a sound. With it off,
purists get silence until completion.

### 4.5 Completion

Last digit placed: the grid's luminance rolls across the board like a wave, the
glass plane “rings” (one subtle specular pulse), streak chip increments. Five
seconds, no fireworks, no stars. Calm is the brand.

## 5. Puzzle engine — generator + verifier

- **Generator:** dig-hole method from a random completed grid (deterministic from
  `(date, difficulty)` seed for the daily).
- **Verifier (the anti-fragile core):** a deterministic logic solver proves (a)
  unique solution and (b) solvability via a bounded human-technique chain
  (singles → pairs → box-line → X-wing ceiling). Difficulty is *defined* by the
  hardest technique required, not by clue count. Any puzzle failing proof is
  discarded and regenerated — a broken or guess-required puzzle is unshippable by
  construction.
- Engine is a pure Swift module with a CLI test harness; 10k-puzzle soak test in
  CI asserting uniqueness + technique bounds.
- **v2 hook (design now, build later):** the verifier's technique chain is the
  ground truth for a “why must this be a 7?” coach and for validating AI-generated
  variant rules. The module boundary (`NineEngine`) must keep solver explanations
  serializable for this future.

## 6. Visual & Liquid Glass specification

- Chrome inventory: three home cards, the board plane, the flick rose, streak
  chip, undo toast (glass, shows the reverted digit), prefs sheet. Complete list.
- The rose is the app's visual crown jewel: petals are true glass (lensing the
  board beneath), blossom animation on `couchFast`, petal flight uses a spring
  with slight overshoot. Prototype this before anything else in M1.
- Background: pure void with an almost-subliminal slow luminance breath (8%–10%,
  60s period) so long sessions never feel static.
- No reds/greens as sole signals (coral underline pairs with a dot marker —
  colorblind-safe by default).

## 7. tvOS native integration

- **Top Shelf:** today's puzzle state — untouched / in-progress (with fill
  percentage as a `GlassRing`) / solved (glowing board thumbnail).
- **Multi-user:** streaks, in-progress boards, prefs per profile; streaks
  cloud-synced.
- **Focus engine:** one focusable board view with in-canvas cursor (as Darkroom);
  the rose is a focus *layer*, trapping focus while open.

## 8. Success metrics

- Median digit-entry time < 1.5s by a user's third session (the superpower claim).
- Flick misfire rate ~0 (ambiguous-shimmer events < 5% of flicks; wrong-digit
  placements from misread flicks: none in QA soak).
- D7 retention of users who complete one puzzle ≥ 30%.

## 9. Milestones

- **M1:** Flick rose prototype on a static board — tuned until it feels like a
  superpower. Gate: 10 consecutive error-free speed runs by a fresh tester.
- **M2:** Engine (generator + verifier + CLI soak), full board play, undo, saves.
- **M3:** Home shelf, daily puzzle, streaks, completion moment, prefs.
- **M4:** Top Shelf, multi-user, four-way fallback, accessibility, App Store pass.

## 10. Open questions

- Pencil-mark ergonomics: is hold-click-then-flick comfortable for heavy note
  takers, or does pencil mode need a sticky toggle? Decide from M1 prototype data.
- Does the daily need a “Gentle” variant for the streak-protective casual user, or
  is one shared daily the ritual? Leaning one shared daily (community feeling).
