---
name: run-nine
description: Build, install, and drive Nine on an Apple TV simulator. Use when asked to run, launch, screenshot, or verify Nine on a tvOS simulator. For Nine's iPhone/iPad/Mac/watch surfaces, use the ios-simulator-skill instead.
---

# Running Nine on an Apple TV simulator

`nine/` consumes the local `couchkit` package. `nine/project.yml` (XcodeGen)
generates `Nine.xcodeproj` — never committed.

## Folder → scheme → bundle id

| Folder | Scheme | Bundle id |
|---|---|---|
| `nine` | `Nine` | `com.couchsuite.nine` |

Nine is universal — the same target builds for tvOS, iOS and macOS, and embeds
`NineWidgets` (iOS) and `NineWatch` (watchOS). This skill covers the tvOS
destination; for the touch and desk surfaces use `ios-simulator-skill`, which
this repo vendors for exactly that reason.

## Prerequisites (one-time)

```bash
xcodegen --version                 # brew install xcodegen if missing
xcrun simctl list runtimes | grep -i tvos   # need a tvOS runtime
# If no tvOS runtime: xcodebuild -downloadPlatform tvOS   (~3.8 GB, slow;
# run in background and poll `xcrun simctl list runtimes`)
```

Create + boot a simulator once (reuse it across runs):

```bash
xcrun simctl create "CouchTV" "Apple TV 4K (3rd generation)" \
  com.apple.CoreSimulator.SimRuntime.tvOS-26-5   # match your installed runtime
xcrun simctl boot CouchTV
open -a Simulator
```

## Build, install, launch

```bash
cd nine
xcodegen generate
xcodebuild -scheme Nine \
  -destination 'platform=tvOS Simulator,name=CouchTV' \
  -derivedDataPath build build          # expect ** BUILD SUCCEEDED **

APP=$(find build/Build/Products -name "*.app" -maxdepth 2 | head -1)
xcrun simctl install CouchTV "$APP"
xcrun simctl launch CouchTV com.couchsuite.nine
```

Nine needs no system permissions — it reads no Photos and runs fully featured
offline.

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

Nine's grammar: arrows walk the board, Return opens the flick rose on the
selected cell, a swipe toward a petal previews that digit and Return places it,
Esc goes back, and a long press on play/pause opens the prefs sheet.
`nine/PRD.md` and `nine/docs/EXECUTING-A-PRD.md` are the full references.

**sim-use caveat:** `sim-use screenshot`/`describe-ui` connect but the tvOS AX tree
reports only the host `PineBoard` shell (no app-level elements), and `sim-use tap
--label` therefore can't find in-app buttons. Use `simctl io ... screenshot` for
capture and AppleScript `key code` for input. (Nine's own AX lane —
`nine/scripts/ax-snapshot.py` — reads the *iOS* tree, where the board's 81
synthetic children are visible; that is why it is an iOS-simulator harness.)

## Verify engines without Xcode

```bash
cd nine     && swift test        # pure engine logic; runs on any host
cd couchkit && swift test        # 35 tests
```

## Gotchas already fixed (don't reintroduce)

- CouchKit's SwiftUI layer is gated `#if os(tvOS)`, **not** `#if canImport(SwiftUI)`.
  macOS can import SwiftUI but lacks `onPlayPauseCommand`, `glassEffect`, absolute
  microGamepad dpad, etc. — so a Mac `swift test` of the umbrella target fails unless
  the UI files compile to nothing off-tvOS.
- `AsciiRenderer.renderMosaic` splits its neighbor-average into statements; the
  one-expression form trips "compiler unable to type-check in reasonable time".
- `CouchGlass` pre-tvOS-26 fallback uses `Shape.stroke(Color.white...)`, not
  `strokeBorder(.white...)` (contextual-base inference fails under `some Shape`).
