# Nine Daily Archive (PRD-14) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A month grid of past dailies on iPhone — solved days checked, today glowing, every past day tappable — regenerated from `DailySeed` rather than stored, with past-day solves that can never touch the streak.

**Architecture:** Two pure Engine additions (an exact ordinal→seed inverse, a guarded streak write), two pure Shared units (`ArchiveLedger`, the only new persisted state, in its own cloud-synced `nine.archive` blob; `ArchiveCalendar`, all grid and label math), and three App surfaces (`ArchiveSheet`, a Today-card affordance, an in-game chip). Everything date-shaped is pure and Linux-testable; the App layer holds no logic worth a test it cannot have.

**Tech Stack:** Swift 6, SwiftPM (`NineEngine` + `NineShared` targets, Linux CI), SwiftUI + CouchKit (`GlassSheet`, `GlassChip`, `TouchCard`), `CouchStored` for persistence, XCTest.

**Spec:** [docs/superpowers/specs/2026-07-26-prd-14-daily-archive-design.md](../specs/2026-07-26-prd-14-daily-archive-design.md)
**Rules:** [nine/docs/EXECUTING-A-PRD.md](../../../nine/docs/EXECUTING-A-PRD.md)

## Global Constraints

- **Never add a field to `LibraryEntry`.** New persisted state takes a sibling top-level key or its own `CouchStored` blob (EXECUTING-A-PRD §2). This PR takes the latter: `nine.archive`.
- **Never throw out of a container decode.** `CouchStored` discards the whole blob when decode throws. Every step of `ArchiveLedger.init(from:)` is `try?`-guarded.
- **The untyped `RawJSON` tree is built only when the typed decode failed** — the lazy-quarantine rule, measured at 950 ms eager vs ~49 ms lazy on the library blob.
- **Run the golden corpus after every engine commit**, not at the end: `swift test --filter GoldenCorpus`. A mismatch is a bug until proven otherwise.
- **`swift test` must stay under ~120 s.** It reads ~112 s today. Nothing in this plan may add a puzzle compose to the suite.
- **User-facing strings live in one `Phrase` block per file** (the PRD-20 localisation seam). No literals scattered through view code.
- **44 pt minimum touch target**, and image-only buttons need `.contentShape(.accessibility, Circle())` or SwiftUI derives the AX frame from the glyph's tight bounds.
- **iOS only.** No tvOS or macOS archive (PRD-14 §3). `HistorySheet.swift` (cross-platform) is not touched.
- **Archive floor: `ArchiveMonth(year: 2026, month: 7)`** — the month Nine's first daily existed.
- **Day-ordinal dates are UTC midnights.** Every formatter that renders one is pinned to UTC.

---

### Task 1: The exact ordinal → seed inverse

**Files:**
- Modify: `nine/Sources/Engine/Generator.swift:326-345` (`enum DailySeed`)
- Test: `nine/Tests/EngineTests/GeneratorTests.swift` (append)

**Interfaces:**
- Consumes: nothing.
- Produces: `DailySeed.seed(forDayOrdinal: Int) -> UInt64`, `DailySeed.utcCalendar: Calendar`.

Why this is exact rather than approximate: `seed(for: date)` hashes the **local** y/m/d, and `dayOrdinal(for: date)` takes that same local y/m/d and reinterprets it as a **UTC** midnight. The ordinal therefore already *is* the local y/m/d re-encoded, so reading it back in UTC recovers exactly the components `seed(for:)` hashed.

- [ ] **Step 1: Write the failing tests**

Append to `nine/Tests/EngineTests/GeneratorTests.swift`:

```swift
// MARK: - Archive: the ordinal → seed inverse (PRD-14)

/// The daily mapping is a forever-contract — every daily Nine will ever serve
/// and every shared seed is `(day → seed) → puzzle`. Nothing pinned it
/// absolutely before this; the relative test below can pass while the whole
/// mapping shifts by one.
func testDailySeedForAKnownDayIsFrozen() {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let july12 = utc.date(from: DateComponents(year: 2026, month: 7, day: 12))!
    XCTAssertEqual(DailySeed.seed(for: july12, calendar: utc), 0)   // replaced in Step 3
}

/// The archive composes from an ordinal, the Today card from a Date. They must
/// be the same puzzle or "today via the archive" is a second board.
func testSeedForDayOrdinalMatchesSeedForDate() {
    for offsetHours in [0, -8, 5, 13] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: offsetHours * 3600)!
        for dayOffset in 0..<400 {
            let date = cal.date(
                byAdding: .day, to: cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!,
                value: dayOffset
            )!
            let ordinal = DailySeed.dayOrdinal(for: date, calendar: cal)
            XCTAssertEqual(
                DailySeed.seed(forDayOrdinal: ordinal),
                DailySeed.seed(for: date, calendar: cal),
                "GMT\(offsetHours) day \(dayOffset)"
            )
        }
    }
}

func testSeedForDayOrdinalIsDistinctAcrossConsecutiveDays() {
    let seeds = (9_300...9_400).map { DailySeed.seed(forDayOrdinal: $0) }
    XCTAssertEqual(Set(seeds).count, seeds.count)
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd nine && swift test --filter GeneratorTests.testSeedForDayOrdinal
```
Expected: FAIL — `type 'DailySeed' has no member 'seed(forDayOrdinal:)'`.

- [ ] **Step 3: Implement**

Replace the body of `enum DailySeed` in `nine/Sources/Engine/Generator.swift` with:

```swift
public enum DailySeed {

    /// A day ordinal is a UTC midnight by construction (see `dayOrdinal`), so
    /// every conversion back out of one reads it in UTC. Rendering it in the
    /// player's zone would land a day early everywhere west of Greenwich.
    public static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Days since the reference epoch in the given calendar's reckoning of
    /// `date`'s local day. Consecutive calendar days differ by exactly 1.
    public static func dayOrdinal(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let midnight = utcCalendar.date(from: components)!
        return Int((midnight.timeIntervalSinceReferenceDate / 86_400).rounded(.down))
    }

    /// Stable daily seed: a hash of the calendar day (yyyymmdd).
    public static func seed(for date: Date, calendar: Calendar = .current) -> UInt64 {
        seed(components: calendar.dateComponents([.year, .month, .day], from: date))
    }

    /// The same seed, addressed by day ordinal — what the archive composes
    /// from (PRD-14).
    ///
    /// Exact, not approximate: `dayOrdinal` re-encodes the *local* y/m/d as a
    /// UTC midnight, so reading that midnight back in UTC recovers precisely
    /// the components `seed(for:)` hashed. Pinned by
    /// `testSeedForDayOrdinalMatchesSeedForDate` across four timezones.
    public static func seed(forDayOrdinal ordinal: Int) -> UInt64 {
        let midnight = Date(timeIntervalSinceReferenceDate: TimeInterval(ordinal) * 86_400)
        return seed(components: utcCalendar.dateComponents([.year, .month, .day], from: midnight))
    }

    private static func seed(components: DateComponents) -> UInt64 {
        let ymd = UInt64(components.year! * 10_000 + components.month! * 100 + components.day!)
        var rng = SplitMix64(seed: 0x9174_E5D1_0000_0000 ^ ymd)
        return rng.next()
    }
}
```

