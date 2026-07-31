# PRD-29 — The Table

**Status:** Approved for implementation · **Thread:** `nine/` · **Wave:** 3 ("Together")
**One-liner:** Twenty people, one week, ranked by how many days you showed up
first and how fast you were second — no cohort to be relegated from, no banner
when anything happens, and a Bool you have to turn on yourself.

> This file did not exist when the work started; `PROGRAM-2.0.md:97` was the
> whole spec, the same way it was for PRD-25, PRD-26, PRD-27, PRD-28, PRD-30 and
> PRD-31. It is the forward document now. What actually happened, including the
> things that turned out to be false, belongs in the PRD-29 section of
> [DEVIATIONS.md](DEVIATIONS.md).

## 1. The thesis, in one paragraph

The three "Together, Quietly" features are each cheap for a different reason.
PRD-27 needed no network. PRD-28 needed no server, because the board is a pure
function of a seed and the hardest problem in multiplayer could be deleted
rather than solved. **The Table needs no server because Game Center already is
one** — but only if the product is expressed in the shape Game Center can
actually hold. That shape is a *rank*, not a *pod*, and §2 is the whole design
consequence of taking that seriously instead of working around it.

The strategic point, one turn on from PRD-28's: the input covenant is
transport-agnostic and now also **audience-agnostic**. A board played for a
table is played with exactly the same rose, on exactly the same board view,
through exactly the same four buttons, and nothing about the game screen knows a
table exists. If that stops being true, the feature is wrong.

## 2. Game Center cannot partition, and that is the feature

The program plan says "opt-in 20-person weekly tables". A league of that shape
normally needs an authority: something that assigns you to table 47, remembers
you were there, and moves you when the week ends. GameKit has no such API and
never has. What it has is:

```swift
// GKLeaderboard, .recurring, weekly occurrence
func loadEntries(for players: [GKPlayer]) async throws
    -> (GKLeaderboard.Entry?, [GKLeaderboard.Entry])
func loadEntries(for playerScope: GKLeaderboard.PlayerScope,
                 timeScope: GKLeaderboard.TimeScope,
                 range: NSRange) async throws
    -> (GKLeaderboard.Entry?, [GKLeaderboard.Entry], Int)
```

`range` is a range of **absolute rank positions** — seats 1…20 of the global
board — and the first tuple element is always the local player's own entry, with
its own `rank`. So the twenty people around you are two loads: one that costs
nothing but tells you your rank, and one that asks for the twenty seats centred
on it.

> **A table is a window on the recurring board, not a cohort in it.**

Everything the covenant wants falls out of that, in the strong form where it is a
property of the design rather than a rule some view obeys:

- **There is no Table 3 and no Table 4, so there is nothing to be relegated
  from.** "No demotion shame" is not a promise the UI keeps. It is a sentence
  that cannot be spelled, because the noun it needs does not exist.
- **Nothing anywhere stores a previous seat.** A delta needs two observations and
  Nine keeps one. `nine.table` is a single `Bool`, and that is the entire new
  persisted state in this PRD — so "you dropped four places" is not a message we
  decided not to send, it is a message no code path could construct.
- **The window is always full and always centred.** A player in seat 3 of the
  world sees seats 1…20; a player in seat 900,000 sees 899,990…900,009. Nobody is
  ever shown an empty table, and nobody is ever shown the bottom of one.

CloudKit public-database pods were the plan's fallback "if GC granularity can't
express tables". They are not needed and are therefore **not built**: a public
database is a schema deploy, a quota, a moderation surface and an availability
question, and the window above is a strictly smaller thing that does the job.

## 3. The score is a lexicographic pair packed into one integer

A leaderboard carries one `Int64`. "Completion-consistency first, time second" is
two keys. The whole ranking rule is therefore one piece of arithmetic, in
`Sources/Shared/DailyTable.swift`, pure and Linux-testable:

```swift
public static let timeSpan = 1_000_000          // seconds; ~11.6 days

score = days * timeSpan + (timeSpan - clamp(seconds, 1, timeSpan))
```

