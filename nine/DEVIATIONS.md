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

## Kept

- Background luminance breath (8–10 %, 60 s) — implemented (`BreathingVoid`),
  though listed as optional.
- Error highlight = coral underline **plus** dot marker (colorblind-safe),
  toggleable; timer off by default; one GlassSheet; no text entry; dark-first
  full-bleed; undo on play/pause with a glass toast; hold-click pencil rose;
  four-way fallback rose.
