# B05 — iPhone game screen · CRITIQUE

**Shots covered:** `B05-S01`–`S04` (game and rose, light and dark)
**Surface:** iphone
**Critic:** main agent (crown bundle)

---

## 1. What this bundle is

The iPhone game screen — the surface most people will actually use — at rest and
with the flick rose open, in both appearances. iPhone 17 Pro, 402×874 pt @3×,
frozen fixture, quiet chrome.

This is where Nine's central design tension is visible: it has a **signature
gesture** (the 3×3 flick rose) and a **fallback control** (a docked digit pad),
and both are on screen at once.

---

## 2. Shot-by-shot inventory

### `B05-S01_iphone-game-rest_light` / `S02_…_dark`

**What is on screen**, top to bottom:

1. Status bar (system).
2. A header pill: back chevron · "Steady" · `0:19` · a red ⊗ with `1` · a grid
   glyph with `49`. **Five pieces of information in one control.**
3. The board card — 9×9, with row/column/box highlight bands around the selected
   cell, one red-rimmed error `7`, one cell of pencil marks.
4. A digit pad card: nine keys in a 5+4 arrangement, each with a small
   remaining-count badge.
5. A toolbar pill: five glyphs — hint (bulb), pencil, auto-notes (grid), undo,
   settings (gear).

**Element count: 11** distinct interactive or informational elements
(5 in the header, board, 9 keys read as one cluster, 5 glyphs read as one
cluster). Against `CRITERIA.md` §5.1's "over ~7 on a game screen is a finding".

**This screen is about:** *solving this board* — **and** reading your stats,
**and** choosing a digit, **and** reaching five tools. Three "and"s. §5.2 fails.

**Weight vs. importance.** Importance: board ≫ selected cell ≫ digit entry ≫
error state ≫ tools ≫ clock ≫ difficulty label. Visual weight: board (44.6%
area) → digit pad (21.2%) → toolbar (7.6%) → header (4.0%). The board wins, but
only by 2.1× over the pad, and pad + toolbar + header together (32.8%) come
within 12 points of it. **The disagreement is that the controls collectively
rival the game.**

**Bare ground: 25.7%** (hand-measured from element boxes). Inside the app's 28%
ceiling — the void the tokens were written to fix is genuinely fixed here.

### `B05-S03_iphone-rose-open_light` / `S04_…_dark`

The rose blooms over the board as a rounded 3×3 card of digits 1–9 with dished
keycaps. The board dims behind it. **The docked digit pad remains fully visible
below, still showing 1–9.**

---

## 3. What works — protect this

- **The dark appearance is markedly stronger than the light.** On dark, the board
  is a genuine near-black field, the cream digits sit on it with authority, and
  the blue entries separate cleanly. It looks authored. (Light looks derived —
  see F-B05-04.)
- **The board is the largest thing on screen**, at 44.6% of the canvas. After
  three rounds of recorded void-fixing, the game screen is no longer 39% empty.
  That fix held.
- **The remaining-count badges on the pad keys** are genuinely useful information
  in a genuinely small amount of space — the one piece of added chrome on this
  screen that earns its pixels outright.
- **Error encoding is redundant** (rim + colour + count), not colour-alone.
- **The rose's dished keycaps** are the one moment of real material character in
  the touch UI. They look like something, not like a system control.

---

## 4. Findings

### F-B05-01 · P1 · shots `B05-S03`, `B05-S04`

**Claim.** The signature gesture and its fallback are on screen simultaneously,
in near-identical form, doing the identical job.

**Evidence.** With the rose open, the frame contains a 3×3 grid of digits 1–9
(the rose) floating directly above a docked 1–9 digit pad. Both are
digit-selection controls. Both are card-shaped, glass-backed, and typeset in the
same face at similar size. The rose additionally covers the board it is being
used on.

**Why it matters.** This is a question about the app's identity, not its layout. The README
leads with "a 3×3 flick-rose for digit entry" — it is the first thing said about
Nine. A player who can already see nine keys has no reason to learn a flick, and
the rose's existence then reads as a second way to do a solved problem rather
than as *the* way. §5.4's removal test cuts both ways here: delete the pad and
the rose becomes necessary and therefore learned; delete the rose and the app
loses the thing that makes it Nine. Apple's ADA Interaction criterion is
"effortless controls **perfectly tailored to their platform**", and two parallel
controls for one action is the opposite of tailored.

