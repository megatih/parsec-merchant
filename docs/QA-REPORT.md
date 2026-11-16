# Parsec Merchant: QA Report

> Completed in M13 (PRD §10). Rows covering `[manual]` requirement IDs are added as each milestone delivers them.

| ID / Item | Evidence | Status |
|---|---|---|
| APP-003 product naming | `project.xcproj`: PRODUCT_NAME "Parsec Merchant", bundle ids per ADR-0001 | ✓ |

## Accepted assumptions

| ID | Assumption | Reasoning | Status |
|---|---|---|---|
| GAL-009 | Palm `sqrDistance`/`realDistance` use exact integers | The CodeWarrior 68K `int` width is not in the source; a 16-bit `int` would only matter for `sqrDistance > 32767` (opposite corners). Exact arithmetic is the intended rule. | accepted |
| GAL-012 | Palm galaxy uses the New Game difficulty | The original built the galaxy before the New Commander form (stale `Difficulty`); the port uses the chosen difficulty. No rule changes. | accepted |
| GAL-027 | Size 0 for not-yet-generated systems in Palm's starting quantities | The original read uninitialised memory there. | accepted |
| GAL-044 | A failed Palm artifact delivery zeroes the Alien Artifact occurrence for that game only | The original wrote into a global table that could leak into later games in the same session. | accepted |
| RNG-026, RUL-019 | Palm game RNG is a documented LCG stand-in | The ROM `SysRandom` algorithm is not in the game source; the Palm ruleset is rule-faithful, not sequence-faithful (PRD §4.2). | accepted |
