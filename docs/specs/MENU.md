# MENU: Menu bar

> Format (PRD §7): `- **ID** {Mn} [UI] [M][W][P] statement (source)`. `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2. `[UI]` = verified by app tests or XCUITest; bullets without `[UI]` are pure functions of the app target (`MenuCatalog`, `MenuRules`) unit-tested in `SpaceTraderMacTests`.
> Milestones: the full menu bar structure, every M7 item, its shortcut, enablement and action are {M7} (PRD §9 M7 "full menu bar (MENU.md)"). Items whose feature lands later are listed now with their milestone tag and are absent (not merely disabled) until then: Galaxy section, Galaxy Chart, map zoom and Plot Route {M8} (MAP); Encounter menu, Newspaper and High Scores {M9} (UI-ENC, SCORE-039); Logbook section and Copy for the log {M10} (LOG, STAT); the shortcut conflict audit document {M12} (UI-KEYS).
> Normative input: UX-VISION §10 and §10.1. C# classic menus for reference: Game (New, Load Ctrl+L, Save Ctrl+S, Save As Ctrl+A, Retire, Exit), View (Commander Status Ctrl+C, Ship Ctrl+H, Personnel Ctrl+P, Quests Ctrl+Q, Bank Ctrl+B, High Scores, Options), Help (About) (Form_SpaceTrader.cs:699-840); in-game items disabled without a game (`SetInGameControlsEnabled`, Form_SpaceTrader.cs:2914-2924). Line numbers re-read on 2026-11-17.
> Ownership: what each action does is owned by the spec cited in its row (SAV, OPT, SCORE, CHEAT, UI-SHELL, ALR); this spec owns the menu structure, titles, shortcuts, identifiers and enablement. All titles come from `Localizable.xcstrings`; English titles are given here.

## 1. Model

- **MENU-001** {M7} [M][W][P] `MenuItemID` is an enum with one case per custom menu item in §3 (system-provided items such as Hide, Services, Minimize and Enter Full Screen are not cases). Every case has exactly one `MenuCatalog` entry; a unit test checks `MenuItemID.allCases` and the catalog keys are equal. (source: UX-VISION §10.1)
- **MENU-002** {M7} [M][W][P] `MenuContext` is a `Sendable, Equatable` value built by `MenuContext.make(session:)` from the session after every step and every presentation change. Fields: `hasGame`, `phase` (`none`, `docked`, `inTransit`, `encounter`, `gameOver`), `isModal` (UI-SHELL-012), `isIronman`, `currentSlotID`, `canRevertToAutosave` (the SAV-039 condition), `recentSlots: [RecentSlot]` (≤ 10, with `isCurrentIronmanSlot`), `warpPreview: WarpTargetPreview?` (for `warpSystem`), `targetIsCurrentSystem`, `jumpAvailable`, `hasDestinations`, `targetIsTracked`, `canBuyFuel`, `canRepair`, `selectedSection`, `searchContext` (`market`, `galaxy` or `other`), and from M8 `focusedMap: MapScope?` (the map whose canvas has focus, for the zoom items, MAP-015) and `galaxyIsKey` (the Galaxy Chart window is key, MAP-070). It holds no engine reference. (source: research 05 §4 "Put dynamic items in CommandMenus whose views observe state")
- **MENU-003** {M7} [M][W][P] `MenuCatalog.entry(for: MenuItemID) -> MenuEntry { menu, titleKey, shortcut: KeyboardShortcut?, identifier, milestone }` is the single source for every custom item's title, shortcut and accessibility identifier (`menu.<menu>.<item>`, e.g. `menu.file.save`, `menu.game.warp`). The `Commands` code reads it, and so does the Keyboard Shortcuts help page (UI-SHELL-110). (source: UX-VISION §10; UI-SHELL Conventions)
- **MENU-004** {M7} [M][W][P] `MenuRules.availability(of: MenuItemID, in: MenuContext) -> Availability { isEnabled, reason: DisabledReason? }` is a pure function with an exhaustive `switch`. Every enablement rule in §3 is implemented there and nowhere else; menu items, the toolbar Warp button and Bridge buttons that mirror a menu item use it. Unit tests cover each rule with a table of contexts. (source: PRD §6.5; UX-VISION §1.4 "Every action has a menu item")
- **MENU-005** {M7} [M][W][P] Shortcut hygiene, checked by a unit test over the catalog: no two items share a shortcut; no custom item uses ⌘C, ⌘V, ⌘X, ⌘A, ⌘Z, ⇧⌘Z, ⌘H, ⌥⌘H, ⌘M, ⌘Q, ⌘W, ⌘,, ⌘? or ⇧⌘G (these stay with their standard items); every shortcut has ⌘ or ⌃ (plain-letter keys belong to focused views, UI-SHELL-064, and to the Encounter menu, MENU-036/037). (source: UX-VISION §10 "Shortcuts must not clash with standard macOS commands"; research 05 §5)
- **MENU-006** {M7} [M][W][P] While `isModal` is true, every item of the File, View, Game and Encounter menus is disabled. App-level items (About, Settings…, Hide, Quit), the Window menu and the Help menu stay enabled. A unit test sets `isModal` and checks every `MenuItemID`. (source: UX-VISION §1.2 "Never stack modal dialogs")
- **MENU-007** {M7} [UI] [M][W][P] Menus are declared once with `CommandGroup`/`CommandMenu` in the `App`'s `.commands`; their item views observe `GameSession` (through `@FocusedValue` or the environment), so titles and enablement update without rebuilding the menu, including Open Recent's items and the Track/Untrack title. No item is created or removed at run time; Open Recent has 10 fixed rows that hide when unused. (source: research 05 §4 "The app menu is computed once", "Submenus can't be built lazily")
- **MENU-008** {M7} [UI] [M][W][P] Each custom item carries the catalog identifier as its `.accessibilityIdentifier`; UI tests open menus through `app.menuBars` and select items by that identifier (falling back to the English title where the system does not expose it). (source: PRD §6.5 "Every interactive element has an accessibilityIdentifier")

## 2. Common rules (used by the rows in §3)

- **MENU-009** {M7} [M][W][P] "Game command" means: `hasGame && !isModal && phase == .docked`. It is false on Welcome, during transit and encounters (encounter lock), and after the game has ended. (source: UX-VISION §9 "Encounter lock"; Form_SpaceTrader.cs:2914-2924; SCORE-013, OPT-007, CHEAT-005)
- **MENU-010** {M7} [M][W][P] "Session command" means: `!isModal` (File items that work with or without a game). (source: UX-VISION §2 "Welcome" actions mirror the File menu)

## 3. Menus, items, shortcuts, enablement and actions

### 3.1 Parsec Merchant (application menu)

- **MENU-011** {M7} [UI] [M][W][P] About Parsec Merchant (`menu.app.about`, replaces `.appInfo`) opens the About window (UI-SHELL-106); always enabled. (source: UX-VISION §10.1; Form_SpaceTrader.cs:3732-3735)
- **MENU-012** {M7} [UI] [M][W][P] Settings… ⌘, is the standard item of the `Settings` scene (UI-SHELL-100); always enabled. Services, Hide Parsec Merchant ⌘H, Hide Others ⌥⌘H and Show All are the system items. (source: UX-VISION §2, §10.1)
- **MENU-013** {M7} [UI] [M][W][P] Quit Parsec Merchant ⌘Q is the system item; `applicationShouldTerminate` writes the autosave (SAV-038) or the Ironman slot (SAV-046) synchronously and then replies `.terminateNow`. It never asks to discard (SAV-043). A write failure is logged and does not block quitting. (source: UX-VISION §2 "Quitting autosaves"; SAV-038, SAV-043, SAV-046)

### 3.2 File (replaces `.newItem`, `.saveItem`, `.importExport`)

| Item | Shortcut | Identifier | Enabled when | Action |
|---|---|---|---|---|
| New Game… | ⌘N | `menu.file.newGame` | session command | SAV-043, then the wizard (UI-SHELL-022) |
| Quick Start | — | `menu.file.quickStart` | session command | SAV-043, then UI-SHELL-019 |
| Open Saved Game… | ⌘O | `menu.file.open` | session command | Open sheet (UI-SHELL-088) |
| Open Recent ▸ (10 rows) | — | `menu.file.openRecent.<n>` | session command and the row's slot is not the current Ironman slot | open that slot (SAV-034/035, SAV-043, SAV-047) |
| Save | ⌘S | `menu.file.save` | `hasGame && phase != .gameOver && !isModal` | SAV-041 / SAV-047 |
| Save As… | ⇧⌘S | `menu.file.saveAs` | as Save, and `!isIronman` | SAV-041 |
| Revert to Autosave | — | `menu.file.revert` | `canRevertToAutosave && !isModal` | UI-SHELL-090 |
| Import… | — | `menu.file.import` | session command | UI-SHELL-093 |
| Export… | ⇧⌘E | `menu.file.export` | `hasGame && !isModal` | UI-SHELL-092 |
| Close Game | — | `menu.file.closeGame` | `hasGame && !isModal` | UI-SHELL-095 |
| Close Window | ⌘W | (system) | system | closes the main window, app keeps running (UI-SHELL-015) |

- **MENU-014** {M7} [UI] [M][W][P] The File menu contains exactly the rows above in that order, with separators after Open Recent, after Revert to Autosave and after Close Game; ⌘N creates a game, not a window (the standard New Window item is replaced). (source: UX-VISION §10.1 "File"; Form_SpaceTrader.cs:699-750)
- **MENU-015** {M7} [M][W][P] File enablement per the table: unit tests over contexts {no game, docked normal game, docked Ironman game, in encounter, ended game, modal} check New Game, Quick Start, Open, Import enabled iff not modal; Save iff a not-ended game; Save As iff a not-ended non-Ironman game; Revert iff `canRevertToAutosave`; Export and Close Game iff a game; none while modal. (source: SAV-039, SAV-041, SAV-047; UX-VISION §10.1)
- **MENU-016** {M7} [UI] [M][W][P] Open Recent shows the 10 newest slots of `SlotStore.list()` as "<Commander> — Day N, <System> (<Ruleset>)" with " · Ironman" and " · Ended" suffixes, newest first; unused rows are hidden, and "No Recent Games" (disabled) shows when there are none. Choosing a row behaves as Open on that slot. (source: SAV-042; UX-VISION §10.1 "Open Recent ▸")
- **MENU-017** {M7} [UI] [M][W][P] In an Ironman game (wizard with `newGame.ironman` on), Save As… and Revert to Autosave are disabled, ⌘S rewrites the game's single slot without a dialog, and Open Recent's row for that slot is disabled (SAV-047). (source: SAV-047; PRD §8.3)

### 3.3 Edit (system)

- **MENU-018** {M7} [UI] [M][W][P] The Edit menu is the system one. No game action registers with the `UndoManager`, so Undo and Redo are disabled except inside text fields, where Cut, Copy, Paste and Select All work as standard. The standard Find submenu's Find… ⌘F (`menu.edit.find`) performs the context search: in Market it focuses the item filter (UI-SHELL-067), in the Galaxy section or while the Galaxy Chart window is key it focuses the map search field (MAP-070, from M8), in other sections it opens Find System (UI-SHELL-085); enabled as a game command. Copy of selected log and statistics content is {M10} (LOG, STAT). (source: UX-VISION §10.1 "Edit", §4.7 "Find (⌘F is context search …)")

### 3.4 View

| Item | Shortcut | Identifier | Enabled when | Action |
|---|---|---|---|---|
| Show/Hide Sidebar | ⌃⌘S | (standard `SidebarCommands`) | `hasGame` | toggles the sidebar |
| Show/Hide Inspector | ⌃⌘I | (standard `InspectorCommands`) | `hasGame` | toggles the inspector (UI-SHELL-046) |
| Bridge | ⌘1 | `menu.view.bridge` | game command | select section |
| Market | ⌘2 | `menu.view.market` | game command | select section |
| Shipyard | ⌘3 | `menu.view.shipyard` | game command | select section |
| Outfitter | ⌘4 | `menu.view.outfitter` | game command | select section |
| Crew | ⌘5 | `menu.view.crew` | game command | select section |
| Bank | ⌘6 | `menu.view.bank` | game command | select section |
| Galaxy {M8} | ⌘7 | `menu.view.galaxy` | game command | select section (MAP) |
| Quests | ⌘8 | `menu.view.quests` | game command | select section |
| Logbook {M10} | ⌘9 | `menu.view.logbook` | `hasGame && !isModal` | select section (LOG) |
| Galaxy Chart {M8} | ⇧⌘M | `menu.view.galaxyChart` | `hasGame` | `openWindow(id: "galaxy")` |
| Zoom In / Zoom Out / Fit {M8} | ⌘+ / ⌘− / ⌘0 | `menu.view.zoomIn`, `.zoomOut`, `.zoomFit` | a map has focus | MAP |
| Enter Full Screen | ⌃⌘F | (system) | system | system |

- **MENU-019** {M7} [UI] [M][W][P] The View menu contains, in order: the sidebar and inspector toggles, a separator, the section items present at the current milestone (M7: Bridge, Market, Shipyard, Outfitter, Crew, Bank, Quests with ⌘1–⌘6 and ⌘8), a separator, and Enter Full Screen. The current section's item shows a checkmark. (source: UX-VISION §10, §10.1 "View")
- **MENU-020** {M7} [UI] [M][W][P] ⌘1…⌘6 and ⌘8 select Bridge, Market, Shipyard, Outfitter, Crew, Bank and Quests; a UI test presses each in a Quick Start game and checks the sidebar selection and the section's root identifier. During an encounter (interim panel) the items are disabled and pressing the keys does nothing. (source: UX-VISION §9 "Encounter lock", §10)
- **MENU-021** {M7} [M][W][P] Section items are enabled iff game command (MENU-009); a unit test checks them disabled in the contexts no game, in transit, encounter, ended and modal. (source: UX-VISION §9)
- **MENU-022** {M8} [UI] [M][W][P] Galaxy ⌘7, Galaxy Chart ⇧⌘M and the map zoom items are added with the galaxy chart; zoom items are enabled only while a map view has focus. (source: UX-VISION §10.1 "View"; MAP)
- **MENU-023** {M10} [UI] [M][W][P] Logbook ⌘9 is added with the Logbook; it stays enabled after the game has ended, so the log of an ended game can be read. (source: UX-VISION §4.9, §10.1)

### 3.5 Game (`CommandMenu("Game")`)

| Item | Shortcut | Identifier | Enabled when | Action |
|---|---|---|---|---|
| Warp | ⌘J | `menu.game.warp` | MENU-030 | `send(.warp)` |
| Use Singularity… | — | `menu.game.jump` | game command and `jumpAvailable` | `send(.jump)` (ALR-019) |
| Previous Target | ⌘[ | `menu.game.previousTarget` | game command and `hasDestinations` | `send(.selectNextTarget(forward: false))` |
| Next Target | ⌘] | `menu.game.nextTarget` | game command and `hasDestinations` | `send(.selectNextTarget(forward: true))` |
| Track "<target>" / Stop Tracking "<target>" | — | `menu.game.track` | MENU-034 | `send(.track(…))` |
| Find System… | ⌥⌘F | `menu.game.findSystem` | game command | UI-SHELL-085 |
| Plot Route… {M8} | — | `menu.game.plotRoute` | game command | MAP route planner |
| Fill Fuel | ⇧⌘F | `menu.game.fillFuel` | game command and `canBuyFuel` | `send(.buyFuel(credits: fullTankCost))` |
| Repair Hull | ⇧⌘R | `menu.game.repair` | game command and `canRepair` | `send(.repairHull(credits: fullRepairCost))` |
| Newspaper {M9} | ⇧⌘N | `menu.game.newspaper` | game command | `send(.readNewspaper)` (NEWS) |
| Options… | ⌥⌘O | `menu.game.options` | game command | options sheet (OPT-025) |
| Retire… | — | `menu.game.retire` | game command | `send(.retire)` → UI-SHELL-096 |

- **MENU-024** {M7} [UI] [M][W][P] The Game menu sits between View and Window and contains the M7 rows above in this order, with separators after Find System…, after Repair Hull and after Options…. Plot Route… is added in {M8} after Find System… and Newspaper in {M9} after Repair Hull. (source: UX-VISION §10.1 "Game"; Form_SpaceTrader.cs:739, :827)
- **MENU-025** {M7} [UI] [M][W][P] Retire… has no shortcut ("menu only", UX-VISION §10) and always goes through the `.retire` confirmation sheet with Cancel as the default (ALR-104, UI-SHELL-096). (source: UX-VISION §5.6, §10; Form_SpaceTrader.cs:3752-3760)
- **MENU-026** {M7} [UI] [M][W][P] Options… ⌥⌘O is disabled with no game, after the game has ended and outside `.docked` (OPT-025); flow 4 (UI-SHELL-126) checks the no-game case and the round trip. (source: OPT-025; Form_SpaceTrader.cs:3742-3749)
- **MENU-027** {M7} [UI] [M][W][P] ⇧⌘F and ⇧⌘R buy the full tank and the full repair as the Bridge Fill Up and Repair buttons do (UI-SHELL-055/056); the engine clamps the amount to cash (SHP-051, SHP-053). A UI test checks that ⇧⌘F is disabled at full tank in a new game and enabled after the flow-1 warp has used fuel. (source: UX-VISION §10 "Fill fuel / Repair hull ⇧⌘F / ⇧⌘R"; Form_SpaceTrader.cs:3531-3541, :3603-3613)
- **MENU-028** {M7} [M][W][P] `canBuyFuel` is `fuel < fuelCapacity && cash >= unit fuel cost of the ship` and `canRepair` is `hull < hullStrength && cash >= unit repair cost`, computed by `MenuContext.make`; a unit test checks both equal "the matching `.buyFuel`/`.repairHull` command with the full cost is not rejected" on an engine copy for fixture states (full, partly empty, broke) in every ruleset (Palm fuel compactor included). (source: SHP-051…054; GameEngine is a value type, so a copy can be probed without changing the game)
- **MENU-029** {M7} [UI] [M][W][P] ⌘[ and ⌘] cycle the target through the systems in range in the order of `selectNextTarget` (wormhole targets included, TRV), updating the toolbar target and the Bridge target card. (source: UX-VISION §4.1 "‹ › (⌘[ / ⌘]) cycle through systems in range"; Form_SpaceTrader.cs:3581-3601)
- **MENU-030** {M7} [M][W][P] Warp (menu, toolbar and Bridge) is enabled iff game command, `!targetIsCurrentSystem`, `warpPreview.inRange` and `warpPreview.blocking == nil`. When disabled for a reason, `Availability.reason` carries it (out of range, or the `CommandError` of `blocking`) for the toolbar help tag. The Wild departure is not a disabling reason: it is the `.wildLeavesWithoutLaser` confirmation (ALR-187). A unit test checks each reason and checks "enabled" agrees with `perform(.warp)` on an engine copy not being rejected, for fixture states per ruleset. (source: TRV-086, BNK-062; Form_SpaceTrader.cs:3185-3222, :3663-3680)
- **MENU-031** {M7} [UI] [M][W][P] ⌘J warps when Warp is enabled; with the window focused on any section the result is the same as the toolbar button (flow 1, UI-SHELL-124). (source: UX-VISION §10 "Warp to target ⌘J")
- **MENU-032** {M7} [M][W][P] Use Singularity… is shown only in rulesets and games where `quests.canSuperWarp` is true (hidden otherwise), and is enabled iff game command and `jumpPreview.available`; it sends `.jump`, whose `.useSingularity` confirmation names the destination (ALR-019). (source: TRV-018…021, TRV-087; Form_SpaceTrader.cs:3543-3568)
- **MENU-033** {M7} [M][W][P] Previous/Next Target are enabled iff game command and `GameState.destinations` is non-empty. (source: Travel.swift `selectNextTarget`)
- **MENU-034** {M7} [M][W][P] The track item reads `Track "<target>"` and sends `.track(warpSystem)` when the target is not the tracked system, and `Stop Tracking "<target>"` and sends `.track(nil)` when it is; it is enabled iff game command and `!targetIsCurrentSystem`. Unit tests cover both titles and the current-system case. (source: research 02 §8 pain point 5 "no Untrack button"; Form_SpaceTrader.cs:3657-3661; OPT-021)
- **MENU-035** {M7} [M][W][P] Find System… ⌥⌘F is always the system search (UI-SHELL-085), whatever section is shown; Find… ⌘F is context-dependent (MENU-018). Both are game commands. (source: UX-VISION §4.7, §10)

### 3.6 Encounter

- **MENU-036** {M9} [UI] [M][W][P] An Encounter menu (`CommandMenu("Encounter")`) between Game and Window mirrors the encounter action bar: Attack A, Flee F, Surrender S, Ignore I, Bribe B, Submit U, Trade T, Plunder P, Board O, Drink D, Meet M, Yield Y, then Auto-repeat ⌥A, Resolve R and Stop (Esc). Each item is shown only for actions in `EncounterPreview.actions` and enabled iff that action's preview has no rejection; the whole menu is disabled outside `.encounter`. Owned in detail by UI-ENC. (source: UX-VISION §5.2, §10, §10.1 "Encounter"; ENC-130, ENC-131)
- **MENU-037** {M9} [M][W][P] The Encounter menu's plain-letter shortcuts are exempt from MENU-005's ⌘/⌃ rule because they are active only while the encounter view (which has no text input) is shown; the unit test of MENU-005 checks that every modifier-less shortcut belongs to the Encounter menu. (source: UX-VISION §10 "Encounter actions A F S I B U T P O D M Y")

### 3.7 Window

- **MENU-038** {M7} [UI] [M][W][P] The Window menu is the system one (Minimize ⌘M, Zoom, Bring All to Front, the window list) plus "Parsec Merchant" (`menu.window.main`), which reopens or focuses the main window with the loaded game (UI-SHELL-015). Galaxy Chart (`menu.window.galaxyChart`, `openWindow(id: "galaxy")`, always enabled; the window shows "No game loaded" without a game) is added in {M8} and High Scores (`menu.window.highScores`, `openWindow(id: "scores")`) in {M9}. (source: UX-VISION §2, §10.1 "Window")

### 3.8 Help (replaces `.help`)

| Item | Shortcut | Identifier | Action |
|---|---|---|---|
| Parsec Merchant Help | ⌘? | `menu.help.help` | Help window, Getting Started (UI-SHELL-109) |
| How Prices Work | — | `menu.help.prices` | Help window at `howPricesWork` |
| Keyboard Shortcuts | — | `menu.help.shortcuts` | Help window at `keyboardShortcuts` |
| Credits & License | — | `menu.help.credits` | About window (UI-SHELL-106) |
| GitHub Project | — | `menu.help.github` | opens `https://github.com/megatih/parsec-merchant` in the default browser |

