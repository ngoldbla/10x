# Nine Cloud Library (PRD-8) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync every board (daily, free-play partials, played log) through CloudKit so a player can start a puzzle on one device and finish it on another, picking up where they left off.

**Architecture:** A pure, SwiftPM-testable merge core lives in the Engine (`SyncedEntry` projection + merge rules over `LibraryEntry`/`BoardLibrary`). A thin, CloudKit-only `LibraryCloudStore` in a new `Sources/App/CloudSync/` module owns a `CKSyncEngine` (private DB, one custom zone `NineLibrary`, one `CKRecord` per entry), (de)serializes records, and drives the merge core; `AppModel` talks to it through a narrow interface (push / delete / apply-remote). The Engine never imports CloudKit; CloudKit never sees an undo stack.

**Tech Stack:** Swift 6, CloudKit `CKSyncEngine` (iOS 18 / tvOS 18 / macOS 15), CouchKit `CouchStored` (JSON-on-disk persistence), swift-testing (`import Testing`), xcodegen (`project.yml`).

## Global Constraints

- **Tolerant decoding is law.** `CouchStored` discards the whole blob when decode throws. Every persisted type's `init(from:)` uses `decodeIfPresent(...) ?? default` for fields added after 1.1, and `try?` for enum fields, following `NinePrefs` (`AppModel.swift:231`) and `NineGame` (`Game.swift:71`).
- **Engine sources stay UI- and CloudKit-free.** No `import CloudKit` / `import SwiftUI` anywhere under `Sources/Engine`. CloudKit appears only under `Sources/App/CloudSync/`.
- **Records exclude `undoStack` and `moveLog`** — device-local UX state. Payload target ~1–2 KB.
- **One `CKRecord` per `LibraryEntry`**, record name = entry `id.uuidString`, record type `LibraryEntry`, in one custom zone named `NineLibrary`, private database.
- **Merge rules (PRD-8 §2), verbatim:** last-writer-wins by `updatedAt`; `solved` always beats `inProgress`; the same day's daily merges through `adoptDaily` (one-entry-per-day); on divergent progress higher `fillFraction` wins and the loser is retained as an `archived` copy (never destroyed); never lose progress silently.
- **KVS stays** for streak + history (unchanged). No migration of streak/history off KVS.
- **No new UI.** The only visible signal is the existing Continue/Today fill ring updating on foreground.
- **No account → today's behavior.** Purely local, zero errors surfaced to UI; quiet re-sync when an account appears; `accountChanged` resets the engine cleanly.
- **Apple team is Aquilops LLC `XC6FN96MA8` only.** The CloudKit container `iCloud.com.couchsuite.nine` + capability already exist on the three app IDs (portal work DONE). Do **not** run `match`; the profile re-mint is handled separately. This branch must not merge until re-minted profiles land (PRD-7 §5 gate).

---

## File Structure

**Engine (pure, tested under `NineEngineTests`):**
- Modify `Sources/Engine/Game.swift` — add `NineGame.clearLocalHistory()`.
- Create `Sources/Engine/LibrarySync.swift` — `SyncedEntry` projection + `LibrarySync` merge functions.
- Create `Tests/EngineTests/LibrarySyncTests.swift` — round-trip, merge rules, daily invariant, idempotence.

**CloudSync (CloudKit, App target only — not SwiftPM-testable):**
- Create `Sources/App/CloudSync/LibrarySyncState.swift` — persisted `CKSyncEngine` state blob (`CouchStored`, tolerant decode).
- Create `Sources/App/CloudSync/LibraryCloudStore.swift` — `CKSyncEngine` owner, `CKRecord` (de)serialization, narrow interface.

**Integration + signing:**
- Modify `Sources/App/AppModel.swift` — own the store, push on progress/solve/delete, apply remote changes.
- Modify `Sources/App/NineApp.swift` — cross-platform foreground hook (tvOS/macOS gain a `scenePhase` `.active` sync kick; iOS extends the existing one).
- Modify `Nine-iOS.entitlements`, `Nine-macOS.entitlements` — add CloudKit container.
- Create `Nine-tvOS.entitlements` — new tvOS entitlements story (base entitlements + CloudKit).
- Modify `project.yml` — tvOS `CODE_SIGN_ENTITLEMENTS` override.

---

## Phase 1 — Engine merge core (TDD)

### Task 1: `NineGame.clearLocalHistory()`

**Files:**
- Modify: `Sources/Engine/Game.swift` (add a mutating method to `NineGame`, after `undo()` around line 191)
- Test: `Tests/EngineTests/LibrarySyncTests.swift` (new file)

**Interfaces:**
- Produces: `mutating func NineGame.clearLocalHistory()` — empties `undoStack` and `moveLog`, leaving `entries`, `pencil`, `timer`, `puzzle` untouched.

- [ ] **Step 1: Write the failing test**

Create `Tests/EngineTests/LibrarySyncTests.swift`:

```swift
// LibrarySyncTests — the cloud merge core (PRD-8). Pure, no CloudKit, no UI,
// no clocks: every timestamp is injected, so the projection round-trip, the
// per-entry merge rules and the one-daily-per-day invariant are deterministic.
import Testing
import Foundation
@testable import NineEngine

@Suite("LibrarySync")
struct LibrarySyncTests {

    // MARK: helpers

    private func t(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
    }

    private func game(seed: UInt64 = 1, difficulty: Difficulty = .gentle) -> NineGame {
        NineGame(puzzle: PuzzleGenerator.generate(seed: seed, difficulty: difficulty))
    }

    /// Place `count` correct digits into the first empty non-given cells.
    private func progressed(seed: UInt64 = 1, count: Int) -> NineGame {
        var g = game(seed: seed)
        let holes = (0..<81).filter { !g.isGiven($0) }
        for cell in holes.prefix(count) { g.place(g.puzzle.solution.cells[cell], at: cell) }
        return g
    }

    private func solved(seed: UInt64 = 1) -> NineGame {
        var g = game(seed: seed)
        for cell in 0..<81 where !g.isGiven(cell) {
            g.place(g.puzzle.solution.cells[cell], at: cell)
        }
        return g
    }

    // MARK: projection

    @Test func clearLocalHistoryDropsUndoAndLogKeepsBoard() {
        var g = progressed(count: 5)
        #expect(!g.undoStack.isEmpty)
        #expect(!g.moveLog.isEmpty)
        let entries = g.entries, pencil = g.pencil
        g.clearLocalHistory()
        #expect(g.undoStack.isEmpty)
        #expect(g.moveLog.isEmpty)
        #expect(g.entries == entries)
        #expect(g.pencil == pencil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LibrarySync/clearLocalHistoryDropsUndoAndLogKeepsBoard`
