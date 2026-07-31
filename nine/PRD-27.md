# PRD-27 — Pass the Remote

**Status:** Approved for implementation · **Thread:** `nine/` · **Wave:** 3 ("Together")
**One-liner:** Two people, one board, one remote — alternating timed turns, each
player's digits in their own tint, mistakes cleared without anyone being told off,
and both hands credited when it's over.

> This file did not exist when the work started; `PROGRAM-2.0.md:94` was the whole
> spec, the same way it was for PRD-25, PRD-26, PRD-30 and PRD-31. It is the
> forward document now. What actually happened, including the things that turned
> out to be false, belongs in the PRD-27 section of [DEVIATIONS.md](DEVIATIONS.md).

## 1. The thesis, in one paragraph

Nine's multiplayer pillar is called "Together, Quietly" and this is its cheapest
member: no login, no network, no matchmaking, no account. Two people are already
in the room. The whole feature is a turn boundary, a second tint, and the decision
that a board handed to another person must be a board they can trust. Everything
else — the rose, the board, the four buttons, the library, the debrief — is what
already shipped, unchanged.

The strategic point is the same one PRD-24 made about variants: the input covenant
is mode-agnostic. A duel is played with exactly the same rose, on exactly the same
board view, through exactly the same four buttons. If that stops being true, the
feature is wrong.

## 2. The one idea: a turn is a window on the board's own clock

There is no second clock. `NineGame.timer` is an `ElapsedTimer` that already
pauses for sheets and for scene backgrounding, and already stamps every
`LoggedMove.at`. A turn is three numbers against that one axis:

```swift
struct DuelTurn {           // Sources/Shared/Duel.swift
    let player: Int         // 0 or 1
    let firstMoveIndex: Int // index into NineGame.moveLog
    let startedAt: TimeInterval  // board-elapsed seconds when this turn began
}
```

Both facts the feature needs fall out of that single monotone axis:

- **The deadline** is `turnLength - (elapsed - startedAt)`. Nothing to keep in
  sync, nothing to drift, and it inherits every pause the board clock already
  takes. Backgrounding the app mid-turn does not eat the turn, because it does not
  eat the solve clock either.
- **Attribution** is a binary search over turn boundaries. Turns are *contiguous
  ranges* of the move log, so "who placed this digit" costs O(log turns), not a
  field on 300 moves.

That second consequence is what keeps this PRD out of the Engine entirely.
`LoggedMove` gains nothing. `NineGame`'s encoded bytes do not move.
`SolveReplay.packed` keeps its format and its version byte. **Nothing the golden
corpus hashes is in the diff**, so the corpus cannot move — which is a stronger
statement than "the corpus was run and passed".

The reason ranges are safe is a decision 1.0 already took and PRD-26 already spent:
undo is logged as an *event* and never pops the log. Indices are monotone forever,
including through corrections, so a range is never invalidated by a later move.

## 3. Attribution lives in a sibling blob, and a duel board is an ordinary board

`nine.duel` is a new `CouchStored` key holding `DuelLedger` — `[boardID: DuelState]`,
local-only, capacity-bounded and pruned against the live library exactly as
`nine.replays` is (same capacity, 60, and the same "prune against the live set"
door, because the two blobs have the same lifetime by construction: a duel board
is a library board and a duel that outlives its board is unreachable). A
`DuelState` is the two players' accents, the chosen turn length, and the turn list
— nothing else, and no `Date`. It is a **sibling top-level key**, which is EXECUTING-A-PRD §2's
rule satisfied structurally rather than by discipline: nothing is added to
`LibraryEntry`, so no older build can decode an entry "successfully" and erase the
new state on its next autosave.

**A duel board is a `.free(difficulty)` board.** `GameKind` gains no case, and that
is a deliberate inversion of PRD-24:

> PRD-24 added `GameKind.channel` *so that* an old build would refuse to open a
> killer board — a build with no cage renderer would draw a grid under constraints
> it does not enforce and mark the player's correct entries as errors. A duel board
> carries no rules an old build cannot enforce. It is an ordinary classic sudoku
> that two people happened to fill in. An old build opening it plays it *correctly*
> and simply does not know it was a duel.

So the degradation is right in both directions for the right reason each time:
quarantine where rendering would be wrong, silent tolerance where it would not.

`DuelState` decodes tolerantly and never throws out of its container. An
unreadable turn list yields *no duel*, not a lost board — the board itself lives in
`nine.library` and is never at risk.

