# Blockhead — Deviations from PRD v1

Sanctioned cuts and pragmatic deviations, in priority order for v1.1.

## Sanctioned cuts (agreed for v1)

1. **Sound is OMITTED — top v1.1 item.** The PRD says Blockhead is "the one
   suite app where sound leads" (tick-tock ring, clack, verdict sting, handoff
   whoosh, ≤8 original chiptune-adjacent sounds, reduce-flash flattens audio
   dynamics). v1 ships silent; the verdict beat was tuned to feel great with
   the sound off (M1 gate), but sound design is the first thing v1.1 adds.
2. **Top Shelf extension SKIPPED** — suite-wide decision. The marquee state
   (sealed / in-progress / finished) exists in the engine (`tonightState`),
   so a Top Shelf provider can be added without engine changes.
3. **188 questions instead of 600.** Quality over quantity: every question is
   hand-written and verifiable. The pack schema + linter (the v2
   generator-verifier contract) are fully in place; growing the pack is pure
   content work. Direction balance is exact (47 correct answers per direction).
4. **Picture rounds use CouchCore DemoArt** (sanctioned adjustment): each
   picture question carries a `DemoArtRecipe` id, rendered `.mosaic` during
   the countdown and sharpened to the raw render on reveal. Real
   licensed/CC0 photography is out of v1; the question text always matches
   the art's theme so the beat still reads.

## Design deviations

5. **Menu selection is RemoteKit-driven, not focus-engine-driven.** PRD §7
   wants slabs as real focusable elements on menu screens. CouchKit's
   `.couchRemote` makes its host view focusable and consumes move commands,
   so mixing it with focusable child slabs risks double-handling. v1 keeps
   ONE input path: every screen has a single `.couchRemote` surface and menus
   (including the prefs GlassSheet's rows) track a selection index with a
   FocusHalo-equivalent `selectionHalo`/cursor treatment.
   See COUCHKIT-ASKS.md for the ask that would unlock real focus menus.
6. **Multi-user / iCloud profiles are partial.** Streak + archive use
   `@CouchStored(cloudSynced: true)` under the default profile; per-tvOS-user
   profile switching (PRD §7) is deferred with the rest of M4.
7. **Episode progress survives Back within a session, not across relaunch.**
   Back suspends the run (clock excluded from speed bonuses) and the marquee
   shows "Resume"; the suspended run is in-memory only. Completed results,
   streaks, and prefs persist to disk/iCloud.
8. **prefs reachability:** `playPauseLongPress` is only emitted by CouchKit's
   GameController-based reader (enabled on the stage via `eightWay: true`).
   As a fallback the stage also opens prefs on hold (long-press), per
   CouchKit's own guidance to expose the sheet from a second path.
9. **Party rounds are 3 (difficulty ramp 1→2→3), one question per player per
   round** — the PRD's "rounds alternate players" made concrete: a 4-player
   match is 12 questions, comfortably under the ≤90s-per-player-turn budget.
10. **Answer-slab lock-in is scale/offset/lensing via `couchGlassInteractive`
    + `couchFast`** — the "clack" is visual-only until sound lands (see #1).
11. **60 fps / <80 ms latency metrics unverified on-device** — no Xcode/tvOS
    hardware in this environment; animation choices follow the suite's spring
    tokens, but the M1 "feels great" gate needs a real Siri Remote pass.

## Environment note

Built and tested on Linux (Swift 6.0.3): `swift build` + `swift test` cover
the entire engine (pack linter over all 188 questions, episode determinism,
curve shape, scoring, streak/archive, party). The SwiftUI target
(`project.yml` → XcodeGen) compiles only on tvOS and has been desk-checked
line-by-line against CouchKit's actual source signatures.
