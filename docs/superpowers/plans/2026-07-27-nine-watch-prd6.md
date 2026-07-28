# Nine on the wrist (PRD-6 phase 6a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a standalone-capable Apple Watch app for Nine — the full board as a
glanceable map, tap to dive into a 3×3 box at finger scale, and the Digital Crown
as the rose — with today's Steady daily handed off from iPhone over
WatchConnectivity because the watch is not allowed to compose it.

**Architecture:** One new watchOS application target (`NineWatch`) embedded in the
iOS app the way `NineWidgets` already is. It reuses the Engine verbatim, the
`Sources/Shared` phrase/speech layer verbatim, and — the load-bearing reuse —
**the same `BoardView` Canvas**, rendered twice at two camera positions rather than
reimplemented. The daily hand-off reuses `SharedDailyBoard`'s revision discipline
(monotone revision, day guard, persisted high-water mark) with WatchConnectivity as
the transport instead of an app-group file, and carries the **immutable
`GeneratedPuzzle`** rather than play state.

**Tech Stack:** Swift 6, SwiftUI (watchOS 11), WatchConnectivity, CouchKit,
XcodeGen, fastlane/match.

---

## Global Constraints

Copied verbatim from the specs; every task's requirements implicitly include these.

- **The covenant is binding** (`nine/PRD-7.md`): no IAP, no subscription, no tips,
  no ads, no gamification, no notifications, no streak shaming. The coach never
  places a digit. There is no fifth control button.
- **One new input concept per release, maximum.** This release spends it on the
  Crown rose. Nothing else new may be added.
- **Watch stays classic-only.** No variant channel reaches the wrist
  (`PROGRAM-2.0.md:80`). `VariantChannelSealTests` must keep passing, and its
  grep must be widened to cover `Sources/Watch`.
- **The watch never generates above catalog-easy** (`PROGRAM-2.0.md:112`). Enforced
  as `WatchComposePolicy.ceiling == .gentle`, with a seal test — not a convention.
- **`Sources/Engine` is frozen for this PRD.** No file under `Sources/Engine`
  changes. The 56-hash golden corpus must be byte-identical after every commit
  (`EXECUTING-A-PRD.md` §3).
- **No new field on `LibraryEntry`.** New persisted state is a sibling top-level
  `CouchStored` key (`EXECUTING-A-PRD.md` §2).
- **Never throw out of a container decode.** Every persisted/wire type decodes
  tolerantly.
- **Every user-facing string goes through the catalog.** No bare `String` literal
  reaches a sink. `scripts/strings.py --audit` and `StringSealTests` must both be
  taught about `Sources/Watch`, or the tree is invisible to them.
- **KVS identifier on the watch is the explicit `$(TeamIdentifierPrefix)com.couchsuite.nine`**,
  never `$(CFBundleIdentifier)` — the default silos the watch's streak
  (`PRD-6.md` §4 Step 1).
- **Entitlement/profile rule applies BEFORE merge** (`EXECUTING-A-PRD.md` §6):
  portal App ID → Matchfile → writable `match appstore` re-mint → merge. CI runs
  `match(readonly: true)` and can mint nothing. A new embedded bundle changes the
  iOS archive's profile set, so a merge without the re-mint breaks `beta_all` for
  the whole five-app suite.
- **Marketing version lockstep:** `MARKETING_VERSION: "1.1"`, matching the app.

---

## Decisions adjudicated up front

These reconcile contradictions between `PRD-6.md` (written earlier) and
`PROGRAM-2.0.md:112` + the kickoff instruction (later, and therefore controlling).
Each is recorded in `DEVIATIONS.md` at the end.

