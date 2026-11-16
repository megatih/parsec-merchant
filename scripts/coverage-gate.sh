#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Scheduled line-coverage gate (PRD §8.1). Reads the milestone from PROGRESS.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
M="$(scripts/lib-milestone.sh)"
JSON="$(swift test --package-path Packages/ParsecKit --show-codecov-path)"
/usr/bin/python3 -I - "$JSON" "$M" <<'PY'
import json, sys
path, m = sys.argv[1], int(sys.argv[2])
data = json.load(open(path))["data"][0]["files"]
# module: list of (from_milestone, threshold)
schedule = {
    "ParsecEngine": [(2, 85.0), (3, 90.0)],
    "ParsecPersistence": [(6, 85.0)],
    "ParsecInsights": [(10, 85.0)],
}
ok = True
for mod, steps in schedule.items():
    total = covered = 0
    for f in data:
        if f"/Sources/{mod}/" in f["filename"]:
            total += f["summary"]["lines"]["count"]
            covered += f["summary"]["lines"]["covered"]
    pct = 100.0 * covered / total if total else 0.0
    req = None
    for frm, th in steps:
        if m >= frm:
            req = th
    status = "not enforced" if req is None else ("OK" if pct >= req else "BELOW")
    if req is not None and pct < req:
        ok = False
    print(f"coverage {mod}: {pct:.1f}% ({covered}/{total} lines) required={req if req is not None else '-'} [{status}]")
sys.exit(0 if ok else 1)
PY
