# B01 — Identity: icons, top shelf, launch · CRITIQUE

**Shots covered:** `B01-S01`–`S12` (12 assets, copied from `Assets.xcassets`)
**Surface:** asset
**Critic:** main agent

---

## 1. What this bundle is

Every piece of Nine's identity that ships as a flat asset: four iOS icon variants
(Original, Ember, Tide, Mono), the macOS icon, the watchOS icon, two top-shelf
images, the launch image, and the three layers of the tvOS parallax icon stack.

These are the only surfaces a person sees **before** the app opens, and the only
ones that must work at 40 px and at 1024 px with the same mark.

---

## 2. Shot-by-shot inventory

### The mark itself (`B01-S01`, and every other icon)

**What is on screen.** A 3×3 grid of nine squares on a near-black,
blue-violet-graded ground carrying a faint dotted texture. Eight squares are pale
lavender; the **centre square is coral**. Generous, even gaps; hard corners on
the squares; no numerals anywhere.

**Element count: 2** — the grid of nine, and the ground. This is the most
disciplined thing in the entire audit.

**This screen is about:** *nine, with one of them different.* No "and".

**Weight vs. importance.** In perfect agreement: the coral square is the single
most important pixel and it is the only saturated colour in the frame.

### Variants (`B01-S02` Ember, `B01-S03` Tide, `B01-S04` Mono, `B01-S05` macOS, `B01-S06` watchOS)

Ember and Tide re-ground the same mark in warm brown and deep teal. macOS is the
same mark inside the platform's rounded-square plate with correct margins. watchOS
is identical to the iOS Original. **Mono replaces the coral centre with a mid-grey.**

### Top shelf (`B01-S07` wide 4640×1440, `B01-S08`)

The same nine-square mark, centred, at roughly 1/5 the frame width, on the same
graded ground extended to a 3.2:1 letterbox.

### Launch image (`B01-S09`)

The mark again, on the same ground.

### tvOS parallax layers (`B01-S10` back, `S11` middle, `S12` front)

Back: the graded ground with its dot texture. Middle: the dot texture alone,
otherwise empty. **Front: the complete nine-square mark, coral centre included.**
The stack is correctly built — the mark floats above the field on focus.

---

## 3. What works — protect this

- **The mark is genuinely good, and it is the best-resolved design decision in
  the app.** Nine squares, one different — it says "sudoku" without a numeral,
  "one cell matters" without a caption, and it is legible at any size. It is
  distinctive in a category where almost every competitor ships a 9×9 grid with
  numbers in it. **This is the answer to `CRITERIA.md` §6's question "name the one
  visual constant that identifies Nine at a glance" — and it is the only surface
  where the answer is unambiguous.**
- **The coral centre is the whole idea.** One saturated accent against eight
  neutrals; it is the app's error colour, its focus idea and its name in one
  shape.
- **The ground is not flat.** The same graded, faintly textured field as
  `VoidBackground` — the identity and the app agree about what the dark *is*.
- **The theme-tinted variants are re-grounded, not re-tinted.** Ember and Tide
  change the field, keeping the mark constant. Correct instinct: the mark is the
  identity, the ground is the theme.

---

## 4. Findings

### F-B01-01 · P1 · shot `B01-S04`

**Claim.** The Mono icon deletes the one element that carries the idea.

**Evidence.** Every other variant has a coral centre square against eight pale
ones. Mono's centre square is a mid-grey (~L 160) against eight near-white
(~L 230). The saturated accent is gone; what remains is a 3×3 grid with one
slightly darker cell.

**Why it matters.** §5.4's removal test, applied by the app to itself and
answered wrongly. "Nine squares, one of them different" survives the loss of
colour only if the difference is re-expressed in another channel — and here the
substitute (a ~70-unit luminance step) is far weaker than the original (a full
hue shift). At icon sizes on a home screen, Mono reads as a plain grid. The other
three variants read as Nine.

**Direction.** Mono must re-encode the distinction structurally rather than
chromatically — invert the centre to the ground colour, cut it out entirely, or
give it the only stroke in the mark. A monochrome variant is a *constraint
exercise*, and this one declined the constraint.

### F-B01-02 · P2 · shots `B01-S10`, `B01-S11`, `B01-S12`

**Claim.** The tvOS parallax stack is correctly built but uses two of its three
layers, leaving the depth idea at half strength.

