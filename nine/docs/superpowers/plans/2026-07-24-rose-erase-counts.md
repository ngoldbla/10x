# Rose Completion — Erase Petal + Digit Counts (PRD-10) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the iOS touch rose a direct **erase** affordance for filled cells and a quiet **"N left / done"** count under each petal, without changing the shared tvOS/macOS/tutorial roses.

**Architecture:** `FlickRoseView`/`TouchRose` are shared across all four platforms, so every addition is a new parameter that defaults *off* (`remainingCounts: nil`, `showsErase: false`, `onErase: nil`). Only the iOS `TouchRose` call site in `TouchUI.swift` opts in. The erase gesture is layered on top of the existing `RoseGeometry.flickDirection` inside `TouchRose` — the shared classifier is never edited, so the never-misfire distance gate and the TV/Mac pixels are untouched. This is pure UI: `game.count(of:)`, `isDigitComplete`, and `model.erase(at:)` already exist and are tested, so there is **no engine change and no new engine test**.

**Tech Stack:** Swift 6 / SwiftUI, CouchKit glass components, xcodegen project, xcodebuild for iOS + tvOS simulators, `sim-use` for driving the iPhone sim.

## Global Constraints

- **Shared-rose parity (PRD-10 §3):** all new `FlickRoseView`/`TouchRose` parameters MUST default off; with defaults the tvOS/macOS/tutorial roses render pixel-identical. Only the iOS `TouchRose` in `TouchUI.swift` passes the new params.
- **Never-misfire rule (PRD-10 §2):** do not modify `RoseGeometry.flickDirection`; its `minimumDistance: 24` gate still governs every stroke. The erase flick is an *additional* decision made in `TouchRose` before delegating to `flickDirection`.
- **Givens/empties (PRD-10 §2):** the erase petal shows only on **filled, non-given** cells. Givens never show it; empty cells never show it.
- **Pencil roses stay clean (PRD-10 §2):** no counts and no erase petal when `state.pencil` is true (petals are small).
- **Copy is exact:** count caption reads `"N left"` (e.g. `"3 left"`) or `"done"` when the digit is complete. Caption font: **11 pt, rounded, semibold**. `"done"` renders in the accent; `"N left"` in `.secondary`.
- **Erase routes through existing API:** the erase action calls `model.erase(at:)` then closes the rose; the undo grammar already yields the `"Restored N"` toast — do not add new toast code.
- **Green gates before PR (PRD-7 §3 rule 3):** `swift test` green (engine, unchanged), `xcodebuild` green for **iPhone simulator AND tvOS simulator**, plus a `sim-use` screenshot of the feature running.
- **Delete prototypes in this PR (PRD-10 §4.3 / PRD-7 §3 rule 4):** remove `RoseDemo` and the two flag cases (`.erase`, `.rosecounts`). Do **not** delete the shared `UXDemo.swift` infrastructure (`DemoBoard`, `DemoData`, `DemoSheet`, etc.) — other in-flight PRDs still use it; the last PRD standing deletes the files.

---

### Task 1: `FlickRoseView` — counts, erase petal, and the erase gesture

**Files:**
- Modify: `nine/Sources/App/FlickRoseView.swift`

**Interfaces:**
- Consumes: existing `RoseState`, `RoseGeometry.offset(forDigit:)`, `RoseGeometry.flickDirection(_:)`, `Direction8OrCenter`, CouchKit `couchGlassInteractive`, `CouchGlassContainer`, `.couchFast`.
- Produces (relied on by Task 2):
  - `FlickRoseView(state:accent:completedDigits:showsFocusRing:scale:remainingCounts:showsErase:)` where `remainingCounts: [Int]? = nil` (9 ints, digit 1…9 order — the number of that digit *still to place*) and `showsErase: Bool = false`.
  - `TouchRose(state:accent:completedDigits:scale:onDigit:remainingCounts:showsErase:onErase:)` where `remainingCounts: [Int]? = nil`, `showsErase: Bool = false`, `onErase: (@MainActor () -> Void)? = nil`.

