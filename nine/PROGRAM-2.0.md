# Nine 2.0 — "The Deep End" Program Plan

> The program of record for Nine 2.0. Per-PRD specs live beside it as
> `nine/PRD-<n>.md`; how to actually execute one is
> [docs/EXECUTING-A-PRD.md](docs/EXECUTING-A-PRD.md). The plan body below is
> unchanged from the approved version — only the status table is maintained.

## Execution status (updated 2026-07-25)

| Item | State | Notes |
|---|---|---|
| **Wave 0 backlog** | | |
| PRD-6 Watch | written, **not shipped** | needs a new target + provisioning |
| PRD-11 coach hints + auto-notes | written, **not shipped** | UI substrate for PRD-25 |
| PRD-12 share card | written, **not shipped** | substrate for PRD-26's comet |
| PRD-13 streak grace | written, **not shipped** | |
| PRD-14 daily archive | written, **not shipped** | replay entry surface for PRD-26 |
| PRD-15 feedback | **half shipped** | haptics landed as PRD-21; sound still blocked on assets |
| PRD-16 themes/icons | written, **not shipped** | |
| PRD-17 Nocturne | written, **not shipped** | first live test of Phase 0 tolerance; stresses the chain PRD-23 generalizes |
| PRD-18 welcome + teaser + UXDemo deletion | written, **not shipped** | `UXDemo.swift` still present |
| **Wave 1 — "Worthy"** | | |
| Phase 0 foundations | **partly shipped** | element-level quarantine + 50-pair golden corpus in. Field-level preservation implemented, measured at 1515 ms vs 49 ms, reverted — see DEVIATIONS |
| PRD-19 accessibility | **mostly shipped** | 81 AX children, rotors, actions, 44 pt chrome. Remaining: Switch Control scan order, Voice Control pass, AX-dump CI lane |
| PRD-20 localization | not started | needs translators, not infrastructure |
| PRD-21 audio + haptics | **haptics shipped** | audio blocked: no recorded samples exist |
| PRD-22 lens | **fingerprints shipped** | remaining: dark-contrast harness (96-cell matrix), Metal per-petal refraction |
| PRD-34 first five minutes | **IA shipped** | new-game routing, drawer grabber, prefs regroup. Remaining: first-launch onboarding, TipKit budget |
| **Waves 2–3** | not started | PRD-23 unblocked — the golden corpus tripwire now exists |

Shipped in PR #32 ("Worthy"; TestFlight tvOS 450 / iOS 451 / macOS 452). Every
deferral above is recorded with its reason in the "Phase 0" and "Worthy"
sections of [DEVIATIONS.md](DEVIATIONS.md) — read those before picking up any
half-finished PRD, because the omissions were decisions, not oversights.

## Context

Nine 1.1 — the $4.99 universal Couch Suite sudoku (iPhone/iPad, Mac, Apple TV, iOS widgets) — has shipped its founding vision: flick-rose input that never misfires, proof-checked puzzles, cloud library, rich stats, plus Wave 1 of the $4.99 buildout (PRD-8/9/10). The user asked for a v2.0 definition that fundamentally deepens **every surface the user experiences**, at the fidelity of a multi-year program by expert Apple-native teams.

This plan was produced from: (a) full codebase + PRD-corpus exploration, (b) a live sim-use audit of the latest build on an iPhone 17 Pro simulator (screenshots in `/tmp/nine-audit/`), and (c) three parallel design passes — product surfaces, engine/systems, craft/calm. Per the user's decisions: **pricing is deferred** (plan the product; the PRD-7 covenant — no IAP, no Pro tier, no ads — remains binding), **visionOS is out of scope**, and the deliverable is **this plan document only** (no in-repo PRDs yet).

### Program thesis

