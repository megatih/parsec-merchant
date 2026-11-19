# 09 · UI audit of Parsec Merchant 1.1.0

> Input for `docs/PRD-UI-Revamp.md`. Audited on 2026-11-19 at commit `296ad2c` (two UI commits after tag `v1.1.0`; the engine is identical to `v1.1.0`). Paths without a prefix are relative to `SpaceTraderMac/` (the app target). `PA/` means `Packages/ParsecKit/Sources/ParsecArt/`. Line numbers are those of commit `296ad2c`; re-check them before relying on one.
>
> How it was made: three read-only code audits (app UI, art, gates and engine queries) and a reading of the committed screenshots `docs/screenshots/readme-*.png` (captured for 1.1.0). The app was not launched for this audit, because the UI tests take over the pointer and run for about an hour.

## 1. Platform and structure

| Item | Finding |
|---|---|
| UI framework | SwiftUI, with AppKit bridges (`PopUpMenuButton` wraps `NSPopUpButton`; `LaunchWindowSizer` and `PlanetMetalView` are `NSViewRepresentable`; the map installs an `NSEvent` scroll monitor). Also Swift Charts, TipKit, App Intents, Metal, Observation. |
| Deployment target | macOS 27.0 (`SpaceTraderMac.xcodeproj/project.xcproj`; package `platforms: [.macOS("27.0")]`). |
| Language | Swift 6 mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, warnings are errors, no third-party dependencies. |
| Size | 203 Swift files, about 28,400 lines in the app target. |
| Packages | `Packages/ParsecKit`: `ParsecEngine` (rules), `ParsecInsights` (fair trade intel, route planner), `ParsecPersistence`, `ParsecArt` (all drawing, no engine import), `ParsecAudio`; tools `pmsim` and `pmart`. |
| Main window | `Window("Parsec Merchant", id: "main")`, default 1320 × 860, minimum 1100 × 720 content (`App/ParsecMerchantApp.swift:12-16`, `Views/RootView.swift:18`), plus a unified toolbar. |
| Other scenes | Galaxy Chart window, High Scores, Settings, About, Help. |

## 2. Navigation and state

- **Root:** `RootView` shows `WelcomeView` or `MainShellView` from `SessionMode` (`Session/SessionTypes.swift:7-18`).
- **Shell:** `NavigationSplitView` with a sidebar `List`, a detail column (section, divider, `StatusBarView`), an `.inspector` (260–380 pt, visible by default) and a toolbar (`Views/Shell/MainShellView.swift:17-40`).
- **Route:** `Section` enum with nine cases, ⌘1–⌘9 (`Session/Section.swift:26-89`): Bridge, Market, Shipyard, Outfitter, Crew, Bank, Galaxy, Quests, Logbook. State is `GameSession.selectedSection`.
- **Detail override:** `DetailMode.derive` (`Session/DetailMode.swift:14-24`) replaces the section with Transit, Encounter or Game Over.
- **Store:** `@Observable @MainActor final class GameSession` (`Session/GameSession.swift`), injected through the environment. Views build pure `…Model.make(state:)` structs on each render (`Session/*Models.swift`).
- **Commands:** `session.send(Command)` calls `engine.perform` and then `apply` (rejections go to the status bar for 4 s; decisions go to the single presentation queue in `Views/Presentation/PresentationHost.swift`).
- **Previews:** read straight from `GameState` / `GameEngine` during render (`warpTargetPreview`, `marketBuyCheck`, `bankPreview`, `encounterPreview`, …). `Menus/MenuRules.swift` builds menu, toolbar and button enablement from the same previews.
- **Localization:** `Resources/Localizable.xcstrings`, 2,258 keys, English only. The engine emits no strings; `Text/*.swift` maps engine values to text.

## 3. Screen inventory