**Design note — the erase flick (the one judgment call in PRD-10 §2 "flick-down-through-it"):** the erase glyph sits *below* the 7-8-9 row, so it is reachable by a downward flick that travels **farther** than the one that reaches digit 8. In `TouchRose`, when `onErase != nil`, a predominantly-vertical downward drag whose downward travel meets `eraseFlickThreshold` (≈ the on-screen distance from the rose center to the erase petal) triggers `onErase()`; any shorter/normal flick falls through to `RoseGeometry.flickDirection` unchanged (so a short down-flick still places 8, and 8 is always tappable). When `onErase == nil` (empty cells, TV, Mac, tutorial) behavior is byte-identical to today.

- [ ] **Step 1: Add the two presentational params to `FlickRoseView` with off defaults**

In `FlickRoseView` (after `var scale: CGFloat = 1.0`), add:

```swift
    /// Per-digit count of that digit still to place (index 0 = digit 1). When
    /// nil the rose draws no counts — the shared TV/Mac/tutorial default.
    var remainingCounts: [Int]? = nil
    /// Adds a tenth "erase" petal below the ring. Off for givens/empty cells
    /// and every non-iOS surface.
    var showsErase: Bool = false
```

- [ ] **Step 2: Reserve vertical room for the erase petal in the frame**

The erase glyph extends below the ring, so the frame must grow when `showsErase` or it will clip. Add a computed extent and use it in `.frame(...)`:

```swift
    private var petalSize: CGFloat { (state.pencil ? 88 : 116) * scale }
    private var spacing: CGFloat { (state.pencil ? 96 : 126) * scale }
    /// Center-to-center drop from the bottom petal row to the erase glyph.
    private var eraseDrop: CGFloat { spacing * 0.92 }
    /// Extra height below the ring when the erase petal is present.
    private var eraseAllowance: CGFloat { showsErase ? eraseDrop : 0 }
```

Change the body's `.frame` to:

```swift
        .frame(width: spacing * 2 + petalSize,
               height: spacing * 2 + petalSize + eraseAllowance,
               alignment: .top)
```

- [ ] **Step 3: Draw the count captions and the erase petal inside the ZStack**

Replace the `ZStack { ForEach(1...9) { petal(for:) } }` block in `body` with:

```swift
            ZStack {
                ForEach(1...9, id: \.self) { digit in
                    petal(for: digit)
                }
                if !state.pencil, let counts = remainingCounts {
                    ForEach(1...9, id: \.self) { digit in
                        countCaption(for: digit, remaining: counts[digit - 1])
                    }
                }
                if showsErase, !state.pencil {
                    erasePetal
                }
            }
```

Then add these two view builders to `FlickRoseView` (next to `petal(for:)`):

```swift
    /// "N left" (or "done" in the accent) tucked under a petal. iOS-only —
    /// pencil roses and non-iOS surfaces pass `remainingCounts == nil`.
    private func countCaption(for digit: Int, remaining: Int) -> some View {
        let offset = RoseGeometry.offset(forDigit: digit)
        let complete = remaining <= 0
        return Text(complete ? "done" : "\(remaining) left")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(complete ? accent : Color.secondary)
            .fixedSize()
            .offset(x: offset.x * spacing,
                    y: offset.y * spacing + petalSize / 2 + 4)
    }

    /// The tenth petal: an eraser glyph directly below the 7-8-9 row.
    private var erasePetal: some View {
        Image(systemName: "eraser.fill")
            .font(.system(size: (state.pencil ? 26 : 34) * scale, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: petalSize, height: petalSize)
            .couchGlassInteractive(in: Circle())
            .offset(y: spacing + eraseDrop)
    }
```

- [ ] **Step 4: Generate the project and build for the iPhone simulator (baseline: shared roses must still compile with defaults)**