Expected: FAIL — `value of type 'NineGame' has no member 'clearLocalHistory'`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/Engine/Game.swift`, inside `struct NineGame`, after `undo()` (line 191):

```swift
    /// Drop device-local UX state (undo stack + move log). The cloud record
    /// carries only the board — undo/redo history is per-device and never
    /// synced (PRD-8 §2). Must live inside NineGame: the two arrays are
    /// `private(set)` (file-scoped setter).
    public mutating func clearLocalHistory() {
        undoStack = []
        moveLog = []
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LibrarySync/clearLocalHistoryDropsUndoAndLogKeepsBoard`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Engine/Game.swift Tests/EngineTests/LibrarySyncTests.swift
git commit -m "Nine: NineGame.clearLocalHistory() for the cloud projection (PRD-8)"
```

---

### Task 2: `SyncedEntry` projection type

**Files:**
- Create: `Sources/Engine/LibrarySync.swift`
- Test: `Tests/EngineTests/LibrarySyncTests.swift`

**Interfaces:**
- Consumes: `LibraryEntry`, `NineGame.clearLocalHistory()`, `GameKind`, `BoardStatus`.
- Produces:
  - `struct SyncedEntry: Codable, Sendable, Equatable` with public stored props `id: UUID`, `kind: GameKind`, `status: BoardStatus`, `game: NineGame`, `createdAt: Date`, `updatedAt: Date`, `solvedAt: Date?`.
  - `init(_ entry: LibraryEntry)` — strips the game via `clearLocalHistory()`.
  - `func hydrated() -> LibraryEntry` — rebuilds a `LibraryEntry` (empty undo/log).
  - Tolerant `init(from:)`.

- [ ] **Step 1: Write the failing test**

Append to `LibrarySyncTests.swift`:

```swift
extension LibrarySyncTests {

    @Test func syncedEntryRoundTripsDroppingOnlyLocalHistory() {
        let entry = LibraryEntry(
            kind: .free(.sharp), game: progressed(count: 7),
            status: .inProgress, createdAt: t(0), updatedAt: t(10)
        )
        let back = SyncedEntry(entry).hydrated()
        #expect(back.id == entry.id)
        #expect(back.kind == entry.kind)
        #expect(back.status == entry.status)
        #expect(back.createdAt == entry.createdAt)
        #expect(back.updatedAt == entry.updatedAt)
        #expect(back.solvedAt == entry.solvedAt)
        // Board preserved; only the device-local history is gone.
        #expect(back.game.entries == entry.game.entries)
        #expect(back.game.pencil == entry.game.pencil)
        #expect(back.game.undoStack.isEmpty)
        #expect(back.game.moveLog.isEmpty)
    }

    @Test func syncedEntryCodableRoundTrips() throws {
        let entry = LibraryEntry(
            kind: .daily(day: 19_000), game: solved(),
            status: .solved, createdAt: t(0), updatedAt: t(20), solvedAt: t(20)
        )
        let data = try JSONEncoder().encode(SyncedEntry(entry))
        let decoded = try JSONDecoder().decode(SyncedEntry.self, from: data)
        #expect(decoded == SyncedEntry(entry))
    }

    @Test func syncedEntryToleratesMissingSolvedAt() throws {
        // A record written before solvedAt existed must decode, not throw.
        let entry = LibraryEntry(
            kind: .free(.gentle), game: game(), status: .inProgress,
            createdAt: t(0), updatedAt: t(1)
        )
        var obj = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(SyncedEntry(entry))
        ) as! [String: Any]
        obj.removeValue(forKey: "solvedAt")
        let data = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(SyncedEntry.self, from: data)
        #expect(decoded.solvedAt == nil)
        #expect(decoded.id == entry.id)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LibrarySync/syncedEntryRoundTripsDroppingOnlyLocalHistory`
Expected: FAIL — `cannot find 'SyncedEntry' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/Engine/LibrarySync.swift`:

```swift
// LibrarySync.swift — the cloud merge core (PRD-8). Pure, Sendable, no
// CloudKit and no UI, so it lives in the Engine and is fully SwiftPM-testable
// on Linux. `SyncedEntry` is the CloudKit projection of a `LibraryEntry`
// (drops the undo stack and move log — device-local UX state, ~1-2 KB once
// gone); `LibrarySync` holds the merge rules that reconcile a remote entry
// into the local library without ever losing progress silently.
import Foundation

/// A `LibraryEntry` as it travels through CloudKit: the board and its
/// lifecycle, minus device-local history. One `SyncedEntry` ⇔ one `CKRecord`.
public struct SyncedEntry: Codable, Sendable, Equatable {
    public let id: UUID
    public var kind: GameKind
    public var status: BoardStatus
    public var game: NineGame
    public let createdAt: Date
    public var updatedAt: Date
    public var solvedAt: Date?

    /// Project a library entry for the cloud: strip undo/move log.
    public init(_ entry: LibraryEntry) {
        var g = entry.game
        g.clearLocalHistory()
        self.id = entry.id
        self.kind = entry.kind
        self.status = entry.status
        self.game = g
        self.createdAt = entry.createdAt
        self.updatedAt = entry.updatedAt
        self.solvedAt = entry.solvedAt
    }

    /// Rebuild a library entry (undo/move log start empty on the new device).
    public func hydrated() -> LibraryEntry {
        LibraryEntry(
            id: id, kind: kind, game: game, status: status,
            createdAt: createdAt, updatedAt: updatedAt, solvedAt: solvedAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, status, game, createdAt, updatedAt, solvedAt
    }

    /// Tolerant decoding: any field added after this ships must fall back to a
    /// default rather than throwing (a thrown decode drops the whole record).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(GameKind.self, forKey: .kind)
        status = (try? c.decode(BoardStatus.self, forKey: .status)) ?? .inProgress
        game = try c.decode(NineGame.self, forKey: .game)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        solvedAt = try c.decodeIfPresent(Date.self, forKey: .solvedAt)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LibrarySync`
Expected: PASS (all projection tests green).

- [ ] **Step 5: Commit**

```bash
git add Sources/Engine/LibrarySync.swift Tests/EngineTests/LibrarySyncTests.swift
git commit -m "Nine: SyncedEntry cloud projection of LibraryEntry (PRD-8)"
```

---

### Task 3: Per-entry merge rules (same id)

**Files:**
- Modify: `Sources/Engine/LibrarySync.swift` (add `LibrarySync` enum + `reconcile`)
- Test: `Tests/EngineTests/LibrarySyncTests.swift`

**Interfaces:**
- Consumes: `LibraryEntry`, `NineGame.fillFraction`, `NineGame.entries`.
- Produces:
  - `enum LibrarySync` namespace.
  - `struct Reconciliation: Equatable { public var winner: LibraryEntry; public var archivedLoser: LibraryEntry? }`
  - `static func reconcile(_ a: LibraryEntry, _ b: LibraryEntry, makeID: () -> UUID) -> Reconciliation`
    - Precondition: `a.id == b.id`. Rules:
      1. If exactly one is `.solved`, it wins; `archivedLoser == nil`.
      2. If both `.solved`, the later `solvedAt` (tie: later `updatedAt`) wins; `archivedLoser == nil`.
      3. Else if the two games' user-entries are equal, the later `updatedAt` wins; `archivedLoser == nil`.
      4. Else if one game's user-entries are a conflict-free superset of the other's (pure continuation), the superset wins; `archivedLoser == nil`.
      5. Else (divergent): higher `fillFraction` wins (tie: later `updatedAt`); the loser is retained as a **new** entry (`makeID()`, `status = .archived`).

- [ ] **Step 1: Write the failing test**

Append to `LibrarySyncTests.swift`:

```swift
extension LibrarySyncTests {

    private func entry(
        id: UUID = UUID(), kind: GameKind = .free(.gentle), game: NineGame,
        status: BoardStatus = .inProgress, created: TimeInterval = 0,
        updated: TimeInterval, solved: TimeInterval? = nil
    ) -> LibraryEntry {
        LibraryEntry(
            id: id, kind: kind, game: game, status: status,
            createdAt: t(created), updatedAt: t(updated),
            solvedAt: solved.map(t)
        )
    }

    private var seqID: () -> UUID {
        var n = 0
        return { n += 1; return UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")! }
    }

    @Test func reconcileLastWriterWinsWhenBoardsAgree() {
        let id = UUID()
        // Same board content, different metadata timestamps → newer wins.
        let g = progressed(count: 4)
        let a = entry(id: id, game: g, updated: 10)
        let b = entry(id: id, game: g, updated: 20)
        let r = LibrarySync.reconcile(a, b, makeID: seqID)
        #expect(r.winner.updatedAt == t(20))
        #expect(r.archivedLoser == nil)
    }

    @Test func reconcileSolvedBeatsInProgressRegardlessOfTime() {
        let id = UUID()
        let inProg = entry(id: id, game: progressed(count: 30), status: .inProgress, updated: 100)
        let done = entry(id: id, game: solved(), status: .solved, updated: 5, solved: 5)
        let r = LibrarySync.reconcile(inProg, done, makeID: seqID)
        #expect(r.winner.status == .solved)          // solved wins though older
        #expect(r.archivedLoser == nil)
    }

    @Test func reconcileContinuationTakesTheSuperset() {
        let id = UUID()
        let short = entry(id: id, game: progressed(count: 5), updated: 10)
        let long = entry(id: id, game: progressed(count: 12), updated: 8) // fewer minutes but more moves
        let r = LibrarySync.reconcile(short, long, makeID: seqID)
        #expect(r.winner.game.fillFraction > short.game.fillFraction) // the longer board
        #expect(r.archivedLoser == nil)               // pure progress, nothing to archive
    }

    @Test func reconcileDivergentKeepsHigherFillArchivesLoser() {
        let id = UUID()
        // Two boards from DIFFERENT seeds progressed to different fills — the
        // user-entry sets conflict, so neither is a superset.
        let lower = entry(id: id, game: progressed(seed: 1, count: 6), updated: 30)
        let higher = entry(id: id, game: progressed(seed: 2, count: 15), updated: 10)
        let r = LibrarySync.reconcile(lower, higher, makeID: seqID)
        #expect(r.winner.game.fillFraction == higher.game.fillFraction)
        let loser = try #require(r.archivedLoser)
        #expect(loser.status == .archived)
        #expect(loser.id != id)                        // retained under a new id
        #expect(loser.game.entries == lower.game.entries) // progress preserved
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LibrarySync/reconcile`
Expected: FAIL — `type 'LibrarySync' has no member 'reconcile'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/Engine/LibrarySync.swift`:

```swift
public enum LibrarySync {

    /// The outcome of reconciling two versions of the same board id.
    public struct Reconciliation: Equatable {
        /// The version to keep under the shared id.
        public var winner: LibraryEntry
        /// A divergent loser preserved under a NEW id (status `.archived`), or
        /// nil when there was nothing to save.
        public var archivedLoser: LibraryEntry?
    }

    /// Reconcile two entries that share an id (`a.id == b.id`), never losing
    /// progress silently. See the type-level rules in this task.
    public static func reconcile(
        _ a: LibraryEntry, _ b: LibraryEntry, makeID: () -> UUID
    ) -> Reconciliation {
        // Rule 1/2: solved is terminal truth.
        switch (a.status == .solved, b.status == .solved) {
        case (true, false): return Reconciliation(winner: a, archivedLoser: nil)
        case (false, true): return Reconciliation(winner: b, archivedLoser: nil)
        case (true, true):
            let winner = laterSolved(a, b)
            return Reconciliation(winner: winner, archivedLoser: nil)
        case (false, false):
            break
        }
        // Rule 3: identical boards → metadata last-writer-wins.
        if userEntriesEqual(a.game, b.game) {
            return Reconciliation(winner: newer(a, b), archivedLoser: nil)
        }
        // Rule 4: one board is a conflict-free continuation of the other.
        if isContinuation(of: a.game, from: b.game) {   // a ⊇ b
            return Reconciliation(winner: a, archivedLoser: nil)
        }
        if isContinuation(of: b.game, from: a.game) {   // b ⊇ a
            return Reconciliation(winner: b, archivedLoser: nil)
        }
        // Rule 5: divergent — higher fill wins, loser archived under a new id.
        let (win, lose) = a.game.fillFraction == b.game.fillFraction
            ? (newer(a, b), older(a, b))
            : (a.game.fillFraction > b.game.fillFraction ? (a, b) : (b, a))
        var loser = lose
        loser.id = makeID()
        loser.status = .archived
        return Reconciliation(winner: win, archivedLoser: loser)
    }

    // MARK: - Board comparison (placed digits only; pencil is not progress)

    private static func userEntriesEqual(_ x: NineGame, _ y: NineGame) -> Bool {
        x.entries == y.entries
    }

    /// True when every user-placed digit in `source` also appears, identical,
    /// in `whole` — i.e. `whole` is a conflict-free superset of `source`.
    private static func isContinuation(of whole: NineGame, from source: NineGame) -> Bool {
        for cell in 0..<81 where !source.isGiven(cell) && source.entry(at: cell) != 0 {
            if whole.entry(at: cell) != source.entry(at: cell) { return false }
        }
        return true
    }

    private static func newer(_ a: LibraryEntry, _ b: LibraryEntry) -> LibraryEntry {
        a.updatedAt >= b.updatedAt ? a : b
    }
    private static func older(_ a: LibraryEntry, _ b: LibraryEntry) -> LibraryEntry {
        a.updatedAt >= b.updatedAt ? b : a
    }
    private static func laterSolved(_ a: LibraryEntry, _ b: LibraryEntry) -> LibraryEntry {
        let sa = a.solvedAt ?? a.updatedAt, sb = b.solvedAt ?? b.updatedAt
        if sa != sb { return sa > sb ? a : b }
        return newer(a, b)
    }
}
```

> **Note on `LibraryEntry.id`:** it is declared `public let id: UUID` (`BoardLibrary.swift:23`). To let `reconcile` re-id the archived loser, change it to `public var id: UUID`. Do this in Task 3, Step 3 (change `let id` → `var id` on `LibraryEntry`); it does not affect the synthesized Codable shape and no existing code mutates it.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LibrarySync`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Engine/LibrarySync.swift Sources/Engine/BoardLibrary.swift Tests/EngineTests/LibrarySyncTests.swift
git commit -m "Nine: per-entry cloud merge rules — LWW, solved-wins, divergence (PRD-8)"
```

---

### Task 4: Daily invariant + top-level apply into the library

**Files:**
- Modify: `Sources/Engine/LibrarySync.swift` (add `apply` + `applyDeletion`)
- Test: `Tests/EngineTests/LibrarySyncTests.swift`

**Interfaces:**
- Consumes: `BoardLibrary` (`entry(id:)`, `upsert`, `delete(id:)`, `adoptDaily`, `markSolved`, `dailyEntry(day:)`), `reconcile`.
- Produces:
  - `struct ApplyEffects: Equatable { public var reupload: [UUID]; public var cloudDeletes: [UUID] }` — ids whose local state changed and must be re-pushed, and ids whose cloud record should be deleted (daily dedup).
  - `static func apply(remote: SyncedEntry, into library: inout BoardLibrary, now: Date, makeID: () -> UUID) -> ApplyEffects`
  - `static func applyDeletion(id: UUID, into library: inout BoardLibrary)`

Behavior:
- **Non-daily remote:** if no local entry with that id → `upsert(remote.hydrated())`. If a local entry exists → `reconcile`; upsert the winner (same id), and if `archivedLoser` exists upsert it too and add its new id to `reupload`. If the winner's board differs from `remote`'s, add the winner id to `reupload`.
- **Daily(day D) remote:** collect the incoming plus every local `.daily(D)` entry (there may be a same-id one and/or a different-id one). Reduce them to a single winning `(game, status, solvedAt, updatedAt)` via `reconcile` pairwise (fold). Choose the **canonical id = min uuidString** among all daily(D) ids seen (deterministic across devices). Apply the winner through `adoptDaily(winningGame, day: D, now: winner.updatedAt)` — reusing the canonical id if that entry is the one `adoptDaily` lands on, else re-home — then if the winner is solved, `markSolved(canonicalID, at: solvedAt)`. Delete every other local daily(D) entry; add their ids to `cloudDeletes`. Add the canonical id to `reupload` when its board changed.

> **Design note for the implementer:** `adoptDaily` reuses the *first* daily(D) entry it finds and forces `.inProgress`. To keep the canonical id stable, before calling `adoptDaily` delete all non-canonical local daily(D) entries so only the canonical one remains for `adoptDaily` to reuse; if none remains, `adoptDaily` creates a fresh id — acceptable, and the next sync round converges. Re-solve via `markSolved` after `adoptDaily` when the winner was solved (adoptDaily clears `solvedAt`).

- [ ] **Step 1: Write the failing test**

Append to `LibrarySyncTests.swift`:

```swift
extension LibrarySyncTests {

    @Test func applyInsertsUnknownRemoteEntry() {
        var lib = BoardLibrary()
        let remote = SyncedEntry(entry(game: progressed(count: 3), updated: 10))
        _ = LibrarySync.apply(remote: remote, into: &lib, now: t(10), makeID: seqID)
        #expect(lib.entry(id: remote.id)?.game.entries == remote.game.entries)
    }

    @Test func applyDailyFromTwoDevicesConvergesToOneEntry() {
        var lib = BoardLibrary()
        let day = 19_500
        // Device A already has its own daily(day) entry (its own uuid).
        let localID = lib.adoptDaily(game: progressed(seed: 3, count: 4), day: day, now: t(5))
        // Device B's daily(day) arrives from the cloud under a DIFFERENT uuid,
        // further along.
        let remote = SyncedEntry(entry(
            id: UUID(), kind: .daily(day: day),
            game: progressed(seed: 3, count: 11), updated: 20
        ))
        let fx = LibrarySync.apply(remote: remote, into: &lib, now: t(20), makeID: seqID)
        // Exactly one daily entry for the day survives (the invariant).
        let dailies = lib.entries.filter { if case .daily(let d) = $0.kind { return d == day }; return false }
        #expect(dailies.count == 1)
        // It carries the further-along board.
        #expect(dailies.first?.game.fillFraction == remote.game.fillFraction)
        // The redundant remote id is scheduled for a cloud delete OR the local
        // id is — whichever is non-canonical. One of the two ids is deleted.
        #expect(fx.cloudDeletes.count == 1)
        #expect(fx.cloudDeletes.first == max(localID.uuidString, remote.id.uuidString).flatMap(UUID.init(uuidString:)))
    }

    @Test func applySolvedDailyMarksSolvedThroughAdoptDaily() {
        var lib = BoardLibrary()
        let day = 19_600
        let localID = lib.adoptDaily(game: progressed(count: 2), day: day, now: t(1))
        let remote = SyncedEntry(entry(
            id: localID, kind: .daily(day: day), game: solved(),
            status: .solved, updated: 30, solved: 30
        ))
        _ = LibrarySync.apply(remote: remote, into: &lib, now: t(30), makeID: seqID)
        #expect(lib.dailyEntry(day: day)?.status == .solved)
        #expect(lib.dailyEntry(day: day)?.solvedAt == t(30))
    }

    @Test func applyIsIdempotentOnRepeat() {
        var lib = BoardLibrary()
        let remote = SyncedEntry(entry(kind: .free(.steady), game: progressed(count: 6), updated: 10))
        _ = LibrarySync.apply(remote: remote, into: &lib, now: t(10), makeID: seqID)
        let snapshot = lib
        _ = LibrarySync.apply(remote: remote, into: &lib, now: t(11), makeID: seqID)
        #expect(lib == snapshot)   // second apply of the same record changes nothing
    }

    @Test func applyDeletionRemovesEntry() {
        var lib = BoardLibrary()
        let id = lib.create(kind: .free(.gentle), game: game(), now: t(0))
        LibrarySync.applyDeletion(id: id, into: &lib)
        #expect(lib.entry(id: id) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LibrarySync/apply`
Expected: FAIL — `type 'LibrarySync' has no member 'apply'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/Engine/LibrarySync.swift` (inside `enum LibrarySync`):

```swift
    /// What the caller must tell CloudKit after a local apply.
    public struct ApplyEffects: Equatable {
        /// Local ids whose board changed and should be pushed back up.
        public var reupload: [UUID]
        /// Cloud record ids to delete (daily dedup — redundant same-day rows).
        public var cloudDeletes: [UUID]
        public init(reupload: [UUID] = [], cloudDeletes: [UUID] = []) {
            self.reupload = reupload
            self.cloudDeletes = cloudDeletes
        }
    }

    /// Merge a remote entry into the local library honoring every rule.
    public static func apply(
        remote: SyncedEntry, into library: inout BoardLibrary,
        now: Date, makeID: () -> UUID
    ) -> ApplyEffects {
        if case .daily(let day) = remote.kind {
            return applyDaily(remote: remote, day: day, into: &library, makeID: makeID)
        }
        return applyRegular(remote: remote, into: &library, makeID: makeID)
    }

    /// Remove a board the cloud says was deleted.
    public static func applyDeletion(id: UUID, into library: inout BoardLibrary) {
        library.delete(id: id)
    }

    // MARK: - Regular (non-daily) entries, keyed by id

    private static func applyRegular(
        remote: SyncedEntry, into library: inout BoardLibrary, makeID: () -> UUID
    ) -> ApplyEffects {
        guard let local = library.entry(id: remote.id) else {
            library.upsert(remote.hydrated())
            return ApplyEffects()
        }
        let r = reconcile(local, remote.hydrated(), makeID: makeID)
        library.upsert(r.winner)
        var fx = ApplyEffects()
        if let loser = r.archivedLoser {
            library.upsert(loser)
            fx.reupload.append(loser.id)
        }
        // The winner differs from what the cloud holds → push it back.
        if r.winner.game.entries != remote.game.entries || r.winner.status != remote.status {
            fx.reupload.append(r.winner.id)
        }
        return fx
    }

    // MARK: - Dailies, keyed by day (one entry per day invariant)

    private static func applyDaily(
        remote: SyncedEntry, day: Int, into library: inout BoardLibrary, makeID: () -> UUID
    ) -> ApplyEffects {
        // Every daily(day) candidate: the locals plus the incoming remote.
        let locals = library.entries.filter {
            if case .daily(let d) = $0.kind { return d == day }; return false
        }
        var winner = remote.hydrated()
        var archived: [LibraryEntry] = []
        for local in locals {
            let r = reconcile(local, winner.reIded(local.id), makeID: makeID)
            // reconcile compares by shared id; align ids so the rules apply to
            // the boards, not the ids (dailies are keyed by day, not id).
            winner = r.winner
            if let loser = r.archivedLoser { archived.append(loser) }
        }
        // Canonical id: deterministic across devices (smallest uuid seen).
        let allIDs = (locals.map(\.id) + [remote.id]).map(\.uuidString)
        let canonical = UUID(uuidString: allIDs.min()!)!
        var fx = ApplyEffects()
        // Drop every local daily(day) so adoptDaily lands on a clean slate,
        // then re-home the winner onto the canonical id.
        for local in locals where local.id != canonical {
            library.delete(id: local.id)
            fx.cloudDeletes.append(local.id)
        }
        if remote.id != canonical { fx.cloudDeletes.append(remote.id) }
        winner.id = canonical
        // Route through adoptDaily (PRD-8 §2), re-solving if the winner is done.
        let id = library.adoptDaily(game: winner.game, day: day, now: winner.updatedAt)
        if winner.status == .solved {
            library.markSolved(id: id, at: winner.solvedAt ?? winner.updatedAt)
        }
        for loser in archived { library.upsert(loser); fx.reupload.append(loser.id) }
        if id != remote.id || winner.game.entries != remote.game.entries {
            fx.reupload.append(id)
        }
        // Idempotence: if nothing actually changed, drop no-op effects.
        return dedupEffects(fx)
    }

    private static func dedupEffects(_ fx: ApplyEffects) -> ApplyEffects {
        ApplyEffects(
            reupload: Array(Set(fx.reupload)),
            cloudDeletes: Array(Set(fx.cloudDeletes))
        )
    }
```

And add a tiny helper on `LibraryEntry` in `Sources/Engine/LibrarySync.swift` (bottom of file):

```swift
private extension LibraryEntry {
    /// A copy under a different id — used so daily reconciliation compares the
    /// boards (dailies are keyed by day) rather than short-circuiting on id.
    func reIded(_ newID: UUID) -> LibraryEntry {
        var copy = self
        copy.id = newID
        return copy
    }
}
```

> **Idempotence check:** the `applyIsIdempotentOnRepeat` test asserts a repeat apply leaves the library `==`. For a regular entry this holds because `reconcile` returns the identical winner and `upsert` is a replace. Verify the test passes; if a spurious re-home changes `updatedAt`, guard `applyRegular` to return early when `local` already equals `remote.hydrated()`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LibrarySync`
Expected: PASS (all apply + daily tests green).

- [ ] **Step 5: Run the full engine suite (no regressions)**

Run: `swift test`
Expected: PASS — the pre-existing 28 tests plus the new `LibrarySync` suite all green.

- [ ] **Step 6: Commit**

```bash
git add Sources/Engine/LibrarySync.swift Tests/EngineTests/LibrarySyncTests.swift
git commit -m "Nine: cloud apply + one-daily-per-day merge invariant (PRD-8)"
```

---

## Phase 2 — CloudStore (CloudKit; App target only)

> These tasks touch `CKSyncEngine`, which is unavailable under SwiftPM/Linux, so they are **not** unit-tested — they are verified by the two-simulator sync check in Phase 5. Gate each on a green `xcodebuild` for all three platforms. This is the schedule-risk spike (PRD-8 §7): time-box to two days; the fallback if `CKSyncEngine` fights back is daily-board-only sync over KVS (a few hundred bytes), keeping this PRD as fast-follow — but proceed with the full design first.

### Task 5: Persisted sync-state blob

**Files:**
- Create: `Sources/App/CloudSync/LibrarySyncState.swift`

**Interfaces:**
- Produces: `struct LibrarySyncState: Codable, Sendable` wrapping the `CKSyncEngine.State.Serialization` (persisted as its `Data` form), tolerant decode; a `CouchStored` under key `nine.cloudSyncState` owned by `LibraryCloudStore`.

- [ ] **Step 1: Create the state blob**

```swift
// LibrarySyncState.swift — the CKSyncEngine state we must persist between
// launches (PRD-8 §2: "a small persisted sync-state blob, CouchStored,
// tolerant decoding"). CKSyncEngine hands us an opaque State.Serialization on
// every .stateUpdate event; we store its encoded form and feed it back at
// construction so the engine resumes its change-token position instead of
// re-fetching the whole zone.
#if os(iOS) || os(macOS) || os(tvOS)
import Foundation
import CloudKit

struct LibrarySyncState: Codable, Sendable {
    /// The engine's opaque serialized state, or nil before the first sync.
    var serialization: Data?

    init(serialization: Data? = nil) { self.serialization = serialization }

    enum CodingKeys: String, CodingKey { case serialization }

    /// Tolerant: a missing/garbled blob just means "start fresh", never a throw.
    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        serialization = try? c?.decodeIfPresent(Data.self, forKey: .serialization) ?? nil
    }

    /// Decode into the CKSyncEngine type, tolerating shape drift.
    func engineState() -> CKSyncEngine.State.Serialization? {
        guard let serialization else { return nil }
        return try? JSONDecoder().decode(
            CKSyncEngine.State.Serialization.self, from: serialization
        )
    }

    /// Capture a new serialization from the engine.
    static func from(_ state: CKSyncEngine.State.Serialization) -> LibrarySyncState {
        LibrarySyncState(serialization: try? JSONEncoder().encode(state))
    }
}
#endif
```

- [ ] **Step 2: Verify it compiles (build gate deferred to Task 6)**

No standalone build here — this type is exercised by `LibraryCloudStore` in Task 6. Proceed.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/CloudSync/LibrarySyncState.swift
git commit -m "Nine: persisted CKSyncEngine state blob (PRD-8)"
```

