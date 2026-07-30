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
  **Resolved 2026-07-30 — by delivery, not by expiry.** PRD-24 shipped both
  channels and deleted the card almost three months early. It promised they would
  "simply appear here"; where it stood is now the pager rail that turns the page to
  them. Its three strings went with it, because the audit reports a dead string as
  a string translators are paid for.
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

---

## PRD-16 — Appearance+, and the accent that could not be placed (2026-07-26)

Three dark themes (Ember, Tide, Mono), two accents, three alternate iOS icons.
No locks, no counters, no unlock order — every one of them is available on first
launch, which is the whole covenant claim this PRD makes.

### The palette became a contract, and it earned that on its first run

PRD-16 §5 asks for a *manual* check that coral and the accents stay legible on
the three new themes. That was written before anyone had the numbers, and the
numbers turned out to be the interesting part, so the check is a test instead:
`Tests/EngineTests/AppearancePaletteTests.swift`. It cannot link `ThemeChoice`
— `Package.swift` covers Engine and Shared only, because Lane 1 is Linux — so it
follows the two patterns already in this repo for that situation: the numbers
live in the test as a table, a source-literal check fails if `AppModel.swift`
disagrees with it (the `VariantChannelSealTests` shape), and the properties are
asserted on the table.

Both floors were proven to fire before being trusted, which is the only reason
to believe them:

- The contrast floor fired **on its first run against unmodified code**, finding
  **crimson on blueprint at 4.23:1** — a shipped sub-AA pair four releases old.
  It is grandfathered by name and *pinned* to 4.23 rather than waved through by a
  lowered floor, so it cannot quietly widen and a second such pair reads as a
  regression rather than a precedent.
- The separation floor was fired deliberately, by adding the periwinkle this PRD
  went on to reject: **ΔE 2.07 against Lilac under protanopia**, against a
  palette floor of 5.98.

### Indigo could not be placed, and Blueprint is why

The obvious ninth accent is a periwinkle in the glacier→lilac hue gap. It cannot
exist. Blueprint's ground is a saturated dark blue, so every escape route breaks
the other constraint:

| Candidate | Blueprint | Worst ΔE |
|---|---|---|
| `(0.30, 0.49, 1.00)` | **4.08** — worse than the shipped exception | 7.48 |
| `(0.42, 0.58, 1.00)` | 5.24 | **5.04** vs Lilac |
| `(0.45, 0.60, 1.00)` | 5.54 | **2.05** vs Lilac |
| `(0.35, 0.58, 0.88)` | 4.85 | 7.88 — *but its nearest neighbour is Glacier* |

Every value between hue 214 and 242 that clears both constraints is a second
Glacier. **A hue gap on the wheel is not a usable gap once the grounds are
fixed.** So Moss (hue 85) fills gold→meadow and Orchid (hue 328) fills
magenta→crimson; both clear AA on all six dark grounds (Moss 8.94–12.46:1,
Orchid 5.03–7.01:1) and the palette's worst pair is unmoved at ΔE 5.98 — still
Meadow/Teal under tritanopia, as it has been since 1.1.

Orchid does crowd the pink corner: Magenta 297°, Orchid 328°, Crimson 340°. That
was a considered trade against shipping one accent instead of two, and the
crowding is measured — 7.80 ΔE at worst — so it reads busy to normal vision and
stays separable to everyone else.

### Alternate icons: no entitlement, and the artifact that says so

Asked to confirm before merging. The answer is **no entitlement, no App ID
capability, no `match` re-mint**, and it is three artifacts rather than a claim:

1. `git diff origin/main` touches none of the four entitlements files, and
   `Nine-iOS.entitlements` is byte-identical.
2. No added `project.yml` line names an entitlement or capability;
   `CODE_SIGN_ENTITLEMENTS` and `PROVISIONING_PROFILE_SPECIFIER` resolve
   identically on both refs.
3. The **complete** built-`Info.plist` diff between `origin/main` and this branch
   is two `CFBundleAlternateIcons` dictionaries (iPhone and `~ipad`) and nothing
   else — saved at `.context/prd16/info-plist.diff`.

A `.xcent` comparison was attempted first and abandoned honestly: Xcode emits no
`.xcent` when `CODE_SIGNING_ALLOWED=NO`, and an absent artifact is not a passing
test.

### Both asset-catalog settings are required, and the failure is silent

`ASSETCATALOG_COMPILER_ALTERNATE_APP_ICON_NAMES` alone does nothing.
`actool` ignores it without a warning: three green platform builds, the setting
resolving correctly in `-showBuildSettings`, the icon sets sitting in the
catalog — and no `CFBundleAlternateIcons` in `Info.plist` at all, so
`setAlternateIconName` would have failed on a device and nowhere else.
`ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS` is what makes `actool`
compile the non-primary sets. Both are scoped to the iOS SDKs; tvOS keeps its
layered brand asset and macOS keeps `AppIcon-macOS.icns`, verified in the built
bundles.

This is EXECUTING-A-PRD §5 in one setting: **a green build proved nothing here,
and `plutil -p` on the artifact was the only thing that disagreed.**

### The icon's state has one owner, and it is the system

Nothing about the chosen icon is persisted. `UIApplication.alternateIconName`
already survives launches and updates and is what Springboard draws, so a mirror
in `NinePrefs` would be a second copy that can disagree — a prefs downgrade
would reset the stored value while the Home Screen kept the icon, with no honest
reconciliation. Prefs are not `cloudSynced`, so the mirror buys nothing either.
Driven, not asserted: tapping Ember produced the system's own alert, Springboard
showed the rust icon, and after terminate-and-relaunch the row still read Ember.

### Numbers

`swift test`: **289 XCTest + 79 swift-testing, 3 skipped, 0 failures**, 136 s
wall at load average **16.81** — set beside DEVIATIONS' existing 111 s at load
2.31 and 135 s at load 7.96 for the same tree before reading it as a cost.
Golden corpus **56/56** after every commit. iOS, tvOS and macOS builds green;
iOS Release archive green with the alternates intact. New themes measured:
digits 15.02–15.62:1, grid 12.95–14.16:1, coral 6.37–6.94:1 — every one above
the floors Blueprint set (12.41 / 10.45 / 5.64).

### Not done

- **The AX lane lost coverage of the accent swatches.** The taller theme row
  pushed them from y=846 past the 874 pt screen edge, so the eight existing
  accent buttons dropped out of `prefs.txt` and the ten new ones and four icon
  swatches never enter it (107 → 102 elements). The row's label and value are
  still pinned, so its existence is covered; the individual swatches are not.
  Fixing it means teaching the lane a scrolled prefs state, which is PRD-19's
  harness. They were driven and read by hand instead.
- **The palette test measures raw theme constants, not the composited glass.**
  The board draws these under a plane that lifts the void, and that gap is the
  entire reason PRD-22 exists. A green run means "no worse than what shipped",
  never "the board meets contrast". PRD-22's 96-cell screenshot harness is still
  unstarted, and now has crimson/blueprint waiting for it.
- **Light-theme coral is untouched.** Paper 2.28:1 and Camel 1.32:1 are
  pre-existing and belong to the same PRD-22 retune. No new theme is
  light-leaning, so this PR neither improves nor worsens it.
- **No `ThemePacksDemo` to delete.** PRD-16 §4.4 asks for it; PRD-18 removed the
  entire `-uxdemo` rig on 2026-07-25. The prototype is one command away:
  `git show a18cbe3:nine/Sources/App/UXDemoScenes.swift`.
- **`PrefsSheet.swift` still holds bare string literals**, not a `Phrase` block.
  The new rows match the file rather than starting a second convention inside
  it; PRD-20 converts the file as a unit.
- **No `downgrade-drill.sh` run.** That script is pinned to PRD-17's
  `Difficulty.nocturne` and refuses to run against a tree that already has the
  case; the prefs equivalent is in-process only. The blast radius is a single
  local field on a non-synced blob, which is why that was judged enough.
- **No tvOS or macOS alternate icons** (unsupported), and no seasonal icons.

## PRD-22 — the lens, and the number the palette test could not see (2026-07-26)

The expensive two-thirds PRD-22's fingerprints half left behind: contrast
measured on the *composited* glass by an automated screenshot-sampling harness,
the retune that measurement demanded, an `accessibilityContrast` hairline board,
the tutorial routed through the theme system, and the rose's petals made true
glass by a third Metal shader on the board Canvas's existing pipeline.

### The board never drew the colours the palette test was measuring

`AppearancePaletteTests` computes contrast against `ThemeChoice`'s declared
`background`. `scripts/contrast-harness.py` screenshots the running app and
samples the pixels. Solving the two box-wash opacities in `BoardView.draw` back
out of nine per-box grounds recovers the plane the board actually sits on, and
the nine boxes agree to within a level:

| theme | declared background | what reaches the board |
|---|---|---|
| Void | (0, 0, 0) | **(19, 19, 19)** |
| Paper | (240, 237, 230) | (247, 245, 238) |
| Camel | (204, 178, 140) | **(250, 230, 200)** |
| Blueprint | (13, 36, 84) | (17, 33, 67) |
| Forest | (13, 33, 23) | (20, 34, 27) |
| Ember | (36, 13, 8) | (39, 23, 19) |
| Tide | (5, 31, 36) | (14, 33, 36) |
| Mono | (28, 28, 31) | (29, 29, 32) |

`couchGlass` is a *material*, so what it draws is dominated by the system's own
glass and only tinted by the colour behind it. Void's true black arrives as 7%
grey; Camel's tan arrives nearly white. **Mono barely moves**, which is the
control that says the model is a model and not a fudge — Mono's declared ground
is already the material's own luminance.

The ink, by contrast, is exact. Void's givens sample as `(237, 229, 214)`, which
is `CouchPalette.paper` × 255 to the byte, because `.glassEffect` renders glass
*behind* its content and the Canvas draws on top at full alpha. So only the
ground is composited — which is what made the retune solvable arithmetically
instead of by thirty-minute trial and error.

### What the harness found on its first run, against unmodified code

| | measured | floor |
|---|---|---|
| Camel entries (Glacier) | **3.36:1** | 4.5 |
| Paper entries (Ember) | **3.04:1** | 4.5 |
| Camel coral | **1.92:1** | 3.0 |
| Paper coral | **2.10:1** | 3.0 |
| Crimson on Blueprint | **3.88:1** | 4.5 |
| Givens, every theme | 10.26–13.16:1 | 7.0 |

PRD-16 shipped exactly one grandfathered sub-AA pair — crimson on blueprint at
4.23:1 on the raw constants — and handed it to PRD-22 by name. On the surface
the board actually draws, that pair measured **3.88:1**, and it was not alone.
Modelling the other five dark grounds from their recovered planes put Forest at
4.04, Tide 4.09, Mono 4.13 and Ember 4.25 — only Void cleared, at 4.52
measured. So the exception PRD-16 recorded as one pair was **five**, and the raw
number was never the number. (The model is the one validated below to within
0.15 against measurement; `Tests/ContrastBaselines/matrix.txt` is the measured
record for every cell.)

### The retune is solved, not tuned

Every value below was derived from the measured planes and then verified by
re-measuring, rather than nudged until it looked right.

- **Crimson moved to (1.00, 0.36, 0.56).** That is the *closest* value to the
  shipped tint — CIE76 ΔE 5.84 — that clears 4.5 on Blueprint, which is the
  binding ground for all ten accents, without becoming the palette's new worst
  dichromat pair. The obvious brighter candidate, (0.98, 0.40, 0.58), reads 5.16
  on the worst dark theme and collides with **Orchid under tritanopia at ΔE
  3.77** against a floor of 5.9. PRD-16 built that floor to catch exactly this,
  and it caught it on the first candidate tried. The palette's worst pair is
  unmoved at 5.98 — still Meadow/Teal under tritanopia, as it has been since 1.1.
- **All ten light-ground accent variants were deepened** to a relative-luminance
  ceiling of 0.098, solved from Camel's composited ground (the worse of the two
  light themes). Every one of them was below AA: Glacier measured 3.36 on Camel
  and 3.67 on Paper, Ember 3.04 on Paper. Gold moved furthest — (0.76, 0.53,
  0.02) → (0.46, 0.32, 0.01) — from a modelled 2.24:1, the palette's worst cell
  anywhere.
- **Coral became a theme tone.** It had been one constant on `BoardView` since
  1.0 and had never been checked against a light ground. `ThemeTones.coralOnLight`
  is (0.72, 0.13, 0.06): 1.92 → 4.65 on Camel, 2.10 → 5.07 on Paper.
- **`ThemeTones.plane`** puts a measured amount of the theme's own ground back
  under the board, between the glass and the Canvas.

### The plane is zero on light themes, and that is the measurement talking

The obvious symmetric move — wash every theme's ground back under its board —
is wrong, and the harness is why anyone would know. Every mark a light theme
draws (givens, accents, coral) is *darker* than its ground, so restoring the
ground lowers its luminance and costs contrast on all three at once. A 0.58
wash on Camel moved givens **10.28 → 8.15** and bought nothing. Light themes are
fixed by deepening the ink instead.

Blueprint is the same lesson in reverse and is the one theme with a `plane`
override. Its backdrop is a saturated blue that reads well full-bleed and is
*lighter* than the composited glass, so the default wash made it worse (crimson
3.93 → 3.79). Blueprint's backdrop and Blueprint's board ground are two
different jobs, and now two different values.

### The lens: nine centres derived, not passed

`rosePetalLens` is the third `[[stitchable]]` function on the board Canvas's
existing pipeline. It takes five uniforms — ring centre, pitch, radius,
magnification, bloom — and derives the nine petal centres itself by rounding
into the 3×3 grid, because the ring *is* rigid and nine passed centres would be
nine chances for the bend to drift from the paint. The core magnifies uniformly
and the outer quarter compresses hard; that compressed rim band is what makes
glass read as glass rather than as a zoom.

`FlickRoseView` drops `.couchGlassInteractive` for a rim and a glyph when the
lens is live, which is the 1.1 audit's finding closed ("rose petals are opaque
`.glassEffect` discs, not the PRD's true glass petals lensing the board
beneath"). **Reduce Motion keeps today's material at every one of the six call
sites**, and `BoardView.lensActive` checks it a second time.

Two deliberate departures from PRD-22's literal wording, both in the same
direction — fewer things that can disagree with each other:

- The PRD asks for "9 centers + radius + magnification uniforms". The centres
  are *derived* instead, from the same ring pitch `RoseLens` hands the petals.
  Nine passed centres are nine chances for the bend to drift from the paint, and
  the ring is a rigid 3x3 grid by construction; componentwise rounding into it
  finds the nearest petal exactly, at one rounding rather than nine distance
  tests.
- The PRD says "SwiftUI draws only glyphs and rims above". There is also a
  10%-alpha body, because a glyph with nothing behind it over a bright board
  cell is a glyph you cannot read, and the harness's petal column is where that
  shows up. It is a breath, not a disc — the board is plainly visible bending
  through it in `.context/prd22/rose-lensed.png`.

The rim's compression was tuned down before it shipped, and a screenshot is why.
The first version ran `smoothstep(0.74, 1.0)` to a 1.85 squeeze, and a board
digit caught in a band that wide and that steep smears into a double image —
an artifact rather than glass, and a board that asks for attention under your
thumb is the thing the idle-pixel test exists to stop. It ships at
`smoothstep(0.80, 1.0)` to 1.42. That number and `lensMagnification` are the
only two in this PRD set by taste rather than by measurement, and they are
adjacent on purpose.

### One value now owns the rose's geometry

The bend has to land exactly where the petal is drawn, and the placement
arithmetic was six copies: `TouchUI`, `MacUI`, `FirstRun`, `TutorialView` twice
and `GameScreen` each recomputed `126 * scale`, the `184 * scale` clamp and
`centre + inset` by hand. `Sources/Shared/RoseLens.swift` is the one copy, in
the Linux-clean tree so Lane 1 tests it without a simulator — the `BoardSpeech`
pattern. Consolidating found a latent disagreement: iOS clamped the rose for the
eraser using `pencilMode` while it *drew* the eraser using `rose.pencil`, so a
rose opened before a pencil toggle reserved space for a petal it was not showing.

### The hairline board made contrast worse, and only the second column said so

