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
- **Board-position symbols (PRD-2 §4):** the PRD's primary picks
  `inset.filled.tophalf.square` / `inset.filled.bottomhalf.square` don't
  exist in the SF catalog (checked against the system symbol set). Used the
  `square.tophalf.filled` / `square.inset.filled` / `square.bottomhalf.filled`
  family instead — closer to the existing Controls-row icons than the
  PRD's arrow fallbacks.
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

## 1.2 — themes, vivid accents, pencil border highlight

- **Themes on both platforms:** `AppearanceChoice` grew into `ThemeChoice`
  (Auto/Void/Paper/Camel/Blueprint/Forest) and the tvOS always-dark rule is
  retired — the theme picker ships on the TV too. `auto` still follows the
  system; old prefs decode unchanged (the field keeps its stored key
  "appearance", and enum fields now decode with `try?` so an unknown raw
  value resets one field, not the whole blob).
- **Vivid accents, eight of them:** the four muted tints are re-tuned to
  saturated hues and crimson/gold/teal/magenta join. Light-leaning themes
  (Paper, Camel) get a deepened variant per hue so the accent keeps contrast.
  Crimson sits at rose (~345°), away from the coral error marker (~9°); the
  underline+dot error grammar is unchanged.
- **Pencil-note highlight is a cell border now:** the tiny accent halos
  behind highlighted pencil digits are replaced by a stroked rounded-rect
  ring on the cell (thinner, dimmer and inset deeper than the cursor ring,
  no fill, so the two never read as one). The highlighted mini digit still
  goes bold accent.
- **Widgets stay system light/dark:** the extension can't read nine's prefs;
  `WidgetPalette` mirrors the new vivid glacier/ember values.

## PRD-1 — Afterglow (win celebration)

- **Suite-first frameworks:** Afterglow introduces the suite's first Metal
  shaders (`Afterglow.metal`, SwiftUI `layerEffect`), first CoreHaptics use
  (`AfterglowHaptics`, iPhone-gated by `supportsHaptics`) and first
  CoreMotion use (`AfterglowMotion`, gravity only — no permission, no
  Info.plist key, not on the required-reason API list; privacy manifest
  unchanged).
- **Solved-board render loop now pauses:** pre-Afterglow, BoardView's
  post-solve `TimelineView` ran at 60fps forever. It now pauses once the
  celebration settles (tvOS: after the sheen fades, ~6.5s; Reduce Motion:
  after the wave). The iOS trophy keeps polling the gyro until the screen
  goes away — that's the feature.
- **Trophy handoff blend:** the PRD's "blend from sweep over its last 15%"
  blends position, tilt *and* strength (sweep 0.35 → trophy 0.30) so no
  visible level jump accompanies the handoff.

## PRD-4 — Nine for Mac (keyboard-native + desk mode)

- **CouchKit gains a macOS destination:** `Package.swift` adds `.macOS(.v15)`
  and `CouchStore` / `CouchUI` / `GlassComponents` / `CouchGlass` / `HelpKit`
  widen their gates to `os(macOS)`. `RemoteKit` / `AsciiEngine` /
  `PhotoKitPlus` stay platform-gated. The four sibling apps declare no macOS
  destination, so this is compile-surface only for them (heads-up in
  COUCHKIT-ASKS.md, done in-repo — not an ask).
- **`CouchScale.chrome` on macOS = 0.70** — a first guess between the couch
  (1.0) and the hand (0.55). Tune on the first screenshot review (PRD-4 §7).
  Typography reuses the iOS ramp on the Mac (no separate mac ramp yet).
- **Model hoisted to the App level:** `AppModel` now lives on `NineApp`
  (`@State`) and is injected into `RootView(model:)`, so the macOS Settings
  scene (⌘,), History window (⌘Y) and menu-bar Commands all share the one
  `@Observable`. tvOS/iOS behavior is unchanged (the model is still created
  once at launch); only its owner moved up one level.
- **Game Center dashboard on macOS = `GKAccessPoint.shared.trigger(.dashboard)`**
  — chosen over an `NSViewControllerRepresentable` host for
  `GKGameCenterViewController`: it needs no window plumbing and the access
  point stays hidden otherwise. Sign-in view controller (which GameKit hands
  back as an `NSViewController` on the Mac) is presented as a sheet on the key
  window.
- **History is a real window (⌘Y), not a sheet** — the Mac-native answer to
  "History window from the Game menu" (PRD-4 §2.6). Settings is the standard
  Settings scene (⌘,) reusing `PrefsSheetContent` with the keyboard legend and
  the touch-only layout rows (Controls / Board position / Ambient) dropped.
- **⌘Z is owned by the Edit menu, not `onKeyPress`** — a menu key-equivalent
  wins over a focused view's key handler, so routing undo through the menu is
  the honest path. The menu calls back into the focused game screen via
  `focusedSceneValue(\.nineActions)` so the glass undo toast (view state) still
  shows; the item greys out via `AppModel.canUndo`.
- **TutorialGrammar shipped (cross-phase contract):** `TutorialView` widened
  to `os(iOS) || os(macOS)` and now consumes a `TutorialGrammar`; the iOS copy
  is `.touch` verbatim (zero copy regressions). `.keyboard` re-gestures the
  five beats and the Mac practice board accepts the keyboard grammar
  (arrows/digits/Space) alongside the pointer rose. `.remote` (tvOS) and
  `.pad` (controller) are defined for PRD-5; `.pad` is a reasonable stub Phase
  5 refines.
- **Shared flick math:** `TouchRose.flickDirection` moved to
  `RoseGeometry.flickDirection(_:minimumDistance:)` (pure math), and the
  `TouchRose` view moved from the iOS-gated `TouchUI.swift` into the shared
  `FlickRoseView.swift`, so the Mac pointer rose and the iOS touch rose place
  through one classifier. A trackpad drag and a finger flick are identical.
- **Afterglow trophy tilt is pointer-steered on the Mac:** `AfterglowPointer`
  maps a hover offset over the solved board into the same `SIMD2<Double>` seam
  `BoardView.afterglowTilt` consumes on iOS. `AfterglowMotion` (CoreMotion)
  stays iOS-gated; `AfterglowHaptics` is untouched (Phase 5 owns it).
- **Erase gesture:** the Mac keyboard's Delete / 0 erases a user entry via a
  new `AppModel.erase(at:)` wrapping the engine's existing `NineGame.erase`.
  Never completes a board; a no-op on givens and empty cells.
- **Desk mode (PRD-4 §2.5):** ⌘⇧D collapses to a ~340pt board-only pane driven
  by an `NSWindow` configurator — transparent titlebar + hidden title (kept,
  not stripped, so the traffic lights and window drag survive), `minSize`
  clamped, `isMovableByWindowBackground` on. Float-on-top is **opt-in and
  remembered** (`nine.mac.deskFloating`, the PRD-4 §7 open question resolved
  toward opt-in) via `window.level = .floating`. Each posture has its own
  frame autosave name (`nine.main` / `nine.desk`) so both remember their
  corner. Esc / ⌘⇧D / a hover-revealed corner glyph restore the full window.
- **Signing is config-only:** `project.yml` carries the macOS profile
  specifier + `Nine-macOS.entitlements` (App Sandbox + KVS + game-center) and
  the Fastfile grows a `platform:mac` leg (train +2, signed pkg via gym, pilot
  upload). The `match AppStore com.couchsuite.nine macos` profile and the **Mac
  Installer Distribution** cert are **not minted from the worktree** — that is
  the pre-merge portal→mint→CI ops step (PRD-3 §3 sequencing; may hit the
  Apple Distribution cert-limit workaround from the tvOS setup).

## PRD-5 — Pad Nine (controller-driven tvOS + haptics + parity ports)

- **PadKit is a new CouchKit reader (`#if os(tvOS)`), sibling to RemoteKit.** It
  filters STRICTLY to `extendedGamepad` profiles, so the Siri Remote (a
  `microGamepad`, owned by RemoteKit) is never double-claimed. It never assumes
  `GCController.current` — it adopts one device and walks `GCController.controllers()`
  (two-controller households). Publishes `PadGesture` (move w/ momentum, flick,
  flickAmbiguous, button, connect/disconnect). Heads-up (not an ask) recorded in
  COUCHKIT-ASKS.md — Blockhead/Cartridge will want it.
- **Ghost-rose shimmer works on the pad (COUCHKIT-ASKS #1, satisfied here).**
  The Siri-Remote reader still swallows ambiguous strokes, but PadKit owns its
  right-stick classifier, so an ambiguous diagonal emits `flickAmbiguous(a, b)`
  and the board shimmers the two candidate petals (`RoseState.shimmerDigits`)
  and places nothing. The never-misfire covenant: 0.75 magnitude + return-to-rest
  + the `FlickClassifier` forgiveness cone.
- **Cursor-momentum IOU paid.** The 1.0 deviation ("fast flick crosses a box")
  deferred momentum because the remote's move command carries no velocity. The
  left stick is analog, so `PadMomentum` maps deflection magnitude → a repeat-rate
  curve: a feathered push steps one cell, a full push glides across a box (a
  detent haptic per box crossed). The d-pad remains the single-step precision
  fallback.
- **Play/pause double-fire IOU paid (in pad sessions).** The remote's
  play/pause-long-press leak (undo then prefs) is worked around on the remote;
  the pad has a dedicated **Options** button for prefs, so the double-fire never
  arises in a pad session. The remote workaround is unchanged.
- **Light mode NOT ported to tvOS — brand call.** The TV void stays always-dark
  in a pad session as everywhere else on tvOS; the theme picker's light-leaning
  options remain available (retired the always-dark rule in 1.2), but there is no
  new light affordance for the pad. The couch reads best dark.
- **Afterglow score refactored into a shared factory.** `AfterglowScoreTiming`
  (Sources/Shared, pure Foundation — Linux/hardware-independent) holds the exact
  numbers; `AfterglowScore` (`canImport(CoreHaptics)`) builds the patterns; the
  iPhone `AfterglowHaptics` keeps its class name / `playSolveScore()` / `stop()`
  API and behavior **byte-identical**, and tvOS `ControllerHaptics` plays the same
  patterns through the `GCDeviceHaptics` engines PadKit vends (`PadHaptics`,
  create-at-need lifecycle). `AfterglowScoreTimingTests` pins the 9-tick
  crescendo (0.25→2.15s) and 2.40s thump so the two hands can never drift.
- **Controller haptics live on the placement paths.** Whisper tick per placement,
  soft double-knock on an error placement (only when error highlight is on), one
  detent per box crossed gliding, full crescendo on solve. A "Controller haptics"
  prefs row (tvOS) silences all of it. Xbox pads with no CoreHaptics fidelity fail
  soft (CoreHaptics degrades to rumble; a throw means silence).
- **Gyro trophy on the controller.** PadKit exposes `motionTilt(at:)` (GCMotion
  gravity delta, clamped ±0.35 — the exact `AfterglowMotion` seam) fed through
  `BoardView.afterglowTilt` in a pad session; `AfterglowMotion` stays iOS-only.
  Remote-mode solves pass no tilt closure, so they keep PRD-1's static settle.
- **Session mode, not a second SKU.** `AppModel.padSession` + `padConnected`
  (PadKit observation). The Pad Play shelf card appears when a pad connects and
  starts a controller-locked session on today's board (Options → New Game switches
  difficulty inside the session). During a session the `.couchRemote` closure
  ignores every board gesture; only Menu/Back exits (save + home). Disconnect
  mid-game drops a glass "Reconnect your controller" veil and pauses the timer;
  reconnect resumes in place.
- **Pad tutorial is a dedicated pad-driven surface, not the pointer TutorialView.**
  `TutorialView.swift` is widened to tvOS, but the pad tutorial is a separate
  `@Observable` `PadTutorialModel` + `PadTutorialView` rather than folding into
  the iOS/macOS `TutorialView` (which is `TouchRose`/pointer-driven): PadKit's
  gesture stream is an external event source that wants a reference model, not
  view `@State`. It plays once on the first pad session (`nine.pad.tutorialSeen`),
  re-gestured onto `TutorialGrammar.pad`. The tvOS remote first-run flow (HomeView
  `HelpOverlay`) is untouched — no regression.
- **Parity ports (5b) widen gates for remote players too.** `GameCenter.swift`
  and `HistorySheet.swift` widen to `+ os(tvOS)` (GameKit dashboard via
  `GKGameCenterViewController`; a History shelf card reachable by remote and pad).
  History content is chrome-scaled ×1.7 on tvOS for the ten-foot read while iOS/
  macOS stay pixel-identical; the tvOS History sheet gains a focusable close
  control so the focus engine can always leave it (the Game Center row is disabled
  when signed out). Resume-on-launch and the prefs New-Game rows now ship on tvOS.
- **`GCSupportsControllerUserInteraction: true` + `GCSupportedGameControllers`
  (ExtendedGamepad)** added to Info.plist; **no requires-controller key** — the
  app stays fully remote-playable, enforcement is session-scoped (App Review
  necessity, PRD-5 §5).
- **Simulator quirk, not shipped behavior:** the tvOS 26.5 simulator's virtual
  remote registers as an *extended* gamepad, so `padConnected` is true and the
  Pad Play card shows in the sim with no controller. The phantom pad emits no
  gestures (keyboard input drives the remote path, which pad sessions
  correctly ignore — the lockout was validated this way). On hardware only
  real extended pads pass the filter; real Siri Remotes are microGamepad.

## PRD-5 revised — playtest fixes (cross-platform)

- **Controller grammar is first-class, adopted automatically.** Playtesting on
  a PS5 pad found the opt-in "Pad Play" mode hid undo/erase/settings/back behind
  Siri-Remote verbs a gamepad can't reach. The Pad Play shelf card and
  `startPadSession()` are retired; instead the in-game remote body listens for
  real PadKit gesture traffic and, on the first one, seeds the cursor from the
  remote and flips `padSession` in place. Adoption keys on **gesture traffic**,
  never on `padConnected` — the tvOS 26.5 simulator's virtual remote registers
  as an extended gamepad but emits no PadKit gestures, so it never adopts (the
  sim keeps the remote grammar, correctly).
