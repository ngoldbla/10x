# B03 — tvOS game screen · CRITIQUE

**Shots covered:** `B03-S01` (more to follow — tvOS capture is an exclusive lane)
**Surface:** tv
**Critic:** main agent (crown bundle)

---

## 1. What this bundle is

The tvOS game screen at rest: a mid-game board on the frozen fixture, seeded
quiet (tips spent, first run seen), photographed on a 4K Apple TV simulator at
3840×2160. This is **the original Nine** — the README says so — and the surface
every other one was derived from. It is therefore the bundle that decides whether
Nine still *has* a canonical expression.

---

## 2. Shot-by-shot inventory

### `B03-S01_tv-game-rest_dark`

**What is on screen**, in the order the eye finds it:

1. A board card, near-black, centred horizontally, filling most of the vertical.
2. A glass timer pill reading `0:27`, top-left — sitting **inside** the board's
   own top-left cell region.
3. One cell with a blue focus ring (row 5, col 5 area).
4. One cell with a red rim and a red underlined `7` — the error mark.
5. Pencil marks (2, 5, 9) in the row-2 col-1 cell.
6. A hint bar along the bottom: "Click a cell for digits · Hold ▶ for settings" —
   **drawn across the board's bottom row**, over the cells holding 7, 1 and 4.
7. A graded ground, lit from the upper right, visible in a wide band left and
   right of the board.

**Element count:** 5 distinct chrome/informational elements over one content
object. Low, and that is correct for this surface.

**This screen is about:** *solving this board.* No "and". The one-idea test
passes — which is exactly why the failures below are so costly: this is the
screen with the least excuse for them.

**Weight vs. importance.** Importance: the board, the focus, the error, the
clock, the hint. Visual weight: the board, the timer pill (bright glass, high
contrast, top-left — a strong position), the focus ring, the error, the hint. The
disagreement is the **timer**, which outranks the focus ring optically while
being the least important thing on the screen; and the **hint bar**, which has
almost no weight at all and yet is the only instruction a first-time viewer gets.

**Bare ground: 58.9%** (measured — board card 1792×1901 in 3840×2160).

---

## 3. What works — protect this

- **The ground is genuinely lit, not flat.** Luminance spans L=15 → L=60 across
  the canvas, and the corners differ measurably (top-left RGB (42,43,46) vs
  top-right (60,59,59)). `VoidBackground` is doing real work: this is a *field*,
  not a black rectangle, and it is what gives the glass anything to refract.
  **This is the single best-executed thing in the bundle.**
- **The board's type is right.** Givens and entries are the same size and differ
  by weight and tone, exactly as `BoardType` specifies. Nothing looks
  ransom-noted. The blue entries read as "mine" against the cream givens without
  a legend.
- **The focus ring clears its floors** — 5.71:1 against the cell it fills, 3.37:1
  against the neighbouring board. On the platform where focus *is* the interaction
  model, it is unmistakable.
- **The error mark is doubly encoded** — a red rim *and* a red underline, so it
  does not rely on colour alone.

---

## 4. Findings

### F-B03-01 · P0 · shot `B03-S01`

**Claim.** The hint bar is illegible and is drawn on top of the board.

**Evidence.** Measured: text RGB (60,61,63) on fill RGB (19,19,22) —
**1.71:1**. The app's own `Ink.textFloor` is 4.5 and WCAG 1.4.3 requires the
same. It is also positioned across the board's bottom row, so the strings "Click
a cell for digits · Hold ▶ for settings" and the cells containing 7, 1 and 4
occupy the same pixels. Both are degraded.

**Why it matters.** Two laws at once. `Ink.textFloor` (§2.4) is breached by a
factor of 2.6× — and this is on tvOS, the platform viewed from ten feet, where a
contrast failure is not a near-miss but total. And charter rule 1 (§1.1) says the
board owns the screen: chrome inside the content is the one placement the art
direction forbids outright. Apple's own current HIG says the same thing in
different words — *"Don't use Liquid Glass in the content layer… it can result in
unnecessary complexity and a confusing visual hierarchy"* (`research/OS27-NOTES.md`).

**Direction.** The hint is onboarding text with no expiry. Either it recedes like
every other piece of chrome in this app (it is the only element on screen that
apparently never does), or it moves out of the board's bounds into the enormous
ground either side — where there is 26.7% of the screen width doing nothing. If
it stays, it must clear 4.5:1, which means a real glass rung under it rather than
a near-transparent wash.

### F-B03-02 · P0 · shot `B03-S01`

**Claim.** The board is inset into a narrow central column, leaving 58.9% of the
screen empty — on the largest, most distant display the app runs on.

**Evidence.** Board card 1792×1901 px in a 3840×2160 canvas. Left margin 1024 px
(26.7%), right margin 1024 px (26.7%), top 184 px (8.5%), bottom 75 px (3.5%).
tvOS's overscan-safe inset is 5% = 192 px; **the side margins are 5.3× that**.
The board is also not square (aspect 0.943) and not optically centred (top margin
is 2.5× the bottom).

