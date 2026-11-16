# C# Space Trader 2.01 — UI, Flows, Alerts & Asset Catalog

> Extracted 2026-11-16. Describes the WinForms UI we are REPLACING (not copying). Original images are © Alexander Lawrence / William W. Connors and must NOT be used in Parsec Merchant.


> **QA note:** `Enums.cs` defines **188** `AlertType` cases. The alert catalog below groups them; docs/specs/ALR.md (M0) must map all 188 by name.

---

I've cataloged all 27 forms, the full alert set, every file in `images/` and all nine ImageLists. I decoded the ImageList headers in the .resx files to get image counts, and read the chart and continuous icon pixels to get their colors. I couldn't view the BMPs themselves without writing temporary files, so the descriptions of ships, logos and other larger art come from file names and how the code uses them. Paths below are relative to `/Users/megatih/Downloads/SpaceTraderSource201/`.

---

# 1. Main window: `Form_SpaceTrader.cs` (class `SpaceTrader`)

**Window.** The window is fixed-size, 768×505, with no maximize and no resizing. Title is "Space Trader". Its position is saved to the registry under `HKCU\Software\FrenchFryz\SpaceTrader` (values X and Y) on close and restored on load (3228-3249). On load it shows the splash alert (`AlertType.AppStart`). If a path is passed on the command line, that save file is loaded at startup (427-436).

**Layout.** Everything is a GroupBox at an absolute position (2363, 2632, 1303, 2553, 923, 907, 990):

