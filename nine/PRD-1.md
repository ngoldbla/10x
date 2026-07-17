# PRD-1 — Afterglow (win celebration)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one PR
**One-liner:** When you place the winning digit, the board *becomes glass* — a
refractive shockwave detonates from that cell under a haptic crescendo, then the
solved board turns into a tilt-responsive trophy pane. No confetti, ever.

## 1. Why

Nine's win moment today is a 2.6s diagonal luminance wave (`BoardView.swift`)
plus a "Solved" `GlassChip` at 2.4s — deliberately calm, but it under-celebrates.
Confetti would betray the brand. Afterglow escalates with iOS 26-era language
instead: light, refraction, physicality, haptics. It is an evolution of the wave
we already ship, not a bolt-on effect.

There are currently **zero** shaders, haptics, audio, or motion APIs in the app.
Everything hooks into the existing completion pipeline: `AppModel.finishSolve()`
(AppModel.swift:288-322) sets `solvedAt: Date?`, which BoardView and both game
screens already observe.

## 2. The experience

1. **t=0 (final digit placed):** a refractive Liquid-Glass ripple emanates from
   the *last-placed cell* — digits magnify and bend as the crest passes, grid
   lines catch a specular glint. Duration stays 2.6s; the crest reaches the
   farthest corner exactly at the end.
2. **Haptic score (iPhone only):** nine soft transient ticks crescendo as the
   crest crosses the board (0.25s→2.15s, intensity 0.30→0.95), landing one warm
   thump at **2.40s** — exactly when the Solved chip fades in.
3. **t=2.6–5.4s:** one slow autonomous specular sweep across the solved board
   (teaches the affordance; runs on tvOS and simulator too).
4. **t≥5.4s (iOS):** the board is now a glass trophy — tilting the phone steers
   the specular highlight with subtle parallax, capped so it always feels like
   glass catching light, never a gimmick. tvOS: sheen settles to faint static and
   the render loop pauses.
5. **Reduce Motion:** today's exact diagonal luminance wave, byte-for-byte — no
   refraction, no sweep, no motion manager. Haptics still play (haptics are not
   motion; platform convention).

Also in scope as **groundwork only** (no UI): record a move log during play so a
future "solve replay" (a comet retracing your solve path) can ship later.

## 3. Non-goals

- No sound (evaluate a chime later; haptics carry the score for now).
- No solve-replay UI yet — only the move-log data.
- No particles, no confetti, no full-screen overlay.

## 4. Implementation plan

New files: `Sources/App/Afterglow.metal`, `Sources/App/AfterglowHaptics.swift`,
`Sources/App/AfterglowMotion.swift`.
Modified: `Sources/Engine/Game.swift`, `Sources/App/AppModel.swift`,
`Sources/App/BoardView.swift`, `Sources/App/TouchUI.swift`,
`Sources/App/GameScreen.swift`, `Tests/EngineTests/GameTests.swift`.

### Step 1 — Move log + wave origin (Engine + AppModel)

- `Game.swift`: add an engine-pure move log:
  ```swift
  public struct LoggedMove: Sendable, Codable, Equatable {
      public enum Kind: String, Sendable, Codable { case place, erase, pencil, undo }
      public let kind: Kind
      public let cell: Int
      public let digit: Int
  }
  public private(set) var moveLog: [LoggedMove]
  ```
  Append in `place`, `erase`, `togglePencil`, and `undo` — log undo as an
  *event*, never pop the log, so a replay can retrace the true path including
  corrections. No timestamps in v1 (respects the engine's "no hidden clocks"
  rule; order suffices).
- **CRITICAL — tolerant decode:** `NineGame` uses synthesized Codable and
  `CouchStored` discards the whole blob when decode throws. Hand-write
  `NineGame.init(from:)` with `moveLog = try c.decodeIfPresent(...) ?? []`
  (mirror the `NinePrefs` comment explaining why). Skipping this destroys every
  player's in-progress autosave on update.
