# 10 · Research for the interface revamp

> Input for `docs/PRD-UI-Revamp.md`. Gathered on 2026-11-19.
>
> **How to read the marks.** **[V]** = read on the cited page during this research. **[S]** = taken from a search-result snippet only; the page itself was not read. **[R]** = recollection, not verified; do not rely on it. Game mechanics in the PRD are taken from this repository's sources and specs (`docs/specs/`, `docs/research/01–08`, the C# source and the Palm source), never from the web.

## 1. The original game

### 1.1 Sources
| Source | URL | Status |
|---|---|---|
| Space Trader Centre (Pieter Spronck) | https://www.spronck.net/spacetrader/index.html | [V] |
| Official documentation | https://www.spronck.net/spacetrader/SpaceTrader.html ; mirror https://stuff.mit.edu/afs/sipb/user/golem/tmp/pilot/SpaceTrader/SpaceTrader.html | [V] |
| Strategies | https://www.spronck.net/spacetrader/STStrategies.html | [V] |
| Tips | https://spronck.net/spacetrader/STTips.html | [V] |
| Downloads and release notes 1.2.1 / 1.2.2 | https://spronck.net/spacetrader/STDownload.html | [V] |
| Ports and information | https://www.spronck.net/spacetrader/STInformation.html | [V] |
| Help text and strings (from the Android 1.3.5 lineage) | https://raw.githubusercontent.com/lunchwine/space-trader-classic/main/src/data.json | [V] |
| Spronck, *Palm Game Design* (2001) | https://www.spronck.net/pubs/PalmGameDesign.pdf | [V] |
| Wikipedia | https://en.wikipedia.org/wiki/Space_Trader_(Palm_OS) | [V] |

### 1.2 Trade loop and prices, as told to players
- Ten goods with documented price ranges, from Water (30–54 cr.) to Robots (3,950–4,400 cr.). [V, manual]
- "The price of natural goods increases with the tech level, while the price of industrial goods decreases." Eight tech levels. [V]
- Seventeen governments, each with its own police strength, crime level and wanted good. [V]
- Resources and events (drought, war, boredom, cold, crop failure, lack of workers) move prices; prices "fluctuate somewhat"; trader skill lowers prices by up to 10%. [V]
- "In small systems prices are higher than in large systems." Criminals lose 10% to an intermediary. [V, Strategies]
- The Average Price List comes with "no guarantee that you will actually get the price shown." [V]

### 1.3 Average Price List
- Shows "the average prices you get for goods in the target system"; goods in **bold** sell there for more than they cost here; a button switches between **Absolute Prices** and **Price Differences**; `<` and `>` cycle through nearby systems. [V, help text]
- After version 1.0, tapping a good on the list opened a buy dialog with a buy-maximum button, which "greatly increased the user-friendliness … and decreased the number of necessary screen-switches." [V, Spronck paper p. 4]
- Design consequence: the PRD puts the average price and the difference in every cargo row, keeps the bold rule and the disclaimer, and makes one click on a chart system the equivalent of `<` / `>`.

### 1.4 Charts and warp
- Short Range Chart: tapping a reachable system shows its information and a Warp button. [V]
- Galactic Chart: tapping a system twice tracks it; tracking adds an arrow on the Short Range Chart. [V]
- Wormholes: fly to the system, then tap the wormhole; no fuel, but a tax that is lower for smaller ships. [V]
- Warp costs: mercenaries' pay, insurance, interest, wormhole tax. Interest 10% per day; insurance 0.25% of trade-in value per day with a no-claim reduction; unpaid mercenaries leave. [V]
- Option "Reserve money for warp costs" keeps buy-maximum from spending that money. [V, strings]

### 1.5 Encounters
- Traders usually ignore you (trade, attack, flee; plunder one that surrenders). Pirates usually attack (fight, flee, surrender). Police may inspect (submit, bribe, flee, attack, surrender). [V, manual]
- "Always ignore when it is safe" per opponent type; "continuous attack and flight"; "continue attacking fleeing ships". [V, Tips]
- The encounter screen shows both ships' state and an icon for police, pirate or trader. [V, help]

