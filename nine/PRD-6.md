# PRD-6 — Nine on the wrist (Apple Watch)

**Status:** Draft v1 for review · **Thread:** `nine/` · **Scope:** two PRs (6a playable watch app, 6b complications + Smart Stack)
**One-liner:** Real sudoku on a 45mm screen, solved by a lens and a dial: the
full board is a glanceable map, tapping a 3×3 box dives into it at finger
scale, and the **Digital Crown becomes the rose** — spin to dial a digit with
a haptic click per detent, Double Tap to place it. Nobody has shipped sudoku
that actually feels native on a watch; this is the one-of-a-kind claim.

## 1. Why

The engine is pure, deterministic, and tiny — the same daily seed produces the
identical puzzle on a wrist that it does on a TV. What has always killed watch
sudoku is input: 81 cells at 22pt are neither readable targets nor tappable
ones, and every shipped attempt is a phone UI shrunk until it breaks. Nine
already owns the answer pattern: on tvOS we turned digit entry into one
gesture (the flick rose); on the watch we turn it into one *rotation*. The
crown has detents, haptics, and precision that fat fingers never will.

Lessons carried in: PRD-3's honesty ("sneak in a move," never pitched as the
primary way to play — a wrist session is 20 seconds between moments);
PRD-3's snapshot discipline (complications read a small local file, never the
save); the engine's no-hidden-clocks rule (sessions pause cleanly when the
wrist drops).

### Approaches considered

- **Shrunken full interactive board** — rejected. 22pt cells fail both
  readability and the 44pt touch floor; it's the failure mode every existing
  watch sudoku shipped.
- **Non-spatial "cell feed"** (show one cell + constraints, crown scrolls
  cells) — rejected. Sudoku's pleasure *is* spatial scanning; a feed reduces
  it to flashcards. Too radical to carry the brand.
- **Lens + Crown-rose** (overview map → box view → crown digit dial) — chosen.
  Preserves the spatial game, puts interaction at finger scale, and gives the
  watch its own signature input the way each platform got one.

## 2. The experience

### 2.1 Overview — the map

The full 9×9 board on the glass plane, edge to edge (~190pt on 45mm; digits
~13pt — readable, deliberately not tappable per cell). This is the scanning
view: same-number highlight, error underlines, and the completion wave all
render here. Tap anywhere → dives into that 3×3 **box** (box targets are
~63pt, comfortably over the touch floor). A thin progress arc and streak
flame live in the toolbar; nothing else.

### 2.2 Box view — the lens

One 3×3 box fills the screen (~56pt cells). Context is preserved by **peer
rails** — the watch's own idiom: slim strips along the top and left edges
showing the digits already present in the selected cell's full row and
column, so cross-hatching works without leaving the lens. Swipe left/right/
up/down slides to the adjacent box (with a brief 9-box minimap flash for
orientation); crown-side edge shows the digit dial. Tap a cell to select it.

### 2.3 The Crown rose (Signature)

With an empty (or user-filled) cell selected, rotating the crown dials
through 1–9 on an arc hugging the crown-side bezel — the rose unrolled. Each
detent lands one digit with a haptic click; the dialed digit **previews live
in the cell**, dimmed, petals-style; digits already complete on the board
render dimmed on the arc (same rule as rose petals). Committing:

- **Double Tap** (the S9+ pinch gesture, `handGestureShortcut(.primaryAction)`)
  places the previewed digit — solve a cell without touching the screen.
- Tapping the selected cell places it too (all hardware).
- **Long-press the cell** places it as a **pencil mark** instead.
- Dialing past 9 reaches ✕ (erase); the dial is a bounded run (∅ … 1–9 … ✕),
  no wraparound — overshoot must stop at the ends, never loop back toward a
  placement.
- Selecting a different cell or leaving the box cancels the preview. Nothing
  ever places without an explicit commit — the never-misfire covenant at
  wrist scale.

### 2.4 Sessions, always-on, celebration

- Aggressive autosave (the existing per-move `persistProgress`); wrist-down
  pauses the timer (`ElapsedTimer` already accumulates cleanly). A watch
  session is expected to be seconds long; the board must reopen exactly where
  the eye left it (last box, last selection).
- Always-On dimmed state: board silhouette + fill arc, no digits (glanceable
  progress without burning the puzzle into a bystander's view).
- Completion: watchOS has no SwiftUI shaders, so the **Reduce-Motion luminance
  wave is the watch's hero celebration** (it's Canvas-drawn and already
  shipped), plus a haptic mini-score built from `WKHaptic` taps — three rising
  clicks riding the wave, `.success` as the Solved chip lands at 2.4s. The
  streak flame increments right on the wrist.
