#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# PROT-002 (docs/PRD-UI-Revamp.md §1.4, §8.2): game logic is the released 1.1.0 logic.
#   1. The engine, insights, persistence and pmsim sources, their tests and the shared fixtures are byte-identical
#      to tag v1.1.0.
#   2. Behaviour fingerprints match the baseline measured at M18 before any other change: the fuzz command counts
#      and the SHA-256 of the initial galaxy of seed 1, per ruleset.
#   scripts/logic-frozen.sh                    full check (runs the fuzz)
#   scripts/logic-frozen.sh --fast             source diff only
#   scripts/logic-frozen.sh --fuzz-log FILE    reuse the output of a fuzz run (verify.sh step 3)
# Prints "LOGIC FROZEN OK" and exits 0, or the first difference and 1.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
TAG=v1.1.0
PKG="Packages/ParsecKit"
PATHS=(
  "$PKG/Sources/ParsecEngine" "$PKG/Sources/ParsecInsights" "$PKG/Sources/ParsecPersistence" "$PKG/Sources/pmsim"
  "$PKG/Tests/ParsecEngineTests" "$PKG/Tests/ParsecInsightsTests" "$PKG/Tests/ParsecPersistenceTests"
  "$PKG/Tests/ParsecScenarioTests" "$PKG/Tests/Fixtures"
)
# Baseline, measured on 296ad2c (M18, before any other change).
FUZZ_MODERN=4531100
FUZZ_WINDOWS201=4528609
FUZZ_PALM122=3134221
GALAXY_MODERN=ff4fb0e36ed8c92f51c01639ef1cd3f27f3e4388b1ac47ee48c5f12a82f0a4bf
GALAXY_WINDOWS201=c04d544a62ddc0a5620e34d2b29850294224f177d6646d699e8f615821f65230
GALAXY_PALM122=8f2dead9e697b685a7b58dda1960e95563ee30bddc8e5602d16e692d882c7a90

FAST=0; FUZZLOG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fast) FAST=1 ;;
    --fuzz-log) FUZZLOG="${2:-}"; shift ;;
    *) echo "usage: $0 [--fast] [--fuzz-log FILE]"; exit 2 ;;
  esac
  shift
done

git rev-parse -q --verify "$TAG^{commit}" >/dev/null || { echo "LOGIC FROZEN FAIL: tag $TAG is missing"; exit 1; }
if ! git diff --exit-code --stat "$TAG" -- "${PATHS[@]}"; then
  echo "LOGIC FROZEN FAIL: the paths above differ from $TAG"; exit 1
fi
ST="$(git status --porcelain -- "${PATHS[@]}")"
if [ -n "$ST" ]; then echo "$ST"; echo "LOGIC FROZEN FAIL: uncommitted changes to frozen paths"; exit 1; fi
if [ "$FAST" -eq 1 ]; then echo "LOGIC FROZEN OK (sources; fingerprints skipped with --fast)"; exit 0; fi

if [ -z "$FUZZLOG" ]; then
  FUZZLOG="build/logs/logic-frozen-fuzz.log"
  mkdir -p build/logs
  swift run --package-path "$PKG" -c release pmsim fuzz --games 2000 --seed 1 --ruleset all > "$FUZZLOG" 2>&1 \
    || { tail -5 "$FUZZLOG"; echo "LOGIC FROZEN FAIL: fuzz failed"; exit 1; }
fi
count() { /usr/bin/sed -nE "s/^fuzz $1: 2000 games, ([0-9]+) commands, 0 violations.*/\1/p" "$FUZZLOG" | head -1; }
check() {
  if [ "$2" != "$3" ]; then echo "LOGIC FROZEN FAIL: $1 is '$2', baseline '$3'"; exit 1; fi
  echo "ok $1 $2"
}
check "fuzz modern commands" "$(count modern)" "$FUZZ_MODERN"
check "fuzz windows201 commands" "$(count windows201)" "$FUZZ_WINDOWS201"
check "fuzz palm122 commands" "$(count palm122)" "$FUZZ_PALM122"
galaxy() { swift run --package-path "$PKG" -c release pmsim dump-galaxy --ruleset "$1" --seed 1 2>/dev/null | shasum -a 256 | cut -d' ' -f1; }
check "galaxy modern sha256" "$(galaxy modern)" "$GALAXY_MODERN"
check "galaxy windows201 sha256" "$(galaxy windows201)" "$GALAXY_WINDOWS201"
check "galaxy palm122 sha256" "$(galaxy palm122)" "$GALAXY_PALM122"
echo "LOGIC FROZEN OK"
