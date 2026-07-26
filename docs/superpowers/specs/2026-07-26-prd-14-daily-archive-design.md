# PRD-14 — Daily archive: design

**Date:** 2026-07-26 · **Thread:** `nine/` · **Scope:** one PR
**Spec:** [nine/PRD-14.md](../../../nine/PRD-14.md) · **Rules:** [nine/docs/EXECUTING-A-PRD.md](../../../nine/docs/EXECUTING-A-PRD.md)

A month grid of past dailies — solved days checked, today glowing, every past
day tappable — regenerated from `DailySeed` rather than stored. What follows is
what PRD-14 §4 does not say and a reader would otherwise have to rediscover.

---

## 1. The finding that changes the plan

PRD-14 §2 sources the checkmarks from `library.dailyEntry(day:)` "+ solve
records". **Neither can hold them.**

- `BoardLibrary.prune()` caps solved+archived entries at **20**
  (`playedCap`), evicting oldest-`updatedAt` first. Work through 21 archive days
  and the earliest checkmarks vanish from the one view the feature exists to
  show. Not a rare edge: "hundreds of hours of content" is PRD-14's own §1 pitch.
- `SolveRecord` carries the **solve** date, never the puzzle's day ordinal —
  deliberately, since PRD-14 §2 sets `date = now` so the PRD-9 heat grid stays
  honest. So history cannot answer "was day N's daily solved?" even before its
  own 200-record cap bites.
- `StreakState` holds one `lastCompletedDay`, not a set.

So the archive needs a durable ledger of solved daily day-ordinals. That is the
only new persisted state in this PR, and per EXECUTING-A-PRD §2 it takes its own
`CouchStored` blob rather than a field on `LibraryEntry`.

## 2. The second finding: the streak guard is load-bearing

PRD-14 §2 calls skipping `recordCompletion` for past days "defense in depth".
It is not — it is the fix for a real bug.

`AppModel.finishSolve` calls `streak.recordCompletion(day:)` for **every**
`.daily(day:)` board. `recordCompletion`'s `guard day > last` only protects a
player who already has a streak. On a fresh install `lastCompletedDay == nil`,
so the guard never runs:

```
fresh install → open the archive → solve yesterday
  → lastCompletedDay = yesterday, current = 1
  → displayedStreak(today:) returns 1
```

A one-day streak the player never earned, on a screen whose whole point is that
the number is true. The guard moves into the Engine so it is testable:

```swift
/// Record a daily completion, ignoring any day earlier than `today`.
/// An archive solve must never rewrite streak state (PRD-14 §2).
public mutating func recordCompletion(day: Int, today: Int) {
    guard day >= today else { return }
    recordCompletion(day: day)
}
```

`AppModel` calls only this overload. The one-argument form stays for the tests
and callers that already pin its behaviour.

---

## 3. Components

Five units, each with one job.

| Unit | Where | Depends on | Job |
|---|---|---|---|
| `DailySeed.seed(forDayOrdinal:)` | Engine | — | ordinal → the same seed `seed(for: date)` gives |
| `StreakState.recordCompletion(day:today:)` | Engine | — | the past-day guard |
| `ArchiveLedger` | Shared | `RawJSON` | durable set of solved daily ordinals |
| `ArchiveCalendar` | Shared | — | month-grid math + day labels, pure |
| `ArchiveSheet` | App (iOS) | the above + `AppModel` | the grid |

Plus `AppModel.openArchiveDay(_:)`, the Today-card affordance and the in-game
chip in `TouchUI.swift`.

### 3.1 `DailySeed.seed(forDayOrdinal:)` — and why it is exact, not approximate

The two existing functions are asymmetric in a way that makes the inverse free:

- `seed(for: date)` hashes the **local** y/m/d.
- `dayOrdinal(for: date)` takes the same **local** y/m/d and reinterprets it as
  a **UTC** midnight, then divides by 86 400.

So the ordinal already *is* the local y/m/d, re-encoded. Reading it back in UTC
recovers exactly the components `seed(for:)` hashed — no calendar round-trip, no
timezone hazard:

```swift
public static func seed(forDayOrdinal ordinal: Int) -> UInt64 {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let date = Date(timeIntervalSinceReferenceDate: TimeInterval(ordinal) * 86_400)
    let c = utc.dateComponents([.year, .month, .day], from: date)
    // …identical hash to seed(for:) from here
}
```

