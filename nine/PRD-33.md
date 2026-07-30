# PRD-33 — Nine, Everywhere You Ask

**Status:** Implemented · **Thread:** `nine/` · **Wave:** 2 ("Deeper")
**One-liner:** Nine answers from Spotlight, from Siri, from the Action button and
from a real Mac menu bar — and a Focus filter can make it go quiet without
turning anything off.

> This file did not exist when the work started; `PROGRAM-2.0.md:100` was the whole
> spec, the same way it was for PRD-25, PRD-26 and PRD-31. It is the forward
> document now. What actually happened — including the item that turned out to be
> unbuildable and the two that hung the app — is in the PRD-33 section of
> [DEVIATIONS.md](DEVIATIONS.md).

**Rejected by the plan and still rejected: Siri voice solving.** Slower than the
rose = demo-ware. Nothing in `NineIntents.swift` takes a cell, a digit or a move.

## 1. Four App Shortcuts

| Intent | Opens app | Does |
|---|---|---|
| `StartTodaysDailyIntent` | yes | `openToday()` — the same door the widget's deep link uses |
| `ContinueBoardIntent` | yes | resumes `library.mostRecentInProgress`, daily or free |
| `HowsMyStreakIntent` | **no** | returns a spoken answer |
| `StartABoardIntent(band:)` | yes | a fresh board at any of the six bands |

Four rather than eight because the last one is parameterised: one phrase template
with a `NineBand: AppEnum` covers every band, and `IntentCatalogTests` fails the day
`Difficulty` gains a case that `NineBand` does not.

**The streak intent is the one that does not open the app**, and that is its whole
point: a question you can ask without losing the screen you were looking at. It
gives three answers and none of them is a reproach. A zero streak says *the board
is waiting* — it never says what was lost, because that is PRD-13's entire
argument. A streak standing on the grace bridge reads exactly like one that is not:
`displayedStreak` already folds the bridge in, and surfacing the difference here
would turn the shield into a warning.

### 1.1 App Intents cannot use the app's string seam

Every user-facing string in an intent is a `LocalizedStringResource` **literal**,
keyed into its own `Intents` catalog table. `Strings.resource(_:)` does not compile
there:

```
error: 'LocalizedStringResource' must be initialized with a call to its
       initializer or a string literal
error: At least one halting error produced during export. No AppIntents metadata
       have been exported and this target is not usable with AppIntents until
       errors are resolved.
```

`appintentsmetadataprocessor` is a **static extractor**: it reads the source for the
strings the system will show, without running anything, so a value produced by a
function call is no value at all. There is no runtime lookup available at any price.

The dangerous part is that its error is **not fatal to the Swift compile**. Written
a little differently the build succeeds and ships an app with no Shortcuts entries
at all — the same family as PRD-16's alternate icons, where three green platform
builds emitted no `CFBundleAlternateIcons`.

So there are two hand-authored catalogs, and a test rather than `scripts/strings.py`
polices them (that script *generates* `Localizable.xcstrings` from
`EnglishPhrases.table`, and `--audit` deletes rows no accessor reaches):

- `Sources/Shortcuts/Intents.xcstrings` — 35 dotted keys × 10 locales. Listed by
  both bundles that declare intents, for the reason `project.yml` gives for listing
  `Sources/Strings` three times.
- `Sources/App/AppShortcuts.xcstrings` — the 9 spoken phrases, keyed by their
  English sentences with `${applicationName}` and `${band}` placeholders. That
  schema belongs to a build phase, not to us: `appshortcutstringsprocessor` fails
  the build with "Invalid Utterance" if any locale drops `${applicationName}`,
  which was falsified by hand.

`IntentCatalogTests` applies the four rules `CatalogTests` applies to the big
catalog — bijection with the source, every launch locale present, every draft
`needs_review`, coined band names left untranslated — and was itself falsified
against three perturbations.

## 2. Focus filters — the only thing Nine has to filter is itself

`QuietShelfFilter` has two switches, and `FocusFilterAppContext` stays at its
default because Nine sends no notifications and has no accounts. There is nothing
to silence; the filter's whole job is to turn down the app's own pull.

- **Hide the streak** → no `StreakChip` on the shelf, on the Mac, in the in-play
  ambient slot, or in the widgets. The Lock Screen streak accessory — which is
  *nothing but* a streak — falls back to the board's glyph rather than to an empty
  slot, because an empty Lock Screen widget reads as one that failed to load.
