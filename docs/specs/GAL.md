# GAL: Galaxy generation, placement and game construction

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. Ruleset tags: [M] Modern, [W] Windows 2.01, [P] Original Palm 1.2.2.
> - A bullet with several ruleset tags carries the milestone of its earliest ruleset. Modern and Palm must satisfy it by M5.
> - Modern uses the Windows 2.01 algorithm throughout, drawing from `Xoshiro256StarStar` (RNG.md). It differs only where a bullet says so (MOD-006, MOD-013).
> - Notation:
>   - `r(n)` is `rng.next(below: n)` (C# `GetRandom(n)`, Palm `GetRandom(n)`).
>   - `r(a,b)` is `rng.next(in: a..<b)` (C# `GetRandom(a,b)`, upper bound exclusive).
>   - All arithmetic is integer, and `/` truncates.
> - Sources:
>   - C#: `/Users/megatih/Downloads/SpaceTraderSource201` (`File.cs:line`).
>   - Palm: `docs/reference/palm-src/Src` (`Src/File.c:Function` or `:line`).
> - `[verify]` marks a value that can't be confirmed from the source. Each one must be closed, or logged as an accepted assumption in RUL.md, by the end of M5.

## 1. Constants

| Constant | Windows 2.01 / Modern | Palm 1.2.2 |
|---|---|---|
| Systems | 128 (ids 0…127) | 120 (ids 0…119) |
| Galaxy width × height | 154 × 110 | 150 × 110 |
| Minimum spacing | `MinDistance 7`: reject if `Distance < 7` (floored) | `MINDISTANCE 6`: reject if `SqrDistance <= SQR(MINDISTANCE+1) = 49` |
| Close distance | `CloseDistance 13`: need some `Distance < 13` | `CLOSEDISTANCE 13`: need some `SqrDistance < 169` |
| Wormholes | 6 (`_wormholes = new int[6]`) | `MAXWORMHOLE 6` |
| Wormhole tax factor | `WormDist 25` | literal `25L` |
| Max range | `MaxRange 20` (short-range chart, mercenary relocation) | `MAXRANGE 20` (short-range chart, Flea tanks) |
| Chart wormhole offset | n/a | `WORMHOLEDISTANCE 3` (chart drawing only) |

- **GAL-001** {M1} [M][W] The galaxy has 128 systems on a 154×110 grid, with `MinDistance = 7`, `CloseDistance = 13`, `MaxRange = 20`, `WormDist = 25` and exactly 6 wormholes. (source: Consts.cs:53-58; Game.cs:39)
- **GAL-002** {M5} [P] The galaxy has 120 systems on a 150×110 grid, with `MINDISTANCE = 6`, `CLOSEDISTANCE = 13`, `MAXRANGE = 20`, `MAXWORMHOLE = 6` and `WORMHOLEDISTANCE = 3` (the last is chart drawing only, never a rule). (source: Src/spacetrader.h:110, 219, 411-422)

## 2. Enumerations (raw values are identical in all rulesets)

| Enum | Values (raw value: name) |
|---|---|
| Size | 0 Tiny, 1 Small, 2 Medium, 3 Large, 4 Huge (C# also defines 5 Gargantuan, which generation never produces) |
| TechLevel | 0 Pre-Agricultural, 1 Agricultural, 2 Medieval, 3 Renaissance, 4 Early Industrial, 5 Industrial, 6 Post-Industrial, 7 Hi-Tech (C# 8 Unavailable is only an equipment/ship marker) |
| SystemPressure (Palm "Status") | 0 None ("under no particular pressure"), 1 War, 2 Plague, 3 Drought, 4 Boredom, 5 Cold, 6 CropFailure, 7 Employment ("lacking enough workers") |
| SpecialResource | 0 Nothing, 1 MineralRich, 2 MineralPoor, 3 Desert, 4 SweetOceans, 5 RichSoil, 6 PoorSoil, 7 RichFauna, 8 Lifeless, 9 WeirdMushrooms, 10 SpecialHerbs, 11 Artistic, 12 Warlike |
| Activity | 0 Absent, 1 Minimal, 2 Few, 3 Some, 4 Moderate, 5 Many, 6 Abundant, 7 Swarms (C# 100 = NA, ship tables only) |

- **GAL-003** {M1} [M][W][P] `Size`, `TechLevel`, `SystemPressure`, `SpecialResource` and `Activity` have the raw values in the table above. Galaxy generation only produces sizes 0…4, tech levels 0…7, pressures 0…7 and resources 0…12. (source: Enums.cs:224-235, 582-590, 658-673, 813-823, 827-838; Palm: Src/spacetrader.h:61, 310, 321, 394; Src/Global.c name tables)

## 3. Political systems (17 rows, index order matters for `r(17)`)

| # | Name | Reaction to illegal goods | Police | Pirates | Traders | Min tech | Max tech | Bribe level | Drugs OK | Firearms OK | Wanted item |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | Anarchy | 0 | Absent (0) | Swarms (7) | Minimal (1) | Pre-Agricultural (0) | Industrial (5) | 7 | yes | yes | Food |
| 1 | Capitalist State | 2 | Some (3) | Few (2) | Swarms (7) | Early Industrial (4) | Hi-Tech (7) | 1 | yes | yes | Ore |
| 2 | Communist State | 6 | Abundant (6) | Moderate (4) | Moderate (4) | Agricultural (1) | Industrial (5) | 5 | yes | yes | none |
| 3 | Confederacy | 5 | Moderate (4) | Some (3) | Many (5) | Agricultural (1) | Post-Industrial (6) | 3 | yes | yes | Games |
| 4 | Corporate State | 2 | Abundant (6) | Few (2) | Swarms (7) | Early Industrial (4) | Hi-Tech (7) | 2 | yes | yes | Robots |
| 5 | Cybernetic State | 0 | Swarms (7) | Swarms (7) | Many (5) | Post-Industrial (6) | Hi-Tech (7) | 0 | no | no | Ore |
| 6 | Democracy | 4 | Some (3) | Few (2) | Many (5) | Renaissance (3) | Hi-Tech (7) | 2 | yes | yes | Games |
| 7 | Dictatorship | 3 | Moderate (4) | Many (5) | Some (3) | Pre-Agricultural (0) | Hi-Tech (7) | 2 | yes | yes | none |
| 8 | Fascist State | 7 | Swarms (7) | Swarms (7) | Minimal (1) | Early Industrial (4) | Hi-Tech (7) | 0 | no | yes | Machines |
| 9 | Feudal State | 1 | Minimal (1) | Abundant (6) | Few (2) | Pre-Agricultural (0) | Renaissance (3) | 6 | yes | yes | Firearms |
| 10 | Military State | 7 | Swarms (7) | Absent (0) | Abundant (6) | Medieval (2) | Hi-Tech (7) | 0 | no | yes | Robots |
| 11 | Monarchy | 3 | Moderate (4) | Some (3) | Moderate (4) | Pre-Agricultural (0) | Industrial (5) | 4 | yes | yes | Medicine |
| 12 | Pacifist State | 7 | Few (2) | Minimal (1) | Many (5) | Pre-Agricultural (0) | Renaissance (3) | 1 | yes | no | none |
| 13 | Socialist State | 4 | Few (2) | Many (5) | Some (3) | Pre-Agricultural (0) | Industrial (5) | 6 | yes | yes | none |
| 14 | State of Satori | 0 | Minimal (1) | Minimal (1) | Minimal (1) | Pre-Agricultural (0) | Agricultural (1) | 0 | no | no | none |
| 15 | Technocracy | 1 | Abundant (6) | Some (3) | Abundant (6) | Early Industrial (4) | Hi-Tech (7) | 2 | yes | yes | Water |
| 16 | Theocracy | 5 | Abundant (6) | Minimal (1) | Moderate (4) | Pre-Agricultural (0) | Early Industrial (4) | 0 | yes | yes | Narcotics |

- **GAL-004** {M1} [M][W][P] The political-system table holds exactly the 17 rows above, in that order and with those values. The Palm `Politics[]` table is value-identical (its "none" wanted item is written as `-1`). A table test asserts every cell. (source: Consts.cs:175-194; Strings.cs:596-614; Palm: Src/Global.c:335-354)

## 4. System names

C# ids and names (Strings.cs:850-983, enum Enums.cs:678-808): 0 Acamar, 1 Adahn, 2 Aldea, 3 Andevian, 4 Antedi, 5 Balosnee, 6 Baratas, 7 Brax, 8 Bretel, 9 Calondia, 10 Campor, 11 Capelle, 12 Carzon, 13 Castor, 14 Cestus, 15 Cheron, 16 Courteney, 17 Daled, 18 Damast, 19 Davlos, 20 Deneb, 21 Deneva, 22 Devidia, 23 Draylon, 24 Drema, 25 Endor, 26 Esmee, 27 Exo, 28 Ferris, 29 Festen, 30 Fourmi, 31 Frolix, 32 Gemulon, 33 Guinifer, 34 Hades, 35 Hamlet, 36 Helena, 37 Hulst, 38 Iodine, 39 Iralius, 40 Janus, 41 Japori, 42 Jarada, 43 Jason, 44 Kaylon, 45 Khefka, 46 Kira, 47 Klaatu, 48 Klaestron, 49 Korma, 50 Kravat, 51 Krios, 52 Laertes, 53 Largo, 54 Lave, 55 Ligon, 56 Lowry, 57 Magrat, 58 Malcoria, 59 Melina, 60 Mentar, 61 Merik, 62 Mintaka, 63 Montor, 64 Mordan, 65 Myrthe, 66 Nelvana, 67 Nix, 68 Nyle, 69 Odet, 70 Og, 71 Omega, 72 Omphalos, 73 Orias, 74 Othello, 75 Parade, 76 Penthara, 77 Picard, 78 Pollux, 79 Quator, 80 Rakhar, 81 Ran, 82 Regulas, 83 Relva, 84 Rhymus, 85 Rochani, 86 Rubicum, 87 Rutia, 88 Sarpeidon, 89 Sefalla, 90 Seltrice, 91 Sigma, 92 Sol, 93 Somari, 94 Stakoron, 95 Styris, 96 Talani, 97 Tamus, 98 Tantalos, 99 Tanuga, 100 Tarchannen, 101 Terosa, 102 Thera, 103 Titan, 104 Torin, 105 Triacus, 106 Turkana, 107 Tyrus, 108 Umberlee, 109 Utopia, 110 Vadera, 111 Vagra, 112 Vandor, 113 Ventax, 114 Xenon, 115 Xerxes, 116 Yew, 117 Yojimbo, 118 Zalkon, 119 Zuul, 120 Centauri, 121 Galvon, 122 Inthara, 123 Meridian, 124 Qonos, 125 Rae, 126 Weytahn, 127 Zonama.

- **GAL-005** {M1} [M][W] The system name table has 128 entries in the order above. Ids 120–127 (Centauri, Galvon, Inthara, Meridian, Qonos, Rae, Weytahn, Zonama) are the 8 port additions. Names come from the content pack and reach the UI through localization. The engine stores only ids. (source: Strings.cs:850-983; Enums.cs:678-808)
- **GAL-006** {M5} [P] The Palm system name table has 120 entries, identical to C# ids 0…119 in order and spelling. The Palm fixed-system constants are Acamar 0, Baratas 6, Daled 17, Devidia 22, Gemulon 32, Japori 41, Kravat 50, Melina 59, Nix 67, Regulas 82, Utopia 109 and Zalkon 118. They equal the C# ids. (source: Src/Global.c:358 `SolarSystemName`; Src/spacetrader.h:219-233)

## 5. Distance functions

Palm integer square root (Src/Math.c:44-55), verbatim:
```c
int sqrt( int a )
{
	int i;
	i = 0;
	while (SQR( i ) < a)
		++i;
	if (i > 0)
		if ((SQR( i ) - a) > (a - SQR( i-1 )))
			--i;
	return( i );
}
long SqrDistance( SOLARSYSTEM a, SOLARSYSTEM b ) { return (SQR( a.X - b.X ) + SQR( a.Y - b.Y )); }   // Math.c:60-63
long RealDistance( SOLARSYSTEM a, SOLARSYSTEM b ) { return (sqrt( SqrDistance( a, b ) )); }          // Math.c:69-72
```

- **GAL-007** {M1} [M][W] `distance(a, b) = floor(sqrt(dx² + dy²))`. It is implemented as an exact integer floor square root, which equals C# `(int)Math.Floor(Math.Sqrt(Math.Pow(dx,2)+Math.Pow(dy,2)))` for every input below 2⁵². A test checks every `dx` in 0…153 and `dy` in 0…109. The coordinate overload `distance(system, x, y)` uses the same formula. (source: Functions.cs:83-91)
- **GAL-008** {M5} [P] `realDistance(a, b)` applies the Palm `sqrt` above to `sqrDistance(a, b) = dx² + dy²`. It finds the smallest `i` with `i² ≥ a`, then decrements if `i² − a > a − (i−1)²`. For integers there are no ties, so this rounds to the nearest integer: `sqrDistance` 12 → 3, 13 → 4, 56 → 7, 57 → 8. A test checks the port against a literal transliteration for every `a` in 0…34600. (source: Src/Math.c:44-72)
- **GAL-009** {M5} [P] The port computes `sqrDistance` and `realDistance` in exact (≥32-bit) integer arithmetic. The original was built with CodeWarrior 68K (`Space Trader.mcp`). If `int` was 16-bit there, `sqrt(int a)` would mis-handle `sqrDistance > 32767` (distance ≥ 182, possible only near opposite corners). That case is `[verify]` (accepted assumption: exact arithmetic). (source: Src/Math.c:44; docs/reference/palm-src/Space Trader.mcp)

## 6. Construction order

- **GAL-010** {M1} [M][W] Game construction follows exactly this order: (1) repeat `GenerateUniverse()` until `PlaceSpecialEvents() && PlaceShipyards()` succeeds (`PlaceShipyards` runs only if `PlaceSpecialEvents` succeeded, by short-circuit, and the RNG is **not** reset between attempts); (2) `InitializeCommander` (start system); (3) `GenerateCrewMemberList`; (4) `CreateShips`; (5) `CalculatePrices(start)` (ECO); (6) `ResetVeryRareEncounters` (no draws); (7) if `difficulty < Normal`, the start system's event becomes `Lottery` (no draws). The harness compares the complete draw sequence. (source: Game.cs:110-133; research 01 errata #4)
- **GAL-011** {M5} [P] Palm construction follows exactly this order: (1) system generation (§8); (2) position shuffle, then wormhole shuffle (§9); (3) mercenaries (§12); (4) special events (§10.2); (5) start system (§13); (6) the player's skills and difficulty (the New Commander form, no draws); (7) `DeterminePrices(start)` (ECO); (8) `Lottery`, if `Difficulty < NORMAL` **and** the start system has no special event. Palm never regenerates the galaxy. (source: Src/Traveler.c:StartNewGame; Src/Traveler.c:NewCommanderFormHandleEvent, 2589-2595)
- **GAL-012** {M5} [P] The original Palm built the galaxy *before* the New Commander form, so its robot and narcotics quantities used whatever `Difficulty` was in effect beforehand. The port generates the galaxy after the New Game wizard has fixed the difficulty, and uses that difficulty. This is an accepted deviation, recorded in RUL.md. It changes no rule, only stale-state leakage. (source: Src/Traveler.c:1405, 2578-2595)

## 7. Windows 2.01 per-system generation (`GenerateUniverse`)

- **GAL-013** {M1} [M][W] For each system `i` in 0…127, in index order, the draws happen in exactly this order: (1) `size = r(5)`; (2) `pol = r(17)`; (3) `tech = r(pol.minTech, pol.maxTech + 1)`; (4) pressure roll(s) (GAL-016); (5) resource roll(s) (GAL-017); (6) coordinate roll(s) (GAL-018/019); (7) the `StarSystem` constructor's `InitializeTradeItems` draws (ECO): for each traded item 0…9 in order, `r(9,14)` and then two `r(10)` (subtracted first, then added). (source: Game.cs:2181-2237; StarSystem.cs:52-65, 84-115)
- **GAL-014** {M1} [M][W] The tech level is uniform over the chosen government's inclusive `[minTech, maxTech]` range (GAL-004). Every government has probability 1/17. (source: Game.cs:2187-2188)
- **GAL-015** {M1} [M][W] Galvon (id 121) is overridden **after** its size, government and tech draws have been consumed: `size = Large (3)`, `government = Monarchy (11)`, `tech = Hi-Tech (7)`. Its pressure, resource and coordinate draws still happen normally. Galvon is therefore always Hi-Tech, even though Monarchy's table maximum is Industrial. (source: Game.cs:2190-2196)
- **GAL-016** {M1} [M][W] Pressure: if `r(100) < 15`, then `pressure = r(1, 8)` (War…Employment, 1…7); otherwise `None`, with no second draw. (source: Game.cs:2198-2199)
- **GAL-017** {M1} [M][W] Special resource: if `r(5) >= 3`, then `resource = r(1, 13)` (MineralRich…Warlike, 1…12); otherwise `Nothing`, with no second draw. (source: Game.cs:2200-2201)
- **GAL-018** {M1} [M][W] Wormhole systems `i < 6` are placed by two draws, `x` before `y`: `x = (154 * (1 + 2*(i % 3))) / 6 − r(−12, 13)`; `y = (110 * (i < 3 ? 1 : 3)) / 4 − r(−12, 13)`. There are no distance checks, and `Wormholes[i] = i`. The x centres are 25, 77, 128 and the y centres 27, 82, giving x in 13…37, 65…89 or 116…140 and y in 15…39 or 70…94. (source: Game.cs:2206-2212)
- **GAL-019** {M1} [M][W] Every other system repeats this until it accepts a position: draw `x = r(1, 154)`, then `y = r(1, 110)`; scan the earlier systems `j = 0…i−1` in order, where `distance(j, x, y) < 7` sets `tooClose` and stops the scan and `distance(j, x, y) < 13` sets `closeFound`; accept if and only if `closeFound && !tooClose`, otherwise draw a new pair. The coordinates fall in x 1…153 and y 1…109. (source: Game.cs:2213-2235)
- **GAL-020** {M1} [W] Trade quantities are initialised while the system is constructed. At that point `StarSystem.SpecialResource` returns `Nothing` because the system isn't visited, so special resources never affect the starting quantities. (The pressure `/5` rule does apply.) (source: StarSystem.cs:84-115, 424-429; research 01 §13.7)
- **GAL-021** {M5} [M] Under MOD-006 the starting quantities use the system's actual special resource. Only the draw values change, never the draw count, because the resource multipliers draw nothing. (source: PRD §4.3 MOD-006; StarSystem.cs:101-105)
- **GAL-022** {M1} [M][W] Each newly generated system starts with no special event (`NA`), no shipyard (`NA`), `countDown = 0` and `visited = false`. (source: StarSystem.cs:42-46)

## 8. Palm per-system generation (`StartNewGame`)

- **GAL-023** {M5} [P] Systems are filled in slots `i = 0…119`. `i` advances only when an attempt is accepted. Each attempt for slot `i` draws in exactly this order: (1) `X`, then `Y` (GAL-024/025); (2) if `i ≥ 6`, the distance checks (no draws; a rejection here ends the attempt); (3) `TL = r(8)`, then `Pol = r(17)`, and if `TL < Politics[Pol].MinTechLevel` or `TL > Politics[Pol].MaxTechLevel` the attempt is rejected and slot `i` restarts from new X and Y (wormhole slots too); (4) resource: `r(5) >= 3 ? 1 + r(12) : 0`; (5) `Size = r(5)`; (6) status: `r(100) < 15 ? 1 + r(7) : 0`; (7) `InitializeTradeitems(i)` (ECO). (source: Src/Traveler.c:1341-1408)
- **GAL-024** {M5} [P] Wormhole slots `i < 6` set: `X = (6 − r(13)) + (150 * (1 + 2*(i % 3))) / 6`; `Y = (6 − r(13)) + (110 * (i < 3 ? 1 : 3)) / 4`. That gives X in 19…31, 69…81 or 119…131 and Y in 21…33 or 76…88. `Wormhole[i] = i`, and there are no distance checks. (source: Src/Traveler.c:1343-1351)
- **GAL-025** {M5} [P] Other slots set `X = 1 + r(148)` (1…148) and `Y = 1 + r(108)` (1…108). They then scan `j = 0…i−1`. `SqrDistance(j, i) <= 49` rejects and stops the scan. `SqrDistance(j, i) < 169` sets `CloseFound`. The attempt is rejected if no system was close. (source: Src/Traveler.c:1352-1379)
- **GAL-026** {M5} [P] Because the government and tech level are rejection-sampled together, each accepted system's (TL, government) pair is uniform over the 81 valid pairs. P(government) = (max − min + 1)/81: for example Dictatorship 8/81 and Satori 2/81. A statistical test over 100 seeds × 120 systems accepts each government's frequency within ±3σ of that value. (source: Src/Traveler.c:1381-1386)
- **GAL-027** {M5} [P] Palm's starting quantity uses `SolarSystem[i].Size` with `i` = the trade-item index (ECO, research 04 §3). For systems generated before slot 9 is filled, some of those entries belong to systems not yet generated in this game. The original read stale memory there. The port reads **Size 0** for any system not yet generated. That is `[verify]` (accepted assumption). (source: Src/Traveler.c:InitializeTradeitems, 397-400)
- **GAL-028** {M5} [P] Each Palm system starts with `Special = −1` (none), `CountDown = 0` and `Visited = false`. (source: Src/Traveler.c:1400-1403)

## 9. Position shuffle and wormholes

- **GAL-029** {M1} [M][W][P] Position shuffle runs for `i = 0…N−1`: draw `j = r(N)` (always consumed); if `j` is currently a wormhole system (it appears in `Wormholes`), skip; otherwise swap the (x, y) of systems `i` and `j` and, if `i` was a wormhole system at index `w`, set `Wormholes[w] = j`. The wormhole therefore follows its coordinates. Palm computes `w` before drawing `j`, which gives the same result. (source: Game.cs:2240-2258; Palm: Src/Traveler.c:1410-1431)
- **GAL-030** {M1} [M][W][P] Wormhole order shuffle runs for `i = 0…5`: draw `j = r(6)` and swap `Wormholes[i]` with `Wormholes[j]`. (source: Game.cs:2260-2267; Palm: Src/Traveler.c:1434-1441)
- **GAL-031** {M1} [M][W][P] Wormholes form a one-directional ring, `Wormholes[k] → Wormholes[(k+1) % 6]`: `wormholeExists(a, b)` is true if and only if `a = Wormholes[k]` and `b = Wormholes[(k+1) % 6]`; `wormholeExists(a, −1)` is true if and only if `a` is in `Wormholes`; `wormholeTarget(a) = Wormholes[(k+1) % 6]`. (source: Functions.cs:334-356; Palm: Src/Traveler.c:2401-2427)
- **GAL-032** {M3} [M][W][P] The wormhole tax is `25 ×` the ship's per-parsec fuel cost, charged only when `wormholeExists(current, target)`. For which cost column each ruleset uses, see TRV.md and MOD-017. (source: Game.cs:4415; Palm: Src/Traveler.c:167-173)

## 10. Special-event placement

### 10.1 Windows 2.01 / Modern (`PlaceSpecialEvents`)

| System | Event | System | Event |
|---|---|---|---|
| Baratas (6) | DragonflyBaratas | Utopia (109) | MoonRetirement |
| Melina (59) | DragonflyMelina | Nix (67) | ReactorDelivered |
| Regulas (82) | DragonflyRegulas | Acamar (0) | SpaceMonsterKilled |
| Zalkon (118) | DragonflyDestroyed | Kravat (50) | WildGetsOut |
| Daled (17) | ExperimentStopped | Endor (25) | SculptureDelivered |
| Gemulon (32) | GemulonRescued | Galvon (121) | Princess |
| Japori (41) | JaporiDelivery | Centauri (120) | PrincessCentauri |
| Devidia (22) | JarekGetsOut | Inthara (122) | PrincessInthara |
| | | Qonos (124) | PrincessQonos |

- **GAL-033** {M1} [M][W] The 17 fixed events above are assigned first, with no draws. (source: Game.cs:2885-2901)
- **GAL-034** {M1} [M][W] `ScarabDestroyed` goes to the first `Wormholes[k]`, for `k = 0…5` in ring order, that has no event. If none is free, placement fails. No draws. (source: Game.cs:2903-2909)
- **GAL-035** {M1} [M][W] `ArtifactDelivery` goes to the **lowest-index** system that has no event and tech `Hi-Tech`. If there is none, placement fails. No draws. (Galvon is always Hi-Tech but already holds `Princess`.) (source: Game.cs:2911-2921)
- **GAL-036** {M1} [M][W] `FindDistantSystem` runs in this order: (Nix → `Reactor`), (Gemulon → `Gemulon`), (Daled → `Experiment`), (Endor → `Sculpture`). Each picks the system with no event, `distance(base, i) >= 70` and the strictly smallest distance. It starts from `best = 999`, scans in index order, and ties go to the lowest index. The first failure stops placement, and the remaining steps are skipped. No draws. (source: Game.cs:2102-2119, 2923-2938)
- **GAL-037** {M1} [M][W] Random placement walks `Consts.SpecialEvents` in table order. Each entry with `Occurrence > 0` is placed `Occurrence` times; each placement draws `s = r(128)` until system `s` has no event, then assigns the event. Order and counts: Artifact 1, CargoForSale 3, Dragonfly 1, EraseRecord 3, Japori 1, Jarek 1, Moon 4, Scarab 1, Skill 3, SpaceMonster 1, Tribble 1, TribbleBuyer 3, Wild 1 (24 in total). (source: Game.cs:2940-2956; Consts.cs:299-347)
- **GAL-038** {M1} [M][W] After a successful placement and before the Lottery, exactly 47 systems have an event: 17 fixed, plus 1 Scarab end-point, 1 artifact delivery, 4 distant, plus 24 random. Every event type appears exactly as often as GAL-033…037 specify. (source: Game.cs:2880-2959)
- **GAL-039** {M1} [M][W] A failed placement (special events or shipyards) discards the whole universe and calls `GenerateUniverse` again with the RNG continuing. A scripted-RNG test forces a first universe with fewer than 5 Hi-Tech systems and checks that a second universe is generated and used. (source: Game.cs:115-118)

### 10.2 Palm 1.2.2 (`StartNewGame`)

Palm event indices (Src/spacetrader.h:237-276; Src/Global.c `SpecialEvent`), shown as name/occurrence:
- **Fixed, 0–6:** 0 DragonflyDestroyed, 1 FlyBaratas, 2 FlyMelina, 3 FlyRegulas, 4 MonsterKilled, 5 MedicineDelivery, 6 MoonBought ("Retirement").
- **Randomly placed, 7–29:** 7 MoonForSale/4, 8 SkillIncrease/3, 9 Tribble ("Merchant Prince")/1, 10 EraseRecord/3, 11 BuyTribble/3, 12 SpaceMonster/1, 13 Dragonfly/1, 14 CargoForSale/3, 15 InstallLightningShield/0, 16 JaporiDisease/1, 17 LotteryWinner/0, 18 ArtifactDelivery/0, 19 AlienArtifact/1, 20 AmbassadorJarek/1, 21 AlienInvasion/0, 22 GemulonInvaded/0, 23 GetFuelCompactor/0, 24 Experiment/0, 25 TransportWild/1, 26 GetReactor/0, 27 GetSpecialLaser/0, 28 Scarab/1, 29 GetHullUpgraded/0.
- **Fixed, 30–36:** 30 ScarabDestroyed, 31 ReactorDelivered, 32 JarekGetsOut, 33 GemulonRescued, 34 ExperimentStopped, 35 ExperimentNotStopped, 36 WildGetsOut.

- **GAL-040** {M5} [P] The Palm event table has the 37 entries above, in that index order. The prices and message-only flags come from `Src/Global.c` `SpecialEvent[]`. (source: Src/Global.c `SpecialEvent[MAXSPECIALEVENT]`; Src/spacetrader.h:237-276)
- **GAL-041** {M5} [P] The fixed events are assigned first, with no draws: Acamar MonsterKilled, Baratas FlyBaratas, Melina FlyMelina, Regulas FlyRegulas, Zalkon DragonflyDestroyed, Japori MedicineDelivery, Utopia MoonBought, Devidia JarekGetsOut, Kravat WildGetsOut. (source: Src/Traveler.c:1484-1492)
- **GAL-042** {M5} [P] Scarab end-point: set `k = 0` and draw `j = r(6)`; while `Special[Wormhole[j]] != −1 && Wormhole[j] ∉ {Gemulon, Daled, Nix} && k < 20`, draw `j = r(6)` and increment `k`; if `k < 20`, place `ScarabDestroyed` at `Wormhole[j]` and set `FreeWormhole = true`. Otherwise there is no Scarab quest and `FreeWormhole = false`. That is at most 21 draws, of which only the first 20 can succeed. The quirky G/D/N clause is reproduced: the end-point can land on Gemulon, Daled or Nix and be overwritten later. (source: Src/Traveler.c:1493-1510)
- **GAL-043** {M5} [P] Reactor: `k` is the system with `Special < 0` and the smallest `realDistance(Nix, i) >= 70`. The scan starts from `d = 999` and runs in index order, and ties keep the first. The source's exclusion `d != GEMULON && d != DALED` compares the *distance* against the ids 32 and 17, so it never excludes anything, and Gemulon or Daled can be chosen (reproduced). If `k` is found, set `Special[k] = GetReactor` and `Special[Nix] = ReactorDelivered`, overwriting a Scarab end-point at Nix. If not, nothing changes. No draws. (source: Src/Traveler.c:1512-1528)
- **GAL-044** {M5} [P] Artifact delivery makes up to 120 attempts. Each draws `d = 1 + r(119)` and accepts if `Special[d] < 0 && TL[d] >= 7 && d ∉ {Gemulon, Daled}`. Acceptance sets `ArtifactDelivery` and stops. If all 120 attempts fail, the AlienArtifact occurrence becomes 0 **for this game**. (The original wrote into the global `const` table, which could leak into later games in the same session. The port scopes it to the game: `[verify]` persistence, accepted.) (source: Src/Traveler.c:1531-1544)
- **GAL-045** {M5} [P] Alien invasion: the scan looks for `Special < 0`, `realDistance(Gemulon, i) >= 70` and a strictly smaller distance. The source's exclusion `k != DALED && k != GEMULON` tests the *current best* `k`, not `i`. So once Daled (17) becomes the best candidate, no later system can replace it (reproduced). If `k` is found, set `Special[k] = AlienInvasion` and `Special[Gemulon] = GemulonRescued`, overwriting any `GetReactor` or `ScarabDestroyed` at Gemulon. No draws. (source: Src/Traveler.c:1546-1563)
- **GAL-046** {M5} [P] Experiment: `k` is the system with `Special < 0` and the smallest `realDistance(Daled, i) >= 70`, with no exclusion. If `k` is found, set `Special[k] = Experiment` and `Special[Daled] = ExperimentStopped`, overwriting any `GetReactor`, `AlienInvasion` or `ScarabDestroyed` at Daled. No draws. (source: Src/Traveler.c:1565-1580)
- **GAL-047** {M5} [P] The random events, indices 7…29, are placed in index order, `Occurrence` times each. Each placement draws `d = 1 + r(119)` until `Special[d] < 0`. It then assigns the event, except when `i == Scarab (28)` and `!FreeWormhole`: then the drawn system stays empty, though its draws were consumed. Random events therefore never land on Acamar. (source: Src/Traveler.c:1583-1598)
- **GAL-048** {M5} [P] The overwrites in GAL-043…046 are reproduced, not repaired. For example, when `GetReactor` lands on Gemulon and is then overwritten, the reactor quest is unreachable while Nix keeps `ReactorDelivered`. A scripted-RNG test builds this case and asserts the resulting `Special` array. Palm placement failures never cause regeneration. (source: Src/Traveler.c:1512-1580; research 04 §3)

## 11. Shipyards

- **GAL-049** {M1} [W] `PlaceShipyards` lists the Hi-Tech systems in ascending index order, Galvon included. If there are fewer than 5, it fails (GAL-039). Otherwise, for shipyard 0…4 (Corellian, Incom, Kuat, Sienar, Sorosuub), it sets `list[r(list.count)].shipyard = that shipyard`. Collisions overwrite (the last one wins), so a galaxy can end up with only 1…5 distinct shipyard systems (reproduced). (source: Game.cs:2857-2877; Consts.cs:272-279)
- **GAL-050** {M5} [M] Under MOD-013, shipyard `k = 0…4` draws `idx = r(remaining.count)`, takes `remaining[idx]` and removes it from `remaining`. The 5 shipyards always sit on 5 distinct Hi-Tech systems, with the same 5 draws as Windows 2.01. (source: PRD §4.3 MOD-013; research 01 §13.17)
- **GAL-051** {M5} [P] Palm has no shipyards, and galaxy construction makes no shipyard draws. (source: research 04 big picture; Src/Traveler.c:StartNewGame)
- **GAL-052** {M1} [M][W] Shipyard placement ignores special events, so a system may have both. The shipyard data (`Size`, skill) comes from `Consts.Shipyards`: Corellian Large/CrewQuarters, Incom Medium/ShieldSlotUnits, Kuat Huge/HullPerUnit, Sienar Tiny/WeaponSlotUnits, Sorosuub Small/FuelBase. (source: Consts.cs:272-279)

## 12. Mercenaries

| Character (id) | Pilot | Fighter | Trader | Engineer |
|---|---|---|---|---|
| Zeethibal (30) | 5 | 5 | 5 | 5 |
| Opponent (31) | 5 | 5 | 5 | 5 |
| Wild (32) | 7 | 10 | 2 | 5 |
| Jarek (33) | 3 | 2 | 10 | 4 |
| Princess "Ziyal" (53) | 4 | 3 | 8 | 9 |
| FamousCaptain (34) | 10 | 10 | 10 | 10 |
| Dragonfly (35) | 4+d | 6+d | 1 | 6+d |
| Scarab (36) | 5+d | 6+d | 1 | 6+d |
| Scorpion (54) | 8+d | 8+d | 1 | 6+d |
| SpaceMonster (37) | 8+d | 8+d | 1 | 1+d |

Here d = difficulty (Beginner 0 … Impossible 4).

- **GAL-053** {M1} [M][W] The special crew members take exactly the skills in the table above. Their system is `NA`, and creating them draws nothing. The commander occupies id 0, set in `InitializeCommander` before this step. There are 55 ids (0…54) in total. (source: Game.cs:2121-2143; Enums.cs:258-315)
- **GAL-054** {M1} [M][W] The remaining 44 mercenaries are generated in ascending id order: ids 1…29 and 38…52. For each one: draw `s = r(128)` until `used[s] < 3`, then increment `used[s]`; then draw `pilot`, `fighter`, `trader` and `engineer` as four `randomSkill()` calls, in that order. `used[Kravat]` starts at 1, so Kravat holds at most 2 random mercenaries, and every other system at most 3. (source: Game.cs:2123-2127, 2145-2166)
- **GAL-055** {M5} [P] Palm's `Mercenary[0]` is the commander, given placeholder skills 1/1/1/1 until the New Commander form. For `i = 1…31` (`MAXCREWMEMBER` inclusive), in order: draw `CurSystem = r(120)`; redo the slot if any `Mercenary[1…i−1]` has the same system, or if the system is Kravat (50); then draw four `RandomSkill()` values (pilot, fighter, trader, engineer). After the loop, `Mercenary[30]` (Zeethibal) gets `CurSystem = 255` (nowhere). (source: Src/Traveler.c:1443-1481)
- **GAL-056** {M5} [P] Slot 31, the opponent scratch slot, keeps the system drawn for it. That system therefore has no hireable mercenary. The hire lookup scans ids 1…30 only, and Zeethibal (30) is hireable only after the Wild quest moves him to Kravat. Ids 1…29 sit in 29 distinct non-Kravat systems. (source: Src/SystemInfoEvent.c:90-107 `GetForHire`; Src/SpecialEvent.c:285-291)

## 13. Commander start

- **GAL-057** {M1} [M][W] The start system repeats this until it accepts a system: draw `s = r(128)`; accept if and only if: system `s` has no event, `1 <= tech <= 6` (above Pre-Agricultural and below Hi-Tech), and at least 3 *other* systems have `distance(i, s) <= 14` (the Gnat's `FuelTanks`). The neighbour count stops at 3. Then set `visited = true`. The source loop is unbounded. The port caps it at 1,000,000 draws and raises a typed `GalaxyError.noStartSystem`, which the invariant suite (GAL-070) proves never happens. (source: Game.cs:2685-2712; Consts.cs ShipSpecs Gnat fuel 14)
- **GAL-058** {M5} [P] The start system makes up to 200 tries, `i = 0…199`. Each try draws `s = r(120)` and skips if `Special[s] >= 0`. While `i < 100` it also skips unless `1 <= TL <= 5`. It skips unless at least 3 other systems have `SqrDistance <= 196` (14²). The first try that passes is accepted. If all 200 fail, the system drawn last is used without any check (reproduced). (source: Src/Traveler.c:1601-1630)
- **GAL-059** {M1} [M][W][P] The commander starts with: cash 1000, debt 0, days 0, police record 0, reputation 0 and all kills 0; no insurance, no-claim 0, no escape pod, and every cost basis (`PriceCargo` / `BuyingPrice`) 0; a Gnat with exactly one Pulse Laser, fuel = 14 (full tanks), hull = 100 and an empty hold. (source: Commander.cs:35-57; Ship.cs:755-765; Palm: Src/Traveler.c:1632-1692)
- **GAL-060** {M1} [M][W] If `difficulty < Normal` (Beginner or Easy), the start system's event is set to `Lottery` unconditionally, after `ResetVeryRareEncounters`. (source: Game.cs:129-132)
- **GAL-061** {M5} [P] If `Difficulty < NORMAL`, the start system's `Special` becomes `LotteryWinner (17)`, but only when it is still `< 0`. That matters when GAL-058 fell back to an unchecked system. (source: Src/Traveler.c:2591-2593)

## 14. Persistent special ships (`CreateShips`)

| Ship | Crew[0] | Equipment (in `AddEquipment` order) |
|---|---|---|
| Dragonfly | Dragonfly (35) | Military Laser, Pulse Laser, 3× Lightning Shield, Auto-Repair System, Targeting System |
| Scarab | Scarab (36) | 2× Military Laser |
| Scorpion | Scorpion (54) | 2× Military Laser, 2× Reflective Shield, Auto-Repair System, Targeting System |
| SpaceMonster | SpaceMonster (37) | 3× Military Laser |

- **GAL-062** {M1} [M][W] `CreateShips` equips the persistent Dragonfly, Scarab, Scorpion and SpaceMonster exactly as in the table, with crew members from GAL-053, and draws nothing. Each hull starts full from its spec (SpaceMonster 500, Dragonfly 10, Scarab 400, Scorpion 300). (source: Game.cs:42-45, 743-768; Ship.cs:755-765; Consts.cs:250-267)
- **GAL-063** {M5} [P] Palm keeps no persistent special ships at construction. It initialises only `MonsterHull = 500` (the Space Monster's hull strength). The Palm special opponents are built at encounter time (ENC.md). (source: Src/Traveler.c:1646)

## 15. Visited flag and pressure changes on arrival

- **GAL-064** {M1} [M][W] `visited` becomes true for the start system in `InitializeCommander`, and for the destination on every arrival, before any arrival processing. It never reverts. (source: Game.cs:2711, 309-312)
- **GAL-065** {M5} [P] `Visited` becomes true when the System Information screen is shown for the current system. The port sets it at the start and on every arrival, which is equivalent because docking always shows that screen. (source: Src/SystemInfoEvent.c:377)
- **GAL-066** {M3} [M][W] On arrival, systems `i = 0…127` are processed in order. Each draws `r(100) < 15`, and on success flips its pressure: `None` becomes `r(1, 8)`, and anything else becomes `None`. That system's quantity update follows immediately (interleaved, ECO). (source: Game.cs:505-512)
- **GAL-067** {M5} [P] On arrival, `ShuffleStatus` runs over all 120 systems **first**. A system with `Status > 0` draws `r(100) < 15` and on success becomes `0`. A system with `Status 0` draws `r(100) < 15` and on success becomes `1 + r(7)`. Then the whole `ChangeQuantities` pass runs (ECO). (source: Src/Traveler.c:715-729, 2434-2441)

## 16. Determinism, fixtures and invariants

- **GAL-068** {M1} [M][W][P] The same ruleset, difficulty and seed always produce the identical galaxy, mercenaries, start system and `RNGState`, byte for byte in canonical JSON. `pmsim dump-galaxy --ruleset <r> --seed <s>` prints that canonical JSON. (source: PRD §6.2, §9 M1)
- **GAL-069** {M1} [W] The harness fixtures `Fixtures/harness/galaxy-<seed>.json` cover seeds 0, 1, 42 and 12345 on Normal difficulty, plus seed 42 on Beginner. Each holds every system's x, y, size, tech, government, pressure, resource, trade quantities, event and shipyard, along with `Wormholes`, every mercenary's system and skills, the start system and its initial prices. All of it matches the Windows 2.01 engine exactly. (source: PRD §8.4)
- **GAL-070** {M1} [M][W] Over 1000 seeds (0…999), every galaxy satisfies all of the following: x stays in 1…153 and y in 1…109; every pair has `distance >= 7`; the 6 wormhole systems are distinct, their coordinates lie inside the six GAL-018 boxes, and the ring is a permutation; every system is reachable from every other through hops of `distance <= 12` plus wormhole links (so with Gnat range 14); GAL-038 holds, and the 4 distant events lie at `distance >= 70` from their base; shipyards sit only on Hi-Tech systems; the start system obeys GAL-057; mercenary counts per system are ≤ 3 (≤ 2 random at Kravat). (source: Game.cs:2175-2959, 2685-2712)
- **GAL-071** {M5} [P] Over 1000 seeds, every Palm galaxy satisfies all of the following: X stays in 1…148 and Y in 1…108; every pair has `sqrDistance >= 50`; the wormhole systems lie in the GAL-024 boxes; every system is reachable through hops of `sqrDistance < 169` plus wormholes; every placed government/TL pair is valid; each random event index 7…29 appears exactly `Occurrence` times, except Scarab when `!FreeWormhole` and AlienArtifact under GAL-044; distant events lie at `realDistance >= 70`; at most one of mercenaries 1…29 and 31 per system, and none at Kravat; the start system has no special event (before the Lottery) and 3 neighbours within `sqrDistance <= 196`. The test also reports how many seeds needed the unchecked fallback (expected 0). (source: Src/Traveler.c:StartNewGame)
- **GAL-072** {M5} [M] Over 1000 seeds, the Modern galaxies satisfy GAL-070, and in addition exactly 5 distinct shipyard systems exist (MOD-013). (source: PRD §4.3 MOD-013)
