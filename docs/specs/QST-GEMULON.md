# QST-GEMULON: The Gemulon invasion

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `{M4}` is C# 2.01 behaviour, kept in Modern, plus anything shared with Palm. `{M5}` is a Palm-only variant or a Modern-only fix that needs a ruleset flag.
> Sources: C# 2.01 at `/Users/megatih/Downloads/SpaceTraderSource201`, Palm 1.2.2 at `docs/reference/palm-src/Src`, re-read on 2026-11-17. Shared rules (availability, consent, price check, removal, `specialEventCompleted`) are QST-INDEX §3. Placement: the `Gemulon` start event goes to the closest free system at least 70 parsecs from Gemulon (GAL-036; Palm GAL-045) and `GemulonRescued` sits at Gemulon (32) (GAL §10.1).
> Status constants: `QuestStatus.Gemulon` = notStarted 0, started 1 (counts 1…7), date 7, tooLate 8, fuel 9, done 10.

## 1. Start

- **QST-GEMULON-001** {M4} [M][W][P] The `Gemulon` event is always shown (no record or reputation condition), is message-only and costs 0. Handling sets `gemulon = 1` and removes the event. (source: StarSystem.cs:189, :199; Game.cs:2326-2328; Consts.cs:314; Palm: Src/SpecialEvent.c:274-276, Src/Global.c:514)
- **QST-GEMULON-002** {M4} [M][W][P] While the `Gemulon` event is still in place, arriving at its system adds `NewsEvent.gemulon` (NEWS-033). Nothing else marks the quest before it is accepted, and an unaccepted quest never invades Gemulon. (source: Game.cs:2758-2760, :2602-2603)
- **QST-GEMULON-003** {M5} [P] Palm hides the start (Alien Invasion) while more than 3 quests are open (`openQuestCap`, RUL-141). (source: Palm: Src/SystemInfoEvent.c:302-314)

## 2. Countdown