- [ ] **Step 4: Freeze the absolute pin**

Run the frozen test, read the actual value out of the failure message, and paste it into `testDailySeedForAKnownDayIsFrozen` in place of `0`:

```bash
cd nine && swift test --filter GeneratorTests.testDailySeedForAKnownDayIsFrozen 2>&1 | grep XCTAssertEqual
```

- [ ] **Step 5: Run the tests and the golden corpus**

```bash
cd nine && swift test --filter GeneratorTests && swift test --filter GoldenCorpus
```
Expected: PASS, and the corpus 56/56. `seed(for:)` was refactored, so the corpus is the proof it did not move.

- [ ] **Step 6: Commit**

```bash
git add nine/Sources/Engine/Generator.swift nine/Tests/EngineTests/GeneratorTests.swift
git commit -m "Nine: DailySeed.seed(forDayOrdinal:) — the archive's exact inverse (PRD-14)"
```

---

### Task 2: The past-day streak guard

**Files:**
- Modify: `nine/Sources/Engine/Game.swift:357-390` (`struct StreakState`)
- Test: `nine/Tests/EngineTests/GameTests.swift` (append)

**Interfaces:**
- Consumes: nothing.
- Produces: `StreakState.recordCompletion(day: Int, today: Int)`.

This is a bug fix, not defence in depth. `recordCompletion(day:)`'s `guard day > last` never runs when `lastCompletedDay == nil`, so on a fresh install an archive solve of *yesterday* sets `lastCompletedDay = yesterday` and `displayedStreak(today:)` reports a 1-day streak nobody earned.

- [ ] **Step 1: Write the failing tests**

Append to `nine/Tests/EngineTests/GameTests.swift`:

```swift
// MARK: - Streak: the archive can never write it (PRD-14)

/// The bug the guard exists for. `recordCompletion(day:)`'s `day > last` check
/// cannot fire when nothing has been completed yet, so a fresh install that
/// solves yesterday from the archive would show a streak it never earned.
func testArchiveSolveOfYesterdayLeavesAFreshStreakAtZero() {
    var streak = StreakState()
    streak.recordCompletion(day: 9_500 - 1, today: 9_500)
    XCTAssertEqual(streak.displayedStreak(today: 9_500), 0)
    XCTAssertNil(streak.lastCompletedDay)
    XCTAssertEqual(streak.current, 0)
    XCTAssertEqual(streak.best, 0)
}

func testArchiveSolveNeverDisturbsALiveStreak() {
    var streak = StreakState()
    streak.recordCompletion(day: 9_499, today: 9_499)
    streak.recordCompletion(day: 9_500, today: 9_500)
    let before = streak
    for pastDay in 9_000..<9_500 {
        streak.recordCompletion(day: pastDay, today: 9_500)
    }
    XCTAssertEqual(streak, before)
    XCTAssertEqual(streak.displayedStreak(today: 9_500), 2)
}

func testTodayStillRecordsThroughTheGuardedForm() {
    var streak = StreakState()
    streak.recordCompletion(day: 9_500, today: 9_500)
    XCTAssertEqual(streak.displayedStreak(today: 9_500), 1)
    XCTAssertEqual(streak.lastCompletedDay, 9_500)
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd nine && swift test --filter GameTests.testArchiveSolve
```
Expected: FAIL — `extra argument 'today' in call`.

- [ ] **Step 3: Implement**

In `nine/Sources/Engine/Game.swift`, directly after the existing `recordCompletion(day:)`:

```swift
    /// Record a daily completion that is only allowed to count when it is
    /// *not* in the past (PRD-14 §2).
    ///
    /// The archive lets any past day be played, and a past solve must never
    /// rewrite streak state. The one-argument form cannot enforce that on its
    /// own: its `day > last` guard does nothing when `lastCompletedDay` is nil,
    /// so a fresh install solving yesterday from the archive would come away
    /// with a one-day streak. Every app-layer call goes through this form.
    public mutating func recordCompletion(day: Int, today: Int) {
        guard day >= today else { return }
        recordCompletion(day: day)
    }
```

- [ ] **Step 4: Run the tests**

```bash
cd nine && swift test --filter GameTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add nine/Sources/Engine/Game.swift nine/Tests/EngineTests/GameTests.swift
git commit -m "Nine: StreakState.recordCompletion(day:today:) — a past day can never write the streak (PRD-14)"
```

---

### Task 3: `ArchiveLedger` — the durable checkmark

**Files:**
- Create: `nine/Sources/Shared/ArchiveLedger.swift`
- Create: `nine/Tests/SharedTests/ArchiveLedgerTests.swift`

**Interfaces:**
- Consumes: `RawJSON` (public, `NineEngine`).
- Produces: `ArchiveLedger()`, `.isSolved(day: Int) -> Bool`, `@discardableResult .markSolved(day: Int) -> Bool`, `.solvedDays: [Int]`, `.count: Int`.

The only new persisted state in this PR. Its own `CouchStored` blob, cloud-synced, because the library's 20-entry `playedCap` evicts the very checkmarks the archive exists to show and `SolveRecord` carries the solve date rather than the puzzle's day ordinal.

- [ ] **Step 1: Write the failing tests**

Create `nine/Tests/SharedTests/ArchiveLedgerTests.swift`:

