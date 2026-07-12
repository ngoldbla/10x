# PRD — CouchKit (shared tvOS foundation)

**Status:** Draft v1 · **Thread:** `couchkit/` · **Type:** Swift Package (library), no app target
**Consumers:** Rabbit Ears, Darkroom, Nine, Blockhead, Cartridge

## 1. Purpose

CouchKit is the boilerplate the five Couch Suite apps share so that each app thread
can stay tiny and focused on its one loop. It owns the four things every app needs
and no app should reimplement: the Liquid Glass design system, the Siri Remote
gesture grammar, the photo→pixel/ASCII render engine, and photo library access +
lightweight persistence.

CouchKit is **interface-first**: this PRD defines the public API contract. App
threads build against these protocols from day one, stubbing until CouchKit lands.

## 2. Goals

- One import gives an app the suite look, the suite gesture grammar, and the render
  engine.
- Zero configuration: sensible defaults everywhere; every knob has a default.
- Small enough to audit: target ≤ 4,000 lines of Swift for the MVP surface.

## 3. Non-goals

- No networking, no accounts, no analytics, no AI/generation code (that lives in
  individual apps, post-MVP).
- No UIKit component wrappers. SwiftUI only.
- No cross-app data sharing in v1 (the Rabbit Ears ⇄ Darkroom gallery flywheel is a
  documented v2 concept, not built now).

## 4. Package structure

```
CouchKit (Swift Package, tvOS 26+, Swift 6 strict concurrency)
├── CouchUI        — Liquid Glass design system
├── RemoteKit      — Siri Remote gesture grammar
├── AsciiKit       — photo → ASCII / pixel-art render engine (Metal)
├── PhotoKitPlus   — photo library access + curation queries
└── CouchStore     — JSON persistence + iCloud key-value sync
```

Apps depend on CouchKit via local path: `.package(path: "../couchkit")`.

## 5. Module specs

### 5.1 CouchUI — the Liquid Glass design system

The suite's visual voice. Everything here follows “Pixels under glass” (see suite
README): content full-bleed, chrome transient glass.

**Components (complete MVP list):**

| Component | Description |
|-----------|-------------|
| `GlassPill` | Capsule control strip that floats near the bottom edge. Hosts 1–5 `GlassAction` items. Appears on remote touch, recedes after 3s idle (animatable opacity+blur+y). Built on `GlassEffectContainer` so adjacent pills merge fluidly. |
| `GlassChip` | Small caption capsule (e.g. “June 2019 · Lake Tahoe”). One line, SF Pro, vibrancy text. |
| `GlassSheet` | Full-height trailing sheet on `.glassEffect(.regular)` for the rare secondary surface (hint coach, pack picker). Dismisses on Back. Only one may exist per app. |
| `GlassRing` | Circular progress/timer (Blockhead timer, Darkroom develop progress). Stroke picks up content color via vibrancy. |
| `FocusHalo` | Standard focus treatment for full-bleed tiles: scale 1.0→1.03, specular sweep, soft shadow lift. Wraps `.hoverEffect`-style tvOS focus so all apps focus identically. |
| `CouchTypography` | Type ramp: Display (SF Pro Rounded, heavy, 96pt), Title (64), Body (38), Caption (29) — all sized for 3m viewing distance. |
| `CouchPalette` | Dark-first tokens: `.void` (true black), `.ink`, `.paper`, plus `AccentDerivation` which extracts a safe accent from the current content image (dominant hue, clamped luminance) so glass tints follow the art. |
| `IdleAttract` | Modifier: after N seconds without remote input, fades chrome to zero and starts a slow content drift (Ken Burns). Every app's default resting state. |

**Rules baked in:** no component draws opaque backgrounds; all glass respects
`GlassEffectContainer` merging; all animation via spring presets `couchFast`
(180ms) and `couchAmbient` (2.4s).

### 5.2 RemoteKit — the gesture grammar

One place where clickpad input is interpreted, so every app feels identical in the
hand and per-app code never touches raw events.

**API surface:**

```swift
// Declarative gesture intents an app subscribes to
enum CouchGesture {
    case swipe(Direction4)          // discrete flick: up/down/left/right
    case flick(Direction8OrCenter)  // 3×3 rose: 8 directions + tap (Nine's digits)
    case click                      // clickpad press
    case holdBegan, holdEnded       // long-press on clickpad
    case playPause
    case playPauseLongPress         // suite-wide: opens the app's single prefs sheet
    case back                       // Menu/Back — apps get it AFTER system handling
}

struct CouchRemote: ViewModifier {
    // .couchRemote(scheme:) — attach a GestureScheme; RemoteKit arbitrates
}
```

