# B04 — iOS shelf (the front door) · CRITIQUE

**Shots covered:** `B04-S01`–`S06` (home, home-bottom, channel — light and dark)
**Surface:** iphone
**Critic:** main agent

---

## 1. What this bundle is

The iPhone shelf: the screen a player lands on when they are *not* resuming a
board, plus its scrolled-to-bottom state and a variant-channel page. This is the
app's front door and its whole offer — three difficulty tiers, three channels, a
resume row, a multiplayer invitation, and three utility destinations.

---

## 2. Shot-by-shot inventory

### `B04-S01_iphone-home_dark` / `B04-S02_…_light`

**What is on screen**, top to bottom:

1. Status bar.
2. Wordmark "Nine" (left), a gear in a glass circle (right).
3. A channel pager: `‹ Classic ›` with three page dots.
4. A **Continue** row — mini-board fingerprint, "Continue", "Steady · 7%", and a
   dismiss ⊗.
5. A section label "Play".
6. Three difficulty tiles — Gentle / Steady / Sharp, each with a dot-pattern
   mini-board, a name and a two-line description.
7. A **Play together** row — icon, title, two-line explanation.
8. Three utility tiles — How to play / History / Technique School.

**Element count: 13** (wordmark, gear, pager with 2 chevrons + title + dots,
Continue row, section label, 3 tiles, Play-together row, 3 utility tiles).

**This screen is about:** *starting a board* — **and** resuming one, **and**
switching variant, **and** playing with others, **and** learning, **and** looking
at records. Five "and"s. §5.2 fails hardest here of any screen in the audit.

**Weight vs. importance.** Importance: start a board ≫ resume ≫ switch channel ≫
everything else. Visual weight: the three difficulty tiles and the three utility
tiles are **the same size, the same shape and the same elevation** — a 3×2 grid of
identical cards where one row is the product and the other row is the help menu.

**Bare ground: ~38%** on light, ~55% on dark — over the app's 28% ceiling in both.

### `B04-S03_iphone-home-bottom_*`

Scrolled to the bottom; the three utility tiles are now fully visible with a
large empty band beneath them.

### `B04-S05_iphone-channel_light` (Thermo)

The channel pager moved to page 2. The three difficulty tiles re-tint to the
channel's colour (green→teal→blue), and a "How to play" explainer card appears
below with a diagram and four lines of prose. **The bottom ~35% of the screen is
empty.**

---

## 3. What works — protect this

- **The mini-board fingerprints are the best content idea in the app.** Each tile
  carries a *dot-pattern rendering of an actual board* — density encodes
  difficulty, so Gentle is visibly fuller than Sharp. It teaches the difference
  without a word, it uses the board as its own illustration, and it is unique to
  Nine. **Protect this above everything else in the bundle.**
- **The Continue row's fingerprint is the same object at the same scale** as the
  tiles', so the shelf reads as one family of marks.
- **The channel re-tint is well judged** — the whole tile set shifts hue when the
  channel changes, so "which variant am I in" is answered peripherally rather
  than by reading the pager title.
- **"Steady · 7%"** is exactly the right amount of resume information.

---

## 4. Findings

### F-B04-01 · P0 · shots `B04-S02` (light), `B04-S01` (dark)

**Claim.** In light mode the shelf's cards are effectively invisible as objects —
they clear no contrast floor against the page they sit on.

**Evidence.** Each card's interior fill measured against the page **immediately
beside it, at its own rows** — not against one global page sample, because the
page grades 43 luminance units top to bottom (see F-B04-02). This is the
comparison `Elevation.fill` itself specifies: a rung composites over "the surface
immediately behind it".