---

### Task 6: `LibraryCloudStore` — CKSyncEngine owner

**Files:**
- Create: `Sources/App/CloudSync/LibraryCloudStore.swift`

**Interfaces:**
- Consumes: `SyncedEntry`, `LibraryEntry`, `LibrarySyncState`, CouchKit `CouchStored`.
- Produces (the narrow interface `AppModel` uses):
  - `@MainActor final class LibraryCloudStore`
  - `init?()` — returns nil when CloudKit is unavailable (no container / build without entitlement), so `AppModel` stays purely local.
  - `func start()` — begin syncing (idempotent).
  - `func push(_ entry: LibraryEntry)` — schedule a save of this entry's projection.
  - `func delete(_ id: UUID)` — schedule a record delete.
  - `func kick()` — request a fetch (called on foreground).
  - `var onRemoteEntry: (@MainActor (SyncedEntry) -> Void)?` — a remote save arrived.
  - `var onRemoteDeletion: (@MainActor (UUID) -> Void)?` — a remote delete arrived.
  - `var onAccountReset: (@MainActor () -> Void)?` — account changed; caller may re-push local state.

- [ ] **Step 1: Write the store**

```swift
// LibraryCloudStore.swift — the CloudKit boundary (PRD-8 §2). Owns one
// CKSyncEngine over the private database and a single custom zone
// `NineLibrary`; every LibraryEntry is one CKRecord (record name = entry uuid)
// carrying the SyncedEntry projection. No CKQuery polling — the engine's event
// stream drives fetch and send. This is the ONLY file in the app that imports
// CloudKit; the merge rules it applies live, tested, in the Engine.
#if os(iOS) || os(macOS) || os(tvOS)
import Foundation
import CloudKit
import OSLog

@MainActor
final class LibraryCloudStore {
    static let zoneName = "NineLibrary"
    static let recordType = "LibraryEntry"
    static let containerID = "iCloud.com.couchsuite.nine"

    var onRemoteEntry: (@MainActor (SyncedEntry) -> Void)?
    var onRemoteDeletion: (@MainActor (UUID) -> Void)?
    var onAccountReset: (@MainActor () -> Void)?

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private var engine: CKSyncEngine?
    private let log = Logger(subsystem: "com.couchsuite.nine", category: "cloud-sync")

    private let stateStore = CouchStored(
        wrappedValue: LibrarySyncState(), "nine.cloudSyncState"
    )
    /// Snapshots the caller can hand us so we can build records on demand.
    private var pendingProjections: [CKRecord.ID: SyncedEntry] = [:]

    init?() {
        // A build without the CloudKit entitlement (or a host with no iCloud
        // support) must degrade to local-only, never crash.
        self.container = CKContainer(identifier: Self.containerID)
        self.database = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    func start() {
        guard engine == nil else { return }
        let config = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateStore.wrappedValue.engineState(),
            delegate: self
        )
        engine = CKSyncEngine(config)
    }

    func push(_ entry: LibraryEntry) {
        let projection = SyncedEntry(entry)
        let recordID = CKRecord.ID(recordName: entry.id.uuidString, zoneID: zoneID)
        pendingProjections[recordID] = projection
        engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }

    func delete(_ id: UUID) {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        pendingProjections.removeValue(forKey: recordID)
        engine?.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
    }

    func kick() {
        Task { try? await engine?.fetchChanges() }
    }

    // MARK: - Record <-> projection

    private func record(for id: CKRecord.ID, projection: SyncedEntry, base: CKRecord?) -> CKRecord {
        let record = base ?? CKRecord(recordType: Self.recordType, recordID: id)
        // One blob field keeps the record robust against schema drift; a couple
        // of scalar fields stay queryable for debugging in the CloudKit console.
        record["payload"] = (try? JSONEncoder().encode(projection)) as CKRecordValue?
        record["updatedAt"] = projection.updatedAt as CKRecordValue
        record["status"] = projection.status.rawValue as CKRecordValue
        return record
    }

    private func projection(from record: CKRecord) -> SyncedEntry? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(SyncedEntry.self, from: data)
    }
}

extension LibraryCloudStore: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            stateStore.wrappedValue = .from(update.stateSerialization)
            try? stateStore.flushNow()

        case .accountChange(let change):
            // Signed out / switched account: reset and let the caller re-push.
            switch change.changeType {
            case .signOut, .switchAccounts:
                pendingProjections.removeAll()
                onAccountReset?()
            case .signIn:
                onAccountReset?()
            @unknown default:
                break
            }

        case .fetchedRecordZoneChanges(let changes):
            for mod in changes.modifications {
                if let projection = projection(from: mod.record) { onRemoteEntry?(projection) }
            }
            for del in changes.deletions {
                if let id = UUID(uuidString: del.recordID.recordName) { onRemoteDeletion?(id) }
            }

        case .sentRecordZoneChanges(let sent):
            // Clear projections we successfully sent; re-queue conflicts.
            for saved in sent.savedRecords {
                pendingProjections.removeValue(forKey: saved.recordID)
            }
            for failed in sent.failedRecordSaves {
                log.error("record save failed: \(failed.error, privacy: .public)")
            }

        case .willFetchChanges, .didFetchChanges, .willSendChanges, .didSendChanges,
             .fetchedDatabaseChanges, .sentDatabaseChanges:
            break

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            guard let projection = self.pendingProjections[recordID] else { return nil }
            return self.record(for: recordID, projection: projection, base: nil)
        }
    }
}
#endif
```

