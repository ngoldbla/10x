# CRITERIA — the rubric every critic reads first

This is the shared instrument. Every critique in `bundles/*/CRITIQUE.md` is
written against *these* checks, in this order, so that fifteen bundles written by
different readers can be compared, ranked and merged into one design language.

**The audit's stance.** Nine is not a bad app being judged by a hostile reader.
It is a *technically excellent* app — a proof-checked engine, nine localizations,
contrast measured off composited glass rather than computed from constants,
accessibility trees pinned as baselines — whose visual language has accreted
across ~35 PRDs and now shows it. The interesting findings are almost never
"this is broken". They are **"this screen is the sum of four correct decisions
made at four different times, and nothing decided what it is *about*."**

So the bar is not "does it work" or even "is it pretty". The bar is:

> Would this frame, taken at a random moment, survive being the App Store
> screenshot? And would a jury that has seen four hundred beautiful apps this
> year remember it tomorrow?

---

## 0. How to write a finding

Every finding gets:

| Field | Rule |
|---|---|
| **ID** | `F-B{bb}-{nn}` — e.g. `F-B05-03`. Unique across the audit. |
| **Severity** | P0 / P1 / P2 — defined below. |
| **Shot IDs** | At least one, always. A finding with no shot is an opinion. |
| **Claim** | One sentence. What is wrong, stated as a fact about the picture. |
| **Evidence** | What is *literally visible*. Counts, positions, relative sizes. |
| **Why it matters** | Which law it violates (§1–§6 below) or which value it costs. |
| **Direction** | What to do instead — a *direction*, not a patch. |

**Severity:**

- **P0 — the screenshot test fails.** This frame cannot be shown to a stranger.
  It reads as unfinished, broken, illegible, or accidentally empty. Also: any
  accessibility floor breached (contrast, hit target, motion, Reduce
  Transparency), because those are not taste.
- **P1 — the frame is defensible but not distinctive.** It looks like a competent
  app built from system defaults. It would not be *remembered*. Most findings
  land here, and this is the level the redesign actually has to beat.
- **P2 — a refinement.** Correct in kind, off by a degree: a spacing rung, a
  weight, a corner radius, an alignment.

**Never write a finding you cannot see in a shot.** If you believe something is
wrong but the evidence is not in the picture, write it in the bundle's
"Unverified suspicions" section instead, flagged as such. The capstone is allowed
to use those; a finding is not.

**Write down what works, too, and be specific.** A critique that is only
negative is useless for synthesis, because the design language has to know what
to *keep*. Every bundle names at least one thing worth protecting.

---

## 1. The charter — the app's own five rules

From `README.md` § "Art direction: Pixels under glass". These are the app's
promises to itself, so a violation is not a matter of taste — it is a broken
contract. Test each shot against all five.

### 1.1 Content is full-bleed and edge-to-edge
> *"The board owns the screen. No letterboxing, no persistent nav bars, no sidebars."*

