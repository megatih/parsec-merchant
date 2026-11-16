# Space Trader — History, Original Documentation, Ports, Fan Reception, UI Patterns & Licensing

> Web research 2026-11-16. URLs were live at research time.

---

I've researched all six areas. One finding affects your plan before anything else: **the game's artwork is not covered by the GPL.** Spronck's ReadMe says "the in-game pictures, except for the program's icon, are copyrighted by Alexander Lawrence." The Windows 2.01 release also bundles ship images by William W. Connors. Plan on drawing new art from the start.

Reddit (blocked to my crawler), GameFAQs and TV Tropes (403) couldn't be fetched, so fan sentiment comes from Hacker News, blogs, SourceForge reviews and Spronck's own 2001 design paper. Where web sources ran out I read the code directly: the Palm C source, the C# repo and the LLM-assisted web port.

---

# 1. The original Palm OS game

## History and versions
- **Author:** Pieter Spronck, then a researcher at Maastricht and later at Tilburg University. Wikipedia's "2002" date is wrong; the release date is September 2000.
- **Inspirations:** Elite, David J. Webb's SolarWars, and Matt Lee's DopeWars. Some DopeWars code is used, per the Merchant.c header.
- **Release history (from the News page, https://spronck.net/spacetrader/STNews.html):**

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2000-09-25 | |
| 1.0.1 | 2000-10-01 | |
| 1.0.2 | 2000-10-05 | Fixed warping beyond range, which overflowed fuel and froze the Short Range Chart |
| 1.1 | 2000-11-01 | iSilo documentation added |
| 1.1.1 | 2000-12-24 | Fixed a bug that overwrote specials, including the moon offer |
| 1.1.1 source | 2001-01-09 | First source release |
| 1.1.2 | 2002-01-14 | Memory fixes for Palm OS 4, code segmentation |
| 1.2.0 | 2002-10-13 | |
| 1.2.1 | 2005-04-16 | See the bug list in section 2 |
| 1.2.2 | 2005-12-08 | See the bug list in section 2 |

- **Contributors:** The FAQ says 1.1.2 and 1.2.0 were "largely created by others." Source headers credit Sam Anderson and Samuel Goldstein for additional coding.
- **Scale:** Spronck estimated 100,000 to 1,000,000 players within a year.
- **Sequel:** "Picoverse" was announced in 2002 and never shipped.
- **Source:** https://www.spronck.net/spacetrader/SpaceTraderSource.zip (1.2.2). GitHub mirror: https://github.com/videogamepreservation/spacetrader. It is C written for CodeWarrior 8.3. The tables you'll want are in `Src/Global.c` and `Src/spacetrader.h`.
- **Playable in a browser:** archive.org runs it in the CloudpilotEmu Palm emulator at https://archive.org/details/palm3_SpaceTrader

## Official site pages (https://www.spronck.net/spacetrader/STNoFrames.html)
- **Documentation:** https://spronck.net/spacetrader/SpaceTrader.html. It covers trading, ships, travel, skills, encounters, goods, equipment, the 10 ship types, the 8 tech levels and the 17 political systems.
- **FAQ:** https://spronck.net/spacetrader/STFAQ.html
- **Tips:** https://spronck.net/spacetrader/STTips.html
- **Strategies:** https://spronck.net/spacetrader/STStrategies.html
- **Downloads:** https://spronck.net/spacetrader/STDownload.html
- **Screenshots:** https://www.spronck.net/spacetrader/STScreenshots.html. It shows the Start, SystemInformation, BuyCargo, SellCargo, ShipYard, BuyShip, BuyEquipment, PersonnelRoster, Bank, CommanderStatus, Warp, AveragePriceList, News, Special, HighScores, NewCommander, Galactic, Short Range Chart and Pirate/Police encounter screens.
- **Other ports Spronck links:** https://spronck.net/spacetrader/STLinks.html
- **Spronck's design paper "Palm Game Design" (2001), a must-read:** https://www.spronck.net/pubs/PalmGameDesign.pdf. His own criticisms of the game:
  - **Too many screens.** Docked, there are about 10 main screens and 10 sub-screens. A redesign "would probably make do with about four main screens."
  - **Buying and selling should be merged** into one "Cargo Trading" screen.
  - **Add a "nerve centre" screen** for the basic functions.
  - **Don't hide core functions in menus.** On the Palm, Bank and Equipment were menu-only, and players forgot they existed.
  - **Quests are the most appreciated part.** He wanted "far more and different quests, with multiple solutions."
  - **Add savegames.** His suggested fix for save-scumming in combat is to disable high-score ranking after a restore.
  - Graphics matter only up to a point.

## In-game help text (the per-screen manual)
The original help lives in a binary Palm resource, which is hard to read. Russell Wolf's Android port carries it over as about 209 `help_*` strings, lightly updated for touch. The easiest copy to read is `src/data.json` (key `text.help_*`) in https://github.com/lunchwine/space-trader-classic.

What the help says about each screen:

- **System Information:** Shows the docked system. It has a News button (paid newspaper), a "Special" button when a quest is available here, and "Mercenary For Hire."
- **Buy Cargo:** Columns are quantity available, item, and price. Tap the quantity to choose an amount, or "Max" to buy as much as stock, bays and cash allow. The "Reserve Money" option holds back enough for insurance and mercenaries.
- **Sell Cargo:** A **bold** item name means you'd sell at a profit. "All" sells everything; "Dump" jettisons goods for a fee. Criminals lose 10% to an intermediary.
- **Ship Yard:** Fuel, hull repair, escape pod, and new ships. Your current ship, equipment and cargo count as a trade-in. You get the new ship empty, and cargo this system won't buy is lost.
- **Buy and Sell Equipment:** Three slot categories: weapons, shields, gadgets. Slot counts depend on the ship.
- **Personnel Roster:** Two crew slots plus one mercenary for hire. Fired mercenaries go home.
- **Bank:**
  - Loans: at least 1,000 credits if your record is clean, at most 500 if not.
  - Interest is 10% per day, taken from cash when you warp; if you lack cash it is added to the debt.
  - While in debt you can't buy ships or equipment.
  - Insurance costs 0.25% of ship value per day, minus 1% per claim-free day, up to 90% off. It requires an escape pod.
- **Short Range Chart (Warp):** Visited systems are blue, unvisited green, wormholes red. A circle shows fuel range, and an arrow points to the tracked system.
- **Target System info:** Distance and "Current Costs" (mercenaries, wormhole tax, interest, insurance), plus Warp and Average Price List buttons. Arrows scroll through the systems in range.
- **Average Price List:** Bold means the price there beats your buy price here. Toggles between absolute prices and differences. Temporary events are excluded, and known special resources are included.
- **Galactic Chart:** Tap a system for info. Tap twice to track it (marked X). Find button. On the Palm, the "J" button uses the Portable Singularity.
- **Commander Status:** Skills shown with effective values in brackets (including mercenaries and gadgets), reputation, police record, net worth. Buttons lead to Ship, Quests and Special Cargo.
- **Encounter:** Your ship on the left, the opponent on the right. Red fill shows hull damage and a halo shows shields. An icon marks pirate (skull), police (badge) or trader (coin).
  - Actions are Attack, Flee, Surrender, Bribe, Submit, Plunder, Ignore, Trade, depending on the opponent.
  - "Continuous attack/flight" repeats the action every second until you tap "Int."
- **Options:** Auto-ignore safe encounters (set separately for police, pirates and traders), auto-fuel, auto-repair, reserve money, "Always go from Chart to Info," always pay for the newspaper, hardware buttons, show range to tracked system.
- **Shortcuts:** B, S, Y, E, Q, P, K, I, C, G, W go to Buy Cargo, Sell Cargo, Shipyard, Buy Equipment, Sell Equipment, Personnel, Bank, System Info, Commander, Galactic Chart and Short Range Chart. These are user-configurable, and there are four quick buttons in the upper right.

## Core data (from the Palm source)
- **Galaxy:** 120 systems on a 150×110 grid, 6 wormholes, maximum range 20 parsecs. The moon costs 500,000 credits; you need a net worth of 400,000 to be offered one.
- **Police record thresholds:** Psychopath −70, Villain −30, Criminal −10, Dubious −5, Clean 0, Lawful 5, Trusted 10, Helper 25, Hero 75.
- **Reputation thresholds (kills):** Harmless 0, Mostly harmless 10, Poor 20, Average 40, Above average 80, Competent 150, Dangerous 300, Deadly 600, Elite 1500.
- **Trade goods:**

| Good | Base price | Notes |
|---|---|---|
| Water | 30 | Price spikes in drought |
| Furs | 250 | Cold |
| Food | 100 | Crop failure |
| Ore | 350 | War |
| Games | 250 | Boredom |
| Firearms | 1,250 | **Illegal**; war |
| Medicine | 650 | Plague |
| Machines | 900 | Labor shortage |
| Narcotics | 3,500 | **Illegal**; boredom |
| Robots | 5,000 | Labor shortage |

Each good also has a minimum tech level to produce, a minimum to use, a tech level where it's cheapest, a per-tech-level price change, variance, a cheap resource and an expensive resource.

- **Ships:**

| Ship | Bays | Weapon/shield/gadget slots | Crew | Range (parsecs) | Price |
|---|---|---|---|---|---|
| Flea | 10 | 0/0/0 | 1 | 20 | 2,000 |
| Gnat | 15 | 1/0/1 | 1 | 14 | 10,000 |
| Firefly | 20 | 1/1/1 | 1 | 17 | 25,000 |
| Mosquito | 15 | 2/1/1 | 1 | 13 | 30,000 |
| Bumblebee | 25 | 1/2/2 | 2 | 15 | 60,000 |
| Beetle | 50 | 0/1/1 | 3 | 14 | 80,000 |
| Hornet | 20 | 3/2/1 | 2 | 16 | 100,000 |
| Grasshopper | 30 | 2/2/3 | 3 | 15 | 150,000 |
| Termite | 60 | 1/3/2 | 3 | 13 | 225,000 |
| Wasp | 35 | 3/2/2 | 3 | 14 | 300,000 |

  Special ships you can't buy: Space Monster, Dragonfly, Mantis (alien), Scarab, Bottle.
- **Weapons:** Pulse laser 2,000, Beam 12,500, Military 35,000, Morgan's laser (quest only).
- **Shields:** Energy 5,000, Reflective 20,000, Lightning (quest only).
- **Gadgets:** 5 extra bays, auto-repair, navigating system, targeting system, cloaking device, fuel compactor (quest only).

## Every quest and special event (Palm 1.2.2)
Titles come from the `SpecialEvent[]` table in Global.c; descriptions from the Strings.cs event text in the C# port.

- **Alien Artifact → Artifact Delivery:** Deliver to Professor Berger at a random hi-tech system for 20,000 credits. Aliens (Mantis ships) harass the carrier, and you can surrender the artifact to them.
- **Dragonfly chain:** Baratas → Melina → Regulas → Zalkon. Destroy the stolen prototype, whose hull is weak but shields are very strong. Reward is a Lightning Shield installed.
- **Space Monster at Acamar:** 15,000 credits.
- **Scarab:** A stolen ship with an organic hull that only pulse lasers can damage; it hides at a wormhole exit. Reward is a hull upgrade, which is not transferable to a new ship.
- **Japori Disease:** Carry 10 bays of antidote. Reward is a skill boost from a fast-learning machine.
- **Ambassador Jarek:** Carry him to Devidia. Reward is a haggling computer (bigger discounts).
- **Jonathan Wild:** Smuggle him to Kravat past the police. Reward is a cleared police record plus a free mercenary, Zeethibal. Patched in 1.2.2 (see section 2).
- **Morgan's Reactor:** Deliver to Nix. It takes 15 bays and drains your shields and hull while aboard. Reward is Morgan's laser.
- **Gemulon alien invasion:** Warn Gemulon within 6 days. Reward is the fuel compactor (+3 parsecs). If you fail, Gemulon drops to pre-agricultural.
- **Dr. Fehler's experiment at Daled:** Stop it within 10 days. Reward is a Portable Singularity (one free jump anywhere). If it fails, space-time is disrupted and warps can misfire.
- **Merchant Prince:** Sells you a tribble for 1,000. Tribbles multiply, eat food and narcotics, and become irradiated if they meet the reactor.
- **Tribble Buyer:** Pays half a credit per tribble. Three systems have one.
- **Paid one-off offers:**
  - Skill Increase: 3,000 credits for a random skill.
  - Erase Record: a hacker clears your police record for 5,000.
  - Cargo For Sale: 3 sealed canisters for 1,000, contents random.
  - Lottery Winner: +1,000 credits.
- **Moon For Sale → Retirement at Utopia:** Ends the game. Four systems sell moons.
- **Very rare encounters:** Marie Celeste (a derelict to loot, then police may ask questions); Captains Ahab, Conrad and Huie (famous captains who trade a skill for equipment); old and good skill tonics in a bottle.
- **Newspaper:** Headlines hint at events, quest locations and heroes.

## Community guides and FAQs
- **Kasey Chang, "Unofficial Strategy Guide and FAQ" (2003):** https://gamefaqs.gamespot.com/palmos/917550-space-trader/faqs/23321 (returned 403 to me; try the Wayback Machine).
- **Strategy page, essential tips:**
  - Put 8 to 10 points into Pilot.
  - Avoid systems with "many" pirates.
  - Take the 1,000-credit loan and sell the starting pulse laser to reach 3,500 credits.
  - Buy extra bays early.
  - Fill every slot with cheap weapons first: 2 pulse lasers beat 1 beam laser.
  - Buy in large systems, sell in small ones.
  - Ride events: labor shortage pays over 3,000 per robot canister.
  - Narcotics go hi-tech to low-tech, and theocracies pay most.
  - Pirates scale with your net worth.
  - Carry about 500,000 credits until a moon is offered.
- **Other references:** Wikipedia https://en.wikipedia.org/wiki/Space_Trader_(Palm_OS), LibreGameWiki https://libregamewiki.org/Space_Trader, TV Tropes https://tvtropes.org/pmwiki/pmwiki.php/VideoGame/SpaceTrader. I found no dedicated fan wiki.

---

# 2. Palm 1.2.2 vs. Windows 2.0, and known bugs

**Windows port history** (from the changelog in https://github.com/SpaceTraderGame/SpaceTrader-Windows, also at https://sourceforge.net/projects/spacetraderwin/):

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2003-12-08 | First release |
| 1.1 | 2003-12-23 | Gnat-upgrade crash; Jarek/Wild not leaving; special-cargo error; firing a mercenary with 2 crew quarters crashed |
| 1.2 | 2004-02-09 | Skill total above 20 possible; Alien Artifact could never finish |
| 2.0 | 2005-03-23 | The version you're basing on (details below) |
| 2.01 | 2008-08-14 | The version on GitHub and SourceForge. The About box says "Additional coding by David Pierron" |

**What Windows 2.0 adds or changes compared with Palm 1.2.2:**
- **Save and Load:** Real savegame files with a forward-compatible format. Palm had no saves, only "Switch Game" with two slots. Loading, starting a new game and quitting ask for confirmation.
- **Layout:** One main window shows the cargo, system, target, chart and shipyard panels together, close to Spronck's "nerve centre" idea. Separate forms remain for Equipment, Personnel, Bank, Commander, Ship, Quests, Find, Costs, Jettison, Plunder and High Scores.
- **Custom ship designer** in some shipyards (the "Custom" ship type). The newspaper reports nearby shipyards.
- **Bounty on the player**, scaled to police record.
- **Two new quests:**
  - **Stolen Sculpture** to Endor. Reward is Hidden Cargo Bays, a new gadget.
  - **Kidnapped Princess Ziyal of Galvon:** Centauri → Inthara → Qonos. You must disable the Scorpion with disruptors. Reward is a Quantum Disruptor.
- **New weapons** that disable instead of destroy: Photon Disruptor and Quantum Disruptor.
- **More content:** 15 more mercenaries, 8 more systems, up to 3 mercenaries per system.
- **Other changes:** Redesigned Equipment and Personnel screens, tooltips, a colored Special button, an option to show the newspaper on arrival, more equipment images, and opponent generation fixed (they had been weaker than intended).
- **Cheats:** Typing "Cheetah" in Find, then codes such as "Monster.com," which opens a hidden quest/monster browser (`Form_Monster`).

**Known bugs**

*Palm:*
- 1.0.1: fuel overflow froze the Short Range Chart.
- 1.1: specials, including the moon, could be overwritten. A similar rare bug in 1.2.0 was still under investigation per the FAQ.
- Fixed in 1.2.1:
  - the Special button crashed on newer OS versions;
  - negative cargo bays were possible;
  - donating equipment to famous captains corrupted your other weapons and shields;
  - a lockup could occur from an incompatible install.
- Fixed in 1.2.2:
  - the Scarab could go missing;
  - newspapers announced only some heroes;
  - delivering Wild reset your police record to clean even if you weren't a criminal.
- Through 1.1.2: the scoring help text was wrong.
- The author of the JavaScript port found "several longstanding bugs" during his rewrite but doesn't list them. He also notes integer-versus-float math matters, so keep Swift on integer arithmetic where the original does.

*Windows 2.0:* SourceForge tracker https://sourceforge.net/p/spacetraderwin/bugs/. Already fixed in 2.01:
- 100 bays truncated to 10 during plunder;
- hull hardening;
- the police choice was negated;
- a money error;
- a shipyard designer error;
- a pirate cargo transfer crash.

Still open:
- a "Police Bug" (2010);
- cancelling a design changes the bay count on your current ship (2009);
- bad ship pricing gives a money exploit (2006).

*Java and C# derivatives:* LeonisX's changelog lists extra fixes, useful as a checklist of places the code is fragile: shield initial charge, stealable cargo, "free" ships in the shipyard, Max/All buttons, negative slots, `hasCrew`. https://github.com/LeonisX/space-trader/blob/master/docs/changelog.md

---

# 3. Other ports and remakes

| Port | Platform / language | Author | Notes |
|---|---|---|---|
| Pocket PC | eVC++ | Jon Welch, 2004–05 | Made with Spronck's permission. https://spacetrader.g7jjf.com |
| Space Trader for Windows | C# WinForms | Jay French, David Pierron | Your base |
| Space Trader for Java 1.12 | Java Swing | Aviv Eyal, 2008–10 | Port of the C# version; adds Mac and Linux support. https://sourceforge.net/projects/spacetraderjava/ |
| LeonisX space-trader | Java 8 | Stavila Leonid | Deep refactor. Quest engine with one class per quest, localization (Russian), Gradle, English and Russian manual (`docs/manual_en.md`). https://github.com/LeonisX/space-trader |
| beyond-space-trader | Java terminal UI (Lanterna) | | GPL-3.0-or-later. https://github.com/antoniovazquezaraujo/beyond-space-trader |
| jSpaceTrader | Java/SWT | | GPLv2. https://sourceforge.net/projects/jspacetrader/ |
| Android, Russell Wolf ("brucelet") | Java | | Faithful port with an optional Palm color scheme, pinch-zoom galaxy, long-press tracking, volume-button scrolling. GPL; F-Droid and Play. Bitbucket source https://bitbucket.org/brucelet/space-trader/ (404 when I checked) |
| Android, Benjamin Schieder ("blind-coder") | Java | | Android port of a Linux native port; ads removed. https://codeberg.org/blindcoder/SpaceTrader |
| Dark Nova | iOS (2009), iPad HD (2010), Android | Dead Jim Studios | Endorsed by Spronck; "greatly expanded," with graphics, soundtrack, autosave |
| Space Trader 2018 | **iOS, Swift/UIKit** | Marc Auger | **The only existing Swift port I found** (details below) |
| memalign web port | Vanilla JS PWA | memalign | Translated from an existing implementation with ChatGPT, every line audited. Deterministic RNG with replay logs, unit and integration tests, coverage. https://memalign.github.io/m/spacetrader/index.html, write-up https://memalign.github.io/p/spacetrader.html, HN https://news.ycombinator.com/item?id=42501201 |
| Space Trader Classic | HTML/JS PWA + Android wrapper | lunchwine | Mostly LLM-written port of brucelet v1.3.5. Adds save import/export and automatic light/dark mode. Has tests. https://github.com/lunchwine/space-trader-classic, https://spacetrader.lunchwine.com |
| alexbeatnik SpaceTrader | React/TS, Electron and Capacitor | | "Ambitious" remake. Interactive star map, in-system locations, mining, orbital stations, procedural per-planet news, economy types. https://github.com/alexbeatnik/SpaceTrader |
| rusttrader | Rust | michaelrogers | Partial; its roadmap names "37 special events." https://github.com/michaelrogers/rusttrader |
| pmprog SpaceTrader | C# | | "Some UI changes." https://github.com/pmprog/SpaceTrader |
| Python | Python | | https://github.com/RPINerd/Space-Trader, https://github.com/gruiick/pySpaceTrader |
| Other | | | OpenBSD package `games/spacetrader`; crummy/spacetrader (Kotlin web backend); many Georgia Tech CS2340 student "Space Trader" projects, which are mostly noise |

**Space Trader 2018 in detail:**
- **Store:** https://apps.apple.com/app/id1106932709, priced $1.99. It currently returns 404 and may have been pulled.
- **Source:** https://github.com/sosaysthecaptain/spacetrader, created 2016, last build commit 2018.
- **Structure:** Storyboard UIKit with a tab bar for System, Buy, Sell, Shipyard and Warp. Saves use Core Data, with multiple save slots. It has an 8-bit pixel font, a Noun Project icon set, a separate Newspaper view controller, a ship designer, and a Mercenaries view.
- **Credits:** UI design by Steph Avalos-Bock. Bills itself as "historically accurate."
- **License:** States **GPLv3** while being on the App Store.

**Swift, iOS and macOS search results:** I found no native macOS port and no SwiftUI port. The only Swift hits on GitHub besides Marc Auger's are student CS2340 projects and clients for spacetraders.io, which is a different game.

**User reception of ports:**
- **Dark Nova:**
  - GamesRadar called it "basically Elite, boiled down to its very essence" and satisfying in 60-second chunks.
  - Blog review (3.5 stars) liked the fixed endpoint, route planning and quick loading. It disliked repetitive combat and travel, rare quests, slow pile-ups of popup combat messages, unexplained red-fill damage, light help, and low risk with noticeable grind once established. https://meandmydroid.blogspot.com/2011/05/dark-nova.html
  - An iMore reader review (iPad HD, 3 stars) found it overpriced and not improved enough over the original.
- **Windows port on SourceForge:** 4.8/5 from 5 reviews. One reviewer: "Would have been 5 stars with a better interface and a little more control of the battles."
- **HN on memalign's port:** Popup dialogs are tiresome; people want auto-dismiss or Enter to close, plus keyboard shortcuts for desktop. Another HN thread said the Android port gives new players too little guidance.
- **The Next Web (2012):** Liked that the Windows port spreads the UI across the bigger PC screen.

---

# 4. Fan reception

**Why it's fun:**
- Trading with simple rules that run deep: tech level × government × size × resources × temporary events. Mostly deterministic, so planning pays off.
- Constant risk-versus-reward choices: fight, flee, surrender or bribe; smuggling; criminal versus hero paths.
- A clear goal (the moon) with a score multiplier per difficulty.
- Short sessions that still mean something.
- Quests as small stories with unique rewards. Spronck calls these the most appreciated part.

**Common complaints:**
- Too many screens and too much tapping.
- Repetitive encounters and popup spam.
- Mid-game grind once the player is strong.
- Quests too rare and single-solution.
- No saves on the Palm.
- Combat with little control (all-or-nothing auto-resolve).
- Hidden mechanics; players don't read the help.
- RNG deaths on Hard and Impossible.

**Features people asked for, or that ports added:**
- Keyboard shortcuts and auto-dismiss.
- Save import/export and multiple saves.
- Light and dark mode.
- Galaxy zoom.
- Better newcomer guidance.
- More quests.

Inferred from the complaints rather than asked for directly:
- A trade-route planner with profit per bay and per jump.
- Price memory and history for visited systems.
- Multi-jump route plotting with fuel and cost.
- A combat log.
- Achievements.
- An undo or "ironman" toggle, following Spronck's idea of disabling high scores after a restore.
- Statistics.

---

# 5. UI patterns worth borrowing from comparable games
- **Endless Sky** (open source, a spiritual successor to EV; manual at https://github.com/endless-sky/endless-sky/wiki/PlayersManual):
  - The map colors systems by the selected commodity's price. Clicking a system shows profit or loss per commodity.
  - Map modes for ports, missions, outfitter and shipyard; F to find; Shift-click to compare two ships or outfits.
  - Trade quantity modifiers: Shift ×5, Cmd ×20, both ×100, Option ×500. Buy All (U) and Sell All (E) keys.
  - Message log on "/".
  - All of this maps directly onto Mac keyboard conventions.
- **Escape Velocity / EV Nova** (classic Mac): Spaceport hub buttons (Commodity Exchange, Shipyard, Outfitter, Bar, Mission Computer) on one screen, which is a natural fit for a SwiftUI sidebar. Fixed commodity prices with a "high/med/low" label. Ship info panels with a picture plus a stats table.
- **Elite Dangerous** plus the Inara and EDDB tools: A commodity market showing galactic average and profit columns, filtered by "supply/demand." A trade-route finder ranked by profit per ton and per jump. Galaxy map filters by trade data.
- **Star Traders: Frontiers:** Letter-grade price ratings (A+ … F) per good per port. Legality and permit shown inline in the exchange.
- **Taipan and Drug Wars:** A single dense screen showing cash, debt, bank, hold and a price list, with one-keystroke buy and sell. The original genre's speed is what to aim for.
- **Applying these to a Mac version:**
  - A single docked "Station" window with a sidebar and keyboard shortcuts, following Spronck's "four screens" advice.
  - A unified Trade table with columns Here / Target / Δ / Profit per bay, bold profit coloring, and modifier-key quantities.
  - A galaxy map with heat-map overlays (by price, pirates, police, visited), multi-jump plotting, and a fuel range ring.
  - Inspector panels comparing ships side by side.
  - An encounter screen with a scrolling combat log and auto-repeat.
  - Notification-style event toasts instead of modal alerts.

---

# 6. Licensing and the name

**License:**
- Both Palm and C# headers say **GPL "version 2, or (at your option) any later version."** The License.txt file is GPLv2. A Swift port derived from the C# code must be GPL (v2+ or v3) and ship its complete source.
- **Spronck's ReadMe asks:** "please consult me before you" port; credit the original in your program; don't release a "new version of Space Trader" under that name without him. These are requests, not license terms, but they are worth honoring.
- **Art:** All in-game pictures except the icon are copyrighted by Alexander Lawrence. Windows 2.01's custom ship images are by William W. Connors. Commission new art.

**Copyright holders, if you want an App Store exception:**
- Pieter Spronck, Sam Anderson, Samuel Goldstein, Matt Lee (DopeWars code), Jay French, David Pierron.
- Plus the artists, if you reuse any art.

**GPL and the App Store:**
- **The conflict:** The FSF argues Apple's usage rules and DRM are "further restrictions" forbidden by GPL §6 (v2) and §10 (v3).
- **The VLC precedent:** VLC was pulled in January 2011 after a VLC developer's complaint (https://www.engadget.com/2011-01-09-the-gpl-the-app-store-and-you.html). GNU Go was pulled too. VLC returned in 2013 only after relicensing to LGPL/MPL with consent from its contributors.
- **The risk is complaint-driven:** Apple removes apps when a copyright holder objects. Marc Auger's GPLv3 Space Trader 2018 and Dark Nova both shipped without trouble.
- **Your options:**
  - **(a) Simplest:** Distribute outside the Mac App Store with Developer ID and notarization (GitHub, itch.io or your own site). Fully compliant, and you can still charge money.
  - **(b) App Store:** Get written permission from the copyright holders, in the style of Signal's GPLv3 App Store exception: https://scancode-licensedb.aboutcode.org/signal-gpl-3.0-exception.LICENSE
  - **(c) Clean-room reimplementation:** Write it from the rules and numbers only. Game mechanics aren't copyrightable, but the code, quest and help text, names and art are. This is hard to do credibly when you are porting from the C#.

**The name:**
- Storefronts carry the notice "Space Trader is a trademark of HermitWorks Entertainment Corporation." HermitWorks released a commercial *Space Trader* for Windows and **Mac OS X** in 2007 and *Space Trader: Merchant Marine* on Steam in 2008 (https://en.wikipedia.org/wiki/Space_Trader).
- I found no live USPTO registration, but I didn't verify against TSDR, so treat this as unverified.
- "SpaceTraders" (spacetraders.io) is also an active, unrelated game.
- **Recommendation:** Pick a distinct product name, as Dark Nova did, and use "based on Space Trader by Pieter Spronck" in descriptions and credits.