- Difficulties: all three, same shared daily (Steady). Generation runs
  on-watch behind the existing "Composing…" chip; if Sharp's healing pass
  proves slow on S-class silicon (>4s), Sharp hides on watch v1 (measure in
  6a; see Open questions).

### 2.5 What syncs, honestly

Streak, history, and points ride the existing `cloudSynced: true` CouchStored
keys (`nine.streak`, `nine.history`) — the watch entitlement pins its iCloud
KVS namespace to the iOS app's
(`$(TeamIdentifierPrefix)com.couchsuite.nine`), so a wrist solve feeds the
same streak the phone and TV show. In-progress **boards do not hand off** in
v1: each device keeps its own SaveSlot, exactly as two iPhones behave today;
the daily being seed-deterministic means both are always solving the same
puzzle. `StreakState.recordCompletion` is idempotent per day, so phone+watch
both solving today costs nothing. No WatchConnectivity (see Non-goals).

## 3. Non-goals

- No WatchConnectivity board mirroring/handoff (the complexity that PRD-3
  quarantined into a revision-numbered file becomes a two-radio distributed
  system on watch; v2 at the earliest, if ever).
- No flick rose on watch (a finger covers the screen it would bloom on; the
  Crown rose *is* the rose here).
- No iPhone-app changes beyond the shared-code gates (the watch app is
  standalone-capable; the phone is not its keyboard).
- No tutorial in 6a (the grammar is two sentences; a "How to play" static
  page suffices — revisit if TestFlight feedback disagrees).
- No timer display anywhere on watch (even the pref; calm × glance = no clock
  anxiety on a device that is a clock).

## 4. Implementation plan

### Step 0 — CouchKit watchOS enablement (6a)

`couchkit/Package.swift` gains `.watchOS(.v11)`. Gate-widening audit as
PRD-4 Step 0 (shared prerequisite — whichever PRD lands first does its own
platform's pass): `CouchStore.swift` (Foundation-pure; KVS available on
watchOS 9+), `CouchUI.swift` (`CouchScale.chrome` watch branch ≈ **0.42**;
typography audit at watch sizes), `GlassComponents`/`CouchGlass` (glass shim
falls back to materials pre-glass watchOS). RemoteKit and the Darkroom kits
stay out. `BoardView`, `FlickRoseView` (for `RoseGeometry` only),
`UndoToastState` compile as-is — verify no stray UIKit imports.

### Step 1 — Target & signing (6a)

- `project.yml`: new **`NineWatch`** target — modern single-target watchOS
  app (`type: application`, `platform: watchOS`, deployment 11.0), bundle id
  `com.couchsuite.nine.watchkitapp`, embedded into Nine via `dependencies` +
  `destinationFilters: [iOS]` (the exact `NineWidgets` pattern; must never
  enter the tvOS graph). Sources: `Sources/Watch` + `Sources/Engine` +
  `Sources/Shared` + the shared board/rose files (list explicitly; do not
  drag `TouchUI`/`GameScreen` in).