> **Zone creation:** `CKSyncEngine` auto-creates the custom zone on first send when you add a `.saveZone`/pending change; if the zone is missing on the first push, add `syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])` in `start()` before the first `push`. Verify against the CKSyncEngine sample flow during the spike; adjust if the API surface differs from this draft (this is the time-boxed risk area).

- [ ] **Step 2: Regenerate the project and build for all three platforms**

Run:
```bash
xcodegen generate
xcodebuild -project Nine.xcodeproj -scheme Nine \
  -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator build | tail -5
```
Expected: BUILD SUCCEEDED. (macOS/tvOS builds follow in Task 8 once integration compiles.)

If `CKSyncEngine` symbols are missing, confirm the deployment target (iOS 18 / tvOS 18 / macOS 15) and that `import CloudKit` resolves. Do **not** add the entitlement yet — that is Task 10 (gated).

- [ ] **Step 3: Commit**

```bash
git add Sources/App/CloudSync/LibraryCloudStore.swift
git commit -m "Nine: LibraryCloudStore — CKSyncEngine over one NineLibrary zone (PRD-8)"
```

---

## Phase 3 — AppModel integration

### Task 7: Own the store; push on every progress/solve/delete; apply remote changes

**Files:**
- Modify: `Sources/App/AppModel.swift`