| Screen | File | Reached by |
|---|---|---|
| Welcome | `Views/Welcome/WelcomeView.swift` | no game loaded |
| Bridge | `Views/Sections/BridgeSectionView.swift` | sidebar, ⌘1 |
| Market | `Views/Sections/MarketSectionView.swift`, `Views/Market/MarketIntelViews.swift` | sidebar, ⌘2 |
| Shipyard and Designer | `Views/Sections/ShipyardSectionView.swift`, `Views/Designer/DesignerView.swift` | sidebar, ⌘3 |
| Outfitter (equipment) | `Views/Sections/OutfitterSectionView.swift` | sidebar, ⌘4 |
| Crew (personnel) | `Views/Sections/CrewSectionView.swift` | sidebar, ⌘5 |
| Bank | `Views/Sections/BankSectionView.swift` | sidebar, ⌘6 |
| Galaxy | `Map/GalaxyMapView.swift`, `Map/MapPlacements.swift` | sidebar, ⌘7, mini chart |
| Quests | `Views/Sections/QuestsSectionView.swift` | sidebar, ⌘8 |
| Logbook (log, statistics, achievements) | `Views/Logbook/*.swift` | sidebar, ⌘9 |
| Commander status | `Views/Inspector/ShipInspectorView.swift` (the inspector; there is no page) | ⌃⌘I |
| Transit | `Views/Transit/TransitView.swift` | automatic |
| Encounter | `Views/Encounter/*.swift` | automatic |
| Game over | `Views/GameOver/*.swift` | automatic |
| Status bar | `Views/Shell/StatusBarView.swift` | always |
| Sheets | New Game wizard, Open, Options, Find System, Ship purchase, Retire, Cheat console, Trade in orbit, Plunder, Newspaper, Narrative, Report, Jettison/Dump, Make Room, System Intel | `Views/Presentation/SheetRouteView.swift` and local sheets |

Menus: App, File, Edit, View, Game, Encounter, Window, Help (`Menus/MenuCommands.swift`, `Menus/MenuCatalog.swift`). All bindings are in one table, `Keys/KeyBindingTable.swift`.

## 4. How things are drawn today

| Subject | Today |
|---|---|
| Ships | Parametric side-view hulls: `PA/Ships/*` (8 files). `ShipHullGenerator.make(stats, variant)` picks one of five archetypes and one of three liveries per archetype. Installed equipment shapes hardpoints. There is **no role input**: police, pirate and trader ships of one type are identical, and the variant is fixed per ship type. |
| Portraits | One system, `CrewAvatar` (`PA/Glyphs/CharacterArt.swift:10-100`): a faceless helmeted bust, 5 helmets × 4 visors × 8 colours. Seed = galaxy seed + crew id. Shown only in the Crew section at 34 × 34 pt. The commander's bust is the same for every game started from the same galaxy code. |
| Planets | `PA/Planets/*` (8 files): seeded noise baked to maps and projected on a sphere on the CPU; the Bridge shows a live Metal planet (`Art/PlanetMetalView.swift`, `Art/PlanetPortrait.swift`, `Art/PlanetSphereShader.swift`). Map mini-planets come from `Art/MapArt.swift`. **Protected by the revamp.** |
| Endings | `PA/Scenes/Endings.swift`: one file with four scenes (retired, moon, moon with princess, killed), hosted by `GameOverArt` in `Art/ArtViews.swift:73-92`. |
| Status bar | One `HStack`: Bays, Fuel, Hull, a rejection reason, an arrival chip, the latest event. It is under the detail column only. |
| App icon | `PA/Icon/AppIconArt.swift` draws a hauler with the ship generator; `scripts/make-icon.sh --check` compares pixels with the committed PNGs. |

Coupling to remember: the endings, the app icon, the achievement emblems (`ShipArtEmblem`), two vignettes and the combat-effect geometry (`ShipArtLayout.frame`) all call ship code.

## 5. Tests and gates

- **Package tests:** 1,371 (engine 1,110; insights 100; art 75; persistence 52; audio 29; scenarios 5). **App tests:** 516 (Swift Testing, hosted). **UI tests:** 52 run, 6 skipped.
- **Gates:** `scripts/verify.sh --quick` (build, tests, lint), `scripts/verify.sh` (adds coverage, fuzz, app build and tests, spec trace, license and SPDX, icon check), `scripts/verify.sh --ui` (adds XCUITests; 53–86 minutes), `scripts/final-check.sh` (8 checks, hard-coded to `v1.1.0` and 18 milestones).
- **Source audits in tests:** no `.popover`, glass only in three files, every `.disabled` has a `.help`, pointer targets of 36 pt, localization rules, identifier pattern.
- **Art tests:** no golden images. Tests render twice and compare SHA-256 fingerprints (`Packages/ParsecKit/Tests/ParsecArtTests/ArtSnapshot.swift`).
- **Layout tests:** `LargestTextSizeUITests` checks clipping at the minimum window with the largest Text Size.
- **Build and test commands:** see `CLAUDE.md`.

