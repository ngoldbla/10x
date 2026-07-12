# PRD — Cartridge

**Status:** Draft v1 · **Thread:** `cartridge/` · **Remote-fit:** 8/10 (shell 10, per-game 6–9)
**One-liner:** Channel-surf a bottomless feed of one-input micro-games — swipe
between games like changing channels, starring sprites made from your own photos.

## 1. Product thesis

The TikTok feed shape — swipe, instant payoff, endless novelty — applied to couch
games. Swiping between full-screen experiences is the remote's home turf; the
danger is the games themselves, so Cartridge enforces a ruthless constraint:
every game conforms to one of **four sanctioned input schemes**, each proven
great on the clickpad. The personal hook: your photo library, run through the
AsciiKit pipeline, becomes the sprites and backdrops — you dodge asteroids as
your own dog.

Feature-limited v1: **six hand-built games**, no AI generation. The feed shell,
the input discipline, and the photo-sprite pipeline are the product. The
AI game-generator (a spec-loop + verifier pipeline) is the documented v2 that this
architecture exists to enable.

## 2. Goals

- Channel-zapping must feel irresistible: game → next game in one swipe, < 400ms,
  the new game already in attract mode and joinable with a single click.
- Every shipped game individually scores ≥ 8/10 on remote feel, enforced by the
  input-scheme gate. A game that needs an exception gets cut, not excepted.
