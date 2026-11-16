# QA: Fidelity Audit of Research 01 and 04

> Independent audit 2026-11-16, ~115 claims checked against the C# source and Palm 1.2.2. All corrections were applied as QA ERRATA blocks at the top of 01 and 04, and in PRD v1.1 (MOD-019, MOD-020, kept-as-designed list).

---

## Fidelity audit: 01-csharp-engine-spec.md and 04-palm-122-ruleset-diff.md

**Result:** I checked about 115 claims against the sources: roughly 100 hold up, 3 are wrong and 10 are imprecise or leave out something important. All of the most important claims are confirmed. That includes the fuel/repair cost swap, the backwards Palm equipment roll, the market-quantity bug and the Palm police-record constants being offset by one rank.

**Sources used:**
- C# 2.01: the local tree at /Users/megatih/Downloads/SpaceTraderSource201.
- Palm 1.2.2: raw files from the GitHub master branch, saved to /private/tmp/claude-501/-Users-megatih-Documents-XcodeProjects-SpaceTraderMac/41153429-8b01-41f4-b2f9-1edc30fcbfec/scratchpad/palm-audit/. I only read them. Palm citations are file:function.

No project files were edited.

---

### A. WRONG

**W1. Doc 01 §7, opponent generation: "Each try picks a weighted ship among indices 0..9".**
- In C#, the Wasp (index 9) can never be picked as a random opponent. Ship.cs GenerateOpponentShip adds up the weights with `for (int i = 0; i < Consts.MaxShip; i++)`, and MaxShip is 9, so indices 0..8 only.
- The roll is then `x = GetRandom(total)`, and the walk is `do { j++; ... } while (sum < x && j < Consts.MaxShip);`. Once index 8 is added, `sum == total > x`, so the walk always stops at 8 or earlier.
- The only Wasp opponent in C# is the famous captain.
- Palm reaches the Wasp: it rolls `GetRandom(100)` against occurrences that sum to 100, giving the Wasp about a 1% roll (Traveler.c:GenerateOpponent).
- **Correct statement:** C# weights over ships 0..8 only; the Wasp is unreachable. This needs a ruleset flag.

**W2. Doc 01 §7: "Weapons: ... Duplicates aren't excluded."**
- C# skips weapon types the ship already has. Ship.cs:GenerateOpponentAddWeapons has `if (!HasWeapon((WeaponType)weaponType, true) && weaponType > bestWeaponType)`, and `HasWeapon(type, exactCompare=true)` (Ship.cs:597) matches the exact type.
- Shields work the same way (`!HasShield(...)`).
- Duplicates only happen through the fallback: if every draw is already owned, the slot gets index 0 (Pulse, Energy shield or Extra Bays).
- Doc 04 describes this correctly ("C# excludes types already owned").

**W3. Doc 01 §2: GetRandom2 "can go negative after overflow".**
- Functions.cs:252 `Rand()` is a multiply-with-carry on `long`, so the seeds stay bounded. SeedX < 18000·65536 ≈ 1.18e9, so `SeedX<<16` < 7.7e13, far below 2^63.
- The result is always non-negative, and the seeds are only replaced when `> 0`.
- **Correct statement:** the output differs from Palm's because of the 64-bit arithmetic and the lack of UInt16 truncation, but it is never negative.

---

### B. IMPRECISE or missing an important difference

**I1. Doc 04, high impact: commander worth is defined differently, and the doc never says so.**
- Palm Money.c:CurrentWorth is `CurrentShipPrice(false) + Credits - Debt + (MoonBought ? COSTMOON : 0)`. `CurrentShipPrice` is the trade-in value plus cargo purchase prices (ShipPrice.c).
- C# Commander.cs:389 uses `Ship.Price`, the list price (doc 01 says this correctly).
- Doc 04 marks max loan "(same as C#)" and repeats the worth-based formulas for bribe, fine, arrest, blackmail, pirate tries, equipment tries, the moon threshold and score, but never notes that the input differs.
- Every one of those formulas changes. Add a ruleset flag `worthUsesTradeInValue`.

**I2. Doc 04 §3 Skills: the difficulty adjustment differs on Hard, and the doc doesn't flag it.**
- Palm Skill.c:AdaptDifficulty: Beginner/Easy +1; `else if (Difficulty == IMPOSSIBLE) return max(1, Level-1); else return Level;`. **Hard is unchanged.**
- C# Functions.cs:54 AdjustSkillForDifficulty gives Hard and Impossible −1.
- The doc's text is technically right for Palm but omits the difference, and the flag list has no entry for it. This affects every skill check on Hard.