| # | Question | Decision | Why |
|---|---|---|---|
| D1 | Scope | **6a only.** 6b (complications + Smart Stack) deferred. | PRD-6 scopes two PRs itself. 6b needs a *second* new bundle id and a watch-side app group, doubling the provisioning blast radius on a PR that already cannot be CI-verified end to end. |
| D2 | WatchConnectivity | **In scope**, overriding PRD-6 §3's non-goal. | `PROGRAM-2.0.md:112` and the kickoff both require it. It is not optional polish: see D3. |
| D3 | What crosses the link | **The immutable `GeneratedPuzzle` down, a `PendingSolve` up. Never play state.** | `SharedDailyBoard`'s own safety proof (`SharedDailyBoard.swift:6-7`) is that "both sides only ever append moves… a lost race costs a move, never corruption". The watch has **undo and erase**, so that invariant does not hold on the wrist and last-writer-wins would silently delete a player's phone progress. A puzzle is a pure function of the day, so revision conflicts on it are unlosable. This also keeps PRD-6 §2.5's "in-progress boards do not hand off in v1" intact. |
| D4 | Compose ceiling | **`.gentle` only, on-watch.** The Steady daily arrives over the link. | The kickoff's rule, taken literally. There is no fast-seed catalog in the repo at all (`grep -rni pantry` → two lines, both in `PROGRAM-2.0.md`), so "catalog-easy" can only mean the easiest band. |
| D5 | Watch free play | **Gentle only.** No difficulty picker on the wrist. | Follows from D4. PRD-6 §4 Step 2's difficulty picker would offer bands the watch cannot compose. |
| D6 | No phone, no cached daily | **Honest empty state** ("Today's board is on your iPhone") plus a Gentle board the watch composes itself. Never a fake board, never a spinner that never ends. | The craft charter's "every state has a designed zero-state (honest absence over fake data)". |
| D7 | Board rendering | **Reuse `BoardView`**, with the three `.layerEffect` shader calls gated `#if !os(watchOS)`. | PRD-6 §4 Step 2: "one drawing surface, two camera positions — no second board implementation". Costs a small, behaviour-free extraction of the theme types out of `AppModel.swift` (Task 3). |
| D8 | `AppModel.swift` on watch | **Not compiled into the watch target.** A purpose-built `WatchModel` replaces it. | `AppModel` carries `LibraryCloudStore`, whose `CKContainer(identifier:)` traps on a binary without the CloudKit entitlement — the exact live macOS defect at `DEVIATIONS.md` ("a locally-built Nine cannot launch on macOS at all"). The watch gets KVS only, so importing `AppModel` would ship that trap to the wrist. |
| D9 | Game Center on watch | **Deferred.** `GameCenter.swift` keeps its current platform list. | PRD-6 §4 Step 3 asks for a slim watch branch. It is fire-and-forget reporting that the phone re-reports anyway once the solve lands in the shared KVS streak, so it buys nothing on the wrist and costs an entitlement conversation. Recorded in DEVIATIONS. |

---

## File Structure

**Created**

| File | Responsibility |
|---|---|
| `nine/Sources/Shared/WatchLink.swift` | The wire types and the adoption rule. `WatchDailyHandoff` (day, puzzle, revision, updatedAt), `WatchSolveReport` (day + the existing `PendingSolve`), `WatchComposePolicy` (the `.gentle` ceiling), and pure `encode`/`decode` to the `[String: Any]` plist dictionaries WatchConnectivity takes. Pure Foundation + Engine → compiles in the SwiftPM `NineShared` target, so all of it is unit-tested without a simulator. |
| `nine/Sources/App/Theme.swift` | `AccentChoice`, `ThemeTones`, `ThemeChoice`, and the `nineTheme` environment key — cut verbatim out of `AppModel.swift` and `NineApp.swift` so the board can be compiled without the model. |
| `nine/Sources/App/PhoneWatchLink.swift` | `#if os(iOS)` phone half of the link: `WCSessionDelegate`, publishes today's puzzle into `updateApplicationContext`, receives solve reports, hands them to `AppModel`. |
| `nine/Sources/Watch/WatchApp.swift` | `@main`, `Strings.install()`, the two-screen `NavigationStack`. |
| `nine/Sources/Watch/WatchModel.swift` | `@Observable` watch state: prefs subset, `nine.streak` (cloudSynced KVS), the current game, the handoff ledger, solve recording. |
| `nine/Sources/Watch/WatchLinkSession.swift` | `#if os(watchOS)` watch half of the link. |
| `nine/Sources/Watch/WatchHomeView.swift` | Today card, streak chip, Continue, "Gentle board". |
| `nine/Sources/Watch/WatchBoardView.swift` | The map: `BoardView` at overview scale, tap → box. |
| `nine/Sources/Watch/WatchBoxView.swift` | The lens: same `BoardView`, scaled and offset to one box, plus peer rails. |
| `nine/Sources/Watch/CrownRose.swift` | The dial: bounded run ∅…1–9…✕, live preview, three commit paths. |
| `nine/Sources/Watch/WatchCelebration.swift` | `WKHaptic` mini-score against the shared wave timing. |
| `nine/NineWatch.entitlements` | KVS pinned to `$(TeamIdentifierPrefix)com.couchsuite.nine`. |
| `nine/Tests/SharedTests/WatchLinkTests.swift` | Wire round-trip, adoption rule, compose ceiling, day guard. |
| `nine/Tests/EngineTests/WatchSealTests.swift` | Source-grep seals: no unbounded generation in `Sources/Watch`; no variant channel; `Sources/Watch` is in both string-audit tree lists. |

