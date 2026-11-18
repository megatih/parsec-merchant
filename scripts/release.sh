#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Release build (PRD §9 M13): Release configuration signed to run locally (ad-hoc, hardened runtime, the build's own
# sandbox entitlements, no --deep), strict codesign verification, the -PMScenario smoke test, a ditto zip in dist/ and
# its SHA-256. With --publish it also creates the GitHub release v$VERSION with the zip attached (needs `gh` auth).
#
#   scripts/release.sh             build, verify, smoke-test, zip
#   scripts/release.sh --publish   … and `gh release create`
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="1.0.0"
APPNAME="Parsec Merchant"
ZIP="Parsec-Merchant-$VERSION.zip"
REPO="megatih/parsec-merchant"
DD="build/release/DD"
DIST="dist"
PUBLISH=0
[ "${1:-}" = "--publish" ] && PUBLISH=1

echo "== Release build $VERSION"
/bin/rm -rf build/release "$DIST"
mkdir -p build/release "$DIST"
xcodebuild -project SpaceTraderMac.xcodeproj -scheme SpaceTraderMac -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DD" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=YES MARKETING_VERSION="$VERSION" CLANG_COVERAGE_MAPPING=NO \
  build > build/release/build.log 2>&1 || { tail -30 build/release/build.log; echo "RELEASE FAIL (build)"; exit 1; }
if /usr/bin/grep -E ': warning: ' build/release/build.log | /usr/bin/grep -v appintentsmetadataprocessor; then
  echo "RELEASE FAIL (warnings)"; exit 1
fi
APP="$DD/Build/Products/Release/$APPNAME.app"
[ -d "$APP" ] || { echo "RELEASE FAIL (no app at $APP)"; exit 1; }
# The scheme gathers coverage when testing; a release binary must carry no profiling counters.
if otool -l "$APP/Contents/MacOS/$APPNAME" | /usr/bin/grep -q "__llvm_prf"; then
  echo "RELEASE FAIL (the binary is instrumented for code coverage)"; exit 1
fi

echo "== Signature"
codesign --verify --strict --verbose=2 "$APP"
# Capture first: `grep -q` exits early, and under pipefail the SIGPIPE'd codesign would fail the check.
ENT="$(codesign -d --entitlements - "$APP" 2>&1)"
SIG="$(codesign -d --verbose=2 "$APP" 2>&1)"
/usr/bin/grep -q "com.apple.security.app-sandbox" <<< "$ENT" || { echo "RELEASE FAIL (sandbox entitlement missing)"; exit 1; }
/usr/bin/grep -qE "flags=.*runtime" <<< "$SIG" || { echo "RELEASE FAIL (hardened runtime missing)"; exit 1; }
/usr/bin/grep -q "Signature=adhoc" <<< "$SIG" || { echo "RELEASE FAIL (not ad-hoc signed)"; exit 1; }
echo "ad-hoc signed, hardened runtime, app sandbox"

echo "== Smoke test (-PMScenario smoke: new game, save and load in the sandbox, exit 0)"
pkill -x "$APPNAME" 2>/dev/null || true
if "$APP/Contents/MacOS/$APPNAME" -PMScenario smoke -PMAudio off > build/release/smoke.log 2>&1; then
  echo "smoke: exit 0"
else
  code=$?; cat build/release/smoke.log; echo "RELEASE FAIL (smoke exit $code)"; exit 1
fi

echo "== Zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$ZIP"
( cd "$DIST" && shasum -a 256 "$ZIP" | tee "$ZIP.sha256" )

if [ "$PUBLISH" -eq 1 ]; then
  echo "== GitHub release v$VERSION"
  NOTES="build/release/notes.md"
  /usr/bin/python3 -I - "$VERSION" > "$NOTES" <<'PY'
import re, sys
v = sys.argv[1]
s = open("CHANGELOG.md").read()
m = re.search(r"^## \[?" + re.escape(v) + r"\]?.*?$(.*?)(?=^## |\Z)", s, re.S | re.M)
print((m.group(1).strip() if m else "Parsec Merchant " + v) + "\n\nSHA-256: see the attached .sha256 file. "
      "The app is ad-hoc signed: on first launch use System Settings › Privacy & Security › Open Anyway (see README).")
PY
  if gh release view "v$VERSION" --repo "$REPO" > /dev/null 2>&1; then
    gh release upload "v$VERSION" "$DIST/$ZIP" "$DIST/$ZIP.sha256" --repo "$REPO" --clobber
  else
    gh release create "v$VERSION" "$DIST/$ZIP" "$DIST/$ZIP.sha256" --repo "$REPO" \
      --title "Parsec Merchant $VERSION" --notes-file "$NOTES" --target main
  fi
fi
echo "RELEASE PASS $DIST/$ZIP"