- Persistence is free: `NineGame` is what `SaveSlot` autosaves.
- Tests: log ordering across place/pencil/undo; a legacy JSON blob *without*
  `moveLog` decodes to `[]`.
- `AppModel`: add `private(set) var lastPlacedCell: Int?` — set in `place()`,
  reset in `resume(_:kind:)`. At `finishSolve()` it is the winning cell by
  definition (works with the DEBUG fill rig too — the final digit is still
  placed by hand).

### Step 2 — Shader + BoardView

- `Afterglow.metal`: two `[[stitchable]]` functions used via **`layerEffect`**
  (the effect needs both displacement and additive color; `distortionEffect`
  can't tint, `colorEffect` can't displace):
  - `afterglowWave(position, layer, origin, progress, maxRadius, amplitude)` —
    gaussian crest at `progress * maxRadius` from the origin; sample displaced
    toward the origin at the crest (magnification) with `1-progress` decay; add
    `band² · 0.22 · decay` white for the glint.
  - `afterglowSheen(position, layer, size, sheenPos, tilt, strength)` — soft
    specular band along the (1,1) diagonal centered at `sheenPos`, sampling at
    `position - tilt * 4.0` for parallax.
- **XcodeGen:** `Sources/App` is a directory source, so the `.metal` file
  compiles into the app target's `default.metallib` automatically (where
  `ShaderLibrary.default` looks) — no `project.yml` edit, but run
  `xcodegen generate` and verify the file landed in Compile Sources.
- `BoardView`: new props `waveOrigin: Int?` and an optional polling closure
  `afterglowTilt: (@MainActor (Date) -> SIMD2<Double>)?`. Add
  `@Environment(\.accessibilityReduceMotion)` (first use in the app). Apply both
  `layerEffect`s **on the Canvas, inside `couchGlass`** — the glass material
  must stay undistorted; only digits/grid refract. The existing post-solve
  `TimelineView(.animation, paused: solvedAt == nil)` is the render loop —
  no new clock.
  - `originPoint = BoardMetrics.center(of: waveOrigin ?? 40, side: side)`;
    `maxRadius` = distance to the farthest board corner.
  - **Retime, don't remove** the existing Canvas luminance boost: when the
    shader wave is active, compute its phase *radially* from the origin so the
    brightening rides the same crest. Reduce Motion keeps today's exact
    diagonal `(row+col)/16` code path. Chip timing (2.4s) untouched.
- Call sites: `TouchUI.swift` (~line 386) and `GameScreen.swift` (~line 66) pass
  `waveOrigin: model.lastPlacedCell`; tilt closure iOS-only.

### Step 3 — Haptic score

- `AfterglowHaptics.swift` (`#if os(iOS)`, `@MainActor` class):
  - **Create the `CHHapticEngine` at solve** (cold start is tens of ms, hidden
    under a 2.6s animation; no warm engine to babysit). Gate on
    `CHHapticEngine.capabilitiesForHardware().supportsHaptics` — this *is* the
    iPhone-only gate (false on iPad and simulator).
  - Pattern: 9 transients at `t = 0.25 + i·0.2375`, intensity 0.30→0.95,
    sharpness 0.35→0.70; final `.hapticContinuous` at t=2.40, duration 0.35,
    intensity 0.6, sharpness 0.15.
  - Stop the engine in `notifyWhenPlayersFinished` (handler runs on CoreHaptics'
    queue — hop back with `Task { @MainActor in ... }`; mind Swift 6 isolation).
    All throws swallowed — haptics must never break the celebration.
- Hook in the **view layer**, not `finishSolve()` (AppModel is platform-shared
  logic; haptics is presentation): `TouchGameScreen` holds
  `@State private var haptics = AfterglowHaptics()` and
  `.onChange(of: model.solvedAt) { _, new in if new != nil { haptics.playSolveScore() } }`.

### Step 4 — Glass trophy pane

