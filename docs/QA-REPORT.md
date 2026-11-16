# Parsec Merchant: QA Report

> Completed in M13 (PRD §10). Rows covering `[manual]` requirement IDs are added as each milestone delivers them.

| ID / Item | Evidence | Status |
|---|---|---|
| APP-003 product naming | `project.xcproj`: PRODUCT_NAME "Parsec Merchant", bundle ids per ADR-0001 | ✓ |

## Accepted assumptions

| ID | Assumption | Reason | Status |
|---|---|---|---|
| ECO-070 | Palm typed trade-in-orbit purchases are capped at the free bays like "All" | the source lets a typed amount overfill the hold; the engine keeps the hold-capacity invariant (ECO-076) that the fuzz gate checks for every ruleset | accepted (M5) |
| CRW-055 | Palm `DecreaseRandomSkill(n)` with no skill above n makes no change | the source re-draws forever (hang) | accepted (M5) |
| CRW-058 | Palm strange tonic below Hard with every skill at 10 ends with no change | the source loops forever (hang) | accepted (M5) |

