#!/usr/bin/env bash
# thermo-scan.sh — what a player waits for on the Thermo channel, measured in the
# configuration that ships.
#
#   nine/scripts/thermo-scan.sh [seeds]       # default 200
#   nine/scripts/thermo-scan.sh 200 --diag    # why a tier fails, not just that
#
# Sibling of `killer-scan.sh`, and the same warning applies with the same force:
# `swift test` builds Debug and generation runs ~50× slower there (measured,
# PRD-17: sharp seed 3004, 0.428 s release against 30.8 s debug). Every compose
# figure in DEVIATIONS.md before PRD-17 was a Debug figure, which is why Nocturne
# initially looked unshippable and is not. Release is the only configuration whose
# numbers mean anything to a player, so this script forces it.
#
# It reports the **success rate** alongside the timing, and that is the number
# that decides whether a tier ships. A tier that composes fast and fails on most
# seeds is not a fast tier; it is a tier with no supply.
#
# **The diagnostic lane is not killer's with the words changed.** Killer can fail
# two ways — not unique, or the chain cannot close it. Thermo can fail a third
# way that the ruleset makes *likely*: a thermo band's clue ceiling has to stay
# well above zero, because a tube layout covers the board partially by
# construction and cannot determine a grid on its own, so a board carrying a dozen
# givens may be one the classic chain closes unaided — the tubes are decoration
# and `minVariantSteps` rejects it. That failure looks nothing like the other two
# and wants the opposite fix (fewer givens or more coverage, NOT a wider chain —
# a wider chain makes it worse). So the lane counts the rejection reason directly
# instead of leaving it to be inferred.
set -euo pipefail

SEEDS="${1:-200}"
MODE="${2:-}"
NINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$NINE_DIR"

echo "==> thermo, $SEEDS seeds per tier, Release configuration"
echo "    (machine: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m))"

if [[ "$MODE" == "--diag" ]]; then
  NINE_THERMO_DIAG="$SEEDS" swift test -c release --filter ThermoSoak 2>&1 \
    | grep -E "thermo diag|error:|failed" || true
  cat <<'NOTE'

Reading the diagnostic — the counts are per *attempt*, not per seed, so they are
comparable with `VariantGenerator.attemptBudget` rather than hiding a 3,000-deep
retry:
  • digExhausted — the chain never closed inside the clue ceiling. The fix is a
    higher ceiling or a wider chain.
  • decoration — the board is well-formed and closes, but not enough of the
    trace was thermo reasoning. This is the thermo-specific cause. The fix is
    fewer givens or more tube coverage; widening the chain makes it WORSE.
  • notUnique / chainMissed — the proof stage disagreed with the dig. Rare, and
    a bug rather than a tuning problem if it is ever common.
  • variantStepsInClosedBoards — the distribution `minVariantSteps` cuts. If the
    threshold sits below p50, the anti-decoration rule cannot fire and the tier
    is defined by whatever the dig happened to do. That was true of the first
    draft of `thermoBand` and the shape report is what caught it.
NOTE
  exit 0
fi

NINE_THERMO_SOAK="$SEEDS" swift test -c release --filter ThermoSoak 2>&1 \
  | grep -E "thermo (gentle|steady|sharp)|error:|failed|passed \(" || true

cat <<'NOTE'

Reading the number:
  • `composed` vs `failed` first, timing second. A tier with a non-trivial
    failure rate has no supply and does not ship, whatever its p95 says.
  • Then read the *shape* line, and read it against the band. `givens max` below
    `maxGivens`, or `variantSteps p50` above `minVariantSteps`, means that knob
    can never reject and the tier is not actually bounded by it.
  • These are Mac (Apple silicon) Release timings. A phone's single-core
    throughput is roughly a third of an M-series Mac's on this workload, so
    multiply by ~3 for an iPhone estimate — and replace the estimate with a real
    device measurement before treating it as a budget. PROGRAM-2.0's nightly
    lane is where that belongs.
NOTE