**I3. Doc 04 §3 Police record decay: "once per normal warp only".**
- In Traveler.c:DoWarp the decay block, the monster heal (`MonsterHull*105/100`), the shield recharge and `Clicks = 21` all sit **outside** `if (!viaSingularity)`.
- So they also run on a singularity jump, where the day doesn't advance and the `Days%3` test uses the old day.
- Only interest, `IncDays(1)` and `++NoClaim` are limited to normal warps.

**I4. Doc 01 §2: commander start order.**
- The doc puts the Lottery before `CreateShips()`.
- The actual order (Game.cs:110-133) is: InitializeCommander → GenerateCrewMemberList → CreateShips → CalculatePrices → ResetVeryRareEncounters → Lottery.
- The start-system pick also comes before the mercenary generation, although the doc lists mercenaries first. This matters for random-number order.

**I5. Doc 04 §3 Bribe wording: "×2 (Normal and below) or ×3 if Wild or the reactor is aboard".**
- This reads as if ×2 always applies on Normal and below.
- Encounter.c is `if (WildStatus == 1 || (ReactorStatus > 0 && ReactorStatus < 21)) { if (Difficulty <= NORMAL) Bribe *= 2; else Bribe *= 3; }`.
- **Correct statement:** the multiplier applies only with Wild or the reactor aboard: ×2 on Normal and below, ×3 above.

**I6. Doc 04 §6: "extra bays counted in cargo" listed as a Palm-only behaviour flag.**
- C# counts them too. Gadgets are generated before cargo (Ship.cs:84-92), and `Ship.CargoBays` (Ship.cs:830) adds Extra and Hidden bays.
- The real Palm-only differences are the `Bays > 5` guard and police carrying a minimum of 1 unit.

**I7. Doc 04 §1: "54 IDs".**
- The C# CrewMemberId enum runs 0..54, which is 55 entries including the Commander (Enums.cs).
- 44 of them get random systems (ids 1–29 and 38–52), as doc 01 says.

**I8. Doc 04 §3: Zeethibal's wage.**
- The macro is `(a < 0 || (a >= MAXCREWMEMBER && WildStatus == 2) ? 0 : ...)` (spacetrader.h:457). It also requires WildStatus == 2.
- The conclusion (index 30, Zeethibal, is paid) is correct.

**I9. Doc 01 §3 Restocking leaves out a clamp.**
- If `CountDown > CountDownStart` after decrementing, it is clamped back (Game.cs:517).
- Palm ChangeQuantities does the same.

**I10. Doc 04 §4 RNG: `RandSeed(s1, s2)` takes UInt16 parameters.**
- The value is truncated before the zero test (Math.c:RandSeed), so `s2 = 65536` would select the default seed.
- This is unlikely to matter in practice.

---

### C. CONFIRMED (abridged)

