# Nine — variant sudoku for the couch, the pocket, the desk and the wrist

A 3×3 flick-rose for digit entry, a proof-checked puzzle engine, and one board
drawn once and shown at four camera positions. Native tvOS 26 Liquid Glass,
dark-first, no onboarding, no text entry anywhere.

| Surface | What it is |
|---|---|
| **tvOS** | The original. Siri Remote swipes walk the rose; a DualSense drives the full grammar. |
| **iOS** | iPhone/iPad touch UI — tap a cell to bloom the rose, tap or flick a petal to place. |
| **macOS** | Keyboard-native, with a menu bar, a History window and a ~340pt always-on-top desk mode. |
| **watchOS** | Box-zoom lens, a bounded Digital Crown dial, and a daily couriered over WatchConnectivity. |

Plus a WidgetKit extension with a playable daily widget, nine localizations,
CloudKit library sync, Game Center leaderboards and iCloud streak sync.

```bash
cd nine
xcodegen generate
open Nine.xcodeproj      # pick a destination — Apple TV, iPhone, iPad, Mac or Watch
```

See [BUILD.md](BUILD.md) to build and [TESTFLIGHT.md](TESTFLIGHT.md) to ship.

## Layout

| Path | What |
|---|---|
| `nine/` | the app — PRDs, `project.yml`, `Sources/{App,Engine,Shared,Watch,Widgets}`, `Tests/` |
| `nine/scripts/` | the harnesses: `simrig.py`, `ax-snapshot.py`, `contrast-harness.py`, `loc-harness.py`, `shotlist.py`, `strings.py` |
| `couchkit/` | the shared Swift package Nine is built on — glass, typography, persistence, remote and gamepad input |
| `fastlane/` | `beta` / `beta_app` / `beta_all` lanes: match → gym → pilot, per platform |
| `scripts/` | `testflight.sh` (manual fallback), `generate_brand_assets.swift`, `setup_gamecenter_nine.rb` |
| `docs/superpowers/` | dated implementation plans and design specs |

`nine/project.yml` is an XcodeGen spec — `.xcodeproj`, `Info.plist` and most
entitlements are generated and never committed. `nine/Package.swift` exposes
`NineEngine` and `NineShared` as pure-Swift targets, so `swift test` runs
anywhere without an SDK.

## CouchKit

`couchkit/` is a local SwiftPM path dependency (`../couchkit`), not a released
package. It is developed here, in the same commits as the app — which is the
honest description of how it has always worked, and the reason it stayed when
the rest of the suite left.

`couchkit/API.md` is the interface contract; `couchkit/PRD.md` and
`couchkit/ASKS-PLAN.md` record the design and the triage protocol from when four
sibling apps consumed it.

## Art direction: "Pixels under glass"

1. **Content is full-bleed and edge-to-edge.** The board owns the screen. No
   letterboxing, no persistent nav bars, no sidebars.
2. **Chrome is Liquid Glass, floating, and transient.** Controls are small glass
   islands that appear on touch and recede after ~3s of stillness. The default
   state of every screen is *zero visible UI*.
3. **Retro content, modern glass.** The pixel aesthetic lives in the content
   layer only. The interface layer is pure tvOS 26 / iOS 26. Never pixel-art
   buttons.
4. **Motion is slow and physical.** Crossfades ≥ 2s in ambient contexts, spring
   responses < 200ms on focus. Nothing blinks. Nothing bounces twice.
5. **Dark-first.** Backgrounds are true black or deep derived tones; glass picks
   up content color via vibrancy. Light mode exists on iOS and macOS, not on TV.

## Definition of done

- Launches to its core experience in **≤ 2 seconds** with **zero onboarding**.
- Fully operable with a Siri Remote (2nd gen+) alone on tvOS, and with the
  keyboard alone on macOS. No text entry anywhere.
- The "screenshot test": any frame captured at any moment must be attractive
  enough to be an App Store screenshot. If a state fails this, redesign it.
- Every user-facing string goes through the catalog, and every gate that can
  measure a claim does — `nine/scripts/strings.py --audit`, the AX-tree
  snapshots, the contrast floors sampled from composited glass.

## History

This repository was the Couch Suite: five tvOS apps sharing CouchKit. The four
that were feature-complete moved to repositories of their own, each carrying its
own history and a frozen copy of CouchKit:

| App | Repo |
|---|---|
| Rabbit Ears | `ngoldbla/rabbit-ears` |
| Darkroom | `ngoldbla/darkroom` |
| Blockhead | `ngoldbla/blockhead` |
| Cartridge | `ngoldbla/cartridge` |

They still share one private `couch-suite-certificates` match repo and the
`com.couchsuite.*` bundle prefix — a repository is not an identity Apple knows
about, so nothing on the App Store Connect side moved.

Earlier still, this repo was a macOS app-builder called 10x, which is where the
name comes from and nothing else survives from. PRDs and `DEVIATIONS.md` entries
that mention sibling apps are records of decisions made when the suite was one
repository; they are left as written.