**Interfaces:**
- Consumes: `LibraryCloudStore`, `LibrarySync.apply`, `LibrarySync.applyDeletion`.
- Produces: an `AppModel` that, when a store exists, mirrors every local library mutation up and merges every remote change down through the tested Engine rules.

- [ ] **Step 1: Add the store property and wire it up in `init`**

In `AppModel`, add near the other `@ObservationIgnored` stores:

```swift
    /// The CloudKit boundary (PRD-8). Nil when CloudKit is unavailable — the
    /// app is then exactly as local as it was before this shipped.
    @ObservationIgnored private var cloudStore: LibraryCloudStore?
```

At the end of `init()` (after the platform blocks), add:

```swift
        // Cloud library (PRD-8). Ambient or absent: no account → local-only,
        // no modal, no error surfaced. Callbacks apply remote changes through
        // the tested Engine merge rules on the main actor.
        if let store = LibraryCloudStore() {
            store.onRemoteEntry = { [weak self] synced in self?.applyRemoteEntry(synced) }
            store.onRemoteDeletion = { [weak self] id in self?.applyRemoteDeletion(id) }
            store.onAccountReset = { [weak self] in self?.repushEntireLibrary() }
            cloudStore = store
            store.start()
            // Seed the cloud from whatever this device already has (idempotent).
            repushEntireLibrary()
        }
```

