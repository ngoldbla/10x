# PRD-11 — Coach (explainable hints) + auto notes — design

**Date:** 2026-07-25 · **Branch:** `ngoldbla/san-francisco` · **Scope:** one PR (11a + 11b together)
**Sources:** [nine/PRD-11.md](../../../nine/PRD-11.md), [nine/PRD-7.md](../../../nine/PRD-7.md),
[nine/PROGRAM-2.0.md](../../../nine/PROGRAM-2.0.md), [nine/docs/EXECUTING-A-PRD.md](../../../nine/docs/EXECUTING-A-PRD.md)

PRD-11 was written for Wave 0 and has sat unshipped since; `PROGRAM-2.0.md`
was written after it and is the program of record. They disagree in three
places. This document records the rulings, the design that follows, and the
deviations that go in `DEVIATIONS.md` when the PR lands.

---

## 1. The three reconciliations (ruled, not assumed)

| Conflict | Ruling |
|---|---|
| PRD-11 §2.1 adds a `lightbulb` button; PROGRAM-2.0's anti-bloat constitution says "will never … add a fifth control button" | **Override the constitution.** The game bar goes from 4 buttons to 6 (lightbulb + wand). Recorded in `DEVIATIONS.md` with the reasoning. |
| PRD-11 §2.1's card commits placements; the same constitution says "will never … let the coach place a digit" | **Keep `Place it` and `Mark it`.** The reconciliation is that the *player* taps it — the clause means the coach never auto-solves, which stays true. Recorded. |
| PRD-11 §2.1's contradiction card says "check the coral cells"; `EXECUTING-A-PRD.md` §4 forbids leaking solution knowledge when `showErrors == false` | **Pure-logic contradictions only.** See §2.2. Recorded as a deviation. |

Two further calls, ruled the same way:

- **The wand is a real toggle**, not the one-shot its §2.2 text implies. See §5.
- **`applyAutoNotes` writes nothing to `moveLog`.** See §9.

---

## 2. Engine — `Sources/Engine/Coach.swift`

### 2.1 The advice type

```swift
public enum CoachAdvice: Sendable, Equatable {
    case step(SolveStep)              // the next move this board's band affords
    case contradiction(cells: [Int])  // the board disagrees with itself
    case exhausted                    // nothing at this board's ceiling
    case solved
}
```

Produced by:

```swift
extension CandidateState {
    /// Candidates as they stand for the player's entries, givens included.
    public init(playerGrid: SudokuGrid, context: ConstraintContext = .classic)
}

extension LogicSolver {
    public static func advice(
        for grid: SudokuGrid,
        allowed: [Technique],
        context: ConstraintContext = .classic
    ) -> CoachAdvice
}
```

`allowed:` is always `game.puzzle.difficulty.allowedTechniques` at the call
site, so a Gentle board never lectures about X-wings (PRD-11 §2.1).

`context:` is defaulted, which matters: `VariantChannelSealTests` fails the
build if `Sources/App`, `Sources/Widgets` or `Sources/Shared` so much as
*names* `ConstraintContext`. The app never writes the symbol, so the seal
holds unchanged and PRD-24 inherits a coach that already speaks variants.

### 2.2 Contradiction is derived from the board, never from the solution

PRD-11 §2.1 wants the card to say *"There's a slip somewhere — check the coral
cells."* Coral cells come from `NineGame.isError`, which compares against
`puzzle.solution`. `EXECUTING-A-PRD.md` §4 is explicit that `showErrors == false`
must suppress the "wrong" word in the spoken value, the wrong-digits rotor
**and** the error haptic. A coach pointing at coral is that same leak.

`contradiction(cells:)` is therefore detected by pure logic only:

1. **Peer clash** — a filled cell whose value equals a peer's value.
2. **Dead cell** — an empty cell with no candidates left (`isStuckDead` already
   answers the boolean; the coach needs the cells).

Both are facts the player could derive from what is on screen, so the sentence
is identical whether `errorHighlight` is on or off, and the coach never reads
the solution.

This also closes a real gap. `CandidateState.init` zeroes candidates for filled
cells and never compares filled cells to each other, so **two 7s in one row are
invisible to it today**. Without check 1 the coach would return a confident
`.step` on a self-contradicting board — the coach lying is worse than the coach
declining.

Order matters: contradiction is checked **before** `nextStep`, because a
contradictory board can still yield a technically-valid-looking step.

---

## 3. Shared — every sentence through `BoardSpeech`

No new sentence code. `Sources/Shared/BoardSpeech.swift`'s own header already
promises this surface:

> This is also the Coach's phrasebook (PRD-19 §2 onward), so the pieces are
> composable — `digitWord`, `boxLabel`, `remainingClause` are public and get
> reused inside future sentence templates rather than re-spelled there.

It gains:

```swift
public static func coachTitle(_ advice: CoachAdvice) -> String
public static func coachSentence(for advice: CoachAdvice, in game: NineGame) -> String
/// "Box 2" / "Row 3" / "Column 5" for the unit a set of cells shares, else "".
public static func unitLabel(containing cells: [Int]) -> String
```

`unitLabel` is the one new composable primitive, built from the existing
`rowLabel` / `columnLabel` / `boxLabel`.

Templates live in the file's existing `Phrase` block — the single seam PRD-20
converts. Sentences compose existing primitives rather than spelling words:

| Technique | Sentence |
|---|---|
| Naked Single | "Row 3, column 5 has one candidate left: seven." |
| Hidden Single | "Only one square in Box 2 can take a seven." |
| Naked Pair | "Three and seven fill these two squares between them, so neither can go anywhere else in Row 4." |
| Hidden Pair | "Three and seven fit only these two squares in Box 5, so nothing else fits there." |
| Box-Line Reduction | "Every seven in Box 2 sits in Row 3, so Row 3's other boxes cannot take one." |
| X-Wing | "Sevens in these two rows sit in the same two columns, so no other cell in those columns can be a seven." |
| contradiction | "Two of these squares disagree — nothing can go here yet." |
| exhausted | "Nothing at this board's level follows from here." |
| solved | `BoardSpeech.solvedAnnouncement` (already exists) |

The four sealed variant techniques fall to a `default:` that names no sealed
symbol.

**The card's visible text and the VoiceOver announcement are the same string
from the same function.** One copy, no drift, one block for PRD-20.

---

## 4. App — a presentation PRD-25 can reuse

New file `Sources/App/CoachCard.swift`. `TouchUI.swift` is 1218 lines and is the
contention point named in `EXECUTING-A-PRD.md` §7; the card does not belong in it.

### 4.1 The reusable seam

```swift
struct CoachFocus: Equatable, Sendable {
    let pattern: [Int]   // cells forming the pattern — accent wash
    let target: Int?     // the cell the step resolves — stronger ring
    let victims: [Int]   // cells losing a candidate — dimmed accent border
    let digit: Int?      // the digit under discussion, for note emphasis
}
```

`BoardView` gains exactly **one** parameter, `var coachFocus: CoachFocus? = nil`,
drawn between the same-number highlight (step 2.5) and the cursor (step 3) so
the cursor ring always draws last and brightest. tvOS and macOS pass nothing and
render byte-identically — the same default-off discipline `dimmedExcept`,
`hoverCell` and `waveOrigin` already use.

**Why this shape is what PRD-25 needs.** PRD-11 renders one `CoachFocus`;
PRD-25 renders a *sequence* of them. Its spec asks for "involved cells breathe
in sequence, one step at a time, no text walls" — that is `[CoachFocus]` driven
by a timeline, with no change to the card, the board, or the sentence layer.
The `pattern` / `target` / `victims` split is deliberately the `roles`
(base/cover/pivot/victim) vocabulary PROGRAM-2.0 names for trace schema v2; a
`pivot` role appends without moving the other three.

Arrays rather than a `[Int: Role]` dictionary: draw order must be deterministic
where cells overlap, and dictionary iteration order is not.

### 4.2 The card

Presented as an overlay in the PRD-2 free band opposite the control bar — the
board never moves, matching the grammar `tipView` and `toastView` already use.
Dismiss is a tap outside, via the same 0.001-opacity scrim the rose uses.

Contents: technique title, the one sentence, and one action —
**Place it** for a step with a `placement`, **Mark it** for an eliminating step
(applies the eliminations to pencil marks). Contradiction, exhausted and solved
cards carry no action.

**`Mark it` is suppressed while auto notes is on.** Under §5 the marks are the
machine's, and the next placement recomputes them — so a `Mark it` whose effect
is erased one move later is a button that lies. With auto notes on, an
eliminating step shows its sentence and its board wash and no action; with auto
notes off it behaves exactly as PRD-11 §2.1 specifies.

`Place it` routes through `model.place` exactly as the rose does, so wave,
error rules, haptics and persistence are all the standard path (PRD-11 §2.1).

Accessibility: the card is one AX element whose label is the same
`coachTitle` + `coachSentence` pair, and appearing posts an announcement built
from the same strings.

### 4.3 The control bar

