# PRD-30 (Quiet Presence) + PRD-33 (Nine, Everywhere You Ask) — implementation plan

Neither `nine/PRD-30.md` nor `nine/PRD-33.md` existed when this started;
`PROGRAM-2.0.md:97` and `:100` were the whole spec, the same way they were for
PRD-25, PRD-26 and PRD-31. Both PRDs get written as part of this work and become
the forward documents.

Rejected by the plan and still rejected: **Siri voice solving** (slower than the
rose = demo-ware).

---

## 0. Facts established before writing a line, from the SDK rather than memory

Xcode 26.6 / iOS 26.5 SDK. Every one of these changes what gets built.

| Claim | Verdict | Evidence |
|---|---|---|
| Live Activities need an entitlement / a `match` re-mint | **False** | The only build settings that exist are `INFOPLIST_KEY_NSSupportsLiveActivities` / `…FrequentUpdates` in `CoreBuildSystem.xcspec`. No entitlement, no App ID capability. **The trap that fired three times does not fire here.** |
| ActivityKit is importable everywhere the app target builds | **Half true, and the half matters** | `canImport(ActivityKit)` is **true on macOS** and false on tvOS/watchOS (probed with `swiftc -typecheck` per target). But `ActivityAttributes` is `@available(macOS, unavailable)`, so `#if canImport(ActivityKit)` compiles and then fails on the conformance. The fence must be `#if os(iOS)`. |
| A third-party app can donate a Journaling Suggestion | **False — there is no API** | `JournalingSuggestions.swiftinterface` is 350 lines and entirely a *consumer* surface: `JournalingSuggestionsPicker`, plus 15 closed system asset types (Workout, Contact, Location, Song, Podcast, Photo, Video, LivePhoto, MotionActivity, StateOfMind, Reflection, EventPoster…). No `donate`, no provider protocol, no symbol named `JournalingSuggestion` anywhere else in the SDK. |
| StandBy is a widget family you can target | **False** | StandBy is a `WidgetLocation`, and the only API taking one is `disfavoredLocations(_:for:)` — an *opt-out*. There is no `\.widgetLocation` to read. StandBy renders `systemSmall`; the only render-time levers are `\.showsWidgetContainerBackground` and `\.widgetRenderingMode`. |
| App Shortcut phrases localize through `Localizable.xcstrings` | **False** | They need their own `AppShortcuts.(xc)strings`, validated by a real build phase: `appshortcutstringsprocessor --help` names the file and `--app-name-override` ("Override looking for `${ApplicationName}`"). |
| `SetFocusFilterIntent` needs an entitlement | **False**, and it is available on iOS 16 / macOS 13 / tvOS 16 / watchOS 9 — every platform Nine ships. |

Two findings from the codebase that shape the work more than the SDK did:

1. **The widget cannot see the player's theme.** `SharedAppearance` (`nine.appearance`)
   goes to `CouchStored` + KVS, **not** the app group, and `WidgetSnapshot` carries no
   appearance fields — so `WidgetPalette` is a hardcoded glacier/ember/paper triple.
   Nobody noticed because the three existing widgets are small and glanceable. A
   StandBy face and a Lock Screen board glyph are the first surfaces where wearing
   someone else's accent is obvious.
2. **⌥-click "why" is already wired on Mac** (`MacUI.swift:534-538`), so one of
   PRD-33's four Mac items is done. It lacks iOS's `announce(...)` and that is the
   actual gap.

---

## 1. PRD-30 — Quiet Presence

### 1.1 The payload is the glyph, and it contains no clock

`Sources/Shared/QuietPresence.swift` — Foundation only, Linux-clean, `swift test`-covered.

```swift
public struct BoardGlyph: Codable, Equatable, Hashable, Sendable   // 22 bytes: two 81-bit masks
public struct DailyPresence: Codable, Equatable, Hashable, Sendable // glyph + day + revision
public enum PresenceDecision / PresencePolicy                       // pure lifecycle rules
```

`DailyPresence` has **no `Date`, no `TimeInterval`, no streak field, and no count**.
That is not a style choice, it is PRD-30's headline requirement made structural: a
payload with no clock in it cannot grow a countdown by accident. Two seal tests
enforce it the way `VariantChannelSealTests` seals the variant channel:

- `testThePresencePayloadCarriesNoClockAndNoStreak` — reflects over the encoded
  JSON keys.
- `testTheLiveActivityViewNamesNoTimerApi` — greps the Live Activity source for
  `timerInterval`, `Text(…, style:`, `.timer`, `countsDown`, `AlertConfiguration`,
  `streak`. Any hit fails.

### 1.2 The lifecycle, as a pure function

`PresencePolicy.decide(...) -> PresenceDecision` (`.start`/`.update`/`.end`/`.none`),
driven from the four places the app already publishes widget state. The rules:

- **Only after the board has been touched.** An untouched board is not a bookmark,
  it is an advert. This is what makes the activity *the player's own act* rather
  than something the app did to their Lock Screen.
