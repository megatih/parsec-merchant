# C# Space Trader for Windows 2.01 — Engine & Mechanics Specification

> Extracted 2026-11-16 from /Users/megatih/Downloads/SpaceTraderSource201 (GPL v2+). File:line citations refer to that tree. This is research input; normative requirements live in docs/specs/ (created in M0). Verify any value against the source before encoding it.


## QA ERRATA (independent fidelity audit, 2026-11-16): these override the text below
About 115 claims were checked across docs 01 and 04: roughly 100 confirmed, 3 wrong, 10 imprecise. Corrections for this document:
1. **WRONG §7, opponent ship choice.** C# weights ships **0..8 only**: `for (i < Consts.MaxShip)` with MaxShip = 9, and the walk stops at index 8. **A Wasp is never generated as a random opponent** in C#; the only Wasp opponent is the famous captain. Palm can generate one (about 1%). This needs a ruleset flag.
2. **WRONG §7, "duplicates aren't excluded".** C# opponent weapons and shields **skip types already owned** (`!HasWeapon(type, true)` / `!HasShield`). Duplicates only arise through the index-0 fallback (Pulse, Energy or Extra Bays) when every draw is already owned.
3. **WRONG §2, "GetRandom2 can go negative".** Pieter's `Rand()` in C# is a multiply-with-carry on `long`. The seeds stay bounded and the output is always ≥ 0. It differs from Palm only because it uses 64-bit arithmetic with no UInt16 truncation.
4. **IMPRECISE §2, construction order** (Game.cs:110-133): InitializeCommander (start system) → GenerateCrewMemberList → CreateShips → CalculatePrices → ResetVeryRareEncounters → Lottery. RNG call order depends on this.
5. **IMPRECISE §3, restock.** After the decrement, a `CountDown > CountDownStart` is clamped back down (Game.cs:517).
6. There are **188** `AlertType` cases, not ~149.

---

I've read every file you listed in full, plus the forms that hold game logic. All line numbers are for files under `/Users/megatih/Downloads/SpaceTraderSource201/`.

Three things matter most for the Swift port:
- **Random numbers can't be reproduced.** The game uses an unseeded `System.Random` (seeded from the clock).
- **There are real bugs to decide on.** At least one gives infinite money (buying a ship refunds cargo cost again and again), and arrest can give you money instead of fining you. See §13.
- **The save format can't be read from Swift.** It's .NET `BinaryFormatter`, so you need your own format.

---

# 1. Architecture

**Classes**
- `Game` (Game.cs) is a singleton (`Game.CurrentGame`, a static `_game` set in both constructors). It holds all game state, and most rules live in it. It extends `STSerializableObject`.
- `Commander` extends `CrewMember`. It holds cash, debt, kills, police and reputation scores, days, insurance, no-claim, the ship, and `PriceCargo[10]` (total paid per trade item, used as cost basis).
- `CrewMember` holds an id, `Skills[4]` (Pilot, Fighter, Trader, Engineer) and the system it's in. Its name comes from `Strings.CrewMemberNames[id]`.
- `ShipSpec` holds static ship stats. `Ship` extends it with fuel, hull, tribbles, cargo[10], weapons/shields/gadgets arrays sized to the slots, crew[quarters] and escape pod.
- `Equipment` is abstract, with subclasses `Weapon`, `Shield` (has Charge) and `Gadget` (has a skill bonus).
- `StarSystem`, `TradeItem`, `PoliticalSystem`, `PoliceRecord`, `Reputation` and `SpecialEvent` are mostly static tables in `Consts`.
- `Shipyard` is the custom ship designer. `ShipTemplate` stores saved designs.
- `GameOptions`, `HighScoreRecord`, `Functions` (random numbers, distance, wormholes, file I/O, string templates).
- `GameEndException(GameEndType)` sets `Game.CurrentGame.EndStatus` and is caught in `Form_SpaceTrader`. `FutureVersionException` is the other exception type.

**Logic inside forms**
- `Form_SpaceTrader.cs` has the cheat codes (3298–3518), fuel and repair buying (3531, 3603), the escape pod (3587, 2000 cr flat), the special-event button (3615: CashToSpend check, then `HandleSpecialEvent`), Warp/Jump, `GameEnd` and high scores (2771–2841), and Retire.
- `Form_Encounter.cs` maps encounter type to visible buttons (`UpdateButtons` 1066). Button handlers call `Game.EncounterVerify*` and `EncounterExecuteAction`. A timer drives continuous attack.
- `Form_ShipList.cs:918-935` prices ships: `spec.Price - Ship.Worth(false)`.
- `Form_Equipment.cs:565-640` buys and sells equipment.
- `Form_ViewBank.cs:62-65` sets the loan limit; it also handles loans and insurance.
- `Form_ViewPersonnel.cs:426` hires and fires.
- `Form_Shipyard.cs:1090-1200` builds custom ships.
- `Form_NewCommander.cs:384` handles skill points.
- `Form_CargoBuy/Sell` cap quantities (see the bug in §13).

**Serialization**
- Every persistent class overrides `Serialize()` to return a `Hashtable` of `"_fieldName" -> value`. Values are primitives, int arrays, nested Hashtables, or ArrayLists of Hashtables (via `ArrayToArrayList`).
- Loading reads each key with `GetValueFromHash(hash, key, default)`, so missing keys fall back to defaults.
- A ship saves its crew as `_crewIds` (int[]) and re-links them to `Game.Mercenaries` on load.
- The custom ship's name and images are stored inside the ship hash and change the global `Consts.ShipSpecs[Custom]` and `Strings.ShipNames[Custom]` on load.
- The whole hash is written with `BinaryFormatter` (`Functions.SaveFile/LoadFile`).
- Save version: `hash["_version"]="2.00"`. Loading throws `FutureVersionException` if the saved version string is greater than "2.00" (Game.cs:147).
- Autosave files `autosave_departure.sav` and `autosave_arrival.sav` are written only when `AutoSave` is on (cheat "PlanB").

**Files**
- `data/HighScores.bin` holds an ArrayList of 3 `HighScoreRecord` hashes.
- `data/DefaultSettings.bin` holds the GameOptions hash.
- `custom/templates` and `custom/images` hold shipyard designs.
- Window position is stored in the registry `HKCU\Software\FrenchFryz\SpaceTrader`.

**Game state fields** (Game.cs:37-104): `_universe[128]`, `_wormholes[6]`, `_mercenaries[55]`, commander, the persistent ships `_dragonfly/_scarab/_scorpion/_spaceMonster`, `_opponent`, `_opponentDisabled`.
- `_chanceOfTradeInOrbit=100` (out of 1000), `_clicks`, and the flags `_raided`, `_inspected`, `_tribbleMessage`, `_arrivedViaWormhole`, `_paidForNewspaper`, `_litterWarning`.
- `_newsEvents` list, difficulty, `_cheatEnabled`, `_autoSave`, `_easyEncounters`, `_endStatus`, `_encounterType`.
- Selected, warp and tracked system ids; `_targetWormhole`; `_priceCargoBuy[10]`, `_priceCargoSell[10]`.
- 13 quest status ints (see §10); `_fabricRipProbability`, `_justLootedMarie`, `_canSuperWarp`.
- `_chanceOfVeryRareEncounter=5` (out of 1000), the `_veryRareEncounters` list, and options.
- The encounter flags are not saved.

# 2. Random numbers and universe generation

**Random numbers** (Functions.cs)
- `GetRandom(max)` is `rand.Next(0,max)`. `GetRandom(min,max)` is `rand.Next(min,max)`, upper bound exclusive.
- `rand` is a static unseeded `new Random()`, so runs can't be reproduced. For tests, use a seedable generator and inject it.
- `GetRandom2(max) = Rand() % max` uses Pieter's two-seed generator: `SeedX=a*(SeedX&0xFFFF)+(SeedX>>16)` with a=18000, and the same for SeedY with b=30903. It returns `(SeedX<<16)+(SeedY&0xFFFF)`. Default seeds are 521288629 and 362436069.
  - The port uses 64-bit `long` with no 32-bit wrap, so its output differs from the Palm C version. The result can go negative after overflow.
  - It is used only for the newspaper, seeded with `RandSeed(systemId, days)` (0 means the default seed).
