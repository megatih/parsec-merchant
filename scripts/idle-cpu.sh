#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# ART-052 spot check: the idle CPU of a docked Bridge with the planet turning, in the Release build.
# Launches build/release/DD (scripts/release.sh builds it), starts a game with Return on the Welcome screen (Quick Start
# is its default button; with a saved game present this is the same Quick Start), waits for the Bridge, then reads the
# app's CPU time over 10 s twice. Needs Accessibility permission for the terminal (System Events sends the key).
# Prints "IDLE-CPU <percent>% (budget 5%)" for each sample and "IDLE-CPU PASSED" when both are within the budget.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="${1:-build/release/DD/Build/Products/Release/Parsec Merchant.app}"
[ -d "$APP" ] || { echo "IDLE-CPU FAILED: $APP is missing (run scripts/release.sh first)"; exit 1; }
pkill -x "Parsec Merchant" 2>/dev/null; sleep 1
open -n "$APP" || exit 1
sleep 6
osascript -e 'tell application "System Events" to tell process "Parsec Merchant" to set frontmost to true' \
  -e 'delay 0.5' -e 'tell application "System Events" to key code 36' || { echo "IDLE-CPU FAILED: could not start a game"; exit 1; }
sleep 8
pid="$(pgrep -x "Parsec Merchant" | head -1)"
[ -n "$pid" ] || { echo "IDLE-CPU FAILED: the app is not running"; exit 1; }
cpu() { ps -o time= -p "$pid" | awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }'; }
ok=0
for n in 1 2; do
  a="$(cpu)"; t0="$(date +%s)"; sleep 10; b="$(cpu)"; t1="$(date +%s)"
  pct="$(awk -v a="$a" -v b="$b" -v d=$((t1 - t0)) 'BEGIN { printf "%.2f", (b - a) / d * 100 }')"
  echo "IDLE-CPU ${pct}% (budget 5%)"
  awk -v p="$pct" 'BEGIN { exit !(p <= 5) }' || ok=1
done
pkill -x "Parsec Merchant"
if [ $ok -eq 0 ]; then echo "IDLE-CPU PASSED"; else echo "IDLE-CPU FAILED"; fi
exit $ok
