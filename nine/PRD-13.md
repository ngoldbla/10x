# PRD-13 — Streak grace (your streak held)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one small PR
**One-liner:** Miss one day and Nine quietly bridges it — "You took yesterday
off; one rest day won't cost you" — with a small shield on the streak chip.
Kind, automatic, no currency, no counting. Churn insurance for the habit that
sells the app.

Prototype: `-uxdemo.shield` (`ShieldDemo`). Production replaces it.

## 1. Why

One missed day is where habit apps lose people forever: the broken flame reads
as a personal failure and the app gets deleted with it. A single-day automatic
grace removes that cliff without cheapening the streak (two missed days still
break it). The freemium "Shield currency" is dead (PRD-7 §1) — this is a
warmth feature, not a mechanic.

## 2. The rules (engine — this is the spec)

In `StreakState` (`Game.swift:225`):

- A completion on day *d* with `lastCompletedDay == d-2` (exactly one missed
  day) **extends** the streak instead of resetting: `current += 1`, and the
  bridge is recorded (`lastGraceDay = d-1`, new persisted field, tolerant
  decode).
- **Non-stacking (crisp rule):** a bridge is allowed only if at least one
  *natural* day-after-day completion has happened since the last bridge —
  formally, grace applies iff `lastGraceDay == nil || lastCompletedDay >
  lastGraceDay + 1`. Consequence: you cannot bridge two gaps back-to-back;
  two+ consecutive missed days always break. TDD the truth table: extend /
  bridge / bridge-then-natural-then-bridge (allowed) / bridge-then-bridge
  (breaks) / two-day gap (breaks).
- `displayedStreak(today:)` keeps a chain alive through one silent missed day:
  `last >= today - 2` shows the streak (today the cutoff is `today - 1`).
- `best` unchanged in meaning. All existing tests must stay green except those
  asserting the old cliff, which update to the new rule deliberately.

## 3. The experience

- Streak chip (home header + ambient slot) gains a small
  `shield.lefthalf.filled` glyph **only while a grace is active** (i.e. the
  streak currently stands because of a bridge).
- The morning after a bridged miss, the home shows one calm card (Today-card
  styling, dismissable, once per bridge): "Your streak held — you took
  yesterday off; one rest day won't cost you."
- No settings, no counters, no "shields remaining" anywhere.

## 4. Non-goals

- No multi-day protection, no earned/purchasable anything, no notifications
  ("your streak is in danger" pushes are the dark pattern we're refusing).

## 5. Implementation plan

1. Engine TDD first: the grace table (extend / bridge / non-stack / break),
   KVS-blob forward/backward decode fixtures (`lastGraceDay` tolerant).
2. UI: chip glyph + one-time card (dismissal flag via `CouchStored`).
3. Delete `ShieldDemo` + flag.

## 6. Verification checklist

- [ ] `swift test`: grace rules + decode fixtures green; updated cliff tests
      documented in the PR body.
- [ ] Sim: fake a bridge (temporary debug arg or injected date) → chip glyph +
      card screenshot; second launch shows no card.
- [ ] iCloud KVS round-trip: old-format streak blob decodes (no reset).
- [ ] tvOS + macOS builds green (shared model field).