**Modified**

| File | Change |
|---|---|
| `couchkit/Package.swift` | `+ .watchOS(.v11)`. |
| `couchkit/Sources/CouchKit/{CouchStore,CouchUI,CouchGlass,GlassComponents}.swift` | Widen the platform gate to include `os(watchOS)`; `CouchScale.chrome` gains a watch branch at 0.42. |
| `nine/Sources/App/AppModel.swift` | Theme types move out (Task 3); solve-report ingestion added (Task 8). |
| `nine/Sources/App/NineApp.swift` | `nineTheme` env key moves out; phone-side link activated. |
| `nine/Sources/App/CoachCard.swift` | `CoachFocus` moves to `BoardView.swift` (it is board-render input). |
| `nine/Sources/App/BoardView.swift` | The three `.layerEffect` calls gated `#if !os(watchOS)`. |
| `nine/Sources/Shared/EnglishPhrases.swift` | New watch keys. |
| `nine/Sources/Strings/Localizable.xcstrings` | Regenerated + nine locales. |
| `nine/project.yml` | `NineWatch` target; embed with `destinationFilters: [iOS]`. |
| `nine/Package.swift` | unchanged (watch tree is Xcode-only, like `Sources/App`). |
| `.gitignore` | `!nine/NineWatch.entitlements`, `nine/WatchInfo.plist`. |
| `fastlane/Matchfile` | `+ com.couchsuite.nine.watchkitapp`. |
| `fastlane/Fastfile` | append the watch bundle to `APPS["nine"][:extensions]`. |
| `nine/scripts/strings.py`, `nine/Tests/EngineTests/StringSealTests.swift`, `CatalogTests.swift` | teach the gates about `Sources/Watch` / the `NineWatch` target. |
| `.github/workflows/nine-engine.yml` | add a watchOS-simulator build of the new target. |
| `nine/DEVIATIONS.md`, `nine/PROGRAM-2.0.md`, `TESTFLIGHT.md` | the record. |

---

## Task 1: CouchKit learns watchOS

**Files:** Modify `couchkit/Package.swift:15-21`, `couchkit/Sources/CouchKit/{CouchStore,CouchUI,CouchGlass,GlassComponents}.swift`

**Interfaces:**
- Produces: a `CouchKit` product that resolves for `generic/platform=watchOS`, exposing `CouchStored`, `CouchPalette`, `CouchTypography`, `CouchScale`, `.couchGlass(in:)`, `GlassChip`.

- [ ] **Step 1: Add the platform.** In `couchkit/Package.swift`, add `.watchOS(.v11)` to the `platforms:` array. Update the file header comment, which currently says "(tvOS)".

- [ ] **Step 2: Widen the four gates.** In each of `CouchStore.swift:11`, `CouchUI.swift:4`, `CouchGlass.swift:14`, `GlassComponents.swift:7`, change
  `#if os(tvOS) || os(iOS) || os(macOS)` → `#if os(tvOS) || os(iOS) || os(macOS) || os(watchOS)`.
  Leave `HelpKit.swift`, `AsciiEngine.swift`, `PhotoKitPlus.swift`, `RemoteKit.swift` and `PadKit.swift`'s gated half **unchanged** — they already exclude watchOS, and the watch wants none of them.

- [ ] **Step 3: The chrome scale branch.** In `CouchUI.swift`, `CouchScale.chrome` gains `#if os(watchOS) 0.42`. (PRD-6 §4 Step 0 fixes this number.)

- [ ] **Step 4: Compile it.** `xcodebuild -scheme CouchKit -destination 'generic/platform=watchOS' -derivedDataPath /tmp/ckwatch build` from `couchkit/`. Expected: succeeds. Any file that fails is a gate that needs widening or excluding — fix and re-run until clean.

- [ ] **Step 5: Prove the other four apps did not move.** `swift test --package-path couchkit`, then one tvOS build of a sibling app: `cd rabbit-ears && COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate && xcodebuild -project RabbitEars.xcodeproj -scheme RabbitEars -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build`. Expected: both pass. Adding a platform floor must not move an existing one.

- [ ] **Step 6: Commit.** `git commit -m "CouchKit: compile for watchOS (PRD-6 Step 0)"`

---

## Task 2: The wire — `WatchLink`

**Files:** Create `nine/Sources/Shared/WatchLink.swift`, `nine/Tests/SharedTests/WatchLinkTests.swift`

