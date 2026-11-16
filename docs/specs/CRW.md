# CRW: Crew, skills and commander

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2.
> C# paths are relative to `/Users/megatih/Downloads/SpaceTraderSource201`. Palm paths are relative to `docs/reference/palm-src/`.
> **Modern = Windows 2.01 plus the closed MOD list (PRD §4.3).** A Windows quirk that no MOD entry fixes is tagged `[M][W]` and needs a keep row in RUL.md.
> Skill indices are Pilot 0, Fighter 1, Trader 2, Engineer 3 (Enums.cs:594). Difficulty is Beginner 0, Easy 1, Normal 2, Hard 3, Impossible 4 (Enums.cs:320; Palm: Src/spacetrader.h:75-80).
> `[verify]` marks a statement that could not be confirmed fully from the source.

## 1. Skill types and commander identity

- **CRW-001** {M2} [M][W][P] There are exactly 4 skill types, in the order Pilot, Fighter, Trader, Engineer, and every crew member (commander, mercenary, special character) stores one integer per skill. (source: Enums.cs:594-601, CrewMember.cs:35; Palm: Src/spacetrader.h:148 `MAXSKILLTYPE 4`)
- **CRW-002** {M2} [M][W][P] A crew member's own skill is capped at `MaxSkill = 10` wherever the source applies a cap (creation, captain training, random increases); effective ship skills (§3) are not capped. (source: Consts.cs:69; Palm: Src/spacetrader.h:87)
- **CRW-003** {M2} [M][W][P] The commander's identity is the name, the difficulty, the 4 raw skills and the optional cosmetic ship name. The difficulty is fixed when the game is created and cannot change during the game. (source: Game.cs:115-119, Form_NewCommander.cs:408-421; PRD §6.2)
- **CRW-004** {M2} [M][W][P] The commander's name is a required, non-empty string. A `newGame` command with an empty name is rejected with `CommandError.commanderNameRequired` and changes no state. (source: Form_NewCommander.cs:375 `txtName.Text.Length > 0`; Palm: Src/Traveler.c:2587 accepts any field text, so the engine applies the same rule to every ruleset)
- **CRW-005** {M5} [P] The Palm name field holds at most `NAMELEN = 20` characters. The engine rejects a longer name in the Palm ruleset with `CommandError.commanderNameTooLong`. (source: Palm: Src/spacetrader.h:88, Src/Traveler.c:2667-2668)
- **CRW-006** {M2} [M][W][P] The cosmetic ship name is optional (nil or empty means "no name"). It is stored in `GameState`, survives ship trades, has no effect on any rule, price, RNG call or score, and is separate from the C# custom-designer ship type name. (source: PRD §4.3 quality-of-life list, PRD §6.2 State)

## 2. New commander

- **CRW-007** {M2} [M][W][P] A new commander starts with every skill at 1 and 16 unspent points. The 4 skills must total exactly 20, with each skill in 1...10. A `newGame` command whose skills break any of these rules is rejected with `CommandError.invalidSkillAllocation`. (source: Form_NewCommander.cs:203-217 min 1 max 10 value 1, :330 "16", :382-391 `points = 20 - (P+F+T+E)`, `Maximum = min(10, skill + points)`; Palm: Src/Traveler.c:1444-1448 skills init 1, :2579-2584 `2*MAXSKILL - sum > 0` blocks OK, :2612-2660 increments need skill < 10 and points > 0, decrements need skill > 1)
- **CRW-008** {M2} [M][W][P] The number of skill points (20) does not depend on difficulty. (source: Form_NewCommander.cs:384; Palm: Src/Traveler.c:2579)
- **CRW-009** {M2} [M][W][P] The new-game difficulty is one of 5 levels, Beginner, Easy, Normal, Hard and Impossible, and the default selection is Normal. (source: Form_NewCommander.cs:64 `SelectedIndex = 2`, :189-194; Palm: Src/Global.c:630 `Difficulty = NORMAL`, Src/spacetrader.h:75 `MAXDIFFICULTY 5`)
- **CRW-010** {M2} [M][W][P] The commander is crew id 0 and always sits in crew slot 0 of the player's ship. (source: Commander.cs:55, Game.cs:2688; Palm: Src/spacetrader.h:448 `COMMANDER Mercenary[0]`, Src/Traveler.c:1687 `Ship.Crew[0] = 0`)

