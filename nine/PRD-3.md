# PRD-3 — Nine on your Home Screen (widget family)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** two PRs (3a glanceable, 3b playable)
**One-liner:** The daily becomes ambient — a glass widget with today's board
state, streak flame, and points on the Home Screen, Lock Screen, and StandBy;
later, a large widget you can actually play, one tap at a time.

## 1. Why

Nine has no presence outside the app. A widget family makes the daily puzzle and
streak ambient, and "play sudoku without opening an app" is a genuine App Store
story. Phase 3a (glanceable) is deliberately small and shippable alone; all
playable-widget complexity is quarantined in Phase 3b.

**Honest constraints established in design review:** interactive widgets route
every tap through an App Intent (~100-500ms) with no pencil marks and no flick
rose — so playability is pitched as "sneak in a move while waiting for coffee,"
never as the primary way to play.

## 2. Core decision — snapshot file, NOT storage migration

The app currently persists via CouchKit `CouchStored`, which hardcodes
`Application Support/CouchKit/` **inside the app container**
(couchkit/Sources/CouchKit/CouchStore.swift:124-129) — invisible to extensions.

**Rejected:** migrating CouchStored to an app-group container.
`CouchStored.directory` is a static shared by **all five Couch Suite apps**
(CouchKit API change, suite-wide blast radius), the migration would move users'
precious streak/history exactly once atomically on two platforms, and a
debounced cross-process writer invites torn reads.

**Chosen:** the app writes a small, versioned, one-way `WidgetSnapshot` JSON
into app group **`group.com.couchsuite.nine`** (per-app id, matching bundle-id
convention). Phase 3b adds a *second* shared file for the daily board with
explicit conflict rules. CouchKit is never touched.

### Snapshot schema (`Sources/Shared/WidgetSnapshot.swift`, compiled into BOTH targets)

Raw facts, not display values, so the provider re-derives at any entry date
(midnight rollover works without an app launch):

```swift
struct WidgetSnapshot: Codable, Equatable {
    var schemaVersion = 1
    var dailyDayOrdinal: Int?       // day of the in-progress/solved daily
    var dailyFillFraction: Double?  // nil = not started
    var dailySolvedSeconds: TimeInterval?
    var streakCurrent: Int
    var streakBest: Int
    var lastCompletedDay: Int?
    var totalPoints: Int
    var generatedAt: Date
}
```

Provider derivation at date `d`: `today = dayOrdinal(d)`; solved-today =
`lastCompletedDay == today`; in-progress iff `dailyDayOrdinal == today`;
displayed streak = `lastCompletedDay >= today - 1 ? current : 0`. Duplicate the
~10 lines of `dayOrdinal`/`displayedStreak` math into the shared file (keeps the
extension Engine-free and tiny) with a **unit test cross-checking against the
Engine originals** (Generator.swift:195-210, Game.swift:187-219). Read/write
with plain sorted-keys JSONEncoder — do not link CouchKit into the extension.

## 3. Phase 3a — Glanceable widgets (shippable alone)

### Widgets

- **NineDailyWidget** — `systemSmall` (status glyph + flame count),
  `systemMedium` (status + fill % ring + flame + points),
  `accessoryRectangular` ("Daily · 64%" / "Solved 4:12" / "Not started" + flame).
- **NineStreakWidget** — `accessoryCircular` (flame + day count; Gauge when
  in-progress), `accessoryInline` ("Nine · 12 day streak").
- StandBy is free (renders systemSmall); use `AccessoryWidgetBackground` /
  hierarchical foregrounds so vibrant/tinted modes don't wash out.
  `containerBackground(for: .widget)` void-black/paper per scheme.
- All families: `.widgetURL(URL(string: "nine://daily"))`.
- Timeline: entries `[now, nextLocalMidnight]`, policy `.after(nextLocalMidnight)`
  — at midnight the same snapshot re-renders as "new puzzle waiting" and the
  flame stays/lapses correctly. Missing snapshot file → "Open Nine" placeholder.

### New files