- [ ] **Step 2: Push on local mutations**

Add a single helper and call it from every path that mutates `library`:

```swift
    /// Mirror one entry up to CloudKit (no-op without a store / account).
    private func pushToCloud(_ id: UUID) {
        guard let entry = library.entry(id: id) else { return }
        cloudStore?.push(entry)
    }

    private func repushEntireLibrary() {
        for entry in library.entries { cloudStore?.push(entry) }
    }
```

Call sites (add the marked lines):
- `persistProgress()` — after `library.upsert(entry)`:
  ```swift
          pushToCloud(id)
  ```
- `finishSolve()` — after `library.markSolved(id: id, at: now)`:
  ```swift
          if let id = currentEntryID { pushToCloud(id) }
  ```
- `discardSaved()` / `archiveEntry(id:)` — after the local `delete`/`archive`:
  ```swift
          // archive keeps the entry → push; discard removes it → delete.
          cloudStore?.push(library.entry(id: entryID) ?? ...)   // archive
          cloudStore?.delete(entryID)                            // discard/delete
  ```
  (Use `push` when the entry still exists after the mutation, `delete` when it is gone. For `archiveEntry` push the now-archived entry; for `discardSaved`/`deleteEntry` call `cloudStore?.delete(id)`.)
- `deleteEntry(id:)` — after `library.delete(id: id)`:
  ```swift
          cloudStore?.delete(id)
  ```