- **MENU-039** {M7} [UI] [M][W][P] The Help menu contains exactly the rows above, all always enabled (the system search field stays at the top). (source: UX-VISION §10.1 "Help"; PRD §2 D4)

## 4. Cross-checks and scenarios

- **MENU-040** {M7} [M][W][P] Every catalog entry tagged with a milestone above the current one is absent from `Commands` (compile-time list filtered by `MenuEntry.milestone <= MenuCatalog.currentMilestone`); a unit test checks that at the current milestone (M8 now) the File, View, Game, Window and Help menus contain exactly the rows of §3 for that milestone. (source: PRD §9 milestone scopes)
- **MENU-041** {M7} [M][W][P] Every enabled game-command item corresponds to an engine command the engine accepts in that context: for fixture states (new game per ruleset, mid-game docked, encounter, ended), each item that `MenuRules` enables and that maps to a `Command` is performed on an engine copy and is not rejected (a confirmation counts as accepted), and each item it disables with an engine reason would be rejected with that reason. (source: ALR §2 "The app also asks `preview(_:)` up front so the control is disabled before the player tries")
- **MENU-042** {M7} [UI] [M][W][P] Scenario, no game: launch with `-PMResetState`; File › Save, Save As, Revert, Export, Close Game, every View section item, and every Game item are disabled; New Game…, Quick Start, Open Saved Game…, Import…, About, Settings… and every Help item are enabled. Choose File › Quick Start: the main window shows Bridge, and Save, Export, the section items, Options… and Retire… are enabled; Warp is disabled (the target is the current system) until Next Target ⌘] selects a system in range, then enabled. (source: Form_SpaceTrader.cs:2914-2924; UX-VISION §10.1)
- **MENU-043** {M7} [UI] [M][W][P] Scenario, Retire: in a Quick Start game choose Game › Retire…; the sheet shows the score preview; Cancel leaves the game unchanged; choose again and confirm; the game-over card appears, and Save, Options…, Retire…, Warp and the section items are disabled while Export… and Close Game stay enabled. (source: SCORE-013, SCORE-017; UX-VISION §5.6)
- **MENU-044** {M7} [UI] [M][W][P] Scenario, Help and About: Help › Keyboard Shortcuts opens the Help window on the Keyboard Shortcuts topic, which lists ⌘J "Warp" and ⌥⌘O "Options…" from the catalog; Help › Credits & License opens the About window, which shows "Pieter Spronck" and the GPL notice. (source: UX-VISION §10.1; PRD §3 "Show the same credits in the About panel")
- **MENU-045** {M12} [UI] [M][W][P] The shortcut conflict audit (UI-KEYS) is generated from `MenuCatalog` plus the in-view key handlers and confirms MENU-005 against the macOS 27 system shortcut list, including Full Keyboard Access. (source: UX-VISION §10 "M12 writes the audit to docs/specs/UI-KEYS.md")

## 5. Notes

- **Additions to UX-VISION §10.1**: File › Close Game (the game-over card's "Main Menu" action, SAV-043) and Game › Use Singularity… (the classic Jump button, which needs a menu item under UX principle 4). Both have no shortcut.
- **Classic shortcuts dropped**: C# Ctrl+L (Load), Ctrl+A (Save As, clashes with Select All), Ctrl+C (Commander, clashes with Copy), Ctrl+H/Ctrl+P/Ctrl+Q/Ctrl+B (views) are replaced by ⌘O, ⇧⌘S, the inspector (⌃⌘I) and ⌘1–⌘8 (research 02 §8 pain point 12).
- **Encounter lock**: the sections and the Game menu are disabled during transit and encounters through MENU-009; in M7 the interim encounter panel (UI-SHELL-010) is the only way forward, and M9 adds the Encounter menu.
