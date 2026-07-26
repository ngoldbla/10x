# Share your solve (PRD-12) + Streak grace (PRD-13) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A finished board becomes a shareable glass card, and a single missed
day quietly bridges the streak instead of breaking it.

**Architecture:** PRD-13 is engine-first — `StreakState` gains `lastGraceDay`
and one predicate (`graceAvailable`) that both the bridge rule and the shield
glyph read, so the two can never disagree. PRD-12 splits the card into a pure
`SolveCardFacts` value (Linux-tested, `Sources/Shared`) and a `ShareCard<Content>`
chrome whose body is a generic slot — `SolvedGridThumb` fills it today, PRD-26's
comet fills it later, at identical geometry.

**Tech Stack:** Swift 6, SwiftUI, `ImageRenderer`, `ShareLink`, XCTest,
CouchKit (`GlassChip`, `couchGlass`), `CouchStored` JSON blobs.

## Global Constraints

- **Covenant (PRD-7 §1):** no IAP, no gamification, no notifications, **no
  streak shaming**. The share button waits, never asks. No "shields remaining"
  counter anywhere.
- **Tolerant decode is law.** `CouchStored` discards the *whole blob* when a
  decode throws. Every persisted type gets a hand-written `init(from:)`.
- **`SolveStep` / `LibraryEntry` / `NineMove.Kind` / `GeneratedPuzzle` gain no
  fields.** Golden corpus must read **56/56 after every engine commit**:
  `cd nine && swift test --filter GoldenCorpus`.
- **Do not bump `WidgetSnapshot.currentSchemaVersion`** — `load` rejects
  `schemaVersion > current`, so a bump blanks the widget. Additive optional
  field only.
- **The control bar is full** (DEVIATIONS, PRD-11): six 44 pt buttons = 322 pt
  on a 375 pt phone. The share button goes **beside the completion chip**, never
  in the bar.
- Copy lives in one `Phrase` block per file (PRD-20 seam). No scattered literals.
- Run from `nine/`: `swift test`, then `xcodebuild` for iOS **and** tvOS **and**
  macOS (shared model field touches all three).

---

### Task 1: `StreakState` — the grace truth table

**Files:**
- Modify: `nine/Sources/Engine/Game.swift:358-414`
- Test: `nine/Tests/EngineTests/GameTests.swift:256-346`

**Interfaces:**
- Produces: `StreakState.lastGraceDay: Int?`, `StreakState.graceAvailable: Bool`,
  `StreakState.standsOnGrace: Bool`. `displayedStreak(today:)` keeps its
  signature and changes meaning.

- [ ] **Step 1: Write the failing tests** — append to the `// MARK: - Streaks`
  section of `GameTests.swift`:

```swift
    // MARK: - Streak grace (PRD-13 §2)

    func testOneMissedDayBridgesInsteadOfBreaking() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 101)
        streak.recordCompletion(day: 103)           // 102 missed
        XCTAssertEqual(streak.current, 3, "the chain extends across the gap")
        XCTAssertEqual(streak.lastGraceDay, 102)
        XCTAssertTrue(streak.standsOnGrace)
    }

    func testBridgeThenNaturalThenBridgeIsAllowed() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 102)           // bridge 101
        XCTAssertTrue(streak.standsOnGrace)
        streak.recordCompletion(day: 103)           // a natural day re-earns it
        XCTAssertFalse(streak.standsOnGrace)
        XCTAssertTrue(streak.graceAvailable)
        streak.recordCompletion(day: 105)           // bridge 104
        XCTAssertEqual(streak.current, 4)
        XCTAssertEqual(streak.lastGraceDay, 104)
    }

    func testTwoBridgesBackToBackBreakTheStreak() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 102)           // bridge 101
        XCTAssertEqual(streak.current, 2)
        XCTAssertFalse(streak.graceAvailable, "no natural day has been earned since")
        streak.recordCompletion(day: 104)           // would bridge 103 — refused
        XCTAssertEqual(streak.current, 1, "non-stacking: the chain restarts")
        XCTAssertEqual(streak.best, 2)
    }

    func testTwoConsecutiveMissedDaysAlwaysBreak() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 101)
        streak.recordCompletion(day: 104)           // 102 and 103 missed
        XCTAssertEqual(streak.current, 1)
        XCTAssertNil(streak.lastGraceDay, "a gap too wide to bridge spends nothing")
    }

    func testGraceNeverInflatesBest() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 102)
        XCTAssertEqual(streak.best, 2, "best counts the chain, bridge included")
    }

    /// The display rule and the bridge rule are the same predicate, so the
    /// chip can never promise a streak the next solve would break.
    func testDisplayedStreakHoldsThroughAGapOnlyWhileABridgeRemains() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 101)
        XCTAssertEqual(streak.displayedStreak(today: 103), 2, "one silent day is bridgeable")
        XCTAssertEqual(streak.displayedStreak(today: 104), 0, "two is not")

        var spent = StreakState()
        spent.recordCompletion(day: 100)
        spent.recordCompletion(day: 102)            // bridge spent on 101
        XCTAssertEqual(spent.displayedStreak(today: 103), 2, "alive: yesterday")
        XCTAssertEqual(
            spent.displayedStreak(today: 104), 0,
            "the bridge is spent, so solving today would restart at 1 — say so now"
        )
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd nine && swift test --filter GameTests 2>&1 | tail -30`
Expected: FAIL — `value of type 'StreakState' has no member 'lastGraceDay'`.

- [ ] **Step 3: Implement.** Replace `Game.swift:358-414` with:

```swift
public struct StreakState: Sendable, Codable, Equatable {
    public private(set) var current: Int
    public private(set) var best: Int
    public private(set) var lastCompletedDay: Int?
    /// The single missed day a bridge is currently spent on (PRD-13 §2), or
    /// nil if no bridge has ever been used. Never a count: there is no
    /// currency here, and nothing in the app may render this as one.
    public private(set) var lastGraceDay: Int?
    /// Unknown siblings at the top level of `nine.streak`, carried so this
    /// build's rewrite cannot strip a newer build's key.
    private var carriedTopLevel: [String: RawJSON]

    public init() {
        current = 0
        best = 0
        lastCompletedDay = nil
        lastGraceDay = nil
        carriedTopLevel = [:]
    }

    public func hasCompleted(day: Int) -> Bool { lastCompletedDay == day }

    /// Is a bridge there to spend?
    ///
    /// PRD-13 §2's non-stacking rule, verbatim: a bridge is allowed only once
    /// at least one *natural* day-after-day completion has happened since the
    /// last one. Two missed days in a row therefore always break, and no
    /// player can chain grace indefinitely.
    public var graceAvailable: Bool {
        guard let bridged = lastGraceDay, let last = lastCompletedDay else { return true }
        return last > bridged + 1
    }

    /// Does the streak stand *because* of a bridge right now?
    ///
    /// Exactly `!graceAvailable`, and that identity is the point: after a
    /// bridge `lastCompletedDay == lastGraceDay + 1` precisely, and the next
    /// natural completion makes it `> lastGraceDay + 1` in the same move that
    /// re-earns the grace. One predicate drives the shield glyph, the "your
    /// streak held" card and the bridge rule, so the three cannot disagree
    /// about whether a streak is being held.
    public var standsOnGrace: Bool { !graceAvailable }

    /// Record a daily completion. Same day twice is a no-op; the day after the
    /// last completion extends the streak; **exactly one** missed day bridges
    /// when a bridge is available; anything else restarts at 1.
    public mutating func recordCompletion(day: Int) {
        if let last = lastCompletedDay {
            guard day > last else { return }
            if day == last + 1 {
                current += 1
            } else if day == last + 2, graceAvailable {
                current += 1
                lastGraceDay = day - 1
            } else {
                current = 1
            }
        } else {
            current = 1
        }
        lastCompletedDay = day
        best = max(best, current)
    }

    /// Record a daily completion that is allowed to count only when it is not
    /// in the past (PRD-14 §2), where `openedOn` is the day the board was
    /// created. Every app-layer call goes through this form.
    ///
    /// The daily archive lets any past day be played, and a past solve must
    /// never rewrite streak state. `recordCompletion(day:)` cannot enforce that
    /// on its own: its `day > last` guard does nothing while `lastCompletedDay`
    /// is nil, so a fresh install solving *yesterday* from the archive would
    /// set `lastCompletedDay = yesterday` and `displayedStreak(today:)` would
    /// report a one-day streak nobody earned.
    ///
    /// **The discriminator is provenance, not the clock.** The obvious guard —
    /// compare `day` against *today* at the moment of the solve — is wrong, and
    /// wrong on the ordinary path rather than the archive one: a player who
    /// opens today's daily at 23:55 and places the last digit at 00:03 has
    /// `day == today - 1` by then, and a clock-based guard throws away a streak
    /// they genuinely earned. A board created on its own day is the real daily
    /// however late it is finished; a board created *after* the day it is for
    /// can only have come from the archive.
    public mutating func recordCompletion(day: Int, openedOn: Int) {
        guard openedOn <= day else { return }
        recordCompletion(day: day)
    }

    /// The streak shown on the shelf.
    ///
    /// PRD-13 §2 words this as an unconditional `last >= today - 2`, and that
    /// wording composes badly with its own non-stacking rule: with the bridge
    /// already spent, the chip would show "12 day streak" through the silent
    /// day and then flip to **1** the instant the player solved — punishing
    /// them at the exact moment of success, which is the cliff this PRD exists
    /// to remove, moved one day later. So the window opens only while a bridge
    /// remains, and the chip never promises a chain the next solve would break.
    public func displayedStreak(today: Int) -> Int {
        guard let last = lastCompletedDay else { return 0 }
        if last >= today - 1 { return current }
        if last == today - 2, graceAvailable { return current }
        return 0
    }
}
```

  Note: `carriedTopLevel` is declared here but its coding is Task 2 — this step
  will not compile until then, so **do Task 2's Step 3 before running tests.**
  (Kept in one edit because the stored property and its decode are one thought.)

