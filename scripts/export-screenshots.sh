#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# A11Y-049: exports screenshots from UI-test attachments. Never called by verify.sh.
#   PM_EXPORT_SCREENSHOTS=1 scripts/export-screenshots.sh        runs ReadmeScreenshotUITests, copies readme-* to docs/screenshots/
#   PM_EXPORT_SCREENSHOTS=1 scripts/export-screenshots.sh --qa   copies qa-* from the last build/results/ui.xcresult to docs/screenshots/qa/
#   PM_EXPORT_SCREENSHOTS=1 scripts/export-screenshots.sh --manual  runs ManualQAUITests (M13 review evidence), copies qa-manual-*
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
  echo "usage: PM_EXPORT_SCREENSHOTS=1 $0 [--qa|--manual]" >&2
  echo "  default: run ReadmeScreenshotUITests and copy readme-*.png to docs/screenshots/" >&2
  echo "  --qa:    copy qa-*.png from build/results/ui.xcresult to docs/screenshots/qa/" >&2
  exit 2
}

[ "${PM_EXPORT_SCREENSHOTS:-}" = "1" ] || usage
MODE="readme"
case "${1:-}" in
  "") ;;
  --qa) MODE="qa" ;;
  --manual) MODE="manual" ;;
  *) usage ;;
esac

if [ "$MODE" = "readme" ]; then
  RESULT="build/results/screenshots.xcresult"
  PREFIX="readme-"
  DEST="docs/screenshots"
  EXPECTED="readme-welcome readme-bridge readme-personnel readme-galaxy readme-shipyard-designer readme-logbook-statistics
            readme-achievements readme-encounter readme-arrival readme-newspaper readme-gameover readme-bridge-dark"
  rm -rf "$RESULT"
  mkdir -p build/logs
  TEST_RUNNER_PM_EXPORT_SCREENSHOTS=1 xcodebuild -project SpaceTraderMac.xcodeproj -scheme SpaceTraderMac \
    -destination 'platform=macOS' -derivedDataPath build/DD -resultBundlePath "$RESULT" \
    test -only-testing:SpaceTraderMacUITests/ReadmeScreenshotUITests > build/logs/export-screenshots.log 2>&1 || {
      tail -40 build/logs/export-screenshots.log
      echo "export-screenshots: the screenshot test failed" >&2
      exit 1
    }
elif [ "$MODE" = "manual" ]; then
  RESULT="build/results/manualqa.xcresult"
  PREFIX="qa-manual-"
  DEST="docs/screenshots/qa"
  EXPECTED=""
  rm -rf "$RESULT"
  mkdir -p build/logs
  TEST_RUNNER_PM_EXPORT_SCREENSHOTS=1 xcodebuild -project SpaceTraderMac.xcodeproj -scheme SpaceTraderMac \
    -destination 'platform=macOS' -derivedDataPath build/DD -resultBundlePath "$RESULT" \
    test -only-testing:SpaceTraderMacUITests/ManualQAUITests > build/logs/export-manual.log 2>&1 || {
      tail -40 build/logs/export-manual.log
      echo "export-screenshots: the QA review test failed" >&2
      exit 1
    }
else
  RESULT="build/results/ui.xcresult"
  PREFIX="qa-"
  DEST="docs/screenshots/qa"
  EXPECTED=""
  [ -d "$RESULT" ] || { echo "export-screenshots: $RESULT is missing; run scripts/verify.sh --ui first" >&2; exit 1; }
fi

OUT="build/screenshots"
rm -rf "$OUT"
mkdir -p "$OUT" "$DEST"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT" > /dev/null

/usr/bin/python3 -I - "$OUT" "$DEST" "$PREFIX" $EXPECTED <<'PY'
import json, pathlib, shutil, sys
out, dest, prefix, expected = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4:]
manifest = json.loads((out / "manifest.json").read_text())
copied = {}
for test in manifest:
    for att in test.get("attachments", []):
        name = att.get("suggestedHumanReadableName") or att.get("exportedFileName", "")
        stem = name.rsplit(".", 1)[0]
        # xcresulttool suffixes names with "_<n>_<uuid>"; the attachment name is the part before it.
        for cut in ("_0_", "_1_", "_2_"):
            if cut in stem:
                stem = stem.split(cut, 1)[0]
        if not stem.startswith(prefix):
            continue
        src = out / att["exportedFileName"]
        target = dest / f"{stem}.png"
        shutil.copyfile(src, target)
        copied[stem] = target
for name in sorted(copied):
    print(copied[name])
missing = [e for e in expected if e not in copied]
if missing:
    print("export-screenshots: missing " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)
if not copied:
    print(f"export-screenshots: no {prefix}* attachments found", file=sys.stderr)
    sys.exit(1)
PY

# The QA review set is downscaled to 1320 px wide (1x of the 1100-pt window class) to keep the repository small;
# the README set keeps its 2x resolution.
if [ "$MODE" = "qa" ] || [ "$MODE" = "manual" ]; then
  for f in "$DEST"/qa-*.png; do sips -Z 1320 "$f" > /dev/null; done
fi
if [ "$MODE" = "manual" ]; then
  # Privacy: the system Window menu lists a Continuity item "Move to <the owner's device name>". Black out that row in
  # qa-manual-menu-*-window.png (the band 615–700 px from the top at 1320 px wide) before committing.
  echo "export-screenshots: mask the device-name row in $DEST/qa-manual-menu-*-window.png before committing" >&2
fi
