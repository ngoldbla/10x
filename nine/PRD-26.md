# PRD-26 — The Comet (replay + debrief)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one PR
**One-liner:** Every solve mints an immutable, packed record of how it actually
went. A comet retraces it — hesitations dwell, corrections run backwards — and a
debrief you have to *pull up* says what the board can prove about the hand that
played it. The same loop becomes the share card's body and the Apple TV's first
ambient surface.

Source of record: [PROGRAM-2.0.md](PROGRAM-2.0.md) §Pillar C. Execution rules:
[docs/EXECUTING-A-PRD.md](docs/EXECUTING-A-PRD.md). Covenant: [PRD-7](PRD-7.md).

---

## 1. Why

The move log has been append-only since 1.0 and logs **undo as an event rather
than popping it** (`Game.swift:46`), which was written down as "solve-replay
groundwork" and has never been spent. That one decision is the whole feature: a
log that pops its undos records a tidied path nobody walked. This one records the
path.

PRD-25 turned the *trace* into a teacher — why must this be a 7. This turns the
*log* into a mirror: not what the board demanded, but what you did about it. The
two are different data and answer different questions, and only the second one
knows you circled the same cell four times before you saw it.

## 2. The experience

### 2.1 The comet is never unbidden

The Afterglow owns T+0 to T+6.5 s after a solve and the completion chip appears
at T+2.4 s. The comet does not join them. It plays only inside a debrief the
player asked for, on a share card they chose to make, or on a TV nobody is
touching.

A replay that starts itself is a replay that has to be *stopped*, and the idle-
pixel test is the one this app has never failed.

### 2.2 The debrief is a pull-up

A 3 pt hairline grabber under the completion chip; drag up, or activate it, and
the debrief rises. It is the mirror image of PRD-34's stats-drawer grabber and
uses the opposite edge on purpose — the drawer pulls *down* from the top
(`TouchUI.swift:1094`), so the two gestures cannot be confused and cannot fire
together. They are also mutually exclusive once open, the same rule the coach
card and the drawer already hold (`TouchUI.swift:1088`).

The card carries, in order:

1. **The comet**, at board size, looping.
2. **What the board can prove.** Placements, corrections, notes — counts, never
   scores.
3. **The technique line**, when there is one: *"You found the X-Wing at move
   31."* This is the only sentence in the app that congratulates anybody, and it
   only appears when the analysis (§3.3) can name a technique above the easiest
   one available at that moment. On a board solved entirely by singles it is
   absent, and nothing takes its place.
4. **The two timing lines** — fastest region, longest-circled cell — **only when
   the log is timed.**

Nothing here is a percentage, a rating, a grade or a comparison against another
player. A debrief nobody opens is a debrief that never happened; the app does
not mention that it exists a second time.

### 2.3 Untimed logs replay, and say nothing about it

`at` is optional (§3.1), so every board solved before this ships — and every
board that reaches this device from iCloud, whose log `clearLocalHistory()`
emptied on the way out (`LibrarySync.swift:23`) — has no timing.

**The comet does not tell.** It plays the same 5 s loop at uniform cadence, and
there is deliberately no watermark, caption or dimming to mark it. The moves are
true; only their spacing is invented, and inventing the spacing is what a
uniform cadence honestly *is*.

**The debrief does tell, by omission.** Fastest region and longest-circled cell
are functions of `at` and nothing else. On an untimed log they are not
computable, so they are not printed — the card is simply shorter. It does not
apologise for them or explain them. This is the craft charter's "honest absence
over fake data", and it is the one place the two answers differ: a comet with
invented spacing is still a true drawing of the path, but "fastest region: box 4"
derived from a uniform cadence is a fabricated fact on a card the player may
believe.

### 2.4 One share chip, two payloads

PRD-12's chip does not become two chips. It carries the **5 s H.264 loop** when
the solve has a replay, and the **still PNG** when it does not.

