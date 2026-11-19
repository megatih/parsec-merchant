#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# PROT-001 (docs/PRD-UI-Revamp.md §1.4, §8.2): the planet graphics and the files they depend on are byte-identical
# to the commit the interface revamp started from. Prints "PROTECTED OK (22 files)" and exits 0, or the diff and 1.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
BASE=296ad2c6729fa626fd826b44f112ac2c959eb870
PA="Packages/ParsecKit/Sources/ParsecArt"
PATHS=(
  "$PA/Planets/PlanetArt.swift"
  "$PA/Planets/PlanetCache.swift"
  "$PA/Planets/PlanetClass.swift"
  "$PA/Planets/PlanetLayers.swift"
  "$PA/Planets/PlanetNoise.swift"
  "$PA/Planets/PlanetRecipe.swift"
  "$PA/Planets/PlanetSphere.swift"
  "$PA/Planets/PlanetTextureBaker.swift"
  "SpaceTraderMac/Art/PlanetMetalView.swift"
  "SpaceTraderMac/Art/PlanetPortrait.swift"
  "SpaceTraderMac/Art/PlanetSphereShader.swift"
  "SpaceTraderMac/Art/MapArt.swift"
  "$PA/Core/ArtRandom.swift"
  "$PA/Core/ArtPalette.swift"
  "$PA/Core/ArtGeometry.swift"
  "$PA/Core/ArtAccessibility.swift"
  "$PA/Space/SpaceArt.swift"
  "Packages/ParsecKit/Tests/ParsecArtTests/PlanetSpaceTests.swift"
  "Packages/ParsecKit/Tests/ParsecArtTests/PlanetSphereTests.swift"
  "SpaceTraderMacTests/PlanetLiveTests.swift"
  "Packages/ParsecKit/Sources/pmart/PlanetSheet.swift"
  "docs/adr/0004-live-planet-metal-layer.md"
)
git cat-file -e "$BASE^{commit}" 2>/dev/null || { echo "PROTECTED FAIL: base commit $BASE is not in this repository"; exit 1; }
MISSING=0
for p in "${PATHS[@]}"; do
  [ -f "$p" ] || { echo "PROTECTED FAIL: missing $p"; MISSING=1; }
done
[ "$MISSING" -eq 0 ] || exit 1
if ! git diff --exit-code --stat "$BASE" -- "${PATHS[@]}"; then
  echo "PROTECTED FAIL: the files above differ from $BASE"; exit 1
fi
ST="$(git status --porcelain -- "${PATHS[@]}")"
if [ -n "$ST" ]; then echo "$ST"; echo "PROTECTED FAIL: uncommitted changes to protected files"; exit 1; fi
echo "PROTECTED OK (${#PATHS[@]} files)"