Run:
```bash
cd nine && xcodegen generate
xcodebuild -project Nine.xcodeproj -scheme Nine \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build 2>&1 | xcbeautify
```
Expected: `** BUILD SUCCEEDED **`. (No call site passes the new params yet, so this proves the defaults compile.)

- [ ] **Step 5: Add the erase params + gesture to `TouchRose`**

In `TouchRose`, add stored params after `let onDigit: @MainActor (Int) -> Void`:

```swift
    var remainingCounts: [Int]? = nil
    var showsErase: Bool = false
    var onErase: (@MainActor () -> Void)? = nil
```

Add the geometry helper next to `petalSize`/`spacing`:

```swift
    /// Minimum downward travel that means "flick past the 7-8-9 row, through
    /// the erase petal." Anything shorter falls through to the digit keypad,
    /// so a normal down-flick still places 8.
    private var eraseFlickThreshold: CGFloat { spacing * 0.92 + petalSize / 2 }
```

Pass the presentational params into the wrapped `FlickRoseView`:

```swift
        FlickRoseView(
            state: state,
            accent: accent,
            completedDigits: completedDigits,
            showsFocusRing: false,
            scale: scale,
            remainingCounts: remainingCounts,
            showsErase: showsErase
        )
```

- [ ] **Step 6: Add the erase tap target and route the flick**

In `TouchRose.body`, add an erase tap target to the overlay `ZStack` (after the `ForEach(1...9)` tap targets), and update the drag gesture. The overlay becomes:

```swift
        .overlay {
            ZStack {
                ForEach(1...9, id: \.self) { digit in
                    let offset = RoseGeometry.offset(forDigit: digit)
                    Color.clear
                        .contentShape(Circle())
                        .frame(width: max(44, petalSize), height: max(44, petalSize))
                        .onTapGesture { onDigit(digit) }
                        .offset(x: offset.x * spacing, y: offset.y * spacing)
                }
                if showsErase, let onErase {
                    Color.clear
                        .contentShape(Circle())
                        .frame(width: max(44, petalSize), height: max(44, petalSize))
                        .onTapGesture { onErase() }
                        .offset(y: spacing + spacing * 0.92)
                }
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    // Erase: a long, predominantly-downward flick that reaches
                    // the erase petal below the ring (iOS filled cells only).
                    if let onErase, showsErase,
                       value.translation.height >= eraseFlickThreshold,
                       value.translation.height >= abs(value.translation.width) {
                        onErase()
                        return
                    }
                    if let direction = RoseGeometry.flickDirection(value.translation) {
                        onDigit(RoseGeometry.digit(for: direction))
                    }
                }
        )
```

- [ ] **Step 7: Build for iPhone simulator again**

Run:
```bash
cd nine && xcodebuild -project Nine.xcodeproj -scheme Nine \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build 2>&1 | xcbeautify
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add nine/Sources/App/FlickRoseView.swift
git commit -m "Nine: rose erase petal + digit counts (FlickRoseView, PRD-10)"
```

---

### Task 2: `TouchUI.swift` — opt the iOS rose in

**Files:**
- Modify: `nine/Sources/App/TouchUI.swift` (rose region: `boardArea`, `rosePosition`, `commit`/erase routing)

**Interfaces:**
- Consumes from Task 1: `TouchRose(...remainingCounts:showsErase:onErase:)`.
- Consumes existing: `game.count(of:)`, `game.entry(at:)`, `game.isGiven(_:)`, `model.erase(at:)`, `cursor`, `closeRose()`.

- [ ] **Step 1: Pass counts, erase flag, and the erase action at the `TouchRose` call site**

In `boardArea(side:inset:)`, replace the `TouchRose(...)` construction (around `Sources/App/TouchUI.swift:608`) with:

```swift
                    TouchRose(
                        state: rose,
                        accent: accent,
                        completedDigits: Set((1...9).filter { game.isDigitComplete($0) }),
                        scale: scale,
                        onDigit: { commit(digit: $0) },
                        remainingCounts: rose.pencil
                            ? nil
                            : (1...9).map { 9 - game.count(of: $0) },
                        showsErase: !rose.pencil
                            && !game.isGiven(cursor)
                            && game.entry(at: cursor) != 0,
                        onErase: { eraseCurrentCell() }
                    )
```

- [ ] **Step 2: Add the erase action helper**

Add near `commit(digit:)` (around `Sources/App/TouchUI.swift:677`):

```swift
    private func eraseCurrentCell() {
        _ = model.erase(at: cursor)
        closeRose()
    }
```

(The `"Restored N"` toast is produced by the existing undo path — no toast code here.)

- [ ] **Step 3: Keep the erase petal on-board when it drops below the ring**

The erase petal extends `~spacing` below the bottom row, so the downward clamp in `rosePosition` needs extra margin when the current cell shows erase. Replace `rosePosition(side:inset:scale:)` (around `Sources/App/TouchUI.swift:634`) with:

```swift
    private func rosePosition(side: CGFloat, inset: CGFloat, scale: CGFloat) -> CGPoint {
        let center = BoardMetrics.center(of: cursor, side: side)
        let radius = 126 * scale + (116 * scale) / 2
        let showsErase = model.game.map {
            !$0.isGiven(cursor) && $0.entry(at: cursor) != 0
                && !(pencilMode && $0.entry(at: cursor) == 0)
        } ?? false
        let bottomExtra = showsErase ? 126 * scale * 0.92 : 0
        let frameSide = side + 2 * inset
        let clampX: (CGFloat) -> CGFloat = { value in
            min(max(value, radius - 6), frameSide - radius + 6)
        }
        let clampY: (CGFloat) -> CGFloat = { value in
            min(max(value, radius - 6), frameSide - radius - bottomExtra + 6)
        }
        return CGPoint(x: clampX(center.x + inset), y: clampY(center.y + inset))
    }
```

- [ ] **Step 4: Build for iPhone simulator**

Run:
```bash
cd nine && xcodebuild -project Nine.xcodeproj -scheme Nine \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build 2>&1 | xcbeautify
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add nine/Sources/App/TouchUI.swift
git commit -m "Nine: wire iOS rose to erase + counts (TouchUI, PRD-10)"
```

---

### Task 3: Delete the `RoseDemo` prototype and its two flag cases

**Files:**
- Modify: `nine/Sources/App/UXDemo.swift` (remove `.erase`, `.rosecounts` enum cases + their switch arms)
- Modify: `nine/Sources/App/UXDemoScenes.swift` (remove the `RoseDemo` struct)

- [ ] **Step 1: Remove the `RoseDemo` struct**

Delete the entire `struct RoseDemo: View { ... }` block in `nine/Sources/App/UXDemoScenes.swift` (starts at `struct RoseDemo: View {`, includes `countBadges`, `eraseAffordance`, `captionCard`, ends before `// MARK: - 6 · Streak Shield`).

- [ ] **Step 2: Remove the two enum cases and switch arms in `UXDemo.swift`**

In the `UXDemo` enum, delete:
```swift
    case erase          // 5  erase petal on the rose (free — table stakes)
```
and
```swift
    case rosecounts     // 12 "N left" petal badges (free polish)
```
In `UXDemoLayer.body`'s switch, delete:
```swift
            case .erase:      RoseDemo(model: model, mode: .erase)
```
and
```swift
            case .rosecounts: RoseDemo(model: model, mode: .counts)
```

- [ ] **Step 3: Build for iPhone simulator (proves no dangling references to `RoseDemo`)**

Run:
```bash
cd nine && xcodegen generate && xcodebuild -project Nine.xcodeproj -scheme Nine \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build 2>&1 | xcbeautify
```
Expected: `** BUILD SUCCEEDED **`. If the compiler flags an unused `RoseState(... focusedIndex:)` or `mode` symbol elsewhere, that reference was the demo — remove it.

- [ ] **Step 4: Commit**