- Only today's daily. Never a free-play board, never an archive day.
- Ends on solve, on day rollover, and when the pref goes off.
- `staleDate` = next local midnight; stale renders the glyph dimmed with no caption
  rather than saying anything.
- `pushType: nil` — Nine holds no push token and no APNs plumbing enters the app.
- `alertConfiguration` is never passed. Ever. Sealed by the grep above.

### 1.3 Dynamic Island: a tiny board glyph, and nothing else

`compactLeading` and `minimal` draw the glyph at dot scale; `compactTrailing` is
`EmptyView()`. Expanded adds the glyph at size plus the band word. `widgetURL` is
`nine://daily`.

### 1.4 StandBy: `systemSmall` with its background taken away

There is no StandBy API, so there is an inference, and it is named rather than
hidden: `family == .systemSmall && showsWidgetContainerBackground == false` **is**
StandBy today (Lock Screen widgets are `accessory*` families; the iOS 18 tinted
Home Screen keeps its container background and only moves
`widgetRenderingMode` to `.accented`). `DailyWidgetViews.small` grows an ambient
arm: the glyph large and centred, no percentage, no chrome, zero animation
(idle-pixel test), and every fill expressed as a shape style so Night Mode's
`.vibrant` monochrome works instead of fighting a hardcoded blue.

### 1.5 Appearance reaches the widget process

`WidgetSnapshot` gains `themeRaw: String?` / `accentRaw: String?` — additive
optionals, `schemaVersion` stays 1, exactly as `lastGraceDay`'s doc comment
prescribes. A tiny Foundation-side palette in `Sources/Shared` resolves the two
raw strings to RGB triples so `Sources/Widgets` stops hardcoding glacier. The
numbers come from `Theme.swift` and a test pins the two lists identical, because
two palettes that drift are worse than one that is wrong.

### 1.6 One pref row

`NinePrefs.livePresence: Bool = true`, in Feel. Default **on**, with the covenant
argument written down: this is not a notification because it is created only by
the player's own act, it never alerts, and it ends itself — and the OS already
owns the global off switch.

---

## 2. PRD-33 — Nine, Everywhere You Ask

### 2.1 App Shortcuts

`Sources/App/NineIntents.swift`, `#if os(iOS) || os(macOS)`. Four shortcuts, well
under the 10-shortcut cap, reaching `AppModel` through
`AppDependencyManager.shared.add` (registered in `NineApp.init`) — a `@MainActor`
class is implicitly `Sendable`, which is what `@AppDependency` requires.

| Intent | Opens app | Does |
|---|---|---|
| `StartTodaysDailyIntent` | yes | `model.openToday()` |
| `ContinueBoardIntent` | yes | resume the most recent in-progress board |
| `HowsMyStreakIntent` | **no** | returns a dialog. Never shames: a zero streak says the board is waiting, not that you broke something. |
| `StartABoardIntent(band:)` | yes | `model.startFree(band)` over a `NineBand: AppEnum` |

The band parameter is why this is four shortcuts and not eight: one phrase
template with `parameterPresentation` covers all five bands.

`Sources/Shortcuts/AppShortcuts.xcstrings` — its **own** tree, listed only by the
`Nine` target, because the validator runs per-target and `NineWidgets` declares no
shortcuts. Hand-authored on purpose (its keys are English sentences, not dotted
ids, and `appshortcutstringsprocessor` owns its schema, so `scripts/strings.py`
would have to learn a second, incompatible catalog to generate it), and therefore
policed by a new `AppShortcutCatalogTests`: every phrase literal in the Swift has
a row, every row has all ten locales, every locale contains `${applicationName}`,
every non-`en` unit is `needs_review`.

### 2.2 Focus filters — the only thing Nine has to filter is itself

`QuietShelfFilter: SetFocusFilterIntent` with two parameters, `hideDaily` and
`hideStreak`. Nine sends no notifications, so `appContext` stays default and there
is no notification predicate to set — the filter's whole job is to take the *pull*
out of the shelf:

- `hideStreak` → no `StreakChip`, on the shelf, on the Mac, and in the widget.
- `hideDaily` → the Today card keeps its board and loses its urgency: no fill
  ring, no percentage, no "Today" framing. A board, when you want one.

State goes to a sibling blob `nine.focus` (local, never KVS — a Focus is a
property of the device in front of you) **and** to `WidgetSnapshot`, because the
widget has to go quiet too or the filter is a lie on the Home Screen.

### 2.3 Interactive-widget growth

- `NineBoardWidget` gains `.systemMedium`: board left, 3×3 digit rail right, both
  interactive. A move is one tap after selection instead of a scroll.
- `StaticConfiguration` → `AppIntentConfiguration` with
  `BoardWidgetConfiguration: WidgetConfigurationIntent`. The one parameter that is
  real today is **which side the digit rail sits on** — which is *handedness*, the
  thing PRD-31 deferred as "a settings row, and the covenant makes those
  expensive." A widget configuration is not a settings row: it is per-placed
  widget, edited in the system's own sheet, and costs the app no chrome. PRD-24's
  channel parameter slots into the same intent.
