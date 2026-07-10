# PRD — Rabbit Ears

**Status:** Draft v1 · **Thread:** `tvos/rabbit-ears/` · **Remote-fit:** 10/10
**One-liner:** Your photo library as a living, conductable ASCII/pixel-art channel —
the thing your TV does when nobody is “using” it.

## 1. Product thesis

Every Apple TV spends most of its life idle or showing Apple's stock aerials.
Rabbit Ears replaces that dead time with art made from the user's own memories,
rendered in styles (ASCII, phosphor terminal, pixel art, ink line) that are
beautiful as *art* — abstract enough for guests, personal enough to stop family
members mid-walk. The remote makes you a conductor, not an operator: every gesture
is optional, atomic, and immediately visible. The null input is a valid state.

This is the suite's flagship for the “Pixels under glass” aesthetic and the app
most likely to be screenshotted. Visual quality is the entire product.

## 2. Goals

- The most beautiful ambient app on tvOS. Period.
- Zero learning curve: launch → art within 2 seconds, no menus in the happy path.
- Every gesture produces a visible, delightful, reversible response within 100ms.

## 3. Non-goals (v1)

- No AirPlay photo receiving, no party/guest mode, no sharing/exporting.
- No music playback of its own (it *reacts* to nothing in v1 — the “sync to music”
  concept is v2; shipping motion is self-paced).
- No video assets, no Live Photos motion. Stills only.
- No style editor or parameter tweaking. Five fixed styles, tuned by us.

## 4. Core experience

### 4.1 The channel (the only screen)

Full-bleed, edge-to-edge rendered photo, slowly drifting (deterministic Ken Burns
via `AsciiKit .drift`). Every 20–40s (style-dependent), a ≥ 3s crossfade to the
next photo. No clock, no watermark, no UI. True black behind everything so OLED
scenes breathe.

Sequencing: `PhotoKitPlus.onThisDay()` first, then `randomMemorable()`, shuffled
with a no-repeat window of 200 photos. If the library is empty or unauthorized,
the bundled CC0 set plays and a single `GlassChip` (“Connect iCloud Photos for your
own memories”) appears once, then never again that session.

### 4.2 The remote grammar (complete)

| Gesture | Effect | Visual response |
|---|---|---|
| Touch (rest) | Wake chrome | `GlassPill` fades up: style dots + `GlassChip` caption (“June 2019 · Lake Tahoe”) |
| Swipe ← / → | Previous / next style (cycles the 5 AsciiKit styles) | Style *wipes* across the image as a moving vertical seam — the same photo re-renders live under the seam. Signature moment #1. |
| Swipe ↑ / ↓ | Change lane: All Memories → On This Day → Favorites → each album | Lane name chip; content crossfades |
| Click | Freeze / unfreeze the current frame | Drift halts; a barely-visible glass frame edge appears, as if the art was mounted. Frozen frames persist until unfrozen — the TV becomes a picture frame. |
| Hold | Morph: current photo dissolves into the next through pure character-space (glyphs re-sort themselves) | Signature moment #2 |
| Play/Pause | Pause / resume the channel’s auto-advance | Tiny glass ⏸ chip, 2s |
| Play/Pause long-press | Prefs sheet (`GlassSheet`): crossfade speed (3 choices), start-on-wake toggle | Only sheet in the app |
| Back | System behavior (exit) | — |

Chrome recedes 3s after last touch (`IdleAttract`). Nothing on screen otherwise.

## 5. Visual & Liquid Glass specification

- **Chrome inventory (total):** one `GlassPill` (5 style dots), one `GlassChip`
  (caption), one `GlassSheet` (prefs). That is the entire UI. If a design ask
  exceeds this inventory, the answer is no.
- Style dots inside the pill are miniature *live previews* — each dot shows the
  current photo in that style at 64px. Focus sweeps between them with `FocusHalo`;
  the pill lenses the artwork behind it (glass over pixels: the thesis in one shot).
- Caption chip derives its tint from `CouchPalette.AccentDerivation` — glass warms
  and cools with the artwork.
- Freeze state must look intentional: 2pt inner glass border, corner radius 0
  (full-bleed), drift stopped, grain alive (shader time continues). A frozen
  phosphor-style frame should read as “expensive generative art,” not “paused app.”

## 6. tvOS native integration

- **Top Shelf extension:** carousel of the user's last 6 frozen frames (rendered
  via AsciiKit helpers). Deep-click opens that frame frozen.
- **Multi-user:** lanes, frozen frames, and prefs are per-profile (`CouchStore`).
- **Focus engine:** only the pill's dots are focusable; the channel itself never
  shows a focus ring.
- **Screensaver honesty:** we cannot replace the system screensaver; instead the
  prefs “start on wake” + Top Shelf presence make launching it a one-click habit.
  Document this limitation in-app nowhere; it needs no explanation.

## 7. Architecture notes

- SwiftUI shell ~thin; all heavy lifting in CouchKit (`AsciiEngine.renderStream`
  for crossfade pairs, `PhotoKitPlus` for sequencing, `RemoteKit` for gestures).
- Pre-render next frame during current dwell; target steady 60fps at 4K, < 40% GPU
  on Apple TV 4K (3rd gen) so thermals stay silent.
- App-specific code budget: ≤ 1,200 lines. If it grows past that, scope is wrong.

## 8. Success metrics

- Median session length > 20 minutes (ambient dwell).
- ≥ 30% of sessions use at least one gesture (conductor behavior exists).
- ≥ 25% of weekly users have ≥ 1 frozen frame (picture-frame behavior exists).

## 9. Milestones

- **M1:** Channel with bundled photos, styles hard-switching (no seam), pill+chip.
- **M2:** iCloud Photos lanes, style wipe seam, freeze, morph, prefs sheet.
- **M3:** Top Shelf, multi-user, performance pass, sound-free QA, App Store assets.

## 10. Open questions

- Should freeze survive app relaunch (TV as permanent picture frame)? Leaning yes
  via `CouchStore`; decide in M2 with real usage.
- Phosphor style burn-in risk on OLED TVs during freeze — may need imperceptible
  1px orbit. Test in M2.
