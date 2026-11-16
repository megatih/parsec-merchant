# QST-MONSTER: The Space Monster at Acamar

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `{M4}` is C# 2.01 behaviour, kept in Modern, plus anything shared with Palm. `{M5}` is a Palm-only variant or a Modern-only fix that needs a ruleset flag.
>
> **Sources.** C# 2.01: `/Users/megatih/Downloads/SpaceTraderSource201` (`File.cs:line`). Palm 1.2.2: `docs/reference/palm-src/Src`. Re-read in the source on 2026-11-17. Research 01 §10 was the checklist; its claims match the source for this chain.
>
> **Shared rules.** `specialEventAvailable`, `Command.specialEvent`, the two-phase consent and the `.noSpecialEvent` and `.insufficientFunds` rejections are defined in QST-INDEX. A handled event emits `GameEvent.specialEventCompleted(type)`.
>
> **Ownership.** GAL owns placement (GAL-033, GAL-037). ENC owns the encounter trigger, loadout and persistence (ENC-010…014). TRV owns monster regrowth (TRV-073, RUL-062). CMB owns combat outcomes (CMB-038, CMB-070). NEWS owns headlines (NEWS-034).

## 1. Statuses, events and table rows

- **QST-MONSTER-001** {M4} [M][W] `quests.spaceMonster` takes the values of `QuestStatus.SpaceMonster`: 0 `notStarted`, 1 `atAcamar`, 2 `destroyed`, 3 `done`. A new game starts at 0. (source: SpecialEvent.cs:99-102)
- **QST-MONSTER-002** {M4} [M][W][P] Events: `spaceMonster` on one random system (occurrence 1, GAL-037) and `spaceMonsterKilled` at Acamar (0, fixed, GAL-033). Table rows (price, occurrence, message-only): `spaceMonster` 0/1/yes; `spaceMonsterKilled` −15000/0/yes. Both are message-only, so neither needs consent. (source: Consts.cs:332-333; Palm: Src/Global.c:495, :503)

## 2. When the button shows

- **QST-MONSTER-003** {M4} [M][W][P] `spaceMonster` always shows (no record or reputation condition). `spaceMonsterKilled` shows only when `spaceMonster == 2`. (source: StarSystem.cs:197, :273-275; Palm: Src/SystemInfoEvent.c:284)
- **QST-MONSTER-004** {M5} [P] Palm hides the `spaceMonster` start while more than 3 quests are open (`openQuestCap`, RUL-141). (source: Palm: Src/SystemInfoEvent.c:302-311)

## 3. Handler effects

- **QST-MONSTER-005** {M4} [M][W][P] `spaceMonster` sets `spaceMonster = 1` and removes the event. (source: Game.cs:2518-2520; Palm: Src/SpecialEvent.c:224-229)
- **QST-MONSTER-006** {M4} [M][W] `spaceMonsterKilled` sets `spaceMonster = 3`, removes the event, and changes cash by `cash -= -15000`, which adds 15000. Because the price is negative, the cash-to-spend check never rejects it, even with a large debt. (source: Game.cs:2521-2523, :2578-2579, Form_SpaceTrader.cs:3640)
- **QST-MONSTER-007** {M5} [P] Palm's `MONSTERKILLED` pays the same 15000 (`Credits -= -15000` before the handler) but leaves `MonsterStatus` at 2. No later rule reads the difference, so the engine stores 3 in every ruleset and needs no flag. (source: Palm: Src/SpecialEvent.c:81-89, :127-128)

## 4. The Acamar encounter

- **QST-MONSTER-008** {M4} [M][W][P] While `spaceMonster == 1`, every trip to Acamar meets the persistent Space Monster (`specialShips.spaceMonster`: hull 500, 3 military lasers, crew 8+D/8+D/1/1+D) at click 1. It is the first fixed check, so it takes precedence over the other fixed encounters (ENC-010(a), ENC-011, ENC-014). No trip meets it at status 0, 2 or 3. (source: Game.cs:782-789; Palm: Src/Traveler.c:1807-1822)
- **QST-MONSTER-009** {M4} [M][W][P] The monster cannot be disabled (CMB-038). Attacking it without laser power is rejected with `.noLasers` (ENC-140). Only destruction completes this step. (source: Ship.cs:905-912, Game.cs:1590-1605)
- **QST-MONSTER-010** {M4} [M][W] Destroying it sets `spaceMonster = 2` and adds `pirateKills += 1`, record +1 and `reputation += 10/2 + 1 = 6` (the monster's ship type is 10), with no bounty and no scoop (CMB-070). (source: Game.cs:2012-2016, :2028)
- **QST-MONSTER-011** {M4} [M][W] If the player escapes, is escaped from, or ignores the monster while cloaked, the status stays 1 and the monster keeps its damage (ENC-012). It regrows in every `IncDays(n)` call to `min(500, (int)(hull × 1.05^n))` (TRV-073; e.g. 100 → 105 after one day, 19 stays 19). The next trip to Acamar meets it at click 1 with that hull. (source: Game.cs:2599-2600)
- **QST-MONSTER-012** {M5} [P] Palm loads the monster's hull from `MonsterHull` at every meeting and writes it back only when the player escapes. It regrows once per warp, including singularity jumps, by `×105/100`, capped at 500 (RUL-062, TRV-032, ENC-013). Destroying it sets status 2 (CMB-076). (source: Palm: Src/Traveler.c:577-579, :1807-1822, Src/Encounter.c:1019-1022, :1067, :1091)
- **QST-MONSTER-013** {M4} [M][W][P] Arrest, the escape pod and ship purchase never change `quests.spaceMonster`. Arriving at Acamar at status 1 (after an escape) shows no button.

## 5. News

- **QST-MONSTER-014** {M4} [M][W] Arriving at Acamar while its event is still `spaceMonsterKilled` adds `spaceMonster` at status 1 and `spaceMonsterKilled` at status 2 (NEWS-034). Status 0 adds nothing. Palm's headlines are NEWS-038/041 {M5}. (source: Game.cs:2818-2823)

## 6. Scenarios

- **QST-MONSTER-015** {M4} [M][W] Scenario (happy path): accept `spaceMonster` (no consent needed; status 1, event gone). Warp to Acamar: a `spaceMonsterAttack` encounter starts at click 1 against a 500-hull monster. Destroy it: status 2, +1 pirate kill, +1 record, +6 reputation, no bounty. Dock at Acamar: the news holds `spaceMonsterKilled`. `.specialEvent` (message-only) adds 15000 cash, sets status 3 and removes Acamar's event.
- **QST-MONSTER-016** {M4} [M][W] Scenario (failure and retry): at status 1, damage the monster to hull 200, then escape. Arrive at Acamar: no button, news `spaceMonster`. Make three one-day warps elsewhere (each heals ×1.05, truncated: 210, 220, 231). Return to Acamar: the encounter starts with hull 231 × 1.05 = 242 (one more day on that trip) and status 1.
- **QST-MONSTER-017** {M4} [M][W] Scenario (gates): at status 0 a trip to Acamar has no monster encounter, and `spaceMonsterKilled` is hidden at status 0 and 1. Attacking the monster with only disruptors returns `.noLasers`.