with `days` the number of that week's dailies you completed (0…7) and `seconds`
their total. Sorted **descending**, more days always beats fewer days by a margin
no amount of speed can close, and inside a day count the faster week wins.

Five properties, each load-bearing:

1. **It is invertible.** `days = score / timeSpan`,
   `seconds = timeSpan - (score % timeSpan)`. Every row the table draws — the
   seven-mark week glyph *and* the time — is read straight off the leaderboard
   entry. There is no second fetch and no side channel.
2. **`context` stays 0.** `GKLeaderboard.Entry.context` is a real 64-bit payload
   and riding the day count in it is the obvious move. It is refused for
   `Strings.channel(_:)`'s reason: a second source for a number the score already
   determines is a second thing that can disagree, and the one that disagrees
   will be the one drawn.
3. **The clamp's lower bound is 1, not 0.** At `seconds == 0` the second term
   equals `timeSpan` and the whole score equals `(days + 1) * timeSpan` — one
   full day of consistency, manufactured by arithmetic. Zero is reachable: every
   untimed solve records `seconds == 0` (widget solves, watch solves, and every
   board that arrived over CloudKit with its log stripped). `clamp(…, 1, …)` keeps
   the remainder in `0..<timeSpan` and the two fields disjoint, forever.
4. **Total seconds, not average, and they induce the same order.** Time only ever
   breaks a tie, a tie is by definition an equal day count, and an equal day count
   is an equal denominator — so the two orderings are identical and the cheaper
   one is correct. Total is also the one that needs no division and no
   nil-when-empty case.
5. **A week's score only ever increases.** That is what makes "keep the best score
   in the occurrence" the right App Store Connect configuration, and it is why a
   dropped submission costs nothing: the next solve resubmits the whole week.

### 3.1 Which solves count

Classic dailies only, one per calendar day, and **the first solve of that day**.

- Classic only, because `nine.channels` exists precisely so a killer streak
  cannot dilute a classic one (PRD-24), and a league that counted both would undo
  that at the surface. The per-channel boards already exist for channels.
- Dailies only, because "consistency" means showing up on the day, and free
  boards are unbounded — a league scored on volume is a league that rewards
  grinding.