- [ ] **Step 4: Update the two tests that assert the old cliff**

`GameTests.swift:287-293` — the "older chains lapse" vantage moves out by one
day, because one silent day is now bridgeable:

```swift
    func testDisplayedStreakLapsesWhenStale() {
        var streak = StreakState()
        streak.recordCompletion(day: 100)
        streak.recordCompletion(day: 101)
        XCTAssertEqual(streak.displayedStreak(today: 101), 2)
        XCTAssertEqual(streak.displayedStreak(today: 102), 2, "yesterday's chain is alive")
        XCTAssertEqual(streak.displayedStreak(today: 103), 2, "PRD-13: one silent day is bridged")
        XCTAssertEqual(streak.displayedStreak(today: 104), 0, "two silent days lapse")
    }
```

Then run `grep -n "displayedStreak\|recordCompletion" nine/Tests/EngineTests/GameTests.swift`
and check every remaining assertion against the new table by hand; fix any that
assumed a one-day window. `testStreakResetsAfterAGapButKeepsBest` (100, 101,
105 — a three-day gap) is unaffected and must stay green untouched.

- [ ] **Step 5: Run the suite + the corpus**

Run: `cd nine && swift test --filter GameTests && swift test --filter GoldenCorpus`
Expected: PASS; corpus **56/56**.

- [ ] **Step 6: Commit**

```bash
git add nine/Sources/Engine/Game.swift nine/Tests/EngineTests/GameTests.swift
git commit -m "PRD-13: one missed day bridges the streak (engine rules)"
```

---

### Task 2: `StreakState` — tolerant decode and the downgrade it cannot survive

**Files:**
- Modify: `nine/Sources/Engine/Game.swift` (append coding to `StreakState`)
- Test: `nine/Tests/EngineTests/TolerantDecodeTests.swift`

**Interfaces:**
- Consumes: `StreakState.lastGraceDay`, `carriedTopLevel` from Task 1.
- Produces: nothing new — `StreakState` stays `Codable`.

**Why this is not optional:** `nine.streak` is its own `CouchStored` blob with
`StreakState` as its *root*, and that root currently has **synthesized**
`Codable`. A single malformed byte throws, `CouchStored` discards the blob, and
the player's streak silently resets to zero — the one number a streak app owes
them. Adding a field is the moment to fix it.

- [ ] **Step 1: Write the failing tests** — append to `TolerantDecodeTests.swift`:

```swift
    // MARK: - StreakState (PRD-13)

    func testStreakDecodesAPreGraceBlobUnchanged() throws {
        let legacy = Data(#"{"current":12,"best":30,"lastCompletedDay":9500}"#.utf8)
        let streak = try JSONDecoder().decode(StreakState.self, from: legacy)
        XCTAssertEqual(streak.current, 12)
        XCTAssertEqual(streak.best, 30)
        XCTAssertEqual(streak.lastCompletedDay, 9_500)
        XCTAssertNil(streak.lastGraceDay)
        XCTAssertTrue(streak.graceAvailable, "no recorded bridge means one is there to spend")
    }

    func testStreakSurvivesGarbageInEveryField() throws {
        let junk = Data(#"{"current":"twelve","best":null,"lastCompletedDay":[1],"lastGraceDay":{}}"#.utf8)
        let streak = try JSONDecoder().decode(StreakState.self, from: junk)
        XCTAssertEqual(streak, StreakState(), "unreadable reads as fresh, never as a thrown blob")
    }

    func testStreakSurvivesAnEntirelyUnkeyedBlob() throws {
        let streak = try JSONDecoder().decode(StreakState.self, from: Data("[]".utf8))
        XCTAssertEqual(streak, StreakState())
    }

    func testStreakCarriesAnUnknownSiblingKeyThroughARewrite() throws {
        let future = Data(#"{"current":3,"best":3,"lastCompletedDay":9500,"restDays":[9499]}"#.utf8)
        var streak = try JSONDecoder().decode(StreakState.self, from: future)
        streak.recordCompletion(day: 9_501)
        let rewritten = try JSONEncoder().encode(streak)
        let tree = try XCTUnwrap(
            JSONSerialization.jsonObject(with: rewritten) as? [String: Any]
        )
        XCTAssertNotNil(tree["restDays"], "a newer build's key survives this build's autosave")
        XCTAssertEqual(tree["current"] as? Int, 4)
    }

    func testStreakRoundTripsAGraceBridge() throws {
        var streak = StreakState()
        streak.recordCompletion(day: 9_500)
        streak.recordCompletion(day: 9_502)
        let decoded = try JSONDecoder().decode(
            StreakState.self, from: JSONEncoder().encode(streak)
        )
        XCTAssertEqual(decoded, streak)
        XCTAssertEqual(decoded.lastGraceDay, 9_501)
        XCTAssertTrue(decoded.standsOnGrace)
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd nine && swift test --filter TolerantDecode 2>&1 | tail -20`
Expected: FAIL (compile error on `lastGraceDay`, or thrown decodes).

- [ ] **Step 3: Implement** — append inside `StreakState`, after
  `displayedStreak(today:)`:

```swift
    // MARK: - Coding (the persistence covenant)

    private enum CodingKeys: String, CodingKey {
        case current, best, lastCompletedDay, lastGraceDay
    }

    /// Nothing in here throws. `CouchStored` discards the entire blob when a
    /// decode does, and a lost `nine.streak` is the player's whole history with
    /// the habit — reset to zero, silently, with no way back.
    ///
    /// Modelled on `ArchiveLedger`, including `carriedTopLevel`. That carry is
    /// forward protection only, and it is worth being plain about the limit:
    /// builds 450/451/452 are already on TestFlight with a *synthesized* decode,
    /// so a downgrade to one of them strips `lastGraceDay` on its next write
    /// whatever this build does. The consequence is bounded and it is kindness —
    /// the returning player is offered one bridge they had already spent — which
    /// is why `lastGraceDay` lives here rather than in a blob of its own: an
    /// unbridgeable second store could disagree with the streak it guards, and
    /// two ledgers that disagree about a streak is the PRD-14 bug all over again.
    public init(from decoder: any Decoder) throws {
        current = 0
        best = 0
        lastCompletedDay = nil
        lastGraceDay = nil
        carriedTopLevel = [:]
        if let anyKey = try? decoder.container(keyedBy: RawJSON.RawKey.self) {
            let known = Set(CodingKeys.allCases.map(\.stringValue))
            for key in anyKey.allKeys where !known.contains(key.stringValue) {
                carriedTopLevel[key.stringValue] =
                    (try? anyKey.decode(RawJSON.self, forKey: key)) ?? .null
            }
        }
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        current = (try? c.decode(Int.self, forKey: .current)) ?? 0
        best = (try? c.decode(Int.self, forKey: .best)) ?? 0
        lastCompletedDay = try? c.decode(Int.self, forKey: .lastCompletedDay)
        lastGraceDay = try? c.decode(Int.self, forKey: .lastGraceDay)
        // Repair rather than trust: `best` is a high-water mark by definition,
        // and a hand-edited blob must not be able to make it a low one.
        best = max(best, current)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: RawJSON.RawKey.self)
        for key in carriedTopLevel.keys.sorted() {
            try container.encode(carriedTopLevel[key]!, forKey: RawJSON.RawKey(key))
        }
        try container.encode(current, forKey: RawJSON.RawKey(CodingKeys.current.stringValue))
        try container.encode(best, forKey: RawJSON.RawKey(CodingKeys.best.stringValue))
        try container.encodeIfPresent(
            lastCompletedDay, forKey: RawJSON.RawKey(CodingKeys.lastCompletedDay.stringValue)
        )
        try container.encodeIfPresent(
            lastGraceDay, forKey: RawJSON.RawKey(CodingKeys.lastGraceDay.stringValue)
        )
    }
```

  Add `CaseIterable` to the `CodingKeys` declaration
  (`private enum CodingKeys: String, CodingKey, CaseIterable`).

  Then make `Equatable` explicit so `carriedTopLevel` stays out of identity —
  every test above builds a `StreakState()` by hand and compares it to a decoded
  one, exactly as `ArchiveLedger` does:

```swift
extension StreakState {
    /// Identity is the four facts. The carried trees are an encoding detail,
    /// and excluding them is load-bearing (see `ArchiveLedger`).
    public static func == (lhs: StreakState, rhs: StreakState) -> Bool {
        lhs.current == rhs.current && lhs.best == rhs.best
            && lhs.lastCompletedDay == rhs.lastCompletedDay
            && lhs.lastGraceDay == rhs.lastGraceDay
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `cd nine && swift test --filter TolerantDecode && swift test --filter GameTests`
Expected: PASS both.

- [ ] **Step 5: Run the corpus and the drill**

Run: `cd nine && swift test --filter GoldenCorpus && swift test --filter DowngradeDrill`
Expected: corpus **56/56**; drill PASS.

- [ ] **Step 6: Commit**

```bash
git add nine/Sources/Engine/Game.swift nine/Tests/EngineTests/TolerantDecodeTests.swift
git commit -m "PRD-13: nine.streak decodes tolerantly and carries unknown keys"
```

---

### Task 3: The widget mirror moves in lockstep

**Files:**
- Modify: `nine/Sources/Shared/WidgetSnapshot.swift:25-72`
- Modify: `nine/Sources/App/WidgetBridge.swift` (the snapshot build site)
- Test: `nine/Tests/SharedTests/WidgetSnapshotTests.swift:45-72, 110-135`

**Interfaces:**
- Consumes: `StreakState.lastGraceDay`, `StreakState.graceAvailable`.
- Produces: `WidgetSnapshot.lastGraceDay: Int?` (memberwise-init parameter,
  defaulted `nil`, placed **after** `lastCompletedDay`).

**Why:** `WidgetSnapshot.displayedStreak` is a deliberate duplicate of the
engine's, and `testDisplayedStreakMatchesEngine` cross-checks them. Leave it
behind and the widget shows a lapsed flame the app still shows lit — on the one
surface a player glances at without opening anything.

- [ ] **Step 1: Write the failing test** — replace the body of
  `testDisplayedStreakMatchesEngine`'s `assertAgreement` so it copies the new
  fact, and add a bridge to the sequence it drives:

```swift
        func assertAgreement(_ label: String) {
            let snapshot = WidgetSnapshot(
                streakCurrent: streak.current,
                streakBest: streak.best,
                lastCompletedDay: streak.lastCompletedDay,
                lastGraceDay: streak.lastGraceDay
            )
            for vantage in (today - 2)...(today + 3) {
                XCTAssertEqual(
                    snapshot.displayedStreak(today: vantage),
                    streak.displayedStreak(today: vantage),
                    "\(label) at vantage \(vantage)"
                )
            }
        }

        assertAgreement("empty streak")
        streak.recordCompletion(day: today - 4)
        streak.recordCompletion(day: today - 3)
        assertAgreement("lapsed chain")
        streak.recordCompletion(day: today - 1)      // bridges today - 2
        assertAgreement("alive via a bridge")
        streak.recordCompletion(day: today)
        assertAgreement("solved today, bridge re-earned")
        streak.recordCompletion(day: today + 2)      // bridge available again
        assertAgreement("second bridge, after a natural day")
```

  and add, beside it:

```swift
    /// The widget must not offer a bridge the app has already spent.
    func testSnapshotRefusesAStackedBridgeExactlyAsTheEngineDoes() {
        let today = 9_200
        var streak = StreakState()
        streak.recordCompletion(day: today - 4)
        streak.recordCompletion(day: today - 2)      // bridge spent on today - 3
        let snapshot = WidgetSnapshot(
            streakCurrent: streak.current,
            streakBest: streak.best,
            lastCompletedDay: streak.lastCompletedDay,
            lastGraceDay: streak.lastGraceDay
        )
        XCTAssertEqual(snapshot.displayedStreak(today: today), 0)
        XCTAssertEqual(snapshot.displayedStreak(today: today), streak.displayedStreak(today: today))
    }
```

  Then fix the explicit-value test at `WidgetSnapshotTests.swift:110-135`: with
  `lastGraceDay` nil the flame now lapses at `today + 3`, not `today + 2`.
  Change the "Two days later without a solve" block to:

```swift
        // Two days later without a solve: one silent day is bridged (PRD-13).
        XCTAssertEqual(snapshot.displayedStreak(today: today + 2), 5)
        // Three days later: two silent days, and the flame lapses.
        XCTAssertEqual(snapshot.displayedStreak(today: today + 3), 0)
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd nine && swift test --filter WidgetSnapshot 2>&1 | tail -20`
Expected: FAIL — extra argument `lastGraceDay` in call.

- [ ] **Step 3: Implement.** In `WidgetSnapshot.swift`, add the stored property
  after `lastCompletedDay` (line 28) and the matching init parameter and
  assignment, then replace `displayedStreak`:

```swift
    /// The single missed day the streak's bridge is spent on, mirrored from
    /// `StreakState.lastGraceDay`. Never rendered — the widget shows no shield.
    public var lastGraceDay: Int?
```

```swift
    /// Mirrors `StreakState.graceAvailable` (cross-checked by unit test).
    public var graceAvailable: Bool {
        guard let bridged = lastGraceDay, let last = lastCompletedDay else { return true }
        return last > bridged + 1
    }

    /// The streak a widget shows at `today`: yesterday's chain is alive, and one
    /// silent missed day is bridged while a bridge remains (PRD-13 §2). Mirrors
    /// `StreakState.displayedStreak` (cross-checked by unit test).
    public func displayedStreak(today: Int) -> Int {
        guard let last = lastCompletedDay else { return 0 }
        if last >= today - 1 { return streakCurrent }
        if last == today - 2, graceAvailable { return streakCurrent }
        return 0
    }
