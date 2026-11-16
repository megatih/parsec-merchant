# QST-ONEOFFS: Cargo for sale, Erase record, Skill increase, Lottery

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `{M4}` is C# 2.01 behaviour, kept in Modern, plus anything shared with Palm. `{M5}` is a Palm-only variant or a Modern-only fix that needs a ruleset flag.
> Sources: C# 2.01 at `/Users/megatih/Downloads/SpaceTraderSource201`, Palm 1.2.2 at `docs/reference/palm-src/Src`, re-read on 2026-11-17. Shared rules are QST-INDEX §3. Placement: CargoForSale, EraseRecord and Skill are placed randomly 3 times each (GAL-037); Lottery is put on the start system on Beginner and Easy only (GAL-060; Palm GAL-061). None of these events has a quest status.
> Trade-item indices: Water 0, Furs 1, Food 2, Ore 3, Games 4, Firearms 5, Medicine 6, Machines 7, Narcotics 8, Robots 9 (Enums.cs:842-855).

## 1. Cargo for sale (sealed canisters)

- **QST-ONEOFF-001** {M4} [M][W][P] `CargoForSale` is shown iff `freeCargoBays >= 3` (the antidote's and the reactor's bays count as filled, QST-002); it is a question with price 1000, and `cashToSpend < 1000` is rejected with `insufficientFunds`. (source: StarSystem.cs:169-171; Consts.cs:303; Palm: Src/SystemInfoEvent.c:277, Src/Global.c:507)
- **QST-ONEOFF-002** {M4} [M][W][P] Accepting draws `item = rand(10)` (any good, Firearms and Narcotics included), adds 3 units to `cargo[item]`, adds 1000 (the whole price, not per unit) to `priceCargo[item]`, charges 1000 and removes the event. Events: `[.sealedCanisters(item), .specialEventCompleted(.cargoForSale)]` (ALR-163). (source: Game.cs:2283-2288, :2577-2581; Palm: Src/SpecialEvent.c:328-333)
- **QST-ONEOFF-003** {M4} [M][W][P] The canisters are ordinary cargo from then on: they can be sold, dumped or jettisoned at their cost basis, and illegal ones are subject to inspections, fines and confiscation (POL-051, POL-056). Prices are not recalculated by the event. (source: Game.cs:2283-2288)

## 2. Erase record

- **QST-ONEOFF-004** {M4} [M][W][P] `EraseRecord` is shown iff `rec < −5`; it is a question with price 5000, and `cashToSpend < 5000` is rejected with `insufficientFunds`. (source: StarSystem.cs:201-204; Consts.cs:310; Palm: Src/SystemInfoEvent.c:276, Src/Global.c:503)
- **QST-ONEOFF-005** {M4} [M][W][P] Accepting sets `rec = 0`, multiplies every current sell price by 100/90 with integer truncation (`RecalculateSellPrices`, ECO-023; buy prices are not recalculated), charges 5000 and removes the event. The app shows ALR-150 from `specialEventCompleted(.eraseRecord)`. Afterwards the record drifts as usual (POL-010/011). (source: Game.cs:2312-2316, :2985-2989; Palm: Src/SpecialEvent.c:218-222)
- **QST-ONEOFF-006** {M5} [M] MOD-015 (`sellPriceRecalcOnlyIfCriminal`, RUL-115) applies the ×100/90 only when the record was below −5 before the event. Because `EraseRecord` is offered only when `rec < −5`, Modern's result is identical to Windows for this event; the flag is observable only at Wild's delivery (QST-WILD). (source: StarSystem.cs:201-204; PRD §4.3 MOD-015)

## 3. Skill increase

- **QST-ONEOFF-007** {M4} [M][W][P] `Skill` is always shown; it is a question with price 3000, and `cashToSpend < 3000` is rejected with `insufficientFunds`. (source: StarSystem.cs:196, :199; Consts.cs:331; Palm: Src/Global.c:501)
- **QST-ONEOFF-008** {M4} [M][W] Accepting calls the commander's `IncreaseRandomSkill` once (CRW-064, CRW-052: the eligible skills are those with `skill + 1 < 10`, one draw `rand(count)` picks among them), charges 3000 and removes the event. The step emits only `.specialEventCompleted(.skill)`: C# shows ALR-164 (`SpecialSkillIncrease`) before the increase whether or not a skill can rise (Game.cs:2515-2516), so the app shows it from that event and derives the raised skill, if any, by comparing the commander's skills before and after the step; if the effective Trader skill changed, buy prices are recalculated (QST-013). (source: Game.cs:2514-2517; CrewMember.cs:69-95)
- **QST-ONEOFF-009** {M4} [M][W] With every skill at 9 or more nothing can rise in Windows: no draw is made and no skill changes, but the 3000 is still charged and the event is still removed. (source: CrewMember.cs:69-79; Game.cs:2577-2581)
- **QST-ONEOFF-010** {M5} [M][P] Modern and Palm let the increase reach 10 (`skillIncreaseCap`, RUL-105, MOD-005); Palm picks with repeated `rand(4)` draws until a skill below 10 is found and does nothing when all four are 10 (CRW-054). (source: PRD §4.3 MOD-005; Palm: Src/Skill.c:170-205, Src/SpecialEvent.c:202-205)

## 4. Lottery

- **QST-ONEOFF-011** {M4} [M][W][P] `Lottery` is always shown and message-only, with price −1000: handling it adds 1000 to cash and removes the event, with no other effect. It remains claimable on any later visit to the start system until handled. (source: StarSystem.cs:192, :199; Game.cs:2382-2383, :2577-2581; Consts.cs:322; Palm: Src/Global.c:510, Src/SpecialEvent.c:89 (no case))

## 5. Scenarios

- **QST-ONEOFF-012** {M4} [M][W] Canisters: with 3 free bays and cash 1000, scripted `rand(10) = 5` → `cargo[Firearms] += 3`, `priceCargo[Firearms] += 1000`, cash 0, events `[.sealedCanisters(.firearms), .specialEventCompleted(.cargoForSale)]`; with only 2 free bays the event is not offered (`noSpecialEvent`). (source: Game.cs:2283-2288; StarSystem.cs:169-171)
- **QST-ONEOFF-013** {M4} [M][W] Erase record: `rec = −30`, a sell price of 100 → after acceptance `rec == 0`, that sell price is 111, buy prices unchanged, cash −5000; with `rec = −5` the event is not offered. (source: Game.cs:2312-2316, :2985-2989)
- **QST-ONEOFF-014** {M4} [M][W] Skill: skills 4/9/9/9 → the single eligible skill (Pilot) becomes 5 with one draw `rand(1)`; skills 9/9/9/9 → no draw, no change, cash −3000, event removed; `cashToSpend == 2999` → `insufficientFunds`. (source: CrewMember.cs:69-87)
- **QST-ONEOFF-015** {M4} [M][W] Lottery: a new Beginner game has `specialEventAvailable == .lottery` at the start system; `.specialEvent` with no acknowledgement adds 1000 and removes it; a new Normal game has no Lottery event. (source: Game.cs:129-132, :2382-2383)