| Region | Position / size | Contents |
|---|---|---|
| System Info | (4,2) 240×206 | Name, Size, Tech Level, Government, Resource, Police, Pirates, then "This system is currently *<pressure>*." Buttons: **News**, **Special** (only when the system has a visible special event; tooltip is the event title), **Mercenary For Hire** (only if mercenaries are present; tooltip "Name available for hire." or "N mercenaries available for hire."). Code at 3141-3183. |
| Dock | (4,212) 240×90 | "You have fuel to fly N parsecs." / "A full tank costs X cr." (or "Your tank is full.") with a **Fuel** button. "Your hull strength is at N%." / "Full repairs will cost X" (or "No repairs are needed.") with a **Repair** button. Buttons are hidden when not needed (3053-3081). |
| Cargo | (252,2) 512×300 | 10 commodity rows: Water, Furs, Food, Ore, Games, Firearms, Medicine, Machines, Narcotics, Robots. Columns: **Sell** (a button labeled with how many you hold, an **All**/**Dump** button, and the price or "no trade"), **Buy** (a button labeled with how many the market has, a **Max** button, and the price or "not sold"), and **Target System** (Price, +/-, %, or dashes when the target is out of range). Bold text marks a profitable sale and profitable buys at the target (2951-3021). Four 1-px lines separate row groups. |
| Shipyard | (4,306) 168×168 | "There are ships for sale." / "No ships for sale." The ship button is labeled **View Ship Info** but opens the buy-ship list. **Design** appears only if the system has a custom shipyard. "There is equipment for sale." with **Buy/Sell Equipment**. Escape pod text (installed / none for sale / "You need 2,000 cr." / "You can buy an escape pod for 2,000 cr.") with **Buy Pod** (3083-3120). |
| Galactic Chart | (180,306) 176×168 | 160×116 white picture box. Below it: "Wormhole to *X*" label (only when a wormhole is targeted), **Jump** (only if you have the Portable Singularity), and **Find**. |
| Short-Range Chart | (364,306) 176×168 | 160×145 white picture box. |
| Target System | (548,306) 216×168 | Name, Size, Tech, Government, Resource ("Unknown" if never visited), Police, Pirates, and Distance. Distance is a bare number with no unit. **<** / **>** cycle through in-range systems. A large 44×44 **Warp** button shows when the target is in range. Otherwise you see "This system is out of range." and a **Track** button (hidden if that system is already tracked). Code at 3185-3222. |
| Status bar | bottom, 24 px | "Cash: X cr." (click opens Bank), "Bays: n/m", "Current Costs: X cr." (click opens the Cost Specification dialog), and a stretch panel that reads "No Game Loaded." when there's no game (3122-3139, 4018-4027). |

**Menus and shortcuts** (682-841):
- **Game**: New... (no shortcut), Load... (Ctrl+L), Save (Ctrl+S), Save As... (Ctrl+A, which is non-standard), separator, Retire, separator, Exit.
- **View**: Commander Status (Ctrl+C), Ship (Ctrl+H), Personnel (Ctrl+P), Quests (Ctrl+Q), Bank (Ctrl+B), separator, High Scores, separator, Options.
- **Help**: About Space Trader.
- Items that need a game are disabled until one exists (`SetInGameControlsEnabled`, 2914). Menu labels have & mnemonics.
- There is no toolbar, no KeyPreview and no other keyboard handlers. No buttons have mnemonics.

**Galactic chart rendering** (`picGalacticChart_Paint`, 3829-3871):
- Scale is 1 px per parsec (galaxy is 154×110) with a 3 px offset.
- The fuel range is a black circle of radius = fuel, centered on the current system.
- Each system is drawn with a 7×7 icon from `ilChartImages`:
  - unvisited: `chartsnv`, a 3×3 green dot
  - visited: `chartsv`, a blue dot
  - the warp target uses the "s" variant (`chartsnvs` / `chartsvs`), which adds black crosshair ticks.
- The tracked system gets a black X drawn across its cell.
- A wormhole is drawn as `chartsw` (yellow-red dot) 4 px to the right of its system. When a wormhole is targeted, a black line runs from it to the destination system.
- With no game, the chart is plain white.

**Short-range chart** (3923-4016):
- Scale is `delta = height/(MaxRange*2)` = 3 px per parsec, centered on the current system, which is marked with a tiny black X. Only systems within about (w/2-10)/3 horizontally and (h/2-10)/3 vertically are drawn.
- Range circle radius = fuel × 3.
- Systems are drawn in two passes: first the names (7 pt black text above each system), then the icons, so names can overlap but icons always stay visible.
  - unvisited: `chartlnv`, a green shaded sphere
  - visited: `chartlv`, a blue sphere
  - wormhole: `chartlw`, concentric yellow-orange-red, 9 px right of the system
- The warp target gets a black + crosshair (±6 px). The tracked system gets a black X (±5 px). A targeted wormhole gets its own crosshair.
- If a tracked system exists, a **crimson triangle** points from the center toward it (25 px long). If the "Show range to tracked system" option is on, the text "N parsecs to Name." appears at the bottom-left.

**Image naming.** The constants are named backwards relative to the files. `IMG_G_*` (indices 0-2) are the **large** "l" icons and are used in the *short-range* chart. `IMG_S_*` (indices 3-7) are the **small** "s" icons and are used in the *galactic* chart (273-280). The ImageList holds 8 images, so `chartsws.bmp` (selected small wormhole) is not used.

**Chart clicks** (3787-3827, 3873-3921):
- Left-click within ±2 px (galactic) or ±3 px (short-range) of a system sets `SelectedSystemId`, which also sets the warp target and clears the wormhole flag.
- Clicking a wormhole icon selects its system and sets `TargetWormhole = true`. The warp target then becomes the next system in the wormhole cycle.
- There is no hover, tooltip, double-click, zoom or right-click.

**How warp is started:**
- **Warp** button → autosave to `autosave_departure.sav` if enabled → `game.Warp(false)` → travel loop with any encounters → `Arrival()` → autosave to `autosave_arrival.sav`. A `GameEndException` routes to `GameEnd()` (3663-3680).
- **Jump** (Portable Singularity) → checks a target is selected and isn't the current system → asks "Use Singularity?" → `game.Warp(true)` (3543-3568).
- `Game.Warp` (Game.cs:3153) checks, in order: debt too large, can't pay mercenaries, can't pay insurance, can't pay wormhole tax, then whether Wild needs a beam laser. `Game.Travel` (3105) runs 20 "clicks"; each click may open `FormEncounter` modally. An uneventful trip shows "Uneventful Trip". `Arrival` (309) runs reactor, tribble and debt checks, auto fuel and repair, an easter egg check, prices and news, and shows the newspaper automatically if that option is on.

**Tracking and Find:**
- **Track** sets the tracked system to the selected one (3657). There is no "stop tracking" control; tracking only clears on arrival if "Stop tracking on arrival" is on.
- **Find** opens `FormFind` (a text box plus a "Track this system" checkbox; both values persist across opens). Matching is a case-insensitive *substring* match, first hit wins (Game.cs:4302).
- Find also doubles as the **cheat console**:
  - typing `Cheetah` shows "Cheater!" and enables cheats
  - then the commands are Bazaar, Cover, DeLorean, Diamond, Energize, Events, Fame, Go, Ice, Indemnity, IOU, Iron, Juice, Knack, L'Engle, LifeBoat, Monster.com, PlanB, Posse, RapSheet, Rarity, Scratch, Skin, Status, Swag, Test, Tool, Varmints, Yellow (3281-3529).
  - `PlanB` is the **only way to turn on autosave**, `Monster.com` opens `FormMonster`, and `Test` opens `FormTest`.

**Game logic living inside the main form:**
- cargo buy/sell dispatch (2780-2793)
- fuel and repair purchase math (3531-3541, 3603-3613)
- escape pod purchase, 2000 cr hard-coded (3587-3595)
- special-event yes/no and price check (3615-3655)
- game end and high-score insertion (2771-2841)
- all cheat mutations
- chart geometry and hit-testing

---

# 2. Every form

All forms are modal (`ShowDialog`), fixed-border, centered on their parent, and hidden from the taskbar. Most "view" dialogs have only a **hidden "X" button placed at (-32,-32)**, so the only ways to close them are Esc or the title-bar close box.

| Form | Opened from | Displays | Actions / validation | Game calls |
|---|---|---|---|---|
| **FormCargoBuy** (`Form_CargoBuy.cs`) | `Game.CargoBuy` (Game.cs:608), via the Buy-quantity button, the trader encounter (Trade), or Plunder | Title "Buy Water" / "Steal Water". Statement varies: system ("At X each, you can buy up to N."), trader ("The trader wants to sell…", "The trader has N units for sale.", "You can afford to buy N units."), plunder ("Your victim has N of these goods.") | Numeric field 1…max; **Ok**, **All** (sets max and accepts), **None** (cancel). No close box. | `Amount`. Before opening, `Game.CargoBuy` checks: debt too large, nothing available, no empty bays, can't afford. |
| **FormCargoSell** | `Game.CargoSell` (700): Sell-quantity, trader encounter, Dump, Jettison | Title "Sell/Dump/Jettison X". "You paid about X per unit[, and can sell N]", "Your profit/loss per unit is X", or the dump cost "It costs X per unit for disposal." | Ok / All / None | Checks: none to sell, nobody interested, littering warning before the first jettison |
| **FormBuyFuel** | Dock → Fuel | "How much do you want to spend on fuel?" Credits spinner preset to max | Ok / Max / Nothing | The main form converts credits to fuel units |
| **FormBuyRepairs** | Dock → Repair | "How much do you want to spend on repairs?" | Ok / Max / Nothing. **Max has no click handler** (it just accepts, and the value already defaults to max). | Same pattern as fuel |
| **FormViewBank** | View → Bank, Cash panel | Loan: Current Debt, Maximum Loan. Insurance: Ship Value, No-Claim Discount % with "(max)" at 90%, Costs "X daily" | **Get Loan**, **Pay Back Loan** (only if in debt), **Buy/Stop Insurance** (stop needs a confirm; buying needs an escape pod). The max-loan formula is in the form itself (62-65). | Opens FormGetLoan / FormPayBackLoan, mutates the commander directly |
| **FormGetLoan** / **FormPayBackLoan** | Bank | "You can borrow up to X credits." / "You have a debt of X." | Ok / Max / Nothing | — |
| **FormViewCommander** | Ctrl+C | Name, Difficulty, Time (days). **Skills** box: Pilot, Fighter, Trader, Engineer shown as "base (with crew/gear)". **Finances**: Cash, Debt, Net Worth. **Notoriety**: Police Record, Reputation, Kills, plus "Bounty offered" (record ≤ Crook) or "Angry kingpins" (record ≥ Trusted) | Read-only | — |
| **FormViewShip** "Current Ship" | Ctrl+H | Type. Hull "Hardened" (after the Scarab quest). Equipment counted by type. Escape Pod. Unfilled weapon/shield/gadget slots. **Special Cargo** box: tribbles, antidote, artifact, haggling computer, reactor plus enriched-fuel bays, sculpture, portable singularity. Built as text inside two labels. | Read-only, **no ship picture** | — |
| **FormViewPersonnel** | Ctrl+P, System Info → Mercenary For Hire | **Current Crew** list (with "Vacancy" rows, or "No quarters available"). **Mercenaries For Hire** list (or "No one for hire"). **Mercenary Information**: name, "X cr. daily", P/F/T/E | **Hire/Fire** button or double-click; fire needs a confirm, hire checks quarters. Quest passengers (Wild, Jarek, the Princess) can't be fired, except Zeethibal. | `Ship.Hire` / `Ship.Fire` |
| **FormViewQuests** | Ctrl+Q | A LinkLabel listing open quests separated by blank lines, or "There are no open quests." **Every system name is a hyperlink**; clicking it selects that system on the charts and closes the dialog | — | The quest text logic lives inside this form (131-266) |
| **FormViewHighScores** | View → High Scores | Ranks 1-3: Name, score "NN.N%", "Retired in N days, worth X credits on normal level." or "Empty" | None. There is no clear button, even though `ClearHighScores()` and the `GameClearHighScores` alert exist. | `Functions.GetHighScores` reads `data/HighScores.bin` |
| **FormShipList** "Ship List" | Shipyard → View Ship Info | 10 rows (Flea…Wasp), each with **Info**, **Buy**, name and net price: "-X cr." trade-in difference, "got one", or "not sold" when tech is too low. **Ship Information** box: picture, Name, Size, Cargo Bays, Range, Hull Strength, Weapon/Shield/Gadget slots, Crew Quarters | Buy triggers the long `Commander.TradeShip` chain: debt, cost, quarters, reactor, per-item transfer prompts, confirm (Commander.cs:120-215). Shows the tribble trade-in warning once. | `Commander.TradeShip` |
| **Form_Shipyard** "Ship Design at X Shipyards" | Shipyard → Design (only at the 5 shipyard systems) | 80×80 shipyard logo. "Welcome to … Our best engineer, Luke, is at your service." Size Specialty, Special Skill and its description, crowding-penalty warning. **Info**: Template dropdown (current ship, separator, "Size (Minimum)", separator, "Ship (Default)", separator, user .sst files; a "\<modified\>" entry appears after edits), **Load**/**Save**, Ship Name, Size dropdown "Medium (Max N Units)", Image picker (< > through 10 stock ships plus Custom), **Set Custom...**. **Space Allocation**: spinners for Weapon/Shield/Gadget slots, Crew Quarters, Range (fuel), Cargo Bays, Hull Strength; Units Used; % of Max, colored yellow at the first penalty, orange at the second, red over 100. **Costs**: Ship Cost, Design Fee, Crowding Penalty, Less Trade-In, Total | **Construct Ship** (default button; grayed text when invalid; hovering shows red-arrow hints "You must enter a Ship Name." / "Your % of Max must be ≤100%"). **Cancel Design**. Save writes `custom/templates/*.sst`. Set Custom loads `name.bmp`, `named.bmp`, `names.bmp` and `namesd.bmp`. | `Shipyard.CalculateDependantVariables`, `Commander.TradeShip`; on success shows "Thank you!" |
| **FormEquipment** "Buy/Sell Equipment" | Shipyard → Buy/Sell Equipment | **Equipment For Sale**: three lists (Weapons, Shields, Gadgets) or "None for sale". **Current Inventory**: three lists including " - FREE SLOT - " rows, or "No slots". **Equipment Information**: 64×52 icon, Name, Type, long description, Buy Price, Sell Price, Power, Charge | **Buy** / **Sell** buttons or double-click. Buy checks: already own one (gadgets), in debt, can't afford, no slot, then confirm. Sell confirms; extra cargo bays can't be sold while full. | `Ship.AddEquipment` / `RemoveEquipment` |
| **FormNewCommander** | Game → New (after the abandon-game confirm) | Name, Difficulty (Beginner/Easy/Normal/Hard/Impossible; default Normal), Skill Points: Pilot, Fighter, Trader, Engineer, each 1-10, starting at 1, with "16 points remaining." | **Ok** is enabled only when 0 points remain and a name is entered. Each skill's maximum is clamped to its value plus the points left. Cancel is Esc only. | `new Game(name, diff, p, f, t, e)` |
| **FormOptions** | View → Options | See section 6 | Ok, Cancel, **Save As Defaults**, **Load from Defaults** | `GameOptions` |
| **FormPlunder** "Plunder Cargo" | Encounter → Plunder | 10 commodity rows with a button showing the victim's quantity plus **All**; "Bays: n/m" | Clicking the quantity opens FormCargoBuy(Plunder). **Jettison** opens FormJettison. **Done** closes. | `Game.CargoPlunder` |
| **FormJettison** "Jettison Cargo" | Plunder → Jettison, or scooping a canister with no room | Your quantity buttons plus All; Bays | Done | `Game.CargoJettison` (littering warning) |
| **FormFind** "Find System" | Galactic chart → Find | "Which system are you looking for?", text box, "Track this system" | Ok / Cancel | Main form parses the text |
| **FormCosts** "Cost Specification" | Click the Costs status panel | Mercenaries, Insurance, Interest, Wormhole Tax, Total | Esc only | — |
| **FormMonster** "Monster.com Job Listing" | Cheat only | Three column tables built from multiline labels. **Mercenaries**: ID, Name, P, F, T, E, System (linked; "Member of Crew (X)"). **Quests**: System (linked), Description. **Shipyards**: System (linked), Description. Column headers are links that sort. Mercenary systems are split across two labels because of a 32-link limit. | Clicking a system selects it and closes | — |
| **FormAbout** | Help → About | 160×160 splash picture (`picLogo.Image`, an embedded 160×160 8-bit BMP that is presumably the splash art); "Space Trader for Windows 2.01"; credits (Jay French; Palm version © 2000-2002 Pieter Spronck; pictures © 2000 Alexander Lawrence; GPL; spacetraderwin.sourceforge.net) | Esc only | — |
| **FormTest** | Cheat only | Dropdown of every AlertType plus three value fields, and a special-event tester | Test buttons | — |
| **FormAlert** | Everywhere | See section 4 | — | — |

---

# 3. Encounter screen: `Form_Encounter.cs`

**Window.** 234×271 "Encounter" dialog with no close box (the close box is enabled only with the `Yellow` cheat). It opens once per encounter from inside `Game.Travel` (Game.cs:3129).

**What it shows:**
- "You:" and "Opponent:" ship pictures, each in a 70×58 box with a 64×52 sprite drawn at offset (2,2), plus the ship name, "Hull at N%" and "Shields at N%" (or "No Shields").
- A 12×12 encounter-type icon at the top right (`ilEncounterType`): 0 alien, 1 pirate, 2 police, 3 special, 4 trader (Game.cs:3537). The Mantis and the space monster use alien. Dragonfly, Scarab and Scorpion use pirate. Bottles, famous captains and the Marie Celeste use special.
- `lblEncounter`: first "At N clicks from X, you encounter a pirate Gnat.", then on later rounds "You hit the X." / "The X missed you." etc.
- `lblAction`: "Your opponent attacks.", "It ignores you." / "It doesn't notice you." (when cloaked), "The X is fleeing.", "The X hails that they wish to surrender…", police inspection or surrender text, the trader offer, etc. (Strings.cs:74-132, Game.cs:3404-3720).
- It's a two-line status that gets overwritten each round, **not a scrolling log**.

**Buttons by encounter type** (`UpdateButtons`, 1066-1166). All buttons share one row and their positions are shuffled in code.

| Encounter type | Buttons |
|---|---|
| Bottle (good/old) | Drink, Ignore |
| Captain Ahab / Conrad / Huie | Attack, Ignore, Meet |
| Dragonfly, Famous Captain, Scorpion, Space Monster, Trader in *attack* mode | Attack, Flee |
| Any *ignore* or *flee* state, plus disabled police or captain | Attack, Ignore |
| Marie Celeste | Board, Ignore |
| Marie Celeste customs police | Attack, Flee, Yield, Bribe |
| Pirate attack, Police attack, Police wants surrender, Scarab attack | Attack, Flee, Surrender |
| Pirate or Trader disabled or surrendered | Attack, Plunder |
| Police inspection | Attack, Flee, Submit, Bribe |
| Trader buy / sell | Attack, Ignore, Trade |
| Continuous mode active | adds **Int.** (interrupt) |

**Continuous attack/flee.** When the option is on, each round restarts a 1-second timer that repeats the last action. The 9×9 indicator next to **Int.** alternates between `continuous0` and `continuous1` (blue concentric rings that swap shading) each round, which reads as a pulse. Pressing any action button, or Int., stops it.

**Tribbles.** There's a fixed scattered grid of 36 12×12 picture boxes. The number shown is `min(36, sqrt(tribbles / ceil(100000/37²)))`, placed at random positions with a random one of `trib0`-`trib7`. Clicking one shows the "Squeek!" alert (1187-1210, 1316).

**Damage and shield visualization** (`Functions.PaintShipImage`, Functions.cs:226-250). Each ship has four sprites: normal, damaged (`d`), shielded (`s`) and shielded+damaged (`sd`). The sprite is split into vertical strips inside the ship's real pixel bounds (`Consts.ShipImageOffsets` X and width per type, Consts.cs:222):
- **Hull damage** grows from the **left edge rightward**. The left fraction (1 − hull%) uses the damaged sprite.
- **Shields** cover from the **right edge leftward**. The right fraction equal to shield% (plus 2 px) uses the shielded sprite.
- Where the two regions overlap, the `sd` sprite is used.
- The result works like a health bar and a shield bar built into the art. Ships with no shield slots never show the s/sd variants.

**After the encounter,** the result (Continue, Normal, Killed, EscapePod, Arrested) drives `Arrested()`, `EscapeWithPod()` or game over, each of which shows a cascade of alerts.

---

# 4. Alert catalog: `Form_Alert.cs:269-835`

**How alerts render.**
- Text alerts: auto-sized, word-wrapped at 80 characters, 1-2 flat buttons, `^1`-style placeholders.
- Image alerts: a 160×160 background picture with no text and a hidden button; click, Enter or Esc dismisses them. The splash is borderless and auto-closes after 4 seconds.

Unless a button pair is shown in brackets, an alert has a single **Ok** button.

**System / file / misc**
- Alert: generic "^1"/"^2" with Ok. This is also how the **newspaper** is shown (masthead as title, headlines as body).
- AppStart: splash image.
- RegistryError: "Error..."
- FileErrorOpen / FileErrorSave: "Error: An error occurred while trying to open/save ^1. ^2"
- Cheater: "Cheater!"
- Egg: "Egg"
- OptionsNoGame: "No Game Active"

**Game lifecycle**
- GameAbandonConfirm: "Are You Sure?" [Yes/No]
- NewGameConfirm: [Yes/No]*
- NewGameMoreSkillPoints*
- GameRetire: "Retire" [Yes/No]
- GameClearHighScores: [Yes/No]*
- GameEndKilled: image `destroyed`, titled "You Are Dead"
- GameEndRetired: image `retire`
- GameEndBoughtMoon: image `moon`
- GameEndBoughtMoonGirl: image `moongirl`*
- GameEndScore: "You achieved a score of ^1.^2%."
- GameEndHighScoreAchieved: "Congratulations!"
- GameEndHighScoreMissed: "Sorry"
- GameEndHighScoreCheat: "Naughy, Naughty!" (typo in the original)

**Arrival / travel**
- ArrivalBuyNewspaper: "Buy Newspaper?" [Buy Newspaper/Cancel]
- ArrivalIFNewspaper: "Can't Afford it!"
- ArrivalIFFuel: "No Full Tanks"
- ArrivalIFRepairs: "No Full Repairs"
- ArrivalIFFuelRepairs: "Not Enough Money"
- TravelUneventfulTrip
- TravelArrival* (commented out in Game.cs:3201)
- SpecialTimespaceFabricRip

**Leaving / debt**
- LeavingIFMercenaries: "Pay Mercenaries"
- LeavingIFInsurance
- LeavingIFWormholeTax
- DebtTooLargeGrounded: "Large Debt"
- DebtTooLargeTrade
- DebtTooLargeLoan
- DebtWarning
- DebtReminder: "Loan Notification"
- DebtNoBuy: "You Have A Debt"
- DebtNone

**Charts**
- ChartJump: "Use Singularity?" [Use Singularity/Don't use it]
- ChartJumpCurrent: "Cannot Jump"
- ChartJumpNoSystemSelected. Its text says to "track" a system, but the code actually checks the *selected* system.
- ChartTrackSystem*
- ChartWormholeUnreachable*

**Cargo**
- CargoIF
- CargoNoEmptyBays
- CargoNoneAvailable
- CargoNoneToSell: "None To Sell/Dump/…"
- CargoNotInterested
- CargoNotSold*

**Encounter combat and decisions**
- EncounterAttackPolice: [Yes/No]
- EncounterAttackTrader: [Yes/No]
- EncounterAttackCaptain: "Really Attack?" [Really Attack/OK, I Won't]
- EncounterAttackNoWeapons
- EncounterAttackNoLasers
- EncounterAttackNoDisruptors
- EncounterYouWin
- EncounterYouLose
- EncounterBothDestroyed
- EncounterDisabledOpponent (gets the long Princess-rescue story appended)
- EncounterEscaped
- EncounterEscapedHit
- EncounterOpponentEscaped
- EncounterEscapePodActivated
- EncounterSurrenderRefused: "To The Death!"
- EncounterAliensSurrender: [Yes/No]

**Police**
- EncounterPoliceBribe: [Offer Bribe/Forget It]
- EncounterPoliceBribeCant
- EncounterPoliceBribeLowCash
- EncounterPoliceSubmit: "You Have Illegal Goods" [Yes, let them/No]
- EncounterPoliceNothingIllegal: [Yes, I still want to/OK, I won't]
- EncounterPoliceSurrender: [Yes/No]
- EncounterPoliceFine: "Caught"
- EncounterPoliceNothingFound
- EncounterArrested

**Pirates**
- EncounterLooting
- EncounterPiratesFindNoCargo
- EncounterPiratesBounty: "Bounty"
- EncounterPiratesExamineReactor
- EncounterPiratesTakeSculpture
- EncounterPiratesSurrenderPrincess
- PreciousHidden

**Special encounters**
- EncounterMarieCeleste: [Yes, Take Cargo/No]
- EncounterMarieCelesteNoBribe
- EncounterPostMarie*
- EncounterPostMarieFlee: "Criminal Act!" [Yes, I still want to/OK, I won't]
- EncounterDrinkContents: [Yes, Drink It/No]
- EncounterTonicConsumedGood
- EncounterTonicConsumedStrange
- MeetCaptainAhab: [Yes, Trade Shield/No]
- MeetCaptainConrad: [Yes, Trade Laser/No]
- MeetCaptainHuie: [Yes, Trade Laser/No]
- EncounterTradeCompleted

**Scoop / dump**
- EncounterScoop: "Scoop Canister" [Pick It Up/Let It Go]
- EncounterScoopNoRoom: [Make Room/Let it go]
- EncounterScoopNoScoop
- EncounterDumpWarning: "Space Littering" [Yes/No]
- EncounterDumpAll*

**Equipment**
- EquipmentBuy: "Buy ^1" [Yes/No]
- EquipmentSell: [Yes/No]
- EquipmentAlreadyOwn
- EquipmentIF
- EquipmentNotEnoughSlots
- EquipmentExtraBaysInUse
- EquipmentEscapePod: [Yes/No]
- EquipmentFuelCompactor
- EquipmentHiddenCompartments
- EquipmentLightningShield
- EquipmentMorgansLaser
- EquipmentQuantumDisruptor

**Ship purchase / design**
- ShipBuyConfirm: [Yes/No]
- ShipBuyIF
- ShipBuyIFTransfer
- ShipBuyNoSlots
- ShipBuyNoTransfer
- ShipBuyTransfer: "Transfer ^1" [Do it!/No thanks]
- ShipBuyCrewQuarters
- ShipBuyPassengerQuarters
- ShipBuyReactor: "Shipyard Engineer"
- ShipBuyNotAvailable*
- ShipDesignIF*
- ShipDesignThanks
- ShipHullUpgraded
- FleaBuilt
- TribblesTradeIn

**Crew**
- CrewFireMercenary: [Yes/No]
- CrewNoQuarters
- SpecialNoQuarters
- SpecialPassengerOnBoard
- Six "Ship's Comm." chatter alerts: SpecialPassengerConcerned and SpecialPassengerImpatient, each for Jarek, Princess and Wild

**Insurance / jail**
- InsuranceNoEscapePod
- InsurancePayoff
- InsuranceStop: [Yes/No]
- JailConvicted
- JailFleaReceived*
- JailHiddenCargoBaysRemoved
- JailIllegalGoodsImpounded
- JailInsuranceLost
- JailMercenariesLeave
- JailShipSold

**Quests**
- AntidoteOnBoard
- AntidoteDestroyed
- AntidoteTaken
- ArtifactLost
- ArtifactRelinquished
- JarekTakenHome
- PrincessTakenHome
- ReactorOnBoard
- ReactorConfiscated
- ReactorDestroyed
- ReactorMeltdown
- ReactorWarningFuel
- ReactorWarningFuelGone
- ReactorWarningTemp
- SculptureConfiscated
- SculptureSaved
- SpecialCleanRecord
- SpecialExperimentPerformed
- SpecialIF
- SpecialMoonBought
- SpecialNotEnoughBays*
- SpecialSealedCanisters
- SpecialSkillIncrease
- SpecialTrainingCompleted
- WildArrested
- WildChatsPirates
- WildGoesPirates
- WildLeavesShip
- WildSculpture
- WildWontBoardLaser
- WildWontBoardReactor
- WildWontStayAboardLaser: [Say Goodbye to Wild/Cancel]
- WildWontStayAboardReactor: [Say Goodbye to Wild/Cancel]

**Tribbles**
- TribblesOwn
- TribblesSqueek
- TribblesAteFood
- TribblesMostDied
- TribblesHalfDied
- TribblesAllDied
- TribblesKilled
- TribblesGone
- TribblesRemoved
- TribblesInspector

**Special events (dynamic).** These don't use AlertType. The main form builds a FormAlert directly from `SpecialEvent.Title` and `.String`, with [Ok] or [Yes/No] (3615-3655). There are 46 titles (Strings.cs:773-823) and 46 long narrative texts (Strings.cs:721-771).

\* = defined but never raised. I confirmed this with a script over all .cs files. Unused: CargoNotSold, ChartTrackSystem, ChartWormholeUnreachable, EncounterDumpAll, EncounterPostMarie, GameClearHighScores, GameEndBoughtMoonGirl, JailFleaReceived, NewGameConfirm, NewGameMoreSkillPoints, ShipBuyNotAvailable, ShipDesignIF, SpecialNotEnoughBays, plus TravelArrival, which is commented out.

**Text categories in `Strings.cs`:**
- single-string UI constants: Bank, Cargo, Dock, Encounter, Equipment, File, HighScore, Mercenary, News, Personnel, Quest (31 quest lines), ShipBuy/ShipName/Shipyard, SpecialCargo
- name arrays: activity levels, cargo operations, 55 crew names, difficulty levels, equipment descriptions, gadget, shield and weapon names, game completion types
- news: event headlines, a 17×4 headline table by government, 17×3 newspaper mastheads, hero and psychopath headlines, pressure headlines
- other arrays: police record, government, reputation and ship names; shipyard engineers, names, skills and skill descriptions; sizes; special event strings and titles; special resources; 128 system names; system pressures; tech levels; trade items; very rare encounter names
- a large commented-out block

The file is Windows-1252 encoded and contains a © character.

---

# 5. Asset inventory: `images/`

ImageList counts come from the decoded `MSFt`/IL headers in the .resx files. All of these lists are embedded in the .resx files; none load from disk at runtime except custom ship images.

| ImageList (form) | Count × size | Files (order) |
|---|---|---|
| `ilChartImages` (main) | 8 × 7×7, white = transparent | chartlnv, chartlv, chartlw, chartsnv, chartsnvs, chartsv, chartsvs, chartsw |
| `ilShipImages` (main) | 68 × 64×52 (17 ship types × 4: normal, d, s, sd) | See ship table below |
| `ilEquipmentImages` (main) | 16 × 64×52 | w_pulse, w_beam, w_military, w_morgan, w_photon, w_quantum, s_energy, s_reflective, s_lightning, g_bays, g_repsys, g_navsys, g_targsys, g_cloak, g_fuel, g_hbays (index logic in Equipment.cs:85-128) |
| `ilDirectionImages` (main) | 4 × 13×13 | arrup, arrdown, arrleft, arrright. Only **down** is used, for the Shipyard hint labels. |
| `ilImages` (FormAlert) | 5 × 160×160 | destroyed (0, Killed), retire (1), moon (2), moongirl (3), splash (4) |
| `ilEncounterType` (Encounter) | 5 × 12×12 | alien, pirate, police, special, trader |
| `ilTribbles` (Encounter) | 8 × 12×12 | trib0-trib7 |
| `ilContinuous` (Encounter) | 2 × 9×9 | continuous0, continuous1 |
| `ilShipyardLogos` (Shipyard) | 5 × 80×80, 24-bit | sy-corellian, sy-incom, sy-kuat, sy-sienar, sy-sorosuub (ShipyardId order) |

**Ship sprites** (all 64×52, 8-bit):

| Index | ShipType | Files |
|---|---|---|
| 0 | Flea | ship0, ship0d (no s/sd; no shield slots) |
| 1 | Gnat | ship1, ship1d (no s/sd) |
| 2-9 | Firefly, Mosquito, Bumblebee, Beetle, Hornet, Grasshopper, Termite, Wasp | shipN, shipNd, shipNs, shipNsd |
| 10 | Space Monster | sm, smd |
| 11 | Dragonfly | df, dfd, dfs, dfsd |
| 12 | Mantis (alien) | mantis, mantisd, mantiss, mantissd |
| 13 | Scarab | scarab, scarabd, scarabs, scarabsd |
| 14 | Bottle (tonic) | bottle, bottled |
| 15 | Custom | Most likely ship10, ship10d, ship10s, ship10sd (the default custom image, replaceable via Set Custom...). This is an inference. |
| 16 | Scorpion (Princess quest) | scorp, scorpd, scorps, scorpsd |

**Chart icon colors** (read from the pixels and palettes):
- `chartlnv`: green shaded sphere (#33CC00 → #336600)
- `chartlv`: blue sphere (#33CCFF → #000099)
- `chartlw`: radial yellow → orange → red, dark red center (#CCCC00/#CC6600/#CC0000/#660000)
- small `chartsnv`, `chartsv`, `chartsw`: 3×3 versions of the same
- the `*s` small variants add black crosshair ticks
- `continuous0` and `continuous1`: cyan and blue concentric rings with inverted shading

**Other files:**
- `splash.bmp` (160×160): splash screen, and probably the About picture.
- `splash.jpg` (160×160): planets plus a ship with "SPACE TRADER" text; this is a source copy, not used.
- `logo.gif` (22×21): a green and blue ringed-planet icon; not used.
- `App.ico`: the window and app icon.
- `find.bmp` (16×16, 4-bit): not used; the Find button is text only.
- `dummy_ship.bmp` and `blank.bmp` (64×52): probably placeholders; not referenced in code.
- `chartsws.bmp`: not in the ImageList.
- `shipyard.psp` (Paint Shop Pro source), `pspbrwse.jbf` (thumbnail cache), `CVS/` and `.cvsignore`: development leftovers.

---

# 6. Options and new commander

**Options dialog** (362×271; `Form_Options.cs`, defaults in `GameOptions.cs:34-49`):

| Option | Default |
|---|---|
| Get full fuel tanks on arrival | off |
| Get full hull repairs on arrival | off |
| Always pay for newspaper | off |
| Show newspaper on arrival (only enabled when "Always pay" is checked) | off |
| Remind about loans | on |
| Show range to tracked system | on |
| Stop tracking on arrival | on |
| Reserve money for warp costs | off |
| Cargo bays to leave empty when buying goods in-system (0-99) | 0 |
| "Always ignore when it is safe:" Pirates | off |
| "Always ignore when it is safe:" Police | off |
| "Always ignore when it is safe:" Traders | on |
| Ignore dealing traders (only enabled when Traders is checked) | off |
| Continuous attack and flight | off |
| Continue attacking fleeing ship (only enabled when Continuous is checked) | off |
| Attempt to disable opponents when possible | off |

- Buttons: **Ok**, **Cancel**, **Save As Defaults** (writes `data/DefaultSettings.bin`), **Load from Defaults**.
- Options are stored per save game.
- With no game open, the dialog first shows the "No Game Active" alert, then opens with **Ok disabled**, so you can only save or load defaults.
- **Autosave has no UI option** at all; it only turns on with the `PlanB` cheat.

**New commander flow:**
1. Game → New.
2. If the game has unsaved days, confirm "Are You Sure?".
3. FormNewCommander: name, difficulty (default Normal), four skills that start at 1 with 16 points to spend (20 total, max 10 each). Ok is enabled only when both requirements are met.
4. `new Game(...)`, menus enabled, `UpdateAll`, and the newspaper shown automatically if that option is on (3687-3705).

There is no portrait, no ship choice and no seed or galaxy preview.

---

# 7. Help/About, save/load, autosave, high scores

- **Help** is only the About box. There is no in-app help or tutorial.
- **Save/Load:**
  - Standard Open and Save dialogs filtered to "Saved-Game Files (\*.sav)", with a default name of `SpaceTrader.sav`, starting in `./save`. All folders are relative to the current working directory: `custom/`, `custom/images/`, `custom/templates/`, `data/`, `save/`, created at startup (2864-2883).
  - Saves are .NET `BinaryFormatter` hashtables tagged with `_version` "2.00".
  - Load errors show "Error" with "not a Space Trader file / wrong version" or "future version".
  - Save (Ctrl+S) reuses the last path, or falls back to Save As.
  - "Dirty" tracking is just `Commander.Days == SaveGameDays`. Abandon prompts appear on New, Load and window close.
- **Autosave** writes `autosave_departure.sav` before a warp or jump and `autosave_arrival.sav` after, into the working directory rather than `save/`.
- **High scores:** top 3 only, stored in `data/HighScores.bin`.
  - At game end the alerts appear in this order: the end-type image, "Score: NN.N%", then "made the list" / "not enough" / "cheat".
  - Cheating disqualifies you.
  - The viewer has no clear or reset button.

---

# 8. UX pain points to fix on macOS

1. **Too many modal alerts in a row.** Arrival, jail and escape pod each fire 3-10 sequential OK boxes, and buying a ship can raise about 8 prompts. Replace them with a single arrival or event summary sheet, a ship-purchase review sheet with transfer checkboxes, and non-blocking toasts or a log.
2. **No persistent log.** Encounter results, news and travel events vanish when dismissed. A captain's log or timeline is the obvious addition.
3. **The encounter window is tiny** (234×271) and overwrites its two status lines each round. Add a round-by-round combat log, real hull and shield bars next to the sprite cropping, larger art and keyboard shortcuts for actions.
4. **Charts are 160 px, white, black-pen, with no zoom, hover, tooltips or legend.** Wormhole hit targets are ±2 px. A redesign wants a zoomable, scalable galaxy map with hover cards (system info and price deltas), a visible route and range, a legend for visited, unvisited, wormhole and tracked, and Retina vector symbols instead of 7×7 bitmaps.
5. **Tracking is confusing.** There's Select vs Track vs Find-with-checkbox, no Untrack button, Track only appears for out-of-range systems, and the Jump alert text says "track" when it means select.
6. **Find is a single substring match with no suggestions** (and it's also the cheat console). Use a searchable combo with autocomplete; ⌘F could open it.
7. **Cargo grid trade-offs.** Buttons labeled with quantities, an All/Dump label that changes, and bold text as the only profit signal are hard to read. Use colored profit indicators, steppers or sliders inline instead of a separate quantity dialog per trade, and drag or quick actions.
8. **Hidden close buttons.** View dialogs close only with Esc or the title bar. Commander, Ship, Personnel, Quests, Bank and High Scores could become inspector panels, tabs or a sidebar that updates live.
9. **Data shown as text-in-labels with no units.** Ship equipment and special cargo are text blobs, target Distance has no unit, and ViewShip has no ship picture.
10. **The "View Ship Info" button actually buys ships.** Separate browsing from purchasing.
11. **Shipyard designer:** construct-button validity is shown only by gray text and hover hints, and custom images require four specially named BMPs. Use a validation summary and image import with automatic generation of damaged and shielded variants.
12. **Odd shortcuts:** Ctrl+A for Save As and Ctrl+C for Commander clash with standard Select All and Copy. Adopt ⌘S, ⇧⌘S, ⌘O and ⌘N, and map the views to ⌘1…⌘5.
13. **Options coupling** is surprising: "Show newspaper on arrival" requires "Always pay". Autosave has no option, and saves land in odd folders. Use Settings (⌘,), the standard document or save model, iCloud and Application Support folders.
14. **The newspaper is shown as a generic alert.** It deserves a styled newspaper view with the masthead.
15. **The main window doesn't scale:** fixed 768×505, absolute positioning, Microsoft Sans Serif 8.25 pt. SwiftUI adaptive layout with Dynamic Type and Dark Mode would fix this (the charts are hard-coded white).
16. **Dead content you can either revive or drop:** the Princess retirement ending (`moongirl` image and alert never fire), a clear-high-scores action, wormhole-unreachable and track-system prompts, and unused art (`logo.gif`, `find.bmp`, `chartsws`, `dummy_ship`, `blank`).
17. **Game logic scattered in forms** should move into the model during the port: fuel and repair purchase, escape pod price, the bank's max-loan formula (FormViewBank:62), quest-text derivation (FormViewQuests), cheats, special-event pricing, and chart hit-testing.