```

  **Do not touch `currentSchemaVersion`.** `Int?` decodes via `decodeIfPresent`,
  so a pre-grace snapshot on disk reads as nil, which is "a bridge is there" —
  the same answer a fresh install gives.

- [ ] **Step 4: Wire the fact through `WidgetBridge`**

Run: `grep -n "lastCompletedDay" nine/Sources/App/WidgetBridge.swift` and add
`lastGraceDay: model.streak.lastGraceDay` to the `WidgetSnapshot(...)` literal,
immediately after the `lastCompletedDay:` argument.

- [ ] **Step 5: Run to verify they pass**

Run: `cd nine && swift test --filter WidgetSnapshot`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add nine/Sources/Shared/WidgetSnapshot.swift nine/Sources/App/WidgetBridge.swift \
        nine/Tests/SharedTests/WidgetSnapshotTests.swift
git commit -m "PRD-13: the widget's streak mirror learns about the bridge"
```

---

### Task 4: `AppModel` — the grace surface and the once-per-bridge flag

**Files:**
- Modify: `nine/Sources/App/AppModel.swift` (stores ~line 411, derived ~line 711)

**Interfaces:**
- Produces: `AppModel.streakHeld: Bool`, `AppModel.pendingGraceDay: Int?`,
  `AppModel.acknowledgeGrace()`.

- [ ] **Step 1: Add the store.** After the `archiveStore` declaration
  (`AppModel.swift:410-411`):

```swift
    /// The `lastGraceDay` whose "your streak held" card has been seen, or 0 for
    /// none. A bare `Int` blob rather than a ledger: there is exactly one live
    /// bridge at a time (PRD-13's non-stacking rule guarantees it), so an
    /// ordinal is the whole state, and `CouchStored` already falls back to the
    /// default when an `Int` fails to decode. Cloud-synced, so a bridge
    /// acknowledged on the phone does not greet the player again on the Mac.
    @ObservationIgnored private let graceSeenStore =
        CouchStored(wrappedValue: 0, "nine.graceSeen", cloudSynced: true)
    private(set) var graceSeenDay: Int {
        didSet { graceSeenStore.wrappedValue = graceSeenDay }
    }
```

  Then add `graceSeenDay = graceSeenStore.wrappedValue` beside
  `streak = streakStore.wrappedValue` in the initializer (`AppModel.swift:559`).

- [ ] **Step 2: Add the derived surface.** Beside `displayedStreak`
  (`AppModel.swift:711`):

```swift
    /// The streak on screen is standing on a bridge right now (PRD-13 §3) —
    /// which is exactly when the chip wears a shield instead of a flame.
    /// Guarded on `displayedStreak` so a bridge that has since lapsed cannot
    /// put a shield on a chip that is no longer drawn.
    var streakHeld: Bool { displayedStreak > 0 && streak.standsOnGrace }

    /// The bridged day still owed a card, or nil. One card per bridge, ever:
    /// the ordinal is the identity, so a relaunch, a re-solve and a second
    /// device all resolve to the same one.
    var pendingGraceDay: Int? {
        guard streakHeld, let day = streak.lastGraceDay, day != graceSeenDay else { return nil }
        return day
    }

    /// Dismiss the card. Idempotent.
    func acknowledgeGrace() {
        guard let day = streak.lastGraceDay else { return }
        graceSeenDay = day
        try? graceSeenStore.flushNow()
    }
```

- [ ] **Step 3: Build all three platforms**

```bash
cd nine && COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate
for dest in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$dest" \
    -derivedDataPath build build 2>&1 | tail -3
done
```
Expected: `** BUILD SUCCEEDED **` three times.

- [ ] **Step 4: Commit**

```bash
git add nine/Sources/App/AppModel.swift
git commit -m "PRD-13: AppModel exposes the held streak and the one-per-bridge card"
```

---

### Task 5: The shield glyph on the streak chip

**Files:**
- Create: `nine/Sources/App/StreakChip.swift`
- Modify: `nine/Sources/App/TouchUI.swift:107-109` and `:1351-1382` (ambient slot)
- Modify: `nine/Sources/App/HomeView.swift:79-81`
- Modify: `nine/Sources/App/MacUI.swift:153-155`

**Interfaces:**
- Consumes: `AppModel.displayedStreak`, `AppModel.streakHeld`.
- Produces: `StreakChip(days:held:)`, `StreakChip.label(days:held:)`.

**The one deviation, taken deliberately:** PRD-13 §3 says the chip "gains" a
`shield.lefthalf.filled` glyph. `GlassChip` renders exactly one `systemImage`,
and the two alternatives are worse — a badge floating off a capsule clips at the
top Dynamic Type sizes, and two chips side by side is the sort of accretion the
craft charter's anti-bloat clause exists to refuse. So the shield **replaces**
the flame while a bridge is holding the streak, which also reads truer: the
flame is the streak burning, the shield is the streak being held.

- [ ] **Step 1: Write the failing test** — append to
  `nine/Tests/SharedTests/BoardSpeechTests.swift`… **no.** `StreakChip` is App
  layer and has no test target. Its one testable part is the sentence, so put
  the sentence in `Sources/Shared` where it can be tested, exactly as PRD-19 did
  for the Voice Control names no dump can see. Add to
  `nine/Tests/SharedTests/BoardSpeechTests.swift`:

```swift
    // MARK: - Streak chip (PRD-13 §3)

    func testStreakSpeechNamesTheHoldWithoutShamingTheMiss() {
        XCTAssertEqual(BoardSpeech.streakChip(days: 12, held: false), "12 day streak")
        XCTAssertEqual(BoardSpeech.streakChip(days: 12, held: true), "12 day streak, held")
        XCTAssertEqual(BoardSpeech.streakChip(days: 1, held: false), "1 day streak")
    }

    /// No count, no currency, no "remaining" — PRD-13 §3 forbids all three, and
    /// the spoken string is the one place they would sneak back in.
    func testStreakSpeechNeverCountsShields() {
        for days in [1, 2, 30] {
            for held in [true, false] {
                let text = BoardSpeech.streakChip(days: days, held: held)
                XCTAssertFalse(text.lowercased().contains("shield"), text)
                XCTAssertFalse(text.lowercased().contains("remaining"), text)
            }
        }
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd nine && swift test --filter BoardSpeechTests 2>&1 | tail -10`
Expected: FAIL — no member `streakChip`.

- [ ] **Step 3: Implement the sentence.** In
  `nine/Sources/Shared/BoardSpeech.swift`, add to the public API:

```swift
    /// The streak chip's spoken label. "Held" rather than "shielded": there is
    /// no currency here and no count, and a glyph named in speech is a mechanic
    /// announcing itself (PRD-13 §3).
    public static func streakChip(days: Int, held: Bool) -> String {
        held ? Phrase.streakHeld(days) : Phrase.streak(days)
    }
```

  and to the file's `private enum Phrase` block (line 366):

```swift
    // Streak chip (PRD-13)
    static func streak(_ days: Int) -> String { "\(days) day streak" }
    static func streakHeld(_ days: Int) -> String { "\(days) day streak, held" }
```

- [ ] **Step 4: Create `nine/Sources/App/StreakChip.swift`**

```swift
// StreakChip.swift — the shelf's streak capsule, and the one place PRD-13's
// shield is drawn.
//
// Four call sites had grown the same `GlassChip("\(n) day streak",
// systemImage: "flame")` literal — the iOS header, the tvOS header, the Mac
// header and the iOS ambient slot — so the glyph rule lives here once rather
// than being remembered four times.
//
// **The shield replaces the flame; it is not added beside it.** PRD-13 §3 asks
// for a chip that "gains" a glyph, and `GlassChip` renders exactly one: a badge
// floating off a capsule clips at the top Dynamic Type sizes, and two chips is
// accretion. Replacing reads truer anyway — the flame is the streak burning,
// the shield is the streak being held.
//
// The label is `BoardSpeech.streakChip`, not the glyph's own accessibility
// name: unlabelled, VoiceOver reads "shield, left half filled, 12 day streak",
// which announces a mechanic the covenant says does not exist.
import SwiftUI
import CouchKit

struct StreakChip: View {
    let days: Int
    /// The streak currently stands on a grace bridge (PRD-13 §3).
    let held: Bool

    var body: some View {
        GlassChip("\(days) day streak", systemImage: held ? "shield.lefthalf.filled" : "flame")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BoardSpeech.streakChip(days: days, held: held))
    }
}
```

- [ ] **Step 5: Replace the four call sites**

`TouchUI.swift:107-109`, `HomeView.swift:79-81` and `MacUI.swift:153-155` each
become:

```swift
            if model.displayedStreak > 0 {
                StreakChip(days: model.displayedStreak, held: model.streakHeld)
            }