| File | Contents |
|---|---|
| `nine/Sources/Shared/WidgetSnapshot.swift` | schema + group-container `fileURL` + atomic read/write + `dayOrdinal`/`displayedStreak` helpers |
| `nine/Sources/App/WidgetBridge.swift` | `#if os(iOS)` app-side writer: build snapshot, write atomically, call `WidgetCenter.shared.reloadTimelines` **only when a coarse digest changed** (state bucket: notStarted/solved/fill-decile, displayed streak, points) — protects the reload budget since `place()` fires per move |
| `nine/Sources/Widgets/NineWidgetBundle.swift` | `@main WidgetBundle` |
| `nine/Sources/Widgets/DailyProvider.swift` | `TimelineProvider` as above |
| `nine/Sources/Widgets/DailyWidgetViews.swift` | daily widget + views |
| `nine/Sources/Widgets/StreakWidget.swift` | accessory widgets |
| `nine/Sources/Widgets/PrivacyInfo.xcprivacy` | no tracking, no required-reason APIs (add `CA92.1` UserDefaults reason in Phase 3b) |
| `nine/Nine-iOS.entitlements` | checked-in copy of existing entitlements + app group (keeps tvOS entitlements byte-identical) |
| `nine/WidgetsInfo.plist` | via project.yml `info:` properties |

### App-side hooks (small edits)

- `AppModel.swift`: `WidgetBridge.publish(from: self)` at end of `init`
  (post-load), `persistProgress()`, `finishSolve()`, `goHome()`,
  `discardSaved()` — all `#if os(iOS)`.
