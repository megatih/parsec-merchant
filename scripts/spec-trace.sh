#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Spec traceability (PRD §7). IDs tagged {Mn} with n <= current milestone must be referenced by a test
# (or by docs/QA-REPORT.md for [manual] IDs). Tests may not reference unknown IDs. At M17 every ID must be traced.
# PM_TRACE_MILESTONE=<n> overrides the milestone read from PROGRESS.md, to preview IDs that are not yet due.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
M="${PM_TRACE_MILESTONE:-$(scripts/lib-milestone.sh)}"
/usr/bin/python3 -I - "$M" <<'PY'
import re, sys, pathlib
m = int(sys.argv[1])
idre = re.compile(r'\*\*([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*-[0-9]{3})\*\*')
ref_re = re.compile(r'\b([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*-[0-9]{3})\b')
specs = {}
for p in sorted(pathlib.Path("docs/specs").glob("*.md")):
    for line in p.read_text().splitlines():
        if not re.match(r'^\s*- \*\*', line):
            continue
        mm = idre.search(line)
        if not mm:
            continue
        rid = mm.group(1)
        ms = re.search(r'\{M(\d+)\}', line)
        specs[rid] = {"m": int(ms.group(1)) if ms else 99, "manual": "[manual]" in line, "file": p.name}
test_dirs = ["Packages/ParsecKit/Tests", "SpaceTraderMacTests", "SpaceTraderMacUITests"]
refs = set()
for d in test_dirs:
    for p in pathlib.Path(d).rglob("*.swift"):
        refs |= set(ref_re.findall(p.read_text()))
qa = pathlib.Path("docs/QA-REPORT.md")
qa_refs = set(ref_re.findall(qa.read_text())) if qa.exists() else set()
unknown = sorted(r for r in refs if r not in specs and not r.startswith(("SHA-", "UTF-", "ISO-")))
missing = []
for rid, info in specs.items():
    due = info["m"] <= m or m >= 17
    if not due:
        continue
    traced = (rid in qa_refs) if info["manual"] else (rid in refs)
    if not traced:
        missing.append(f"{rid} ({info['file']}, M{info['m']})")
deferred = sum(1 for i in specs.values() if i["m"] > m)
print(f"spec IDs: {len(specs)} total, {deferred} deferred to later milestones, {len(refs & specs.keys())} referenced by tests")
if unknown:
    print("tests reference unknown IDs:", ", ".join(unknown))
if missing:
    print(f"untraced IDs due by M{m}: {len(missing)}")
    for x in missing[:60]:
        print("  -", x)
sys.exit(1 if (unknown or missing) else 0)
PY
