# QST-JAREK: Ambassador Jarek and the haggling computer

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `{M4}` is C# 2.01 behaviour, kept in Modern, plus anything shared with Palm. `{M5}` is a Palm-only variant or a Modern-only fix that needs a ruleset flag.
>
> **Sources.** C# 2.01: `/Users/megatih/Downloads/SpaceTraderSource201` (`File.cs:line`). Palm 1.2.2: `docs/reference/palm-src/Src`. Re-read in the source on 2026-11-17. Research 01 §10 was the checklist (see §7).
>
> **Shared rules.** `specialEventAvailable`, `Command.specialEvent`, the two-phase consent and the `.noSpecialEvent` and `.insufficientFunds` rejections are defined in QST-INDEX. A handled event emits `GameEvent.specialEventCompleted(type)`.
>
> **Ownership.** GAL owns placement (GAL-033, GAL-037). CRW owns Jarek's skills, quarters and the trader bonus (CRW-018, CRW-024, CRW-038). ECO owns the buy-price formula (ECO-019, ECO-020). POL owns the arrest and pod sequences (POL-093…095, POL-104…105). TRV owns the `IncDays` order (TRV-070). NEWS owns headlines (NEWS-034).

## 1. Statuses, events and table rows

- **QST-JAREK-001** {M4} [M][W] `quests.jarek` takes the values of `QuestStatus.Jarek`: 0 `notStarted`, 1 `started` (Jarek aboard), 2…10 counting, 11 `impatient`, 12 `done` (delivered, haggling computer owned). A new game starts at 0. (source: SpecialEvent.cs:65-68)
- **QST-JAREK-002** {M4} [M][W][P] Events: `jarek` on one random system (occurrence 1, GAL-037) and `jarekGetsOut` at Devidia (22, fixed, GAL-033). Table rows (price, occurrence, message-only): `jarek` 0/1/no, so it needs `.acceptSpecialEvent` with amounts `[0]`; `jarekGetsOut` 0/0/yes. (source: Consts.cs:320-321; Palm: Src/Global.c:511, :523)
- **QST-JAREK-003** {M4} [M][W] "Jarek aboard" (`jarekOnBoard`) means crew member 33 is in the commander's crew array. It does not depend on the quest status. (source: Ship.cs:1139-1145)

## 2. When the button shows

- **QST-JAREK-004** {M4} [M][W][P] `jarek` needs police record ≥ −5 (Dubious). `jarekGetsOut` needs Jarek aboard. (source: StarSystem.cs:160-165, :220-222; Palm: Src/SystemInfoEvent.c:278-280, :296)
- **QST-JAREK-005** {M5} [P] Palm shows `jarekGetsOut` when `JarekStatus == 1` and hides the `jarek` start while more than 3 quests are open (RUL-141). (source: Palm: Src/SystemInfoEvent.c:296, :302-311)

## 3. Boarding