**Evidence.** Opened and inspected rather than inferred from file size — the
first draft of this finding said the parallax was unused, which was **wrong**.
Back (73.7 KB) carries the graded ground; **front (7.4 KB) carries the entire
nine-square mark, coral centre included**; middle (7.5 KB) is empty but for the
ground's dot texture. So the mark *does* float above the field on focus, which is
the effect working as intended.

**Why it matters.** This is a P2 and a compliment with a note. The available
gesture the stack is not using: the mark is nine *separable* squares, and it is
currently one flat plane. Splitting the eight lavender squares onto the middle
layer and leaving the coral one alone on the front would make the odd cell float
above its own siblings — the icon would then *animate the idea it depicts*
(one of nine is different) rather than merely floating a logo. Apple's ADA
citations repeatedly reward craft in exactly these unrequired places
(`research/ADA-NOTES.md`).

**Direction.** Move the eight lavender squares to the middle layer; keep the
coral square alone on the front. Two assets, no new artwork.

### F-B01-03 · P1 · shots `B01-S07`, `B01-S08`, `B01-S09`

**Claim.** The top shelf and launch images are the app icon enlarged, not
compositions in their own right.

**Evidence.** All three place the identical centred mark on the identical ground.
On the wide top shelf (4640×1440, 3.2:1) the mark occupies roughly the central
fifth; the remaining ~80% of a very large, very visible canvas is empty gradient.

**Why it matters.** The top shelf is the largest single piece of real estate any
Apple platform gives an app, and it is seen at couch distance by someone who has
not opened the app yet. Charter rule 1 (content full-bleed) and §5.6 (decoration
audit) both apply: this is not restraint, it is the icon scaled up and centred.
The same habit as F-B03-02 and the iPad shelf — a composition designed once at
one size and inherited by every larger canvas with margins.

**Direction.** The top shelf should say what the app *is*, not repeat its badge:
a board mid-solve at enormous scale, the flick rose caught open, or the nine
squares broken out of formation across the full width. It is a 3.2:1 letterbox —
one of the few canvases that genuinely wants a horizontal idea.

### F-B01-04 · P2 · shot `B01-S06`

**Claim.** The watchOS icon is byte-identical to the iOS icon.

**Evidence.** `AppIcon-watchOS.appiconset/AppIcon-1024.png` and
`AppIcon.appiconset/AppIcon-1024.png` are the same 150.4 KB file.

**Why it matters.** watchOS icons are **circular**. A square mark with generous
corner margins survives the crop, but the composition was never checked against
it — the outer squares sit closer to the circle's edge than to a rounded
rectangle's, and the mark's own square silhouette fights the circular plate.

**Direction.** Either confirm the crop deliberately (and record that it was
checked), or tighten the grid slightly for the circular mask.

---

## 5. Unverified suspicions

- **I have not seen the tvOS icon focused in situ.** The layers are confirmed by
  opening them, so the stack is known to be built correctly; what is unverified is
  how much depth the *rendered* parallax actually shows. (Deferred: the tvOS lane
  is exclusive and was contended.)
- Whether the Ember/Tide/Mono variants are reachable in the shipped build or are
  tied to a purchase/theme is not visible in these assets.

**A method note, recorded because it nearly produced a false P1.** The first
draft of F-B01-02 claimed the parallax was unused, reasoning from file sizes:
back 73.7 KB, middle 7.5 KB, front 7.4 KB, therefore "the layers that move carry
almost nothing". The inference was wrong — the front layer is small because nine
flat squares on transparency compress well, not because it is empty. **Opening
the file showed the entire mark.** No finding in this audit may rest on file
metadata where the pixels are one Read away.

---

## 6. Cross-references

- **F-B01-03 is the same habit as F-B03-02 (tvOS board inset) and the iPad shelf
  void** — one composition, inherited by larger canvases with margins added. It
  recurs on three surfaces and is a candidate for the capstone's central finding.

---

## 7. One-paragraph verdict

**The mark is the strongest thing in this audit** — nine squares with one coral,
saying "sudoku" and "one cell matters" without a numeral or a word, distinctive
in a category of grids-with-numbers-in-them. It works at every size, it agrees
with the app's own ground, and its tvOS parallax stack is correctly built. What is
weaker is everything the mark was *asked to do next*: the monochrome variant
deletes the coral and with it the idea, and the top-shelf and launch images are
the badge enlarged and centred on an 80%-empty canvas rather than compositions
about the game. So the identity is not a design problem — it is a design *asset*
that has been applied rather than developed. The capstone should start from this
mark, because it is already the answer to "what is the one thing that identifies
Nine at a glance", and no other surface in the audit answers that question at all.
