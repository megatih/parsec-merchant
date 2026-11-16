# QST-WILD: Transporting Jonathan Wild

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `{M4}` is C# 2.01 behaviour, kept in Modern, plus anything shared with Palm. `{M5}` is a Palm-only variant or a Modern-only fix that needs a ruleset flag.
>
> **Sources.** C# 2.01: `/Users/megatih/Downloads/SpaceTraderSource201` (`File.cs:line`). Palm 1.2.2: `docs/reference/palm-src/Src`. Re-read in the source on 2026-11-17. Research 01 §10 was the checklist (see §8).
>
> **Shared rules.** `specialEventAvailable`, `Command.specialEvent`, the two-phase consent and the `.noSpecialEvent` and `.insufficientFunds` rejections are defined in QST-INDEX. A handled event emits `GameEvent.specialEventCompleted(type)`.
>
> **Ownership.** GAL owns placement (GAL-033, GAL-037). TRV owns the departure consent (TRV-014, TRV-015, TRV-017). CRW owns Wild's crew role and Zeethibal (CRW-024, CRW-046, CRW-065). ENC owns the police effects (ENC-022, ENC-062). POL owns the arrest, pod, pirate and inspection effects (POL-046, POL-051, POL-084, POL-089, POL-093…095, POL-104…105). NEWS owns headlines (NEWS-031, NEWS-034). This spec owns the statuses, the handler, impatience and the scenarios.

## 1. Statuses, events and table rows

- **QST-WILD-001** {M4} [M][W] `quests.wild` takes the values of `QuestStatus.Wild`: 0 `notStarted`, 1 `started`, 2…10 counting, 11 `impatient`, 12 `done` (delivered). A new game starts at 0. (source: SpecialEvent.cs:104-107)
- **QST-WILD-002** {M4} [M][W][P] Events: `wild` on one random system (occurrence 1, GAL-037) and `wildGetsOut` at Kravat (50, fixed, GAL-033). Table rows (price, occurrence, message-only): `wild` 0/1/no, so it needs `.acceptSpecialEvent` with amounts `[0]`; `wildGetsOut` 0/0/yes. (source: Consts.cs:336-337; Palm: Src/Global.c:516, :527)
- **QST-WILD-003** {M4} [M][W] "Wild aboard" (`wildOnBoard`) means crew member 32 is in the commander's crew array. It does **not** depend on the quest status. Every Wild rule in ENC, POL, SHP and this spec tests this, not the status. (source: Ship.cs:1343-1349)

## 2. When the button shows

- **QST-WILD-004** {M4} [M][W][P] `wild` needs police record < −5 (below Dubious). `wildGetsOut` needs Wild aboard. (source: StarSystem.cs:201-204, :279-281; Palm: Src/SystemInfoEvent.c:281, :297)
- **QST-WILD-005** {M5} [P] Palm shows `wildGetsOut` when `WildStatus == 1` and hides the `wild` start while more than 3 quests are open (RUL-141). (source: Palm: Src/SystemInfoEvent.c:297, :302-311)

## 3. Boarding

