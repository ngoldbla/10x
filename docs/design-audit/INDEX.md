# Nine — design audit

A photograph of every surface Nine has, a verbose critique of each against an
Apple Design Award bar, a set of executable design prompts, and a capstone design
language other agents can build from.

**Date:** August 2026 · **OS baseline:** 26 (Liquid Glass), with OS 27 in beta
**Scope:** audit only — **no app source, asset, token or harness was changed.**

---

## How to use this

| If you want to… | Read |
|---|---|
| Understand the rubric before judging anything | [`CRITERIA.md`](CRITERIA.md) |
| Rebuild a screenshot | [`SHOTLOG.md`](SHOTLOG.md) |
| Critique one surface | `bundles/B**/CRITIQUE.md` |
| Check the Apple/ADA research | [`research/`](research/) |

**Pending, not yet written:** `DESIGN-LANGUAGE.md` (the capstone that turns the
findings into a redesign brief) and per-bundle `PROMPTS.md` files. This first
pass stops at the critiques; the synthesis and the executable prompts are the
next stage.

**Images.** Each bundle's `img/` holds ~1400px downscales, committed so this
directory is self-contained for a future agent. Full-resolution originals live
in the gitignored `.context/design-audit/shots/`, and `SHOTLOG.md` says how to
re-make any of them.

**Shot IDs.** `B{bb}-S{ss}_{surface}-{scene}-{state}_{appearance}` — e.g.
`B05-S03_iphone-game-rest_dark`. Surfaces: `tv` · `iphone` · `ipad` · `ipadls`
(landscape) · `mac` · `watch` · `widget` · `asset`. Appearance: `dark` · `light`
· `theme-<name>` · `accent-<name>`. Critiques cite IDs and never paths; this
file is the only ID → path map.

---

## Bundles

| ID | Surface / topic | Shots | Critique | Prompts |
|---|---|---|---|---|
| B01 | Identity — icons, top shelf, launch | 12 | [`CRITIQUE.md`](bundles/B01-identity/CRITIQUE.md) | — |
| B02 | tvOS shelf | — | | |
| B03 | tvOS game — board, rose, pad, parlor | 1 | [`CRITIQUE.md`](bundles/B03-tv-game/CRITIQUE.md) | — |
| B04 | iOS shelf + first run | 6 | [`CRITIQUE.md`](bundles/B04-ios-shelf/CRITIQUE.md) | — |
| B05 | iOS game — rose, coach, drawer, debrief | 8 | [`CRITIQUE.md`](bundles/B05-ios-game/CRITIQUE.md) | — |
| B06 | iPad — two-column shelf, drafting table | — | | |
| B07 | macOS — windows, menu bar, desk mode | 2 | — | |
| B08 | watchOS — home, map, box, Crown rose | — | | |
| B09 | Widgets | — | | |
| B10 | Sheets — Preferences, History, Boards | — | | |
| B11 | Learn — Tutorial, Technique School | — | | |
| B12 | Theme gallery — 9 themes × accents | 4 | — | |
| B13 | Post-solve — debrief, share card | — | | |
| B14 | Motion — clips and frame strips | — | | |
| B15 | Cross-platform coherence — montages | — | | |

**This is a first-pass audit, not a full one.** The crown surfaces are critiqued
(B01, B03, B04, B05); B07 and B12 have shots captured but no critique yet; the
rest are not captured. See **What was not captured** below for exactly what is
missing and why.

---

## Shot manifest

One row per committed shot: ID · bundle · full-res path · committed downscale
path · what it shows.

### B01 — identity (12)

| ID | Full-res | Downscale | Shows |
|---|---|---|---|
| `B01-S01` | `.context/design-audit/shots/B01/B01-S01_asset-icon-ios-default_dark.png` | `bundles/B01-identity/img/B01-S01_…_dark.png` | iOS icon, Original variant |
| `B01-S02` | `…/B01-S02_asset-icon-ios-ember_dark.png` | same | iOS icon, Ember variant |
| `B01-S03` | `…/B01-S03_asset-icon-ios-tide_dark.png` | same | iOS icon, Tide variant |
| `B01-S04` | `…/B01-S04_asset-icon-ios-mono_dark.png` | same | iOS icon, Mono variant |
| `B01-S05` | `…/B01-S05_asset-icon-mac_dark.png` | same | macOS icon |
| `B01-S06` | `…/B01-S06_asset-icon-watch_dark.png` | same | watchOS icon |
| `B01-S07` | `…/B01-S07_asset-topshelf-wide_dark.png` | same | tvOS top-shelf wide (4640×1440) |
| `B01-S08` | `…/B01-S08_asset-topshelf_dark.png` | same | tvOS top-shelf |
| `B01-S09` | `…/B01-S09_asset-launch_dark.png` | same | launch image |
| `B01-S10` | `…/B01-S10_asset-tvicon-layer-back_dark.png` | same | tvOS icon, parallax back layer |
| `B01-S11` | `…/B01-S11_asset-tvicon-layer-middle_dark.png` | same | tvOS icon, parallax middle layer |
| `B01-S12` | `…/B01-S12_asset-tvicon-layer-front_dark.png` | same | tvOS icon, parallax front layer |

### B03 — tvOS game (1)

| ID | Full-res | Downscale | Shows |
|---|---|---|---|
| `B03-S01` | `.context/design-audit/shots/B03/B03-S01_tv-game-rest_dark.png` | `bundles/B03-tv-game/img/B03-S01_…_dark.png` | tvOS game screen at rest, mid-board, dark |