```

`TouchUI.swift`'s `AmbientSlotView` (line ~1364) swaps its symbol and its text
for the same rule:

```swift
            case .streak:
                GlassChip(streakText, systemImage: model.streakHeld ? "shield.lefthalf.filled" : "flame")
```

and its `streakText` helper uses the shared sentence:

```swift
        if model.displayedStreak > 0 {
            parts.append(BoardSpeech.streakChip(days: model.displayedStreak, held: model.streakHeld))
        }
```

- [ ] **Step 6: Run tests + build three platforms**

Run: `cd nine && swift test --filter BoardSpeechTests` — Expected: PASS.
Then the three-destination `xcodebuild` loop from Task 4 Step 3.

- [ ] **Step 7: Commit**

```bash
git add nine/Sources/App/StreakChip.swift nine/Sources/Shared/BoardSpeech.swift \
        nine/Sources/App/TouchUI.swift nine/Sources/App/HomeView.swift \
        nine/Sources/App/MacUI.swift nine/Tests/SharedTests/BoardSpeechTests.swift
git commit -m "PRD-13: the streak chip wears a shield while a bridge holds it"
```

---

### Task 6: "Your streak held" — one calm card, once per bridge

**Files:**
- Modify: `nine/Sources/App/TouchUI.swift:48-97` (the home `VStack`), plus a new
  `private var graceCard` beside `todayCard`

**Interfaces:**
- Consumes: `AppModel.pendingGraceDay`, `AppModel.acknowledgeGrace()`.

**Placement:** directly under the header and **above** the Today card. The
shield the player is being asked about is in the header one row up; the
adjacency is the explanation. iOS only — PRD-13 §3 scopes the card to the home
shelf, and tvOS/macOS keep the shield glyph without it (recorded in DEVIATIONS).

- [ ] **Step 1: Add the card.** In `TouchUI.swift`, beside `todayCard`:

```swift
    /// PRD-13 §3. The morning after a bridged miss, one sentence, once ever per
    /// bridge, and then gone. It is deliberately not a Today-card *action*: a
    /// card that starts a board would make the miss a prompt to play, which is
    /// the nagging PRD-13 exists so the app never has to do. Tapping it only
    /// dismisses it.
    ///
    /// No count, no "1 of 1 used", no settings row — the covenant rules the
    /// currency out, and this card is the entire user-facing surface of the
    /// feature besides the glyph.
    @ViewBuilder
    private var graceCard: some View {
        if model.pendingGraceDay != nil {
            Button {
                withAnimation(.couchFast) { model.acknowledgeGrace() }
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)   // decoration; the sentence says it
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Phrase.graceTitle)
                            .font(CouchTypography.body)
                        Text(Phrase.graceBody)
                            .font(CouchTypography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .couchGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(Phrase.graceTitle). \(Phrase.graceBody)")
            .accessibilityHint(Phrase.graceHint)
            .transition(.opacity)
        }
    }
```

  Add the strings to the file's `Phrase` block (create one at the bottom of
  `TouchUI.swift` if the file has none, following `BoardFingerprint.swift`'s
  shape — a `private enum Phrase` with a `// PRD-20 seam` comment):

```swift
    // PRD-13 §3. "Won't cost you" and not "you're safe": nothing was at risk,
    // because nothing here is a resource.
    static let graceTitle = "Your streak held"
    static let graceBody = "You took yesterday off; one rest day won't cost you."
    static let graceHint = "Dismisses this card"
```

- [ ] **Step 2: Insert it into the shelf.** In the home `VStack`
  (`TouchUI.swift:51-59`), between `header` and `todayCard`:

```swift
                    header
                    graceCard
                    todayCard
```

  and add the animation beside the two existing first-run ones (line 78):

```swift
        .animation(.couchFast, value: model.pendingGraceDay)
```

- [ ] **Step 3: Build iOS**

Run:
```bash
cd nine && xcodebuild -project Nine.xcodeproj -scheme Nine \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add nine/Sources/App/TouchUI.swift
git commit -m "PRD-13: one calm card the morning after a bridged miss"
```

---

### Task 7: `SolveCardFacts` — the card's facts, pure and Linux-tested

**Files:**
- Create: `nine/Sources/Shared/SolveCardFacts.swift`
- Test: `nine/Tests/SharedTests/SolveCardFactsTests.swift`

**Interfaces:**
- Produces: `SolveCardFacts.init(game:difficulty:isDaily:streak:at:)`,
  `.timeLine`, `.creditLine`, `.dailyLine`, `.shareTitle`, `.digits`, `.givens`,
  `SolveCardFacts.elapsedText(_:)`.

**Why a separate value type:** the words on the card must be provable without a
renderer, and PRD-26 needs exactly these facts to caption its comet video. The
card view then holds no logic at all — it is geometry over a struct.

- [ ] **Step 1: Write the failing test** — create
  `nine/Tests/SharedTests/SolveCardFactsTests.swift`:

```swift
import XCTest
@testable import NineShared
@testable import NineEngine

final class SolveCardFactsTests: XCTestCase {

    private func solvedGame() -> NineGame {
        let puzzle = PuzzleGenerator.generate(seed: 0xN1NE, difficulty: .steady)
        var game = NineGame(puzzle: puzzle, startedAt: Date(timeIntervalSinceReferenceDate: 0))
        for cell in 0..<81 where !game.isGiven(cell) {
            game.place(digit: puzzle.solution.cells[cell], at: cell)
        }
        return game
    }

    func testTimeLineReadsAsMinutesAndSeconds() {
        XCTAssertEqual(SolveCardFacts.elapsedText(220), "3:40")
        XCTAssertEqual(SolveCardFacts.elapsedText(9), "0:09")
        XCTAssertEqual(SolveCardFacts.elapsedText(3_725), "62:05", "no hours field; minutes run on")
    }

    func testCreditLineCarriesTheStreakOnlyWhenThereIsOne() {
        let game = solvedGame()
        let withStreak = SolveCardFacts(
            game: game, difficulty: .steady, isDaily: true, streak: 12,
            at: Date(timeIntervalSinceReferenceDate: 220)
        )
        XCTAssertEqual(withStreak.creditLine, "Steady · 12 day streak")

        let noStreak = SolveCardFacts(
            game: game, difficulty: .sharp, isDaily: false, streak: 0,
            at: Date(timeIntervalSinceReferenceDate: 220)
        )
        XCTAssertEqual(noStreak.creditLine, "Sharp")
    }

    /// PRD-12 §2: the streak line is daily-only. A free-play board solved
    /// during a streak must not borrow it.
    func testFreePlayNeverBorrowsTheStreak() {
        let facts = SolveCardFacts(
            game: solvedGame(), difficulty: .gentle, isDaily: false, streak: 30,
            at: Date(timeIntervalSinceReferenceDate: 60)
        )
        XCTAssertEqual(facts.creditLine, "Gentle")
        XCTAssertNil(facts.dailyLine)
    }

    func testDailyGetsItsSecondLineAndNoURL() {
        let facts = SolveCardFacts(
            game: solvedGame(), difficulty: .steady, isDaily: true, streak: 1,
            at: Date(timeIntervalSinceReferenceDate: 60)
        )
        XCTAssertEqual(facts.dailyLine, "Nine · daily puzzle")
        XCTAssertFalse(facts.shareTitle.contains("http"), "no URL spam (PRD-12 §2)")
        XCTAssertFalse(facts.shareTitle.contains("nine.app"))
    }

    func testGridCarriesEveryDigitAndKnowsTheGivens() {
        let game = solvedGame()
        let facts = SolveCardFacts(
            game: game, difficulty: .steady, isDaily: false, streak: 0,
            at: Date(timeIntervalSinceReferenceDate: 60)
        )
        XCTAssertEqual(facts.digits.count, 81)
        XCTAssertEqual(facts.givens.count, 81)
        XCTAssertFalse(facts.digits.contains(0), "a share card is only ever made of a solved board")
        XCTAssertEqual(facts.givens.filter { $0 }.count, game.puzzle.puzzle.cells.filter { $0 != 0 }.count)
    }

    func testTimeLineComesFromTheGameTimerNotTheWallClock() {
        var game = solvedGame()
        game.timer.pause(at: Date(timeIntervalSinceReferenceDate: 220))
        let facts = SolveCardFacts(
            game: game, difficulty: .steady, isDaily: false, streak: 0,
            at: Date(timeIntervalSinceReferenceDate: 99_999)
        )
        XCTAssertEqual(facts.timeLine, "Solved in 3:40")
    }
}
```

  **Before running:** confirm the generator entry point and `NineGame`
  initializer names with
  `grep -n "public static func generate\|public init(puzzle" nine/Sources/Engine/Generator.swift nine/Sources/Engine/Game.swift`
  and fix the two helper lines to match. `0xN1NE` is not a literal — use any
  fixed seed, e.g. `0x9_1_9_1`.

