# QST-ARTIFACT: The alien artifact

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `{M4}` is C# 2.01 behaviour, kept in Modern, plus anything shared with Palm. `{M5}` is a Palm-only variant or a Modern-only fix that needs a ruleset flag.
> Sources: C# 2.01 at `/Users/megatih/Downloads/SpaceTraderSource201`, Palm 1.2.2 at `docs/reference/palm-src/Src`, re-read on 2026-11-17. Shared rules are QST-INDEX §3. Placement: `Artifact` is placed randomly once (GAL-037); `ArtifactDelivery` goes to the lowest-index free Hi-Tech system (GAL-035; Palm GAL-044, RUL-028).
> Status constants: `QuestStatus.Artifact` = notStarted 0, onBoard 1, done 2. `artifactOnBoard` ⇔ `artifact == 1` (C# `Ship.ArtifactOnBoard`, Ship.cs:811-816).

## 1. Pick-up

- **QST-ARTIFACT-001** {M4} [M][W][P] `Artifact` is shown iff `rec >= −5`; it is a question (consent `amounts == [0]`) and costs 0. Handling sets `artifact = 1` and removes the event. The artifact uses no cargo bay, crew quarter or equipment slot. (source: StarSystem.cs:160-164; Game.cs:2277-2279; Consts.cs:301; Ship.cs:959-972; Palm: Src/SpecialEvent.c:163-165)
- **QST-ARTIFACT-002** {M5} [P] Palm hides the pick-up while more than 3 quests are open (`openQuestCap`, RUL-141), and stores the quest as the boolean `ArtifactOnBoard`; the engine keeps the status codes, mapping Palm "aboard" to 1. (source: Palm: Src/SystemInfoEvent.c:302-314, Src/Global.c ArtifactOnBoard)

## 2. While aboard

- **QST-ARTIFACT-003** {M4} [M][W] On each click of every trip with the artifact aboard, when no encounter band matched and the Kravat/Wild branch was not taken, one draw `rand(20) <= 3` (4 in 20) turns the click into a Mantis pirate encounter (ENC-022/023, ENC-026, RUL-072). (source: Game.cs:955-956)
- **QST-ARTIFACT-004** {M5} [P] Palm makes the artifact Mantis draw whenever no pirate, police or trader flag is set, including after a failed Kravat roll (ENC-025, `artifactMantisCheck`). (source: Palm: Src/Traveler.c Travel)
- **QST-ARTIFACT-005** {M4} [M][W][P] Surrendering to the Mantis with the artifact aboard needs `WarningID.surrenderArtifact`; on consent `artifact = 0`, `GameEvent.artifactRelinquished` is emitted and the encounter ends normally (POL-076, ALR-012). Without the artifact the surrender is refused (`surrenderRefused`). (source: Game.cs:1837-1850)
- **QST-ARTIFACT-006** {M4} [M][W][P] Destroying a Mantis changes nothing in the quest; the artifact stays aboard. (source: Game.cs:1968-2029 `EncounterWon` has no artifact case)
- **QST-ARTIFACT-007** {M4} [M][W] Arrest and ship trades keep the artifact aboard (the status is not touched, and "aboard" follows the commander's current ship). (source: Game.cs:202-300; Ship.cs:811-816)
- **QST-ARTIFACT-008** {M4} [M][W] The escape pod with the artifact aboard sets `artifact = 2` (done) (POL-104 step 5). As for every pod step, there is no separate event: the pod report derives ALR-011 (`ArtifactLost`) from `escapePodUsed` and the status change (POL-104). (source: Game.cs:2055-2059)
- **QST-ARTIFACT-009** {M5} [P] The Palm escape pod sets `ArtifactOnBoard = false`, which the engine maps to `artifact = 0` (POL-107); the outcome is the same because the pick-up event no longer exists. (source: Palm: Src/Encounter.c:585-609)

## 3. Delivery

- **QST-ARTIFACT-010** {M4} [M][W][P] `ArtifactDelivery` is shown iff the artifact is aboard; it is message-only with price −20000. Handling sets `artifact = 2`, adds 20000 to cash (QST-008, `cash -= −20000`) and removes the event. While it is shown, arriving at its system adds `NewsEvent.artifactDelivery` (NEWS-033). (source: StarSystem.cs:166-168; Game.cs:2280-2282, :2577-2578; Consts.cs:302; Game.cs:2725-2728; Palm: Src/SpecialEvent.c:159-161, Src/Global.c:511)
- **QST-ARTIFACT-011** {M4} [M][W][P] After a surrender (status 0) or the pod (status 2) the quest cannot restart: the pick-up was removed when accepted and `ArtifactDelivery` stays hidden for the rest of the game. (source: Game.cs:2277-2282, StarSystem.cs:166-168)

## 4. Scenarios

- **QST-ARTIFACT-012** {M4} [M][W] Success: with `rec = 0`, `.specialEvent` at the pick-up returns the confirmation `acceptSpecialEvent` `[0]`; with it → status 1; travel to the delivery system; `specialEventAvailable == .artifactDelivery`; `.specialEvent` (no acknowledgement needed) → cash +20000, status 2, event removed, events `[.specialEventCompleted(.artifactDelivery)]`. (source: Game.cs:2277-2282)
- **QST-ARTIFACT-013** {M4} [M][W] Scripted RNG: with the artifact aboard and a click whose band roll matches nothing, a draw of 3 for `rand(20)` starts a Mantis encounter and a draw of 4 does not. (source: Game.cs:955-956)
- **QST-ARTIFACT-014** {M4} [M][W] Surrender failure: in a Mantis encounter, `.surrender` returns the `surrenderArtifact` confirmation; with it → status 0, `.artifactRelinquished`, transit resumes; `ArtifactDelivery` is never shown again. (source: Game.cs:1839-1846)
- **QST-ARTIFACT-015** {M4} [M][W] Pod failure: destroyed with an escape pod while carrying the artifact → status 2 (the pod report shows ALR-011); no reward is ever paid. (source: Game.cs:2055-2059)
- **QST-ARTIFACT-016** {M4} [M][W] Record gate: with `rec = −6` the pick-up is not offered (`specialEventAvailable == nil`, `.specialEvent` → `noSpecialEvent`); after the record rises to −5 it is offered. (source: StarSystem.cs:160-164)
