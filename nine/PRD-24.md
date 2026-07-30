# PRD-24 — Channels (Thermo, then Killer)

> Pillar B, "The Second Language". The product surface PRD-23's engine was built
> to feed, specified in [PROGRAM-2.0.md](PROGRAM-2.0.md) §Pillar B and expanded
> here into the design of record. Wave 3; the 2.0 launch train.
>
> How to execute it: [docs/EXECUTING-A-PRD.md](docs/EXECUTING-A-PRD.md). The
> covenant it must clear: [PRD-7.md](PRD-7.md) §1 and `EXECUTING-A-PRD.md` §1.

---

## 1. The thesis, in one paragraph

Nine 1.x proved the *input* covenant: the rose never misfires. PRD-23 proved the
*engine* covenant: a variant is a compiled `ConstraintContext` that the existing
solver loops read, and its reasoning arrives as ordinary `SolveStep`s. What is
left is the product claim those two make together, and it is a negative one:

> **A killer board and a thermo board are played with exactly the same rose, on
> exactly the same board view, through exactly the same four buttons.**

Nothing about the input changes. That is not a saving; it *is* the feature. A
variant shelf that needed a fifth control button would have disproved the thing
1.x spent three PRDs establishing. So this PRD's job is to add two rulesets and
spend **zero** of the input budget on them — and then spend the release's one
allowed new input concept on the only thing that genuinely is new: turning the
shelf's page.

## 2. What ships

**Channels.** The home shelf page-turns between three channels:

| channel | ruleset | status |
|---|---|---|
| **Classic** | plain sudoku, six bands | unchanged, byte for byte |
| **Thermo** | strictly-increasing tubes | new — ships **first** |
| **Killer** | cages with sums | PRD-23's engine, opened |

Each channel carries **its own** Today, its own streak, its own stats slice and
its own leaderboard. Dailies are **one per day per channel**.

Thermo ships first, and the ordering is a de-risking decision rather than a
taste one: `ConstraintContext` has compiled `.thermometer` into peer tables,
`thermoPositions` and position-narrowed `initialCandidates` since PRD-23
(`ConstraintContext.swift:238-252`), and `thermoBound` is a working technique
with fixtures and fuzz coverage. So thermo is a **supply** problem and nothing
else — no new reasoning, no new proof obligation. If the channel architecture is
wrong, thermo finds out cheaply. Killer follows once it holds.

### 2.1 Why the classic streak cannot be diluted, structurally

The stated requirement is "dailies are one-per-day per channel so the classic
streak is never diluted". A comment saying so would survive until the first
refactor. Instead:

> **`nine.streak`, `nine.history` and `nine.archive` stay classic-only and
> byte-identical. Channel state lives in its own `CouchStored` blob,
> `nine.channels`, which classic code never reads.**

The dilution question then has no code path to travel down. A killer solve
cannot touch the classic streak because the function that would do it does not
take a variant, and the blob it writes has no killer field. This is the same
move PRD-26 made with replays: the safety proof is the shape of the payload.

The blob reuses `SolveHistory` and `StreakState` **as value types, once per
channel**. That is the whole reason per-channel stats and per-channel grace cost
almost nothing: `count(of:)`, `bestSeconds(for:)`, `averageSeconds(for:)`,
`trend(window:)`, `displayedStreak(today:)` and PRD-13's non-stacking grace rule
all arrive already written and already tested.

### 2.2 A variant board on disk

`EXECUTING-A-PRD.md` §2 is binding and its two sanctioned moves are both used:

- **`GameKind` gains a case**, `.channel(variant:tier:day:)`. An older build's
  `BoardLibrary` decode cannot type it and **quarantines the whole entry
  verbatim** — which is the *correct* outcome, not a tolerated one: a build with
  no cage renderer must not open a cage board and call it classic.
- **The constraints go in a sibling top-level key** of `nine.library`, which
  `carriedTopLevel` preserves for free. So the older build keeps the rules it
  cannot read *and* the entry it cannot type, and the newer build gets both back
  intact.

No field is added to `LibraryEntry`, to `NineGame`, or to `NinePrefs`. The
1515 ms measurement at `BoardLibrary.swift:83-95` is why.

The play state is a plain `NineGame`. A variant board's grid, entries, pencil
marks, undo stack, timer and move log are the classic ones — which is §1's claim
restated as a data structure, and it is what makes the rose, the coach, the
replay, the debrief and the share card work on a thermo board with no new code.

### 2.3 The page-turn is this release's one new input concept

`Sources/` contains **zero** `TabView`s, zero horizontal `ScrollView`s and zero
`scrollTargetBehavior`s. A horizontal page-turn is therefore genuinely new, and
it is the only new thing:

- the rose is untouched;
- there is no fifth control button;
- no gesture is added to the game screen;
- the page-turn is on the **shelf only**, where nothing is at stake.

It must be paired, not sole: a discrete route (chevrons, in the shape
`ArchiveSheet.pager` already established at `ArchiveSheet.swift:93-122`) and a
named accessibility action, because a swipe alone is not an affordance and
`describe-ui` is the check.