The first `accessibilityContrast` variant *deepened* the box washes — more
separation between the boxes is more contrast, obviously. The harness measured
every Increase Contrast cell coming out **below** its standard twin: Void
14.72 → 13.62, Paper's coral 5.06 → 4.43, Camel's 4.63 → 4.50. The setting that
exists to help was hurting, on all eight themes, and nothing on screen said so —
the board looked *more* structured, which is what made it convincing.

A box wash is a wash toward `gridTone`, and `gridTone` is the ink's end of the
scale on a dark theme and the ground's on a light one. Either way it drags the
ground toward the digits and every ratio in that box falls. The mode that asks
for more contrast has to **remove** the wash, not thicken it, and let the box
*borders* — which is what "hairline variant" meant all along — carry the
structure the step was standing in for. With both washes at zero:

| | standard | Increase Contrast |
|---|---|---|
| Void givens | 14.72 | **16.48** |
| Paper givens | 11.42 | **13.45** |
| Camel coral | 4.63 | **5.77** |
| Blueprint entries | 6.80 | **7.73** |

That invariant is a gate now, not an observation: `gate_increased` fails the run
if any increased cell reads below its standard one. Recording a number does not
make it true, so `--record` runs it too and refuses to bless a regression.

### Three things that only measuring could have found

1. **A blank launch screen is both "changed" and "stable".** The harness's first
   readiness check was change-then-settle, and on its fourth cell it photographed
   a white window, printed a row of dashes, and was believed. `drawn()` — a
   strided luminance-spread test — is the fix, and a missing column is now a
   hard failure rather than an em dash, because the frozen board has givens,
   entries and a wrong digit by construction.
2. **The tap gets dropped.** On a machine at load 258 `sim-use tap` intermittently
   does not open the rose, and "did the ring change" cannot tell that from a
   cursor move — both change pixels. `moved()` thresholds at 15% of the ring,
   which a rose exceeds and a cursor does not.
3. **Pixel-stability was the wrong stability.** The interactive glass never
   settles frame to frame, so a resting rose "never stopped changing"; the retry
   that provoked then tapped an *open* rose, closed it, and measured the board's
   digits through the petal frames as 2.21:1. The gate is now on the
   measurement, not the pixels: the median petal ratio has to come out the same
   twice. Median, not minimum — *which* petal is worst flips between frames, and
   two readings of a perfectly stable rose came out 14.40 and 15.21.

### The macOS tutorial was reading the wrong theme, and had been

`.environment(\.nineTheme,…)` writes into the modified view's subtree, and an
overlay's content is a sibling of that view rather than a descendant. The Mac
tutorial is attached with `.overlay` *after* that write in `NineApp`, so it and
the `BoardView` inside it were reading `NineThemeKey.defaultValue` — `.auto`.
With Camel selected the app is light-pinned, `.auto` resolves to Paper, and the
tutorial drew a Paper board inside a Camel app. iOS and tvOS were never affected;
their hosts are themselves descendants of the write.

### 96 is not 96

PRD-22 says "6 themes × 8 accents × light/dark". That was written before PRD-16
shipped Ember, Tide and Mono and the Moss and Orchid accents. The shipped matrix
is **8 concrete themes × 10 accents = 80 composites**, doubled to 160 by the
Increase Contrast pass. `auto` is not a cell: `ThemeChoice.tones(for:)` delegates
it to Void or Paper by construction, so measuring it would photograph one of
those twice and report the matrix as larger than it is. Light and dark are both
covered — by Paper and Camel, and by the six dark themes.

### Numbers

The retune, measured on the composited glass before and after:

| | before | after | floor |
|---|---|---|---|
| Void givens | 13.02 | **14.72** | 7.0 |
| Void entries (Crimson) | 4.52 | **6.30** | 4.5 |
| Void coral | 6.11 | **6.91** | 3.0 |
| Paper entries (Glacier) | 3.67 | **5.59** | 4.5 |
| Paper coral | 2.10 | **5.06** | 3.0 |
| Camel entries (Glacier) | 3.36 | **5.11** | 4.5 |
| Camel coral | 1.92 | **4.63** | 3.0 |
| Void petal glyph | 14.99 | 12.31 | 4.5 |

The petal column *fell* and that is the change working: the opaque disc is gone,
so the glyph is now measured against the board bending underneath it rather than
against a frosted plate. 12.12 is still 2.7× the floor.

The predictive model built from the recovered planes reproduced the measured
board to within **0.15** on every cell it was checked against, and to within
0.02 on the two that mattered most — Camel coral predicted 4.65 / measured 4.63,
Camel entries 5.05 / 5.11; Void givens 14.84 / 14.72; Camel givens 10.28 /
10.26. That agreement is why the retune could be *solved* once rather than
searched for at twenty minutes a guess, and it is the whole return on having
recovered the planes instead of nudging constants.

Harness cost, and the load it was measured at, because a number without one is
not a number: **20.7 s per cell** at load average 16, **~110 s per cell** at load
average 260 with five other agents on the same machine. `describe-ui` is the
expensive call and the harness now makes exactly **two per run** rather than four
per cell — the board's 81 frames and the ring's ten do not move between cells.

### Not done

- **No tvOS or macOS contrast lane.** `describe-ui` is iOS-only, and every
  sample rectangle in the harness comes from an accessibility frame. The TV
  board is a fixed 900pt plane so its geometry could be hard-coded instead, but
  a lane that cannot classify its own cells is not the same instrument.
- **The light variants' dichromat separation is pinned, not fixed.** They have
  never been under `separationFloor`; measured, the shipped set's worst pair was
  ΔE **1.44** (glacier/lilac, deuteranopia). Deepening them for AA compresses
  the palette further in principle and in fact improved it, to 3.17. That is
  better and still well short of the vivid palette's 5.98. Closing it is a
  palette redesign — the vivid set needed two accents rejected to hold 5.9 — and
  it is not a contrast retune.
- **The tvOS rose is still unclamped.** The audit found it can hang 156pt past
  the board edge on a corner cursor, where the lens has nothing to bend. Both TV
  call sites build their `RoseLens` with `clamped: false`, which reproduces
  today's placement exactly. Moving where the ring blooms is a UX change and
  PRD-22 is a rendering change; it belongs with the TV's IA pass.
- **The petal column cannot separate the petal's glyph from the board's.** With
  no opaque disc there is nothing to tell them apart, so on a petal over dense
  givens the measured ink may be the magnified board digit. It is a floor on
  legibility rather than a measurement of the glyph — wrong in the safe
  direction, and not the same claim.
- **`--rose-all` is not what CI runs.** The petal column is measured once per
  theme, on that theme's first accent, because the glyph is `Color.primary` over
  a theme-coloured board and the accent does not move it. Ten roses per theme
  cost most of the harness's wall clock to say the same thing ten times.
- **The Increase Contrast pass is one accent per theme** for the same reason:
  the mode moves grounds, never ink.

## PRD-20 — the catalog, and the five claims that were false until someone ran them (2026-07-27)

The localization **infrastructure**, shipped without the nine languages. Every
user-facing string in the app and the widget extension now resolves through a
String Catalog; the Engine names nothing; and the gates that will hold nine
translations honest exist and have each been fired against a deliberate defect.
Translation itself is a separate PR — see "Not done".

### The premise was wrong by a factor of three, and counting is why anyone knows

`EXECUTING-A-PRD.md §4` says user-facing strings belong in one `Phrase` block per
file, "the single seam PRD-20 converts". Eleven files had one, out of ~48 with
copy — and three of those blocks were named something else (`CoachPhrase`,
`ShareCardPhrase`, and an unnamed `// MARK: Phrases` run), so the obvious grep
missed them. The blocks held the *minority*:

| | in `Phrase`-style blocks | bare literals | total |
|---|---|---|---|
| `Sources/App` | ~40 | **~275** | ~315 |
| `Sources/Shared` | ~55 | ~12 | ~67 |
| `Sources/Widgets` | **0** | ~34 | ~34 |

Worse for the plan: most strings never reach the screen as
`Text(LocalizedStringKey)`. They arrive as `String` through helpers (`GlassChip`,
`statusLabel`, `LegendRow`) and through `.accessibilityLabel(_: String)` — the
**non**-localizing overload. Xcode's automatic extraction sees almost none of
it, so the extraction had to be a script plus a source-grep test rather than a
build setting. That is why the instrument is Task 1 and not Task 9.

### `techniqueID` did not need to exist

`PROGRAM-2.0.md:71` asks the Engine to emit "stable IDs (`techniqueID`,
difficulty raw values)". It already did: `Technique` and `Difficulty` are
`String`-raw-valued enums whose values are persisted inside every
`GeneratedPuzzle` trace and therefore inside the 56 golden-corpus hashes. Adding
a `techniqueID` field would have created a second identity that can disagree
with the frozen one. So the Engine change is a **deletion** —
`Technique.displayName`, `Difficulty.title`, `VariantTier.title`, all computed,
none encoded — and the corpus was **56/56 after every one of the eight tasks**.

### Five claims that were false, and the one thing they had in common

Not one was a logic error. Every one was a confident statement nobody had
executed, and each was found by running it.

| Claim | What running it showed |
|---|---|
| `xcstringstool compile` validates a catalog | It accepts a plural with **no `other` category**, exit 0, silent |
| A missing category renders the raw key | It renders **`(null)`** — which also defeats `Strings`' `format == key` English fallback |
| `catalog_keys` reads `xcstringstool print` | `print` emits **bare** keys; the parser required quotes, so the key set was always empty and `dead = keys - used` could never fire |
| `PhraseArg` closes the `String(format:)` hazard | Closing the *argument* set does nothing about the *specifier* set. `%1$@` × `.int` → **SIGSEGV, exit 139** |
| `Array(format)` is "a rounding error" | **518 ns/label, 33% of the call**, on the 81-label AX path. Rewritten as a utf8 state machine: 44–47 ns |

The `(null)` correction matters most: the degrade path built two tasks earlier
would not have caught it either, and a reviewer told to expect the raw key would
have concluded the gate was broken.

### The plural axis had nowhere to say what it counts

`board.stats.digitLeft` is `"%1$lld, %2$lld left"` — two integers. A whole-string
`variations.plural` in an `.xcstrings` cannot record **which** one drives the
category, so `xcstringstool` infers it, and it picked argument 1 — the *digit*,
not the count. Measured: `"5, 1 left"` took `other` and `"1, 5 left"` took `one`.
Exactly inverted, in English, today. Only explicit CLDR substitutions with
`argNum` written down can express it; three keys now do, and both the generator
and the tests hard-fail the ambiguous shape.

### The guard that would have broken every plural at once

`String(localized:)` returns the catalog's `NSStringLocalizedFormatKey` —
`%#@value@` — which the specifier guard added three tasks earlier correctly saw
as an unknown specifier and rejected. In Debug that is an `assertionFailure`; in
Release it is a raw `%1$#@value@` on screen, on **every pluralised string
simultaneously**. Nothing was wrong when the guard was written. Only running the
two together revealed it.

A later correction to the same area is worth recording because it inverts the
headline: a missing **minority** category is not a hole. Foundation resolves the
computed category, else `other`, else nothing —
`fr` missing `many` at 1,000,000 renders `"1000000 OTHER"` (a *silent grammar
error*), while `fr` missing `other` at 2 renders `(null)`. The assertion messages
now name which of the two applies.

### Three live bugs that predate this PRD

- **`ArchiveCalendar.weekdayInitials` returned `["S","M","T","W","T","F","S"]` in
  every locale.** The column *order* already respected `firstWeekday`; the
  letters were always English. Now `veryShortWeekdaySymbols` off the existing
  locale-keyed cache. German is `["M","D","M","D","F","S","S"]` from Monday, and
  the test asserting it failed against the old code first.
- **`streak(1)` read "1 day streak"** — 8 sites, 3 spellings, one of them the
  share card this file already calls the artifact that "outlives the session and
  cannot be corrected".
- **The Mac and the phone disagreed about the same board.** The Continue caption
  printed `Int(fillFraction * 100)%` on macOS and `BoardProgressCaption` on iOS,
  so one saved board read "Steady · 0%" on the Mac and "Steady · Untouched" on
  the phone. No AX baseline covers macOS, so nothing caught it and nothing would.

### The dead-key gate could not fail, and then found 118

`swift_referenced_keys` unioned all of `EnglishPhrases.table` into the used-set,
and the catalog's `en` is *generated from* that table — so `dead = keys - used`
was empty **by construction for all 394 keys**. Strict mode dropped that reader
and reported **118**: 58 `NineLegend`, 28 `TutorialGrammar`, 19 digit-word array
entries, 13 the second arm of a ternary the regex could not reach. Every one is
genuinely reachable at runtime through a `scope + ".field"` shape, so the fix is
readers that parse shapes rather than a list of names — and the drill (a planted
key, strict exits 1, lenient exits 0) is what says the gate has teeth.

### Numbers

`swift test`: **336 XCTest (3 skipped) + 79 swift-testing, 0 failures**, 121.65 s
at load average **3.95** — set beside this file's existing 111 s at load 2.31 and
136 s at load 16.81 for the same tree before reading it as a cost. Golden corpus
**56/56 after every task**. Catalog **425 keys** in three structural shapes, `en`
only. Call-site offences **134 → 0**. iOS, tvOS and macOS all build; the entitlements
diff against `origin/main` is **empty**, so no capability changed and no `match`
re-mint is implied.

### Not done

- **No translations.** Nine locales were scoped and are not in this PR. The
  catalog declares `CFBundleLocalizations: [en]`, held to the catalog's actual
  contents by `testDeclaredLocalizationsMatchTranslatedLocales` — so the
  declaration cannot outrun reality, and the locale list and the translations
  must land in the same commit. `PROGRAM-2.0.md`'s own status line said this PRD
  "needs translators, not infrastructure"; the infrastructure is the half that
  could be finished well without a human who reads Japanese.
- **No pseudo-loc/RTL lane, no Dynamic Type stress lane** (planned Tasks 10–11).
  Both mechanisms were **verified by hand** so the next session does not have to
  re-derive them: `-NSDoubleLocalizedStrings YES` fires; `-AppleTextDirection YES
  -NSForceRightToLeftWritingDirection YES` fires and **the board already does the
  right thing** — chrome mirrors, the board and rose do not (screenshots in
  `.context/prd20/`). `simctl ui <udid> content_size accessibility-extra-extra-extra-large`
  is the Dynamic Type lever. The fallback design (generating a `qps-Ploc` locale)
  is not needed.
- **A bare-specifier key is a loaded gun, and one probe fired it.** Under
  double-localization every board digit rendered `lld 4` instead of `4`, because
  `board.value.plain` was `"%1$lld"` — a translation unit whose entire content is
  one specifier. Not shipped (the same build renders correctly unflagged), and
  those keys are now formatted in Swift. But a translator can do what the
  pseudolocalizer did.
- **An omitted argument is still invisible.** `specifierMismatch` rejects an
  index above `args.count` and a wrong conversion; a translation that simply
  *drops* `%2$@` validates and formats fine, and half the sentence disappears.
  ~~Four keys are exposed (`board.announce.pair`, `board.cell.hintPair`,
  `coach.card.label`, `shelf.continue.caption`).~~ **Closed here, and the count
  was wrong: 32 keys are exposed, not four.** Those four are a sample. Every key
  carrying two or more positional indices is exposed — the whole
  `coach.*.sentence.*` family, and most of `board.*`, `shelf.*` and
  `firstrun.*`. `testEveryLocaleUsesEveryArgumentIndexTheEnglishValueUses` and
  `testEverySubstitutionVariationStillNamesItsCount` hold it now.

  **How the 32nd key hid is the transferable part.** `board.progress.filled` is
  `%1$#@filled@ filled.` at the top level — one index — and its `%2$lld` lives
  inside the substitution's plural forms. So a reader that examines each stored
  value on its own counts 31, and the first script written to justify the
  assertion returned exactly 31. The Swift test, written from the same
  understanding but unioning the two levels, disagreed with it and was right.
  Argument coverage has to be computed per *rendering* — top-level ∪ the
  selected substitution form — not per stored value.

  **The hole was measured before it was closed.** A `ja` locale was injected
  carrying four deliberate defects: a dropped `%2$@`; a `%2$lld` dropped from
  inside a substitution; an index dropped from one plural category only; and a
  substitution form with no `%arg`. Against that catalog `strings.py --audit`
  was green, `strings.py --selftest-catalog` was green, and `xcstringstool
  compile` **exited 0 with no warning** — emitting `"board.announce.pair" =>
  "%1$@"` straight into the shipping `.strings`. Of the entire existing
  `CatalogTests` suite, nothing failed but the undeclared-locale tripwire. The
  two new tests failed on all four, naming the key and the category.