```swift
import XCTest
@testable import NineShared

final class ArchiveLedgerTests: XCTestCase {

    // MARK: - The set

    func testEmptyLedgerHasSolvedNothing() {
        let ledger = ArchiveLedger()
        XCTAssertFalse(ledger.isSolved(day: 9_500))
        XCTAssertEqual(ledger.count, 0)
        XCTAssertEqual(ledger.solvedDays, [])
    }

    func testMarkSolvedIsASetInsert() {
        var ledger = ArchiveLedger()
        XCTAssertTrue(ledger.markSolved(day: 9_500))
        XCTAssertFalse(ledger.markSolved(day: 9_500), "a second mark reports no change")
        XCTAssertTrue(ledger.isSolved(day: 9_500))
        XCTAssertEqual(ledger.count, 1)
    }

    func testSolvedDaysAreSortedRegardlessOfInsertionOrder() {
        var ledger = ArchiveLedger()
        for day in [9_503, 9_500, 9_777, 9_501] { ledger.markSolved(day: day) }
        XCTAssertEqual(ledger.solvedDays, [9_500, 9_501, 9_503, 9_777])
    }

    /// `isSolved` binary-searches, so an unsorted store would answer wrongly
    /// rather than slowly. Ten thousand days is ~27 years of daily play.
    func testLookupIsCorrectAcrossALargeLedger() {
        var ledger = ArchiveLedger()
        for day in stride(from: 9_000, to: 19_000, by: 2) { ledger.markSolved(day: day) }
        XCTAssertTrue(ledger.isSolved(day: 9_000))
        XCTAssertTrue(ledger.isSolved(day: 18_998))
        XCTAssertFalse(ledger.isSolved(day: 9_001))
        XCTAssertFalse(ledger.isSolved(day: 19_000))
    }

    // MARK: - The decode covenant (nothing here may throw)

    func testRoundTrips() throws {
        var ledger = ArchiveLedger()
        for day in [9_500, 9_501, 9_777] { ledger.markSolved(day: day) }
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(ArchiveLedger.self, from: data), ledger)
    }

    func testGarbageDecodesToAnEmptyLedgerRatherThanThrowing() throws {
        for json in ["{}", "[]", "\"nope\"", "{\"days\":\"nope\"}", "{\"days\":{}}"] {
            let ledger = try JSONDecoder().decode(ArchiveLedger.self, from: Data(json.utf8))
            XCTAssertEqual(ledger.count, 0, json)
        }
    }

    func testAnUnreadableElementIsSkippedAndTheRestSurvive() throws {
        let json = "{\"days\":[9500,\"nope\",9501,null,9502]}"
        let ledger = try JSONDecoder().decode(ArchiveLedger.self, from: Data(json.utf8))
        XCTAssertEqual(ledger.solvedDays, [9_500, 9_501, 9_502])
    }

    /// A future build's sibling key survives this build's rewrite — the rule
    /// `SolveHistory` and `BoardLibrary` already keep.
    func testUnknownTopLevelSiblingsAreCarried() throws {
        let json = "{\"days\":[9500],\"firstOpenedAt\":\"2026-07-26\",\"schemaVersion\":2}"
        var ledger = try JSONDecoder().decode(ArchiveLedger.self, from: Data(json.utf8))
        ledger.markSolved(day: 9_501)
        let rewritten = try JSONEncoder().encode(ledger)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: rewritten) as? [String: Any]
        )
        XCTAssertEqual(object["firstOpenedAt"] as? String, "2026-07-26")
        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        XCTAssertEqual(object["days"] as? [Int], [9_500, 9_501])
    }

    /// Identity is the days. The carried trees are an encoding detail, and
    /// excluding them is what lets a hand-built ledger compare equal to a
    /// decoded one.
    func testEqualityIgnoresCarriedKeys() throws {
        let decoded = try JSONDecoder().decode(
            ArchiveLedger.self, from: Data("{\"days\":[9500],\"x\":1}".utf8)
        )
        var built = ArchiveLedger()
        built.markSolved(day: 9_500)
        XCTAssertEqual(decoded, built)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd nine && swift test --filter ArchiveLedgerTests
```
Expected: FAIL — `cannot find 'ArchiveLedger' in scope`.

- [ ] **Step 3: Implement**

Create `nine/Sources/Shared/ArchiveLedger.swift`:

