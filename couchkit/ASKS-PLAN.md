# CouchKit asks — triage & response plan

Consolidated response to the five `COUCHKIT-ASKS.md` files (Blockhead,
Cartridge, Darkroom, Nine, Rabbit Ears). Every ask gets a decision here:
**accept**, **accept (modified)**, **document**, or **defer** — with the
design choice and rationale. Nothing blocks any app today (all shipped with
workarounds), so this is sequenced by how many apps each fix unblocks and by
risk to the input grammar.

## Decision summary

| # | Ask | Raised by | Decision | Milestone |
|---|-----|-----------|----------|-----------|
| 1 | `playPauseLongPress` without the 8-way reader | BH3, C3, DR2, RE5 | **Accept** — always-on button reader | M1 |
| 2 | Suppress `.playPause` on long press (double-fire) | C4, DR1, N3 | **Accept** — emit-on-release, exactly one gesture | M1 |
| 3 | Deliver ambiguous flicks (`flickAmbiguous(a, b)`) | N1 | **Accept** | M1 |
| 4 | Suppress `.flick(.center)` when the stroke contained a click | N2 | **Accept** | M1 |
| 5 | `dragStep(x:y:)` between `holdBegan`/`holdEnded` | DR3 | **Accept** | M1 |
| 6 | Move-command velocity / key-repeat metadata | DR5 | **Defer** — no shipped moment needs it | — |
| 7 | `.couchRemote` menu mode / focus passthrough | BH1 | **Accept (modified)** — `enabled:` param + documented menu pattern; `.observe` deferred | M2 |
| 8 | `GlassSheet` should capture focus | RE4, N4 | **Accept** | M2 |
| 9 | Document the sheet/remote focus hand-off | N4 | **Accept** (API.md) | M2 |
| 10 | `GlassRing` `animation:` parameter | BH2 | **Accept** | M2 |
| 11 | Public `transientChrome(_:)` treatment | RE1 | **Accept** | M2 |
| 12 | `GlassPill` with custom content | RE2 | **Accept** | M2 |
| 13 | Phase-preserving pausable clock | BH4 | **Accept** (CouchCore `PausableClock`) | M2 |
| 14 | `CuratedPhoto` orientation/aspect metadata | C2 | **Accept** | M3 |
| 15 | `demoPhotos` can repeat ids in one call | RE6 | **Accept** — window = count − 1 | M3 |
| 16 | Subject-aware crops (`subjectRect`) | C1 | **Accept** — Vision saliency | M3 |
| 17 | Location labels for real assets | DR4 | **Accept (modified)** — async resolver + cache | M3 |
| 18 | `canvas:` passthrough on `render(image:)` | C5 | **Accept** | M4 |
| 19 | Alpha-preserving `cgImage(from:)` | C6 | **Accept** | M4 |
| 20 | Style-wipe pair rendering + pre-render cache | RE3 | **Accept (modified)** — cache + `prewarm` + mask-composite wipe view | M4 |
| 21 | Animated grain on frozen frames | RE7 | **Accept (modified)** — overlay, not renderer plumbing | M4 |
| — | `CouchStored` dictionary pattern confirmation | BH5 | **No action** — noted as endorsed pattern in API.md | M5 |

(BH = Blockhead, C = Cartridge, DR = Darkroom, N = Nine, RE = Rabbit Ears.)

---

## M1 — RemoteKit input correctness

The highest-leverage milestone: four of five apps carry workarounds for the
play/pause path, and Nine's double-fire workaround costs gameplay state.
All changes land in `RemoteKit.swift` + `CouchCore/Flick.swift`.

### 1+2. One play/pause path, one gesture per press

Today the button is handled twice: the base path emits `.playPause` from
`onPlayPauseCommand` on press, and `MicroGamepadFlickReader.handlePlayPause`
times `buttonX` for `.playPauseLongPress` on release — so 4-way apps can't
get the prefs gesture at all, and 8-way apps get both gestures for one long
press. Fix both with one design:

- Extract the `buttonX` timing out of `MicroGamepadFlickReader` into a
  standalone `PlayPauseButtonReader` (GameController, button only — no
  analog dpad, no `reportsAbsoluteDpadValues`). `CouchRemoteModifier`
  starts it unconditionally, independent of `eightWay`.
- While a controller is attached, the reader owns the button and emits
  **exactly one** gesture on release: `.playPause` if held < 0.6 s,
  `.playPauseLongPress` if ≥ 0.6 s. The SwiftUI `onPlayPauseCommand`
  emission is suppressed whenever the reader is live.
- If no `GCController` is present, fall back to today's behavior:
  `onPlayPauseCommand` → `.playPause`, no long press. On real hardware the
  Siri Remote always surfaces as a controller, so in practice every device
  gets the suite prefs gesture; the docs keep "also expose the sheet from a
  pill action" as the belt-and-braces rule for ambient apps (RE5's concern).
- The press classification (duration → tap/long) becomes a pure function in
  CouchCore next to `FlickThresholds` so it's unit-testable.

Behavior change to call out: `.playPause` now fires on **release**, not
press. A tap is < 300 ms so the added latency is imperceptible, and it is
the only way to disambiguate — accepted.

### 3. `flickAmbiguous` with the two candidate sectors

`FlickClassifier` already computes the stroke angle; add
`FlickClassifier.neighbors8(dx:dy:) -> (Direction8OrCenter, Direction8OrCenter)`
returning the sectors on either side of the boundary the stroke fell on.
The reader's `finishStroke` forwards `.ambiguous` results as a new gesture:

```swift
case flickAmbiguous(Direction8OrCenter, Direction8OrCenter)
```

The never-misfire rule holds — no digit is placed; apps that ignore the new
case lose nothing. Nine's shimmer is already wired to consume it.

### 4. Click-during-stroke suppression

The reader observes `buttonA.pressedChangedHandler`; if a digital click
occurred during the current touch, `finishStroke` suppresses a resulting
`.flick(.center)` (directional flicks still deliver — a click then a real
flick is intentional). The click itself still arrives as `.click` via the
tap gesture. Removes Nine's 0.4 s heuristic.

### 5. `dragStep` during hold

New gesture `case dragStep(x: Int, y: Int)`. When the 8-way reader is
running and the modifier has emitted `holdBegan`, per-sample dpad deltas are
fed through `CouchCore.CellStepAccumulator` (which exists for exactly this)
and non-zero steps are emitted until `holdEnded`. On 4-way systems there is
no analog stream, so apps keep the repeated-swipe fallback — document that.

### 6. Velocity/repeat metadata — deferred

Momentum cursors are speculative: no PRD moment in the five apps needs them
once `dragStep` exists, and exposing raw velocity invites per-app
re-derivations of flick math that CouchCore is supposed to own. Revisit with
a concrete design moment.

**Compatibility:** two new `CouchGesture` cases break exhaustive switches in
the apps. The suite is a monorepo — update all five apps in the same PR.

**Tests:** press classification, `neighbors8` boundary math,
accumulator-driven drag sequences, and center-suppression decision logic all
live in CouchCore as pure functions with `CouchCoreTests` coverage. The
GameController glue stays thin and is verified on hardware.

---

## M2 — Focus & Glass components

### 7. `.couchRemote` and system focus

The root ask (a `.observe` mode that reports gestures without claiming
focus) can't be built on SwiftUI commands — `onMoveCommand` only fires on
the focused view. A GameController-backed observe mode is possible but
would duplicate the 4-way path with weaker guarantees, so it's **deferred as
an investigation**, not promised. What ships instead:

- `couchRemote(enabled:)` (default `true`). When `false` the modifier drops
  `.focusable()` and all handlers, letting system focus walk real focusable
  elements (menu slabs, sheet buttons). This blesses the detach pattern Nine
  discovered.