### 1.6 Dock services, record, reputation, end game
- Shipyard: fuel, repair, escape pod, new ship with trade-in. Personnel Roster: crew slots and one mercenary for hire. Commander Status: skills, reputation, worth, with Ship and Quests buttons. [V, help]
- Cargo dialogs have **Max**, **All** and **None** buttons. [V]
- Police record: Psycho, Villain, Criminal, Crook, Dubious, Clean, Lawful, Trusted, Liked, Hero. Reputation: Harmless … Elite. [V, strings]
- The moon is offered once worth reaches the threshold; it is in Utopia. [V]

### 1.7 The command bar
- Four buttons at the upper right of most screens, by default **B** (Buy Cargo), **S** (Sell Cargo), **Y** (Ship Yard), **W** (Short Range Chart), reassignable under Game → Shortcuts. [V, Tips]
- Design consequence: the PRD keeps B and S as the trade keys.

### 1.8 What the author thought was wrong [V, *Palm Game Design*, pp. 4–5]
- "'Space Trader' simply contains too many screens. A better design would have integrated more functions in fewer screens."
- "It would be possible to also integrate the selling function, producing one 'Cargo Trading' screen."
- He proposes a "nerve centre" screen from which the basic functions are reached.
- "Ten main screens and about the same number of sub-screens … far too many screen-switches … could do with about four main screens and a few sub-screens."
- "Don't use the menu except for housekeeping … some players completely forget about them."
- Main functions should take no more than one tap; double-tap is "totally out of the question".
- Players do not read help; buying, equipping and travelling must explain themselves.
- Graphics should be functional. Clarity came from standard fonts and buttons and no abbreviations.

These are the PRD's Bridge, its Cargo region, the one-click rule and the vocabulary rule.

## 2. Ports and remakes