```swift
// ArchiveLedger.swift — which dailies have been solved (PRD-14 §2).
//
// The daily archive regenerates every board from `DailySeed`, so it stores no
// puzzles. It does have to store one thing, and this is it: the set of day
// ordinals whose daily is solved, which is what puts the checkmarks in the
// month grid.
//
// **Nothing else in the app can answer that question, which is why this type
// exists.** `BoardLibrary.prune()` caps solved+archived entries at 20 and
// evicts oldest-first, so the 21st archive solve silently erases the earliest
// checks. `SolveRecord` carries the *solve* date and never the puzzle's day
// ordinal — deliberately, so the PRD-9 heat grid buckets honestly — and caps at
// 200 besides. `StreakState` holds one `lastCompletedDay`, not a set.
//
// **Its own `CouchStored` blob (`nine.archive`), never a `LibraryEntry` field.**
// An older build's synthesized decode drops a field it has no property for and
// erases it on the next autosave 0.6 s later, repeatedly, for any mixed-version
// two-device player; field-level preservation was measured at 1515 ms against a
// 49 ms baseline and reverted (EXECUTING-A-PRD §2). Its own blob rather than a
// sibling key of `nine.history` because `SolveHistory` is an array of records
// with an ordering contract, a capacity prune and a quarantine, and a set of
// ordinals shares none of it — the same call `nine.coach` made.
//
// Cloud-synced, unlike `nine.coach`: a checkmark is a property of the player,
// not of the hand that held the phone, so it belongs beside `nine.streak` and
// `nine.history`.
//
// Size, since the alternative was range compression: one `Int` per solved day,
// five digits and a comma. Ten years of unbroken daily play is ~3 650 ordinals
// ≈ 22 KB against a 1 MB KVS budget. Ranges win on the contiguous case and lose
// on the alternating one, for real code and real tests — so this is a sorted
// array until a measurement says otherwise.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

public struct ArchiveLedger: Codable, Sendable {

    /// Sorted and deduplicated, always — `isSolved` binary-searches it.
    private var days: [Int]

    /// Unknown siblings of `days` at the top level of the blob, carried so an
    /// older build's rewrite does not strip a newer build's key.
    private var carriedTopLevel: [String: RawJSON]

    public init() {
        days = []
        carriedTopLevel = [:]
    }

    // MARK: - The set

    public var solvedDays: [Int] { days }

    public var count: Int { days.count }

    public func isSolved(day: Int) -> Bool {
        var low = 0
        var high = days.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if days[mid] == day { return true }
            if days[mid] < day { low = mid + 1 } else { high = mid - 1 }
        }
        return false
    }

    /// Insert, keeping the array sorted. Returns whether anything changed, so
    /// the caller's backfill can skip a write on the overwhelmingly common
    /// launch where nothing is new.
    @discardableResult
    public mutating func markSolved(day: Int) -> Bool {
        let index = days.firstIndex { $0 >= day } ?? days.count
        guard index == days.count || days[index] != day else { return false }
        days.insert(day, at: index)
        return true
    }

    // MARK: - Coding (the persistence covenant)

    private enum CodingKeys: String, CodingKey { case days }

    /// Nothing in here throws. `CouchStored` discards the entire blob when a
    /// decode does, and a lost blob is every checkmark the player has earned.
    public init(from decoder: any Decoder) throws {
        days = []
        carriedTopLevel = [:]
        if let anyKey = try? decoder.container(keyedBy: RawJSON.RawKey.self) {
            for key in anyKey.allKeys where key.stringValue != CodingKeys.days.stringValue {
                carriedTopLevel[key.stringValue] =
                    (try? anyKey.decode(RawJSON.self, forKey: key)) ?? .null
            }
        }
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        // The typed decode first, and the untyped tree only when it failed —
        // the same laziness `RawLibraryEntry` exists for. A healthy ledger is
        // thousands of plain integers on the cold-launch path; building a
        // `RawJSON` node for each of them costs several times what reading the
        // real type costs, and buys nothing until the day something is wrong.
        if let typed = try? container.decode([Int].self, forKey: .days) {
            days = typed
        } else if let raw = try? container.decode([RawJSON].self, forKey: .days) {
            days = raw.compactMap {
                switch $0 {
                case .int(let value): return value
                case .uint(let value): return Int(exactly: value)
                case .double(let value): return Int(exactly: value.rounded())
                default: return nil
                }
            }
        }
        days = Array(Set(days)).sorted()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: RawJSON.RawKey.self)
        for key in carriedTopLevel.keys.sorted() {
            try container.encode(carriedTopLevel[key]!, forKey: RawJSON.RawKey(key))
        }
        try container.encode(days, forKey: RawJSON.RawKey(CodingKeys.days.stringValue))
    }
}

extension ArchiveLedger: Equatable {
    /// Identity is the days. The carried trees are an encoding detail, and
    /// every caller and test builds an `ArchiveLedger()` by hand.
    public static func == (lhs: ArchiveLedger, rhs: ArchiveLedger) -> Bool {
        lhs.days == rhs.days
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
cd nine && swift test --filter ArchiveLedgerTests
```
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add nine/Sources/Shared/ArchiveLedger.swift nine/Tests/SharedTests/ArchiveLedgerTests.swift
git commit -m "Nine: ArchiveLedger — the checkmark the library's 20-entry cap cannot hold (PRD-14)"
```

---

### Task 4: `ArchiveCalendar` — grid math and labels

**Files:**
- Create: `nine/Sources/Shared/ArchiveCalendar.swift`
- Create: `nine/Tests/SharedTests/ArchiveCalendarTests.swift`

**Interfaces:**
- Consumes: `DailySeed.utcCalendar` (Task 1).
- Produces: `ArchiveMonth(year:month:)` with `.advanced(by:)` and `Comparable`; `ArchiveCalendar.floor`, `.dayOrdinal(year:month:day:)`, `.month(ofDayOrdinal:)`, `.grid(for:firstWeekday:) -> [[Int?]]`, `.weekdayInitials(firstWeekday:) -> [String]`, `.title(for:) -> String`, `.shortLabel(forDayOrdinal:) -> String`, `.longLabel(forDayOrdinal:) -> String`.

The trap this unit exists to contain: a day ordinal's canonical `Date` is a **UTC midnight**, so formatting it in the player's timezone renders the previous day everywhere west of Greenwich. Every formatter here is UTC-pinned and a test proves it under `GMT-8`.

- [ ] **Step 1: Write the failing tests**

Create `nine/Tests/SharedTests/ArchiveCalendarTests.swift`:

```swift
import XCTest
@testable import NineShared
import NineEngine

final class ArchiveCalendarTests: XCTestCase {

    // MARK: - Ordinals

