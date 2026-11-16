# Parsec Merchant: QA Report

> Completed in M13 (PRD §10). Rows covering `[manual]` requirement IDs are added as each milestone delivers them.

| ID / Item | Evidence | Status |
|---|---|---|
| APP-003 product naming | `project.xcproj`: PRODUCT_NAME "Parsec Merchant", bundle ids per ADR-0001 | ✓ |

## Accepted assumptions

| Item | Assumption and reasoning | Status |
|---|---|---|
| TRV-022 jump + Wild consent | Declining the Wild prompt after confirming a jump keeps the singularity (both sources lose it); a two-phase confirmation must not commit state. Deliberate deviation in every ruleset. | accepted (M5) |
| NEWS-039 Palm arrival flags | The engine adds the Palm System Information news flags once per arrival; Palm re-adds them each time the screen opens, which can only push a later flag past the 4-flag cap. | accepted (M5) |
| NEWS-046 Palm page limit metrics | The engine applies Palm's `DisplayHeadline` rule with app-supplied `HeadlineMetrics`; the font (Palm stdFont, 148 px line) and glyph widths are reproduced by the app with the Palm strings in M7. RNG output is independent of the page layout. | accepted (M5), app part M7 |
| NEWS-047 Palm Rsc texts | Rsc masthead and canned stories assumed equal to the C# arrays except "Sources say"; re-checked when the app's Palm strings are written (M7). | accepted (M5), check M7 |
| NEWS-036 Palm replaceNewsEvent | When the latest flag is not a captain-attacked flag or WILDARRESTED/CAUGHTLITTERING/EXPERIMENTPERFORMED (codes 90…92), Palm writes `latest + 10`, a special-event index with no headline mapping in the engine; the engine leaves the store unchanged in that case (only reachable when the 4-flag store was already full). | accepted (M5) |
| SCORE-022 Palm worth at hull ≤ 0 | The Palm killed score uses `CurrentShipPrice` as written for a destroyed hull; no Palm harness exists to confirm it. | accepted (M5) |
| GAL-009 Palm `sqrDistance`/`realDistance` use exact integers | The CodeWarrior 68K `int` width is not in the source; a 16-bit `int` would only matter for `sqrDistance > 32767` (opposite corners). Exact arithmetic is the intended rule. | accepted |
| GAL-012 Palm galaxy uses the New Game difficulty | The original built the galaxy before the New Commander form (stale `Difficulty`); the port uses the chosen difficulty. No rule changes. | accepted |
| GAL-027 Size 0 for not-yet-generated systems in Palm's starting quantities | The original read uninitialised memory there. | accepted |
| GAL-044 A failed Palm artifact delivery zeroes the Alien Artifact occurrence for that game only | The original wrote into a global table that could leak into later games in the same session. | accepted |
| RNG-026, RUL-019 Palm game RNG is a documented LCG stand-in | The ROM `SysRandom` algorithm is not in the game source; the Palm ruleset is rule-faithful, not sequence-faithful (PRD §4.2). | accepted |
| ECO-070 | Palm typed trade-in-orbit purchases are capped at the free bays like "All" — the source lets a typed amount overfill the hold; the engine keeps the hold-capacity invariant (ECO-076) that the fuzz gate checks for every ruleset | accepted (M5) |
| CRW-055 | Palm `DecreaseRandomSkill(n)` with no skill above n makes no change — the source re-draws forever (hang) | accepted (M5) |
| CRW-058 | Palm strange tonic below Hard with every skill at 10 ends with no change — the source loops forever (hang) | accepted (M5) |
| POL-074 Palm Yield-arrest fall-through | Palm's Yield handler calls `Arrested()` (which queues the system screen) and then falls through to `Travel()`, resuming the click loop at an already-reached destination. The interaction with the queued form cannot be confirmed from source alone; Parsec ends the trip after the arrest like every other Palm arrest (tested in CombatPoliceRulesetSpecTests). | accepted |