## 4. The turn clock

Chosen when the duel starts, beside the difficulty, from three lengths:

| | seconds | for |
|---|---|---|
| Brisk | 60 | a board you both know how to read |
| Standard | 90 | the default |
| Unhurried | 180 | teaching someone, or a Nocturne |

This is a **per-duel setup choice, not a settings row.** The covenant makes
settings rows expensive (PRD-31 deferred a handedness pref on exactly this ground);
a choice made on the way into a mode costs nothing, the same way picking a
difficulty does.

**Remaining time renders as digits in the existing timer chip**, which during a
duel counts down instead of up. That slot is already `TimelineView(.periodic(by:
1))` — a 1 Hz redraw of a small glass chip outside the grid — so the countdown
costs **no new animation** and the board still reaches 0fps when nobody is moving.
The idle-pixel test is passed by reusing a pixel that already ticks rather than by
arguing about a new one.

Two things about that chip are deliberate and both are departures:

- **It shows even when `prefs.showTimer` is off.** The chip is normally gated on
  that pref. A duel is unplayable without knowing whose turn is ending, so the mode
  overrides the preference. Ignoring a pref is something this app otherwise refuses
  to do, and it is recorded here rather than discovered later.
- **It is a countdown, in an app that has spent a whole PRD refusing clocks.**
  PRD-30's mechanism is a payload structurally incapable of carrying one, sealed by
  a test that greps for `style: .timer`. That rule is about a **Lock Screen**
  surface and about streak-endangerment: a clock that nags someone who is not in
  the app, about something they might lose. This clock is consensual, shared, in
  the room, and bounded by the turn rather than by the board. `QuietPresenceSealTests`
  covers the quiet surfaces and the duel is not one of them; the seal is not
  weakened and no quiet surface gains a clock.

### 4.1 When the clock runs out

The turn ends, the rose closes **without committing** — a digit you did not confirm
is not yours — and the hand-off card appears. If the board is solved by the
placement, there is no hand-off: the duel ends and Afterglow runs.

The incoming player's clock **does not start until they confirm.** Passing a
physical remote across a sofa takes several seconds and it would otherwise come out
of their turn.

### 4.2 The accessibility out

`accessibilityVoiceOverEnabled` or `accessibilitySwitchControlEnabled` ⇒ **the turn
has no deadline at all.** It ends when the player places a digit.

Traversing 81 elements and opening a modal rose cannot be done in 90 seconds, and a
timed turn is otherwise a straightforward regression against the bar PRD-19 set.
This is detected, never configured — there is no row to find and no way to be in
the wrong state. In that mode the chip reverts to its ordinary behaviour
completely — the elapsed clock, and gated on `prefs.showTimer` again — because the
override in §4 exists only to keep a deadline visible and there is no deadline. A
countdown that never counts down is worse than none.

## 5. The quiet correction

**`showErrors` is forced off for the whole duel, regardless of the pref.** That is
what makes this a mechanic rather than a decoration: nobody is marked in coral
while a second person is watching them think.

At each hand-off, every wrong digit the outgoing player placed is erased — through
`NineGame.erase`, so the corrections land in the move log *before* the next turn's
`firstMoveIndex` is taken, which is what puts them inside the outgoing player's
range and makes them attributable. The order is load-bearing: clear, then close
the turn, then open the next one. The hand-off card names a **count with no
owner**:

> Two cells cleared.

No name, no cell, no "wrong", no coral, no haptic, no announcement of what was
there. At zero, the line is absent rather than "0 cells cleared" — honest absence,
the same rule `SolveDebrief.countsLine` already applies to errors.

The board the incoming player inherits is therefore always *truthful*: every digit
on it is either a given or correct. That is the property that makes a shared board
playable at all. Without it the second player spends their turn debugging the
first, which is neither calm nor a game.

Two consequences worth stating because they will look like bugs:

- The outgoing player watches their digit vanish under the card. The alternative —
  erasing after they confirm the pass — hides it from everyone, and a board that
  changes while nobody is looking is worse than one that changes while the person
  responsible is.
- The error haptic and the Conflicts rotor are wired to the same `showErrors` gate
  (PRD-19), so both fall silent for free. This must be *verified* rather than
  assumed: the leak PRD-19 documents is precisely a second path that keeps speaking
  after the first goes quiet.

## 6. Per-player tint

`BoardView` takes a single flat `accent: Color` and resolves it once per screen.
The change is one optional at the same site every additive board feature has used
(`highlightDigit`, `coachFocus`, `dimmedExcept`, `hoverCell`, `channelRules`):

