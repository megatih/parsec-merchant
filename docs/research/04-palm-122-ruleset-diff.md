# Palm OS Space Trader 1.2.2 vs C# 2.01 — Ruleset Diff

> Research 2026-11-16 against https://github.com/videogamepreservation/spacetrader (cross-checked with https://www.spronck.net/spacetrader/SpaceTraderSource.zip) and the local C# tree. Basis for the 'Original Palm 1.2.2' ruleset.


## QA ERRATA (independent fidelity audit, 2026-11-16): these override the text below
All critical claims are **confirmed**: the fuel/repair cost swap (DataTypes.h field order plus Fuel.c, Shipyard.c and ShipPrice.c usage), the backwards equipment roll, the market quantity bug and the offset police constants. Corrections:
1. **MISSING, high impact: commander worth differs.** Palm `CurrentWorth = CurrentShipPrice(false) + Credits - Debt + moon`, where `CurrentShipPrice` is the trade-in value plus the cargo purchase price. C# uses the **list price** `Ship.Price` (Commander.cs:389). This affects max loan, fines, bribes, blackmail, pirate and equipment tries, the moon threshold and the score. Ruleset flag: `worthUsesTradeInValue`.
2. **MISSING: difficulty skill adjustment.** Palm `AdaptDifficulty`: Beginner and Easy +1, **Hard unchanged**, Impossible −1 (minimum 1). C# applies −1 on both Hard and Impossible. Flag needed.
3. **MISSING: C# never spawns a Wasp opponent** (weights cover 0..8). Palm can.
4. **IMPRECISE, police decay "per normal warp only".** In `DoWarp`, the decay, monster heal, shield recharge and Clicks = 21 sit **outside** `if (!viaSingularity)`, so they also run on singularity jumps (using the old day). Only interest, IncDays(1) and ++NoClaim are limited to normal warps.
5. **IMPRECISE, bribe.** The ×2 (≤ Normal) or ×3 (> Normal) multiplier applies **only** when Wild or the reactor is aboard.
6. **IMPRECISE, "extra bays counted in cargo" is not Palm-only.** C# counts them too. The Palm-only differences are the `Bays > 5` guard and police carrying a minimum of 1 unit.
7. **Minor:** C# has 55 crew IDs (0..54, including the commander). The Palm Zeethibal-wage macro also requires `WildStatus == 2`. `RandSeed` truncates its parameters to UInt16 before the zero test. Palm also clamps the restock countdown.

---

I've finished the diff. Everything below comes from the Palm 1.2.2 source (GitHub mirror) and the C# source in `/Users/megatih/Downloads/SpaceTraderSource201`. I checked the most surprising Palm quirks (the 120-system count, the reversed equipment-roll loop, the market-quantity indexing bug) against Spronck's original zip, and they match.

**Big picture:**
- **Content:** Palm has only the 120 original systems and 37 special-event entries: no Princess, Sculpture or Scorpion, no shipyards, no disruptors, no hidden bays, no custom ship designer and no disabling.
- **Fuel and repair costs are swapped in C#.** C# passes Palm's per-hull-point repair cost (1,1,1,1,1,1,2,3,4,5) as `fuelCost` and Palm's per-parsec fuel cost (1,2,3,5,7,10,15,15,20,20) as `repairCost`. So in Palm fuel is expensive, repairs are cheap, and the wormhole tax (25 × fuel cost) is up to 500 cr for a Wasp, against 125 in C#.
- **Palm bugs you must reproduce:**
  - Opponent equipment rolls run backwards, so opponents get far more military lasers, reflective shields and cloaks.
  - Market quantities are scaled by the size of the wrong system.
  - Palm's thresholds named "criminal" and "villain" are the C# Crook and Criminal values, so several police rules trigger much earlier.

Palm files are under `Src/` (e.g. `Src/Traveler.c`). C# files are in the local folder. "C# x" in the tables means C# 2.01.

---

## 1. Constants