## 3. Effective ship skills

- **CRW-011** {M2} [M][W] For each skill, the ship's effective value is computed in this order: (1) `max` = the highest raw value among all crew in the ship's crew array, starting from 1; (2) `max = max(1, AdjustSkillForDifficulty(max))`; (3) add `SkillBonus = 3` for **each** installed gadget whose skill bonus is that skill. There is no upper cap. (source: Ship.cs:1228-1257, Consts.cs:66)
- **CRW-012** {M2} [M][W] `AdjustSkillForDifficulty(s)` returns `s+1` on Beginner and Easy, `s-1` on Hard and Impossible, and `s` on Normal. (source: Functions.cs:54-71)
- **CRW-013** {M5} [P] Palm computes each effective skill in this order: (1) `max` = the highest raw value among the commander and the mercenaries in crew slots 1...2, stopping at the first empty slot; (2) add the gadget bonus (Pilot: +3 if a Navigating System is installed and +2 if a Cloaking Device is installed; Fighter: +3 for a Targeting System; Engineer: +3 for an Auto-repair System; each gadget type counts once); (3) Trader only: +1 if `JarekStatus >= 2`; (4) apply `AdaptDifficulty`. (source: Palm: Src/Skill.c:117-136 TraderSkill, :281-353 Fighter/Pilot/EngineerSkill, :387-402 HasGadget)
- **CRW-014** {M5} [P] Palm `AdaptDifficulty(L)` returns `L+1` on Beginner and Easy, `max(1, L-1)` on Impossible, and `L` unchanged on Normal **and Hard**. (source: Palm: Src/Skill.c:355-365; research 04 errata #2)
- **CRW-015** {M2} [M][W] Example: Hard, best Pilot 5, Navigating System and Cloaking Device installed gives effective Pilot `max(1, 5-1) + 3 + 3 = 10`. (source: Ship.cs:1240-1253, Consts.cs:149-151 the cloak's bonus is `SkillType.Pilot`)
- **CRW-016** {M5} [P] Example: Hard, best Pilot 5, Navigating System and Cloaking Device installed gives effective Pilot `5 + 3 + 2 = 10` (no Hard adjustment). On Impossible the same ship gives `max(1, 10-1) = 9`. (source: Palm: Src/Skill.c:305-329, Src/spacetrader.h:149-150)
- **CRW-017** {M2} [M][W] The cloaking device gives the C# standard `+3` Pilot bonus. `Consts.CloakBonus = 2` exists but is unused. (source: Consts.cs:67, Consts.cs:151; research 01 §8)
- **CRW-018** {M2} [M][W] The ship's effective Trader is `Skills[Trader] + 1` when `HagglingComputerOnBoard`, that is when this is the commander's ship and `QuestStatusJarek == StatusJarekDone`. The +1 is added **after** the difficulty adjustment and gadget bonuses. (source: Ship.cs:1088-1094, Ship.cs:1315-1321)
- **CRW-019** {M2} [M][W][P] The difficulty adjustment also applies to every non-player ship's effective skills (opponents, special ships), because the same skill function serves every ship. (source: Ship.cs:1248 uses the game difficulty for any ship; Palm: Src/Skill.c:281-353 take any `SHIP*`)
- **CRW-020** {M2} [M][W] Special passengers held in the crew array (Wild, Jarek, Princess) contribute their skills to the effective-skill maximum: Wild 7/10/2/5, Jarek 3/2/10/4, Princess 4/3/8/9 (P/F/T/E). (source: Game.cs:2136-2138, Ship.cs:1238-1243)
- **CRW-021** {M5} [P] Palm passengers (Jarek while `JarekStatus == 1`, Wild while `WildStatus == 1`) are not in the crew array and contribute no skills. (source: Palm: Src/Skill.c:117-353 iterate `Sh->Crew[]` only; Src/SpecialEvent.c:238-276 set only the status)

## 4. Mercenary roster

- **CRW-022** {M1} [M][W] The C# roster has 55 crew ids (0...54): 0 Commander, 1-29 the original mercenaries, 30 Zeethibal, 31 Opponent, 32 Wild, 33 Jarek, 34 FamousCaptain, 35 Dragonfly, 36 Scarab, 37 SpaceMonster, 38-52 the 15 C# extras (Aragorn, Brady, Eight of Nine, Fangorn, Gagarin, Hoshi, Jackson, Kaylee, Marcus, O'Neill, Ripley, Stilgar, Taggart, Vansen, Xizor), 53 Princess (named "Ziyal"), 54 Scorpion. The name table has exactly 55 entries. (source: Enums.cs:258-316, Strings.cs:278; research 04 errata #7)
- **CRW-023** {M1} [M][W] The special crew ids are Commander, Dragonfly, FamousCaptain, Jarek, Opponent, Princess, Scarab, Scorpion, SpaceMonster and Wild. Zeethibal is **not** special. (source: Consts.cs:282-295)
- **CRW-024** {M1} [M][W] The fixed special-crew skills (P/F/T/E, d = difficulty) are: Zeethibal 5/5/5/5 (placeholder, system none), Opponent 5/5/5/5, Wild 7/10/2/5, Jarek 3/2/10/4, Princess 4/3/8/9, FamousCaptain 10/10/10/10, Dragonfly 4+d/6+d/1/6+d, Scarab 5+d/6+d/1/6+d, Scorpion 8+d/8+d/1/6+d, SpaceMonster 8+d/8+d/1/1+d. (source: Game.cs:2134-2143)
- **CRW-025** {M1} [M][W] Hireable mercenaries are generated for every id from 1 to 54 not already created (ids 1-29 and 38-52, 44 in total), in id order. For each, draw `GetRandom(128)` until the system holds fewer than 3 mercenaries, then draw 4 skills in P, F, T, E order with `RandomSkill() = 1 + GetRandom(5) + GetRandom(6)` (range 1...10). Kravat starts with a count of 1, so it holds at most 2 generated mercenaries. (source: Game.cs:2121-2167, Functions.cs:263-266; also GAL)
- **CRW-026** {M5} [P] The Palm roster has `MAXCREWMEMBER = 31`: names 0...30 (0 the commander, default "Jameson"; 1-29 mercenaries; 30 Zeethibal) plus a scratch index 31 used for opponents. For i = 1...31, draw `GetRandom(120)` and redraw if any earlier index j in 1...i-1 has that system or if it is Kravat; then draw 4 `RandomSkill()` values. Afterwards Zeethibal (index 30) is set to system 255 (absent). Index 31 occupies a system but is never offered for hire. (source: Palm: Src/spacetrader.h:84, Src/Global.c:146-180, Src/Traveler.c:1443-1481, Src/SystemInfoEvent.c:90-106)
- **CRW-027** {M2} [M][W] The mercenaries for hire in a system are every id i ≥ 1 whose current system is the commander's system and who is not in the player's crew, in ascending id order. (source: StarSystem.cs:331-347)
- **CRW-028** {M5} [P] Palm offers at most one mercenary for hire per system: the lowest index i in 1...30 whose system is the commander's and who is not in crew slot 1 or 2. (source: Palm: Src/SystemInfoEvent.c:90-106)

## 5. Wages

- **CRW-029** {M2} [M][W][P] A mercenary's daily wage is `(Pilot + Fighter + Trader + Engineer) * 3`, using the mercenary's raw skills. (source: CrewMember.cs:245-251; Palm: Src/spacetrader.h:457)
- **CRW-030** {M2} [M][W] Special crew and Zeethibal have a wage of 0. (source: CrewMember.cs:249)
- **CRW-031** {M5} [P] Palm Zeethibal (index 30) is paid the normal wage `(P+F+T+E)*3`. The macro's free branch only covers `a >= 31 && WildStatus == 2`. (source: Palm: Src/spacetrader.h:457; research 04 errata #7, research 07 I8)
- **CRW-032** {M2} [M][W] The total mercenary cost sums `Rate` over crew slots 1, 2, … and stops at the first empty slot. (source: Game.cs:3872-3882)
- **CRW-033** {M5} [P] The Palm total mercenary cost sums the wage over crew slots 1 and 2, skipping empty slots. (source: Palm: Src/Traveler.c:152-162)
- **CRW-034** {M2} [M][W][P] Example: a mercenary with skills 4/7/3/6 costs `20 * 3 = 60` credits per day. (source: CrewMember.cs:250)

## 6. Hiring and firing

- **CRW-035** {M2} [M][W] `hire(id)` requires the mercenary to be for hire here (CRW-027), to have a non-zero wage or be Zeethibal, and the ship to have at least one free crew slot. It does not check cash. On success the mercenary goes into the first empty crew slot and keeps its home system. With no free slot it is rejected with `CommandError.noFreeQuarters`. (source: Form_ViewPersonnel.cs:404-406, :440-449; Ship.cs:608-621, Ship.cs:996-1008)
- **CRW-036** {M5} [P] Palm `hire` puts the mercenary into crew slot 1, or slot 2 if slot 1 is taken. It is rejected with `CommandError.noFreeQuarters` when neither slot is free or when `AvailableQuarters() <= slot`, where `AvailableQuarters = CrewQuarters - (JarekStatus == 1 ? 1 : 0) - (WildStatus == 1 ? 1 : 0)`. It does not check cash. (source: Palm: Src/SystemInfoEvent.c:79-83, :871-899)
- **CRW-037** {M2} [M][W][P] `fire(id)` is a two-phase command: without acknowledgement it returns `.confirm(.fireMercenary(id))` and changes nothing. With acknowledgement it removes the mercenary and shifts later crew slots down by one. (source: Form_ViewPersonnel.cs:430-437, Ship.cs:195-209; Palm: Src/SystemInfoEvent.c:856-870)
- **CRW-038** {M2} [M][W] Wild, Jarek and the Princess cannot be fired (zero wage, no hire/fire button). Zeethibal can be hired and fired. A `fire` of a special crew id is rejected with `CommandError.cannotFireSpecialPassenger`. (source: Form_ViewPersonnel.cs:393, :406)
- **CRW-039** {M2} [M][W] A fired non-special mercenary (Zeethibal included) relocates: its system is set to none, then `GetRandom(128)` is drawn repeatedly until `Distance(system, commander's current system) < MaxRange (20)`. The current system itself qualifies. (source: Ship.cs:215-226, Consts.cs:57)
- **CRW-040** {M5} [P] A Palm mercenary's system never changes on hire or fire, so a fired mercenary (Zeethibal included) is next offered at its home system. (source: Palm: Src/SystemInfoEvent.c:856-870 only edit `Ship.Crew[]`)
- **CRW-041** {M2} [M][W][P] Hiring or firing recalculates buy prices for the current system when the ship's effective Trader changes (CRW-062). (source: Ship.cs:197, :211-212, :610, :619-620; Palm: Src/SystemInfoEvent.c:855, :906-907)

## 7. Special passengers and quarters

- **CRW-042** {M4} [M][W] Wild, Jarek and the Princess board with `Ship.Hire` into a crew slot (each needs a free slot, otherwise `SpecialNoQuarters`) and leave with `Ship.Fire` at their destination; as special crew they do not relocate. (source: Game.cs:2364-2381, :2400-2411, :2426-2427, :2533-2558, :2572; Ship.cs:215)
- **CRW-043** {M2} [M][W] C# quarters accounting: the crew array has `CrewQuarters` slots, slot 0 is the commander, and mercenaries and passengers both use slots. Free quarters = number of empty slots. (source: Ship.cs:762, Ship.cs:996-1008)
- **CRW-044** {M5} [P] Palm quarters accounting: crew slots 1...2 hold mercenaries only. Jarek and Wild each take one quarter through `AvailableQuarters` (CRW-036). Their boarding is refused when `Ship.Crew[CrewQuarters-1] >= 0`. (source: Palm: Src/SpecialEvent.c:238-276, Src/SystemInfoEvent.c:79-83)
- **CRW-045** {M5} [P] Palm quirk: on a 2-quarter ship, Wild can board while Jarek is aboard (slot 1 is empty because hiring was blocked), leaving 3 people in 2 quarters. The Palm ruleset needs a documented exception to the `crew ≤ quarters` invariant. Re-checked 2026-11-17: reachable whenever the Wild event is accepted while Jarek is aboard a 2-quarter ship with a beam laser (`Src/SpecialEvent.c:250-269` tests only `Crew[CrewQuarters-1]`, the laser and the reactor). Not representable while the engine keeps passengers in crew slots. (source: Palm: Src/SpecialEvent.c:240, :251, Src/SystemInfoEvent.c:79-83)
- **CRW-046** {M3} [M][W] When Wild "leaves" (a warp without a Beam laser or better and the player accepts, Game.cs:3168-3177; Wild hops onto a raiding pirate ship, Game.cs:1915-1920; Wild refuses to stay with the reactor, Game.cs:2440-2446), C# only resets `QuestStatusWild` to not-started. Wild stays in the crew array, still adding skills and using a quarter, because only `WildGetsOut` calls `Ship.Fire(Wild)`; since `WildOnBoard` is `HasCrew(Wild)`, the departure `IncDays(1)` then counts the reset status up again. [port quirk; RUL.md keep/fix row needed] (source: Game.cs:2572, Ship.cs:1343-1349)

## 8. Losing mercenaries (jail and escape pod)

- **CRW-047** {M3} [M][W] On arrest, all crew slots 1... are cleared only when `CrewCount - SpecialCrew.Length > 1` (two or more non-special crew). With exactly one mercenary, nobody leaves. [port quirk; RUL.md row needed] (source: Game.cs:254-259)
- **CRW-048** {M5} [P] On arrest, Palm clears crew slots 1...2 when `Ship.Crew[1] >= 0` (any mercenary). (source: Palm: Src/Encounter.c:706-711)
- **CRW-049** {M3} [M][W][P] The escape pod replaces the ship with a Flea, which has 1 crew slot, so every mercenary is lost. (source: Game.cs:735-741, :2101; Palm: Src/BuyShipEvent.c:108-120)
- **CRW-050** {M3} [W][P] A mercenary lost to jail or the escape pod keeps its old system id, so it is next offered where it was hired. (source: Game.cs:254-259, :735-741 no system update; Palm: Src/Encounter.c:709-710; research 01 §13 #21)
- **CRW-051** {M5} [M] MOD-016: each mercenary lost to jail or the escape pod relocates exactly like a fired one (CRW-039), in ascending crew-slot order, measured from the system where the commander arrives. (source: PRD §4.3 MOD-016)

## 9. Skill changes

- **CRW-052** {M2} [W] `ChangeRandomSkill(amount)` builds the list of skills with `skill + amount > 0 && skill + amount < 10`, in index order. If the list is not empty, it picks `list[GetRandom(list.Count)]` and adds `amount`. Random increases therefore stop at 9. (source: CrewMember.cs:69-87; research 01 §13 #5)
- **CRW-053** {M5} [M] MOD-005: Modern uses the CRW-052 algorithm with the condition `skill + amount > 0 && skill + amount <= 10`, so random increases can reach 10. (source: PRD §4.3 MOD-005)
- **CRW-054** {M5} [P] Palm `IncreaseRandomSkill` returns at once if all 4 skills are ≥ 10. Otherwise it draws `GetRandom(4)` until the chosen skill is < 10, then adds 1. Increases reach 10. (source: Palm: Src/Skill.c:170-205)
- **CRW-055** {M5} [P] Palm `DecreaseRandomSkill(n)` returns at once if all 4 skills are ≥ 10. Otherwise it draws `GetRandom(4)` until the chosen skill is `> n`, then subtracts n. The source loops forever when no skill is `> n`; the engine instead makes no change in that case. Re-checked: `Src/Skill.c:220-228` re-draws without bound; the no-op is a documented deviation (QA-REPORT "Accepted assumptions"). (source: Palm: Src/Skill.c:208-245)
- **CRW-056** {M3} [M][W][P] Good tonic: `IncreaseRandomSkill` once, and once more if difficulty ≤ Normal. (source: Game.cs:1122-1133; Palm: Src/Encounter.c:2286-2296 `Difficulty < HARD`)
- **CRW-057** {M3} [M][W][P] Strange tonic below Hard: repeat `+1 to a random skill, then -1 to a random skill` until at least one skill differs from its value before the drink. On Hard and Impossible: `+1`, `+1`, `-3` (each a random-skill change that may do nothing). C# uses `ChangeRandomSkill(+1/-1/-3)`; Palm uses `IncreaseRandomSkill` and `DecreaseRandomSkill(1 or 3)`. (source: CrewMember.cs:137-158; Palm: Src/Skill.c:248-279)
- **CRW-058** {M5} [P] Palm strange tonic below Hard when all skills are 10 would loop forever (both helpers return early). The engine ends the loop with no change. Re-checked: `Src/Skill.c:259-266` loops while the skills are unchanged; the engine stops when neither helper can change a skill (QA-REPORT "Accepted assumptions"). (source: Palm: Src/Skill.c:175-177, :213-215, :259-266)
- **CRW-059** {M3} [M][W][P] Famous-captain training: Ahab takes a Reflective shield and trains Pilot; Conrad takes a Military laser and trains Engineer; Huie takes a Military laser and trains Trader. The commander's raw skill becomes `min(10, skill + (difficulty <= Normal ? 2 : 1))`. (source: Game.cs:1402-1438; Palm: Src/Encounter.c:2165-2268)
- **CRW-060** {M3} [M][W] After Huie's training, C# does **not** recalculate buy prices. [port quirk; RUL.md row needed] (source: Game.cs:1434-1437)
- **CRW-061** {M5} [P] After Huie's training, Palm always calls `RecalculateBuyPrices(current system)`. (source: Palm: Src/Encounter.c:2266)
- **CRW-062** {M2} [M][W][P] Whenever a random skill change, hire or fire changes the effective Trader of the player's ship (CRW-018/CRW-013), buy prices for the current system are recalculated at once with `(103 + 10 - Trader)/100` (see ECO). (source: CrewMember.cs:82-85, Ship.cs:211-212, :619-620, Game.cs:2960-2974; Palm: Src/Skill.c:142-166, :198-199, :236-237)
- **CRW-063** {M4} [M][W][P] The Japori medicine delivery calls `IncreaseRandomSkill` twice. (source: Game.cs:2359-2362; Palm: Src/SpecialEvent.c:184-187)
- **CRW-064** {M4} [M][W][P] The Skill special event (price 3000) calls `IncreaseRandomSkill` once. (source: Game.cs:2514-2516, Consts.cs:331; Palm: Src/SpecialEvent.c:202-204)

## 10. Zeethibal

- **CRW-065** {M4} [M][W][P] When Wild is delivered, Zeethibal is placed at Kravat with skills 10 in the commander's lowest raw skill, 8 in the second lowest and 5 in the other two. Ties are broken in the order Pilot, Fighter, Trader, Engineer. (source: Game.cs:2560-2567, CrewMember.cs:103-121; Palm: Src/SpecialEvent.c:283-320, Src/Skill.c:62-110)
- **CRW-066** {M4} [M][W][P] Example: commander skills P4 F4 T6 E6 give Zeethibal P10 F8 T5 E5. (source: CrewMember.cs:107-118 stable sort; Palm: Src/Skill.c:68-108 ascending scan in P, F, T, E order)
- **CRW-067** {M4} [M][W] Zeethibal is hired through the normal personnel flow, has a wage of 0, and relocates within distance < 20 when fired. (source: CrewMember.cs:249, Form_ViewPersonnel.cs:406, Ship.cs:215)

## 11. Previews

- **CRW-068** {M2} [M][W][P] `preview(.crew)` is pure and returns: the effective ship skills (with each part: crew maximum, difficulty adjustment, gadget bonus, haggling bonus), the free quarters, the total daily mercenary cost, the mercenaries for hire here with their wages, and for each crew member whether `fire` is allowed (or its typed `CommandError`). (source: PRD §5 "WinForms logic moves into the engine"; Form_ViewPersonnel.cs:339-420)
- **CRW-069** {M2} [M][W][P] `preview(.newCommander(skills, name))` returns the points remaining (`20 - sum`), each skill's allowed maximum `min(10, skill + remaining)`, and whether the input is valid (or the `CommandError` from CRW-004/005/007). (source: Form_NewCommander.cs:382-391)