```swift
var digitTint: ((Int) -> Color?)? = nil        // BoardView
…
var color = isGiven ? digitTone : (digitTint?(index) ?? accent)   // step 4, ~:705
```

Placed **above** the error, completion-wave and pad-peek branches, so all three keep
their existing precedence and every current call site renders byte-identically.

**Player One is your accent. Player Two is derived, not chosen.** The partner tint
is the `AccentChoice` maximising minimum perceptual separation from your accent
*and* from coral, across normal vision plus the three dichromacies — reusing the
machinery `AppearancePaletteTests` already applies to the 10 × 6 accent/theme
matrix. It is a pure function, deterministic, and pinned by a test.

Deriving it rather than offering it is the covenant choice: a colour picker for
player two is a settings surface, and PRD-16 already established that the obvious
free hue in the wheel is usually not a usable one.

**Players are named by their tint** — "Glacier", "Ember". `AccentChoice.title`
already routes through `Strings.string("accent.glacier")`, so this costs zero new
translation and zero text entry. A tvOS keyboard asking two people on a sofa to
type their names would be its own small tragedy.

Colour is never the sole signal: the hand-off card names the player in words, and
VoiceOver hears the owner in §8.

## 7. What a duel refuses to touch

Two people solved that board. It is not your solve.

`nine.streak`, `nine.history`, `nine.archive`, `nine.channels` and every Game
Center submission are skipped for a duel board. The drill pins `nine.history`
**byte-identical** across a duel solve, which is the same shape of proof PRD-24
used for the classic streak — a comment stating this survives until the first
refactor; an asserted byte comparison does not.

A duel never consumes the daily. It is always a fresh free board, so there is no
path by which two people playing on the sofa can spend the streak of the person
whose device it is.

**No winner is ever declared.** The debrief credits contributions; it does not
rank them, score them, or name one. A winner is a badge and EXECUTING-A-PRD §1
rules badges out by name. This is the line the feature is most likely to drift
across later, so it is stated as a requirement rather than as taste.

## 8. Surfaces

### 8.1 Where the duel is offered

tvOS, plus **wherever the drafting-table composition adopts** —
`BoardCompositionRules.resolve(width:height:) == .table`.

That is "tvOS and iPad" expressed as a measured rule with no device check in it,
consistent with PRD-31's finding that the composition is a pure function of the
window and never of the device. A duel wants a board two people can both see; a
1000×700 Stage Manager tile reports `.regular` while having less usable width than
an iPhone has height, so a size class would be actively wrong here for the same
reason it was there.

An iPhone gets no duel, and that is a real deferral rather than an oversight:
passing a phone back and forth every 90 seconds is a worse experience than not
having the feature.

### 8.2 The shelf

One card, in the extras row on tvOS and the trailing column of the iPad shelf pair
(the "boards you could start" side). Opening it presents difficulty × turn length,
then starts the board. Two title strings, because the noun differs and each is
right on its own surface: **Pass the Remote** on tvOS, **Pass and Play** on iPad.

### 8.3 The hand-off card

A `GlassSheet`-class overlay carrying: whose turn is next, in their tint and by
name; the cleared-cells line when non-zero; and one confirm action.

On tvOS it **owns the focus engine while up and the board's `couchRemote` surface
detaches** — the prefs-sheet detach pattern `GameScreen` already uses in both its
remote and pad bodies. This is the single most likely place for this PRD to
produce a defect that three green platform builds do not catch (PRD-31's
`.focusable()` inside a `GeometryReader` built fine and could not receive a
keystroke), so it is driven on a simulator, not merely compiled.

**Resuming a duel board always re-enters through the hand-off card**, whether it
was left mid-turn or the app was killed. Whoever picks the device up is told whose
turn it is before they can play. The turn's remaining time survives the pause for
free, because it is measured against a clock that was paused too.

## 9. Accessibility

The tint is the primary new information on the board and it is invisible to
VoiceOver. PRD-24's finding applies directly — a board can be structurally perfect
in the accessibility tree and semantically silent — so the owner is spoken.

It goes in the **cell value, not the label**, which is the opposite of where
PRD-24 put the cage clause, and the reason is the difference between the two facts:

> A cage's printed sum is permanent board information, closer to a given, so it
> belongs in the label — the part that locates the cell and never changes. *Who
> placed this digit* changes whenever the digit does, and value is the part
> VoiceOver re-speaks on every focus move.

