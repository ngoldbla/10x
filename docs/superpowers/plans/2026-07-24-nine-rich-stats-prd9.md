# Nine Rich Stats (PRD-9) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Nine's History sheet from three flat numbers into a page worth opening — a 12-week completion heat grid, average-vs-best twin bars per difficulty, and a solve-time trend sparkline — all derived from data the engine already records.

**Architecture:** All derivation lives as pure, `Codable`-safe helpers on `SolveHistory` in `NineEngine` (TDD). Three dumb SwiftUI views (`HeatGrid`, `TwinBar`, `Sparkline`) in a new `StatsViews.swift` render the derived values, re-themed via `ThemeTones` and scaled by the sheet's existing `s` factor. `HistorySheetContent` composes them. The `SolveHistory.capacity` ceiling rises 200 → 1000 (append-only, no migration). The flag-gated `RichStatsDemo` prototype is deleted in the same PR.

**Tech Stack:** Swift 6, SwiftUI, CouchKit, Swift Testing (`swift test` via SwiftPM), xcodegen (`project.yml`) for the app, XCUITest-free — UI verified by `sim-use` screenshots.

## Global Constraints

- Engine changes are **TDD**: write the failing test in `Tests/EngineTests/` first, keep the existing suite green (`swift test`). — PRD-7 §3 rule 5.
- **Tolerant decoding is law.** No new persisted fields are added here; the only persistence change is the capacity constant. A decode-compat test must prove existing 200-record blobs decode unchanged. — PRD-7 §3 rule 5, PRD-9 §3.
- New engine helpers are **pure**: no UI imports, no wall clocks, no `Date()` — a `Calendar` is passed in (default `.current`), matching `DailySeed.dayOrdinal(for:calendar:)`. — PRD-9 §1, suite audit "no engine UI imports".
- New views must look right on **iOS, macOS AND tvOS**, scaled by the sheet's `s` factor (`1.0` on iOS/macOS, `1.7` on tvOS), and in **light themes** — re-theme via `ThemeTones`, never hardcode `.white.opacity(...)`. — PRD-9 §2.
- No new dependencies: **no Swift Charts**, hand-rolled `Canvas`/`Path` only. No new persisted analytics. — PRD-9 §4.
- The heat grid must **never render an empty chart**: with `< 5` records the three new sections collapse to the existing "Solve a board and it lands here" line. — PRD-9 §2.
- Verify per **PRD-7 §3 rule 3**: `swift test` green, `xcodebuild` for iPhone sim AND tvOS sim (macOS too — this touches shared UI), and `sim-use` screenshots of the feature running (populated, sparse, light-theme).
- On ship, **delete the `-uxdemo.stats` scene** (`RichStatsDemo` + the `.stats` enum case + its `Sparkline`) in the same PR. — PRD-7 §3 rule 4, PRD-9 §5.4.

## Key files

- `Sources/Engine/Scoring.swift` — `SolveHistory`, `SolveRecord`, `SolveScore`, `capacity`. Add `DaySolves`, `solvesByDay`, `averageSeconds`, `trend`; bump `capacity`.
- `Sources/Engine/Generator.swift:199` — `DailySeed.dayOrdinal(for:calendar:)` (consumed, not modified).
- `Tests/EngineTests/ScoringTests.swift` — existing helper suite; add the new tests here.
- `Sources/App/StatsViews.swift` — **new**: `HeatCell`, `HeatGrid`, `TwinBar`, `Sparkline`.
- `Sources/App/HistorySheet.swift` — compose the new sections into `HistorySheetContent`; replace `bestTimes` with the twin-bar section.
- `Sources/App/UXDemo.swift:27,67` — delete the `.stats` case + its overlay-host line.
- `Sources/App/UXDemoScenes.swift:436-550` — delete `RichStatsDemo` + its private `Sparkline`.
- `Sources/App/AppModel.swift:83` (`ThemeTones`), `:66` (`AccentChoice.color(isLight:)`), `:526` (`todayOrdinal`) — consumed by the sheet.

---

## Task 1: Engine — `averageSeconds(for:)`

**Files:**
- Modify: `Sources/Engine/Scoring.swift` (add method to `SolveHistory`, after `bestSeconds(for:)` ~line 84)
- Test: `Tests/EngineTests/ScoringTests.swift` (add to `@Suite("SolveHistory")`)