- **Hide today's progress** → the Today card keeps its constellation and loses its
  percentage. The fingerprint says "there is a board here" without saying how much
  you owe it.

Two switches rather than one because they answer different questions: hiding the
streak removes what makes a missed day feel like a cost, hiding the daily removes
what makes an unstarted board feel like a task, and a player who wants one often
does not want both.

**The widget goes quiet in the same breath**, through two additive optionals on
`WidgetSnapshot` and a `reloadDigest` that folds them in. A filter that calmed the
app while a widget two inches away kept counting would not be a filter; it would be
a setting with a bug. Under the filter the small widget renders the *same view the
StandBy face does* — "Focus that adds calm" and "a nightstand glass object" turn out
to want exactly the same thing, which is the board with no numbers on it.

State lives in `nine.focus`, a sibling blob, **local and never cloud-synced**: it is
machine state the system writes rather than a preference the player set, and a
Focus is a property of the device in front of you — an iPhone entering Work Focus
must not quiet an Apple TV in another room.

## 3. The widget grows a medium family, and a configuration

`NineBoardWidget` supports `.systemMedium` beside `.systemLarge`: board on one side,
a 3×3 digit pad on the other, both interactive. A medium tile is about half as tall
as it is wide, so the large family's board-over-strip stack would leave a ~60pt
board with 7pt cells — the same reasoning `DraftingTable` applies to an iPad, that
the composition follows the shape of what you were handed.

**On the "three moves" framing.** PROGRAM-2.0 writes this as a systemMedium *"three
moves" mode*, and a literal cap of three was refused. A widget that silently stops
accepting taps after the third is input that breaks with no explanation: it fails
the first-flick test outright, and to anyone who has met one it reads as a paywall
— which the covenant forbids the *shape* of as well as the substance. What "three
moves" actually asserts is a claim about **scale**, and the honest way to say that
is a surface small enough to make it obvious with the app one tap away, not a
counter the player cannot see.

`StaticConfiguration` becomes `AppIntentConfiguration`. The one parameter that is
real today is **which side the digit pad sits on** — which is *handedness*, the
thing DEVIATIONS recorded as deferred at the end of PRD-31 because "a handedness
row is a settings row and the covenant makes those expensive". A widget
configuration is not a settings row: it is per placed widget, edited in the
system's own sheet, and costs the app no chrome. PRD-24's channel parameter slots
into the same intent, which is the other half of why this conversion is worth doing
now rather than when Channels ship.

## 4. Journaling Suggestions cannot be built

There is no donation API. `JournalingSuggestions.swiftinterface` is 350 lines and
entirely a *consumer* surface — `JournalingSuggestionsPicker` plus fifteen closed
system asset types (Workout, Contact, Location, Song, Podcast, Photo, Video,
LivePhoto, MotionActivity, StateOfMind, Reflection, EventPoster…). There is no
`donate`, no provider protocol, and no symbol named `JournalingSuggestion` anywhere
else in the SDK. A sudoku solve cannot become a suggestion.

The one path that would technically work is examined and refused: **HealthKit
`HKStateOfMind`** *is* a journaling-suggestion asset type, so an app that logs a
mood does produce a suggestion. Taking it would mean a HealthKit entitlement and
capability (the trap that has fired three times), a permission prompt, and asking a
player how they feel about a sudoku.

The product intent — "the completed daily as a private reflective moment" — is
already shipped as PRD-26's debrief, which is a pull-up you have to ask for.

## 5. The Mac

### 5.1 First, the defect that made the rest driveable

`CKContainer.init` **traps** — not throws — on a binary that has an iCloud account
available but no CloudKit entitlement, and `setUpCloudSyncIfAvailable` guarded on
`FileManager.default.ubiquityIdentityToken != nil`, which asks the *operating
system* a question about the *binary*. Recorded as a standing gap since PRD-20 and
re-quoted by PRD-31: a locally-built Nine could not launch on macOS at all.

Fixed by asking the code signature instead, through `SecTask` — macOS only, which is
both where the API is and where the trap is. Proven both ways: reverting the guard
reproduces `EXC_BREAKPOINT` in `CKContainer.__allocating_init(identifier:)` ←
`LibraryCloudStore.init()` ← `setUpCloudSyncIfAvailable()`, and restoring it launches.

