# PRD-23 — Variant Engine: Killer (+ constraint architecture)

> Pillar B, "The Second Language". Long-lead engine work started during Wave 1
> per [PROGRAM-2.0.md](PROGRAM-2.0.md) §Sequencing; the product surface it feeds
> is **PRD-24 (Channels)**, in Wave 3. This PRD is written after the fact from
> the program-plan paragraph that specified it, and records what was built,
> what was measured, and what did not survive contact.

## 1. What shipped

Engine only, behind a channel with **no user-facing surface**. Nothing on any
screen changed; no entitlement, no persisted key, no new string.

| Piece | File |
|---|---|
| Wire form of a variant rule, tolerant end to end | `Sources/Engine/VariantConstraint.swift` |
| Rules compiled into the shape the solver's loops want | `Sources/Engine/ConstraintContext.swift` |
| Cage/thermometer reasoning as ordinary `Technique` cases | `Sources/Engine/VariantTechniques.swift` |
| Seeded polyomino cage tilings | `Sources/Engine/CageTiling.swift` |
| Constraint-checked uniqueness prover | `Sources/Engine/ConstraintBacktrackSolver.swift` |
| Killer supply | `Sources/Engine/VariantGenerator.swift` |
| The sealed door | `Sources/Engine/VariantChannel.swift` |

## 2. The contract, and how it was held

**Classic generation must not move.** Every daily is `(day → seed) → puzzle` and
every shared board is a seed, so a quiet change re-rolls every future daily and
breaks every shared seed. `Tests/EngineTests/GoldenCorpusTests.swift` freezes 56
hashes and it was run **after every commit**, not at the end:

| commit | golden |
|---|---|
| §1 constraint wire form + context | 56/56 |
| §2 solver reads geometry off the context | 56/56 |
| §3 variant techniques | 56/56 |
| §4 constraint-checked prover | 56/56 |
| §5 killer generation + channel | 56/56 |

Four mechanisms, not one:

- **`SudokuGrid` and `BacktrackSolver` are byte-identical to `origin/main`.** The
  prover got a *twin*, not a parameter, and classic delegates into the original
  through a single pointer compare.
- **Classic delegates rather than being rewritten.** `ConstraintContext.classic`
  is a shared singleton whose `peers`/`units`/`unitsOfCell` *are* the static
  `Sudoku` tables. Every loop that used to name them now reads them off the
  context — same arrays, same order.
- **`GeneratedPuzzle` gained no field.** It is inside the golden hash, so a
  `constraints: []` would have moved all 56 hashes for a value empty on every
  classic board. `VariantPuzzle` is a **sibling type** — the same shape as the
  `band` sibling key `nine.history` grew in PRD-17.
- **New `Technique` cases are appended.** `Difficulty.allowedTechniques` is
  `techniques(upTo: .xWing)`, which filters them out by rank; and a classic
  context has no cages, so they would find nothing anyway. Both are asserted.

`ConstraintDelegationTests` is the tripwire *below* the corpus: the corpus says
"generation moved", these say which link broke.

## 3. Compose time, measured

**Release, 100 seeds per tier, Apple silicon Mac** — `scripts/killer-scan.sh`.
Every figure below is a Release figure; `swift test` builds Debug and generation
runs ~50× slower there (PRD-17 measured 0.428 s vs 30.8 s on one seed), which is
more than the width of the ship/don't-ship decision.

| tier | composed | p50 | p90 | **p95** | p99 | max |
|---|---|---|---|---|---|---|
| gentle | 100/100 | 0.01 s | 0.02 s | **0.02 s** | 0.02 s | 0.02 s |
| steady | 100/100 | 0.02 s | 0.04 s | **0.05 s** | 0.08 s | 0.08 s |
| sharp  | 100/100 | 0.03 s | 0.11 s | **0.14 s** | 0.17 s | 0.17 s |

For scale, Nocturne — the band that shipped in PRD-17 — has a Mac Release p95 of
**5.25 s**. Killer's slowest tier is ~37× cheaper. On a phone (×3, an estimate
and labelled as one) Sharp's p95 is ~0.4 s, comfortably inside a compose the
player does not notice.

**All three tiers meet budget.** That is not the same as all three being ready to
ship — see §5.

### What the boards are made of