An empty cell has no owner and says nothing. A given has no owner. On a non-duel
board the value is byte-identical to today's, which the four existing
`Tests/AXBaselines/*.txt` are the standing proof of — they must match with **no
re-record**.

The hand-off card announces on appearance, and its confirm action carries a 44pt
accessibility frame (`contentShape(.accessibility, …)` — PRD-24's tier cards
reported 41pt for exactly this reason).

## 10. The debrief credits both hands

`SolveDebrief` gains an optional `duel:` parameter. When nil, every existing line
is unchanged and the type is byte-identical in behaviour. When present it appends
to `lines`, which is the one place the card's order is decided — `DebriefCard.swift`
`ForEach`es `debrief.lines` and needs no change at all.

Three lines, in this order:

1. `Glacier placed 24 · Ember placed 21` — correct placements per player.
2. `Glacier cleared 2 · Ember cleared 3` — wrong placements per player, absent
   when both are zero. "Cleared", not "errors": the word describes what happened
   to the board, not a verdict on a person.
3. `Ember placed the last digit.` — the closest this feature comes to a flourish,
   and deliberately a fact rather than a result.

"Placed 24" counts placements whose digit matches the solution; "cleared 2" counts
those that did not, per attempt, which is the same definition `NineGame.errorCount`
already uses (three wrong tries at one cell is three).

The comet gets the tints for free — `CometTimeline` walks the move log by index,
and index is what the ledger is keyed on.

## 11. The input-concept budget: this release spends zero

The rose is untouched. There is no fifth control button. No gesture is added
anywhere.

- The shelf card is a card.
- Setup is difficulty cards, which is how every free board already starts.
- The hand-off is one focusable confirm — a click on tvOS, a tap on iPad, both of
  which every sheet in the app already uses.
- The countdown replaces the contents of a chip that already exists and already
  ticks.

A "pass now" affordance was considered and **refused**: it would be a fifth
control, and the turn clock already *is* the escape hatch a stuck player needs. A
player with nothing to place waits out the clock, which is exactly what happens at
a real table.

## 12. What this PRD explicitly does not do

- **No network, no login, no account, no SharePlay, no Game Center match.** Those
  are PRD-28 and PRD-29. The duel state never leaves the device.
- **No sync.** `nine.duel` is local-only, riding beside `nine.library` the way
  `nine.channelRules` does. Carrying attribution across devices would need a
  CloudKit record type and a production schema deploy — the human gate PRD-24's
  variant boards and PRD-26's replays both hit. A duel board that arrives on
  another device is an ordinary solved board, which is the correct degradation.
- **No iPhone, no Mac, no watch.** iPhone by the reasoning in §8.1; the Mac has no
  second seat and a duel on a desk is a different design, not a translation of this
  one (the same shape of deferral as PRD-24's tvOS channel page and PRD-26's Mac
  debrief).
- **More than two players.** Two is what "pass the remote" means and what a tint
  pair can stay separable across three dichromacies at.
- **No score, no winner, no rematch streak, no per-player stats over time.** §7.
- **No duel archive and no duel leaderboard.**

## 13. Verification

Green gates, per PRD-7 §3 rule 3 and EXECUTING-A-PRD §5:

- `swift test` — the pure layers (`Duel.swift`'s turn resolution, credit math and
  partner-tint derivation) are Linux-clean in `Sources/Shared`, tested with no
  simulator, the same shape as `RoseLens`, `DraftingTable` and `QuietPresence`.
- Golden corpus **56/56** and variant corpus **9/9** after every commit — expected
  to be trivially green, since nothing they hash is in the diff. That expectation
  is the claim being checked.
- iOS + tvOS + macOS builds, plus a Release archive.
- `python3 scripts/ax-snapshot.py` — all five baselines match with **no
  re-record**. A drift means the duel leaked onto a non-duel board.
- `python3 scripts/strings.py --audit` — new keys with translator comments, zero
  new bare-literal offences.
- A downgrade drill: a duel board opened by a build with no `nine.duel` reader
  plays as an ordinary free board with nothing lost.
- A history drill: `nine.history` byte-identical across a duel solve.

And then it is **driven, on both surfaces** — an Apple TV simulator and an iPad
simulator — for the three defects this repo keeps finding and this PRD is
structurally exposed to: a silent accessibility tree (§9), a focus fight on the
hand-off card (§8.3), and a second path that keeps speaking after `showErrors`
goes quiet (§5).
