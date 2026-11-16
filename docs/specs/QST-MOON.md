# QST-MOON: Buying a moon and retiring to Utopia

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `{M4}` is C# 2.01 behaviour, kept in Modern, plus anything shared with Palm. `{M5}` is a Palm-only variant or a Modern-only fix that needs a ruleset flag.
> Sources: C# 2.01 at `/Users/megatih/Downloads/SpaceTraderSource201`, Palm 1.2.2 at `docs/reference/palm-src/Src`, re-read on 2026-11-17. Shared rules are QST-INDEX §3. Placement: `Moon` is placed randomly 4 times (GAL-037); `MoonRetirement` sits at Utopia (109) (GAL §10.1). The score formula, its display and the high-score table are owned by SCORE.md.
> Status constants: `QuestStatus.Moon` = notStarted 0, bought 1, done 2; `QuestStatus.moonCost = 500000`.

## 1. Buying the moon

- **QST-MOON-001** {M4} [M][W] `Moon` is shown iff `moon == 0 && worth > 400000` (QST-003), where `worth` follows `worthUsesTradeInValue` (RUL-119): Windows list-price worth `Ship.Price + cash − debt` (BNK-004) until the flag lands. (source: StarSystem.cs:223-226; Commander.cs:389-394)
- **QST-MOON-002** {M5} [M] Modern evaluates the threshold with trade-in worth (MOD-019, BNK-006): a commander whose list-price worth exceeds 400000 but whose trade-in worth does not is not offered the moon. (source: PRD §4.3 MOD-019, RUL-119)
- **QST-MOON-003** {M5} [P] Palm shows Moon For Sale iff `!MoonBought && CurrentWorth() >= 400000` (`moonOfferThreshold`, RUL-142; Palm worth BNK-005): worth exactly 400000 qualifies in Palm only. (source: Palm: Src/SystemInfoEvent.c:299)
- **QST-MOON-004** {M4} [M][W][P] `Moon` is a question with price 500000: without acknowledgement `.specialEvent` returns `Confirmation(.acceptSpecialEvent, amounts: [500000])`; with it, `cashToSpend < 500000` is rejected with `insufficientFunds` (no debt check: a commander in debt may buy if the cash suffices). (source: Consts.cs:323; Form_SpaceTrader.cs:3638-3640; Palm: Src/Global.c:500, Src/SpecialEvent.c:82-87)
- **QST-MOON-005** {M4} [M][W][P] Accepting sets `moon = 1`, then `cash -= 500000`, and removes that system's `Moon` event. The app shows ALR-153 (`SpecialMoonBought`) from `specialEventCompleted(.moon)`. (source: Game.cs:2384-2387, :2577-2581; Palm: Src/SpecialEvent.c:89, :190-193)
- **QST-MOON-006** {M4} [M][W][P] While `moon > 0`, worth includes +500000 (BNK-004/005/006), so the purchase leaves worth unchanged under every worth definition. (source: Commander.cs:393; Palm: Src/Money.c:48)
- **QST-MOON-007** {M4} [M][W] The other three `Moon` events stay in their systems but are never shown again (`moon != 0`). The newspaper still prints `.moonForSale(i)` for every reachable system whose event is `Moon` (NEWS-022), whether or not a moon was bought. (source: StarSystem.cs:223-225; Game.cs:3954-3955)

## 2. Retirement (the ending)

- **QST-MOON-008** {M4} [M][W][P] `MoonRetirement` (Utopia) is shown iff `moon == 1`; it is a question with price 0 (confirmation `amounts == [0]`). Declining (not resending) leaves the player docked with nothing changed, and the offer stays available on every later visit. (source: StarSystem.cs:227-228; Consts.cs:324; Form_SpaceTrader.cs:3615-3636; Palm: Src/SystemInfoEvent.c:300, Src/Global.c:499)
- **QST-MOON-009** {M4} [M][W] Accepting sets `moon = 2` and ends the game: `phase = .gameOver(.boughtMoon)`, the event is not removed, no price is charged, and the step returns `[.specialEventCompleted(.moonRetirement), .gameEnded(.boughtMoon)]` (QST-015). (source: Game.cs:2388-2390; GameEndException.cs; Form_SpaceTrader.cs:3646-3649, :2800-2819)
- **QST-MOON-010** {M4} [M][W][P] The ending's score is `GameState.score(for: .boughtMoon)` (SCORE.md: modifier 100 plus the early-retirement day bonus), computed from the state after the handler, so the moon's 500000 is part of the worth. (source: Game.cs:4246-4270; Form_SpaceTrader.cs:2819-2823)
- **QST-MOON-011** {M4} [M][W][P] After the ending every command is rejected with `CommandError.gameOver` and the state no longer changes. (source: Form_SpaceTrader.cs:2802 `SetInGameControlsEnabled(false)`)
- **QST-MOON-012** {M5} [M] Modern only (RUL-006): when `princess == 16` (Princess quest done, QST-PRINCESS) at the moment of retirement, the ending is `.gameOver(.boughtMoonGirl)` with `.gameEnded(.boughtMoonGirl)`; its score equals `score(for: .boughtMoon)`. Windows 2.01 and Palm never produce it (C# never raises `GameEndBoughtMoonGirl`). Flag needed: `moonGirlEnding` (Modern true). (source: PRD §4.3; Enums.cs:411; Form_Alert.cs:560-561)
- **QST-MOON-013** {M5} [P] Palm retirement shows the Utopia screen and then ends the game with status MOON without changing `MoonBought`; the Palm score formula applies (`scoreFormula`, RUL-149). The engine's `moon = 2` is unobservable after the end, so one handler serves both. (source: Palm: Src/SpecialEvent.c:195-200, Src/Traveler.c:2448-2480, :178)

## 3. Scenarios

- **QST-MOON-014** {M4} [M][W] Threshold: at a Moon system with `moon == 0`, worth 400000 → not offered; worth 400001 → offered. (source: StarSystem.cs:224-225)
- **QST-MOON-015** {M4} [M][W] Funds: worth above 400000 but `cashToSpend == 499999` → the acknowledged command is rejected with `insufficientFunds` and nothing changes; with `cashToSpend == 500000` it succeeds and cash drops by exactly 500000. With `reserveMoney` on, the reserved daily costs count against the price (ECO-042). (source: Form_SpaceTrader.cs:3638-3640)
- **QST-MOON-016** {M4} [M][W] Full ending: buy the moon, travel to Utopia, `specialEventAvailable == .moonRetirement`; the unacknowledged command returns the confirmation; the acknowledged one gives `moon == 2`, `phase == .gameOver(.boughtMoon)` and the score of SCORE.md; a following `.warp` is rejected with `gameOver`. (source: Game.cs:2384-2390)
- **QST-MOON-017** {M4} [M][W] Utopia before buying: with `moon == 0`, Utopia offers nothing (`noSpecialEvent`). (source: StarSystem.cs:227-228)