- **QST-JAREK-006** {M4} [M][W] `jarek` with consent: if the ship has no free crew quarter, the command is rejected with `.noFreeQuarters` (C# `SpecialNoQuarters`, ALR-154) and the offer stays. Otherwise Jarek (crew 33) is put into the first free crew slot, `jarek = 1`, and the event is removed. If his Trader skill raises the ship's effective Trader, buy prices are recalculated at once (C# `Ship.Hire`). (source: Game.cs:2364-2377, Ship.cs:608-622)
- **QST-JAREK-007** {M4} [M][W] While aboard, Jarek is a crew member (`passengersAsCrew`, RUL-057). He has skills 3/2/10/4 (CRW-024), adds to the ship's skills, has wage 0, takes a quarter and cannot be fired (`.cannotFireSpecialPassenger`, CRW-038). A ship trade needs quarters for him (`.passengersNeedQuarters`, SHP-036), and he moves to the new ship with the crew copy (SHP-044). (source: Game.cs:2136, Consts.cs:282-295, CrewMember.cs:249)
- **QST-JAREK-008** {M5} [P] Palm Jarek is a passenger: `JarekStatus = 1`, no crew slot or skills, and one fewer available quarter (CRW-036, CRW-044, CRW-045). Boarding is refused when `Crew[CrewQuarters-1]` is filled. (source: Palm: Src/SpecialEvent.c:238-247, Src/SystemInfoEvent.c:79-83)

## 4. Impatience (`IncDays`)

- **QST-JAREK-009** {M4} [M][W] Each `IncDays(n)` call while Jarek is aboard (TRV-070 step 8) does the following once, whatever `n` is. If `jarek == 5`, emit `passengerConcerned(crewID: 33)`. Else if `jarek == 10`, emit `passengerImpatient(crewID: 33)` and set Jarek's four skills (`mercenaries[33].skills`) to 0. Then, if `jarek < 11`, do `jarek += 1`. After boarding at status 1, the concern therefore comes on the 5th call and the impatience on the 10th, and the status then stays at 11. An arrest's `IncDays(term)` counts as one call. (source: Game.cs:2633-2648)
- **QST-JAREK-010** {M4} [M][W] Impatience never fails the quest: delivery works at any status 1…11. The zeroed skills are permanent, and no buy-price recalculation follows the drop. (source: Game.cs:2637-2644, :2378-2381)
- **QST-JAREK-011** {M5} [P] Palm has no impatience (`passengerImpatience`, RUL-061). (source: Palm: Src/Traveler.c:1705-1746)

## 5. Delivery and the haggling computer

- **QST-JAREK-012** {M4} [M][W] `jarekGetsOut` (message-only, at Devidia): `jarek = 12`, then Jarek is removed from the crew and later crew shift up one slot (C# `Ship.Fire`; no relocation for a special crew member), and the event is removed. Buy prices are recalculated only when the effective Trader computed after the status change with Jarek still aboard (bonus included) differs from the value after his removal. (source: Game.cs:2378-2381, Ship.cs:195-226)
- **QST-JAREK-013** {M4} [M][W] Haggling computer: from `jarek == 12` on, the commander's ship's effective Trader is the difficulty-adjusted best Trader + 1 (CRW-018, ECO-019). It feeds the buy price `price × (103 + 10 − Trader) / 100`. Example: best adjusted Trader 7 → 8, and a 1000 sell price buys at 1050 instead of 1060. (source: Ship.cs:1088-1094, :1315-1321, Game.cs:2974)
- **QST-JAREK-014** {M4} [M][W] The bonus is permanent. Status 12 is never reset (arrest and the pod test "aboard"), and the bonus is tied to the commander's ship, not to a hull, so it survives ship trades, the escape pod and a ship sold on arrest. (source: Ship.cs:1092, Game.cs:261-265, :2061-2065)
- **QST-JAREK-015** {M5} [P] Palm delivery sets `JarekStatus = 2` and always recalculates buy prices. The Palm +1 is added **before** the difficulty adjustment (`haggleBonusOrder`, RUL-051; ECO-020). (source: Palm: Src/SpecialEvent.c:278-281, Src/Skill.c:117-135)

## 6. Failure paths

- **QST-JAREK-016** {M4} [M][W] Arrest (POL-093 steps 7–8). If Jarek is still aboard after the mercenary step, `jarek = 0`; there is no separate engine event: the arrest report derives ALR-115 (`JarekTakenHome`) from `arrested` and the status change (POL-093/104 decision). Port quirk (POL-095): with fewer than two non-special crew he is **not** removed, and the arrest's `IncDays(term)` takes the status from 0 to 1. He then stays aboard, and `jarekGetsOut` at Devidia still completes the quest, unless the ship is sold for the fine. With two or more mercenaries he is cleared with them, the status stays where it was (the quest is stuck), and the report shows no Jarek notice. (source: Game.cs:254-265, :281-292, :306)
- **QST-JAREK-017** {M4} [M][W] Escape pod (POL-104 step 6): `jarek = 0` (the pod report derives ALR-115 from `escapePodUsed` and the state before the step). Then `IncDays(3)` takes the status to 1 while he is still in the old crew (POL-105), and `CreateFlea` removes him. The quest can no longer be finished: the `jarek` event is gone and `jarekGetsOut` needs him aboard. (source: Game.cs:2061-2065, :2097-2100)
- **QST-JAREK-018** {M5} [P] Palm arrest and pod set `JarekStatus` 1 → 0 (POL-098, POL-107). Passengers are not in the crew array, so he always leaves. (source: Palm: Src/Encounter.c:612-615, :719-722)

## 7. News and research notes

- **QST-JAREK-019** {M4} [M][W] Arriving at Devidia with Jarek aboard adds `jarekGetsOut` (NEWS-034). Palm: NEWS-038/041 {M5}. (source: Game.cs:2778-2781)
- **QST-JAREK-020** {M4} [M][W] Research 01 §10 says Jarek "becomes impatient at status 10". Precisely, the impatience notice and the zeroed skills happen in the `IncDays` call that **finds** status 10, and that call leaves status 11 (`impatient`). Impatience counts `IncDays` calls, not days. (source: Game.cs:2635-2647)

## 8. Scenarios

- **QST-JAREK-021** {M4} [M][W] Scenario (happy path): on Normal, in a Bumblebee (2 quarters) with no mercenaries, record 0, and a commander Trader skill of 5, accept `jarek`: he is in the crew, status 1, and the ship's Trader becomes 10, with buy prices recalculated. Make 10 normal warps: `passengerConcerned(crewID: 33)` on warp 5, `passengerImpatient(crewID: 33)` on warp 10, his skills become 0, and the status is 11. Dock at Devidia (news `jarekGetsOut`) and take `jarekGetsOut`: status 12, Jarek is gone, and the ship's Trader is the commander's adjusted 5 + 1 = 6. Buy a new ship: the Trader is still 6.
- **QST-JAREK-022** {M4} [M][W] Scenario (failures): (a) with no free quarter, the consented accept returns `.noFreeQuarters` with the state unchanged. (b) With record −6, the `jarek` start is hidden. (c) Arrested with Jarek and no other crew: `arrested` with the status reset (ALR-115 derived), then status 1 after the jail days, Jarek still aboard, and delivery at Devidia still gives status 12. (d) Arrested with Jarek and two mercenaries (this needs a Custom ship with at least 4 quarters, SHP-072): everyone leaves, the status is unchanged, and no `jarekGetsOut` button appears at Devidia. (e) Pod with Jarek aboard: `escapePodUsed`, final status 1, Jarek not in the Flea's crew.
