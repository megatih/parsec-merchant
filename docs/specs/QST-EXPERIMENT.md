# QST-EXPERIMENT: The dangerous experiment

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `{M4}` is C# 2.01 behaviour, kept in Modern, plus anything shared with Palm. `{M5}` is a Palm-only variant or a Modern-only fix that needs a ruleset flag.
> Sources: C# 2.01 at `/Users/megatih/Downloads/SpaceTraderSource201`, Palm 1.2.2 at `docs/reference/palm-src/Src`, re-read on 2026-11-17. Shared rules are QST-INDEX §3. Placement: the `Experiment` start event goes to the closest free system at least 70 parsecs from Daled (GAL-036; Palm GAL-046) and `ExperimentStopped` sits at Daled (17) (GAL §10.1).
> Status constants: `QuestStatus.Experiment` = notStarted 0, started 1 (counts 1…11), date 11, performed 12, cancelled 13. Related state: `quests.fabricRipProbability`, `quests.canSuperWarp`.

## 1. Start

- **QST-EXPERIMENT-001** {M4} [M][W][P] `Experiment` is shown iff `rec >= −5`; it is message-only and costs 0. Handling sets `experiment = 1` and removes the event. No arrival headline belongs to the start system. (source: StarSystem.cs:162-164; Game.cs:2317-2319; Consts.cs:311; Game.cs:2719-2829 has no Experiment case; Palm: Src/SpecialEvent.c:147-149, Src/SystemInfoEvent.c:278-280)
- **QST-EXPERIMENT-002** {M5} [P] Palm hides the start while more than 3 quests are open (`openQuestCap`, RUL-141). (source: Palm: Src/SystemInfoEvent.c:302-314)

## 2. Countdown and the performed experiment

- **QST-EXPERIMENT-003** {M4} [M][W][P] The counter follows TRV-078: each `IncDays(n)` with `0 < experiment < 12` sets `experiment = min(experiment + n, 12)`. With one day per warp, Daled must be reached on an arrival after at most 10 day advances (status ≤ 11); the 11th day advance performs the experiment. (source: Game.cs:2618-2621; Palm: Src/Traveler.c:1727-1730)
- **QST-EXPERIMENT-004** {M4} [M][W][P] On reaching 12, in the same `IncDays` call: `fabricRipProbability = 25`; Daled's event becomes `ExperimentFailed` (replacing `ExperimentStopped`); `GameEvent.experimentPerformed` is emitted (ALR-151); `NewsEvent.experimentPerformed` is appended (lost at the departure news reset when the day advance was the departure's own, TRV-029). The fabric-rip probability is not lowered in that same call (`else if`). (source: Game.cs:2622-2631; Palm: Src/Traveler.c:1731-1741)
- **QST-EXPERIMENT-005** {M4} [M][W][P] After the experiment, each `IncDays(n)` with `experiment == 12 && fabricRipProbability > 0` lowers the probability by `n` (it may go below 0); each departure then makes the rip test of TRV-036/037 with the current probability, and a rip changes only the destination (TRV-038). A probability of exactly 25 always rips (TRV-039). (source: Game.cs:2630-2631, :3108-3113)
- **QST-EXPERIMENT-006** {M4} [M][W][P] `ExperimentFailed` is always shown, is message-only, costs 0 and only removes itself; arriving at Daled while it is in place adds `NewsEvent.experimentFailed` (NEWS-033). It does not change `experiment` or the rip probability. (source: StarSystem.cs:188, :199; Game.cs:2320-2321; Consts.cs:312; Game.cs:2750-2752; Palm: Src/SpecialEvent.c:156-157)

## 3. Stopping the experiment

- **QST-EXPERIMENT-007** {M4} [M][W][P] `ExperimentStopped` (Daled) is shown iff `0 < experiment < 12`; it is message-only and costs 0. Arriving at Daled while it is shown adds `NewsEvent.experimentStopped` (NEWS-033). (source: StarSystem.cs:205-208; Consts.cs:313; Game.cs:2753-2757; Palm: Src/SystemInfoEvent.c:285)
- **QST-EXPERIMENT-008** {M4} [M][W][P] Handling `ExperimentStopped` sets `experiment = 13` (cancelled) and `canSuperWarp = true`, and removes the event. From then on `IncDays` changes neither `experiment` nor the rip probability (which stays 0), so no fabric rip can ever occur. (source: Game.cs:2322-2325, :2618-2631; Palm: Src/SpecialEvent.c:151-154)
- **QST-EXPERIMENT-009** {M4} [M][W][P] The portable singularity is the `.jump` command of TRV-019…025: one jump to any system, consumed on consent (`canSuperWarp = false`, TRV-021). No other rule sets `canSuperWarp`; arrest, the escape pod and ship trades keep it. (source: Game.cs:3262, Form_SpaceTrader.cs:3048, :3551; Game.cs:202-300, :2031-2101)

## 4. Scenarios

- **QST-EXPERIMENT-010** {M4} [M][W] Stopped in time: with `rec = 0`, handle `Experiment` (status 1); make 5 one-day warps (status 6) to Daled; `specialEventAvailable == .experimentStopped`; handling it gives status 13, `canSuperWarp == true`, Daled's event `nil`, events `[.specialEventCompleted(.experimentStopped)]`; a later `.jump` with `[.useSingularity]` reaches any target and clears `canSuperWarp`. (source: Game.cs:2317-2325)
- **QST-EXPERIMENT-011** {M4} [M][W] Performed: handle `Experiment` and make 11 one-day warps avoiding Daled; the 11th departure emits `.experimentPerformed`, sets the probability to 25 and Daled's event to `ExperimentFailed`, and that same trip is redirected by a fabric rip (`.fabricRip(newDestination:)`); the next departure lowers the probability to 24 before its rip test. At Daled `.experimentFailed` is offered and handling it only removes it. (source: Game.cs:2618-2631, :3108-3113)
- **QST-EXPERIMENT-012** {M4} [M][W] Performed in jail: an arrest with a 30-day term at status 2 sets status 12 and probability 25 during the jail `IncDays(30)` without lowering it; the `experimentPerformed` headline survives into the arrival paper (TRV-029); the next departure's `IncDays(1)` lowers the probability to 24 before its rip test, so that trip rips only with probability 24/100. (source: Game.cs:2618-2631, :2854, :3108-3109)
- **QST-EXPERIMENT-013** {M4} [M][W] Not accepted: with `rec < −5` the start is not offered; Daled's `ExperimentStopped` is never shown (status 0) and the experiment never happens. (source: StarSystem.cs:162-164, :205-208)