- **QST-GEMULON-004** {M4} [M][W] Every `IncDays(n)` with `0 < gemulon < 8` sets `gemulon = min(gemulon + n, 8)` (TRV-075). Statuses 0, 9 and 10 never count. With one day per warp, status `1 + k` holds after `k` day advances, so Gemulon must be reached on an arrival after at most 6 day advances (status ≤ 7). Jail terms (POL-097) and escape-pod days (`IncDays(3)`) count too. (source: Game.cs:2602-2606)
- **QST-GEMULON-005** {M4} [M][W] When the counter reaches 8, in the same `IncDays` call: Gemulon's event becomes `GemulonInvaded` (replacing `GemulonRescued`), its tech level becomes Pre-Agricultural and its government Anarchy, and `GameEvent.gemulonInvaded` is emitted (TRV-082). Every rule that reads Gemulon's tech level or government (prices, quantities, equipment and ship availability, police/pirate/trader activity) uses the new values from then on. (source: Game.cs:2606-2612)
- **QST-GEMULON-006** {M4} [M][W][P] While `gemulon == 8`, every click of a trip whose destination is Gemulon makes the single Mantis draw of ENC-020 (`rand(10) > 4` → Mantis pirate encounter) instead of the normal encounter bands. (source: Game.cs:925-929; Palm: Src/Traveler.c Travel)
- **QST-GEMULON-007** {M5} [P] Palm counts `InvasionStatus += n` without a cap and invades when it reaches `>= 8` (TRV-076, `invasionStatusCapped`); the Mantis rule tests `InvasionStatus > 7` (C#: `== 8`, since 9 and 10 follow a rescue; Palm's rescue resets to 0, QST-GEMULON-012). (source: Palm: Src/Traveler.c:1708-1717)

## 3. Rescue and reward

- **QST-GEMULON-008** {M4} [M][W][P] `GemulonRescued` is shown iff `0 < gemulon < 8`; it is message-only and costs 0. (source: StarSystem.cs:209-212; Consts.cs:317; Palm: Src/SystemInfoEvent.c:298)
- **QST-GEMULON-009** {M4} [M][W] Handling `GemulonRescued` sets `gemulon = 9` (fuel) and replaces Gemulon's event with `GemulonFuel`; the countdown stops. Gemulon keeps its tech level and government. (source: Game.cs:2342-2346)
- **QST-GEMULON-010** {M4} [M][W][P] `GemulonFuel` is always shown, is a question (consent `amounts == [0]`) and costs 0. With no free gadget slot it is rejected with `CommandError.noFreeSlot` (C# `EquipmentNotEnoughSlots`) and nothing changes: the event and `gemulon == 9` stay, so the reward can be claimed on any later visit. (source: StarSystem.cs:190, :199; Game.cs:2329-2334; Consts.cs:315; Palm: Src/SpecialEvent.c:364-370)
- **QST-GEMULON-011** {M4} [M][W] With a free gadget slot, `GemulonFuel` installs one Fuel Compactor (`Gadgets[FuelCompactor]`, SHP-060), sets `gemulon = 10` and removes the event. Fuel is not changed (the larger tank only matters for later refuelling, SHP-016). The app shows ALR-083 from `specialEventCompleted(.gemulonFuel)`. (source: Game.cs:2335-2340)
- **QST-GEMULON-012** {M5} [P] Palm rescue sets `InvasionStatus = 0` (there is no fuel or done status) and turns Gemulon's event into Fuel Compactor; installing the compactor puts it in the first empty gadget slot and sets `Fuel = GetFuelTanks()` (SHP-017). Flag `gemulonRewardRefuels` (RUL-172; Palm true). The engine stores the same 0 (flag `gemulonRescueResetsStatus`, Palm true; C# 9 then 10 after the compactor, which leaves the Palm 0 unchanged): the waiting compactor counts as the open quest (RUL-141) and the counter no longer ticks. (source: Palm: Src/SpecialEvent.c:178-182, :364-377)

## 4. Too late

- **QST-GEMULON-013** {M4} [M][W][P] `GemulonInvaded` is always shown, is message-only and costs 0. Handling it has no effect beyond removing the event (it is absent from the C# handler switch). (source: StarSystem.cs:191, :199; Game.cs:2275-2575 (no case), :2580-2581; Consts.cs:316; Palm: Src/SpecialEvent.c:91-391 (no case), :393-394)
- **QST-GEMULON-014** {M4} [M][W] Quirk (kept; NEWS-033 lists it faithfully): the arrival headline `gemulonInvaded` is unreachable, because the GemulonRescued branch of `NewsAddEventsOnArrival` needs `gemulon >= 8` while Gemulon still holds `GemulonRescued`, and the event is replaced by `GemulonInvaded` (or `GemulonFuel`) in the same step that sets the status to 8 (or 9). No arrival ever adds `NewsEvent.gemulonInvaded`; `gemulonRescued` is added on arrivals at Gemulon with `0 < gemulon < 8`. (source: Game.cs:2761-2768, :2606-2612, :2343-2344)
- **QST-GEMULON-015** {M4} [M][W][P] After the invasion the quest is over: no event can set `gemulon` again (the start was removed, and `GemulonRescued` no longer exists), so the Fuel Compactor is unobtainable in that game. (source: Game.cs:2326-2346, :2602-2613)

## 5. Other interactions

- **QST-GEMULON-016** {M4} [M][W][P] Arrest, the escape pod, ship trades and encounters never change `gemulon`; only their day advances count (QST-GEMULON-004). (source: Game.cs:202-300, :2031-2101)

## 6. Scenarios

- **QST-GEMULON-017** {M4} [M][W] Success: accept `Gemulon` (status 1); make 3 one-day warps (status 4) and arrive at Gemulon; `specialEventAvailable == .gemulonRescued`; handle it → status 9, event `GemulonFuel`, events `[.specialEventCompleted(.gemulonRescued)]`; then `.specialEvent` without acknowledgement returns the `acceptSpecialEvent` confirmation with `[0]`; with it and a free gadget slot → a Fuel Compactor is installed, status 10, Gemulon's event `nil`. (source: Game.cs:2326-2346)
- **QST-GEMULON-018** {M4} [M][W] Slot refusal: with every gadget slot full, accepting `GemulonFuel` returns `noFreeSlot` and the state hash is unchanged; after selling a gadget the same command succeeds. (source: Game.cs:2329-2340)
- **QST-GEMULON-019** {M4} [M][W] Too late by travel: accept the quest and make 7 one-day warps that avoid Gemulon; the 7th departure's day advance emits `.gemulonInvaded`, Gemulon becomes Pre-Agricultural Anarchy with event `GemulonInvaded`; the next trip to Gemulon uses the Mantis rule on every click (QST-GEMULON-006); at Gemulon `specialEventAvailable == .gemulonInvaded`, and handling it only removes it. (source: Game.cs:2602-2613, :925-929)
- **QST-GEMULON-020** {M4} [M][W] Too late by jail: an arrest with a 30-day term while `gemulon == 2` invades Gemulon during the jail `IncDays(30)` (status 8, not 32), before the arrival at the destination. (source: Game.cs:2605, POL-097)
