# ECO: Economy (markets, prices, quantities, cargo trading)

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. Tags: `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2. A bullet carries only the tags of rulesets for which the statement holds; differing values get separate bullets.
> Milestones: Windows 2.01 baseline and shared behaviour {M2}; Palm-only and Modern-only variants {M5}; preview/command API {M2}.
> C# sources are relative to `/Users/megatih/Downloads/SpaceTraderSource201`; Palm sources are `docs/reference/palm-src/Src/…`. Every number below was re-read from those lines on 2026-11-16. Items marked [verify] could not be confirmed from source alone.
> Integer arithmetic: `/` is truncating integer division (Swift, C#, C agree). `GetRandom(n)` = uniform `0..n-1`; `GetRandom(a,b)` = uniform `a..b-1` (one RNG draw each; C# `rand.Next`, Palm `SysRandom(0)%n`).

## 1. Reference data

### 1.1 Trade items (Consts.cs:351-363; Palm Global.c:131-143, identical values)

Column order is the C# constructor order (TradeItem.cs:51-69). Tech levels: PreAgricultural=0, Agricultural=1, Medieval=2, Renaissance=3, EarlyIndustrial=4, Industrial=5, PostIndustrial=6, HiTech=7, Unavailable=8 (Enums.cs:827-838).

| # | Item | Tech prod | Tech use | Tech top | Price low tech | Inc / tech | Variance | Pressure hike | Cheap resource | Expensive resource | Orbit min | Orbit max | Round-off |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | Water | PreAg (0) | PreAg (0) | Medieval (2) | 30 | 3 | 4 | Drought | SweetOceans | Desert | 30 | 50 | 1 |
| 1 | Furs | PreAg (0) | PreAg (0) | PreAg (0) | 250 | 10 | 10 | Cold | RichFauna | Lifeless | 230 | 280 | 5 |
| 2 | Food | Agric (1) | PreAg (0) | Agric (1) | 100 | 5 | 5 | CropFailure | RichSoil | PoorSoil | 90 | 160 | 5 |
| 3 | Ore | Medieval (2) | Medieval (2) | Renaissance (3) | 350 | 20 | 10 | War | MineralRich | MineralPoor | 350 | 420 | 10 |
| 4 | Games | Renaissance (3) | Agric (1) | PostInd (6) | 250 | -10 | 5 | Boredom | Artistic | NA | 160 | 270 | 5 |
| 5 | Firearms | Renaissance (3) | Agric (1) | Industrial (5) | 1250 | -75 | 100 | War | Warlike | NA | 600 | 1100 | 25 |
| 6 | Medicine | EarlyInd (4) | Agric (1) | PostInd (6) | 650 | -20 | 10 | Plague | SpecialHerbs | NA | 400 | 700 | 25 |
| 7 | Machines | EarlyInd (4) | Renaissance (3) | Industrial (5) | 900 | -30 | 5 | Employment | NA | NA | 600 | 800 | 25 |
| 8 | Narcotics | Industrial (5) | PreAg (0) | Industrial (5) | 3500 | -125 | 150 | Boredom | WeirdMushrooms | NA | 2000 | 3000 | 50 |
| 9 | Robots | PostInd (6) | EarlyInd (4) | HiTech (7) | 5000 | -150 | 100 | Employment | NA | NA | 3500 | 5000 | 100 |

Name mapping (Palm → C#): `LOTSOFWATER`=SweetOceans, `LOTSOFHERBS`=SpecialHerbs, `LACKOFWORKERS`=Employment; Palm `-1` = C# `NA`.
Enums: SystemPressure None=0, War=1, Plague=2, Drought=3, Boredom=4, Cold=5, CropFailure=6, Employment=7 (Enums.cs:813-823). SpecialResource NA=-1, Nothing=0, MineralRich=1, MineralPoor=2, Desert=3, SweetOceans=4, RichSoil=5, PoorSoil=6, RichFauna=7, Lifeless=8, WeirdMushrooms=9, SpecialHerbs=10, Artistic=11, Warlike=12 (Enums.cs:658-674). Size Tiny=0 … Huge=4 (Enums.cs:582-590). Difficulty Beginner=0 … Impossible=4 (Enums.cs:320-327).

### 1.2 Government columns used by the economy (Consts.cs:175-194; Palm Global.c `Politics`, same values)

| Government | Trader activity | DrugsOk | FirearmsOk | Wanted |
|---|---|---|---|---|
| Anarchy | Minimal (1) | yes | yes | Food |
| Capitalist | Swarms (7) | yes | yes | Ore |
| Communist | Moderate (4) | yes | yes | — |
| Confederacy | Many (5) | yes | yes | Games |
| Corporate | Swarms (7) | yes | yes | Robots |
| Cybernetic | Many (5) | no | no | Ore |
| Democracy | Many (5) | yes | yes | Games |
| Dictatorship | Some (3) | yes | yes | — |
| Fascist | Minimal (1) | no | yes | Machines |
| Feudal | Few (2) | yes | yes | Firearms |
| Military | Abundant (6) | no | yes | Robots |
| Monarchy | Moderate (4) | yes | yes | Medicine |
| Pacifist | Many (5) | yes | no | — |
| Socialist | Some (3) | yes | yes | — |
| Satori | Minimal (1) | no | no | — |
| Technocracy | Abundant (6) | yes | yes | Water |
| Theocracy | Moderate (4) | yes | yes | Narcotics |

### 1.3 Ruleset flags referenced (to be registered in RUL.md)

| Flag | Modern | Windows 2.01 | Palm 1.2.2 | Ref |
|---|---|---|---|---|
| `specialResourceRequiresVisit` | false | true | false | MOD-006 |
| `priceVarianceTwoRolls` | false | false | true | 04 §3 |
| `quantityUsesWrongSystemSize` | false | false | true | 04 §3 |
| `restockUsesOwnSystemItemTraded` | true | false | true | MOD-007 |
| `restockDriftTriangular` | false | false | true | 04 §3 |
| `shuffleStatusBeforeQuantities` | false | false | true | 04 §3 |
| `cashToSpendPalmFormula` | false | false | true | this spec |
| `dumpCapPrecedenceBug` | false | false | true | 04 §3 |
| `tradeableItemPickPalm` | false | false | true | this spec |
| `tradeInOrbitPalmPricing` | false | false | true | 04 §3 |
| `tradeInOrbitMutatesMarketPrices` | false | false | true | 04 §3 |
| `tradeInOrbitCashCapUsesOrbitPrice` | true | false | true | MOD-008 |
| `tradeInOrbitTypedBuyIgnoresFreeBays` | false | false | true | 04 §3 |
| `tradeInOrbitSellCapUsesTotalBays` | false | false | true | 04 §3 |
| `hagglingBonusBeforeDifficulty` | false | false | true | CRW (owner) |
| `recalcSellPricesOnlyIfWasCriminal` | true | false | false | MOD-015 |
| `dumpAllConfirmShowsCostBasis` | false | false | true | this spec |

## 2. Where items trade

- **ECO-001** {M2} [M][W][P] The engine's trade-item table contains exactly the 10 rows of §1.1 in that index order, with every column value as listed; Palm uses the same numbers. (source: Consts.cs:351-363, TradeItem.cs:51-69; Palm: Src/Global.c:131-143)
- **ECO-002** {M2} [M][W][P] An item is illegal iff it is Firearms (5) or Narcotics (8). (source: TradeItem.cs:120-126; Palm: Src/spacetrader.h:102,105)
- **ECO-003** {M2} [M][W][P] `ItemTraded(system, item)` (a market sells it) is true iff `(item != Narcotics || gov.DrugsOk) && (item != Firearms || gov.FirearmsOk) && system.tech >= item.techProduction`. (source: StarSystem.cs:118-123; Palm: Src/Skill.c:RecalculateBuyPrices, Src/Traveler.c:InitializeTradeitems)
- **ECO-004** {M2} [M][W][P] `ItemUsed(system, item)` (a market buys it) is the same test with `item.techUsage` in place of `techProduction`. With the shipped table `techUsage <= techProduction` for every item, so every traded item is also used. (source: StarSystem.cs:125-130; Palm: Src/Traveler.c:StandardPrice)
- **ECO-005** {M2} [W] The special resource used by pricing and quantity formulas is the system's resource only if the system has been visited; otherwise it is `Nothing` (0), which never matches any item's cheap/expensive resource (`NA` = -1 never matches either). Flag `specialResourceRequiresVisit = true`. (source: StarSystem.cs:424-430)
- **ECO-006** {M5} [M][P] Pricing and quantity formulas always use the system's actual special resource, whether or not it has been visited (`specialResourceRequiresVisit = false`). Palm passes `SolarSystem[i].SpecialResources` directly; the Modern fix is MOD-006. (source: PRD MOD-006; Palm: Src/Traveler.c:DeterminePrices, Src/Traveler.c:InitializeTradeitems)
- **ECO-007** {M5} [M] In Modern the resource is still *displayed* only after the system is visited; player-facing previews of unvisited systems (and the Average Price List estimate) use `Nothing` for the resource so no hidden information leaks. (source: PRD MOD-006, PRD §6.6 fairness)

## 3. Standard price

- **ECO-008** {M2} [M][W][P] `StandardPrice(item, system)` returns 0 when `!ItemUsed(system, item)`. (source: TradeItem.cs:87-91; Palm: Src/Traveler.c:StandardPrice)
- **ECO-009** {M2} [M][W][P] Otherwise, using integer arithmetic in exactly this order: `p = priceLowTech + tech*priceInc`; if `gov.Wanted == item` then `p = p*4/3`; `p = p*(100 - 2*gov.traderActivity)/100`; `p = p*(100 - size)/100`; if resource == cheapResource then `p = p*3/4`, else if resource == expensiveResource then `p = p*4/3`. The resource is chosen per ECO-005/ECO-006. (source: TradeItem.cs:93-110; Palm: Src/Traveler.c:StandardPrice)
- **ECO-010** {M2} [M][W][P] With the shipped tables StandardPrice is never negative; Palm's `if (Price < 0) return 0` guard is therefore unobservable and need not be a flag. Worked check: Robots at HiTech (7) give `5000 - 150*7 = 3950` before modifiers. (source: Consts.cs:362; Palm: Src/Traveler.c:StandardPrice)

## 4. Sell prices (CalculatePrices)

- **ECO-011** {M2} [M][W][P] `CalculatePrices(system)` computes, for each item in index order, `p = StandardPrice(item, system)`; if `p > 0` and `item.pressureHike == system.pressure`, then `p = p*3/2` (Palm `(p*3)>>1`, identical for p ≥ 0). (source: Game.cs:534-546; Palm: Src/Traveler.c:DeterminePrices)
- **ECO-012** {M2} [M][W] Variance (when p > 0): `v = min(item.variance, p - 1)`; `p = p + GetRandom(-v, v + 1)`, which is one RNG draw, uniform over `-v..v` in absolute credits (not percent, even though the field comment says "percentage"; kept as designed in Modern, PRD §4.3 #9). Items with p == 0 consume no RNG draw. (source: Game.cs:548-550)
- **ECO-013** {M5} [P] Palm variance: `p = p + GetRandom(V) - GetRandom(V)` (two draws, evaluated left to right, range `-(V-1)..+(V-1)`, triangular, no clamp against p). If the result is ≤ 0, both buy and sell prices are 0 for that item. Flag `priceVarianceTwoRolls`. (source: Palm: Src/Traveler.c:DeterminePrices)
- **ECO-014** {M2} [M][W][P] After variance, if `PoliceRecordScore < -5` (Dubious) then `p = p*90/100` ("criminals pay an intermediary"). The result is the sell price; items with StandardPrice 0 get sell price 0. (source: Game.cs:552-557; Palm: Src/Traveler.c:DeterminePrices)
- **ECO-015** {M2} [M][W][P] CalculatePrices ends by calling RecalculateBuyPrices(system) (ECO-018). (source: Game.cs:558; Palm: Src/Traveler.c:472)
- **ECO-016** {M2} [M][W][P] CalculatePrices runs (a) for the start system at game construction, after the crew list and ships are created; (b) at departure for the destination `WarpSystem`, after the departure system's countdown is set (these are the prices used by trade in orbit); (c) on arrival for the current system, after pressures and quantities are updated; (d) on the cheat direct warp. (source: Game.cs:127, 3190-3194, 3216-3218, 325; Palm: Src/Traveler.c:593, 2439)
- **ECO-017** {M2} [M][W][P] The engine holds one pair of market price arrays (`sell[10]`, `buy[10]`) for the current/destination system, as the source does; they are part of the saved state. (source: Game.cs:4054-4068; Palm: Src/Global.c BuyPrice/SellPrice)

## 5. Buy prices (RecalculateBuyPrices)

- **ECO-018** {M2} [M][W][P] For each item: if `!ItemTraded(system, item)` then `buy = 0`; otherwise `buy = sell`; if `PoliceRecordScore < -5` then `buy = buy*100/90`; then `buy = buy*(103 + 10 - Trader)/100`; finally if `buy <= sell` then `buy = sell + 1`. 10 is MaxSkill. (source: Game.cs:2960-2980; Palm: Src/Skill.c:142-165)
- **ECO-019** {M2} [M][W] `Trader` is the ship's effective trader skill: the best crew Trader skill adjusted for difficulty (minimum 1), plus 1 if the haggling computer is aboard (Jarek delivered), added after the difficulty adjustment. The full skill rules belong to CRW. (source: Ship.cs:1228-1246, Ship.cs:1315-1320, Ship.cs:1088-1094)
- **ECO-020** {M5} [P] Palm adds the Jarek +1 before the difficulty adjustment (`AdaptDifficulty(max + 1)`), so on Impossible a best skill of 1 yields 1 (C# yields 2). Flag `hagglingBonusBeforeDifficulty`; owned by CRW. (source: Palm: Src/Skill.c:117-135, Src/Skill.c:355-363)
- **ECO-021** {M2} [M][W][P] Buy prices (only) are recalculated for the current system whenever the effective Trader skill changes: hiring, firing and random skill changes. Sell prices are not touched. (source: Ship.cs:212-213, Ship.cs:620-621, CrewMember.cs:82-85; Palm: Src/Skill.c:199,237, Src/SystemInfoEvent.c:907)
- **ECO-022** {M2} [M][W][P] With the shipped tables every traded item has sell > 0, so `buy >= sell + 1` always holds for traded items and `buy == 0` exactly for untraded items. (source: Game.cs:2960-2980; Palm: Src/Skill.c:142-165)

## 6. RecalculateSellPrices

- **ECO-023** {M2} [W][P] `RecalculateSellPrices` multiplies every sell price by 100/90 (`sell = sell*100/90`) unconditionally and does **not** recalculate buy prices. C# calls it after Erase Record and after Wild is delivered; Palm only after Erase Record. (source: Game.cs:2985-2989, 2315, 2573; Palm: Src/Skill.c:368-374, Src/SpecialEvent.c:218-221)
- **ECO-024** {M5} [M] Modern applies the ×100/90 only if `PoliceRecordScore < -5` held immediately before the record was reset (flag `recalcSellPricesOnlyIfWasCriminal`, MOD-015). Buy prices are left unchanged as in the source. (source: PRD MOD-015)

## 7. Market quantities (InitializeTradeItems)

- **ECO-025** {M2} [M][W][P] For each item in index order, an item with `!ItemTraded` gets quantity 0 and consumes no RNG draw. (source: StarSystem.cs:86-91; Palm: Src/Traveler.c:385-395)
- **ECO-026** {M2} [M][W] For a traded item: `q = (system.size + 1) * (GetRandom(9, 14) - |item.techTop - system.tech|)`. (source: StarSystem.cs:94-95)
- **ECO-027** {M5} [P] Palm: `q = ((9 + GetRandom(5)) - |item.techTop - system.tech|) * (1 + SolarSystem[i].Size)` where `i` is the **trade-item index**, so the size of system 0..9 is used instead of the system's own size. Flag `quantityUsesWrongSystemSize`. (source: Palm: Src/Traveler.c:397-400)
- **ECO-028** {M2} [M][W][P] For Narcotics and Robots (index ≥ 8): `q = q*(5 - difficulty)/(6 - difficulty) + 1`. (source: StarSystem.cs:97-99; Palm: Src/Traveler.c:402-404)
- **ECO-029** {M2} [M][W][P] Then, as two independent tests: if resource == cheapResource, `q = q*4/3`; if resource == expensiveResource, `q = q*3/4` (Palm `(q*3)>>2`, identical for q ≥ 0). The resource follows ECO-005/ECO-006. (source: StarSystem.cs:101-105; Palm: Src/Traveler.c:406-414)
- **ECO-030** {M2} [M][W][P] Then, if `system.pressure == item.pressureHike`, `q = q/5`. (source: StarSystem.cs:107-108; Palm: Src/Traveler.c:416-418)
- **ECO-031** {M2} [M][W][P] Finally `q = q - GetRandom(10) + GetRandom(10)` (two draws, left to right), clamped to ≥ 0. Per item, the draw order is: base roll (ECO-026/027), then these two. (source: StarSystem.cs:110-113; Palm: Src/Traveler.c:420-424)

## 8. Restock, drift and pressure shuffle

- **ECO-032** {M2} [M][W][P] `CountDownStart = difficulty + 3`. Systems start with countdown 0. (source: Game.cs:3330-3336; Palm: Src/spacetrader.h:466, Src/Traveler.c:1402)
- **ECO-033** {M2} [M][W][P] On every departure (normal warp, wormhole, singularity, and the direct-warp cheat) the system being left gets `CountDown = CountDownStart`. (source: Game.cs:3190, 3216; Palm: Src/Traveler.c:546)
- **ECO-034** {M2} [M][W][P] Pressure shuffle on arrival, per system: `GetRandom(100) < 15` toggles it: a system with no pressure gets a uniform pressure War..Employment (C# `GetRandom(1, 8)`, Palm `1 + GetRandom(7)`); a system with a pressure returns to None. A system draws once for the 15% test and once more only if it gains a pressure. (source: Game.cs:509-512; Palm: Src/Traveler.c:715-728)
- **ECO-035** {M2} [M][W] On arrival, systems are processed in index order, and for each system the pressure shuffle (ECO-034) happens immediately before that system's countdown step (ECO-036). (source: Game.cs:505-532)
- **ECO-036** {M2} [M][W][P] Countdown step for a system with `CountDown > 0`: decrement it; then if `CountDown > CountDownStart` clamp it to CountDownStart (no restock that arrival); else if `CountDown <= 0` call InitializeTradeItems (§7); else apply drift (ECO-037..039). Systems with CountDown 0 are untouched. (source: Game.cs:514-528; Palm: Src/Traveler.c:1192-1206)
- **ECO-037** {M2} [W] Drift: for each item j for which `WarpSystem.ItemTraded(j)` is true (the arrival system, not system i: a port bug), `q = max(0, q + GetRandom(-4, 5))` (uniform −4..4, one draw). Untraded items of system i are skipped, not zeroed. Flag `restockUsesOwnSystemItemTraded = false`. (source: Game.cs:522-526)
- **ECO-038** {M5} [M] Drift tests system i's own `ItemTraded(j)` (MOD-007, `restockUsesOwnSystemItemTraded = true`); otherwise identical to ECO-037 (uniform `GetRandom(-4, 5)`). (source: PRD MOD-007)
- **ECO-039** {M5} [P] Palm drift: items untraded in system i are set to 0 (no draw); traded items get `q = q + GetRandom(5) - GetRandom(5)` (triangular −4..4, two draws), clamped to ≥ 0. Flags `restockUsesOwnSystemItemTraded = true`, `restockDriftTriangular`. (source: Palm: Src/Traveler.c:1207-1224)
- **ECO-040** {M5} [P] Palm runs the pressure shuffle over all systems first and only then the countdown/quantity pass over all systems (flag `shuffleStatusBeforeQuantities`); this changes RNG call order only. (source: Palm: Src/Traveler.c:2434-2439)
- **ECO-041** {M2} [M][W][P] Within the arrival pipeline the market work happens in this order: (W/M) reactor, tribbles, debt, repairs, **pressures and quantities**, Easter egg, **CalculatePrices(current)**; (P) **ShuffleStatus, ChangeQuantities, DeterminePrices(current)**. The full pipeline is owned by TRV. (source: Game.cs:309-330; Palm: Src/Traveler.c:2434-2441)

## 9. Cash to spend and options

- **ECO-042** {M2} [M][W] `CashToSpend = Cash - (Options.ReserveMoney ? InsuranceCosts + InterestCosts + MercenaryCosts + WormholeCosts : 0)`, unclamped (it may be negative). WormholeCosts is evaluated for the currently selected warp system. (source: Commander.cs:253-259, Game.cs:3338-3343, Game.cs:4410-4416)
- **ECO-043** {M5} [P] Palm `ToSpend() = ReserveMoney ? max(0, Credits - MercenaryMoney() - InsuranceMoney()) : Credits`; interest and wormhole tax are not reserved. Flag `cashToSpendPalmFormula`. (source: Palm: Src/Traveler.c:1234-1239)
- **ECO-044** {M2} [M][W][P] Option defaults: ReserveMoney = false, LeaveEmpty = 0; LeaveEmpty accepts 0..99. (source: GameOptions.cs:46-49, Form_Options.cs:287-291; Palm: Src/Global.c:613,653, Src/AppHandleEvent.c:212)

## 10. Buying at a market

- **ECO-045** {M2} [M][W][P] Buy checks, in this order, each producing a typed CommandError: debt > 100000 → `.debtTooLargeToTrade` (AlertType.DebtTooLargeTrade); stock ≤ 0 or buy price ≤ 0 → `.cargoNoneAvailable` (CargoNoneAvailable); `freeBays == 0` → `.noEmptyBays` (CargoNoEmptyBays); `CashToSpend < buyPrice` → `.insufficientFunds` (CargoIF). (source: Game.cs:589-596; Palm: Src/Cargo.c:862-884)
- **ECO-046** {M2} [M][W][P] `freeBays = max(0, Ship.FreeCargoBays - Options.LeaveEmpty)`, where FreeCargoBays = CargoBays − FilledCargoBays as defined in SHP (special cargo such as the Japori medicine and the reactor occupies bays). (source: Game.cs:571, Ship.cs:988-994; Palm: Src/Cargo.c:874,887)
- **ECO-047** {M2} [M][W][P] Maximum purchasable quantity = `min(freeBays, stock, CashToSpend / buyPrice)`. (source: Game.cs:600-602; Palm: Src/Cargo.c:886-888)
- **ECO-048** {M2} [M][W][P] Buying q units: `cargo[i] += q`, `stock[i] -= q`, `Cash -= q*buyPrice`, `PriceCargo[i] += q*buyPrice` (the cost basis is the total paid). (source: Game.cs:614-621; Palm: Src/Cargo.c:890-893)

## 11. Selling and dumping

- **ECO-049** {M2} [M][W][P] Selling checks, in order: nothing held → `.cargoNoneToSell` (CargoNoneToSell); sell price ≤ 0 → the market does not buy the item and the docked sell action becomes Dump (§11, ECO-052). A direct sell command on such an item is rejected with `.marketNotInterested` (CargoNotInterested). (source: Game.cs:676-679, Form_SpaceTrader.cs:2786-2792; Palm: Src/Cargo.c:912-925, 566-575)
- **ECO-050** {M2} [M][W][P] Maximum sell quantity at a market = units held. (source: Game.cs:687; Palm: Src/Cargo.c:937)
- **ECO-051** {M2} [M][W][P] Selling, dumping or jettisoning q of h held units: `PriceCargo[i] = PriceCargo[i]*(h - q)/h` (computed with the pre-sale h), then `cargo[i] -= q`, then `Cash += q*unitPrice` (unitPrice is the sell price, `-dumpCost`, or 0). (source: Game.cs:706-711; Palm: Src/Cargo.c:944-949)
- **ECO-052** {M2} [M][W][P] Dump (docked, item with sell price ≤ 0): cost per unit `5*(difficulty + 1)`; Cash decreases by `q*5*(difficulty + 1)`; no police or news effect. (source: Game.cs:689-693, 711; Palm: Src/Cargo.c:948-949)
- **ECO-053** {M2} [M][W] Dump maximum = `max(0, min(held, CashToSpend / (5*(difficulty + 1))))`; the engine floors at 0 where C# would hand a negative maximum to the dialog. (source: Game.cs:687-692)
- **ECO-054** {M5} [P] Palm caps the dumped amount with `ToSpend() / 5 * (difficulty + 1)` (operator precedence bug: divides by 5 and then multiplies), while the dialog text shows the correct `ToSpend()/(5*(difficulty+1))`. Flag `dumpCapPrecedenceBug`. (source: Palm: Src/Cargo.c:939-942, Src/Cargo.c:114-119)

## 12. Jettison and littering

- **ECO-055** {M2} [M][W][P] Jettison is available only in space (from the plunder screen and when scooping with no room) and costs nothing; maximum = units held. (source: Form_Plunder.cs:577, Game.cs:1486-1491, Game.cs:687; Palm: Src/Encounter.c:389, Src/Cargo.c:716-781)
- **ECO-056** {M2} [M][W][P] The littering confirmation is required iff `!LitterWarning && PoliceRecordScore > -5`. Issuing the warning sets `LitterWarning = true`. LitterWarning resets to false at the start of every trip. (source: Game.cs:682-684, Form_Alert.cs:409-411, Game.cs:3118; Palm: Src/Cargo.c:927-934, Src/Traveler.c:576)
- **ECO-057** {M2} [M][W][P] After jettisoning q > 0 units (ECO-051 with unitPrice 0), one draw `GetRandom(10) < difficulty + 1` decides whether you are caught. If caught: if `PoliceRecordScore > -5` it becomes -5, otherwise it decreases by 1; and a `CaughtLittering` news event is added. (source: Game.cs:713-724; Palm: Src/Cargo.c:950-958)
- **ECO-058** {M5} [P] Palm's "jettison all" button first asks a confirmation that shows the total paid (`BuyingPrice[i]`) for the goods. C# defines `AlertType.EncounterDumpAll` but never raises it. Flag `dumpAllConfirmShowsCostBasis`. (source: Palm: Src/Cargo.c:744-750; C#: Form_Alert.cs:406, no caller)

## 13. Trade in orbit

- **ECO-059** {M2} [M][W][P] A trader who would ignore you rolls `GetRandom(1000) < ChanceOfTradeInOrbit` (default 100). On success: if you have a free bay and the trader `HasTradeableItems`, the encounter becomes TraderSell (the trader sells to you); otherwise, if your ship `HasTradeableItems`, it becomes TraderBuy. The encounter logic is owned by ENC. (source: Game.cs:49, 985-994; Palm: Src/Traveler.c:2062-2073)
- **ECO-060** {M2} [M][W][P] `HasTradeableItems(ship)`: item i qualifies iff `cargo[i] > 0`, it passes the XOR rule (criminals, `score < -5`, trade only illegal goods; non-criminals only legal goods), and the destination price is positive: the system **buy** price when the ship is the trader's, the system **sell** price when it is the commander's. Prices are those computed at departure for the warp system (ECO-016). (source: Ship.cs:570-595; Palm: Src/Cargo.c:199-229)
- **ECO-061** {M2} [M][W] The traded item is picked with `idx = GetRandom(10)`, then advanced `idx = (idx + 1) % 10` until it qualifies (one draw). (source: Ship.cs:505-513)
- **ECO-062** {M5} [P] Palm picks with up to 10 tries of `GetRandom(10)`; if none qualifies it scans sequentially from 0. Flag `tradeableItemPickPalm`. (source: Palm: Src/Cargo.c:234-292)
- **ECO-063** {M2} [M][W] Trader sells to you (TraderSell): `chance = illegal ? 45 : 10`; `adj = GetRandom(100) < chance ? 1.1 : (illegal ? 0.8 : 0.9)`; `price = min(maxTrade, max(minTrade, (int)Math.Round(buy[i]*adj/roundOff)*roundOff))`, where the product and quotient are IEEE-754 double and `Math.Round` is round-half-to-even. (source: Game.cs:576-583)
- **ECO-064** {M2} [M][W] Trader buys from you (TraderBuy): `adj = GetRandom(100) < chance ? (illegal ? 0.8 : 0.9) : 1.1`, applied to `sell[i]` with the same rounding and clamping as ECO-063. (source: Game.cs:665-670)
- **ECO-065** {M2} [M][W] The item pick (ECO-061) and the price roll happen when the player chooses Trade, in that order; the market price arrays are not modified. (source: Game.cs:1502-1515, 576-583, 665-670)
- **ECO-066** {M5} [P] Palm pricing (flag `tradeInOrbitPalmPricing`): thresholds are inclusive (`GetRandom(100) <= 45` / `<= 10`); `price = (long)(price*adj)` (truncated); TraderSell: `price = price/roundOff*roundOff`; TraderBuy: `price = (price/roundOff + 1)*roundOff`; then clamp to [min, max]. (source: Palm: Src/Encounter.c:1640-1661, 1725-1745)
- **ECO-067** {M5} [P] Palm writes the in-orbit price back into the global `BuyPrice[i]`/`SellPrice[i]`, where it persists (and compounds over later trades) until the next DeterminePrices. Flag `tradeInOrbitMutatesMarketPrices`. (source: Palm: Src/Encounter.c:1655-1661, 1740-1745)
- **ECO-068** {M2} [W] Buying from a trader: blocked if you have no free bays (`.noEmptyBays`; LeaveEmpty is ignored) or if `Cash < orbitPrice` (`.insufficientFunds`; Cash, not CashToSpend; no debt check). Maximum = `min(FreeCargoBays, trader.cargo[i], Cash / buy[i])`, using the **system** buy price, so the charge `q*orbitPrice` can drive Cash negative (port bug #10). Effect: `cargo[i] += q`, `trader.cargo[i] -= q`, `Cash -= q*orbitPrice`, `PriceCargo[i] += q*orbitPrice`. (source: Game.cs:563-621, Form_CargoBuy.cs:77-81)
- **ECO-069** {M5} [M] Modern caps buying from a trader at `min(FreeCargoBays, trader.cargo[i], Cash / orbitPrice)`, so Cash never goes negative (MOD-008, `tradeInOrbitCashCapUsesOrbitPrice = true`). Everything else is as in ECO-068. (source: PRD MOD-008)
- **ECO-070** {M5} [P] Palm buying from a trader: a typed amount j is `max(0, min(trader.cargo[i], typed))`, and "All" is `min(trader.cargo[i], free bays)`; both are then capped `j = min(j, Credits / orbitPrice)`. A typed amount is **not** capped by free bays (flags `tradeInOrbitTypedBuyIgnoresFreeBays`, `tradeInOrbitCashCapUsesOrbitPrice = true`). (source: Palm: Src/Encounter.c:1779-1803)
- **ECO-071** {M2} [M][W] Selling to a trader: maximum = `min(held, trader.FreeCargoBays)`; effect as ECO-051 with the in-orbit price; the trader's cargo is not changed. (source: Game.cs:687, 701-711)
- **ECO-072** {M5} [P] Palm selling to a trader caps at `min(held, typed or all, Shiptype[trader.type].CargoBays)` (total bays, not free bays) and then sets `trader.cargo[i] = j` (overwrite). Flag `tradeInOrbitSellCapUsesTotalBays`. (source: Palm: Src/Encounter.c:1697-1715)
- **ECO-073** {M2} [M][W][P] When a trade in orbit changes Cash, a `tradeCompleted(direction, item)` event is emitted (AlertType.EncounterTradeCompleted / OrbitTradeCompletedAlert). Trading 0 units changes nothing and emits nothing. (source: Game.cs:1513-1516; Palm: Src/Encounter.c:1716, 1802)

## 14. Arithmetic fidelity

- **ECO-074** {M2} [M][W][P] Every ECO formula uses integer arithmetic with truncating division in the source's operation order. Floating point appears only in trade-in-orbit pricing (ECO-063/064/066), where it is IEEE-754 binary64 as written, followed by the source's explicit conversion (C# round-half-even; Palm truncation). (source: Game.cs:534-728; Palm: Src/Encounter.c:1640-1745)
- **ECO-075** {M5} [M] Modern keeps the exact integer price and quantity arithmetic of Windows 2.01 (MOD-021); no Modern formula may substitute floating point or rounding where the source truncates. (source: PRD MOD-021)
- **ECO-076** {M2} [M][W][P] Invariants after every ECO command: every stock and cargo quantity ≥ 0; filled bays ≤ total bays (except Palm ECO-070, which is documented as a flag-guarded quirk); `PriceCargo[i] == 0` whenever `cargo[i] == 0` after a sale of the whole lot. (source: Game.cs:706-711; Palm: Src/Cargo.c:944-946)

## 15. Commands and pure previews (engine API)

- **ECO-077** {M2} [M][W][P] `preview(.market)` is pure and returns, per item: buy price, sell price, stock, units held, cost basis per unit `PriceCargo[i]/held` (0 when nothing is held), maximum buy quantity (ECO-047, 0 when blocked), maximum sell quantity, and the docked sell mode (`.sell` or `.dump` with its unit cost). (source: Game.cs:561-728, Form_CargoSell.cs:62; Palm: Src/Cargo.c:83-196, 299-356)
- **ECO-078** {M2} [M][W][P] `preview(.buyCargo(item))` returns either `{unitPrice, maxQuantity}` or the first blocking CommandError in ECO-045 order. `perform(.buyCargo(item, quantity))` uses the same function: quantity must be `1...maxQuantity`, else `.invalidQuantity`, and a blocked buy is rejected with the same error with no state change. A `.max` quantity means maxQuantity. (source: Game.cs:589-621; Palm: Src/Cargo.c:858-901)
- **ECO-079** {M2} [M][W][P] `preview(.sellCargo(item))` returns `{mode, unitPrice or unitCost, maxQuantity, costBasisPerUnit, profitPerUnit}` or `.cargoNoneToSell`; `perform(.sellCargo(item, q))` and `perform(.dumpCargo(item, q))` validate q against the previewed maximum. (source: Game.cs:655-711; Palm: Src/Cargo.c:908-949)
- **ECO-080** {M2} [M][W][P] `perform(.jettison(item, q))` without the `.litteringWarning` acknowledgement, when ECO-056 requires the warning, returns `.confirm(.litteringWarning)` and changes no state. With the acknowledgement it sets LitterWarning and jettisons. Deviation: declining leaves LitterWarning false, so the warning can reappear in the same trip (the source sets the flag even on decline; this affects prompts only, never rules). (source: Game.cs:682-684, Form_Alert.cs:409-411; Palm: Src/Cargo.c:927-934)
- **ECO-081** {M2} [M][W][P] Trade in orbit is a `PendingDecision.tradeInOrbit {direction, item, unitPrice, maxQuantity, unitsAvailable, costBasisPerUnit}` created when the player chooses Trade (after the RNG draws of ECO-065/ECO-066). `preview` reads it without RNG; `perform(.resolveTradeInOrbit(quantity))` accepts `0...maxQuantity` (0 declines). The unitPrice shown is the price actually charged (C# shows the system buy price in its buy dialog; that display quirk is not reproduced). (source: Game.cs:1502-1515, Form_CargoBuy.cs:83-84; Palm: Src/Encounter.c:1636-1803)
- **ECO-082** {M2} [M][W][P] `preview(.priceBreakdown(item))` for the current system returns the deterministic components of the sell price (base, wanted, trader activity, size, displayed resource, pressure hike, criminal factor), the residual "market fluctuation" (actual sell price minus the deterministic value), and the buy-price markup from trader skill. It uses only information visible to the player (PRD §6.6). (source: TradeItem.cs:87-114, Game.cs:534-559, Game.cs:2960-2980)
- **ECO-083** {M2} [M][W][P] ECO CommandErrors map one-to-one to source alerts: `.debtTooLargeToTrade`=DebtTooLargeTrade, `.cargoNoneAvailable`=CargoNoneAvailable, `.noEmptyBays`=CargoNoEmptyBays, `.insufficientFunds`=CargoIF, `.cargoNoneToSell`=CargoNoneToSell, `.marketNotInterested`=CargoNotInterested; the littering warning is the Confirmation `.litteringWarning`=EncounterDumpWarning. ALR owns the full mapping. (source: Game.cs:589-596, 676-684; Palm: Src/Cargo.c:862-934)