- `RandomSkill() = 1 + GetRandom(5) + GetRandom(6)` gives 1..10.
- `Distance` is `floor(sqrt(dx²+dy²))`.

**Universe** (`GenerateUniverse`, Game.cs:2175)
- There are 128 systems, one per name in `Strings.SystemNames` (ids 0..127; enum in Enums.cs:678). The last 8 (Centauri, Galvon, Inthara, Meridian, Qonos, Rae, Weytahn, Zonama) are port additions.
- Constants: galaxy 154×110, `MinDistance=7`, `CloseDistance=13`, `MaxRange=20` (chart only), `WormDist=25`.
- Each system uses the generator in this order:
  1. size = `GetRandom(5)` (Tiny..Huge)
  2. political system = `GetRandom(17)`
  3. tech = `GetRandom(pol.minTech, pol.maxTech+1)`
  4. Galvon is overridden after these rolls: Large, Monarchy, HiTech.
  5. pressure: if `GetRandom(100)<15`, pick `GetRandom(1,8)` (War..Employment)
  6. special resource: if `GetRandom(5)>=3`, pick `GetRandom(1,13)`
  7. coordinates
- Coordinates for systems i<6 (the wormhole systems): `x = 154*(1+2*(i%3))/6 - GetRandom(-12,13)` and `y = 110*(i<3?1:3)/4 - GetRandom(-12,13)`. Then `Wormholes[i]=i`.
- Other systems retry random `x∈[1,154)`, `y∈[1,110)` until no earlier system is closer than 7 and at least one is closer than 13.
- The `StarSystem` constructor calls `InitializeTradeItems()`, which also uses the generator.
- Shuffle pass: for each i, pick a random j. If j isn't a wormhole system, swap the coordinates of i and j and update the wormhole index if i was one.
- The wormhole array is then shuffled by swapping. Wormholes form a ring: `Wormholes[k] -> Wormholes[(k+1)%6]`. The tax is `25 * ship.FuelCost`.

**Retry loop:** generation repeats until both `PlaceSpecialEvents()` and `PlaceShipyards()` succeed (Game.cs:118).

**`PlaceSpecialEvents`** (2880)
1. Fixed systems:

   | System | Event |
   |---|---|
   | Baratas | DragonflyBaratas |
   | Melina | DragonflyMelina |
   | Regulas | DragonflyRegulas |
   | Zalkon | DragonflyDestroyed |
   | Daled | ExperimentStopped |
   | Gemulon | GemulonRescued |
   | Japori | JaporiDelivery |
   | Devidia | JarekGetsOut |
   | Utopia | MoonRetirement |
   | Nix | ReactorDelivered |
   | Acamar | SpaceMonsterKilled |
   | Kravat | WildGetsOut |
   | Endor | SculptureDelivered |
   | Galvon | Princess |
   | Centauri | PrincessCentauri |
   | Inthara | PrincessInthara |
   | Qonos | PrincessQonos |

2. ScarabDestroyed goes on the first wormhole system (in Wormholes order) with no event; if none, fail.
3. ArtifactDelivery goes on the first HiTech system by index with no event. This is deterministic, not random.
4. `FindDistantSystem` places Reactor (from Nix), Gemulon (from Gemulon), Experiment (from Daled) and Sculpture (from Endor). Each goes on the *closest* empty system at distance ≥70; if none, fail.
5. Every event with Occurrence>0 is placed that many times on random empty systems: Artifact 1, CargoForSale 3, Dragonfly 1, EraseRecord 3, Japori 1, Jarek 1, Moon 4, Scarab 1, Skill 3, SpaceMonster 1, Tribble 1, TribbleBuyer 3, Wild 1.

**`PlaceShipyards`** collects the HiTech systems and fails if there are fewer than 5. Each of the 5 shipyards goes to a random HiTech system. Two can land on the same system and overwrite each other.

**Mercenaries** (`GenerateCrewMemberList` 2121)
- Fixed entries (Pilot, Fighter, Trader, Engineer), with d = difficulty:

  | Character | Skills |
  |---|---|
  | Zeethibal | 5,5,5,5 |
  | Opponent | 5,5,5,5 |
  | Wild | 7,10,2,5 |
  | Jarek | 3,2,10,4 |
  | Princess | 4,3,8,9 |
  | FamousCaptain | 10,10,10,10 |
  | Dragonfly | 4+d, 6+d, 1, 6+d |
  | Scarab | 5+d, 6+d, 1, 6+d |
  | Scorpion | 8+d, 8+d, 1, 6+d |
  | SpaceMonster | 8+d, 8+d, 1, 1+d |

- The other 44 (ids 1–29 and 38–52) get random systems with at most 3 per system; Kravat starts with 1 already counted. Each gets 4× `RandomSkill()`.
- The Princess is named "Ziyal" (index 53).

**Commander start** (`InitializeCommander` 2685)
- Picks a random system with no event, tech between 1 and 6, and at least 3 other systems within `Ship.FuelTanks` (Gnat: 14).
- Starts with 1000 cash, 0 debt, a Gnat, a Pulse Laser, full fuel (14) and full hull (100).
- After `CalculatePrices` and `ResetVeryRareEncounters`: on Beginner or Easy, the start system gets the Lottery event (+1000).
- Then `CreateShips()` (Game.cs:743) equips the persistent ships:

  | Ship | Equipment |
  |---|---|
  | Dragonfly | Military Laser + Pulse Laser, 3 Lightning shields, AutoRepair, Targeting |
  | Scarab | 2 Military Lasers |
  | Scorpion | 2 Military Lasers, 2 Reflective shields, AutoRepair, Targeting |
  | SpaceMonster | 3 Military Lasers |

**Pressure changes** happen on every arrival (`ArrivalUpdatePressuresAndQuantities` 505). For every system, with a 15% chance: None becomes a random pressure, otherwise it becomes None.

# 3. Trade

**TradeItems table** (Consts.cs:351). Columns: produced-at tech / used-at tech / top-production tech, low-tech price, increase per tech level, variance, pressure that raises the price, resource that makes it cheap, resource that makes it expensive, in-orbit min/max price, round-off.
```
Water     PreAg  PreAg  Medieval   30    3    4  Drought     SweetOceans    Desert       30   50   1
Furs      PreAg  PreAg  PreAg     250   10   10  Cold        RichFauna      Lifeless    230  280   5
Food      Agric  PreAg  Agric     100    5    5  CropFailure RichSoil       PoorSoil     90  160   5
Ore       Mediev Mediev Renaiss   350   20   10  War         MineralRich    MineralPoor 350  420  10
Games     Renais Agric  PostInd   250  -10    5  Boredom     Artistic       NA          160  270   5
Firearms  Renais Agric  Industr  1250  -75  100  War         Warlike        NA          600 1100  25
Medicine  EarlyI Agric  PostInd   650  -20   10  Plague      SpecialHerbs   NA          400  700  25
Machines  EarlyI Renais Industr   900  -30    5  Employment  NA             NA          600  800  25
Narcotics Industr PreAg Industr  3500 -125  150  Boredom     WeirdMushrooms NA         2000 3000  50
Robots    PostInd EarlyI HiTech  5000 -150  100  Employment  NA             NA         3500 5000 100
```
Firearms and Narcotics are illegal (`TradeItem.Illegal`).

**Where an item trades**
- `ItemTraded` (can buy there): tech ≥ production tech, and the government allows it (Narcotics need DrugsOk, Firearms need FirearmsOk).
- `ItemUsed` (can sell there): same rule with the usage tech.

**`StandardPrice`** (TradeItem.cs). It returns 0 unless the item is used there.
```
p = lowTech + tech*inc
if gov.Wanted == item: p = p*4/3
p = p*(100 - 2*gov.ActivityTraders)/100
p = p*(100 - size)/100
if sys.SpecialResource == cheapRes: p = p*3/4  else if == expensiveRes: p = p*4/3
```
`StarSystem.SpecialResource` returns Nothing unless the system has been visited (StarSystem.cs, near the end).