| Item | Palm 1.2.2 (`spacetrader.h` unless noted) | C# 2.01 (`Consts.cs` unless noted) |
|---|---|---|
| Systems | `MAXSOLARSYSTEM 120` (Acamar…Zuul) | 128. Same first 120, plus Centauri, Galvon, Inthara, Meridian, Qonos, Rae, Weytahn, Zonama (`Enums.cs`) |
| Galaxy size | `GALAXYWIDTH 150`, `GALAXYHEIGHT 110` | `GalaxyWidth 154`, `GalaxyHeight 110` |
| Minimum spacing | `MINDISTANCE 6`. A system is rejected if squared distance ≤ 7² (exact Euclidean) | `MinDistance 7`. Rejected if floor(distance) < 7 |
| Close distance | `CLOSEDISTANCE 13`: needs some system with squared distance < 169 | 13, using floor(distance) < 13 (same result) |
| Distance function | `Math.c:RealDistance` uses a custom integer sqrt that **rounds to nearest** | `Functions.Distance` uses `Math.Floor(Math.Sqrt())` (**truncates**) |
| Wormholes | `MAXWORMHOLE 6`; tax = `CostOfFuel × 25` | 6; tax = `WormDist 25 × FuelCost` (swapped column) |
| Max range | `MAXRANGE 20` | `MaxRange 20` |
| Fuel compactor | Sets tanks to **18** (`Fuel.c:GetFuelTanks`), which is a downgrade for the Flea | Adds **+3** tanks (`Ship.FuelTanks`) |
| Hull upgrade | `UPGRADEDHULL 50` | `HullUpgrade 50`, plus C# halves hull damage |
| Hireable crew | `MAXCREWMEMBER 31`: index 0 commander, 1–29 mercenaries, 30 Zeethibal, 31 a scratch slot for opponents. One mercenary per system, none on Kravat | 54 IDs (adds Aragorn, Brady, EightOfNine, Fangorn, Gagarin, Hoshi, Jackson, Kaylee, Marcus, ONeill, Ripley, Stilgar, Taggart, Vansen, Xizor, plus special crew). Up to 3 per system |
| Mercenary names 1–30 | Alyssa, Armatur, Bentos, C2U2, Chi'Ti, Crystal, Dane, Deirdre, Doc, Draco, Iranda, Jeremiah, Jujubal, Krydon, Luis, Mercedez, Milete, Muri-L, Mystyc, Nandi, Orestes, Pancho, PS37, Quarck, Sosumi, Uma, Wesley, Wonton, Yorvick, Zeethibal. Default commander names "Jameson" / "Shelby" | Same 30, plus the extras above |
| Start | 1000 cr, Gnat with 1 pulse laser, full tank, 20 skill points (each 1–10), Lottery event on Beginner/Easy | 1000 cr, Gnat, 20 points, Lottery on Beginner/Easy (same) |
| Start-system choice | Up to 200 random tries. Must have no special event. On the first 100 tries the tech level must be 1–**5**. Needs 3 systems within squared distance ≤ 14² (`Traveler.c:StartNewGame`) | Loops forever. Tech level 1–**6**. Needs 3 systems with floor(distance) ≤ 14 (`Game.cs:InitializeCommander`) |
| Market countdown | `STARTCOUNTDOWN 3+Difficulty` | `CountDownStart` (same) |
| Debt limits | 75000 warning, 100000 too large | Same |
| Insurance | `max(1, ((worth×5)/2000) × (100 − min(NoClaim,90)) / 100)`, all integer (`Traveler.c:InsuranceMoney`) | `(int)max(1, worth × 0.0025 × (100 − NoClaim)/100)` (double maths, `Game.InsuranceCosts`) |
| Interest | `max(1, Debt/10)` (`Money.c:PayInterest`) | `max(1, (int)(Debt×0.1))` (same) |
| Tribbles max | 100000 | 100000 |
| Trade-in-orbit chance | 100/1000; very-rare chance 5/1000 | Same |
| High-score slots | `MAXHIGHSCORE 3` | — |
| Escape pod | 2000 cr. Kept free (with insurance) when you buy a new ship | Pod transfer costs `PodTransferCost 200` |

## 2. Tables

**Ships** (`Global.c:Shiptype`, field order: Bays, Weapons, Shields, Gadgets, Crew, Fuel tanks, Min tech, **CostOfFuel**, Price, Bounty, Occurrence %, Hull, Police, Pirates, Traders, **RepairCosts**, Size). Police/Pirates/Traders are the minimum system strength; −1 means never.
```
Flea        10 0 0 0 1 20 4  1   2000   5  2  25 -1 -1  0 1 0
Gnat        15 1 0 1 1 14 5  2  10000  50 28 100  0  0  0 1 1
Firefly     20 1 1 1 1 17 5  3  25000  75 20 100  0  0  0 1 1
Mosquito    15 2 1 1 1 13 5  5  30000 100 20 100  0  1  0 1 1
Bumblebee   25 1 2 2 2 15 5  7  60000 125 15 100  1  1  0 1 2
Beetle      50 0 1 1 3 14 5 10  80000  50  3  50 -1 -1  0 1 2
Hornet      20 3 2 1 2 16 6 15 100000 200  6 150  2  3  1 2 3
Grasshopper 30 2 2 3 3 15 6 15 150000 300  2 150  3  4  2 3 3
Termite     60 1 3 2 3 13 7 20 225000 300  2 200  4  5  3 4 4
Wasp        35 3 2 2 3 14 7 20 300000 500  2 200  5  6  4 5 4
SpaceMonster 0 3 0 0 1  1 8  1 500000   0  0 500  8 8 8 1 4
Dragonfly    0 2 3 2 1  1 8  1 500000   0  0  10  8 8 8 1 1
Mantis       0 3 1 3 3  1 8  1 500000   0  0 300  8 8 8 1 2
Scarab      20 2 0 0 2  1 8  1 500000   0  0 400  8 8 8 1 3
Bottle       0 0 0 0 0  1 8  1    100   0  0  10  8 8 8 1 1
```
- Everything matches C# `ShipSpecs` except the swapped fuel/repair columns.
- C# also adds Custom and Scorpion.
- The Palm Bounty column is unused; the bounty formula is in section 3.

