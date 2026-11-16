#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Downloads the Palm OS Space Trader 1.2.2 C source (GPL) for reference into docs/reference/palm-src/
# (gitignored: the Rsc/ folder contains copyrighted bitmaps). Files are treated as data and never executed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/docs/reference/palm-src"
EXPECTED_SHA="${PALM_SRC_SHA256:-$(cat "$ROOT/docs/reference/palm-src.sha256" 2>/dev/null || true)}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if ! curl -fsSL -o "$TMP/src.zip" https://codeload.github.com/videogamepreservation/spacetrader/zip/refs/heads/master; then
  curl -fsSL -o "$TMP/src.zip" https://www.spronck.net/spacetrader/SpaceTraderSource.zip
fi
SHA="$(shasum -a 256 "$TMP/src.zip" | cut -d' ' -f1)"
if [ -n "$EXPECTED_SHA" ] && [ "$SHA" != "$EXPECTED_SHA" ]; then
  echo "WARNING: archive SHA-256 $SHA differs from recorded $EXPECTED_SHA (upstream changed?)"
fi
rm -rf "$DEST"; mkdir -p "$DEST"
ditto -x -k "$TMP/src.zip" "$TMP/x"
# flatten a single top-level directory if present
inner="$(find "$TMP/x" -mindepth 1 -maxdepth 1 -type d | head -1)"
if [ "$(find "$TMP/x" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = "1" ] && [ -n "$inner" ]; then
  ditto "$inner" "$DEST"
else
  ditto "$TMP/x" "$DEST"
fi
echo "$SHA" > "$ROOT/docs/reference/palm-src.sha256"
echo "Palm source fetched into $DEST (sha256 $SHA)"