**Interfaces:**
- Consumes: `GeneratedPuzzle`, `Difficulty`, `DailySeed` (Engine); `PendingSolve` (`SharedDailyBoard.swift:21`).
- Produces:
  - `WatchDailyHandoff{ schemaVersion, dayOrdinal, puzzle, revision, updatedAt }`, `.isCurrent(today:)`, `.supersedes(known:today:)`
  - `WatchSolveReport{ dayOrdinal, solve: PendingSolve }`
  - `WatchComposePolicy.ceiling: Difficulty`, `.mayComposeLocally(_:) -> Bool`
  - `WatchLinkWire.encode(_:) -> [String: Any]`, `.decodeHandoff(_:)`, `.decodeReport(_:)`

- [ ] **Step 1: Write the failing tests** in `Tests/SharedTests/WatchLinkTests.swift`:

```swift
import Foundation
import Testing
@testable import NineShared
import NineEngine

@Suite("WatchLink")
struct WatchLinkTests {
    private func handoff(day: Int, revision: Int) -> WatchDailyHandoff {
        WatchDailyHandoff(
            dayOrdinal: day,
            puzzle: PuzzleGenerator.generate(seed: DailySeed.seed(forDayOrdinal: day), difficulty: .steady),
            revision: revision,
            updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    @Test func theWireSurvivesARoundTrip() throws {
        let sent = handoff(day: 9_400, revision: 3)
        let got = try #require(WatchLinkWire.decodeHandoff(WatchLinkWire.encode(sent)))
        #expect(got == sent)
    }

    @Test func theWireIsPlistSafe() {
        // WCSession rejects a dictionary holding anything but plist types.
        let payload = WatchLinkWire.encode(handoff(day: 9_400, revision: 1))
        #expect(payload.values.allSatisfy { $0 is Data || $0 is Int || $0 is String })
    }

    @Test func garbageDecodesToNilRatherThanThrowing() {
        #expect(WatchLinkWire.decodeHandoff(["nine.watch.handoff": Data([0x00, 0x01])]) == nil)
        #expect(WatchLinkWire.decodeHandoff([:]) == nil)
        #expect(WatchLinkWire.decodeReport(["nine.watch.solve": Data("{}".utf8)]) == nil)
    }

    @Test func onlyAStrictlyHigherRevisionForTodayIsAdopted() {
        let h = handoff(day: 9_400, revision: 5)
        #expect(h.supersedes(known: 4, today: 9_400))
        #expect(!h.supersedes(known: 5, today: 9_400))   // equal is not newer
        #expect(!h.supersedes(known: 6, today: 9_400))
        #expect(!h.supersedes(known: 0, today: 9_401))   // yesterday's board, never
    }

    @Test func theWatchMayComposeGentleAndNothingHarder() {
        #expect(WatchComposePolicy.ceiling == .gentle)
        #expect(WatchComposePolicy.mayComposeLocally(.gentle))
        for band in [Difficulty.steady, .sharp, .nocturne] {
            #expect(!WatchComposePolicy.mayComposeLocally(band))
        }
    }

    @Test func theHandedOffPuzzleIsTheOneTheWatchWouldHaveComposed() {
        // The link is a courier, not an authority: the daily stays a pure
        // function of the day on every device (PRD-6 §6 item 6).
        let day = 9_400
        let sent = handoff(day: day, revision: 1)
        let localTruth = PuzzleGenerator.generate(
            seed: DailySeed.seed(forDayOrdinal: day), difficulty: .steady
        )
        #expect(sent.puzzle == localTruth)
    }

    @Test func aSolveReportCarriesTheDayItBelongsTo() throws {
        let report = WatchSolveReport(
            dayOrdinal: 9_400,
            solve: PendingSolve(solvedAt: Date(timeIntervalSinceReferenceDate: 10), seconds: 212)
        )
        let got = try #require(WatchLinkWire.decodeReport(WatchLinkWire.encode(report)))
        #expect(got == report)
    }

    @Test func aNewerSchemaIsRefusedRatherThanMisread() {
        var future = handoff(day: 9_400, revision: 1)
        future.schemaVersion = WatchDailyHandoff.currentSchemaVersion + 1
        let wire = WatchLinkWire.encode(future)
        #expect(WatchLinkWire.decodeHandoff(wire) == nil)
    }
}
```

- [ ] **Step 2: Run them and watch them fail.** `cd nine && swift test --filter WatchLink`
  Expected: FAIL, "cannot find 'WatchDailyHandoff' in scope".

