# PRD — Blockhead

**Status:** Draft v1 · **Thread:** `tvos/blockhead/` · **Remote-fit:** 9.5/10
**One-liner:** A nightly living-room game show where the four swipe directions are
the four answers — flick to answer, pass the remote, keep the streak.

## 1. Product thesis

Swipe-as-answer is the single best trick the Siri Remote can do: one gesture, four
choices, zero targeting, works at party speed with the remote changing hands.
Blockhead builds a nightly ritual around it — a short, gorgeous, game-show-styled
run of trivia and picture puzzles. Solo it's a streak ritual (Wordle's shape);
with people on the couch it's pass-the-remote party fuel with zero extra hardware,
zero phones, zero accounts.

Feature-limited: bundled, hand-curated packs in v1. No AI generation, no network.
The show format, the swipe feel, and the glass stage *are* the product.

## 2. Goals

- Answering must feel physically great — the flick, the card catch, the verdict.
- A full solo episode ≤ 4 minutes. A party round ≤ 90 seconds per player turn.
- Instant party: from app launch to four players playing in < 30 seconds.

## 3. Non-goals (v1)

- No AI-generated packs, no theme requests, no downloads (all packs bundled).
- No phones-as-buzzers, no SharePlay, no Game Center.
- No text entry ever — player identities are picked, not typed (see 4.3).
- No lifelines/economies/coins. Score, streak, done.

## 4. Core experience

### 4.1 The stage (home)

A full-bleed game-show stage rendered in the suite's pixels-under-glass style: a
dark hall with a slow volumetric light sweep, tonight's episode floating center as
a marquee glass slab — “**Tonight's Episode · #142 · General**” — flanked by two
smaller slabs: **Party** and **Archive** (past episodes; missed days playable but
marked, streak-honest). A `GlassChip` carries the streak flame. That's the screen.

### 4.2 The question moment (the whole game)

One question at a time, full screen:

- The prompt sits center-stage in Display type (96pt), on nothing — text floating
  over the stage void. Picture rounds put the image full-bleed behind glass-dimmed
  edges (AsciiKit `.mosaic`-treated during the countdown, sharpening to full photo
  on reveal — a built-in “enhance” drama beat).
- Four answers occupy the four compass positions as **glass slabs** (top, bottom,
  left, right), each with a faint directional chevron. The mapping *is* the layout;
  no A/B/C/D labels ever.
- A `GlassRing` timer (default 12s) hugs the center prompt.
- **Flick to answer:** the chosen slab catches the flick — it lenses, lifts, and
  locks in with a physical *clack*; the other three fall away into the void.
  Verdict beat (~600ms of theatrical hold, light sweep pauses) → the slab flares
  correct-gold or fades wrong-smoke, and the correct slab glides center.
- No click-to-answer alternative on modern remotes. The flick is the identity.
  (`capability: .fourWay` remotes get identical behavior — swipes are 4-way.)

Episode shape: 10 questions — 6 trivia, 2 picture, 2 “Odd One Out.” Same grammar
throughout; only the prompt type varies. Score = correct count + speed bonus dots.

### 4.3 Party mode (pass the remote)

- Setup screen: 2–6 player tokens, each an 8-bit avatar tile + color; swipe to a
  token, click to claim, hold to change avatar. No names, no typing — avatars and
  colors are the identity. Setup for four players: ~20 seconds.
- Rounds alternate players; a glass **handoff card** fills the screen between
  turns (“Pass to 🟣 Bandit”) — the remote physically moving *is* the game's pulse.
- Each player has an 8-bit `health-bar`-styled score meter along the bottom edge
  (the suite's one sanctioned retro-chrome exception, since it's *scoreboard
  content*, not controls). Final tally: podium of glass slabs, avatars asciified
  large, one winner light sweep. Rematch = one click.

### 4.4 Remote grammar (complete)

| Gesture | Effect |
|---|---|
| Swipe ↑↓←→ (question) | Answer in that direction |
| Swipe (menus) | Move focus between slabs/tokens |
| Click | Confirm / advance / rematch |
| Hold (party setup) | Cycle avatar on claimed token |
| Play/Pause | Pause episode (glass curtain drops over the stage) |
| Play/Pause long-press | Prefs sheet: timer length (8/12/20s), reduce-flash mode |
| Back | Exit to stage (episode progress saved) |

## 5. Content system

- Packs are bundled JSON, hand-curated: v1 ships **600 questions** (episodes are
  deterministic draws seeded by date — everyone gets the same nightly episode).
- Every question is validated at build time by a schema linter (exactly 4 answers,
  1 correct, length caps for 3m legibility, image rounds carry licensed/CC0 art).
  Invalid questions fail CI — a malformed question is unshippable by construction.
- Difficulty curve within an episode is fixed (warm → hard → cool-down finisher).
- **v2 hook (design now, build later):** the pack schema + linter are the contract
  an AI pack-generator must satisfy — same generator-verifier pattern as Nine.
  Voice-requested themed packs ride on this without touching the game shell.

## 6. Visual & Liquid Glass specification

- Chrome inventory: marquee slabs (home), four answer slabs, timer ring, streak
  chip, handoff card, score meters, podium, pause curtain, prefs sheet. Complete.
- The four answer slabs are the app's crown jewels: true glass over the stage
  volumetrics, content-tinted, with lensing strong enough that the light sweep
  visibly refracts through them. The lock-in animation (`couchFast`, slight
  overshoot, 60fps mandatory) is Signature Moment #1 — prototype it first.
- The verdict beat is choreographed lighting, not badges: correct = the hall
  warms gold for 1s; wrong = the hall cools and dims. The room reacts, not a label.
- Sound: the one suite app where sound leads — tick-tock ring, clack, verdict
  sting, handoff whoosh. All original chiptune-adjacent, ≤ 8 sounds total,
  mixed for TV speakers. Reduce-flash prefs also flattens audio dynamics.

## 7. tvOS native integration

- **Top Shelf:** tonight's episode state — sealed (marquee art) / in-progress /
  finished (score + streak flame). Deep-click launches straight into it.
- **Multi-user:** solo streaks and archive progress per profile, cloud-synced;
  party mode is profile-agnostic by design (guests welcome).
- **Focus engine:** slabs are real focusable elements on menu screens (system
  focus feel for free); during questions, focus is suspended — flicks are answers,
  not navigation (RemoteKit scheme swap).

## 8. Success metrics

- Solo D7 streak retention ≥ 30% of users who finish one episode.
- Party sessions ≥ 20% of weekly sessions (couch mode is real).
- Median answer input latency (flick → lock-in render) < 80ms.

## 9. Milestones

- **M1:** The question moment — one hardcoded question, four slabs, flick, lock-in,
  verdict lighting. Gate: it feels great with the sound off.
- **M2:** Episode engine, 600-question pack + linter CI, scoring, streaks, archive.
- **M3:** Party mode (tokens, handoff, meters, podium), pause curtain, prefs.
- **M4:** Top Shelf, multi-user, reduce-flash accessibility pass, App Store assets.

## 10. Open questions

- 12s default timer: right for mixed-age couches? Playtest at M2 (8/12/20 options
  exist; the default is the brand statement).
- Should the nightly episode lock after midnight (FOMO purity) or stay in the
  archive marked “late”? Currently: archive-with-mark (kinder, still streak-honest).
