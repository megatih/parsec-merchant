#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# MAP-090: the Release map-render benchmark. Renders GalaxyMapRenderer at 1320x860 (zoom 1 and 4), prints the median
# and p90 frame times and fails when a median is 8 ms or more. Writes only under build/. The hardened runtime is off for
# this test build: its library validation rejects the locally signed test bundle (no team).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build/logs
LOG="build/logs/bench-map.log"
rm -rf build/results/bench-map.xcresult
xcodebuild -project SpaceTraderMac.xcodeproj -scheme SpaceTraderMac -destination 'platform=macOS' \
  -configuration Release -derivedDataPath build/DD-release -resultBundlePath build/results/bench-map.xcresult \
  ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO \
  test -only-testing:SpaceTraderMacTests/MapRenderBenchmarkTests > "$LOG" 2>&1
rc=$?
/usr/bin/grep -E "MAP-090 zoom|measured \[Clock" "$LOG" | sed 's/^.*MAP-090/MAP-090/'
if [ $rc -ne 0 ]; then
  /usr/bin/grep -E "error:|failed" "$LOG" | tail -10
  echo "BENCH-MAP FAILED (see $LOG)"
  exit 1
fi
if ! /usr/bin/grep -q "MAP-090 zoom" "$LOG"; then
  echo "BENCH-MAP FAILED: the benchmark did not run (skipped?) — see $LOG"
  exit 1
fi
echo "BENCH-MAP PASSED"
