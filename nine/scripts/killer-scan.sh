#!/usr/bin/env bash
# killer-scan.sh — what a player would wait for if the Killer channel existed,
# measured in the configuration that ships.
#
#   nine/scripts/killer-scan.sh [seeds]       # default 200
#   nine/scripts/killer-scan.sh 200 --diag    # why a tier fails, not just that
#
# **Read this before quoting a compose number anywhere.** `swift test` builds
# Debug, and generation runs ~50× slower in Debug than in Release — measured on
# one machine, sharp seed 3004: 0.428 s release, 30.8 s debug. Every compose
# figure in DEVIATIONS.md before PRD-17 was a Debug figure, which is why Nocturne
# initially looked unshippable and is not. Release is the only configuration
# whose numbers mean anything to a player, so this script forces it — the sibling
# `compose-scan.sh` does the same for classic Nocturne.
#
# It reports the **success rate** alongside the timing, and that is the number
# that decides whether a tier ships. A tier that composes fast and fails on most
# seeds is not a fast tier; it is a tier with no supply. PRD-23's rule is that a
# variant tier ships only when catalog mining shows p95 compose inside budget —
# which presupposes there is anything to time.
set -euo pipefail

SEEDS="${1:-200}"
MODE="${2:-}"
NINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$NINE_DIR"

echo "==> killer, $SEEDS seeds per tier, Release configuration"
echo "    (machine: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m))"

if [[ "$MODE" == "--diag" ]]; then
  NINE_KILLER_DIAG="$SEEDS" swift test -c release --filter KillerSoak 2>&1 \
    | grep -E "killer diag|error:|failed" || true
  cat <<'NOTE'

Reading the diagnostic:
  • uniqueFromCagesAlone — how many zero-given boards the cages already
    determine. If this is high and chainClosedFromCagesAlone is low, the tier is
    blocked on *technique coverage*, not on cage design, and the fix is a
    solver PRD rather than a generator one.
  • cellsFilled p50 — how far the chain gets before it stalls. A p50 near 0 means
    the chain cannot even start; a p50 near 81 means it is close and one more
    technique might close it.
  • lastStepBeforeStall — which technique was the last useful one. Whatever
    appears most is what the next technique has to follow.
NOTE
  exit 0
fi

NINE_KILLER_SOAK="$SEEDS" swift test -c release --filter KillerSoak 2>&1 \
  | grep -E "killer (gentle|steady|sharp)|error:|failed|passed \(" || true

cat <<'NOTE'

Reading the number:
  • `composed` vs `failed` first, timing second. A tier with a non-trivial
    failure rate has no supply and does not ship, whatever its p95 says.
  • These are Mac (Apple silicon) Release timings. A phone's single-core
    throughput is roughly a third of an M-series Mac's on this workload, so
    multiply by ~3 for an iPhone estimate — and replace the estimate with a real
    device measurement before treating it as a budget. PROGRAM-2.0's nightly
    lane is where that belongs.
  • The p99 is the number to watch. It decides whether a caption on the card is
    honest or an apology.
NOTE