**Interfaces:**
- Consumes: `SolveRecord.seconds`, `SolveRecord.difficulty`, `Difficulty` (existing).
- Produces: `func averageSeconds(for difficulty: Difficulty) -> TimeInterval?` — mean solve time for that difficulty, `nil` when the difficulty has no solves.

- [ ] **Step 1: Write the failing test**

Add inside `@Suite("SolveHistory")` in `Tests/EngineTests/ScoringTests.swift`:

```swift
@Test func averageSecondsPerDifficulty() {
    var history = SolveHistory()
    history.record(record(difficulty: .gentle, seconds: 300))
    history.record(record(difficulty: .gentle, seconds: 500))
    history.record(record(difficulty: .sharp, seconds: 900))
    #expect(history.averageSeconds(for: .gentle) == 400)
    #expect(history.averageSeconds(for: .sharp) == 900)
    #expect(history.averageSeconds(for: .steady) == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter averageSecondsPerDifficulty`
Expected: FAIL — `value of type 'SolveHistory' has no member 'averageSeconds'`.

- [ ] **Step 3: Write minimal implementation**

Add to `SolveHistory` in `Sources/Engine/Scoring.swift`, directly after `bestSeconds(for:)`:

```swift
/// Mean solve time for this difficulty, nil when none exist.
public func averageSeconds(for difficulty: Difficulty) -> TimeInterval? {
    let times = records.lazy.filter { $0.difficulty == difficulty }.map(\.seconds)
    var sum: TimeInterval = 0
    var n = 0
    for t in times { sum += t; n += 1 }
    return n == 0 ? nil : sum / TimeInterval(n)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter averageSecondsPerDifficulty`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add nine/Sources/Engine/Scoring.swift nine/Tests/EngineTests/ScoringTests.swift
git commit -m "Nine: SolveHistory.averageSeconds(for:) engine helper (PRD-9)"
```

---

## Task 2: Engine — `DaySolves` + `solvesByDay(ordinalRange:)`

**Files:**
- Modify: `Sources/Engine/Scoring.swift` (add `DaySolves` struct + method to `SolveHistory`)
- Test: `Tests/EngineTests/ScoringTests.swift`

**Interfaces:**
- Consumes: `DailySeed.dayOrdinal(for:calendar:)` (from `NineEngine`, `Generator.swift:199`), `SolveRecord.date`, `SolveRecord.isDaily`.
- Produces:
  - `struct DaySolves: Sendable, Equatable { public let count: Int; public let hasDaily: Bool }`
  - `func solvesByDay(ordinalRange: ClosedRange<Int>, calendar: Calendar = .current) -> [Int: DaySolves]` — buckets records whose day ordinal falls in `ordinalRange`, keyed by day ordinal. Days with no solves are absent from the dict (caller defaults them to zero). `hasDaily` is `true` if any solve that day was a daily.

- [ ] **Step 1: Write the failing test**

```swift
@Test func solvesByDayBucketsAndFlagsDaily() {
    var history = SolveHistory()
    // Two solves "today" (daysAgo: 0), one of them a daily; one solve 3 days ago.
    history.record(record(daysAgo: 0, isDaily: false))
    history.record(record(daysAgo: 0, isDaily: true))
    history.record(record(daysAgo: 3, isDaily: false))

    let cal = Calendar(identifier: .gregorian)
    let today = DailySeed.dayOrdinal(for: history.records.first!.date, calendar: cal)
    let buckets = history.solvesByDay(ordinalRange: (today - 6)...today, calendar: cal)

    #expect(buckets[today]?.count == 2)
    #expect(buckets[today]?.hasDaily == true)
    #expect(buckets[today - 3]?.count == 1)
    #expect(buckets[today - 3]?.hasDaily == false)
    #expect(buckets[today - 5] == nil)          // no solve → absent
}

@Test func solvesByDayExcludesOutsideRange() {
    var history = SolveHistory()
    history.record(record(daysAgo: 0))
    history.record(record(daysAgo: 40))
    let cal = Calendar(identifier: .gregorian)
    let today = DailySeed.dayOrdinal(for: history.records.first!.date, calendar: cal)
    let buckets = history.solvesByDay(ordinalRange: (today - 6)...today, calendar: cal)
    #expect(buckets.count == 1)                 // the 40-day-old solve is dropped
    #expect(buckets[today]?.count == 1)
}
```

> Note: the existing `record(daysAgo:...)` helper anchors dates to `Date(timeIntervalSince1970: 1_000_000 - daysAgo*86400)`. A fixed gregorian calendar keeps ordinals deterministic regardless of the test host's `.current` calendar/timezone.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter solvesByDay`
Expected: FAIL — no member `solvesByDay`.