The contract is a test, not a comment:
`seed(forDayOrdinal: dayOrdinal(for: d)) == seed(for: d)` for a spread of dates
across several timezones. Nothing in `Generator.swift`'s existing surface moves,
so the golden corpus cannot be touched by this — but it is run anyway, after the
engine commit, per EXECUTING-A-PRD §3.

### 3.2 `ArchiveLedger` — `nine.archive`, cloud-synced

Its own `CouchStored` blob (`cloudSynced: true`), in `Sources/Shared` beside
`CoachLedger` and `TipLedger`: pure Foundation, so it tests on Linux CI.

State: a sorted, deduplicated `[Int]` of day ordinals whose daily is solved.
Nothing else. Not a record — a set.

**Why its own blob and not a sibling key of `nine.history`.** `SolveHistory` is
an array of `SolveRecord` with a newest-first ordering contract, a 200-record
capacity prune and a quarantine; a set of ordinals shares none of that and would
have to be threaded past all of it. `nine.coach` set this exact precedent one PRD
ago. Cloud-synced because a checkmark is a property of the *player*, not of the
hand that held the phone — the same call `nine.streak` and `nine.history` made,
and the opposite of `nine.coach`'s hint counts.

**Why not local-only in `nine.library`.** EXECUTING-A-PRD §2's data-placement
rule puts streak/prefs/history/coach in KVS and the library in CloudKit. A
solved-day set is streak-shaped, not board-shaped.

**Size.** One `Int` per solved day, five digits plus a comma. Ten years of
unbroken daily play is ~3 650 ordinals ≈ **22 KB** against a 1 MB KVS budget
already carrying 200 history records. Range-compression was considered and
dropped as premature: it wins on the contiguous case and *loses* on the
alternating one, for real code and real tests. The number is recorded here so
whoever revisits it starts from a measurement.

**Decode covenant.** Tolerant throughout — a missing container, a `days` key
that is not an array, an element that is not a number — none of it throws, per
EXECUTING-A-PRD §2. Unknown top-level siblings are carried in `carriedTopLevel`
and re-emitted, the same shape `SolveHistory` and `BoardLibrary` already take.

### 3.3 `ArchiveCalendar` — pure grid math, and one real trap

Given a floor ordinal, today's ordinal and a `Calendar`, it produces: the list of
months the pager may reach, and for one month a 6×7 grid of optional ordinals
(leading and trailing blanks where the month does not reach). Plus the labels.

**The trap: an ordinal's canonical `Date` is a UTC midnight** (§3.1). Formatting
it in the player's local timezone shows the *previous* day at any negative UTC
offset — so "Archive · Jul 12" would read "Jul 11" for every player in the
Americas. Every formatter in this unit is pinned to UTC, and
`testDayLabelIsStableAcrossTimezones` pins it with a `GMT-8` calendar. This is
the highest-value test in the batch: the failure is silent, off by one, and
invisible to anyone developing in UTC+0.

**The floor is 2026-07-01**, the month Nine's first daily existed (first `nine/`
commit: 2026-07-11). `DailySeed` will happily generate a seed for 2019, but a day
before Nine shipped was never anybody's daily — offering it is content dressed as
history. PRD-14 §2's "launch month of the archive feature" and Nine's own launch
month are the same month today, so this reading costs nothing now and is the
defensible one in a year.

### 3.4 `AppModel.openArchiveDay(_:)`

Mirrors `openToday()` minus the widget ingestion and minus streak writes:

```swift
func openArchiveDay(_ day: Int) {
    guard day <= todayOrdinal else { return }       // future days are not offered
    if day == todayOrdinal { openToday(); return }  // one entry, no dupes (PRD-14 §5)
    if let entry = library.inProgressDaily(day: day) { startEntry(entry.id); return }
    compose(kind: .daily(day: day), seed: DailySeed.seed(forDayOrdinal: day), difficulty: .steady)
}
```

Three things fall out for free and are worth naming, because they are the reason
this is a small change rather than a large one:

- **Resume works already.** `library.inProgressDaily(day:)` is keyed on an
  arbitrary day; nothing in it assumes today. A half-finished Jul 12 is a
  partial like any other.
- **CloudKit sync works already.** The entry is `.daily(day: 12)`, an ordinary
  `LibraryEntry`, pushed by `persistProgress` through the PRD-8 path.