- **`needs_review` is erased by compilation — measured, not repeated.** A
  catalog whose every unit is `needs_review` and the same catalog marked
  `translated` compile to byte-identical output: `ja.lproj/*.strings` sha256
  `6a874df5…ba35` both ways, `*.stringsdict` `285b4548…9678` both ways, and the
  token `needs_review` appears **zero** times in any compiled artifact. The
  state exists only in the source catalog, so
  `testEveryMachineDraftIsMarkedNeedsReview` is the only thing that keeps "nobody
  on this project reads these nine languages" true in the repo rather than in a
  comment.

- **Task 11 (Dynamic Type at AX5) was retired, not deferred.** It specified an
  AX5 sweep, and the sweep would have measured its own absence: `Sources/App`
  holds **0** `@ScaledMetric`, **0** `dynamicTypeSize` and **0** `relativeTo:`
  against **64** fixed `.system(size:)` and **107** `CouchTypography`
  references, and `CouchTypography` itself
  (`couchkit/Sources/CouchKit/CouchUI.swift:22-31`) is fixed points on both
  branches of its `#if os(tvOS)`. Nothing in the app grows, so AX5 renders
  identically to the default size and returns green. Making Nine scale means
  changing `CouchTypography`, which all five Couch Suite apps render through —
  the same class of suite decision as the `HelpKit` strings below. Recorded as
  **[PRD-36](PRD-36.md)**.

  The plan's prediction was stale in both directions: it named the six
  `GlassIconButton`s as the first failure *and* `.contentShape(.accessibility,
  Circle())` as the fix, and that fix had already landed in PRD-19 at
  `TouchUI.swift:1558`. The one place text does grow today is the widget
  extension — 22 semantic text styles, and `BoardWidget.swift:129` grows into a
  `.frame(height: 34)` with no `lineLimit` and no `minimumScaleFactor`. That is
  a real bug, reachable now, and PRD-36 ships it first because it needs no suite
  coordination.
- **No whole-branch review.** Every task was reviewed and every finding fixed or
  parked, but the final cross-task pass was not run.
- **The app has not been driven in a non-English locale**, beyond the widget
  gallery in German (verified on screen, per-key, with an untranslated key
  correctly falling back to English). Walking every screen in `ja` and `de` on
  three platforms belongs with the translations.
- **`Linux-clean` remains unmeasured.** It is the stated reason `Sources/Shared`
  has a `Phrasebook` seam instead of `LocalizedStringResource`, and all three CI
  workflows are `macos-latest`. The discipline held; nothing proves it.
- **CouchKit's own strings are untouched.** `HelpKit.swift:117-134` ("Click to
  start" / "Tap to start") reaches Nine's tvOS home through `HelpOverlay`.
  Localizing them means a catalog in a package shared by five apps — a suite
  decision, not Nine's.
- **No `AppShortcutsProvider` to localize** (PRD-33) and **no store-page
  localization** (PRD-35).

---

## PRD-20 (continued) — the lane that could not fail, and the two bugs it found once it could (2026-07-27)

Tasks 10 and 12: the pseudo-localization and RTL lane, and driving the nine
languages. Task 11 stayed retired.

The headline is that **the lane as specified was incapable of failing, and the
two real bugs in this PRD's subject matter were both sitting in the one place
the plan told us to look and had been checked with the wrong instrument.**

### The truncation rule can never fire in this app

Task 10 Step 4 specified: *any element whose frame width is at its container's
width **and** whose label ends in `…` is a clipped string.* The follow-up prompt
parked the `and`-vs-`or` choice as the lane's precision dial and said to settle
the ellipsis half empirically first.

Settled, across five modes and five screens, twenty-five accessibility trees:
**zero labels contain an ellipsis.** Not one. SwiftUI reports the full logical
string to accessibility, and long text in Nine *wraps* rather than truncating.
The frame height is where it shows:

| | English | German |
|---|---|---|
| "Light up all of its kind" | `w=132 h=16` | `w=128 h=31` — `'Alle gleichen Ziffern aufleuchten lassen'` |

`h=16` is one line, `h=31` two, and the German string is complete. So the
conjunction was never the question: the ellipsis half is dead in both
directions, which leaves the frame test carrying a rule it was written to share.
A gate whose only clause cannot match is the Dynamic Type sweep this PRD already
retired for measuring its own absence — the same failure, one task later.

**What the lane asserts instead.** Four things, each of which has been watched to
fail (`scripts/loc-harness.py --selftest`, 15 cases, no simulator):

1. **No label or value renders `(null)`.** A plural missing its `other` compiles
   at exit 0 and renders exactly that. Every other gate reads the catalog; this
   reads the screen, which is the only place the two can be caught disagreeing.
2. **No unsubstituted format specifier reaches the user.** Exempt under
   `double`, where the pseudolocalizer prints the raw format beside the
   substituted one — with the percent eaten, `Row 1$lld, column 2$lld Row 1,
   column 1`, so the percent is precisely what separates a real failure from the
   mode working.
3. **Nothing runs off the side of the screen.** Horizontal only, and that
   narrowing is the design. The first version measured all four edges and its
   first run reported ten failures, every one of them wrong: two Japanese
   preference rows and eight theme swatches below the fold of a sheet that
   scrolls. Content past the bottom edge is what a scroll view *is*. Nothing in
   Nine scrolls sideways, so horizontal overflow has no innocent reading.
4. **Under RTL the board and the rose hold still, and the control bar mirrors.**

Vertical growth is not asserted, it is **recorded**: `Tests/LocBaselines/`
carries every frame on every screen in every mode, so the Japanese sheet growing
by 40pt is a diff to read rather than an error to dismiss. German wraps
constantly and is not a bug; a tripwire that cries wolf is deleted six weeks
later, which `simrig.py:1-14` is a monument to.

**The limit, stated rather than papered over:** a string clipped by a
`lineLimit` or shrunk by a `minimumScaleFactor` changes no frame and still
reports in full, so this lane cannot see it. The fixed-height boxes where that
happens are named in `PRD-36.md`, they are widget surfaces, and `describe-ui`
cannot reach a widget at all.

### Two RTL bugs, and both were checked with the wrong instrument first

The execution ledger records a hand-verification: *"`-AppleTextDirection YES`
fires, and the app ALREADY behaves per decision 3 with no code change needed:
the board did NOT mirror… Task 10's job is to ASSERT this, not to implement
it."* That was read off a **screenshot**, and the prompt built on it said in the
same breath to assert from AX frames, not pixels, because a screenshot diff
cannot tell a mirrored rose from a moved one. Both halves turned out to matter.

**The board.** The pixels were right and the accessibility tree was not.
Measured: `Row 1, column 1` reported value `4` at x=342 while the digit 4 was
drawn at x=20; the whole top row read back in reverse. The board is drawn by a
`Canvas`, which draws in raw coordinates and does not mirror, and its 81
synthetic children are placed with `.position(x:y:)`, which does. So every cell
but column 5 had its accessibility frame somewhere other than it looked — for
VoiceOver touch exploration, for Switch Control, and for Voice Control's
cell names alike. Invisible to a screenshot diff by construction: the board
looks perfect. `BoardAccessibility.swift` now pins
`.environment(\.layoutDirection, .leftToRight)` on the grid, and the RTL frames
match the LTR frames exactly.

