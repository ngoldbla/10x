# PRD-8 — Cloud library (your boards, everywhere)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one large PR (schedule risk lives here — start first)
**One-liner:** Every board — the daily, free-play partials, the played log —
syncs through CloudKit, so you start the daily on the iPad, place three digits
on the iPhone in line at the store, and finish it on the TV. This is the
sentence that sells the $4.99.

## 1. Why

The store pitch is "buy once, play everywhere, *pick up where you left off*."
Two-thirds of that is already true: Nine is one universal target, and the streak
+ solve history sync via iCloud KVS. The library itself is deliberately local —
`AppModel.swift:299` documents the reason (KVS is 1 MB total; a `LibraryEntry`
carries a full `NineGame` with undo stack and move log). CloudKit removes the
ceiling. Until this ships, the flagship claim is false; it cannot slip.

## 2. Architecture (decided)

- **CKSyncEngine** (iOS 18 / tvOS 18 / macOS 15 targets — fully available),
  private database, one custom zone `NineLibrary`. No CKQuery polling; the
  engine's event stream drives everything.
- **One `CKRecord` per `LibraryEntry`**, record name = entry UUID. Payload:
  puzzle, entries, pencil, timer state, `kind`, `status`, `createdAt`,
  `updatedAt`, `solvedAt` — **excluding `undoStack` and `moveLog`**, which are
  device-local UX state. That keeps records ~1–2 KB; the whole pruned library
  is a few dozen records.
- **New `Sources/App/CloudSync/`** module boundary: a `LibraryCloudStore`
  owning the sync engine, serialization, and a small persisted sync-state blob
  (`CouchStored`, tolerant decoding). `AppModel` talks to it through a narrow
  interface: push(entry), delete(id), and an async stream of merged entries.
  Engine sources stay UI- and CloudKit-free (suite audit).
- **Merge semantics, per record:** last-writer-wins by `updatedAt`, with two
  overrides — `solved` always beats `inProgress`, and for the *same day's
  daily*, merges flow through the existing `library.adoptDaily` path so the
  one-entry-per-day invariant holds. A cloud daily and the widget's app-group
  board reconcile through the same funnel as today (`ingestSharedDailyBoard`
  runs first; cloud ingestion follows; both are idempotent).
- **Conflict rule of thumb:** never lose progress silently. If both sides
  progressed the same board divergently, higher `fillFraction` wins; the loser
  is retained as an `archived` copy rather than destroyed.
- **Account states:** no iCloud account → purely local (today's behavior),
  quiet re-sync when an account appears; `accountChanged` events reset the
  engine cleanly. No modal nagging, ever — sync is ambient or absent.
- **KVS stays** for streak + history in this PR (PRD-9 depends on it; a later
  migration to CloudKit is out of scope).

## 3. The experience

- No new UI beyond one quiet signal: the home Continue/Today cards reflect
  remote progress within seconds of foreground (`scenePhase` hook already
  exists). A board updated remotely mid-view animates its fill ring calmly.
- First launch on a new device: library appears without any action.
- tvOS: same model, same engine — the shelf's Continue card is the surface.

## 4. Non-goals

- Prefs/theme sync (open question in PRD-7 §7). Watch app (PRD-6, unbuilt).
- Sharing/collaboration (CKShare). Public leaderboards (Game Center covers it).
- Migrating streak/history off KVS.

## 5. Implementation plan

1. **Engine-side:** a `SyncedEntry` codable projection of `LibraryEntry`
   (drops undo/move log) + tests: round-trip, merge rules, daily invariant.
   TDD — these rules are the feature.
2. `LibraryCloudStore` with CKSyncEngine wiring; unit-testable via a protocol
   seam over the engine's event/record types where practical.
3. `AppModel` integration: push on `persistProgress`/`finishSolve`/delete;
   apply merged entries on the existing main-actor paths; `WidgetBridge.publish`
   after cloud merges (widgets must reflect remote moves).
4. Entitlements: add the CloudKit container to `Nine-iOS.entitlements`,
   `Nine-macOS.entitlements`, and a **new tvOS entitlements story** — tvOS
   currently ships the generated default; `project.yml` gains a tvOS
   `CODE_SIGN_ENTITLEMENTS` override. ⚠️ Gate: PRD-7 §5 portal + match work
   **must land before this merges** or `beta_all` CI breaks (the PRD-3 lesson).
5. Verification pass (below), then delete `-uxdemo` nothing (no prototype
   existed for sync — nothing to remove).

## 6. Verification checklist

- [ ] `swift test`: merge-rule suite green (divergent progress, solved-vs-partial,
      same-day daily from two devices, widget+cloud+app triple write).
- [ ] iPhone + tvOS + macOS simulators build and run with **no iCloud account**
      (fully local, zero errors surfaced to UI).
- [ ] Two iCloud-signed simulators (or devices): board started on A appears on
      B ≤ 30 s after foreground; solve on B marks solved on A; delete propagates.
- [ ] Kill-app-mid-sync then relaunch: no duplicate entries, no lost board.
- [ ] CI `beta_all` green with re-minted profiles.

## 7. Risks & open questions

- **Schedule risk is here** — conflict handling and entitlement plumbing, not
  UI. Time-box the CKSyncEngine spike to two days; if it fights back, fall back
  to scoping v1 to daily-board-only sync over KVS (a few hundred bytes fits)
  and keep this PRD as fast-follow. The store pitch survives either way.
- CloudKit schema must be deployed to Production before release (PRD-7 §5).
- Should archived boards sync or only active ones? Default: sync everything the
  pruner keeps; revisit if record counts surprise us.