- `NineApp.swift`: `.onOpenURL` → host/path `daily` → existing
  `model.openToday()` (already safe mid-composition). Add
  `@Environment(\.scenePhase)`; publish snapshot on `.background`
  (belt-and-braces; also where Phase 3b's merge hooks in).

### project.yml (sketch)

```yaml
targets:
  Nine:
    dependencies:
      - package: CouchKit
      - target: NineWidgets
        embed: true
        destinationFilters: [iOS]      # MUST NOT embed in tvOS
    sources: [Sources/App, Sources/Engine, Sources/Shared, ...]
    settings:
      base:
        "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]": Nine-iOS.entitlements
        "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]": Nine-iOS.entitlements
    info:
      properties:
        CFBundleURLTypes:
          - CFBundleURLName: com.couchsuite.nine
            CFBundleURLSchemes: [nine]

  NineWidgets:
    type: app-extension
    supportedDestinations: [iOS]
    deploymentTarget: { iOS: "18.0" }
    sources: [Sources/Widgets, Sources/Shared]
    settings:
      base:
        SWIFT_VERSION: "6.0"
        PRODUCT_BUNDLE_IDENTIFIER: com.couchsuite.nine.widgets
        MARKETING_VERSION: "1.0"        # must match the app's
        TARGETED_DEVICE_FAMILY: "1,2"
        SKIP_INSTALL: true
        CODE_SIGN_STYLE: Manual
        "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]": "match AppStore com.couchsuite.nine.widgets"
    entitlements:
      path: NineWidgets.entitlements
      properties:
        com.apple.security.application-groups: [group.com.couchsuite.nine]
    info:
      path: WidgetsInfo.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
```

Verify installed XcodeGen supports `destinationFilters` (≥2.38; fallback
`platformFilter: iOS`).

### Signing / match / CI — THE LONG POLE, sequence first

1. **Portal (manual, one-time):** create app group `group.com.couchsuite.nine`;
   register App ID `com.couchsuite.nine.widgets` with App Groups; enable App
   Groups on the **iOS** `com.couchsuite.nine` App ID and assign the group.
   (match does not manage capabilities.)
2. **Matchfile:** append `com.couchsuite.nine.widgets` to `app_identifier`.
3. **Writable match re-mint (local, one-time):** `fastlane match appstore` (+
   `development` for device debugging). ⚠️ Adding the capability invalidates the
   existing iOS `com.couchsuite.nine` profile — re-mint **before** the next CI
   run or nine/iOS CI fails. CI stays `readonly: true`.
4. **Fastfile:** nine/iOS leg: `match(app_identifier: [app_id,
   "com.couchsuite.nine.widgets"])` and a second entry in gym's
   `export_options.provisioningProfiles`. Data-drive via e.g.
   `APPS["nine"][:extensions]` merged when `plat == "ios"` (Fastfile:61-77).
   Build numbers stay in lockstep via the existing project-wide xcargs; ASC
   requires the extension's `CFBundleShortVersionString` to equal the app's
   (pinned via shared `MARKETING_VERSION`).
5. **CI:** no workflow changes (paths already cover `nine/**`, `fastlane/**`);
   tvOS leg unaffected — the widget is not in its dependency graph.

## 4. Phase 3b — Playable large widget (separate PR)

- **Second shared file** `Sources/Shared/SharedDailyBoard.swift`:
  ```swift
  struct SharedDailyBoard: Codable {
      var dayOrdinal: Int
      var game: NineGame          // Engine type, Codable end-to-end
      var revision: Int           // monotonic; last-writer-wins
      var updatedAt: Date
      var pendingSolve: PendingSolve?   // widget sets; app ingests
  }
  struct PendingSolve: Codable { var solvedAt: Date; var seconds: TimeInterval }
  ```
- Widget target adds `Sources/Engine` to its sources; real `game.place()` runs
  in-process (pure value type, extension-safe). **Single source of truth for the
  daily = this file**: app writes on every daily persist (revision++); on
  `scenePhase == .active` / `openToday()` the app adopts if revision is newer
  (widget moves flow into the autosave, undo stack included). Free-play never
  touches it.
- **The widget never generates puzzles** (Sharp generation takes seconds;
  extension budget ~30MB). No board for today → "Tap to start today's puzzle"
  deep link; app composes and publishes.
- **Intents:** `SelectCellIntent(row, col)` → selection into
  `UserDefaults(suiteName: group)` (ephemeral; requires `CA92.1` privacy reason);
  `PlaceDigitIntent(digit)` → read selection + board, place, revision++, write
  board + snapshot, keep selection for fast consecutive entry. Skip erase in v1.
  Stale-day guard: dayOrdinal mismatch → refuse and re-render "new puzzle".
- **Solve in widget:** sets `pendingSolve` + optimistic snapshot (solved,
  streak+1 shown). Streak/history/Game Center are recorded **only** when the app
  next activates and ingests (`recordCompletion` already idempotent per day,
  Game.swift:202-211). Honest caveat: Game Center sync lags until app open.
- **Rendering** (`systemLarge`, ~338×354pt): SwiftUI `Grid` of
  `Button(intent:)` `.buttonStyle(.plain)` — ~30pt cells, givens semibold,
  entries in accent, selected ring, heavier 3×3 strokes, **no pencil marks**;
  digit strip of 9 intent buttons, completed digits dimmed. 90 buttons is within
  archived-view limits but verify on-device (fallback: Canvas board + invisible
  button overlay).

## 5. Risks

- **Signing:** capability add invalidates the live iOS profile — sequence
  portal → match mint → merge, or CI breaks.
- **`destinationFilters` misbehaving** would embed the widget into tvOS and
  break tvOS signing — guarded by verification item 1.
- Extension memory/CPU (~30MB): trivial for 3a; 3b must never run the generator.
- Widget reload budget: digest-gated `reloadTimelines`.
- Midnight/DST streak correctness: raw facts + per-entry derivation + unit
  tests.

## 6. Verification checklist

Phase 3a:
1. `xcodegen generate` → two targets; widget embedded in iOS app only;
   `xcodebuild -scheme Nine -destination 'generic/platform=tvOS' build` passes.
2. Unit tests: snapshot round-trip; shared `dayOrdinal`/`displayedStreak` agree
   with Engine across DST/midnight edges.
3. Sim: play daily moves → background → small+medium widgets show fill %; solve
   (DEBUG long-press-Undo rig) → solved + streak increments. Lock Screen
   circular+rectangular; StandBy check.
4. Midnight rollover → "not started", flame persists (yesterday solved) or
   lapses.
5. Tap each family → app opens today's daily (cold + warm).
6. Fresh install (no snapshot) → placeholder, no crash.
7. `fastlane beta app:nine platform:ios upload:false` resolves both profiles;
   tvOS lane unchanged.

Phase 3b additions:
8. Round-trip: place in app → force-quit → place in widget → reopen → both moves
   present, revisions monotone; undo in app reverts the widget's move.
9. Solve entirely in widget → open app → streak/history/Game Center recorded
   exactly once; `pendingSolve` cleared; same-day re-ingest no-ops.
10. Instruments: extension <30MB under rapid taps.
11. Yesterday's board + post-midnight tap → intent refuses, "new puzzle" state.
