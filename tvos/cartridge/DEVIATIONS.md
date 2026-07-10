# Cartridge — deviations from PRD v1

Sanctioned cuts and pragmatic calls, with reasons. Nothing here violates the
four-scheme law or the pure-engine boundary.

## Sanctioned scope cuts

- **Four games instead of six.** Stomp (A) and Shuttle (B) cut per PRD §11's
  own contingency ("cut Stomp and Shuttle first — scheme duplicates, never
  the feed polish"). Launch lineup covers every scheme exactly once:
  Flap (A · click), Noodle (B · swipe-steer), Quadrant (C · four-way snap),
  Putt (D · hold-and-release).
- **Top Shelf skipped** — suite-wide decision for this round (PRD §8).
- **Sound omitted in v1** (PRD §6 wants ≤4 chiptunes/game + a zap). The
  audio-ducking channel transition is likewise deferred with it.
- **Saliency/pet/face subject detection replaced by center-crop + circular
  knockout** (PRD §5.3). PhotoKitPlus exposes no saliency API today; the ask
  is filed in COUCHKIT-ASKS.md. Center-crop at 24×24 `.pixel` reads great at
  arcade sizes and is fully deterministic.
- **Multi-user profiles not wired** (PRD §8): bests/prefs use CouchStore's
  default profile. The `profile:` parameter exists on every `@CouchStored`
  call site when the suite turns this on.

## Design/implementation calls

- **Feed paging is bespoke state, not ScrollView**: a ring pager driven by
  `.couchRemote` swipe(.up/.down), vertical push via offsets animated with
  `.couchFast`, wrap-around ring so the feed is "bottomless" with 4 channels.
- **Only the visible channel's attract mode ticks**; neighbor channels hold
  their last frame (they warm up instantly on arrival). Keeps the 60 fps
  floor honest with one Canvas active.
- **Menu/Back handling**: the suite rule says `interceptsBack: false` at the
  app root, but in-game Back must return to the feed, not exit the app. The
  root toggles `interceptsBack: model.mode != .feed`. From the feed, Back
  exits to tvOS as the suite requires.
- **`playPauseLongPress` needs the 8-way reader** (RemoteKit only times the
  button there), so the root enables `eightWay: true` and ignores `.flick`.
  If the system also delivers the short `.playPause` on the same press, the
  worst case is pause + prefs — both reversible with one input.
- **Life cap**: every game hard-ends at 90 s (PRD §3 "no game longer than
  90 seconds per life"), enforced in the engine, tested.
- **Verdict card listens on swipe ↓ too** (previous channel) — same beat as
  swipe ↑, zero extra chrome.
- **Putt cup capture requires arrival speed ≤ 6 u/s** — blasting over the
  hole rolls on, keeping the hold-and-release timing meaningful.
- **Bots are pure functions of visible state** (no RNG), which makes attract
  mode, the winnability tests, and determinism tests share one code path —
  this is the PRD §7 verifier pattern actually enforced in CI.

## Verification notes (Linux container, no Xcode)

- `swift build` / `swift test` cover `Sources/Engine` + `Tests/EngineTests`
  (36 tests green; determinism, bot winnability ≥10 s/game, game-over,
  collision edges, mutator bounds, feed order, score book).
- `Sources/App` (SwiftUI/tvOS) cannot compile here; every CouchKit call was
  hand-checked against `couchkit/Sources/` signatures (RemoteKit, Glass
  components, AsciiEngine, PhotoKitPlus, CouchUI, CouchStore) as the final
  step. Known residual risk: strict-concurrency diagnostics around CGImage
  crossing into the `AsciiEngine` actor — the same pattern CouchKit's own
  `AsciiArtView` uses, so any fix lands in CouchKit first.
