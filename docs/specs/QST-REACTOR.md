# QST-REACTOR: Morgan's unstable reactor

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `{M4}` is C# 2.01 behaviour, kept in Modern, plus anything shared with Palm. `{M5}` is a Palm-only variant or a Modern-only fix that needs a ruleset flag.
>
> **Sources.** C# 2.01: `/Users/megatih/Downloads/SpaceTraderSource201` (`File.cs:line`). Palm 1.2.2: `docs/reference/palm-src/Src`. Re-read in the source on 2026-11-17. Research 01 §10 was the checklist (see §8).
>
> **Shared rules.** `specialEventAvailable`, `Command.specialEvent`, the two-phase consent and the `.noSpecialEvent` and `.insufficientFunds` rejections are defined in QST-INDEX. A handled event emits `GameEvent.specialEventCompleted(type)` as its last event.
>
> **Ownership.** GAL owns placement (GAL-036, GAL-043). TRV owns the arrival pipeline and the counter (TRV-050, TRV-052, TRV-077). SHP owns bay accounting and the trade block (SHP-015, SHP-036). CMB owns the damage factor (CMB-024, CMB-025). POL owns inspection, arrest and the pod (POL-051, POL-066, POL-093, POL-103, POL-104). The tribble rules belong to QST-TRIBBLES (TRV-053, RUL-151). This spec owns the statuses, the handler, the countdown effects, meltdown and the scenarios.

## 1. Statuses, events and table rows

- **QST-REACTOR-001** {M4} [M][W] `quests.reactor` takes the values of `QuestStatus.Reactor`: 0 `notStarted`, 1 `fuelOK` (just loaded), 2…19 counting days, 20 `date` (meltdown), 21 `delivered`, 22 `done` (laser installed, or reactor lost in the pod). "Reactor aboard" (`reactorOnBoard`) means `0 < reactor < 21`, on the commander's ship. A new game starts at 0. (source: SpecialEvent.cs:83-87, Ship.cs:1163-1170)
- **QST-REACTOR-002** {M4} [M][W][P] Events: `reactor` on the system nearest to Nix at ≥ 70 parsecs (GAL-036; Palm GAL-043) and `reactorDelivered` at Nix (67). `reactorLaser` is never placed and replaces `reactorDelivered` (QST-REACTOR-011). Table rows (price, occurrence, message-only): `reactor` 0/0/no, `reactorDelivered` 0/0/yes, `reactorLaser` 0/0/no. `reactor` and `reactorLaser` need `.acceptSpecialEvent` with amounts `[0]`. (source: Consts.cs:325-327; Palm: Src/Global.c:517-518, :522)

## 2. When the button shows

- **QST-REACTOR-003** {M4} [M][W][P] `reactor` needs `reactor == 0`, police record < −5 and reputation ≥ 40. `reactorDelivered` needs the reactor aboard. `reactorLaser` always shows. (source: StarSystem.cs:193, :249-256; Palm: Src/SystemInfoEvent.c:282-283)
- **QST-REACTOR-004** {M5} [P] Palm hides the `reactor` start while more than 3 quests are open (RUL-141). (source: Palm: Src/SystemInfoEvent.c:302-311)

## 3. Accepting the reactor

