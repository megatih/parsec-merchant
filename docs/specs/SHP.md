# SHP: Ships, equipment and shipyard services

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. Tags: `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2. A bullet carries only the tags of rulesets for which the statement holds; differing values get separate bullets.
> Milestones: Windows 2.01 baseline and shared behaviour {M2}; Palm-only and Modern-only variants {M5}; preview/command API {M2}.
> C# sources are relative to `/Users/megatih/Downloads/SpaceTraderSource201`; Palm sources are `docs/reference/palm-src/Src/…`. Every number below was re-read from those lines on 2026-11-16. Items marked [verify] could not be confirmed from source alone.
> `CashToSpend`/`ToSpend()` are defined in ECO-042/ECO-043. `Trader` is the effective trader skill (ECO-019/ECO-020, owned by CRW). Integer `/` truncates.

## 1. Reference data

### 1.1 Ship types (C# Consts.cs:249-267; constructor order ShipSpec.cs:56-77)

Columns as in the C# constructor. **FC** is the C# `fuelCost` field (credits per parsec of fuel) and **RC** the C# `repairCost` field (credits per hull point). The C# port swapped these two columns relative to Palm (PRD MOD-017): C# FC holds Palm's `RepairCosts` values and C# RC holds Palm's `CostOfFuel` values. Activity: Absent=0, Minimal=1, Few=2, Some=3, Moderate=4, Many=5, Abundant=6, Swarms=7, NA=100 (Enums.cs:224-235). Police/Pirates/Traders give the minimum government activity at which the type appears as that opponent.

| # | Type | Size | Bays | W | S | G | Crew | Fuel tanks | FC (C#) | Hull | RC (C#) | Price | Occur % | Police | Pirates | Traders | Min tech |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | Flea | Tiny | 10 | 0 | 0 | 0 | 1 | 20 | 1 | 25 | 1 | 2000 | 2 | NA | NA | Absent | EarlyIndustrial |
| 1 | Gnat | Small | 15 | 1 | 0 | 1 | 1 | 14 | 1 | 100 | 2 | 10000 | 28 | Absent | Absent | Absent | Industrial |
| 2 | Firefly | Small | 20 | 1 | 1 | 1 | 1 | 17 | 1 | 100 | 3 | 25000 | 20 | Absent | Absent | Absent | Industrial |
| 3 | Mosquito | Small | 15 | 2 | 1 | 1 | 1 | 13 | 1 | 100 | 5 | 30000 | 20 | Absent | Minimal | Absent | Industrial |
| 4 | Bumblebee | Medium | 25 | 1 | 2 | 2 | 2 | 15 | 1 | 100 | 7 | 60000 | 15 | Minimal | Minimal | Absent | Industrial |
| 5 | Beetle | Medium | 50 | 0 | 1 | 1 | 3 | 14 | 1 | 50 | 10 | 80000 | 3 | NA | NA | Absent | Industrial |
| 6 | Hornet | Large | 20 | 3 | 2 | 1 | 2 | 16 | 2 | 150 | 15 | 100000 | 6 | Few | Some | Minimal | PostIndustrial |
| 7 | Grasshopper | Large | 30 | 2 | 2 | 3 | 3 | 15 | 3 | 150 | 15 | 150000 | 2 | Some | Moderate | Few | PostIndustrial |
| 8 | Termite | Huge | 60 | 1 | 3 | 2 | 3 | 13 | 4 | 200 | 20 | 225000 | 2 | Moderate | Many | Some | HiTech |
| 9 | Wasp | Huge | 35 | 3 | 2 | 2 | 3 | 14 | 5 | 200 | 20 | 300000 | 2 | Many | Abundant | Moderate | HiTech |
| 10 | SpaceMonster | Huge | 0 | 3 | 0 | 0 | 1 | 1 | 1 | 500 | 1 | 500000 | 0 | NA | NA | NA | Unavailable |
| 11 | Dragonfly | Small | 0 | 2 | 3 | 2 | 1 | 1 | 1 | 10 | 1 | 500000 | 0 | NA | NA | NA | Unavailable |
| 12 | Mantis | Medium | 0 | 3 | 1 | 3 | 3 | 1 | 1 | 300 | 1 | 500000 | 0 | NA | NA | NA | Unavailable |
| 13 | Scarab | Large | 20 | 2 | 0 | 0 | 2 | 1 | 1 | 400 | 1 | 500000 | 0 | NA | NA | NA | Unavailable |
| 14 | Bottle | Small | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 10 | 1 | 100 | 0 | NA | NA | NA | Unavailable |
| 15 | Custom | Huge | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | NA | NA | NA | Unavailable |
| 16 | Scorpion | Huge | 30 | 2 | 2 | 2 | 2 | 1 | 1 | 300 | 1 | 500000 | 0 | NA | NA | NA | Unavailable |

### 1.2 Palm 1.2.2 ship columns (Palm Global.c:186-204; field order DataTypes.h:92-111)

Palm has rows 0..14 only (no Custom, no Scorpion). Its other columns equal the C# table (Palm `-1` = NA, tech `8` = Unavailable, size as the last field). Palm-only and swapped columns:

| # | Type | CostOfFuel (per parsec) | RepairCosts (per hull pt) | Bounty (unused) |
|---|---|---|---|---|
| 0 | Flea | 1 | 1 | 5 |
| 1 | Gnat | 2 | 1 | 50 |
| 2 | Firefly | 3 | 1 | 75 |
| 3 | Mosquito | 5 | 1 | 100 |
| 4 | Bumblebee | 7 | 1 | 125 |
| 5 | Beetle | 10 | 1 | 50 |
| 6 | Hornet | 15 | 2 | 200 |
| 7 | Grasshopper | 15 | 3 | 300 |
| 8 | Termite | 20 | 4 | 300 |
| 9 | Wasp | 20 | 5 | 500 |
| 10 | Space monster | 1 | 1 | 0 |
| 11 | Dragonfly | 1 | 1 | 0 |
| 12 | Mantis | 1 | 1 | 0 |
| 13 | Scarab | 1 | 1 | 0 |
| 14 | Bottle | 1 | 1 | 0 |

### 1.3 Weapons, shields, gadgets (C# Consts.cs:145-155, 213-219, 367-375; Palm Global.c:207-237, spacetrader.h:118-150)

| Weapon | Power | Disabling | Price | Min tech | Chance | Rulesets |
|---|---|---|---|---|---|---|
| Pulse laser | 15 | no | 2000 | Industrial (5) | 50 | M W P |
| Beam laser | 25 | no | 12500 | PostIndustrial (6) | 35 | M W P |
| Military laser | 35 | no | 35000 | HiTech (7) | 15 | M W P |
| Morgan's laser | 85 | no | 50000 | Unavailable (8) | 0 | M W P |
| Photon disruptor | 20 | yes | 15000 | PostIndustrial (6) | 0 | M W |
| Quantum disruptor | 60 | yes | 50000 | Unavailable (8) | 0 | M W |

| Shield | Power | Price | Min tech | Chance | Rulesets |
|---|---|---|---|---|---|
| Energy | 100 | 5000 | Industrial (5) | 70 | M W P |
| Reflective | 200 | 20000 | PostIndustrial (6) | 30 | M W P |
| Lightning | 350 | 45000 | Unavailable (8) | 0 | M W P |

| Gadget | Skill bonus (C#) | Price | Min tech | Chance | Rulesets |
|---|---|---|---|---|---|
| Extra cargo bays (+5) | — | 2500 | EarlyIndustrial (4) | 35 | M W P |
| Auto-repair system | Engineer | 7500 | Industrial (5) | 20 | M W P |
| Navigating system | Pilot | 15000 | PostIndustrial (6) | 20 | M W P |
| Targeting system | Fighter | 25000 | PostIndustrial (6) | 20 | M W P |
| Cloaking device | Pilot | 100000 | HiTech (7) | 5 | M W P |
| Fuel compactor | — | 30000 | Unavailable (8) | 0 | M W P |
| Hidden cargo bays (+5) | — | 60000 | Unavailable (8) | 0 | M W |

### 1.4 Derived equipment prices (base price ×3/4 and C# transfer price ×110/90)

| Item | Sell price (base×3/4) | C# transfer price (sell×110/90) | Palm transfer price |
|---|---|---|---|
| Pulse laser | 1500 | — | — |
| Beam laser | 9375 | — | — |
| Military laser | 26250 | — | — |
| Morgan's laser | 37500 | 45833 | 33333 |
| Photon disruptor | 11250 | — | — |
| Quantum disruptor | 37500 | 45833 | — |
| Energy shield | 3750 | — | — |
| Reflective shield | 15000 | — | — |
| Lightning shield | 33750 | 41250 | 30000 |
| Extra cargo bays | 1875 | — | — |
| Auto-repair system | 5625 | — | — |
| Navigating system | 11250 | — | — |
| Targeting system | 18750 | — | — |
| Cloaking device | 75000 | — | — |
| Fuel compactor | 22500 | 27500 | 20000 |
| Hidden cargo bays | 45000 | 55000 | — |
| Escape pod | — | 200 | free (kept) |

### 1.5 Custom shipyard tables (Shipyard.cs:37-77), index = Size Tiny..Gargantuan

| Constant | Tiny | Small | Medium | Large | Huge | Gargantuan |
|---|---|---|---|---|---|---|
| COST_FUEL | 1 | 1 | 1 | 3 | 5 | 10 |
| COST_HULL | 1 | 5 | 10 | 15 | 20 | 40 |
| BASE_FUEL | 15 | 14 | 13 | 12 | 11 | 10 |
| BASE_HULL | 10 | 25 | 50 | 100 | 150 | 200 |
| DESIGN_FEE | 2000 | 5000 | 10000 | 20000 | 40000 | 100000 |
| MAX_UNITS | 50 | 100 | 150 | 200 | 250 | 999 |
| PER_UNIT_FUEL | 3 | 2 | 1 | 1 | 1 | 1 |
| PER_UNIT_HULL | 35 | 30 | 25 | 20 | 15 | 10 |
| PRICE_PER_UNIT | 75 | 250 | 500 | 750 | 1000 | 1200 |
| UNITS_CREW | 20 | 20 | 20 | 20 | 20 | 20 |
| UNITS_FUEL | 1 | 1 | 1 | 5 | 10 | 15 |
| UNITS_GADGET | 5 | 5 | 5 | 5 | 5 | 5 |
| UNITS_HULL | 1 | 2 | 3 | 4 | 5 | 6 |
| UNITS_SHIELD | 10 | 10 | 10 | 8 | 8 | 8 |
| UNITS_WEAPON | 15 | 15 | 15 | 10 | 10 | 10 |

Scalars: ADJUST_SIZE_DEFAULT 100, ADJUST_SIZE_SPECIALTY 90, ADJUST_SIZE_WEAKNESS 110; ADJUST_SKILL_CREW 2, _FUEL 2, _HULL 5, _SHIELD 2, _WEAPON 2; PENALTY_FIRST_PCT 80 / PENALTY_FIRST_FEE 25; PENALTY_SECOND_PCT 90 / PENALTY_SECOND_FEE 75.

| Shipyard (id) | Specialty size | Skill | Effect |
|---|---|---|---|
| Corellian (0) | Large | CrewQuarters | crew quarter costs 2 fewer units |
| Incom (1) | Medium | ShieldSlotUnits | shield slot costs 2 fewer units |
| Kuat (2) | Huge | HullPerUnit | 5 more hull points per unit |
| Sienar (3) | Tiny | WeaponSlotUnits | weapon slot costs 2 fewer units |
| Sorosuub (4) | Small | FuelBase | base fuel is 2 greater |

(Consts.cs:272-279, Enums.cs:559-578, Shipyard.cs:93-118)

### 1.6 Ruleset flags and content referenced (to be registered in RUL.md)

| Flag / content | Modern | Windows 2.01 | Palm 1.2.2 | Ref |
|---|---|---|---|---|
| table `shipSpecs` fuel/repair columns | Palm values | C# values | Palm values | MOD-017 |
| `worthUsesTradeInValue` | true | false | true | MOD-019 |
| `shipTraderDiscount` | false | false | true | 04 §3 |
| `uniqueTransferFixedPrices` | false | false | true | 04 §3 |
| `escapePodKeptOnShipTrade` | false | false | true | 04 §1 |
| `escapePodPurchaseUsesToSpend` | false | false | true | this spec |
| `resetPriceCargoOnHoldClear` | true | false | true | MOD-001 |
| `fuelCompactorSetsTanks` | false (+3) | false (+3) | true (18) | 04 §1 |
| `palmShipTradeChecks` | false | false | true | this spec |
| `transferredShieldUncharged` | false | false | true | 04 §3 |
| `worthFuelTermUsesBaseTanks` | false | false | true | this spec |
| `arrivalAutoBuyPartial` | false | false | true | 04 §3 (owner TRV) |
| content `hasDisruptors` | yes | yes | no | PRD §4.4 |
| content `hasHiddenBays` | yes | yes | no | PRD §4.4 |
| content `customShipyard` | yes | yes | no | PRD §4.4 |

## 2. Ship and equipment data

- **SHP-001** {M2} [W] The Windows ship table has the 17 rows of §1.1 in index order with every column value as listed, including FC = (1,1,1,1,1,1,2,3,4,5,1,1,1,1,1,0,1) and RC = (1,2,3,5,7,10,15,15,20,20,1,1,1,1,1,0,1). (source: Consts.cs:249-267, ShipSpec.cs:56-77)
- **SHP-002** {M5} [M] The Modern ship table equals SHP-001 except that rows 0..14 use Palm's columns: fuel cost per parsec = (1,2,3,5,7,10,15,15,20,20,1,1,1,1,1) and repair cost per hull point = (1,1,1,1,1,1,2,3,4,5,1,1,1,1,1); Scorpion keeps 1/1 and Custom takes its costs from the designer (SHP-071). The wormhole tax follows the fuel cost (TRV). (source: PRD MOD-017; Palm: Src/Global.c:186-204)
- **SHP-003** {M5} [P] The Palm ship table has rows 0..14 only, with the columns of §1.2: fuel cost per parsec = `CostOfFuel` and repair cost = `RepairCosts`; the `Bounty` column is carried but unused. (source: Palm: Src/Global.c:186-204, Src/DataTypes.h:92-111)
- **SHP-004** {M2} [M][W][P] Only types 0..9 (Flea..Wasp) can be bought from the ship list (C# `MaxShip = 9`, ten buy buttons; Palm `MAXSHIPTYPE 10`). (source: Consts.cs:75, Form_ShipList.cs:916-933; Palm: Src/spacetrader.h:109, Src/BuyShipEvent.c:88-104)
- **SHP-005** {M2} [M][W] Weapons, shields and gadgets are exactly the rows of §1.3 marked M/W, in that index order. (source: Consts.cs:145-155, 213-219, 367-375)
- **SHP-006** {M5} [P] Palm has 4 weapons (no disruptors), the same 3 shields and 6 gadgets (no hidden cargo bays), with the values of §1.3. (source: Palm: Src/Global.c:207-237, Src/spacetrader.h:116-145)
- **SHP-007** {M2} [M][W] Equipment for sale, in display order: Pulse, Beam, Military, Photon disruptor; Energy, Reflective; Extra bays, Auto-repair, Navigating, Targeting, Cloaking. Morgan's laser, Quantum disruptor, Lightning shield, Fuel compactor and Hidden bays are never for sale. (source: Consts.cs:379-392)
- **SHP-008** {M5} [P] Palm sells weapons 0..2, shields 0..1 and gadgets 0..4 (the C# list minus the Photon disruptor). (source: Palm: Src/BuyEquipEvent.c:121-156, Src/spacetrader.h:116,127,139)
- **SHP-009** {M2} [M][W] Each gadget with a skill bonus adds `SkillBonus = 3` to that skill: Auto-repair → Engineer, Navigating → Pilot, Targeting → Fighter, Cloaking → Pilot. `CloakBonus = 2` is defined but unused. Effective skills are owned by CRW. (source: Consts.cs:66-67, 147-151, Ship.cs:1240-1243)
- **SHP-010** {M5} [P] Palm gives the cloaking device +2 Pilot (`CLOAKBONUS`) instead of +3; the other gadget bonuses are +3. Owned by CRW. (source: Palm: Src/spacetrader.h:149-150, Src/Skill.c:305-330)

## 3. Equipment prices and tech gating

- **SHP-011** {M2} [M][W][P] Equipment buy price = `basePrice*(100 - Trader)/100` if `system.tech >= item.minTech`, else 0, and a price of 0 means "not sold here". (source: Equipment.cs:148-160; Palm: Src/Cargo.c:1111-1115, Src/spacetrader.h:450-452)
- **SHP-012** {M2} [M][W][P] Equipment sell price = `basePrice*3/4`, independent of tech level and skill (values in §1.4). (source: Equipment.cs:162-168; Palm: Src/Cargo.c:1120-1123, Src/spacetrader.h:454-456)
- **SHP-013** {M2} [M][W] Equipment transfer price (to a newly bought ship) = `SellPrice*110/90` (values in §1.4). (source: Equipment.cs:178-185)

## 4. Slots and capacity

- **SHP-014** {M2} [M][W][P] A ship has as many weapon, shield, gadget and crew slots as its spec gives. Adding equipment fills the first empty slot of its type; removing slot k shifts the higher slots down by one and empties the last. (source: Ship.cs:117-128, 696-704, 755-765; Palm: Src/Cargo.c:1068-1105, Src/SellEquipEvent.c:72-110)
- **SHP-015** {M2} [M][W][P] Total cargo bays = spec bays + 5 per Extra cargo bays + 5 per Hidden cargo bays (Hidden bays exist only in M/W). Filled bays = Σcargo + 10 while the Japori medicine is in transit + `5 + 10 - (reactorStatus - 1)/2` while the reactor is aboard; free bays = total − filled. Palm subtracts the same special amounts from the total instead, which gives the same free bays. (source: Ship.cs:830-843, 934-994; Palm: Src/Cargo.c:1016-1048)
- **SHP-016** {M2} [M][W] Fuel tank capacity = spec tanks + 3 if a fuel compactor is installed (`FuelCompactorTanks = 3`). (source: Consts.cs:73, Ship.cs:1072-1078)
- **SHP-017** {M5} [P] Palm tank capacity = 18 if a fuel compactor is installed, else spec tanks (a downgrade for the 20-tank Flea); usable fuel = `min(Ship.Fuel, capacity)`. Flag `fuelCompactorSetsTanks`. (source: Palm: Src/Fuel.c:50-62)
- **SHP-018** {M2} [M][W] Hull strength = spec hull + 50 (`HullUpgrade`) if the ship's `hullUpgraded` flag is set; the flag is set only by the Scarab quest reward and a newly built ship never has it. (source: Consts.cs:74, ShipSpec.cs:282-288, Game.cs:2486-2489, Ship.cs:755-765)
- **SHP-019** {M5} [P] Palm hull strength = spec hull + 50 (`UPGRADEDHULL`) while `ScarabStatus == 3`; it is not stored on the ship. (source: Palm: Src/Shipyard.c:117-123, Src/spacetrader.h:136)

## 5. Buying and selling equipment

- **SHP-020** {M2} [M][W] Equipment buy checks, in this order: a gadget already installed (any gadget except Extra cargo bays) → `.equipmentAlreadyOwned` (EquipmentAlreadyOwn); `Debt > 0` → `.inDebt` (DebtNoBuy); `price > CashToSpend` → `.insufficientFunds` (EquipmentIF); no free slot of that type → `.noFreeSlot` (EquipmentNotEnoughSlots); otherwise a confirmation `.buyEquipment(item, price)` (EquipmentBuy). (source: Form_Equipment.cs:565-595)
- **SHP-021** {M5} [P] Palm order: a gadget already installed (except Extra bays) → already owned (NoMoreOfItemAlert); `price <= 0` → not sold; `Debt > 0` → in debt; `price > ToSpend()` → can't afford; no free slot → no slot; then confirm. Only the order of the first error differs from SHP-020 (for example a Palm player in debt trying an unsold item sees "not sold"). (source: Palm: Src/BuyEquipEvent.c:144-155, Src/Cargo.c:1068-1105)
- **SHP-022** {M2} [M][W][P] Weapons and shields may be installed more than once (only gadgets have the already-owned test); Extra cargo bays may be stacked up to the gadget slot count. (source: Form_Equipment.cs:572-574; Palm: Src/BuyEquipEvent.c:144-146)
- **SHP-023** {M2} [M][W][P] Buying installs the item in the first free slot and `Cash -= price`. A newly bought C# shield is at full charge; a Palm shield gets its charge at the next departure recharge, which is not observable before any encounter. (source: Form_Equipment.cs:588-590, Shield.cs:42-48; Palm: Src/Cargo.c:1098-1100, Src/Traveler.c:538-543)
- **SHP-024** {M2} [M][W][P] Selling any installed item (including the unbuyable unique items) asks a confirmation (EquipmentSell), then `Cash += SellPrice` and removes it with the slot shift of SHP-014. (source: Form_Equipment.cs:606-633; Palm: Src/SellEquipEvent.c:58-118)
- **SHP-025** {M2} [M][W] Selling Extra or Hidden cargo bays is refused with `.extraBaysInUse` (EquipmentExtraBaysInUse) when `FreeCargoBays < 5`. (source: Form_Equipment.cs:617-624)
- **SHP-026** {M5} [P] Palm refuses selling Extra bays when `FilledCargoBays() > TotalCargoBays() - 5` (CargoBaysFullAlert), equivalent to free bays < 5. (source: Palm: Src/SellEquipEvent.c:95-101)

## 6. Ship value and worth

- **SHP-027** {M2} [M][W] `BaseWorth(forInsurance) = spec.Price*(tribbles > 0 && !forInsurance ? 1 : 3)/4 - (HullStrength - Hull)*RepairCost - (FuelTanks - Fuel)*FuelCost + Σ SellPrice of every installed weapon, shield and gadget`, using the ship's own cost columns (SHP-001/002) and the compactor-adjusted tank count. (source: Ship.cs:130-152)
- **SHP-028** {M2} [M][W] `Worth(forInsurance) = BaseWorth(forInsurance) + Σ Commander.PriceCargo[i]` over all 10 items (the trade-in value). (source: Ship.cs:783-790)
- **SHP-029** {M5} [P] Palm `CurrentShipPriceWithoutCargo(forInsurance) = (Price*(tribbles > 0 && !forInsurance ? 1 : 3))/4 - (GetHullStrength() - Hull)*RepairCosts - (Shiptype.FuelTanks - GetFuel())*CostOfFuel + Σ base×3/4 of installed equipment`. The fuel term uses the **spec** tank count, so with a compactor (18 tanks) on a ship with fewer spec tanks and more than that fuel, the term is negative and adds value. Flag `worthFuelTermUsesBaseTanks`. (source: Palm: Src/ShipPrice.c:72-97, Src/Fuel.c:59-62)
- **SHP-030** {M5} [P] Palm `CurrentShipPrice(forInsurance) = CurrentShipPriceWithoutCargo(forInsurance) + Σ BuyingPrice[i]`. (source: Palm: Src/ShipPrice.c:102-111)
- **SHP-031** {M2} [W] Commander worth = `Ship.Price` (the spec list price) `+ Cash - Debt + (QuestStatusMoon > 0 ? 500000 : 0)`. Example: the starting Gnat with one pulse laser and 1000 cr gives 11000. Flag `worthUsesTradeInValue = false`. (source: Commander.cs:389-395)
- **SHP-032** {M5} [M][P] Commander worth = trade-in value (`Worth(false)` / `CurrentShipPrice(false)`) `+ Cash - Debt + 500000 if the moon was bought`. Example: the starting Gnat with one pulse laser and 1000 cr gives `7500 + 1500 + 1000 = 10000`. Flag `worthUsesTradeInValue = true` (MOD-019). It feeds loans, fines, bribes, opponent strength, the moon offer and the score. (source: PRD MOD-019; Palm: Src/Money.c:46-49)

## 7. Ship availability and price

- **SHP-033** {M2} [M][W][P] Ship type i (0..9) is offered iff `spec.minTech <= system.tech` and `i != current ship type`; otherwise it shows "not sold" (tech) or "got one" (same type). Below EarlyIndustrial no ship is offered. (source: Form_ShipList.cs:916-933, Form_SpaceTrader.cs:3096-3101; Palm: Src/BuyShipEvent.c:88-104, 128-136)
- **SHP-034** {M2} [M][W] Net price = `spec.Price - Ship.Worth(false)` with no trader discount; it may be negative (the trader pays you). Example: new Gnat with one pulse laser, no cargo, buying a Firefly: `25000 - 9000 = 16000`. (source: Form_ShipList.cs:930)
- **SHP-035** {M5} [P] Palm net price = `Price*(100 - Trader)/100 - CurrentShipPrice(false)`, and a result of exactly 0 becomes 1. Example (Trader 5): Firefly from the starting Gnat `23750 - 9000 = 14750`. Flag `shipTraderDiscount`. (source: Palm: Src/BuyShipEvent.c:88-104, Src/spacetrader.h:453)

## 8. Trading in a ship (TradeShip)

- **SHP-036** {M2} [M][W] TradeShip checks, in order: `netPrice > 0 && Debt > 0` → `.inDebt` (DebtNoBuy); `netPrice > CashToSpend` → `.insufficientFunds` (ShipBuyIF); `newSpec.crewQuarters < SpecialCrew.count` → `.passengersNeedQuarters(names)` (ShipBuyPassengerQuarters), where SpecialCrew counts the aboard members among Commander, Jarek, Princess and Wild; `newSpec.crewQuarters < CrewCount` → `.tooManyCrew` (ShipBuyCrewQuarters); reactor aboard → `.reactorAboard` (ShipBuyReactor). (source: Commander.cs:120-139, Ship.cs:1260-1277, Consts.cs:283-295)
- **SHP-037** {M5} [P] Palm checks, in order: price 0 → not available; `price > 0 && Debt > 0` → in debt; `price > ToSpend()` → can't afford; Jarek aboard (`JarekStatus == 1`) and quarters < 2 → passenger needs quarters; same for Wild (`WildStatus == 1`); reactor aboard (status 1..20) → can't sell; then the transfer offers (SHP-042); then hired crew count (commander included) `> quarters` → too many crew members, checked **after** the transfer prompts. Flag `palmShipTradeChecks`. (source: Palm: Src/BuyShipEvent.c:196-216, 326-328)
- **SHP-038** {M2} [M][W] Unique-equipment transfer candidates, in this order: Morgan's laser, Quantum disruptor, Lightning shield, Fuel compactor, Hidden cargo bays. For each one installed: if the new spec has 0 slots of its type, the event `.cannotTransfer(item)` (ShipBuyNoSlots) is emitted and the item is lost; otherwise it is a candidate at its TransferPrice (§1.4). If the old ship has an escape pod, the pod is a candidate at 200 (`PodTransferCost`). (source: Commander.cs:142-173, Consts.cs:78)
- **SHP-039** {M2} [M][W] If `netPrice + Σ candidate prices > CashToSpend` the warning `.cannotAffordAllTransfers` (ShipBuyIFTransfer) is emitted; it does not abort. (source: Commander.cs:175-176)
- **SHP-040** {M2} [M][W] Candidates are then decided in order (equipment first, pod last), keeping a running `extra`: a candidate with `netPrice + extra + price > CashToSpend` is declined automatically with `.cannotAffordTransfer(item)` (ShipBuyNoTransfer); otherwise the player accepts or declines it (ShipBuyTransfer), and an accepted price is added to `extra`. (source: Commander.cs:178-203)
- **SHP-041** {M2} [M][W] Finally the purchase is confirmed (ShipBuyConfirm); declining leaves all state unchanged. (source: Commander.cs:205-207)
- **SHP-042** {M5} [P] Palm candidates are, in order, Lightning shield 30000, Fuel compactor 20000, Morgan's laser 33333 (flag `uniqueTransferFixedPrices`). The pre-check sum adds each installed item's price even when the new ship has no slot for it. An item is offered only if the new ship has a slot of its type and `price + extraSoFar <= ToSpend()`; the item's own price is **not** included, so accepting can leave Credits negative. (source: Palm: Src/BuyShipEvent.c:229-317)
- **SHP-043** {M5} [P] Palm keeps the escape pod (and insurance) on a ship trade at no cost; the pod is not offered as a transfer. Flag `escapePodKeptOnShipTrade`. (source: Palm: Src/BuyShipEvent.c:40-82, Src/Global.c EscapePod)
- **SHP-044** {M2} [M][W] On a confirmed trade: a new ship of the chosen type replaces the old one with full tanks (spec tanks, before any compactor), full spec hull, no equipment, empty cargo, 0 tribbles and no hull upgrade; `Cash -= netPrice + extra`; crew slot j is copied from the old ship for `j < min(old quarters, new quarters)`; accepted items are added (a transferred shield keeps its charge, which is full); the pod is set if accepted, otherwise if insured then `Insurance = false` and `NoClaim = 0`. (source: Commander.cs:208-228, Ship.cs:755-765, Shield.cs:58-63)
- **SHP-045** {M5} [P] On a confirmed Palm trade: equipment slots cleared, cargo and `BuyingPrice` cleared, fuel = new tank capacity, hull = spec hull; `Credits -= price`; `ScarabStatus 3 → 0`; `Credits -= extra`; accepted items go into slot 0 of their type; a transferred Lightning shield has charge 0 until the next departure (flag `transferredShieldUncharged`); `Tribbles = 0`; the crew is unchanged. (source: Palm: Src/BuyShipEvent.c:40-82, 357-369)
- **SHP-046** {M2} [W] The cost basis `Commander.PriceCargo` is **not** reset when the hold is emptied by a ship trade, so the next trade-in counts it again (port bug #1, kept in Windows 2.01: `resetPriceCargoOnHoldClear = false`). (source: Commander.cs:208-228, Ship.cs:783-790)
- **SHP-047** {M5} [M] Modern resets all 10 `PriceCargo` entries to 0 whenever the hold is cleared by a ship trade (including a designer-built ship), and by the Flea after arrest or the escape pod (POL owns those paths). Flag `resetPriceCargoOnHoldClear = true` (MOD-001). (source: PRD MOD-001)
- **SHP-048** {M2} [M][W] After any successful ship purchase (ship list or designer), `QuestStatusScarab == 3` (Done) is reset to 0, so the Scarab quest effects end with the old hull. (source: Form_ShipList.cs:892-895, Form_Shipyard.cs:1185-1190, SpecialEvent.cs:89-92)

## 9. Escape pod

- **SHP-049** {M2} [M][W] The escape pod is offered iff the ship has none, `system.tech >= EarlyIndustrial` (the Flea's minimum tech) and `Cash >= 2000` (Cash, not CashToSpend). Buying asks a confirmation (EquipmentEscapePod), then `Cash -= 2000` and the pod is installed. (source: Form_SpaceTrader.cs:3096-3118, 3587-3595)
- **SHP-050** {M5} [P] Palm offers the pod iff none, tech ≥ EarlyIndustrial and `ToSpend() >= 2000`; it costs 2000. Flag `escapePodPurchaseUsesToSpend`. (source: Palm: Src/Shipyard.c:169-172, 229-236, 313-318)

## 10. Fuel and repairs

- **SHP-051** {M2} [M][W][P] Buying fuel for an amount A credits: `A = min(A, (capacity - fuel)*fuelCost, Cash)`; `units = A / fuelCost`; `fuel += units`; `Cash -= units*fuelCost`. Partial amounts are allowed; the cap uses Cash, not CashToSpend. (source: Form_BuyFuel.cs:59, Form_SpaceTrader.cs:3531-3541; Palm: Src/Fuel.c:68-82)
- **SHP-052** {M2} [M][W][P] The fuel service is available iff `capacity - fuel > 0`; the full-tank cost shown is `(capacity - fuel)*fuelCost`. (source: Form_SpaceTrader.cs:3069-3073; Palm: Src/Shipyard.c:134-143, 177-187)
- **SHP-053** {M2} [M][W][P] Buying repairs for A credits: `A = min(A, (hullStrength - hull)*repairCost, Cash)`; `points = A / repairCost`; `hull += points`; `Cash -= points*repairCost`. (source: Form_BuyRepairs.cs:59, Form_SpaceTrader.cs:3603-3613; Palm: Src/Shipyard.c:243-258)
- **SHP-054** {M2} [M][W][P] The repair service is available iff `hullStrength - hull > 0`; the full-repair cost shown is `(hullStrength - hull)*repairCost`; hull percent shown is `floor(100*hull/hullStrength)`. (source: Form_SpaceTrader.cs:3075-3080; Palm: Src/Shipyard.c:144-153, 189-201)
- **SHP-055** {M2} [W] Fuel and repair unit costs come from the C# columns (FC, RC of §1.1): fuel is 1..5 per parsec and repairs 1..20 per hull point. (source: Consts.cs:249-267, Form_SpaceTrader.cs:3535, 3607)
- **SHP-056** {M5} [M][P] Fuel and repair unit costs come from the Palm columns: fuel 1..20 per parsec (`CostOfFuel`) and repairs 1..5 per hull point (`RepairCosts`) (MOD-017 for Modern). (source: PRD MOD-017; Palm: Src/Fuel.c:72-81, Src/Shipyard.c:248-257)
- **SHP-057** {M2} [M][W] Arrival auto-fuel and auto-repair (options) are all-or-nothing: each is bought in full only if `Cash >= full cost`, else nothing is bought and a warning is raised (fuel is tried before repairs). Owned by TRV. (source: Game.cs:470-498)
- **SHP-058** {M5} [P] Palm arrival auto-fuel and auto-repair buy partial amounts (`BuyFuel(999)`, `BuyRepairs(9999)`); if the tank is not full and auto-repair is on with damage, the repair is skipped with a combined warning. Flag `arrivalAutoBuyPartial`; owned by TRV. (source: Palm: Src/Traveler.c:2327-2348)

## 11. Hull upgrade, fuel compactor and extra bays

- **SHP-059** {M2} [M][W][P] The hull upgrade (+50, SHP-018/SHP-019) is obtained only from the Scarab quest and is lost on any ship trade. Hull-damage halving for the upgraded hull belongs to CMB (MOD-004). (source: Game.cs:2486-2489, Form_ShipList.cs:894-895; Palm: Src/BuyShipEvent.c:80-81)
- **SHP-060** {M2} [M][W][P] The fuel compactor is obtained only from the Gemulon quest, is never for sale, and can be sold or transferred (SHP-012, SHP-038/SHP-042). Its tank effect is SHP-016 (M/W) or SHP-017 (P). (source: Consts.cs:153; Palm: Src/Global.c:236)
- **SHP-061** {M2} [M][W][P] Each Extra cargo bays gadget adds 5 bays and is buyable (min tech EarlyIndustrial, 2500). (source: Consts.cs:147, Ship.cs:934-945; Palm: Src/Cargo.c:1022-1024)
- **SHP-062** {M2} [M][W] Hidden cargo bays add 5 bays, are obtained only from the Sculpture quest (content `hasHiddenBays`), are never for sale, and can be transferred at 55000. Their concealment effect belongs to POL/ENC. (source: Consts.cs:154, Ship.cs:1096-1107, Commander.cs:148)

## 12. Custom ship designer (Windows 2.01 and Modern only)

- **SHP-063** {M2} [M][W] The designer is available only in a system that hosts one of the five shipyards (content `customShipyard`; placement is owned by GAL); Palm has no designer. (source: Form_SpaceTrader.cs:3102, StarSystem.cs:377-390)
- **SHP-064** {M2} [M][W] The designer uses the per-size tables and scalars of §1.5 verbatim and the shipyard specialty/skill table of §1.5. (source: Shipyard.cs:37-77, Consts.cs:272-279)
- **SHP-065** {M2} [M][W] Selectable sizes are `max(Tiny, specialty - 2) ... min(Gargantuan, specialty + 2)`. (source: Shipyard.cs:155-166)
- **SHP-066** {M2} [M][W] Derived per-design values for size s: `BaseFuel = BASE_FUEL[s] + (skill == FuelBase ? 2 : 0)`; `BaseHull = BASE_HULL[s]`; `PerUnitFuel = PER_UNIT_FUEL[s]`; `PerUnitHull = PER_UNIT_HULL[s] + (skill == HullPerUnit ? 5 : 0)`; `UnitsCrew = 20 - (skill == CrewQuarters ? 2 : 0)`; `UnitsShield = UNITS_SHIELD[s] - (skill == ShieldSlotUnits ? 2 : 0)`; `UnitsWeapon = UNITS_WEAPON[s] - (skill == WeaponSlotUnits ? 2 : 0)`; `UnitsFuel = UNITS_FUEL[s]`; `UnitsGadget = 5`; `UnitsHull = UNITS_HULL[s]`. (source: Shipyard.cs:93-118, 170-184, 296-302, 352-398)
- **SHP-067** {M2} [M][W] `UnitsUsed = bays + crew*UnitsCrew + ceil((double)(fuel - BaseFuel)/PerUnitFuel*UnitsFuel) + gadgets*UnitsGadget + (hull - BaseHull)/PerUnitHull*UnitsHull + shields*UnitsShield + weapons*UnitsWeapon`; the fuel term divides in double before multiplying and rounds up; the hull term is integer (truncating) division then multiplication. Example: Tiny, fuel 20 → `ceil(5/3*1) = 2` units. (source: Shipyard.cs:400-412)
- **SHP-068** {M2} [M][W] `PercentOfMaxUnits = UnitsUsed*100/MAX_UNITS[s]` (integer). Crowding penalty = `BasePrice*75/100` if percent ≥ 90, else `BasePrice*25/100` if percent ≥ 80, else 0, where `BasePrice = UnitsUsed*PRICE_PER_UNIT[s]`. (source: Shipyard.cs:186-192, 265-286)
- **SHP-069** {M2} [M][W] `CostAdjustment` = 90 if `s == specialty`, 100 if `|s - specialty| == 1`, else 110. `AdjustedPrice = BasePrice*adj/100`, `AdjustedPenalty = Penalty*adj/100`, `AdjustedFee = DESIGN_FEE[s]*adj/100`; `TotalCost = AdjustedPrice + AdjustedPenalty + AdjustedFee - Ship.Worth(false)` (the current ship's trade-in value, SHP-028). (source: Shipyard.cs:129-153, 194-214, 336-350)
- **SHP-070** {M2} [M][W] Worked example A, Corellian (Large, CrewQuarters), Large design with 30 bays, fuel 12, hull 100, 2 weapons, 2 shields, 2 gadgets, 2 crew: UnitsUsed = `30 + 2*18 + 0 + 2*5 + 0 + 2*8 + 2*10 = 112` of 200 (56%, no penalty); BasePrice 84000; AdjustedPrice 75600; AdjustedFee 18000; TotalCost = `93600 - tradeIn`. Example B, Sienar (Tiny, WeaponSlotUnits), Tiny design with 10 bays, fuel 15, hull 10, 1 weapon, 0 shields, 1 gadget, 1 crew: UnitsUsed `10 + 20 + 0 + 5 + 0 + 0 + 13 = 48` of 50 (96%); BasePrice 3600; penalty 2700; adjusted 3240 + 2430 + fee 1800 = `7470 - tradeIn`. (source: Shipyard.cs:37-77, 120-412)
- **SHP-071** {M2} [M][W] The built Custom spec stores size, bays, tanks, hull, slots and quarters as designed, `Price = BasePrice + Penalty` (unadjusted, without fee), `FuelCost = COST_FUEL[s]` (per parsec), `RepairCost = COST_HULL[s]` (per hull point), occurrence 0, activities NA and minimum tech Unavailable. These designer costs are not subject to the MOD-017 column swap. (source: Shipyard.cs:120-125, Consts.cs:266)
- **SHP-072** {M2} [M][W] Input limits: bays 0..999; fuel `BaseFuel..20` (`MaxFuelTanks`); hull `BaseHull..9999`; weapon, shield and gadget slots 0..5 (`MaxSlots`); crew quarters 1..5. (source: Form_Shipyard.cs:713-760, 1090-1110, Consts.cs:72,76)
- **SHP-073** {M2} [M][W] Snapping: a fuel value whose `(fuel - BaseFuel) % PerUnitFuel > 0` and which is below 20 is raised to `min(20, ((extra + PerUnitFuel)/PerUnitFuel)*PerUnitFuel + BaseFuel)`; a hull value whose `(hull - BaseHull) % PerUnitHull > 0` is raised to the next multiple above BaseHull. (source: Form_Shipyard.cs:1112-1125)
- **SHP-074** {M2} [M][W] A design can be built iff its name is non-empty and `PercentOfMaxUnits <= 100`. Because the percentage truncates, UnitsUsed may exceed MAX_UNITS slightly (for example 151 units on a Medium ship is 100%, allowed). Errors: `.designNameEmpty`, `.designOverCapacity`. (source: Form_Shipyard.cs:963-966, 1206-1210)
- **SHP-075** {M2} [M][W] Building runs TradeShip (§8) with the Custom spec and `netPrice = TotalCost`, with every check, transfer offer and effect; on success the ship takes the given name, the Scarab status resets (SHP-048), and the Custom spec is stored in `GameState` (one Custom spec per game; a new build replaces it). (source: Form_Shipyard.cs:1181-1203, ShipSpec.cs:112-120)
- **SHP-076** {M2} [M][W] Design templates offered to the player: the current ship, the minimum design of each available size, the default spec of each buyable type (0..9) whose size is available, and user-saved designs of an available size. (source: Form_Shipyard.cs:1038-1072, ShipTemplate.cs:51-70)

## 13. Commands and pure previews (engine API)

- **SHP-077** {M2} [M][W][P] `preview(.equipmentMarket)` is pure and returns every for-sale item with its buy price (0 = not sold) and the first blocking CommandError per SHP-020/SHP-021, plus every installed item with its sell price and any blocking error (SHP-025/SHP-026). (source: Form_Equipment.cs:565-660; Palm: Src/BuyEquipEvent.c:58-156, Src/SellEquipEvent.c:40-118)
- **SHP-078** {M2} [M][W][P] `perform(.buyEquipment(item))` and `perform(.sellEquipment(type, slot))` return `.confirm(...)` without the acknowledgement and change no state; with it they apply SHP-023/SHP-024. A blocked command is rejected with the previewed CommandError. (source: Form_Equipment.cs:584-633; Palm: Src/Cargo.c:1086-1101)
- **SHP-079** {M2} [M][W][P] `preview(.shipyard)` returns, per ship type 0..9: availability (SHP-033), net price (SHP-034/SHP-035), the first TradeShip blocker (SHP-036/SHP-037), and the transfer candidates with prices and lost items (SHP-038/SHP-042, SHP-043). (source: Form_ShipList.cs:916-933, Commander.cs:120-204; Palm: Src/BuyShipEvent.c:88-330)
- **SHP-080** {M2} [M][W][P] `perform(.buyShip(type, transfers: Set<TransferItem>))` takes the player's transfer choices up front; the engine evaluates candidates in source order (SHP-040/SHP-042), auto-declines unaffordable ones with events, requires the `.confirmShipPurchase` acknowledgement (two-phase), and applies SHP-044/SHP-045. The confirmation lists the final accepted transfers and the total charge. (source: Commander.cs:175-231; Palm: Src/BuyShipEvent.c:271-372)
- **SHP-081** {M2} [M][W][P] `preview(.fuel)` and `preview(.repairs)` return the units missing, the unit cost, the full cost, the maximum spend `min(full cost, Cash)` and, for a given amount, the units bought; `perform(.buyFuel(credits))` and `perform(.buyRepairs(credits))` apply SHP-051/SHP-053 and reject amounts < 1 with `.invalidAmount`. (source: Form_BuyFuel.cs:59, Form_BuyRepairs.cs:59; Palm: Src/Fuel.c:68-82, Src/Shipyard.c:243-258)
- **SHP-082** {M2} [M][W][P] `preview(.escapePod)` returns offered/blocked with reason (`.alreadyHavePod`, `.techTooLow`, `.insufficientFunds`) and price 2000; `perform(.buyEscapePod)` is two-phase (EquipmentEscapePod confirmation). (source: Form_SpaceTrader.cs:3104-3118, 3587-3595; Palm: Src/Shipyard.c:169-172, 313-318)
- **SHP-083** {M2} [M][W] `preview(.shipDesign(spec, size))` is pure and returns every derived figure of §12 (units used, percent, penalty, adjusted price, fee, trade-in, total cost, custom fuel/repair cost), the snapped inputs, buildability (SHP-074) and the TradeShip blockers; `perform(.buildShip(design, name, transfers))` follows SHP-075 and SHP-080. (source: Shipyard.cs:120-412, Form_Shipyard.cs:1112-1203)
- **SHP-084** {M2} [M][W][P] SHP CommandErrors and confirmations map one-to-one to source alerts: `.equipmentAlreadyOwned`=EquipmentAlreadyOwn, `.inDebt`=DebtNoBuy, `.insufficientFunds`=EquipmentIF/ShipBuyIF, `.noFreeSlot`=EquipmentNotEnoughSlots, `.extraBaysInUse`=EquipmentExtraBaysInUse, `.passengersNeedQuarters`=ShipBuyPassengerQuarters, `.tooManyCrew`=ShipBuyCrewQuarters, `.reactorAboard`=ShipBuyReactor; events `.cannotTransfer`=ShipBuyNoSlots, `.cannotAffordAllTransfers`=ShipBuyIFTransfer, `.cannotAffordTransfer`=ShipBuyNoTransfer, `.shipDesignBuilt`=ShipDesignThanks; confirmations EquipmentBuy, EquipmentSell, EquipmentEscapePod, ShipBuyTransfer, ShipBuyConfirm. ALR owns the full mapping. (source: Form_Equipment.cs:565-633, Commander.cs:120-207, Form_Shipyard.cs:1200)
- **SHP-085** {M2} [M][W][P] Invariants after every SHP command: `0 <= hull <= hullStrength`, `0 <= fuel <= capacity` (Palm: usable fuel per SHP-017), installed items ≤ slots per type, crew ≤ quarters, and `Cash >= 0` except under the flag-guarded Palm quirk SHP-042. (source: PRD §6.2 invariants)