Order becomes: `Home · timer · lightbulb · pencil · wand · undo · gear`.
Lightbulb leads the right cluster and wand sits beside pencil, per PRD-11.

**Layout risk to verify, not assume:** six 44pt buttons plus five 10pt gaps is
314pt, and the timer chip needs ~70pt more. A 375pt-wide iPhone SE / mini has
~361pt of usable width after the existing 8+6pt padding. This must be driven on
an SE-class simulator with `showTimer` **on**, and the spacing reduced if it
overflows. A control bar that clips on the smallest phone is a shipping bug.

---

## 5. Auto notes — a real toggle

PRD-11 §2.2 calls the wand a toggle but describes a one-shot: `place` already
prunes the placed digit from peer marks (`Game.swift:170-173`, verified — §2.2
asked for this to be checked), so an "on" state would have no ongoing effect.
**Ruling: make the toggle real.**

### 5.1 Semantics

- **On enable:** every empty cell's marks become its candidate set. One
  undoable move. If nothing changes, `applyAutoNotes()` returns false and
  pushes no undo entry — the `place`/`erase` no-op convention.
- **While on:** after every `place` and `erase`, every empty cell's marks are
  **replaced** by its candidate set, folded into *that same move's* undo entry.
  Replace, not merge: the marks are the machine's while the toggle is on.
- **On disable:** marks freeze exactly as they are. Nothing is cleared, ever
  (PRD-11 §2.2: "no destructive clear").
- Hand edits via the pencil rose stay legal while on, and are overwritten by
  the next placement. That is what "the marks are the machine's" means, and it
  is the accepted cost of a toggle that is genuinely a mode.
- A contradictory board yields empty candidate sets for its dead cells, so
  their marks vanish. That is honest — no legal digit remains — and it is the
  same information `contradiction(cells:)` reports.

`erase` is where the toggle earns its keep: `place` already prunes the placed
digit from peer marks, but nothing today re-derives marks after an erase widens
the candidate set. That re-derivation is the ongoing behaviour that makes the
toggle a mode rather than a one-shot.

`togglePencil` is untouched.

### 5.2 Engine API

```swift
@discardableResult
public mutating func place(_ digit: Int, at cell: Int, autoNotes: Bool = false) -> Bool
@discardableResult
public mutating func erase(at cell: Int, autoNotes: Bool = false) -> Bool
@discardableResult
public mutating func applyAutoNotes() -> Bool
```

The default keeps all ~20 existing call sites — widgets, tutorial, first-run,
Mac, pad session, tvOS — byte-identical.

### 5.3 No new `NineMove.Kind` case, and why that is not a shortcut

`NineMove.Kind` is persisted inside `undoStack` inside `NineGame` inside
`LibraryEntry`, and `NineGame.init(from:)` decodes it with a bare
`try c.decode([NineMove].self, forKey: .undoStack)`. A new `.autoNotes` raw
value would **throw** on an older build, taking the whole entry down —
quarantined by `BoardLibrary`, but that board is gone. Builds 450/451/452 are
already on TestFlight, so tolerance added now cannot save them. Same lesson as
PRD-17's `nine.history`.

So a bulk fill reuses `kind: .pencil` and carries every touched cell in the
existing `previousPencil: [PencilSnapshot]` array. A normal pencil move always
has exactly one snapshot, so `kind == .pencil && previousPencil.count > 1` is an
unambiguous discriminator, exposed as `NineMove.isBulkNotes`.

The payoff: `NineGame.undo()` already restores every entry in `previousPencil`
regardless of kind, so **an older build undoes both a bulk fill and an
auto-notes placement correctly, with zero changes.**

### 5.4 Undo coherence

Undoing a bulk-notes move also switches the toggle off (`AppModel` reads
`move.isBulkNotes`). Otherwise the next placement immediately refills what the
player just undid. The undo toast reads "Undid auto notes".

### 5.5 The chip

One glass chip on first enable: "Auto notes · filled N candidates" (PRD-11 §2.2),
reusing `GlassChip` and the existing `toast`/`tip` overlay slot.

---

## 6. Persistence — `nine.coach`

Its own `CouchStored` blob. **Never a field on `LibraryEntry`** — the 1515 ms
vs 49 ms finding in `EXECUTING-A-PRD.md` §2 rules that out, and §2 names PRD-11's
"hints used" as a direct instance.

```swift
public struct CoachLedger: Codable, Equatable, Sendable {
    public struct Board: Codable, Equatable, Sendable {
        public var hints: Int = 0
        public var autoNotes: Bool = false
    }
    public private(set) var boards: [String: Board]   // LibraryEntry UUID → record
}
```

