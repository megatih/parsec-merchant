# TRV: Travel & arrival

> **Skeleton.** This file is completed at the start of **M3** (PRD §7). Requirement bullets use the format `- **TRV-001** {M3} [M][W][P] statement (source)`.
> Inputs: docs/research/01 and 04 (with errata), docs/design/UX-VISION.md, docs/reference/csharp-index.md.

## Planned contents
- Warp preconditions and their check order (C# Game.cs:3153; Palm Traveler.c:DoWarp)
- Departure costs: mercenaries, insurance, wormhole tax, interest; fuel use; IncDays
- Wormholes and the singularity jump (what is skipped; errata 04 #4)
- Transit state machine: 20 clicks (C#) or 21 (Palm), per-click repairs (Palm halves them), fabric rip
- Arrival pipeline order per ruleset: reactor, tribbles, debt, repairs, auto fuel/repair, pressures/quantities, Og egg, prices, news
- IncDays effects per ruleset (record decay, no-claim, monster regen, quest counters)
- Tracking and auto-untracking on arrival

## Requirements
_To be written at the start of M3._