**Direction.** Decide which one is the design. Three coherent answers, and the
audit's recommendation is (a): **(a)** the rose is the interaction and the pad is
an accessibility/preference alternative that is *off* by default — the rose then
has to be discoverable in one gesture, which is a real design problem worth
solving; **(b)** the pad is the interaction on touch and the rose is the *tvOS*
grammar only, honestly platform-specific; **(c)** they merge — the docked pad
*is* the rose, and tapping a cell lifts it to the cell rather than drawing a
second copy. What is not defensible is shipping both and letting the player
discover that they are the same thing.

### F-B05-02 · P1 · shots `B05-S01`, `B05-S02`

**Claim.** Four full-width elements on one screen sit on four different rails,
none of which is the rail the app's own layout code specifies.

**Evidence.** Measured left/right gutters:

| Element | L | R |
|---|---|---|
| Header pill | 21.7 pt | 22.0 pt |
| Board card | 8.0 pt | 8.3 pt |
| Digit pad | 8.3 pt | 8.7 pt |
| Toolbar pill | 55.0 pt | 55.3 pt |

`NineLayout.gutter(for: 402)` returns **16 pt**. Not one element uses it. The
spread is 8 → 55 pt, a factor of 6.9. Three of the four values are not `Space`
rungs at all.

**Why it matters.** `NineLayout`'s own docstring states the law — *"a screen
resolves `gutter(for:)` once and every full-width element on it uses that
value"* — and records that it exists because two slabs starting at x=32 and x=40
were "a 4pt jog between two things that are obviously one object". This is that
defect at 6× the magnitude, on the app's most-used screen. The visible symptom is
that the four bands read as four unrelated objects that happen to be stacked,
rather than as one composition.

**Direction.** Resolve one gutter per screen and use it. If the toolbar is
*meant* to be a narrow floating pill rather than a full-width element, then it is
not on the rail system at all and should be centred on a stated width — but then
the header, which is also a pill, should follow the same rule, and today it does
not.

### F-B05-03 · P1 · shots `B05-S01`, `B05-S02`

**Claim.** The header pill carries five unrelated facts in one control and is the
screen's least considered element.

**Evidence.** Back chevron, difficulty name, elapsed time, error count with a red
⊗, and a remaining-cells count with a grid glyph — in a single 29 pt-tall
capsule, 358 pt wide, at 21.7 pt gutters.

**Why it matters.** §5.2 (one idea per surface) and §5.3 (weight vs. importance).
A navigation control, a static label, a live clock, an error tally and a progress
tally are five different *kinds* of thing — one is an action, two are state, two
are progress — flattened into one visual object of uniform weight. The player who
wants to know "how am I doing" and the player who wants to leave are served by
the same 4%-area strip.

**Direction.** Split by kind, not by convenience. Navigation is chrome and should
recede with the rest (charter rule 2). Progress is *content* about the board and
belongs with it. The clock is reference and can live at `Ink.secondary` weight or
be off entirely — note the app already exposes that preference and Apple's 2026
ADA citations twice praised the absence of timers.

### F-B05-04 · P2 · shots `B05-S01` vs `B05-S02`

**Claim.** The light appearance reads as a desaturated copy of the dark one
rather than as its own design.

**Evidence.** In light, the board card, the pad card, the page and the toolbar
all sit within a narrow luminance band; the board's own fill is barely
distinguishable from the page it floats on. In dark, the same four surfaces are
clearly separated. (Quantified on the shelf, where the effect is worst — cards
measure **1.04–1.13:1** against the page in light versus 1.29–1.40:1 in dark.)

**Why it matters.** Charter rule 5 is "dark-first", so light being second is
*by design* — this is P2, not P1, and `CRITERIA.md` §8 says so. But
`Elevation`'s light ladder is explicitly not the dark one inverted ("on paper you
may lift until you hit white, and then you must recess"), and the light frames
are not using that rule; they are using the dark amounts on a light ground.