**`CalculatePrices`** (Game.cs:534) sets the sell price for each item:
```
if p>0: if pressureHike==sys.pressure: p=p*3/2
        v=min(variance,p-1); p += GetRandom(-v, v+1)      // the variance is ABSOLUTE credits, although the field comment says "percentage"
        if PoliceRecordScore < -5: p = p*90/100
sell[i]=p
```
**`RecalculateBuyPrices`** (2960) sets the buy price:
```
if !ItemTraded: buy=0
else buy=sell; if criminal: buy=buy*100/90
     buy = buy*(103 + 10 - Ship.Trader)/100
     if buy<=sell: buy=sell+1
```
- `Ship.Trader` = the best crew Trader skill, adjusted for difficulty, plus 1 if the haggling computer is on board (Jarek done).
- Prices are recalculated when trader skill changes on hire or fire, and in `ChangeRandomSkill`.
- `RecalculateSellPrices` (2985) multiplies every sell price by 100/90 unconditionally. It runs after EraseRecord and WildGetsOut.
- `CalculatePrices(WarpSystem)` runs both at departure (these prices are used for in-orbit trades) and again on arrival.

**Quantities** (`InitializeTradeItems`). Untraded items get 0. Otherwise:
```
q = (size+1)*(GetRandom(9,14) - |topTech - tech|)
if item>=Narcotics: q = q*(5-diff)/(6-diff) + 1
cheapRes: q=q*4/3 ; expensiveRes: q=q*3/4   (only if visited, see above)
pressureHike: q=q/5
q = q - GetRandom(10) + GetRandom(10); clamp ≥0
```

**Restocking**
- On departure, the system you leave gets `CountDown = diff+3`.
- On each arrival, every system with CountDown>0 decrements it.
  - If it reaches 0 or below, the system's trade items are re-initialized.
  - Otherwise each traded item gets `+GetRandom(-4,5)`, clamped at ≥0. Whether an item counts as traded is checked against `WarpSystem.ItemTraded` instead of the system's own (bug).

**Buying at a market** (`CargoBuy` 561)
- Free bays = `FreeCargoBays - Options.LeaveEmpty`.
- Blocked if debt >100000.
- Max quantity = `min(freeBays, stock, CashToSpend/price)`.
- Cash -= qty×price; `PriceCargo += total`.

**Selling** (655)
- `PriceCargo = PriceCargo*(held-qty)/held`.
- If the market doesn't buy the item, the sell button becomes "Dump". Dumping costs `5*(diff+1)` per unit, limited by CashToSpend.
- Jettison is free. After you confirm the litter warning (skipped if the warning was already given or your record is ≤ -5): with `GetRandom(10) < diff+1`, your record drops to -5 if it was higher, otherwise by 1, and a CaughtLittering news item is added.

**Trading in orbit**
- Buying from a trader: with chance 45 (illegal) or 10 (legal) out of 100, the factor is 1.1; otherwise 0.8 (illegal) or 0.9. `price = clamp(min,max, round(buyPrice*adj/roundOff)*roundOff)`.
- Selling to a trader: same, but the factor is 0.8/0.9 *with* the chance and 1.1 otherwise.
- Max quantity sold = `min(held, opponent free bays)`.
- `HasTradeableItems` only allows illegal goods if you're a criminal (record < -5) and only legal goods if you're not (an XOR rule).

# 4. Ships and equipment

**Ship table** (Consts.cs:249). Columns: Size, Bays, Weapon/Shield/Gadget slots, Crew quarters, Fuel tanks (range), Fuel cost per parsec, Hull, Repair cost per hull point, Price, Occurrence %, Police / Pirate / Trader activity needed, Minimum tech.
```
Flea        Tiny   10 0 0 0 1 20 1  25  1   2000  2 NA       NA       Absent   EarlyInd
Gnat        Small  15 1 0 1 1 14 1 100  2  10000 28 Absent   Absent   Absent   Industrial
Firefly     Small  20 1 1 1 1 17 1 100  3  25000 20 Absent   Absent   Absent   Industrial
Mosquito    Small  15 2 1 1 1 13 1 100  5  30000 20 Absent   Minimal  Absent   Industrial
Bumblebee   Medium 25 1 2 2 2 15 1 100  7  60000 15 Minimal  Minimal  Absent   Industrial
Beetle      Medium 50 0 1 1 3 14 1  50 10  80000  3 NA       NA       Absent   Industrial
Hornet      Large  20 3 2 1 2 16 2 150 15 100000  6 Few      Some     Minimal  PostInd
Grasshopper Large  30 2 2 3 3 15 3 150 15 150000  2 Some     Moderate Few      PostInd
Termite     Huge   60 1 3 2 3 13 4 200 20 225000  2 Moderate Many     Some     HiTech
Wasp        Huge   35 3 2 2 3 14 5 200 20 300000  2 Many     Abundant Moderate HiTech
SpaceMonster Huge   0 3 0 0 1  1 1 500  1 500000  0 NA NA NA Unavailable
Dragonfly   Small   0 2 3 2 1  1 1  10  1 500000  0
Mantis      Medium  0 3 1 3 3  1 1 300  1 500000  0
Scarab      Large  20 2 0 0 2  1 1 400  1 500000  0
Bottle      Small   0 0 0 0 0  1 1  10  1    100  0
Custom      Huge    0 ... all 0
Scorpion    Huge   30 2 2 2 2  1 1 300  1 500000  0
```
- Activity enum: Absent=0, Minimal=1, Few=2, Some=3, Moderate=4, Many=5, Abundant=6, Swarms=7, NA=100.
- `MaxShip=9`, so only indices 0..9 can be bought or generated.
- The hull upgrade adds 50 (`HullStrength` property).
- The Fuel Compactor adds 3 tanks.
- Extra Cargo Bays and Hidden Cargo Bays each add 5 bays.

**Weapons** (power, disabling, price, tech, chance):

| Weapon | Power | Disabling | Price | Tech | Chance |
|---|---|---|---|---|---|
| Pulse | 15 | no | 2000 | Industrial | 50 |
| Beam | 25 | no | 12500 | PostInd | 35 |
| Military | 35 | no | 35000 | HiTech | 15 |
| Morgan's | 85 | no | 50000 | Unavailable | 0 |
| Photon Disruptor | 20 | yes | 15000 | PostInd | 0 |
| Quantum Disruptor | 60 | yes | 50000 | Unavailable | 0 |

**Shields** (power, price, tech, chance):

| Shield | Power | Price | Tech | Chance |
|---|---|---|---|---|
| Energy | 100 | 5000 | Industrial | 70 |
| Reflective | 200 | 20000 | PostInd | 30 |
| Lightning | 350 | 45000 | Unavailable | 0 |

**Gadgets** (skill bonus, price, tech, chance):

| Gadget | Skill bonus | Price | Tech | Chance |
|---|---|---|---|---|
| Extra Cargo Bays | — | 2500 | EarlyInd | 35 |
| AutoRepair | Engineer | 7500 | Industrial | 20 |
| Navigating | Pilot | 15000 | PostInd | 20 |
| Targeting | Fighter | 25000 | PostInd | 20 |
| Cloaking Device | **Pilot** | 100000 | HiTech | 5 |
| Fuel Compactor | — | 30000 | Unavailable | 0 |
| Hidden Cargo Bays | — | 60000 | Unavailable | 0 |

Each gadget with a skill bonus adds `SkillBonus=3`. `CloakBonus=2` exists but is never used.

**Equipment for sale:** Pulse, Beam, Military, Photon; Energy, Reflective; ExtraBays, AutoRepair, Nav, Targeting, Cloak.

**Equipment prices** (Equipment.cs)
- Buy price = `_price*(100-Ship.Trader)/100`. It is 0 (not for sale) if the system's tech is below the item's minimum.
- Sell price = `_price*3/4`.
- Transfer price (to a new ship) = `SellPrice*110/90`.
- Buying is blocked if debt >0, if you already own that gadget (except Extra Bays), if there's no free slot, or if price > CashToSpend.
- Selling Extra or Hidden bays needs ≥5 free bays.

