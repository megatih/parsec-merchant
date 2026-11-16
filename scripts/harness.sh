#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Differential harness (PRD §8.4): builds a COPY of the C# 2.01 game logic with headless stubs and regenerates
# JSON fixtures in Packages/ParsecKit/Tests/ParsecEngineTests/Fixtures/harness/.
# The .NET SDK is installed locally into build/harness/dotnet with Microsoft's dotnet-install.sh (no sudo needed;
# the Homebrew cask is a .pkg that requires an admin password). Nothing here is shipped.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CS="/Users/megatih/Downloads/SpaceTraderSource201"
H="build/harness"
DOTNET="$H/dotnet/dotnet"
OUT="Packages/ParsecKit/Tests/ParsecEngineTests/Fixtures/harness"
CMD="${1:-all}"

if [ ! -x "$DOTNET" ]; then
  mkdir -p "$H/dl"
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$H/dl/dotnet-install.sh"
  bash "$H/dl/dotnet-install.sh" --channel LTS --install-dir "$ROOT/$H/dotnet" --no-path
fi

mkdir -p "$H/src"
FILES="Game.cs Ship.cs Commander.cs CrewMember.cs StarSystem.cs TradeItem.cs Equipment.cs Weapon.cs Shield.cs Gadget.cs
ShipSpec.cs ShipTemplate.cs Shipyard.cs SpecialEvent.cs PoliticalSystem.cs PoliceRecord.cs Reputation.cs HighScoreRecord.cs
GameOptions.cs Functions.cs Consts.cs Enums.cs Strings.cs STSerializableObject.cs GameEndException.cs FutureVersionException.cs"
for f in $FILES; do
  # Windows-1252 → UTF-8; drop the .NET-Framework-only assembly permission attribute.
  iconv -f cp1252 -t utf-8 "$CS/$f" | /usr/bin/sed -E '/RegistryPermissionAttribute|using System.Security.Permissions;/d' > "$H/src/$f"
done
cp harness/ParsecHarness.csproj harness/Stubs.cs harness/Driver.cs "$H/src/"

export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
"$DOTNET" build "$H/src/ParsecHarness.csproj" -c Release -o "$H/bin" -nologo -v quiet
mkdir -p "$OUT"
"$DOTNET" "$H/bin/ParsecHarness.dll" "$CMD" "$OUT"