- Entitlements `NineWatch.entitlements`: iCloud KVS with the **explicit**
  identifier `$(TeamIdentifierPrefix)com.couchsuite.nine` (the sync keystone —
  the default `$(CFBundleIdentifier)` would silo the watch's streak).
- Signing/ops, in PRD-3's hard-learned order: portal App ID
  (`com.couchsuite.nine.watchkitapp`, KVS capability) → Matchfile append →
  writable `match appstore` re-mint (**embedding a watch app changes the iOS
  archive's profile set; re-mint before the next CI run or nine/iOS CI
  breaks**) → Fastfile: append the watch bundle to the nine iOS leg's
  `extensions`-style profile map. Marketing version pinned to the app's.

### Step 2 — Watch UI (6a)

New `Sources/Watch/` (all `#if os(watchOS)`, structured like TouchUI):
- `WatchApp.swift` — `@main`, two-screen NavigationStack (Home → Board).
- `WatchHomeView.swift` — Today card + streak/points chips + Continue +
  difficulty picker (List, not shelf — watch idiom).
- `WatchBoardView.swift` — overview map: reuses `BoardView` Canvas with a
  `boxTapHandler`; box-dive zoom is a scale+opacity transition of the same
  Canvas (one drawing surface, two camera positions — no second board
  implementation).
- `WatchBoxView.swift` — the lens: cells, peer rails, selection.
- `CrownRose.swift` — `.digitalCrownRotation($dial, from: 0, through: 10,
  by: 1, sensitivity: .medium, isHapticFeedbackEnabled: true)` (0=∅, 10=✕),
  bezel arc rendering, live preview binding, `handGestureShortcut(.primaryAction)`
  commit, long-press pencil commit.
- `WatchCelebration.swift` — WKHaptic mini-score timed against the shared
  wave.
`AppModel` compiles for watchOS as-is (audit its `#if` branches; widget
bridge and GameCenter stay out via existing gates).

### Step 3 — Game Center + polish (6a)

`GameCenter.swift` gains a slim watch branch: authenticate +
`reportSolve` only (GameKit supports score/achievement submission on watchOS;
no dashboard UI — the phone/TV/Mac own that). Fire-and-forget, as everywhere.

### Step 4 — Complications + Smart Stack (6b)

`NineWatchWidgets` extension (accessory families only) reusing
`DailyWidgetViews`/`StreakWidget` layouts nearly verbatim — watch
complications are the same WidgetKit accessory widgets iOS Lock Screen
already renders. Data path: the watch app writes its own `WidgetSnapshot`
into a **watch-side app group** (`group.com.couchsuite.nine`, registered for
the watch bundle ids) via a watch-gated `WidgetBridge` twin. Smart Stack
relevance: unfinished daily + evening hour → surface. New match profile for
the extension; same re-mint choreography.

## 5. Risks

- **The dial must feel like jewelry or the app is dead.** Detent sensitivity,
  arc animation, and preview latency need the M1-style tuning gate: ten
  consecutive comfortable solves by a fresh wrist before anything else builds
  on 6a.
- **Profile invalidation** (PRD-3's long pole, now with two new bundle ids):
  any capability slip breaks nine/iOS CI. Sequence portal → mint → merge,
  verify with a `upload:false` dry run before merging.
- **KVS namespace pinning** is load-bearing for the whole "one streak" story;
  a wrong identifier silently forks streaks. Verify cross-device within 6a
  week one.
- **Canvas performance on S9** (81 cells + wave at watch refresh): expected
  fine (it's one Canvas), but profile early; the fallback is dropping the
  breathing background on watch, never the wave.
- **watchOS glass fidelity**: if the shim's material fallback reads flat at
  wrist size, bias to higher-contrast strokes (the board must stay readable
  in sunlight — test outdoors, not just in the sim).
- **Double Tap exclusivity**: `.primaryAction` may collide with system
  defaults in unforeseen focus states; commit-by-tap must always work so
  Double Tap stays an accelerator, never the only path.

## 6. Verification checklist

1. `xcodegen generate`: NineWatch embeds in the iOS app only; tvOS and mac
   graphs untouched; `generic/platform=tvOS` build passes.
2. Watch sim (45mm + 41mm + 49mm): overview readable; box targets honest
   (mis-tap rate near zero at 41mm); peer rails correct for every cell.
3. Crown: dial 1→9→✕→∅, detent haptic per stop, preview tracks; commit by
   tap, by Double Tap (device-only), pencil by long-press; dial-then-navigate
   places nothing.
4. Solve a full Gentle board on the wrist in one sitting; then a Steady daily
   across ≥5 separate sessions — resume lands on the last box+selection every
   time.
5. Wave + haptic mini-score on solve; Solved chip at 2.4s; Always-On shows
   silhouette + arc only.
6. Daily determinism: watch, phone, TV, Mac all serve the identical board for
   the same date.
7. Streak: solve today's daily on watch only → flame increments on phone
   within KVS latency; solve on both → streak +1, history sane, Game Center
   reported once per device without error.
8. Generation timing on real S9/S10 hardware: Gentle/Steady sub-second;
   Sharp measured → ship/hide decision recorded in DEVIATIONS.
9. 6b: complications render on all accessory families + Smart Stack; midnight
   rollover flips to "new puzzle"; deep-tap opens the app to Today.
10. `fastlane beta app:nine platform:ios upload:false` resolves app + widget +
    watch profiles; ASC accepts the build (watch app version lockstep).

## 7. Open questions

- Sharp on watch: ship with a "takes a moment" composing state, or hide it?
  Decide from Step 8 measurements (leaning: ship it — the engine's dignity is
  the brand, and the composing chip already tells the truth).
- Peer rails: row+column only, or box-remaining digits too? (Leaning
  row+column only — three hints is clutter at 45mm.)
- Should the overview's tap zones bias toward the box containing the last
  selection (fat-finger forgiveness), or stay strictly geometric?
- A "wrist streak" achievement (solve a daily entirely on watch) — cheap
  delight, needs a new Game Center ID; bundle into 6b?