    func testDayOrdinalAgreesWithDailySeed() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: 2026, month: 7, day: 12))!
        XCTAssertEqual(
            ArchiveCalendar.dayOrdinal(year: 2026, month: 7, day: 12),
            DailySeed.dayOrdinal(for: date, calendar: utc)
        )
    }

    func testMonthOfDayOrdinalRoundTrips() {
        for (year, month, day) in [(2026, 7, 1), (2026, 7, 31), (2026, 12, 31), (2027, 1, 1)] {
            let ordinal = ArchiveCalendar.dayOrdinal(year: year, month: month, day: day)
            XCTAssertEqual(
                ArchiveCalendar.month(ofDayOrdinal: ordinal),
                ArchiveMonth(year: year, month: month)
            )
        }
    }

    // MARK: - The grid

    func testGridIsSixRowsOfSeven() {
        let grid = ArchiveCalendar.grid(for: ArchiveMonth(year: 2026, month: 7), firstWeekday: 1)
        XCTAssertEqual(grid.count, 6)
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })
    }

    /// 1 July 2026 is a Wednesday, so a Sunday-first grid leads with three
    /// blanks and a Monday-first grid with two.
    func testLeadingBlanksFollowTheFirstWeekday() {
        let july = ArchiveMonth(year: 2026, month: 7)
        let sundayFirst = ArchiveCalendar.grid(for: july, firstWeekday: 1).flatMap { $0 }
        let mondayFirst = ArchiveCalendar.grid(for: july, firstWeekday: 2).flatMap { $0 }
        XCTAssertEqual(sundayFirst.prefix(4).map { $0 == nil }, [true, true, true, false])
        XCTAssertEqual(mondayFirst.prefix(3).map { $0 == nil }, [true, true, false])
    }

    func testGridHoldsEveryDayOfTheMonthInOrderAndNothingElse() {
        for (year, month, days) in [(2026, 7, 31), (2026, 2, 28), (2028, 2, 29), (2026, 4, 30)] {
            let filled = ArchiveCalendar
                .grid(for: ArchiveMonth(year: year, month: month), firstWeekday: 1)
                .flatMap { $0 }
                .compactMap { $0 }
            XCTAssertEqual(filled.count, days, "\(year)-\(month)")
            XCTAssertEqual(filled, filled.sorted(), "\(year)-\(month)")
            XCTAssertEqual(filled.first, ArchiveCalendar.dayOrdinal(year: year, month: month, day: 1))
        }
    }

    // MARK: - Paging

    func testMonthsRunFromTheFloorToTheMonthContainingToday() {
        let today = ArchiveCalendar.dayOrdinal(year: 2026, month: 9, day: 15)
        let months = ArchiveCalendar.months(through: today)
        XCTAssertEqual(months.first, ArchiveCalendar.floor)
        XCTAssertEqual(months.last, ArchiveMonth(year: 2026, month: 9))
        XCTAssertEqual(months.count, 3)
    }

    func testMonthsNeverRunBelowTheFloor() {
        let beforeLaunch = ArchiveCalendar.dayOrdinal(year: 2026, month: 1, day: 1)
        XCTAssertEqual(ArchiveCalendar.months(through: beforeLaunch), [ArchiveCalendar.floor])
    }

    func testAdvancingAMonthCrossesTheYear() {
        XCTAssertEqual(
            ArchiveMonth(year: 2026, month: 12).advanced(by: 1), ArchiveMonth(year: 2027, month: 1)
        )
        XCTAssertEqual(
            ArchiveMonth(year: 2027, month: 1).advanced(by: -1), ArchiveMonth(year: 2026, month: 12)
        )
    }

    // MARK: - Labels

    func testTitleNamesTheMonthAndYear() {
        XCTAssertEqual(ArchiveCalendar.title(for: ArchiveMonth(year: 2026, month: 7)), "July 2026")
    }

    /// The highest-value test here. A day ordinal is a UTC midnight, so a
    /// formatter left on the device's timezone renders "Jul 11" for 12 July
    /// everywhere west of Greenwich — silently, off by one, and invisible to
    /// anyone developing in UTC+0.
    func testDayLabelsAreStableAcrossTimezones() {
        let ordinal = ArchiveCalendar.dayOrdinal(year: 2026, month: 7, day: 12)
        let saved = TimeZone.default
        defer { TimeZone.default = saved }
        for identifier in ["UTC", "America/Los_Angeles", "Pacific/Kiritimati", "Asia/Tokyo"] {
            TimeZone.default = TimeZone(identifier: identifier)!
            XCTAssertEqual(ArchiveCalendar.shortLabel(forDayOrdinal: ordinal), "Jul 12", identifier)
            XCTAssertEqual(ArchiveCalendar.longLabel(forDayOrdinal: ordinal), "July 12", identifier)
        }
    }

    func testWeekdayInitialsMatchTheGridColumns() {
        XCTAssertEqual(ArchiveCalendar.weekdayInitials(firstWeekday: 1).count, 7)
        XCTAssertEqual(ArchiveCalendar.weekdayInitials(firstWeekday: 1).first, "S")
        XCTAssertEqual(ArchiveCalendar.weekdayInitials(firstWeekday: 2).first, "M")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd nine && swift test --filter ArchiveCalendarTests
```
Expected: FAIL — `cannot find 'ArchiveCalendar' in scope`.

- [ ] **Step 3: Implement**

Create `nine/Sources/Shared/ArchiveCalendar.swift`:

```swift
// ArchiveCalendar.swift — every date computation the daily archive needs
// (PRD-14), as pure functions with no clock of their own.
//
// One rule runs through all of it. A day ordinal is a **UTC midnight** by
// construction: `DailySeed.dayOrdinal` takes the *local* y/m/d and reinterprets
// it as a UTC midnight, so the ordinal already is the local calendar day,
// re-encoded. Read one back in the device's timezone and every player west of
// Greenwich sees the day before — a silent off-by-one that never crashes, never
// warns, and is invisible to anyone developing in UTC+0. So every calendar and
// every formatter here is pinned to UTC, and
// `testDayLabelsAreStableAcrossTimezones` is what keeps it that way.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

/// A calendar month, which is what the archive pages through.
public struct ArchiveMonth: Sendable, Equatable, Hashable, Comparable {
    public let year: Int
    /// 1...12.
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public func advanced(by months: Int) -> ArchiveMonth {
        let total = year * 12 + (month - 1) + months
        return ArchiveMonth(year: total / 12, month: total % 12 + 1)
    }

    public static func < (lhs: ArchiveMonth, rhs: ArchiveMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

public enum ArchiveCalendar {

    /// The month Nine's first daily existed (first `nine/` commit: 2026-07-11).
    ///
    /// `DailySeed` will happily produce a seed for 2019, and the pager could
    /// scroll back forever on that alone — but a day before Nine shipped was
    /// never anybody's daily. Offering it would be content dressed as history,
    /// so the floor is a launch date rather than an absence of one (PRD-14 §2,
    /// "a sane floor … no infinite scroll").
    public static let floor = ArchiveMonth(year: 2026, month: 7)

    private static var calendar: Calendar { DailySeed.utcCalendar }

    // MARK: - Ordinals

    public static func dayOrdinal(year: Int, month: Int, day: Int) -> Int {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return Int((date.timeIntervalSinceReferenceDate / 86_400).rounded(.down))
    }

    public static func date(forDayOrdinal ordinal: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(ordinal) * 86_400)
    }

    public static func month(ofDayOrdinal ordinal: Int) -> ArchiveMonth {
        let components = calendar.dateComponents([.year, .month], from: date(forDayOrdinal: ordinal))
        return ArchiveMonth(year: components.year!, month: components.month!)
    }

    // MARK: - Paging

    /// Every month the pager may reach, oldest first: the floor through the
    /// month holding `today`. Never empty, and never below the floor even on a
    /// device whose clock is set before Nine shipped.
    public static func months(through today: Int) -> [ArchiveMonth] {
        let last = max(floor, month(ofDayOrdinal: today))
        var months: [ArchiveMonth] = []
        var cursor = floor
        while cursor <= last {
            months.append(cursor)
            cursor = cursor.advanced(by: 1)
        }
        return months
    }

    // MARK: - The grid

    /// Six rows of seven, oldest first, `nil` outside the month. Six rows
    /// always: a 31-day month beginning on the last column needs 37 slots, and
    /// a fixed height keeps the sheet from resizing as the pager moves.
    public static func grid(for month: ArchiveMonth, firstWeekday: Int) -> [[Int?]] {
        let first = dayOrdinal(year: month.year, month: month.month, day: 1)
        let start = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1))!
        let dayCount = calendar.range(of: .day, in: .month, for: start)!.count
        // Calendar weekdays are 1 = Sunday; the offset is how far the 1st sits
        // from the column the player's locale starts its weeks on.
        let weekday = calendar.component(.weekday, from: start)
        let leading = ((weekday - firstWeekday) + 7) % 7
        var slots = [Int?](repeating: nil, count: 42)
        for day in 0..<dayCount { slots[leading + day] = first + day }
        return (0..<6).map { Array(slots[($0 * 7)..<($0 * 7 + 7)]) }
    }

    /// One letter per grid column, in the grid's own column order.
    public static func weekdayInitials(firstWeekday: Int) -> [String] {
        let symbols = ["S", "M", "T", "W", "T", "F", "S"]
        return (0..<7).map { symbols[($0 + firstWeekday - 1) % 7] }
    }

    // MARK: - Labels

    public static func title(for month: ArchiveMonth) -> String {
        let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1))!
        return formatter("MMMM yyyy").string(from: date)
    }

    /// "Jul 12" — the in-game chip.
    public static func shortLabel(forDayOrdinal ordinal: Int) -> String {
        formatter("MMM d").string(from: date(forDayOrdinal: ordinal))
    }

    /// "July 12" — the date half of a grid cell's accessibility label.
    public static func longLabel(forDayOrdinal ordinal: Int) -> String {
        formatter("MMMM d").string(from: date(forDayOrdinal: ordinal))
    }

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone   // the whole point — see the file header
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
cd nine && swift test --filter ArchiveCalendarTests
```
Expected: PASS, 11 tests. If a label test fails on format (e.g. "12 Jul" under a non-US locale), pin `formatter.locale = Locale(identifier: "en_US_POSIX")` in the test rather than loosening the assertion.

- [ ] **Step 5: Commit**

```bash
git add nine/Sources/Shared/ArchiveCalendar.swift nine/Tests/SharedTests/ArchiveCalendarTests.swift
git commit -m "Nine: ArchiveCalendar — UTC-pinned grid math and labels for the archive (PRD-14)"
```

---

### Task 5: `AppModel` — open a past day, and record the check

**Files:**
- Modify: `nine/Sources/App/AppModel.swift` (store declarations ~line 391; `init` ~line 551; `openToday` ~line 681; `finishSolve` ~line 975)

**Interfaces:**
- Consumes: `DailySeed.seed(forDayOrdinal:)` (Task 1), `StreakState.recordCompletion(day:today:)` (Task 2), `ArchiveLedger` (Task 3).
- Produces: `AppModel.archive: ArchiveLedger`, `AppModel.openArchiveDay(_ day: Int)`, `AppModel.archiveDay: Int?`.

The App layer has no test target, which is exactly why Tasks 1–4 pushed every decision into the Engine and Shared. What is left here is wiring.

- [ ] **Step 1: Add the store and the property**

Beside the `coachStore` declaration in `nine/Sources/App/AppModel.swift`:

```swift
    /// Which dailies are solved (PRD-14). Cloud-synced: a checkmark is a
    /// property of the player, not of the device that earned it.
    @ObservationIgnored private let archiveStore =
        CouchStored(wrappedValue: ArchiveLedger(), "nine.archive", cloudSynced: true)
