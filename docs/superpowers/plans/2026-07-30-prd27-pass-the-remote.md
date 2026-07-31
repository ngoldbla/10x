# PRD-27 "Pass the Remote" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two people share one board on tvOS and iPad, taking alternating timed turns, each player's digits in their own tint, with wrong digits cleared silently at hand-off and both hands credited in the debrief.

**Architecture:** A turn is a window on the board's *existing* clock — `(player, firstMoveIndex, startedAt)` measured against `NineGame.timer`. Deadline and attribution both fall out of that one monotone axis, so turns are contiguous move-log ranges and `Sources/Engine` is untouched. Duel state lives in a new sibling `CouchStored` blob `nine.duel`; a duel board is an ordinary `.free(difficulty)` board that an older build plays correctly without knowing it was a duel.

**Tech Stack:** Swift 6, SwiftUI, XCTest + swift-testing, CouchKit (`CouchStored`, `GlassSheet`, `couchRemote`), xcodegen. Pure layers go in `Sources/Shared` (Linux-clean, no SwiftUI) so `swift test` covers them with no simulator.

## Global Constraints

Copied verbatim from `nine/PRD-27.md`; every task's requirements implicitly include these.

- **`Sources/Engine` gains no file and no changed line.** `LoggedMove`, `NineGame`'s encoded bytes and `SolveReplay.packed` are untouched. `GameKind` gains no case.
- **Nothing is added to `LibraryEntry`** (EXECUTING-A-PRD §2). New per-board state goes in the sibling top-level key `nine.duel`.
- **Golden corpus 56/56 and variant corpus 9/9 after every commit.** Expected trivially green; that expectation is the claim being checked.
- **`Tests/AXBaselines/*.txt` must match with no re-record.** A drift means the duel leaked onto a non-duel board.
- **No new user-facing English literal in view code.** Every string is a row in `EnglishPhrases.table` with a translator comment in `scripts/strings.py`'s `COMMENTS`, reached via `Strings.string(…)` (App) or `Phrasebook.current.string(…)` (Shared).
- **Turn lengths are exactly `brisk = 60`, `standard = 90`, `unhurried = 180`** seconds.
- **No winner is ever declared.** The debrief credits contributions; it does not rank, score, or name one.
- **Player Two's tint is derived, never chosen.** No colour picker, no settings row.
- **`showErrors` is forced `false` for the whole duel**, regardless of `prefs.errorHighlight`.
- **Duel surfaces are tvOS plus `BoardCompositionRules.resolve(width:height:) == .table`.** No `UIDevice`, no `userInterfaceIdiom`, no size class anywhere in the diff.
- **Two players only.** No third seat anywhere in the types.

---

### Task 1: `DuelTint` — the derived partner accent

**Files:**
- Create: `nine/Sources/Shared/DuelTint.swift`
- Test: `nine/Tests/SharedTests/DuelTintTests.swift`

**Interfaces:**
- Consumes: `PaletteRGB`, `SharedPalette.accentsOnDark`, `SharedPalette.accentsOnLight`, `SharedPalette.defaultAccent` (all `nine/Sources/Shared/SharedPalette.swift`).
- Produces: `DuelTint.partner(for: String, isLight: Bool) -> String`, `DuelTint.separation(_ a: PaletteRGB, _ b: PaletteRGB) -> Double`, `DuelTint.coral(isLight: Bool) -> PaletteRGB`.

**Why this is first:** it is a pure function with no dependency on anything else in the PRD, and every later task that shows two tints needs its answer.

- [ ] **Step 1: Write the failing test**

Create `nine/Tests/SharedTests/DuelTintTests.swift`:

```swift
// DuelTintTests.swift — the second tint is derived, and these are the
// properties that make it safe rather than merely different.
import XCTest
@testable import NineShared

final class DuelTintTests: XCTestCase {

    /// PRD-27 §6. The floor is `AppearancePaletteTests.separationFloor` (5.9),
    /// which is the palette's own worst sibling pair under any dichromacy.
    static let floor = 5.9

    func testEveryAccentGetsAPartnerThatIsNotItself() {
        for accent in SharedPalette.accentsOnDark.keys {
            for isLight in [true, false] {
                let partner = DuelTint.partner(for: accent, isLight: isLight)
                XCTAssertNotEqual(partner, accent, "\(accent) partnered with itself")
                XCTAssertNotNil(SharedPalette.accentsOnDark[partner], "\(partner) is not an accent")
            }
        }
    }

    func testEveryPartnerPairClearsTheSeparationFloorAgainstEachOtherAndCoral() {
        for accent in SharedPalette.accentsOnDark.keys.sorted() {
            for isLight in [true, false] {
                let partner = DuelTint.partner(for: accent, isLight: isLight)
                let mine = SharedPalette.accent(accent, isLight: isLight)
                let theirs = SharedPalette.accent(partner, isLight: isLight)
                let coral = DuelTint.coral(isLight: isLight)

                let pair = DuelTint.separation(mine, theirs)
                XCTAssertGreaterThanOrEqual(
                    pair, Self.floor,
                    "\(accent)/\(partner) only \(String(format: "%.2f", pair)) apart (isLight: \(isLight))")

                let vsCoral = DuelTint.separation(theirs, coral)
                XCTAssertGreaterThanOrEqual(
                    vsCoral, Self.floor,
                    "\(partner) only \(String(format: "%.2f", vsCoral)) from coral (isLight: \(isLight))")
            }
        }
    }

    /// Deterministic, because it is persisted: a duel resumed tomorrow must
    /// come back in the same two colours it was played in today.
    func testThePartnerIsDeterministic() {
        for accent in SharedPalette.accentsOnDark.keys {
            let first = DuelTint.partner(for: accent, isLight: false)
            for _ in 0..<20 {
                XCTAssertEqual(DuelTint.partner(for: accent, isLight: false), first)
            }
        }
    }

    /// Total, like every other `SharedPalette` lookup: a duel state written by
    /// a newer build naming an accent this one has never heard of still opens.
    func testAnUnknownAccentResolvesRatherThanTrapping() {
        let partner = DuelTint.partner(for: "chartreuse", isLight: false)
        XCTAssertNotNil(SharedPalette.accentsOnDark[partner])
        XCTAssertNotEqual(partner, SharedPalette.defaultAccent)
    }

    /// Pins the maths itself, so a refactor of `simulate` cannot quietly turn
    /// the separation function into a constant and keep every test above green.
    func testSeparationCollapsesForIdenticalColoursAndIsLargeForOpposites() {
        let blue = PaletteRGB(0.33, 0.68, 0.98)
        XCTAssertEqual(DuelTint.separation(blue, blue), 0, accuracy: 0.001)
        XCTAssertGreaterThan(DuelTint.separation(PaletteRGB(0, 0, 0), PaletteRGB(1, 1, 1)), 50)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd nine && swift test --filter DuelTintTests 2>&1 | tail -20
```
Expected: FAIL — `cannot find 'DuelTint' in scope`.

- [ ] **Step 3: Write the implementation**

Create `nine/Sources/Shared/DuelTint.swift`:

```swift
// DuelTint.swift — which two tints two people can share a board in (PRD-27 §6).
//
// Player One is the player's own accent. Player Two is *derived*, and deriving
// it rather than offering it is the covenant choice: a colour picker for the
// second player is a settings surface, and PRD-16 already established that the
// obvious free hue in the wheel is usually not a usable one — a periwinkle in
// the glacier→lilac gap cannot clear Blueprint's blue ground and stay clear of
// Lilac at once.
//
// The numbers come from `SharedPalette`, which already carries all ten accents
// as triples and is already pinned to `Theme.swift` by a test that reads that
// file as text. So this is not a third copy of the palette; it is arithmetic on
// the second one.
//
// The dichromat matrices below are a deliberate second copy of the ones in
// `Tests/EngineTests/AppearancePaletteTests.swift`, and the alternative was
// worse: extracting them would edit a test that pins nine properties of the
// shipped palette, to save fifty lines of pure arithmetic that cannot drift
// without `DuelTintTests.testSeparationCollapsesForIdenticalColours…` failing.
import Foundation

public enum DuelTint {

    /// The accent a second player gets when the first is playing in `accent`.
    ///
    /// The winner is the accent whose *worst* showing is best: maximise the
    /// minimum separation from the first player's tint and from coral, across
    /// normal vision and all three dichromacies. Ties break on the accent's
    /// name so the answer is stable across launches — this value is persisted,
    /// and a duel resumed tomorrow must come back in the colours it was played
    /// in today.
    ///
    /// Coral is in the comparison because it is not decoration: it is the error
    /// mark, and a second player whose digits look like mistakes is a worse
    /// outcome than a second player who looks like the first.
    public static func partner(for accent: String, isLight: Bool) -> String {
        let mine = SharedPalette.accent(accent, isLight: isLight)
        let coral = self.coral(isLight: isLight)
        let candidates = SharedPalette.accentsOnDark.keys.sorted().filter { $0 != accent }
        var best: (name: String, score: Double)?
        for name in candidates {
            let rgb = SharedPalette.accent(name, isLight: isLight)
            let score = min(separation(rgb, mine), separation(rgb, coral))
            if score > (best?.score ?? -1) { best = (name, score) }
        }
        // Total by construction: `candidates` is non-empty for any input,
        // including an accent string this build has never heard of.
        return best?.name ?? SharedPalette.defaultAccent
    }

    /// `ThemeTones.coral`'s two values, parallel to `Theme.swift`'s dark/light
    /// twin. Only the two components this file compares against are copied —
    /// the rest of `ThemeTones` is board-drawing and copying tones nothing here
    /// renders is how two palettes start to drift (`SharedPalette`'s own rule).
    public static func coral(isLight: Bool) -> PaletteRGB {
        isLight ? PaletteRGB(0.78, 0.25, 0.20) : PaletteRGB(1.00, 0.45, 0.38)
    }

    /// The worst separation between two colours across normal vision and the
    /// three dichromacies — the number that decides whether two players can
    /// tell their own digits apart.
    public static func separation(_ a: PaletteRGB, _ b: PaletteRGB) -> Double {
        var worst = deltaE(a, b)
        for mode in Simulation.allCases {
            worst = min(worst, deltaE(simulate(a, mode), simulate(b, mode)))
        }
        return worst
    }

    // MARK: - Colour maths

    public enum Simulation: CaseIterable, Sendable {
        case protanopia, deuteranopia, tritanopia
    }

    /// Machado (2009) dichromat simulation matrices at full severity, applied
    /// in linear RGB.
    static func simulate(_ c: PaletteRGB, _ mode: Simulation) -> PaletteRGB {
        let m: [[Double]]
        switch mode {
        case .protanopia:
            m = [[0.152286, 1.052583, -0.204868],
                 [0.114503, 0.786281, 0.099216],
                 [-0.003882, -0.048116, 1.051998]]
        case .deuteranopia:
            m = [[0.367322, 0.860646, -0.227968],
                 [0.280085, 0.672501, 0.047413],
                 [-0.011820, 0.042940, 0.968881]]
        case .tritanopia:
            m = [[1.255528, -0.076749, -0.178779],
                 [-0.078411, 0.930809, 0.147602],
                 [0.004733, 0.691367, 0.303900]]
        }
        let r = linear(c.red), g = linear(c.green), b = linear(c.blue)
        return PaletteRGB(
            gamma(m[0][0] * r + m[0][1] * g + m[0][2] * b),
            gamma(m[1][0] * r + m[1][1] * g + m[1][2] * b),
            gamma(m[2][0] * r + m[2][1] * g + m[2][2] * b)
        )
    }

    /// CIE76 ΔE in Lab. Chosen over ΔE2000 because it is the metric the
    /// published dichromat-palette literature quotes, so the floor of 5.9 means
    /// what that literature means by it.
    static func deltaE(_ a: PaletteRGB, _ b: PaletteRGB) -> Double {
        let la = lab(a), lb = lab(b)
        return sqrt(pow(la.0 - lb.0, 2) + pow(la.1 - lb.1, 2) + pow(la.2 - lb.2, 2))
    }

    private static func linear(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func gamma(_ v: Double) -> Double {
        let c = max(0, min(1, v))
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    private static func lab(_ c: PaletteRGB) -> (Double, Double, Double) {
        let r = linear(c.red), g = linear(c.green), b = linear(c.blue)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 1.00000
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3) : (7.787 * t) + 16.0 / 116
        }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
}
```