| Card | Fill | Page beside it | Ratio |
|---|---|---|---|
| **Gentle tile** | (225,223,219) | (226,223,217) | **1.001:1** |
| Continue row | (233,231,228) | (229,226,220) | 1.051:1 |
| Play together | (230,229,226) | (220,218,213) | 1.110:1 |
| How to play | (229,228,226) | (209,208,204) | 1.220:1 |
| Steady tile | (224,222,219) | (192,189,184) | 1.398:1 |
| Sharp tile | (226,225,221) | (193,191,185) | 1.407:1 |
| History tile | (229,228,226) | (179,178,175) | 1.671:1 |
| School tile | (229,228,226) | (179,178,174) | 1.675:1 |

`Ink.graphicalFloor` = **3.0** (WCAG 1.4.11, for "a graphical object, and the
boundary of any control"). **Every card is under it. The Gentle tile measures
1.001:1 — its fill and the page beside it are the same colour to within one unit
per channel.** Dark mode is no better: 1.023–1.145:1.

**Why it matters.** These are the app's primary controls — the things a player
taps to start playing — and as *shapes* they are not there at all. Only hairline
rims, drop shadows and text separate them from the page. `Ink`'s own docstring
states the principle: *"A control you cannot see is not a quiet control."*

Note that this is **worse** than a first, cruder measurement suggested (which
compared everything to one page sample and got 1.04–1.13:1 light / 1.29–1.40:1
dark). Measuring each card against its own local ground was intended to be the
fairer test; it made the finding stronger, and dark mode lost its apparent
advantage entirely.

**Direction.** The light palette needs its own elevation amounts, which
`Elevation.lightFill` already anticipates — *"on paper you may lift until you hit
white, and then you must recess"*. The cards are currently *lifting* on a page
that is already near-white, so there is nowhere to go. Either the page recedes
(a genuinely tinted ground, which every theme already defines via
`ThemeTones.surfaceHue`) or the cards recess into it.

### F-B04-02 · P1 · shots `B04-S01`, `B04-S02`

**Claim.** The elevation ladder is flat: eight cards of at least three different
ranks occupy a 7.9-luminance band.

**Evidence.** Dark mode, card interior fills: L = 23.6 (Sharp), 25.6 (Steady),
25.8 (Gentle), 28.8 (School), 29.0 (Play together), 29.4 (History), 29.9 (How to
play), 31.5 (Continue). **Spread 7.9 across eight elements.**

*A correction to an earlier draft of this finding.* It first read that every card
is *darker than the page*, from a single page sample of L=50. That comparison was
wrong: `VoidBackground` grades steeply, and sampling the page down its own left
edge gives **L=66 at the top falling to L=32 at the bottom** (spread 34.1; in
light, 247→204, spread 42.9). So the page is brighter than the cards at the top
of the screen and *darker* than them at the bottom — the ladder is not inverted,
it is **unanchored**: the same card fill reads as raised or recessed depending
purely on where it sits in the gradient.

**Why it matters.** `Elevation`'s ordering is stated in its own source as a
**law**: `ground < panel < track < card < data`. That law is expressed as fills
composited over a ground assumed constant, and this ground varies by 34 luminance
units — four times the entire card-to-card spread. So the ladder cannot be read
off the screen at all: the ranks that ought to differ (start a board, resume, help
menu) are within 8 units of each other while the ground they are judged against
moves 34. This is the defect `Elevation`'s docstring records ("Seven ranks of
importance, one elevation") — round 4 separated the fills into five *measurable*
steps, and the gradient then swallowed them.

**Direction.** Two things, and the second is the one nobody has noticed.

1. **Spend the ladder.** The three difficulty tiles are the product and should be
   unmistakably the most present objects on the screen; the three utility tiles
   are a footer and want `track`, not `card` — marks cut into the page rather than
   objects standing on it.
2. **Decide what the ladder is measured against.** A relative fill over a ground
   that moves 34 luminance units cannot express a 5-unit hierarchy. Either the
   ground stops grading behind content (grade the *field*, hold the page flat
   where cards sit), or elevation stops being a relative wash and becomes an
   absolute tone per rung. `Elevation.fill` composites "over **the surface
   immediately behind it**" — on a graded page there is no single such surface,
   and that is a gap in the token system rather than a misuse of it. **Candidate
   for a new law in the capstone.**

### F-B04-03 · P1 · shots `B04-S01`, `B04-S03`

**Claim.** The product and the help menu are rendered as the same object.

**Evidence.** Gentle / Steady / Sharp and How-to-play / History / School are both
three-across grids of equal-width rounded cards with a glyph-or-mark above a
label, at the same elevation (measured within 5 luminance units of each other),
the same radius and the same rail.

**Why it matters.** §5.3, the audit's most productive test. Ranked by importance
these two rows are not close: one is the reason the app exists, the other is a
utility drawer. Ranked by visual weight they are indistinguishable. A first-time
player sees six equal choices.

**Direction.** Make them different *kinds* of thing, not different sizes of the
same thing. The difficulty tiles carry board fingerprints and should keep them;
the utility row wants to be a text row, a footer, or a single overflow —
something that is visibly not a place to start playing.

### F-B04-04 · P1 · shot `B04-S05`

**Claim.** The channel page leaves its bottom third empty while paginating
content that would fit.

**Evidence.** On the Thermo page, content ends after the explainer card at roughly
65% of the screen height; the remaining ~35% is bare ground. Meanwhile the three
channels are reached by *turning pages* — the pager shows "1 of 3".

**Why it matters.** `Rhythm.maxEmptyFraction` = 28%, exceeded. But the more
interesting failure is architectural: the screen is simultaneously **too empty**
and **paginated**. Pagination is a device for content that does not fit; this
content does not fill what it has.

**Direction.** If three channels fit on one screen, show three channels. Note the
**iPad already does exactly this** — a segmented `Classic / Thermo / Killer`
control with everything visible — so the app has already made this decision once,
on another surface, without reconciling the two.

### F-B04-05 · P2 · shots `B04-S01`, `B04-S02`

**Claim.** "Play" is the only section label on the screen, and it labels the one
section that needs no label.

**Evidence.** A single "Play" heading sits above the difficulty tiles. The
Continue row, the Play-together row and the utility row carry no headings.

**Why it matters.** §5.5, the label test. Three tiles showing boards, named
Gentle / Steady / Sharp, under a wordmark reading "Nine", do not need to be told
they are for playing. And an app with exactly one section heading has not decided
whether it has sections.

**Direction.** Delete it, or commit to headings throughout.

---

## 5. Unverified suspicions

- Whether the shelf's chrome (the gear, the pager chevrons) recedes is untested
  here; on the game screen it does not (`F-B05-05`), so the presumption is that it
  does not here either.
- ~~The dark shelf's page ground being brighter than every card~~ — **settled and
  withdrawn.** It was a gradient artifact of one sample. Sampling down the page's
  own edge shows a 34-unit grade, which is now the substance of F-B04-02 rather
  than an inversion claim. Recorded here rather than deleted because the correction
  is the finding.

---

## 6. Cross-references

- **F-B04-01 and F-B05-04 are the same defect** — the light appearance is the
  dark one's amounts applied to a light ground. Measured on the shelf; visible on
  the game screen.
- **F-B04-04's pagination contradicts the iPad's segmented control.** Same
  content, two information architectures, no reconciliation. See the iPad
  bundle.

---

## 7. One-paragraph verdict

The shelf contains the app's single best content idea — mini-board fingerprints
that teach difficulty by density, in a category where everyone else writes
"Easy / Medium / Hard" — and then renders it at the same weight as a help menu.
Thirteen elements and five ideas compete on one screen; in light mode the cards
that carry them measure between 1.04:1 and 1.13:1 against their own page, roughly
thirty times under the app's own graphical-contrast floor, so the primary controls
are functionally invisible as shapes. Nothing here is unfinished — every element
is drawn with care. What is missing is a hierarchy: this screen knows everything
the app can do and has not decided what the app is *for*.