- The photo-sprite moment (“that's MY cat”) happens in the first session.

## 3. Non-goals (v1)

- No AI-generated games, no downloadable games, no third-party games.
- No multiplayer, no Game Center, no game controllers (clickpad-only; controller
  support would mask input-scheme violations).
- No meta-progression, unlocks, or currencies. High scores and daily challenges only.
- No game longer than 90 seconds per life.

## 4. The four input schemes (the law)

Every game declares exactly one scheme; RemoteKit enforces the mapping. There is
no scheme five.

| Scheme | Verbs | Feel target |
|---|---|---|
| **A · Click-only** | click (and nothing else) | Flappy/timing purity |
| **B · Swipe-steer** | discrete 4-way swipes | Snake/lane-runner |
| **C · Four-way dodge** | 4-way as position snaps | Quadrant dodge/match |
| **D · Hold-and-release** | hold to charge, release to act | Golf/launch |

Banned by construction: continuous touch tracking, fast direction reversals,
simultaneous inputs, any gesture needing the clickpad's absolute position. (These
are exactly where the Siri Remote's real weaknesses live.)

## 5. Core experience

### 5.1 The feed

Full-bleed vertical channel feed. Each game occupies the whole screen, running a
live **attract mode** (self-playing demo with your sprites) the moment it's on
screen. Overlaid: one `GlassChip` — the **cartridge label** (game name, your best,
today's challenge) — bottom-left, receding on idle like all suite chrome.

- Swipe ↑/↓: next/previous channel. Transition is a vertical push with the
  outgoing game's audio ducking under the incoming's — genuinely like zapping.
- Click: play, instantly. No loading screens (games are code-resident); attract
  mode morphs into round start within 400ms.
- Feed order: daily-challenge game first, then by personal recency/affinity;
  deterministic per day.

### 5.2 In-game

- The game owns the full screen; the only chrome is a minimal glass score chip.
- Death → **verdict card**: a glass slab with score, best, and the beat that makes
  the feed loop work — it's already listening: click = retry, swipe ↑ = next
  channel. Retry-or-zap in one input, under one second. Signature Moment #1.
- Play/Pause: pause (glass curtain). Back: to feed. Play/Pause long-press: prefs
  (sprite source lane, reduce-motion).

### 5.3 The photo-sprite pipeline

- On first launch (post-permission, or bundled CC0 fallback), AsciiKit builds a
  **sprite locker**: subject-ish crops (saliency/pet/face heuristics from
  PhotoKitPlus) rendered `.pixel` at 32/64px with background knockout, plus
  `.mosaic` backdrops from landscape shots.
- Every game pulls actors/backdrops from the locker; the locker refreshes daily.
  Deterministic per (asset, day) so a great sprite day is shareable by screenshot.
- Sprites are art, not physics: hitboxes are game-defined circles/capsules —
  photo content can never make a game unfair (anti-fragility: any photo works;
  weird photos just make funnier heroes).

### 5.4 Launch lineup (six games, two per “mood”)

| Game | Scheme | One line |
|---|---|---|
| **Flap** | A | Your pet flaps through glass pipes |
| **Stomp** | A | Timing-jump over scrolling obstacles, rhythm-flavored |
| **Noodle** | B | Snake; the tail is your photo strip growing |
| **Shuttle** | B | Lane-dodge runner down an infinite mosaic highway |
| **Quadrant** | C | Snap between four zones to catch/avoid fallers |
| **Putt** | D | Hold-charge mini-golf across pixel dioramas of your landscapes |

Each ships with one **daily challenge** variant (seeded mutator: speed, gravity,
palette) — the feed's freshness without any generation infrastructure.

## 6. Visual & Liquid Glass specification

- The split brand: game canvases are pure retro pixels (the suite's content
  layer); ALL surrounding chrome — cartridge label, verdict card, pause curtain,
  score chip — is Liquid Glass lensing those pixels. The verdict card refracting
  a scrolling game-over screen behind it is the poster shot.
- Attract modes are choreographed to be beautiful even unplayed — the feed
  doubles as an ambient arcade if you just… don't click (IdleAttract hides even
  the labels; kinship with Rabbit Ears).
- 60fps is a hard floor for canvases and transitions alike; a game that can't
  hold it gets simplified, not excused.
- Sound: each game ≤ 4 chiptune sounds + one feed “zap”; global mix keeps
  channel-surfing pleasant, never jarring.

## 7. Architecture notes

- `CartridgeEngine`: a tiny shared runtime (scene loop, sprite atlas from the
  locker, physics-lite, scheme-scoped input via RemoteKit). Games are Swift
  modules implementing `protocol Cartridge { var scheme: Scheme; func tick(...) }`
  — pure functions of (state, input, dt) where possible.
- **v2 hook (design now, build later):** `Cartridge` conformance doubles as the
  target spec for AI-generated games: a declarative parameter surface (entities,
  speeds, rules) + a verifier that replays bot-inputs to prove winnability and
  input-scheme compliance before a generated game can enter the feed — the same
  generator-verifier pattern as Nine and Blockhead. Nothing in v1 may violate
  this boundary.
- Per-game code budget ≤ 500 lines; the constraint keeps games micro and the
  future generation target realistic.

## 8. tvOS native integration

- **Top Shelf:** today's challenge lineup as a carousel of live-rendered frames
  with your sprites; deep-click lands directly in that game's attract mode.
- **Multi-user:** bests, affinity order, and sprite locker per profile.
- **Focus engine:** suspended inside games (scheme input only); standard focus on
  verdict cards and prefs.

## 9. Success metrics

- Median channels visited per session ≥ 4 (zapping is real).
- Retry rate after death ≥ 50% (the verdict-card loop works).
- ≥ 60% of sessions play with personal sprites (the hook lands).
- Per-game remote-feel audit ≥ 8/10 by fresh testers before any game ships.

## 10. Milestones

- **M1:** Feed shell + attract/zap/verdict loop with two placeholder games.
  Gate: zapping alone is fun with the games at 4/10.
- **M2:** CartridgeEngine + sprite locker; Flap and Noodle at 8/10 polish.
- **M3:** Remaining four games, daily challenges, bests, sound mix.
- **M4:** Top Shelf, multi-user, reduce-motion, performance floor, App Store pass.

## 11. Open questions

- Does attract mode use live personal sprites on the App Store screenshots
  (privacy optics) or bundled art? Leaning bundled for marketing, personal on-device.
- Six games vs four at launch if M3 timeline slips: cut Stomp and Shuttle first
  (scheme duplicates), never the feed polish.
