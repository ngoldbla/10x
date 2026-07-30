# PRD-31 — The Drafting Table (iPad)

**Status:** Implemented · **Thread:** `nine/` · **Wave:** 2 ("Deeper")
**One-liner:** The iPad stops being a large iPhone — board centre stage,
controls floating beside it, the stats drawer left permanently open as a rail —
and the Apple Pencil earns the release's one new input concept: you write a
digit, and it becomes a pencil mark **in your handwriting**.

> This file did not exist when the work started; `PROGRAM-2.0.md:97` was the
> whole spec, the same way it was for PRD-25 and PRD-26. It is the forward
> document now. What actually happened, including the things that turned out to
> be false, is in the PRD-31 section of [DEVIATIONS.md](DEVIATIONS.md).

## 1. The problem

`Sources/` contained **zero** `horizontalSizeClass`, zero `UIDevice`, zero
`userInterfaceIdiom`. The whole iPad story was one `.frame(maxWidth: 560)` on
the home shelf and a board clamp in `TouchUI` whose height term subtracted a
control-bar reserve and whose width term did not — portrait-shaped reasoning,
shipped to a device that runs landscape and that `project.yml:182` grants all
four orientations.

The result on an 11" iPad in landscape: a 560pt ribbon of cards in the middle of
800pt of nothing on the shelf, and on the game screen a board that ate the full
screen height with the flexible bands collapsed to zero and six 44pt buttons
spread across 1300pt.

## 2. The composition is a function of the window, never of the device

`Sources/Shared/DraftingTable.swift` — Linux-clean, no SwiftUI, tested by
`swift test` with no simulator, exactly like `RoseLens`.

```swift
BoardCompositionRules.resolve(width:height:) -> BoardComposition   // .column | .table
```

**A size class would be actively wrong here.** A 1000×700 Stage Manager tile on
an iPad Pro reports `.regular` horizontally while having less usable width than
an iPhone 17 Pro Max has height; an external display hands us 1920×1080 from the
same idiom that hands us 834×1194. Asking the window is both simpler and correct,
and it is the entire Stage Manager story — there is no Stage Manager code.

**The adoption rule: the rail never costs you board.** Take the drafting table
only when its board is at least as big as the column's would have been (within a
named 8% skirt, because held literally the two land within single-digit points on
an 11" and a 2pt chrome change would flip the whole composition), and never below
a 520pt floor. That rule, and not a width threshold, is what correctly refuses
portrait: an iPad Pro is 1024pt wide upright, and any threshold generous enough
to admit an 11" in landscape also admits it — at the price of dropping the board
from 984pt to 568pt.

| Window | Composition | Board |
|---|---|---|
| iPhone, either orientation | column | unchanged |
| iPad portrait (all sizes) | column | unchanged |
| iPad mini landscape | table | 617pt |
| iPad 11" landscape | table | 678pt |
| iPad Pro 13" landscape | table | 850pt |
| Stage Manager 1000×700 | column | 584pt |
| 1080p external display | table | 1000pt (capped) |

Both arms cap the board at 1000pt. `theCapIsInertOnEveryShippingDevice` proves
the cap changes nothing anyone currently owns — the largest real board is an
iPad Pro 12.9" in portrait at 984pt. It exists so a 1440p panel does not draw a
1324pt grid you read by moving your head.

## 3. The table

```
┌──────────────────────────────────────────────────────┐
│  ⌂                                     ╭───────────╮ │
│                ┌──────────────┐        │ ①②③④⑤⑥⑦⑧⑨ │ │
│                │              │        │ time pace │ │
│                │    BOARD     │        │ notes … │ │
│  ○ hint        │              │        ╰───────────╯ │
│  ○ pencil      └──────────────┘                      │
│  ○ auto notes                                        │
│  ○ undo                                              │
│  ○ settings                                          │
└──────────────────────────────────────────────────────┘
```

- **Controls lead, stats trail, and the sides are not interchangeable.** The rail
  is what you glance at, and glancing is cheaper on the side your writing hand is
  not covering; the controls are what you reach for, and reaching across the board
  with a Pencil in hand drags your wrist over the grid you are reading.
- **The control column is not the bar rotated.** Home pins to the top, where "out
  of here" belongs and a stray reach cannot find it; the five tools group at the
  bottom, in the arc a resting hand already sweeps. Same six buttons, same labels,
  same 44pt targets, built from the same six factories — so the bar and the column
  cannot come to disagree about what a control does.
- **The rail is the stats drawer with the drawer taken off it.** Same
  `StatsDrawerContent`, same width, same glass; it is not redesigned for the iPad,
  it is simply left open. PRD-34 spent a hairline grabber and three sessions of
  its tip budget teaching people the drawer exists; at this width the geometry
  says it for free and permanently. In table mode the grabber, the pull-down
  gesture and the "Show board stats" VoiceOver action all stand down — an action
  that opens something already on screen is the defect `ax-snapshot.py` found in
  PRD-26's rotor.
- The phone's free bands have no home here, so the timer chip and the ambient slot
  move into the rail.
- **PRD-26's debrief stays a pull-up over the board**, not a rail section. "Never
  unbidden" is a shipped decision and geometry is not a reason to re-litigate it.
- The home shelf splits into two columns at the same threshold, decided by the
  same function: boards you *have* on the left, boards you could *start* on the
  right.

## 4. Hover

