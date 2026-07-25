#!/usr/bin/env bash
# downgrade-drill.sh — run PRD-17's downgrade drill against a real checkout of a
# previous release, rather than against a mirror type that claims to be one.
#
#   nine/scripts/downgrade-drill.sh [base-ref]        # default: origin/main
#
# What it does:
#   1. This tree writes the fixture blobs — a `nine.history` containing a
#      Nocturne solve, and a `nine.library` containing a Nocturne board.
#   2. `base-ref` is checked out into a throwaway git worktree.
#   3. `scripts/downgrade-drill/LegacyDrillTests.swift` is copied into that
#      worktree's test target and run there, so every type it touches is the
#      old release's code, compiled from the old release's source.
#
# It fails loudly if the old tree turns out to already know about Nocturne —
# that would mean the drill is comparing a build against itself and proving
# nothing. `PROGRAM-2.0.md` Phase 0 §3 asks for exactly this, scripted.
set -euo pipefail

BASE_REF="${1:-origin/main}"
NINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$NINE_DIR/.." && pwd)"
WORKTREE="$(mktemp -d)/previous"
FIXTURES="$(mktemp -d)/fixtures"

cleanup() {
  git -C "$REPO_DIR" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> writing fixtures from the current tree"
cd "$NINE_DIR"
NINE_WRITE_DOWNGRADE_FIXTURES="$FIXTURES" \
  swift test --filter DowngradeDrill >/dev/null
test -s "$FIXTURES/nine.history.json" || { echo "no history fixture written"; exit 1; }
test -s "$FIXTURES/nine.library.json" || { echo "no library fixture written"; exit 1; }
grep -q nocturne "$FIXTURES/nine.library.json" \
  || { echo "library fixture does not contain a Nocturne board"; exit 1; }

echo "==> checking out $BASE_REF ($(git -C "$REPO_DIR" rev-parse --short "$BASE_REF"))"
git -C "$REPO_DIR" worktree add --detach "$WORKTREE" "$BASE_REF" >/dev/null

# The drill is only meaningful against a build that lacks the case. If the base
# ref already has it, say so instead of printing a green run that means nothing.
if grep -qE 'case gentle, steady, sharp, nocturne' "$WORKTREE/nine/Sources/Engine/Generator.swift"; then
  echo "!! $BASE_REF already has Difficulty.nocturne — this proves nothing."
  echo "   Pass the last ref that predates PRD-17."
  exit 1
fi

echo "==> running the drill against the old engine"
cp "$NINE_DIR/scripts/downgrade-drill/LegacyDrillTests.swift" \
   "$WORKTREE/nine/Tests/EngineTests/LegacyDrillTests.swift"
cd "$WORKTREE/nine"
NINE_DOWNGRADE_FIXTURES="$FIXTURES" swift test --filter LegacyDrill

echo
echo "==> drill passed: $BASE_REF read a Nocturne history and library without losing either."
