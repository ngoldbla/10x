# B{bb} — {bundle name} · PROMPTS

> Copy this file, keep every heading, delete this blockquote.
>
> **Who reads this.** A fresh agent with no memory of this audit, tasked with
> producing a *mockup* (not shipping code) of one redesigned surface. It has the
> repo and it has `docs/design-audit/`. It has not seen the screenshots and it
> was not in the conversation.
>
> That means every prompt must be **self-contained**. A prompt that says "fix the
> hierarchy problem" is useless; a prompt that says "the board, the pad and the
> tool row currently share one elevation — put them on three rungs of
> `Elevation`, with the board highest" is executable.

---

## P-B{bb}-01 — {short imperative title}

**Addresses:** `F-B{bb}-03`, `F-B{bb}-07`
**Surface:** {tvOS game screen | iPhone shelf | …}
**Reference shots:** `B{bb}-S02`, `B{bb}-S05` (paths in `../../INDEX.md`)

### Context

One paragraph a stranger can act on. What this screen is, who is looking at it,
from how far away, holding what input device, and what they came here to do.
State what is wrong now in one sentence — but write the *goal*, not the
complaint.

### Laws to honor

Pin every constraint to a file so the agent can read the real thing rather than
trust this summary:

- `nine/Sources/App/DesignTokens.swift` — `Space`, `Radius`, `Elevation`
  (ladder: `ground < panel < track < card < data`), `Rhythm.maxEmptyFraction`
  (0.28), `NineLayout.gutter/readable/controlGap`, `Hit.min` (44, never scaled),
  `Ink.graphicalFloor` (3.0) / `textFloor` (4.5), `BoardType`.
- `nine/Sources/App/Theme.swift` — `ThemeChoice` (9), `AccentChoice` (10),
  `ThemeTones.surfaceHue` / `.wellHue`.
- `couchkit/Sources/CouchKit/CouchGlass.swift` — the material ladder
  L1 → L4. **Never two materials in a stack**; a card inside a panel is
  `couchInset`.
- `couchkit/Sources/CouchKit/CouchUI.swift` — `couchFast` / `couchAmbient`.
- `README.md` — the five art-direction rules.
- `docs/design-audit/DESIGN-LANGUAGE.md` — the capstone. **Where this prompt and
  the capstone disagree, the capstone wins.**

### Layout specification

Be concrete enough to build from, loose enough to leave room for design:

- What the primary object is and roughly what share of the canvas it takes.
- Where the rails are (which `NineLayout.gutter` rung).
- What is docked, what floats, what is summoned.
- Which elevation rung each surface sits on, and which material rung draws it.
- What is *removed* relative to today, and what replaces the function it served.

### States to cover

Every state the mockup must show — at minimum: at rest, engaged, and the moment
the interaction resolves. Name the appearance(s) and any theme.

- [ ] {state} — {what must be visible}

### Acceptance criteria

Testable. A reviewer must be able to say yes or no without asking the author.

- [ ] Resting frame shows ≤ {n} chrome elements.
- [ ] Bare ground ≤ 28% by area.
- [ ] No two glass materials stacked.
- [ ] Every gap is a `Space` rung; every radius a `Radius` rung.
- [ ] Every interactive target ≥ 44pt.
- [ ] Any glyph that is a control's only content is `Ink.glyph`, never secondary.
- [ ] The frame passes the screenshot test: it could ship as an App Store shot.

### Diffusion-prompt variant *(optional — include only where a visual beats prose)*

A mood/composition paragraph for an image model. Describe light, material,
palette, weight, and negative space. Name no UI controls; this is for *feel*.

> {e.g. "A single luminous grid floating in near-black, lit from a low left
> source so the glass edge catches a thin specular line; nine lavender marks and
> one coral, spaced generously; the surrounding dark is not empty but graded,
> like a photograph of a lightbox in a dim room."}

---

*(repeat per prompt — aim for 2–5 per bundle, each addressing named findings)*