### 2.4 The rose is unchanged, and a test says so

PRD-23's `VariantChannelSealTests` forbade *any* app-layer reference to the
variant engine. This PRD is the one that deletes it — and deleting it should
feel like a decision, so it is **replaced rather than removed**:

> `VariantInputSealTests` forbids the **input and wrist** layers from naming the
> variant engine: `FlickRoseView`, `PadSession`, `BoardKeys`, `PencilInk`,
> `Handwriting`, `Sources/Watch`.

The old seal asserted "no variant surface exists yet". The new one asserts the
claim this PRD actually makes, which is stronger and permanent: **the input
covenant is variant-agnostic, and the watch stays classic-only.**

---

## 3. Engine: thermo supply

### 3.1 The tiler

Killer's cages are a **tiling** — every cell belongs to exactly one cage, which
is what makes the rule of 45 work. Thermometers are **paths**, and they cover a
board only partially. So `ThermoTiling` is not `CageTiling` with a different
shape; it is a different algorithm with a different termination condition:

1. walk cells in a seeded order;
2. from an unused cell, grow a strictly-increasing path through king-move
   neighbours (the standard thermo geometry — orthogonal and diagonal), choosing
   greedily among neighbours whose solution digit is larger, seeded;
3. keep the path if it reached `minLength`, otherwise discard and move on;
4. stop at the band's thermometer count or when the board is walked out.

Two cells may not share a thermometer, which keeps `cagesAreDisjoint`'s thermo
analogue trivially true and keeps the peer table honest.

### 3.2 The band ladder

Thermo differs from killer in where its information comes from. A cage's sum is
an explicit number printed on the board; a thermometer's information is
**positional**, and `initialCandidates` already spends most of it before the
first technique runs. So the knobs are different:

| knob | why |
|---|---|
| `allowed` | as killer — the technique chain the proof may use |
| `maxGivens` | thermo boards legitimately carry givens; zero-given thermo is not the aesthetic the way zero-given killer is |
| `minVariantSteps` | the anti-decoration rule: without it a "thermo" board is a classic board with tubes drawn on it |
| `thermometers` | how many tubes the tiler aims for — the coverage knob |
| `minLength` / `maxLength` | a 2-cell thermo carries one bit; a 9-cell thermo fixes the whole line |

The ladder is **measured, not chosen.** `scripts/thermo-scan.sh` reports
composed-rate, p50/p90/p95/p99/max and the technique mix per tier in Release,
exactly as `killer-scan.sh` does, and a tier ships only at a p95 the player does
not notice.

Thermo's diagnostic lane needs a **third** cause that killer's did not, and the
ruleset makes it likely rather than unlikely. Killer can fail two ways — not
unique, or the chain cannot close it. A thermo band's clue ceiling has to stay
well above zero, so a board carrying a dozen givens may be one the *classic*
chain closes unaided: the tubes are decoration, `minVariantSteps` rejects it, and
that failure looks nothing like either killer cause and wants the opposite fix
(fewer givens or more coverage — a **wider** chain makes it worse). So the lane
counts the rejection reason rather than leaving it to be inferred.

### Measured, 200 seeds per tier, Apple silicon Mac, Release

| tier | composed | p50 | p95 | max | givens p50 (max) | tubes | cells on a tube |
|---|---|---|---|---|---|---|---|
| gentle | 200/200 | 0.00 s | **0.01 s** | 0.16 s | 14 (19) | 8 | 28 |
| steady | 200/200 | 0.01 s | **0.02 s** | 0.12 s | 12 (16) | 9 | 32 |
| sharp  | 200/200 | 0.01 s | **0.03 s** | 0.14 s | 7 (11) | 10 | 43 |

Thermo is 5–14× cheaper than killer's Sharp (0.14 s) and ~175× cheaper than
Nocturne (5.25 s), on every tier. That is what makes it the right ruleset to
de-risk the channel architecture with.

**The finding, and it changed the ladder.** The first draft composed 200/200 too
— which looks like a pass. But the shape report showed `maxGivens` set to
30/24/18 against a measured *max* of 19/19/11, and `minVariantSteps` at 3/6/10
against a measured p50 of 11/13/18. **Neither knob could ever reject anything.**
A band parameter that cannot fire is a decision dressed as a constraint, and the
tier would have been defined by whatever the dig happened to do.

What actually walks the ladder is the third knob: **a wider chain closes the
board with fewer givens**, because the extra techniques do work the clues would
otherwise have to. Gentle 14 → Steady 12 → Sharp 7. Both dead knobs were then
tightened to sit just inside the measured distribution, where the diagnostic
confirms they fire (`digExhausted` 14/17/7 and `decoration` 1/4/7 per 60
attempts) while supply stays 200/200 — the cost is paid in attempts, not in
supply.

This also answers the question PRD-23 §5 left open for this PRD. Killer's ladder
is compressed (6/4/0 givens, separated mostly by technique set); thermo's is
not. For thermo, three tiers read as three tiers.