| Port | What was learned | Source | Status |
|---|---|---|---|
| Space Trader for Windows 2.01 (Jay French, C#) | The single-window layout with a cargo grid and target-price columns is in this repo's `docs/research/02-csharp-ui-catalog.md`, which is the reference used. A reviewer wanted "a better interface and more control over battles". | https://sourceforge.net/projects/spacetraderwin/ | [V] |
| Java port and forks | Based on the C# port. | https://sourceforge.net/p/spacetraderjava/wiki | [V] |
| Android (Brucelet 1.3.5) | Faithful port. | https://apt.izzysoft.de/fdroid/index/apk/com.brucelet.spacetrader?repo=archive | [V] |
| Android (Benjamin Schieder) | Adds sliders and a side bar for menus. | https://appwisp.com/app/android/de.anderdonau.spacetrader | [S] |
| Space Trader Classic (web) | Port of the Android version. | https://github.com/lunchwine/space-trader-classic | [V] |
| memalign web port (2024) | A rewrite because the original "lacked a clean separation between UI and business logic"; deterministic RNG and replay logs made it testable. | https://memalign.github.io/p/spacetrader.html | [V] |
| Dark Nova (iOS) | Graphical overhaul; one review found navigation clunky. | https://www.pocketgamer.com/features/the-free-iphone-game-trawler-report-dark-nova-loopz-digital-heist | [V]; the iMore review is [S] |

No Hacker News or Reddit discussion of the game's interface was found.

## 3. Trade screens in related games

| Game | Pattern | Source | Status |
|---|---|---|---|
| Classic Elite | One list; Enter sells all of the selected good, or buys the maximum when none is held. | https://wiki.alioth.net/index.php/Trade_(Classic_Elite) | [V] |
| Oolite | Buy-maximum and sell-all on one key; filters; popular add-ons add the price paid, the average price and nearby markets, which shows what players missed. | https://wiki.alioth.net/index.php/Oolite_Trading | [V] |
| Endless Sky | One row per good: price, a worded price level, **profit = price − basis** for held goods, buy, sell, in hold; free space always shown; Shift-B buys maximum, Shift-S sells all. | https://raw.githubusercontent.com/endless-sky/endless-sky/master/source/TradingPanel.cpp | [V] |
| Elite Dangerous | A column compares with markets the player has data for; accurate only "at the time of being displayed". | Frontier forum | [S] |
| Offworld Trading Company | Players complained that tooltips hid key prices and that attention was split across panels. | https://www.designer-notes.com/otc-designer-notes-12-offworld-market/ [V]; Stardock forum [S] |

**What one trade row should hold** (synthesis): the good and its legality, local stock, local buy and sell price, units held and their cost basis, the destination price and the difference, and buy / maximum / sell / all controls; with cash, free bays and reserved costs always in view. The PRD's Cargo region is this row.

## 4. Apple Human Interface Guidelines and platform facts

Read on 2026-11-19 from the HIG's JSON endpoints (`https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json`); the human URLs are `https://developer.apple.com/design/human-interface-guidelines/<page>`. All items [V] unless marked.

### 4.1 Games on the Mac (`designing-for-games`, `designing-for-macos`, `going-full-screen`, `game-controls`)
- Text: macOS default 13 pt, minimum 10 pt. Buttons: default 28 × 28 pt, minimum 20 × 20 pt.
- Players on a Mac "tend to expect keyboard and mouse or trackpad support"; touch is listed as an additional input, and since 28 Oct 2026 the HIG covers Macs with touch displays ("larger tap targets … while keeping control size and density the same").
- In-game menus must adapt to different aspect ratios; "avoid fixed layouts as much as possible".
- "Use the system-provided full-screen experience"; let people choose when to enter it.
- "Use the menu bar to give people easy access to all the commands."
- In games, "prioritize single-key commands"; players still expect standard shortcuts such as ⌘Q.
- "Always include a press state for a custom button." "Avoid making custom window frames or controls." "Rely on system-provided focus effects."
- Onboarding should be fast and optional; prefer context-specific tips.

### 4.2 Windows and layout (`windows`, `layout`, `toolbars`)
- **No numeric minimum window size for macOS is given.** "Make sure that your windows adapt fluidly to different sizes."
- "**Avoid placing controls or critical information at the bottom of a window.** People often move windows so that the bottom edge is below the bottom of the screen." This moved the PRD's dock bar and status bar to the top.
- "Don't title windows with your app name."
- "Make every toolbar item available as a command in the menu bar."

### 4.3 Menu bar and keyboard (`the-menu-bar`, `menus`, `keyboards`, `focus-and-selection`)
- Order: App, File, Edit, Format, View, app-specific menus, Window, Help. "Provide a Window menu even if your app has only one window. Include the Minimize and Zoom menu items."
- "Always show the same set of menu items … disable the action instead of hiding it." Title-style capitalisation. An ellipsis "when the action requires more information before it can complete."
- "In general, don't repurpose standard keyboard shortcuts"; the list is reproduced in UI-HIG-002.
- Command is the main modifier; "avoid using the Control key as a modifier".
- "Let people use the keyboard alone to navigate and interact with your app."

### 4.4 Accessibility, colour, type, help tags, motion (`accessibility`, `color`, `dark-mode`, `typography`, `materials`, `offering-help`, `motion`, `voiceover`)
- Contrast: at least 4.5:1; "strive for a contrast ratio of 7:1, especially in small text". Provide an increased-contrast variant.
- "Convey information with more than color alone."
- "macOS doesn't support Dynamic Type"; "ideally, give people the option to enlarge text by at least 200 percent".
- Built-in macOS text styles: Large Title 26, Title 1 22, Title 2 17, Title 3 15, Headline 13 bold, Body 13, Callout 12, Subheadline 11, Footnote 10, Caption 10.
- "Don't use Liquid Glass in the content layer." "In rare cases, consider using only a dark appearance."
- Help tags: describe the action, begin with a verb, do not repeat the control's name, at most 60 to 75 characters, sentence case, no ending punctuation.
- Motion: no durations are given. "Make motion optional"; "aim for brevity and precision"; honour Reduce Motion by removing automatic and repetitive animation.
- VoiceOver: label every custom element; describe meaningful images; exclude decorative ones; announce layout changes.

### 4.5 Displays
| Mac | Native pixels | Points | Source | Status |
|---|---|---|---|---|
| MacBook Neo (2026), 13.0" | 2408 × 1506 | 1204 × 753 at exactly 2× (arithmetic; the default mode is not published) | https://www.apple.com/macbook-neo/specs/ | pixels [V], points unverified |
| MacBook Air 13.3" (M1, 2020) | 2560 × 1600 | scaled modes 1680 × 1050, 1440 × 900, 1024 × 640 listed | https://support.apple.com/en-us/111883 | [V] |
| MacBook Air 13.6" | 2560 × 1664 | 1470 × 956 default | https://www.apple.com/macbook-air/specs/ | pixels [V], points [R] |
| MacBook Pro 14.2" | 3024 × 1964 | 1512 × 982 | https://www.apple.com/macbook-pro/specs/ | pixels [V], points [R] |

- macOS 27 supports the MacBook Neo, Apple-silicon MacBook Air, MacBook Pro, iMac, Mac mini, Mac Studio and Mac Pro. [V, https://www.apple.com/os/macos/]
- Menu bar height 24 pt [V, `the-menu-bar`]; taller on displays with a camera housing (about 37 pt) [R]. Title bar about 28 pt [R].
- Not found on any Apple page: a default scaled resolution for notch-era MacBooks, the Neo's default mode, the notched menu-bar height.

## 5. Procedural ships

| Technique | Use for this project | Source | Status |
|---|---|---|---|
| Mount points: a hull carries mounts for wings, engines and weapons; a seeded generator makes results reproducible. Pitfalls: degenerate seeds, fragile generation order. | Slots as explicit mounts; golden signatures. | https://blog.rahix.de/004-spaceships | [V] |
| Blender SpaceshipGenerator: extrude a core, classify faces, add engines, antennas, turrets; mirror. | Module classes by function. | https://github.com/a1studmuffin/SpaceshipGenerator | [V] |
| Start from big simple solids, add detail second; chamfers make things look manufactured. | Silhouette first. | https://www.shamusyoung.com/twentysidedtale/?p=47461 | [V] |
| Endless Sky art guide: human ships "mostly shades of grey with some highlights"; faction recolouring by masks; baked shadows do not rotate. | Base grey plus accent; livery as a separate layer; one fixed light. | https://github.com/endless-sky/endless-sky/wiki/CreatingShips | [V] |
| Mask-and-mirror pixel ships (Bollinger). | Mirror symmetry for human ships; break it for aliens. | https://raw.githubusercontent.com/zfedoran/pixel-sprite-generator/master/pixel-sprite-generator.js | [V] |
| Keep fine detail in limited zones so the silhouette reads. | Greeble zones. | Fractal Softworks blog | [S] |
| "NASA-punk": grounded, worn, lived-in technology. | Wear layer. | GamesRadar, TechRadar | [S] |

Pitfalls: muddy silhouettes, uniform noise, size that does not match the ship's role.

## 6. Procedural portraits

| Finding | Use | Source | Status |
|---|---|---|---|
| Faces built from rows of parts with slight rotation and scale; a probability table for rare features; "human-looking features constrain what works"; counts locked for human faces. | Fixed template sets per feature, clamped variation. | https://dukope.itch.io/mars-after-midnight/devlog/263965/making-martian-faces ; https://dukope.itch.io/mars-after-midnight/devlog/532640/face-generator-updates | [V] |
| Crusader Kings II: layered portraits from a short "DNA" of genes plus properties. | The genome and gene-distance uniqueness test. | Paradox forum dev diary | [S] |
| Drawing proportions: eye line at half the head height; face in thirds; head about five eye-widths wide; mouth corners under the eye centres. | ART-FACE-004 constraints. | drawing guides | [S] |
| Uncanny effect: abnormal eyes and mismatched realism trigger it; flaws are tolerated less on realistic faces than on stylised ones. | Flat-shaded illustrated style, early proof of concept, a helmeted fallback. | Eurographics and JPMTR papers | [S] |
| Layer-order bugs (hair over or under headgear) are the classic failure of layered portraits. | Explicit back and front hair layers. | modding forums | [S] |

## 7. Pages that could not be read
GameFAQs FAQ (403); web.archive.org (blocked); Google Play and F-Droid main pages (404); TV Tropes and TouchArcade (403); the iMore review (redirect); Fractal Softworks posts (402); davebollinger.org (DNS); the Paradox forum (500); Atomic Rockets (404); the Frontier forum (403). Nothing from them is used as a requirement.