- [ ] **Step 3: Write `Sources/Shared/WatchLink.swift`.** Header comment must state
  the D3 reasoning (why the puzzle crosses and play state does not). Body:

```swift
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

/// Today's daily, couriered to a watch that is not allowed to compose it.
public struct WatchDailyHandoff: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var dayOrdinal: Int
    public var puzzle: GeneratedPuzzle
    public var revision: Int
    public var updatedAt: Date

    public init(schemaVersion: Int = WatchDailyHandoff.currentSchemaVersion,
                dayOrdinal: Int, puzzle: GeneratedPuzzle,
                revision: Int, updatedAt: Date) { … }

    public func isCurrent(today: Int) -> Bool { dayOrdinal == today }

    /// The whole adoption rule, in one place: today's, and strictly newer.
    public func supersedes(known: Int, today: Int) -> Bool {
        isCurrent(today: today) && revision > known
    }
}

public struct WatchSolveReport: Codable, Equatable, Sendable {
    public var dayOrdinal: Int
    public var solve: PendingSolve
    public init(dayOrdinal: Int, solve: PendingSolve) { … }
}

/// The hardest band the watch composes for itself.
public enum WatchComposePolicy {
    public static let ceiling: Difficulty = .gentle
    public static func mayComposeLocally(_ difficulty: Difficulty) -> Bool {
        difficulty == ceiling
    }
}

public enum WatchLinkWire {
    public static let handoffKey = "nine.watch.handoff"
    public static let reportKey = "nine.watch.solve"
    // encode → [key: Data]; decode → try? JSONDecoder, then reject a
    // schemaVersion above ours (the WidgetSnapshot doctrine: a reader that
    // cannot understand a payload says so rather than half-reading it).
}
```

- [ ] **Step 4: Run the tests.** `swift test --filter WatchLink` — expected: PASS.

- [ ] **Step 5: Run the corpus.** `swift test` — expected: PASS, all suites, corpus 56/56.

- [ ] **Step 6: Commit.** `git commit -m "Nine: the watch wire — a puzzle down, a solve up (PRD-6)"`

---

## Task 3: Free the board from the model

Behaviour-free extraction so `BoardView` can compile into a target that has no
`AppModel`. **Nothing in this task may change a rendered pixel or a spoken word.**

**Files:** Create `nine/Sources/App/Theme.swift`; modify `AppModel.swift`, `NineApp.swift`, `CoachCard.swift`, `BoardView.swift`

- [ ] **Step 1: Cut, don't rewrite.** Move `AccentChoice` (`AppModel.swift:30`),
  `ThemeTones` (`:105`) and `ThemeChoice` (`:190`) — with their comments intact —
  into a new `Sources/App/Theme.swift`. Move the `nineTheme` `EnvironmentKey` +
  `EnvironmentValues` extension (`NineApp.swift:207`) into the same file.
- [ ] **Step 2: Move `CoachFocus`** from `CoachCard.swift:21` to `BoardView.swift`,
  beside the property that consumes it.
- [ ] **Step 3: Gate the shaders.** Wrap the three `.layerEffect(…)` modifiers in
  `BoardView.refracted(now:)` (`:250-291`) in `#if !os(watchOS) … #endif`, and gate
  `lensActive` to return `false` on watchOS. PRD-6 §2.4 already rules that the
  Canvas-drawn Reduce-Motion wave is the watch's celebration.
- [ ] **Step 4: Prove nothing moved.** All three platform builds, then the AX
  baselines, which are the pixel-level paper trail:
  `swift test` · three `xcodebuild` destinations · `python3 nine/scripts/ax-snapshot.py`
  Expected: builds pass, **AX diff is empty**. A non-empty diff here means the
  extraction was not behaviour-free — fix, do not re-record.
- [ ] **Step 5: Commit.** `git commit -m "Nine: the board's theme leaves the model (PRD-6)"`

---

## Task 4: The `NineWatch` target

**Files:** Modify `nine/project.yml`, `.gitignore`; create `nine/NineWatch.entitlements`, `nine/Sources/Watch/WatchApp.swift` (placeholder that builds)