```

Beside the `coach` property:

```swift
    /// The archive's checkmarks. Read by the month grid; written only by
    /// `finishSolve` and the launch backfill.
    private(set) var archive: ArchiveLedger {
        didSet { archiveStore.wrappedValue = archive }
    }
```

- [ ] **Step 2: Load and backfill in `init`**

Beside `coach = coachStore.wrappedValue`:

```swift
        archive = archiveStore.wrappedValue
```

and, after the library has loaded (immediately before the `#if os(iOS)` resume block):

```swift
        backfillArchiveLedger()
```

Then add the method next to `writeCoach`:

```swift
    /// Seed the checkmark ledger from what is still knowable, every launch.
    ///
    /// Idempotent (`markSolved` is a set insert), O(library), and self-healing:
    /// a solved daily that arrives later from CloudKit gets its check on the
    /// next launch. It cannot recover days the library pruned before this build
    /// shipped — nothing can, and pretending otherwise would put holes in the
    /// grid that look like unplayed days.
    private func backfillArchiveLedger() {
        var ledger = archive
        var changed = false
        if let last = streak.lastCompletedDay {
            changed = ledger.markSolved(day: last) || changed
        }
        for entry in library.entries where entry.status == .solved {
            if case .daily(let day) = entry.kind {
                changed = ledger.markSolved(day: day) || changed
            }
        }
        if changed { archive = ledger }
    }
```

- [ ] **Step 3: Add `openArchiveDay` and `archiveDay`**

Immediately after `openToday()`:

```swift
    /// Open any past daily from the archive (PRD-14). Mirrors `openToday`
    /// without its two today-only concerns: no widget ingestion (the widget
    /// only ever holds today's board, so an archive board is structurally
    /// invisible to it) and no streak write (`finishSolve` guards that).
    ///
    /// Today routes through `openToday` rather than composing its own board, so
    /// "today via the archive" and "today via the Today card" are the same
    /// entry — one daily a day, no duplicates.
    func openArchiveDay(_ day: Int) {
        guard day <= todayOrdinal else { return }
        guard day != todayOrdinal else { return openToday() }
        if let entry = library.inProgressDaily(day: day) {
            startEntry(entry.id)
        } else {
            compose(kind: .daily(day: day), seed: DailySeed.seed(forDayOrdinal: day),
                    difficulty: .steady)
        }
    }
```

And beside `todaySolved` in the Derived block:

```swift
    /// The past day the board on screen belongs to — nil for today's daily and
    /// for free play. Drives the in-game "Archive · Jul 12" chip.
    var archiveDay: Int? {
        guard case .daily(let day)? = kind, day < todayOrdinal else { return nil }
        return day
    }
```

- [ ] **Step 4: Guard the streak and write the check in `finishSolve`**

Replace the `if case .daily(let day)? = kind { … }` block in `finishSolve`:

```swift
        if case .daily(let day)? = kind {
            isDaily = true
            // A past-day solve must never rewrite streak state (PRD-14 §2).
            // The guard lives in the Engine because the one-argument form
            // cannot enforce it: its `day > last` check does nothing on a
            // fresh install, so an archive solve of yesterday would come away
            // with a one-day streak nobody earned.
            streak.recordCompletion(day: day, today: todayOrdinal)
            try? streakStore.flushNow()
            // Every daily solve, not only archive ones — a day solved from the
            // Today card has to show a check in the grid too.
            var ledger = archive
            if ledger.markSolved(day: day) { archive = ledger }
            try? archiveStore.flushNow()
        }
```

- [ ] **Step 5: Build all three platforms**

```bash
cd nine && COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate
for dest in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$dest" -derivedDataPath build build || break
done
```
Expected: BUILD SUCCEEDED ×3.

- [ ] **Step 6: Commit**

```bash
git add nine/Sources/App/AppModel.swift
git commit -m "Nine: AppModel.openArchiveDay + the guarded streak write and the checkmark (PRD-14)"
```

---

### Task 6: `ArchiveSheet` — the month grid

**Files:**
- Create: `nine/Sources/App/ArchiveSheet.swift`

**Interfaces:**
- Consumes: `ArchiveCalendar`, `ArchiveMonth` (Task 4); `AppModel.archive`, `.openArchiveDay(_:)`, `.todayOrdinal`, `.library` (Task 5).
- Produces: `ArchiveSheetContent(model:onClose:)`.

