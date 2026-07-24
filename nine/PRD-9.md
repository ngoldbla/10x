# PRD-9 — Rich stats (the habit, made visible)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one PR
**One-liner:** History grows from three flat numbers into a page you *want* to
open — a completion heat grid, average-vs-best per difficulty, and a solve-time
trend — all derived from data the engine already records. The second store
screenshot, and the daily reason to come back.

Prototype: `-uxdemo.stats` (`RichStatsDemo` in `UXDemoScenes.swift`) — the
approved look. Production replaces it.

## 1. Why

`SolveRecord` already stores date, difficulty, isDaily, seconds and points for
every finish; `HistorySheet` shows almost none of it. For a paid app, stats are
the "this app respects my time" signal — and the heat grid converts one solve
into a visible journey the same way the streak flame does.

## 2. The experience

All inside `HistorySheetContent` (shared iOS / macOS / tvOS — everything scales
by the existing `s` factor and must look right in all three, plus light themes):

- **Totals row** (kept): points · solved · best streak.
- **Heat grid** — last 12 weeks, one cell per day; intensity = solves that day
  (0–3+), daily-solve days get the accent at full strength. Derived by
  bucketing `records` by `DailySeed.dayOrdinal(for:)`.
- **Average vs. best** — per difficulty, twin capsule bars (avg muted, best
  full accent) with `best · avg` mm:ss labels. Rows appear only for
  difficulties with ≥ 1 solve.
- **Trend sparkline** — rolling mean of the last 20 solve times, drawn with
  Canvas/Path exactly as the prototype (`Sparkline`); "▼ faster" caption when
  the trend improves.
- **Recent + Game Center rows** (kept, below the new sections).
- **Empty-state grace:** with < 5 records the new sections collapse to the
  existing "Solve a board and it lands here" line — never an empty chart.

## 3. Data change: the 200-record ceiling

`SolveHistory.capacity` rises **200 → 1000**. Rationale: a daily solver fills
200 in ~7 months and the heat grid would silently truncate. At ~110 bytes per
JSON record, 1000 records ≈ 110 KB — comfortably inside the 1 MB iCloud-KVS
total alongside the tiny streak blob. Tests assert the new cap and that
existing 200-record blobs decode unchanged (append-only change, no migration).

## 4. Non-goals

- No new persisted analytics, no per-cell/technique telemetry, no Swift Charts
  dependency (hand-rolled Canvas, per suite rules), no Mac-only extra window,
  no stats widget (a natural PRD-3 follow-up, later).

## 5. Implementation plan

1. Engine: pure helpers on `SolveHistory` — `solvesByDay(ordinalRange:)`,
   `averageSeconds(for:)`, `trend(window:)` — TDD in `Tests/`.
2. New `Sources/App/StatsViews.swift`: `HeatGrid`, `TwinBar`, `Sparkline`
   (ported from the prototype, re-themed via `ThemeTones`, scaled by `s`).
3. Compose into `HistorySheet.swift`; capacity bump in `Scoring.swift`.
4. Delete `RichStatsDemo` + the `.stats` flag case.

## 6. Verification checklist

- [ ] `swift test`: helper suite green incl. cap change + decode-compat test.
- [ ] iPhone sim: `sim-use` screenshots — populated (use `--debug-fill` +
      solves), sparse (fresh install), and light-theme variants.
- [ ] tvOS sim: History sheet renders scaled, focus navigation intact.
- [ ] macOS: History window (⌘Y) renders the new sections.

## 7. Open questions

- Heat-grid tap → jump to that day's archive entry: wire it once PRD-14 lands
  (leave a seam, don't block on it).