`BoardView` has drawn a hover halo since PRD-4 and macOS was the only caller. A
trackpad pointer and a hovering Apple Pencil tip deliver the same
`onContinuousHover` phases, so one modifier gives iPadOS the same affordance off
the same value.

Hovering a **rose petal** lights `BoardView.previewDigit` — the ghost digit that
has existed since tvOS's pad rose and has been dead on iOS. A finger on a petal
is direct and needs no preview; a hovering tip is *asking*, and this is the
answer. The hit radius is the petal's own, not the 44pt tap target: a tap must be
forgiving because a fingertip is 10mm and lands blind; a hover is neither.

The control buttons take the system's `.hoverEffect()`, inert with no pointer.

## 5. Keyboard parity

`MacBoardKeys` moved out of `MacUI.swift`'s `#if os(macOS)` whole, as
`Sources/App/BoardKeys.swift`, compiled for both. Keyboard parity is mostly the
deletion of a platform fence — a second table would drift, and the drift would be
invisible until someone played the same board on both.

An iPad with a Magic Keyboard now has arrows, 1–9, ⇧1–9 for notes, `P` for sticky
pencil, `0`/⌫ to erase, Space to highlight, Tab/⇧Tab for the next empty cell, Esc,
plus ⌘Z and ⌘, on the control bar. ⌘-chords fall through untouched.

## 6. Apple Pencil — the one new input concept

**The Pencil writes notes. That is the whole grammar.**

A full Pencil vocabulary was available and refused: write-to-place,
scribble-to-erase, double-tap-to-switch are three more concepts and the craft
charter allows one per release. What ships falls out of a rule the app already
has — `NineGame.togglePencil` *toggles*, so writing a 4 into a cell that already
notes a 4 takes it away. **Erase needs no gesture, no mode and no glyph**, and it
reads the same as the rose's dashed-rim petal. A Pencil *tap* is left alone and
blooms the rose like any other tap.

Placed digits are never inked. Your hand is what *tentative* looks like in this
app and the typeface is what *committed* looks like; inking an entry would erase
that distinction to make a nicer screenshot.

### 6.1 Recognition is a pure function

`Sources/Shared/Handwriting.swift` — $P point-cloud matching against authored
templates. Deterministic, ~150 lines, no training data, the same answer on every
device forever. A model would be neither Linux-testable nor stable across OS
versions, which is precisely the property `GoldenCorpusTests` exists to forbid.

One deviation from stock $P: scale **uniformly** by the larger dimension rather
than to a non-uniform unit box, which would collapse a `1` — a vertical line of
zero width — into a degenerate cloud.

**Templates are authored and stay authored.** Feeding accepted glyphs back in is
the obvious next move and it is a trap: the day the matcher reads your 4 as a 9,
that 4-shape becomes the 9 template and every subsequent 4 reads as a 9 more
confidently. A recognizer that degrades in the direction of its own mistakes is
worse than one that never learns.

### 6.2 The bar is set for safety, and the cost is named

Measured on 45 synthesized hands and five deliberately degraded ones: garbage (a
dash, a box, a scribble, a cross, a circle) tops out at **0.033**; ordinary hands
read correctly at **0.58** and up; the best *wrong* reading is **0.391**; the
worst *right* reading of a badly-formed hand is **0.303**.

Those last two overlap, so no bar keeps every right answer and drops every wrong
one. **0.45** sits above the wrong answers and pays for it in refused right ones.
A mark appearing in a cell the player did not mean is the worst failure this
feature has; a stroke that fades and has to be written again is the mildest.

A **margin** bar (best minus runner-up) was written first and deleted: across the
whole corpus every reading that clears the score bar is already correct, so a
second bar could only ever take a right answer away.
`testTheMarginBarWouldHaveNothingLeftToReject` fails the day that stops being
true.

Every refusal is silent. A message about handwriting, on a board someone is
thinking over, fails the idle-pixel test on its own.

### 6.3 The specimen: one glyph per digit, not one per mark

Storing the ink of every note is per-board state, which `EXECUTING-A-PRD.md` §2
makes expensive and dangerous. A specimen is a property of the **player**:
**773 bytes** for all nine, its own cloud-synced top-level blob (`nine.hand`),
no schema change to any board.

It is also the better product. Every pencil mark renders in your hand —
*including the ones you place with the rose, on the phone, with no Pencil in the
room* — so the board looks like one person wrote it rather than like nine
unrelated scrawls.

**Last confident stroke wins.** First-wins would enshrine the one bad 4 you wrote
while the pen skipped, with no way back short of a settings row nobody should
have to find. Adoption uses a stricter bar (0.60) than placement: a mark is
recoverable by writing it again, a specimen is worn by every future note.

## 7. What was deliberately not done

Recorded with reasons in DEVIATIONS; the headline three:

- **No Apple Pencil has ever written a digit into Nine.** There is no Pencil in a
  simulator. The recognizer is measured only against synthesized strokes,
  constructed differently from the templates. The same class of standing
  deferral as PRD-20's "no human has read the nine languages".
- **No Mac rail.** The layout function is shared and the Mac would take it
  cheaply, but `MacUI` has no drawer, no first run and cannot be launched locally
  on an iCloud-signed-in host (PRD-20's standing gap). The Mac's answer to a
  second pane is a window, which is PRD-33's.
- **No handedness preference.** Left-handed players get the worse half of the
  controls-lead/stats-trail decision. A handedness row is a settings row, and the
  covenant makes those expensive.