1.x proved the *input* covenant (the rose). 2.0 proves the *engine* covenant: the deterministic generator-verifier that emits human-readable proof traces is a platform, not a curiosity. Two shipped assets power nearly everything: the serialized `SolveStep` trace chain (`nine/Sources/Engine/LogicSolver.swift` — "why") and the move log (`nine/Sources/Engine/Game.swift` — "how"). 2.0 turns *why* into a Coach and a variant channel, *how* into replays and quiet multiplayer — while paying down the debts (accessibility, localization, audio, contrast, onboarding) that separate a good indie app from an Apple Design Award contender. Calm is the constraint on every line.

### What the live sim audit found (build 1.1)

Strengths verified: rose grammar (petal tap, erase petal, dimmed complete digits), same-number highlight, coral+dot error marking, pull-down stats drawer, playable tutorial, rich prefs (6 themes/8 accents), instant resume, live light↔dark switching.

Gaps verified (beyond the known PRD-6/11–18 backlog):
1. **The board exposes zero accessibility elements** — `describe-ui` shows no cells; VoiceOver users cannot play at all. Chrome AX frames are tiny (9×15pt chevron).
2. **No audio identity anywhere**; placement/error haptics exist as built patterns in `AfterglowHaptics.swift`/`AfterglowScoreTiming.swift` but are **never wired on iOS** (only the solve score plays).
3. **Zero localization** — every string hardcoded English, including engine `displayName`s.
4. **Dark-theme board contrast very low** (glass plane lifts the void; digits tuned against the raw theme constant, not the composited surface); tutorial sheet muddy in dark.
5. **Home shelf emptiness** — Today card a mostly-blank slab; Continue/Boards rows render blank gray rings at 0%.
6. **Discoverability debt** — stats drawer has no affordance (by design comment, but it fails in practice); "New game" buried at the bottom of Settings.
7. Rose petals are opaque `.glassEffect` discs — not the PRD's "true glass petals lensing the board beneath."
8. No onboarding; no iPad-specific composition (centered phone column); no Watch app.

### Standing backlog 2.0 builds on (wave 0 — commitments, not v2 novelty)

PRD-6 (Watch: box-zoom + Crown rose), PRD-11 (coach hints + auto-notes), PRD-12 (share card), PRD-13 (streak grace), PRD-14 (daily archive), PRD-15 (feedback haptics/chime), PRD-16 (themes/icons), PRD-17 (Nocturne difficulty), PRD-18 (welcome + variants teaser + UXDemo deletion). Loose ends: DualSense Create/Options verification (PRD-5), iCloud pace-skew fix (PRD-10 drawer), four open CouchKit asks (ambiguous-flick forwarding, click-vs-tap, play/pause double-fire, sheet focus hand-off).

---

## The Program: five pillars, PRD-19…35

### Pillar A — "Worthy" (the invisible expert-team work; ships early as a 1.5-class release)