A timing table cannot tell you a tier is worth playing, so the soak also reports
the technique mix. Per 100 boards:

| tier | givens p50 (max) | cages | cage reasoning |
|---|---|---|---|
| gentle | 6 (10) | 27 | cageSingle 100/100 boards · cageCombination 100/100, 2257 steps · innieOutie 93/100 |
| steady | 4 (7) | 27 | cageSingle 100/100 · cageCombination 100/100, 2855 steps · innieOutie 85/100 |
| sharp | **0 (0)** | 32 | cageSingle 100/100 · cageCombination 100/100, 3628 steps · innieOutie 98/100 |

Sharp is the real killer aesthetic — zero givens, cages only — on every one of
100 seeds.

## 4. The measurement that changed the design

Sharp did not compose at first: 3,000 attempts, nothing. The obvious reading was
"our technique chain is too weak", which would have meant a solver PRD.

The diagnostic lane (`killer-scan.sh --diag`) exists to refuse that guess. It
separates two causes that want completely different fixes — *is the zero-given
board even uniquely determined by its cages*, and *if it is, can the chain close
it* — and the answer was neither of the expected ones:

| maxCageSize | cages alone determine the grid | our chain closes it |
|---|---|---|
| 2 | 15/40 | 15/40 |
| 3 | 5/40  | 2/40  |
| 4 | 1/40  | 0/40  |
| 5 | 0/40  | 0/40  |

With cages up to five cells the board is not unique **at all** — 0 of 200. No
technique could ever have closed it. Small cages carry far more information (a
two-cell cage summing to 17 admits exactly `{8,9}`), so `maxCageSize` became a
band parameter and Sharp took 3.

Two things in that table are worth keeping:

- At size 2 the columns are **equal** — whenever the cages determine the grid,
  our chain closes it. Technique coverage is not the binding constraint down
  there. It begins to bind at size 3 (5 unique, 2 closed).
- And size-2 boards close on naked singles (38 of 40 traces ended on one). Small
  cages buy uniqueness by spending difficulty. Size 3 is the compromise, not a
  free lunch.

## 5. Not done, and the honest caveats

- **The tier ladder is compressed.** Gentle sits at 6 givens and Steady at 4;
  they are separated mostly by technique set, not by clue count. Whether that
  reads as three tiers to a player is a PRD-24 question and it has not been
  answered by anything here.
- **No device measurement.** Every number is Mac Release; the ×3 phone figure is
  an estimate, exactly as PRD-17's was. PROGRAM-2.0's nightly lane is where the
  real one belongs.
- **No fast-seed catalog, no `PuzzleForge` pantry.** PROGRAM-2.0 §Pillar B
  specifies both as cost mitigations. At a 0.14 s p95 there is nothing to
  mitigate yet; they become interesting if the device number comes back badly or
  if a later variant is expensive.
- **Thermo is implemented but not generated.** `.thermometer` compiles to peer
  and bound tables and `thermoBound` is a working technique with fixtures and
  fuzz coverage, because an architecture that has only ever seen one constraint
  kind is not evidence of anything. Thermo *supply* is PRD-24's, which is where
  thermo ships first anyway.
- **No persistence, no `GameKind`, no library entry, no share format.** A
  `VariantPuzzle` has never been written to disk. When PRD-24 does that, the rule
  from `EXECUTING-A-PRD.md` §2 applies: a sibling top-level key or its own
  `CouchStored` blob, never a field on `LibraryEntry`.
- **Rule of 45 is single-unit only.** The chute forms (two and three rows at
  once) are standard in killer and are not implemented. The innie branch is in
  fact unreachable on a fully tiled board — every cell is caged — so only the
  outie form fires in practice; the innie code path is exercised by fixtures for
  the partially-caged boards a future variant might produce.
- **`cageCombination` does no bipartite matching.** A combination that passes
  both feasibility filters and is still unassignable survives, which costs an
  elimination and never causes a wrong one.

## 6. How to run it

```bash
cd nine
swift test --filter GoldenCorpus            # the contract, after every commit
swift test                                   # everything, Debug-affordable

scripts/killer-scan.sh 200                   # the p95 table, Release
scripts/killer-scan.sh 200 --diag            # why a tier fails, not just that
NINE_VARIANTS=1 …                            # the only way to open the channel
```