**The rose.** This one was visible all along and nobody had opened the rose in
RTL. The petals laid out `3 2 1 / 6 5 4 / 9 8 7` — mirrored on screen, which is
the precise harm decision 3 was written to forbid ("mirroring it would move the
7 under the thumb that expects the 3"). `FlickRoseView` offsets its petals from
`RoseGeometry` with `.offset(x:)`, which is direction-aware. The flick path is
the second half of the argument: `flickDirection` reads `DragGesture`'s raw
translation, which is *not* mirrored, so a rightward flick would have placed the
digit drawn on the left. Both the drawn ring and `TouchRose`'s tap targets are
now pinned — separately, because pinning one and not the other would have taken
the targets off the petals, which looks correct and is worse.

**And the rose is not laid out the way two documents said it was.** Both the
plan and the prompt describe the invariant as "petal 1 bottom-left and petal 9
top-right". Measured: it is telephone-keypad order — 1 2 3 across the top at
y=220, 4 5 6 at 270, 7 8 9 at 320 — so petal 1 is top-*left*. The assertion
does not pin a corner, because which corner holds the 1 is not the claim and
pinning it would fail the day the ring is redesigned for reasons unrelated to
language. It compares the two directions' arrangements to each other.

### An English anchor cannot survive a localized build

Every screen the AX lane reaches, it reaches by waiting on an English label.
None of them work here: under `double` the cell "Row 1, column 1" is reported as
`Row 1$lld, column 2$lld Row 1, column 1`, and the first harness timed out on
the first screen of the second mode.

`describe-ui` reports each chrome button's SF Symbol as `uniqueId`, and **that
does not localize** — `gearshape` is `gearshape` in all five modes, verified
across ten trees. Every tap in the loc lane is by symbol, or by a frame taken
from the English reference pass. The one screen with no symbol of its own, the
rose, is opened on the first empty cell's *frame* rather than its label.

Related, and the reason `simrig.relaunch` grew an `args` parameter rather than
the loc lane growing its own launch path: **`ax-snapshot.py` had a private
`relaunch` that inlined the same four steps** and never called `simrig`'s. It
was harmless while it had one caller. A loc harness reusing `capture()` would
have dropped every mode flag in silence and recorded five plausible-looking
English baselines. It delegates now, and the AX baselines were re-run and are
byte-identical. The seeded quiet state both lanes depend on moved to
`scripts/ninestate.py` for the same reason — a lane that forgets one tip flag
does not fail, it intermittently photographs a glass slab.

### The whole-branch review, finally run

Never run for #42 or #43; run here over `71a52d6^..2a17ce7` end to end. Four
findings were fixed in this PR and each was reproduced before it was believed.

**A locale that loses its plural entirely is invisible to every gate.**
`testEveryPluralHasTheCategoriesItsLanguageRequires` builds its work list from
the plurals it *finds* in each locale body, so a body with no plural block
contributes no assertions; the `checked > 0` floor stands at 180 axes and cannot
notice one going missing. Measured on clean `2a17ce7`: replacing French's
three-category `board.streak.plain` with a flat unit passed `strings.py
--audit`, passed `xcstringstool compile` at exit 0 with no warning, and passed
every test in `CatalogTests`. French would read "série de 1 jours" at every
count on the streak chip, the widget and the share card — French `one` covers 0
and 1 — silently and forever. This is the same defect #43 closed one level down:
that drill removed a *category* from a plural and was caught; removing the
*plural* was not. `testEveryLocaleCarriesTheSameShapeAsItsEnglish` derives the
required shape from English and compares, rather than reading it out of the data
being judged.

**The catalog had already drifted from its generator.**
`difficulty.nocturne.title`'s DO-NOT-TRANSLATE comment was hand-edited into the
artifact during Task 9 and not back into `COMMENTS`, so `--build-catalog
--dry-run` reported `1 changed` and the next real run would have deleted the
only do-not-translate instruction in the catalog without a word. Nothing ran the
generator to find out: `--audit` reads the artifact and `--build-catalog` is only
run deliberately, so the drift had no observer. `--audit` now runs the generator
dry and fails on any difference — a generated artifact that disagrees with its
generator is the "two lists that agree only by inspection" failure this file was
written against.

**A third sentence join, in the same file as the other two.**
`BoardSpeech.progressSummary` was `sentence += " " + Phrase.wrongCount(wrong)`.
It outlived both rounds that produced `board.announce.pair` and
`board.cell.hintPair` because it carries no interpolations — the seal looks for
two `\(` on a line — and is not a `.text(…)` argument, so the other seal never
saw it. Japanese shipped `"51 マス中 18 マス 記入済み。 誤り 3 マス。"`: an ASCII space
after a `。` that already separates. Same in zh-Hans. It is a VoiceOver surface,
spoken from the progress control and a rotor action. The seal now also flags a
whitespace-or-punctuation-only literal being concatenated onto a phrase, and was
calibrated by putting the old line back and watching it fire.

**The kebab rule asserted a false universal and was dropping real English.** The
comment claimed "hyphenated English never has an uppercase letter inside a
word"; the rule implemented it as *any* uppercase after position 0, which is not
CamelCase but merely capitalisation. `Face-ID`, `non-ASCII`, `PDF-only`,
`AI-powered` and `TV-connected` all took the machine-name exit and would have
shipped English behind a green gate. CamelCase now means a lowercase letter
followed by an uppercase one. The cost is `UTF-8`, which is prose now — the
right direction to be wrong in, because a false positive is a literal somebody
exempts and a false negative is nine locales of untranslated English.
`iOS-only` survives even the tightened rule (`i`→`O` is a genuine boundary,
indistinguishable in shape from `AppIcon`) and is pinned as a fixture alongside
`hold-click`, so the residue is a test rather than a sentence.

Two more parked minors closed: `--selftest-catalog`'s dead-key case asserted by a
substring that stopped before the key, and passed while the check reported an
entirely different key (measured); and `testBothTargetsListTheStringsTree`
counted `- Sources/Strings` file-wide, so moving it from `NineWidgets` to a
second copy under `Nine` kept the count at 2, the test green, all three builds
green, and the widget permanently English. Both now name what they check.

### Not done, each with its reason

- **No human has read any of the nine languages.** This is the headline
  deferral, unchanged from #43 and stated plainly: every unit is
  `needs_review`, nine locales' worth, and the only mitigation applied was blind
  back-translation.
- **Only iOS is driven.** `describe-ui` is iOS-only — the same wall PRD-19 and
  PRD-22 hit — so there is no tvOS or macOS localization lane.

- **`MacUI.swift` was still not driven, and there is now a reason rather than an
  omission.** A locally-built Nine **cannot launch on macOS at all** on a host
  signed into iCloud. Measured: `Nine.app/Contents/MacOS/Nine` exits 133,
  `EXC_BREAKPOINT` in `CKContainer.__allocating_init(identifier:)` ←
  `LibraryCloudStore.init()` ← `AppModel.setUpCloudSyncIfAvailable()` ←
  `NineApp.init()`. The guard at `AppModel.swift:797` is
  `FileManager.default.ubiquityIdentityToken != nil` — it asks whether an iCloud
  *account* is signed in, not whether this binary carries the CloudKit
  *entitlement* that makes `CKContainer(identifier:)` legal. A build made with
  `CODE_SIGNING_ALLOWED=NO`, which is what every gate in this repo and every
  local `xcodebuild` produces, has the account and not the entitlement, and
  traps on the first line of `App.init()`.

  This is not a localization bug and it is not new — but it is almost certainly
  *why* this surface has gone five PRDs without being run, and it means the
  macOS build being green has never implied the macOS app opens. Whoever picks
  it up should widen that guard to survive a missing entitlement before trying
  to review the German window; it is out of PRD-20's scope to change how Nine
  starts up. `swift test`, all three platform builds and the whole iOS lane are
  unaffected.
- **The widgets are not in any lane.** `describe-ui` cannot reach a widget, so
  the German gallery check remains the only evidence, and the fixed-height
  clipping `PRD-36.md` names is unmeasured.
- **`UndoPhrase.forMove`'s behaviour change is disclosed but untested.** The
  `isBulkNotes` branch now applies on macOS and tvOS, where an auto-notes bulk
  undo previously said "Undid note 0" — reachable by wand-filling on iPhone and
  resuming the board on either. The new sentence is right and the old one was
  nonsense; what is missing is a test on `UndoPhrase.forMove`, which has none.
  Recorded here because #43's report claimed the Mac Continue caption was the
  only English change, and this is a second one.
- **The two seal implementations still share five verbatim tables with nothing
  asserting they agree**, and they already differ on `"""` handling. The
  cross-runner battery that closed that minor was run by hand, once, out of
  tree.
- **The offence detector's `/` and `_` branch has no case discrimination** —
  `Play/Pause` and `On/Off` slip — and `preceding_label` cannot tell an argument
  colon from a ternary's, so a false branch after `board.id ? :` is suppressed.
  Both are real, neither is currently firing on a live string.
- **`EXEMPT` is honoured by the offence scanner but not by the key reader**, so
  a key named only from the debug-only `PadProbeHUD` reads as live.
- **`build_catalog` preserves a translation across an English rewording without
  downgrading its state.** Harmless while everything is `needs_review`; it
  becomes a live hazard the first time a human reviews a locale and flips it to
  `translated`.

---

## PRD-6 — Nine on the wrist (6a)

A watchOS app: the board as a glanceable map, a tap to dive into a 3×3 box, and
the Digital Crown as the rose. Shipped with today's daily arriving over
WatchConnectivity, because the watch is not allowed to compose it.

### Nine decisions, taken rather than deferred

`PRD-6.md` was written before `PROGRAM-2.0.md`'s engineering-foundations line,
and they disagree in two places. The program doc and the kickoff are later and
therefore controlling; each reconciliation is here with its reason.

**The link carries a puzzle down and a solve up, never play state.** PRD-6 §3
listed WatchConnectivity as a non-goal; `PROGRAM-2.0.md:112` requires it. Both
are satisfiable at once, because what the wrist actually needs from the phone is
the *board*, not the game. The reason not to send play state is written into
`SharedDailyBoard.swift:6-7`, which this pattern is borrowed from: that file is
safe under last-writer-wins because "both sides only ever append moves to the
same day's board, so a lost race costs a move, never corruption." A watch has
undo and erase. It can legitimately hold *fewer* filled cells than the phone it
is syncing with, so the identical rule stops losing moves and starts deleting a
player's evening. A `GeneratedPuzzle` is a pure function of the day, so a
revision conflict on it cannot lose anything, and PRD-6 §2.5's "in-progress
boards do not hand off in v1" stands unamended.

**The watch composes gentle and nothing harder.** The kickoff's rule, taken
literally. There is no fast-seed catalog in the repo — `grep -rni pantry`
returns two lines, both in `PROGRAM-2.0.md`, and PRD-23 shipped with
"catalogs/pantry" explicitly not done — so "catalog-easy" can only mean the
easiest band. `WatchComposePolicy` holds `ceiling = .gentle` *and*
`dailyBand = .steady` in one place, so the link is provably load-bearing:
`theDailyIsAboveTheCeilingSoTheLinkIsLoadBearing` fails the day those two agree.

Measured anyway, because a rule is worth more next to a number.
**Mac Release compose p95 is gentle 0.02 s / steady 0.05 s** (`PROGRAM-2.0.md:29`),
and the encoded daily is **6,386 bytes** — well inside an application context,
asserted at 32 KB because `updateApplicationContext` rejects an oversized
payload on a real watch and nowhere else. So steady would very likely have been
*fast enough*; it is excluded because the rule is a ceiling, not a benchmark,
and because the same ceiling is what keeps Nocturne off the wrist without a
second conversation.

**Free play on the watch is gentle-only, and there is no difficulty picker.**
Follows from the ceiling: offering Sharp would be offering something the watch
cannot make.

**No phone, no daily — and the app says so.** "Today · On your iPhone", with the
iPhone glyph and a VoiceOver hint naming the fix. Not a spinner, and never
yesterday's board.

**`AppModel` is not compiled into the watch.** It builds a `LibraryCloudStore`,
whose `CKContainer(identifier:)` traps on a binary holding the iCloud *account*
but not the CloudKit *entitlement* — the live defect recorded above, the one
that means a locally-built Nine cannot launch on macOS at all. The watch carries
KVS and no CloudKit container, so importing the model would have shipped that
trap to the wrist. A purpose-built `WatchModel` replaces it, and three value
types moved out of `AppModel.swift` into `Theme.swift` so `BoardView` could come
along without it.

**The board is reused, not reimplemented.** The lens is `BoardView` scaled 3×
and offset inside a clip — PRD-6 §4 Step 2's "one drawing surface, two camera
positions", literally. The three `.layerEffect` shaders are gated off watchOS,
which has none; `waveOrigin: nil` routes the celebration down the Canvas-drawn
diagonal luminance wave, which PRD-6 §2.4 already names as the watch's hero
moment for exactly that reason.

**Theme and accent arrive over a new cloud-synced `nine.appearance` key.** A
sibling top-level key, never a field on `nine.prefs`, which ships in every
released build and whose next write from an older version would erase a field it
has no property for. The alternative was a settings screen on a watch.

**Game Center on the watch is deferred** (PRD-6 §4 Step 3). It is
fire-and-forget reporting that the phone performs anyway when it ingests the
solve, so the entitlement would buy a capability with no caller.

**6b — complications and Smart Stack — is deferred.** PRD-6 scopes it as a
separate PR. It needs a second new bundle id and a watch-side app group, which
doubles the provisioning blast radius on a change that already cannot be
verified end to end without a paired device.

### Four things that were only found by running it

**A watch app embedded in an iOS app still needs `WKCompanionAppBundleIdentifier`.**
The plan said it did not — a modern single-target watch app is associated by
being embedded. That is wrong: a watch app must declare itself either watch-only
or paired by bundle id, and omitting both is malformed rather than modern.
Nothing catches it at build time. `xcodebuild` succeeded, `NineWatch.app`
appeared in `Debug-watchsimulator`, and `simctl install` was the first thing in
the chain that refused.

**The board drew underneath the clock.** `.ignoresSafeArea()` looked right for a
full-bleed board and put rows 1 and 2 behind the status bar and the title. On a
grid where every cell carries information that is not a cosmetic defect.

**`scaleEffect` on a toolbar `Gauge` shrinks the drawing and not the slot**, so
the progress arc floated inside a circle twice its size.

**A root `.tint` makes watchOS 26 draw the back chevron as a filled accent
disc** that out-shouts the board — an idle-pixel-test failure on the one screen
the player is thinking on. The accent now applies only where it carries meaning.

The peer rails took three measured passes: centred strips run off the sides,
edge-flush strips lose their ends to the rounded corner, and two strips both
starting at the origin print the row on top of the column. The 16 pt inset is
one constant for both so they cannot be tuned apart.

### The seals, and the one that fired

`WatchSealTests` greps `Sources/Watch` for a `Difficulty` named outside
`WatchComposePolicy`, for more than one call into the generator, for a clock,
and for its own tree still existing (so it cannot pass vacuously — PRD-20's
plural gate failed exactly that way).

**It fired on its first run, on something it was not written for.** The home
screen's compose button read `Strings.string("difficulty.gentle.title")` while
the ceiling was a constant three files away: move `ceiling` to `.steady` and the
button would still have said "Gentle". A grep for `.gentle` cannot tell a
difficulty literal from a catalog key, and that imprecision is what found a real
coupling. It reads `Strings.difficulty(WatchComposePolicy.ceiling)` now.

`VariantChannelSealTests`, `StringSealTests`, `scripts/strings.py` and
`CatalogTests` were all taught about `Sources/Watch`; `CatalogTests` counted
bundles rather than targets and had to learn there are three.

Two link rules were falsified before being believed: `revision >= known` and a
provenance stamp with the seed check removed each make a test fail.

`matchesTheDayItClaims` is a **stamp check, not a proof**, deliberately.
Re-deriving the board would mean composing steady on the watch — the very thing
the ceiling forbids — so it compares the seed and band `GeneratedPuzzle` already
carries, and then checks the givens against the solution to catch a payload that
was garbled rather than forged.

### Not done, each with its reason

- **No real hardware.** Everything below was measured on 45 mm and 41 mm
  simulators. **Double Tap (`handGestureShortcut(.primaryAction)`) has therefore
  never been fired** — it needs S9-class hardware. It is wired as an
  accelerator, never a sole path: tapping the selected cell always commits, per
  PRD-6 §5's own instruction.
- **PRD-6 §5's tuning gate is unmet.** "Ten consecutive comfortable solves by a
  fresh wrist" cannot be answered by a crown driven with a scroll wheel. The
  dial's detent sensitivity is `.medium` on the strength of the API's default,
  not a measurement.
- **KVS does not work in the simulator** — `Unable to find entitlement for KVS
  store`, because a `CODE_SIGNING_ALLOWED=NO` build has no entitlements. So the
  one-streak story, which the whole pinned `ubiquity-kvstore-identifier` exists
  for, is **argued and not observed**. PRD-6 §5 calls this out as load-bearing
  and asks for cross-device verification in week one; it is still owed.
- **The link itself has never carried a byte.** A simulator watch is not paired
  to a simulator phone, so `WCSession` never activates. Both halves are covered
  by unit tests on the pure adoption rule and the wire, which is what the design
  was shaped to allow — but no handoff has crossed a real radio.
- **No watch accessibility lane.** `describe-ui` is iOS-only, the same wall
  PRD-19, PRD-20 and PRD-22 hit. The board keeps its 81 synthetic children on
  the wrist because `BoardAccessibility.swift` compiles in, and the rails and
  dial stops carry labels — but nothing diffs any of it.
- **No watch contrast lane**, for the same reason, and the wrist is the one
  screen PRD-6 §5 says to test outdoors.
- **The nine new locales are machine-drafted and unreviewed**, consistent with
  PRD-20's standing headline deferral. They were translated against the terms
  already in the catalog — Erase, Row, Column, Home all reuse the board's and
  the legend's existing wording — rather than invented.
- **A board digit shows behind the dial arc** at the very edge of the lens on
  45 mm. Cosmetic, visible in the shipped screenshots, not fixed.
- **The watch has no first run.** It inherits the phone's welcome ledger
  through nothing at all; PRD-6 §3 rules out a tutorial in 6a and the grammar is
  two sentences, but a wrist-first player meets the crown with no introduction.

### Two lanes that had never run, found while getting this PR green

Neither is PRD-6's work. Both are here because they are what made the PR red,
and because a gate that cannot fire is not a gate.

**The contrast lane has never once completed.** `contrast-harness.py`'s verify
path ended `handle.write(text)` with `text` assigned only on the `--record`
path. So the lane booted a simulator, relaunched and sampled 26 cells over 22
minutes, measured every one correctly, and then died on `NameError` before
`gate()` was ever called. `gh run list --workflow=nine-accessibility.yml` is
unambiguous: green through PRD-16, red on **every** PR from PRD-22 — the one
that added the harness — onward, five in a row, three of which merged anyway.
The floors PRD-22 shipped have been enforced by nothing since the day they were
written. Fixed by rendering the measured rows in the same shape `--record`
writes the baseline in, which is what the workflow comment always said the
failure artifact was for. Verified locally: 26 cells, every one clears its floor.

**The pseudo-loc/RTL lane has never run in CI at all**, because it is the step
*after* contrast and the crash took the job down first. Run locally here for the
first time, it failed five ways — all one cause: the baselines bake the literal
date into the home shelf's Today card, so they rot at every midnight.
`ax-snapshot.py` has masked exactly this since PRD-19 (`mask()`, `TODAY`), and
this lane is the drifted copy — the third-copy drift `ninestate.py`'s own header
warns about. It now masks the date in all four renderings the launch locales
produce (`Jul 27, 2026`, `27. Juli 2026`, `2026年7月27日`, and the doubled
pseudo-locale). Baselines re-recorded: the diff is five lines, one per locale,
all of them the date.

**Residual, stated rather than hidden:** masking the *label* does not fix the
*frame*. Japanese measured 99×129 with `27日` and 100×129 with `28日`, so the ja
home baseline still rots whenever the rendered date changes width — a
one-or-two-digit day boundary, or a longer month name. Daily rot is fixed;
monthly rot is not. Doing it properly means pinning the clock in the seeded
state, which is `simrig.py`'s territory and a change every lane would inherit.

## PRD-25 — the board shows its work, and the two bands that were cheaper than the one above them (2026-07-28)

`PRD-25.md` did not exist when this started; `PROGRAM-2.0.md:84` was the whole
spec. The PRD is written now and is the forward document; this is what happened.

### The deep end costs less than Nocturne, and that is the finding

Two bands, 200 seeds each, Mac **Release** (`scripts/compose-scan.sh`'s rule —
`swift test` builds Debug and generation is ~50× slower there):

| band | p50 | p90 | p95 | p99 | max | givens (min/med/max) |
|---|---|---|---|---|---|---|
| tempest | 0.00 s | 0.01 s | **0.02 s** | 0.03 s | 0.07 s | 24 / 28 / 33 |
| abyss | 0.05 s | 0.15 s | **0.23 s** | 0.41 s | 0.44 s | 24 / 28 / 33 |
| *nocturne, for scale* | | | *5.25 s* | | | *≤26* |

**The two deepest bands compose 25–250× faster than the band above them.** The
reason is worth keeping: a maximally-dug board usually needs *more* than an
X-wing, which is exactly why Sharp has to heal so much of its own dig back.
Widen the chain and the healing loop stops earlier — so the boards Sharp throws
away are the boards Tempest is looking for. Difficulty and compose cost are not
the same axis, and Nocturne's 5.25 s is the cost of *rejecting* hard boards
rather than of making them.

Neither band carries `BandDemands`, and that is a decision. Nocturne needed them
because it had no technique Sharp lacked, so "harder" had to be measured in
clues and density. These two are defined by a floor no other band can reach.

**Zero Tempest boards are defined by a swordfish.** Across 200 seeds the hardest
step is `skyscraper` 117 / `xyWing` 83. Swordfish appears mid-chain — the School
teaches it from a real Tempest trace — but it is never the top of one. Recorded
rather than tuned away: forcing it would mean a demand, and a demand is what the
p95 above is cheap *because* of.

### What "minimal sub-chain" turned into

PROGRAM-2.0 says the engine "re-derives the minimal `SolveStep` sub-chain forcing
that cell". Taken literally that is a trap, and it was measured before it was
designed around: a hidden single reads a whole unit and a naked single reads
every peer, so within a few steps almost everything transitively supports almost
everything and the "minimal" chain is the whole chain. A backward dependency
slice and a drop-one-and-retry reduction both converge on ~the full trace.

What ships instead answers the question the player actually asked. "Why must
this be a 7" is "here is what killed the 3, here is what killed the 5, and that
leaves the 7": the solver runs forward and records only the steps that touch
*this cell's* candidates, reporting the number it skipped rather than hiding
them. Bounded by construction at nine (a cell has nine candidates), usually two
or three. `DerivationTests` pins the replay invariant.

### Four defects found only by driving it

Each of these compiles, renders, and is invisible to every test in the repo.

**The long-press gesture never fired.** `LongPressGesture` reports no location —
it is the one gesture that tells you *that* and not *where* — so the first
version sequenced it before a zero-distance drag and read `startLocation` off the
second phase. A press-and-hold that does not move produces `.second(true, nil)`
and no drag value at all, so the point stayed `.zero` and the board was asked
about a cell off its top-left corner. It is two simultaneous gestures now: the
drag records where the finger is at touch-down, the long press says when to ask.

**The narration card's action button was not in the accessibility tree.**
`.accessibilityElement(children: .contain)` with an explicit label — which is
what `CoachCardContent` does, and what its header says keeps the button
activatable — exposed three of six subviews and no button, so a VoiceOver user
could read the first beat and had no way to reach the second. The container
holds only the prose now and the button is its sibling.

**A School row was tappable only across its own text.** A `Button`'s hit region
is its label's *content*, and the label is a dot, a `Text` and a `Spacer`; a
`Spacer` has no content, so a row 334 pt wide responded only in its leftmost
~120. Every tap at the row centre landed on nothing, which looks exactly like a
button that does not work. It took a scrim temporarily wired to dismiss on tap
to prove the touch was reaching the card and being swallowed rather than never
arriving. `.contentShape(RoundedRectangle(…))` fixes the touch; a second
`.contentShape(.accessibility, …)` fixes the tree, where the same row measured
104×16.

**Three action buttons were under the 44 pt floor.** Measured at 69×36 and 36×16
in `describe-ui` dumps. `.frame(minHeight: 44)` *outside* the glass, so the
target grows and the drawn capsule does not move. One of the three is PRD-11's
shipped hint card, which PRD-19's 44 pt sweep never covered because **no AX
baseline reaches a card** — nothing has ever looked at one.

### Two pieces of copy that had rotted

**"Three difficulties, every board proved solvable by logic"** on the welcome
card. There were four when PRD-17 shipped Nocturne and nobody noticed; this PRD
would have made it six. Copy that counts something the app can grow does not
survive the app growing, so the count is gone rather than corrected.

**"Why a 8?"** — the narration's own heading, `Why a %1$lld?`. Choosing *a* or
*an* from a numeral is English grammar that no other language shares, and this
repo already bans that class of thing (`BoardSpeechTests.testNoSentenceCasingHelperSurvives`).
Rephrased to `Why must this be %1$lld?`, which needs no article anywhere.

Found and **not** fixed: the shipped `coach.hiddenSingle.sentence.col` renders
"can take a 8" with the same defect. It is a 1.5-era string with nine
translations behind it, and changing it invalidates all nine for a bug this PRD
did not introduce. It is a one-line fix for whoever next opens that family.

### The AX lane needed a scroll, and would otherwise have gone quiet

Three stacked deep-end cards pushed the learn row past the fold on an iPhone 17
Pro, and the home baseline's anchor ("How to play") stopped being on screen.
Re-anchoring on the last visible card would have kept the lane green and quietly
dropped the tutorial, records and School cards out of the baseline — a shorter
file that reads like a passing diff. `ax-snapshot.py` scrolls to the bottom
before reading home now, in short swipes against the stop rather than one fling,
because where momentum stops is not deterministic and a hard stop is.

`home.txt` re-recorded (11 lines). `game`, `game-quiet`, `game-rose` and `prefs`
are untouched, which is the signal that mattered: the board's 81 children, its
9 box containers and the rotors did not move.

### `strings.py --build-catalog` emitted a 41,000-line whitespace diff

It wrote Xcode's `"key" : value` while the committed catalog is in the compact
form PRD-20's translation pass left it in, so every regeneration buried the real
rows inside a whole-file reformat. It sniffs the file now — **before** opening it
for write, because `"w"` truncates and reading it inside the block reads an empty
file and silently takes the default.

### Not done, each with its reason

- **tvOS narration.** `.holdBegan` on an empty non-given cell is already the
  pencil rose *and* the four-way remote's only door to Prefs (`GameScreen.swift`
  and PRD-5). Re-gesturing that is a PRD-5 decision, not this one's.