**Doc 01 (C#)**
- **Ship table:** all 17 rows and the column order are correct. The constructor order is `(..., fuelTanks, fuelCost, hullStrength, repairCost, price, occurrence, ...)` (ShipSpec.cs:63; Consts.cs:250-267). C# fuelCost is 1,1,1,1,1,1,2,3,4,5 and repairCost is 1,2,3,5,7,10,15,15,20,20.
- **Equipment:** the weapons, shields and gadgets tables, the EquipmentForSale list, Cloak = Pilot with +3, CloakBonus unused (Consts.cs). Buy price `_price*(100-Trader)/100` (0 below the tech level), sell price `*3/4`, transfer `Sell*110/90` (Equipment.cs:148-186).
- **Trade item table:** all 10 rows (Consts.cs TradeItems).
- **Prices:** StandardPrice (TradeItem.cs:87); SpecialResource hidden until visited (StarSystem.cs:424). CalculatePrices uses absolute variance `min(V, p-1)` and criminals ×90/100 (Game.cs:534). RecalculateBuyPrices `*(103+10-Trader)/100`, minimum sell+1 (Game.cs:2960). RecalculateSellPrices ×100/90 unconditionally (Game.cs:2985).
- **Quantities and restock:** the quantity formula (StarSystem.cs:84-116) and the restock bug `WarpSystem.ItemTraded` (Game.cs:526).
- **Galaxy and universe:** galaxy constants (Consts.cs); generation order size → government → tech → Galvon override → pressure → resource → coordinates; centre offset `GetRandom(-12, 13)` (Game.cs:2175-2259).
- **Placement:** PlaceSpecialEvents (fixed list, first free wormhole for the Scarab, *first* HiTech system for the artifact, FindDistantSystem picks the closest system at ≥70, then random placement) and PlaceShipyards (Game.cs:2857-2958); regenerate loop (Game.cs:120).
- **Start and crew:** start system tech > PreAg and < HiTech, ≥3 systems within 14 (Game.cs:2685). Special-crew skills and "max 3 per system, Kravat pre-counted" (Game.cs:2121).
- **Random encounters:** `GetRandom(44-2d)`, doubled in a Flea, `policeMod = max(1, 3 - recordIndex)`, raided pirates give no encounter, Kravat `100/max(2, min(4, 5-d))`, artifact `GetRandom(20) <= 3`, very rare `GetRandom(1000) < 5` (Game.cs:917-970).
- **Reactions:** pirate, police (surrender demand at ≥ −30) and trader reactions (Game.cs:828-1007).
- **Opponent generation:** pirate tries `max(1, 1 + Worth/100000 + d - 2)`; police tries 5 / 3 / 1 then +d−2; equipment tries; gadget, shield and weapon count rules; best-of-5 shield charge; hull "no shields or 1 in 5"; cargo `min(15, 3+GetRandom(bays-5))`, pirates ×4/5 or /d (Ship.cs:56-480). The Kravat engineer check uses the *opponent's* WildOnBoard (quirk 11).
- **Combat:** to-hit; damage uses **Fighter**; Scarab exclusions; reactor `(int)` cast giving 1,1,1,2,2; hull cap `max(1, 4-d)` giving 4,3,2,1,1; Scarab-done halving for every defender; Scorpion floor at hull 1 (Game.cs:1288-1390).
- **Flee and state changes:** both escape formulas and the state-change chances 60/10, 40, 60, 20/60 (Game.cs:1225-1240, 1519-1584).
- **Police record and actions:** classification gives Psychopath for anything < −70, and GetPoliceRecordFromScore ignores its argument (PoliceRecord.cs:46). Attack police / trader / captain, flee inspection `min(r-2, -5-(d≥N))`, Marie flee `min(r-3, -30)`, fine, bribe, surrender ≤ −100, blackmail (Game.cs:1586-1960).
- **Arrest:** `term = max(30, -rec)`, `fine = (1 + Worth*min(80, -rec)/50000)*500`, ×1.05 with Wild; negative-fine bug (Game.cs:202).
- **Money:** insurance (Game.cs:3831), interest (Commander.cs:79), NoClaim capped at 90 by its setter (Commander.cs:341), max loan `Worth/5000*500` (Form_ViewBank.cs:62), Worth (Commander.cs:389), BaseWorth (Ship.cs:130), bounty with the trader-discounted equipment `Price` (Ship.cs:154), wormhole tax `25*FuelCost` (Game.cs:4410).
- **Time:** IncDays integer-division decay and `1.05^n` monster heal (Game.cs:2584).
- **Events and quests:** special events table (Consts.cs:298) and all status codes (SpecialEvent.cs:36-107).
- **Score, newspaper, tribbles:** score (Game.cs:4246). Newspaper villain ≤ −70, hero ≥ 75, StoryProbability 6 (Game.cs:3928-3964). Tribbles (Game.cs:395).
- **Arrival and repairs:** debt warning and reminder are mutually exclusive (Game.cs:332). PerformRepairs is not halved (Ship.cs:664).
- **Cargo actions:** jettison and dump rules (Game.cs:680-722); trade-in-orbit `<45 / <10` with Math.Round (Game.cs:579, 666).
- **Skills:** ChangeRandomSkill `< MaxSkill`, so random increases stop at 9 (CrewMember.cs:69).

**Doc 04 (Palm)**
- **Fuel/repair swap (critical):** DataTypes.h SHIPTYPE order is `..., MinTechLevel, CostOfFuel, Price, Bounty, Occurrence, HullStrength, Police, Pirates, Traders, RepairCosts, Size`. Global.c:188-203 gives CostOfFuel 1,2,3,5,7,10,15,15,20,20 and RepairCosts 1,1,1,1,1,1,2,3,4,5. The usage is consistent everywhere: Fuel.c:73-82 and Traveler.c:170 (`CostOfFuel*25L` wormhole tax) use CostOfFuel; Shipyard.c:249-258 uses RepairCosts; ShipPrice.c:81-83 uses both. The Wasp's tax is 500 in Palm against 125 in C#.
- **Tables:** every Palm ship row (the bounty column is unused, commented out in Encounter.c); weapons, shields and gadgets (Global.c:207-233); trade items and governments identical.
- **Constants:** cloak +2 (Skill.c:PilotSkill); police constants PSYCHOPATHSCORE −70 / VILLAINSCORE −30 / CRIMINALSCORE −10 and the display table (spacetrader.h:365-367; Global.c PoliceRecord); MAXSOLARSYSTEM 120, 150×110, MINDISTANCE 6 tested as `SqrDistance <= SQR(7)`; round-to-nearest sqrt (Math.c); compactor sets tanks to 18 (Fuel.c:52).
- **Start and money:** start system (200 tries, TL 1–5 on the first 100, `<= SQR(14)`); insurance with integer `*5/2000`; interest; special events table (37 entries, index 7..29 placed at random).
- **Generation and placement:** reject-whole-system generation order; centre offset `6 - rand(13)`; buggy Scarab, Reactor (`d !=`), Artifact (120 tries, occurrence 0 on failure) and Invasion (`k !=`) placement.
- **Markets and prices:** the quantity bug `(1 + SolarSystem[i].Size)` (Traveler.c:InitializeTradeitems); ChangeQuantities `+rand(5) - rand(5)` with untradeable items zeroed; ShuffleStatus runs before quantities (Arrival); variance from two rolls; buy price formula.
- **Warp:** DoWarp order (Wild check first, shields recharged at departure, `Fuel -= min`, Clicks 21); NoClaim per normal warp; per-click repair `>> 1`.
- **Encounters:** a raided pirate roll falls through to police; police logic (no surrender state, unarmed police still attack, `rand(40) == 1`, "better ship" override); traders flee at ≤ −10; trade in orbit even while cloaked; very rare `rand(6)` over all six, captains need > −10, Marie unrestricted; post-Marie police generated after the loop.
- **Opponent generation:** police tries code; ship roll; backwards equipment roll giving 35% cloak / 65% bays, 50% military / 50% pulse, 70% reflective / 30% energy; counts including the weapon difficulty term; hull `rand(10) <= 7`; police carry 1 unit; generation order; famous captain with 3 reflective shields (Traveler.c:GenerateOpponent).
- **Combat:** damage uses `EngineerSkill(Attacker)` (Encounter.c:818, 821); Scarab hurt only by pulse and Morgan's; real fractional reactor multiplier; no halving; cap uses GetHullStrength when the Scarab is done.
- **Kills:** bounty credited regardless of record; famous captain gives no trader-kill count; monster, Dragonfly and Scarab count as pirate kills; scoop `rand(D) == 1` with a random item, re-rolled once if ≥ 5 (Encounter.c:ExecuteAction, Scoop, GetBounty).
- **Player actions:** attack police (−10 then −3), flee inspection, Marie flee, famous captain −30, trader, surrender refused at ≤ −70, fine `/(6-D)*10` rounded up to 50, reactor alone is confiscated, warning tests `ReactorStatus > 1`.
- **Arrest:** fine `/100/500`, goods' purchase price kept, then Arrival → IncDays → pay or sell ship → −5 → debt → interest.
- **Arrival:** tribble algorithm; debt warning and reminder can both show; trade-in-orbit `<= 45`, `+1` rounding.
- **Ships:** ship discount `BASESHIPPRICE` with 0 → 1; transfer costs 30000 / 20000 / 33333.
- **Skills and quests:** IncreaseRandomSkill reaches 10; Jarek +1 before the difficulty adjustment; open-quest cap > 3 (QuestEvent.c:OpenQuests); moon shown at ≥ 400000; Wild delivered `max(score, 0)`.
- **Newspaper:** villain ≤ −30, hero `== 75`, tank range and `Status > 0`, bound re-rolled each pass (SystemInfoEvent.c:465-790).
- **RNG:** `UInt16 SeedX/SeedY`, defaults truncate to 15285 / 21989, output equals the SeedY recurrence (Math.c); `GetRandom = SysRandom(0) % a` (spacetrader.h:444).
- **Score and timers:** score (Traveler.c:GetScore); Gemulon Mantis `rand(10) > 4`; Wild-at-Kravat 25 / 33 / 50.

---

### Corrections, in priority order

1. **Doc 04:** add the worth-definition difference (Palm trade-in value plus cargo vs C# list price) and a ruleset flag. It changes loans, fines, bribes, pirate and equipment tries, the moon check and the score.
2. **Doc 01, and both docs' ship-selection sections:** C# never generates a Wasp opponent because the weights only cover indices 0..8. Add a flag.
3. **Doc 04:** Palm leaves skills unchanged on Hard, while C# applies −1. Add a flag.
4. **Doc 01:** C# opponent weapons and shields skip types already owned; duplicates come only from the index-0 fallback.
5. **Doc 01:** remove "GetRandom2 can go negative".
6. **Doc 04:** Palm decay, monster heal and shield recharge also run on singularity warps.
7. **Doc 04:** reword the bribe multiplier (it applies only with Wild or the reactor aboard).
8. **Doc 01:** fix the constructor and random-number order (CreateShips comes before CalculatePrices and the Lottery; the commander start comes before mercenary generation).
9. **Doc 04:** "extra bays counted in cargo" is not Palm-only.
10. **Minor:** 55 C# crew IDs; the Zeethibal macro also needs `WildStatus == 2`; the restock CountDown clamp; RandSeed truncates its UInt16 parameters.