- The **first** solve of a day rather than the fastest, because a daily can be
  replayed (`BoardLibrary.adoptDaily` reuses the day's slot) and "fastest" pays
  for repetition. First is the attempt that counted.

None of this is new persisted state. The whole standing is derived from
`nine.history`, which has held every solve's date, `isDaily` and `seconds` since
1.0.

## 4. The week starts on Monday, and it is not the player's calendar

```swift
weekStart(containing: ordinal) = ordinal - ((ordinal % 7) + 7) % 7
```

Day ordinal 0 is 2001-01-01, which was a Monday, so this is exact with no
`Calendar`, no `Locale`, no `TimeZone` and no branch.

**`Calendar.firstWeekday` is deliberately not consulted**, and this is the one
place the player's own settings are overruled on purpose. A US player whose week
starts on Sunday and a German player whose week starts on Monday, counting
against one leaderboard occurrence, are two people playing different games and
neither of them can tell. The week is a property of the league, not of the
device.

The day *boundary* is still local midnight, because `DailySeed.dayOrdinal` is
what defines a daily and a league about dailies has to agree with them.

The App Store Connect occurrence must therefore be configured to a 7-day duration
starting at a Monday. Where GameKit reports the occurrence's own `startDate` and
`duration`, they are preferred over the local computation — asking is always
better than assuming, and this is a case where the answer exists.

## 5. Anti-cheat is a re-simulation, and it says what it cannot do

`Sources/Engine/ReplayAudit.swift`, pure, Linux-clean, **no new solving code** —
it re-derives the proven grid with the shipped `BacktrackSolver` and re-walks the
path with the shipped `ReplayWalk`, which is the same rule PRD-26's classifier
kept for the same reason.

| finding | what it means | what it actually catches |
|---|---|---|
| `unreadable` | the packed blob does not unpack | a truncated or foreign record |
| `notProvable` | the puzzle has no unique solution | a fabricated grid |
| `tamperedGiven` | a move placed on or erased a clue | a hand-built log |
| `unfinished` | the walked board ≠ the proven solution | a log that does not solve its board |
| `nonMonotoneTiming` | a stamp goes backwards | a hand-built log, only |
| `claimShorterThanLog` | `seconds` < the log's own last stamp | a wrong clock, a doctored time |

Two honesty clauses, both of which belong in the spec rather than in a code
comment:

- **Every check must be shown to be able to fire.** PRD-24's `thermoBand` composed
  200/200 with two knobs that could never reject anything, and the lesson was that
  a constraint nobody falsified is a decision in costume. Each finding above gets
  a test that constructs the input that produces it. `nonMonotoneTiming` is the
  interesting one: `SolveReplay`'s packed format stores **unsigned deltas**, so a
  replay that came through `unpack` is monotone by construction and the check can
  never fire on one. It is kept, because the audit's argument is about a
  `[LoggedMove]` and one can arrive from somewhere else — but the fact that it is
  structurally satisfied on today's only caller is stated here, and the test that
  fires it builds the log directly.
- **This runs on the player's own device against the player's own replay.** It is
  no defence at all against a patched binary, and there is no server to move it
  to; that was the premise. What it is worth is everything else — a corrupted
  vault, a clock that jumped, a board that arrived from iCloud with its log
  stripped, a future build's wire read by an older one — which is the set of ways
  a wrong number arrives when nobody is attacking. Trust-but-verify, and the
  emphasis is on the first word. A zen game that shipped a client-side
  anti-cheat and called it anti-cheat would be lying twice.

The audit is a **gate on submission, not a judgement of a person.** A dirty
verdict means this device does not submit that week; nothing is shown, nothing is
logged at the player, and there is no path from a finding to a sentence.

## 6. The surface

One section in the History sheet, between the Game Center row and Recent Solves,
in `StatsViews.swift`'s vocabulary — `Canvas`/`Path`, no Swift Charts, themed
through `ThemeTones`, scaled by the sheet's `s` factor. **iPhone, iPad, Mac and
Apple TV**, because the History sheet is already all four and the drawing is
already `#if os(iOS) || os(macOS) || os(tvOS)`; nothing here is a gesture, which
is what made PRD-24's and PRD-28's surfaces iOS-only.

Twenty rows. Each is a seven-mark week glyph — the heat grid's own mark, one row
of it — then a display name, then the week's time. Your row wears the accent and
is the only row that ever says *You*.

What is not on it, each refused by name:

- **No rank numbers.** The order is the rank; printing it invites arithmetic.
- **No deltas, no arrows, no "moved up", no "moved down".** §2: nothing is stored
  that could compute one.
- **No podium, no medals, no colour above seat 3, no highlight on the leader.**
- **No avatars.** `GKPlayer` will load one; it is an image of a stranger on a
  surface about your own week.
- **No total-player count, and no "top 4%".** `loadEntries` returns it. Drawing it
  turns a window back into a position in a hierarchy, which is the exact thing §2
  removed.

### 6.1 The zero-states, all three of them

PRD-34's rule is one designed zero-state per surface, and this surface has three
distinguishable nothings that must not collapse into one:

1. **Opted out** (the default): one sentence and the control that changes it.
2. **Opted in, not signed in to Game Center:** the same sentence the Game Center
   row above already uses. Two rows disagreeing about whether you are signed in
   is the Mac/iPhone caption bug PRD-20 found.
3. **Opted in, signed in, no table yet** — a fresh week, or the App Store Connect
   record not deployed: honest absence. One sentence saying there is nothing,
   and the control to leave; **no empty seats are drawn and there is no
   spinner**. Twenty grey rows waiting to fill would be fake data, which the
   craft charter rules out by name.

### 6.2 What VoiceOver hears

The section is a container; each seat is one child, labelled with the name, the
day count and the time, and your own seat names itself. The week glyph is a
`Canvas` of marks with no text near it — PRD-24's "structurally perfect and
semantically silent" trap in its exact original form — so the day count is in the
**label**, not the hint, because hints can be turned off.

## 7. Opt-in, and one Bool

`CouchStored(wrappedValue: false, "nine.table", cloudSynced: true)`.

Off by default. Cloud-synced beside `nine.streak` and `nine.graceSeen`, and a
bare `Bool` for `nine.graceSeen`'s stated reason: the Bool *is* the whole state,
so a struct would add a tolerant decode with nothing to be tolerant about.

Turning it off stops this device submitting. It **cannot** withdraw what Game
Center already holds — there is no delete-my-score API, and the occurrence ages
out on its own — and the row says so plainly rather than implying an erasure it
cannot perform.

## 8. The input-concept budget: this release spends zero

The rose is untouched. There is no fifth control button. No gesture is added
anywhere. The table is a section in a sheet that already scrolls, and the opt-in
is a row in a settings list.

**It never notifies**, and that is sealed rather than promised:
`UNUserNotificationCenter`, `UNNotificationRequest`, `GKNotificationBanner` and
`showsCompletionBanner` are all forbidden on every file this PRD touches. The
last of those is the one that matters — `GameCenter.progress(_:fraction:)` sets
`showsCompletionBanner = true` on achievements today, so the API is already in
the file and one line away from the table.

## 9. What this PRD explicitly does not do

- **No CloudKit public database.** §2 — the window makes it unnecessary, and it
  costs a schema deploy and a moderation surface.
- **No per-channel tables.** Classic dailies only (§3.1). The per-channel
  leaderboards from PRD-24 already exist and still have no App Store Connect
  records.
- **No friends table, no private table, no invite.** `GKLeaderboard.PlayerScope`
  has `.friendsOnly` and it would work; a second table is a second thing to
  compare yourself against, and the point of one window is that there is one.
- **No history.** No past weeks, no "your best table", no season. §2's Bool is the
  whole persisted footprint, and this is the clause that keeps it that way.
- **No notification, no reminder, no "the week ends tomorrow", no "you're about to
  be passed".** The covenant, unchanged, and now sealed.
- **No watch surface.** The watch has no History sheet.
- **No server-side audit.** §5, said out loud.

## 10. Verification

Green gates, per PRD-7 §3 rule 3 and EXECUTING-A-PRD §5:

- `swift test` — §3, §4 and §5 are pure and live in `Sources/Shared` and
  `Sources/Engine`, tested with no simulator, no session and no Game Center, the
  same shape as `Parlor`, `RoseLens`, `DraftingTable` and `QuietPresence`.
- Every `ReplayAudit` finding falsified — a constructed input that produces it —
  and the one that cannot fire through the packed format named as such.
- Two seals: the source of every table surface carries no notification API and no
  demotion vocabulary, and no `table.*` catalog key does either.
- Golden corpus **56/56** and variant corpus **9/9** after every commit.
- iOS + tvOS + macOS builds, plus a Release archive.
- `python3 scripts/ax-snapshot.py` — the six existing baselines match with **no
  re-record**, and the lane gains a seventh. The History sheet has never had one,
  and PRD-24's rule applies in its exact original form: a baseline that cannot
  see a surface will not catch it regressing.
- `python3 scripts/strings.py --audit` — new keys with translator comments, zero
  new bare-literal offences, nine machine drafts per key, every one
  `needs_review`.

And then it is **driven**, with this PRD's own honest caveat: the App Store
Connect recurring-leaderboard record does not exist, so `loadEntries` returns
nothing and a real table has never been on a screen. Everything below the GameKit
call is pure and tested; the drawing is driven against a constructed twenty-seat
standing behind a DEBUG launch argument, sealed out of Release the way PRD-28's
loopback transport is — which is the same position PRD-31's Pencil recognizer and
PRD-28's parlor shipped in, and named the same way.