- [ ] **Step 3: Write minimal implementation**

Add to `Sources/Engine/Scoring.swift`. Place `DaySolves` just above `SolveHistory` (or nested — top-level is simpler for `Equatable` synthesis):

```swift
/// One day's worth of solves, for the History heat grid. `hasDaily` lights
/// the cell at full accent strength (a daily solve is the streak-worthy one).
public struct DaySolves: Sendable, Equatable {
    public let count: Int
    public let hasDaily: Bool
    public init(count: Int, hasDaily: Bool) {
        self.count = count
        self.hasDaily = hasDaily
    }
}
```

Add the method to `SolveHistory` (after `averageSeconds`):

```swift
/// Buckets solves by their local day ordinal within `ordinalRange`. Days
/// with no solves are absent; the caller defaults them to an empty cell.
public func solvesByDay(
    ordinalRange: ClosedRange<Int>,
    calendar: Calendar = .current
) -> [Int: DaySolves] {
    var byDay: [Int: (count: Int, hasDaily: Bool)] = [:]
    for record in records {
        let ordinal = DailySeed.dayOrdinal(for: record.date, calendar: calendar)
        guard ordinalRange.contains(ordinal) else { continue }
        var entry = byDay[ordinal] ?? (0, false)
        entry.count += 1
        entry.hasDaily = entry.hasDaily || record.isDaily
        byDay[ordinal] = entry
    }
    return byDay.mapValues { DaySolves(count: $0.count, hasDaily: $0.hasDaily) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter solvesByDay`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add nine/Sources/Engine/Scoring.swift nine/Tests/EngineTests/ScoringTests.swift
git commit -m "Nine: SolveHistory.solvesByDay heat-grid bucketing (PRD-9)"
```

---

## Task 3: Engine — `trend(window:)`

**Files:**
- Modify: `Sources/Engine/Scoring.swift`
- Test: `Tests/EngineTests/ScoringTests.swift`

**Interfaces:**
- Consumes: `records` (newest-first), `SolveRecord.seconds`.
- Produces: `func trend(window: Int) -> [TimeInterval]` — the rolling-mean solve-time trend over the most recent `window` solves (across all difficulties), returned **oldest → newest** for the sparkline. Each point is the mean of a trailing sub-window (`max(1, n / 4)`, `n` = points in the window) so a single fast solve nudges rather than spikes the line. Returns `[]` when fewer than 2 solves exist (the view hides the sparkline). Preserves the "faster" signal: `series.last < series.first` iff recent solves got faster.

- [ ] **Step 1: Write the failing test**

```swift
@Test func trendIsEmptyBelowTwoSolves() {
    var history = SolveHistory()
    #expect(history.trend(window: 20).isEmpty)
    history.record(record(seconds: 400))
    #expect(history.trend(window: 20).isEmpty)   // one solve is not a trend
}

@Test func trendConstantTimesIsFlat() {
    var history = SolveHistory()
    for _ in 0..<10 { history.record(record(seconds: 300)) }
    let series = history.trend(window: 20)
    #expect(series.count == 10)
    #expect(series.allSatisfy { abs($0 - 300) < 0.0001 })
}

@Test func trendImprovesWhenSolvesGetFaster() {
    var history = SolveHistory()
    // Insert oldest→fastest last. records is newest-first, so record the
    // SLOW ones "older" (larger daysAgo) and FAST ones "newer".
    for i in 0..<12 {
        history.record(record(daysAgo: 12 - i, seconds: TimeInterval(600 - i * 30)))
    }
    let series = history.trend(window: 12)
    #expect(series.count == 12)
    #expect(series.last! < series.first!)        // newest rolling mean is faster
}

