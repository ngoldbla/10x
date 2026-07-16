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
- **Prefs on four-way remotes:** `.playPauseLongPress` is only emitted by the
  8-way GameController reader, so four-way remotes could never reach the
  sheet. Added rule: *hold-click on a cell you can't write in* (a given or a
  filled cell) opens prefs; hold-click on a writable empty cell is the pencil
  rose, as specced. One gesture, two honest meanings.
- **Play/pause long-press double-fire guard:** RemoteKit attaches
  `onPlayPauseCommand` unconditionally, so a long press may *also* leak a
  plain `.playPause` (= undo) before `.playPauseLongPress` arrives. The
  screen keeps the last undone move for 1.2 s and rolls it forward again
  when the long-press lands — the player never loses a move to opening
  prefs. (See COUCHKIT-ASKS.md for the kit-level fix.)
- **Sharp generation ("healing pass"):** maximal symmetric digging often
  overshoots past X-wing. Instead of discarding those attempts, the generator
  restores dug orbits one at a time until the full chain solves, then demands
  the hardest-used technique be exactly X-wing; otherwise the attempt is
  discarded and the next derived seed is tried. Still fully deterministic by
  (seed, difficulty); still proof-checked (uniqueness + bound re-verified on
  the final grid).

## 1.1 — touch-first quality-of-life (iOS)

- **Same-number highlight (default on):** tapping any placed digit washes
  every cell holding it in the accent — pencil notes of the digit get a halo.
  Sticky across placements; tap a cell of the same digit to switch off.
  tvOS parity: parking the cursor on a digit highlights its kind. Toggleable
  in prefs ("Number highlight").
- **"One GlassSheet" rule, amended to one per screen:** the game keeps the
  prefs sheet; the home screen gains a History sheet (points, best times,
  recent solves, Game Center). Never two at once.
- **Controls at the bottom by default** on touch (thumb reach; pencil is two
  taps closer). "Controls: Top" restores the 1.0 layout.
- **Appearance Auto/Dark/Light (iOS only):** `UIUserInterfaceStyle` removed
  from Info.plist; the void stays the dark brand, light mode swaps in warm
  paper. tvOS remains always-dark.
- **Resume on launch (default on, iOS):** a board in progress opens directly;
  home is one tap back. Off in prefs restores launch-to-shelf.
- **New game from the sheet:** in-game difficulty switch (abandons the board,
  compose runs behind a "Composing…" chip); the home Continue card gains a
  discard ✕.
- **Points + history:** engine-level `SolveScore`/`SolveHistory` (tested),
  capped at 200 records, cloud-synced beside the streak. Daily solves earn a
  streak bonus (capped at 30 days); sub-5-minute solves a speed bonus.
- **GameKit:** fire-and-forget leaderboards (points, best streak) and
  achievements; the app never depends on Game Center being configured or
  signed in. IDs live in `GameCenter.ID`.
- **Interactive tutorial:** five beats on a real nearly-finished board
  (goal → place → pencil → highlight → difficulty guide), each advancing on
  the actual gesture. Prefs decoding is now field-tolerant so 1.0 settings
  survive the upgrade.

## Kept

- Background luminance breath (8–10 %, 60 s) — implemented (`BreathingVoid`),
  though listed as optional.
- Error highlight = coral underline **plus** dot marker (colorblind-safe),
  toggleable; timer off by default; one GlassSheet; no text entry; dark-first
  full-bleed; undo on play/pause with a glass toast; hold-click pencil rose;
  four-way fallback rose.
