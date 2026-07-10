# The Couch Suite — five tvOS apps, one shared foundation

A family of five small, gorgeous, remote-first Apple TV apps. Each app is deliberately
feature-limited: one core loop, executed beautifully, full screen, native tvOS 26
Liquid Glass. Looks and simplicity outrank feature count everywhere.

## The apps

| Folder | App | One-liner | Remote-fit |
|--------|-----|-----------|------------|
| `rabbit-ears/` | **Rabbit Ears** | Your photo library as a living, conductable ASCII/pixel-art channel | 10/10 |
| `blockhead/` | **Blockhead** | A nightly game-show ritual where the four swipe directions are the four answers | 9.5/10 |
| `darkroom/` | **Darkroom** | Picross puzzles compiled from your own photos — solving develops the memory | 9/10 |
| `cartridge/` | **Cartridge** | Channel-surf a bottomless feed of one-input micro-games starring your photos | 8/10 |
| `nine/` | **Nine** | Variant sudoku with a 3×3 flick-rose digit entry and a proof-checked puzzle engine | 7.5/10 |

Plus the shared foundation:

| Folder | Package | Role |
|--------|---------|------|
| `couchkit/` | **CouchKit** | Shared Swift package: Liquid Glass design system, remote gesture grammar, photo→pixel/ASCII render engine, photo library access, persistence |

## Shared art direction: “Pixels under glass”

Every app follows the same visual thesis, so the suite feels like one brand:

1. **Content is full-bleed and edge-to-edge.** The art, the board, the game — it owns
   all 3840×2160 pixels. No letterboxing, no persistent nav bars, no sidebars.
2. **Chrome is Liquid Glass, floating, and transient.** Controls are small glass
   islands (`.glassEffect`) that appear on remote touch and recede after ~3s of
   stillness. The default state of every screen is *zero visible UI*.
3. **Retro content, modern glass.** The pixel/ASCII aesthetic lives in the content
   layer only. The interface layer is pure tvOS 26 — glass capsules, lensing,
   focus-driven specular highlights. Never pixel-art buttons.
4. **Motion is slow and physical.** Crossfades ≥ 2s in ambient contexts, spring
   responses < 200ms on focus. Nothing blinks. Nothing bounces twice.
5. **Dark-first.** All apps assume a dim living room. Backgrounds are true black or
   deep photo-derived tones; glass elements pick up content color via vibrancy.

## Development model — read this before building

Each app is an **independent development thread** built by its own agent in its own
subfolder. The rules that keep threads independent:

- **One folder, one thread.** An app agent may modify only its own folder. Nothing
  outside it.
- **CouchKit is a dependency, not a shared playground.** Apps consume CouchKit via a
  local SwiftPM path dependency (`../couchkit`). App agents must not edit CouchKit.
  If an app needs a CouchKit change, record it in the app folder's `COUCHKIT-ASKS.md`
  and build against the current interface in the meantime (copy a shim locally if
  blocked). The CouchKit thread periodically triages asks.
- **CouchKit ships first.** Its PRD defines the interface contract each app builds
  against. Until CouchKit lands, app agents may stub its protocols locally.
- **Project generation mirrors the parent repo:** each app folder contains a
  `project.yml` (XcodeGen spec) that produces its `.xcodeproj`. No hand-maintained
  project files.
- **Deployment target: tvOS 26.0.** Swift 6, SwiftUI only. No UIKit view controllers
  except where tvOS APIs require (Top Shelf extension).

## Definition of done (all apps)

- Launches to its core experience in **≤ 2 seconds** with **zero onboarding screens**
  (a single system permission prompt is allowed where required, e.g. Photos).
- Fully operable with a Siri Remote (2nd gen+) alone. Every screen answers: swipe,
  click, hold, play/pause, back. No text entry anywhere in the MVP.
- The “screenshot test”: any frame captured at any moment must be attractive enough
  to be an App Store screenshot. If a state fails this, redesign the state.
- No settings screen. Preferences that survive the cut live behind a single glass
  sheet reachable via long-press on play/pause.
- Honors the per-PRD non-goals. Feature-limited is a requirement, not a compromise.

## Folder layout

```
tvos/
├── README.md            ← this file
├── couchkit/            ← shared package (PRD.md, then Sources/)
├── rabbit-ears/         ← each app: PRD.md, then project.yml + Sources/
├── darkroom/
├── nine/
├── blockhead/
└── cartridge/
```