### B04 — iOS shelf (6)

| ID | Full-res | Downscale | Shows |
|---|---|---|---|
| `B04-S01` | `.context/design-audit/shots/_stock/iphone-dark-home.png` | `bundles/B04-ios-shelf/img/B04-S01_iphone-home_dark.png` | iPhone home shelf, dark |
| `B04-S02` | `…/_stock/iphone-light-home.png` | `bundles/B04-ios-shelf/img/B04-S02_iphone-home_light.png` | iPhone home shelf, light |
| `B04-S03` | `…/_stock/iphone-dark-home-bottom.png` | `bundles/B04-ios-shelf/img/B04-S03_iphone-home-bottom_dark.png` | iPhone home scrolled to bottom, dark |
| `B04-S04` | `…/_stock/iphone-light-home-bottom.png` | `bundles/B04-ios-shelf/img/B04-S04_iphone-home-bottom_light.png` | iPhone home scrolled to bottom, light |
| `B04-S05` | `…/_stock/iphone-light-channel.png` | `bundles/B04-ios-shelf/img/B04-S05_iphone-channel_light.png` | Thermo channel page, light |
| `B04-S06` | `…/_stock/iphone-dark-channel.png` | `bundles/B04-ios-shelf/img/B04-S06_iphone-channel_dark.png` | Thermo channel page, dark |

### B05 — iOS game (8)

| ID | Full-res | Downscale | Shows |
|---|---|---|---|
| `B05-S01` | `.context/design-audit/shots/_stock/iphone-light-game.png` | `bundles/B05-ios-game/img/B05-S01_iphone-game-rest_light.png` | game screen at rest, light |
| `B05-S02` | `…/_stock/iphone-dark-game.png` | `bundles/B05-ios-game/img/B05-S02_iphone-game-rest_dark.png` | game screen at rest, dark |
| `B05-S03` | `…/_stock/iphone-light-rose.png` | `bundles/B05-ios-game/img/B05-S03_iphone-rose-open_light.png` | flick rose open over the board, light |
| `B05-S04` | `…/_stock/iphone-dark-rose.png` | `bundles/B05-ios-game/img/B05-S04_iphone-rose-open_dark.png` | flick rose open over the board, dark |
| `B05-S05` | `…/_recede/iphone-dark-game-t01s.png` | `bundles/B05-ios-game/img/B05-S05_iphone-game-recede-t01s_dark.png` | recede test, 1 s after launch, dark |
| `B05-S06` | `…/_recede/iphone-dark-game-t04s.png` | `bundles/B05-ios-game/img/B05-S06_iphone-game-recede-t04s_dark.png` | recede test, 4 s after launch, dark |
| `B05-S07` | `…/_recede/iphone-dark-game-t08s.png` | `bundles/B05-ios-game/img/B05-S07_iphone-game-recede-t08s_dark.png` | recede test, 8 s after launch, dark |
| `B05-S08` | `…/_recede/iphone-dark-game-t15s.png` | `bundles/B05-ios-game/img/B05-S08_iphone-game-recede-t15s_dark.png` | recede test, 15 s after launch, dark |

### B07 — macOS (2)

| ID | Full-res | Downscale | Shows |
|---|---|---|---|
| `B07-S01` | `.context/design-audit/shots/B07/B07-S01_mac-game-rest_dark.png` | `bundles/B07-macos/img/B07-S01_…_dark.png` | macOS game window at rest, dark |
| `B07-S02` | `…/B07-S02_mac-settings_dark.png` | `bundles/B07-macos/img/B07-S02_…_dark.png` | macOS Settings window, dark |

### B12 — theme gallery (4)

| ID | Full-res | Downscale | Shows |
|---|---|---|---|
| `B12-S01` | `.context/design-audit/shots/B12/iphone-theme-auto.png` | `bundles/B12-themes/img/B12-S01_iphone-game-rest_theme-auto.png` | game screen, theme auto |
| `B12-S02` | `…/iphone-theme-camel.png` | `bundles/B12-themes/img/B12-S02_…_theme-camel.png` | game screen, theme camel |
| `B12-S03` | `…/iphone-theme-dark.png` | `bundles/B12-themes/img/B12-S03_…_theme-dark.png` | game screen, theme dark |
| `B12-S04` | `…/iphone-theme-light.png` | `bundles/B12-themes/img/B12-S04_…_theme-light.png` | game screen, theme light |

---

## What was not captured

This is a first pass. The gaps below are recorded because a critique that
silently omits a surface reads as a critique that judged it and had nothing to
say.

- **B02 (tvOS shelf), B08 (watch), B09 (widgets), B10 (sheets), B11 (learn),
  B13 (post-solve), B15 (coherence):** not captured at all. The tvOS lane is an
  exclusive single-actor resource (AppleScript keystrokes) and was contended;
  the watch and widget lanes have flaky capture paths per the plan's risk list.
- **B06 (iPad):** full-res frames exist in `.context/design-audit/shots/_stock/`
  (`ipad-*`) and `_recede/` (`ipad-*`) and the measurements in
  `.context/design-audit/measurements.md` cite them, but no committed critique
  was written, so no downscale was committed for the bundle.
- **B07 and B12:** shots captured and committed, **critiques pending** — the
  frames are the evidence a future critic will cite.
- **B14 (motion):** no clips captured; `ffmpeg` was confirmed installed but the
  video lanes did not run in this pass.
- **The rose focused in situ on tvOS** (B01's unverified suspicion) and the
  iPad drafting-table landscape pass: not captured.