- The conversion is the risk, not the feature: an already-placed
  `StaticConfiguration` widget meeting an `AppIntentConfiguration` of the same
  `kind`. This is driveable — place the widget on the old build, install the new
  one, look — so it gets driven rather than assumed.

### 2.4 Journaling Suggestions — cannot be built, and the near-miss is worth recording

No donation API exists (§0). The one path that would technically work is examined
and refused: **HealthKit `HKStateOfMind`** is a journaling-suggestion asset type,
so an app that logs a mood does produce a suggestion. Taking it would mean a
HealthKit entitlement and capability (the trap that has fired three times), a
permission prompt, and asking a player how they feel about a sudoku. The product
intent — "the completed daily as a private reflective moment" — is already shipped
as PRD-26's debrief, which is a pull-up you have to ask for.

### 2.5 The Mac

1. **`onOpenURL` is missing on macOS** while `project.yml:172` registers `nine://`
   for the shared target — so a `nine://daily` open on the Mac is silently
   dropped. A prerequisite for routing anything, and a bug on its own.
2. **`CKContainer.init` traps a locally-built Mac binary.** The guard is
   `ubiquityIdentityToken != nil`, which is true on an iCloud-signed-in host
   whether or not the binary carries the CloudKit entitlement. Until this is
   fixed the Mac half of PRD-33 cannot be driven at all (PRD-20's standing gap,
   re-quoted by PRD-31). Fixed by asking the code signature for the entitlement
   instead of asking the OS for an account.
3. **A real menu bar**: a new Board menu (why / hint / auto-notes / pencil /
   erase / next empty), Game gains Archive and Technique School, Window gains the
   two new windows, View gains the menu-bar extra toggle. Routed through the
   existing `NineFocusActions` + `macShow*` pattern rather than a new mechanism.
4. **`MenuBarExtra` mini board**, `.window` style, behind a pref that is **off by
   default** — a permanent glyph in the menu bar is the idle-pixel test's exact
   subject. It shows the fingerprint and two rows. It is deliberately *not*
   playable: a 200pt board in a popover is a worse rose than the window, and it
   would be a second input concept against a budget of one.
5. **Per-puzzle window restoration**: `@SceneStorage` remembers which board the
   window was showing, so relaunch returns you to that puzzle and not merely to
   the most recent one. The archive gets a `Window(id:)` (it is `#if os(iOS)` today
   and does not compile for Mac at all) and Boards is promoted from overlay to
   window — "the Mac's answer to a second pane is a window", which is the sentence
   PRD-26 and PRD-31 both deferred to here. N live boards in N windows is refused:
   `AppModel` owns one `game`, one undo stack, one timer hold set and one autosave,
   and a second live board forks all four.
6. **⌥-click why already works**; what it lacks is iOS's spoken announcement.

---

## 3. The input-concept budget: this release spends zero

Every surface here is either an output surface (Live Activity, Dynamic Island,
StandBy, menu-bar extra), an invocation (App Shortcuts, Action button, menu items,
`⌘`-chords over `BoardKeys`' existing table), or configuration (Focus filters,
widget configuration). The widget's medium family extends PRD-3's existing
tap-cell/tap-digit grammar to a second size; it does not invent one. The menu-bar
board is explicitly not playable so that it stays on this side of the line.

## 4. Order of work, with the gate after each

Golden corpus (`swift test --filter GoldenCorpus`) after every commit — the Engine
is not touched here, so a mismatch would mean something went badly wrong, which is
exactly why it is worth the seconds.

1. Shared substrate: `QuietPresence.swift`, the appearance channel, `nine.focus`
   — plus their tests. Gate: `swift test`.
2. PRD-30 iOS: activity attributes, the widget-side `ActivityConfiguration`,
   `PresenceBridge`, `NSSupportsLiveActivities`, the pref. Gate: three platform
   builds + a driven simulator.
3. PRD-30 StandBy + widget palette. Gate: driven, photographed.
4. PRD-33 intents + `AppShortcuts.xcstrings` + focus filter. Gate: `swift test`,
   Shortcuts app, Settings ▸ Focus.
5. PRD-33 widget growth + configuration migration. Gate: old build → new build
   with a placed widget.
6. PRD-33 Mac: the CloudKit trap first (nothing else is driveable until it is),
   then URL routing, menus, `MenuBarExtra`, windows, restoration.
7. Strings: `EnglishPhrases` + `COMMENTS` + `--build-catalog` + nine machine
   drafts, marked `needs_review`.
8. `ax-snapshot.py`, `contrast-harness.py --quick`, `loc-harness.py`, then
   PRD-30.md, PRD-33.md, DEVIATIONS.md, PROGRAM-2.0.md status.
