# BNK: Bank, debt, insurance, daily costs and worth

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2.
> C# paths are relative to `/Users/megatih/Downloads/SpaceTraderSource201`. Palm paths are relative to `docs/reference/palm-src/`.
> **Modern = Windows 2.01 plus the closed MOD list (PRD §4.3).** A Windows quirk that no MOD entry fixes is tagged `[M][W]`.
> All amounts are integer credits (Int32 in C#, `long` (32-bit) on Palm). C# insurance uses `double` arithmetic with a final truncating `(int)` cast. Per MOD-021, Modern keeps that double formula and truncates explicitly.
> `[verify]` marks a statement that could not be confirmed fully from the source.

## 1. Starting state and constants

- **BNK-001** {M2} [M][W][P] A new game starts with cash 1000, debt 0, no insurance and no-claim 0. (source: Commander.cs:35-44; Palm: Src/Traveler.c:1632-1650)
- **BNK-002** {M2} [M][W][P] Constants: `DebtWarning = 75000`, `DebtTooLarge = 100000`, `MaxNoClaim = 90`, insurance rate `0.0025` (Palm `5/2000`), interest rate `0.1` (Palm `/10`), moon value `500000`, Flea conversion cost `500`. (source: Consts.cs:60-64, :77, SpecialEvent.cs:34; Palm: Src/spacetrader.h:236, :390-391, Src/Traveler.c:95-102, Src/Money.c:63, Src/Encounter.c:640-646)
- **BNK-003** {M2} [M][W][P] Debt has no upper bound. Borrowing alone cannot exceed the max loan (≤ 25000), but interest, unpaid fines, unpaid blackmail and the escape-pod charge can push debt past 100000. (source: Commander.cs:79-92, Game.cs:1812, :1892, :2088-2092; Palm: Src/Money.c:55-68, Src/Encounter.c:644, :1909, :2095)

## 2. Commander worth

- **BNK-004** {M2} [W] `Worth = Ship.Price + cash - debt + (QuestStatusMoon > 0 ? 500000 : 0)`, where `Ship.Price` is the ship type's **list price** (not its trade-in value). (source: Commander.cs:389-395, ShipSpec.cs:390-399; research 04 errata #1)
- **BNK-005** {M5} [P] `CurrentWorth = CurrentShipPrice(false) + Credits - Debt + (MoonBought ? 500000 : 0)`, where `CurrentShipPrice(false) = CurrentShipPriceWithoutCargo(false) + Σ BuyingPrice[i]` (the trade-in value plus the cargo purchase prices). (source: Palm: Src/Money.c:46-49, Src/ShipPrice.c:72-110)
- **BNK-006** {M5} [M] MOD-019: Modern worth is `Ship.Worth(false) + cash - debt + (moon bought ? 500000 : 0)`, where `Ship.Worth(false) = BaseWorth(false) + Σ PriceCargo[i]`. It uses the MOD-001 cost-basis resets and the MOD-017 fuel/repair columns. (source: PRD §4.3 MOD-019, Ship.cs:783-790)
- **BNK-007** {M2} [M][W][P] `BaseWorth(forInsurance) = Price * (tribbles > 0 && !forInsurance ? 1 : 3) / 4 - (HullStrength - Hull) * RepairCost - (FuelTanks - Fuel) * FuelCost + Σ (3/4 of each installed weapon, shield and gadget price)`, with integer division at each step. The exact per-ruleset columns, hull and tank values are specified in SHP. (source: Ship.cs:130-151, Equipment.cs:162-167; Palm: Src/ShipPrice.c:72-99, Src/Cargo.c:1120-1123)
- **BNK-008** {M2} [W] Example: on the new-game Gnat (full hull and fuel, one Pulse laser), cash 1000 and debt 0, Worth = `10000 + 1000 = 11000`. (source: Commander.cs:393, Consts.cs:369)
- **BNK-009** {M5} [P] Example: the same new-game state gives CurrentWorth = `10000*3/4 + 2000*3/4 + 1000 = 7500 + 1500 + 1000 = 10000`. (source: Palm: Src/ShipPrice.c:78-95, Src/Cargo.c:1122)
- **BNK-010** {M2} [M][W][P] Worth is a pure function of state and is recomputed whenever it is read (max loan, fines, bribes, blackmail, opponent tries, the moon offer, the score). It is never cached. (source: Commander.cs:389; Palm: Src/Money.c:46)

## 3. Max loan

- **BNK-011** {M2} [M][W][P] `maxLoan = policeRecordScore >= 0 ? min(25000, max(1000, worth / 5000 * 500)) : 500`, with integer division. The `worth` input follows the ruleset (BNK-004/005/006). (source: Form_ViewBank.cs:62-65; Palm: Src/Bank.c:40-44)
- **BNK-012** {M2} [M][W][P] Palm's form `(worth / 10) / 500 * 500` equals C#'s `worth / 5000 * 500` for every 32-bit integer worth, because nested truncating division equals truncating division by the product. One implementation serves all rulesets, and a test sweeps worth values including negatives and multiples of 5000 ± 1. (source: Form_ViewBank.cs:64; Palm: Src/Bank.c:43)
- **BNK-013** {M2} [M][W][P] Examples: worth 11000 gives 1000; worth 123456 gives 12000; worth 4999 or a negative worth gives 1000; worth 260000 gives 25000; police record −1 gives 500 whatever the worth. (source: Form_ViewBank.cs:62-65)
- **BNK-014** {M2} [M][W][P] Max loan is computed at command time. Borrowing and repaying change cash and debt by the same amount, so they leave worth (and therefore max loan) unchanged under all three worth definitions. This matches C#, which computes it once when the bank form opens. (source: Form_ViewBank.cs:62 field initializer; Palm: Src/Bank.c:153, :181)

## 4. Borrowing and repaying

- **BNK-015** {M2} [M][W][P] `borrow(amount)` is rejected with `CommandError.debtTooLargeForLoan` when `debt >= maxLoan`. (source: Form_ViewBank.cs:333-334 `DebtTooLargeLoan`; Palm: Src/Bank.c:153-158 `DebtTooHighAlert`)
- **BNK-016** {M2} [M][W][P] Otherwise `borrow(amount)` accepts `1 <= amount <= maxLoan - debt` and does `cash += amount; debt += amount`. `amount < 1` is rejected with `CommandError.invalidAmount`, and `amount > maxLoan - debt` with `CommandError.exceedsAvailableLoan`. (source: Form_ViewBank.cs:337-341, Form_GetLoan.cs:53 `Maximum = max`, :99-103 `Minimum = 1`; Palm: Src/Bank.c:50-57 clamps to `MaxLoan() - Debt`, so the app offers the clamped maximum)
- **BNK-017** {M2} [M][W][P] `repay(amount)` is rejected with `CommandError.noDebt` when `debt == 0`. (source: Form_ViewBank.cs:351-352 `DebtNone`; Palm: Src/Bank.c:187-192 `NoDebtAlert`)
- **BNK-018** {M2} [M][W][P] Otherwise `repay(amount)` accepts `1 <= amount <= min(debt, cash)` and does `cash -= amount; debt -= amount`. It uses cash, not cash-to-spend. `amount < 1` is rejected with `CommandError.invalidAmount`, and `amount > min(debt, cash)` (including cash 0) with `CommandError.exceedsRepayable`. (source: Form_PayBackLoan.cs:60-62, Form_ViewBank.cs:356-359; Palm: Src/Bank.c:63-71)
- **BNK-019** {M5} [P] Palm's "pay back everything" button calls `PayBack(99999)`, so it repays `min(debt, credits, 99999)`. The Palm preview exposes this as `repayAllAmount`. (source: Palm: Src/Bank.c:214-215)

## 5. Interest

- **BNK-020** {M2} [M][W] `PayInterest`: if `debt > 0`, `interest = max(1, (int)(debt * 0.1))` (double multiply, truncating cast). If `cash > interest` then `cash -= interest`; otherwise `debt += interest - cash` and `cash = 0`. (source: Commander.cs:79-92, Consts.cs:63)
- **BNK-021** {M5} [P] Palm `PayInterest` uses `interest = max(1, debt / 10)` (integer), with the same `credits > interest` branch. (source: Palm: Src/Money.c:55-68)
- **BNK-022** {M2} [M][W][P] For every `0 <= debt < 2^31`, `(int)(debt * 0.1) == debt / 10`. A test proves this over a sweep (1...1,000,000 plus boundary values) so that the three rulesets agree. (source: Commander.cs:83; Palm: Src/Money.c:63)
- **BNK-023** {M2} [M][W][P] Examples: debt 5 gives interest 1; debt 1234 gives 123. With cash 50 and debt 1234, the result is debt 1307 and cash 0. With cash exactly 123 and debt 1234, the result is debt 1234 and cash 0. (source: Commander.cs:84-90; Palm: Src/Money.c:62-67)
- **BNK-024** {M3} [M][W][P] Interest is charged once per normal warp, after departure costs and fuel are deducted and before the day advances. A singularity jump charges no interest. (source: Game.cs:2849-2855, :3184-3188; Palm: Src/Traveler.c:533-567)
- **BNK-025** {M3} [M][W] In jail, after the fine, the remaining debt is reduced by `min(cash, debt)` from cash. If debt is still > 0, `PayInterest` runs `term` times, and only then `IncDays(term)`. (source: Game.cs:294-306)
- **BNK-026** {M5} [P] In jail, Palm runs `Arrival()` and `IncDays(term)` first, then the fine and the ship sale, then sets the record to Dubious, reduces debt by available credits, and calls `PayInterest` `term` times. (source: Palm: Src/Encounter.c:738-781)
- **BNK-027** {M3} [M][W][P] An unpaid police fine (inspection) or pirate blackmail is paid from cash up to the amount owed, and the remainder is added to debt. Formulas are in POL/ENC. (source: Game.cs:1808-1813, :1889-1893; Palm: Src/Encounter.c:1903-1911, :2087-2097)

## 6. Debt limits and blocks

- **BNK-028** {M3} [M][W][P] A warp is blocked with `CommandError.debtTooLargeToTravel` when `debt > 100000` (strictly greater). (source: Game.cs:3155-3156 `DebtTooLargeGrounded`; Palm: Src/Traveler.c:501-505)
- **BNK-029** {M2} [M][W] Buying cargo from the system market is blocked with `CommandError.debtTooLargeToTrade` when `debt > 100000`. Trade-in-orbit purchases and plunder are not blocked by debt. (source: Game.cs:589-590 `op == CargoBuyOp.BuySystem`, `DebtTooLargeTrade`)
- **BNK-030** {M5} [P] Palm `BuyCargo` (the market buy path) is blocked when `debt > 100000`. Palm's trade-in-orbit purchase does not go through `BuyCargo`. Re-checked: the orbit buy (`Src/Encounter.c:1725-1803`) has no debt test. (source: Palm: Src/Cargo.c:858-866, :533-539, Src/Traveler.c:2709)
- **BNK-031** {M2} [M][W][P] Buying equipment is blocked with `CommandError.inDebt` when `debt > 0`. C# checks in this order: gadget already owned, debt, cash-to-spend, free slot. Palm checks: price ≤ 0, debt, to-spend, free slot. (source: Form_Equipment.cs:572-581 `DebtNoBuy`; Palm: Src/Cargo.c:1075-1082 `YoureInDebtAlert`)
- **BNK-032** {M2} [M][W][P] Buying a ship is blocked with `CommandError.inDebt` when `netPrice > 0 && debt > 0`. A ship trade with net price ≤ 0 is allowed while in debt. (source: Commander.cs:124-125; Palm: Src/BuyShipEvent.c:203-205)

## 7. Debt warning and reminder

- **BNK-033** {M3} [M][W][P] `RemindLoans` defaults to true. Palm also resets it to true at every new game. (source: GameOptions.cs:45; Palm: Src/Global.c:672, Src/Traveler.c:1649)
- **BNK-034** {M3} [W] On arrival, `debt >= 75000` emits the `debtWarning` event; **otherwise**, when `debt > 0 && RemindLoans && days % 5 == 0`, it emits `debtReminder(debt)`. The two never fire together. (source: Game.cs:332-340)
- **BNK-035** {M3} [W] The C# debt check is part of every `Arrival()` (after the reactor and tribble checks, before arrival repairs), including the arrival after arrest or the escape pod, and it uses the day count after the departure, jail or pod days. (source: Game.cs:309-331, :3196-3207)
- **BNK-036** {M5} [P] Palm checks `debt >= 75000` (warning) and `debt > 0 && RemindLoans && Days % 5 == 0` (reminder) independently, so both can fire. The check runs only on the normal arrival path in `Travel`, before `Arrival()`, and not after arrest or the escape pod (which call `Arrival()` directly). (source: Palm: Src/Traveler.c:2220-2232, Src/Encounter.c:592, :738)
- **BNK-037** {M5} [M] MOD-018: Modern evaluates the warning and the reminder independently (both can fire) at the C# position in `Arrival()` (BNK-035), and both go into the arrival report. (source: PRD §4.3 MOD-018)

## 8. Insurance

- **BNK-038** {M2} [M][W][P] `buyInsurance` requires an escape pod; without one it is rejected with `CommandError.insuranceRequiresEscapePod`. When already insured it is rejected with `CommandError.insuranceAlreadyActive`. On success `insured = true` and `noClaim = 0`. (source: Form_ViewBank.cs:367-383; Palm: Src/Bank.c:219-229, where noClaim is already 0 whenever uninsured)
- **BNK-039** {M2} [M][W][P] `stopInsurance` is two-phase: without acknowledgement it returns `.confirm(.stopInsurance)` and changes nothing. With acknowledgement it sets `insured = false` and `noClaim = 0`. When not insured it is rejected with `CommandError.insuranceNotActive`. (source: Form_ViewBank.cs:369-375 `InsuranceStop`; Palm: Src/Bank.c:230-240)
- **BNK-040** {M2} [M][W] Daily premium: `insured ? (int)max(1.0, BaseWorth(true) * 0.0025 * (100 - noClaim) / 100) : 0`, evaluated in double from left to right, then truncated. (source: Game.cs:3831-3837, Consts.cs:62)
- **BNK-041** {M5} [P] Palm daily premium: `insured ? max(1, ((W * 5) / 2000) * (100 - min(noClaim, 90)) / 100) : 0`, all integer, with `W = CurrentShipPriceWithoutCargo(true)`. (source: Palm: Src/Traveler.c:95-102)
- **BNK-042** {M2} [M][W][P] Examples: W = 10000, noClaim 0 gives 25 in every ruleset. W = 7999, noClaim 1 gives 19 in C#/Modern (`19.797525` truncated) and 18 in Palm (`(39995/2000 = 19) * 99 / 100 = 18`). Any W ≤ 0 gives 1. (source: Game.cs:3835; Palm: Src/Traveler.c:100-101)
- **BNK-043** {M2} [M][W] `noClaim` is stored clamped to 0...90 (the setter applies `max(0, min(90, value))`). `IncDays(n)` adds n while insured. (source: Commander.cs:333-343, Game.cs:2588-2589)
- **BNK-044** {M5} [P] Palm adds 1 to `noClaim` once per normal warp while insured, after `IncDays(1)` (not on singularity jumps, jail days or pod days). The stored value is not clamped; the premium and display use `min(noClaim, 90)`. (source: Palm: Src/Traveler.c:560-567, :95-102, Src/Bank.c:118)
- **BNK-045** {M5} [P] The Palm bank screen shows "(maximum)" only when `noClaim == 90` exactly, so the label disappears once the stored value passes 90. The Palm preview's `noClaimAtMaximum` follows this. (source: Palm: Src/Bank.c:118-122)
- **BNK-046** {M3} [M][W][P] Arrest cancels insurance (`insured = false`, `noClaim = 0`) before the jail days pass. (source: Game.cs:247-252 `JailInsuranceLost`; Palm: Src/Encounter.c:699-704)
- **BNK-047** {M3} [M][W][P] Using the escape pod: if insured, cash `+= ` the destroyed ship's insurance value (C#/Modern `BaseWorth(true)`, Palm `CurrentShipPriceWithoutCargo(true)`, both excluding cargo and ignoring tribbles). Then the Flea charge applies: `cash > 500 ? cash -= 500 : (debt += 500 - cash; cash = 0)`. Then `IncDays(3)`, then the Flea replaces the ship and insurance ends (`insured = false`, `noClaim = 0`). (source: Game.cs:2079-2101, :735-741; Palm: Src/Encounter.c:631-650, Src/BuyShipEvent.c:108-120)
- **BNK-048** {M5} [P] Palm runs `Arrival()` at the start of the escape-pod sequence, before the payout. (source: Palm: Src/Encounter.c:592)
- **BNK-049** {M2} [M][W] Trading ships: if the old ship has an escape pod and the player transfers it (200 cr), insurance continues. If there is no pod or the transfer is declined or unaffordable, insurance is cancelled (`insured = false`, `noClaim = 0`). (source: Commander.cs:169-173, :194-203, :222-228, Consts.cs:78)
- **BNK-050** {M5} [P] Palm ship trades keep the escape pod and insurance automatically and free (`BuyShip`/`CreateShip` do not touch them). (source: Palm: Src/BuyShipEvent.c:40-82)

## 9. Daily costs and cash to spend

- **BNK-051** {M2} [M][W][P] Current daily costs (for the selected warp target) = mercenaries (CRW-032/033) + insurance premium (BNK-040/041) + interest (`debt > 0 ? max(1, debt/10) : 0`) + wormhole tax (`wormholeExists(current, target) ? 25 * fuelCostColumn : 0`). (source: Game.cs:3338-3343, :3840-3845, :4410-4416; Palm: Src/Traveler.c:636-637, :167-173, :2855-2880)
- **BNK-052** {M2} [W] The wormhole tax uses C#'s `Ship.FuelCost` column (Palm's repair values). (source: Game.cs:4414, research 04 §1)
- **BNK-053** {M5} [M][P] The wormhole tax uses Palm's `CostOfFuel` column (Modern via MOD-017). (source: Palm: Src/Traveler.c:170; PRD §4.3 MOD-017)
- **BNK-054** {M2} [M][W] `cashToSpend = cash - (ReserveMoney ? currentCosts : 0)`, where currentCosts includes interest and the wormhole tax to the selected target. It can be negative. (source: Commander.cs:253-259, Game.cs:3338-3343)
- **BNK-055** {M5} [P] Palm `ToSpend = ReserveMoney ? max(0, credits - mercenaries - insurance) : credits`. It ignores interest and the wormhole tax and is never negative. (source: Palm: Src/Traveler.c:1234-1239)
- **BNK-056** {M2} [M][W][P] `ReserveMoney` defaults to false. Cash-to-spend limits cargo buying caps, equipment, ship purchases (net price plus transfers) and special-event prices. Fuel, repairs and loan repayment use cash. (source: GameOptions.cs:46, Game.cs:574, :602, Form_Equipment.cs:577, Commander.cs:126, :175, Form_SpaceTrader.cs:3639, Form_BuyFuel.cs:59, Form_BuyRepairs.cs:59; Palm: Src/Global.c:653, Src/Cargo.c:325, :880-888, :1079, Src/BuyShipEvent.c:206, Src/SpecialEvent.c:82)
- **BNK-057** {M3} [M][W] Warp affordability, checked in this order before any state change (also for a singularity jump, which then charges nothing): (1) `debt > 100000` → `debtTooLargeToTravel`; (2) `cash < mercenaries` → `cannotPayMercenaries`; (3) `cash < mercenaries + insurance` → `cannotPayInsurance`; (4) `cash < mercenaries + insurance + wormholeTax` → `cannotPayWormholeTax`; then the Wild/no-laser confirmation. Interest is not checked; a shortfall goes to debt (BNK-020). (source: Game.cs:3153-3181)
- **BNK-058** {M5} [P] Palm checks the Wild/no-laser confirmation **first** (accepting removes Wild even if a later check fails), then `debt > 100000`, then `mercenaries > credits`, then (if insured) `insurance + mercenaries > credits`, then `insurance + mercenaries + wormholeTax > credits`. (source: Palm: Src/Traveler.c:483-530)
- **BNK-059** {M3} [M][W][P] On a normal warp the departure deducts `mercenaries + insurance + wormholeTax` from cash, then fuel, then interest, then the day. A singularity jump deducts nothing. (source: Game.cs:2849-2855, :3184-3188; Palm: Src/Traveler.c:533-537, :560-567)

## 10. Previews

- **BNK-060** {M2} [M][W][P] `preview(.bank)` is pure and returns: `debt`, `maxLoan`, `availableToBorrow = max(0, maxLoan - debt)`, `maxRepay = min(debt, cash)`, `insured`, `currentPremium` (BNK-040/041, 0 when uninsured, as the source bank screen shows), `premiumQuote` (the premium if insurance were bought now with noClaim 0), `shipValueForInsurance` (`BaseWorth(true)` or Palm `CurrentShipPriceWithoutCargo(true)`), `noClaimPercent = min(noClaim, 90)`, `noClaimAtMaximum`, and for each of borrow, repay, buy insurance and stop insurance either "allowed" or the typed `CommandError` the command would return. (source: Form_ViewBank.cs:310-325; Palm: Src/Bank.c:76-129)
- **BNK-061** {M2} [M][W][P] `preview(.dailyCosts(target))` is pure and returns `{mercenaries, insurance, interest, wormholeTax, total}` with `total` equal to BNK-051, for the costs breakdown UI (C# FormCosts, Palm Specification form) and the status bar. (source: Form_Costs.cs:61-70, Form_SpaceTrader.cs:3136; Palm: Src/Traveler.c:2855-2880)
- **BNK-062** {M3} [M][W][P] `GameState.warpBlocker()` (for the selected `warpSystem`) returns the first failing check from BNK-057/058 as a `CommandError`, or `nil` (affordable), without changing state. `perform(.warp)` returns the same error as its rejection. (source: Game.cs:3153-3162; Palm: Src/Traveler.c:501-530)
- **BNK-063** {M2} [M][W][P] Bank `CommandError` cases and their C# alerts: `debtTooLargeForLoan` (DebtTooLargeLoan), `noDebt` (DebtNone), `invalidAmount`, `exceedsAvailableLoan`, `exceedsRepayable`, `insuranceRequiresEscapePod` (InsuranceNoEscapePod), `insuranceAlreadyActive`, `insuranceNotActive`, `debtTooLargeToTravel` (DebtTooLargeGrounded), `cannotPayMercenaries` (LeavingIFMercenaries), `cannotPayInsurance` (LeavingIFInsurance), `cannotPayWormholeTax` (LeavingIFWormholeTax), `inDebt` (DebtNoBuy), `debtTooLargeToTrade` (DebtTooLargeTrade). Confirmations: `stopInsurance` (InsuranceStop). Events: `debtWarning` (DebtWarning), `debtReminder(amount)` (DebtReminder), `insurancePaid(amount)` (InsurancePayoff), `insuranceLost` (JailInsuranceLost). The engine emits no strings. (source: Enums.cs:58-64, :136-138, :143, :147-149; PRD §6.2)
