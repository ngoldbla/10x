# PRD-4 — Nine for Mac (keyboard-native desk sudoku)

**Status:** Draft v1 for review · **Thread:** `nine/` · **Scope:** two PRs (4a foundation + full play, 4b desk mode + polish)
**One-liner:** A dedicated macOS Nine where the keyboard is the superpower —
arrows walk the grid, digits type straight in, ⌘Z undoes — and the board can
shrink into a small always-on-top **desk window** that sits beside your work,
inverting PRD-2's lesson: on iPhone we made room for other apps; on the Mac
*we* are the thing you glance at.

## 1. Why

Nine's engine is pure Swift and already builds for macOS (`Package.swift`
declares `.macOS(.v14)` for CI); the board, rose, and celebration are shared
SwiftUI. What's missing is a Mac-shaped body. The lessons earned on the other
platforms point straight at what that body should be:

- **tvOS taught us input is the product.** The remote's superpower was the
  flick rose. The Mac's native superpower is faster still: a full keyboard.
  Median digit entry on a keyboard should beat every other platform.
- **iOS 1.1 taught us respect for platform reach** (thumb-zone controls, light
  mode, resume-on-launch). The Mac equivalents are the menu bar, keyboard
  shortcuts, window management, and system appearance.
- **PRD-2 taught us the multitask posture.** iPhone Nine parks the board so PiP
  can float over it. On the Mac the roles flip: Nine should offer a compact,
  chromeless board window that floats over *your* work between meetings.

### Approaches considered

- **Mac (Designed for iPad)** — rejected. Zero work, but it ships the touch
  grammar behind a pointer, no menu bar, no keyboard-first entry, iOS glass
  rendered through translation. Not "optimized for Mac" by any reading.
- **Mac Catalyst** — rejected. Reuses `TouchUI.swift` at the cost of inheriting
  its touch assumptions forever; Catalyst is the legacy bridge and CouchKit's
  `#if os(iOS)` gates would half-apply in confusing ways.
- **Native macOS destination on the existing universal target** — chosen. Exact
  precedent: PR #9 added iOS to the tvOS app as `supportedDestinations` +
  one platform UI file (`TouchUI.swift`). macOS is the third destination +
  `MacUI.swift`. One bundle id, one engine, one save/streak model.

## 2. The experience

### 2.1 Window & board

One resizable window (default 720×820pt, min 480×560). The board scales with
the window on the same glass plane; the void background and `BreathingVoid`
carry over. Appearance follows the system (or the in-app Appearance pref, as
iOS) — warm paper in light mode. Full screen supported but not the pitch.

### 2.2 Keyboard grammar (Signature)

| Key | Effect |
|---|---|
| Arrow keys | Move cell cursor (wraps at edges) |
| `1`–`9` | Place digit in the cursor cell |
| `⇧1`–`⇧9` | Toggle pencil mark |
| `P` | Sticky pencil mode toggle (chip shows state, as iOS) |
| `Delete` / `0` | Erase user entry |
| `⌘Z` | Undo (glass toast shows the reverted digit) |
| `Space` | Toggle same-number highlight of the digit under the cursor |
| `Tab` / `⇧Tab` | Jump cursor to next / previous empty cell |
| `Esc` | Close rose / sheet; else home |

No modes to learn: the cursor is always live, digits always type. The
never-misfire rule holds trivially — a keypress is unambiguous.

### 2.3 Pointer grammar (secondary, full parity)

Hover halos the cell under the pointer (first hover affordance in the suite).
Click selects; click a selected empty cell and the **flick rose blooms** —
petals are real click targets, and a quick trackpad-style drag toward a petal
places it (same `RoseGeometry`, same forgiveness). The rose is brand identity
and tutorial continuity, not the primary path.

### 2.4 Menu bar & shortcuts

- **Game**: New Game ▸ Gentle/Steady/Sharp (⌘N Steady), Today's Puzzle (⌘T),
  Discard Board.
- **Edit**: Undo (⌘Z).
- **View**: Appearance, Show Timer, Error Highlight, Number Highlight, Enter
  Desk Mode (⌘⇧D), accent tint.
- **Window/Help**: standard; Help ▸ How to Play opens the tutorial.
- Prefs live in the standard **Settings scene (⌘,)** on Mac — same rows as the
  iOS sheet, minus touch-only ones (Controls position, Board position).

### 2.5 Desk mode (Signature Moment, PR 4b)

⌘⇧D collapses the window to a compact ~340pt board-only pane — no header, no
chips, board + nothing — optionally floating above other windows
(`.windowLevel(.floating)`, macOS 15+), remembering its corner. The keyboard
grammar still works whenever it has key focus. This is Nine as a desk toy:
one glance, one digit, back to work. Esc or ⌘⇧D restores the full window.

