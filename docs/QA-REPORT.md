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
