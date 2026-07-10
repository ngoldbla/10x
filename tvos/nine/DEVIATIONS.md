# DEVIATIONS — Nine (vs PRD v1)

Sanctioned cuts and pragmatic deviations, with reasons.

## Sanctioned cuts (per suite direction)

- **Top Shelf extension: SKIPPED** — suite-wide decision. The engine already
  exposes `fillFraction` / solved state, so a future extension is a view-only
  add.
- **Variants (killer, thermo): v2** — classic sudoku only, per PRD §1/§3.
- **Multi-user profiles:** single profile ("default") in v1. `CouchStored`
  takes a `profile:` parameter throughout, so per-profile state is a
  plumbing change, not a redesign. Streaks are `cloudSynced: true` as asked.

## Implemented with adjustments

- **Ambiguous-flick shimmer:** CouchKit's flick reader silently drops
  `.ambiguous` strokes, so the app never sees them (see COUCHKIT-ASKS.md #1).
  The rose has the shimmer state + animation wired (`RoseState.shimmerDigits`),
  but it cannot trigger until CouchKit forwards ambiguity. The load-bearing
  guarantee — **never misfire** — holds today: ambiguous strokes place
  nothing.
- **Click-tap grace window:** a clickpad press is also a touch, so the click
  that opens the rose would read back as a `.flick(.center)` (= place 5) when
  the finger lifts. Center flicks are ignored for 0.4 s after the rose opens;
  directional flicks pass through immediately (power users can click-flick in
  one motion). Misfire-proof by construction.
- **Cursor momentum ("fast flick crosses a box"):** PRD marks momentum
  optional; v1 moves one cell per swipe. The system move command carries no
  velocity, so real momentum needs the analog reader also active on the
  board layer — deferred.
- **Daily difficulty:** the shared daily is **Steady** (one communal ritual,
  PRD §10 leaning). Gentle/Sharp remain a click away in Free Play.
- **10k-puzzle CI soak (PRD §5):** the shipped XCTest soak is 25 puzzles
  across all difficulties (uniqueness + technique bounds + symmetry +
  determinism asserted for every puzzle) sized to keep `swift test` < 120 s
  on the Linux container, per thread rules. The soak is a constant away from
  10k for a nightly lane.
- **Prefs sheet focus:** `.couchRemote` detaches while the GlassSheet is up
  so tvOS focus can reach the sheet's buttons (COUCHKIT-ASKS.md #3).
- **Sharp generation ("healing pass"):** maximal symmetric digging often
  overshoots past X-wing. Instead of discarding those attempts, the generator
  restores dug orbits one at a time until the full chain solves, then demands
  the hardest-used technique be exactly X-wing; otherwise the attempt is
  discarded and the next derived seed is tried. Still fully deterministic by
  (seed, difficulty); still proof-checked (uniqueness + bound re-verified on
  the final grid).

## Kept

- Background luminance breath (8–10 %, 60 s) — implemented (`BreathingVoid`),
  though listed as optional.
- Error highlight = coral underline **plus** dot marker (colorblind-safe),
  toggleable; timer off by default; one GlassSheet; no text entry; dark-first
  full-bleed; undo on play/pause with a glass toast; hold-click pencil rose;
  four-way fallback rose.