- **W-Wing and any full chain.** PROGRAM-2.0 marks W-Wing optional and states
  the limit this PRD kept: explanation complexity, not difficulty. A technique
  Nine cannot say in one sentence has no business in a band Nine sells.
- **School lessons for the four variant techniques.** They are behind PRD-23's
  channel seal; a lesson for a board the player cannot reach is a lie with an
  animation on it.
- **`swift test` is 3:47, against the ~120 s budget in EXECUTING-A-PRD §5.** It
  was **2:40 before this PRD** — already over — and the new suites add ~28 s
  (`DeepTechniqueTests` 14 s, `TechniqueSchoolTests` 8 s, `DerivationTests` 3 s).
  Both numbers are here rather than one, because the budget was already broken
  and this PRD is not the reason. The generation-heavy files share their boards
  through file-level `static let`s, which is where the cheap savings were.
- **No device compose measurement**, same standing gap as PRD-17 and PRD-23. The
  numbers above are Mac Release; PROGRAM-2.0's nightly lane is where a device
  number belongs.
- **The nine languages are machine-drafted and unreviewed** — 39 new keys ×
  9 locales, every one `needs_review`, consistent with PRD-20's standing
  headline deferral. Lowest confidence: "lines" in the skyscraper sentence,
  where French and Brazilian Portuguese have no word that is not already "row"
  in this catalog (`alignements` / `unidades`), and the XY-wing's "ringed
  square" and "partners", which have no precedent in the catalog at all.
- **The narration card can cover the board's first row.** It sits in PRD-2's
  free band, which is ~190 pt on an iPhone 17 Pro against a card that reaches
  ~195 pt with both honesty lines showing. Measured, bounded, and the same
  behaviour PRD-11's card already has; a taller card would need the band resized,
  which moves the board.

## PRD-26 — the comet, and the two classifiers that could not have been wrong out loud (2026-07-28)

`PRD-26.md` did not exist when this started; `PROGRAM-2.0.md:85` was the whole
spec, exactly as with PRD-25. The PRD is written now and is the forward
document; this is what happened.

### Two classifiers that pass every test and answer nothing

"Replay analysis re-runs the solver alongside your moves to classify each
placement" is one sentence in the plan and three different features depending on
what "classify" means. Two readings were implemented before the third, and both
are worth keeping because each looks correct until it is run.

**"Does technique T *place* this cell?"** — a lane that cannot fire. Every pair,
box-line, fish and wing **eliminates**; only the singles ever carry a
`placement`, which `PRD-25.md:85` already records in another context. So the
probe can answer nothing but `hiddenSingle`, `headline` is permanently nil, and
*"You found the X-Wing at move 31"* — the one sentence the feature exists for —
never appears on any board, with every test green. It was caught by writing the
test that asserts a Tempest solve names a technique, which is the shape of test
this repo keeps having to learn.

**"Run the whole chain until the cell falls, and name the hardest technique that
fired."** — credits an X-Wing on the far side of the grid for a cell it never
touched. And because every Nine board is *proved solvable by logic*, the chain
reaches every cell, so `.leap` becomes unreachable: `testALeapIsReachable`
failed, and the honest fix was not to loosen the test but to notice that the
question was wrong.

