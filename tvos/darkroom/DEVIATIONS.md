# Darkroom — deviations from PRD v1

Sanctioned cuts and pragmatic interpretations, logged per suite rules.

## Sanctioned cuts

1. **Top Shelf extension: SKIPPED** (suite-wide sanction). The developed
   wall lives only in-app. `WallEntry` history (last 24 develops) is already
   persisted via `@CouchStored("wall")`, so a Top Shelf provider can be added
   later without a data migration.
2. **Momentum cursor is simple repeat-move.** `onMoveCommand` carries no
   velocity, so "fast flick travels multiple cells" is implemented as
   acceleration on repeated same-direction swipes within 0.35 s (max step
   configurable 1–3 via the prefs sheet, default 2). Feels equivalent at
   couch distance; no raw dpad access needed.
3. **Large stays 20×20.** The legibility math works out: at 1080-pt layout
   height the 20-board cell is ≈ 38 pt and clue numerals render at exactly
   the 29 pt suite minimum, so the 18×18 fallback wasn't taken. Revisit
   after a real living-room test (PRD open question stands).

## Interpretations / small deviations

4. **Long-press disambiguation.** RemoteKit exposes one hold gesture
   (`holdBegan`/`holdEnded`). The PRD wants hold+swipe = drag-fill AND
   long-press = coach ray. Resolution: a hold that *moves* is a drag-fill;
   a hold released without movement is the coach ray. One gesture, two
   intents, zero conflicts in practice.
5. **Drag-fill rejection ends the stroke.** When a painted run hits a
   contradicting cell, the refusal (shake + clue glow + mistake) fires once
   and painting stops for the rest of that hold; the cursor keeps moving.
   Prevents a single drag from farming N mistakes.
6. **`playPause` double-fire guard.** The system delivers `.playPause` on
   press and RemoteKit's 8-way reader delivers `.playPauseLongPress` on a
   long release, so a long press would also toggle an ✕. The board undoes
   the immediately-preceding ✕ toggle (< 1.2 s) when the long-press arrives.
   Filed in COUCHKIT-ASKS.
7. **No GlassPill.** API.md suggests exposing the prefs sheet from a pill as
   a fallback for remotes without the 8-way reader, but the PRD's chrome
   inventory ("nothing else") wins. Boards enable the 8-way reader solely so
   `playPauseLongPress` is delivered.
8. **Wall shows today's roll only** (per PRD §4.1 — "solved plates hang
   developed on the same wall"). Older develops persist in the wall store
   for the (skipped) Top Shelf carousel; they are not browsable in v1.
9. **Coach beam is a settle, not a sweep.** The ray fades in over the
   provable line and pulses its clues for ~2.6 s instead of animating a
   traveling beam. Reads identically at 3 m, far less code to get wrong.
10. **Flat-photo rejection.** Beyond the PRD's solvability proof, the
    compiler rejects regions whose fill-score field has < 0.05 contrast
    spread (10th–90th percentile) — a featureless photo would otherwise
    threshold into dithered noise. Rejected photos fall through to the next
    daily-roll candidate.
11. **Mistake surfacing.** Mistakes are counted (PRD: "mistake counting")
    and whispered in the transient bottom caption ("· 2 missteps") rather
    than given persistent chrome, keeping boards serene.
12. **Deployment target tvOS 18** per the suite build templates (README says
    tvOS 26; CouchKit's glass shim handles both — `.glassEffect` on 26+,
    ultra-thin material below).
