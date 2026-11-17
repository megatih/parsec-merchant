#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Parsec Merchant quality gate (PRD §8.1).
#   scripts/verify.sh --quick   steps 1, 2 (no coverage), 6
#   scripts/verify.sh           steps 1-7 (7b: app icon check, from M11, ART-056)
#   scripts/verify.sh --ui      steps 1-8
# Writes only under build/ and Packages/ParsecKit/.build.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE="default"
case "${1:-}" in
  --quick) MODE="quick" ;;
  --ui) MODE="ui" ;;
  "") ;;
  *) echo "usage: $0 [--quick|--ui]"; exit 2 ;;
esac
PKG="Packages/ParsecKit"
LOGS="build/logs"
mkdir -p "$LOGS"
FAILED=0
MILESTONE="$(scripts/lib-milestone.sh)"
echo "verify.sh mode=$MODE milestone=M${MILESTONE:-?} head=$(git rev-parse --short HEAD 2>/dev/null)"

step() {
  local name="$1"; shift
  local start=$SECONDS
  if "$@" > "$LOGS/$name.log" 2>&1; then
    echo "PASS $name ($((SECONDS-start))s)"
  else
    echo "FAIL $name ($((SECONDS-start))s) — last lines of $LOGS/$name.log:"
    tail -25 "$LOGS/$name.log" | sed 's/^/    /'
    FAILED=1
  fi
}

package_tests_cov() {
  swift test --package-path "$PKG" --enable-code-coverage && scripts/coverage-gate.sh
}
app_build_test() {
  rm -rf build/results/app.xcresult
  xcodebuild -project SpaceTraderMac.xcodeproj -scheme SpaceTraderMac -destination 'platform=macOS' \
    -derivedDataPath build/DD -resultBundlePath build/results/app.xcresult \
    build test -skip-testing:SpaceTraderMacUITests SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
    > "$LOGS/xcodebuild-app.log" 2>&1
  local rc=$?
  tail -40 "$LOGS/xcodebuild-app.log"
  [ $rc -eq 0 ] || return $rc
  scripts/warnings-gate.sh "$LOGS/xcodebuild-app.log"
}
ui_tests() {
  rm -rf build/results/ui.xcresult
  xcodebuild -project SpaceTraderMac.xcodeproj -scheme SpaceTraderMac -destination 'platform=macOS' \
    -derivedDataPath build/DD -resultBundlePath build/results/ui.xcresult \
    test -only-testing:SpaceTraderMacUITests
}
fuzz() {
  swift run --package-path "$PKG" -c release pmsim fuzz --games 2000 --seed 1 --ruleset all
}

step 1-package-build swift build --package-path "$PKG"
if [ "$MODE" = "quick" ]; then
  step 2-package-tests swift test --package-path "$PKG"
else
  step 2-package-tests-coverage package_tests_cov
  step 3-fuzz fuzz
  step 4-app-build-test app_build_test
  step 5-spec-trace scripts/spec-trace.sh
fi
step 6-swiftlint swiftlint lint --strict --quiet
if [ "$MODE" != "quick" ]; then
  step 7-license-check scripts/license-check.sh
  if [ "${MILESTONE:-0}" -ge 11 ]; then
    step 7b-icon-check scripts/make-icon.sh --check
  fi
fi
if [ "$MODE" = "ui" ]; then
  step 8-ui-tests ui_tests
fi

if [ $FAILED -eq 0 ]; then
  echo "ALL GATES PASSED"; echo "EXIT=0"; exit 0
else
  echo "GATES FAILED"; echo "EXIT=1"; exit 1
fi