### 5.2 A real menu bar

A new **Board** menu, because Game is about *which* board and this is about what you
do to one: Why Must This Be…? (⇧⌘Y), Show a Hint (⇧⌘H), Pencil (⇧⌘P), Auto Notes
(⇧⌘A), Erase (⌘⌫), Next/Previous Empty Cell (⌥⌘→/←). Every row routes through
`NineFocusActions`, widened from the one closure it has carried since PRD-4, so all
of them grey out on the shelf for free.

Two of those rows are the Mac's **first** coach surfaces of their kind:

- **⌥-click "why" already worked** (PRD-25, `MacUI.swift`). What it lacked was iOS's
  spoken announcement, which is the half that was genuinely missing rather than
  merely undiscoverable — and a menu row with a shortcut printed beside it, because
  a pointer idiom with a modifier has no affordance anywhere.
- **The hint card had never reached the Mac at all.** `CoachCard.swift` was
  `#if os(iOS)`. No lightbulb button: the sixth control the touch bar has would be a
  fifth button here, and the covenant forbids one. A menu row costs the board no
  pixels.

Game gains Continue (⌘R) and two windows. View gains the menu-bar toggle. Help
gains the school.

### 5.3 The Mac's answer to a second pane is a window

The sentence PRD-26 and PRD-31 both deferred to this PRD, delivered:

- **Archive** (⌥⌘A) as a `Window`. It was `#if os(iOS)` and did not compile for the
  Mac at all; widening the fence was the entire cost, because `ArchiveCalendar`
  already owned every date and every word from `Sources/Shared`. A calendar is the
  case that proves the rule — you consult it *while* looking at a board, and a
  sheet would cover the thing you are deciding about.
- **Technique School** (⇧⌘E) as a `Window`. It has compiled for macOS since PRD-25
  and nothing had ever presented it: the cheapest patch in the repo.
- **Per-puzzle window restoration.** `resumeOnLaunch` already returns you to
  `mostRecentInProgress`, which is not the same claim: open an older board from the
  Boards sheet, quit, and you come back to a different puzzle. The window now
  remembers which board it had, falling back when that board has since been solved,
  archived, pruned or lost to a cloud merge.

**N live boards in N windows is refused.** `AppModel` owns one `game`, one undo
stack, one timer hold set and one autosave, and a second live board forks all four.

### 5.4 The menu-bar extra

Off by default, from the View menu. A Live Activity exists because the player
started a board and left; a menu-bar glyph is on screen from login, in every app,
forever, whether or not Nine is running — the idle-pixel test's most literal
subject.

It shows the board's constellation, one status line and two doors (Today's Puzzle,
Continue). **It is deliberately not playable**: a rose in a 260pt popover would have
petals under the minimum target size and nowhere for a flick to travel, and it would
be a second input concept against a budget this release has otherwise spent nothing
of.

The status line carries no streak. The menu bar is the surface a player sees most
often without choosing to, which makes it the closest thing to nagging this app
could build.

## 6. This release spends zero new input concepts

Every surface here is an output surface (menu-bar extra), an invocation (App
Shortcuts, the Action button, menu items over `BoardKeys`' existing table), or
configuration (Focus filters, widget configuration). The widget's medium family
extends PRD-3's existing tap-cell/tap-digit grammar to a second size rather than
inventing one, and the menu-bar board is explicitly not playable so that it stays on
this side of the line.

## 7. What was deliberately not done

Recorded with reasons in DEVIATIONS; the headline four:

- **No Siri phrase has ever been spoken and no Action button pressed.** The
  metadata is verified from the built artifact — five intents and four shortcuts in
  `Metadata.appintents`, with the right identifiers and short-title keys — but a
  microphone and an iPhone 15 Pro are hardware.
- **No Focus has ever activated.** `QuietShelfFilter` extracts with
  `com.apple.link.systemProtocol.FocusConfiguration` in the Release artifact and the
  filtered rendering is exercised by construction, but Settings ▸ Focus needs a
  booted simulator that this host could not spare the memory for.
- **The static→intent widget migration is unverified on a device.** The plan was to
  place the widget on the old build, install the new one and look.
- **No Mac first run, no Mac stats drawer, no Mac debrief.** The first two are
  PRD-34's and PRD-9's; the third is PRD-26's shipped decision that a pull-up is a
  touch gesture, and geometry is not a reason to re-litigate it.