- **QST-REACTOR-005** {M4} [M][W][P] `reactor` with `.acceptSpecialEvent`: if free cargo bays < 15, the command is rejected with `.noEmptyBays` (C# `CargoNoEmptyBays`) and the offer stays. (source: Game.cs:2432-2437; Palm: Src/SpecialEvent.c:94-99)
- **QST-REACTOR-006** {M4} [M][W] With enough bays and Wild aboard, the command also needs `.wildLeavesForReactor` (ALR-188; amounts empty, the system is the current one). Without it, the result is `needsConfirmation(Confirmation(.wildLeavesForReactor))` and nothing changes, so declining keeps Wild and the offer (C# `remove = false`). With it, `wild = 0` and `wildLeftShip` is emitted. Wild stays in the crew (port quirk, QST-WILD-014, CRW-046). (source: Game.cs:2438-2450)
- **QST-REACTOR-007** {M4} [M][W][P] On success, `reactor = 1` and the event is removed. The events are `[wildLeftShip]` (only in the Wild case) followed by `specialEventCompleted(.reactor)`. (source: Game.cs:2451-2457; Palm: Src/SpecialEvent.c:116-118)

## 4. While the reactor is aboard

- **QST-REACTOR-008** {M4} [M][W][P] Bays: the reactor fills `5 + 10 − (reactor − 1) / 2` bays (SHP-015): 15 at status 1 and 2, 14 at 3, … 6 at status 19. It is not a trade item: it cannot be sold, dumped, jettisoned or stolen. Example: a 30-bay ship accepted at status 1 has 15 free bays (empty hold); at status 5 it has 17. (source: Ship.cs:961-970; Palm: Src/Cargo.c:1028-1029)
- **QST-REACTOR-009** {M4} [M][W] Other effects while aboard: (a) combat damage to the player is multiplied (CMB-024 [W]; CMB-025 / RUL-114 [M][P] {M5}); (b) on arrival the tribbles all die below 20, else they halve (TRV-053, RUL-151); (c) it is illegal special cargo (POL-051): submitting leads to arrest (POL-059, RUL-139), the bribe is multiplied (POL-066), yielding leads to arrest (POL-071); (d) a ship trade is rejected with `.reactorOnBoard` (SHP-036); (e) after a pirate raid the event `piratesIgnoredReactor` is emitted (ALR-056); (f) Wild refuses to board (QST-WILD-006). (source: Game.cs:1336-1337, :405-416, :1929-1930, Commander.cs:138, Ship.cs:1131-1137)
- **QST-REACTOR-010** {M4} [M][W][P] Countdown: each `IncDays(n)` with the reactor aboard does `reactor = min(reactor + n, 20)` (TRV-077). This counts days, unlike passenger impatience. While the reactor is aboard only a normal departure's `IncDays(1)` can run (an arrest confiscates it first and the pod destroys it first), and a singularity jump adds no day. So status `1 + k` is reached on the k-th normal departure after loading. (source: Game.cs:2615-2616, :2849-2855; Palm: Src/Traveler.c:1719-1723)

## 5. Arrival: warnings and meltdown

- **QST-REACTOR-011** {M4} [M][W] `reactorDelivered` (message-only, at Nix): `reactor = 21` and the event becomes `reactorLaser` (not removed). The reactor bays are freed at once. Delivery is possible at statuses 1…19, because an arrival at 20 melts down first. (source: Game.cs:2459-2463)
- **QST-REACTOR-012** {M4} [M][W] The reactor check is the first arrival step (TRV-050, TRV-052). At status 2, 16 or 18 it emits `reactorWarning(status:)` with that status (ALR-131 fuel consumption, ALR-132 fuel starvation, ALR-133 core temperature). After loading at status 1 these come on the 1st, 15th and 17th arrivals, and meltdown on the 19th. (source: Game.cs:365-393)
- **QST-REACTOR-013** {M4} [M][W] Meltdown at status 20: emit `reactorMeltdown` and set `reactor = 0`. With an escape pod, the pod sequence runs (POL-103, POL-104). Its reactor step does **not** fire, because the status is already 0: no `reactorDestroyed`, and the status stays 0, not 22. The arrival pipeline then continues (TRV-052). Without a pod: emit `reactorDestroyed` (ALR-128) and `gameEnded(.killed)`, set `phase = .gameOver(.killed)`, and stop the pipeline. The score is the killed score (SCORE). (source: Game.cs:365-376, :2031-2042)
- **QST-REACTOR-014** {M5} [P] Palm arrival order: `Arrival()` runs first, then the warnings at 2, 16 and 18 and the meltdown at 20 (RUL-066, TRV-060). After a meltdown the Palm pod runs only its short `Arrival()` (POL-110). (source: Palm: Src/Traveler.c:2232-2258)

## 6. The laser reward

- **QST-REACTOR-015** {M4} [M][W] `reactorLaser` with consent: with no free weapon slot, the command is rejected with `.noFreeSlot` (C# `EquipmentNotEnoughSlots`) and the offer stays (it always shows). Otherwise one Morgan's laser (power 85) goes into the first free weapon slot, `reactor = 22`, and the event is removed. Afterwards it is an ordinary Morgan's laser (unique transfer price, RUL-053). (source: Game.cs:2464-2476, Consts.cs:372)
- **QST-REACTOR-016** {M5} [P] Palm `GETSPECIALLASER` installs Morgan's laser but leaves `ReactorStatus` at 21. No later rule reads the difference, so the engine stores 22 in every ruleset and needs no flag. (source: Palm: Src/SpecialEvent.c:121-125, :350-362)

## 7. Failure paths

- **QST-REACTOR-017** {M4} [M][W] Arrest with the reactor aboard (POL-093 step 2): `reactor = 0` and event `reactorConfiscated` (ALR-127). The quest is over: the `reactor` event was removed, and `reactorDelivered` needs the reactor aboard. (source: Game.cs:222-226)
- **QST-REACTOR-018** {M4} [M][W] Escape pod in combat with the reactor aboard (POL-104 step 2): `reactor = 22` and event `reactorDestroyed` (ALR-128). The quest is over with no laser. (source: Game.cs:2038-2042)
- **QST-REACTOR-019** {M5} [P] Palm: the pod sets status 0 instead of 22 (POL-107). Submitting with the reactor and no Wild confiscates it without an arrest (RUL-139, POL-062). The damage factor follows RUL-114. (source: Palm: Src/Encounter.c:594-597, :2123-2131)
- **QST-REACTOR-020** {M4} [M][W][P] The chain adds no news headline.

## 8. Research notes

- **QST-REACTOR-021** {M4} [M][W] Research 01 §10 says that at 20 "you melt down (escape pod or death)". The source adds two details: meltdown is tested only on arrival (QST-REACTOR-012), and after a meltdown with a pod the status ends at 0, not 22, with no `reactorDestroyed` notice (QST-REACTOR-013). (source: Game.cs:365-376)

## 9. Scenarios

- **QST-REACTOR-022** {M4} [M][W] Scenario (happy path): with record −10, reputation 40 and 20 free bays, accept `reactor` (consent): status 1, 5 free bays. Each normal warp adds 1: the 1st arrival emits `reactorWarning(status: 2)`. Reach Nix on, say, the 6th arrival (status 7, 12 bays in use): `reactorDelivered` sets status 21, frees the bays and turns the event into `reactorLaser`. With consent and a free weapon slot, Morgan's laser is installed, status 22, and Nix has no event.
- **QST-REACTOR-023** {M4} [M][W] Scenario (meltdown): load the reactor and make 19 normal warps without reaching Nix. Warnings come on arrivals 1, 15 and 17. On arrival 19: (a) without a pod: `reactorMeltdown`, `reactorDestroyed`, `gameEnded(.killed)`, `phase == .gameOver(.killed)`, and no further arrival events; (b) with a pod: `reactorMeltdown`, then the pod events (a Flea, the 500 charge, `IncDays(3)`), `reactor == 0`, no `reactorDestroyed`, and the arrival completes.
- **QST-REACTOR-024** {M4} [M][W] Scenario (refusals): (a) 14 free bays: `.noEmptyBays`, state unchanged. (b) Wild aboard: the consented accept returns the `.wildLeavesForReactor` confirmation with the state unchanged. Acknowledging both gives `[wildLeftShip, specialEventCompleted(.reactor)]`, `wild == 0`, Wild still in the crew, and `reactor == 1`. (c) `reactorLaser` with all weapon slots full: `.noFreeSlot`, status 21, and the offer remains. (d) Record −5 or reputation 39: hidden.
- **QST-REACTOR-025** {M4} [M][W] Scenario (losses): (a) arrested with the reactor aboard: `reactorConfiscated`, `reactor == 0`, and no button at Nix. (b) Destroyed in combat with a pod and the reactor aboard: `reactorDestroyed`, `reactor == 22`, and no button at Nix. (c) With the reactor aboard, buying a ship returns `.reactorOnBoard`.