### 2.6 Feature parity ledger (vs iOS 1.1 + PRDs 1–3)

| iOS-era feature | Mac disposition |
|---|---|
| Same-number highlight | Ported (Space key + click a placed digit) |
| History + points + streak | Ported (History window from Game menu, ⌘Y) |
| Game Center | Ported — GameKit is native on macOS; same leaderboard/achievement IDs (`GameCenter.ID`); `GKAccessPoint` stays hidden, dashboard from Game menu |
| Interactive tutorial | Ported, re-gestured for keyboard (five beats: goal → type → pencil → highlight → difficulty) |
| Afterglow wave + sweep | Shared already (`layerEffect` works on macOS) |
| Afterglow trophy tilt | **Pointer-steered**: hovering the solved board steers the specular highlight (CoreMotion has no meaning on desktop; the pointer is the Mac's tilt) |
| Haptic score | Skipped (no meaningful surface; see Non-goals) |
| Resume on launch | Ported (same pref) |
| Board anchor / ambient slot | Not applicable — desk mode is the Mac's answer |
| Widgets | Deferred (macOS desktop widgets are cheap later via the same snapshot; see Open questions) |

## 3. Non-goals

- No Catalyst, no iPad-compatibility build alongside the native app.
- No trackpad force-touch haptics (cute, inaudible value; revisit never).
- No macOS widgets/menu-bar extra in v1 — desk mode covers the glance case.
- No new gameplay: same engine, same daily (deterministic seed ⇒ the Mac gets
  the identical shared daily), same difficulties.
- No Sparkle/notarized direct distribution — Mac App Store + TestFlight only,
  matching the suite's pipeline.

## 4. Implementation plan

### Step 0 — CouchKit macOS enablement (the real cost; PR 4a)

`couchkit/Package.swift` gains `.macOS(.v15)`. Files today gated
`#if os(tvOS) || os(iOS)` get macOS added **where the APIs are portable**:

- `CouchStore.swift` — `@CouchStored` is Foundation-only; path
  (`Application Support/CouchKit/`, CouchStore.swift:124-129) resolves inside
  the sandbox container on macOS. Gate widens; behavior identical. iCloud KVS
  (`cloudSynced:`) works on macOS unchanged.
- `CouchUI.swift` — `CouchScale.chrome` gains a macOS branch (**0.70**,
  between TV 1.0 and phone 0.55; tune in 4a); `CouchTypography` sizes audit.
- `GlassComponents.swift`, `CouchGlass.swift` — widen gates; the Liquid Glass
  shim's fallback path covers pre-glass macOS. Verify `glassEffect`
  availability annotations compile per-SDK.
- `RemoteKit`, `AsciiEngine`, `PhotoKitPlus` — untouched, stay platform-gated.

Blast radius: the four sibling apps don't declare a macOS destination, so this
is compile-surface only for them. Note the enablement in `DEVIATIONS.md` and
`COUCHKIT-ASKS.md` (heads-up, not an ask — we do it in-repo).

### Step 1 — Target & signing (PR 4a)

- `project.yml`: `supportedDestinations: [tvOS, iOS, macOS]`; per-SDK settings
  following the existing pattern — mac AppIcon (brand-assets script gains a
  `macIcon` emitter: 1024 with margin per HIG), `Nine-macOS.entitlements`
  (App Sandbox **required for MAS** + iCloud KVS + game-center),
  `PROVISIONING_PROFILE_SPECIFIER[sdk=macosx*]`.
- Info: macOS ignores the iOS-only keys already present; add `LSMinimumSystemVersion` via deployment target.
- match: mint `match AppStore com.couchsuite.nine macos` (+ the **Mac Installer
  Distribution** cert — a cert type the account doesn't hold yet; the Apple
  Distribution cert-limit workaround from the tvOS setup may repeat here.
  Sequence portal → mint → CI, exactly the PRD-3 §3 lesson).
- Fastfile: `beta` lane accepts `platform:mac` (`destination:
  "generic/platform=macOS"`, gym exports a signed pkg, pilot uploads — pilot
  supports Mac TestFlight). Build train: `commit_count*10 + 2` (tvOS +0, iOS
  +1; the disjoint-train rule from PR #10 extends).

### Step 2 — MacUI.swift (PR 4a)

New `Sources/App/MacUI.swift` (`#if os(macOS)`), structured as `TouchUI.swift`
is: `MacHomeView` (Today / Continue / Free Play cards, pointer + keyboard
navigable), `MacGameScreen` (board + right-aligned status chips; no control
bar — the menu bar and keys replace it), reusing `BoardView`, `FlickRoseView`,
`GlassChip`, `UndoToastState` unchanged. `RootView` (NineApp.swift:68-84) gains
the `#elseif os(macOS)` branch.

### Step 3 — Input plumbing (PR 4a)

- Keyboard: `.onKeyPress` handlers on the game screen (macOS 14+ API), routed
  through the same `AppModel` mutations the other grammars call. `⌘`-shortcuts
  via SwiftUI `Commands` + `@FocusedValue(AppModel.self)` so menu items
  enable/disable with context (Undo greys out with an empty stack).
- Pointer: `.onContinuousHover` on the board container → `BoardMetrics` cell
  math (the Canvas has no per-cell views; same geometry code the touch path
  uses) → hover halo drawn in-canvas.
- Rose on Mac: petals get `.onTapGesture` plus the drag-classifier path
  (`TouchRose`'s `flickDirection` moves to a shared helper — it is pure math).

### Step 4 — Parity ports (PR 4a)

- `GameCenter.swift`: gate widens `#if os(iOS) || os(macOS)`; dashboard
  invocation branches (`GKGameCenterViewController` via
  `NSViewControllerRepresentable`… or `GKAccessPoint.trigger` — decide in
  implementation, both are macOS-supported).
- `HistorySheet.swift`, `TutorialView.swift`: gates widen; tutorial beat copy
  swaps gesture nouns per platform (a `TutorialGrammar` struct, also needed by
  PRD-5 — coordinate).
- Afterglow: `BoardView.afterglowTilt` closure fed by hover position instead
  of CoreMotion (`AfterglowMotion` stays iOS-gated; a tiny
  `AfterglowPointer.swift` maps hover offset → the same `SIMD2<Double>`).

### Step 5 — Desk mode (PR 4b)

Window state enum on `AppModel` (`full`/`desk`); desk applies
`.windowResizability(.contentSize)`, fixed content, `.windowLevel(.floating)`
toggle, `.persistentSystemOverlays(.hidden)`. Frame autosaved. Menu item +
⌘⇧D + a small corner glyph on hover.

## 5. Risks

- **CouchGlass on macOS**: the shim was only ever exercised on tvOS/iOS; if the
  macOS fallback renders flat, budget a material-tuning pass (glass is the
  brand — a flat Mac build does not ship).
- **Per-SDK settings sprawl** in one target (three destinations × icons ×
  entitlements × profiles). If xcodegen fights us, fallback is a separate
  `NineMac` target sharing the same sources — a mechanical change, decided in
  4a, not a redesign.
- **Sandbox + existing saves**: fresh install surface only (no prior Mac
  users), but verify KVS-synced streak/history arrive on first launch.
- **Keyboard focus wars**: SwiftUI key handling vs. menu shortcuts vs. the
  Settings scene. Keep one `focusable` game surface owning `onKeyPress`
  (mirrors the tvOS "one focusable board" rule that already works).
- **Mac Installer cert mint** blocked by account limits → TestFlight blocked;
  discover in week one, not at ship.

## 6. Verification checklist

1. `xcodegen generate`; build all three destinations; tvOS + iOS byte-identical
   behavior (their entitlements/profiles untouched).
2. Keyboard: solve an entire Gentle board without touching the mouse; every
   table row in §2.2 behaves; Tab skips givens.
3. Pointer: hover halo tracks; click-select; rose blooms, petal click and
   petal drag both place; never a misfire from a sloppy drag.
4. Menu: every item routes; Undo enables/disables with stack state; ⌘, opens
   Settings with parity rows; shortcuts don't fire while Settings has focus.
5. Daily determinism: same date ⇒ Mac and iPhone generate the identical board.
6. Streak/history KVS round-trip Mac ↔ iPhone (solve on one, see it on the
   other within KVS latency).
7. Afterglow: wave + sweep on solve; pointer steers the trophy sheen; Reduce
   Motion (System Settings) falls back to the diagonal wave.
8. Desk mode: collapse, float over another app's window, place a digit by
   keyboard, restore; frame position survives relaunch.
9. Light/dark: system auto + explicit pref, both window sizes.
10. `fastlane beta app:nine platform:mac upload:false` exports a signed,
    sandboxed pkg; `codesign -d --entitlements -` shows sandbox + KVS +
    game-center.

## 7. Open questions

- Desk mode default: float-on-top on by default, or opt-in per session?
  (Leaning opt-in with the state remembered.)
- macOS desktop widgets (the PRD-3 family renders on Mac with little work once
  a snapshot writer exists on macOS) — 4c candidate, decide after 4b ships.
- `CouchScale.chrome` 0.70 is a guess until the first screenshot review.