- [ ] **Step 1: Entitlements, checked in.** `nine/NineWatch.entitlements` with
  `com.apple.developer.ubiquity-kvstore-identifier` = the **literal**
  `$(TeamIdentifierPrefix)com.couchsuite.nine`, and a comment saying why the
  default `$(CFBundleIdentifier)` would fork the streak. No CloudKit, no
  `aps-environment`, no app group (6b's problem).
- [ ] **Step 2: Un-ignore it.** `.gitignore` has a blanket `*/*.entitlements`; add
  `!nine/NineWatch.entitlements` beside the three existing negations, and an ignore
  line for `nine/WatchInfo.plist` (the existing rule names `WidgetsInfo.plist`
  exactly and will not match).
- [ ] **Step 3: The target**, modelled line-for-line on `NineWidgets`
  (`project.yml:185-239`) with the differences that matter:

```yaml
  NineWatch:
    type: application
    supportedDestinations: [watchOS]
    deploymentTarget:
      watchOS: "11.0"
    sources:
      - Sources/Watch
      - Sources/Engine
      - Sources/Shared
      - Sources/Strings          # third bundle, third Bundle.main
      # Named files, not Sources/App: the board is reused, the phone UI is not.
      - Sources/App/BoardView.swift
      - Sources/App/BoardAccessibility.swift
      - Sources/App/Theme.swift
      - Assets.xcassets
    dependencies:
      - package: CouchKit
    settings:
      base:
        SWIFT_VERSION: "6.0"
        PRODUCT_BUNDLE_IDENTIFIER: com.couchsuite.nine.watchkitapp
        MARKETING_VERSION: "1.1"
        CURRENT_PROJECT_VERSION: 1
        SKIP_INSTALL: true
        CODE_SIGN_STYLE: Manual
        CODE_SIGN_IDENTITY: "Apple Distribution"
        DEVELOPMENT_TEAM: ${COUCH_TEAM_ID}
        "PROVISIONING_PROFILE_SPECIFIER[sdk=watchos*]": "match AppStore com.couchsuite.nine.watchkitapp"
        "CODE_SIGN_ENTITLEMENTS[sdk=watchos*]": NineWatch.entitlements
        "CODE_SIGN_ENTITLEMENTS[sdk=watchsimulator*]": NineWatch.entitlements
    entitlements: ~   # checked-in file above, not generated
    info:
      path: WatchInfo.plist
      properties:
        CFBundleDisplayName: Nine
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        CFBundleDevelopmentRegion: en
        CFBundleLocalizations: [en, ja, de, fr, es, it, pt-BR, ko, zh-Hans, nl]
        WKApplication: true
        WKRunsIndependentlyOfCompanionApp: true
```

  and beside the widget entry in `Nine.dependencies`:

```yaml
      - target: NineWatch
        embed: true
        destinationFilters: [iOS]
```

- [ ] **Step 4: A `@main` that builds.** Minimal `Sources/Watch/WatchApp.swift`:
  `Strings.install()` at the top of the `App` struct (a third process needs its own
  bootstrap — `NineWidgetBundle.swift:25` is the precedent), one `Text`.
- [ ] **Step 5: Generate and build all four graphs.**

```bash
cd nine && COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate
xcodebuild -project Nine.xcodeproj -scheme NineWatch  -destination 'generic/platform=watchOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
for d in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$d" -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
done
```

  Expected: all four pass. **The tvOS one is the regression that matters** — PRD-3's
  `destinationFilters` trap fires here if the watch app enters the tvOS graph.

- [ ] **Step 6: Prove the embed is iOS-only.** `plutil -p build/Build/Products/*-appletvsimulator/Nine.app/Info.plist` and `ls` the tvOS `.app` — expected: **no `Watch/` directory**; the iOS one has it.
- [ ] **Step 7: Commit.**

---

## Task 5: The watch model and the link

**Files:** Create `Sources/Watch/WatchModel.swift`, `Sources/Watch/WatchLinkSession.swift`, `Sources/App/PhoneWatchLink.swift`; modify `AppModel.swift`, `NineApp.swift`

- [ ] **Step 1: `WatchModel`** — `@MainActor @Observable`, holding only:
  `@CouchStored("nine.streak", cloudSynced: true) streak: StreakState`,
  `@CouchStored("nine.prefs") prefs: NinePrefsWatch` (theme/accent/showErrors only —
  a *sibling* key would fork prefs, so read the same `nine.prefs` key with a
  tolerant decode that ignores everything it does not know),
  `@CouchStored("nine.watch.link") link: WatchLinkLedger` (local: last adopted
  handoff revision, and the day of any solve not yet acknowledged),
  plus `game: NineGame?`, `board: WatchScreen`, `selection: Int?`.
  Autosave the in-progress game to a local `CouchStored` key — **not** `nine.library`,
  which is not cloud-synced and whose 20-entry prune has nothing to do with a wrist.
- [ ] **Step 2: `WatchLinkSession`** — `WCSessionDelegate` on the watch:
  `didReceiveApplicationContext` → `WatchLinkWire.decodeHandoff` → `supersedes(known:today:)`
  → adopt, persist the revision **before** using the puzzle (the persisted
  high-water mark is the cold-launch clobber fix, `SharedDailyBoard.swift:122-137`).
  On solve: `transferUserInfo(WatchLinkWire.encode(report))` — queued and guaranteed,
  unlike `sendMessage`.
- [ ] **Step 3: `PhoneWatchLink`** — `#if os(iOS)`. Publishes today's composed
  daily into `updateApplicationContext` from the same call sites as
  `WidgetBridge.publish`, gated on `WCSession.isSupported() && session.isPaired && isWatchAppInstalled`.
  Bumps the revision only when the day changes — the puzzle is immutable, so a
  per-move bump would burn the link for nothing.
- [ ] **Step 4: Phone-side ingestion.** `AppModel.ingestWatchSolve(_:)`, modelled
  on `ingestSharedDailyBoard`'s `pendingSolve` branch (`AppModel.swift:1424-1459`)
  and guarded by the same `streak.hasCompleted(day:)` idempotence. **Reuse that
  branch rather than copying it** — `BoardIntents.swift:80-83` records what a
  hand-copied streak rule cost last time.
- [ ] **Step 5: Tests** — the adoption/idempotence logic lives in `WatchLink` and is
  already covered; add one test that ingesting the same report twice records one
  solve.
- [ ] **Step 6: Commit.**

---

## Task 6: The map, the lens, and the Crown rose

**Files:** Create `WatchHomeView.swift`, `WatchBoardView.swift`, `WatchBoxView.swift`, `CrownRose.swift`, `WatchCelebration.swift`

- [ ] **Step 1: Home.** A `List` (watch idiom, not the phone shelf): Today row
  (state from the handoff — composed / waiting for iPhone / in progress / solved),
  streak chip, Continue, "Gentle board". No difficulty picker (D5). No timer (§3).
- [ ] **Step 2: The map.** `BoardView` at `side` = screen width, `inset: 4`,
  `roseOpen: false`, `roseLens: nil`, `waveOrigin: nil`, `afterglowTilt: nil`.
  Tap → `BoardMetrics.cellIndex(at:side:)` → `cell / 27 * 3 + (cell % 9) / 3` → box.
  Box tap targets are ~63pt; per-cell targets are deliberately not offered.
- [ ] **Step 3: The lens.** The **same** `BoardView`, `.scaleEffect(3, anchor:)` +
  offset so one box fills the screen, inside a `.clipShape`. Peer rails: two slim
  strips reading the digits already present in the selected cell's row and column
  (row+column only — PRD-6 §7's leaning, and three hints is clutter at 45mm).
- [ ] **Step 4: The Crown rose.**
  `.digitalCrownRotation($dial, from: 0, through: 10, by: 1, sensitivity: .medium, isHapticFeedbackEnabled: true)`
  — 0 = ∅, 1–9, 10 = ✕. **A bounded run, never wrapping**: overshoot stops at an
  end, so it can never loop back toward a placement. The dialed digit previews in
  the cell via `BoardView`'s existing `previewDigit`/`previewPencil` — no new
  rendering path. Digits already complete on the board render dimmed on the arc,
  the same rule as rose petals. Commit: tap the selected cell, or
  `handGestureShortcut(.primaryAction)`; long-press commits a pencil mark.
  Changing selection or leaving the box clears the preview. **Nothing places
  without an explicit commit.**
- [ ] **Step 5: Celebration.** The Canvas luminance wave (already shipped, the only
  one that survives without shaders) plus three rising `WKInterfaceDevice.play`
  clicks timed from `AfterglowScoreTiming`, `.success` as the Solved chip lands at
  2.4 s. Always-On (`\.isLuminanceReduced`) shows silhouette + fill arc, **no
  digits** — a bystander must not read the board off a dimmed wrist.
- [ ] **Step 6: Strings.** Every literal via `Strings.string(...)`. **Reuse existing
  catalog keys wherever the English already matches** (`difficulty.gentle.title`,
  the Continue and streak keys) and add only genuinely new ones to
  `EnglishPhrases.table`, in sorted position, each with a comment
  (`--build-catalog` refuses a key with none).
- [ ] **Step 7: Teach the gates about the new tree.** `scripts/strings.py:55` `TREES`,
  `StringSealTests.swift:68` `trees`, `CatalogTests`'s `["Nine", "NineWidgets"]`
  target loop, and `VariantChannelSealTests`'s grep — all four gain `Sources/Watch`
  / `NineWatch`. A tree no gate scans is a tree that ships English.
- [ ] **Step 8: Translate.** `python3 scripts/strings.py --build-catalog`, then the
  nine locales, then `--audit`. New units are `needs_review`, consistent with
  PRD-20's standing deferral.
- [ ] **Step 9: Verify.** `swift test`; watch build; iOS/tvOS/macOS builds;
  `ax-snapshot.py` (expected empty — the watch is not in that lane, but the board
  extraction is); `strings.py --audit`.
- [ ] **Step 10: Commit.**

---

## Task 7: Drive it

A green build is not evidence (`EXECUTING-A-PRD.md` §5).

- [ ] **Step 1:** Boot a 45mm watch simulator, install, and walk: home → today →
  map → box dive → dial → commit by tap → pencil by long-press → back out (places
  nothing) → undo → solve a Gentle board end to end. Screenshot each.
- [ ] **Step 2:** Repeat the tap-target check at **41mm** (the smallest) — box
  targets must stay honest.
- [ ] **Step 3:** Kill and relaunch mid-board: resume must land on the last box and
  selection.
- [ ] **Step 4:** Measure Gentle compose on the watch simulator, and measure Steady
  too even though the watch will never run it — the number is what makes D4 a
  measurement rather than an adjective. Record both in DEVIATIONS.
- [ ] **Step 5:** Commit the screenshots' findings, not the screenshots.

---

## Task 8: The record and the merge gate

- [ ] **Step 1: `DEVIATIONS.md`** — a new section carrying D1–D9 with reasons,
  every measured number, and plainly: what was **not** done (6b complications, Game
  Center on watch, a real device, Double Tap — untestable in a simulator, a watch AX
  lane — `describe-ui` is iOS-only, the same wall PRD-19/20/22 hit).
- [ ] **Step 2: `PROGRAM-2.0.md`** status row for PRD-6.
- [ ] **Step 3: `TESTFLIGHT.md`** — the watch signing choreography, modelled on the
  widget section at `:200-221`.
- [ ] **Step 4: `fastlane/Matchfile`** += `com.couchsuite.nine.watchkitapp`;
  **`fastlane/Fastfile`** `APPS["nine"][:extensions]` += the same. No new lane and
  no new platform value — the watch app ships inside the iOS ipa.
- [ ] **Step 5: CI.** Add a watchOS-simulator build of `NineWatch` to
  `nine-engine.yml`. Note in the PR that `nine-accessibility.yml`'s existing
  `-scheme Nine -destination 'generic/platform=iOS Simulator'` build now also
  compiles the watch target, so a watch compile error fails that lane first.
- [ ] **Step 6: The merge blocker, stated loudly in the PR body.** This PR **must
  not merge** until a human with portal access has, in this order:
  1. registered App ID `com.couchsuite.nine.watchkitapp` with the iCloud
     key-value-store capability;
  2. run `source signing.env && fastlane match appstore` **writable**, re-minting
     the iOS `com.couchsuite.nine` profile (embedding a new bundle changes the
     archive's profile set) and minting the watch profile;
  3. verified with `fastlane beta app:nine platform:ios upload:false`.
  Merging first breaks `beta_all` for all five apps, not just Nine.

---

## Self-review

**Spec coverage.** PRD-6 §2.1 map → Task 6.2 · §2.2 lens + peer rails → 6.3 ·
§2.3 Crown rose → 6.4 · §2.4 sessions/Always-On/celebration → 6.5, 7.3 ·
§2.5 sync → Task 5, amended by D3 · §3 non-goals honoured except the
WatchConnectivity one, overridden by D2 with its reason · §4 Step 0 → Task 1 ·
Step 1 → Task 4 + 8.4 · Step 2 → Tasks 3, 6 · Step 3 → deferred, D9 ·
Step 4 (6b) → deferred, D1 · §6 checklist items 1–8 → Tasks 4.5–4.6, 7, and
item 10 → 8.6. Items 9 (6b) and the real-device half of 3 and 8 are
recorded as not done.

**Type consistency.** `WatchDailyHandoff`, `WatchSolveReport`, `WatchComposePolicy`,
`WatchLinkWire` are spelled identically in Tasks 2, 5 and 6. `supersedes(known:today:)`
keeps that argument label in the test, the type and the call site.

**Known thin spot, stated rather than hidden:** Task 6's Crown-rose feel is the one
thing this plan cannot verify. PRD-6 §5 sets the gate at "ten consecutive
comfortable solves by a fresh wrist", and a simulator crown driven by a scroll
wheel cannot answer it. The PR says so.
