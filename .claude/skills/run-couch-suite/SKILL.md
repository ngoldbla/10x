---
name: run-couch-suite
description: Build, install, and drive any of the five Couch Suite tvOS apps (Rabbit Ears, Darkroom, Nine, Blockhead, Cartridge) on an Apple TV simulator. Use when asked to run, launch, screenshot, or verify a tvos/ app on a simulator.
---

# Running the Couch Suite on an Apple TV simulator

Five tvOS apps in `tvos/<app>/` share the local `tvos/couchkit` package. Each app
has a `project.yml` (XcodeGen) — the `.xcodeproj` is generated, never committed.

## App → scheme → bundle id

| Folder | Scheme | Bundle id |
|---|---|---|
| `rabbit-ears` | `RabbitEars` | `com.couchsuite.rabbitears` |
| `darkroom` | `Darkroom` | `com.couchsuite.darkroom` |
| `nine` | `Nine` | `com.couchsuite.nine` |
| `blockhead` | `Blockhead` | `com.couchsuite.blockhead` |
| `cartridge` | `Cartridge` | `com.couchsuite.cartridge` |

## Prerequisites (one-time)

```bash
xcodegen --version                 # brew install xcodegen if missing
xcrun simctl list runtimes | grep -i tvos   # need a tvOS runtime
# If no tvOS runtime: xcodebuild -downloadPlatform tvOS   (~3.8 GB, slow;
# run in background and poll `xcrun simctl list runtimes`)
```

Create + boot a simulator once (reuse it across apps):

```bash
xcrun simctl create "CouchTV" "Apple TV 4K (3rd generation)" \
  com.apple.CoreSimulator.SimRuntime.tvOS-26-5   # match your installed runtime
xcrun simctl boot CouchTV
open -a Simulator
```

## Build, install, launch (per app)

```bash
cd tvos/<folder>
xcodegen generate
xcodebuild -scheme <Scheme> \
  -destination 'platform=tvOS Simulator,name=CouchTV' \
  -derivedDataPath build build          # expect ** BUILD SUCCEEDED **

APP=$(find build/Build/Products -name "*.app" -maxdepth 2 | head -1)
xcrun simctl install CouchTV "$APP"
# Rabbit Ears / Darkroom / Cartridge read Photos; pre-grant to skip the prompt:
xcrun simctl privacy CouchTV grant photos <bundle-id>
xcrun simctl launch CouchTV <bundle-id>
```

All apps run fully featured with **zero permissions** — procedural DemoArt stands
in until Photos is granted. Granting photos just swaps demo art for the library.

## Drive it and look

```bash
xcrun simctl io CouchTV screenshot /tmp/shot.png   # then Read the PNG
```

The remote grammar maps to the **hardware keyboard** while the Simulator window is
focused (arrows = swipe, Return = click/select, Esc = Menu/Back). Send keys with
AppleScript so focus is guaranteed:

```bash
osascript -e 'tell application "Simulator" to activate' -e 'delay 0.5' \
  -e 'tell application "System Events" to key code 124'   # 124=→ 123=← 126=↑ 125=↓ 36=Return 53=Esc
```

Example — Rabbit Ears: `→` cycles render style (and crossfades to a new photo),
`↑/↓` switch photo lanes, Return freezes the frame, Space/PlayPause pauses drift.

**sim-use caveat:** `sim-use screenshot`/`describe-ui` connect but the tvOS AX tree
reports only the host `PineBoard` shell (no app-level elements), and `sim-use tap
--label` therefore can't find in-app buttons. Use `simctl io ... screenshot` for
capture and AppleScript `key code` for input. `xcrun simctl privacy` handles the
one system permission dialog without needing to tap it.

## Verify engines without Xcode

```bash
cd tvos/<folder> && swift test        # pure CouchCore logic; runs on any host
cd tvos/couchkit  && swift test        # 35 tests
```

## Gotchas already fixed on this branch (don't reintroduce)

- CouchKit's SwiftUI layer is gated `#if os(tvOS)`, **not** `#if canImport(SwiftUI)`.
  macOS can import SwiftUI but lacks `onPlayPauseCommand`, `glassEffect`, absolute
  microGamepad dpad, etc. — so a Mac `swift test` of the umbrella target fails unless
  the UI files compile to nothing off-tvOS.
- `AsciiRenderer.renderMosaic` splits its neighbor-average into statements; the
  one-expression form trips "compiler unable to type-check in reasonable time".
- `CouchGlass` pre-tvOS-26 fallback uses `Shape.stroke(Color.white...)`, not
  `strokeBorder(.white...)` (contextual-base inference fails under `some Shape`).
