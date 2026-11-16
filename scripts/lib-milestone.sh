#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Prints the current milestone number (e.g. 3 for "M3") parsed from PROGRESS.md.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
/usr/bin/sed -nE 's/^- \*\*Current milestone:\*\* M([0-9]+).*/\1/p' "$ROOT/PROGRESS.md" | head -1