- [ ] **Step 4: Run the test**

```bash
cd nine && swift test --filter DuelTintTests 2>&1 | tail -20
```
Expected: PASS, 5 tests.

**If `testEveryPartnerPairClearsTheSeparationFloor…` fails:** that is a real finding, not a bug to code around — it means some accent has no safe partner and the PRD's §6 claim is false for that hue. Record the failing pair and its ΔE, then either lower the floor *with the measured number written down* or make coral-separation a tiebreak rather than a floor. Do not delete the assertion.

- [ ] **Step 5: Commit**

```bash
cd /Users/aquilops/conductor/workspaces/10x/osaka
git add nine/Sources/Shared/DuelTint.swift nine/Tests/SharedTests/DuelTintTests.swift
git commit -m "Nine: PRD-27 — the second player's tint is derived, not chosen

Maximise the minimum separation from the first player's accent and from
coral, across normal vision and three dichromacies. Deterministic because
the value is persisted; total because a newer build may name an accent
this one has never heard of."
```

---

### Task 2: `Duel` — turn boundaries, deadline, and the ledger

**Files:**
- Create: `nine/Sources/Shared/Duel.swift`
- Test: `nine/Tests/SharedTests/DuelTests.swift`

**Interfaces:**
- Consumes: `LoggedMove` (`NineEngine`), `DuelTint.partner(for:isLight:)`.
- Produces:
  - `DuelTurnLength: Int, Codable, CaseIterable` — `.brisk = 60`, `.standard = 90`, `.unhurried = 180`
  - `DuelTurn { player: Int; firstMoveIndex: Int; startedAt: TimeInterval }`
  - `DuelState { accents: [String]; turnLength: DuelTurnLength; turns: [DuelTurn] }` with `currentPlayer: Int`, `player(forMoveIndex: Int) -> Int?`, `remaining(atElapsed: TimeInterval) -> TimeInterval?`, `mutating func beginTurn(player: Int, firstMoveIndex: Int, startedAt: TimeInterval)`
  - `DuelLedger { subscript(UUID) -> DuelState?; mutating func set(_:for:); mutating func remove(_:); mutating func prune(to: Set<UUID>) }`, `DuelLedger.capacity = 60`

- [ ] **Step 1: Write the failing test**

Create `nine/Tests/SharedTests/DuelTests.swift`:

```swift
// DuelTests.swift — turns are contiguous ranges of the move log, and this is
// what that buys.
import XCTest
@testable import NineShared
#if canImport(NineEngine)
import NineEngine
#endif

final class DuelTests: XCTestCase {

    private func state(_ turns: [(Int, Int, TimeInterval)]) -> DuelState {
        var s = DuelState(accents: ["glacier", "ember"], turnLength: .standard)
        for (player, index, at) in turns {
            s.beginTurn(player: player, firstMoveIndex: index, startedAt: at)
        }
        return s
    }

    // MARK: Attribution

    func testAMoveIsOwnedByTheTurnItLandedIn() {
        let s = state([(0, 0, 0), (1, 4, 90), (0, 9, 180)])
        XCTAssertEqual(s.player(forMoveIndex: 0), 0)
        XCTAssertEqual(s.player(forMoveIndex: 3), 0)
        XCTAssertEqual(s.player(forMoveIndex: 4), 1)
        XCTAssertEqual(s.player(forMoveIndex: 8), 1)
        XCTAssertEqual(s.player(forMoveIndex: 9), 0)
        XCTAssertEqual(s.player(forMoveIndex: 900), 0, "the last turn is open-ended")
    }

    /// A time slice makes this the common case: a player who placed nothing
    /// still took a turn. A count-based turn could never produce one.
    func testAnEmptyTurnOwnsNoMovesAndBreaksNothing() {
        let s = state([(0, 0, 0), (1, 2, 90), (0, 2, 180)])
        XCTAssertEqual(s.player(forMoveIndex: 1), 0)
        XCTAssertEqual(s.player(forMoveIndex: 2), 0, "the later turn wins a shared boundary")
        XCTAssertEqual(s.turns.count, 3)
    }

    func testAMoveBeforeAnyTurnHasNoOwner() {
        XCTAssertNil(DuelState(accents: ["glacier", "ember"], turnLength: .brisk).player(forMoveIndex: 0))
    }

    // MARK: The deadline

    func testRemainingCountsDownAgainstTheBoardClock() {
        let s = state([(0, 0, 10)])
        XCTAssertEqual(s.remaining(atElapsed: 10), 90, accuracy: 0.001)
        XCTAssertEqual(s.remaining(atElapsed: 55), 45, accuracy: 0.001)
        XCTAssertEqual(s.remaining(atElapsed: 100), 0, accuracy: 0.001)
        XCTAssertEqual(s.remaining(atElapsed: 5000), 0, accuracy: 0.001,
                       "never negative — a chip does not show -04:12")
    }

    func testRemainingIsNilBeforeTheFirstTurnBegins() {
        XCTAssertNil(DuelState(accents: ["glacier", "ember"], turnLength: .brisk).remaining(atElapsed: 0))
    }

    func testTurnLengthsAreTheThreeTheSpecNames() {
        XCTAssertEqual(DuelTurnLength.brisk.rawValue, 60)
        XCTAssertEqual(DuelTurnLength.standard.rawValue, 90)
        XCTAssertEqual(DuelTurnLength.unhurried.rawValue, 180)
        XCTAssertEqual(DuelTurnLength.allCases.count, 3)
    }

    func testCurrentPlayerIsTheLastTurnsAndZeroBeforeAnyTurn() {
        XCTAssertEqual(DuelState(accents: ["glacier", "ember"], turnLength: .brisk).currentPlayer, 0)
        XCTAssertEqual(state([(0, 0, 0), (1, 3, 90)]).currentPlayer, 1)
    }

    // MARK: Tolerant decode — nothing throws out of a container

    func testAStateWithGarbageTurnLengthDecodesToTheDefaultRatherThanThrowing() throws {
        let json = """
        {"accents":["glacier","ember"],"turnLength":9999,"turns":[]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DuelState.self, from: json)
        XCTAssertEqual(decoded.turnLength, .standard)
    }

    func testAStateMissingItsTurnsDecodesEmptyRatherThanThrowing() throws {
        let json = #"{"accents":["glacier","ember"],"turnLength":60}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DuelState.self, from: json)
        XCTAssertEqual(decoded.turns, [])
        XCTAssertEqual(decoded.turnLength, .brisk)
    }

    func testAStateWithTheWrongNumberOfAccentsStillDecodesAndStillHasTwoPlayers() throws {
        let json = #"{"accents":["glacier"],"turnLength":90,"turns":[]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DuelState.self, from: json)
        XCTAssertEqual(decoded.accents.count, 2, "a duel is always two seats")
        XCTAssertEqual(decoded.accents[0], "glacier")
    }

    func testRoundTrip() throws {
        let s = state([(0, 0, 0), (1, 4, 90)])
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(DuelState.self, from: data), s)
    }

    // MARK: The ledger

    func testTheLedgerStoresAndPrunesAgainstTheLiveLibrary() {
        let live = UUID(), dead = UUID()
        var ledger = DuelLedger()
        ledger.set(state([(0, 0, 0)]), for: live)
        ledger.set(state([(1, 0, 0)]), for: dead)
        XCTAssertNotNil(ledger[live])
        ledger.prune(to: [live])
        XCTAssertNotNil(ledger[live])
        XCTAssertNil(ledger[dead], "a duel outliving its board is unreachable")
    }

    /// `ReplayVault`'s rule, for its reason: `prune` refuses an empty live set,
    /// so deletion gets its own door.
    func testPruneRefusesAnEmptyLiveSetAndRemoveIsTheOtherDoor() {
        let id = UUID()
        var ledger = DuelLedger()
        ledger.set(state([(0, 0, 0)]), for: id)
        ledger.prune(to: [])
        XCTAssertNotNil(ledger[id], "an empty live set is a library that has not loaded yet")
        ledger.remove(id)
        XCTAssertNil(ledger[id])
    }

    func testTheLedgerIsCapacityBoundedLikeTheReplayVault() {
        var ledger = DuelLedger()
        var ids: [UUID] = []
        for _ in 0..<(DuelLedger.capacity + 10) {
            let id = UUID(); ids.append(id)
            ledger.set(state([(0, 0, 0)]), for: id)
        }
        XCTAssertEqual(ledger.count, DuelLedger.capacity)
        XCTAssertNil(ledger[ids[0]], "oldest evicted first")
        XCTAssertNotNil(ledger[ids.last!])
    }

    func testALedgerWithOneUndecodableEntryKeepsTheOthers() throws {
        let good = UUID()
        let json = """
        {"states":{"\(good.uuidString)":{"accents":["glacier","ember"],"turnLength":90,"turns":[]},
        "not-a-uuid":{"accents":["glacier","ember"],"turnLength":90,"turns":[]}},
        "order":["\(good.uuidString)"]}
        """.data(using: .utf8)!
        let ledger = try JSONDecoder().decode(DuelLedger.self, from: json)
        XCTAssertNotNil(ledger[good])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd nine && swift test --filter DuelTests 2>&1 | tail -20
```
Expected: FAIL — `cannot find 'DuelState' in scope`.

- [ ] **Step 3: Write the implementation**

Create `nine/Sources/Shared/Duel.swift`:

```swift
// Duel.swift — two people, one board, alternating timed turns (PRD-27).
//
// **The one idea: a turn is a window on the board's own clock.** There is no
// second clock anywhere in this feature. `NineGame.timer` already pauses for
// sheets and for scene backgrounding, and already stamps every `LoggedMove.at`,
// so a turn is three numbers against that one axis — who, from which move, from
// which elapsed second.
//
// Both facts the feature needs fall out of that:
//
//   * the deadline is `turnLength - (elapsed - startedAt)`, which inherits every
//     pause the board clock already takes, so backgrounding the app mid-turn
//     cannot eat a turn;
//   * attribution is a search over turn boundaries, because turns are
//     *contiguous ranges* of the move log.
//
// That second consequence is what keeps this file out of the Engine. Undo is
// logged as an event and never pops the log (a 1.0 decision PRD-26 spent), so
// move indices are monotone forever and a range is never invalidated by a later
// move. `LoggedMove` gains nothing, `NineGame`'s bytes do not move, and
// `SolveReplay.packed` keeps its version byte — so nothing the golden corpus
// hashes is in this diff.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

/// How long one turn lasts, chosen when the duel starts.
///
/// A per-duel setup choice and deliberately **not** a settings row: the covenant
/// makes those expensive (PRD-31 deferred a handedness pref on exactly this
/// ground), and a choice made on the way into a mode costs nothing, the same way
/// picking a difficulty does.
public enum DuelTurnLength: Int, Codable, Sendable, CaseIterable {
    case brisk = 60
    case standard = 90
    case unhurried = 180
}

/// One turn: who took it, where in the move log it starts, and when on the
/// board's clock it began.
///
/// There is no end index and no end time on purpose. A turn ends exactly where
/// the next one begins, and the last turn is open-ended — storing both would be
/// two places for the same fact to be written and one place for them to
/// disagree.
public struct DuelTurn: Codable, Equatable, Sendable {
    public let player: Int
    public let firstMoveIndex: Int
    public let startedAt: TimeInterval

    public init(player: Int, firstMoveIndex: Int, startedAt: TimeInterval) {
        self.player = player
        self.firstMoveIndex = firstMoveIndex
        self.startedAt = startedAt
    }
}

/// Everything a duel is, and nothing else. No `Date` — every time in here is
/// board-elapsed seconds, so this type is as replayable as the move log it
/// indexes.
public struct DuelState: Codable, Equatable, Sendable {

    public static let seats = 2

    /// The two players' accent raw values, player 0 first.
    public let accents: [String]
    public let turnLength: DuelTurnLength
    public private(set) var turns: [DuelTurn]

    public init(accents: [String], turnLength: DuelTurnLength, turns: [DuelTurn] = []) {
        self.accents = DuelState.seated(accents)
        self.turnLength = turnLength
        self.turns = turns
    }

    /// Player One is the player's own accent; Player Two is derived (§6).
    public init(accent: String, isLight: Bool, turnLength: DuelTurnLength) {
        self.init(
            accents: [accent, DuelTint.partner(for: accent, isLight: isLight)],
            turnLength: turnLength
        )
    }

    /// A duel is always two seats. A state that arrives with a different number
    /// — a newer build with a third player, a truncated blob — is repaired
    /// rather than rejected, because the board it belongs to is fine and the
    /// alternative is losing the whole ledger over a cosmetic field.
    private static func seated(_ raw: [String]) -> [String] {
        var seats = Array(raw.prefix(DuelState.seats))
        while seats.count < DuelState.seats {
            seats.append(DuelTint.partner(for: seats.first ?? "glacier", isLight: false))
        }
        return seats
    }

    public var currentPlayer: Int { turns.last?.player ?? 0 }

    public var accent: String { accents[currentPlayer] }

    public func accent(forPlayer player: Int) -> String {
        accents.indices.contains(player) ? accents[player] : accents[0]
    }

    /// Whose digit this is. Nil only before the first turn has begun.
    ///
    /// A linear reverse scan rather than a binary search, and that is a measured
    /// non-decision: turn counts are in the tens, the call site is a board draw
    /// asking 81 times, and 81 × 40 comparisons is nothing next to the `Canvas`
    /// it is feeding. Binary search here would be a cleverness with no number
    /// behind it.
    public func player(forMoveIndex index: Int) -> Int? {
        for turn in turns.reversed() where turn.firstMoveIndex <= index {
            return turn.player
        }
        return nil
    }

    /// Seconds left in the current turn, clamped at zero, or nil before the
    /// first turn begins. Never negative: a chip does not show -04:12.
    public func remaining(atElapsed elapsed: TimeInterval) -> TimeInterval? {
        guard let turn = turns.last else { return nil }
        return max(0, Double(turnLength.rawValue) - (elapsed - turn.startedAt))
    }

    /// Close the open turn and open the next. The caller does the clearing
    /// first — see `DuelSession` and PRD-27 §5: the quiet correction's erases
    /// must land in the log *before* this index is taken, or they are credited
    /// to the incoming player instead of the outgoing one.
    public mutating func beginTurn(player: Int, firstMoveIndex: Int, startedAt: TimeInterval) {
        turns.append(DuelTurn(player: player, firstMoveIndex: firstMoveIndex, startedAt: startedAt))
    }

    /// Tolerant in every field, because `CouchStored` discards the whole blob
    /// when a decode throws. Note `try?` on `turnLength` rather than
    /// `try … ?? default`: the second spelling survives an *absent* key and
    /// still throws on a key of the wrong *type*, which is the bug PRD-30's
    /// `QuietPresenceTests` found in three scalars of four.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accents = DuelState.seated((try? c.decode([String].self, forKey: .accents)) ?? [])
        turnLength = (try? c.decode(DuelTurnLength.self, forKey: .turnLength)) ?? .standard
        turns = (try? c.decode([DuelTurn].self, forKey: .turns)) ?? []
    }
}

/// `[boardID: DuelState]`, local-only, pruned against the live library.
///
/// A sibling top-level key (`nine.duel`) rather than a field on `LibraryEntry`,
/// which is EXECUTING-A-PRD §2's rule satisfied structurally: nothing an older
/// build decodes "successfully" can erase this on its next autosave, because the
/// older build never reads or writes this key at all.
public struct DuelLedger: Codable, Equatable, Sendable {

    /// `ReplayVault.capacity`, for the same reason and by no coincidence: the
    /// two blobs have identical lifetimes, because a duel board is a library
    /// board and a duel that outlives its board is unreachable.
    public static let capacity = 60

    private var states: [UUID: DuelState] = [:]
    private var order: [UUID] = []

    public init() {}

    public var count: Int { states.count }

    public subscript(boardID: UUID) -> DuelState? { states[boardID] }

    public mutating func set(_ state: DuelState, for boardID: UUID) {
        if states[boardID] == nil { order.append(boardID) }
        states[boardID] = state
        trim()
    }

    public mutating func remove(_ boardID: UUID) {
        states[boardID] = nil
        order.removeAll { $0 == boardID }
    }

    /// Drop every duel whose board is gone. Refuses an empty live set —
    /// `ReplayVault`'s rule, for its reason: an empty library is far more often
    /// one that has not finished loading than one the player emptied, and
    /// deletion has its own door above.
    public mutating func prune(to live: Set<UUID>) {
        guard !live.isEmpty else { return }
        for id in order where !live.contains(id) { states[id] = nil }
        order.removeAll { states[$0] == nil }
    }

    private mutating func trim() {
        while order.count > DuelLedger.capacity {
            states[order.removeFirst()] = nil
        }
    }

    enum CodingKeys: String, CodingKey { case states, order }

    /// Per-element quarantine, so one unreadable duel costs one duel.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decode([String: DuelState].self, forKey: .states)) ?? [:]
        for (key, value) in raw {
            guard let id = UUID(uuidString: key) else { continue }
            states[id] = value
        }
        let claimed = (try? c.decode([String].self, forKey: .order)) ?? []
        order = claimed.compactMap(UUID.init(uuidString:)).filter { states[$0] != nil }
        // Repair: anything present but unordered goes to the back, so a
        // hand-edited or partially-written blob still trims deterministically.
        for id in states.keys where !order.contains(id) { order.append(id) }
        trim()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Dictionary(uniqueKeysWithValues: states.map { ($0.key.uuidString, $0.value) }), forKey: .states)
        try c.encode(order.map(\.uuidString), forKey: .order)
    }
}
```

- [ ] **Step 4: Run the test**

```bash
cd nine && swift test --filter DuelTests 2>&1 | tail -20
```
Expected: PASS, 14 tests.

- [ ] **Step 5: Run the corpora — the claim is that they cannot move**

```bash
cd nine && swift test --filter "GoldenCorpus|VariantCorpus" 2>&1 | tail -5
```
Expected: PASS. If either moves, stop — something reached the Engine that should not have.

- [ ] **Step 6: Commit**

```bash
cd /Users/aquilops/conductor/workspaces/10x/osaka
git add nine/Sources/Shared/Duel.swift nine/Tests/SharedTests/DuelTests.swift
git commit -m "Nine: PRD-27 — a turn is a window on the board's own clock

DuelTurn is (player, firstMoveIndex, startedAt) against NineGame.timer, so
the deadline and the attribution come off one monotone axis. Turns are
contiguous move-log ranges, which is why the Engine is untouched: LoggedMove
gains nothing and the golden corpus cannot move.

nine.duel is a sibling blob with per-element quarantine and ReplayVault's
capacity, because the two have identical lifetimes by construction."
```

---

### Task 3: `DuelCredits` — who placed what

**Files:**
- Create: `nine/Sources/Shared/DuelCredits.swift`
- Test: `nine/Tests/SharedTests/DuelCreditsTests.swift`

**Interfaces:**
- Consumes: `DuelState.player(forMoveIndex:)`, `LoggedMove`.
- Produces: `DuelCredits { placed: [Int]; cleared: [Int]; lastPlayer: Int? }`, `init(state: DuelState, moves: [LoggedMove], solution: [Int])`.

- [ ] **Step 1: Write the failing test**

Create `nine/Tests/SharedTests/DuelCreditsTests.swift`:

```swift
// DuelCreditsTests.swift — the debrief credits both hands, and never ranks them.
import XCTest
@testable import NineShared
#if canImport(NineEngine)
import NineEngine
#endif

final class DuelCreditsTests: XCTestCase {

    /// A solution where cell N holds (N % 9) + 1 — not a legal sudoku, and it
    /// does not need to be: `DuelCredits` compares a digit to a grid and knows
    /// nothing about rules.
    private let solution = (0..<81).map { ($0 % 9) + 1 }

    private func place(_ cell: Int, _ digit: Int) -> LoggedMove {
        LoggedMove(kind: .place, cell: cell, digit: digit)
    }

    private func twoTurns() -> DuelState {
        var s = DuelState(accents: ["glacier", "ember"], turnLength: .standard)
        s.beginTurn(player: 0, firstMoveIndex: 0, startedAt: 0)
        s.beginTurn(player: 1, firstMoveIndex: 3, startedAt: 90)
        return s
    }

    func testCorrectPlacementsAreCreditedToTheTurnTheyLandedIn() {
        let moves = [place(0, 1), place(1, 2), place(2, 3), place(3, 4), place(4, 5)]
        let credits = DuelCredits(state: twoTurns(), moves: moves, solution: solution)
        XCTAssertEqual(credits.placed, [3, 2])
        XCTAssertEqual(credits.cleared, [0, 0])
    }

    /// Per attempt, which is `NineGame.errorCount`'s own definition: three
    /// wrong tries at one cell is three.
    func testEachWrongAttemptCountsSeparately() {
        let moves = [place(0, 9), place(0, 8), place(0, 1), place(3, 7), place(3, 4)]
        let credits = DuelCredits(state: twoTurns(), moves: moves, solution: solution)
        XCTAssertEqual(credits.cleared, [2, 1])
        XCTAssertEqual(credits.placed, [1, 1])
    }

    func testErasesAndNotesAndUndosAreCreditedToNobody() {
        let moves = [
            place(0, 1),
            LoggedMove(kind: .erase, cell: 0, digit: 1),
            LoggedMove(kind: .pencil, cell: 5, digit: 3),
            LoggedMove(kind: .undo, cell: 0, digit: 1),
        ]
        let credits = DuelCredits(state: twoTurns(), moves: moves, solution: solution)
        XCTAssertEqual(credits.placed, [1, 0])
        XCTAssertEqual(credits.cleared, [0, 0])
    }

    func testTheLastDigitIsTheLastCorrectPlacement() {
        let moves = [place(0, 1), place(3, 4), place(4, 9)]
        XCTAssertEqual(DuelCredits(state: twoTurns(), moves: moves, solution: solution).lastPlayer, 1)
    }

    func testTheLastDigitIsNilWhenNobodyPlacedACorrectOne() {
        let moves = [place(0, 9)]
        XCTAssertNil(DuelCredits(state: twoTurns(), moves: moves, solution: solution).lastPlayer)
    }

    func testAnEmptyLogCreditsNobodyAndDoesNotTrap() {
        let credits = DuelCredits(state: twoTurns(), moves: [], solution: solution)
        XCTAssertEqual(credits.placed, [0, 0])
        XCTAssertNil(credits.lastPlayer)
    }

    /// A short or absent solution must not crash the debrief — the replay's
    /// grid and the library entry's solution are two blobs and either can be
    /// missing.
    func testAnOutOfRangeCellOrShortSolutionIsSkippedRatherThanTrapping() {
        let moves = [place(0, 1), place(500, 4), place(-1, 2)]
        let credits = DuelCredits(state: twoTurns(), moves: moves, solution: [])
        XCTAssertEqual(credits.placed, [0, 0])
        XCTAssertEqual(credits.cleared, [0, 0])
    }

    func testMovesBeforeAnyTurnAreCreditedToNobody() {
        let s = DuelState(accents: ["glacier", "ember"], turnLength: .brisk)
        let credits = DuelCredits(state: s, moves: [place(0, 1)], solution: solution)
        XCTAssertEqual(credits.placed, [0, 0])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd nine && swift test --filter DuelCreditsTests 2>&1 | tail -20
```
Expected: FAIL — `cannot find 'DuelCredits' in scope`.