- **The widget cannot see it.** `WidgetBridge.publishDailyBoard` reads
  `library.inProgressDaily(day: today)`. An archive board is structurally
  invisible to the widget — no guard needed, and none added.

### 3.5 Where the checkmark is written

`finishSolve`, in the one place that already knows the day:

```swift
if case .daily(let day)? = kind {
    isDaily = true
    streak.recordCompletion(day: day, today: todayOrdinal)   // guarded (§2)
    archive.markSolved(day: day)                             // the durable check
}
```

Note it records for **every** daily solve, not only archive ones — a day solved
normally from the Today card must show a check in the grid too, or the grid lies
about the present while being right about the past.

**Backfill.** `AppModel.init` seeds the ledger, every launch, from what is still
knowable: `streak.lastCompletedDay`, plus every `.daily(day:)` entry with
`status == .solved`. Idempotent (it is a set insert), O(60), and self-healing —
a solved daily that arrives later from CloudKit gets its check on the next
launch. It cannot recover days already pruned before this build; nothing can, and
that is stated rather than papered over.

---

## 4. The surfaces

**Entry:** a calendar-glyph button inside the Today card, exactly the nested-
button pattern `continueCard`'s discard ✕ already uses. Opens a `GlassSheet`
alongside the shelf's existing History and Boards sheets — one at a time, per the
amended one-sheet rule (DEVIATIONS, 1.1).

**Grid:** iOS `GlassSheet` is `maxWidth: 380` with 22pt content padding, leaving
336pt. Seven 44pt cells with 2pt gaps is 320pt — the craft charter's 44pt floor
survives at the smallest width, which is what fixes the cell size rather than
taste.

Cell states: solved (checkmark), in progress (accent ring), untouched past
(plain), today (accent fill), future (muted, not tappable).

**In-game chip:** `GlassChip("Archive · Jul 12", systemImage: "calendar")` in the
slot `composingChip` occupies, shown when the board on screen is a `.daily(day:)`
with `day < todayOrdinal`. Mutually exclusive with the composing chip by
construction — a board cannot be both composing and on screen as an archive
board.

**Accessibility.** Every cell is a labelled button: "July 12, solved", "July 12,
not played", "July 26, today", "July 27" + `.isButton` dropped for future days.
`ax-snapshot.py` gains a sixth screen, `archive`; `home.txt` re-records because
the Today card gains a button. Both are deliberate re-records with a paper trail,
per EXECUTING-A-PRD §4.

---

## 5. Testing

Engine (`swift test`, Linux-safe):

- `seed(forDayOrdinal:)` ↔ `dayOrdinal(for:)` round-trip across dates and
  timezones; distinct days give distinct seeds.
- `recordCompletion(day:today:)`: a past day is a no-op on a fresh install
  (`displayedStreak` stays 0), a no-op mid-streak, and today still records.
- Golden corpus, after the engine commit — 56/56 or the change is wrong.

Shared:

- `ArchiveLedger`: insert/contains/sorted/deduped; tolerant decode of a missing
  container, a non-array `days`, a non-numeric element; `carriedTopLevel`
  round-trip.
- `ArchiveCalendar`: grid shape and leading blanks for a month starting on each
  weekday; floor and today clamping; **day labels stable under `GMT-8`**.

Driven, not merely green (EXECUTING-A-PRD §5): solve a past day in the simulator
and read `displayedStreak` before and after; reopen it and confirm the partial
resumes; open today from the grid and confirm one entry, not two; screenshot the
populated grid and the in-game chip.

---

## 6. Explicitly not in this PR

- **The PRD-9 heat-grid tap seam.** `HistorySheet.swift` is iOS + macOS + tvOS
  and the archive sheet is iOS-only, so wiring the tap means either a
  platform-gated tap in shared code or a sheet opening a sheet — against the
  one-secondary-surface rule. Documented instead, as PRD-14 §4.4 allows.
- **tvOS and macOS archives** (PRD-14 §3 non-goal).
- **Deleting `ArchiveDemo` / `-uxdemo.archive`** (PRD-14 §4.4): already gone.
  PRD-18 deleted the entire `-uxdemo` rig; `UXDemoScenes.swift` does not exist on
  `main`. Nothing to remove.
- **Per-day stats, calendar-app integration** (PRD-14 §3 non-goals).