iOS's `GlassSheet` is `maxWidth: 380` with 22 pt content padding, leaving 336 pt. Seven 44 pt cells with 2 pt gaps is 320 pt — the craft charter's 44 pt floor survives at the narrowest width, which is what fixes the cell size rather than taste.

- [ ] **Step 1: Create the file**

Create `nine/Sources/App/ArchiveSheet.swift`:

```swift
// ArchiveSheet.swift — the daily archive (PRD-14): a month grid of every daily
// Nine has served, all of it regenerated from `DailySeed` rather than stored.
//
// The view holds no date arithmetic. `ArchiveCalendar` owns all of it, in
// `Sources/Shared`, because a day ordinal is a UTC midnight and rendering one
// in the device's timezone puts every label a day early west of Greenwich —
// the kind of bug that wants a Linux test, not a screenshot.
#if os(iOS)
import SwiftUI
import CouchKit
import NineEngine
import NineShared

struct ArchiveSheetContent: View {
    let model: AppModel
    let onClose: () -> Void

    @State private var month: ArchiveMonth
    @Environment(\.colorScheme) private var colorScheme

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _month = State(initialValue: ArchiveCalendar.month(ofDayOrdinal: model.todayOrdinal))
    }

    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }
    private var months: [ArchiveMonth] { ArchiveCalendar.months(through: model.todayOrdinal) }
    private var firstWeekday: Int { Calendar.current.firstWeekday }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            pager
            weekdayHeader
            grid
            Spacer(minLength: 0)
            Text(Phrase.footnote)
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack {
            Text(Phrase.title).couchText(CouchTypography.title)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.accessibility, Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Phrase.close)
        }
    }

    private var pager: some View {
        HStack(spacing: 12) {
            pagerButton(Phrase.previousMonth, "chevron.left", by: -1, enabled: month > ArchiveCalendar.floor)
            Text(ArchiveCalendar.title(for: month))
                .font(CouchTypography.body)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            pagerButton(Phrase.nextMonth, "chevron.right", by: 1, enabled: month < months[months.count - 1])
        }
    }

    private func pagerButton(_ label: String, _ symbol: String, by step: Int, enabled: Bool) -> some View {
        Button { withAnimation(.couchFast) { month = month.advanced(by: step) } } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(.accessibility, Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
        .accessibilityLabel(label)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(Array(ArchiveCalendar.weekdayInitials(firstWeekday: firstWeekday).enumerated()),
                    id: \.offset) { _, initial in
                Text(initial)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 44)
            }
        }
        .accessibilityHidden(true)   // every cell names its own date
    }

    private var grid: some View {
        VStack(spacing: 2) {
            ForEach(Array(ArchiveCalendar.grid(for: month, firstWeekday: firstWeekday).enumerated()),
                    id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, ordinal in
                        if let ordinal {
                            ArchiveDayCell(
                                ordinal: ordinal,
                                state: state(of: ordinal),
                                accent: accent,
                                action: { open(ordinal) }
                            )
                        } else {
                            Color.clear.frame(width: 44, height: 44)
                        }
                    }
                }
            }
        }
    }

    private func open(_ ordinal: Int) {
        onClose()
        model.openArchiveDay(ordinal)
    }

    private func state(of ordinal: Int) -> ArchiveDayState {
        if ordinal > model.todayOrdinal { return .future }
        if model.archive.isSolved(day: ordinal) { return .solved }
        if model.library.inProgressDaily(day: ordinal) != nil { return .inProgress }
        return ordinal == model.todayOrdinal ? .today : .unplayed
    }

    private enum Phrase {
        static let title = "Archive"
        static let close = "Close"
        static let previousMonth = "Previous month"
        static let nextMonth = "Next month"
        static let footnote = "Every past day, regenerated from its date. Solving one never touches your streak."
        static let solved = "solved"
        static let inProgress = "in progress"
        static let today = "today"
        static let unplayed = "not played"
    }

    /// Kept beside `Phrase` so the two never drift; the cell renders the mark,
    /// this names it.
    static func accessibilityLabel(ordinal: Int, state: ArchiveDayState) -> String {
        let date = ArchiveCalendar.longLabel(forDayOrdinal: ordinal)
        switch state {
        case .solved: return "\(date), \(Phrase.solved)"
        case .inProgress: return "\(date), \(Phrase.inProgress)"
        case .today: return "\(date), \(Phrase.today)"
        case .unplayed: return "\(date), \(Phrase.unplayed)"
        case .future: return date
        }
    }
}

enum ArchiveDayState { case solved, inProgress, today, unplayed, future }

private struct ArchiveDayCell: View {
    let ordinal: Int
    let state: ArchiveDayState
    let accent: Color
    let action: () -> Void

    private var dayNumber: String {
        let components = DailySeed.utcCalendar.dateComponents(
            [.day], from: ArchiveCalendar.date(forDayOrdinal: ordinal)
        )
        return "\(components.day!)"
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                background
                if state == .solved {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accent)
                } else {
                    Text(dayNumber)
                        .font(CouchTypography.caption)
                        .foregroundStyle(state == .future ? .tertiary : .secondary)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state == .future)
        .accessibilityLabel(ArchiveSheetContent.accessibilityLabel(ordinal: ordinal, state: state))
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        switch state {
        case .today: shape.fill(accent.opacity(0.28))
        case .inProgress: shape.strokeBorder(accent.opacity(0.55), lineWidth: 1.5)
        case .solved, .unplayed, .future: shape.fill(.clear)
        }
    }
}
#endif
```

- [ ] **Step 2: Regenerate and build iOS**

```bash
cd nine && COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate \
  && xcodebuild -project Nine.xcodeproj -scheme Nine \
     -destination 'generic/platform=iOS Simulator' -derivedDataPath build build
```
Expected: BUILD SUCCEEDED. (The file is not yet reachable from any screen — Task 7 wires it.)

- [ ] **Step 3: Commit**

```bash
git add nine/Sources/App/ArchiveSheet.swift
git commit -m "Nine: ArchiveSheet — the month grid (PRD-14)"
```

---

### Task 7: `TouchUI` — the way in and the way it says where you are

**Files:**
- Modify: `nine/Sources/App/TouchUI.swift:21-23` (state), `:79-80` (overlays), `:137-153` (`todayCard`), `:698-704` (`composingChip`), and the game screen's chip overlay.

**Interfaces:**
- Consumes: `ArchiveSheetContent` (Task 6), `AppModel.archiveDay` (Task 5), `ArchiveCalendar.shortLabel(forDayOrdinal:)` (Task 4).
- Produces: nothing downstream.