The fallback is not defensive coding, it is three real paths that mint no log at
all: a widget solve (`BoardIntents.swift:75`), a watch solve
(`WatchModel.swift:286`), and any board solved on another device — CloudKit
carries the board, and `SyncedEntry` strips the log by design. Making the loop
unconditional would have deleted PRD-12's shipped behaviour on all three.

The card's chrome, margins and captions are untouched: `ShareCard` is generic
over its body at `ShareCardMetrics.bodySide` and the comet takes that 888 pt
square unchanged, which is what that seam was cut for.

### 2.5 tvOS gets an ambient surface

A **Replays** card on the shelf opens a full-screen loop that cycles your own
solved boards. The same view auto-engages after 90 s of no remote input on the
home shelf and leaves on any button.

This is the first thing Nine has ever drawn on a TV that nobody is playing, and
the constraint is the room, not the screen: no sound, no chrome, no text, no
progress bar, board-only, and it must pass the roommate test from the doorway.

## 3. Engine

### 3.1 `LoggedMove.at`

```swift
public let at: TimeInterval?   // seconds since this board's timer started
```

**Caller-passed, and the engine still never reads a clock.** `place`,
`togglePencil` and `erase` gain `elapsed: TimeInterval? = nil`; `AppModel` passes
`game.timer.elapsed(at: now)` from the same `Date` it already has in hand. The
label is `elapsed:` and not `at:` because `place(_ digit: Int, at cell: Int)`
spent `at:` on the cell in 1.0.

Defaulted to nil, so every call site that existed before this PRD is unchanged in
text as well as in meaning — the `autoNotes` precedent from PRD-11.

Optional is what makes it free. Swift's synthesized encoder spells an optional
property `encodeIfPresent`, so an untimed log's bytes do not move; decode is
`decodeIfPresent`. The mechanism is exactly `SolveStep.roles`/`chain`
(`LogicSolver.swift:176`), and like those it is verified by running the corpus
rather than by asserting it here.

### 3.2 `SolveReplay` is immutable

Its own file, `let` on every field, no mutating member and no setter. A replay is
a record of something that already happened; there is no correct reason to edit
one, so the type does not offer a way.

The move log packs to binary because 1.1's JSON spelling of one move is ~48
bytes and a long Nocturne runs past 400 moves:

```
header  : magic 'N9R'(3) · version(1) · flags(1) · moveCount(u16)
move    : byte0 = kind<<4 | digit ; byte1 = cell ; [byte2..3 = centiseconds]
```

Two bytes a move untimed, four timed — a 300-move solve is ~1.2 KB, inside
PROGRAM-2.0's 1–2 KB. The `timed` flag is on the *header*, not per move: a log is
timed or it is not, and a per-move flag would let one exist that is half of each.

Decode is total and returns nil rather than throwing, for `CouchStored`'s reason.

### 3.3 Replay analysis

**No new solving code.** The classifier walks a `CandidateState` forward with the
shipped `LogicSolver.nextStep(in:allowed:)` and `apply(_:to:)`
(`LogicSolver.swift:343,356`), asking at each placement what the solver would
have done from exactly that board.

| case | meaning |
|---|---|
| `.forced` | the easiest available step places this digit in this cell |
| `.found` | forced, but by a technique **above** the easiest available — the praise class, and the source of §2.2's one sentence |
| `.leap` | no allowed technique resolves this cell from here |
| `.slip` | contradicts the proven solution |