- [ ] **Step 2: Run to verify it fails**

Run: `cd nine && swift test --filter SolveCardFacts 2>&1 | tail -20`
Expected: FAIL — no such module member `SolveCardFacts`.

- [ ] **Step 3: Implement** — create `nine/Sources/Shared/SolveCardFacts.swift`:

```swift
// SolveCardFacts.swift — everything the share card says, with nothing that
// knows how to draw (PRD-12 §2).
//
// The card is a picture that leaves the app and is never seen again in a
// context we control, so its words have to be provable rather than eyeballed
// in a preview. Splitting them out buys three things:
//
//   • they test on Linux CI, beside `BoardSpeech`, which is where the wording
//     of anything the player reads has lived since PRD-19;
//   • `ShareCardView` becomes pure geometry over a struct, with no branching
//     of its own to get wrong;
//   • **PRD-26 gets the seam.** Its comet replaces the card's *body*, not its
//     chrome, and its debrief video needs precisely these captions. A
//     `SolveCardFacts` is what both the still and the loop are captioned from,
//     so the two cannot drift apart.
//
// Pure Foundation plus the Engine's `NineGame`, so no SwiftUI leaks into a
// module the widget extension compiles.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

public struct SolveCardFacts: Equatable, Sendable {

    /// The finished grid, row-major. Every entry is 1...9 — a card is only ever
    /// minted from a solved board.
    public let digits: [Int]
    /// Which of those 81 the puzzle supplied. The card draws these in the
    /// theme's digit tone and the player's own in the accent, so the picture
    /// shows how much of it was theirs.
    public let givens: [Bool]

    /// "Solved in 3:40".
    public let timeLine: String
    /// "Steady · 12 day streak", or just "Steady".
    public let creditLine: String
    /// "Nine · daily puzzle" on a daily, nil otherwise.
    public let dailyLine: String?
    /// The share sheet's subject line. Deliberately carries no URL: PRD-12 §2
    /// makes the wordmark the hook, and a link in the text is the growth-hack
    /// register the brand refuses.
    public let shareTitle: String

    public init(
        game: NineGame,
        difficulty: Difficulty,
        isDaily: Bool,
        streak: Int,
        at now: Date
    ) {
        digits = (0..<81).map { game.entry(at: $0) }
        givens = (0..<81).map { game.isGiven($0) }

        let elapsed = game.timer.elapsed(at: now)
        timeLine = Phrase.solvedIn(Self.elapsedText(elapsed))

        // The streak line is daily-only (PRD-12 §2). A free-play board solved
        // in the middle of a 30-day run has not advanced it, and a card that
        // implied otherwise would be the app's first dishonest pixel.
        if isDaily, streak > 0 {
            creditLine = "\(difficulty.title) · \(Phrase.streak(streak))"
        } else {
            creditLine = difficulty.title
        }
        dailyLine = isDaily ? Phrase.dailyLine : nil
        shareTitle = "\(Phrase.wordmark) · \(timeLine)"
    }

    /// `m:ss`, with the minutes field allowed to run past 60 rather than
    /// growing an hours field — an hour-long sudoku is a real thing and
    /// "1:02:05" reads like a video timestamp on a card this size.
    public static func elapsedText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // PRD-20 seam: these become `LocalizedStringResource` lookups.
    private enum Phrase {
        static let wordmark = "NINE"
        static let dailyLine = "Nine · daily puzzle"
        static func solvedIn(_ clock: String) -> String { "Solved in \(clock)" }
        static func streak(_ days: Int) -> String { "\(days) day streak" }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd nine && swift test --filter SolveCardFacts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add nine/Sources/Shared/SolveCardFacts.swift nine/Tests/SharedTests/SolveCardFactsTests.swift
git commit -m "PRD-12: the share card's facts, pure and testable"
```

---

### Task 8: `ShareCardView` — the chrome, and the slot PRD-26 fills

**Files:**
- Create: `nine/Sources/App/ShareCardView.swift`

**Interfaces:**
- Consumes: `SolveCardFacts`, `ThemeTones`.
- Produces: `ShareCard<Content: View>`, `SolvedGridThumb`, `ShareCardMetrics`,
  `ShareCardRenderer.png(facts:tones:accent:)`.

**The PRD-26 seam, stated plainly:** `ShareCard` is generic over its body and
takes the body as a `@ViewBuilder` slot sized by `ShareCardMetrics.bodySide`.
Today `SolvedGridThumb` fills it. PRD-26 passes its 5-second comet loop instead,
at the same side length and the same origin, and every caption, margin and
wordmark position is already correct — it does not touch this file to do it.
No platform fence: `Canvas`, `ImageRenderer` and `Text` all compile on tvOS, and
PRD-26's tvOS screensaver will want the body. Only `ShareLink` is iOS/macOS, and
that lives in the two already-fenced UI files.

- [ ] **Step 1: Create the file**