- Tolerant decode that never throws (the `TipLedger` pattern — a malformed or
  future-shaped payload reads as empty rather than taking the file down).
- Local-only, not `cloudSynced` — per-board hint counts are device-local UX, the
  same call `undoCount` makes (PRD-8 §2). Mastery across boards is PRD-25's
  `CoachProgress` in KVS, a separate thing.
- Pruned on write to ids still present in the library, so it cannot grow
  without bound.
- Old builds never see the key, so there is no downgrade hazard here. The
  sibling-key rule still applies *inside* it for future fields.

The auto-notes flag lives here rather than in view `@State` because §5 made it
behavioural: a flag that resets on relaunch would silently stop updating a
player's marks with no signal.

### 6.1 Where the count surfaces

A fifth `StatsDrawerContent` tile, **shown only once `hints > 0`**. Nothing is
ever gated on it (PRD-11 §3: "No hint quotas, ever"). A player who never uses
the coach never sees coach chrome — the craft charter's "every state has a
designed zero-state (honest absence over fake data)".

---

## 7. Testing

Engine and Shared only, so the whole suite stays Linux-clean.

| Suite | Covers |
|---|---|
| `CoachTests` (Engine) | one fixture per classic technique → expected `SolveStep`; band ceiling respected (a Sharp-only X-wing is not offered on a Gentle board); peer clash detected; dead cell detected; contradiction beats `nextStep`; solved and exhausted cases |
| `BoardSpeechTests` (Shared, existing) | a sentence per technique; `unitLabel` for row/column/box/none; contradiction wording identical with `showErrors` true and false; nothing traps on out-of-range input |
| `GameTests` (Engine, existing) | bulk fill undoes in one step; `isBulkNotes` discriminates; `place(autoNotes: true)` folds the recompute into one undo entry; `place(autoNotes: false)` is byte-identical to today; `erase(autoNotes: true)` re-derives widened candidates; a no-op `applyAutoNotes()` pushes no undo entry; disable clears nothing |
| `TolerantDecodeTests` (Engine, existing) | `CoachLedger` survives malformed, empty and future-shaped payloads |

Then the gates a green suite does not cover:

- `swift test` under ~120 s (it reads 112.5 s today — thin, and this PRD must
  not be what breaks it).
- Golden corpus after **every** engine commit, not at the end.
- `xcodebuild` for iOS, tvOS and macOS simulators, plus a Release archive.
- `python3 nine/scripts/ax-snapshot.py` — **`game.txt`, `game-quiet.txt` and
  `game-rose.txt` will all drift**, because the control bar is in every one of
  them. That is intended, so re-record with `--record` and say so in the PR.
- Drive it on a simulator: coach on a mid `--debug-fill` board shows a real step
  with lit cells; `Place it` advances the board; auto notes fill and undo in one
  step; the control bar does not clip on an SE-class device with the timer on.

---

## 8. Deviations to record in `DEVIATIONS.md`

1. The control bar grew from four buttons to six, overriding PROGRAM-2.0's
   "never add a fifth control button".
2. `Place it` / `Mark it` kept; "the coach never places a digit" read as "the
   coach never auto-solves", since the player taps it.
3. Contradictions are pure-logic, not coral — PRD-11 §2.1's wording would leak
   solution knowledge when `errorHighlight` is off.
4. The wand is a genuine mode that recomputes marks on every placement and
   erasure, which is more than §2.2 asked for and is what makes "toggle"
   honest. Its cost — hand-made marks are overwritten while on — is accepted,
   and it is why `Mark it` is suppressed in that mode.
5. `applyAutoNotes` reuses `NineMove.Kind.pencil` rather than adding a case,
   for downgrade safety. Discriminated by snapshot count.
6. The tvOS and macOS coach remain out of scope (PRD-11 §3).

## 9. Not done (deliberate)

- **No `moveLog` entry for auto notes.** `LoggedMove.Kind` carries the identical
  downgrade hazard (`decodeIfPresent` still throws on a present-but-unknown
  value), and there is no honest single `(cell, digit)` for a bulk fill.
  PRD-26 is already adding `LoggedMove` v2 fields; it should design the
  representation with a consumer in hand rather than have one guessed now.
  Consequence: a PRD-26 replay will show marks appearing without a cause.
- **No tvOS or macOS coach** — PRD-11 §3 non-goal; the band layout is iOS.
- **No new solver techniques** — PRD-11 §3; that is PRD-25's frontier.
- **No hint quotas, ever** — PRD-11 §3, and the covenant.
