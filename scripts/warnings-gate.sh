#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Counts compiler/linker warnings only (PRD §8.1). Tool noise (e.g. appintentsmetadataprocessor) is out of scope.
set -u
LOG="${1:?usage: warnings-gate.sh <xcodebuild-log>}"
W="$(/usr/bin/grep -E '^/.+:[0-9]+:[0-9]+: warning:|^ld: warning:' "$LOG" | sort -u)"
N=0; [ -n "$W" ] && N="$(printf '%s\n' "$W" | wc -l | tr -d ' ')"
echo "compiler/linker warnings: $N"
[ "$N" -eq 0 ] || { printf '%s\n' "$W"; exit 1; }