- [ ] **Step 3: Write the implementation**

Create `nine/Sources/Shared/DuelCredits.swift`:

```swift
// DuelCredits.swift — what each hand contributed (PRD-27 §10).
//
// **Credit, never rank.** There is no total here, no ratio, no accuracy, no
// winner and no ordering by anything but seat number. A winner is a badge and
// EXECUTING-A-PRD §1 rules badges out by name; this is the line the feature is
// most likely to drift across later, so the type simply does not carry a value
// anyone could sort on.
//
// "Cleared", not "errors": the word describes what happened to the board, not a
// verdict on a person — and unlike a solo solve there is a second person in the
// room reading it.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

public struct DuelCredits: Equatable, Sendable {

    /// Correct placements, per seat.
    public let placed: [Int]
    /// Wrong placements, per seat, **per attempt** — the same definition
    /// `NineGame.errorCount` uses, so three wrong tries at one cell is three.
    public let cleared: [Int]
    /// Who placed the digit that finished the board. Nil when no correct
    /// placement was ever made, which is every untouched and every abandoned
    /// board.
    public let lastPlayer: Int?

    public init(state: DuelState, moves: [LoggedMove], solution: [Int]) {
        var placed = [Int](repeating: 0, count: DuelState.seats)
        var cleared = [Int](repeating: 0, count: DuelState.seats)
        var last: Int?

        for (index, move) in moves.enumerated() {
            guard move.kind == .place else { continue }
            guard solution.indices.contains(move.cell) else { continue }
            guard let player = state.player(forMoveIndex: index),
                  placed.indices.contains(player) else { continue }
            if move.digit == solution[move.cell] {
                placed[player] += 1
                last = player
            } else {
                cleared[player] += 1
            }
        }

        self.placed = placed
        self.cleared = cleared
        self.lastPlayer = last
    }

    /// Whether there is anything worth printing — a duel abandoned before
    /// anyone placed a digit gets no lines rather than three zeroes.
    public var isEmpty: Bool { placed.allSatisfy { $0 == 0 } && cleared.allSatisfy { $0 == 0 } }
}
```

- [ ] **Step 4: Run the test**

```bash
cd nine && swift test --filter DuelCreditsTests 2>&1 | tail -20
```
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/aquilops/conductor/workspaces/10x/osaka
git add nine/Sources/Shared/DuelCredits.swift nine/Tests/SharedTests/DuelCreditsTests.swift
git commit -m "Nine: PRD-27 — credit both hands, rank neither

Correct and wrong placements per seat, plus who placed the last digit. The
type carries no total, no ratio and no ordering, because a winner is a badge."
```

---

### Task 4: The debrief's three duel lines

**Files:**
- Modify: `nine/Sources/Shared/SolveDebrief.swift:56` (add stored property), `:60-62` (`lines`), `:80-110` (`init`), `:170-199` (`Phrase`)
- Modify: `nine/Sources/Shared/EnglishPhrases.swift` (three rows, sorted into place)
- Modify: `nine/scripts/strings.py` `COMMENTS` (three entries)
- Test: `nine/Tests/SharedTests/SolveDebriefTests.swift` (append; do not edit existing cases)

**Interfaces:**
- Consumes: `DuelCredits`, `DuelState.accent(forPlayer:)`.
- Produces: `SolveDebrief.init(replay:analysis:duel:names:)` where `duel: DuelCredits? = nil` and `names: [String] = []`; `SolveDebrief.duelLines: [String]`.

**Why `names` is a parameter and not looked up:** `SolveDebrief` is Linux-clean and `AccentChoice.title` is App-layer. The caller resolves the two names; this type only orders them. Same seam `Phrase.headline` uses for technique names.

- [ ] **Step 1: Write the failing test**

Append to `nine/Tests/SharedTests/SolveDebriefTests.swift` (inside the existing final class):

```swift
    // MARK: - PRD-27 duel credits

    private func duelReplay() throws -> (SolveReplay, ReplayAnalysis) {
        // Reuse whatever this file's existing helper mints; if it has none,
        // build the smallest solved board the other tests in this file use.
        try XCTUnwrap(Self.sampleReplayAndAnalysis())
    }

    func testANilDuelLeavesEveryExistingLineExactlyWhereItWas() throws {
        let (replay, analysis) = try duelReplay()
        let plain = SolveDebrief(replay: replay, analysis: analysis)
        let explicitlyNil = SolveDebrief(replay: replay, analysis: analysis, duel: nil, names: [])
        XCTAssertEqual(plain.lines, explicitlyNil.lines)
        XCTAssertEqual(plain.countsLine, explicitlyNil.countsLine)
        XCTAssertTrue(plain.duelLines.isEmpty)
    }

    func testTheDuelAddsAPlacedLineNamingBothPlayers() throws {
        let (replay, analysis) = try duelReplay()
        var state = DuelState(accents: ["glacier", "ember"], turnLength: .standard)
        state.beginTurn(player: 0, firstMoveIndex: 0, startedAt: 0)
        state.beginTurn(player: 1, firstMoveIndex: 1, startedAt: 90)
        let credits = DuelCredits(state: state, moves: replay.moves, solution: (0..<81).map { ($0 % 9) + 1 })
        let debrief = SolveDebrief(replay: replay, analysis: analysis,
                                   duel: credits, names: ["Glacier", "Ember"])
        XCTAssertFalse(debrief.duelLines.isEmpty)
        XCTAssertTrue(debrief.duelLines[0].contains("Glacier"))
        XCTAssertTrue(debrief.duelLines[0].contains("Ember"))
        XCTAssertTrue(debrief.lines.contains(debrief.duelLines[0]),
                      "duel lines are part of `lines`, which is the one place order is decided")
    }

    func testTheClearedLineIsAbsentWhenNobodyPlacedAWrongDigit() throws {
        let (replay, analysis) = try duelReplay()
        var state = DuelState(accents: ["glacier", "ember"], turnLength: .standard)
        state.beginTurn(player: 0, firstMoveIndex: 0, startedAt: 0)
        let clean = DuelCredits(state: state, moves: [LoggedMove(kind: .place, cell: 0, digit: 1)],
                                solution: (0..<81).map { ($0 % 9) + 1 })
        let debrief = SolveDebrief(replay: replay, analysis: analysis,
                                   duel: clean, names: ["Glacier", "Ember"])
        XCTAssertFalse(debrief.duelLines.contains { $0.lowercased().contains("cleared") })
    }

    func testAnEmptyDuelPrintsNothingRatherThanThreeZeroes() throws {
        let (replay, analysis) = try duelReplay()
        let empty = DuelCredits(state: DuelState(accents: ["glacier", "ember"], turnLength: .brisk),
                                moves: [], solution: [])
        let debrief = SolveDebrief(replay: replay, analysis: analysis,
                                   duel: empty, names: ["Glacier", "Ember"])
        XCTAssertTrue(debrief.duelLines.isEmpty)
    }

    func testMissingNamesDoNotTrap() throws {
        let (replay, analysis) = try duelReplay()
        var state = DuelState(accents: ["glacier", "ember"], turnLength: .standard)
        state.beginTurn(player: 0, firstMoveIndex: 0, startedAt: 0)
        let credits = DuelCredits(state: state, moves: replay.moves, solution: (0..<81).map { ($0 % 9) + 1 })
        let debrief = SolveDebrief(replay: replay, analysis: analysis, duel: credits, names: [])
        XCTAssertNoThrow(debrief.lines)
    }
```

**Note:** if `SolveDebriefTests` has no `sampleReplayAndAnalysis()` helper, add one as a `static func` that mints a `SolveReplay` from a short synthetic move log the way the file's existing cases already do — read the file first and reuse its idiom rather than inventing a second one.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd nine && swift test --filter SolveDebriefTests 2>&1 | tail -20
```
Expected: FAIL — no `duel:` parameter, no `duelLines`.

- [ ] **Step 3: Add the three English rows**

In `nine/Sources/Shared/EnglishPhrases.swift`, insert into `table` **in sorted position** (the table is one sorted entry per line and `PhrasebookTests.testTableIsOneSortedEntryPerLineSoAScriptCanReadIt` reads it as text):

```swift
        "debrief.duel.cleared": "%1$@ cleared %2$lld · %3$@ cleared %4$lld",
        "debrief.duel.last": "%1$@ placed the last digit.",
        "debrief.duel.placed": "%1$@ placed %2$lld · %3$@ placed %4$lld",
```

In `nine/scripts/strings.py`, add to `COMMENTS`:

```python
    "debrief.duel.placed": "Post-solve debrief line for a two-player local duel (PRD-27). %1$@ and %3$@ are the two players' names, which are the names of their board colours (\"Glacier\", \"Ember\"); %2$lld and %4$lld are how many correct digits each placed. A record, never a score — do not translate as a competitive result, and do not reorder so that one player reads as the winner. The \"·\" is a separator, keep it.",
    "debrief.duel.cleared": "Post-solve debrief line for a two-player local duel (PRD-27), shown only when at least one wrong digit was placed. %1$@ and %3$@ are player names (their board colours); %2$lld and %4$lld are how many of their digits were silently removed during the game. VERB, past tense, neutral: the digits were cleared from the board. Avoid any word meaning \"mistake\", \"failure\" or \"wrong\" — the whole point of this feature is that nobody is told off.",
    "debrief.duel.last": "Post-solve debrief line for a two-player local duel (PRD-27). %1$@ is a player's name (their board colour). A statement of fact about who completed the puzzle, NOT a declaration that they won. Full sentence, ends with a full stop.",
```

- [ ] **Step 4: Modify `SolveDebrief`**

In `nine/Sources/Shared/SolveDebrief.swift`, after the `isTimed` property (`:56`) add:

```swift
    /// PRD-27's contribution credits, or empty on every solo solve — which is
    /// every solve on iPhone, Mac, watch and widget. Stored rather than
    /// computed because the names come from the App layer and this type stays
    /// Linux-clean.
    public let duelLines: [String]
```

Replace `lines` (`:60-62`) with:

```swift
    /// Every line, in order, skipping the ones that are not there. The one
    /// place the card's order is decided — `DebriefCard` `ForEach`es this and
    /// needs no knowledge of duels at all.
    public var lines: [String] {
        [headline, fastestRegion, longestCircled].compactMap { $0 } + duelLines
    }
```

Change the initialiser signature (`:80`) and add the duel block immediately before the `guard timed else` at `:103`:

```swift
    public init(
        replay: SolveReplay,
        analysis: ReplayAnalysis,
        duel: DuelCredits? = nil,
        names: [String] = []
    ) {
```

```swift
        // PRD-27 §10. Built before the `guard timed else` early return, so a
        // duel on an untimed log still credits both hands — the two timed facts
        // are the only things timing gates.
        duelLines = SolveDebrief.duelLines(duel, names: names)
```

**Important:** `duelLines` must be assigned on *both* paths out of `init`. Assigning it before the `guard` does that.

Add the builder as a `static func` beside `fastestBox`:

```swift
    /// The duel's lines, or none. Empty when there is no duel, and empty when
    /// the duel produced nothing — a board abandoned before anyone placed a
    /// digit gets no lines rather than three zeroes, which is `countsLine`'s
    /// own honest-absence rule.
    static func duelLines(_ duel: DuelCredits?, names: [String]) -> [String] {
        guard let duel, !duel.isEmpty else { return [] }
        let a = names.indices.contains(0) ? names[0] : ""
        let b = names.indices.contains(1) ? names[1] : ""
        var lines = [Phrase.duelPlaced(a, duel.placed[0], b, duel.placed[1])]
        if duel.cleared.contains(where: { $0 > 0 }) {
            lines.append(Phrase.duelCleared(a, duel.cleared[0], b, duel.cleared[1]))
        }
        if let last = duel.lastPlayer, names.indices.contains(last) {
            lines.append(Phrase.duelLast(names[last]))
        }
        return lines
    }
```

