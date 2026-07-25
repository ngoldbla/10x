#!/usr/bin/env bash
# compose-scan.sh — measure what a player actually waits for when they tap a
# difficulty card, in the configuration that ships.
#
#   nine/scripts/compose-scan.sh [seeds]      # default 200
#
# **Read this before quoting a compose number anywhere.** `swift test` builds
# Debug, and generation runs ~50× slower in Debug than in Release — measured on
# one machine, sharp seed 3004: 0.428 s release, 30.8 s debug. Every compose
# figure in DEVIATIONS.md before PRD-17 was a Debug figure, including the
# "0.7–65 s sharp" in the Phase 0 entry, which is why Nocturne initially looked
# unshippable and is not. Release is the only configuration whose numbers mean
# anything to a player, so this script forces it.
#
# It also reports the two properties the timing is *for*: a fast compose that
# quietly missed the band's demands is a regression, not an improvement. See the
# attemptBudget note in NocturneSoakTests for the bug that taught us that.
set -euo pipefail

SEEDS="${1:-200}"
NINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$NINE_DIR"

echo "==> composing $SEEDS Nocturne boards, Release configuration"
echo "    (machine: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m))"
NINE_SOAK="$SEEDS" swift test -c release --filter NocturneSoak 2>&1 \
  | grep -E "nocturne compose|error:|failed|passed \(" || true

cat <<'NOTE'

Reading the number:
  • These are Mac (Apple silicon) Release timings. A phone's single-core
    throughput is roughly a third of an M-series Mac's on this workload, so
    multiply by ~3 for an iPhone estimate — and replace the estimate with a real
    device measurement before treating it as a budget. PROGRAM-2.0's nightly
    lane is where that belongs.
  • PRD-17 §3 budgets "tens of seconds" for a Nocturne compose and pairs it with
    the caption on the card. The p99 is the number to watch: it is the one that
    decides whether the caption is honest or an apology.
NOTE