**Ship value**
- `BaseWorth(forInsurance)` (Ship.cs:130) = `Price*(tribbles>0 && !forIns ? 1 : 3)/4 - (HullStrength-Hull)*RepairCost - (FuelTanks-Fuel)*FuelCost + Σ equipment SellPrice`.
- `Worth(forIns)` = BaseWorth + Σ`Commander.PriceCargo`.
- Ship purchase price (Form_ShipList.cs:931) = `spec.Price - Ship.Worth(false)`. There is **no trader-skill discount** on ships in the port.
- A ship is offered if minimum tech ≤ the system's tech and it isn't the type you already have.

**`TradeShip`** (Commander.cs)
- Blocked if net price >0 and debt >0, if net price > CashToSpend, if the new ship has too few quarters for the special crew or for all crew, or if the reactor is on board.
- Offers to transfer Morgan's Laser, Quantum Disruptor, Lightning Shield, Fuel Compactor and Hidden Bays at TransferPrice each, plus the escape pod for 200 (`PodTransferCost`).
- The new ship copies the old crew up to the new capacity.
- If the pod isn't transferred, insurance is cancelled and no-claim reset.
- After buying any ship, if Scarab status was 3 it is reset to 0, which removes the hardened-hull effect.

**Other costs and services**
- Escape pod: 2000 flat (Form_SpaceTrader.cs:3591). Offered if tech ≥ EarlyIndustrial and cash ≥2000.
- Fuel: FuelCost per parsec. Repair: RepairCost per hull point. You enter an amount in credits, and units = amount/cost.

**Bounty** (Ship.cs:154): `p = Price + Σweapon.Price + Σshield.Price` (prices use the *player's* trader discount and the current system's tech). Then `p = p*(2*Pilot+Engineer+3*Fighter)/60`, and `bounty = clamp(25, 2500, p/200/25*25)`.

**Custom shipyard** (Shipyard.cs). Per-size tables (Tiny..Gargantuan) cover fuel cost, hull cost, base fuel, base hull, design fee, max units, units per fuel/hull, price per unit, and units per crew/fuel/gadget/hull/shield/weapon. They're listed verbatim in the file.
- Each shipyard has a speciality size (cost ×90%; ±1 size costs 100%; further away costs 110%) and one skill: Crew −2 units, Fuel base +2, Hull per unit +5, Shield −2 units, or Weapon −2 units.
- Units used = `bays + crew*UnitsCrew + ceil((fuel-baseFuel)/perUnitFuel*UnitsFuel) + gadgets*5 + (hull-baseHull)/perUnitHull*UnitsHull + shields*UnitsShield + weapons*UnitsWeapon`.
- Crowding penalty: 25% at ≥80% of max units, 75% at ≥90%.
- Price = units × price per unit + penalty. Total = adjusted price + adjusted penalty + adjusted design fee − `Ship.Worth(false)`.
- Shipyards: Corellian (Large, Crew), Incom (Medium, Shield), Kuat (Huge, Hull), Sienar (Tiny, Weapon), Sorosuub (Small, Fuel).
- Maximum 20 fuel tanks and 5 of each slot type. Construction requires ≤100% of max units.

# 5. Crew and skills

**New commander:** 20 points spread over 4 skills, each 1–10 (`Form_NewCommander.cs:384`). The number of points doesn't depend on difficulty.

**Effective ship skill** (`Ship.Skills`, Ship.cs:1228):
- For each skill, take the max over crew (floor 1).
- Adjust for difficulty: Beginner/Easy +1, Hard/Impossible −1 (`Functions.AdjustSkillForDifficulty`), then floor at 1.
- Add +3 for each gadget with that bonus. There's no cap, so skills can exceed 10.
- Trader also gets +1 from the haggling computer.

**Mercenary pay:** `Rate = (P+F+T+E)*3` per day. Special characters and Zeethibal are free. It's paid on each departure (`MercenaryCosts`). Hiring needs a free quarter and doesn't check cash.

**Firing:** a fired normal mercenary moves to a random system within distance 20 (<20) of you. Mercenaries lost through jail or the escape pod keep their old system id.

**Skill changes**
- `IncreaseRandomSkill` → `ChangeRandomSkill(+1)` picks among skills where `skill+amt>0 && skill+amt<10`. This means random increases can **only reach 9** (quirk).
- Bad tonic (`TonicTweakRandomSkill`): below Hard, +1 to one skill and −1 to another, repeated until something changes. On Hard or above: +1, +1, −3.

# 6. Travel and time

**Warp** (Game.cs:3153). Blocked if debt >100000, or if cash < mercenaries, < mercenaries+insurance, or < mercenaries+insurance+wormhole tax.
- If Wild is on board and you have no Beam laser or better, he leaves unless you cancel.
- `ArrivedViaWormhole = WormholeExists(cur, target)`.
- Normal warp calls `NormalDeparture(fuel)`:
  1. cash −= mercenaries + insurance + wormhole costs
  2. fuel −= distance (0 through a wormhole)
  3. `PayInterest()`
  4. `IncDays(1)`
- A singularity jump (`Warp(true)`) skips NormalDeparture entirely: no costs, no fuel, **no day passes**. It adds the ExperimentArrival news.
- Then: the current system's CountDown is set, news is reset, `CalculatePrices(WarpSystem)` runs, then `Travel()`, then `Arrival()`.
- `DestOk` = target ≠ current and (distance ≤ fuel, or a wormhole leads there).

**`Travel()`** (3105)
- Fabric rip: if the experiment was performed and probability >0, and (probability == 25 or `GetRandom(100) < prob`), the destination becomes a random system. The first trip after the experiment always rips.
- Resets Raided, Inspected and LitterWarning; `Clicks=20`.
- Loop while Clicks>0: `Ship.PerformRepairs()`, then `DetermineEncounter()` (shows the encounter form); then `Clicks--`.
  - Arrested sets Clicks=0 and calls `Arrested()`.
  - Escape pod sets Clicks=0 and calls `EscapeWithPod()`.
  - Killed throws GameEnd.
  - After arrest or escape pod you still arrive at the destination.

**`PerformRepairs`** (per click): `r = GetRandom(Engineer)` goes to hull; any leftover ×2 goes to shields in order. A disabled opponent can't repair.

**`Arrival()`** (309) runs these in order:
1. Set the current system and mark it visited; reset the newspaper flag; auto-untrack the system if the option is on.
2. `ArrivalCheckReactor()`
3. `ArrivalCheckTribbles()`
4. `ArrivalCheckDebt()`: debt ≥75000 gives a warning; otherwise, with RemindLoans on, a reminder when debt >0 and days%5==0.
5. `ArrivalPerformRepairs()`: hull += `min(missing, GetRandom(Engineer))`; shields fully recharge; then auto-fuel and auto-repair if the options are on and you can afford them.
6. Pressures and quantities update.
7. Easter egg: at Og, if every cargo slot holds exactly 1 unit and a shield slot is free, you get a Lightning Shield and the cargo is cleared.
8. `CalculatePrices`, news events, and the newspaper if auto-show is on.

**`IncDays(n)`** (2584)
1. days += n; no-claim += n if insured (capped at 90).
2. Positive police record: `max(0, rec - n/3)`. Record below −5: `min(-5, rec + n/(diff<=Normal?1:diff))`. Integer division means n=1 gives 0 change in several cases (see §13).
3. Space Monster hull: `min(max, (int)(hull*1.05^n))`.
4. Gemulon, reactor and experiment counters (see §10); the fabric rip probability drops by n.
5. Passenger impatience for Jarek, Princess and Wild.

**Daily costs**
- Insurance = `max(1, BaseWorth(true)*0.0025*(100-NoClaim)/100)`.
- Interest = `max(1, (int)(Debt*0.10))`, charged per warp. If cash ≤ interest, the shortfall is added to debt.

**Newspaper**
- Costs diff+1, paid once per system visit.
- Content, in order: news events; internal pressure; a villain/psychopath story if record ≤ −70, or a hero story if ≥75.
- For each other reachable system: Moon for sale and TribbleBuyer events, and shipyards, are always shown. A pressure story appears if `GetRandom2(100) <= 6*tech + 10*(5-diff)` (`StoryProbability = 50/8 = 6`).
- If there are no pressure stories, it shows canned headlines for the government type.

# 7. Encounters

**Order:** the fixed (non-random) checks run first, then the random roll (`DetermineEncounter`).