Add to `private enum Phrase`:

```swift
        static func duelPlaced(_ a: String, _ ac: Int, _ b: String, _ bc: Int) -> String {
            Phrasebook.current.string("debrief.duel.placed", .text(a), .int(ac), .text(b), .int(bc))
        }
        static func duelCleared(_ a: String, _ ac: Int, _ b: String, _ bc: Int) -> String {
            Phrasebook.current.string("debrief.duel.cleared", .text(a), .int(ac), .text(b), .int(bc))
        }
        static func duelLast(_ name: String) -> String {
            Phrasebook.current.string("debrief.duel.last", .text(name))
        }
```

- [ ] **Step 5: Rebuild the catalog and audit**

```bash
cd nine
python3 scripts/strings.py --build-catalog
python3 scripts/strings.py --audit
```
Expected: catalog gains 3 keys; audit reports zero new offences, zero missing, zero dead.

**If the audit fails with "no translator comment for":** the `COMMENTS` entry key does not match the `table` key exactly. Compare them character by character.

- [ ] **Step 6: Run the tests**

```bash
cd nine && swift test --filter "SolveDebriefTests|CatalogTests|PhrasebookTests" 2>&1 | tail -20
```
Expected: PASS. `CatalogTests` will check the three new keys have all ten locales — machine drafts, every one marked `needs_review`.

- [ ] **Step 7: Commit**

```bash
cd /Users/aquilops/conductor/workspaces/10x/osaka
git add nine/Sources/Shared/SolveDebrief.swift nine/Sources/Shared/EnglishPhrases.swift \
        nine/scripts/strings.py nine/Sources/Strings/Localizable.xcstrings \
        nine/Tests/SharedTests/SolveDebriefTests.swift
git commit -m "Nine: PRD-27 — the debrief credits both hands

Three lines appended to \`lines\`, which is still the one place the card's
order is decided, so DebriefCard needs no change. Nil duel leaves every
existing line byte-identical. The cleared line is absent at zero, and the
translator comments say in words that this is a record and not a score."
```

---

### Task 5: `BoardView.digitTint` — the per-player tint

**Files:**
- Modify: `nine/Sources/App/BoardView.swift` (property beside `channelRules` ~`:227`; draw step 4 at `:705`)
- Test: none directly — a `Canvas` has no unit-testable output. The gate is that all existing call sites compile unchanged and the AX baselines do not move (Task 11).

**Interfaces:**
- Produces: `BoardView.digitTint: ((Int) -> Color?)? = nil`

- [ ] **Step 1: Add the property**

In `nine/Sources/App/BoardView.swift`, immediately after the `channelRules` declaration, add:

```swift
    /// A per-cell tint for placed digits, or nil for one accent everywhere
    /// (PRD-27 §6). Nil by default, so all existing call sites render
    /// byte-identically — `channelRules`' pattern, and the reason the watch
    /// board, the tutorial boards, the first-run board, the school board and
    /// the fingerprint needed no change at all.
    ///
    /// A closure rather than a `[Int: Color]` because the answer is a search
    /// over turn boundaries, not a table: materialising 81 entries on every
    /// body evaluation to look up the handful of cells that are actually filled
    /// is work the draw loop can just not do.
    ///
    /// Givens are never tinted. A given belongs to the puzzle, not to a player,
    /// and colouring it would claim a digit nobody placed.
    var digitTint: ((Int) -> Color?)? = nil
```

- [ ] **Step 2: Use it in draw step 4**

In `nine/Sources/App/BoardView.swift`, change line 705 from:

```swift
                var color = isGiven ? digitTone : accent
```

to:

```swift
                // PRD-27: a duel tints each player's digits. Above the three
                // branches below on purpose — error, completion wave and pad
                // peek all still override, and their precedence is unchanged.
                var color = isGiven ? digitTone : (digitTint?(index) ?? accent)
```

- [ ] **Step 3: Verify every platform still builds**

```bash
cd nine && COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate
for dest in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$dest" \
    -derivedDataPath build build 2>&1 | tail -3
done
```
Expected: `** BUILD SUCCEEDED **` three times. No call site should need editing — `digitTint` has a default.

- [ ] **Step 4: Commit**

```bash
cd /Users/aquilops/conductor/workspaces/10x/osaka
git add nine/Sources/App/BoardView.swift
git commit -m "Nine: PRD-27 — BoardView can tint digits per cell

One optional closure at draw step 4, above the error/wave/peek branches so
their precedence is untouched. Nil at every existing call site, which is
channelRules' pattern and why nine call sites needed no edit."
```

---

### Task 6: `AppModel` — the store, the start door, and the four refusals

**Files:**
- Modify: `nine/Sources/App/AppModel.swift` (store beside `replaysStore` ~`:452`; `startDuel` beside `startFree` `:1076`; guards in `finishSolve` `:1689`; prune in `persistProgress`/`deleteEntry`)
- Test: `nine/Tests/EngineTests/DuelSealTests.swift`

**Interfaces:**
- Consumes: `DuelLedger`, `DuelState`, `DuelCredits`, `AccentChoice.title`.
- Produces: `AppModel.duels: DuelLedger`, `AppModel.duelState: DuelState?`, `AppModel.isDuel: Bool`, `AppModel.startDuel(difficulty:turnLength:)`, `AppModel.recordDuelTurn(player:startedAt:)`, `AppModel.duelCredits(for: UUID) -> DuelCredits?`

**Why a seal test:** `swift test` compiles Engine + Shared only, so `AppModel`'s guards are structurally untestable there. `VariantInputSealTests` and `QuietPresenceSealTests` already solve this by reading App-layer source as text; this follows them.

- [ ] **Step 1: Write the failing seal test**

Create `nine/Tests/EngineTests/DuelSealTests.swift`:

```swift
// DuelSealTests.swift — a duel solve is nobody's solve, held by reading the
// source (PRD-27 §7).
//
// `swift test` compiles Engine and Shared, so `AppModel.finishSolve` cannot be
// called from here at all. `VariantInputSealTests` and `QuietPresenceSealTests`
// already answer that the same way: the invariant is about *which lines exist*,
// so the check reads the file. A seal is weaker than a unit test and stronger
// than a comment, and this invariant has no unit-testable form.
import XCTest

final class DuelSealTests: XCTestCase {

    private func appSource(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // nine
            .appendingPathComponent("Sources/App/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The whole of §7 in one assertion: every ledger a solo solve writes is
    /// named here, and each must be guarded by the duel check.
    func testFinishSolveGuardsEverySoloLedgerBehindTheDuelCheck() throws {
        let source = try appSource("AppModel.swift")
        let finish = try XCTUnwrap(source.range(of: "private func finishSolve()"))
        let body = String(source[finish.lowerBound...].prefix(9000))
        XCTAssertTrue(
            body.contains("isDuel"),
            "finishSolve must consult the duel guard — PRD-27 §7: two people solved that board")
    }

    /// The negative that erodes silently. A duel board must never reach the
    /// classic streak, the classic history, the archive, the channel ledger or
    /// Game Center.
    func testTheDuelGuardNamesEverySurfaceItProtects() throws {
        let source = try appSource("AppModel.swift")
        for surface in ["nine.duel"] {
            XCTAssertTrue(source.contains(surface), "missing \(surface)")
        }
        XCTAssertTrue(
            source.contains("func startDuel"),
            "PRD-27 §8.2 — the duel needs its own start door, so it can never be a daily")
    }

    /// A duel board is an ordinary free board (PRD-27 §3): `GameKind` gains no
    /// case, so an older build opens it and plays it correctly.
    func testGameKindGainsNoDuelCase() throws {
        let engine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Engine/BoardLibrary.swift")
        let source = try String(contentsOf: engine, encoding: .utf8)
        XCTAssertFalse(
            source.lowercased().contains("case duel"),
            "PRD-27 §3 — a duel board is .free(difficulty). A GameKind case would "
            + "quarantine it on older builds for no reason: unlike a killer board, "
            + "there is nothing here an older build renders wrong.")
    }

    /// The Engine is not in this PRD's diff at all.
    func testLoggedMoveGainsNoPlayerField() throws {
        let engine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Engine/Game.swift")
        let source = try String(contentsOf: engine, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "public struct LoggedMove"))
        let end = try XCTUnwrap(source.range(of: "public struct NineGame"))
        let declaration = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(
            declaration.contains("player"),
            "PRD-27 §2 — attribution is a boundary list in nine.duel, not a field "
            + "on 300 moves. A field here moves SolveReplay.packed and every "
            + "autosaved board's bytes.")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd nine && swift test --filter DuelSealTests 2>&1 | tail -20
```
Expected: the two `GameKind`/`LoggedMove` cases PASS already (nothing has been added); the `finishSolve` and `startDuel` cases FAIL.

- [ ] **Step 3: Add the store**

In `nine/Sources/App/AppModel.swift`, immediately after the `replaysStore` declaration (~`:452`), add:

```swift
    /// PRD-27's duel attribution. Its own blob for `nine.replays`' reason and
    /// with its lifetime: a duel board is a library board, so the two prune
    /// together. Local-only — a duel is a couch, not a cloud, and carrying
    /// attribution across devices needs a CloudKit record type and a schema
    /// deploy (PRD-27 §12).
    @ObservationIgnored private let duelsStore =
        CouchStored(wrappedValue: DuelLedger(), "nine.duel")
```

