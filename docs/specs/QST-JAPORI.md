# QST-JAPORI: Antidote for Japori

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `{M4}` is C# 2.01 behaviour, kept in Modern, plus anything shared with Palm. `{M5}` is a Palm-only variant or a Modern-only fix that needs a ruleset flag.
>
> **Sources.** C# 2.01: `/Users/megatih/Downloads/SpaceTraderSource201` (`File.cs:line`). Palm 1.2.2: `docs/reference/palm-src/Src`. Re-read in the source on 2026-11-17. Research 01 §10 was the checklist; its claims match the source.
>
> **Shared rules.** `specialEventAvailable`, `Command.specialEvent`, the two-phase consent and the `.noSpecialEvent` and `.insufficientFunds` rejections are defined in QST-INDEX. A handled event emits `GameEvent.specialEventCompleted(type)`.
>
> **Ownership.** GAL owns placement (GAL-033, GAL-037). SHP owns bay accounting (SHP-015). CRW owns `IncreaseRandomSkill` (CRW-063). POL owns the arrest and escape-pod sequences (POL-093, POL-104). NEWS owns headlines (NEWS-034).

## 1. Statuses, events and table rows

- **QST-JAPORI-001** {M4} [M][W][P] `quests.japori` takes the values of `QuestStatus.Japori`: 0 `notStarted`, 1 `inTransit` (the antidote is aboard), 2 `done`. A new game starts at 0. (source: SpecialEvent.cs:61-63; Palm: Src/Global.c:629)
- **QST-JAPORI-002** {M4} [M][W][P] Events: `japori` (the pickup) on one random system (occurrence 1, GAL-037) and `japoriDelivery` at Japori (41, fixed, GAL-033). Table rows (price, occurrence, message-only): `japori` 0/1/no, so it needs `.acceptSpecialEvent` with amounts `[0]`; `japoriDelivery` 0/0/yes. (source: Consts.cs:318-319; Palm: Src/Global.c:497, :508)

## 2. When the button shows

- **QST-JAPORI-003** {M4} [M][W][P] `japori` needs `japori == 0` and police record ≥ −5 (Dubious). `japoriDelivery` needs `japori == 1`. (source: StarSystem.cs:213-219; Palm: Src/SystemInfoEvent.c:278-280, :293-294)
- **QST-JAPORI-004** {M5} [P] Palm hides the `japori` pickup while more than 3 quests are open (RUL-141). (source: Palm: Src/SystemInfoEvent.c:302-311)

## 3. Handler effects

- **QST-JAPORI-005** {M4} [M][W] `japori` with consent: if free cargo bays < 10, the command is rejected with `.noEmptyBays` (C# `CargoNoEmptyBays`) and nothing changes. Otherwise `japori = 1`. In **both** cases C# keeps the pickup event on the system (`remove = false`), so the quest can start again after a failure (QST-JAPORI-009). It is hidden while the status is not 0. (source: Game.cs:2347-2358)
- **QST-JAPORI-006** {M4} [M][W][P] While `japori == 1`, the antidote fills 10 cargo bays (SHP-015): free bays drop by 10 and filled bays rise by 10. The antidote is not a trade item. It is not in `ship.cargo`, has no cost basis, cannot be sold, dumped or jettisoned, and pirates cannot take it. (source: Ship.cs:961-973; Palm: Src/Cargo.c:1025-1026)
- **QST-JAPORI-007** {M4} [M][W][P] `japoriDelivery` (message-only) sets `japori = 2`, calls `IncreaseRandomSkill` twice on the commander (CRW-063, RNG draws as CRW specifies), and removes the event. The 10 bays become free. If a skill change alters the effective Trader skill, buy prices are recalculated as CRW specifies. (source: Game.cs:2359-2363, CrewMember.cs:92-95; Palm: Src/SpecialEvent.c:184-188)
- **QST-JAPORI-008** {M5} [P] Palm removes the pickup once it has been accepted (`JAPORIDISEASE` is removed unless the bay check fails). New flag `japoriPickupPersists` (needs a RUL row): Modern and Windows true, Palm false. (source: Palm: Src/SpecialEvent.c:379-391, :394-395)

## 4. Failure paths

- **QST-JAPORI-009** {M4} [M][W] Escape pod with `japori == 1` (POL-104 step 4): `japori = 0`. There is no separate event (POL-093/104 decision): the app derives the "antidote destroyed" notice (ALR-003) by comparing the state before and after the `escapePodUsed` step, and its "return to" system is the first system, in index order, whose event is `japori`. Because the pickup was kept, it shows again at that system once the record is ≥ −5. (source: Game.cs:2047-2053)
- **QST-JAPORI-010** {M4} [M][W] Arrest with `japori == 1` (POL-093 step 10): `japori = 2`. There is no separate event: the app derives the "antidote taken" notice (ALR-004) by comparing the state before and after the `arrested` step. The Space Corps completes the delivery, but the commander gets **no** skill increase. The quest is over, and the pickup stays on its system but hidden. (source: Game.cs:273-277)
- **QST-JAPORI-011** {M5} [P] Palm arrest sets status 2 (POL-098). The Palm escape pod sets status 0 (POL-107), and with `japoriPickupPersists == false` the quest cannot be restarted. (source: Palm: Src/Encounter.c:600-603, :713-716)
- **QST-JAPORI-012** {M4} [M][W][P] The quest has no deadline: no `IncDays` rule reads `quests.japori`.

## 5. News

- **QST-JAPORI-013** {M4} [M][W] Arrival headlines (NEWS-034): the pickup system gives `japori` whenever `japori == 0`, including after a pod failure and whatever the record. Japori gives `japoriDelivery` at status 1. Palm: NEWS-038/041 {M5}. (source: Game.cs:2770-2777)

## 6. Scenarios

- **QST-JAPORI-014** {M4} [M][W] Scenario (happy path): with record 0 and 12 free bays, `.specialEvent` at the pickup returns the `.acceptSpecialEvent` confirmation. With consent, `japori == 1`, free bays are 2, and the pickup is still on the system but hidden. Warp to Japori and take `japoriDelivery`: `japori == 2`, two random skill increases (scripted RNG decides which), 12 free bays, and Japori has no event.
- **QST-JAPORI-015** {M4} [M][W] Scenario (failures): (a) with 9 free bays the consented accept returns `.noEmptyBays` with the state unchanged. (b) With record −6 the pickup is hidden. (c) With the antidote aboard, lose the ship with a pod: `japori == 0`, the first system holding `japori` is the pickup, and back at the pickup (record ≥ −5) the button shows again. (d) With the antidote aboard, get arrested: `japori == 2`, the commander's skills are unchanged, and no Japori button appears.
