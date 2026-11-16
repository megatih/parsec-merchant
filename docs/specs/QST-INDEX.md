# QST: Quest chains and special events (index and shared rules)

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2.
> Milestones: Windows 2.01 behaviour, which Modern shares until the {M5} ruleset flags land, is {M4}. Palm-only variants and Modern-only fixes are {M5} and name their RUL flag.
> C# sources are relative to `/Users/megatih/Downloads/SpaceTraderSource201` (cp1252; line numbers re-read on 2026-11-17). Palm sources are `docs/reference/palm-src/Src/…`.
> Shared IDs in this file are `QST-001…`. Each chain file uses `QST-<CHAIN>-NNN`. Event placement in the galaxy is owned by GAL.md §10 and is not re-specified here. Arrival headlines are owned by NEWS-033/034, day counters by TRV §9, arrest and escape-pod sequences by POL §8/§9.
> Engine names: quest statuses are the `QuestStatus.*` constants of `Model/GameState.swift` (the C# codes). `rec` = police record score, `rep` = reputation score, `worth` = commander worth (BNK-004/006, flag `worthUsesTradeInValue`).

## 1. Chains

| Chain | Events (C# `SpecialEventType`) | Spec | Content pack |
|---|---|---|---|
| Dragonfly | Dragonfly, DragonflyBaratas, DragonflyMelina, DragonflyRegulas, DragonflyDestroyed, DragonflyShield | [QST-DRAGONFLY.md](QST-DRAGONFLY.md) | all |
| Space Monster | SpaceMonster, SpaceMonsterKilled | [QST-MONSTER.md](QST-MONSTER.md) | all |
| Scarab | Scarab, ScarabDestroyed, ScarabUpgradeHull | [QST-SCARAB.md](QST-SCARAB.md) | all |
| Japori | Japori, JaporiDelivery | [QST-JAPORI.md](QST-JAPORI.md) | all |
| Jarek | Jarek, JarekGetsOut | [QST-JAREK.md](QST-JAREK.md) | all |
| Wild | Wild, WildGetsOut | [QST-WILD.md](QST-WILD.md) | all |
| Reactor | Reactor, ReactorDelivered, ReactorLaser | [QST-REACTOR.md](QST-REACTOR.md) | all |
| Gemulon | Gemulon, GemulonRescued, GemulonFuel, GemulonInvaded | [QST-GEMULON.md](QST-GEMULON.md) | all |
| Experiment | Experiment, ExperimentStopped, ExperimentFailed | [QST-EXPERIMENT.md](QST-EXPERIMENT.md) | all |
| Artifact | Artifact, ArtifactDelivery | [QST-ARTIFACT.md](QST-ARTIFACT.md) | all |
| Moon | Moon, MoonRetirement | [QST-MOON.md](QST-MOON.md) | all |
| Tribbles | Tribble, TribbleBuyer (plus the arrival tribble update) | [QST-TRIBBLES.md](QST-TRIBBLES.md) | all |
| One-offs | CargoForSale, EraseRecord, Skill, Lottery | [QST-ONEOFFS.md](QST-ONEOFFS.md) | all |
| Sculpture | Sculpture, SculptureDelivered, SculptureHiddenBays | [QST-SCULPTURE.md](QST-SCULPTURE.md) | Windows 2.01, Modern |
| Princess | Princess, PrincessCentauri, PrincessInthara, PrincessQonos, PrincessReturned, PrincessQuantum | [QST-PRINCESS.md](QST-PRINCESS.md) | Windows 2.01, Modern |

The first seven chain files are written by a parallel spec pass; the names above are the agreed file names.

## 2. The special-event table (C# `Consts.SpecialEvents`, ShowSpecialButton, removal)

Columns: **Price** (a negative price is paid to the player), **Occ** (random placement count, GAL-037), **Msg** (`messageOnly`: T = acknowledgement only, F = question needing consent), **Shown when** (C# `StarSystem.ShowSpecialButton`, StarSystem.cs:153-287; `onBoard` predicates are C# `Ship.*OnBoard`), **After handling** (C# `HandleSpecialEvent`, Game.cs:2270-2582: *removed* sets the system's event to `nil`; *→ X* replaces it with X; *kept* leaves it; "refused" means an in-handler refusal, which always keeps the event), **Palm** (index and name in `Src/spacetrader.h:237-276`; `—` = not in Palm).

| # | Event | Price | Occ | Msg | Shown when | After handling | Palm |
|---|---|---|---|---|---|---|---|
| 0 | Artifact | 0 | 1 | F | `rec >= −5` | removed | 19 ALIENARTIFACT |
| 1 | ArtifactDelivery | −20000 | 0 | T | artifact aboard (`artifact == 1`) | removed | 18 ARTIFACTDELIVERY |
| 2 | CargoForSale | 1000 | 3 | F | `freeCargoBays >= 3` | removed | 14 CARGOFORSALE |
| 3 | Dragonfly | 0 | 1 | T | `rec >= −5` | removed | 13 DRAGONFLY |
| 4 | DragonflyBaratas | 0 | 0 | T | `0 < dragonfly < 5` | removed | 1 FLYBARATAS |
| 5 | DragonflyDestroyed | 0 | 0 | T | `dragonfly == 5` | → DragonflyShield | 0 DRAGONFLYDESTROYED |
| 6 | DragonflyMelina | 0 | 0 | T | `1 < dragonfly < 5` | removed | 2 FLYMELINA |
| 7 | DragonflyRegulas | 0 | 0 | T | `2 < dragonfly < 5` | removed | 3 FLYREGULAS |
| 8 | DragonflyShield | 0 | 0 | F | always | removed; kept if refused (no shield slot) | 15 INSTALLLIGHTNINGSHIELD |
| 9 | EraseRecord | 5000 | 3 | F | `rec < −5` | removed | 10 ERASERECORD |
| 10 | Experiment | 0 | 0 | T | `rec >= −5` | removed | 24 EXPERIMENT |
| 11 | ExperimentFailed | 0 | 0 | T | always | removed | 35 EXPERIMENTNOTSTOPPED |
| 12 | ExperimentStopped | 0 | 0 | T | `0 < experiment < 12` | removed | 34 EXPERIMENTSTOPPED |
| 13 | Gemulon | 0 | 0 | T | always | removed | 21 ALIENINVASION |
| 14 | GemulonFuel | 0 | 0 | F | always | removed; kept if refused (no gadget slot) | 23 GETFUELCOMPACTOR |
| 15 | GemulonInvaded | 0 | 0 | T | always | removed | 22 GEMULONINVADED |
| 16 | GemulonRescued | 0 | 0 | T | `0 < gemulon < 8` | → GemulonFuel | 33 GEMULONRESCUED |
| 17 | Japori | 0 | 1 | F | `japori == 0 && rec >= −5` | kept (always) | 16 JAPORIDISEASE |
| 18 | JaporiDelivery | 0 | 0 | T | `japori == 1` | removed | 5 MEDICINEDELIVERY |
| 19 | Jarek | 0 | 1 | F | `rec >= −5` | removed; kept if refused (no quarters) | 20 AMBASSADORJAREK |
| 20 | JarekGetsOut | 0 | 0 | T | Jarek aboard | removed | 32 JAREKGETSOUT |
| 21 | Lottery | −1000 | 0 | T | always | removed | 17 LOTTERYWINNER |
| 22 | Moon | 500000 | 4 | F | `moon == 0 && worth > 400000` | removed | 7 MOONFORSALE |
| 23 | MoonRetirement | 0 | 0 | F | `moon == 1` | game ends (event kept) | 6 MOONBOUGHT |
| 24 | Reactor | 0 | 0 | F | `reactor == 0 && rec < −5 && rep >= 40` | removed; kept if refused (bays, or Wild kept) | 26 GETREACTOR |
| 25 | ReactorDelivered | 0 | 0 | T | reactor aboard (`0 < reactor < 21`) | → ReactorLaser | 31 REACTORDELIVERED |
| 26 | ReactorLaser | 0 | 0 | F | always | removed; kept if refused (no weapon slot) | 27 GETSPECIALLASER |
| 27 | Scarab | 0 | 1 | T | `scarab == 0 && rep >= 40` | removed | 28 SCARAB |
| 28 | ScarabDestroyed | 0 | 0 | T | `scarab == 2` | → ScarabUpgradeHull | 30 SCARABDESTROYED |
| 29 | ScarabUpgradeHull | 0 | 0 | F | `scarab == 2` | kept (hidden afterwards: `scarab == 3`) | 29 GETHULLUPGRADED |
| 30 | Skill | 3000 | 3 | F | always | removed | 8 SKILLINCREASE |
| 31 | SpaceMonster | 0 | 1 | T | always | removed | 12 SPACEMONSTER |
| 32 | SpaceMonsterKilled | −15000 | 0 | T | `spaceMonster == 2` | removed | 4 MONSTERKILLED |
| 33 | Tribble | 1000 | 1 | F | always | removed | 9 TRIBBLE |
| 34 | TribbleBuyer | 0 | 3 | F | `tribbles > 0` | removed | 11 BUYTRIBBLE |
| 35 | Wild | 0 | 1 | F | `rec < −5` | removed; kept if refused (quarters, laser, reactor) | 25 TRANSPORTWILD |
| 36 | WildGetsOut | 0 | 0 | T | Wild aboard | removed | 36 WILDGETSOUT |
| 37 | Sculpture | −2000 | 0 | F | `sculpture == 0 && rec < −5 && rep >= 40` | removed | — |
| 38 | SculptureDelivered | 0 | 0 | T | `sculpture == 1` | → SculptureHiddenBays | — |
| 39 | SculptureHiddenBays | 0 | 0 | F | always | removed; kept if refused (no gadget slot) | — |
| 40 | Princess | 0 | 0 | T | `rec >= 5 && rep >= 40` | → PrincessReturned | — |
| 41 | PrincessCentauri | 0 | 0 | T | `1 <= princess <= 3` | removed | — |
| 42 | PrincessInthara | 0 | 0 | T | `2 <= princess <= 3` | removed | — |
| 43 | PrincessQonos | 0 | 0 | F | `princess == 4` and Princess not aboard | removed; kept if refused (no quarters) | — |
| 44 | PrincessQuantum | 0 | 0 | F | always | removed; kept if refused (no weapon slot) | — |
| 45 | PrincessReturned | 0 | 0 | T | Princess aboard | → PrincessQuantum | — |

Message-only events: 26 (T rows). Question events: 20 (F rows). Every event that can be refused inside the handler has price 0.

## 3. Requirements

### 3.1 Availability

- **QST-001** {M4} [M][W][P] `GameState.specialEventAvailable: SpecialEventType?` is `nil` unless `phase == .docked` and the current system has an event; otherwise it is that event if its "Shown when" condition of the §2 table holds, else `nil`. It is a pure query (no state change, no RNG). (source: StarSystem.cs:153-287, Form_SpaceTrader.cs:3179; Palm: Src/SystemInfoEvent.c:274-316)
- **QST-002** {M4} [M][W] The "Shown when" column of §2 is exactly C# `ShowSpecialButton`, with the constants Dubious −5, Lawful 5 and ReputationAverage 40 (Consts.cs:108, :110, :118), and `free…` / `…aboard` predicates as C# `Ship` computes them (FreeCargoBays includes the antidote and reactor bays, Ship.cs:959-994; Artifact/Reactor/Sculpture aboard derive from the quest status, Ship.cs:811-816, :1163-1179; Jarek, Wild and the Princess aboard mean present in a crew slot). Events the switch does not list (none in C# 2.01) are never shown. (source: StarSystem.cs:153-287)
- **QST-003** {M4} [M][W] The Moon threshold `worth > 400000` is C# `Worth > MoonCost * .8` evaluated in double; for integer worth it equals the integer test `worth > 500000 * 4 / 5`. (source: StarSystem.cs:223-226, SpecialEvent.cs:34)
- **QST-004** {M5} [P] Palm availability (`SystemInfoEvent.c:274-316`) equals the C# table for every shared event except: the Dragonfly waypoints are shown when `dragonfly >= 1`/`>= 2`/`>= 3` with no upper bound and DragonflyDestroyed when `dragonfly >= 5`; MonsterKilled when `monster >= 2`; Moon For Sale when `!moonBought && worth >= 400000` (RUL-142, Palm worth); and, when more than 3 quests are open, the 11 quest starts Tribble, SpaceMonster, Dragonfly, Japori, Artifact, Jarek, Gemulon (Alien Invasion), Experiment, Wild, Reactor and Scarab are hidden (`openQuestCap`, RUL-141). Palm has no Sculpture or Princess events (RUL-013). (source: Palm: Src/SystemInfoEvent.c:274-316, Src/QuestEvent.c)

### 3.2 The `Command.specialEvent` flow

- **QST-005** {M4} [M][W][P] `perform(.specialEvent)` with `specialEventAvailable == nil` (no event, condition false, or not docked) is rejected with `CommandError.noSpecialEvent` and changes nothing. (source: Form_SpaceTrader.cs:3179 hides the button)
- **QST-006** {M4} [M][W][P] Consent: for a question event (Msg F) the command without `acknowledging: [.acceptSpecialEvent]` returns `needsConfirmation(Confirmation(.acceptSpecialEvent, amounts: [price]))` and changes nothing; declining means not resending. A message-only event (Msg T) needs no acknowledgement and is handled at once. (source: Form_SpaceTrader.cs:3615-3636; Palm: Src/SpecialEvent.c:40-63, :80)
- **QST-007** {M4} [M][W][P] Price check: after consent (or at once for message-only events), `cashToSpend < price` (ECO-042, BNK-054) rejects with `CommandError.insufficientFunds` and changes nothing. The check applies to every event, including negative prices: with `reserveMoney` on, a `cashToSpend` below −20000 blocks even the artifact reward. (source: Form_SpaceTrader.cs:3638-3640 `SpecialIF`; Palm: Src/SpecialEvent.c:82-87 `ToSpend()`)
- **QST-008** {M4} [M][W] Handling order: (1) the event's effect (chain spec); (2) `cash -= price` if `price != 0` (a negative price adds cash); (3) if not kept or replaced, the system's event becomes `nil`. The step emits the chain-specific events in effect order followed by `GameEvent.specialEventCompleted(type)`. (source: Game.cs:2270-2582)
- **QST-009** {M4} [M][W] C# reads the price in step (2) from the system's event **after** the effect, so for a replaced event it reads the replacement's price. Every replacement pair (DragonflyDestroyed/Shield, GemulonRescued/Fuel, Princess/PrincessReturned, PrincessReturned/Quantum, ReactorDelivered/Laser, ScarabDestroyed/UpgradeHull, SculptureDelivered/HiddenBays) has price 0 on both sides, so the engine charges the handled event's own price with identical results. (source: Game.cs:2577-2578, Consts.cs:301-346)
- **QST-010** {M4} [M][W] In-handler refusals (no free slot, quarters or bays; Wild's laser or reactor refusal; declining Wild's departure for the reactor) are returned as a rejection with the chain's `CommandError` and change nothing. This matches C#, where the refusal sets `remove = false` and the price charged afterwards is 0 for every refusable event (RUL-143). The single exception is SculptureHiddenBays (QST-SCULPTURE-011), whose status change precedes its refusal. (source: Game.cs:2299-2311, :2329-2341, :2347-2358, :2364-2377, :2400-2425, :2432-2476, :2500-2513, :2533-2559)
- **QST-011** {M5} [P] Palm charges the price **before** the effect and before any refusal (`specialEventPriceTiming`, RUL-143). Because every refusable Palm event has price 0 the outcome is the same, and Palm refusals also keep the event (`handled = true`). (source: Palm: Src/SpecialEvent.c:82-90, :393-394)
- **QST-012** {M4} [M][W][P] One command handles exactly one event. A replacement event (§2 "→ X") is a new event of the same system: it is offered by `specialEventAvailable` immediately if its condition holds and needs its own `.specialEvent` command (and consent, if it is a question). (source: Game.cs:2296, :2343, :2392, :2428, :2460, :2482, :2497; Form_SpaceTrader.cs:3654 `UpdateAll`)
- **QST-013** {M4} [M][W][P] A special event never advances the day, never runs `IncDays` and never touches the market except as a chain spec states (EraseRecord and WildGetsOut sell-price ×100/90, ECO-023; buy-price recalculation when a hire, a fire or a random skill change alters the ship's effective Trader skill, C# `Ship.Hire`/`Ship.Fire`/`ChangeRandomSkill`). (source: Game.cs:2270-2582, Ship.cs:195-213, :608-622, CrewMember.cs:69-87)
- **QST-014** {M4} [M][W] The only special events that draw from the game RNG are CargoForSale (one `rand(10)`), Skill (one `ChangeRandomSkill(1)` draw when an eligible skill exists, CRW-052) and JaporiDelivery (two such draws). Every other event draws nothing. (source: Game.cs:2285, :2361-2362, :2516, CrewMember.cs:69-87)
- **QST-015** {M4} [M][W] MoonRetirement ends the game inside the handler: no price is charged, the event is not removed, the phase becomes `.gameOver(.boughtMoon)` and the step's events end with `.specialEventCompleted(.moonRetirement), .gameEnded(.boughtMoon, score: score(for: .boughtMoon))` (QST-MOON, SCORE-002). (source: Game.cs:2388-2390)

### 3.3 Events, errors and confirmations

- **QST-016** {M4} [M][W][P] Shared QST API: `Command.specialEvent`; `WarningID.acceptSpecialEvent` (amounts `[price]`); `CommandError.noSpecialEvent`, `.insufficientFunds`; `GameEvent.specialEventCompleted(SpecialEventType)`, `.specialEventRefused(SpecialEventType, reason: CommandError)` (only QST-SCULPTURE-011), `.gameEnded(GameEndType, score: Int)`. In-handler refusals use `.noFreeSlot` (C# `EquipmentNotEnoughSlots`, as SHP-084), `.noFreeQuarters` (ALR-154 `SpecialNoQuarters`) and `.noEmptyBays` (ALR-014). The app derives the result narrative (ALR `Narrative.*` rows, e.g. ALR-083/150/153/163/171/175) from `specialEventCompleted(type)` plus the chain events. (source: ALR.md §3, Form_Alert.cs)
- **QST-017** {M4} [M][W][P] The 46 event texts are not `AlertType`s: the app shows `Strings.SpecialEventTitles[type]` / `SpecialEventStrings[type]` (C#) for the offer and the narrative, with OK for message-only and Accept/Decline for questions. Palm reuses the C# strings (RUL-005). (source: SpecialEvent.cs:173-187, Form_SpaceTrader.cs:3615-3636)

### 3.4 Invariants (fuzzer)

- **QST-018** {M4} [M][W] After every step: each quest status is one of the codes of its `QuestStatus` enum or in the counting ranges of TRV §9 (Gemulon 1…8, Experiment 1…12, Reactor 1…20, Jarek/Wild 1…11, Princess 4…14 while aboard); `artifact == 1` iff the artifact is aboard; at most one system holds each of GemulonRescued, GemulonFuel, ExperimentStopped, PrincessReturned and PrincessQuantum; the moon status never decreases. (source: SpecialEvent.cs:36-107)
- **QST-019** {M4} [M][W] Every shown event is handleable: for any state with `specialEventAvailable == e`, `perform(.specialEvent, acknowledging: [.acceptSpecialEvent])` returns either a completed step, a documented rejection (QST-007, QST-010) or the Reactor/Wild consent of QST-REACTOR, never `noSpecialEvent`. (source: Form_SpaceTrader.cs:3615-3655)

## 4. Discrepancies resolved against the source
- ALR-152 names the funds rejection `specialEventInsufficientFunds(price:)`; the engine API decision is the shared `.insufficientFunds` (QST-007), and the price is already carried by the consent's `amounts`.
- Research 01 §10 says the price is "charged even when the action fails"; true in C#, but every refusable event costs 0, so the engine models refusals as rejections (QST-010).
- Two arrival headlines are unreachable in C#: `gemulonInvaded` (QST-GEMULON-014) and `princessReturned` (QST-PRINCESS-014); NEWS-033/034 list them faithfully.