```swift
// ShareCardView.swift — a finished board as a gift (PRD-12 §2).
//
// **Not `BoardView`.** The live board carries the Afterglow's Metal pipeline,
// the rose, error state, pencil marks, selection and 81 accessibility children;
// none of that survives being flattened to a PNG, and all of it would have to
// be reasoned about to be sure. This is a fresh Canvas that draws 81 digits and
// nothing else.
//
// **The body is a slot, and that is the whole architecture (PRD-26).** The
// comet replay is going to become this card's animated body, so the chrome —
// margins, captions, wordmark, the body's side and origin — is a layout that
// takes its centre as a generic view. Swapping `SolvedGridThumb` for a comet
// changes one call site and moves no pixels around it.
//
// Rendered at a fixed 1080×1350 in the renderer's own coordinate space, so the
// output is identical on every device and at every Dynamic Type setting: a
// share card is a picture, not a screen, and must not reflow. That is also why
// nothing here uses `CouchTypography`, which is scaled for screens.
import SwiftUI
import CouchKit

/// The card's fixed geometry. One place, so a future body (PRD-26's comet)
/// inherits the exact frame the grid had.
enum ShareCardMetrics {
    /// Portrait, sized for feeds (PRD-12 §2).
    static let size = CGSize(width: 1080, height: 1350)
    static let margin: CGFloat = 96
    /// The body slot is square and spans the card between the margins.
    static var bodySide: CGFloat { size.width - margin * 2 }
    static let wordmarkSize: CGFloat = 64
    static let timeSize: CGFloat = 76
    static let creditSize: CGFloat = 40
    static let dailySize: CGFloat = 30
}

/// The card: a themed backdrop, a square body, three lines of caption.
struct ShareCard<Content: View>: View {
    let facts: SolveCardFacts
    let tones: ThemeTones
    let accent: Color
    /// The card's animated-or-still centre. PRD-26 passes its comet here.
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
                .frame(width: ShareCardMetrics.bodySide, height: ShareCardMetrics.bodySide)

            Spacer(minLength: 48)

            VStack(spacing: 14) {
                Text(facts.timeLine)
                    .font(.system(size: ShareCardMetrics.timeSize, weight: .bold, design: .rounded))
                    .foregroundStyle(tones.digitTone)
                Text(facts.creditLine)
                    .font(.system(size: ShareCardMetrics.creditSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(tones.digitTone.opacity(0.62))
                if let dailyLine = facts.dailyLine {
                    Text(dailyLine)
                        .font(.system(size: ShareCardMetrics.dailySize, weight: .medium, design: .rounded))
                        .foregroundStyle(tones.digitTone.opacity(0.42))
                }
            }

            Spacer(minLength: 40)

            // The wordmark is the whole call to action (PRD-12 §2) — no URL,
            // no "get it on the App Store", no QR code.
            Text("NINE")
                .font(.system(size: ShareCardMetrics.wordmarkSize, weight: .heavy, design: .rounded))
                .kerning(ShareCardMetrics.wordmarkSize * 0.18)
                .foregroundStyle(accent)
        }
        .padding(ShareCardMetrics.margin)
        .frame(width: ShareCardMetrics.size.width, height: ShareCardMetrics.size.height)
        .background(tones.background)
    }
}

/// The still body: 81 digits on the theme's wash, with the 3×3 structure read
/// from gaps rather than drawn rules — the same move `BoardFingerprint` makes,
/// at a size where the digits themselves are legible.
struct SolvedGridThumb: View {
    let facts: SolveCardFacts
    let tones: ThemeTones
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let boxGap = size.width * 0.018
            let cell = (size.width - boxGap * 2) / 9
            let digitSize = cell * 0.62

            for index in 0..<81 {
                let column = index % 9, row = index / 9
                let origin = CGPoint(
                    x: CGFloat(column) * cell + CGFloat(column / 3) * boxGap,
                    y: CGFloat(row) * cell + CGFloat(row / 3) * boxGap
                )
                let box = CGRect(x: origin.x, y: origin.y, width: cell, height: cell)
                context.fill(
                    Path(roundedRect: box.insetBy(dx: cell * 0.035, dy: cell * 0.035),
                         cornerRadius: cell * 0.16),
                    with: .color(tones.gridTone.opacity(tones.isLight ? 0.07 : 0.10))
                )

                // Givens in the theme's digit tone, the player's own in the
                // accent — so the card shows at a glance how much of the board
                // was theirs, which is the thing worth being proud of.
                let isGiven = facts.givens[index]
                var text = context.resolve(
                    Text("\(facts.digits[index])")
                        .font(.system(size: digitSize,
                                      weight: isGiven ? .medium : .semibold,
                                      design: .rounded))
                )
                text.shading = .color(isGiven ? tones.digitTone.opacity(0.72) : accent)
                context.draw(text, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
            }
        }
        // One picture, one sentence: 81 digits in an image's accessibility tree
        // would be unreadable, and the card is decoration around the caption.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(facts.creditLine)
    }
}

/// Flattens a card to PNG bytes.
@MainActor
enum ShareCardRenderer {
    /// `scale: 1` against a 1080-point card gives a 1080-pixel PNG on every
    /// device — the card must not inherit the screen's scale, or an iPhone SE
    /// and a Pro Max would produce different files from the same board.
    static func png(facts: SolveCardFacts, tones: ThemeTones, accent: Color) -> Data? {
        let renderer = ImageRenderer(
            content: ShareCard(facts: facts, tones: tones, accent: accent) {
                SolvedGridThumb(facts: facts, tones: tones, accent: accent)
            }
        )
        renderer.scale = 1
        renderer.isOpaque = true
        #if os(macOS)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #else
        return renderer.uiImage?.pngData()
        #endif
    }

    /// Writes the PNG to a uniquely-named temp file and returns its URL.
    ///
    /// A file URL rather than a `Transferable` image, so the share sheet shows
    /// a real filename and AirDrop/Files/Photos all take it; the name is the
    /// only copy Nine puts in the recipient's file list.
    static func temporaryFile(
        facts: SolveCardFacts, tones: ThemeTones, accent: Color
    ) -> URL? {
        guard let data = png(facts: facts, tones: tones, accent: accent) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nine-\(UUID().uuidString.prefix(8)).png")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }
}
```

- [ ] **Step 2: Build all three platforms**

Run the three-destination loop from Task 4 Step 3.
Expected: `** BUILD SUCCEEDED **` three times (this file is unfenced, so tvOS
compiling it is the check that matters).

- [ ] **Step 3: Commit**

```bash
git add nine/Sources/App/ShareCardView.swift
git commit -m "PRD-12: the share card, with the body PRD-26's comet will fill"
```

---

### Task 9: The share button on iOS

**Files:**
- Modify: `nine/Sources/App/TouchUI.swift:815-844` (`completionChip`)

**Interfaces:**
- Consumes: `ShareCardRenderer.temporaryFile`, `SolveCardFacts`,
  `AppModel.streakHeld`/`displayedStreak`.

**Where and when:** beside the existing completion chip, inside the same
`> 2.4` Afterglow gate — the card waits for the celebration to finish, and the
render (a 1080×1350 `ImageRenderer` pass) therefore never competes with it for a
frame. **Not in the control bar**, which is full at six buttons (DEVIATIONS).

- [ ] **Step 1: Add the state and the render.** Beside the other `@State`
  declarations in the game view:

```swift
    /// The rendered card, written once per solve. `nil` while it renders or if
    /// rendering failed — in which case the button simply never appears, which
    /// is the right failure for a feature the covenant says must never nag.
    @State private var shareCardURL: URL?
```

- [ ] **Step 2: Replace `completionChip`** (`TouchUI.swift:815-837`):

```swift
    @ViewBuilder
    private var completionChip: some View {
        if let solvedAt = model.solvedAt {
            TimelineView(.periodic(from: solvedAt, by: 0.5)) { timeline in
                if timeline.date.timeIntervalSince(solvedAt) > 2.4 {
                    HStack(spacing: 10) {
                        GlassChip(completionText, systemImage: "checkmark")
                        shareButton
                        if case .free(let difficulty)? = model.kind {
                            Button {
                                highlightedDigit = nil
                                model.startFree(difficulty)
                            } label: {
                                GlassChip("Another", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Another \(difficulty.title) board")
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    /// PRD-12. The button waits and never asks: no prompt, no badge, no "share
    /// your streak!" — it sits beside the chip and is ignored at no cost.
    @ViewBuilder
    private var shareButton: some View {
        if let shareCardURL {
            ShareLink(item: shareCardURL, preview: SharePreview(shareTitle)) {
                GlassChip("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share your solve")
        }
    }

    private var shareTitle: String {
        shareFacts.map(\.shareTitle) ?? "Nine"
    }

    /// The facts behind the card, or nil when there is no solved board to
    /// describe. `model.solvedAt` is the clock the timer was paused at, so the
    /// card's time matches the one the completion chip showed.
    private var shareFacts: SolveCardFacts? {
        guard let game = model.game, let solvedAt = model.solvedAt else { return nil }
        let isDaily: Bool
        let difficulty: Difficulty
        switch model.kind {
        case .daily?:
            // An archive board is a real solve and shares like one, but it did
            // not advance the streak, so it must not print one (PRD-14).
            isDaily = true
            difficulty = .steady
        case .free(let d)?:
            isDaily = false
            difficulty = d
        case nil:
            return nil
        }
        return SolveCardFacts(
            game: game,
            difficulty: difficulty,
            isDaily: isDaily,
            streak: model.archiveDay == nil ? model.displayedStreak : 0,
            at: solvedAt
        )
    }
```

