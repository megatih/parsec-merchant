#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Fails if any tracked file is byte-identical to an original Space Trader image/resource,
# or if bitmap/icon formats appear outside docs/reference/ (PRD §3), or if any tracked image is outside the
# allowlist of generated icon outputs (ART-066).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CS="/Users/megatih/Downloads/SpaceTraderSource201"
/usr/bin/python3 -I - "$CS" <<'PY'
import hashlib, os, subprocess, sys, pathlib
cs = pathlib.Path(sys.argv[1])
def h(p): return hashlib.sha256(p.read_bytes()).hexdigest()
originals = {}
srcs = []
if (cs / "images").is_dir(): srcs += [p for p in (cs / "images").rglob("*") if p.is_file()]
if (cs / "App.ico").is_file(): srcs.append(cs / "App.ico")
palm = pathlib.Path("docs/reference/palm-src")
if palm.is_dir(): srcs += [p for p in palm.rglob("*") if p.is_file() and "Rsc" in p.parts]
for p in srcs:
    if p.stat().st_size > 0:
        originals[h(p)] = str(p)
tracked = subprocess.run(["git", "ls-files", "-z"], capture_output=True, check=True).stdout.decode().split("\0")
bad = []
for f in filter(None, tracked):
    p = pathlib.Path(f)
    if not p.is_file():
        continue
    if p.suffix.lower() in (".bmp", ".gif", ".ico") and not f.startswith("docs/reference/"):
        bad.append(f"{f}: forbidden bitmap/icon format")
    elif p.stat().st_size > 0 and h(p) in originals:
        bad.append(f"{f}: identical to original asset {originals[h(p)]}")
# ART-066: no tracked raster or vector image outside the allowlist of generated outputs (all reproducible by make-icon.sh).
import fnmatch
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".tif", ".tiff", ".heic", ".webp", ".pdf", ".svg", ".icns")
ALLOWED = ["SpaceTraderMac/AppIcon.icon/Assets/*.png", "SpaceTraderMac/Assets.xcassets/AppIcon.appiconset/*.png"]
for f in filter(None, tracked):
    allowed = any(str(pathlib.PurePosixPath(f).parent) == str(pathlib.PurePosixPath(pat).parent)
                  and fnmatch.fnmatchcase(pathlib.PurePosixPath(f).name, pathlib.PurePosixPath(pat).name) for pat in ALLOWED)
    if pathlib.Path(f).suffix.lower() in IMAGE_EXT and not allowed:
        bad.append(f"{f}: image outside the generated-art allowlist (ART-066)")
print(f"license-check: {len(originals)} original assets hashed, {len([t for t in tracked if t])} tracked files scanned, {len(bad)} violations")
for b in bad: print("  -", b)
# SPDX header check for Swift sources
missing = [f for f in tracked if f.endswith(".swift") and "SPDX-License-Identifier: GPL-2.0-or-later" not in pathlib.Path(f).read_text(errors="ignore")[:400]]
for f in missing: print("  - missing SPDX header:", f)
sys.exit(1 if (bad or missing) else 0)
PY