- **Circle mapping changed (PRD-5 §2.1).** Circle was erase/cancel. It is now
  **tap = undo, hold (~0.4 s) = erase**; with the rose open a Circle tap still
  cancels the rose. PadKit wires `buttonB` press/release like L2 so the app can
  classify tap-vs-hold; a glass undo toast mirrors the remote's.
- **Reconnect veil retired.** A controller drop mid-session no longer freezes
  the board behind a modal veil or pauses the timer. It falls back to the remote
  grammar in place (cursor seeded from the pad), flashes a "Controller
  disconnected" chip, and keeps playing. `pausePadTimer`/`resumePadTimer` gone.
- **Controller-aware guidance.** `NineLegend` gained `pad`/`padCompact` row sets;
  the prefs sheet legend is keyed on `padSession` (not `padConnected`, so the sim
  phantom never flips it); the pad body flashes its own hint chip ("Right stick
  places · Circle undoes · Create for settings"); the first-run HelpOverlay
  appends a controller row when a pad is connected; `TutorialGrammar.pad`'s
  advance hint now states the Circle tap-undo/hold-erase semantics.
- **`--debug-pad` sim rig** (DEBUG only, beside `--debug-fill`): forces
  `padSession` on so the pad legend/chip/toast can be screenshotted in the
  simulator, which can never adopt on its own.

## PRD-5 controller fix — DualSense first-class on real hardware (2026-07-23)

Playtest on a real Apple TV: **stick navigation worked, nothing else did** — no
pencil, buttons unmapped, "just the joysticks." Every prior validation ran in the
simulator, whose phantom extended gamepad emits no gestures, so no physical button
press had ever been observed end-to-end.

- **Root cause & the unconditional fix (Phase 2.1).** Sticks were *polled* at
  60 Hz (re-reading the live profile each tick), but every button hung off a
  `pressedChangedHandler` wired once to the profile object present at `adopt()`.
  A reconnect / profile replacement (`handleConnect` guarded `controller == nil`
  and silently ignored the same controller) left those handlers on a dead object
  forever. **Every button now rides the same poll path**: `pollButtons` reads live
  `isPressed` each tick and a pure `PadButtonSampler` turns edges into gestures.
  This neutralizes *both* candidate hypotheses (stale profile AND suppressed
  handler delivery) at once, so it shipped unconditionally rather than waiting on
  the observation gate. Worst-case latency ≤16 ms — imperceptible.
- **Same-controller re-adopt (Phase 2.3).** `handleConnect` now re-runs the
  device-facing setup (motion wake, haptics re-point, sampler reset) when the
  re-announced controller is the one we already hold, instead of returning.
- **Deliberate deviations from the plan.**
  - **Phase 1 (manual observation) was NOT run in this change.** It needs a
    physical DualSense paired to the Mac and Simulator ▸ I/O ▸ *Send Game
    Controller to Device* (no CLI can inject gamepad HID; GCVirtualController is
    iOS-only). Because 2.1 is unconditional, the fix does not depend on which
    hypothesis Phase 1 would have confirmed. The observation protocol and matrix
    below are retained for a confirming pass on real hardware.
  - **The handler-vs-poll divergence detector and wired-vs-live profile
    `ObjectIdentifier` comparison from Phase 0 were dropped as obsolete.** With
    2.1 there is no handler path and no wired profile to go stale, so those
    instruments would measure nothing. The pad-probe HUD keeps the parts that
    still mean something: live pressed/axis state, per-button **poll-edge
    counters** (proof a physical press reached the sampler), the controllers()
    census, last gesture, and the routing label.
  - **Phase 2.2 (GCEventViewController host) was skipped** per the plan's own
    default — padBody's absorb-and-drop `.couchRemote` closure already neutralizes
    focus-engine echoes; adopt only on observed evidence.
  - **Create/Options mapping is UNVERIFIED.** `buttonOptions` is still polled for
    the Create/Options button, marked with a comment in `PadKit.pollButtons`. The
    physical probe (Phase 1) settles which element the DualSense *Create* button
    lights; if disproven, swap the polled element and fix the three label surfaces
    (GameScreen hint, HomeView legend, pad tutorial strings) in one commit.
- **Phase 3 completeness.** R2 is now a first-class **peek alias of L2** (hold);
  legend reads "Hold L2 · R2". The DualSense **light bar** is painted to the
  accent on the pad-session flip (`PadReader.setLight`, nil-safe on Xbox pads).
  PS/`buttonHome` (system-reserved), touchpad-click, and adaptive-trigger
  resistance are documented-as-deferred in the `PadButton` header.
- **CI gap closed (Phase 4.1).** The pure grammar (`PadButton`, `PadGesture`,
  `PadMomentum`/`classifyStick`, `PadButtonSampler`) moved outside `#if os(tvOS)`;
  a new `CouchKitTests` target exercises it on the Mac. `swift test` used to
  compile PadKit out entirely — which is how the broken mapping shipped.
- **DEBUG rigs.** `--pad-probe` mounts the diagnostics HUD + turns on PadKit
  logging/counters (adoption stays organic). `--debug-pad-gestures
  "square,flick.up,circle.tap,l2.hold"` replays a scripted gesture stream through
  the reader's own callback so the sim can screenshot pencil chip / undo toast /
  ghost-rose shimmer / peek. Honest boundary: the rig validates routing + grammar
  + UI, never the GCController poll/sampler hardware read.

### Phase 1 observation protocol (run on the Mac with a real DualSense)

Pair DualSense to the Mac → boot the tvOS sim → launch nine with `--pad-probe`
(NOT `--debug-pad` — adoption must be organic) → Simulator ▸ I/O ▸ *Send Game
Controller to Device* → open a board, then:

1. Check the HUD: `adopted` shows the vendor name, `controllers` ≥ 1 extended,
   routing flips `adoption-listener` → `pad-grammar` on the first input.
2. Nudge the left stick: HUD `gestures` counter climbs and `session` flips to
   PAD (organic adoption), OR the cursor moves with **zero** gestures (focus
   engine drove it — adoption never flipped; revisit).
3. Press every physical button once: ✕ ○ □ △ L1 R1 L2 R2 L3 R3 d-pad×4 Create
   Options touchpad-click. For each, confirm the HUD button lights green and its
   **poll-edge counter increments**. Note which element **Create** lights.
4. Un-forward mid-session (fallback chip + remote grammar), re-forward
   (re-adoption via the same-controller path).

### Manual verification matrix (per-button grammar, post-fix)

Full pass via Simulator forwarding; one confirming pass on a physical Apple TV.

- ✕ Cross — opens the rose / confirms a focused petal
- ○ Circle — tap → undo toast · hold → erase the cell
- □ Square — pencil chip toggles
- △ Triangle — same-number highlight toggles
- L1 / R1 — jump to previous / next empty cell
- L2 **and R2** — peek (dim all but one kind) while held
- Right stick — 8 petals place 1–9; ambiguous angle shimmers, places nothing
- R3 — places 5 (center petal)
- Left stick — analog momentum glide; d-pad single-steps
- Create — opens prefs (focus walks the sheet)
- Menu — rose→cancel · prefs→close · else→shelf; shelf Menu→TV home
- Light bar — lights to the accent when the pad session begins
- Un-forward mid-game → fallback chip, remote grammar, cursor preserved
- Re-forward + press → re-adoption

### Findings

_Phase 1 not yet run — record the observed hypothesis row and any Create/Options
correction here after the confirming session on the Mac and on the Apple TV._

## Playtest fix D — board library + tracker (supersedes PRD.md §4.1 single Continue)

- **The single `SaveSlot` autosave is replaced by a `BoardLibrary`** (Engine,
  pure, SwiftPM-tested): one daily entry per day plus unlimited concurrent
  free-play partials, with solved boards retained as a "previously played" log.
  PRD.md §4.1 specced a single Continue card; the home now shows a **Boards
  section / tracker** (resume, archive, delete) on every platform — an iPhone/iPad
  home section + "See all" sheet, a tvOS "Boards" shelf card, a macOS Boards card
  + `Game ▸ Boards…` (⌘B). `GameKind` moved into the Engine so the library can key
  on it (Codable shape unchanged; old `nine.save` blobs still decode).
- **Migration is one-way and safe:** a legacy `nine.save` board seeds the library
  once, then the slot is blanked so a downgrade sees "no save", never a stale one.
- **Local-only persistence** (`nine.library`, not `cloudSynced`): iCloud KVS is
  1 MB total and already carries the streak + 200-record history; `nine.save` was
  never synced, so no regression. Prune caps at 60 total / 20 solved+archived.
- **Widget-sync fixes (D3):** `knownBoardRevision` is now persisted in the app
  group (was an in-memory counter reset to 0 per process, which re-adopted and
  clobbered a free-play partial on every cold launch). `ingestSharedDailyBoard`
  and `publishDailyBoard` work in library terms — widget moves flow into the one
  daily entry only, free-play entries structurally untouched. The daily revision
  is folded into the reload digest so a within-decile daily move reloads the
  playable BoardWidget (foreground reloads are budget-exempt; free-play moves
  don't bump the revision, so no waste).

## macOS TestFlight — one-time ASC app-record setup (2026-07-23)

The mac leg's `altool` upload fails with *"Cannot determine the Apple ID from
Bundle ID 'com.couchsuite.nine' and platform 'MAC_OS'"* until a **macOS App
Store version exists on the ASC app record** — exactly the `ensure_version!`
step that was needed for iOS before its first upload. Registered via the ASC
API (Spaceship): `app.ensure_version!('1.0', platform: MAC_OS)` on app id
6789779314. With that in place the signed `.pkg` uploads (the Fastfile mac leg
passes `app_platform: "osx"` + the pkg path so pilot doesn't re-ship the iOS
`.ipa`). Build numbers are `commit-count × 10 + train` (mac train +2), so a
retry must land on a new commit or it collides with the partial run's uploads.

## PRD-10 petal counts → pull-down stats drawer (2026-07-24)

PRD-10 §"Counts" put an 11 pt "3 left" / "done" caption under every rose
petal. Shipped, played, and cut: the captions crowded the one surface that
has to stay calm, and a number that only appears while the rose is open is
the wrong home for board-wide information. **All captions are removed**
(`FlickRoseView.countCaption` and the `remainingCounts` parameter are gone;
petal dimming for completed digits stays). The same information now lives in
a pull-down drawer on the iPhone game screen — digits 1–9, each in a
nine-segment ring whose lit segments are the instances still to place —
alongside four current-board tiles (time, pace, notes, undos). The drawer is
deliberately unhinted: pull down from the top of the game screen.

Two consequences worth recording:

- The rings count **placed entries, not correct ones** (`9 - count(of:)`),
  so a wrong digit still closes a segment. This matches the existing petal
  dimming, which has always used `isDigitComplete` — the alternative would
  make the rings a free error detector and undercut `errorHighlight`.
- Pace is elapsed ÷ placements, not the gap between moves: the engine keeps
  no per-move timestamps by design ("no hidden clocks"). A board that arrives
  from iCloud therefore shows 0 undos, and its pace is not merely reset but
  briefly *inflated* — `clearLocalHistory()` empties the move log while
  `timer` keeps the accumulated seconds (PRD-8 §2), so the first placement
  after a merge would divide a whole session by one. The drawer suppresses
  the tile below three placements (`StatsDrawer.paceMinimumPlacements`),
  which hides the worst of it; the residual skew decays as you play. A true
  fix needs a per-session placement baseline stored beside the timer, which
  this change deliberately avoided — no new persisted state, no autosave
  migration risk.

## Kept

- Background luminance breath (8–10 %, 60 s) — implemented (`BreathingVoid`),
  though listed as optional.
- Error highlight = coral underline **plus** dot marker (colorblind-safe),
  toggleable; timer off by default; one GlassSheet; no text entry; dark-first
  full-bleed; undo on play/pause with a glass toast; hold-click pencil rose;
  four-way fallback rose.

## Phase 0 — engine foundations: a preserving library decode + a golden corpus (2026-07-25)

Two pieces of load-bearing plumbing with no user-visible surface, both aimed at
making later refactors survivable.

- **`BoardLibrary` decode is hand-written, tolerant and *element*-preserving —
  and that is where it stops, for a measured reason.** The library persists as
  ONE `nine.library` blob and `CouchStored` discards the whole blob when decode
  throws, so the synthesized `[LibraryEntry]` decode meant a single unreadable
  entry — a future `Difficulty` case, a future `GameKind` discriminator, a
  newly-required field written by a newer build on another device — destroyed the
  player's entire library. `init(from:)` decodes each element individually, keeps
  the ones it understands, and holds the ones it cannot in `quarantined`;
  `encode(to:)` re-emits both into the same `entries` array. Unknown **top-level
  sibling keys** of `entries` (a future `schemaVersion`, a future `settings`) are
  carried the same way, in `carriedTopLevel`. `==` is explicit over `entries` +
  `quarantined` only — `carriedTopLevel` is an encoding detail, not identity, and
  `LibrarySync` and the tests compare a hand-built `BoardLibrary(entries:)`
  against a decoded one. Nothing in the decode path throws. The covenant is
  written on the type: *never throw out of a container decode; never delete what
  you cannot read.*
- **The quarantine is now lazy, and that is a launch-path requirement rather
  than a style choice.** `RawLibraryEntry` builds the untyped `RawJSON` tree
  **only when the typed decode failed**. `RawJSON`'s decode walks a `try?` ladder
  per scalar and Swift's `Codable` failure path allocates a `DecodingError` with
  a coding-path array on every miss; a `NineGame` is ~250 numbers, so building
  the untyped tree costs several times what decoding the real type costs.
  Measured on a full 60-entry library (a 502 KB blob, the `totalCap` worst case),
  worst of 10 decodes: **49 ms** with no tolerance at all, **950 ms** with an
  eager tree per element, **~44-49 ms** with the lazy tree. `AppModel.init`
  decodes this blob synchronously against an 800 ms cold-launch budget, so the
  eager version was unshippable. A healthy library has zero undecodable elements,
  so the tolerance now costs essentially nothing until the day it is needed.
- **Field-level preservation was implemented, measured at 1515 ms, and
  reverted.** Element-level quarantine does not cover the commonest form of
  schema evolution: the synthesized decode of `LibraryEntry` *ignores* unknown
  keys, so a 1.6 entry carrying a new optional `lastHintAt` decodes cleanly on a
  1.5 device and never reaches the quarantine. The fix — keep every element's raw
  tree and merge it back underneath the typed encoding on the way out, recursive
  for objects and typed-wins-wholesale for arrays and scalars — worked and was
  fully tested, but it needs the untyped tree for **every** element, which is
  exactly the cost the laziness above exists to avoid: **1515 ms against the
  49 ms baseline** on the same 60-entry library. It was reverted whole. It also
  carried a hidden coupling worth remembering: rendering an entry as a tree needs
  a coder, and an `Encoder` cannot be read back, so the merge had to hardcode
  `CouchJSON`'s `.iso8601` date strategy — a silent breakage waiting for the day
  the store's strategy changed. Removing the merge removes that edge too.
  **So, stated plainly: a field a newer build adds to `LibraryEntry` is NOT
  protected.** An older build that can still decode the entry will drop the new
  field on its next autosave — 0.6 s after the older device merely *opened* the
  library — and a two-device player on mixed versions will lose it repeatedly.
  Whoever picks this up should start from the constraint, not from `Codable`:
  the cost is inherent to building an untyped tree through `Codable`, so the
  route is `JSONSerialization` (or another non-`Codable` reader) **at the
  CouchKit store layer**, where the blob is already `Data` and the raw tree can
  be had in one pass without a per-scalar failure ladder. That is a CouchKit
  change, out of scope for Phase 0.
- **Sentinel enum cases (`Difficulty.beyond`, `Technique.unrecognized`) were
  deliberately NOT added.** They are the other obvious way to survive an unknown
  raw value, and they are the wrong one here: `Difficulty` is `CaseIterable` and
  feeds every difficulty picker, the daily mapping and `Difficulty.index` (which
  participates in the derived generation seed); `Technique` is `Comparable` and
  ordered by rank, and the solver switches over it exhaustively. A sentinel case
  would leak into pickers and force a meaningless rank on the ordering, for a
  blast radius across the app — while the entry-level quarantine achieves the
  same data-safety goal with the damage contained to one entry.
- **Quarantine is held as a decoded JSON tree (`RawJSON`), not as `Data`.** A
  `Decoder` never hands out the underlying bytes and an `Encoder` cannot splice
  pre-encoded bytes back in, so a tree is the only representation that survives a
  trip *through* the same coder the outer value is using (and so inherits its
  date strategy). The round trip is therefore value-exact rather than byte-exact:
  object keys come back sorted, and a whole-valued `1.0` may come back as `1`.
  Numbers decode through an `Int → UInt64 → Double` ladder specifically so a
  puzzle `seed` (`UInt64`, can exceed `Int.max`) survives verbatim. Quarantined
  elements are invisible to `entries`, to `prune()`'s caps and to `sort()` —
  nothing here can read their `updatedAt`, so on rewrite they are appended after
  the known entries and the build that *can* read them re-sorts on next decode.
  There is no cap on the quarantine; it can only grow by one per unreadable
  element the newer build wrote.
- **`GoldenCorpusTests` freezes classic generation, 50 (seed, difficulty) pairs
  deep.** Each pair is generated, encoded with `JSONEncoder(.sortedKeys)` — not
  `CouchJSON`, so the hash cannot move if the persistence layer changes its
  formatting — and SHA-256'd; the 50 hashes are frozen in the file. The full
  `SolveStep` trace is inside the hash, so a solver change that alters the
  *explanation* while still solving the board also trips it.
- **The corpus composition is cost-shaped, not uniform** — 30 gentle / 14 steady
  / 6 sharp, all three difficulties covered. Measured on an M-series Mac,
  generation costs ~0.03 s gentle, ~0.3 s steady and **0.7–65 s sharp** (scan of
  seeds 3000...3029: median ~8 s, worst 65 s), because sharp digs for maximal
  uniqueness and then heals back down. A uniform 17/17/16 split would cost
  minutes on its own against the `swift test` < 120 s budget. The six sharp seeds
  are the cheap ones from that scan (0.7–2.5 s each); they exercise the identical
  pipeline, including the healing pass. **Cost of the whole corpus: 9.5 s** — the
  pre-existing 25-puzzle `GeneratorTests` soak is 87 s of the same budget, so a
  future trim should start there, not here.
- **SHA-256 is implemented in the test file (~50 lines) rather than taking a
  package dependency.** CryptoKit does not exist on Linux and CI Lane 1 is Linux
  SwiftPM, so the usual `canImport(CryptoKit)` / swift-crypto shim would mean a
  new transitive dependency on the engine and on every app target that compiles
  it in, to hash 50 small blobs in one test. `testSHA256MatchesTheStandardVectors`
  pins it to the FIPS 180-4 vectors, so a corpus mismatch always means generation
  moved, never that the hasher did.

- **Preservation goes one level further than the quarantine: unknown *fields*.**
  Element-level quarantine only catches elements that fail to decode, and the
  commonest form of schema evolution never fails: the synthesized decode of
  `LibraryEntry` silently *ignores* keys it has no property for, so a 1.6 entry
  carrying a new optional field decodes cleanly on 1.5 and would be re-encoded
  from the typed value — dropping the field 0.6 s after the older device merely
  *opened* the library. So the decode also keeps the remainder of each element's
  raw tree (`carriedFields`, subtracted against the entry's own encoded shape,
  recursive through objects but not arrays) and any unknown sibling of `entries`
  (`carriedTopLevel`), and `encode(to:)` merges them back *underneath* the typed
  encoding. Subtracting the shape rather than keeping the whole tree is what
  stops a cleared `solvedAt` being resurrected on a replay-after-solve.
- **Two accepted asymmetries in that merge, both deliberate.** (a) *Deletion does
  not survive a downgrade*: if a newer build removes a field, an older build
  holding the pre-removal tree resurrects it on rewrite. That is the right way
  round — a resurrected key is inert to the newer build's decode, a dropped key
  is lost data — but a build that removes a field must not assume it stays gone.
  (b) *The merge path re-renders the element through a locally-chosen coder*
  (`.iso8601` dates, matching `CouchJSON`), because an `Encoder` cannot be read
  back to discover the caller's date strategy. Only entries that actually carry
  unknown fields take that path, and `nine.library` is only ever written through
  `CouchJSON` — but if the store's date strategy ever moves, `tree(of:)` must
  move with it. That coupling is the single thing a reviewer should push on.
- **Equality is explicitly `entries` + `quarantined`, excluding the carried
  trees.** They are an encoding detail, not identity, and excluding them is
  load-bearing: `LibrarySync` and the tests build a `BoardLibrary(entries:)`
  (no carried trees, by construction) and compare it against a decoded one.

## "Worthy" (1.5) — accessibility, board fingerprints, IA, iOS haptics (2026-07-25)

The four user-visible halves of Wave 1, each closing a gap a live sim-use audit
found in the shipped 1.1 build. What each deliberately does *not* do is recorded
alongside, because the omissions are the decisions.

### PRD-19 — a voice for the board

The board is one `Canvas`, and `describe-ui` on the 1.1 build listed **zero**
cells: a VoiceOver player could reach every button in the chrome and not one
square of the game. The Canvas is untouched; `.accessibilityChildren` now hangs
81 synthetic elements on it, laid out on `BoardMetrics.rect(of:side:)`, and they
verify in the simulator as 81 `Button`s with values like `"5, given"`,
`"Empty, notes 2, 5, 9"` and `"4, wrong"`.

- **The actions rotor mirrors the rose rather than replacing it.** Each playable
  cell carries `Place 1`…`Place 9` (renamed `Note N` when the control bar's
  pencil toggle is on) plus `Erase` on a filled cell — the same nine digits, the
  same modes, no new concept (craft charter: one new input concept per release
  maximum, and this release spends that budget on nothing). Givens carry no
  actions at all, which also keeps the rotor from being 81 identical menus.
- **Custom actions are declared in reverse.** UIKit surfaces them in the reverse
  of declaration order; `describe-ui`'s `custom_actions` list confirmed a
  naïve `ForEach(1...9)` offered `Place 9` first. Verified, not assumed.
- **Double-tap moves the cursor and does not bloom the rose.** The petals are a
  spatial flick grammar with no screen-reader equivalent worth having, and a
  modal ring reachable by accident is worse than no ring. The rose *is* labelled
  and `.isModal` for the mixed case (VoiceOver on, a sighted hand flicking), and
  the board goes `.accessibilityHidden` while it is open so focus cannot wander
  back to a cell whose board state is dimmed out from under it.
- **`showErrors: false` is honoured through every channel.** With error
  highlighting off, `BoardSpeech.cellValue` drops the "wrong" word, the Wrong
  Digits rotor is empty (an empty rotor does not appear at all), and the error
  haptic does not fire. A knock the screen is withholding would leak the answer
  through the fingertips.
- **Chrome accessibility frames were the other half of the gap.** The audit
  measured the Home chevron at 9×15pt: SwiftUI derives an image button's AX frame
  from the SF Symbol's tight glyph bounds, not the 44pt button around it.
  `.contentShape(.accessibility, Circle())` on `GlassIconButton` and the Boards
  sheet's icon buttons brings every one to 44×44 — verified in `describe-ui`.
- **Not done here:** Switch Control group-scan ordering (boxes → cells), a
  Voice Control cell-addressing pass, and a CI lane that diffs AX-tree dumps per
  screen. All three want a harness this change does not build.

### PRD-22 — board fingerprints (the shelf's honest zero-state)

CouchKit's `GlassRing` lights its arc with `trim(from: 0, to: progress)`, so a
board you generated and have not touched drew *nothing* — a dead gray track
beside the literal text "0%". Three untouched boards were three identical dead
circles. `BoardFingerprint` draws the board instead: givens as a dot
constellation in `digitTone`, your entries in the accent, deterministic and free
because the seed already determines the givens. Three boards on the shelf are now
three visibly different portraits, and a 98%-full board reads as almost-solid
accent at 34pt.

- **`BoardProgressCaption` refuses to print a meaningless number.** Below 3%
  ("2%" on a 51-hole board means *one digit*) it says "Untouched" or "Just
  started". Honest absence over false precision.
- **`BoardsSheet.ProgressRing` was deleted, not left dormant.** Its `max(0.02,…)`
  floor was the right instinct — a board is never *nothing* — but an arc that
  short is indistinguishable from the next board's. Dead view code drifts.
- **Not done here:** the full PRD-22 dark-contrast retune against the composited
  glass (the 96-cell theme × accent matrix and its screenshot-sampling harness),
  the `accessibilityContrast` hairline variant, and the Metal per-petal
  refraction shader. Those are the expensive two-thirds of PRD-22 and want their
  own change.

### PRD-34 — the next board, and where settings live

- **"New game" left Settings on iOS and macOS.** The audit found it at the bottom
  of the prefs sheet, which is the last place anyone looks for the next board.
  Its three homes now are the shelf's difficulty cards (already there), a "Fresh
  board" row at the *top* of the Boards sheet, and an "Another" chip beside
  "Solved" once the Afterglow has settled (free-play boards only — the daily is
  one a day, and offering another would be a lie). **tvOS keeps the prefs
  section**: the TV has no in-game route to the Boards sheet, and its IA wants a
  pass of its own.
- **A copy bug went with it.** The old section warned "Starts fresh — the current
  board is abandoned". `startFree` → `compose` calls `library.create`, which mints
  a *new* entry; the board you were on stays a resumable partial. The warning had
  been scaring people off a non-destructive action.
- **The stats drawer gets a 3pt grabber for three sessions.** PRD-10 shipped the
  pull-down deliberately unhinted, and the audit found the predictable result:
  nothing suggests it exists, so nobody pulls. The compromise is the smallest
  mark that reads as a handle, budgeted in launches (`AppModel.sessionCount`,
  saturating) and retired the instant the drawer is opened by any route
  (`drawerFound`) — after that the top of the screen is bare again forever. It is
  decoration: not a button, and hidden from VoiceOver, which has had a named
  drawer action since PRD-10.
- **Prefs regrouped into Play / Feel / Appearance / Layout.** The flat list had
  drifted into an order nobody could hold — theme at row six, accent at row ten,
  with resume, haptics and the whole Layout block wedged between the two colour
  controls. Headings carry `.isHeader`, so VoiceOver's heading rotor works.
- **Not done here:** the first-launch-is-the-tutorial flow and the TipKit budget.
  Both are PRD-34's larger half and need the onboarding content designed first.

### PRD-21 — the built haptics, finally wired on iOS

`AfterglowScore.placementTick`, `errorKnock` and `boxDetent` have existed since
PRD-5 and compile on iOS (the gate is `canImport(CoreHaptics)`), but the only
class that played them was `ControllerHaptics`, which is `#if os(tvOS)`. On
iPhone and iPad the game was haptically silent until the solve crescendo. This
adds the missing player and nothing else — same patterns, same tuned timings.

- **A warm engine, separate from the solve engine.** In-play feedback fires many
  times a minute, so it cannot pay a cold `CHHapticEngine` start per digit;
  `resetHandler`/`stoppedHandler` rebuild it after an interruption, without which
  the first tap after a phone call is silent and so is every one after it.
  `stop()` tears down both engines on backgrounding.
- **The solving placement gets no tick.** The crescendo is already queued by
  `onChange(of: model.solvedAt)`, and a tick under its first beat only muddies it.
- **`NinePrefs.touchHaptics` gates in-play marks only**, not the solve score:
  a once-a-board celebration is a different thing from a per-move texture.
- **Not done here:** the audio identity. `CalmAudio` needs recorded glass-and-felt
  samples that do not exist yet; shipping synthesised stand-ins would set the
  wrong sound in players' ears first, which is the one thing an audio identity
  cannot recover from. The "Feel" prefs group is where it lands when it exists.

## PRD-19 finished — group scan, Voice Control, and a CI lane for the tree (2026-07-25)

The three thirds "Worthy" left on the table, in the order they matter to someone
who cannot use a touchscreen: a Switch Control user could reach the board and
not play it, a Voice Control user could not name a cell at all, and nothing
anywhere would notice if the whole 81-element tree collapsed again.

### Switch Control: nine box groups, and the door they open onto

`BoardAXGrid` was a flat `ForEach(0..<81)`. iOS has no explicit grouping API for
Switch Control — group scan is derived from the *accessibility container tree* —
so the fix is structural: nine `.accessibilityElement(children: .contain)`
containers, laid out on `BoardMetrics.boxRect`, nine cells each. Item scanning a
flat 81 costs up to 81 switch hits to reach one cell; boxes → cells costs at most
9 + 9. Each container is labelled "Box 4" and valued "3 empty" / "Filled", which
is the one fact that makes a nine-stop scan worth having: you can skip a finished
box without descending into it.

- **The cell frames did not move, on purpose.** Cell rects are board-local and
  the container is positioned at the box, so the offset subtracts out. The
  absolute frame of all 81 cells is byte-identical to before the nesting — which
  is what let the new baselines double as proof that the restructure changed
  nothing else.
- **VoiceOver's swipe order is now box-major, and that is the trade.** A child
  belongs to one container, so a hierarchy that groups by box cannot also
  traverse by row; `.accessibilitySortPriority` only orders siblings *within* a
  container. Accepted rather than worked around: every cell announces its own
  row and column, so orientation costs nothing, boxes are the unit sudoku
  reasoning actually happens in, and the Empty / Notes / Wrong rotors are
  unaffected — rotor order follows the declared entry list, which is still
  strictly ascending. The alternative was leaving switch users at 81 hits a cell.
- **`Erase` was the first action in the rotor, not the last.** Custom actions are
  declared in reverse because UIKit surfaces them reversed, and the erase button
  sat *after* the digit loop — so the reversal put a destructive action under the
  very first swipe of any filled cell. Found by reading a real `custom_actions`
  list, not by reasoning about the code. The block now reads bottom-up in full:
  erase declared first, digits `9...1`, surfacing as `Place 1 … Place 9 | Erase`.

### Voice Control: names you can actually say

`BoardSpeech.cellInputLabels` feeds `.accessibilityInputLabels` on every cell:
`["Cell 5 5", "Row 5 column 5", "5 5"]`, canonical first because that is the one
Voice Control draws in "Show Names" — and on this screen Show Names means 81
badges at once, so the leading name is the shortest thing still unmistakably a
board cell.

- **Inheriting the VoiceOver label would have left all 81 cells unaddressable.**
  Voice Control matches against speech-recogniser output, which never contains a
  comma, and the label is "Row 3, comma, column 5". `testInputLabelsCarryNoPunctuation`
  looks pedantic and is the highest-value test in the batch: the failure mode is
  silent, with no crash, no warning and no visible symptom.
- **Activation now opens the rose for everyone except VoiceOver.** This is the
  half that makes addressing worth anything. "Tap cell 3 5" moves the cursor
  through the same AX action VoiceOver uses — and Voice Control, Switch Control
  and Full Keyboard Access cannot reach a custom action, so all three could name
  any of 81 cells and then do nothing to one. `TouchGameScreen.axActivate` gates
  on `UIAccessibility.isVoiceOverRunning`: under VoiceOver it stays exactly the
  dull cursor move "Worthy" shipped (the rotor is that door, and a modal ring
  reachable by accident is worse than no ring), and otherwise it does what a
  finger tap does. Same input concept, not a new one.
- **macOS deliberately does none of this.** Mac Voice Control can say "Press 5"
  and `handleKey` places it, so the Mac already has a non-rotor door and
  activation stays cursor-only there.
- **Not verifiable in the simulator, and pinned by unit tests instead:** Voice
  Control does not exist on the iOS Simulator, and `accessibilityUserInputLabels`
  is absent from the AX API `describe-ui` reads — the input labels appear in no
  dump. `BoardSpeechTests` pins their content, uniqueness across all 81 cells and
  punctuation-freedom; the real-device pass is a manual step this change cannot
  automate.

### The CI lane: `nine/scripts/ax-snapshot.py`

Five screens dumped through `sim-use describe-ui` and diffed against committed
baselines in `Tests/AXBaselines/`, wired to pull requests in
`.github/workflows/nine-accessibility.yml`. Deliberately a separate workflow from
the TestFlight lane: that one ships and must never be blocked by a slow
simulator boot; this one gates review and is free to be slow.

The tripwire was tested by reintroducing the 1.1 bug — stubbing out the Canvas's
`.accessibilityChildren` — and it fires with the exact original symptom, all four
chrome buttons present and not one cell, plus a message that names
`BoardAccessibility.swift`.

- **The board on screen is frozen, because the daily is not.** A fresh launch
  shows today's puzzle, so every per-cell value in the baselines would rot
  overnight. `AXFixtureTests` owns a library blob built from seed 7 / steady — a pair the
  golden corpus already freezes (it covers steady 1...14; the first draft used
  seed 19, which is in the corpus only as *gentle*, so the ordering it claimed
  did not exist), so if generation moves the *engine* test fails first and in
  engine terms — and the lane seeds it into the simulator
  container before first launch, where `resumeOnLaunch` opens straight onto it.
  The board is chosen to carry every `cellValue` branch at once: givens, a
  correct entry, exactly one wrong entry, empties, and exactly one noted cell.
  Re-freezing is deliberate and paired: `NINE_FREEZE_AX_FIXTURE=1 swift test
  --filter AXFixture` then `ax-snapshot.py --record`.
- **`game-quiet` is the baseline worth the whole exercise.** Same board with
  `errorHighlight` off, and the wrong cell reads `"9"` where `game.txt` reads
  `"9, wrong"`. The privacy rule, proven in the shipped tree rather than in a
  formatter test.
- **The measuring instruments are in the header.** Line two of every baseline
  carries the device type, the runtime version and the `sim-use` version. Frames
  are in points so the device type fixes them, but sheet metrics move between OS
  releases and CI installs whatever Homebrew has today — so a runner bump
  announces itself as one line of diff instead of 300 unexplained frame changes.
- **Two flake sources found by running it, not by reasoning about it.**
  `simctl terminate` returns when the request is *sent*, and `CouchStored`
  flushes on a 0.6 s debounce and again from `deinit` — so a dying Nine could
  rewrite the prefs blob on top of the one just seeded, and `game-quiet` would
  intermittently photograph `errorHighlight: true`, which reads exactly like the
  privacy regression that baseline exists to catch. The script now waits for the
  process to leave `launchctl list` before seeding. Separately, a label enters
  the tree the instant its view does, which on the prefs sheet is well before
  the frames stop moving: an early run drifted by one point on nine rows.
  `settled()` now requires two consecutive identical reads before a dump counts.
- **A slow accessibility bridge is not a regression, and the script knows it.**
  `simctl bootstatus` returning is not the same as the AX bridge being up; on a
  freshly erased simulator the gap is minutes and every probe inside it answers
  "No translation object returned for simulator", which reads exactly like a
  collapsed tree. `warm_up_bridge` waits for a real answer before the first
  screen, and every poll tolerates a failed probe. Taps resolve their coordinates
  from the tree already in hand rather than through `sim-use tap --label`, whose
  fresh AX round-trip intermittently cannot find a button that a dump one second
  either side of it lists.
- **What the dumps deliberately do not claim.** `describe-ui` finds elements by
  point hit-test and a hit-test ignores AX modality, so `prefs.txt` lists board
  cells behind the sheet; that is a structural fingerprint, not an assertion that
  VoiceOver can reach them. And the JSON entry order is geometric, not traversal
  order, so the box-major VoiceOver ordering above is *not* what these baselines
  pin — they pin containment. Grouping the output by container is as close as the
  instrument gets.
- **One thing this change moved without being able to check it.** The `Erase`
  reordering above is justified by a *UIKit* quirk, and `cellActions` is
  platform-shared — the Mac supplies non-nil `place`/`erase`, so it emits the
  same action list. Whether AppKit performs the same reversal is unverified:
  there is no macOS AX-dump harness and a Mac VoiceOver rotor cannot be read
  from a script. If AppKit does not reverse, the Mac now reads `Erase` first,
  where it previously read `Place 9` first. Left unforked on purpose — a
  `#if os(macOS)` split guessed wrong is the same bug with more code — and the
  Mac's primary grammar is the keyboard, not the rotor. **The check is one
  manual pass:** turn on VoiceOver, focus a filled cell, open the actions rotor,
  read the first entry. If it says Erase, swap the two blocks under
  `#if os(macOS)`.
- **Not done here:** tvOS and macOS have no lane. `describe-ui` is iOS-only, the
  tvOS board still passes a default (read-only) `BoardAXActions` and so has no
  per-cell actions to photograph at all, and the Mac's door is the keyboard. The
  tvOS gap is the larger of the two and predates this change: PRD-19's audit was
  an iOS audit, and the TV's accessibility grammar wants a pass of its own.
- **Five screens, not every screen.** `game`, `game-quiet`, `game-rose`, `prefs`,
  `home`. The Boards sheet, History and the tutorial are not covered; the
  selection is the board-bearing screens plus the two the board is reached from.

## The first run — welcome, first flick, tip budget (PRD-34 + PRD-18, 2026-07-25)

PRD-34's remaining half (first launch *is* the tutorial's first beat; TipKit
capped at three tips) and PRD-18 (welcome card, variants teaser, and the death
of the `-uxdemo` rig) shipped as one change, because a buyer does not
experience them as two: the welcome and the first flick are one sequence.

- **The first-run legend card was deleted, not kept alongside.** PRD-18 called
  for the welcome card *plus* the existing touch legend ("two cards max"); the
  audit's own finding is that a six-row gesture table is a manual, and a manual
  is the thing a rose is supposed to make unnecessary. The beat teaches the one
  gesture by doing it, and the legend it replaced still exists verbatim in
  Settings ▸ How to play (`NineLegend.touchCompact`) and in the playable
  tutorial, so nothing was lost — it moved to where a reference belongs. Two
  cards is still the ceiling: ledger, then flick.
- **Two flags, not one, and the update install is why.** `welcome.seen` gates
  the ledger and the existing `help.seen` gates the beat. A 1.1 player updating
  into this build has `help.seen` true already: they get the ledger once and no
  beginner's lesson. Verified on a simulator by seeding `help.seen` alone —
  welcome, Begin, shelf, no beat.
- **The rose's `.isModal` trait was hiding the way out.** The first beat puts
  the rose inside a card that also carries the lesson and the **Skip** button,
  and `describe-ui` on the first build listed nine petals *and nothing else at
  all* — Skip, the heading and the instruction were beyond VoiceOver, Switch
  Control and Full Keyboard Access, in the one screen a player most needs to be
  able to leave. `TouchRose` gained `isModal: Bool = true`; only the first-run
  beat passes false. Every other rose is byte-identical.
- **TipKit-the-framework was not adopted; the budget was.** The requirement is
  a *global* cap — three tips ever, one per session, across all tips — and
  TipKit expresses per-tip counts plus one app-wide display frequency, so the
  cross-tip budget is hand-held either way. Against that it brings a datastore
  on an 800 ms launch path, a card that is not in the glass language without a
  custom `TipViewStyle`, and nothing `swift test` can reach. `TipCoach` is ~90
  pure lines in `Sources/Shared` with 14 tests covering the cap, the
  one-per-session rule, each trigger and the tolerant decode. If a later PRD
  wants TipKit's presentation, `TipCoach.next` is the eligibility function to
  hand it.
- **The tip ledger stores raw ids, not enum cases.** A tip minted by a later
  build still costs one of the three when an older build reads `nine.tips`
  back; decoding to a case would drop it and hand a downgraded player a fresh
  budget. Its own top-level blob, never a field on `LibraryEntry`.
- **Tips are silent under VoiceOver.** Every sentence is in the finger grammar
  ("tap the pencil, then flick"), which is not how a VoiceOver player reaches
  any of the three; they have the cell's actions rotor and its hint, which say
  the true thing for them. Switch Control and Voice Control still see them —
  those drive the tap path.
- **The undo tip is gated on `errorHighlight`, like the error haptic.** Its
  trigger is a wrong digit standing on the board, which the engine knows only
  from the proven solution. With mistake-marking off the tip must not fire, or
  a hint becomes the leak the whole PRD-19 privacy rule exists to prevent. The
  `TipMoment.visibleMistake` field is the caller's assertion that the screen is
  already showing it; there is a test for the false branch.
- **`UXDemo.swift` and `UXDemoScenes.swift` were deleted early.** PRD-18 says
  the last PRD standing removes them, and PRD-11–17 have not shipped, so their
  prototypes (`CoachDemo`, `AutoNotesDemo`, `ShieldDemo`, `ArchiveDemo`,
  `FeedbackDemo`, `ThemePacksDemo`, `ShareCardDemo`, `ProSheetDemo`, the
  nocturne card) went with them. This was directed, and the cost is recoverable
  in one command — they are not lost, only out of the build:

  ```bash
  git show a18cbe3:nine/Sources/App/UXDemoScenes.swift   # every scene
  git show a18cbe3:nine/Sources/App/UXDemo.swift         # DemoBoard, DemoData, the flag reader
  ```

  The screenshots those flags existed to produce are already in
  `.context/ux-audit`, which is what the PRDs actually reason from. A PRD that
  wants its prototype back restores the file, ships the production version, and
  deletes it again — which was always the workflow.
- **The teaser carries a remove-by date in its own comment: 2026-10-25.** A
  "coming soon" with no expiry rots into a lie on someone's home screen. If
  PRD-23/24 have not landed Killer or Thermo by then, the card comes out.
- **Not done here:** the welcome ledger is iOS-only (PRD-18 §2 defers tvOS and
  macOS parity), and the tvOS/macOS first runs are unchanged — the TV still
  shows its remote legend and the Mac still has no first-run screen at all. The
  Mac is the odd one out and wants its own pass: a buyer who lands on the Mac
  first sees nothing about what they bought.

## PRD-17 — Nocturne, and what measuring it cost (2026-07-25)

A fourth difficulty, and the first schema change Nine has shipped since Phase 0
— which is the point of it. Two findings reframed the PRD before a line of UI
was written, and both are numbers rather than opinions.

### The compose numbers in this file were Debug numbers

**`swift test` builds Debug, and generation runs ~50× slower in Debug than in
the Release configuration that ships.** Measured on one machine, same seeds:

| seed | Release | Debug | ratio |
|---|---|---|---|
| sharp 3000 | 0.017 s | 0.824 s | 48× |
| sharp 3004 | 0.428 s | 30.8 s | 72× |

So the Phase 0 entry's "**0.7–65 s sharp**, median ~8 s" is a Debug figure. The
shipping figure, over a 500-seed Release scan, is **p50 0.11 s, p95 0.42 s, max
0.71 s**. That is a 20× error in the number the program has been reasoning about,
and it is the difference between "Nocturne is obviously unshippable" and the
result below. `scripts/compose-scan.sh` exists so nobody re-derives a compose
figure from a Debug run again; it refuses to run in any other configuration.

### Nocturne's compose budget, measured

200 seeds, Release, Apple silicon, `scripts/compose-scan.sh 200`:

| p50 | p75 | p90 | p95 | p99 | max | mean |
|---|---|---|---|---|---|---|
| 0.98 s | 2.04 s | 3.60 s | 5.25 s | 11.21 s | 12.08 s | 1.60 s |

Every one of the 200 boards cleared the band: 0 over the clue ceiling, 0 under
the density floor. Givens landed 24/25/26 (20/20/160).

**On device this is an estimate, and it is labelled as one.** A phone's
single-core throughput is roughly a third of an M-series Mac's on this workload,
which puts an iPhone at **p50 ~3 s, p95 ~16 s, p99 ~34 s**. PRD-17 §3 budgets
"tens of seconds" and pairs it with a caption, so this composes inside its own
PRD's budget — but the p99 is a 30-second wait, and an estimate is not a
measurement. **A real device number belongs in PROGRAM-2.0's nightly perf lane
before anyone treats 16 s as the p95.** If it comes back materially worse, the
fix is not to loosen the band: it is the fast-seed catalog and forge pantry
PROGRAM-2.0 §Pillar B already specifies, because a mined seed composes in
milliseconds and the band stays honest.

### The band spec is measured, not chosen — and PRD §1's premise was half wrong

PRD-17 §1 says Nocturne "*requires* X-wing/box-line usage (not merely allows)".
Sharp already requires one: `Difficulty.sharp.floor == .xWing` has shipped since
1.0, and the verifier rejects any sharp board a lesser chain can solve. So that
axis was already spent, and the only headroom for a generator-parameter band is
**fewer clues** and **more advanced steps**. Both were priced:

| spec | Mac Release p50 | max | verdict |
|---|---|---|---|
| ≤26 givens, ≥3 advanced steps | **0.98 s** | 12.1 s | shipped |
| ≤26 givens, ≥4 advanced steps | 1.92 s | 16.2 s | ~2× for one more deduction |
| ≤24 givens, ≥1 X-wing | ~6 s | 26.7 s | 13× — the clue floor is a cliff |
| ≤26 givens, ≥2 X-wings | ~6 s | 53 s+ | 16× — pure rejection, ~6% of boards |

The cliff at 24 givens and the one at two X-wings have the same cause and
different shapes. The **Nocturne-only re-dig pass** (offer each orbit that
healing restored back to the hole, keep it out if the board stays unique and
inside the chain) drives the clue count to a local minimum *by construction*, so
26 is nearly free and 24 is not — 24 is below where the re-dig lands, so it
reverts to rejection sampling. A second X-wing was never anything but rejection:
only ~6% of sharp-grade boards have one, and no dig strategy here can aim at it.

`BandDemands` is the one-line seam if the product call changes. What it must not
become is a *tuning* knob for compose time — see the next entry for why.

### The attempt budget was calibrated against the wrong quantity, and it lied

PRD-23's never-spin rule says a band with demands needs an attempt ceiling.
The first one was **500**, reasoned from wall-clock: "p50 is 0.75 s, so a compose
is a handful of attempts." It is not. Most Nocturne attempts cost **~0.4 ms**
because the dig degenerates early and `verify` rejects on the X-wing floor before
the expensive part; roughly **one attempt in 500** clears everything. So the
budget fired on nearly every seed and handed out Sharp-grade boards wearing a
Nocturne label — 31 givens, one X-wing — **while the wall-clock p95 improved from
4.7 s to 0.44 s.** A compose-time test would have called that a win and shipped
it.

Two things came out of that:

- The budget is now **200,000**, an order of magnitude above the measured p95 of
  ~12,000 attempts, and its doc comment states the quantity it bounds.
- `NocturneSoakTests` asserts on **the product** — givens, density, uniqueness,
  trace, symmetry — and only *prints* the timing. A compose-time threshold in a
  test is a flake on shared CI hardware, and worse, it is a metric that improves
  when the feature breaks.

The backstop's fallback is a board that is genuinely unique, inside Sharp's chain
and past the X-wing floor, and only short on density — never a stall, never an
unproven puzzle. At the current budget it is unreachable in practice.

### `nine.history` was the soft blob, and tolerance in *this* build cannot fix it

Phase 0 hardened `nine.library` and stopped there, which left the history the
most dangerous blob Nine persists: `SolveHistory` shipped with a **synthesized**
decode, so one record carrying an unknown `Difficulty` raw value threw the whole
`[SolveRecord]` array, `CouchStore`'s `try?` swallowed the throw, and the player
lost **every solve they had ever recorded**. It is `cloudSynced`, so it would
have gone from the old device to every device, LWW.

The trap is that adding tolerance here fixes nothing: **the build that throws is
already on TestFlight** (tvOS 450 / iOS 451 / macOS 452). So the fix is on the
wire, and it is the same sibling-key lesson the library taught:

> A band added after 1.5 persists **two** keys. `difficulty` holds the nearest
> band an old build can read (`Difficulty.wireBand` — Nocturne writes `sharp`),
> and `band` holds the true identity. Every shipped `Codable` decode ignores an
> unknown key, so the old build reads a complete history with the new solve shown
> as Sharp; this build reads `band` first and gets Nocturne back.

The three 1.5 bands write no sibling, so their bytes are unchanged.

**The accepted cost, asserted as a test rather than left as a footnote:** an old
build re-encodes from its typed value, so once a downgraded device *writes the
history back*, the sibling is gone and that solve is permanently Sharp. The
solve, its date, its time and its 800 points all survive — only the label is
lost. `anOldBuildRewriteDemotesNocturneToSharpButLosesNoSolve` is that sentence.

`SolveHistory` also got Phase 0's covenant proper — per-element quarantine and
`carriedTopLevel` — so the *next* schema change is a per-record loss at worst.

### The library needed nothing, and that is the Phase 0 dividend

A Nocturne board fails the old build's `LibraryEntry` decode twice over
(`GameKind.free`, and the puzzle's own `difficulty`), so Phase 0's quarantine
holds it verbatim and hands it back on upgrade. No bridge, no new code. The
cost is that the board is **invisible while the player is on the old build** —
strictly better than the alternative, because nothing is lost, but worth knowing.
Deliberately *not* bridged: `GeneratedPuzzle.difficulty` is inside the golden
corpus hash, and rewriting it to smuggle a sibling would move every frozen
Nocturne hash for no data-safety gain the quarantine does not already provide.

### The drill runs against real old code, and it has been falsified

`DowngradeDrillTests` models the old build with `Legacy*` mirror types, which is
a *claim* about code that is not in the tree. `scripts/downgrade-drill.sh` is the
check on that claim: it writes fixtures from this tree, checks the base ref into
a throwaway worktree, copies `scripts/downgrade-drill/LegacyDrillTests.swift`
into it, and runs the assertions against that release's own source. It refuses
to run if the base ref already knows about Nocturne, because a drill that
compares a build against itself proves nothing.

Both halves were falsified before being believed: with `wireBand` disabled,
`origin/main` fails `testTheOldBuildKeepsItsWholeHistory` and the in-tree suite
fails 6 assertions — and the *library* half still passes, which is the clean
demonstration that the two blobs are protected by two different mechanisms.

PROGRAM-2.0 Phase 0 §3 asked for this scripted. It now is.

### Three things a review caught that the tests had not

- **`SolveHistory.init(from:)` did not restore newest-first.** `records` is
  newest-first by contract — `capacity` prunes the tail as the oldest,
  `trend(window:)` reads `prefix` as the most recent, the History sheet shows
  `prefix(15)`, `WidgetBridge` takes `first` — and quarantined elements are
  necessarily re-emitted *after* the readable ones, because this build cannot
  read their dates. Without a sort on the way back in, a future build's
  recovered records (the player's *newest* solves) would land at the tail: shown
  last, excluded from the trend, invisible to the widget, and the first ones
  `removeLast` deletes at capacity. `BoardLibrary.init(from:)` closes this exact
  loop; `SolveHistory` now does too. The sort also exposed a pre-existing
  fixture bug — `legacyTwoHundredRecordBlobDecodesUnchanged` built its 200
  records in reverse-chronological order, producing an oldest-first array that
  violated the invariant its own sibling test asserts.
- **The band stand-in a *future* build chooses is now carried, not rewritten.**
  A later band need not degrade to Sharp: one pitched between Steady and Sharp
  would write `{"difficulty":"steady","band":"dusk"}`. The first version forced
  `.sharp` on any unrecognised band, which restated that record as Sharp for
  every build downstream — and, since Nocturne now counts toward `sharp.first`,
  inflated an achievement with a band nobody had played. `carriedWireBand` holds
  the writer's own choice and re-emits it verbatim.
- **A `difficulty` that is no longer a string is quarantined rather than
  flattened.** `try?` on the string decode meant a future record whose *shape*
  changed decoded as Sharp with everything else intact, never reached
  `RawSolveRecord`'s quarantine, and was overwritten on the next autosave — the
  precise failure the covenant exists to prevent, hiding behind a `try?`. That
  decode now throws so the element is held verbatim.

### The compose guard became visible, because Nocturne made it long

`AppModel.compose` has always dropped a second request while one is in flight
(`guard composing == nil else { return }`), and every entry point routes through
it: all four shelf cards, the Mac ⌘N menu, the Boards sheet's Fresh board row,
the tvOS New game row, and Today. Sub-second that guard was invisible. At
Nocturne's measured tail it is a shelf where Today and three other cards look
live and silently ignore taps for tens of seconds.

The cards that are *not* composing are now `.disabled` on iOS and macOS while a
compose runs, so the wait is legible instead of the app feeling broken. **tvOS
was deliberately left alone:** `.disabled` removes focusability, and disabling
the card that currently holds focus moves focus somewhere else mid-compose — a
focus-management change that wants its own pass and its own AX baseline, not a
drive-by in a difficulty PRD. The TV still shows the composing chip on the card
you chose; the other three simply do nothing if you click them.

### Deviations from the PRD text, and why

- **The blurb is "Fewer clues, deeper logic", not §3's "X-wings, chains — the
  deep end".** Chains are precisely what Nocturne does not have — §1 of the same
  PRD rules new solver techniques out of scope — and a band that advertises a
  technique the verifier cannot prove is a claim the engine would have to break.
  The copy says the two things true of every Nocturne board.
- **Points base 800 as specified**, plus a new test that the whole table stays
  monotone in `allCases` order, since that is the order every picker renders.
- **Nocturne counts toward the existing `sharp.first` achievement** rather than
  getting its own. Its own needs an App Store Connect record, and §4 rules
  separate prestige surfaces out of scope — but gating on `.sharp` alone would
  leave a Nocturne-only player unable to earn it.
- **The composing caption replaces the blurb rather than stacking under it.** A
  card that grows a line mid-compose shoves the rest of the shelf down while the
  player is watching it.
- **The Mac's New Game menu is now `ForEach(Difficulty.allCases)`.** It was three
  hand-written `Button`s, and a missing one is not a compile error the way a
  missing `switch` case is — this would have shipped a Mac with no way to start a
  Nocturne board. ⌘N stays on Steady; moving it would retrain a shipped habit.
- **The iOS variants teaser is now below the fold.** The full-width Nocturne card
  costs ~130 pt, and the teaser is what fell off the first screen (re-recorded in
  `Tests/AXBaselines/home.txt`). It is still reachable by scrolling, it is the
  least load-bearing thing on the shelf, and it carries a 2026-10-25 remove-by
  date anyway — but it is a real change to what a new buyer sees first.

### Not done

- **No device-measured compose time.** Every number here is Mac Release; the
  iPhone figures are a ×3 estimate. Nightly lane.
- **No Nocturne daily** (PRD §4 non-goal — the daily stays `.steady`), no
  separate leaderboard, no new solver techniques.
- **The Nocturne golden pairs are the six cheapest seeds of 200.** They exercise
  the identical pipeline including the re-dig, but a Debug-affordable seed is by
  definition an unrepresentative one — a median Nocturne seed would cost ~50 s in
  Debug on its own. Breadth lives in the Release soak, not the corpus.
- **`swift test` is now 109 s against a ~120 s budget** (idle machine; it reads
  116 s with simulators booted, which is worth knowing before blaming a commit).
  Nocturne added ~9 s of that — 6.5 s of golden-corpus pairs and ~2 s for the one
  Debug-affordable compose. The other ~100 s was already there: 60 s of
  `testGenerationSoakAcrossDifficulties` and 25 s of `testGenerationIsDeterministic`.
  The headroom is thin and it is not Nocturne's doing; whoever needs some should
  start with the 25-puzzle soak, exactly as the Phase 0 entry already said.
- **The tvOS difficulty guide was mitigated, not verified.** `PadDifficultyGuide`
  is a fixed-height beat with no `ScrollView`, and a fourth row is exactly what
  could push it off screen. The Nocturne `explainer` was cut to the length of its
  three peers so the row cannot wrap to three lines — but the beat itself was not
  driven on a TV. The four-card *shelf* was (screenshot in the PR); the guide was
  not.

## PRD-23 — the variant engine, and the number that decided its top tier (2026-07-25)

Engine only, behind a channel with no user-facing surface. Nothing on any screen
changed, no entitlement moved, no persisted key was added. The full write-up is
[PRD-23.md](PRD-23.md); what follows is what a later reader needs and would not
otherwise find.

### The golden corpus was run after every commit, and that was the point

Five commits, five 56/56 runs. Not one run at the end — the contract was
"byte-identical through the entire refactor", and a corpus checked only at the
end tells you *that* something moved, across five commits' worth of diff, which
is the expensive time to find out. Corpus run times across the five: 14.97 s
before any change, then 13.72 / 13.41 / 13.40 / 15.33. The indirection through
`ConstraintContext` costs nothing measurable on the classic path.

Four independent mechanisms hold it, and it is worth being explicit that they are
independent, because each one alone would have been a single point of failure:

- `Sudoku.swift` and `BacktrackSolver.swift` are **byte-identical to
  origin/main**. The prover has a twin, `ConstraintBacktrackSolver`, and classic
  delegates into the frozen original through one pointer compare. It is not a
  fast path; for classic it is the only path.
- `ConstraintContext.classic` is a shared singleton whose `peers`, `units` and
  `unitsOfCell` **are** the static `Sudoku` arrays. Every loop that used to name
  them reads them off the context instead — same arrays, same order, same bytes.
  `compile([])` returns that singleton and `init` is private, so `isClassic` is
  total rather than a heuristic.
- **`GeneratedPuzzle` gained no field.** It is inside the golden hash, so a
  `constraints: []` would have moved all 56 hashes for a value that is empty on
  every classic board. `VariantPuzzle` is a sibling type — the identical shape to
  the `band` sibling key `nine.history` grew in PRD-17, for the identical reason.
- New `Technique` cases are **appended**. `Difficulty.allowedTechniques` is
  `techniques(upTo: .xWing)` and filters them out by rank; and a classic context
  has no cages, so they would find nothing anyway. Both are asserted, because on
  the one enum the golden hash is made of, one mechanism is not enough.

### Sharp's failure was an information problem, not a solver problem

Sharp asks for zero givens — the real killer aesthetic, cages only. It composed
nothing: 3,000 attempts, no board. The natural reading is "our technique chain is
too weak", and acting on that reading would have meant a solver PRD.

It was the other cause, and a diagnostic lane written to tell the two apart is
what said so. With cages up to five cells, the zero-given board is **not uniquely
determined at all — 0 of 200**. No technique could have closed it, because there
was nothing to close.

| maxCageSize | cages alone determine the grid | our chain closes it |
|---|---|---|
| 2 | 15/40 | 15/40 |
| 3 | 5/40  | 2/40  |
| 4 | 1/40  | 0/40  |
| 5 | 0/40  | 0/40  |

Small cages carry far more information — a two-cell cage summing to 17 admits
exactly `{8,9}` — so `maxCageSize` became a band parameter and Sharp took 3.

Two readings of that table are load-bearing and easy to lose:

- **At size 2 the two columns are equal.** Whenever the cages determine the grid,
  our chain closes it. So technique coverage is *not* the binding constraint down
  there, which is a genuine (and cheerful) result about the technique set. It
  begins to bind at size 3.
- **And size-2 boards close on naked singles** — 38 of 40 traces ended on one.
  Buying uniqueness with small cages spends the difficulty that made the tier
  worth having. Size 3 is a compromise, not a free lunch, and if PRD-24 wants a
  harder Sharp the lever is a *designed* cage layout, not a smaller one.

### Compose p95 per tier, Release, and all three meet budget

100 seeds per tier, Apple silicon Mac, `scripts/killer-scan.sh`:

| tier | composed | p50 | p95 | p99 | max |
|---|---|---|---|---|---|
| gentle | 100/100 | 0.01 s | **0.02 s** | 0.02 s | 0.02 s |
| steady | 100/100 | 0.02 s | **0.05 s** | 0.08 s | 0.08 s |
| sharp  | 100/100 | 0.03 s | **0.14 s** | 0.17 s | 0.17 s |

Nocturne's Mac Release p95 is 5.25 s, so killer's slowest tier is ~37× cheaper
than a band that already shipped. The ×3 phone estimate puts Sharp's p95 near
0.4 s. It is an estimate and it is labelled as one — PROGRAM-2.0's nightly lane
still owes a device number, exactly as it does for Nocturne.

The soak reports the technique mix alongside the clock, deliberately. A tier that
composes in 20 ms and hands out a board every naked single closes is not a tier,
and no timing table can say so. All three are cage-driven: `cageCombination`
fires on 100/100 boards (22–36 steps each) and `innieOutie` on 85–98/100.

### Four things the tests found that review would not have

- **A cage tiling grown on pure geometry.** A region spanning two boxes can hold
  the same digit twice — legal as a *sum*, illegal as a *cage*. The context then
  made two cells that legitimately share a digit into mutual peers, the true
  digit was eliminated, and the contradiction surfaced two steps later inside
  `hiddenSingle`, a classic technique doing nothing wrong. Cage growth is
  grid-aware now. The lesson is about the diagnostic, not the fix: the first
  unsound deduction a fuzz reports is usually downstream of its cause, and
  "the failing technique is the buggy technique" would have sent someone to
  rewrite `hiddenSingle`.
- **`return .none` from a function returning `SolutionCount?`** resolves to
  `Optional.none` — nil — so every "provably zero solutions" was silently
  returning "cannot answer". `isUnique` reads false either way, so no call site
  could see it. Every case is spelled out in full now, and two tests exist purely
  to tell nil from `.none`.
- **`String.hashValue` is seeded per process in Swift.** An early `attemptSeed`
  folded `variant.rawValue.hashValue` into the seed, which would have returned a
  different board on every launch — the exact property the golden-corpus
  discipline exists to protect, broken in the one file nobody would have checked
  it in. The salt is an explicit constant with a test.
- **`Difficulty.sharp.allowedTechniques == Technique.allCases`** — a shorthand in
  a test that had shipped since 1.0, true only while every technique was a
  classic one, and false the moment four were appended. It failed correctly, and
  it is the reason to note a process point: it fails in `GeneratorTests`, which
  was not in any of the filters used while iterating, so it went unseen from the
  commit that introduced it until the first full `swift test`. **Filtered runs
  verify the thing you changed; only the full suite verifies what you changed it
  under.** The assertion now spells the six cases out and adds the general form —
  no `Difficulty` band, ever, reaches a variant technique — because "the whole
  enum" is exactly the wrong thing for a band frozen by the golden corpus to
  mean.

### The channel is sealed by a test, not by a comment

`VariantChannel.isOpen` is `false` outright in Release and additionally needs
`NINE_VARIANTS=1` in Debug, so a developer running the app in Xcode sees nothing.
Neither of those survives somebody wanting a debug menu, so
`VariantChannelSealTests` walks `Sources/App`, `Sources/Widgets` and
`Sources/Shared` and fails if any of them so much as names the variant engine.
**PRD-24 is the PR that deletes that test**, and deleting it should feel like a
decision rather than a fix.

### Not done

- **No device-measured compose time.** Mac Release only; the phone figure is a
  ×3 estimate. Nightly lane.
- **No persistence at all.** A `VariantPuzzle` has never been written to disk, so
  there is no `GameKind`, no library entry, no share format and no downgrade
  drill. When PRD-24 adds them, `EXECUTING-A-PRD.md` §2 applies unchanged: a
  sibling top-level key or its own `CouchStored` blob, never a field on
  `LibraryEntry`.
- **No fast-seed catalog and no `PuzzleForge` pantry.** PROGRAM-2.0 §Pillar B
  specifies both as cost mitigations for exactly this PRD. At a 0.14 s p95 there
  is nothing to mitigate; they become interesting if the device number disagrees.
- **Thermo is implemented but not generated.** The constraint compiles to peer
  and bound tables and `thermoBound` is a working technique with fixtures and
  fuzz coverage — an architecture that has only ever seen one constraint kind is
  not evidence that it generalises. Thermo *supply* is PRD-24's, which is where
  thermo ships first anyway.
- **Rule of 45 is single-unit only.** The chute forms (two and three rows at
  once) are standard killer and are absent. Worth knowing: on a fully tiled board
  the *innie* branch is unreachable, because every cell is caged — only the outie
  form ever fires. The innie path is kept and fixture-tested for the
  partially-caged boards a future variant might produce.
- **The tier ladder is compressed.** Gentle lands at 6 givens (p50) and Steady at
  4; they are separated mostly by technique set rather than clue count. Whether
  that reads as three tiers to a player is a PRD-24 question and nothing here
  answers it.
- **`swift test` grew ~10.4 s**, and it is measured per suite rather than
  inferred from the total, because the total moves with the machine. The eight
  new suites, idle Mac, Debug:

  | suite | cost |
  |---|---|
  | `VariantGeneratorTests` | 8.22 s |
  | `VariantTechniqueTests` | 1.34 s |
  | `ConstraintBacktrackSolverTests` | 0.68 s |
  | `VariantChannelSealTests` | 0.11 s |
  | `CageTilingTests` | 0.07 s |
  | `VariantConstraintTests` | 0.02 s |
  | `ConstraintDelegationTests` | 0.01 s |
  | `KillerSoakTests` | skipped (opt-in) |

  Almost all of it is `VariantGeneratorTests`' four real composes. The suite now
  reads **112.5 s** (1:55 wall clock including the build) against the ~120 s
  budget; the PRD-17 entry recorded 109 s, and the difference between that and
  112.5 is not 10.4 s because these are different machines-in-different-moods,
  which is the reason the per-suite table above is the number to trust. The
  budget was thin before this PRD and the Phase 0 advice still stands: the
  60 s `testGenerationSoakAcrossDifficulties` and the 24 s
  `testGenerationIsDeterministic` are where the headroom is, not here.

## PRD-11 — the coach explains itself, and the two covenant clauses it spends (2026-07-25)

Both halves in one PR (11a coach, 11b auto notes), because they share
`TouchUI.swift` and EXECUTING-A-PRD §7 allows only one owner of that file at a
time. The design doc is
[docs/superpowers/specs/2026-07-25-prd-11-coach-design.md](../docs/superpowers/specs/2026-07-25-prd-11-coach-design.md);
what follows is what a later reader needs and would not otherwise find.

### PRD-11 predates the constitution it now lives under, and two clauses lost

`PROGRAM-2.0.md`'s anti-bloat constitution says 2.0 will never "let the coach
place a digit" or "add a fifth control button". PRD-11 §2.1 does both. The
rulings, taken deliberately rather than drifted into:

- **`Place it` and `Mark it` stay.** The clause is read as "the coach never
  *auto-solves*", which remains true: nothing in `Coach.swift` runs unprompted,
  and `applyCoachStep` only ever executes because the player pressed a button.
  It routes through the ordinary `model.place`, so the wave, the error rules,
  the haptics and persistence are exactly what the rose would have left.
- **The control bar went from four buttons to six.** An override, not an
  oversight. What it cost is in the next section.

### "No fifth control button" turned out to be geometry, not taste

The bar could not hold six buttons *and* the timer chip. Measured, not
estimated: six 44 pt targets are 264 pt, the timer chip measures ~82, and with
gaps and padding the row wanted **~422 pt — wider than any iPhone made**.
`sim-use describe-ui` caught `Settings` running to x=395 on a **375 pt** iPhone
SE (20 pt off-screen) *and* on a **393 pt** iPhone 17 (2 pt off). Closing the
gaps from 10 pt to 6 was not enough, and shrinking the targets was never
available — the craft charter's 44 pt floor is the reason the AX frames are
`.contentShape(.accessibility, Circle())` in the first place.

So **the timer chip moved out of the control bar into the PRD-2 free band**,
which was sized for exactly this ambient chrome and already hosts
`AmbientSlotView`. The bar is controls only now, and 6×44 + 5×6 + padding =
322 pt clears the smallest phone by 53 pt (verified: `Settings` ends at 361 of
375). Both band occupants stand down while the coach card is up, since the card
parks in that same band.

Worth stating plainly for whoever picks up PRD-12, the next `TouchUI` owner:
**the control bar is now full.** A seventh button does not fit at 44 pt on a
375 pt phone, whatever the taste argument.

### The coach cannot read the solution, and that is structural

PRD-11 §2.1 wanted the contradiction card to say "check the coral cells". Coral
comes from `NineGame.isError`, which compares against `puzzle.solution` — and
`errorHighlight` is a setting the player can switch off. Pointing at coral
would leak, through the one surface a stuck player is most likely to open,
precisely what PRD-19 spent a release teaching the AX layer to refuse to say.

A `CoachAdvice.contradiction` is therefore a **peer clash** (a filled cell whose
value duplicates a peer's) or a **dead cell** (an empty cell with no candidates
left). Both are provable from what is already on screen, so the sentence is
identical with the setting on or off — verified live on the frozen fixture
board: with `errorHighlight` off, the coral underline and dot vanish, the coach
still lights **both** 7s in row 1 and still says "Two of these squares disagree",
and it never reveals which of them is the mistake.

The guarantee is a signature rather than a comment: **`BoardSpeech.coachSentence`
takes no `NineGame`**, and nothing in `Coach.swift` takes one either. There is
nothing for the solution to leak through even by accident.

The peer-clash check also closed a real gap. `CandidateState.init` zeroes
candidates for filled cells and never compares filled cells to *each other*, so
**two 7s in one row were invisible to the solver's state** — the coach would
have returned a confident, valid-looking step on a board that cannot be
finished. A coach that lies is worse than one that declines, so contradiction is
checked before `nextStep`, not after.

### Nothing new went inside `SolveStep`, `LibraryEntry`, or `NineMove.Kind`

Three separate applications of the same rule, and each would have been a quiet
disaster:

- **`CoachStep` wraps `SolveStep`**, carrying the `patternUnit` / `targetUnit`
  the sentences name. `SolveStep` lives in `GeneratedPuzzle.steps` and so inside
  the golden-corpus hash; a field that is nil on every classic board would have
  moved all 56 frozen hashes. Corpus ran 56/56 after every engine commit.
- **`CoachLedger` is a sibling top-level blob** (`nine.coach`), never a
  `LibraryEntry` field — the 1515 ms vs 49 ms finding in EXECUTING-A-PRD §2
  already settled that, and §2 names PRD-11's "hints used" as its example.
- **`applyAutoNotes` adds no `NineMove.Kind` case.** `Kind` is persisted inside
  every autosaved `NineGame`, `init(from:)` decodes `undoStack` without a
  `try?`, and builds 450/451/452 are already on TestFlight — an unknown raw
  value would throw and lose the board. A bulk fill is instead a `.pencil` move
  carrying many `PencilSnapshot`s; a toggle always carries exactly one, so the
  count discriminates them with nothing new on the wire.

  The dividend is worth naming: `undo()` already restores every snapshot
  regardless of kind, so **an older build undoes both a bulk fill and an
  auto-notes placement correctly, with no change at all.** A test pins it.

### The wand is a real mode, which is more than §2.2 asked for

§2.2 calls it a toggle but describes a one-shot. It could not have been one:
`place` already prunes the placed digit from peer marks, so "recompute after a
placement" is a no-op in isolation. **`erase` is where the mode earns its keep** —
it widens the candidate set, and nothing re-derived marks after it until now.

Consequences accepted deliberately:

- While on, marks are **replaced**, not merged. Hand-made notes are overwritten
  by the next placement. That is what "the marks are the machine's" means.
- **`Mark it` is suppressed while auto notes is on.** Its eliminations would be
  recomputed away one move later, and a button whose effect is erased that fast
  is a button that lies.
- The flag is per-board in `nine.coach`, not view state: a mode that silently
  stopped updating marks after a relaunch would be worse than no mode.
- Undoing the bulk fill also switches the mode off, or the next placement
  refills exactly what the player just took back.

### Verified by driving it, not by a green suite

`swift test` **1:52.98** wall, 0 failures (the budget is ~120 s; PRD-23 left it
at 112.5 s, and this PRD's tests are all sub-second — the movement is
machine mood, not new cost). iOS/tvOS/macOS builds green, Release archive green,
golden corpus 56/56, channel seal intact (`LogicSolver.advice` takes `context:`
as a defaulted parameter, so no app-layer file names `ConstraintContext`).

On an iPhone SE simulator, seeded with the frozen AX fixture: the coach found
the fixture's deliberate wrong 7 as a peer clash and lit both cells; on a
`--debug-fill` board it offered "Naked Single — Row 9, column 9 has one
candidate left: six", and `Place it` completed the board through the normal
path (Afterglow, "Solved", the PRD-34 "Another" chip). Auto notes filled 149
candidates with the chip to say so, and **one** undo took all 149 back and
switched the wand off.

### The AX lane is flaky at launch, and it is not this PRD's doing

Three of five `ax-snapshot.py --record` runs failed to capture `prefs`, twice
with `cannot tap 'Settings' — not in the tree` and once by silently recording
the game screen *over* the prefs baseline (105 → 87 elements, which is exactly
`game.txt`). Driving the app by hand showed the same thing from the other side:
the first `sim-use tap` after `simctl launch` was swallowed three times in a
row, on three different buttons.

So it is a launch-timing race in the harness, not a regression — a
`--only prefs` run against the same build captured the correct tree on the
first try. Two things follow for whoever hits it next:

- **Check the element count before trusting a `--record`.** A silent
  screen-for-screen substitution looks like a successful recording, and the
  count is the only thing in the file that gives it away.
- `--only <screen>` re-records one screen without risking the other four, and
  `Tests/AXBaselines/.captured/` holds the last capture, so a verified good
  dump can be promoted rather than re-rolled.

The drift itself is +2 buttons and nothing else, identical across `game`,
`game-quiet` and `prefs`: 85 → 87, 85 → 87, 105 → 107, with the 10/10/11
container counts unmoved — which is the proof the 81-cell board tree did not
flatten.

### Not done

- **No `moveLog` entry for auto notes.** `LoggedMove.Kind` carries the identical
  downgrade hazard (`decodeIfPresent` still throws on a present-but-unknown
  value), and there is no honest single `(cell, digit)` for a bulk fill. PRD-26
  is already adding `LoggedMove` v2 fields and should design the representation
  with a consumer in hand rather than have one guessed now. Consequence: a
  PRD-26 replay will show marks appearing without a cause.
- **`Mark it` applies eliminations one `togglePencil` at a time**, so each is its
  own undo entry. Eliminations are rarely more than three; the alternative is a
  second bulk-move helper in the engine.
- **No tvOS or macOS coach** (PRD-11 §3 non-goal — the band layout is iOS).
- **No sentences for the four variant techniques.** They fall to a `default:`
  returning "", because naming them in `Sources/Shared` would trip the PRD-23
  channel seal and they are unreachable on a classic board. PRD-24 adds them.
- **The coach is capped at the board's difficulty ceiling**, so a Gentle board
  that the player has made harder than Gentle can reach `.exhausted` and say
  "nothing at this board's level follows from here". That is honest but it is a
  dead end; PRD-25's "show me the next why" is where it stops being one.

## PRD-14 — the daily archive, and the checkmark that had nowhere to live (2026-07-26)

A month grid of every daily Nine has served, regenerated from `DailySeed`
rather than stored. The design doc is
[docs/superpowers/specs/2026-07-26-prd-14-daily-archive-design.md](../docs/superpowers/specs/2026-07-26-prd-14-daily-archive-design.md);
what follows is what a later reader needs and would not otherwise find.

### PRD-14 §2 sources the checkmark from three places, and none of them can hold it

The spec says solved days come "from `library.dailyEntry(day:)` + solve
records". Both were checked and neither works:

- **`BoardLibrary.prune()` caps solved+archived entries at 20** (`playedCap`)
  and evicts oldest-`updatedAt` first. The 21st archive solve silently erases
  the earliest checks — from the one view the feature exists to show, and
  "hundreds of hours of content" is PRD-14 §1's own pitch.
- **`SolveRecord` carries the *solve* date, never the puzzle's day ordinal.**
  That is deliberate and PRD-14 §2 asks for it, so the PRD-9 heat grid buckets
  by when you played rather than by what you played. It also means history
  cannot answer the archive's question at all, 200-record cap or no.
- **`StreakState` holds one `lastCompletedDay`,** not a set.

So `ArchiveLedger` is the one piece of new persisted state in this PR: a
sorted, deduplicated set of solved day ordinals in its own **cloud-synced
`nine.archive` blob**. Not a `LibraryEntry` field (EXECUTING-A-PRD §2's 1515 ms
vs 49 ms finding settles that), and not a sibling key of `nine.history` either —
`SolveHistory` is an ordered record array with a capacity prune and a
quarantine, and a set of ordinals shares none of that. The same call
`nine.coach` made one PRD ago, except cloud-synced: a checkmark is a property
of the player, not of the hand that earned it.

**A sorted `[Int]` rather than ranges, with the number written down so the next
person starts from a measurement:** one ordinal is five digits and a comma, so
ten years of unbroken daily play is ~3 650 entries ≈ **22 KB** against a 1 MB
KVS budget already carrying 200 history records. Range compression wins on the
contiguous case and *loses* on the alternating one, for real code and real
tests.

The launch backfill seeds the ledger from `streak.lastCompletedDay` and every
`.solved` `.daily` entry — `.solved` specifically, not `status != .inProgress`,
because `archiveEntry(id:)` archives *partials* too and an abandoned board is
not a solved one. It is idempotent, O(library), and self-healing when a solved
daily arrives later from CloudKit. **It cannot recover days the library pruned
before this build shipped.** Nothing can, and the alternative to saying so is
holes in the grid that look exactly like unplayed days.

### The past-day streak guard is a bug fix, not defence in depth

PRD-14 §2 files it under "defense in depth; TDD". It is neither optional nor
theoretical. `finishSolve` calls `recordCompletion` for **every** `.daily(day:)`
board, and that function's `guard day > last` only protects a player who
already has a streak — with `lastCompletedDay` nil it never runs:

```
fresh install → open the archive → solve yesterday
  → lastCompletedDay = yesterday, current = 1
  → displayedStreak(today:) reports 1
```

A one-day streak nobody earned, on the one number a streak app owes the player.
The guard is a `StreakState.recordCompletion(day:today:)` overload rather than
an `if` in `AppModel`, because `AppModel` has no test target and this is exactly
the rule that has to be provable. Verified live as well: solving 12 July from
the archive moved points 100 → 450 and left the shelf with no streak chip at
all, and the completion chip read "Solved" rather than "Solved · N day streak".

### The ordinal → seed inverse is exact, and the mapping is now frozen

`seed(forDayOrdinal:)` needs no calendar round-trip. `seed(for:)` hashes the
**local** y/m/d and `dayOrdinal` takes that same local y/m/d and reinterprets it
as a **UTC** midnight — so an ordinal already *is* the player's calendar day,
re-encoded, and reading it back in UTC recovers precisely the components that
were hashed. Pinned across GMT-8/+0/+5/+13 for 400 consecutive days.

Extracting the shared constant also surfaced a gap worth naming: **the daily
mapping had never been pinned absolutely.** Every daily Nine will ever serve and
every shared seed is `(day → seed) → puzzle`, and the only test guarding it
compared days *to each other* — it would have passed with the entire mapping
shifted by one. `testDailySeedForAKnownDayIsFrozen` now nails 12 July 2026 to a
literal. Golden corpus ran 56/56 after every engine commit.

### A day ordinal is a UTC midnight, and that is a rendering trap

Every formatter in `ArchiveCalendar` is pinned to UTC. Left on the device's own
timezone they render 12 July as "Jul 11" for every player west of Greenwich —
no crash, no warning, and invisible to anyone developing in UTC+0. The stability
sweep is unconditional; the English wording is a separate test that skips off an
English locale, because a Linux CI container's `Locale.current` is not the
developer's and a red lane over a month name says nothing true about the code.

### Progress and position are orthogonal, and a flat enum could not say so

The cell state started as five mutually exclusive cases (solved / inProgress /
today / unplayed / future) and could not represent **"today, and already
solved"** — which is what every player sees for most of every evening. Two axes
instead: the background renders position, the mark renders progress. Simpler and
strictly more informative.

That refactor paid twice, because it made `ArchiveDayState` and the
accessibility label pure. **The archive is the one screen that can never have an
AX baseline** — every label in it is derived from today's date and would rot
overnight, and `AXFixtureTests` can freeze a board but nothing can freeze
"today". So the wording is pinned in `ArchiveCalendarTests` instead, which is
the move PRD-19 already made for the Voice Control input labels no dump can see.
`home.txt` is re-recorded for the new button; no `archive` screen is added to
the lane.

The grid's one deliberate move: **a solved day loses its number.** The checkmark
takes the date's place rather than sitting beside it, so a month reads as a
record of what you have done rather than a calendar wearing badges. 44 pt cells
with 2 pt gaps is 320 pt against the 336 pt a 380-wide `GlassSheet` leaves — the
craft charter's touch floor fixes the cell size, not taste.

### Three defects that only driving the app could find

EXECUTING-A-PRD §5 says a green suite is not evidence that a reshaped surface
works. Three for three, none visible to `swift test`:

- **The Today card's accessibility element collapsed.** A `Button` nested inside
  `TouchCard`'s `Button` is merged by SwiftUI, and the merge takes the *inner*
  frame: `describe-ui` measured the card at **44×44** where the committed
  baseline has **89×129**, with the archive button absent from the tree
  entirely. Nothing on screen changes when that happens. Moving it to an overlay
  *on* the card rather than a button *in* it makes the two siblings, and the
  card's frame is byte-identical to the baseline again.
  **Worth knowing: the Continue card's discard ✕ is nested the same way and has
  the same defect** — its element is missing from `home.txt` too, and has been
  since it shipped. Left alone here; it is not this PR's surface.
- **The archive chip printed across the coach card's title.** The coach parks in
  the band directly beneath that `.top` overlay, which is why the timer chip
  already carries `coachAdvice == nil`. A chip that is up for the whole board
  has to yield to a card the player just asked for. For the same reason the
  ambient slot stands down — but only when the two would actually share the top
  band, not for every archive session.
- **The board tracker dated every archive board today, in two places.**
  `BoardsSheet.title` and `TouchUI.boardTitle` both read `entry.createdAt`
  instead of the `.daily(day:)` payload. Those were the same date for every
  board that could exist before this PR, so the bug was invisibly correct until
  the archive made them diverge: 13 July opened today listed as "Daily · Jul
  26". Both now read the day.

### What a review pass caught that driving the app did not

Three independent reviewers converged on the same defect, and it was mine:

- **A clock-based streak guard broke the ordinary path.** The first version read
  `recordCompletion(day: day, today: todayOrdinal)`, comparing the day the board
  was *composed for* against a clock read at the moment of the solve. Open
  today's daily at 23:55, place the last digit at 00:03, and `day >= today` is
  false — **a streak of any length silently resets on a night the player
  actually solved the puzzle.** Worse, `markSolved` on the next line still fired,
  so the grid showed a checkmark for a day the streak recorded as missed; the two
  ledgers disagreed permanently.

  **The discriminator is provenance, not the clock.** A board created on its own
  day is that day's daily however late it is finished; a board created *after*
  the day it is for can only have come from the archive. So the guard is
  `recordCompletion(day:openedOn:)` against `DailySeed.dayOrdinal(for:
  entry.createdAt)`, which needs no new state — `createdAt` has been on every
  `LibraryEntry` since the tracker shipped. `archiveDay` (and therefore the
  in-game chip) had the identical bug from the identical cause, and takes the
  identical fix: without it a board being actively finished grew an
  "Archive · Jul 25" chip the moment midnight passed under it.

- **The widget was the app's other solve path, and it was missed.**
  `ingestSharedDailyBoard` records streak, history, library and Game Center for a
  daily finished entirely in the widget, and wrote nothing to `nine.archive`. The
  fallback — the next cold launch's backfill reading `status == .solved` — is
  exactly the thing `ArchiveLedger` exists because you cannot rely on:
  `prune()`'s 20-entry cap can evict that entry first, losing the day for good.

- **A compose in flight could yank the player off an archive board.** The archive
  glyph is an overlay applied *after* `.disabled(...)`, so it stayed live during
  a foreign compose. Tap a past day with a partial and `startEntry` puts it on
  screen — then the pending `Task.detached` lands and calls `startEntry` again,
  unconditionally, replacing the board mid-move. Most reproducible on Sharp and
  Nocturne, where generation takes tens of seconds. `openArchiveDay` now refuses
  while `composing != nil` and the grid disables its cells for the same window.

- **The floor was a month where its own argument was about days.** Nine's first
  daily was 11 July 2026, but `ArchiveMonth(2026, 7)` made 1–10 July ordinary
  playable past days — boards for dates on which Nine served nothing, earning
  permanent checkmarks. `floorDayOrdinal` is the day, and `Position.beforeLaunch`
  renders those ten like future days: present so the month is a whole month,
  unplayable, and making no progress claim in speech. Verified live — July 1–10
  read `"July 3"` and disabled, July 11 reads `"July 11, not played"`.

- **`mediumLabel` would have re-rendered the tracker for non-Gregorian regions.**
  It replaced `entry.createdAt.formatted(date: .abbreviated)`, which honours
  `Calendar.current`; pinning the whole file to Gregorian would have left a
  Japanese- or Buddhist-calendar player's board row disagreeing with the
  `statusLine` directly beneath it. It is now the one label rendered in the
  player's calendar with the clock still pinned to UTC. The archive's own
  surfaces stay Gregorian, because the grid *is* a Gregorian month.

- **Cost, not correctness:** `DailySeed.utcCalendar` and `ArchiveCalendar`'s
  formatters were rebuilt per access on a path that touches them several times
  per cell — roughly 32 `DateFormatter` constructions and 130 `Calendar` builds
  per grid render, inside a `withAnimation` that wants the frame. The calendar is
  a `static let` now and the formatters are cached by template + locale +
  calendar. `state(of:)`'s `todayOrdinal` reads and its linear
  `inProgressDaily(day:)` scan are hoisted out of the 42-cell loop, and
  `newestMonth` no longer allocates a month-per-element array to take its last
  element.

**The lesson worth keeping:** every one of these is in code that a green suite
and a full hands-on pass had already blessed. The streak bug in particular is
invisible for 23 hours and 50 minutes of every day.

### `swift test` is 0 failures; the wall clock is not measurable right now

252 tests, 3 skipped, 0 failures — but **342 s and 520 s across two runs** against a ~120 s budget, on a
machine at **load average 189 and climbing** (several agents in parallel worktrees). The
number is contention, not cost, and the cheapest proof is that the golden
corpus read **14.7 s standalone** in the same session and **50.8 s** inside that
run — a ~3.5× factor that applies uniformly across the three expensive suites
(`testGenerationSoakAcrossDifficulties` 167.8 s against its recorded 60 s,
`testGenerationIsDeterministic` 66.1 s against 24 s). **This PR's own cost is
27 tests in 0.035 s.** Whoever needs real headroom should still start with the
25-puzzle soak, exactly as the Phase 0 entry has said since.

### Not done

- **The PRD-9 heat-grid tap seam** (PRD-14 §4.4, "wired if PRD-9 is merged").
  `HistorySheet.swift` is iOS + macOS + tvOS and the archive sheet is iOS-only,
  so wiring the tap means either a platform-gated tap in shared code or a sheet
  opening a sheet — against the one-secondary-surface rule. Documented instead,
  which §4.4 explicitly allows.
- **No tvOS or macOS archive** (PRD-14 §3 non-goal). Both still show archive
  boards in their board trackers as ordinary `.daily` entries, correctly dated
  now.
- **No per-day stats and no calendar-app integration** (PRD-14 §3 non-goals).
- **Nothing to delete.** PRD-14 §4.4 asks for `ArchiveDemo` + its flag to go;
  PRD-18 already deleted the entire `-uxdemo` rig, so `UXDemoScenes.swift` does
  not exist on `main`.
- **The archive floor is a constant, not a preference.** `ArchiveMonth(2026, 7)`
  — the month Nine's first daily existed. `DailySeed` will happily seed 2019,
  but a day before Nine shipped was never anybody's daily, and offering it is
  content dressed as history.
- **Points still carry the daily bonus and the current streak multiplier on an
  archive solve** (PRD-14 §2 asks for "record normally"). A player working
  through the archive during a long streak banks more than one starting fresh.
  Left as specified rather than quietly changed — but §2 wrote that clause
  before the archive existed to test it, and a reviewer found the consequence it
  did not anticipate: `SolveRecord.isDaily` feeds three other consumers, not just
  points. `SolveHistory.solvesByDay` sets `DaySolves.hasDaily` for the *solve*
  date, so an archive solve lights the PRD-9 heat grid's daily marker on a day
  the real daily was never opened, and `GameCenter.reportSolve` submits it as a
  daily. **Whoever revisits this should start from `isDaily` being one flag doing
  four jobs**, not from the points formula.

## PRD-12 + PRD-13 — the gift and the held streak (2026-07-26)

Two small PRDs in one PR because they share `TouchUI.swift` and EXECUTING-A-PRD
§7 allows one owner of that file at a time. The plan is
[docs/superpowers/plans/2026-07-26-prd-12-13-share-and-grace.md](../docs/superpowers/plans/2026-07-26-prd-12-13-share-and-grace.md);
what follows is what a later reader needs and would not otherwise find.

### PRD-13 §2's two rules contradict each other, and the chip is where it shows

§2 gives the bridge rule and the display rule independently:

- grace applies iff `lastGraceDay == nil || lastCompletedDay > lastGraceDay + 1`
- `displayedStreak(today:)` shows the streak while `last >= today - 2`

Compose them at the state where the bridge is already spent — `lastCompletedDay
== lastGraceDay + 1` — and the shelf shows "12 day streak" through the silent
day, the player solves, and **the chip flips to 1**, because non-stacking
refuses the second bridge. The app would punish them at the exact instant of
success. That is the churn cliff PRD-13 exists to remove, moved one day later
and made worse by being a surprise.

So the display window is gated on `graceAvailable`. The consequence is that a
player whose bridge is spent sees the chip lapse quietly a day earlier than §2's
wording implies — which is also the kinder behaviour, because nothing announces
it. **`swift test` cannot catch a rule that is individually correct and jointly
wrong**, so the property is pinned directly:
`testTheChipNeverPromisesAStreakTheNextSolveWouldBreak` sweeps all sixteen
two-completion gap pairs and asserts that a nonzero chip never precedes a solve
that shortens the chain.

The invariant that makes this cheap is that `standsOnGrace == !graceAvailable`
**exactly**: a bridge leaves `lastCompletedDay == lastGraceDay + 1`, and the
next natural completion makes it `> lastGraceDay + 1` in the same move that
re-earns the grace. One predicate therefore drives the bridge rule, the display
window, the shield glyph and the card, and the four cannot disagree.

### `lastGraceDay` is on `StreakState`, and the downgrade is unpreventable

EXECUTING-A-PRD §2 bans new fields on `LibraryEntry` — an *element inside* a
container. `nine.streak` is a blob whose **root** is `StreakState`, so the rule
does not reach it, but the hazard partly does: builds 450/451/452 are on
TestFlight with a *synthesized* decode, so a downgrade strips `lastGraceDay` on
its next write no matter what this build does. `carriedTopLevel` protects
against *future* keys, not past builds.

The consequence is bounded and it errs kind — a returning player is offered one
bridge they had already spent — and it is pinned by
`aDowngradeStripsTheBridgeAndErrsKind`. The alternative considered was a
separate `nine.grace` blob, which a downgrade genuinely could not touch. It was
rejected because it cannot be written in the same flush as the streak it guards,
and **two ledgers that disagree about one streak is the bug PRD-14 shipped a fix
for** — its clock-based guard left the archive grid checkmarked for a day the
streak recorded as missed, permanently.

While adding the field, `StreakState` also gained a hand-written tolerant decode
it should have had all along. It had synthesized `Codable`: one malformed byte
threw, `CouchStored` discarded the blob, and the player's streak silently reset
to zero.

### The widget had a *third* copy of the streak rule, and PRD-13 made it wrong

`WidgetSnapshot.displayedStreak` is a deliberate duplicate with a cross-check
test, so it was found immediately. `BoardIntents` had a second, hand-rolled copy
for dailies finished entirely inside the widget, with no test at all — found
only by grepping `lastCompletedDay`. Solve in the widget after one missed day
and it reset the streak to 1 while the app's next ingest bridged it back to 13:
**the widget would have been the app's one streak-shaming surface**, on the
screen a player is least likely to look at twice.

It is `WidgetSnapshot.recordOptimisticSolve(day:)` now, driven against the
Engine across every gap in a test rather than written out a third time. The
lesson generalises: a duplicated rule is safe only when a test drives both
copies from the same input — the copy with the cross-check survived PRD-13, the
copy without it did not.

`currentSchemaVersion` deliberately did **not** move. `WidgetSnapshotStore.load`
rejects `schemaVersion > current`, so a bump blanks the widget rather than
degrading it; an additive optional field decodes to nil on a pre-grace file,
which reads as "a bridge is there" — the same answer a fresh install gives.

### The shield replaces the flame rather than joining it

PRD-13 §3 asks for a chip that "gains" a `shield.lefthalf.filled`. `GlassChip`
renders exactly one `systemImage`, and both ways to obey the wording are worse:
a badge overlaid on a capsule clips at the top Dynamic Type sizes, and a second
chip beside the first is the accretion the anti-bloat constitution exists to
refuse. Replacing reads truer anyway — the flame is the streak burning, the
shield is the streak being held — and the header keeps exactly the width it had.

The four call sites that had grown the same chip literal (iOS, tvOS and macOS
headers plus the iOS ambient slot) now share `StreakChip`. Its label is
`BoardSpeech.streakChip`, because unlabelled VoiceOver reads the SF Symbol's own
name — "shield, left half filled, 12 day streak" — announcing a mechanic the
covenant says does not exist. A test bans `shield`, `remaining`, `left`,
`missed`, `lost` and `danger` from that string.

### The card is a chrome with a slot, because PRD-26 is going to fill it

PROGRAM-2.0 commits the 5-second comet loop to becoming this card's animated
body. So `ShareCard` is generic over its centre, `ShareCardMetrics` owns the
body's side and the margins around it, and `SolvedGridThumb` is merely what
fills the slot today. Swapping in a comet is a call-site change: no caption
moves, no margin is re-derived, and still and loop are laid out by the same code
because they are laid out by the same type.

`SolveCardFacts` is the other half of that seam — a pure value in
`Sources/Shared`, Linux-tested beside `BoardSpeech`, holding every word the card
says. The card leaves the app as a PNG and is then seen only where nobody here
can correct it, so its captions are pinned rather than previewed once; PRD-26's
debrief is captioned from the same value, so the still and the loop cannot
drift.

Deliberately **not** `BoardView`: the live board carries the Afterglow's Metal
pipeline, the rose, selection, error state, pencil marks and 81 accessibility
children, none of which survives being flattened to a PNG. Fixed 1080×1350 at
`scale = 1`, so the file is identical on every device and at every Dynamic Type
setting — a share card is a picture, not a screen, and must not reflow.

### Two defects only driving the app could find, on one feature

EXECUTING-A-PRD §5 again, and this time the artifacts actively lied: the PNG was
on disk, correct, 1080×1350, while the button to reach it was not on screen.

- **The `@State` read was inside `TimelineView`'s escaping content closure.** It
  therefore captured a snapshot of the view struct from before the render landed
  ~70 ms after the solve. Instrumented, the renderer logged `assigned,
  shareCard=set` **once** and the button logged `shareCard=nil` on all **30**
  subsequent evaluations. The card is now read in the body and passed into the
  closure as a parameter. The pair of logs is what localised it — one alone
  reads as a render failure or a UI failure; both together name the read.
- **A 2.4 s `Task.sleep` inside `.task(id: model.solvedAt)`**, so the render
  would land after the Afterglow. `Task.sleep` returns immediately on
  cancellation, so any view churn in that window left `shareCard` nil with no
  restart to repair it — the button then never appeared for that solve. It is a
  synchronous `onChange` now, **measured at 38–70 ms** for the full
  1080×1350 pass. The wait was never buying anything: the button lives inside
  the completion chip's own `> 2.4 s` gate, which was already doing the work the
  sleep was credited with.

Both are invisible to a green suite, to three clean platform builds, and to
reading the code. A feature that works four times in five is worse than one that
is absent, because nobody can report it.

### The AX lane does not cover either new element, and says so

`ax-snapshot.py` reports **all five trees matching their baselines** — not
because nothing was added, but because neither new element is reachable in the
states the lane captures: `game.txt` is a partially-filled fixture board, never
a solved one, so the completion chip and its share button do not exist; and the
lane's streak is unbridged, so the grace card does not either. No baseline was
re-recorded, and the count is the proof that nothing else moved.

Extending the lane means a sixth seeded state (a solved board) and a seventh
(a bridged streak). Worth doing when something else needs a solved-board tree;
not worth a fixture rig on its own here, where both surfaces were driven by hand
in both themes instead.

### Numbers

`swift test`: **278 tests, 3 skipped, 0 failures.** 111 s wall at load average
2.31 and 135 s at load 7.96, same tree — which is the contention factor showing
up again on a quiet machine, and worth setting beside PRD-14's 342 s and 520 s
at load 189 for whoever next reads a slow number as a cost. This PR's own tests
are all sub-second. Golden corpus
**56/56** after every engine commit. iOS, tvOS and macOS builds green; iOS
Release archive green. Share-card render **38–70 ms**, iPhone 17 Pro simulator,
Debug.

### Not done

- **No tvOS share.** There is no share sheet on tvOS (PRD-12 §3). The card
  itself is unfenced and compiles there, so PRD-26's ambient screensaver
  inherits it.
- **No tvOS or macOS grace card.** Both wear the shield glyph; the one-time card
  is iOS-only, per PRD-13 §3's scoping to the home shelf.
- **The share sheet's preview thumbnail is generic.** Passing
  `SharePreview(_:image:)` was tried and reverted while chasing the bug above —
  it turned out to be innocent, but by then the button was fixed without it and
  re-adding it is a change with no evidence behind it. `ShareCardExport` still
  carries the rendered `Image`, so it is one argument away.
- **Nothing to delete.** PRD-12 §4.3 and PRD-13 §5.3 ask for `ShareCardDemo` and
  `ShieldDemo` to go; PRD-18 already deleted the entire `-uxdemo` rig, so
  `UXDemoScenes.swift` does not exist on `main` (`git show a18cbe3:` restores
  it).
- **No `nine.graceSeen` pruning.** It is one `Int` and PRD-13's non-stacking rule
  guarantees one live bridge at a time, so there is nothing to grow.
- **The header streak chip is a 102×16 AX element**, below the craft charter's
  44 pt floor. Pre-existing on every `GlassChip` in the header and not this PR's
  surface; it is non-interactive decoration, but it is worth a sweep with the
  points chip beside it.