- **QST-WILD-006** {M4} [M][W][P] `wild` with consent checks, in this order, rejecting with the state unchanged and the offer kept: (1) no free crew quarter → `.noFreeQuarters` (ALR-154); (2) no weapon whose type is ≥ Beam laser (`has(.beamLaser, exact: false)`: Beam, Military, Morgan's, Photon or Quantum) → `.wildRequiresLaser` (ALR-185); (3) reactor aboard → `.wildRefusesReactor` (ALR-186). (source: Game.cs:2533-2548, Ship.cs:597-606, Enums.cs:871-879; Palm: Src/SpecialEvent.c:249-268)
- **QST-WILD-007** {M5} [M][P] `wildRequiresRealLaser` (RUL-111, MOD-011): in Modern and Palm only Beam, Military and Morgan's lasers qualify, for boarding (QST-WILD-006 check 2) and for staying (QST-WILD-012). Until the flag exists, every ruleset uses the Windows predicate (TRV-014). (source: PRD MOD-011)
- **QST-WILD-008** {M4} [M][W] When all checks pass, Wild (crew 32) goes into the first free crew slot (buy prices are recalculated if the ship's effective Trader changes, `Ship.Hire`), `wild = 1`, and the event is removed. With the sculpture aboard, the app shows the "Wild admires the sculpture" follow-up (ALR-184) from the state (`quests.sculpture == 1`); the engine emits no extra event. (source: Game.cs:2549-2558, Ship.cs:608-622)
- **QST-WILD-009** {M5} [P] Palm Wild is a passenger: `WildStatus = 1`, no crew slot or skills, and one fewer available quarter (RUL-057, CRW-044, CRW-045). (source: Palm: Src/SpecialEvent.c:269-271, Src/SystemInfoEvent.c:79-83)

## 4. While Wild is aboard

- **QST-WILD-010** {M4} [M][W] Wild is a crew member. He has skills 7/10/2/5 (CRW-024), adds to the ship's skills, has wage 0, takes a quarter, cannot be fired (CRW-038), needs quarters on a ship trade (SHP-036) and moves with the crew copy. He also makes police tries 5 (ENC-062), adds the Kravat police band (ENC-022), multiplies the arrest fine by 1.05 (POL-089), and is illegal special cargo (POL-051): submitting leads to arrest (POL-059), the bribe is multiplied (POL-066) and yielding leads to arrest (POL-071). (source: Game.cs:2136, Ship.cs:450, :1131-1137, Game.cs:206-207, :952-954)
- **QST-WILD-011** {M4} [M][W] Impatience: each `IncDays(n)` call while Wild is aboard (TRV-070 step 10) does the following once. If `wild == 5`, emit `passengerConcerned(crewID: 32)`. Else if `wild == 10`, emit `passengerImpatient(crewID: 32)` and set Wild's four skills (`mercenaries[32].skills`) to 0 permanently. Then, if `wild < 11`, do `wild += 1`. Impatience never fails the quest. Palm has none (RUL-061, QST-WILD-021). (source: Game.cs:2667-2682)

## 5. Wild "leaving" (port quirk)

- **QST-WILD-012** {M4} [M][W] Warp without a qualifying laser: the departure needs `.wildLeavesWithoutLaser` (TRV-014). With it, `wild = 0` and `wildLeftShip` is emitted. Port quirk (CRW-046): Wild is **not** removed from the crew. He keeps his skills, quarter and police effects, and the departure's `IncDays(1)` takes the status from 0 to 1. Because `wildGetsOut` tests "aboard", delivering him at Kravat still completes the quest. Kept in Modern (no MOD), so it needs a RUL keep/fix audit row. (source: Game.cs:3167-3177, :2667-2682)
- **QST-WILD-013** {M4} [M][W] Pirate raid with Wild aboard (POL-084): if the pirate ship has more than one crew quarter, `wild = 0` and `wildJoinedPirates` is emitted (ALR-182); otherwise `wildChattedWithPirates` (ALR-181). In both cases Wild stays in the crew (same quirk as QST-WILD-012). (source: Game.cs:1915-1926)
- **QST-WILD-014** {M4} [M][W] Accepting the reactor with Wild aboard needs `.wildLeavesForReactor`, then `wild = 0` and `wildLeftShip`, and Wild stays in the crew next to the reactor (QST-REACTOR-006). (source: Game.cs:2440-2447)
- **QST-WILD-015** {M5} [P] In Palm, leaving is real: `WildStatus = 0` removes the passenger (TRV-013, TRV-015, POL-085). (source: Palm: Src/Traveler.c:484-498, Src/Encounter.c:1949-1958, Src/SpecialEvent.c:101-112)

## 6. Arrest and the escape pod

- **QST-WILD-016** {M4} [M][W] Arrest with Wild aboard (POL-093 step 4, before the mercenary step): `wild = 0`, news `wildArrested` (NEWS-031), event `wildArrested` (ALR-180). The record becomes −5 by the arrest, with no extra −4 (POL-046). Port quirk (POL-095): Wild leaves the ship only if the mercenary step clears the crew or the ship is sold for the fine. Otherwise he stays aboard and the arrest's `IncDays(term)` takes the status to 1. (source: Game.cs:234-239, :254-259, :306)
- **QST-WILD-017** {M4} [M][W][P] Escape pod with Wild aboard (POL-104 step 8): `rec -= 4`, news and event `wildArrested`, `wild = 0`. Then `IncDays(3)` takes the status to 1 (POL-105) and `CreateFlea` removes him. The quest can no longer be finished. (source: Game.cs:2073-2079, :2097-2100; Palm: Src/Encounter.c:618-623)

## 7. Delivery at Kravat

- **QST-WILD-018** {M4} [M][W] `wildGetsOut` (message-only), in this order: (1) Zeethibal (crew 30) is placed at Kravat with skill 10 in the commander's lowest raw skill, 8 in the second lowest and 5 in the other two, with ties in the order Pilot, Fighter, Trader, Engineer (CRW-065); (2) `wild = 12`; (3) police record = 0 exactly, so a Hero (≥ 75) drops to 0 (RUL-037); (4) Wild is removed from the crew, and buy prices are recalculated if the effective Trader changes; (5) every sell price becomes `sell * 100 / 90` (integer, `RecalculateSellPrices`), and buy prices are not recalculated by this step; (6) the event is removed. (source: Game.cs:2560-2575, CrewMember.cs:103-121, Game.cs:2985-2989)
- **QST-WILD-019** {M5} [M] `sellPriceRecalcOnlyIfCriminal` (RUL-115, MOD-015): Modern applies step (5) only if the record before step (3) was < −5. (source: PRD MOD-015)
- **QST-WILD-020** {M5} [P] Palm delivery: `WildStatus = 2`, Zeethibal as CRW-065, record = `max(record, 0)` (RUL-037), and no sell-price recalculation (RUL-115). (source: Palm: Src/SpecialEvent.c:283-325)
- **QST-WILD-021** {M5} [P] Palm has no Wild impatience (`passengerImpatience`, RUL-061). The Kravat engineer boost reads the player's Wild (RUL-109). (source: Palm: Src/Traveler.c:1705-1746, :1168)

## 8. News and research notes

- **QST-WILD-022** {M4} [M][W] Arriving at Kravat with Wild aboard adds `wildGetsOut` (NEWS-034), even if his status was reset by a "leave". Palm: NEWS-038/041 {M5}. (source: Game.cs:2824-2827)
- **QST-WILD-023** {M4} [M][W] Research 01 §10 says Wild "leaves if you warp without such a weapon". In C# only his status resets (QST-WILD-012). He physically leaves only on delivery, a crew clear on arrest, a ship sold on arrest, or the escape pod. (source: Game.cs:3175-3176, :2572)

## 9. Scenarios

- **QST-WILD-024** {M4} [M][W] Scenario (happy path): with record −10, a Beam laser and a free quarter, accept `wild`: he is in the crew, status 1. Warp 5 times: `passengerConcerned(crewID: 32)` on warp 5. Dock at Kravat (news `wildGetsOut`) and take `wildGetsOut`: Zeethibal is at Kravat with 10/8/5 skills derived from the commander's skills, status 12, record 0, Wild is out of the crew, and every sell price is `old * 100 / 90`.
- **QST-WILD-025** {M4} [M][W] Scenario (boarding refusals): (a) record −5: hidden. (b) Pulse laser only: `.wildRequiresLaser`. (c) No free quarter: `.noFreeQuarters` (checked first, even without a laser). (d) Reactor aboard with a Beam laser: `.wildRefusesReactor`. In each case the state is unchanged. (e) In Windows, a Photon disruptor alone qualifies.
- **QST-WILD-026** {M4} [M][W] Scenario (leave quirk): with Wild aboard at status 7, sell the Beam laser, then `.warp`: it returns the `.wildLeavesWithoutLaser` confirmation. With the acknowledgement: `wildLeftShip`, Wild still in the crew, status 1 after departure. At Kravat `wildGetsOut` still shows and completes with status 12 and record 0.
- **QST-WILD-027** {M4} [M][W] Scenario (arrest and pod): (a) submit to police with Wild aboard and no mercenaries: arrested, `wildArrested`, news `wildArrested`, record −5 at the end of the arrest, then the status 0 → 1 from `IncDays(term)` with Wild still aboard. (b) Lose the ship with a pod while Wild is aboard: record lowered by 4, `wildArrested`, Flea without Wild, status 1.