- **PRD-20 — Nine in Nine Languages.** String Catalogs first (before the string explosion): mechanical extraction of every literal; Engine never localizes (Linux CI) — it emits stable IDs (`techniqueID`, difficulty raw values), a single App-layer `Strings.swift` maps IDs → `LocalizedStringResource`. Launch: JA, DE, FR, ES, IT, PT-BR, KO, zh-Hans, NL (sudoku's biggest markets are Japan and Germany). Pseudo-loc + RTL audit CI lane; plural variants; Dynamic Type stress tests.
- **PRD-19 — A Voice for the Board (Accessibility).** Keep the single Canvas; add virtual AX children: 9 box/row containers × cells, stable identities, value-only updates. A pure `BoardSpeech` formatter (Sources/Shared; unit-tested; shared with the coach's sentence templates): "Row 3, column 5 — your 4, error / empty, notes 2 5 9". Custom rotors (Empty cells, Conflicts, Notes, per-digit); the rose opens as an AX-modal 9-button ring (and/or adjustable element: swipe cycles digits, double-tap commits); post-move announcements ("Four placed. Two fours remaining."). Switch Control group-scan = boxes→cells; Voice Control cell addressing; Full Keyboard Access audit; 44pt AX frames on all chrome. CI: `describe-ui` AX-tree dumps diffed per screen.
- **PRD-21 — The Sound of Nine (Audio identity).** A `CalmAudio` module (candidate for couchkit): one `AVAudioEngine`, preloaded PCM buffers, all samples <120ms recorded glass/felt at −18dBFS with ±3-cent variation. Placement tick, pencil (low-passed twin), erase (reversed grain), error hush (quieter than placement — whispered, never scolded), digit-complete partial, and a 2.6s solve shimmer that tracks the Afterglow luminance wave exactly. Session `.ambient` + `.mixWithOthers` (never ducks the user's podcast — critical given the PiP feature); silent switch respected. Nothing sounds on navigation/home/rose-open. Simultaneously **wire the already-built placement/error/box-detent haptic patterns on iOS** with a persistent `CHHapticEngine` (20ms budget; AHAP with embedded audio for sample-accurate sync). Sync law: visual anchors; haptic within 20ms; audio within one frame of the haptic.
- **PRD-22 — The Lens (rendering).** True glass petals: SwiftUI `layerEffect` can't sample behind a layer, so glassifying petal views is a dead end — instead extend the **board Canvas's existing Metal pipeline** (Afterglow.metal already applies two `layerEffect`s) with a third per-petal refraction shader (9 centers + radius + magnification uniforms) so board digits genuinely bend and magnify under each petal; SwiftUI draws only glyphs and rims above. Reduce-Motion/fallback = current material (pure upside). Plus: **dark contrast retune** measured against the *composited* glass (standards: givens ≥7:1, entries ≥4.5:1, coral ≥3:1, across 6 themes × 8 accents × light/dark, sampled from screenshots in an automated harness); an `accessibilityContrast` hairline variant; **real board-fingerprint thumbnails** on the home shelf (deterministic seeds make them free — givens as dot constellation, filling with accent dots as you progress; no more blank rings; below ~3% show "Untouched", never a 0% ring); route the tutorial through the theme system (fixes the muddy dark composite).
- **PRD-34 — The First Five Minutes (onboarding + IA).** First launch *is* the tutorial's first beat: one pre-focused cell, "flick to place a 7", under 30 seconds, one-tap skippable (the PRD's own metric: superpower within 60 seconds). New Game leaves Settings entirely — its homes: the difficulty cards on the shelf, an "Another" action after Afterglow settles, and a "Fresh board" row atop the Boards sheet. Stats drawer gets a one-time 3pt hairline grabber that appears for the first three sessions then fades forever. TipKit hard-capped: three tips total, one per session max. Prefs regroup into Play / Feel (new: sound+haptics) / Appearance / Layout / About.

### Pillar B — "The Second Language" (variants — the generator-verifier's named payoff)

- **PRD-23 — Variant Engine: Killer (+ constraint architecture).** No protocol rewrite: `SudokuGrid` untouched; new Codable `VariantConstraint` (`.cage(cells:sum:)`, `.thermometer(cells:)`, later arrow/kropki/sandwich; unknown discriminators decode to `.unrecognized`) compiled once per puzzle into a `ConstraintContext` (extra peers, cage tables, thermo bounds; classic = shared static empty context, one pointer compare). `CandidateState`/solver techniques iterate `context.peers/units` which return the exact static classic arrays for classic — **byte-identical goldens prove no destabilization**. Variant reasoning enters as ordinary `Technique` cases (cageSingle, cageCombination, innieOutie/rule-of-45, thermoBound) emitting ordinary `SolveStep`s — the Coach speaks variants for free. `BacktrackSolver` gets a constraint-checked twin (originals frozen — they define classic dailies forever). Killer generation: seeded grid → seeded polyomino cage tiling → sums from solution → *add* givens (inverse dig-hole) until technique-bounded. Cost mitigations: **fast-seed catalogs** (ship proven-to-converge seeds, not puzzles — a few KB; device re-proves on demand), a background `PuzzleForge` pantry actor (2–3 proven puzzles per variant×tier, refilled on idle/charging), attempt budgets (never `while true` for variants). A variant tier ships only when catalog mining shows p95 compose within budget.
- **PRD-24 — Channels (Thermo + the variant shelf).** Thermo ships first as the de-risking variant (cheap generation; thermos rendered as luminous glass tubes). Product framing: **Channels** — home shelf page-turns between Classic | Killer | Thermo, each with its own Today, streak, stats slice, and leaderboard; dailies one-per-day per channel so the classic streak is never diluted. The rose is unchanged across variants — the input covenant is variant-agnostic, which is the strategic point. Watch stays classic-only. **AI-generated rulesets explicitly deferred to 2.x** (they strain the proof covenant until the verifier can gate arbitrary rules).

### Pillar C — "The Coach" (the traces become a teacher)

- **PRD-25 — Why Must This Be a Seven?** Long-press any empty cell (⌥-click Mac; long-press-select tvOS): the engine re-derives the minimal `SolveStep` sub-chain forcing that cell and narrates it *on the board* — involved cells breathe in sequence, one step at a time, no text walls. A **Technique School** extends the playable tutorial: one lesson per technique through the new ceilings, each a real seeded position (an exemplar = `(seed, difficulty, stepIndex)` ≈ 20 bytes; the device regenerates and proves it; CI validates every exemplar). Mastery tracked quietly (`CoachProgress`, <2KB, KVS). Hints (PRD-11) become "show me the next why." Solver expansion for the deep end: **Tempest** (swordfish via a generalized `fish(n:)` where X-Wing = `fish(2)` with byte-identical emitted steps, skyscraper, XY-Wing) and **Abyss** (simple coloring, optionally W-Wing; stop before full chains — explanation complexity is the limit). Trace schema v2 (additive, tolerant): stable `techniqueID` strings as the wire/l10n identity, `roles` (base/cover/pivot/victim) for coach rendering, `chain` links for coloring animation.
- **PRD-26 — The Comet (replay + debrief).** `LoggedMove` gains optional elapsed-time (`at:`, caller-passed — the engine still never reads a clock; old logs replay at uniform cadence). At solve time a finalized `SolveReplay` is minted (packed binary move log, 1–2KB per solve) — replay analysis re-runs the solver alongside your moves to classify each placement (matched-trace / harder-than-needed / guess), feeding stats and `CoachProgress`. UI: a comet retraces your solve — hesitations slow it, erasures loop retrograde; post-solve **Debrief** card (pull-up, never forced): fastest region, longest-circled cell, "you found the X-Wing at move 31." The 5s comet loop becomes the animated body of the PRD-12 share card. tvOS gets a your-own-solves ambient screensaver.

### Pillar D — "Together, Quietly" (multiplayer a calm brand survives)

- **PRD-27 — Pass the Remote (tvOS/iPad local duel).** Two players, one remote, one board, alternating fixed turns; per-player tint; errors corrected quietly at hand-off; move-log credits contributions in the debrief. No login, no network — App-layer only.
- **PRD-28 — The Parlor (SharePlay + GC challenges).** Same seeded puzzle on each FaceTime participant's device; ambient presence only (a soft glow-dot per friend showing fill %, no times until everyone finishes; then side-by-side comets). Game Center challenges wrap the same primitive async: "beat my Thursday daily" sends a seed. Deterministic seeds are the transport — trivially correct everywhere.
- **PRD-29 — The Table (daily league).** Opt-in 20-person weekly tables ranked by completion-consistency first, time second; no demotion shame; never notifies; rendered in the stats drawer's hand-inked Canvas language. Backed by Game Center recurring leaderboards (no server); CloudKit public-DB pods only if GC granularity can't express tables. Anti-cheat: pure-Engine replay re-simulation (legal moves, final grid = proven solution, monotone timing) — trust-but-verify, appropriate for a zen game.

### Pillar E — "Every Surface, Native Depth"

- **PRD-30 — Quiet Presence.** Live Activity: mini board state after you start-and-leave the daily — **no timers, no countdowns, no streak-endangered nagging ever** (PRD-13 grace exists so we never have to). Dynamic Island: tiny board glyph only. StandBy: a dedicated ambient face — today's board as a nightstand glass object.
- **PRD-31 — The Drafting Table (iPad).** True regular-width composition: board center-stage, stats drawer becomes a persistent right rail (discoverability solved by geometry), controls float beside the board; Stage Manager/external display sanity; Mac hover-halo on trackpad; keyboard parity. Apple Pencil: hover previews the petal under the tip; strokes become pencil marks *in your handwriting* (same hand-drawn Canvas language as stats) — the 2.0 signature-moment candidate. (Craft rule tension noted: this is the release's one new input concept.)
- **PRD-32 — reserved (visionOS)** — explicitly out of scope per user decision; slot kept to avoid renumbering if revisited in 2.x.
- **PRD-33 — Nine, Everywhere You Ask.** Full App Shortcuts suite (Start the daily / Continue / How's my streak / Start a gentle game) in Spotlight, Siri, Action button; **Focus filters** (hide the daily/streak during Work Focus — Focus that *adds* calm); interactive-widget growth (systemMedium "three moves" mode; per-channel widget configuration); Journaling Suggestions (completed daily as a private reflective moment). Mac: real menu bar with every command, menu-bar extra mini board, per-puzzle window restoration, ⌥-click why. Rejected: Siri voice solving (slower than the rose = demo-ware).
- **PRD-35 — The Store Tells the Story.** 2.0 re-launch: three preview videos (rose-on-remote; why-must-this-be-a-7; the comet), per-platform screenshot sets, localized store pages for all nine languages, custom product pages (learners → Coach; TV gaming → duel), in-app one-scroll "What's in 2.0" card. **Pricing intentionally deferred** — the covenant (no IAP/Pro/ads) is binding regardless; the free-update-plus-price-raise option from the product pass is recorded for the later decision.

---

## Engineering foundations (Phase 0 — everything depends on this)

The single highest-leverage migration fix: **`nine.library` is one CouchStored blob — one undecodable `LibraryEntry` currently throws the array decode and discards the entire library.** Phase 0 ships, before any new enum case or record kind exists:
1. Tolerant-decode program: `Difficulty`/`Technique`/`GameKind` sentinel cases (`.beyond`, `.unrecognized`), lossy per-entry `BoardLibrary` decode; nothing ever throws out of a container decode. Old builds must *skip* (never delete) unknown CloudKit records — `LibraryCloudStore.projection` already returns nil-skip; add cross-version fixture tests to pin it.
2. **Golden determinism corpus**: ~50 (seed, difficulty) pairs → SHA-256 of encoded `GeneratedPuzzle` frozen. Any solver/topology refactor must keep classic hashes byte-identical — this is the tripwire that makes the variant refactor safe (risk #1: one reordered loop silently changes every future daily and breaks shared-seed duels).
3. Schema fixture harness (frozen blobs per released version, decoded both directions in CI; the PRD-17 downgrade drill scripted).
4. Additive `SolveStep` v2 fields, `LoggedMove.at`, string-catalog extraction.

Data placement: streak/prefs/history/CoachProgress stay KVS (small, LWW-safe; do not grow SolveHistory); library + immutable `SolveReplay` records in CloudKit zone `NineLibrary`; duel state in Game Center matchData (packed replay ≤64KB); pantry/catalogs local-only. Watch: KVS + WatchConnectivity daily hand-off (reuse `SharedDailyBoard` revision pattern) + on-watch steady-tier regeneration fallback; watch never generates above catalog-easy.

CI shape: Lane 1 Linux SwiftPM (Engine+Shared, every push) · Lane 2 macOS (all-platform builds, snapshot + AX-dump tests, contrast harness) · Lane 3 nightly (500–1000-puzzle variant proof soaks, catalog mining, pseudo-loc screenshots, downgrade drills, perf baselines: compose p95 per tier, rose round-trip <400ms, cold launch <800ms, widget ≤30MB).

## Craft charter (the bar, held program-wide)

Ten checkable standards (full detail from the craft pass, enforced in CI/release ritual): every interactive element a first-class AX citizen (≥44pt AX frames); contrast measured on the composited glass (96-cell theme×accent matrix); named motion tokens only — add `couchBloom` (the rose's promised overshoot lives here), `couchSettle`, `couchWhisper` to CouchKit, ban inline animation literals; latency budgets (bloom <250ms, flick-commit <50ms); zero misfires forever (1,000-flick soak per release); every string through catalogs, no truncation at top non-AX Dynamic Type; sensory sync law (visual → haptic ≤20ms → audio ≤1 frame); every state has a designed zero-state (honest absence over fake data); ProMotion discipline (120Hz bloom, 0fps idle board — the idle-pixel test); **one new input concept per release maximum**.

Anti-bloat constitution (2.0 will never): sell past the base price (no IAP/subscription/tips), show anything ad-shaped, gamify (XP/levels/badges/avatars), send notifications (single opt-in silent daily reminder at most, off by default), shame a streak, let the coach place a digit, add a fifth control button, play a sound identifiable by the person beside you in bed, or ship any pixel that asks for attention while the player is thinking. Taste ritual per feature: the 11pm-in-bed test, the roommate test, the first-flick test, the delete-it-for-a-week test, the idle-pixel test.

## Sequencing

- **Wave 0 (committed backlog):** PRD-6, 11–18 + loose ends (DualSense probe, pace-skew fix, CouchKit asks). PRD-11 is the Coach's UI substrate; PRD-12 the share substrate; PRD-14 the replay entry surface; PRD-17 stresses the technique chain PRD-23 generalizes.
- **Wave 1 — "Worthy" (1.5-class release):** Phase-0 engineering foundations + PRD-20 (l10n infra first), 19, 21, 22, 34. Long-lead start in parallel: PRD-23 engine work behind a debug channel.
- **Wave 2 — "Deeper":** PRD-25 Coach + School, PRD-26 Comet, PRD-31 iPad, PRD-33 Intents/Focus, PRD-30 Quiet Presence; killer engine soaks; PRD-27 duel begins.
- **Wave 3 — "Together" (the 2.0 launch train):** PRD-24 Channels ships (thermo first, then killer), PRD-27/28/29 Together features, PRD-35 store re-launch. **2.0 ships when Channels + Coach + one Together feature are simultaneously ready.**

## Top risks

1. Classic determinism breakage during the variant refactor → golden corpus first; classic paths delegate, never rewrite; BacktrackSolver originals frozen.
2. Schema evolution nuking user data (CouchStored discard-on-throw × version skew) → Phase 0 tolerance program before any new case exists; fixture drills forever.
3. Killer generation cost unshippable on-device → catalogs + forge pantry + attempt budgets; tier ships only at proven p95.
4. VoiceOver performance on an 81-element tree → stable identities, value-only updates, AX-dump perf checks.
5. Calm-brand erosion by accretion → the craft charter's constitution + taste ritual gate every PRD.

## Verification

- **This plan:** grounded in firsthand evidence — every "gap" was observed in the live build via sim-use (`/tmp/nine-audit/*.png`) or in source; every "asset" cites the file it lives in.
- **When execution begins (per wave):** golden-corpus hashes green before/after every engine PR; `describe-ui` AX diffs show the board's 81 elements + rotor actions; contrast harness passes the 96-cell matrix; sim-use walkthrough of each reshaped surface (shelf thumbnails, drawer grabber, first-run flow) on iPhone + iPad sims; `swift test` (Engine, Linux-clean) + nightly variant soaks; TestFlight builds via the existing fastlane lanes on all three platforms; the five-test taste ritual on every user-visible PRD before merge.

## Decisions taken (from user)

- Pricing: **deferred** — product planned independent of price; covenant binding.
- visionOS: **out of scope** (slot PRD-32 reserved).
- Deliverable now: **this plan document only**; PRD authoring / Wave-1 implementation are separate future requests.