**Weapons / shields / gadgets** (Palm `Global.c`): `{name, power, price, tech, chance}`
- Weapons: Pulse 15/2000/5/50, Beam 25/12500/6/35, Military 35/35000/7/15, Morgan's (not buyable) 85/50000/8/0. C# adds Photon Disruptor 20/15000/6/0 (buyable) and Quantum Disruptor 60/50000/unavailable.
- Shields: Energy 100/5000/5/70, Reflective 200/20000/6/30, Lightning 350/45000/8/0. Same as C#.
- Gadgets: Extra bays 2500/4/35, Auto-repair 7500/5/20, Navigating 15000/6/20, Targeting 25000/6/20, Cloaking 100000/7/5, Fuel compactor 30000/8/0. C# adds Hidden Cargo Bays 60000/unavailable.
- Cloak skill bonus: Palm **+2 pilot** (`CLOAKBONUS`, `Skill.c:PilotSkill`). C# gives the cloak `SkillType.Pilot`, so it gets the standard **+3**.

**Trade items and political systems:** values are identical in both. (C# writes the tech levels as enums; Palm has an extra `-1` "no resource" marker.)

**Police record:**
- Palm table (`Global.c:PoliceRecord`): Psycho −100, Villain −70, Criminal −30, Crook −10, Dubious −5, Clean 0, Lawful 5, Trusted 10, Liked 25, Hero 75. These are the same displayed thresholds as C#; only the first name differs ("Psycho" vs "Psychopath").
- **The trap:** Palm's code constants are offset by one rank. `PSYCHOPATHSCORE = −70`, `VILLAINSCORE = −30`, `CRIMINALSCORE = −10`. Every Palm rule written with "CRIMINALSCORE" therefore means −10, while C# uses −30 (likewise villain −30 vs −70, psychopath −70 vs −100). Section 3 lists where this matters.

**Reputation:** identical in both.

**Difficulty names:** Beginner, Easy, Normal, Hard, Impossible in both.

**Special events** (`Global.c:SpecialEvent`, columns are price/occurrence/message-only; index order matters for placement):
```
0 Dragonfly Destroyed 0/0/T   1 Weird Ship (Baratas) 0/0/T   2 Lightning Ship (Melina) 0/0/T
3 Strange Ship (Regulas) 0/0/T 4 Monster Killed -15000/0/T  5 Medicine Delivery 0/0/T
6 Retirement (Utopia) 0/0/F   --- placed randomly from here (7..29) ---
7 Moon For Sale 500000/4/F    8 Skill Increase 3000/3/F     9 "Merchant Prince"=Tribble 1000/1/F
10 Erase Record 5000/3/F      11 Tribble Buyer 0/3/F        12 Space Monster 0/1/T
13 Dragonfly 0/1/T            14 Cargo For Sale 1000/3/F    15 Lightning Shield 0/0/F
16 Japori Disease 0/1/F       17 Lottery Winner -1000/0/T   18 Artifact Delivery -20000/0/T
19 Alien Artifact 0/1/F       20 Ambassador Jarek 0/1/F     21 Alien Invasion 0/0/T
22 Gemulon Invaded 0/0/T      23 Fuel Compactor 0/0/F       24 Dangerous Experiment 0/0/T
25 Jonathan Wild 0/1/F        26 Morgan's Reactor 0/0/F     27 Install Morgan's Laser 0/0/F
28 Scarab Stolen 0/1/T        29 Upgrade Hull 0/0/F         --- fixed ---
30 Scarab Destroyed 0/0/T     31 Reactor Delivered 0/0/T    32 Jarek Gets Out 0/0/T
33 Gemulon Rescued 0/0/T      34 Disaster Averted 0/0/T     35 Experiment Failed 0/0/T
36 Wild Gets Out 0/0/T
```
- Prices and occurrences match C# for every shared event.
- C# adds Sculpture (−2000), SculptureDelivered, SculptureHiddenBays, Princess, PrincessCentauri, PrincessInthara, PrincessQonos and PrincessQuantum, with the Princess events fixed at Galvon/Centauri/Inthara/Qonos and the Sculpture delivered at Endor.
- The quest texts are string resources in `Rsc/*.rsrc`, not in the C source.
- The same applies to the newspaper mastheads (3 per government) and canned headlines (4 per government).

## 3. Formula and algorithm differences

**Universe generation** (`Traveler.c:StartNewGame` vs `Game.cs:GenerateUniverse` / `PlaceSpecialEvents`)
- **Centre (wormhole) systems:** Palm offset is `6 − rand(13)` (−6..+6) from `W×(1+2(i%3))/6` and `H×(i<3?1:3)/4`. C# offset is −12..+12.
- **Other systems:** Palm `X = 1+rand(148)`, `Y = 1+rand(108)`.
- **Order of rolls per system:** position, then distance checks, then `TL = rand(8)`, `Pol = rand(17)`. If TL is outside that government's min/max, Palm **rejects the whole system and re-rolls everything, including position** (a uniform pick over valid (TL, government) pairs). C# picks a government first, then a TL uniformly inside its range.
- Then: resources (`rand(5)≥3 → 1+rand(12)`), size `rand(5)`, status (`rand(100)<15 → 1+rand(7)`), then `InitializeTradeitems`.
- The position shuffle and wormhole shuffle are the same as C#.
- **Special-event placement in Palm, in order:**
  - Fixed events: Acamar, Baratas, Melina, Regulas, Zalkon, Japori, Utopia, Devidia, Kravat.
  - **Scarab end-point:** random wormhole, up to 20 tries, with a buggy loop condition. If all 20 tries fail there is no Scarab quest. It can land on Gemulon/Daled/Nix and then get overwritten.
  - **Reactor:** the closest system ≥70 parsecs from Nix that has no special. The Gemulon/Daled exclusion is buggy (it compares the distance `d` instead of the index). Nix then gets Reactor Delivered.
  - **Artifact delivery:** up to 120 random tries for a system in 1..119 with TL ≥ 7, not Gemulon/Daled. If none is found, the Alien Artifact event's occurrence becomes 0.
  - **Alien invasion:** closest ≥70 from Gemulon (exclusion again buggy: it tests `k`).
  - **Experiment:** closest ≥70 from Daled.
  - **Random events (indices 7–29):** placed at `1+rand(119)`, so never Acamar.
  - Palm never regenerates the galaxy. C# loops `GenerateUniverse` until every placement succeeds, picks the **first** hi-tech system for the artifact, can place random events at system 0, and also places shipyards.

**Market quantities** (`InitializeTradeitems`)
- `((9+rand(5)) − |TechTopProduction − TL|) × (1 + SolarSystem[i].Size)`, where **`i` is the trade-item index**. This is a Palm bug: it uses the size of systems 0–9. C# uses its own size.
- Robots/narcotics: `×(5−D)/(6−D)+1`. Cheap resource ×4/3. Expensive resource ×3/4 (written `>>2`). Status match /5. Then `−rand(10)+rand(10)`, floored at 0.
- **Market drift** (`ChangeQuantities`): untradeable items are set to 0; tradeable ones get `+rand(5) − rand(5)` (a triangular −4..4). C# uses `GetRandom(−4,5)` (uniform) and also has a bug: it tests `WarpSystem.ItemTraded` instead of each system's own.
- Palm runs `ShuffleStatus` over all systems first, then quantities. C# interleaves the two per system.

**Prices** (`Traveler.c:StandardPrice` / `DeterminePrices`, `Skill.c:RecalculateBuyPrices`)
- The base price is the same as C#.
- Status hike: `×3 >> 1`.
- Variance: Palm `+rand(V) − rand(V)` (two independent rolls, no clamp). C# uses uniform `[−v, v]` with `v = min(V, price−1)`.
- Criminals (score < −5) pay 90% on the sell price.
- Buy price: `(sell×100/90 if criminal) × (103 + 10 − TraderSkill)/100`, at least sell+1.
- The Average Price List uses `StandardPrice` with resources = −1 for unvisited systems.

**Police record decay**
- Palm, in `Traveler.c:DoWarp`, so **once per normal warp only** (not in `IncDays`, not during jail or the pod's 3 days):
```c
if (Days%3 == 0) { if (PoliceRecordScore > CLEANSCORE) --PoliceRecordScore; }
if (PoliceRecordScore < DUBIOUSSCORE)
    if (Difficulty <= NORMAL) ++PoliceRecordScore;
    else if (Days%Difficulty == 0) ++PoliceRecordScore;
```
- C# `Game.IncDays`: `score − num/3` (with num = 1 this never decays a positive record) and `+ num/(D ≤ Normal ? 1 : D)` (never improves on Hard/Impossible). These are bugs.

**Other daily and warp effects**
- **Insurance no-claim counter:** in Palm, `NoClaim++` happens once per normal warp in `DoWarp`. In C# it happens inside `IncDays(num)`, so it counts every day, including jail and pod days.
- **Space monster healing:** Palm `MonsterHull = MonsterHull×105/100` per warp, in integer maths. C# uses `×1.05^num` in `IncDays`.
- **Order of checks in `DoWarp`:**
  1. Wild needs a beam laser or better.
  2. Debt > 100000.
  3. Mercenaries affordable.
  4. Insurance affordable.
  5. Wormhole tax affordable.
  6. Pay all of these.
  7. **Recharge shields (at departure).**
  8. Fuel `−= min(dist, fuel)`.
  9. Interest, `IncDays(1)`, Clicks = 21, decay, `DeterminePrices(WarpSystem)`, then `Travel`.
- A singularity jump skips all payments, interest and the day.
- **Timers:** Palm has no Jarek/Wild impatience. The reactor counter goes up by `Amount`, capped at 20.

**During travel** (`Travel`)
- Per click, engineer repair is `rand(Eng) >> 1` (**halved**; C# `PerformRepairs` does not halve). Overflow beyond hull ×2 goes to the shields, in order.
- Encounter test: `rand(44−2D)`, doubled in a Flea.
  - Pirate if the roll is < pirate strength **and not raided**. **If you have already been raided, that band falls through to the police check.** C# turns it into no encounter.
  - Police band: `StrengthPolice × (3 if score < −70, 2 if < −30, else 1)` (same as C#).
  - Then traders. Then Wild-at-Kravat police: 25% Easy-and-below / 33% Normal / 50% Hard-and-above (same as C#).
  - Then the artifact Mantis check (`rand(20) ≤ 3`). In Palm this runs whenever none of pirate/police/trader is set.
- **Gemulon after invasion:** Mantis if `rand(10) > 4`.
- **Special encounters:**
  - Space monster: click 1, crew stats 8+D / 8+D / 1 / 1+D.
  - Scarab: click 20 via wormhole, 5+D / 6+D / 1 / 6+D.
  - Dragonfly: click 1, 4+D / 6+D / 1 / 6+D.
  - Post-Marie customs police: generated **after the loop ends** (Clicks++), not at click 1.
- **Police reaction** (Palm):
  - Score < −5: attack if reputation < 40 or `rand(1500) > rep/(1+type)`; otherwise ignore if they're cloaked, else flee. There is **no "police surrender" state**, and police with no weapons still attack.
  - Score −5..−1: inspect, if not already inspected.
  - Score < 5: inspect if `rand(12−D) < 1`.
  - Otherwise: inspect if `rand(40) == 1`.
  - If they would flee but their ship is better than yours: attack (if criminal) or inspect.
  - Skipped if they ignore you and are cloaked, or with "always ignore police" when they ignore/flee.
- **Pirates:** the same as C#.
- **Traders flee** when `score <= −10` (Palm criminal), against **−30** in C#, with `rand(1500) ≤ rep×10/(1+type)`. Trade in orbit is rolled only while the trader would ignore you; in Palm that can happen even when you are cloaked.
- **Very rare encounters:** `Days > 10 && rand(1000) < 5`, then `rand(6)` **over all six**. One that's already done or whose conditions fail produces nothing. C# picks from the remaining list.
  - Ahab/Conrad/Huie require **score > −10** (C# > −30).
  - Marie Celeste has no system or click restriction in Palm.

**Opponent generation** (`Traveler.c:GenerateOpponent` vs `Ship.cs`)
- **Police tries:**
```c
if (PRS < -30 && WildStatus != 1) Tries = 3;
else if (PRS < -70 || WildStatus == 1) Tries = 5;
```
  So psychopaths get only 3; only Wild gives 5. Then `max(1, Tries + D − 2)`. C#: < −100 or Wild → 5, < −70 → 3.
- **Ship type:** `d = rand(100)`, walking the cumulative occurrence over all 10 types (`while sum < d`). If that type isn't allowed (needs strength + max(0, D−2) ≥ the type's minimum, and the minimum ≥ 0), it re-rolls. Take the maximum over the tries, starting from Gnat (Flea for traders). Mantis: the tries loop runs with `Tries = 1+D`, then the type is overwritten.
- **Equipment tries:** `max(1, worth/150000 + D − 2)` (same as C#).
- **Equipment-type roll bug** (confirmed in the original zip):
```c
k = GetRandom(100); j = 0; sum = Chance[0];
while (k < sum) { if (j >= MAXTYPE-1) break; ++j; sum += Chance[j]; }
```
  The comparison is backwards, so each roll gives:
  - Gadget: 35% **cloaking device**, 65% extra bays.
  - Weapon: 50% military laser, 50% pulse laser.
  - Shield: 70% reflective, 30% energy.
  Gadgets keep the best one not already owned. Weapons and shields allow duplicates (C# excludes types already owned).
- **Equipment counts:**
  - Gadgets: `rand(slots+1)`; if below slots, `tries > 4 → +1`, else `tries > 2 → +rand(2)`. Impossible gets all slots.
  - Weapons: 0 slots → 0, 1 slot → 1. Otherwise `1+rand(slots)`; if below slots, **`tries > 4 && D ≥ Hard → +1`, else `tries > 3 || D ≥ Hard → +rand(2)`**. C# has no difficulty term here.
  - Shields: `rand(slots+1)`; `tries > 3 → +1`, else `tries > 1 → +rand(2)`. Strength is the best of 5 rolls of `1+rand(power)`.
- **Hull:** full if it has shields and `rand(10) ≤ 7`, otherwise the best of 5 rolls. Mantis and Famous Captain always get full hull.
- **Cargo:** only if bays (including extra bays) > 5.
  - Normal and above: `min(3+rand(bays−5), 15)`; below Normal: all bays.
  - Police: 0, then the **minimum of 1 applies to everyone**, so police carry 1 unit.
  - Pirates: Easy and below ×4/5, otherwise /D.
- **Crew:** opponent skills are `1+rand(10)` in P, F, T, E order, then the Kravat/Wild engineer = 10 check (`rand(10) < D+1`). Crew count: `1+rand(quarters)`, Hard +1, Impossible all. Extra crew are `rand(31)` (any mercenary).
- **Order of generation in Palm:** type, gadgets, cargo, fuel, weapons, shields, hull, crew.
- **Famous captains:** a Wasp with **3** reflective shields (ignoring the slot limit), 3 military lasers, targeting + navigating systems, and all skills 10.

**Combat** (`Encounter.c:ExecuteAttack` / `ExecuteAction`)
- To-hit is the same as C#.
- **Damage:** `rand(weapons × (100 + 2×EngineerSkill(attacker))/100)`. C# uses **Fighter**.
- **Scarab:** only pulse lasers and Morgan's laser hurt it.
- **Reactor boost:** `Damage *= 1 + (D+1)×(D < Normal ? 0.25 : 0.33)`, a real fractional multiplier. C# casts the multiplier to `int`, so the boost is ×1 on Beginner/Easy/Normal and ×2 on Hard/Impossible.
- **Hull damage:** `max(1, dmg − rand(EngDef))`, capped at `hull/(cmdr ? max(1, 4−D) : 2)`. With the Scarab hull upgrade the cap uses the upgraded hull. There is **no damage halving** (C# halves damage for every defender once the Scarab quest is done).
- **When you attack:** the opponent shoots first, then you. Against surrendering opponents your shot counts as non-fleeing in Palm.
- Flee and escape formulas and the opponent state-change probabilities are the same as C#.
- **Kills:**
  - **Pirate bounty is credited regardless of police record**; only the dialog needs score ≥ −5. C# credits it only at ≥ −5.
  - Bounty = `max(25, min(2500, EnemyShipPrice/200/25×25))`, where `EnemyShipPrice = (hull + weapons + shields price) × (2P + E + 3F)/60`.
  - Famous captain kill: reputation becomes max(300, +100), and **no trader-kill count** (C# counts it).
  - Monster, Dragonfly and Scarab kills count as pirate kills with +1 police score.
  - Reputation `+= 1 + type/2`.
- **Scooping:** at Normal and above you get something if `rand(D) == 1`. The item is `rand(10)`, re-rolled once if ≥ 5. It does **not** come from the victim's cargo.

**Player actions in encounters (Palm)**
- **Attacking police:** confirm if score > −10, then score = min(score, −10) and −3. C# uses −30.
- **Fleeing an inspection:** score > −5 → −5 (−6 on Normal and above); otherwise −2.
- **Fleeing customs after the Marie Celeste:** score ≥ −10 → −10; otherwise −3.
- **Attacking a famous captain:** score = min(score, −30), then −2. C# uses −70.
- **Attacking a peaceful trader:** clean or better → confirm, then −5; otherwise −2.
- **Surrendering to police is refused at score ≤ −70** (C# ≤ −100).
- **Bribe:** `worth/((10 + 5(4−D)) × bribeLevel)`, rounded up to 100, ×2 (Normal and below) or ×3 if Wild or the reactor is aboard, clamped 100–10000.
- **Submitting to inspection:**
  - Fine = `worth/((6−D)×10)`, rounded up to 50, clamped 100–10000; anything unpaid goes to debt; −1 score.
  - Clean inspection: +1, but not if Wild is aboard.
  - **A reactor alone is just confiscated, with no arrest** (C# arrests).
  - The warning prompt tests `ReactorStatus > 1` (a Palm bug).
- **Yield (customs):** narcotics and firearms are removed, **but their purchase price is not reset**.
- **Arrest** (`Encounter.c:Arrested`):
  - Fine `(1 + worth×min(80, −PRS)/100/500) × 500` (×1.05 with Wild); jail `max(30, −PRS)` days.
  - Narcotics and firearms are impounded; their purchase price is **not** cleared.
  - Insurance lost, mercenaries leave, antidote and Jarek gone, Wild arrested, reactor confiscated.
  - Then `Arrival()`, `IncDays(term)`. If you can't pay, the ship is sold for `CurrentShipPrice(true)` (including cargo purchase price) and you get a Flea. Score becomes −5, debt is paid down, then interest is charged term times.
- **Escape pod:** `Arrival()`, Scarab upgrade lost, reactor / antidote / artifact / Jarek lost, Wild arrested (−4), tribbles gone, insurance pays the ship value without cargo, then −500 (into debt if needed), `IncDays(3)`, Flea.
- **Pirate raid:** no cargo → blackmail `min(25000, max(500, worth/20))`. Otherwise pirates steal **random units** until their free bays are full, or everything if it fits. Stolen goods are not added to their hold.
- **Plunder:** −2 (trader) or −1 (pirate) is applied when you press Plunder. **No reputation gain** (C# adds type/2+1).
- **Trade in orbit:**
  - Trader sells to you: illegal goods `rand(100) ≤ 45 → ×1.1`, else ×0.8; legal goods `≤ 10 → ×1.1`, else ×0.9. Then truncated to the round-off step and clamped to min/max.
  - Trader buys from you: illegal `≤ 45 → ×0.8`, else ×1.1; legal `≤ 10 → ×0.9`, else ×1.1. Then `/roundoff`, **+1**, `×roundoff`, clamped.
  - These mutate the global buy/sell prices.
  - Quantity you can sell is capped by the trader's **total** bays. When buying, a typed amount is **not capped by your free bays** (only "All" is). C# uses `<45` and `Math.Round`.

**Arrival** (`Travel` tail, `Arrival`)
- Order:
  1. Arrival alert, then the debt warning **and** the 5-day loan reminder (both can show; C# shows only one).
  2. `Arrival()`: shuffle statuses, change quantities, prices.
  3. Reactor warnings at status 2/16/18 and meltdown at 20.
  4. Tribbles.
  5. Engineer repair `rand(Eng)`.
  6. Auto-fuel / auto-repair. These buy **partial** amounts (C# is all-or-nothing). Shields are **not** recharged here.
  7. The Og easter egg.
- **Tribbles** (Palm `Travel`):
```
reactor aboard: T/=2; if T<10 → 0
else narcotics: T = 1+rand(3); eat min(1+rand(3), narc) narcotics → furs (purchase price scaled)
else food: T += 100+rand(food×100); food = rand(food) (purchase price scaled); FoodOnBoard=true
then ALWAYS (any branch): if 0<T<MAX: T += 1+rand(max(1, T >> (FoodOnBoard?0:1))); cap MAX
alerts when crossing 100 / 1000 / 10000 / 50000
```
  C# differs in all three branches and grows only in the food/none branch.

**Shipyard and ship trade**
- New ship price = `Price×(100 − TraderSkill)/100 − CurrentShipPrice(false)`, so **Palm gives a trader-skill discount on ships**; a result of 0 becomes 1. C# has no discount.
- Trade-in value = `price × (tribbles ? 1 : 3)/4 − (hull missing × RepairCosts) − (empty tanks × CostOfFuel) + 3/4 of base equipment price + total cargo purchase price`. **The cargo refund at purchase price exists in Palm too**, but `CreateShip` clears the cargo **and** the purchase-price record. C# keeps the stale `PriceCargo` after trading ships.
- Buying is blocked if in debt (and the price > 0) or the reactor is aboard. Jarek or Wild only need 2 crew quarters (they aren't counted together with mercenaries).
- Unique-equipment transfer costs: Lightning shield 30000, Fuel compactor 20000, Morgan's laser 33333. C# uses sell price × 110/90.
- A transferred lightning shield is left at 0 charge until the next warp.
- Equipment price = `price × (100 − Trader)/100` if your tech level allows it; resale is 3/4 of base price. You can't buy equipment while in debt. C# works the same.
- Repairs and fuel buy partial amounts (`BuyRepairs` / `BuyFuel`).
- **Loans:** `MaxLoan = score ≥ 0 ? min(25000, max(1000, worth/10/500×500)) : 500` (same as C#).

**Cargo**
- Buying is blocked when debt > 100000.
- Dumping in dock costs `5(D+1)` per unit. The cap is computed as `ToSpend()/5*(D+1)`, a precedence bug.
- Jettison: you're caught if `rand(10) < D+1` (score → min(score, −5), else −1), plus a litter warning when score > −5.

**Skills**
- The best skill in the crew, plus the gadget bonus, **then** adjusted for difficulty (Beginner/Easy +1; Impossible `max(1, −1)`).
- Trader +1 after Jarek is delivered (counted before the difficulty adjustment).
- `IncreaseRandomSkill` can go up to **10**. C#'s `ChangeRandomSkill` stops at 9.
- Tonic: below Hard, +1/−1 until something changes; Hard and above, +1, +1, −3.
- Jarek and Wild are passengers, not crew. They add no skills, take quarters, cost nothing, and have no impatience.

**Special-event behaviour (Palm)**
- The price is deducted **before** any refusal checks.
- **Open-quest cap:** when more than 3 quests are open, these start events are hidden: Tribble, Space Monster, Dragonfly, Japori, Artifact, Jarek, Alien Invasion, Experiment, Wild, Reactor, Scarab. C# has no cap. Open quests counted (`QuestEvent.c:OpenQuests`):
  - monster
  - Dragonfly (or its shield still unclaimed)
  - Japori
  - artifact
  - Wild
  - Jarek
  - invasion (or the compactor still unclaimed)
  - experiment
  - reactor
  - Morgan's laser unclaimed
  - Scarab
  - tribbles
  - moon bought
- **Moon** needs worth ≥ 400000 (C# > 400000).
- **Wild delivered:** score = max(score, 0), with no sell-price recalculation. C# forces the score to exactly 0, even for heroes.
- **Zeethibal** is paid wages (the free-wage macro tests index ≥ 31, but Zeethibal is index 30). C# makes Zeethibal free.
- **Fired mercenaries** stay in their original system. C# moves them to a random system within 20 parsecs.

**Newspaper**
- Cost D+1, paid once per system.
- Masthead `WarpSystem % 3`; `RandSeed(WarpSystem, Days)`.
- Fixed event headlines first.
- Villain headline at **score ≤ −30**. Hero headline only at **score == 75 exactly**.
- Distant news: systems within **ship-type tank range** (ignoring the compactor and your current fuel) or the wormhole target, **and status > 0**. The moon and tribble stories also need status > 0. Each qualifying system rolls `GetRandom2(100) ≤ 50/8×TL + 10(5−D)`, then picks a prefix with `GetRandom2(6)`.
- Canned headlines: `for (i=0; i <= GetRandom2(4); i++)`, which **re-rolls the bound on every pass**.
- The page fills until the next line would start below y = 128 (1-line headline) or 107 (2-line), and stories over 71 characters are dropped (`Draw.c:DisplayHeadline`).
- C# has shipyard news, uses current fuel range and Villain = −70, computes the canned-headline bound once, and has no page limit.

**Scoring and high scores**
- Worth above 1M counts at 1/10.
- Killed: `(L+1)×((W×90)/50000)`. Retired: `(L+1)×((W×95)/50000)`. Moon: `(L+1)×((W + max(0, (L+1)×100 − days)×1000)/500)`.
- Displayed as `a/50 "." (a%50)/5 "%"`.
- C# `Game.Score`: `(L+1)×mod×(…)/250000`, the same scale but different integer rounding.
- 3 slots. Ties are broken by worth, then **more** days.
- Not saved if a game was loaded with the "Timewarp" cheat (`GameLoaded`).

**Other**
- **No custom ship designer, shipyards, disruptors, disabling, hidden bays, Sculpture, Princess, Scorpion or Quantum disruptor in Palm.**
- **Cheats** via Find System: "Moolah" (+100000), "Very rare", "Cheetah", "Go <system>", "Quests", "Timewarp".

## 4. Palm RNG

1. **Game logic** uses `GetRandom(a) = SysRandom(0) % a`, the Palm OS ROM generator. The game never seeds it. Its algorithm isn't in the game source. I believe it is the LCG `seed = 0x015A4E35×seed + 1; return (seed>>16) & 0x7FFF`, but a web search could not confirm that; it needs a Palm OS / POSE source to verify. Since this RNG is unseeded, outcomes aren't reproducible anyway, so any good RNG is acceptable here.
2. **Newspaper** uses `Math.c:Rand` / `GetRandom2` / `RandSeed`, which must be reproduced exactly:
   - `SeedX` and `SeedY` are declared **`UInt16`**, so the defaults truncate to **15285** and **21989**.
   - `SeedX>>16 == 0`, and the return value truncates to `UInt16`. In effect:
```
RandSeed(s1,s2): SeedY = (s2 ? s2 : 21989) & 0xFFFF   // SeedX irrelevant to output
Rand(): SeedY = (30903 * SeedY) & 0xFFFF; return SeedY
GetRandom2(n) = Rand() % n
```
   - No overflow is possible with either 16- or 32-bit `int` (30903 × 65535 < 2³¹).
   - C# `Functions.Rand` uses 64-bit `long` seeds with no truncation, so its sequence differs.

## 5. Palm-only features
- **Options:**
  - Always go from chart to info; reserve money; leave N bays empty.
  - Continuous attack/flee; keep attacking fleeing ships.
  - Textual encounters.
  - Hardware buttons for encounter actions.
  - Auto-pay newspaper; show tracked range; stop tracking on arrival; loan reminder.
  - Share preferences between switched games; identify commander at startup; rectangular buttons.
  - 4 configurable shortcut buttons.
- Average Price List screen, with a price-difference toggle and buying directly from it.
- Switch Game (2 commanders), Snapshot save, the "Timewarp" reload that disables scoring.
- Special Cargo screen.
- Quest-limit gating (section 3).
- Tribble buttons on the encounter screen ("squeek").

## 6. What the `Ruleset` abstraction should expose

**Data tables per ruleset:**
- system list (120 or 128)
- galaxy width (150 or 154)
- minimum distance and test
- ship table, including the swapped cost columns
- weapons, shields, gadgets and which are buyable
- mercenary roster and how many per system
- special-event table with its index order and placement plan
- police and reputation thresholds and names
- newspaper strings
- unique-equipment transfer prices
- pod transfer rule
- fuel-compactor rule (set to 18 vs +3)
- cloak bonus (2 vs 3)

**Behaviour flags:**
- distance rounding (round vs floor)
- generation: system rejection vs government-then-TL; regenerate galaxy on placement failure; placement exclusion bugs; start-system TL range and reach test
- quantity bug: size of the wrong system
- quantity drift: triangular vs uniform; zero untraded items
- price variance: two rolls vs uniform with clamp
- police decay: Palm's per-warp code vs C#'s `IncDays` version
- no-claim and monster regen: per warp vs per day
- shield recharge at departure vs arrival
- in-flight repair halved; arrival auto-buy partial vs all-or-nothing
- encounter: raided pirate band falls through to police; very-rare pick over all six vs remaining
- Palm "criminal" constant set (−10/−30/−70) vs C#'s (−30/−70/−100) for each rule that uses it
- police surrender state; police attack without weapons
- the equipment-roll bug; duplicate equipment allowed; weapon-count difficulty term; police cargo minimum 1; extra bays counted in cargo; famous captain with 3 shields
- damage skill (Engineer vs Fighter); reactor multiplier as a real number vs integer cast; hull hardening halves damage for all defenders
- bounty credited regardless of record; plunder reputation; scoop from random item vs victim's cargo
- pirates steal random vs most expensive units
- trade-in-orbit rounding and threshold
- trader-skill ship discount; cargo price refund on ship trade and clearing it
- impounded goods keep their purchase price
- reactor submission arrests or not
- tribble algorithm; zero-tribble rule
- skill cap 9 vs 10; Jarek/Wild as crew vs passengers; impatience timers
- open-quest cap
- Wild-delivered score rule
- Zeethibal wage; where fired mercenaries go
- newspaper algorithm variant
- score rounding variant
- debt warning and reminder exclusive or both
- equipment allowed while in debt

**Too big for flags (separate content packs):**
- quest sets: Palm's 37 events vs C# with Princess, Sculpture, Scorpion, Quantum disruptor and hidden bays
- shipyards and the custom ship designer
- disruptors and disabling
- the C# extra systems and mercenaries
- the two RNG back-ends (Palm OS `SysRandom` vs .NET `Random`, plus the newspaper `Rand` described above)
- for bit-faithful modes, call order per ruleset, because RNG consumption order differs (generation and opponent creation order, `ShuffleStatus` placement, and when rolls are taken)

Sources:
- [Palm OS SDK 4.0 headers (Free Pascal port, sysutil.pp)](https://git.osdyson.ru/pkg-pascal/fpc/tree/fpcsrc/packages/palmunits/src/sysutil.pp): confirms only that `SysRandom` returns 0..`sysRandomMax` (0x7FFF), not its algorithm.
- Palm 1.2.2 source: https://github.com/videogamepreservation/spacetrader, cross-checked against https://www.spronck.net/spacetrader/SpaceTraderSource.zip