@Test func trendRespectsWindow() {
    var history = SolveHistory()
    for i in 0..<30 { history.record(record(daysAgo: 30 - i, seconds: 400)) }
    #expect(history.trend(window: 20).count == 20)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter trend`
Expected: FAIL — no member `trend`.

- [ ] **Step 3: Write minimal implementation**

Add to `SolveHistory` in `Sources/Engine/Scoring.swift`:

```swift
/// Rolling-mean solve-time trend over the most recent `window` solves,
/// oldest→newest, for the History sparkline. Smoothed by a trailing
/// sub-window so one fast solve nudges the line rather than spiking it.
/// Empty below two solves (nothing to trend).
public func trend(window: Int) -> [TimeInterval] {
    // records is newest-first; take the last `window`, chronological.
    let recent = Array(records.prefix(max(0, window)).reversed()).map(\.seconds)
    guard recent.count >= 2 else { return [] }
    let sub = max(1, recent.count / 4)
    return recent.indices.map { i in
        let lower = max(0, i - sub + 1)
        let slice = recent[lower...i]
        return slice.reduce(0, +) / TimeInterval(slice.count)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter trend`
Expected: PASS (all four).

- [ ] **Step 5: Commit**

```bash
git add nine/Sources/Engine/Scoring.swift nine/Tests/EngineTests/ScoringTests.swift
git commit -m "Nine: SolveHistory.trend rolling-mean solve-time series (PRD-9)"
```

---

## Task 4: Engine — raise the 200-record ceiling to 1000

**Files:**
- Modify: `Sources/Engine/Scoring.swift:58` (`SolveHistory.capacity`)
- Test: `Tests/EngineTests/ScoringTests.swift`

**Interfaces:**
- Consumes: `SolveHistory.capacity`, synthesized `Codable`, `record(_:)`.
- Produces: `SolveHistory.capacity == 1000`. No signature changes.

- [ ] **Step 1: Write the failing tests**

Add to `@Suite("SolveHistory")`:

```swift
@Test func capacityIsOneThousand() {
    #expect(SolveHistory.capacity == 1000)
}

@Test func legacyTwoHundredRecordBlobDecodesUnchanged() throws {
    // A blob written under the old 200 cap must decode intact under the new
    // cap (append-only change, no migration — PRD-9 §3).
    var history = SolveHistory()
    for day in 0..<200 { history.record(record(daysAgo: day)) }
    #expect(history.records.count == 200)

    let data = try JSONEncoder().encode(history)
    let decoded = try JSONDecoder().decode(SolveHistory.self, from: data)
    #expect(decoded.records.count == 200)
    #expect(decoded == history)
}
```

> The existing `capsAtCapacity` test (`Tests/EngineTests/ScoringTests.swift:61`) already reads `SolveHistory.capacity` symbolically, so it keeps passing at the new value — no edit needed.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter capacityIsOneThousand`
Expected: FAIL — `200 == 1000` is false.
(The decode-compat test passes already; run it too: `swift test --filter legacyTwoHundred` → PASS. It exists to lock the guarantee against future regressions.)

- [ ] **Step 3: Write minimal implementation**

In `Sources/Engine/Scoring.swift`, change the constant and update the doc comment:

```swift
/// The rolling log of finished boards, newest first, capped so the value
/// stays small enough to mirror through iCloud KVS alongside the streak.
/// 1000 records ≈ 110 KB — a daily solver fills 200 in ~7 months and the
/// heat grid would silently truncate, so the ceiling is generous (PRD-9 §3).
public struct SolveHistory: Sendable, Codable, Equatable {
    public static let capacity = 1000
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: whole suite PASS (including `capsAtCapacity`, `capacityIsOneThousand`, `legacyTwoHundredRecordBlobDecodesUnchanged`).

- [ ] **Step 5: Commit**

```bash
git add nine/Sources/Engine/Scoring.swift nine/Tests/EngineTests/ScoringTests.swift
git commit -m "Nine: raise SolveHistory ceiling 200→1000 + decode-compat test (PRD-9 §3)"
```

---

## Task 5: New `StatsViews.swift` — `Sparkline`, `TwinBar`, `HeatGrid`

**Files:**
- Create: `Sources/App/StatsViews.swift`

**Interfaces:**
- Consumes: `ThemeTones` (`AppModel.swift:83`), `AccentChoice.color(isLight:)`, `DaySolves` (from `NineEngine`), `CouchKit`.
- Produces (all `internal`, same module as `HistorySheet`):
  - `struct HeatCell: Identifiable { let id: Int; let count: Int; let hasDaily: Bool }`
  - `struct HeatGrid: View` — `init(columns: [[HeatCell]], accent: Color, emptyTrack: Color, s: CGFloat)`
  - `struct TwinBar: View` — `init(title: String, avg: Double, best: Double, bestLabel: String, avgLabel: String, accent: Color, track: Color, s: CGFloat)`
  - `struct Sparkline: View` — `init(points: [Double], accent: Color)` (`points`: normalized `0` fast … `1` slow, oldest→newest)

This task has **no unit test** (SwiftUI views, no snapshot infra). Its deliverable is verified by compilation in Task 6/7's builds and by the Task 8 screenshots. It ends with a build check.

- [ ] **Step 1: Write the file**

Create `Sources/App/StatsViews.swift`:

```swift
// StatsViews.swift — the three hand-rolled stat views the History sheet
// composes (PRD-9): a completion heat grid, average-vs-best twin bars, and a
// solve-time trend sparkline. Ported from the -uxdemo.stats prototype and
// re-themed via ThemeTones so they read right on Void, Paper and the tinted
// themes, scaled by the sheet's `s` factor. No Swift Charts — Canvas/Path only.
#if os(iOS) || os(macOS) || os(tvOS)
import SwiftUI
import CouchKit

/// One day in the heat grid. `count` is solves that day (0…3+ intensity);
/// `hasDaily` lights the cell at full accent — the daily is the one that
/// grows the streak, so it earns the strongest tint.
struct HeatCell: Identifiable {
    let id: Int          // day ordinal
    let count: Int
    let hasDaily: Bool
}

/// Last-12-weeks completion grid: 12 columns (weeks) × 7 rows (a rolling
/// 7-day cadence, today at the bottom-right), GitHub-contribution style.
struct HeatGrid: View {
    let columns: [[HeatCell]]   // 12 columns, each 7 cells, oldest→newest
    let accent: Color
    let emptyTrack: Color
    let s: CGFloat

    var body: some View {
        HStack(spacing: 4 * s) {
            ForEach(columns.indices, id: \.self) { col in
                VStack(spacing: 4 * s) {
                    ForEach(columns[col]) { cell in
                        RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                            .fill(fill(cell))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func fill(_ cell: HeatCell) -> Color {
        if cell.count == 0 { return emptyTrack }
        if cell.hasDaily { return accent }                 // full strength
        let level = min(cell.count, 3)                     // 1, 2, 3+
        return accent.opacity([0, 0.4, 0.65, 0.9][level])
    }
}

/// Average-vs-best capsule pair for one difficulty: a muted avg bar with the
/// full-accent best bar drawn over it (best ≤ avg always, so it nests inside).
struct TwinBar: View {
    let title: String
    let avg: Double        // 0…1 fraction of the track
    let best: Double       // 0…1 fraction of the track
    let bestLabel: String
    let avgLabel: String
    let accent: Color
    let track: Color
    let s: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            HStack {
                Text(title).font(CouchTypography.caption)
                Spacer()
                Text("\(bestLabel) · \(avgLabel)")
                    .font(.system(size: 12 * s, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(track).frame(height: 8 * s)
                    Capsule().fill(accent.opacity(0.35))
                        .frame(width: geo.size.width * clamp(avg), height: 8 * s)
                    Capsule().fill(accent)
                        .frame(width: geo.size.width * clamp(best), height: 8 * s)
                }
            }
            .frame(height: 8 * s)
        }
    }

    private func clamp(_ v: Double) -> CGFloat { CGFloat(min(1, max(0, v))) }
}

/// A tiny filled sparkline for the solve-time trend. `points` run oldest→
/// newest, 0 (fast) at the top … 1 (slow) at the bottom.
struct Sparkline: View {
    let points: [Double]
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let step = points.count > 1 ? w / CGFloat(points.count - 1) : w
            let pt: (Int) -> CGPoint = { i in
                CGPoint(x: CGFloat(i) * step, y: h * CGFloat(points[i]))
            }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    for i in points.indices { p.addLine(to: pt(i)) }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [accent.opacity(0.35), accent.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                Path { p in
                    p.move(to: pt(0))
                    for i in points.indices.dropFirst() { p.addLine(to: pt(i)) }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
#endif
```

- [ ] **Step 2: Build the iPhone target to verify it compiles**

Run (from `nine/`):
```bash
xcodebuild -project Nine.xcodeproj -scheme Nine \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5
```
(If `Nine.xcodeproj` is absent, generate it first: `xcodegen generate`.)
Expected: `** BUILD SUCCEEDED **`. The new file is not referenced yet — this only proves it compiles.

- [ ] **Step 3: Commit**

```bash
git add nine/Sources/App/StatsViews.swift
git commit -m "Nine: StatsViews — HeatGrid, TwinBar, Sparkline (PRD-9)"
```

---

## Task 6: Compose the new sections into `HistorySheetContent`

**Files:**
- Modify: `Sources/App/HistorySheet.swift`

**Interfaces:**
- Consumes: `HeatCell`, `HeatGrid`, `TwinBar`, `Sparkline` (Task 5); `SolveHistory.solvesByDay`, `.averageSeconds`, `.bestSeconds`, `.trend` (Tasks 1–3); `AppModel.todayOrdinal` (`AppModel.swift:526`); `ThemeChoice.tones(for:)`; `model.prefs.theme`, `model.prefs.accent`.
- Produces: History sheet renders (in order): totals → heat grid → average-vs-best → trend → Game Center → recent. New sections appear only with `≥ 5` records; below that they collapse to the existing guidance line.

Layout decisions (locked):
- Heat grid: `12` columns × `7` rows, window = `todayOrdinal - 83 ... todayOrdinal`. Cell `(col, row)` ordinal = `start + col*7 + row`; today lands bottom-right (`col 11, row 6`). Rows are a rolling 7-day cadence, not real weekdays (the prototype shows no weekday labels).
- Twin bars: normalize both `avg` and `best` against the **largest average** among shown difficulties, so the slowest difficulty's avg bar ~fills the track. A difficulty row appears only when it has `≥ 1` solve.
- Trend: `trend(window: 20)`, normalized fastest→`0`, slowest→`1`; flat `0.5` when all equal. Caption `"▼ faster"` shown when `series.last < series.first`.
- The old `bestTimes` section is **replaced** by the twin-bar "Average vs. best" section (best time now lives in the `best · avg` label).

- [ ] **Step 1: Add derived-data + theme helpers**

In `HistorySheetContent`, add near the `accent` property (`HistorySheet.swift:22`):

```swift
/// Theme tones for re-theming the stat views (muted tracks, empty cells)
/// so they read on Paper and the tinted themes, not just Void.
private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }

/// The new stat sections need a real history to be worth drawing; below
/// this they collapse to the guidance line (PRD-9 §2 — never an empty chart).
private var hasRichStats: Bool { model.history.records.count >= 5 }
```

- [ ] **Step 2: Add the three section view-builders**

Add these methods to `HistorySheetContent` (e.g. after `bestTimes`, which they supersede):

```swift
// MARK: - Heat grid (last 12 weeks)

private var heatColumns: [[HeatCell]] {
    let today = model.todayOrdinal
    let start = today - (12 * 7 - 1)            // 84 days incl. today
    let buckets = model.history.solvesByDay(ordinalRange: start...today)
    return (0..<12).map { col in
        (0..<7).map { row in
            let ord = start + col * 7 + row
            let day = buckets[ord]
            return HeatCell(id: ord, count: day?.count ?? 0, hasDaily: day?.hasDaily ?? false)
        }
    }
}

private var heatSection: some View {
    VStack(alignment: .leading, spacing: 10 * s) {
        sectionHeader("Last 12 weeks")
        HeatGrid(columns: heatColumns,
                 accent: accent,
                 emptyTrack: tones.gridTone.opacity(0.10),
                 s: s)
    }
}

// MARK: - Average vs. best

private var avgVsBestRows: [(Difficulty, TimeInterval, TimeInterval)] {
    Difficulty.allCases.compactMap { d in
        guard let avg = model.history.averageSeconds(for: d),
              let best = model.history.bestSeconds(for: d) else { return nil }
        return (d, avg, best)
    }
}

@ViewBuilder
private var avgVsBestSection: some View {
    let rows = avgVsBestRows
    if !rows.isEmpty {
        let maxAvg = rows.map(\.1).max() ?? 1
        VStack(alignment: .leading, spacing: 12 * s) {
            sectionHeader("Average vs. best")
            ForEach(rows, id: \.0) { difficulty, avg, best in
                TwinBar(title: difficulty.title,
                        avg: avg / maxAvg,
                        best: best / maxAvg,
                        bestLabel: Self.format(best),
                        avgLabel: Self.format(avg),
                        accent: accent,
                        track: tones.gridTone.opacity(0.10),
                        s: s)
            }
        }
    }
}

// MARK: - Solve-time trend

@ViewBuilder
private var trendSection: some View {
    let raw = model.history.trend(window: 20)
    if raw.count >= 2 {
        let lo = raw.min() ?? 0, hi = raw.max() ?? 0
        let span = hi - lo
        let points = raw.map { span > 0 ? ($0 - lo) / span : 0.5 }
        let faster = raw.last! < raw.first!
        VStack(alignment: .leading, spacing: 10 * s) {
            sectionHeader("Solve time trend", trailing: faster ? "▼ faster" : nil)
            Sparkline(points: points, accent: accent)
                .frame(height: 56 * s)
        }
    }
}

// MARK: - Section header

private func sectionHeader(_ text: String, trailing: String? = nil) -> some View {
    HStack {
        Text(text)
            .font(CouchTypography.caption)
            .foregroundStyle(.secondary)
        Spacer()
        if let trailing {
            Text(trailing)
                .font(CouchTypography.caption)
                .foregroundStyle(accent)
        }
    }
}
```

- [ ] **Step 3: Rewire `body` — insert the sections, gate on `hasRichStats`, drop `bestTimes`**

Replace the middle of `body` (`HistorySheet.swift:56-69`) — from `totalsRow` through the `if model.history.records.isEmpty { … } else { recentSolves }` block — with:

```swift
                totalsRow

                if hasRichStats {
                    heatSection
                    avgVsBestSection
                    trendSection
                } else {
                    Text("Solve a board and it lands here — time, difficulty and points.")
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                gameCenterRow

                if !model.history.records.isEmpty {
                    recentSolves
                }
```

Then delete the now-unused `bestTimes` computed property (`HistorySheet.swift:114-137`) and its `// MARK: - Best times` header.

> The guidance line now stands in for the charts below 5 records. When 1–4 records exist it shows *and* `recentSolves` lists them — intended: the line explains why the charts are absent, the list shows the few solves.

- [ ] **Step 4: Build all three platforms**

Run (from `nine/`):
```bash
xcodebuild -project Nine.xcodeproj -scheme Nine -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
xcodebuild -project Nine.xcodeproj -scheme Nine -destination 'generic/platform=tvOS Simulator' build 2>&1 | tail -3
xcodebuild -project Nine.xcodeproj -scheme Nine -destination 'generic/platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **` for each.

- [ ] **Step 5: Commit**

```bash
git add nine/Sources/App/HistorySheet.swift
git commit -m "Nine: compose rich-stats sections into HistorySheet (PRD-9)"
```

---

## Task 7: Delete the `-uxdemo.stats` prototype

**Files:**
- Modify: `Sources/App/UXDemo.swift` (remove the `.stats` case + host line)
- Modify: `Sources/App/UXDemoScenes.swift` (remove `RichStatsDemo` + its private `Sparkline`)

**Interfaces:** none exported — pure deletion. Other `-uxdemo.*` scenes are owned by sibling PRDs and must stay untouched.

- [ ] **Step 1: Remove the enum case and its overlay-host line**

In `Sources/App/UXDemo.swift`:
- Delete line 27: `case stats          // 7  rich stats`
- Delete line 67: `case .stats:      RichStatsDemo(model: model)`

- [ ] **Step 2: Remove the prototype scene**

In `Sources/App/UXDemoScenes.swift`, delete `struct RichStatsDemo` (lines ~436–520) **and** the private `struct Sparkline` immediately below it (lines ~522–550) — that `Sparkline` is the prototype's own copy and is used nowhere else once `RichStatsDemo` is gone. (The production `Sparkline` lives in `StatsViews.swift`.)

Verify nothing else references them:
```bash
grep -rn "RichStatsDemo\|\.stats\b\|case stats" nine/Sources/App/UXDemo*.swift
```
Expected: no matches.

- [ ] **Step 3: Confirm the production `Sparkline` is the only one left**

```bash
grep -rn "struct Sparkline" nine/Sources/
```
Expected: exactly one match — `nine/Sources/App/StatsViews.swift`.

- [ ] **Step 4: Build the iPhone target**

Run (from `nine/`):
```bash
xcodebuild -project Nine.xcodeproj -scheme Nine -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add nine/Sources/App/UXDemo.swift nine/Sources/App/UXDemoScenes.swift
git commit -m "Nine: delete -uxdemo.stats prototype scene (PRD-7 §3 rule 4)"
```

---

## Task 8: Verification — tests, builds, screenshots, PR

**Files:** none — this is the PRD-7 §3 rule 3 gate + `finishing-a-development-branch`.

- [ ] **Step 1: Full engine suite green**

Run (from `nine/`): `swift test 2>&1 | tail -20`
Expected: all suites pass, including the four new helper tests, `capacityIsOneThousand`, and `legacyTwoHundredRecordBlobDecodesUnchanged`. Confirm the prior 19 still pass.

- [ ] **Step 2: Build iPhone + tvOS + macOS**

Run the three `xcodebuild … build` commands from Task 6 Step 4. Expected: all `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Screenshot the feature running (populated + light + sparse)**

Use the `run-couch-suite` / `ios-simulator-skill` tooling. Boot an iPhone sim, install a debug build, open History:
- **Populated (dark):** launch with `--debug-fill` and record several solves so `≥ 5` records exist across difficulties + some dailies; open History; screenshot heat grid + twin bars + sparkline.
- **Light theme:** switch theme to Paper in Prefs (or launch pinned light), reopen History; screenshot — verify muted tracks/empty cells read against the light background (this is what the `tones.gridTone` re-theme buys us).
- **Sparse (fresh install):** wipe app data (< 5 records); open History; screenshot — verify the guidance line shows and **no** empty chart renders.

Save screenshots under `.context/ux-audit/` (or the workspace `.context/`) for the PR body.

- [ ] **Step 4: tvOS + macOS spot-check**

- tvOS sim: open the History card; confirm the sections render scaled (the `1.7` `s`) and remote focus still lands on a control (Close / Game Center).
- macOS: open the History window (⌘Y); confirm the new sections render.

- [ ] **Step 5: Finish the branch**

Use the **superpowers:finishing-a-development-branch** skill. Open a PR against `main` titled exactly:

```
Nine: rich stats (PRD-9)
```

PR body: summarize the engine helpers + cap change, note the prototype deletion, and embed/link the populated / light / sparse screenshots. Confirm the PRD-9 §6 checklist boxes and PRD-7 §3 gates.

---

## Self-Review

**Spec coverage (PRD-9):**
- §2 Totals row — kept (unchanged `totalsRow`). ✓
- §2 Heat grid (12 weeks, intensity 0–3+, daily = full accent) — Task 2 (`solvesByDay`/`DaySolves`) + Task 5 (`HeatGrid`) + Task 6 (`heatSection`). ✓
- §2 Average vs. best twin bars, rows only for solved difficulties, `best · avg` labels — Task 1 (`averageSeconds`) + Task 5 (`TwinBar`) + Task 6 (`avgVsBestSection`). ✓
- §2 Trend sparkline (rolling mean last 20, "▼ faster") — Task 3 (`trend`) + Task 5 (`Sparkline`) + Task 6 (`trendSection`). ✓
- §2 Recent + Game Center kept below — Task 6 rewire keeps `gameCenterRow` + `recentSolves`. ✓
- §2 Empty-state grace (< 5 records → guidance line, never empty chart) — Task 6 `hasRichStats` gate. ✓
- §3 Capacity 200→1000 + decode-compat + cap tests — Task 4. ✓
- §4 Non-goals (no Charts, no new persistence, no extra window/widget) — respected; hand-rolled Canvas, no new stored fields. ✓
- §5 Implementation plan order (engine → StatsViews → compose → delete prototype) — Tasks 1–4, 5, 6, 7. ✓
- §6 Verification checklist — Task 8. ✓
- §7 Open question (heat tap → archive) — explicitly deferred to PRD-14; no seam blocks this PR (`HeatCell.id` carries the ordinal, a natural future hook). ✓

**Placeholder scan:** no TBD/TODO; every code step has concrete code. ✓

**Type consistency:** `DaySolves(count:hasDaily:)`, `HeatCell(id:count:hasDaily:)`, `HeatGrid(columns:accent:emptyTrack:s:)`, `TwinBar(title:avg:best:bestLabel:avgLabel:accent:track:s:)`, `Sparkline(points:accent:)`, `averageSeconds(for:)`, `solvesByDay(ordinalRange:calendar:)`, `trend(window:)` — names/params match across Tasks 1–7. ✓
```