- `compose(...)`/`create`/`adoptDaily` land in `persistProgress()` already (composition calls `persistProgress()`), so no extra push there.

- [ ] **Step 3: Apply remote changes through the Engine rules**

Add:

```swift
    /// A remote board arrived: merge it in (Engine rules), persist, and
    /// refresh any surface showing it. Runs on the main actor.
    private func applyRemoteEntry(_ synced: SyncedEntry) {
        let fx = LibrarySync.apply(
            remote: synced, into: &library, now: Date(), makeID: { UUID() }
        )
        try? libraryStore.flushNow()
        // Push back anything the merge changed (archived losers, daily winner).
        for id in fx.reupload { pushToCloud(id) }
        for id in fx.cloudDeletes { cloudStore?.delete(id) }
        refreshOnScreenBoardAfterMerge(changedID: synced.id)
        #if os(iOS)
        WidgetBridge.publish(from: self)   // widgets must reflect remote moves
        #endif
    }

    private func applyRemoteDeletion(_ id: UUID) {
        LibrarySync.applyDeletion(id: id, into: &library)
        if currentEntryID == id { currentEntryID = nil }
        try? libraryStore.flushNow()
        #if os(iOS)
        WidgetBridge.publish(from: self)
        #endif
    }

    /// If the merged entry is the board on screen, swap it in calmly (no undo
    /// stack reset mid-move; keep the timer running). Mirrors the widget-ingest
    /// on-screen update.
    private func refreshOnScreenBoardAfterMerge(changedID: UUID) {
        guard screen == .game, solvedAt == nil, let id = currentEntryID,
              let entry = library.entry(id: id) else { return }
        // Only adopt if the merged board is further along than what's shown
        // (never yank progress out from under an active hand).
        if let shown = game, entry.game.fillFraction > shown.fillFraction {
            var g = entry.game
            g.timer.start(at: Date())
            game = g
        }
    }
```

- [ ] **Step 4: Foreground kick — add a `kick()` on scene activation**

`AppModel` gains a small hook the app scene calls (wired in Task 8):

```swift
    /// Ask CloudKit to fetch now (called when the app comes forward). Ambient:
    /// no store / no account → no-op.
    func syncOnForeground() { cloudStore?.kick() }
```

- [ ] **Step 5: Build for iOS (integration compiles)**

