# QST-DRAGONFLY: The stolen Dragonfly

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `{M4}` is C# 2.01 behaviour, kept in Modern, plus anything shared with Palm. `{M5}` is a Palm-only variant or a Modern-only fix that needs a ruleset flag.
>
> **Sources.** C# 2.01: `/Users/megatih/Downloads/SpaceTraderSource201` (`File.cs:line`). Palm 1.2.2: `docs/reference/palm-src/Src`. Re-read in the source on 2026-11-17. Research 01 §10 was the checklist; its claims match the source for this chain.
>
> **Shared rules.** `GameState.specialEventAvailable` (C# `ShowSpecialButton`), `Command.specialEvent` (two-phase for events that are not message-only, with `WarningID.acceptSpecialEvent` and `amounts == [price]`), and the rejections `.noSpecialEvent` and `.insufficientFunds` are defined in QST-INDEX. A rejected command changes nothing. Unless stated otherwise, a handled event emits `GameEvent.specialEventCompleted(type)` as its last event.
>
> **Ownership.** Placement belongs to GAL (GAL-033, GAL-037). The Zalkon encounter's trigger, loadout and persistence belong to ENC (ENC-010…014). Combat outcomes belong to CMB (CMB-045, CMB-070). Arrival news belongs to NEWS (NEWS-033). This spec owns the quest statuses, the button conditions, the handler effects and the scenarios.

## 1. Statuses, events and table rows

- **QST-DRAGONFLY-001** {M4} [M][W] `quests.dragonfly` takes the values of `QuestStatus.Dragonfly`: 0 `notStarted`, 1 `flyBaratas`, 2 `flyMelina`, 3 `flyRegulas`, 4 `flyZalkon`, 5 `destroyed`, 6 `done`. A new game starts at 0. (source: SpecialEvent.cs:40-46)
- **QST-DRAGONFLY-002** {M4} [M][W][P] The chain's events and their placement: `dragonfly` on one random system (occurrence 1, GAL-037); `dragonflyBaratas` at Baratas (6), `dragonflyMelina` at Melina (59), `dragonflyRegulas` at Regulas (82) and `dragonflyDestroyed` at Zalkon (118), all fixed (GAL-033). `dragonflyShield` is never placed: it replaces `dragonflyDestroyed` at Zalkon (QST-DRAGONFLY-008). (source: Consts.cs:304-309, Game.cs:2885-2901; Palm: Src/Traveler.c:1484-1492)
- **QST-DRAGONFLY-003** {M4} [M][W][P] Table rows (price, occurrence, message-only): `dragonfly` 0/1/yes, `dragonflyBaratas` 0/0/yes, `dragonflyMelina` 0/0/yes, `dragonflyRegulas` 0/0/yes, `dragonflyDestroyed` 0/0/yes, `dragonflyShield` 0/0/no. Only `dragonflyShield` needs `.acceptSpecialEvent` (amounts `[0]`). No event in the chain changes cash. (source: Consts.cs:304-309; Palm: Src/Global.c:492-506)

## 2. When the button shows (`specialEventAvailable`)

- **QST-DRAGONFLY-004** {M4} [M][W][P] Conditions, while docked at the event's system: `dragonfly` needs police record ≥ −5 (Dubious); `dragonflyBaratas` needs `0 < dragonfly < 5`; `dragonflyMelina` needs `1 < dragonfly < 5`; `dragonflyRegulas` needs `2 < dragonfly < 5`; `dragonflyDestroyed` needs `dragonfly == 5`; `dragonflyShield` always shows. Because each follow-up needs a status that only the previous step sets, the steps can only be taken in the order start → Baratas → Melina → Regulas. (source: StarSystem.cs:160-186; Palm: Src/SystemInfoEvent.c:274-301)
- **QST-DRAGONFLY-005** {M5} [P] Palm hides the `dragonfly` start while more than 3 quests are open (`openQuestCap`, RUL-141). Palm's follow-up tests (`dragonfly < n` hides) are equivalent to C#'s for every reachable status. (source: Palm: Src/SystemInfoEvent.c:286-289, :302-311)

## 3. Handler effects

- **QST-DRAGONFLY-006** {M4} [M][W][P] `dragonfly`, `dragonflyBaratas`, `dragonflyMelina` and `dragonflyRegulas` each do `dragonfly += 1` and remove the event from the system. The start takes 0 → 1, Baratas 1 → 2, Melina 2 → 3 and Regulas 3 → 4. (source: Game.cs:2289-2294; Palm: Src/SpecialEvent.c:167-171, :231-236)
- **QST-DRAGONFLY-007** {M4} [M][W][P] No step in §3 draws from the RNG, and none touches cargo, crew, record or reputation.
- **QST-DRAGONFLY-008** {M4} [M][W][P] `dragonflyDestroyed` (status 5) replaces Zalkon's event with `dragonflyShield` instead of removing it, and leaves the status at 5. The shield offer is available at once, because `dragonflyShield` always shows. (source: Game.cs:2295-2298; Palm: Src/SpecialEvent.c:173-176)
- **QST-DRAGONFLY-009** {M4} [M][W][P] `dragonflyShield` without `.acceptSpecialEvent` returns `needsConfirmation(Confirmation(.acceptSpecialEvent, amounts: [0]))`. With it, if the ship has no free shield slot the command is rejected with `.noFreeSlot` (C# `EquipmentNotEnoughSlots`): the offer stays at Zalkon and the status stays 5. Otherwise one Lightning shield (power 350, charge 350) goes into the first free shield slot, the event is removed, and the C# status becomes 6. (source: Game.cs:2299-2311, Ship.cs:117-128, Shield.cs:42-48, Consts.cs:218; Palm: Src/SpecialEvent.c:335-348)
- **QST-DRAGONFLY-010** {M4} [M][W][P] The reward shield is an ordinary Lightning shield afterwards. It is sold, recharged and lost with the ship like any other shield, and transferring it on a ship trade costs the unique-equipment transfer price (SHP-044, RUL-053). Losing it never reopens the offer.
- **QST-DRAGONFLY-011** {M5} [P] Palm has no `done` status: installing the shield leaves `DragonflyStatus` at 5. No later rule reads the difference (the offer is removed and the Palm quest list shows only statuses 1…4), so the engine stores 6 in every ruleset and needs no flag. (source: Palm: Src/SpecialEvent.c:335-348, Src/QuestEvent.c:113-123, Src/Global.c:628)

## 4. The Zalkon encounter

- **QST-DRAGONFLY-012** {M4} [M][W][P] While `dragonfly == 4`, every trip to Zalkon meets the persistent Dragonfly (`specialShips.dragonfly`) at click 1, as ENC-010(c), ENC-011 and ENC-012 specify. Escaping, being escaped from, or ignoring it while cloaked leaves the status at 4, so the encounter repeats on the next trip to Zalkon. In C# the damage carries over to that meeting. (source: Game.cs:800-806; Palm: Src/Traveler.c:1842-1850)
- **QST-DRAGONFLY-013** {M4} [M][W] Destroying or disabling the Dragonfly sets `dragonfly = 5` and adds `pirateKills += 1`, record +1 and `reputation += 11/2 + 1 = 6` (the Dragonfly's ship type is 11), with no bounty and no scoop (CMB-045, CMB-070). The trip continues to Zalkon. (source: Game.cs:1101-1106, :1195-1217, :2028)
- **QST-DRAGONFLY-014** {M5} [P] Palm cannot disable ships (RUL-015). Destroying the Dragonfly sets status 5 (CMB-076). Every Palm meeting starts with an undamaged Dragonfly with reset crew skills (ENC-013). (source: Palm: Src/Encounter.c:1025-1028, Src/Traveler.c:1842-1850)
- **QST-DRAGONFLY-015** {M4} [M][W][P] Arrest, the escape pod, ship purchase and death in other encounters never change `quests.dragonfly`. A player destroyed by the Dragonfly loses the game by the normal CMB and SCORE rules.

## 5. News

- **QST-DRAGONFLY-016** {M4} [M][W] Arrival headlines follow NEWS-033 and read the current system's event at arrival time. The start system gives `dragonfly` while its event is unhandled; Baratas, Melina and Regulas give their headline at status 1, 2 and 3; Zalkon gives `dragonflyZalkon` at status 4 and `dragonflyDestroyed` at status 5 while its event is still `dragonflyDestroyed`. Once that event has become `dragonflyShield`, Zalkon gives nothing. Palm's flag chain is NEWS-038/041 {M5}. (source: Game.cs:2729-2749)

## 6. Scenarios

- **QST-DRAGONFLY-017** {M4} [M][W] Scenario (happy path): with record 0, accept `dragonfly` (status 1, event gone); dock at Baratas, Melina and Regulas and take each message (status 2, 3, 4). Warp to Zalkon: a `dragonflyAttack` encounter starts at click 1. Destroy it: status 5, +1 pirate kill, +1 record, +6 reputation. At Zalkon, take `dragonflyDestroyed`: the event becomes `dragonflyShield` and the status stays 5. Then `.specialEvent` without consent returns the `.acceptSpecialEvent` confirmation. With consent, a Lightning shield at charge 350 is in the first free slot, the status is 6, Zalkon has no event, and `specialEventAvailable == nil`.
- **QST-DRAGONFLY-018** {M4} [M][W] Scenario (gates and order): with record −6, the `dragonfly` start is hidden (`.specialEvent` → `.noSpecialEvent`). At status 1, Melina and Regulas are hidden while Baratas shows. At status 0, Baratas is hidden.
- **QST-DRAGONFLY-019** {M4} [M][W] Scenario (failures): (a) with every shield slot filled, the consented `dragonflyShield` returns `.noFreeSlot` with the state unchanged; after selling one shield the same command installs the Lightning shield. (b) At status 4, fleeing from the Dragonfly successfully leaves the status at 4 and keeps its hull damage. The next trip to Zalkon meets it again at click 1 with that hull. (c) Arriving at Zalkon at status 4 after the Dragonfly was ignored while cloaked shows no button.