**Behaviors it owns (apps must not reimplement):**
- **Flick-rose detection** with a forgiveness cone: diagonal vs cardinal
  classification with hysteresis; ambiguous flicks (within 8° of a boundary) are
  returned as `.ambiguous` so the app can ignore rather than misfire. This is
  load-bearing for Nine.
- **Rest-touch rejection:** thumb resting on the clickpad ≠ input.
- **Drag-fill streams** (Darkroom): hold + move emits a cell-step stream.
- **Standard exits:** Back at app root shows nothing custom — defer to system.
- **Old-remote fallback:** 1st-gen remotes lack reliable 8-way; RemoteKit reports
  `capability: .fourWay` and apps must offer degraded paths (Nine shows an on-screen
  rose to click through).

### 5.3 AsciiKit — the render engine

A Swift/Metal port of the `asciify-them` pipeline (`ImgProcessor` → `Renderer`),
restructured as compositable stages, targeting 4K at 60fps for ambient animation.

**Pipeline stages (mirroring the Python original):**
1. `Downsample(grid:)` — image → W×H cell grid, aspect-ratio-correct.
2. `Quantize(paletteSize:)` — k-means or fixed-palette color reduction.
3. `EdgeField` — Sobel/Canny edge magnitude + angle per cell (vImage/MPS).
4. `Render(style:)` — cells → pixels via one of the shipped styles.

**Shipped styles (exactly five, no more):**

| Style | Description |
|-------|-------------|
| `.terminal` | Classic colored ASCII, density-ranked charset, subtle CRT glow |
| `.phosphor` | Monochrome green/amber terminal, scanline shader |
| `.pixel` | Pure pixel-art quantization (no glyphs), chunky 8-bit palette |
| `.inkline` | Edge-only line art using angle-mapped glyphs (`/ — \ |`), paper tint |
| `.mosaic` | Large soft “tiles” — the gentlest, most photographic style |

**API:**
```swift
let frame = try await AsciiEngine.shared.render(
    image: cgImage, style: .terminal,
    grid: .fit(cols: 160), motion: .drift(seed:)   // deterministic Ken Burns
)
// Also: AsciiEngine.renderStream(...) -> AsyncSequence<Frame> for crossfading pairs
```

Determinism requirement: same input + seed ⇒ same output (needed by Darkroom's
puzzle compiler and by resumable ambient sessions).

### 5.4 PhotoKitPlus — library access + curation

- Wraps PHPhotoLibrary (tvOS iCloud Photos, read-only): authorization flow with a
  single beautiful pre-prompt screen component (`PhotoPermissionView`, glass, one
  sentence, one button).
- Curation queries used by multiple apps: `onThisDay()`, `randomMemorable()`
  (favorites + high aesthetic score), `album(named:)`, `recentHighlights(limit:)`.
- All fetches return `CuratedPhoto { asset, displayDate, locationLabel? }` sized for
  the request — apps never touch PHImageManager directly.
- Graceful empty-library mode: ships with 12 bundled CC0 photographs so every app
  demos beautifully with zero permissions (also the App Review path).

### 5.5 CouchStore — persistence

- `@CouchStored` property wrapper: Codable value → JSON on disk, debounced writes.
- Optional `.cloudSynced` flag → NSUbiquitousKeyValueStore mirror (streaks survive
  Apple TV resets; tvOS local storage is purgeable, so anything precious must sync).
- Per-profile awareness: keys are namespaced by the current tvOS user profile.

## 6. What CouchKit deliberately does NOT include

- Game/puzzle logic of any kind (each app owns its engine).
- Top Shelf extension code (each app owns its own; CouchKit provides only image
  rendering helpers they may call).
- Sound. Each app ships its own tiny sound set; CouchKit defines only the rule
  (all UI sounds ≤ −18 LUFS, no sound in ambient states).

## 7. Milestones

- **M0 — Interface freeze (docs only):** public API in this PRD refined into
  `Sources/**/Interface.swift` stubs. Apps unblock here.
- **M1 — CouchUI + RemoteKit** functional (apps can build real UI).
- **M2 — AsciiKit** at 4K/60 with all five styles + determinism tests.
- **M3 — PhotoKitPlus + CouchStore**, bundled demo photos, sample app target
  (`CouchKitGallery`) that cycles every component and style for visual QA.

## 8. Acceptance criteria

- A blank app importing CouchKit reaches the suite look with < 30 lines of code
  (background, one GlassPill, IdleAttract, remote handling).
- AsciiKit renders a 12MP photo to 4K `.terminal` in < 50ms steady-state.
- Flick-rose misclassification < 2% in a 500-flick manual test; rest-touch false
  positives: zero in a 10-minute hold test.
- All five styles pass the screenshot test on the bundled demo photos.