```bash
git add nine/Sources/App/UXDemo.swift nine/Sources/App/UXDemoScenes.swift
git commit -m "Nine: delete RoseDemo prototype + flag cases (PRD-10)"
```

---

### Task 4: Verification (PRD-7 §3 rule 3 + PRD-10 §5)

**Files:** none (verification only).

- [ ] **Step 1: Engine tests stay green (no engine change)**

Run:
```bash
cd nine && swift test 2>&1 | tail -20
```
Expected: all tests pass (28 green), unchanged.

- [ ] **Step 2: tvOS simulator build green (shared rose parity)**

Run:
```bash
cd nine && xcodebuild -project Nine.xcodeproj -scheme Nine \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  build 2>&1 | xcbeautify
```
Expected: `** BUILD SUCCEEDED **`. (Confirms the TV rose compiles with the new defaults; it passes no new params, so pixels are unchanged.)

- [ ] **Step 3: iPhone sim — screenshot the counts + a "done" petal**

Install and launch with the debug-fill fixture, tap a filled non-given cell to bloom the rose, screenshot:
```bash
cd nine
xcrun simctl install booted "$(xcodebuild -project Nine.xcodeproj -scheme Nine -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings 2>/dev/null | awk '/ CODESIGNING_FOLDER_PATH/{print $3}')"
xcrun simctl launch booted com.couchsuite.nine --debug-fill
```
Then drive with `sim-use`: tap a filled cell, confirm the rose shows "N left" under petals and "done" (in accent) on completed digits. Save `screenshot: rose-counts.png`.
Expected: most petals read "done" in the accent; the one incomplete digit reads "1 left"; pencil-mode rose (toggle pencil on an empty cell) shows **no** counts.

- [ ] **Step 4: iPhone sim — erase petal + erase→undo round-trip**

With a filled non-given cell selected, confirm the `eraser.fill` petal appears below the 7-8-9 row. Tap it (and separately test a long down-flick): the cell clears. Then trigger Undo and confirm the `"Restored N"` toast. Confirm a **given** cell shows **no** erase petal, and an **empty** cell shows **no** erase petal. Save `screenshot: rose-erase.png` and `screenshot: erase-undo-toast.png`.
Expected: erase clears the cell via `model.erase(at:)`; undo restores it with the `"Restored N"` toast; givens/empties never show the petal.

- [ ] **Step 5: Confirm prototype removal**

Run:
```bash
cd nine && grep -rn "RoseDemo\|uxdemo.erase\|uxdemo.rosecounts" Sources/
```
Expected: no matches.

---

## Self-Review

- **Spec coverage:** Erase petal (§2) → Task 1 Step 3 + Task 2 Steps 1-3; tap/flick erase → Task 1 Step 6; counts "N left/done" (§2) → Task 1 Step 3 + Task 2 Step 1; pencil roses clean (§2) → guarded by `!state.pencil` (Task 1) and `rose.pencil ? nil` (Task 2); givens/empties never show erase (§2) → Task 2 Step 1 `showsErase` predicate; parameterized-off parity (§3) → all defaults nil/false, TV build in Task 4 Step 2; never-misfire (§2) → `flickDirection` untouched; delete `RoseDemo` + both flag cases (§4.3) → Task 3; verification checklist (§5) → Task 4.
- **Placeholder scan:** none — every step has concrete code or an exact command.
- **Type consistency:** `remainingCounts: [Int]?`, `showsErase: Bool`, `onErase: (@MainActor () -> Void)?` are spelled identically in `FlickRoseView` (presentational, no `onErase`), `TouchRose` (adds `onErase`), and the `TouchUI` call site. `eraseCurrentCell()` defined once (Task 2 Step 2) and referenced once (Task 2 Step 1). `eraseDrop`/`eraseFlickThreshold`/`bottomExtra` all use the same `spacing * 0.92` drop so the drawn petal, its tap target, its clamp margin, and the flick threshold agree.