### 3.3 What must not move

`swift test --filter GoldenCorpus` after **every** commit. 56/56 or it is a bug.
`SudokuGrid`, `Sudoku`, `BacktrackSolver` and `GeneratedPuzzle`'s encoded shape
stay untouched; `VariantPuzzle` remains the sibling type. `Difficulty` gains no
case — `VariantTier` is the variant ladder and always was.

---

## 4. Surfaces

### 4.1 The shelf (iOS)

`TouchHomeView`'s single vertical `ScrollView` gains a channel identity. The
pager wraps the shelf content and must work in **both** compositions —
`shelfColumn` and PRD-31's `shelfPair` — because `BoardCompositionRules.resolve`
decides that from the window and a pager does not get to override it.

Per channel the shelf shows: the channel's Today, the channel's streak chip, the
channel's boards, and the channel's bands. Classic's shelf is unchanged.

Gesture hygiene, all of it learned the hard way in this file:

- `.simultaneousGesture`, attached above any scrim, or the shelf cards lose taps
  (`TouchUI.swift:896-903`);
- `DragGesture.translation` is **not** RTL-mirrored (`FlickRoseView.swift:128`),
  so the pager resolves direction against the layout direction explicitly;
- a `predictedEndTranslation` snap, like the drawer's, not a raw-offset one.

### 4.2 The board

A new draw pass in `BoardView.draw`, inserted **between the hairlines and the
same-number highlight** (`BoardView.swift:539`) — above the grid so tubes are not
cut by hairlines, below the rings and digits so the loudest marks stay loudest
and no digit is ever occluded.

- **Thermometers as luminous glass tubes**: a bulb disc and a capsule stroke,
  drawn in the accent at low opacity, with the board's existing glass doing the
  lensing. No new shader — PRD-22 established that the Canvas *is* the render
  surface and the shaders sample it.
- **Cages as dashed inset outlines with a sum label** in the anchor cell's
  corner, in the same visual family as the coach's dashed victim ring.

Constraints reach the view as **one optional stored property with a default**,
the `CoachFocus` idiom, so all nine existing call sites render byte-identically.

Contrast is not optional here: a tube under a digit is a new ground for that
digit, so the PRD-22 harness must sample it across themes.

### 4.3 Accessibility

A tube and a cage are board facts a sighted player can see, so VoiceOver must
hear them. `BoardSpeech` — the pure formatter in `Sources/Shared`, which PRD-23's
seal had locked out of naming a variant — gains the constraint clause and the
four variant technique sentences PRD-11 left as a `default: return ""`
(`DEVIATIONS.md:1559-1561`).

`python3 nine/scripts/ax-snapshot.py` is the gate, and a drift is a bug until
proven otherwise.

### 4.4 Leaderboards

Per-channel leaderboard IDs beside the existing two
(`GameCenter.swift:28-38`). The entitlement is already present on all three
GameKit platforms, so this needs **no `match` re-mint** — but the leaderboard
records must exist in App Store Connect, which is a human gate of exactly the
kind PRD-7 §5 describes. Submission is fire-and-forget `try?` already, so a
missing record degrades to silence rather than a crash.

### 4.5 Watch, widget, tvOS, macOS

- **Watch stays classic-only.** `WatchSealTests` already asserts it; the new
  input seal reasserts it from the other direction.
- **tvOS and macOS** get the channel *switcher* in their own idiom (focus and a
  menu/segment respectively), not a swipe. A page-turn is a touch gesture.
- **The widget's channel parameter** slots into the `AppIntentConfiguration`
  PRD-33 already built for it (`DEVIATIONS.md:3957-3962`).

---

## 5. What this PRD explicitly does not do

- **No AI-generated rulesets.** Deferred to 2.x per PROGRAM-2.0 §Pillar B: they
  strain the proof covenant until the verifier can gate arbitrary rules.
- **No new variants beyond thermo and killer.** `.arrow` is the case
  `VariantConstraint`'s tolerant decode was written for, and it stays unwritten.
- **No fifth control button, no rose change, no new game-screen gesture.**
- **No channel-specific pricing, unlock, or "try it" surface.** There is nothing
  to unlock; the covenant forbids the shape as well as the substance.
- **No notification** when a channel's daily arrives.

## 6. Verification

Per PRD-7 §3 rule 3 and `EXECUTING-A-PRD.md` §5:

```bash
swift test --filter GoldenCorpus        # after every commit. 56/56.
swift test                              # the whole suite
scripts/thermo-scan.sh 200              # the p95 table, Release
scripts/thermo-scan.sh 200 --diag       # why a tier fails, not just that
python3 scripts/ax-snapshot.py          # per-screen AX diff
python3 scripts/contrast-harness.py     # tubes are a new ground for digits
```

Three platform builds plus a Release archive, then **drive it** — a green suite
is not evidence that a reshaped shelf works, and every recent PRD found defects
that only appeared on a simulator.
