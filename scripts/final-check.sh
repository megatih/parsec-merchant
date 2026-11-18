#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Final completion check (PRD §10). Prints one PASS/FAIL line per check,
# then "FINAL CHECK n/8 PASS" and "EXIT=<code>".
# Scratch folders live under build/final/ (gitignored) and are recreated on each run.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
REPO="megatih/parsec-merchant"
TAG="v1.0.0"
ASSET="Parsec-Merchant-1.0.0.zip"
APPNAME="Parsec Merchant"
LOGS="build/final/logs"
mkdir -p "$LOGS"
PASSN=0

check() {
  local n="$1" name="$2"; shift 2
  if "$@" > "$LOGS/$n.log" 2>&1; then
    echo "PASS $n $name"; PASSN=$((PASSN+1))
  else
    echo "FAIL $n $name (see $LOGS/$n.log)"
    tail -15 "$LOGS/$n.log" | sed 's/^/    /'
  fi
}

c1() { scripts/verify.sh --ui | tee /dev/stderr | tail -2 | /usr/bin/grep -q "ALL GATES PASSED"; }

c2() {
  local n
  # Count distinct milestones: checklist items such as "- [x] M0 exit: …" must not stand in for an unchecked milestone.
  n=$(/usr/bin/grep -oE '^- \[x\] M([0-9]|1[0-3]) ' PROGRESS.md | sort -u | wc -l | tr -d ' ')
  echo "milestones checked: $n/14"
  [ "$n" -eq 14 ] || return 1
  /usr/bin/python3 -I - <<'PY'
import re, sys
s = open("PROGRESS.md").read()
m = re.search(r"- \*\*Blockers:\*\*\s*(.*)", s)
b = m.group(1).strip().lower() if m else ""
print("blockers:", b or "(none)")
sys.exit(0 if b in ("", "none", "none.") else 1)
PY
}

c3() {
  gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name' | tee /dev/stderr | /usr/bin/grep -qx "$ASSET"
}

c4() {
  [ -f docs/QA-REPORT.md ] || return 1
  if /usr/bin/grep -nE '✗|TODO' docs/QA-REPORT.md; then return 1; fi
  local required=("AlertType (188)" "SpecialEventType (46)" "EncounterType (35)" "ShipType (17)"
    "Palm special events (37)" "UX-VISION §12" "full game per ruleset" "Economy bot" "Accessibility audit"
    "Text Size" "Pseudo-localization" "Light and dark" "Smallest window" "License check" "Credits visible"
    "Release smoke test" "Clean-clone build")
  local ok=0 r
  for r in "${required[@]}"; do
    if /usr/bin/grep -F "$r" docs/QA-REPORT.md | /usr/bin/grep -q '✓'; then echo "✓ $r"; else echo "missing or not ✓: $r"; ok=1; fi
  done
  return $ok
}

c5() {
  local dir="build/final/release"
  /bin/rm -rf build/final/release
  mkdir -p "$dir"
  gh release download "$TAG" --repo "$REPO" --pattern "$ASSET" --dir "$dir" || return 1
  ditto -x -k "$dir/$ASSET" "$dir/x" || return 1
  local app
  app="$(cd "$dir/x" && find "$PWD" -maxdepth 2 -name "$APPNAME.app" -type d | head -1)"
  [ -n "$app" ] || { echo "app not found in zip"; return 1; }
  pkill -x "$APPNAME" 2>/dev/null; sleep 1
  open -n "$app" --args -PMAudio off || return 1
  local i
  for i in $(seq 1 20); do pgrep -f "$app/Contents/MacOS" >/dev/null && break; sleep 1; done
  pgrep -lf "$app/Contents/MacOS" || { echo "not running"; return 1; }
  osascript -e 'tell application id "io.github.megatih.ParsecMerchant" to quit' 2>/dev/null || true
  sleep 2
  pkill -f "$app/Contents/MacOS" 2>/dev/null
  return 0
}

c6() {
  /bin/rm -rf build/final/clone
  mkdir -p build/final
  git clone --quiet "https://github.com/$REPO.git" build/final/clone/src || return 1
  [ ! -f build/final/clone/src/Config/Local.xcconfig ] || return 1
  (cd build/final/clone/src && xcodebuild -project SpaceTraderMac.xcodeproj -scheme SpaceTraderMac \
     -destination 'platform=macOS' -derivedDataPath ../DD build 2>&1 | tail -3) | tee /dev/stderr | /usr/bin/grep -q "BUILD SUCCEEDED"
}

c7() { swift run --package-path Packages/ParsecKit -c release pmsim bench --check; }

c8() {
  git fetch --quiet origin || return 1
  local st
  st="$(git status --porcelain)"
  [ -z "$st" ] || { echo "dirty:"; echo "$st"; return 1; }
  echo "HEAD=$(git rev-parse HEAD) origin/main=$(git rev-parse origin/main)"
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]
}

check 1 "verify --ui ALL GATES PASSED on HEAD" c1
check 2 "all milestones M0-M13 checked, no open blockers" c2
check 3 "gh release $TAG lists $ASSET" c3
check 4 "QA-REPORT complete, all ✓" c4
check 5 "downloaded release app launches (open -n, pgrep -f)" c5
check 6 "clean clone builds" c6
check 7 "pmsim bench within budgets" c7
check 8 "git clean and HEAD == origin/main" c8
echo "FINAL CHECK $PASSN/8 PASS"
if [ "$PASSN" -eq 8 ]; then echo "EXIT=0"; exit 0; else echo "EXIT=1"; exit 1; fi