- [ ] **Step 3: Render off the celebration.** Attach to the same view that
  hosts `completionChip` (the board's `.overlay(alignment: .bottom)`):

```swift
        .task(id: model.solvedAt) {
            shareCardURL = nil
            guard let facts = shareFacts else { return }
            // After the Afterglow, not during it: the chip itself is gated at
            // 2.4 s, and a 1080×1350 ImageRenderer pass is not something to run
            // against the celebration's frame budget.
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            shareCardURL = ShareCardRenderer.temporaryFile(
                facts: facts,
                tones: model.prefs.theme.tones(for: colorScheme),
                accent: accent
            )
        }
```

  Confirm the view has `@Environment(\.colorScheme) private var colorScheme` and
  an `accent` computed property; the home view has both (`TouchUI.swift:29-32`)
  and the game view should — check with
  `grep -n "colorScheme\|private var accent" nine/Sources/App/TouchUI.swift`.

- [ ] **Step 4: Build iOS**

Run:
```bash
cd nine && xcodebuild -project Nine.xcodeproj -scheme Nine \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add nine/Sources/App/TouchUI.swift
git commit -m "PRD-12: share your solve, beside the completion chip"
```

---

### Task 10: The share button on macOS

**Files:**
- Modify: `nine/Sources/App/MacUI.swift:425-441` (`completionChip`)

**Interfaces:** identical to Task 9. `ShareLink` on macOS presents the standard
`NSSharingServicePicker`, which is what PRD-12 §3 asks for "if free" — it is.

- [ ] **Step 1: Mirror Task 9** into `MacUI.swift`: the `shareCardURL` state,
  the `shareButton` / `shareTitle` / `shareFacts` members verbatim, the
  `.task(id: model.solvedAt)` render, and `shareButton` added to the completion
  chip's row. `MacUI.swift:425-434` currently renders a bare `GlassChip`; wrap
  it in an `HStack(spacing: 10)` with the share button beside it.

- [ ] **Step 2: Build macOS**

Run:
```bash
cd nine && xcodebuild -project Nine.xcodeproj -scheme Nine \
  -destination 'platform=macOS' -derivedDataPath build build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add nine/Sources/App/MacUI.swift
git commit -m "PRD-12: the Mac shares the same card through NSSharingServicePicker"
```

---

### Task 11: Verify by driving it, re-record the AX tree, write it down

**Files:**
- Modify: `nine/Tests/AXBaselines/game.txt`, `home.txt` (re-recorded)
- Modify: `nine/DEVIATIONS.md` (new section), `nine/PROGRAM-2.0.md` (status table)

**A green suite is not evidence** (EXECUTING-A-PRD §5). PRD-14 found three
defects this way that `swift test` could not see.

- [ ] **Step 1: Full suite + all three builds + Release archive**

```bash
cd nine && swift test 2>&1 | tail -20
for dest in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$dest" \
    -derivedDataPath build build 2>&1 | tail -3
done
xcodebuild archive -project Nine.xcodeproj -scheme Nine \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath /tmp/NineRelease.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3
```
Expected: 0 failures, corpus 56/56, four `SUCCEEDED`. Record the wall clock and
the machine's load average — DEVIATIONS wants the number, not an adjective.

- [ ] **Step 2: Drive PRD-12 on an iPhone simulator**

Boot a sim, install, start a free-play Gentle board, long-press Undo for 1.2 s
(`debugFillAlmostAll`), place the last digit, wait past the Afterglow. Confirm:
share chip appears beside "Solved"; tapping presents the share sheet; the
preview thumbnail is the card. Save the screenshots. Then flip the theme to Void
and to Paper in Settings and repeat, saving one PNG of each (PRD-12 §5).

```bash
sim-use describe-ui --device $UDID | grep -i "share"
```

- [ ] **Step 3: Fake a bridge and drive PRD-13**

Seed `nine.streak` in the sim container with a bridged state (the
populated-screenshot seeding pattern: write the JSON blob into the app's
Application Support directory before launch):

```json
{"current":12,"best":30,"lastCompletedDay":<today-1>,"lastGraceDay":<today-2>}
```

Launch and confirm: the header chip shows a **shield**, not a flame; the "Your
streak held" card is above the Today card; tapping it dismisses it; **relaunch
and the card does not come back**. Screenshot each. Then seed
`lastCompletedDay: <today-2>, lastGraceDay: <today-3>` (bridge spent, one silent
day) and confirm the chip is **absent** — the grace-aware display rule refusing
to promise a streak the next solve would break.

- [ ] **Step 4: Re-record the AX baselines**

The completion chip's row gains a button on `game`, and the home shelf gains
the grace card on `home`.

```bash
python3 nine/scripts/ax-snapshot.py                 # see the drift first
python3 nine/scripts/ax-snapshot.py --record --only game
python3 nine/scripts/ax-snapshot.py --record --only home
```

**Check the element count before trusting a `--record`** (PRD-11's lesson: a
silent screen-for-screen substitution looks like success, and the count is the
only tell). `game.txt` should move by exactly the share button; `home.txt` by
exactly the grace card's element. The 81-cell board tree and the 9 box
containers must not move at all — if the container count changes, stop.

- [ ] **Step 5: Run the taste ritual** (PRD-7 / craft charter) and write the
  answers into the PR body: the 11pm-in-bed test, the roommate test, the
  first-flick test, the delete-it-for-a-week test, the idle-pixel test.

- [ ] **Step 6: Write `DEVIATIONS.md`.** New section
  `## PRD-12 + PRD-13 — the gift and the held streak (2026-07-26)`, covering at
  minimum:
  - **The display rule deviates from PRD-13 §2's literal wording**, and why —
    the composition of §2's two rules would have flipped a 12-day chip to 1 at
    the instant of a successful solve.
  - **The shield replaces the flame** rather than joining it, and the three
    alternatives measured against `GlassChip`'s single-glyph API.
  - **`lastGraceDay` lives on `StreakState`, not in its own blob**, and the
    downgrade consequence that buys: builds 450/451/452 strip it, so a
    downgrading player is offered one bridge they had spent. Named as bounded
    and in the kind direction, against the alternative of two ledgers that can
    disagree about one streak (the PRD-14 bug).
  - **Which cliff tests moved, by name**, per PRD-13 §6.
  - **The `WidgetSnapshot` mirror** and why `currentSchemaVersion` did not move.
  - **The PRD-26 seam:** `ShareCard` is generic over its body at
    `ShareCardMetrics.bodySide`; the comet is a call-site change.
  - **Not done:** no tvOS share (no share sheet), no tvOS/macOS grace card (the
    glyph only), and whatever else the build actually left.

- [ ] **Step 7: Update `PROGRAM-2.0.md`'s status table** — PRD-12 and PRD-13
  rows move from "written, **not shipped**" to "**shipped**" with the one-line
  notes the other shipped rows carry.

- [ ] **Step 8: Open the PR**

```bash
git add -A && git commit -m "PRD-12 + PRD-13: verification, baselines, deviations"
git push -u origin ngoldbla/asuncion
gh pr create --base main \
  --title "Nine: share your solve, and a streak that holds (PRD-12 + PRD-13)"
```

---

## Self-review notes

- **Spec coverage.** PRD-12: §2 card contents → Task 7/8; theme+accent → Task 8;
  daily second line → Task 7; button beside chip → Task 9/10; §3 no-tvOS →
  Task 8 (fence-free file, fenced call sites); §4.3 "delete `ShareCardDemo`" →
  **nothing to delete**, PRD-18 removed the whole `-uxdemo` rig (note it in
  DEVIATIONS, as PRD-14 did). PRD-13: §2 truth table → Task 1; tolerant decode →
  Task 2; `displayedStreak` → Task 1 (deviating, per decision); §3 chip glyph →
  Task 5; §3 card → Task 6; §4 non-goals → nothing built; §6 checklist → Task 11.
- **Cross-task type consistency.** `streakHeld` / `standsOnGrace` /
  `graceAvailable` / `pendingGraceDay` / `acknowledgeGrace()` are used in Tasks
  4–6 exactly as Tasks 1 and 4 define them. `SolveCardFacts.init(game:
  difficulty:isDaily:streak:at:)` is called identically in Tasks 7, 9 and 10.
- **Known risk to watch:** Task 1 Step 3 declares `carriedTopLevel` but Task 2
  Step 3 supplies its coding — the tree does not compile between them. Run the
  two tasks back to back and commit only after Task 2's tests pass, or squash.