Add the backing property beside the other `didSet` pairs (follow `replays`' exact shape in the same file):

```swift
    var duels: DuelLedger {
        didSet { duelsStore.wrappedValue = duels }
    }
```

and seed it in `init` beside `replays = replaysStore.wrappedValue`:

```swift
        duels = duelsStore.wrappedValue
```

- [ ] **Step 4: Add the accessors and the start door**

Beside `startFree` (`:1076`):

```swift
    // MARK: - Duel (PRD-27)

    /// The duel this board is part of, or nil — which is every board on every
    /// surface but tvOS and the drafting table.
    var duelState: DuelState? {
        guard let id = currentEntryID else { return nil }
        return duels[id]
    }

    var isDuel: Bool { duelState != nil }

    /// Start a two-player board. Always a fresh free board and never the daily,
    /// so two people on a sofa can never spend the streak of the person whose
    /// device it is (PRD-27 §7).
    func startDuel(difficulty: Difficulty, turnLength: DuelTurnLength, isLight: Bool) {
        pendingDuel = DuelState(accent: prefs.accent.rawValue, isLight: isLight, turnLength: turnLength)
        startFree(difficulty)
    }

    /// `startFree` composes asynchronously, so the state is parked until the
    /// entry exists and adopted in `startEntry`. Session-scoped by design —
    /// a duel that never got a board is not a duel.
    @ObservationIgnored private var pendingDuel: DuelState?

    /// Called by `startEntry` once `currentEntryID` is set.
    func adoptPendingDuelIfAny() {
        guard let pending = pendingDuel, let id = currentEntryID else { return }
        pendingDuel = nil
        duels.set(pending, for: id)
    }

    /// Open a turn. The caller has already applied the quiet correction, which
    /// is what puts those erases inside the *outgoing* player's range
    /// (PRD-27 §5 — the order is load-bearing).
    func recordDuelTurn(player: Int, startedAt: TimeInterval) {
        guard let id = currentEntryID, var state = duels[id] else { return }
        state.beginTurn(player: player, firstMoveIndex: game?.moveLog.count ?? 0, startedAt: startedAt)
        duels.set(state, for: id)
    }

    /// The debrief's credits for a board, or nil if it was not a duel.
    func duelCredits(for boardID: UUID) -> DuelCredits? {
        guard let state = duels[boardID],
              let entry = library.entry(id: boardID) else { return nil }
        return DuelCredits(
            state: state,
            moves: replays.replay(for: boardID)?.moves ?? entry.game.moveLog,
            solution: entry.game.puzzle.solution.cells
        )
    }

    /// The two players' names — their tints' names, which cost nothing to
    /// translate because `AccentChoice.title` already goes through the catalog.
    func duelNames(for boardID: UUID) -> [String] {
        guard let state = duels[boardID] else { return [] }
        return state.accents.map { AccentChoice(rawValue: $0)?.title ?? "" }
    }
```

**Note on `replays.replay(for:)`:** read `ReplayVault`'s actual accessor name in `nine/Sources/Engine/SolveReplay.swift` and use it verbatim — if the vault exposes a subscript instead, use that. Do not invent an accessor.

Call `adoptPendingDuelIfAny()` at the end of `startEntry` (find it at `:1196`), after `currentEntryID` is assigned.

- [ ] **Step 5: Add the four refusals in `finishSolve`**

In `finishSolve` (`:1689`), immediately after `clockHolds.removeAll()`, insert:

```swift
        // PRD-27 §7. Two people solved that board; it is not your solve.
        //
        // Every solo ledger is skipped: the classic streak, the classic
        // history, the archive, the channel ledger and every Game Center
        // submission. The replay is still minted — a duel has a comet and a
        // debrief, which is the whole point of §10 — and the library still
        // marks it solved, because the board really is finished.
        let isDuel = self.isDuel
```

Then guard each write site with `!isDuel`:
- the `if case .daily(let day)? = kind` block → `if !isDuel, case .daily(let day)? = kind`
- the `if let channelSlot` block → `if !isDuel, let channelSlot`
- the classic `history.record(...)` call → wrap in `if !isDuel { … }`
- the Game Center submission block (`:1795-1809`) → wrap in `if !isDuel { … }`

**Read each site before editing** — the exact spellings are in the file and this plan's line numbers are from before any edit.

- [ ] **Step 6: Prune the ledger with the library**

In `deleteEntry` (`:1224`), beside the existing `replays` removal, add:

```swift
        duels.remove(id)
```

In `mintReplay` (`:1826`), beside `vault.prune(to: live ids)`, add the same prune for `duels` using the identical live-id set.

- [ ] **Step 7: Run the seal test and build**

```bash
cd nine && swift test --filter DuelSealTests 2>&1 | tail -10
COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate
for dest in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$dest" -derivedDataPath build build 2>&1 | tail -3
done
```
Expected: seal PASS (5 tests), three `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
cd /Users/aquilops/conductor/workspaces/10x/osaka
git add nine/Sources/App/AppModel.swift nine/Tests/EngineTests/DuelSealTests.swift
git commit -m "Nine: PRD-27 — a duel solve touches no solo ledger

nine.duel joins the stores beside nine.replays and prunes with it. startDuel
is always a fresh free board, so two people on a sofa cannot spend the daily
of whoever owns the device.

The four refusals in finishSolve are held by a seal test rather than a unit
test, because swift test compiles Engine and Shared and finishSolve is in
neither — VariantInputSealTests' and QuietPresenceSealTests' answer to the
same problem. The seal also pins the two negatives: GameKind gains no case
and LoggedMove gains no field."
```

---

### Task 7: `DuelSession` — the turn state machine ⚠️ USER CONTRIBUTION

**Files:**
- Create: `nine/Sources/App/DuelSession.swift`
- Test: `nine/Tests/SharedTests/DuelHandoffTests.swift` (tests the *pure* policy, which lives in `Duel.swift`)

**Interfaces:**
- Consumes: `AppModel`, `DuelState`, `NineGame.errorCells`.
- Produces: `DuelSession` (`@Observable`, `@MainActor`) with `remaining: TimeInterval?`, `handoffPending: Bool`, `clearedCount: Int`, `func tick(now:)`, `func confirmHandoff()`; and the pure `DuelHandoff.decide(...)` it calls.

**This task contains the one function I am asking you to write.** Everything around it — the observable wrapper, the clearing, the timer plumbing, the tests — is scaffolding I will build. See "Step 3".

- [ ] **Step 1: Build the pure policy's failing test**

Create `nine/Tests/SharedTests/DuelHandoffTests.swift`:

```swift
// DuelHandoffTests.swift — when a turn ends, and what that costs.
import XCTest
@testable import NineShared

final class DuelHandoffTests: XCTestCase {

    private func input(
        remaining: TimeInterval? = 30,
        roseOpen: Bool = false,
        solved: Bool = false,
        untimed: Bool = false,
        placedThisTurn: Int = 0
    ) -> DuelHandoff.Input {
        DuelHandoff.Input(
            remaining: untimed ? nil : remaining,
            isUntimed: untimed,
            roseOpen: roseOpen,
            boardSolved: solved,
            placementsThisTurn: placedThisTurn
        )
    }

    func testATurnWithTimeLeftContinues() {
        XCTAssertEqual(DuelHandoff.decide(input()), .continue)
    }

    func testAnExpiredTurnHandsOff() {
        XCTAssertEqual(DuelHandoff.decide(input(remaining: 0)), .handOff)
    }

    /// PRD-27 §4.1 — a digit you did not confirm is not yours.
    func testAnExpiredTurnWithTheRoseOpenClosesTheRoseFirst() {
        XCTAssertEqual(DuelHandoff.decide(input(remaining: 0, roseOpen: true)), .closeRoseThenHandOff)
    }

    /// PRD-27 §4.1 — a solved board goes straight to Afterglow.
    func testASolvedBoardNeverHandsOff() {
        XCTAssertEqual(DuelHandoff.decide(input(remaining: 0, solved: true)), .finish)
        XCTAssertEqual(DuelHandoff.decide(input(remaining: 30, solved: true)), .finish)
        XCTAssertEqual(DuelHandoff.decide(input(remaining: 0, roseOpen: true, solved: true)), .finish)
    }

    /// PRD-27 §4.2 — VoiceOver and Switch Control suspend the deadline; the
    /// turn ends when the player places a digit instead.
    func testAnUntimedTurnEndsOnAPlacementAndNotBefore() {
        XCTAssertEqual(DuelHandoff.decide(input(untimed: true, placedThisTurn: 0)), .continue)
        XCTAssertEqual(DuelHandoff.decide(input(untimed: true, placedThisTurn: 1)), .handOff)
    }

    func testAnUntimedTurnIgnoresTheClockEntirely() {
        XCTAssertEqual(DuelHandoff.decide(input(remaining: 0, untimed: true, placedThisTurn: 0)), .continue)
    }
}
```

- [ ] **Step 2: Add the scaffolding around the decision**

Append to `nine/Sources/Shared/Duel.swift`:

```swift
/// When a turn ends, as a pure function — so the rule is testable on Linux and
/// the view layer only has to obey it.
public enum DuelHandoff {

    public struct Input: Equatable, Sendable {
        /// Seconds left, or nil when the turn has no deadline.
        public let remaining: TimeInterval?
        /// PRD-27 §4.2: VoiceOver or Switch Control is running, so this turn
        /// has no deadline at all and ends on a placement instead.
        public let isUntimed: Bool
        public let roseOpen: Bool
        public let boardSolved: Bool
        public let placementsThisTurn: Int

        public init(
            remaining: TimeInterval?,
            isUntimed: Bool,
            roseOpen: Bool,
            boardSolved: Bool,
            placementsThisTurn: Int
        ) {
            self.remaining = remaining
            self.isUntimed = isUntimed
            self.roseOpen = roseOpen
            self.boardSolved = boardSolved
            self.placementsThisTurn = placementsThisTurn
        }
    }

    public enum Decision: Equatable, Sendable {
        /// Nothing to do.
        case `continue`
        /// The turn is over. Clear, close the turn, open the next, show the card.
        case handOff
        /// The turn is over and the rose is open: dismiss it *without*
        /// committing, then hand off.
        case closeRoseThenHandOff
        /// The board is finished. No hand-off — Afterglow runs.
        case finish
    }

    // TODO(user): implement `decide`. See the plan's Task 7 Step 3.
    public static func decide(_ input: Input) -> Decision {
        .continue
    }
}
```

- [ ] **Step 3: ⚠️ USER WRITES `DuelHandoff.decide`**

**Context.** I've built the whole session around this: the 1 Hz tick, the quiet correction, the ledger writes, the hand-off card, and the six tests above. This one function decides what the mode actually *feels* like, and there are four genuinely contestable calls in it that I don't think I should make alone:

1. **Solved beats everything, including an open rose.** If the winning digit lands with the rose still open, is the board finished or does the rose still need dismissing first? I've written the test to assert `.finish` wins outright — but that means a solved board can swallow an open rose, and you may prefer the rose close cleanly first.
2. **An expired turn with the rose open.** `.closeRoseThenHandOff` discards an uncommitted digit. The kinder alternative is letting the in-flight commit land — but then the clock isn't really a deadline, and a player could hold the rose open indefinitely.
3. **An untimed turn (VoiceOver) ends on the *first* placement.** That is strict: a sighted player gets 90 seconds and might place four digits, while a VoiceOver player gets exactly one. Should it be one placement, or should the untimed turn end only when they place *and* the count matches what a timed turn typically yields?
4. **Order of precedence generally** — solved vs untimed vs rose vs expiry. The tests pin one ordering; a different one is defensible.

**Request.** In `nine/Sources/Shared/Duel.swift`, replace the `decide` stub's body. Roughly 8–10 lines.

**Guidance.** The six tests in `DuelHandoffTests` encode my proposed answers — if you disagree with any of them, change the test and the implementation together and say which one you changed and why. That disagreement is more valuable than the code. Constraints that aren't negotiable: the function must stay pure (no clock reads, no globals), total (every `Input` returns a `Decision`), and `boardSolved` must never produce a hand-off, because a hand-off card over the Afterglow celebration is the one outcome that is definitely wrong.

- [ ] **Step 4: Run the policy tests**

```bash
cd nine && swift test --filter DuelHandoffTests 2>&1 | tail -20
```
Expected: PASS, 6 tests.

- [ ] **Step 5: Build the session around it**

Create `nine/Sources/App/DuelSession.swift`:

```swift
// DuelSession.swift — the live half of a duel (PRD-27 §4, §5).
//
// The rule about *when* a turn ends is `DuelHandoff.decide`, in Shared, tested
// on Linux. This type is the plumbing: it reads the board clock, applies the
// quiet correction, moves the ledger on, and holds the one piece of state the
// views need — whether the hand-off card is up.
//
// It reads no clock of its own. `remaining` is a function of the board's
// `ElapsedTimer`, which is what makes a backgrounded app cost nobody their turn.
import Foundation
import SwiftUI

@MainActor
@Observable
final class DuelSession {

    /// Up between turns. While true the board's remote surface detaches on
    /// tvOS — the prefs-sheet pattern — so the card owns the focus engine.
    private(set) var handoffPending = false
    /// How many digits the quiet correction removed at the last hand-off.
    /// Zero prints nothing (PRD-27 §5's honest absence).
    private(set) var clearedCount = 0
    /// Placements in the current turn — the untimed turn's end condition.
    private(set) var placementsThisTurn = 0

    /// PRD-27 §4.2. Detected, never configured.
    var isUntimed: Bool {
        #if os(tvOS) || os(iOS)
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
        #else
        false
        #endif
    }

    func remaining(in model: AppModel, now: Date) -> TimeInterval? {
        guard !isUntimed, let game = model.game, let state = model.duelState else { return nil }
        return state.remaining(atElapsed: game.timer.elapsed(at: now))
    }

    /// Called from the 1 Hz `TimelineView` that already drives the timer chip,
    /// and after every placement.
    func evaluate(model: AppModel, roseOpen: Bool, now: Date) -> DuelHandoff.Decision {
        guard let game = model.game, model.duelState != nil else { return .continue }
        let decision = DuelHandoff.decide(
            DuelHandoff.Input(
                remaining: remaining(in: model, now: now),
                isUntimed: isUntimed,
                roseOpen: roseOpen,
                boardSolved: game.isSolved,
                placementsThisTurn: placementsThisTurn
            )
        )
        if decision == .handOff || decision == .closeRoseThenHandOff {
            beginHandoff(model: model, now: now)
        }
        return decision
    }

    func notePlacement() { placementsThisTurn += 1 }

    /// PRD-27 §5. **The order is load-bearing**: clear first, so the erases land
    /// in the move log *before* the next turn's `firstMoveIndex` is taken and
    /// are therefore credited to the player who made them, not the one arriving.
    private func beginHandoff(model: AppModel, now: Date) {
        guard let state = model.duelState else { return }
        clearedCount = model.clearDuelErrors()          // ← step 1: clear
        let next = (state.currentPlayer + 1) % DuelState.seats
        model.recordDuelTurn(                            // ← step 2: close and open
            player: next,
            startedAt: model.game?.timer.elapsed(at: now) ?? 0
        )
        placementsThisTurn = 0
        handoffPending = true                            // ← step 3: show the card
    }

    /// The incoming player is ready. Their clock has not been running: the turn
    /// opened at the elapsed second the card appeared, and the board clock is
    /// held while the card is up, so a slow pass across a sofa costs nothing.
    func confirmHandoff() {
        handoffPending = false
        clearedCount = 0
    }

    /// Re-entering a duel board always shows the card, whoever picks the device
    /// up (PRD-27 §8.3).
    func resume() { handoffPending = true }
}
```

Add to `AppModel` beside the other duel members:

```swift
    /// Erase every wrong digit on the board, silently. Returns how many.
    ///
    /// Through `NineGame.erase`, so each correction is an ordinary logged move
    /// inside the outgoing player's range rather than a mutation nothing can
    /// see. No haptic, no announcement, no toast — PRD-27 §5.
    func clearDuelErrors() -> Int {
        guard var g = game else { return 0 }
        let wrong = g.errorCells
        guard !wrong.isEmpty else { return 0 }
        let stamp = moveStamp(g)
        for cell in wrong {
            g.erase(at: cell, autoNotes: false, elapsed: stamp)
        }
        game = g
        persistProgress()
        return wrong.count
    }
```

**Note:** read `NineGame.erase`'s real signature in `nine/Sources/Engine/Game.swift:282` and match it exactly, including whether `autoNotes` takes a `Bool` or the prefs value. Do not guess.

- [ ] **Step 6: Build all three platforms**

```bash
cd nine && COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate
for dest in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$dest" -derivedDataPath build build 2>&1 | tail -3
done
```
Expected: three `** BUILD SUCCEEDED **`. `DuelSession.swift` is unfenced but `UIAccessibility` needs the `#if` above — macOS must still compile.

- [ ] **Step 7: Commit**

```bash
cd /Users/aquilops/conductor/workspaces/10x/osaka
git add nine/Sources/Shared/Duel.swift nine/Sources/App/DuelSession.swift \
        nine/Sources/App/AppModel.swift nine/Tests/SharedTests/DuelHandoffTests.swift
git commit -m "Nine: PRD-27 — the turn state machine

DuelHandoff.decide is pure and lives in Shared, so when a turn ends is
testable on Linux; DuelSession is the plumbing that reads the board clock and
moves the ledger on.

Clear, then close the turn, then open the next: the order is load-bearing,
because an erase logged after the boundary is credited to the player arriving
rather than the one who made it."
```

---

### Task 8: The tvOS surfaces

**Files:**
- Create: `nine/Sources/App/DuelHandoffCard.swift`
- Modify: `nine/Sources/App/HomeView.swift` (`extrasRow` `:209-243`), `nine/Sources/App/GameScreen.swift` (`timerChip` `:452`, `remoteBody` `:125`, `core` `:139`)
- Modify: `nine/Sources/Shared/EnglishPhrases.swift`, `nine/scripts/strings.py`

**Interfaces:**
- Consumes: `DuelSession`, `DuelState`, `AppModel.startDuel(difficulty:turnLength:isLight:)`.
- Produces: `DuelHandoffCard(state:clearedCount:accent:onConfirm:)`, `DuelSetupSheet(model:onStart:)`.

- [ ] **Step 1: Add the strings**

To `EnglishPhrases.table`, in sorted position:

```swift
        "duel.cleared": "%1$lld cells cleared.",
        "duel.handoff.begin": "Begin",
        "duel.handoff.title": "%1$@'s turn",
        "duel.length.brisk": "Brisk · 1 min",
        "duel.length.standard": "Standard · 90 sec",
        "duel.length.title": "Turn length",
        "duel.length.unhurried": "Unhurried · 3 min",
        "duel.setup.start": "Start",
        "duel.title.touch": "Pass and Play",
        "duel.title.tv": "Pass the Remote",
        "duel.blurb": "Two players, one board, taking turns.",
```

Add a plural for `duel.cleared` in `EnglishPhrases.plurals`:

```swift
        "duel.cleared": EnglishPlural(count: 1, one: "%1$lld cell cleared."),
```

Add all eleven to `COMMENTS` in `scripts/strings.py`. Each comment must name the part of speech, where it appears, and what the arguments are. The two that need care:

```python
    "duel.cleared": "Shown on the hand-off card between turns of a two-player local duel (PRD-27), only when at least one digit was removed. %1$lld is a count of board squares. DELIBERATELY BLAME-FREE and with no subject: it does not say who placed them or that they were wrong. Do not add a possessive or the word \"your\". PLURAL.",
    "duel.title.tv": "Title of the Apple TV shelf card that starts a two-player game where people take turns with the SAME physical remote, handing it back and forth. Not networked, not online. The iPad wording is a separate key (duel.title.touch) because there is no remote there.",
```

- [ ] **Step 2: Build the hand-off card**

Create `nine/Sources/App/DuelHandoffCard.swift`. It must:
- show `Strings.string("duel.handoff.title", .text(name))` in the incoming player's tint;
- show `Strings.string("duel.cleared", .int(n))` **only when `n > 0`**;
- carry exactly one action, labelled `duel.handoff.begin`, with `.contentShape(.accessibility, Capsule())` so its AX frame clears 44pt (PRD-24's tier cards reported 41pt without it);
- claim focus on tvOS via `FocusHalo(claimsDefaultFocus: true)` — read `CouchKit/GlassComponents.swift:231-284` and use it, do not add a bare `.focusable()`;
- post an accessibility announcement on appear.

- [ ] **Step 3: Wire the game screen**

In `GameScreen.swift`:

- `timerChip` (`:452`) — when `model.isDuel` and `duel.remaining(in:now:)` is non-nil, render the countdown **ignoring `prefs.showTimer`** (PRD-27 §4). Reuse the existing `TimelineView(.periodic(from: .now, by: 1))`; do not add a second one. Format with `SolveCardFacts.elapsedText` if it accepts a plain interval — check first.
- `remoteBody` (`:125`) — extend the existing detach condition so the surface also detaches while `duel.handoffPending`:

```swift
if showPrefs || duel.handoffPending { core }
else { core.couchRemote(chrome: chrome, eightWay: true, interceptsBack: true) { handle($0) } }
```

- `core` (`:139`) — add the card as an overlay, and pass `digitTint:` to `BoardView` (`:396`):

```swift
digitTint: model.duelState.map { state in
    { cell in
        guard let player = state.player(forMoveIndex: /* the move that filled this cell */) else { return nil }
        return AccentChoice(rawValue: state.accent(forPlayer: player))?.color(isLight: colorScheme == .light)
    }
}
```

**This needs a cell→move-index map**, which `DuelState` does not have. Add it to `DuelCredits.swift` as a pure helper and unit-test it in the same commit:

```swift
/// The last placement into each cell, as a move index — which is what turns a
/// board position into an owner. Recomputed per board draw rather than cached,
/// because an incremental cache and a move log are two records of one fact.
public static func owners(state: DuelState, moves: [LoggedMove]) -> [Int: Int] {
    var owner: [Int: Int] = [:]
    for (index, move) in moves.enumerated() {
        switch move.kind {
        case .place: owner[move.cell] = state.player(forMoveIndex: index)
        case .erase: owner[move.cell] = nil
        default: break
        }
    }
    return owner
}
```

Add tests for `owners` to `DuelCreditsTests` covering: a place then an erase leaves no owner; a place over another player's digit transfers it; an undo does not transfer (undo is an event, and the board state it restores is already reflected by the next real move).

- [ ] **Step 4: Add the shelf card and setup sheet**

In `HomeView.swift`'s `extrasRow` (`:209-243`), add a card following the existing `ShelfCard` idiom exactly (360×300 sizing, `focusHalo`), titled `duel.title.tv`, opening a `GlassSheet` containing difficulty cards × the three turn lengths, whose confirm calls `model.startDuel(...)`.

- [ ] **Step 5: Build, then drive it**

```bash
cd nine && COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate
xcodebuild -project Nine.xcodeproj -scheme Nine -destination 'generic/platform=tvOS Simulator' -derivedDataPath build build 2>&1 | tail -3
```

Then use the `run-couch-suite` skill to install and drive on an Apple TV simulator. **Walk the whole loop and keep the screenshots:** shelf card → setup → board → let a turn expire → hand-off card → confirm → place a wrong digit → let it expire → confirm the "1 cell cleared." line → solve → debrief.

**The three things to look for specifically**, because they are green in every build:
1. Does the hand-off card actually take focus, or does the board surface keep it? (Detach bug.)
2. Do both tints render, and are they distinguishable on the actual TV panel?
3. Does the countdown appear with `prefs.showTimer` off?

- [ ] **Step 6: Commit**

```bash
cd /Users/aquilops/conductor/workspaces/10x/osaka
git add nine/Sources/App/DuelHandoffCard.swift nine/Sources/App/HomeView.swift \
        nine/Sources/App/GameScreen.swift nine/Sources/App/DuelCredits.swift \
        nine/Sources/Shared/EnglishPhrases.swift nine/scripts/strings.py \
        nine/Sources/Strings/Localizable.xcstrings nine/Tests/SharedTests/DuelCreditsTests.swift
git commit -m "Nine: PRD-27 — the duel on Apple TV

Shelf card, setup, countdown chip and the hand-off card. The card owns the
focus engine while up and the board's couchRemote surface detaches, which is
the prefs-sheet pattern GameScreen already uses in both its bodies."
```

---

### Task 9: The iPad surface

**Files:**
- Modify: `nine/Sources/App/TouchUI.swift` (`shelfPair` `:200-241`, `draftingTable(_:in:)` `:991-1013`, `chromed` `:1021-1066`)

- [ ] **Step 1: Gate on the composition, never the device**

In `TouchHomeView.body` (`:63-69`), the `resolve(...).table != nil` branch already exists. Add the duel row to `shelfPair`'s **trailing** column (boards you could start), titled `duel.title.touch`. The column arm only — an iPhone must get no duel row, and it gets none for free because `shelfColumn` is a different function.

- [ ] **Step 2: Wire the game screen's table arm**

In `draftingTable(_:in:)` (`:991`), pass `digitTint:` to the board exactly as Task 8 did, and add the hand-off card to `chromed`'s overlay stack (`:1021`) — `chromed` is the one shared overlay stack for both arms, so **guard the card on the table composition** or an iPhone inherits it.

The countdown goes in the same `timerChip` this file already has; find it and apply Task 8 Step 3's rule.

- [ ] **Step 3: Build and drive on an iPad simulator**

```bash
cd nine && xcodebuild -project Nine.xcodeproj -scheme Nine -destination 'generic/platform=iOS Simulator' -derivedDataPath build build 2>&1 | tail -3
```

Install on an iPad simulator and walk the same loop as Task 8 Step 5. **Then rotate to portrait** and confirm the duel row and card are gone — that is the composition gate doing its job, and it is the one thing a landscape-only walk cannot see.

- [ ] **Step 4: Commit**

```bash
cd /Users/aquilops/conductor/workspaces/10x/osaka
git add nine/Sources/App/TouchUI.swift
git commit -m "Nine: PRD-27 — the duel on the drafting table

Offered where BoardCompositionRules.resolve returns .table and nowhere else,
so 'iPad landscape' is a measured property of the window rather than a device
check. An iPhone gets no duel row because shelfColumn is a different function."
```

---

### Task 10: VoiceOver hears the owner

**Files:**
- Modify: `nine/Sources/Shared/BoardSpeech.swift` (`cellValue` `:228`, `Phrase` block)
- Modify: `nine/Sources/App/BoardAccessibility.swift` (thread an owner name through, `:148-180`)
- Modify: `nine/Sources/Shared/EnglishPhrases.swift`, `nine/scripts/strings.py`
- Test: `nine/Tests/SharedTests/BoardSpeechTests.swift` (append)

- [ ] **Step 1: Write the failing test**

Append to `BoardSpeechTests`:

```swift
    // MARK: - PRD-27, the duel owner

    func testANonDuelBoardsValueIsByteIdenticalToBefore() {
        let game = Self.sampleGame()   // reuse this file's existing fixture helper
        for cell in 0..<81 {
            XCTAssertEqual(
                BoardSpeech.cellValue(cell, in: game, showErrors: false),
                BoardSpeech.cellValue(cell, in: game, showErrors: false, owner: nil),
                "cell \(cell) — the four AX baselines are the standing proof of this")
        }
    }

    func testADuelEntryNamesWhoPlacedIt() {
        var game = Self.sampleGame()
        let cell = Self.firstEmptyCell(in: game)
        game.place(4, at: cell, autoNotes: false, elapsed: 0)
        let spoken = BoardSpeech.cellValue(cell, in: game, showErrors: false, owner: "Ember")
        XCTAssertTrue(spoken.contains("Ember"))
        XCTAssertTrue(spoken.contains("4"))
    }

    func testAGivenHasNoOwnerEvenInADuel() {
        let game = Self.sampleGame()
        let given = try! XCTUnwrap((0..<81).first { game.isGiven($0) })
        XCTAssertEqual(
            BoardSpeech.cellValue(given, in: game, showErrors: false, owner: "Ember"),
            BoardSpeech.cellValue(given, in: game, showErrors: false, owner: nil),
            "a given belongs to the puzzle, not to a player")
    }

    func testAnEmptyCellHasNoOwner() {
        let game = Self.sampleGame()
        let empty = Self.firstEmptyCell(in: game)
        XCTAssertEqual(
            BoardSpeech.cellValue(empty, in: game, showErrors: false, owner: "Ember"),
            BoardSpeech.cellValue(empty, in: game, showErrors: false, owner: nil))
    }
```

- [ ] **Step 2: Add the string and the overload**

`EnglishPhrases.table`, sorted:

```swift
        "board.value.owned": "%1$@, %2$@",
```

`COMMENTS`:

```python
    "board.value.owned": "VoiceOver, the value of one board square during a two-player local duel (PRD-27). %1$@ is the square's ordinary spoken value (usually just a digit, e.g. \"4\"); %2$@ is the name of the player who placed it, which is the name of their colour (\"Glacier\", \"Ember\"). Punctuation and order only — both halves are already-translated strings, so add no words of your own. Same sanctioned shape as board.cell.withRule.",
```

In `BoardSpeech.swift`, add an overload beside `cellValue` following `cellLabel(_:rules:)`'s exact pattern (`:105-110`):

```swift
    /// The value, plus who placed it during a duel (PRD-27 §9).
    ///
    /// **In the value, not the label** — the opposite of where PRD-24 put the
    /// cage clause, and for the difference between the two facts. A cage's sum
    /// is permanent board information, closer to a given, so it belongs in the
    /// part that locates the cell and never changes. *Who placed this digit*
    /// changes whenever the digit does, and value is the part VoiceOver
    /// re-speaks on every focus move.
    ///
    /// Givens and empty cells have no owner, so `owner` is ignored for both and
    /// a non-duel board is byte-identical to the one-argument form — which the
    /// four `Tests/AXBaselines/*.txt` are the standing proof of.
    public static func cellValue(
        _ cell: Int, in game: NineGame, showErrors: Bool, owner: String?
    ) -> String {
        let base = cellValue(cell, in: game, showErrors: showErrors)
        guard let owner, !owner.isEmpty,
              isValidCell(cell),
              game.entry(at: cell) != 0,
              !game.isGiven(cell) else { return base }
        return Phrase.ownedValue(base, owner)
    }
```

and to `Phrase`:

```swift
        static func ownedValue(_ value: String, _ owner: String) -> String {
            Phrasebook.current.string("board.value.owned", .text(value), .text(owner))
        }
```

Add `board.value.owned` to `strings.py`'s splice allowlist **with its reason** (both halves are finished translated strings, so what the join carries is punctuation and order — the same sanctioned shape as `board.cell.withRule` and `board.announce.pair`).

- [ ] **Step 3: Thread it through `BoardAXGrid`**

In `BoardAccessibility.swift`, add `var owners: [Int: String]? = nil` to `BoardAXGrid` — **`= nil` by default, so every classic caller produces a byte-identical tree**, which is `channelRules`' documented pattern in the same file. Use it at `:163`:

```swift
.accessibilityValue(BoardSpeech.cellValue(cell, in: game, showErrors: showErrors, owner: owners?[cell]))
```

Pass it from the two duel-capable screens only.

- [ ] **Step 4: Run tests, rebuild the catalog, audit**

```bash
cd nine
python3 scripts/strings.py --build-catalog && python3 scripts/strings.py --audit
swift test --filter "BoardSpeechTests|CatalogTests|PhrasebookTests" 2>&1 | tail -10
```
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/aquilops/conductor/workspaces/10x/osaka
git add nine/Sources/Shared/BoardSpeech.swift nine/Sources/App/BoardAccessibility.swift \
        nine/Sources/Shared/EnglishPhrases.swift nine/scripts/strings.py \
        nine/Sources/Strings/Localizable.xcstrings nine/Tests/SharedTests/BoardSpeechTests.swift
git commit -m "Nine: PRD-27 — VoiceOver hears who placed the digit

In the value, not the label, which is the opposite of PRD-24's cage clause
and for the difference between the two facts: a cage sum is permanent board
information, an owner changes whenever the digit does, and value is what
VoiceOver re-speaks on every focus move."
```

---

### Task 11: The full verification sweep

**Files:** none created; this task is the gate.

- [ ] **Step 1: The whole suite**

```bash
cd nine && swift test 2>&1 | tail -20
```
Expected: 0 failures. Note the count and the wall time — it must stay under ~120 s per EXECUTING-A-PRD §5.

- [ ] **Step 2: The corpora**

```bash
cd nine && swift test --filter "GoldenCorpus|VariantCorpus|ConstraintDelegation" 2>&1 | tail -5
```
Expected: 56/56 and 9/9. **A mismatch is a bug until proven otherwise** — and here it would falsify the PRD's central claim that nothing in the diff reaches the Engine.

- [ ] **Step 3: The AX baselines — no re-record**

```bash
cd nine && python3 scripts/ax-snapshot.py
```
Expected: all five screens match. **A drift is a bug**: it means the duel leaked onto a non-duel board, most likely `BoardAXGrid.owners` not defaulting to nil or `digitTint` not defaulting to nil. Do **not** `--record` your way past this. The captured dumps are in `Tests/AXBaselines/.captured/` either way.

- [ ] **Step 4: Strings**

```bash
cd nine && python3 scripts/strings.py --audit
```
Expected: zero new offences against `Tests/StringBaselines/offences.txt`, zero missing, zero dead, generator no-drift.

- [ ] **Step 5: The Release archive**

```bash
cd nine && xcodebuild archive -project Nine.xcodeproj -scheme Nine \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath /tmp/NineRelease.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -5
```
Expected: `** ARCHIVE SUCCEEDED **`. Release breaks in ways Debug does not and CI archives in Release.

- [ ] **Step 6: The downgrade drill**

Add to `nine/Tests/EngineTests/DowngradeDrillTests.swift` a case proving a duel board survives a build with no `nine.duel` reader: encode a `BoardLibrary` containing a duel's `.free` entry, decode it with the duel ledger absent, and assert the board, its move log and its solved state all come back intact. A duel board must degrade to an ordinary free board and lose only the attribution.

- [ ] **Step 7: The taste ritual**

Run all five against the built app, per EXECUTING-A-PRD §1, and write the answers into the DEVIATIONS section: the 11pm-in-bed test, the roommate test, the first-flick test, the delete-it-for-a-week test, the idle-pixel test. **The idle-pixel test is the one this PRD is most exposed to** — confirm on a running simulator that the board is genuinely still while the countdown ticks, and say how you confirmed it.

- [ ] **Step 8: Write the DEVIATIONS section**

Append a `## PRD-27 — …` section to `nine/DEVIATIONS.md` following the shape of the PRD-24 section immediately above it: what was found that the plan got wrong, a **Numbers** table with measured values, and **Not done, each with its reason**. Prefer a measured number over an adjective.

Update `nine/PROGRAM-2.0.md`'s status table: row for PRD-27, and the Wave 3 remainder line at `:35`.

- [ ] **Step 9: Commit and open the PR**

```bash
cd /Users/aquilops/conductor/workspaces/10x/osaka
git add nine/DEVIATIONS.md nine/PROGRAM-2.0.md nine/Tests/EngineTests/DowngradeDrillTests.swift
git commit -m "Nine: PRD-27 — deviations, drill and program status"
gh pr create --base main --title "Nine: two players, one remote, and errors nobody is told about (PRD-27)"
```

---

## Self-Review

**Spec coverage.** §1 thesis → whole plan. §2 turn-as-window → Task 2. §3 sibling blob + no `GameKind` case → Tasks 2, 6 (sealed). §4 turn clock, three lengths, chip override → Tasks 2, 8. §4.1 expiry, rose, solved → Task 7. §4.2 VoiceOver out → Task 7. §5 quiet correction + ordering → Task 7. §6 tint → Tasks 1, 5. §7 refusals → Task 6. §8.1 composition gate → Task 9. §8.2 shelf → Tasks 8, 9. §8.3 hand-off card + focus detach + resume → Tasks 7, 8. §9 AX → Task 10. §10 debrief → Task 4. §11 input budget → nothing to build; asserted in Task 11's taste ritual. §12 not-done → Task 11 Step 8. §13 verification → Task 11.

**Gap found and closed:** §8.3's "resuming always re-enters through the hand-off card" had no step. `DuelSession.resume()` is in Task 7 Step 5, but nothing *calls* it — **Task 8 Step 3 must call `duel.resume()` when a duel board is opened from the library**, and Task 9 must do the same on the table arm. Added to both.

**Gap found and closed:** the cell→owner map (`DuelCredits.owners`) was needed by Task 8's `digitTint` but defined nowhere. Now defined and tested in Task 8 Step 3.

**Placeholder scan.** Three steps say "read the real signature before editing" (`NineGame.erase`, `ReplayVault`'s accessor, `SolveDebriefTests`' fixture helper). Those are deliberate — the plan should not assert a signature it has not read, and guessing one is how a plan ships a compile error. Every other step carries its actual content.

**Type consistency.** `DuelState.player(forMoveIndex:)` is spelled identically in Tasks 2, 3 and 8. `DuelTint.partner(for:isLight:)` takes `isLight` in Tasks 1, 2 and 6. `DuelCredits.init(state:moves:solution:)` matches between Tasks 3, 4 and 6. `SolveDebrief.init(replay:analysis:duel:names:)` matches between Tasks 4 and 6. `DuelHandoff.Input`'s five fields match between Tasks 7's test and its implementation.
