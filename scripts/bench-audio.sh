#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# AUD-049: the release-build audio render budget. Renders 1 s at 48 kHz with 16 SFX voices and music in a Release
# (`-c release`) build of the ParsecAudio tests, prints the best of three timings and fails above 50 ms.
# Writes only under build/ and Packages/ParsecKit/.build.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build/logs
LOG="build/logs/bench-audio.log"
swift test -c release --package-path Packages/ParsecKit --filter AudioBudget > "$LOG" 2>&1
rc=$?
/usr/bin/grep -E "AUD-049 release" "$LOG"
if [ $rc -ne 0 ]; then
  /usr/bin/grep -E "error:|failed" "$LOG" | tail -10
  echo "BENCH-AUDIO FAILED (see $LOG)"
  exit 1
fi
if ! /usr/bin/grep -q "AUD-049 release" "$LOG"; then
  echo "BENCH-AUDIO FAILED: the release measurement did not run — see $LOG"
  exit 1
fi
echo "BENCH-AUDIO PASSED"