**Fixed encounters** (Game.cs:778):
- Click 1, destination Acamar, monster status 1: Space Monster (Ignore if you're cloaked).
- Arrived via wormhole, click 20, destination's event is ScarabDestroyed, Scarab status 1: Scarab.
- Click 1, Zalkon, Dragonfly status 4: Dragonfly.
- Click 1, Qonos, Princess status 3: Scorpion.
- Click 1 and you just looted the Marie Celeste: police, `MarieCelestePolice`.

**Random encounters** (917)
- If the destination is Gemulon and the invasion was too late: Mantis on `GetRandom(10)>4`, which happens on every click.
- Otherwise `r = GetRandom(44 - 2*diff)`. In a Flea, `r *= 2`.
- `policeMod = max(1, 3 - recordTypeIndex)`, where Psychopath=0 … Hero=9.
- Pirates if `r < pirateActivity` (and not Raided this trip).
- Police if `r < pirates + police*policeMod`.
- Trader if `r < … + traders`.
- Otherwise, if Wild is on board and the destination is Kravat: police with probability `100/max(2,min(4,5-diff))` %.
- Otherwise, if the artifact is on board and `GetRandom(20)<=3`: Mantis.
- If nothing happened, days >10, `GetRandom(1000) < 5` and the very-rare list isn't empty: very-rare encounter.

**Pirate encounter**
- Mantis always attacks.
- Otherwise: Ignore if you're cloaked. Attack if the opponent's ship type > yours, or type ≥ Grasshopper, or `GetRandom(1500) > Rep*4/(1+oppType)`. Otherwise Flee.
- Shown if Attack, or if neither (the opponent is cloaked) nor AlwaysIgnorePirates.

**Police encounter** (864)
- Default is Ignore.
- If you're not cloaked and your record is < −5: if `(opp has weapons && (Rep<40 || GetRandom(1500) > Rep/(1+type))) || oppType > yourType`, then Surrender-demand if record ≥ −30, else Attack. Otherwise Ignore if the opponent is cloaked, else Flee.
- Else, if not yet inspected this trip and (record <0, or record <5 with `GetRandom(12-diff)<1`, or record ≥5 with `GetRandom(40)==0`): Inspect.
- Shown if Attack, Inspect, or neither (opponent cloaked) nor AlwaysIgnorePolice.

**Trader encounter**
- Default is Ignore.
- If you're not cloaked: Flee if record ≤ −30 and `GetRandom(1500) <= Rep*10/(1+type)`.
- Else, if `GetRandom(1000) < 100`: trader Sell (you buy) if you have free bays and the trader has tradeable items; else trader Buy if you have tradeable items.
- Hidden if the opponent is cloaked, or AlwaysIgnoreTraders applies to Ignore/Flee, or AlwaysIgnoreTradeInOrbit applies to Buy/Sell.

**Encounter types** (enum values):

| Value | Type | Value | Type | Value | Type |
|---|---|---|---|---|---|
| 0 | BottleGood | 12 | PirateIgnore | 24 | ScorpionAttack |
| 1 | BottleOld | 13 | PirateFlee | 25 | ScorpionIgnore |
| 2 | CaptainAhab | 14 | PirateSurrender | 26 | SpaceMonsterAttack |
| 3 | CaptainConrad | 15 | PirateDisabled | 27 | SpaceMonsterIgnore |
| 4 | CaptainHuie | 16 | PoliceAttack | 28 | TraderAttack |
| 5 | DragonflyAttack | 17 | PoliceIgnore | 29 | TraderIgnore |
| 6 | DragonflyIgnore | 18 | PoliceFlee | 30 | TraderFlee |
| 7 | FamousCaptainAttack | 19 | PoliceSurrender | 31 | TraderSurrender |
| 8 | FamousCaptDisabled | 20 | PoliceDisabled | 32 | TraderDisabled |
| 9 | MarieCeleste | 21 | PoliceInspect | 33 | TraderBuy |
| 10 | MarieCelestePolice | 22 | ScarabAttack | 34 | TraderSell |
| 11 | PirateAttack | 23 | ScarabIgnore | | |

**Opponent generation** (`Ship(OpponentType)`, Ship.cs:56)
- Ship type: pirates get tries = `max(1, 1 + Worth/100000 + diff-2)`.
- Police get tries 5 if record < −100 or Wild is on board, 3 if record < −70, else 1; then `max(1, tries + diff-2)`.
- Traders get tries 1.
- Each try picks a weighted ship (Occurrence) among indices 0..9 where `ShipTypeLikely` holds: `activity + max(0, diff-2) >= spec.{Pirates|Police|Traders}`. The best index wins. Police and pirates start at Gnat, traders at Flea.
- Equipment tries = Mantis: diff+1; else `max(1, Worth/150000 + diff-2)`.
- Crew: crew[0] is the shared "Opponent" merc with P, F, T, E each `1+GetRandom(10)`.
  - Crew count is all quarters on Impossible; otherwise `1+GetRandom(quarters)`, with +1 on Hard if below max.
  - Extra crew are random non-special mercenaries.
- Gadgets: count is all slots on Impossible, else `GetRandom(slots+1)`, +1 if `tries>4 || (tries>2 && coin)`. Each slot takes the best of `tries` weighted draws not already owned.
- Shields: same, but the +1 rule is `tries>3 || (tries>1 && coin)`. Charge = best of 5 draws of `1+GetRandom(power)`.
- Weapons: all slots on Impossible; 1 if there's only one slot; else `1+GetRandom(slots)`, +1 if `tries>4 || (tries>3 && coin)`. Duplicates aren't excluded.
- Hull (not for Mantis): if the ship has no shields, or on a 1-in-5 roll, hull = best of 5 draws of `1+GetRandom(HullStrength)`.
- Cargo (not for police): bays = CargoBays. On Normal or above, bays = `min(15, 3+GetRandom(bays-5))`.
  - Pirates: ×4/5 below Normal, else `max(1, bays/diff)`.
  - Fill loop: item = `GetRandom(10)`, amount = `min(remaining, 1+GetRandom(10-item))`.
- Famous Captain: Wasp, all slots Reflective and Military, Nav + Targeting, crew FamousCaptain.
- Bottle: the Bottle spec.

**Combat round** (`EncounterExecuteAction` 1142)
- In attack types, the opponent fires at you first (with "defender fleeing" = you are fleeing). Then you fire, unless you're fleeing.
- In opponent Flee/Surrender types, only you fire, with defender fleeing = true.
- In other types, only you fire.

**`EncounterExecuteAttack`** (1288), in order:
1. On Beginner, if you're the fleeing defender, you're never hit.
2. Hit if you're the attacker, the opponent is disabled and you have a Targeting System; or if `GetRandom(F_att + defenderSize) >= (fleeing?2:1)*GetRandom(5 + P_def/2)`.
3. If you hit a disabled opponent, its hull becomes 0.
4. Otherwise: lasers = power of Pulse..Morgan's; disruptors = power of Photon..Quantum. Against the Scarab, Beam, Military and Photon are excluded.
5. If the defender can be disabled, its shield charge is 0, it isn't already disabled, the DisableOpponents option is on and you have disruptors: `disrupt = GetRandom(disr*(100+2F)/100)`, and no damage is dealt.
6. Otherwise `damage = GetRandom(weapons*(100+2F)/100)`. If damage >0 it counts as a hit:
   - Reactor on board: `damage *= (int)(1 + (diff+1)*(diff<Normal?0.25:0.33))`. The cast truncates the factor to 1,1,1,2,2 by difficulty.
   - Shields absorb in order.
   - Remaining damage: `max(1, dmg - GetRandom(E_def))`; `disrupt = dmg*disr/weapons`; `dmg -= disrupt`.
   - Cap: `HullStrength / (you ? max(1, 4-diff) : 2)`, i.e. Beginner 4, Easy 3, Normal 2, Hard/Impossible 1.
   - If Scarab status == 3: `dmg /= 2` (applies to every defender; bug).
   - `hull = max(0, hull-dmg)`.
7. Disable check: if hull >0, the defender can be disabled, and `GetRandom(100) < disrupt*3*100/hull`, it becomes disabled.
8. The Scorpion never dies: at hull 0 it becomes hull 1 and disabled.
- The Bottle, Mantis and Space Monster can't be disabled, and neither can your own ship.

**Round outcome**
- Your hull ≤0: escape pod if you have one, otherwise Killed.
- Opponent disabled: if it's the Dragonfly, Scarab or Scorpion, it counts as defeated (rep += type/2+1). Otherwise the encounter type updates.
- Opponent hull ≤0: `EncounterWon`.
- Otherwise check escapes:
  - You escape if Beginner, or `(GetRandom(7) + Pilot/3)*2 >= GetRandom(oppPilot)*(2+diff)`.
  - The opponent escapes if `GetRandom(yourPilot)*4 <= GetRandom(7+oppPilot/3)*2`.
- Otherwise `EncounterUpdateEncounterType` (1519), with chance = GetRandom(100), applied only if the opponent took damage or was disabled:
  - **Pirates**: disabled → PirateDisabled. If opponent hull < 2/3 of before: when your hull < 2/3 of before, Flee with chance <60; else Surrender with chance <10 (never Mantis), otherwise Flee.
  - **Police**: disabled → PoliceDisabled. If opponent hull < 1/2 and (your hull ≥ 1/2 or chance <40): Flee.
  - **Traders**: disabled → TraderDisabled. If hull < 2/3: Surrender with chance <60, else Flee. Else if hull < 9/10 and ((yours < 2/3 && chance<20) || (yours < 9/10 && chance<60) || yours ≥ 9/10): Flee.
  - **Famous captain**: disabled → FamousCaptDisabled.
- Continuous attack (option): sets ContinueFleeing or ContinueAttacking under the conditions at 1273.

**Attacking** (`EncounterVerifyAttack` 1586)
- Needs weapons. Lasers are required if the opponent can't be disabled; disruptors are required against the Scorpion.
- Ignore types become Attack (type−1).
- Police (Inspect, Ignore, Flee, Surrender, MarieCelestePolice): confirm if record > −30; then record = min(rec, −30) − 3; the type becomes PoliceAttack unless it was Flee.
- Trader (Buy, Ignore, Sell): if record <0, −2; else confirm and record = −5. Then, like TraderAttack/TraderSurrender: Flee if `GetRandom(1500) <= Rep*10/(type+1)` or the opponent has no weapons, else Attack.
- Famous captains: record = min(rec, −70) − 2; news "attacked"; FamousCaptainAttack.

**Fleeing**
- From Inspect (only if you carry something illegal, or you confirm anyway): record = `min(rec-2, -5 - (diff<Normal?0:1))`.
- From MarieCelestePolice: record = `min(rec-3, -30)`.
- Both become PoliceAttack.

**Submit to inspection**
- If illegal goods are detectable (illegal units > hidden bays) or illegal special cargo is aboard: goods are removed; fine = `clamp(100, 10000, ceil(Worth/((4-diff+2)*10)/50)*50)`; any unpaid part goes to debt; record −1.
- If special cargo (Wild, Reactor, Sculpture) is aboard, the result is Arrested.
- If clean: record +1.

**Bribe** (inspection or Marie police; never Marie)
- Needs gov BribeLevel >0.
- diffMod = `10+5*(4-diff)`; passMod = special cargo ? (diff≤Normal?2:3) : 1.
- Bribe = `clamp(100, 10000, ceil(Worth/bribeLevel/diffMod/100)*100*passMod)`.

**Yield** (Marie police): with special cargo, you're arrested. Otherwise record = min(rec, −5) and illegal goods are removed.

**Surrender**
- To the Mantis: only if the artifact is aboard; it's taken and the artifact status goes back to 0.
- To police (Attack or Surrender-demand): refused if record ≤ −100, else Arrested.
- To pirates: refused if the Princess is aboard without hidden bays. Otherwise Raided = true.
  - The sculpture is taken (status 0) unless hidden.
  - Cargo is sorted by item index descending (Robots first); the top `HiddenBays` items (−1 for the Princess, −1 for the Sculpture) are protected. Pirates take items one at a time while they have free bays.
  - If there's no stealable cargo: blackmail = `min(25000, max(500, Worth/20))`, cash first and then debt.
  - Wild joins the pirates if their quarters >1, otherwise he just chats.

**Winning** (`EncounterWon` 1968)
- Pirate (not Mantis): bounty paid if record ≥ −5; record +1; scoop.
- Police: record −6.
- Trader: record −4; scoop.
- Monster: record +1, monster status 2.
- Dragonfly or Scarab: record +1 and status set.
- Famous captain: rep = max(300, rep+100) (if below 300 it's set to 300, else +100); traders-killed +1; the news item changes from attacked to destroyed.
- Always: rep += `(int)oppType/2 + 1`. The kill counters increment.

**Scoop** (after a kill): succeeds if diff < Normal, or `GetRandom(diff)==0` (about 50%, 33%, 25%), and the opponent has cargo. It picks a random filled unit and offers it to you, letting you jettison if you're full.

**Plunder** (disabled or surrendered opponent)
- You take cargo freely, with a cost basis of 0.
- Trader types (≥ TraderAttack): record −2, and traders-killed +1 if the trader was disabled.
- Disabled pirate: bounty if record ≥ −5; record +1; pirates-killed +1.
- Surrendered pirate: record −1.
- Always rep += type/2+1.

**Very rare encounters** (picked uniformly from the remaining list; removed only if their condition holds)
- **Marie Celeste**: needs clicks >1 and a current (departure) system other than Acamar, Zalkon or Qonos. It's a trader ship whose cargo is replaced by Narcotics = min(bays, 5). Boarding opens plunder; taking narcotics sets JustLootedMarie, which brings the police at click 1.
- **Captain Ahab**: needs a Reflective shield, Commander.Pilot <10 and record > −30. **Conrad**: a Military Laser and Engineer <10. **Huie**: a Military Laser and Trader <10.
  - Meeting a captain swaps the item for +2 skill (+1 on Hard or above), capped at 10.
- **Good tonic**: +1 random skill, +1 more if diff ≤ Normal. **Old tonic**: the tweak in §5.

**Arrested** (Game.cs:202)
- Term = `max(30, -rec)` days. Fine = `(1 + Worth*min(80,-rec)/50000)*500`, ×1.05 if Wild is aboard.
- Then, in order:
  1. Hidden bays are removed.
  2. The reactor is confiscated (status 0), the sculpture too (status 0), and Wild is taken (status 0, news).
  3. Illegal goods are removed.
  4. Insurance is lost (no-claim 0).
  5. Mercenaries leave; Jarek goes back to status 0, the Princess to 0, and Japori in transit becomes done (antidote taken).
  6. Pay the fine. If you can't, cash = `max(0, cash + Ship.Worth(true) - fine)`, the ship is sold and you get a new Flea.
  7. Debt is paid down from cash; if debt remains, interest is charged `term` times.
  8. Record = −5; `IncDays(term)`.

**Escape pod** (2031)
- The sculpture is saved, the reactor is destroyed (status 22), and tribbles die.
- Japori in transit goes back to 0 (antidote destroyed). The artifact is lost (status 2). Jarek goes to 0 and the Princess to 0. Wild: record −4 and status 0.
- Insurance pays `BaseWorth(true)` of the wrecked ship (hull 0, so repairs are subtracted).
- Pay 500 for the Flea (debt if you can't); 3 days pass; new Flea with insurance off.

**Tribbles on arrival** (395)
- With the reactor: under 20 they all die, otherwise they halve.
- With narcotics: dead = `min(1+GetRandom(3), narcs)`; that many narcotics become Furs; tribbles −= `min(dead*(GetRandom(5)+98), tribbles-1)`.
- Otherwise, if there's food: eaten = `food - GetRandom(food)`, tribbles += eaten×100. Then `+1+GetRandom(food>0 ? t : t/2)`, capped at 100000.
- An inspector alert fires when crossing 100, 1000, 10000, 50000 or the max.
- With tribbles aboard, trade-in value is 1/4 instead of 3/4. The tribble buyer pays tribbles/2.

# 8. Police record and reputation

**Police record** (minimum score per level): Psychopath ≤ (below −70), Villain −70, Criminal −30, Crook −10, Dubious −5, Clean 0, Lawful 5, Trusted 10, Liked 25, Hero 75. A score is classified as the highest level whose minimum it meets. `GetPoliceRecordFromScore` ignores its argument and uses the commander's score.

**Reputation:** Harmless 0, Mostly harmless 10, Poor 20, Average 40, Above average 80, Competent 150, Dangerous 300, Deadly 600, Elite 1500.

**Score constants:** AttackPirate 0, AttackPolice −3, AttackTrader −2, CaughtWithWild −4, FleePolice −2, KillCaptain +100 (reputation), KillPirate +1, KillPolice −6, KillTrader −4, PlunderPirate −1, PlunderTrader −2, Trafficking −1. "Criminal" in price rules means record < −5. `BountyModifier`, `CloakBonus` and `ReactionIllegal` are unused.

# 9. Bank

- **Max loan:** record ≥0 gives `min(25000, max(1000, Worth/5000*500))`; otherwise 500.
- `Worth` (Commander.cs) = `Ship.Price` (the ship type's list price, **not** its trade-in value) + cash − debt + (moon bought ? 500000 : 0).
- **Interest:** 10% of debt per warp, minimum 1. Debt >100000 blocks warping and buying cargo. Any debt >0 blocks buying equipment or ships (when the net price is >0). Repaying is limited to min(debt, cash).
- **Insurance:** needs an escape pod. Cost is in §6; no-claim maximum is 90. Stopping it resets no-claim.

# 10. Special events and quests

**Event table** (type: price, occurrence, message-only?). A negative price is credit you receive (`cash -= price`).
```
Artifact 0,1,F | ArtifactDelivery -20000,0,T | CargoForSale 1000,3,F | Dragonfly 0,1,T | DragonflyBaratas 0,0,T
DragonflyDestroyed 0,0,T | DragonflyMelina 0,0,T | DragonflyRegulas 0,0,T | DragonflyShield 0,0,F | EraseRecord 5000,3,F
Experiment 0,0,T | ExperimentFailed 0,0,T | ExperimentStopped 0,0,T | Gemulon 0,0,T | GemulonFuel 0,0,F | GemulonInvaded 0,0,T
GemulonRescued 0,0,T | Japori 0,1,F | JaporiDelivery 0,0,T | Jarek 0,1,F | JarekGetsOut 0,0,T | Lottery -1000,0,T
Moon 500000,4,F | MoonRetirement 0,0,F | Reactor 0,0,F | ReactorDelivered 0,0,T | ReactorLaser 0,0,F | Scarab 0,1,T
ScarabDestroyed 0,0,T | ScarabUpgradeHull 0,0,F | Skill 3000,3,F | SpaceMonster 0,1,T | SpaceMonsterKilled -15000,0,T
Tribble 1000,1,F | TribbleBuyer 0,3,F | Wild 0,1,F | WildGetsOut 0,0,T | Sculpture -2000,0,F | SculptureDelivered 0,0,T
SculptureHiddenBays 0,0,F | Princess 0,0,T | PrincessCentauri 0,0,T | PrincessInthara 0,0,T | PrincessQonos 0,0,F
PrincessQuantum 0,0,F | PrincessReturned 0,0,T
```
- The button needs `ShowSpecialButton()` (StarSystem.cs) and `CashToSpend >= price`.
- `HandleSpecialEvent` (2270) then deducts the price and removes the event unless `remove=false`. The price is charged even when the action fails for lack of slots, bays or quarters, but all those events cost 0.

**Status codes** (SpecialEvent.cs):

| Quest | Codes |
|---|---|
| Artifact | 0 / 1 on board / 2 done |
| Dragonfly | 0, 1 Baratas, 2 Melina, 3 Regulas, 4 Zalkon, 5 destroyed, 6 done |
| Experiment | 0, 1..11 counting, 12 performed, 13 cancelled |
| Gemulon | 0, 1..7, 8 too late, 9 fuel offered, 10 done |
| Japori | 0, 1 in transit, 2 done |
| Jarek / Wild | 0, 1..11 (impatient at 11), 12 done |
| Moon | 0, 1 bought, 2 done |
| Princess | 0, 1 Centauri, 2 Inthara, 3 Qonos, 4 rescued, ..14 impatient, 15 returned, 16 done |
| Reactor | 0, 1..20 (20 = meltdown), 21 delivered, 22 done |
| Scarab | 0, 1 hunting, 2 destroyed, 3 done (hull upgrade) |
| Sculpture | 0, 1, 2, 3 |
| Space Monster | 0, 1 at Acamar, 2 destroyed, 3 done |

**Visibility rules**
- Record ≥ −5: Artifact, Dragonfly, Experiment, Jarek, Japori (Japori also needs status 0).
- Record < −5: EraseRecord, Wild.
- Reactor and Sculpture: status 0, record < −5 and rep ≥ 40.
- Scarab: status 0 and rep ≥ 40. Princess (Galvon): record ≥ 5 and rep ≥ 40.
- Moon: status 0 and Worth > 400000. CargoForSale: ≥3 free bays. TribbleBuyer: you have tribbles.
- Follow-up events show only at the right status.

**Quest chains**
- **Dragonfly:** each event increments the status. Destroy or disable it at Zalkon, click 1. At Zalkon, DragonflyDestroyed becomes DragonflyShield, which installs a Lightning Shield (needs a free shield slot) and sets status 6.
- **Space Monster:** status 1; kill it at Acamar, click 1 → 2. At Acamar you get +15000 and status 3.
- **Scarab:** status 1. Encountered on the first click after arriving by wormhole at the system that has ScarabDestroyed. Destroy or disable → 2. The event then becomes UpgradeHull: `HullUpgraded=true`, hull +50, status 3, which also halves hull damage (see §13). The upgrade is lost on buying a new ship, which resets the status to 0.
- **Japori:** needs 10 free bays, status 1; the antidote occupies 10 bays. Delivering gives status 2 and 2 random skill increases. The pickup event is never removed.
- **Jarek:** needs a free quarter. Concerned at status 5; at status 10 he becomes impatient and his skills drop to 0. At Devidia: status 12, he leaves, and you get the haggling computer (Trader +1).
- **Wild:** needs a free quarter, a weapon of Beam or higher enum value, and no reactor. He leaves if you warp without such a weapon. At Kravat: Zeethibal appears at Kravat with skill 10 in your lowest skill, 8 in your second lowest and 5 in the rest; your record becomes 0; Wild leaves. Police tries rise to 5, Kravat has heavy police, and arrest fines are ×1.05.
- **Reactor:** needs 15 free bays; Wild refuses to come along. Bays used = `5 + 10 - (status-1)/2`. The status counts up daily. Warnings come at statuses 2, 16 and 18; at 20 you melt down (escape pod or death). Combat damage against you is boosted. At Nix: status 21, then Morgan's Laser (needs a weapon slot), status 22. Tribbles halve or die.
- **Gemulon:** status 1, counting daily. At 8 Gemulon is invaded (tech PreAg, Anarchy, event GemulonInvaded), with Mantis encounters on the way there. Arriving at 1..7 gives status 9, then the Fuel Compactor (needs a gadget slot), status 10.
- **Experiment:** status 1 counting. At 12: performed; fabric rip probability 25; Daled gets ExperimentFailed; news. Reaching Daled first: status 13 and the Portable Singularity (one free jump anywhere).
- **Artifact:** status 1; Mantis attacks (§7). Delivery gives +20000 and status 2.
- **Sculpture:** pays +2000 up front, status 1. Pirates take it unless hidden; police confiscate it. At Endor: status 2, then Hidden Cargo Bays (needs a gadget slot), status 3.
- **Princess:** the Galvon event sets status 1 and the Galvon event becomes PrincessReturned. Centauri → 2, Inthara → 3. The Scorpion at Qonos, click 1, needs disruptors and must be disabled → 4. At Qonos the Princess boards (needs a quarter). She counts up daily: concerned at 9, impatient at 13. At Galvon she leaves, status 15, then the Quantum Disruptor (needs a weapon slot), status 16.
- **Moon:** pay 500000, status 1. At Utopia: MoonRetirement ends the game (BoughtMoon).
- **Others:** CargoForSale gives 3 units of a random item with cost basis +1000. Skill: +1 random skill. EraseRecord: record 0 and sell prices ×100/90. Tribble: 1 tribble. TribbleBuyer: cash += tribbles/2. Lottery: +1000.

# 11. Game end and scoring

- Endings: Killed (no pod, or reactor meltdown without a pod), Retired (menu), BoughtMoon. BoughtMoonGirl exists but is never set.
- **Score** (Game.cs:4246):
  ```
  w = worth<1e6 ? worth : 1e6 + (worth-1e6)/10
  Killed: mod=90 | Retired: mod=95 | Moon: mod=100, daysMoon = max(0, (diff+1)*100 - days)
  score = (diff+1)*mod*(daysMoon*1000 + w)/250000
  ```
  It's displayed as `score/10 . score%10` %.
- **High scores:** there are 3 slots. A new score replaces slot [0] if it's greater (comparing score, then worth, then days), and the array is re-sorted ascending. It isn't recorded if cheats were enabled.

# 12. Options and difficulty

**Options** (defaults): AlwaysIgnorePirates F, AlwaysIgnorePolice F, AlwaysIgnoreTradeInOrbit F, **AlwaysIgnoreTraders T**, AutoFuel F, AutoRepair F, ContinuousAttack F, ContinuousAttackFleeing F, DisableOpponents F, NewsAutoPay F, NewsAutoShow F, **RemindLoans T**, ReserveMoney F (CashToSpend = cash − current costs), **ShowTrackedRange T**, **TrackAutoOff T**, LeaveEmpty 0. They load from DefaultSettings.bin.

**Difficulty effects** (Beginner 0 .. Impossible 4)

*Universe and setup*
- Lottery at the start system: Beginner and Easy only.
- Narcotics and Robots quantity factor: `(5-d)/(6-d)`.
- Restock countdown: `d+3`.

*Your skills and travel*
- Ship skills: +1 on Beginner/Easy, −1 on Hard/Impossible.
- Encounter roll range: `44-2d`.
- Record recovery divisor: Hard 3, Impossible 4.
- Newspaper cost: `d+1`.
- Story chance: `+10*(5-d)`.

*Opponents*
- Opponent ship, equipment and crew tries include `+d-2`; `ShipTypeLikely` gets `+max(0,d-2)`.
- On Impossible, opponents have full equipment and crew.
- Pirate cargo: §7.
- Mantis tries: `d+1`.
- Special ship crews: `+d`.

*Combat*
- Hull damage cap: Beginner 4, Easy 3, Normal 2, Hard/Impossible 1 hits.
- Reactor damage factor: §7.
- Flee formula: `×(2+d)`; Beginner always escapes and is never hit while fleeing.
- Scoop chance: §7.

*Police*
- Inspection chance: `1/(12-d)`.
- Flee-inspection penalty: −1 extra on Normal or above.
- Fine divisor: `(6-d)*10`.
- Bribe diffMod: §7; passenger multiplier 2 or 3.
- Jettison caught chance: `(d+1)/10`.
- Dump cost: `5*(d+1)`.
- Kravat Wild police: §7.

*Rewards and scoring*
- Captain and tonic bonuses: +2 on Normal or below, +1 above.
- Score multiplier: `(d+1)`; moon days `(d+1)*100`.

# 13. Cheats, debug and port quirks

**Cheats** (Find box, Form_SpaceTrader.cs:3298)
- "Cheetah" enables cheats (`CheatEnabled`, which then blocks high scores).
- With cheats on:

  | Command | Effect |
  |---|---|
  | Bazaar n | trade-in-orbit chance (out of 1000) |
  | Cover i j | set shield slot i to shield type j |
  | DeLorean n | days |
  | Diamond | toggle hull upgrade |
  | Energize | toggle singularity |
  | Events / Events Reset | list or reset very-rare encounters |
  | Fame n | reputation |
  | Go name | warp directly, no travel |
  | Ice Pirate/Police/Trader n | kill counts |
  | Indemnity n | no-claim |
  | IOU n | debt |
  | Iron i j | set weapon slot i to weapon type j |
  | Juice n | fuel |
  | Knack id a,b,c,d | set a mercenary's skills |
  | L'Engle n | fabric rip probability |
  | LifeBoat | toggle escape pod |
  | Monster.com | shows `Form_Monster`, a list of quest, mercenary and shipyard locations |
  | PlanB | autosave on |
  | Posse slot id | put mercenary `id` in crew slot |
  | RapSheet n | police record |
  | Rarity n | very-rare chance |
  | Scratch n | cash |
  | Skin n | hull |
  | Status quest n | set a quest status (no quest name shows all) |
  | Swag i n | cargo |
  | Test | opens `Form_Test`, which tests alerts and event dialogs |
  | Tool i j | set gadget slot i to gadget type j |
  | Varmints n | tribbles |
  | Yellow | EasyEncounters: lets you close the encounter window |

**Bugs and quirks** (decide whether to keep them)
1. **Infinite money.** Neither `TradeShip` nor `CreateFlea` resets `Commander.PriceCargo`, but ship trade-in (`Worth(false)`) adds PriceCargo. Buying a ship refunds your cargo's purchase cost and then the cargo vanishes. Each later ship purchase refunds the stale total again.
2. **Arrest can pay you.** With a positive record (for example, submitting while carrying special cargo), `min(80,-rec)` is negative, so the fine can be negative and adds cash.
3. **Records barely change day to day.** `IncDays` uses `num/3` and `num/diff` with integer division. A positive record never drops on 1-day warps, and a criminal record never improves on Hard or Impossible. The Palm original used `Days%3` and `Days%diff` checks.
4. The hardened-hull halving applies to **any** defender, opponents included, while Scarab status == 3.
5. Random skill increases cap at 9 (`< MaxSkill`).
6. Worth uses the hull's list `Price`, not trade-in value. Ships get no trader discount.
7. Special resources are hidden until a system is visited (`SpecialResource` getter), so initial quantities never use them.
8. Restocking uses `WarpSystem.ItemTraded` instead of the system's own (Game.cs:526).
9. Price variance is in absolute credits, not percent.
10. The trader-buy dialog limits quantity using the *system* buy price, but charges the adjusted in-orbit price, so cash can go negative.
11. The Kravat "engineer 10" boost checks `WildOnBoard` on the *opponent* ship, so it never triggers.
12. The Marie Celeste location check uses the departure system.
13. Disruptors count as "Beam laser or better" for Wild (enum order).
14. Morgan's Laser and the Quantum Disruptor damage the Scarab.
15. The singularity jump costs no day, fuel or fees.
16. `StealableCargo.RemoveRange` can throw if hidden bays exceed the cargo held.
17. Shipyards can overwrite each other.
18. `GetRandom2` differs from the Palm generator (64-bit, can go negative).
19. The reactor damage factor is truncated by the int cast.
20. `RecalculateSellPrices` applies ×100/90 even if you weren't a criminal.
21. Mercenaries you lose keep their old system.

**Strings.cs** (about 1273 lines; text only, no logic). Mostly about 200 scalar UI and alert strings, plus:

| Array | Count |
|---|---|
| SystemNames | 128 |
| CrewMemberNames | 55 |
| SpecialEventTitles, SpecialEventStrings | 46 each |
| NewsEvent | 39 |
| NewsHeadlines, NewsMastheads | 17 sets each (one per government) |
| NewsPoliceRecordHero, NewsPoliceRecordPsychopath, NewsPressureExternal | short lists |
| NewsPressureInternal | per pressure |
| PoliticalSystemNames | 17 |
| PoliceRecordNames | 10 |
| ReputationNames | 9 |
| ShipNames | 17 |
| WeaponNames | 6 |
| ShieldNames | 3 |
| GadgetNames | 7 |
| TechLevelNames | 8 |
| TradeItemNames | 10 |
| SpecialResources | 13 |
| SystemPressures | 8 |
| ActivityLevels | 8 |
| Sizes | 6 |
| DifficultyLevels | 5 |
| VeryRareEncounters | 6 |
| Shipyard names, engineers, skills | 5 each |
| ListStrings | 5 |
| EquipmentDescriptions | jagged, per equipment type |

The full alert texts live in `Form_Alert.cs`. Templates use `^1..^n` placeholders (`Functions.StringVars`).