What ships is PRD-25's `derivation` reused verbatim — the hardest technique that
bore on **this** cell. Gating it additionally on `elsewhere == 0` ("no unrelated
work first") reads as the principled bar and **fails the solver's own path**: the
chain takes elimination-only steps between placements, none of which bear on the
cell it is about to fill, so a perfectly-played Sharp board produced seven leaps
and a Tempest board named nothing. Any non-zero bar would be a number nobody
could defend, so there is none.

`.leap`, not `.guess`. PROGRAM-2.0 says guess; a raw value becomes the
localization identity the moment it ships (PRD-20's finding), so it is worth
choosing once rather than renaming against nine translations later.

### The 2 KB budget, and the cap that did not have to move

`CoachProgress.Met` gained `usedInSolve`. A third `Bool`, spelled by the
synthesized encoder on all 32 rows, puts a full blob **past** PRD-25 §2.5's 2 KB
— which `theBlobIsBoundedNoMatterWhatItIsFed` measures rather than trusts, so it
failed rather than shipping. Raising `capacity` was the easy answer and the wrong
one: the budget is what keeps this blob in KVS beside the streak. `Met.encode`
omits defaults now, which shrinks the existing rows too and is the more tolerant
wire in the bargain.

### Numbers

| thing | measured |
|---|---|
| packed replay, 300 timed moves | **1288 bytes** (PROGRAM-2.0 budgets 1–2 KB) |
| packed replay, the driven 55-move solve | **308 bytes** |
| exported loop | H.264, 1080×1350, **5.000 s**, **705 KB** |
| `swift test` | **3:26** (399 XCTest + 147 swift-testing, 0 failures) |

Deltas rather than absolute timestamps in the packed log, and that is the one
arithmetic decision worth defending: an absolute `UInt16` of deciseconds tops out
at 6553 s — 109 minutes — which a leisurely Abyss can genuinely exceed, and the
failure mode is every move after the ceiling collapsing onto one instant. A
*delta* of 109 minutes cannot exist, because `ElapsedTimer` pauses in the
background.

### Where the honesty rule had to split

"Old logs replay at uniform cadence" and "the debrief says fastest region" cannot
both be unconditional, and the question came up as a real decision rather than as
an edge case.

- **The comet does not tell.** Same 5 s loop, no watermark, no dimming. The moves
  are true and only their spacing is invented, and a uniform cadence *is* honestly
  inventing the spacing.
- **The debrief tells by omission.** Fastest region and longest-circled cell are
  functions of `LoggedMove.at` and nothing else, so on an untimed log they are
  absent and the card is shorter. It does not apologise for them. "Fastest region:
  box 4" derived from a uniform cadence is a fabricated fact on a card the player
  will believe — the class of thing `SolveCardFacts.swift:58` calls the app's
  first dishonest pixel.

Driven on a simulator, both ways, and the untimed run also proved the
partially-timed rule in production: 55 seeded untimed moves plus one real timed
placement pack as untimed, because a log is timed or it is not.

### The AX lane found the one defect nothing else could

**"Show your solve" was in the rotor of all 81 cells of every unsolved board.**
`accessibilityAction(named:)` registers its action whatever the view's state, so
the `debrief != nil` guard *inside* the closure guarded the effect and not the
action's existence — a VoiceOver user on any mid-game board found an action that
silently did nothing. Invisible to every screenshot, every unit test and every
hand-driven walk-through; `ax-snapshot.py` diffed it on the first run.

The fix is `accessibilityActions` (plural), which takes a `ViewBuilder` and so
accepts a real `if`. Worth stating as the general rule, because the singular form
is the one that reads naturally: **a conditional action needs a conditional
builder, not a conditional body.**

### The comet followed the grid, and it was the demo that was wrong

Watching the exported loop, the digits appeared top-to-bottom — a picture of the
grid rather than of a hand. The engine turned out to be innocent: nothing between
`pack` and `CometTimeline.frame` sorts, and the seeded fixture was filling holes
by ascending cell index because that is what `enumerate` over a hole list does.

Two things came out of it anyway, and the second is the durable one. The harness
seeds from `puzzle.steps` now — the proof chain already inside every board, whose
placements genuinely jump (40, 3, 10, 44, 61, …) because deductions do. And
`theHeadFollowsTheLogAndNeverTheGrid` pins the claim: a comet that visited cells
in board order would look completely plausible, which is exactly why it needed a
test and not a comment.

### Three defects found only by driving it

Each compiles, renders, and is invisible to every test in the repo.

**The pull-up's reveal band *was* the control bar.** A bottom-120 pt band on a
screen whose bottom 96 pt is six 44 pt buttons meant the one place the gesture
listened was a row of buttons: every pull-up either did nothing or fought Undo.
The fix is not a smaller band — a solved board takes no input at all
(`AppModel.place` guards `solvedAt == nil`), so the board *is* the drag surface.

**The grabber was drawn under the control bar.** `.bottom` padding 6 puts a 3 pt
hairline beneath the bar and on top of the home indicator: invisible against one,
confusable with the other. It sits under the completion chip now.

**The comet's trail was drawn on top of the digits.** At 888 pt in the exported
card a translucent disc over a numeral reads as a smudge on the digit, not as a
path through the cell — visible only in a frame pulled out of the MP4. It is a
cell-shaped wash *behind* the glyph now.

### Not done, each with its reason

- **A CloudKit production schema deploy.** The new `SolveReplay` record type
  needs **no entitlement change and no `match` re-mint** — EXECUTING-A-PRD §6's
  trap fires on capabilities, and a record type is schema — but it does need
  deploying to the production environment before release. Human-owned, same shape
  as PRD-7 §5's container gate.
- **A macOS debrief.** The Mac gets the animated share card (it is the same
  artifact leaving the same app) and no pull-up: a pull-up is a touch gesture and
  the Mac's answer is a window, which is PRD-33's. The Mac also still has no first
  run and no drawer, so this is the standing gap rather than a new one.
- **No AX baseline reaches the debrief card**, for the reason PRD-25 recorded
  about its own: the baselines photograph a mid-game board and this card exists
  only after a solve. Its two accessibility rules were taken from PRD-25's scar
  tissue rather than from a lane — the action button is a *sibling* of the prose,
  not a child of a `.contain` container, and `minHeight: 44` sits outside the
  glass.
- **The nine languages are machine-drafted and unreviewed** — 12 keys × 9 locales,
  every one `needs_review`, consistent with PRD-20's standing headline deferral.
  Lowest confidence: "circled", which is figurative in English (the player circled
  *around* a cell) and has no idiom in several of the nine, and "corrections",
  where the neutral register matters and the obvious word in some languages
  implies error.
- **No device measurement of the export.** 150 `ImageRenderer` passes are
  synchronous on the solve path; on an iPhone 17 Pro simulator it is imperceptible
  behind the 2.4 s completion-chip gate, but that gate is the only thing hiding
  it and a cold device has never been measured. PROGRAM-2.0's nightly lane is
  where that number belongs.
- **tvOS has no debrief and no share**, only the ambient surface — there is no
  share sheet on tvOS (PRD-12's standing deferral) and a pull-up needs a touch.

## The erase petal, the honest clock, and the count that was never counted (2026-07-29)

**PRD-10 §2's tenth petal is gone** (supersedes `PRD-10.md:21`). The spec's erase
affordance was an `eraser.fill` glyph hung below the ring on any filled non-given
cell. In play it read as advice: a cell grows a delete button exactly when it holds
a digit, so the rose nudged toward changing digits that were already correct. The
grammar is now an indicator rather than an extra target — the digit already placed
(or already pencilled) gets a **dashed rim on its own petal** and erases when that
petal is tapped. It says "this digit is here", never "this is wrong", so it leaks
nothing about the solution, and it costs the ring no vertical space, which deleted
`RoseLens.eraseDrop` and the bottom-clamp reservation with it. The other doors onto
erase — the VoiceOver rotor's custom action and the watch's `CrownDial.erase` stop —
are untouched, because they were never petals.

Two things fell out of removing it. `RoseLens`'s bottom clamp had been tested only
*through* the erase-petal cases, so deleting those tests took the coverage of the
`min(...)` upper bound with it — restored directly. And the Mac mount had been
threaded with `currentDigit` under a comment promising the Mac rose "is not a silent
exception the moment that changes"; `MacUI.commit` has no erase branch, so the moment
it changed the Mac rose would have drawn the rim, spoken "Erase 5" and *placed* a 5.
Inert only because `handleClick` returns on a filled cell. The half that genuinely
fires on Mac — `notedDigits`, on a pencil-marked empty cell — was not passed at all.
The indicator was missing where it would have been right and threaded where it would
have been wrong; both halves are now real and the comments say which is live.

**The clock counted wall time, not play time.** `TimerState` had one open run and no
notion of being held, so backgrounding the app, or opening any board-occluding
overlay, kept the run ticking. It is hold-counted now (a set of hold reasons; the run
resumes only when the set empties), which is what makes `scenePhase` and the four
real occluders on `TouchGameScreen` — there is no `.sheet` seam there, only
hand-rolled overlay flags — able to pause it. The plan named one leak; the branch
found four, each at a seam that adopts a board the app did not itself start:

| Seam | Leak | Cap |
|---|---|---|
| `BoardLibrary` decode | process died mid-run | `entry.updatedAt` |
| `LibrarySync.apply` | cloud board from a device that died | `remote.updatedAt` |
| `ingestSharedDailyBoard` | jetsam mid-daily, resumed via widget | `shared.updatedAt` |
| `pendingSolve` adopt | widget-solved daily | `pending.solvedAt` |

The caps live on the adoption paths deliberately and **not** inside
`BoardLibrary.upsert`, which the live-play save path writes through — sanitising
there would pause the clock of the board you are actually playing.

**`SolveRecord.errors` was always zero.** Nothing counted wrong entries, so every
debrief and every stat that reads the field was reporting a constant. `NineGame`
counts them now and the debrief, the drawer and the share surfaces say the number
out loud, in nine languages.

**The rose's petals are opaque glass again, which walks back PRD-22 on the rose**
(supersedes the lens half of PRD-22 for this surface only). Petal glyphs collided with
the board's own digits under the transparent lens, worst in pencil mode where a ghost
`4` sat under petal 1 and a ghost `5` under petal 2. Four treatments were built and
photographed (`.context/rose-variants/`, five-panel contact sheets); the owner picked
**A**, the revert to `.couchGlassInteractive`. This is a taste call taken with its
costs on the table, so the costs are recorded rather than implied:

- It **reopens the 1.1 audit finding PRD-22 was written to close** — "rose petals are
  opaque `.glassEffect` discs, not the PRD's true glass petals lensing the board
  beneath." That sentence is true again.
- `rosePetalLens` in `Afterglow.metal` **still runs**, and `BoardView` still bends the
  board under the ring. Nothing can see it: the petals cover the area that refracts,
  and Liquid Glass merges adjacent discs into one blob that closes the gaps between
  them. The shader was left in place deliberately — deleting it is the one move that
  would make this pick expensive to reverse — so the cost of A today is GPU work whose
  output is fully occluded.
- Because A is byte-identical to what the unlensed branch already did, `PetalSurface`
  had two identical arms and **collapsed to a single `.couchGlassInteractive` call**.
  `lensed` lost its only consumer and is gone from `FlickRoseView`, `TouchRose` and
  all seven mount sites; the board's own `roseLens:` is untouched, since that is the
  refraction and a different parameter.

### Not done, each with its reason

- **The dashed erase rim has never been seen on the surface that now ships.** In
  `A-pencil-paper.png` — the same opaque glass, captured for the grid — the ring is
  absent on all three pencilled petals while the digit still reads accent-coloured,
  leaving colour as the only cue for erase. `EraseIndicator` is inset 8% off the
  petal's edge to clear what is presumed to be Liquid Glass's rim highlight, but
  **that inset is unverified**: it builds, and no one has looked at it. The presumed
  cause is inferred from the screenshot, not proven.
- **The simulator lane would not drive this session, and the reason is unknown.** A
  seeded container (`ninestate.quiet_blobs` + the AX fixture) that resumed straight
  onto a board at 12:03 today lands on Home at 19:18: the app honours neither the
  seeded `appearance` nor the seeded library, `resumeOnLaunch` does not fire against a
  fixture holding exactly one `inProgress` entry, and `sim-use tap` does not register
  at coordinates that match the render. It is **not** this change — the pre-change
  build was rebuilt and reproduces it exactly — and it is not decode, which
  `AXFixtureTests` still passes. Ruled out: stale process, stale container (cold
  uninstall/reinstall), and a wedged device (reboot). Unexamined: why a container the
  app demonstrably writes to is not read back.
- **tvOS overlays still leave the clock running.** The hold set is generic, but tvOS
  has no `.sheet` analogue to attach it to and its overlays were not audited; macOS is
  covered incidentally, through `scenePhase`.
- **The nine languages are machine-drafted and unreviewed**, consistent with PRD-20's
  standing headline deferral.

## PRD-31 — the drafting table, and the recognizer that had to be allowed to say no (2026-07-29)

`PRD-31.md` did not exist when this started; `PROGRAM-2.0.md:97` was the whole
spec, the same way it was for PRD-25 and PRD-26. The PRD is written now and is
the forward document; this is what happened.

### The finding that shaped everything: there was no iPad code to adapt

`Sources/` held **zero** `horizontalSizeClass`, zero `verticalSizeClass`, zero
`UIDevice`, zero `userInterfaceIdiom`. The entire iPad story was one
`.frame(maxWidth: 560)` on the shelf under the comment "center the column on
iPad" and a board clamp that subtracts a control-bar reserve from the height
term and nothing from the width term — portrait reasoning, shipped to a device
`project.yml:182` grants all four orientations.

So the question was never "which size class" but whether to introduce one at
all, and the answer is no. **A size class is wrong for this app.** A 1000×700
Stage Manager tile on an iPad Pro reports `.regular` horizontally while having
less usable width than an iPhone 17 Pro Max has height; an external display
hands us 1920×1080 from the same idiom that hands us 834×1194. The composition
is a pure function of the window (`Sources/Shared/DraftingTable.swift`,
Linux-clean, tested by `swift test` with no simulator, exactly like `RoseLens`),
and **there is no Stage Manager code anywhere in this change** — Stage Manager
sanity is what asking the window gets you for free.

The adoption rule is *the rail never costs you board*, and it is what correctly
refuses portrait. Any width threshold generous enough to admit an 11" in
landscape (1194pt) also admits an iPad Pro upright (1024pt), where the board
would fall from 984 to 568 to make room. Held literally the rule is also
unusable: on an 11" the two sides land within single-digit points, so a 2pt
chrome change anywhere would flip the entire composition. The 8% skirt is the
width of that knife edge, named rather than implied, and it is the only
softening — the 520pt floor and the comparison itself are absolute.

| Window | Composition | Board |
|---|---|---|
| iPad mini landscape | table | 617pt |
| iPad 11" landscape | table | 678pt (column would draw 718) |
| iPad Pro 13" landscape | table | 850pt |
| iPad Pro 12.9" portrait | column | 984pt (table would draw 568) |
| Stage Manager 1000×700 | column | 584pt |
| 1080p external display | table | 1000pt, capped |

`testTheRailNeverMeaningfullyCostsBoard` sweeps 169×113 window sizes rather than
the two an engineer happens to open, and `testShrinkingAWindowCrossesOnceAndStaysCrossed`
pins the property a two-threshold rule would have broken: dragging a window
narrower crosses into the column exactly once and never oscillates.

### Three defects found only by driving an iPad, each invisible to every test

**The two-column shelf inflated the Today card to half the screen.** `todayCard`
carries `.frame(minHeight: 130)` with no maximum, which makes it flexible
*upward* — it accepts any height offered. On the phone that has never shown,
because a `ScrollView` proposes nil and every child settles at its ideal size.
Put it in an `HStack` beside a taller column and the column is suddenly given a
concrete height, `VStack` divides the surplus between the card and the trailing
`Spacer`, and Today becomes a slab. A latent property of shipped code that only
a second column could expose; the fix is `fixedSize(horizontal: false, vertical: true)`
on each column, and the comment says so where the next person will be tempted to
remove it.

**The rail was 200pt of stats above 700pt of empty glass.** Specified and built
as a full-height panel, which is what "rail" suggests, and on an 11" it reads as
a panel that failed to load. A drawer is the height of what is in it, and
leaving it open should not change that. It is intrinsic-height now, top-aligned,
with the `HStack` switched to `.top` and the other two columns claiming
`maxHeight: .infinity` so they still fill.

**Keyboard parity built, shipped green, and could not receive a keystroke.**
`.focusable()`/`.focused()`/`.onKeyPress` were attached *inside* the
`GeometryReader`, where the surface is rebuilt on every geometry change and the
`@FocusState` set in `onAppear` never survives to see a key. The log showed
`[UIKit:KeyboardUI] Keyboard receives keyEvent type: 4` and the cursor did not
move — the event reached the app and fell through. `MacUI.swift:319-330` has
carried the same three lines *outside* its own `GeometryReader` since PRD-4,
under a comment about "focus wars"; this is that comment being right a second
time. Verified after the fix by injecting HID keycodes: arrows moved the cursor,
`5` placed, `⌘Z` undid it, `⇧3` left `Empty, notes 3`.

### The recognizer, and the two constants that had to be measured rather than chosen

$P point-cloud matching against authored templates — deterministic, Linux-clean,
~150 lines, no training data. A model would be neither Lane-1-testable nor
stable across OS versions, which is the property `GoldenCorpusTests` exists to
forbid. One deviation from stock $P earns its keep: scaling **uniformly** by the
larger dimension instead of to a non-uniform unit box, because a `1` is a
vertical line of zero width and stock $P divides by that.

The templates stay authored and never learn. Feeding accepted glyphs back in is
the obvious next move and it is a trap: the day the matcher reads your 4 as a 9,
that 4-shape becomes the 9 template and every subsequent 4 reads as a 9 more
confidently than the last. Learning affects **rendering only**.

**The commit bar is set for safety, not at the crossover, and it costs
something.** Measured across 45 synthesized hands and five deliberately degraded
ones:

| population | score |
|---|---|
| garbage — dash, box, scribble, cross, circle | ≤ **0.033** |
| best *wrong* reading (a 7 whose hook is so small it is a 1) | **0.391** |
| worst *right* reading (a 3 with flat bumps) | **0.303** |
| ordinary hands, all 45, all correct | ≥ **0.58** |

The last two overlap, so **no bar keeps every right answer and drops every wrong
one**. 0.45 sits above the wrong answers and refuses some right ones as the
price. `testTheSafeBarAlsoRefusesSomeCorrectReadings` asserts that price is
still being paid, so nobody quietly lowers the bar and re-opens the failure that
matters: a mark appearing in a cell the player did not mean.

**A margin bar was written, measured, and deleted.** "A guess that barely beats
its rival is a coin toss" is a good idea that is false here — not because the
populations overlap (they nearly separate) but because **the score bar has
already rejected everything the margin bar could reject**. Every reading in the
corpus that clears 0.45 is correct. `testTheMarginBarWouldHaveNothingLeftToReject`
fails the day that stops being true, and `Reading.margin` survives as reported
diagnostics so the next person to have the idea meets the number instead of the
intuition.

The first draft of that test **asserted the opposite and passed for the wrong
reason**: it bucketed the five degraded hands as "wrong" by which list they came
from rather than by what the matcher actually said, and two of them are read
correctly. It measured its own labelling. Caught by a failing assertion, which
is the shape of test this repo keeps having to learn.

### Erase costs nothing, because the model already toggles

A full Pencil vocabulary was on the table — write to place, scribble to erase,
double-tap to switch tool — and every item is a second input concept against a
budget of one. What ships falls out of a rule the app already had:
`NineGame.togglePencil` *toggles*, so writing a 4 into a cell that already notes
a 4 takes it away. No gesture, no mode, no glyph, and it reads the same as the
rose's dashed-rim petal. The Pencil never places a digit even though the
recognizer would allow it: your hand is what *tentative* looks like and the
typeface is what *committed* looks like, and inking an entry would spend that
distinction on a nicer screenshot.

### The specimen, and why it is not per board

One accepted glyph per digit, **773 bytes for all nine**, in its own cloud-synced
top-level blob. Per-mark ink would be per-board state, which EXECUTING-A-PRD §2
prices at 1515 ms against a 49 ms baseline. The specimen is also the better
product: every pencil mark wears the hand, *including the ones placed with the
rose, on the phone, with no Pencil in the room*, so a board looks like one person
wrote it rather than like nine unrelated scrawls.

Last confident stroke wins, at a stricter bar (0.60) than placement. First-wins
would enshrine the one bad 4 written while the pen skipped, recoverable only
through a settings row nobody should have to find.

### The haptic the source had already earmarked for this PRD, and why it is not wired

`AfterglowHaptics.swift` carries a comment saying `AfterglowScore.boxDetent`
"remains tvOS's … until iPad's Pencil hover gives touch a traversal of its own
(PRD-31)". The premise is right and the conclusion fails on physics: during a
hover **neither hand is touching the iPad**, so a taptic pulse in the chassis is
felt by nobody. Left unwired, and the comment corrected rather than fulfilled.

### Numbers

| thing | measured |
|---|---|
| a full hand, nine glyphs, encoded | **773 bytes** (test asserts < 4096) |
| board, iPad 11" landscape | **678pt** table vs 718pt column |
| board, iPad Pro 13" landscape | **850pt** |
| board cap | 1000pt, **inert on every shipping device** (pinned by test) |
| composition decision | swept over **19,097** window sizes in 0.006 s |
| AX baselines after `.focusable()` | **all five match**, no re-record |
| golden corpus | **56/56** |
| `swift test` | **3:17** (424 XCTest, 6 skipped + 161 swift-testing, 0 failures) |

### Not done, each with its reason

- **No Apple Pencil has ever written a digit into Nine, and no pointer has ever
  hovered over it.** There is no Pencil and no hover in a simulator, and neither
  can be synthesized: `SpatialEventCollection.Event.Kind.pencil` and
  `onContinuousHover` both need hardware. The recognizer is measured only against
  constructed strokes — constructed *differently from the templates* (different
  control points, different stroke splits, a shear, a rotation, per-point jitter),
  so a template that only matches its own coordinates fails — but that is not the
  same thing as a hand. The same class of standing deferral as PRD-20's "no human
  has read the nine languages". The **rendering** half was driven end to end: a
  real `nine.hand` blob seeded into the container, notes laid down over the
  keyboard, and the strokes photographed at note scale
  (`.context/prd31/06-handwritten-notes.png`).
- **The glyph box is 0.30 of a cell and that number came from one screenshot.**
  At 0.34 neighbouring marks in the mini keypad touch, because the note pitch is
  0.28. It has not been checked against a mixed cell — some digits learned, some
  not — where a written glyph sits beside a typeset one and the two optical sizes
  have to agree.
- **`sim-use tap` still does not drive this app's shelf, and `origin/main`
  reproduces it exactly.** Tapping a difficulty card at coordinates that match
  both the render and the reported accessibility frame does nothing, on the
  unmodified shipped build as well as this one; taps on the learn row and inside
  sheets work. This is the same unexplained lane failure recorded in the previous
  section, re-confirmed against main rather than assumed. Routed around with the
  widget deep link (`simctl openurl nine://daily`) and HID key injection, which is
  how everything above was driven. Still unexamined.
- **No Mac rail.** The layout function is shared and the Mac would take it
  cheaply, but `MacUI` has no drawer, no first run, and cannot be launched locally
  on an iCloud-signed-in host (PRD-20's standing gap), so it would ship undriven.
  The Mac's answer to a second pane is a window, which is PRD-33's.
- **No handedness preference.** Left-handed players get the worse half of
  controls-lead/stats-trail. A handedness row is a settings row and the covenant
  makes those expensive; the cheaper future fix is to mirror the composition off
  the same pure function, which takes no new state.
- **The debrief is not in the rail.** PRD-26's "never unbidden" is a shipped
  decision and geometry is not a reason to re-litigate it, so the pull-up stays a
  pull-up over the board.
- **No AX baseline covers the drafting table.** `ax-snapshot.py` is pinned to an
  iPhone 17 Pro (`DEVICE_TYPE`), which fixes the point geometry every frame in the
  baselines is measured in; an iPad lane means a second device and a second set of
  five baselines. The tree *was* read by hand in landscape — 81 cells in nine box
  containers, the rail's nine digit rings labelled, Home present — but nothing
  diffs it on the next PR.
- **The nine languages gained no new keys**, which is the one piece of good news
  in this list: the rail reuses `board.stats.*` verbatim and the Pencil says
  nothing at all.

## PRD-30 + PRD-33 — the presence that carries no clock, and the two lines that hung the Mac (2026-07-30)

Neither `PRD-30.md` nor `PRD-33.md` existed when this started; `PROGRAM-2.0.md:97`
and `:100` were the whole spec, the same way they were for PRD-25, PRD-26 and
PRD-31. Both PRDs are written now and are the forward documents; this is what
happened.

Rejected by the plan and still rejected: **Siri voice solving**. Nothing in
`NineIntents.swift` takes a cell, a digit or a move.

### Six claims checked against the SDK before a line was written, and four were false

The plan's Pillar E is a list of platform features, so the first task was finding
out which of them exist. `swiftc -typecheck` per target, `.swiftinterface` files,
and the build tools' own `--help`:

| Claim | Verdict |
|---|---|
| Live Activities need an entitlement and a `match` re-mint | **False.** The only build settings Xcode 26.6 defines are `INFOPLIST_KEY_NSSupportsLiveActivities` and `…FrequentUpdates` (`CoreBuildSystem.xcspec`). No entitlement, no App ID capability. **The trap EXECUTING-A-PRD §6 says has fired three times does not fire here** — the first new surface in three PRDs that needs nothing from the portal. |
| `#if canImport(ActivityKit)` is the right fence | **False, and it compiles.** `canImport(ActivityKit)` is **true on macOS** and false on tvOS/watchOS. But every type in the module, `ActivityAttributes` included, is `@available(macOS, unavailable)` — so on macOS the import succeeds and the conformance then fails. `canImport` answers "is there a module", which is not the question. The fence is `#if os(iOS)`. |
| A third-party app can donate a Journaling Suggestion | **False — there is no API.** See below. |
| StandBy is a widget family you can target | **False.** StandBy is a `WidgetLocation`, and the only function taking one is `disfavoredLocations(_:for:)` — an *opt-out*. There is no `\.widgetLocation` to read. |
| App Shortcut phrases localize through `Localizable.xcstrings` | **False.** They need their own `AppShortcuts.(xc)strings`, and `appshortcutstringsprocessor --help` names the file and the `--app-name-override` flag that exists to turn its `${applicationName}` check off. |
| `SetFocusFilterIntent` needs an entitlement | **False**, and it is available on every platform Nine ships (iOS 16 / macOS 13 / tvOS 16 / watchOS 9). |

### Journaling Suggestions cannot be built, and the near-miss is the interesting part

`JournalingSuggestions.swiftinterface` is 350 lines and entirely a **consumer**
surface: `JournalingSuggestionsPicker`, `JournalingSuggestionsConfiguration`, and
fifteen closed system asset types (Workout, WorkoutGroup, Contact, Location,
LocationGroup, Song, Podcast, GenericMedia, Photo, Video, LivePhoto,
MotionActivity, StateOfMind, Reflection, EventPoster). There is no `donate`, no
provider protocol, and `grep -rl JournalingSuggestion` over every other framework
in the SDK returns nothing. The framework is for apps that want to *read* the
system's suggestions. A sudoku solve cannot become one.

The one path that would technically work was examined and refused. **HealthKit
`HKStateOfMind` *is* an asset type**, so an app that logs a mood does produce a
suggestion. Taking it would mean a HealthKit entitlement and capability — the trap
that has fired three times — a permission prompt, and asking a player how they feel
about a sudoku. The product intent ("the completed daily as a private reflective
moment") is already shipped as PRD-26's debrief, which is a pull-up you have to ask
for.

### PRD-30: the payload is the mechanism

PRD-30's requirement is a **negative** — no timers, no countdowns, no
streak-endangered nagging ever — and negatives erode without anything going red. A
Live Activity that grows an elapsed-time line still builds, still passes every
other test, and is exactly the app Nine promised not to be.

So the negative is structural rather than editorial. `DailyPresence` carries a day
ordinal, a band id, a 22-byte glyph and a revision; `NineDailyActivity.ContentState`
— the bytes ActivityKit re-encodes on every update — carries the glyph and the
revision. No `Date`, no `TimeInterval`, no count, no streak. Two seals hold it:
`testThePresencePayloadCarriesNoClockAndNoStreak` reflects over the encoded JSON
keys, and `QuietPresenceSealTests` greps every quiet surface for `timerInterval`,
`style: .timer`, `countsDown`, `AlertConfiguration`, `pushType: .token` and the word
"streak". `Text(_:style: .timer)` is the one that matters: **it needs no field in
the payload at all**, because the system animates it from a `Date` on its own side.

The seal fired once on its first honest run, and correctly: `PresenceBridge` read
`model.streak.hasCompleted(day:)` to ask whether the daily was solved. Not a
rendered streak — but the fix is better than an exemption. `AppModel.hasSolved(day:)`
now exists, because *where a solve is recorded* is streak bookkeeping and a caller
that only wants to know whether a board is done should not have to know it.

`QuietPresenceTests` also caught the tolerant decode being tolerant in only one
field of four: three scalars used `try … ?? default`, which survives an *absent* key
and throws on a key of the wrong *type*. `NinePrefs` and `SharedAppearance` both had
this right already.

A `PresenceScreen` parameter was written and deleted. "Is the daily the board on
screen" sounds like part of "start-and-leave", and `glyph.isTouched` already proves
the player started the daily — so the extra check would only have dropped the
bookmark for someone who plays the daily at breakfast and a free board at lunch.
More code, worse behaviour; the test that replaced it is
`testNothingStartsWhileThePlayerIsLookingAtTheApp`.

### PRD-30: the finding that improved three widgets that already shipped

`WidgetPalette` was three hardcoded constants under a comment saying "the in-app
tinted themes don't reach the extension (it can't read nine's prefs)". True, and not
a law. `SharedAppearance` has carried theme and accent across a process boundary
since PRD-6 — just not *this* one, because it travels by KVS and the widget
extension reads KVS no more than it reads Application Support. Nobody noticed
because the three shipped widgets are small; a StandBy face is the largest thing
Nine draws on any screen.

Two additive optionals on `WidgetSnapshot` (`schemaVersion` stays 1, per
`lastGraceDay`'s own rule) and `Sources/Shared/SharedPalette.swift` fixed it for all
four widgets at once. The palette is a second copy of the numbers by necessity —
`AccentChoice.lightBarRGB` is already a hand-written second copy in the App layer,
under a comment saying SwiftUI `Color` → RGB round-tripping is unreliable — so
`SharedPaletteTests` reads `Theme.swift` as text and fails in both directions. It
was falsified against three perturbations: a changed accent triple, a changed theme
background, and a deleted theme row.

`SharedPalette.resolve` also encodes PRD-22's finding in its shape: the accent's
light/dark variant follows the **theme's** leaning, not the system's. Camel is a
light theme on a phone in dark mode, and a vivid accent on Camel is 3.36:1.

### PRD-33: App Intents cannot use the app's string seam, and the failure is quiet

`EXECUTING-A-PRD.md` §4 calls `Strings` "the single seam" every user-facing string
goes through. It does not compile in an intent:

```
error: 'LocalizedStringResource' must be initialized with a call to its
       initializer or a string literal
error: At least one halting error produced during export. No AppIntents metadata
       have been exported and this target is not usable with AppIntents until
       errors are resolved.
```

`appintentsmetadataprocessor` is a **static extractor** — it reads the source for
the strings the system will show without running anything, so a value produced by a
function call is no value at all. There is no runtime lookup available at any price.

**The dangerous part is that its error is not fatal to the Swift compile.** It says
"this target is not usable with AppIntents" and the build carries on. Written a
little differently this ships an app with no Shortcuts entries and no red anywhere —
the same family as PRD-16's alternate icons, which shipped green with no
`CFBundleAlternateIcons` at all.

That is not hypothetical here: the **first** iOS build of this branch produced no
`Metadata.appintents` in `Nine.app` and `** BUILD SUCCEEDED`, because `xcodegen`
had not been re-run and the two new files were not in the project. The artifact was
the only thing that disagreed. What settles it now is reading
`Nine.app/Metadata.appintents/extract.actionsdata`: five intents with the right
identifiers, `QuietShelfFilter` carrying
`com.apple.link.systemProtocol.FocusConfiguration`, `NineBand` as a
`linkEnumeration`, and four `autoShortcuts` with the right short-title keys.

So intent strings are literal keys in their own table, and two hand-authored
catalogs exist that `scripts/strings.py` cannot own — it *generates*
`Localizable.xcstrings` from `EnglishPhrases.table`, and `--audit` reports any row
no accessor reaches as a dead string. `IntentCatalogTests` applies the same four
rules `CatalogTests` applies to the big catalog, by a different route, and was
falsified against a missing locale, a translated coined band name, and an orphan row.

The phrase catalog is half-checked here on purpose: the build checks the other half.
`appshortcutstringsprocessor` fails with **"Invalid Utterance. Every App Shortcut
utterance should have one '${applicationName}' in it"** — verified by dropping it
from one German phrase.

### PRD-33: the trap that made the Mac driveable, and the two lines that undid it

**The CloudKit trap is fixed.** PRD-20 recorded it and PRD-31 re-quoted it: "a
locally-built Nine cannot launch on macOS at all on an iCloud-signed-in host,
trapping in `CKContainer.init` because the entitlement-free build passes an account
check it should not". The guard asked the *operating system* whether an iCloud
account exists, which is true on any signed-in Mac whatever the binary is signed
with; `CKContainer(identifier:)` then **traps** rather than throwing, because an
unentitled container request is a programmer error as far as CloudKit is concerned.

`AppModel.mayBuildCloudContainer` asks the binary instead, through `SecTask`. macOS
only, and the scope is honest rather than lazy: `SecTask` is not in the public iOS or
tvOS SDK, and the trap needs a signed-in host *and* an unentitled build, which on
those platforms means a simulator with no iCloud account to find.

Proven both ways rather than assumed. Reverting the guard reproduces
`EXC_BREAKPOINT` with a stack reading `CKContainer.__allocating_init(identifier:)` ←
`LibraryCloudStore.init()` ← `setUpCloudSyncIfAvailable()` ← `AppModel.init()`;
restoring it launches and stays up. **Everything else on the Mac in this PRD was
driven because of this** — the menu bar was read out of the live process, the
menu-bar board was clicked and photographed.

**And then two obvious spellings of one line hung the app at 100% CPU.**
`MenuBarExtra(isInserted:)` takes a `Binding<Bool>`, and the pref has to be readable
from `App.body`:

| `isInserted:` | result |
|---|---|
| `Binding` reading `model.prefs.macMenuBarExtra` | **103% CPU, unresponsive** |
| `@AppStorage(…)` | **99% CPU, unresponsive** |
| `.constant(true)` / `.constant(false)` | quiet, 0.4% |
| `@State` seeded from `UserDefaults` | quiet, 0.1% |

The spin is `AppDelegate.scenesDidChange` → `makeMainMenu` →
`AppKitMainMenuItem.updateMainMenu` → `MainMenuItemHost.requestUpdate` →
`scenesDidChange`, forever, read off `sample`. A `MenuBarExtra` makes the main menu
part of the scene update, and any source that republishes *during* that update —
`@Observable` state or `UserDefaults` change notifications alike — closes the loop.
The two `.constant` rows are what prove `MenuBarExtra` itself is innocent.

**Neither version could have been caught by anything but driving it.** Three
platform builds and 615 tests were green; the app launched, drew a board from the
menu bar, and then stopped answering AppleEvents. `@AppStorage` is standard practice
in an `App`, which is exactly why the second attempt looked like the fix.

Persisting outside `NinePrefs` turned out to be what EXECUTING-A-PRD §2 asks for
anyway — new state in its own key, never a new field on `nine.prefs`, which ships in
every released build — so the field was removed from `NinePrefs` rather than kept
beside the `@State`.

### PRD-33: three fences were the whole cost of three "missing" Mac features

Worth recording together, because the pattern is that the Mac's gaps were mostly
not gaps in the code:

- **The archive** had no Mac surface because `ArchiveSheet.swift` was `#if os(iOS)`
  and did not compile there. `ArchiveCalendar` already owned every date and every
  word from `Sources/Shared`, so widening the fence was the entire change.
- **The coach card** had never reached the Mac because `CoachCard.swift` was
  `#if os(iOS)`. It is `WhyCardContent`'s sibling, and that has rendered on the Mac
  since PRD-25.
- **The Technique School** has compiled for macOS since PRD-25 (`#if os(iOS) ||
  os(macOS)`) and nothing had ever presented it. The cheapest patch in the repo.

And one genuine absence: **macOS had no `onOpenURL` at all**, while
`project.yml` registers `nine://` on the *shared* Info.plist — so the Mac has
advertised a scheme it silently dropped since PRD-3. The handler's body needed no
change; only its fence.

### The literal "three moves" cap was refused

PROGRAM-2.0 writes the medium board widget as a *"three moves" mode*. A widget that
silently stops accepting taps after the third is input that breaks with no
explanation: it fails the first-flick test outright, and to anyone who has met one it
reads as a paywall — which the covenant forbids the *shape* of as well as the
substance. What "three moves" asserts is a claim about **scale**, and the honest way
to say that is a surface small enough to make it obvious with the app one tap away.

The `AppIntentConfiguration` the item really wanted is there, and its one real
parameter today is **handedness** — which DEVIATIONS recorded as deferred at the end
of PRD-31 because "a handedness row is a settings row and the covenant makes those
expensive". A widget configuration is not a settings row: per placed widget, edited
in the system's own sheet, no app chrome at all. PRD-24's channel parameter slots
into the same intent.

### The input-concept budget: this release spends zero

Every surface is an output surface (Live Activity, Dynamic Island, StandBy,
menu-bar extra), an invocation (App Shortcuts, Action button, menu rows over
`BoardKeys`' existing table) or configuration (Focus filters, widget
configuration). The widget's medium family extends PRD-3's tap-cell/tap-digit
grammar to a second size rather than inventing one, and the menu-bar board is
deliberately not playable so it stays on this side of the line — a rose in a 260pt
popover would have petals under the minimum target size and nowhere for a flick to
travel.

### Numbers

| thing | measured |
|---|---|
| the board glyph, both masks | **22 bytes** (ActivityKit's cap is 4KB for attributes + state) |
| new keys in `Localizable.xcstrings` | **14**, ×10 locales; catalog now **501** keys |
| `Intents.xcstrings` | **35** keys × 10 locales, hand-authored |
| `AppShortcuts.xcstrings` | **9** phrases × 10 locales, hand-authored |
| intents in the built artifact | **5**, and **4** `autoShortcuts` |
| menu-bar spin, before → after | **103% → 0.1%** CPU |
| AX baselines | **1 of 5 drifted** (prefs, one new row), re-recorded |
| Release archive | **ARCHIVE SUCCEEDED**; `NSSupportsLiveActivities` true, 5 intents, 4 shortcuts, 3 catalogs × 10 locales |
| golden corpus | **56/56** |
| `swift test` | **454 XCTest** (6 skipped) **+ 161 swift-testing**, 0 failures |

### Not done, each with its reason

- **No Live Activity has ever appeared on a Lock Screen, and no Dynamic Island has
  ever shown the glyph.** ActivityKit needs the app backgrounded on a device or a
  booted simulator, and a Live Activity is not in the accessibility tree
  `ax-snapshot.py` reads even when it is on screen. The policy is proven by unit
  test, the views compile on all three platforms, the Release archive carries
  `NSSupportsLiveActivities` and links ActivityKit into the appex — and the
  rendering is unphotographed. The same class of standing deferral as PRD-31's "no
  Apple Pencil has ever written a digit into Nine".
- **The loc lane did not run, and the reason is this host rather than this branch.**
  `loc-harness.py` failed twice at `simctl bootstatus` — `Status=4294967295`,
  "Waiting on System App" — on a freshly created `Nine-Loc`, with **4481 free pages
  (~70 MB)** on the machine. The failure is before the app is installed, so nothing
  in the diff can reach it. `--selftest` passes (15 cases, every assertion watched
  to fire and to stay quiet) and CI runs the lane on its own runner.
- **The AX lane, by contrast, worked** — which is worth recording because the two
  sections above this one say the simulator would not drive at all. Five screens
  captured on `Nine-AX`, one intended drift, re-recorded. Whatever broke on
  2026-07-29 either was not `ax-snapshot.py` or has stopped; it was not
  investigated here, and the note above it is now at least partly stale.
- **No Siri phrase has been spoken and no Action button pressed.** The metadata is
  verified from the artifact rather than the source, which is the strongest check
  available without hardware, but a microphone is hardware.
- **No Focus has ever activated.** `QuietShelfFilter` extracts with the right system
  protocol and the filtered rendering is exercised by construction; Settings ▸ Focus
  needs the simulator.
- **The static→intent widget migration is unverified.** The plan was to place the
  widget on the old build, install the new one and look — which needs the lane.
  Existing placed widgets are expected to adopt a default-initialised configuration;
  that is an expectation, not an observation.
- **The prefs AX baseline lost the accent label to the new row**, which is PRD-16's
  recorded pattern happening again: "the AX lane lost the accent swatches to the
  taller theme row". The sheet is taller than the capture and every row added pushes
  something below it. Re-recorded deliberately; the fix is a scrolled second capture,
  which is `ax-snapshot.py`'s to make.
- **No tvOS or macOS AX/contrast/loc lane**, unchanged: `describe-ui` is iOS-only.
  The Mac menu bar was read out of the live process by `System Events` instead, which
  is not a baseline anything diffs.
- **The nine languages are machine-drafted and unreviewed**, consistent with
  PRD-20's standing headline deferral. The drafts here were built against a term
  table pulled out of the shipped catalog rather than invented — board, erase, notes,
  continue, today and empty-cell all reuse the words already on screen.
- **No Mac first run and no Mac stats drawer.** PRD-34's and PRD-9's respectively.
  **No Mac debrief**: PRD-26's "never unbidden" is a shipped decision and a window is
  not a reason to re-litigate it.

## PRD-24 — the channel that had to be refused, and the two knobs that could never have fired (2026-07-30)

[PRD-24](PRD-24.md) opens the Channels shelf: Classic | Thermo | Killer, each with
its own Today, streak, stats slice and leaderboard, and dailies one per day per
channel. Thermo ships first as the de-risking variant, then Killer on the same
machinery. Nine commits, driven on an iPhone 17 Pro.

The PRD's strategic claim is a negative one — *a killer board is played with exactly
the same rose, on the same board view, through the same four buttons* — so the
interesting work was mostly in what did **not** change, and the interesting failures
were all in things that were green.

### The finding that changed the ladder: a band knob that cannot reject

`scripts/thermo-scan.sh 200` on the first draft of `thermoBand` reported
**200/200 composed at every tier**, which looks exactly like a pass. The shape
line beside it did not:

| knob | set to | measured |
|---|---|---|
| `maxGivens` | 30 / 24 / 18 | max **19 / 19 / 11** |
| `minVariantSteps` | 3 / 6 / 10 | p50 **11 / 13 / 18** |

Neither knob could ever have rejected anything. A band parameter that cannot fire
is a decision dressed as a constraint, and the tier was in fact defined by whatever
the dig happened to do. Both were tightened to sit inside the measured distribution;
the diagnostic then confirms they fire (`digExhausted` 14/17/7 and `decoration`
1/4/7 per 60 attempts) while supply stays 200/200 — the cost is paid in attempts,
not in supply.

**What actually walks the thermo ladder is chain width.** A wider chain closes the
board with fewer givens, because the extra techniques do work the clues would
otherwise have to: Gentle 14 → Steady 12 → Sharp 7 (p50). That answers the question
PRD-23 §5 left open for this PRD — killer's ladder is compressed (6/4/0, separated
mostly by technique set); thermo's is not. For thermo, three tiers read as three
tiers.

Thermo, 200 seeds per tier, Mac Release:

| tier | composed | p50 | **p95** | max | givens p50 (max) | tubes | cells on a tube |
|---|---|---|---|---|---|---|---|
| gentle | 200/200 | 0.00 s | **0.01 s** | 0.16 s | 14 (19) | 8 | 28 |
| steady | 200/200 | 0.01 s | **0.02 s** | 0.12 s | 12 (16) | 9 | 32 |
| sharp  | 200/200 | 0.01 s | **0.03 s** | 0.14 s | 7 (11) | 10 | 43 |

5–14× cheaper than killer Sharp (0.14 s) and ~175× cheaper than Nocturne (5.25 s),
on every tier. That is the whole case for shipping thermo first.

### Thermo's diagnostic needed a third cause, and it is the ruleset's fault

Killer can fail two ways — not unique, or the chain cannot close it — and PRD-23's
`--diag` separates exactly those. Thermo has a third that the ruleset makes *likely*
rather than unlikely: a tube layout covers the board partially by construction and
cannot determine a grid on its own, so a thermo band's clue ceiling has to stay well
above zero, and a board carrying a dozen givens may be one the **classic** chain
closes unaided. The tubes are then decoration, `minVariantSteps` rejects it, and the
failure looks nothing like either killer cause and wants the *opposite* fix — fewer
givens or more coverage, because a wider chain makes it worse. So the lane counts
the rejection reason directly instead of leaving it to be inferred.

### A quarantine that is the desired outcome, not a tolerated one

Every other tolerance rule in this repo is about *preserving* a value an old build
cannot read. `GameKind.channel` is about **refusing to play** a board an old build
cannot render, and that inverts the usual reasoning:

> A build with no cage renderer that opened a killer board as ordinary sudoku would
> show a grid with no cages drawn, under constraints it does not enforce, and would
> mark the player's correct entries as **errors** — `NineGame.isError` compares
> against a solution that is only *the* solution under the rules.

`GameKind` has a synthesized `Codable`, so an old build throws and Phase 0's
element-level decode catches it. The drill reuses `QuarantiningLibrary` unchanged and
pins that both channel boards come back with channel, tier and day intact. Nothing
was needed to make this work; what was needed was noticing it is right.

The same reasoning runs through `ChannelRules.isPlayable`, which is false in all
four ways a board's rules can be untrustworthy — absent, unreadable, empty, or
carrying a future `.arrow` — and through two independent refusals built on it:
`openChannelBoard` will not start such a board, and `BoardView.drawRules` will not
draw it. Two guards for one hazard, kept because a renderer that trusts its input is
a renderer that ships the bug.

### "The classic streak is never diluted" as a type, not a comment

The requirement is PROGRAM-2.0's. A comment stating it survives until the first
refactor, so:

- `nine.streak`, `nine.history` and `nine.archive` are untouched and classic-only.
  Nothing in `ChannelLedger` reads or writes them, so the dilution question has no
  code path to travel down. The drill asserts a channel solve leaves `nine.history`
  byte-identical.
- **`Channel.Ledgered` has no classic case.** `Channel` has three because the shelf
  has three pages; the ledger's whole mutating API is keyed by the nested type,
  which has only `.thermo` and `.killer`. "Record a classic solve into the channel
  ledger" is not a call that can be written rather than one that is guarded, and the
  same type keys the per-channel leaderboard IDs, so a killer score cannot reach the
  classic board either.
- The ledger records a solve **atomically** — streak and history move together or
  neither does — because a caller updating one and forgetting the other is the shape
  of every streak bug this repo has had (PRD-13 found a third copy of the streak
  rule in `BoardIntents`).

`StreakState` and `SolveHistory` are reused as value types, once per channel, and
that is the design rather than a shortcut: per-channel grace *is* PRD-13's
non-stacking rule and per-channel stats *are*
`count(of:)`/`bestSeconds(for:)`/`averageSeconds(for:)`/`trend(_:)`. Neither had to
be re-derived or kept in step. `SolveHistory.record` gained a `capacity:` parameter
defaulting to `Self.capacity`, so every classic caller is byte-identical; a channel
keeps 200 against classic's 1000, which is a KVS budget (1 MB total, ~150 KB already
spent) and not a preference.

`nine.channels` needed no wire bridge at all, and the reason is worth stating: it is
a **new** key, so no shipped build has ever written it. `nine.history` needed the
`band`-sibling contortion for one added `Difficulty` case precisely because the
throwing build was already on TestFlight.

### Three defects found only by driving it, each green everywhere else

1. **The leading chevron was never in the accessibility tree.** The pager's first
   draft put `.accessibilityElement(children: .contain)` plus a label on the
   enclosing `HStack`, and SwiftUI merged the first child button into the labelled
   container. `describe-ui` showed "Next channel" on every page and never "Previous
   channel" — including page 3, where Next is *disabled* and Previous is the only one
   that works. Same trap the Today card carries a comment about
   (`TouchUI.swift:308`, where a nested `Button` collapsed an 89×129 element to
   44×44). Fixed by labelling the indicator rather than the container.
2. **The tier cards reported a 41pt-wide accessibility frame**, under the charter's
   44pt floor, because SwiftUI derives it from tight content bounds when the content
   is only a symbol and a caption. Classic's difficulty cards escape this by
   accident — their `MiniBoard` is 64pt and forces the width. `contentShape(.accessibility, …)`;
   now 75×96.
3. **The tubes were silent.** With nine thermometers drawn on screen, `describe-ui`
   reported the cell under one as `Row 3, column 5` / `Empty`. A VoiceOver player had
   no way to learn any of them existed, and every gate was green: three platform
   builds, 470 tests, 81 children in 9 box containers, all AX baselines matching. The
   tree was structurally perfect and semantically silent.

The fix for (3) contains the finding worth keeping. `cellHint` was the obvious home
— its own doc comment says it "can afford the extra syllables the label cannot" —
and it is **wrong, because VoiceOver hints can be turned off**. A cage's printed sum
is not a tip about a cell; it is the primary information on a killer board, closer to
a given. A hint-only clause leaves those players an unplayable board that reports no
error anywhere. So the clause is in the *label*, and the four AX baselines matching
with no re-record is the proof it cannot leak onto a classic board.

The two rulesets say different things because they are different things: a cage is
its sum ("cage of 15"), a thermometer is *positional* ("thermometer, 2 of 4") —
its constraint is largely spent by `initialCandidates` before a technique runs, so
what a player needs is where along the tube they are. A clause reading only "on a
thermometer" would report the one thing inferable from a board with no cages on it.

### PRD-20's lane refused this diff five times, every time correctly

Worth recording as a group, because the lane is now the most productive reviewer in
the repo:

1. `EnglishPhrases.table` unsorted — the catalog is generated by diffing that file.
2. **Eleven keys with no translator comment**, a hard failure by design. "Sharp" is
   unguessable in isolation, and "Killer" as the name of a puzzle variant localizes
   nothing like the adjective — `channel.killer.title`'s comment now says so in
   capitals.
3. Two keys used by no Swift file yet (removed, reintroduced with the shelf that
   uses them).
4. Two pager labels reported as dead because the key was threaded through a
   parameter — the audit greps for `Strings.string("…")`, so the label is resolved at
   the call site now.
5. **`coach.cageCombination.sentence` splicing a joined digit list through `%2$@`.**
   A `%N$@` hole inside a `coach.*` sentence carries English's grammar into nine
   languages that do not share it, and "none of them puts 2, 5 and 9 here" needs a
   conjunction `BoardSpeech` has no business choosing. Reworded to name one digit as
   an `.int` and let the board's coach wash carry the rest, which is what
   `coachNakedPair` already does.

The `board.cell.withRule` join was then added to the splice allowlist *with* its
reason: both halves are finished translated strings, so what the join carries is
punctuation and order — the same sanctioned shape as `board.announce.pair`.

### The seal came off the app layer and went onto the rose

PRD-23's `VariantChannelSealTests` said in its own header: *"When PRD-24 does open
the channel, this test is the thing to delete, and deleting it should feel like a
decision."* The decision was not to delete it but to re-aim it. The old seal
asserted a *temporary* fact — no variant surface exists yet — which stops being true
by definition on the day the shelf ships. `VariantInputSealTests` asserts the claim
this PRD actually makes, which is narrower, stronger and permanent:

> the input covenant is variant-agnostic, and the watch stays classic-only.

It is a hand-written list of seven files rather than a directory sweep, and that is
the substantive change: a tree is a location, this is an argument about
responsibility. Each entry is on the path between a finger and `NineGame.place`.
`BoardView` is deliberately **not** sealed — it renders cages and tubes, and
rendering a constraint is not reading input under it.

### The input-concept budget: this release spends exactly one

The shelf page-turn, and nothing else. `Sources/` held zero `TabView`s, zero
horizontal `ScrollView`s and zero `scrollTargetBehavior`s before this, so it is
genuinely new; it is paid for by the rose being untouched across every variant. The
rose is unchanged, there is no fifth control button, and no gesture was added to the
game screen — the page-turn is on the shelf, where nothing is at stake, and it ships
*paired* with chevrons and a named accessibility action because a swipe alone is not
an affordance (the lesson PRD-34 records about the stats drawer).

### A tripwire PRD-23 correctly did not need, and one line of spec made mandatory

PRD-23 shipped variant generation with no golden corpus, and that was right: nothing
was persisted and no daily depended on it. "Dailies one per day per channel" makes
every channel daily `(day → seed) → board`, so a quiet change to either tiler, the
band ladder, the inverse dig, the trim or the verifier re-rolls every future channel
daily and breaks every shared channel seed. `VariantCorpusTests` freezes 9 seeds
(2.4 s in Debug), re-frozen the same deliberate way as the classic 56.

### Numbers

| thing | measured |
|---|---|
| thermo compose p95, Mac Release | 0.01 / 0.02 / 0.03 s (gentle / steady / sharp) |
| thermo composed rate | 200/200 per tier |
| killer compose p95, Mac Release (PRD-23, unchanged) | 0.02 / 0.05 / 0.14 s |
| thermo givens p50 | 14 / 12 / 7 |
| tubes per board | 8 / 9 / 10 |
| channel history capacity | 200 records per channel (classic keeps 1000) |
| both channels' KVS cost at capacity | ~44 KB against a 1 MB store |
| new catalog keys | 30, × 9 locales = 270 machine drafts, all `needs_review` |
| catalog size | 498 → 528 keys |
| AX baselines | 5 (`channel.txt` is new); classic four match with **no** re-record |
| contrast harness | 26 cells, every one clears its floor |
| golden corpus | 56/56 after every commit |
| variant corpus | 9/9 |
| `swift test` | 479 XCTest + 197 swift-testing, 0 failures, 195 s |
| platform builds | iOS + tvOS + macOS green, plus a Release archive |

### Not done, each with its reason

- **No tvOS or macOS channel page.** Both compile, both stay on Classic, and neither
  is broken — `model.channel` defaults to `.classic` and they never change it. The
  reason it is a deferral rather than a port: a page-turn is a touch gesture, so the
  TV needs a focus-based switcher and the Mac a menu or segmented one, and each is a
  design question rather than a translation of this one. The same shape as PRD-12's
  tvOS share card, PRD-13's grace card, PRD-18's welcome and PRD-26's Mac debrief.
- **A variant board does not sync.** `nine.channelRules` is local, riding with
  `nine.library`, and `LibraryCloudStore` syncs per-entry CloudKit records — so
  carrying a board's rules across needs a new record type and a production schema
  deploy, the human gate PRD-26's replays also had. The failure mode is deliberate
  rather than latent: a board whose rules did not arrive is not `isPlayable`, so it
  refuses to open instead of opening under the wrong rules, and says so on its row.
  The per-channel *streak* does sync — `nine.channels` is KVS like `nine.streak`.
- **The per-channel leaderboards have no App Store Connect records.** The IDs and the
  submission are in; the records are a human gate of exactly the kind PRD-7 §5
  describes. **No entitlement change and therefore no `match` re-mint** — Game Center
  is already on all three GameKit platforms. Submission is fire-and-forget `try?`, so
  until the records exist a channel solve submits into silence, which is the right
  failure mode for a leaderboard and why this can ship ahead of the portal work.
- **Achievements stay classic-only.** A channel solve does not advance them.
  Splitting them per channel would triple a set the covenant already calls the outer
  edge of what it tolerates, and "first killer solve" is a badge, which
  `EXECUTING-A-PRD` §1 rules out by name.
- **The share card says the tier, not the channel.** A killer Steady solve shares as
  "Steady". `SolveCardFacts` and `ShareCard` are laid out around a single band
  caption and widening them is a share-card change rather than a channel one — but
  the card is honestly incomplete rather than wrong, which was the deciding factor
  against the alternative of printing nothing.
- **No contrast measurement on a variant board.** The harness seeds the frozen
  classic AX fixture, so its 26 green cells prove only that `BoardView.draw` gained a
  pass without moving classic's numbers. A tube is a new ground for the digit above
  it and wants its own fixture, which is a harness change.
- **No channel archive.** `nine.archive` is classic-only and there is no way to open
  a past channel daily. `ChannelLedger.record` already threads the `openedOn`
  provenance guard through, so the streak side is ready for it.
- **No widget channel parameter.** PRD-33 built the `AppIntentConfiguration` this
  slots into and said so; `SharedDailyBoard` is a single slot keyed on the day
  ordinal with no channel axis, so the widget shows Classic and the channels are
  structurally invisible to it. That is also why `openChannelToday` needs no widget
  merge.
- **No School lessons for the four variant techniques.** They have coach *sentences*
  now, which is what PRD-11 left owed; a lesson is an exemplar `(seed, difficulty,
  stepIndex)` and `TechniqueSchool` has no variant axis. PRD-25's surface, unblocked
  by this PRD rather than delivered by it.
- **No device-measured compose time**, the standing gap since PRD-17: every figure
  here is Mac Release and the phone estimate is ×3. PROGRAM-2.0's nightly lane.
- **No fast-seed catalog and no `PuzzleForge` pantry.** PROGRAM-2.0 §Pillar B
  specifies both as cost mitigations. At a 0.03 s p95 there is even less to mitigate
  than there was at killer's 0.14 s.
- **Rule of 45 is still single-unit only** and `cageCombination` still does no
  bipartite matching — both PRD-23's, both unchanged, both still costing an
  elimination rather than causing a wrong one.
- **The nine languages are machine-drafted and no human has read them**, the
  headline deferral standing since PRD-20. 270 new drafts, every one
  `needs_review`. `variantTier.*` reuses `difficulty.*.title`'s drafts verbatim
  rather than inventing a second synonym for an identical meaning.
- **No AI-generated rulesets**, explicitly deferred to 2.x by PROGRAM-2.0: they
  strain the proof covenant until the verifier can gate arbitrary rules. `.arrow`
  remains the case `VariantConstraint`'s tolerant decode was written for and stays
  unwritten — it is now also the case two refusal paths are tested against.