- **Check:** Does the board (or the screen's primary object) reach the edges, or
  is it a card floating in a margin?
- **Check:** Is there a persistent bar, rail or sidebar that never goes away?
- **Measure:** `Rhythm.maxEmptyFraction = 0.28` (`nine/Sources/App/DesignTokens.swift`)
  — **no more than 28% of a screen's area may be bare ground.** Ground *behind*
  glass does not count as bare; ground with nothing over it does. Estimate the
  fraction and say so. This rule exists because the iPad frames passed the linear
  "no gap over 40pt" rule while measuring 37–50% empty by area.

### 1.2 Chrome is Liquid Glass, floating, and transient
> *"Controls are small glass islands that appear on touch and recede after ~3s of stillness. The default state of every screen is zero visible UI."*

- **Check:** In a resting frame, how many chrome elements are visible? The
  charter's answer is **zero**. Count them.
- **Check:** Is a control a *small floating island*, or has it become a docked
  bar, a full-width row, a permanent toolbar?
- **Note:** Several screens have legitimately traded this away for usability
  (the iOS keypad, the Mac menu bar). Say when the trade is *right* and when it
  was made by accident.

### 1.3 Retro content, modern glass
> *"The pixel aesthetic lives in the content layer only. The interface layer is pure tvOS 26 / iOS 26. Never pixel-art buttons."*

- **Check:** Is the retro/pixel character actually *present* in the content, or
  has the board become a plain modern grid with no point of view?
- **Check (the inverse, and the more likely failure):** has any pixel/retro
  styling leaked into chrome?
- **The harder question:** the rule says where the personality lives. Does the
  app actually *have* one there, or is the rule protecting an empty room?

### 1.4 Motion is slow and physical
> *"Crossfades ≥ 2s in ambient contexts, spring responses < 200ms on focus. Nothing blinks. Nothing bounces twice."*

- Tokens: `CouchMotion.couchFast` = `spring(response: 0.18, dampingFraction: 0.86)`,
  `couchAmbient` = `spring(response: 2.4, dampingFraction: 1.0)`
  (`couchkit/Sources/CouchKit/CouchUI.swift`).
- **Check (B14 and frame strips):** Does a transition read as *one physical
  object moving*, or as two states cross-dissolving? Is anything easing linearly?
- **Check:** Is there any motion whose only job is decoration?

### 1.5 Dark-first
> *"Backgrounds are true black or deep derived tones; glass picks up content color via vibrancy. Light mode exists on iOS and macOS, not on TV."*

- **Check:** Does the dark appearance look *authored* and the light appearance
  look *derived*? Or the reverse — which would be a finding.
- **Check:** Is glass actually picking up content colour, or is every pane the
  same neutral grey regardless of what is behind it?

---

## 2. The app's own numeric laws

Unlike §1, these are exact. A violation is arithmetic, not opinion. All from
`nine/Sources/App/DesignTokens.swift` unless noted.

### 2.1 The elevation ladder (a **law**, per the source)
```
ground  <  panel  <  track  <  card  <  data
```
- **Check:** Is a container brighter than the data inside it? (The recorded
  historical defect: an *empty* heat cell measured brighter than the filled stat
  tiles — "the one square on the screen with no data in it was the brightest
  object in the sheet".)
- **Check:** Do seven ranks of importance share one elevation? (The recorded
  iPhone-shelf defect: Today, Continue, three difficulty tiles and two channels
  were all the same ~4% white fill with the same 1pt hairline.)
- **Check:** Are chrome and content at the same altitude?

### 2.2 Never two materials in a stack
`CouchGlass.swift`'s ladder: L1 `couchGlassOverContent` · L1½ `couchGlassBar` ·
L2 `couchGlass` · L3 `couchGlassTinted` · L4 `couchInset` (`.identity` — shape
and tint, **no second lens**).
- **Check:** Glass inside glass. It reads as one murkier pane, and it is the
  documented cause of twelve sites measuring 1.03:1 against their own background.
- **Check:** Two stroked siblings whose 1pt rims touch — `NineLayout.controlGap = 12`
  is the floor. Two tangent circles "read as a Venn diagram rather than as two
  controls".

### 2.3 Spacing, corners, rails
- `Space`: 2 / 4 / 8 / 12 / 16 / 20 / 28 / 40 / 56. Every gap should be a rung.
- `Radius`: 8 chip / 12 tile / 16 control / 22 card / 28 sheet / 40 hero.
  Nested shapes must use `Radius.inner(outer, inset:)` to stay concentric —
  same radius nested inside itself looks visibly too round.
- `NineLayout.gutter(for:)`: 16 (<420pt) / 20 (<760) / 28 (default). **A screen
  resolves the gutter once and every full-width element uses that value.** The
  recorded defect: two stacked slabs of the same material starting at x=32px and
  x=40px — a 4pt jog between two things that are obviously one object.
- `NineLayout.readable = 560` — the widest a single column of chrome may grow.
  Past it, add a *second column*, never stretch.
- `Rhythm.maxDeadBand = 40` — the largest fixed run of empty ground between two
  elements, unless it is a flexible spacer doing deliberate compositional work.
- `Rhythm.cluster = 16` — exactly one gap of this size inside a docked cluster.

### 2.4 Ink and hit targets
- `Hit.min = 44`, **never** multiplied by `CouchScale.chrome`. "A floor that
  scales is not a floor. A finger is the same size on every screen."
- `Ink.graphicalFloor = 3.0`, `Ink.textFloor = 4.5` (WCAG 1.4.11 / 1.4.3).
- **The stated rule:** *"A glyph that is a control's only content is `Ink.glyph`.
  Never `.secondary`, never an opacity."* Dim the container, not the symbol.
  "A control you cannot see is not a quiet control."

### 2.5 Board typography
`BoardType`: entry / given / ghost all **0.66 × cell** (differ by weight and
tone, never by size — "two sizes in one grid is what makes a board look
ransom-noted"); note / noteGhost / cageSum 0.22; `notePitch` 0.33.
- **Check:** do all five surfaces that draw a board (game board, shelf
  mini-boards, fingerprint, share card, widget) read as *the same object*?

---

## 3. Apple platform conformance — OS 26 Liquid Glass, OS 27 forward

Read `research/OS27-NOTES.md` before writing this section of a critique, and cite
it rather than your own recollection. Where the research is silent, say so.

- **Material honesty.** Glass should sample and refract what is behind it. A
  pane that would look identical over anything is not glass — it is a grey
  rectangle with a blur budget. (Recorded: an iPhone Preferences sheet measured
  RGB (41,42,43) at three points 1300pt apart, over a board carrying
  full-brightness blue digits.)
- **Glass is for chrome, not for content.** Everything is not glass. A screen
  where the material is applied to the primary object has nothing left to float.
- **Concentricity.** Nested rounded shapes share a centre of curvature.
- **Standard components where they are standard.** A system sheet, a system
  toolbar, a system list should look like one — deviating costs credibility and
  buys nothing unless the deviation *is* the design.
- **Per-platform idiom (weight this heavily):**
  - **tvOS** — focus is the entire interaction model. Focus must be unmistakable
    at 10 feet. Type is huge. Nothing is tappable; everything is focusable.
  - **iOS/iPadOS** — thumb reach, safe areas, sheet detents, Dynamic Type.
  - **iPadOS** — the pointer, the keyboard, multi-column. A stretched phone
    layout is the classic failure and this repo has already recorded it.
  - **macOS** — the menu bar is the primary interface. Windows resize; keyboard
    is first-class; density is higher than iOS and *should* be.
  - **watchOS** — glanceable in under two seconds. The Crown is a real input.
- **Accessibility as design, not as compliance:** Dynamic Type, Reduce
  Transparency (`CouchGlass` claims every rung honours it — check the evidence),
  Reduce Motion, Increase Contrast, VoiceOver, colourblind separability. The
  palette is already colourblind-engineered — verify it *reads* that way.

---

## 4. The ADA lenses

Read `research/ADA-NOTES.md` first and cite it. Judge each bundle through the
categories it could plausibly compete in:

- **Delight and Fun** — is there a moment here a player would *show someone*? An
  app can be flawless and have none.
- **Interaction** — is the core gesture (the flick-rose) genuinely better than
  the obvious alternative (a keypad), and does the design *make the case* for it?
- **Visuals and Graphics** — does the app have a visual idea, or a visual
  *style*? A style is a set of choices; an idea is a single choice everything
  else follows from.
- **Inclusivity** — does accessibility work show up as *design*, or only as
  conformance in a test harness?
- **Innovation** — what does this app do that no other sudoku app does, and is
  that visible in a screenshot?

---

## 5. Parsimony — the section most likely to produce the real findings

The brief that opened this audit was that the app is **overwrought** and its UX
**basic**. Those two words go together more often than they look: an interface
gets busy precisely when nobody decided what it was for, so everything stays.

Test every screen:

1. **Element count.** Count every distinct visible element. Say the number.
   A number over ~7 on a game screen is a finding on its own.
2. **One idea per surface.** Name, in one sentence, what this screen is *about*.
   If the sentence needs an "and", that is the finding.
3. **Contrast of importance.** Rank the visible elements by how much they matter.
   Then rank them by how much visual weight they *have*. Where the two orders
   disagree, that is a finding. (This is the single most productive check in this
   document — run it on every screen.)
4. **The removal test.** For each element: what breaks if it is deleted? "Nothing
   visible" is a finding. Be ruthless — this is where the kill list comes from.
5. **The label test.** Every text label: does it earn its pixels, or is it
   narrating something the picture already says?
6. **Decoration audit.** Anything present only to fill space, or because the
   space looked empty. Filling a void is not the same as composing.

---

## 6. Cross-platform coherence (B15, but note it everywhere)

- Is this recognisably **the same app** on five surfaces — or five apps that
  share an engine?
- Which surface is the **canonical** expression? (The README says tvOS is the
  original. Is that still true in the pictures?)
- What is the **one visual constant** that identifies Nine at a glance from any
  of the five? If you cannot name it, that is the audit's most important finding.
- Where a platform diverges: is the divergence *earned by the platform's idiom*,
  or is it drift?

---

## 7. What a good critique reads like

> **F-B05-02 · P1 · shots `B05-S03_iphone-game-rest_dark`, `B05-S04_iphone-game-rest_light`**
>
> **Claim.** The game screen has three competing horizontal bands and no clear
> primary object.
>
> **Evidence.** Counting from the top: status bar, a header row carrying
> difficulty + clock + mistake count (3 elements), the board, a 9-key digit pad,
> a 4-icon tool row. Eleven distinct interactive or informational elements. The
> board occupies roughly 41% of the screen height; the chrome occupies ~34%; the
> remainder is two margins of roughly equal weight.
>
> **Why it matters.** Charter rule 1 says the board owns the screen and rule 2
> says the resting state is zero visible UI; this frame shows neither. §5.3: the
> board is the most important element and has roughly the same visual weight as
> the pad. The pad's keys and the tool row's icons share one elevation, so the
> ladder in §2.1 is flat across two functionally different clusters.
>
> **Direction.** Decide whether this screen is a *board* with optional tools or a
> *workstation*. If a board: the pad recedes to a summoned surface and the board
> takes the freed height. If a workstation: the pad earns permanence by becoming
> visibly a different kind of object from the board — different elevation,
> different material rung, docked to the edge rather than floating near it.

Note what that does: it counts, it measures, it cites the app's own law by
number, it names the *decision* that was never made, and its direction is a fork
rather than a pixel patch.

---

## 8. Traps for the critic

- **Do not critique the fixture.** The board is frozen
  (`nine/Tests/AXBaselines/fixture.nine.library.json`) and the clock is pinned to
  9:41 so shots are comparable. The *particular* puzzle and the particular time
  are harness artifacts. The *typography* of the digits is fair game.
- **Do not mistake a seeded state for a design decision.** The audit seeds tips
  as spent and first-run as seen, so those surfaces are captured deliberately
  rather than by luck.
- **Simulator caveats.** Liquid Glass renders differently in the simulator than
  on device; the specular highlight in particular is weaker. Judge composition,
  hierarchy, spacing and colour confidently. Be more careful claiming a material
  "looks flat" — check whether anything behind it could have been sampled at all.
- **Some surfaces are legitimately dense.** Preferences is a settings sheet, and
  a settings sheet is a list. Do not demand full-bleed drama from it; demand that
  it be a *beautiful list*.
- **The app is dark-first by charter.** A light-mode shot that looks less
  resolved than its dark twin is a finding, but a *small* one — unless light is
  where the platform's users actually live (macOS).