- `AfterglowMotion.swift` (`#if os(iOS)` for CoreMotion): wraps
  `CMMotionManager`, 1/60 update interval, **polled** from BoardView's timeline
  closure via the `afterglowTilt` prop (never a handler — avoids an Observation
  invalidation storm and keeps BoardView platform-agnostic). No permission or
  Info.plist key needed for gravity. Capture a baseline pose on first read;
  return `clamp(gravity.xy - baseline, ±0.35)`.
- Choreography — all pure functions of `now - solvedAt` computed in BoardView:
  - `t < 2.6`: wave shader, sheen off.
  - `2.6 ≤ t < 5.4`: autonomous sweep, `sheenPos` eases 0→1 once, slow.
  - `t ≥ 5.4` iOS: gyro steering (`sheenPos = 0.5 + tilt.x·k`, ≤4pt parallax);
    blend from sweep over its last 15% so there's no jump.
  - `t ≥ 5.4` tvOS: sheen fades to faint static over ~1s, then pause the
    TimelineView via a computed `paused:` condition (`solvedAt == nil ||
    afterglowSettled`) — no Siri Remote gyro (GameController IMU not worth it),
    and this also fixes the latent always-running-60fps-after-solve behavior.
- Lifecycle in `TouchGameScreen`: start in the same `.onChange` (skip when
  Reduce Motion); stop on `.onDisappear`, `goHome`, and `scenePhase != .active`.

### Step 5 — Plumbing

- `xcodegen generate` after adding the three files; verify `.metal` in Compile
  Sources. No new privacy-manifest entries expected (verify CMMotionManager
  gravity against the current required-reason list). Note CoreHaptics +
  CoreMotion as suite-firsts in `DEVIATIONS.md` if conventions ask.

Sequence: 1 (testable via `swift test`) → 2 (visible in sim) → 3 & 4 (either
order) → 5 alongside 2.

## 5. Risks

- **Autosave destruction** if the tolerant decode is skipped — highest severity,
  cheap to test with a hand-crafted legacy JSON.
- **Stitchable resolution fails at runtime, not compile time** (wrong signature
  → silent no-op or clear render). Start with a passthrough
  `layer.sample(position)` shader and verify pixels before adding math.
- `layerEffect` outside `couchGlass` would rasterize the material backdrop —
  keep it on the Canvas. Crest displacement near edges samples the padding; the
  28pt inset hides it, but check a corner-origin solve.
- Swift 6 strict concurrency with CoreHaptics/CoreMotion callbacks — keep both
  wrappers `@MainActor`, poll rather than subscribe.
- tvOS 4K perf: single-pass fragment shader over a ~900pt layer — expected fine;
  profile once with the GPU HUD.

## 6. Verification checklist

Simulator (iPhone + Apple TV; DEBUG long-press-Undo → `debugFillAlmostAll()`,
then place the final digit somewhere off-center):
1. Wave emanates from the last-placed cell; corner placement still reaches the
   opposite corner by 2.6s.
2. Digits visibly magnify/bend at the crest; glint tracks grid lines; glass
   plane and background void undistorted.
3. Solved chip still at 2.4s; streak text correct on a daily.
4. One slow autonomous sweep after the wave; simulator (no gyro) then holds
   gracefully — nothing jitters.
5. Reduce Motion ON → today's exact diagonal wave, no refraction/sweep, motion
   manager never started (log/breakpoint).
6. Light mode, all four accents, iPad portrait+landscape (side prop varies).
7. tvOS: wave + sweep only; sheen settles; timeline pauses; Back mid-wave goes
   home cleanly.
8. Move log: place/undo/re-place recorded in order; kill & relaunch mid-game
   restores board *and* log; legacy save without `moveLog` restores fine.

Real iPhone:
9. Haptic crescendo tracks the wave; thump lands with the chip; iPad silent;
   engine stops after (no audio-session hum); backgrounding mid-pattern safe.
10. Tilt steers the specular, capped; baseline captures the natural holding
    pose, not flat-on-table.