## 6. Usability problems

### 6.1 The core loop is split across screens
1. **The Bridge scrolls.** The whole page is one `ScrollView` (`Views/Sections/BridgeSectionView.swift:14`). In `docs/screenshots/readme-bridge.png` the Mercenaries card is cut by the bottom edge at the default size and the Newspaper card is off screen.
2. **Buying and selling are not on the Bridge.** Every trade needs a switch to Market, and fuel and repair need a switch back, because arrival never changes the section (UI-ENC-055).
3. **Cash is not in the status bar** (`Views/Shell/StatusBarView.swift:15-27` shows only bays, fuel and hull). Cash lives in the window subtitle, which hides it during transit and encounters (`Session/WindowTitles.swift:25-27`), and in the inspector, which can be closed.
4. **Destination prices follow one global target.** The Market's Target column shows only the selected warp target, and Market has no target selector. The 10-good list for another system is four clicks away on the map (`Map/MapActions.swift:92-94`).
5. **No "sell the hold" action.** Selling N goods costs N to 2N clicks; the one-click path (⌥-click Sell) is an undiscoverable modifier (`Session/MarketModels.swift:8-43`).
6. **The Market row is overloaded.** Seven controls per row (1, 5, 20, Max, Sell, Qty, Buy; see `docs/screenshots/readme-market.png`), with Sell and Buy drawn as plain text and a "No history" column on every row.
7. **Jettison is unreachable from Market** (`canJettison = !docked`, `Session/MarketModels.swift:151`).
8. **Width is spent on chrome.** Sidebar (180–260 pt) plus inspector (260–380 pt) leave the Market in compact mode at the default window size (`Views/Sections/MarketSectionView.swift:118-124`).

### 6.2 Duplicated navigation and data
9. **Warp is in four places** (toolbar, Bridge Target card, map strip, Game menu) and target selection has about seven entry points with different wording.
10. **Two system searches** with different interfaces (`Views/Presentation/FindSystemSheet.swift` and `Map/MapHUDViews.swift:310-447`); ⌘F picks one by context.
11. **The same data in several places:** next-warp costs four times (inspector, Bank, Target card, Warp help tag); skills twice; police record and reputation twice; bays three times; hull three times.

### 6.3 Terminology drift (the original's terms are in brackets)
12. "Outfitter" [Buy/Sell Equipment], "Crew" [Personnel Roster], "Galaxy" / "Galaxy Chart" [Galactic Chart], "Inspector" / "ship status" [Commander Status].
13. Tracking: "Track", "Untrack", "Stop Tracking", "Track Target".
14. Fuel and hull: "Fill Up" vs "Fill Fuel"; "Repair" vs "Repair Hull"; partial amounts use a bare "Buy".
15. Maximum quantity: "Max", "Buy Max", "Sell All", "All", "Take All" (`Accessibility/PointerTarget.swift:158-163`, `Views/Encounter/EncounterSheets.swift:72-112`).
16. Costs: "Daily Costs", "Costs of the Next Warp", "Total costs".

### 6.4 Inconsistent components
17. **Four tab styles** (Shipyard buttons, Logbook segmented picker, High Scores buttons, Settings `TabView`).
18. **Four card containers** (`GroupBox`, custom rounded background, grouped `Form`, `Color.secondary.opacity`).
19. **Seven corner radii** (10, 8, 6, 12, 18, 3, 2) and **five selection tints** (accent at 0.12 to 0.35).
20. **No spacing tokens:** 133 literal `.padding` calls. No shared card, section header, badge or empty-state component.
21. **Raw colours bypass tokens:** `Views/Encounter/EncounterShipPane.swift:108-112`, `Views/Sections/BankSectionView.swift:39`, `Views/Shell/SidebarView.swift:77`, `Views/Sections/QuestsSectionView.swift:79`; unscaled fonts in `Views/Newspaper/NewspaperSheet.swift:17` and `Views/Sections/BridgeSectionView.swift:164`.
22. **The accent colour set is empty** (`Assets.xcassets/AccentColor.colorset/Contents.json`), so the "brass" accent of UX-VISION §7 is not applied.
23. **Page widths and headings differ** (Crew 900, Bank and Quests 720, Bridge and Market full width; three heading styles).