**`.leap`, not "guess".** PROGRAM-2.0 §Pillar C says guess, and the word is
wrong for the register: a raw value becomes the localization identity the moment
it ships (PRD-20's finding), so it is worth choosing once rather than renaming
against nine translations later. The covenant bans streak shaming; a leap is the
same sentence in a kinder mood, and the app never shows the count anyway.

The analysis has no opinion about whether any of these is better. `.found` earns
a sentence; `.leap` and `.slip` earn nothing, and are not summed, ranked or
displayed.

### 3.4 What the coach remembers

`CoachProgress.Met` gains `usedInSolve: Bool` — tolerant, `(try? …) ?? false`,
per that file's own rule.

It feeds the **existing** `hasMet`, so PRD-25's one line in the stats drawer
("seven of ten techniques met") becomes truer and **no new pixel appears
anywhere**. A technique you found on your own board is a technique you have met;
that it took a fourth reader of `CoachProgress` to notice is the argument for it,
not against.

`CoachProgress.swift`'s header names its readers exhaustively and warns it is
"the file most likely to grow gamification by accident". This PRD adds a writer,
not a reader, and the header is updated to say so.

## 4. Persistence

Per EXECUTING-A-PRD §2:

- **`ReplayVault` is its own top-level blob** (`nine.replays`), not a field on
  `LibraryEntry`. Field-level preservation was implemented, measured at 1515 ms
  against a 49 ms baseline, and reverted; this is that rule.
- **Pruned with the library**, `prune(to liveIDs:)`, modelled on
  `CoachLedger.swift:87`. A replay is about a board; when the board goes, the
  replay has nothing left to be about. This is the opposite call from
  `CoachProgress`, deliberately — that one is about the *person*, so it must
  outlive every board.
- **Local-only blob, CloudKit for the records.** A new record type
  `SolveReplay` in the **existing** `NineLibrary` zone.
  **No entitlement change, no `match` re-mint** — the trap in EXECUTING-A-PRD §6
  fires on capabilities, and a record type is schema. It *does* need a
  **CloudKit Production schema deploy before release**, which is human-owned and
  recorded in §6 alongside PRD-7 §5's gate.

## 5. Verification checklist

- [x] Golden corpus 56/56 **after every commit**.
- [x] `LoggedMove` with `at == nil` encodes byte-identically to 1.1's spelling —
      asserted against the literal bytes, not against a round trip.
- [x] A packed replay round-trips: pack → unpack → same moves, timed and untimed.
      300 timed moves is **1288 bytes**.
- [x] A truncated, over-long or garbage buffer decodes to nil, never throws —
      including a header that promises 65535 moves and carries one.
- [x] Analysis soak: a solver-order solve of a gentle, a sharp and a tempest
      board yields no `.slip` and no `.leap`; a deep board names a technique
      above the singles (`ReplayAnalysisTests`).
- [x] Replay of an untimed log produces a debrief with no timing lines and a
      comet of the same duration. Driven on a simulator, both ways.
- [x] The comet follows the **log** and never the grid
      (`theHeadFollowsTheLogAndNeverTheGrid`).
- [x] `ReplayVault` prunes exactly with the library and stays under its cap; one
      unreadable record costs one record.
- [x] Three platform builds + a Release archive.
- [x] `ax-snapshot.py`: it **found a defect on its first run** (§6) and is clean
      after the fix; no baseline re-recorded.
- [x] Driven on a simulator — iOS debrief, share loop (H.264 1080×1350, 5.000 s,
      705 KB), tvOS ambient. **Four defects found there and nowhere else.**
- [ ] Taste ritual: 11pm-in-bed, roommate, first-flick, delete-it-for-a-week,
      idle-pixel.

## 6. Non-goals and deferrals (recorded up front)

- **A CloudKit Production schema deploy.** Human-owned, like PRD-7 §5. The new
  record type needs no entitlement change and no `match` re-mint.
- **Editing, trimming or annotating a replay.** §3.2 — the type has no setter.
- **Any number derived from `.leap` or `.slip`.** §3.3. There is no accuracy
  score, and the covenant is why.
- **A macOS debrief.** The Mac has no drawer and no first run either; a pull-up
  is a touch gesture and the Mac's answer is a window, which is PRD-33's.
- **Multiplayer replay re-simulation** (PRD-29's anti-cheat). It reads this
  format and is not built here.