Run:
```bash
xcodegen generate
xcodebuild -project Nine.xcodeproj -scheme Nine \
  -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator build | tail -5
```
Expected: BUILD SUCCEEDED. Fix the archive/discard push/delete call sites until they compile cleanly (they are the fiddly ones — `push` when the entry survives, `delete` when it's gone).

- [ ] **Step 6: Commit**

```bash
git add Sources/App/AppModel.swift
git commit -m "Nine: AppModel drives the cloud library — push, apply, foreground kick (PRD-8)"
```

---

### Task 8: Cross-platform foreground hook

**Files:**
- Modify: `Sources/App/NineApp.swift`

**Interfaces:**
- Consumes: `AppModel.syncOnForeground()`.
- Produces: a `scenePhase` `.active` → `syncOnForeground()` call on all three platforms (iOS extends the existing hook; tvOS/macOS gain one).

- [ ] **Step 1: Extend the iOS hook**

In the existing `#if os(iOS)` `.onChange(of: scenePhase)` (NineApp.swift:107), add to the `.active` case:

```swift
            case .active:
                model.ingestSharedDailyBoard()
                model.syncOnForeground()
```

- [ ] **Step 2: Add a cross-platform hook for tvOS/macOS**

`RootView` currently declares `scenePhase` only under `#if os(iOS)` (NineApp.swift:56). Make it available everywhere and add the kick. Replace the iOS-only declaration with:

```swift
    @Environment(\.scenePhase) private var scenePhase
```

and add, on the `body`'s `ZStack` (outside the iOS-only block, so it compiles on all platforms):

```swift
        #if os(tvOS) || os(macOS)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.syncOnForeground() }
        }
        #endif
```

- [ ] **Step 3: Build all three platforms**

Run:
```bash
xcodegen generate
for dest in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  echo "== $dest ==";
  xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$dest" build 2>&1 | tail -3;
done
```
Expected: BUILD SUCCEEDED for all three. (Signing still uses the current profiles — the CloudKit entitlement is added next.)

- [ ] **Step 4: Commit**

```bash
git add Sources/App/NineApp.swift
git commit -m "Nine: sync on foreground across iOS, tvOS and macOS (PRD-8)"
```

---

## Phase 4 — Entitlements + project.yml (⚠️ merge gate)

> **Gate:** the CloudKit container `iCloud.com.couchsuite.nine` and the capability on the three app IDs already exist (portal work DONE, team `XC6FN96MA8`). The **match profile re-mint is handled separately** — do not run `match`. This branch must not merge until re-minted profiles land, or `beta_all` CI breaks (the PRD-3 lesson).

### Task 9: Add CloudKit to the iOS and macOS entitlements

**Files:**
- Modify: `Nine-iOS.entitlements`
- Modify: `Nine-macOS.entitlements`

- [ ] **Step 1: iOS entitlements**

Add inside the `<dict>` of `Nine-iOS.entitlements`:

```xml
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.com.couchsuite.nine</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>
```

- [ ] **Step 2: macOS entitlements**

Add the same two keys inside the `<dict>` of `Nine-macOS.entitlements`. (App Sandbox + `network.client` are already present, which CloudKit needs.)

- [ ] **Step 3: Commit**

```bash
git add Nine-iOS.entitlements Nine-macOS.entitlements
git commit -m "Nine: CloudKit container in iOS + macOS entitlements (PRD-8)"
```

---

### Task 10: New tvOS entitlements story

**Files:**
- Create: `Nine-tvOS.entitlements`
- Modify: `project.yml`

- [ ] **Step 1: Create `Nine-tvOS.entitlements`**

tvOS currently ships the generated `Nine.entitlements` (game-center + KVS). Give it a checked-in file that keeps those and adds CloudKit:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- tvOS entitlements (PRD-8 §5 step 4): the generated base (game-center +
	     KVS) plus the CloudKit container, applied for the tvOS SDKs via the
	     CODE_SIGN_ENTITLEMENTS override in project.yml. No app group (tvOS has
	     no widgets), no sandbox (macOS-only). -->
	<key>com.apple.developer.game-center</key>
	<true/>
	<key>com.apple.developer.ubiquity-kvstore-identifier</key>
	<string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.com.couchsuite.nine</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Point the tvOS SDKs at it in `project.yml`**

In the `Nine` target's `settings.base`, alongside the existing `CODE_SIGN_ENTITLEMENTS[sdk=...]` overrides (project.yml:63-65), add:

```yaml
        "CODE_SIGN_ENTITLEMENTS[sdk=appletvos*]": Nine-tvOS.entitlements
        "CODE_SIGN_ENTITLEMENTS[sdk=appletvsimulator*]": Nine-tvOS.entitlements
```

- [ ] **Step 3: Regenerate and build tvOS**

Run:
```bash
xcodegen generate
xcodebuild -project Nine.xcodeproj -scheme Nine \
  -destination 'generic/platform=tvOS Simulator' -sdk appletvsimulator build | tail -5
```
Expected: BUILD SUCCEEDED with the new entitlements applied.

- [ ] **Step 4: Commit**

```bash
git add Nine-tvOS.entitlements project.yml
git commit -m "Nine: tvOS entitlements story — CloudKit container override (PRD-8)"
```

---

## Phase 5 — Verification (PRD-8 §6 + PRD-7 §3 rule 3)

### Task 11: Full verification pass

- [ ] **Step 1: Engine suite green**

Run: `swift test`
Expected: PASS — the pre-existing suite plus the full `LibrarySync` suite (divergent progress, solved-vs-partial, same-day daily from two devices, idempotence, deletion).

- [ ] **Step 2: Three-platform build**

Run:
```bash
xcodegen generate
for dest in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  echo "== $dest =="; xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$dest" build 2>&1 | tail -3;
done
```
Expected: BUILD SUCCEEDED ×3.

- [ ] **Step 3: No-account local run (iPhone + tvOS + macOS)**

Boot each simulator **signed out of iCloud**, install, launch, play a few moves, background/foreground, relaunch. Expected: fully local, zero errors surfaced to the UI, boards persist exactly as before. Capture a `sim-use` screenshot of the iPhone Continue/Today card (the feature's visible surface) per PRD-7 §3 rule 3.

- [ ] **Step 4: Two-simulator sync (PRD-8 §6)**

Two iCloud-signed simulators (or devices) A and B on the same test Apple ID:
- Start a board on A → within ≤30 s of foregrounding B it appears on B.
- Solve on B → A marks it solved.
- Delete on A → the delete propagates to B.
- Same-day daily started on both → converges to one entry per day.
Capture screenshots of A and B showing the same board.

- [ ] **Step 5: Kill-mid-sync durability**

Place moves on A, force-quit A mid-sync, relaunch. Expected: no duplicate entries, no lost board (the persisted `nine.cloudSyncState` resumes the change-token position; the merge rules are idempotent).

- [ ] **Step 6: Finish the branch**

Use `superpowers:finishing-a-development-branch` to open a PR titled **`Nine: cloud library (PRD-8)`** against `main`. In the PR body, restate the merge gate: **do not merge until the re-minted iOS/tvOS/macOS match profiles land** (PRD-7 §5), or `beta_all` CI breaks on merge. Note that the CloudKit **schema must be deployed to Production before release** (dev schemas do not auto-promote).

---

## Self-Review

**Spec coverage (PRD-8):**
- §2 CKSyncEngine, private DB, one zone `NineLibrary` → Task 6. ✅
- §2 one CKRecord per entry, record name = uuid, payload excludes undo/moveLog → Tasks 1, 2, 6. ✅
- §2 `Sources/App/CloudSync/` boundary, persisted sync-state blob, narrow interface → Tasks 5, 6, 7. ✅
- §2 merge semantics (LWW, solved-beats-inProgress, same-day daily via adoptDaily, divergence→higher fill + archived loser) → Tasks 3, 4. ✅
- §2 account states (no account local, quiet re-sync, accountChanged reset) → Tasks 6, 7. ✅
- §2 KVS stays → untouched (no change to streak/history stores). ✅
- §3 experience (Continue/Today reflects remote within seconds; on-screen board updates calmly; tvOS shelf) → Tasks 7 (`refreshOnScreenBoardAfterMerge`), 8. ✅
- §5.1 SyncedEntry + tests (round-trip, merge, daily) TDD → Tasks 1–4. ✅
- §5.2 LibraryCloudStore + protocol seam → Task 6 (merge logic seam lives in tested Engine; CloudKit glue thin). ✅
- §5.3 AppModel integration (push on persistProgress/finishSolve/delete; WidgetBridge.publish after cloud merges) → Task 7. ✅
- §5.4 entitlements for iOS/macOS + new tvOS story + project.yml override + gate → Tasks 9, 10. ✅
- §5.5 no `-uxdemo` to delete → noted (Phase 5). ✅
- §6 verification checklist → Task 11. ✅

**PRD-7 gates:** §3 rule 3 (swift test + iPhone AND tvOS build + sim-use screenshot) → Task 11; rule 5 (engine TDD, tolerant decoding) → Phase 1 + Global Constraints; §5 ASC gate restated in Task 11 Step 6. ✅

**Placeholder scan:** two spots are honestly marked as spike-risk (CKSyncEngine zone-creation flow in Task 6; the archive/discard push-vs-delete call sites in Task 7 Step 2). Both name the exact ambiguity and the resolution path rather than hiding it — acceptable per the schedule-risk framing in PRD-8 §7.

**Type consistency:** `SyncedEntry` fields (id/kind/status/game/createdAt/updatedAt/solvedAt) match across Tasks 2, 4, 6. `LibraryEntry.id` changed `let`→`var` in Task 3 (needed by `reIded`/archived-loser). `ApplyEffects{reupload, cloudDeletes}` consistent Tasks 4, 7. `LibraryCloudStore` interface (`push/delete/kick/start/onRemoteEntry/onRemoteDeletion/onAccountReset`) consistent Tasks 6, 7.