**Why it matters.** `Rhythm.maxEmptyFraction` = 0.28 and this is 0.589 — more
than double the app's own ceiling, and the worst figure of any screen measured so
far except the iPad shelf. Charter rule 1 says "content is full-bleed and
edge-to-edge… the board owns the screen"; here the board owns the middle half.
The vertical asymmetry additionally reads as a mistake rather than a composition.

**Direction.** This is the screen with the most obvious spare resource in the
whole app: ~2000 px of horizontal ground. Three honest options, and the choice is
a design decision rather than a patch — (a) **grow the board** until the margins
are the overscan inset plus one `Space` rung, which makes the digits enormous and
the couch-distance reading trivial; (b) **use the flanks** — put the clock, the
error count, the remaining-digit tally out there as a quiet left rail, which is
what the space is shaped for; (c) **keep the board this size and make the ground
the subject** — but then the ground has to earn it, and today it is a gradient
rather than a composition. Do not do (c) by accident, which is what is happening
now.

### F-B03-03 · P1 · shot `B03-S01`

**Claim.** The timer pill is placed inside the board's top-left corner, where it
covers the content and claims more visual weight than any control on screen.

**Evidence.** The glass pill sits within the board card's bounds, overlapping the
region of row 1. Measured 6.42:1 — the highest-contrast small element in the
frame, brighter than the focus ring.

**Why it matters.** Same content-layer intrusion as F-B03-01 (§1.1), and a
contrast-of-importance inversion (§5.3): the least consequential fact on the
screen — an elapsed clock, which `NinePrefs.showTimer`'s own docstring calls "the
least anxious thing that band can hold" — is optically the loudest. Note also
that Apple's 2026 ADA citations twice praised the *absence* of timers ("no timers
but lots of smiles"); a clock that is both present and prominent is arguing
against the calm this app otherwise achieves.

**Direction.** Move it into the ground the board is already leaving empty, at
`Ink.secondary` weight. It is reference information, not a control.

### F-B03-04 · P2 · shot `B03-S01`

**Claim.** The board card is not square and not optically centred.

**Evidence.** 1792×1901 px = aspect 0.943; top margin 184 px vs bottom 75 px.

**Why it matters.** A sudoku grid is nine equal squares by nine; a container that
is 6% taller than it is wide either stretches the cells or leaves an unexplained
band inside the card. Neither is visible at a glance, which is what makes it a
P2 — but on the canonical surface it is the kind of thing that separates
"carefully made" from "nearly right".

**Direction.** Square the card, then centre it optically (slightly above
geometric centre) rather than arithmetically.

---

## 5. Unverified suspicions

- **The hint bar may be transient and I photographed it inside its window.** The
  seeded state spends the tip budget, but this bar is not a tip. If it *is*
  permanent, F-B03-01 is understated; if it fades after a few seconds, the
  contrast failure still stands but the content-layer intrusion is less severe.
  **Settles it:** a capture 10 s after launch with no input.
- **Liquid Glass renders weaker in the simulator than on device**, particularly
  the specular highlight. The timer pill's material may read as more articulate
  on real hardware. The *contrast* numbers are unaffected; the judgement "the
  glass looks thin" is deliberately not made here.
- **tvOS glass is focus-driven and hardware-gated** (pre-2nd-gen Apple TV 4K gets
  no glass at all — `research/OS27-NOTES.md`). Whether this screen degrades
  gracefully there is not testable in this simulator.

---

## 6. Cross-references

- **F-B03-02 is the same defect as the iPad shelf's void** — a composition that
  ignores the canvas it was given. On tvOS it is 58.9%; on the iPad shelf 55.5%.
  Two platforms, one habit: the phone layout is the design, and the larger
  canvases inherit it with margins.
- **F-B03-01 and F-B03-03 are the same defect twice** — chrome placed in the
  content layer while the interface layer sits empty.
- **tvOS is the platform that best honours the charter, and this matters for the
  capstone.** Measured resting-state element counts: **tvOS 5, iPhone 11.** And
  the recede test (`F-B05-05`) shows iOS and iPadOS chrome is pixel-identical
  after 15 s of stillness, while this tvOS frame is already close to "zero visible
  UI" — its only persistent chrome is the timer pill and the hint bar, and both
  are findings above. The README's rule 2 reads like a rule written **for a
  focus-driven surface** and never re-derived for touch. Whether the redesign
  keeps it for touch is the single largest open question in the audit.

---

## 7. One-paragraph verdict

A jury seeing only this frame would say: *this is a well-made sudoku board that
has not been designed for a television.* The type is right, the focus is
unmistakable, the ground is genuinely lit, and the restraint is real — five
elements, one idea. But it is a phone composition enlarged: the board floats in a
central column with a quarter of the screen blank on either side, the only
instruction on screen is unreadable at 1.71:1, and the two pieces of chrome that
*are* visible are both sitting on top of the content while an acre of empty
ground goes unused. Nothing here is broken. What is missing is the decision about
what a Nine board looks like on a wall-sized display ten feet away — and that is a
decision, not a defect, which is why this bundle's directions are forks rather
than fixes.
