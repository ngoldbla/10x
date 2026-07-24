# PRD-14 — Daily archive (every day, on tap)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one PR
**One-liner:** A month grid of past dailies — solved days checked, today
glowing, every day tappable — powered entirely by `DailySeed`'s determinism.
Hundreds of hours of content, zero backend, zero downloads.

Prototype: `-uxdemo.archive` (`ArchiveDemo`). Production replaces it.

## 1. Why

`DailySeed.seed(for: date)` regenerates any day's puzzle from the calendar
alone (`Generator.swift:195`). The archive is therefore free content — and the
natural companion to PRD-9's heat grid: see a gap, tap it, fill it.

## 2. The experience

- Entry: an **Archive** affordance on/under the Today card (calendar glyph).
  Opens a GlassSheet month grid (the suite's one-secondary-surface rule: it
  *is* the secondary surface while open).
- Month grid: 7-column, checkmarks on solved days (from
  `library.dailyEntry(day:)` + solve records), accent fill on today, muted
  future days (not tappable), month pager back to a sane floor (launch month
  of the archive feature — no infinite scroll).
- Tap a past day → compose via `DailySeed.seed(for:)` at `.steady` (the
  daily's difficulty), play on the normal game screen with a small "Archive ·
  Jul 12" chip where the composing chip sits.
- **Streak integrity (the invariant):** past-day solves must never rewrite
  streak state. `recordCompletion` already guards `day > last` — the archive
  path additionally *skips* `recordCompletion` for any `day < todayOrdinal`
  (defense in depth; TDD). Points/history record normally with `isDaily: true`
  and `SolveRecord.date = now` (no schema change): the PRD-9 heat grid buckets
  by *solve* date, while the archive checkmark reads the *library entry* for
  that day — the two views agree by construction.
- Archive entries live in the library as `.daily(day:)` like any other, so
  they sync via PRD-8 and resume across devices for free.

## 3. Non-goals

- No archive on tvOS/macOS this PR (sheet is iOS; the library entries still
  appear in their trackers). No calendar-app integration, no per-day stats.

## 4. Implementation plan

1. `ArchiveSheet.swift` (month grid + pager) — reads library + history only.
2. `TouchUI.swift`: Today-card affordance + archive chip on the game screen;
   `AppModel.openArchiveDay(_:)` mirroring `openToday()` minus streak writes.
3. Engine: none beyond a test pinning the past-day streak invariant.
4. Delete `ArchiveDemo` + flag. Leave the PRD-9 heat-grid tap seam wired if
   PRD-9 is merged (one-line hookup), else leave documented.

## 5. Verification checklist

- [ ] Solve a past day in the sim: streak/`displayedStreak` unchanged (test +
      manual), history gains the record, archive shows the check.
- [ ] Same past day re-opened resumes its partial (library invariant holds).
- [ ] Today via archive == today via Today card (one entry, no dupes).
- [ ] Screenshots: month grid populated + mid-archive-game chip. tvOS green.