**Direction.** Light needs its own elevation amounts, and probably its own
decision about what the ground *is*. A near-white page with near-white cards on
it is the one configuration where the material has nothing to do.

---

### F-B05-05 · P0 · shots `B05-S05`–`S08` (recede series)

**Claim.** The chrome never recedes. The app's headline art-direction rule does
not hold on this surface.

**Evidence.** The same screen photographed at 1 s, 4 s, 8 s and 15 s after launch
with **no input at all**. Comparing t=1 s to t=15 s, per-region maximum pixel
delta out of 255:

| Region | Max delta | Mean delta |
|---|---|---|
| Header pill | 158 | 6.73 |
| Digit pad | **2** | 0.07 |
| Toolbar | **2** | 0.00 |

The only difference anywhere in the frame is in rows 0–423 — the clock advancing
0:17 → 0:31. The pad and toolbar are pixel-identical across fourteen seconds of
stillness.

**Why it matters.** README rule 2 states: *"Controls are small glass islands that
appear on touch and recede after ~3s of stillness. The default state of every
screen is zero visible UI."* The measured resting state is **eleven visible
elements**. This is P0 not because the screen is ugly but because the app's most
load-bearing design claim is currently false on its most-used surface — and every
other finding in this bundle was written against the possibility that I had
merely photographed a transient window. I had not. This *is* the resting state.

It also explains an asymmetry worth noting: tvOS shows five elements at rest to
iOS's eleven. The rule appears to have been written for a focus-driven surface
and never re-derived for touch.

**Direction.** The app has two incompatible doctrines and ships both. Resolve it
explicitly, in one direction or the other:

- **Make the rule true.** The pad and toolbar recede; a touch anywhere brings
  them back. This is the charter's own answer and it makes the rose necessary
  (see F-B05-01), which would resolve two findings with one decision.
- **Retire the rule for touch.** A docked pad is thumb-reachable, carries
  remaining-digit counts, and never has to be re-summoned mid-solve — a real
  argument, and the same one `NinePrefs.showTimer`'s docstring makes about the
  clock ("A calm app is one that does not shout, not one that shows no state").
  If this is the answer, the README must say so, and the *composition* then has
  to earn permanence: docked chrome must look like a different **kind** of object
  from the board, not like three more cards on the same rung.

What is not defensible is the present state, where the rule is quoted in the
README, contradicted on screen, and the screen is composed as though the rule
were still coming.

---

## 5. Unverified suspicions

- Whether the rose can be summoned without the pad being present (a preference,
  a first-run choice) is not visible in these frames.
- Whether chrome recedes on **tvOS** — where a focus engine makes "recede" mean
  something different — is not yet tested. The tvOS resting frame is already much
  closer to the rule (five elements), so the answer may simply be that the rule
  was always a tvOS rule.

---

## 6. Cross-references

- **F-B05-02 (four rails) recurs on iPad** as three different right-hand gutters
  (7 / 5 / 14.5 pt) where the law says 28. Same defect, same screen family.
- **F-B05-04 (light is derived)** is measured on the shelf in B04 and is
  app-wide, not specific to the game screen.

---

## 7. One-paragraph verdict

A jury would call this **a good sudoku app and not yet a distinctive one**. The
craft is real — the board is large, the type is disciplined, the error state is
redundantly encoded, the dark appearance has genuine presence, and the void that
three prior rounds fought is gone. But the resting state — *measured*, not
assumed — is eleven elements and three ideas; the four stacked bands sit on four
different rails spanning 8 to 55 pt; the gesture the app is named for appears
alongside a keypad that does the same job; and the charter's headline promise
that chrome recedes to "zero visible UI" is contradicted by a frame that does not
change by more than 2/255 in fourteen seconds. Nine's problem on this surface is
not that anything is broken. It is that **the app is running two design doctrines
at once** — transient glass islands over a full-bleed board, and a docked
workstation with a permanent toolbar — and every band is individually defensible
because nothing on the screen has to argue against anything else.