### 6.5 Hidden or missing cues
24. **Sidebar shortcut hints are never drawn** (`Views/Shell/SidebarView.swift:48-62`).
25. **Encounter buttons show no key caps** although the doc comment says they do (`Views/Encounter/EncounterActionBar.swift:5`); in `docs/screenshots/readme-encounter.png` half the page is empty and the action bar floats at the bottom.
26. **The Market context menu is attached only to the Held cell** (`Views/Sections/MarketSectionView.swift:192`).
27. **Police, pirate and trader ships look the same**; only a badge capsule and the pane title differ.
28. **Portraits are faceless** and appear on one screen only.

### 6.6 Dead code found
`PlaceholderSheet` (`Views/Presentation/SheetRouteView.swift:42-58`), `InterimEncounterModel` (`Session/ShellModels.swift:236-252`), `MarketRowModel.target`, and unused `ContrastStyle` members (`Accessibility/DisplayStyles.swift:74-78`).

## 7. Click cost of the core loop today

Start: docked, on the Bridge, pointer only. A "screen change" is a section switch or a sheet.

| Step | Clicks today | Screen changes today |
|---|---|---|
| Arrive and read the situation | 0–2 (dismiss the report sheet, close the auto newspaper) | 0–2 |
| Sell one good, all units | 3 the first time (Market, Max chip, Sell), then 1–2 per good | 1 |
| Sell a hold of 3 goods | 5–7 | 1 |
| Buy one good, maximum | 2 (Max chip, Buy) once in Market | 0–1 |
| Refuel | 2 (back to Bridge, Fill Up) | 1 |
| Repair | 1 on the Bridge | 0 |
| Choose a destination and compare its prices | 2–4 (pick on the chart, switch to Market; or map, system, Find Prices, Done) | 1–3 |
| Warp | 1–4 (Warp, Skip, Continue, Close newspaper) | 1–3 |
| Resolve an encounter | 1 per action, +1 for each confirmation | 0 |
| **One uneventful loop (sell 2, buy 1, refuel, pick, warp)** | **about 12–14** | **about 4–5** |

## 8. Engine facts the design depends on

- **Exact prices in another system do not exist until arrival.** Only the current system has `buyPrices` and `sellPrices`. The original's Average Price List is `standardPrice` with the resource known only for visited systems (C# `Form_SpaceTrader.cs:2960-3020`, `TradeItem.cs:87-114`; Palm `Traveler.c:762-830`).
- **The fair intel layer already exists:** `TradeIntel.quote` / `estimate` / `bestBuys` / `bestDestinations` / `holdValue` in `Packages/ParsecKit/Sources/ParsecInsights/Intel/TradeIntel.swift`, with the source order live → observed (with age) → estimate (INT-012, INT-013, INT-030).
- **`GameState` is fully public**, so a view could read hidden data (other systems' stock, pressure, true resource, an unpaid newspaper). Fairness is by convention and tests (INT-001…023, MAP-097).
- **Cost basis exists:** `MarketRow.costBasisPerUnit` (`Economy/Market.swift:12`).
- **No per-opponent identifier** is stored; `EncounterState` has the type, the opponent ship, the round and the clicks. Crew are identified by integer `CrewID` (55 ids; 44 hireable in Modern and Windows, 31 in Palm).
- **Saves:** `GameState.seed` and the envelope's `gameID` are persisted. Adding any field to `GameState` would change the save format and the fuzz hashes.
- **Reference values for "logic unchanged"** (from `build/logs/3-fuzz.log` and `docs/QA-REPORT.md`; re-measure before relying on them): fuzz command counts modern 4,531,100, windows201 4,528,609, palm122 3,134,221; scenario moon days 265 / 336 / 657; bot 17/20, 19/20, 13/20.
