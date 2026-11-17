#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Generates the app icon from ParsecArt code (ART-054…056).
#   scripts/make-icon.sh           writes SpaceTraderMac/AppIcon.icon/{icon.json,Assets/*.png} and the full-bleed
#                                  PNGs + Contents.json of SpaceTraderMac/Assets.xcassets/AppIcon.appiconset
#   scripts/make-icon.sh --check   regenerates into build/, compares pixels with the committed files and runs actool;
#                                  prints "make-icon: OK" on success
# Idempotent: a second run produces byte-identical files. Touches nothing else.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE="write"
case "${1:-}" in
  --check) MODE="check" ;;
  "") ;;
  *) echo "usage: $0 [--check]"; exit 2 ;;
esac
PKG="Packages/ParsecKit"
APP="SpaceTraderMac"
mkdir -p build
TMP="$(mktemp -d "$ROOT/build/make-icon.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

swift build --package-path "$PKG" --product pmart > "$TMP/build.log" 2>&1 || { tail -20 "$TMP/build.log"; exit 1; }
PMART="$(swift build --package-path "$PKG" --show-bin-path)/pmart"

if [ "$MODE" = "write" ]; then
  "$PMART" icon --out "$TMP/out"
  mkdir -p "$APP/AppIcon.icon/Assets" "$APP/Assets.xcassets/AppIcon.appiconset"
  cp "$TMP/out/AppIcon.icon/icon.json" "$APP/AppIcon.icon/icon.json"
  cp "$TMP/out/AppIcon.icon/Assets/"*.png "$APP/AppIcon.icon/Assets/"
  cp "$TMP/out/Assets.xcassets/AppIcon.appiconset/"* "$APP/Assets.xcassets/AppIcon.appiconset/"
  echo "make-icon: wrote $APP/AppIcon.icon and $APP/Assets.xcassets/AppIcon.appiconset"
  exit 0
fi

# --check: pixels first (at most 0.1% of pixels may differ by more than 2 in a channel), JSON byte for byte.
if ! "$PMART" icon --out "$TMP/out" --check "$APP"; then
  echo "make-icon: committed icon files are stale (run scripts/make-icon.sh)"
  exit 1
fi

# actool: zero warnings, notices and errors; the partial Info.plist names the icon.
mkdir -p "$TMP/actool"
xcrun actool --compile "$TMP/actool" --platform macosx --minimum-deployment-target 27.0 --app-icon AppIcon \
  --output-partial-info-plist "$TMP/actool/p.plist" --warnings --notices --errors --output-format xml1 \
  "$APP/Assets.xcassets" "$APP/AppIcon.icon" > "$TMP/actool.plist" 2>"$TMP/actool.err" || {
    echo "make-icon: actool failed"; cat "$TMP/actool.err" "$TMP/actool.plist"; exit 1; }
if /usr/bin/grep -E 'com\.apple\.actool\.(document\.(warnings|notices|errors)|errors)' "$TMP/actool.plist" > /dev/null; then
  echo "make-icon: actool reported diagnostics:"
  cat "$TMP/actool.plist"
  exit 1
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$TMP/actool/p.plist" 2>/dev/null)" != "AppIcon" ]; then
  echo "make-icon: partial Info.plist lacks CFBundleIconName = AppIcon"
  cat "$TMP/actool/p.plist"
  exit 1
fi
echo "make-icon: OK"
