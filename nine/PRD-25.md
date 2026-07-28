# PRD-25 — Why Must This Be a Seven? (+ Technique School)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one PR
**One-liner:** Long-press an empty cell and the board *shows its work* — the
minimal chain of deductions that forces that square, narrated one step at a time
on the board itself, never as a wall of text. A Technique School teaches each
technique from a real seeded position. Two new bands open the deep end.

Source of record: [PROGRAM-2.0.md](PROGRAM-2.0.md) §Pillar C. Execution rules:
[docs/EXECUTING-A-PRD.md](docs/EXECUTING-A-PRD.md). Covenant: [PRD-7](PRD-7.md).

---

## 1. Why

Nine already knows the answer to "why must this be a 7?" and has since 1.0.
`LogicSolver.solve` returns an ordered `[SolveStep]` — technique, cells, digits,
placement, eliminations — and that trace is *inside every `GeneratedPuzzle`*,
frozen in the golden corpus. PRD-11 spends it one step at a time ("here is the
next move"). What it has never done is answer the question a stuck player
actually asks, which is not *what next* but *why that*.

The gap between those two is the whole product. A hint is a fish. A derivation
is the rod — and it is the one thing a sudoku app can do that a sheet of paper
cannot.

## 2. The experience

### 2.1 The question

- **iOS:** long-press any cell (0.45 s) whose entry is empty.
- **macOS:** ⌥-click the same cell.
- **tvOS:** deferred — see §6. `.holdBegan` on an empty non-given cell is
  already the pencil rose *and* the four-way remote's only door to Prefs.

The gesture is additive: a plain tap still opens the rose, so the first-flick
covenant is untouched. This is **not** a new input concept in the craft-charter
sense — long-press-for-explanation is the platform's own idiom, and the release
spends its one concept allowance on nothing else.

### 2.2 The answer, on the board

No card, no scroll, no paragraph. The board narrates:

1. The chain is derived (§3.2) and reduced to its **minimal** ordered form.
2. Step 1's pattern cells breathe in — the accent wash PRD-11 already
   established — its victims dash, its placement rings.
3. One line of copy sits in the PRD-2 free band: the technique's name and its
   single sentence. That is the entire text budget for a step.
4. **Next** advances. Tap anywhere else, or press the lightbulb again, and it
   ends. The chain never auto-advances: a player reading a proof sets the pace.
5. The last step places the digit — and the coach still does not. The final
   beat offers **Place it**, which routes through the ordinary `model.place`.

A chain longer than **6** steps is truncated to its last 6 and says so ("…and
five steps before this"). The honest alternative — narrating a 40-step chain —
is a text wall wearing an animation.

### 2.3 Technique School

The playable tutorial (`TutorialView`) gains a second door: **School**. One
lesson per technique, ordered by rank, each a *real position from a real board*:

> An exemplar is `(seed, difficulty, stepIndex)` — about 20 bytes. The device
> regenerates the puzzle (pure function of the pair), replays the trace to
> `stepIndex`, and **proves** that the step at that index is the technique the
> lesson claims. Nothing is shipped as a serialized grid, so nothing can rot
> against a generator change without CI saying so.

A lesson is: the position, the narration from §2.2 run over that one step, and
then the board handed back to the player to make the move themselves. Locked
lessons do not exist — every lesson is open from the first launch. The list is
ordered, not gated.

### 2.4 Hints become "show me the next why"

PRD-11's coach card gains one action alongside **Place it** / **Mark it**:
**Why?** — which starts the §2.2 narration on the step the card is already
showing. The card is the summary; the narration is the proof.

### 2.5 What the coach remembers

`CoachProgress` — its own `CouchStored` blob (`nine.coachProgress`), KVS,
cloud-synced, hard-capped under 2 KB. Per technique: whether it has ever been
explained, whether its lesson has been finished, and how many times it has been
narrated.

It exists to make the app quieter, never louder. Its only three readers:

- School orders "the one you have not met yet" to the top of the list.
- A technique explained before gets its sentence and skips the preamble.
- The stats drawer says "seven of ten techniques met", once, in the existing
  hand-inked language.

**No badges, no XP, no levels, no percentage ring, no notification.** A player
who never opens School is never told they have not.

## 3. Engine

### 3.1 The deep end: two bands and four techniques

`Technique` is **appended to, never reordered** — its raw values are the
localization identity and its ranks are inside 56 golden hashes.

| new case | rank | tier |
|---|---|---|
| `swordfish` | 10 | Tempest |
| `skyscraper` | 11 | Tempest |
| `xyWing` | 12 | Tempest |
| `simpleColoring` | 13 | Abyss |

- **`fish(n:)` generalizes `xWing`.** X-Wing *is* `fish(2)` and must emit
  byte-identical `SolveStep`s — same corner order, same elimination order, same
  digit list — or the corpus moves. Swordfish is `fish(3)`. The generalization
  is the point: one loop, one proof, two techniques.
- **W-Wing is not shipped.** PROGRAM-2.0 marks it optional and the rule it
  states is the reason: *stop before full chains — explanation complexity is
  the limit*. A technique Nine cannot narrate in one sentence has no business
  in a band Nine sells.

`Difficulty` gains `.tempest` and `.abyss`. **Both ship only at a measured
compose p95** (§5) — the PRD-23 rule, applied to bands.

### 3.2 The why-chain

```swift
public static func derivation(
    forCell cell: Int, in grid: SudokuGrid,
    allowed: [Technique] = allTechniques, context: ConstraintContext = .classic
) -> Derivation?
```

1. Solve from the *player's* grid until a step places `cell`.
2. Reduce: drop each earlier step, last-to-first, keeping only those whose
   removal breaks the chain. The result is **locally minimal** — no single step
   in it can be removed — which is what "minimal" can honestly mean at this
   cost. Stated, not implied.
3. Every retained step is re-checked by `LogicSolver.validate(_:in:)`, a
   per-technique re-derivation. The invariant a test pins: *every step the
   solver emits validates in the state it was emitted from*, and *every step of
   a returned derivation validates in sequence*.

**Nothing here takes a `NineGame`.** That is Coach.swift's structural rule
against leaking `puzzle.solution`, and it holds unchanged: a derivation is a
function of what is on the board.

### 3.3 SolveStep v2

Additive and tolerant, per Phase 0 §4:

- `roles: [Role]?` — `base` / `cover` / `pivot` / `victim`, parallel to `cells`.
- `chain: [Link]?` — the coloring graph, for the Abyss animation.
- `techniqueID`: **already shipped.** PRD-20 found the raw values were the
  frozen identity, so this half of schema v2 is a deletion that happened.

Both are `Optional` and **nil for every step the classic six emit**, so the
synthesized encoder omits the keys and the corpus is byte-identical. That claim
is not asserted, it is *run*: the corpus after every commit. Decode is
`decodeIfPresent`. An old build that drops them on re-encode loses nothing —
they are derivable from the step.

## 4. Persistence

Per EXECUTING-A-PRD §2, and stated so the next person does not have to re-derive
it:

- `CoachProgress` is **its own top-level blob**, not a field on `LibraryEntry`
  and not a field on `CoachLedger`. (Field-level preservation: 1515 ms against
  a 49 ms baseline, reverted.)
- New `Technique` raw values ride inside `GeneratedPuzzle.steps`, so an older
  build meets `"swordfish"` in a library entry and **quarantines that entry**
  rather than the library — Phase 0's element-level decode, doing its job.
- New `Difficulty` raw values need the `nine.history` `band` sibling that PRD-17
  built. `.tempest` and `.abyss` both write `wireBand == .sharp`.
  `DowngradeDrillTests` already names both by string; it stops being
  hypothetical.

## 5. Verification checklist

- [ ] Golden corpus 56/56 **after every commit**, not at the end.
- [ ] `fish(2)` emits byte-identical steps to the frozen `xWing` on a fixture
      corpus — a named tripwire below the golden hash, so a failure says *where*.
- [ ] Every new technique is sound: a soak asserting no emitted placement
      disagrees with the solution and no elimination removes a solution digit.
- [ ] `validate` round-trip: every emitted step validates where it was emitted.
- [ ] Every exemplar in the School catalog regenerates and proves, in CI.
- [ ] Compose p95 per new band, Release, ≥100 seeds, published as a number.
- [ ] `swift test` under ~120 s.
- [ ] Three platform builds + a Release archive.
- [ ] `ax-snapshot.py` diff clean, or re-recorded with a stated reason.
- [ ] Driven on a simulator: long-press an empty cell on a Steady board, walk a
      chain, screenshots kept.
- [ ] Taste ritual: 11pm-in-bed, roommate, first-flick, delete-it-for-a-week,
      idle-pixel.

## 6. Non-goals and deferrals (recorded up front)

- **tvOS narration.** The gesture collision is real and the fix is a re-gesture
  of the pencil rose, which is a PRD-5 decision and not this one's to take.
- **W-Wing and any full chain** (§3.1).
- **A School lesson for the four variant techniques.** They are behind PRD-23's
  channel seal; a lesson for a board the player cannot reach is a lie.
- **Mastery as a number the player is shown.** §2.5.