- API.md gets a **"Menus and sheets"** section documenting the two endorsed
  patterns: (a) model-driven selection with `FocusHalo`-style treatment for
  gesture-first screens (Blockhead's workaround, now canonical), and
  (b) `couchRemote(enabled: !sheetPresented)` for `GlassSheet` hosts.

### 8+9. `GlassSheet` captures focus

`GlassSheet` already has a `focusSection()`; add `@FocusState` +
`.defaultFocus` so presentation moves focus into the sheet. That makes its
`.onExitCommand` reliably see Back (Menu can no longer exit the app from an
open sheet — RE4's failure mode) without requiring the host to do anything
beyond the `enabled:` hand-off above.

### 10. `GlassRing(progress:lineWidth:animation:)`

Add `animation: Animation? = .couchFast`; `nil` renders the value as given.
Default preserves current behavior for discrete progress; Blockhead's
30 Hz countdown passes `nil`.

### 11. Public `transientChrome(_:)`

`TransientChrome` already exists as an internal modifier; expose

```swift
extension View {
    public func transientChrome(_ chrome: ChromeVisibility, hiddenOffsetY: CGFloat = 24) -> some View
}
```

and rebase `GlassPill` on it so custom chrome and stock chrome can't drift
apart. Rabbit Ears deletes its duplicated modifiers.

### 12. `GlassPill` with custom content

Add a generic initializer `GlassPill(chrome:) { content }` hosting arbitrary
content in the same capsule chrome; the `[GlassAction]` initializer becomes
a convenience over it. Rabbit Ears' style pill (colored dots / live
previews) uses the generic form.

### 13. `PausableClock` in CouchCore

A small value type alongside `DriftPath`: feed it wall time, it returns
content time; `pause()`/`resume()` accumulate an offset so resumed
animations keep phase instead of snapping to absolute time. Pure and
deterministic (time is injected, never read), so it tests like everything
else in CouchCore. Blockhead's stage-light sweep is the first consumer.

---

## M3 — PhotoKitPlus

Ordered cheapest-first; the first two are near-trivial wins.

### 14. Orientation metadata on `CuratedPhoto`

Add `pixelSize: CGSize?` (from `PHAsset.pixelWidth/pixelHeight`; demo
photos report their 16:9 render size) plus a derived `isLandscape`
convenience. Stored at curation time — no pixel decode. Cartridge routes
actor vs. backdrop lanes without loading full images.

### 15. `demoPhotos` duplicate ids

Draw with `window: recipes.count - 1` (as the ask suggests) so any
`limit ≤ recipes.count` result is duplicate-free. **Note:** this changes the
deterministic sequence for existing seeds — an ambient session resumed
across the update will land on a different order once. Acceptable for a
correctness fix; called out in the changelog.

### 16. `subjectRect` via Vision

```swift
extension CuratedPhoto {
    public func subjectRect(maxDimension: Int = 960) async -> CGRect?
}
```

Implementation: `VNGenerateAttentionBasedSaliencyImageRequest` for the
salient bounding box, unioned with face/animal rectangles when present
(that's the "that's MY cat" ask). Runs on the decoded buffer PhotoKitPlus
already produces; returns `nil` for demo photos and on any Vision failure so
callers keep the center-crop fallback. Guarded `#if canImport(Vision)`.

### 17. Location labels

Keep the stored `locationLabel` as-is (`nil` for assets — curation must stay
synchronous and offline). Add an async resolver:

```swift
extension CuratedPhoto {
    public func resolvedLocationLabel() async -> String?
}
```

Backed by `CLGeocoder` reverse geocoding of `PHAsset.location`, with an
in-memory cache keyed by coarse-rounded coordinates (~1 km) so a library
clustered around home resolves once, respecting geocoder rate limits.
Darkroom's develop chip requests it lazily and shows the date-only string
until it lands — matching the PRD's "October 2016 · Portland".

---

## M4 — AsciiEngine & render pipeline

### 18. `canvas:` on `render(image:)`

Pure sugar: add `canvas: CGSize? = nil` to `render(image:)` and
`renderDemo`, passed through to `draw(grid:style:canvas:)` (which already
takes it). Cartridge's sprite path collapses to one call.

### 19. Alpha-preserving `cgImage(from:)`

Add `preservingAlpha: Bool = false`; when `true`, use `premultipliedLast`
instead of `noneSkipLast`. `PixelBuffer` already carries the alpha byte.
Default keeps today's opaque behavior.

### 20. Style wipe + pre-render (the `renderStream` PRD reference)

Rendering per seam position would re-run the CPU pipeline every frame —
wrong shape. Two pieces instead:

- **Render cache + prewarm.** An LRU cache inside the `AsciiEngine` actor
  keyed by caller-supplied identity (photo id + style + grid + seed —
  `CGImage` identity is not stable across loads), with
  `prewarm(key:image:style:grid:seed:)` and a cache-aware `render`. "Pre-render
  the next frame during dwell" becomes literal.
- **`AsciiWipeView(leading:trailing:seam:)`** in CouchKit: composites two
  already-rendered frames with a moving mask, so the wipe costs two cached
  renders total, not one per seam position. The wipe signature moment is a
  mask animation, which the compositor does for free.

API.md documents the pair as the endorsed crossfade/wipe recipe and retires
the phantom `renderStream` reference from the PRD.

### 21. Grain alive during freeze

Plumbing shader time into the CPU renderer would mean re-rendering a 1080p
CoreText pass at 30 Hz — rejected on the canvas-policy grounds at the top of
`AsciiEngine.swift`. Instead: a `FilmGrainOverlay` view (seeded animated
noise via a SwiftUI `colorEffect` shader, `TimelineView`-driven) composited
above the frozen frame, and an optional `grain:` parameter on
`AsciiArtView`. The frame stays frozen; only the cheap overlay animates.
Deterministic per seed, per suite rules.

---

## M5 — Documentation & app cleanup

- **API.md:** new gestures, `enabled:`, `transientChrome`, generic
  `GlassPill`, `PausableClock`, `subjectRect`, `resolvedLocationLabel`,
  render cache/wipe recipe, the "Menus and sheets" focus section, and a note
  endorsing Blockhead's `[String: EpisodeResult]` + sorted-keys `CouchJSON`
  pattern (BH5 — confirmed, no change needed).
- **Per-app workaround removal** (each app's thread, after the kit lands):
  - *Blockhead:* drop `eightWay: true` + `.flick` filtering (1); pass
    `animation: nil` to `GlassRing` (10); adopt `PausableClock` (13).
  - *Cartridge:* drop the 8-way reader (1), delete the long-press debounce
    (2), collapse sprite rendering to `render(canvas:)` (18), adopt
    `subjectRect` (16) and `pixelSize` (14), alpha sprites (19).
  - *Darkroom:* delete the ✕-mark undo-on-long-press workaround (2), drop
    the analog reader (1), adopt `dragStep` for drag-fill (5), adopt
    `resolvedLocationLabel` (17).
  - *Nine:* delete the re-apply-undo heuristic (2) and the 0.4 s center-flick
    swallow (4), wire `flickAmbiguous` to the waiting shimmer (3), replace
    manual `.couchRemote` detach with `enabled:` (7/8).
  - *Rabbit Ears:* delete duplicated chrome modifiers (11), rebuild the style
    pill on generic `GlassPill` (12), adopt prewarm + `AsciiWipeView` (20),
    grain overlay (21), drop the id dedupe (15).
- **Update each `COUCHKIT-ASKS.md`** with resolution status per item.

## Sequencing & risk notes

1. **M1 first and alone.** It touches the input grammar every app depends
   on, adds enum cases that break switches, and changes `.playPause` timing
   (press → release). One PR, all five apps updated, verified on hardware.
2. **M2–M4 are independent** of each other and can land in any order or in
   parallel; none changes existing behavior by default (every new parameter
   defaults to today's semantics), except the `demoPhotos` sequence change
   (15), which is called out above.
3. **Deferred, tracked, not forgotten:** `.observe` mode for `couchRemote`
   (7) and move-command velocity metadata (6). Both need a concrete design
   moment before they earn API surface.