`TouchUI.swift` owns both the iPhone shelf and the game screen, so this is the one file EXECUTING-A-PRD §7 forbids sharing. No other PRD may be in flight while this task runs.

- [ ] **Step 1: Add the sheet state and overlay**

Beside `@State private var showBoards = false`:

```swift
    @State private var showArchive = false
```

Beside the two existing sheet overlays:

```swift
        .overlay {
            GlassSheet(isPresented: $showArchive) {
                ArchiveSheetContent(model: model, onClose: { showArchive = false })
            }
        }
```

- [ ] **Step 2: Add the Today-card affordance**

Replace `todayCard` with:

```swift
    private var todayCard: some View {
        TouchCard(action: { model.openToday() }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today")
                            .couchText(CouchTypography.title)
                        Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                            .font(CouchTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // PRD-14. Nested in the card exactly as the Continue card's
                    // discard ✕ is: the archive is a property of the daily, so
                    // it belongs on the daily's card rather than earning a
                    // seventh row on a shelf that is already long.
                    Button { showArchive = true } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(.accessibility, Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Archive")
                }
                Spacer(minLength: 12)
                todayStatus
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        }
        // Composing the daily is its own state on this card, so only a *foreign*
        // compose disables it.
        .disabled(composeInFlight && !isComposingDaily)
    }
```

- [ ] **Step 3: Add the in-game chip**

Replace `composingChip` with the pair (an archive board and a compose are mutually exclusive by construction — a composing board is not yet on screen):

```swift
    /// While a replacement board is composed (New game in the sheet), the
    /// old board stays up — this chip is the only sign work is happening,
    /// so it matters on Sharp, which can take tens of seconds.
    @ViewBuilder
    private var composingChip: some View {
        if model.composing != nil, model.game != nil {
            GlassChip("Composing…", systemImage: "sparkles")
                .transition(.opacity)
        } else if let day = model.archiveDay, model.game != nil {
            // PRD-14: a past day looks exactly like today's board, so the one
            // thing the screen owes the player is which day they are on.
            GlassChip("Archive · \(ArchiveCalendar.shortLabel(forDayOrdinal: day))",
                      systemImage: "calendar")
                .transition(.opacity)
        }
    }
```

- [ ] **Step 4: Confirm `NineShared` is imported by `TouchUI.swift`**

```bash
cd nine && grep -n "^import" Sources/App/TouchUI.swift
```
If `NineShared` is absent, add `import NineShared` beside the other imports.

- [ ] **Step 5: Build all three platforms**

```bash
cd nine && COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate
for dest in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$dest" -derivedDataPath build build || break
done
```
Expected: BUILD SUCCEEDED ×3. tvOS and macOS must build even though neither shows the archive — `ArchiveSheet.swift` is `#if os(iOS)` and `archiveDay` is not.

- [ ] **Step 6: Commit**

```bash
git add nine/Sources/App/TouchUI.swift
git commit -m "Nine: the archive's way in, and the chip that says which day you are on (PRD-14)"
```

---

### Task 8: Verify by driving it, re-record the AX baseline, record the deviations

**Files:**
- Modify: `nine/Tests/AXBaselines/home.txt` (re-record)
- Modify: `nine/DEVIATIONS.md` (append a PRD-14 section)

- [ ] **Step 1: Full suite and a Release archive**

```bash
cd nine && time swift test
xcodebuild archive -project Nine.xcodeproj -scheme Nine \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath /tmp/NineRelease.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```
Expected: 0 failures, under ~120 s; ARCHIVE SUCCEEDED. Record the wall-clock number — DEVIATIONS wants the measurement, not an adjective.

- [ ] **Step 2: Drive the five checks from PRD-14 §5**

Install on an iPhone simulator (see the `run-couch-suite` skill; prefer `sim-use` over `axe` on iOS 26.x) and confirm, with a screenshot each:

1. Note `displayedStreak` on the shelf. Open Archive, solve a past day, return. **The streak number is unchanged** and the day now carries a check.
2. Reopen the same past day: the partial resumes rather than composing a fresh board.
3. Tap today in the grid: it opens the same entry the Today card opens — check the Boards sheet shows **one** entry for today, not two.
4. Screenshot the populated month grid and the in-game "Archive · <day>" chip.
5. tvOS still builds and shows no archive anywhere.

- [ ] **Step 3: Re-record the home AX baseline**

The Today card gained a button, so the shelf's tree moved. Re-record only that screen and check the element count moved by exactly one before trusting it (a silent screen-for-screen substitution looks like a successful recording):

```bash
cd nine && python3 scripts/ax-snapshot.py --record --only home
git diff --stat nine/Tests/AXBaselines/home.txt
```
Expected: one new `Archive` button at 44×44, nothing else.

**No `archive` screen is added to the lane, deliberately.** Every label in the grid is derived from today's date, so a baseline would rot overnight and again at every month boundary — `AXFixtureTests` can freeze a board but nothing can freeze "today". The archive's accessibility strings are pinned in `ArchiveCalendarTests` instead, which is the move PRD-19 already made for the Voice Control input labels no dump can see.

- [ ] **Step 4: Append to `nine/DEVIATIONS.md`**

A `## PRD-14 — the daily archive, and the checkmark that had nowhere to live (2026-07-26)` section covering, with the measured numbers:

- The library's 20-entry `playedCap` versus PRD-14 §2's "read the library entry", and why `ArchiveLedger` is its own cloud-synced blob (with the ~22 KB / 10-year size figure and the rejected range compression).
- The streak guard as a bug fix rather than defence in depth, with the fresh-install repro.
- The absolute daily-seed pin (`testDailySeedForAKnownDayIsFrozen`) — the mapping every daily and every shared seed rests on had never been frozen absolutely before.
- The UTC label trap and the timezone test.
- The floor at Nine's launch month rather than infinite scroll, and why.
- **Not done:** the PRD-9 heat-grid tap seam (cross-platform `HistorySheet` versus an iOS-only sheet, and the one-secondary-surface rule); tvOS/macOS archives; per-day stats. And: `ArchiveDemo` / `-uxdemo.archive` needed no deletion — PRD-18 removed the whole rig already.
- The `swift test` wall clock from Step 1.

- [ ] **Step 5: Commit and open the PR**

```bash
git add nine/Tests/AXBaselines/home.txt nine/DEVIATIONS.md
git commit -m "Nine: verify the archive on device, re-record home AX, record the deviations (PRD-14)"
git push -u origin ngoldbla/pretoria
gh pr create --base main --title "Nine: the daily archive (PRD-14)" --body "…"
```
