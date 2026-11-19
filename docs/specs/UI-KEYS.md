# UI-KEYS: Keyboard shortcuts, keyboard navigation and the HIG / Liquid Glass audit

> Format (PRD §7): `- **ID** {Mn} [UI] [M][W][P] statement (source)`. `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2. `[UI]` = verified by app tests (`SpaceTraderMacTests`, hosted in the app) or XCUITest (`SpaceTraderMacUITests`). Bullets without `[UI]` are pure functions of the app target, unit-tested in `SpaceTraderMacTests`. `[manual]` = a `docs/QA-REPORT.md` row.
> Milestones: everything here is {M12} (PRD §9 M12: "HIG, Liquid Glass and shortcut audit (UI-KEYS.md) … full keyboard navigation"; exit: `verify.sh --ui` green including flows 6 and 7).
> Normative inputs: UX-VISION §1.4 ("Keyboard first … Full Keyboard Access works everywhere"), §3, §7 ("Liquid Glass", "Motion"), §9 ("Keyboard: full traversal"), §10 (keyboard map, "M12 writes the audit to docs/specs/UI-KEYS.md"), §10.1; research 05 §4–§5; PRD §6.5. Code inspected on 2026-11-17: `SpaceTraderMac/Menus/MenuCatalog.swift`, `Menus/MenuCommands.swift`, `Session/EncounterKeys.swift`, `Session/MarketModels.swift` (`MarketKeyAction`), `Map/GalaxyMapView.swift`, every `.keyboardShortcut(.defaultAction/.cancelAction)` site under `Views/`.
> **Ownership (do not restate, reference).** Menu structure, titles, identifiers and enablement: MENU (MENU-001…044). Encounter key semantics, default action and Stop: UI-ENC-027…035, ENC-130…132. Map gestures and keys: MAP-014, MAP-015, MAP-032, MAP-051, MAP-073, MAP-086. Market trade keys: UI-SHELL-062/064 (amended by UI-KEYS-012). Accessibility (VoiceOver, display settings, Text Size, flows 6 and 7, localization, TipKit, screenshots): A11Y. This spec owns the binding table, the conflict and reserved-key audit (MENU-045), Return/Esc routing, keyboard focus and the HIG / Liquid Glass checklist.

## 1. The binding table (single source)

- **UI-KEYS-001** {M12} [M][W][P] `KeyBindingTable.all: [KeyBinding]` (app target, `nonisolated`, `Sendable`) is the one list of every keyboard binding the app defines or keeps. `KeyBinding { action: KeyActionID, shortcut: MenuShortcut, context: KeyContext, owner: KeyOwner, titleKey: LocalizedStringResource }`, where `KeyOwner` is `.menu(MenuItemID)`, `.systemItem(SystemMenuItem)`, `.view(ViewKeySite)` or `.sheet(SheetKeyRole)`. It is built from `MenuCatalog` (every entry with a shortcut, all milestones), `SystemMenuItem.keptShortcuts` (§2.1 rows marked "system"), `MarketKeyAction.bindings`, `MapKeys.bindings`, `EncounterKeys` and `SheetKeys.bindings` (§5). In-view handlers (`.onKeyPress`, `.onExitCommand`) match keys by looking them up in their `bindings`, never by literals of their own. A unit test checks that every `MenuCatalog` shortcut appears exactly once with owner `.menu`, and that `MarketKeyAction.make` and the map key handler accept exactly the keys their `bindings` list. (source: UX-VISION §10 "M12 writes the audit"; MENU-003, MENU-045)
- **UI-KEYS-002** {M12} [UI] [M][W][P] Help › Keyboard Shortcuts (UI-SHELL-110) is generated from `KeyBindingTable.all`, grouped by context in the order of §2 (Menus, Market, Galaxy map, Encounter, Sheets and dialogs, Text fields), each row "<display>  <title>". Hidden aliases (UI-KEYS-013 ⌘=) are listed after their primary key. An app test builds the page model and checks it has one row per binding with an English title. (source: UI-SHELL-110; MENU-044)
- **UI-KEYS-003** {M12} [M][W][P] The tables of §2 are normative. A unit test holds them as a fixture `[(KeyActionID, display, KeyContext)]` and checks `KeyBindingTable.all` equals it (order-insensitive), so any new or changed binding must update this spec. (source: UX-VISION §10)
- **UI-KEYS-004** {M12} [M][W][P] Display glyphs: modifiers in the order ⌃⌥⇧⌘ (`MenuShortcut.display`); Escape is "⎋" in menus and help and "Esc" on key caps (`EncounterKeys.keyCap`); Return "↩", arrows "← → ↑ ↓", Tab "⇥". Letters are shown uppercase without implying ⇧. Unit test over every binding. (source: HIG "Keyboards"; MenuCatalog.swift `display`)

## 2. Complete shortcut table

### 2.1 Menu bar (global context; a key equivalent fires only while its item is enabled, MENU-004)

| Menu | Item | Keys | Owner |
|---|---|---|---|
| Parsec Merchant | About Parsec Merchant | — | `.about` |
| | Settings… | ⌘, | system (Settings scene) |
| | Hide Parsec Merchant / Hide Others / Show All | ⌘H / ⌥⌘H / — | system |
| | Quit Parsec Merchant | ⌘Q | system (autosaves, MENU-013) |
| File | New Game… | ⌘N | `.newGame` |
| | Quick Start | — | `.quickStart` |
| | Open Saved Game… | ⌘O | `.open` |
| | Open Recent ▸ | — | `.openRecent` |
| | Save | ⌘S | `.save` |
| | Save As… | ⇧⌘S | `.saveAs` |
| | Revert to Autosave | — | `.revert` |
| | Import… | — | `.importSave` |
| | Export… | ⇧⌘E | `.export` |
| | Close Game | — | `.closeGame` |
| | Close Window / Close All | ⌘W / ⌥⌘W | system |
| Edit | Undo / Redo | ⌘Z / ⇧⌘Z | system (text fields only, MENU-018) |
| | Cut / Copy / Paste / Select All | ⌘X / ⌘C / ⌘V / ⌘A | system |
| | Find ▸ Find… | ⌘F | `.find` (context search) |
| | Emoji & Symbols, AutoFill, Start Dictation | system keys (🌐E, ⌃⌘Space) | system |
| View | Show/Hide Sidebar | ⌃⌘S | system (`SidebarCommands`) |
| | Show/Hide Inspector | ⌃⌘I | system (`InspectorCommands`) |
| | Bridge … Logbook | ⌘1 Bridge, ⌘2 Shipyard, ⌘3 Outfitter, ⌘4 Crew, ⌘5 Bank, ⌘6 Commander Status, ⌘7 Quests, ⌘8 Galaxy, ⌘9 Logbook (release 2.0 dock order; the 1.x Market page has no shortcut) | `.bridge` … `.logbook` |
| | Galaxy Chart | ⇧⌘M | `.galaxyChart` |
| | Zoom In / Zoom Out / Fit | ⌘+ (alias ⌘=) / ⌘− / ⌘0 | `.zoomIn` / `.zoomOut` / `.zoomFit` (map focused) |
| | Enter Full Screen | ⌃⌘F (also 🌐F) | system |
| Game | Warp | ⌘J | `.warp` |
| | Use Singularity… | — | `.jump` |
| | Previous Target / Next Target | ⌘[ / ⌘] | `.previousTarget` / `.nextTarget` |
| | Track "<target>" / Stop Tracking | — | `.track` |
| | Find System… | ⌥⌘F | `.findSystem` |
| | Plot Route… | — | `.plotRoute` |
| | Sell All Cargo | ⌥⌘S | `.sellAllCargo` (release 2.0) |
| | Price Details… | ⌥⌘I | `.priceDetails` (release 2.0; ⌘I stays free for text) |
| | Buy Fuel… / Repair… | — | `.buyFuelAmount` / `.repairAmount` (release 2.0) |
| | Fill Fuel / Repair Hull | ⇧⌘F / ⇧⌘R | `.fillFuel` / `.repair` |
| | Newspaper | ⇧⌘N | `.newspaper` |
| | Options… | ⌥⌘O | `.options` |
| | Retire… | — (menu only) | `.retire` |
| Encounter | Attack, Flee, Surrender, Ignore, Bribe, Submit, Trade, Plunder, Board, Drink, Meet, Yield | A, F, S, I, B, U, T, P, O, D, M, Y | `.encounterAttack` … `.encounterYield` (encounter context only) |
| | Auto-repeat / Resolve / Stop | ⌥A / R / ⎋ | `.encounterAutoRepeat` / `.encounterResolve` / `.encounterStop` |
| Window | Minimize / Minimize All | ⌘M / ⌥⌘M | system |
| | Zoom, Fill, Center, Move & Resize, Bring All to Front | system (🌐⌃ arrows, 🌐⌃F, 🌐⌃C) | system |
| | Parsec Merchant / Galaxy Chart / High Scores | — | `.mainWindow` / `.galaxyChartWindow` / `.highScores` |
| | Cycle windows | ⌘` / ⇧⌘` | system |
| Help | Parsec Merchant Help | ⌘? | `.help` (standard role; the system "Show Help menu" ⇧⌘/ may open Help search first, which is accepted standard behaviour) |
| | How Prices Work / Keyboard Shortcuts / Credits & License / GitHub Project | — | `.prices` / `.shortcuts` / `.credits` / `.github` |

### 2.2 In-view keys (active only while the named view is focused and no text field is focused)

| Context | Keys | Action | Owner spec |
|---|---|---|---|
| Market table (`market.table`) | B / S | buy 1 / sell (or dump) 1 of the selected row | UI-SHELL-064, UI-KEYS-012 |
| | ⇧B / ⇧S | Buy Max / Sell All | UI-SHELL-064 |
| | ↑ / ↓ | move the row selection | UI-SHELL-064 |
| Market quantity field (`market.row.<item>.quantity`) | ↩ / ⇧↩ | buy / sell the typed quantity | UI-SHELL-062 |
| Market filter (`market.filter`) | ⎋ | clear the filter | UI-SHELL-067 |
| Galaxy map canvas (`<scope>.map`) | ← → ↑ ↓ | pan by one eighth of the visible extent | MAP-015 |
| | ⌘+ / ⌘= / ⌘− / ⌘0 | zoom in / zoom in / zoom out / Fit Galaxy (through the View menu items) | MAP-015, UI-KEYS-013 |
| | ⎋ | close the hover card, legend and suggestions | MAP-015, MAP-032 |
| Map search field (`<scope>.search.field`) | ↑ / ↓, ↩, ⎋ | move in suggestions, choose, clear | MAP-073 |
| Logbook search (`logbook.search`) | ⎋ | clear | LOG-032 |
| Encounter view | ↩ | the default action (never Attack or Surrender) or Continue Decision | UI-ENC-029, UI-ENC-036 |
| | ⎋ | Stop when `canStop` (menu item; otherwise nothing) | UI-ENC-032, UI-ENC-040 |
| Transit view | ↩ / ⎋ | Skip the playback | UI-ENC-008 |
| Welcome | ↩ | Quick Start | UI-SHELL-019 |
| Game-over card (`gameOver.card`) | ↩ | New Game… | UI-ENC-082 |
| Shipyard compare | ⎋ | clear the compare selection | UI-SHELL-070 |
| Event feed overlay (`status.feed`) | ⎋ | close the overlay | LOG (feed links) |
| Any focused control (Full Keyboard Access) | ⇥ / ⇧⇥, Space, ⌃⇥ | next / previous control, press, leave a text view | system (UI-KEYS-024) |

Mouse modifiers are accelerators only; each has a visible control that does the same without a modifier (UI-PTR-004): Market Buy/Sell with ⇧ 5, ⌘ 20, ⇧⌘ 100, ⌥ all override the row's quantity chip (UI-SHELL-062); map ⌥-click tracks like the selection card's Track button; ⌘-scroll zooms like the plain wheel and pinch; double-click targets and focuses Warp (MAP-014, MAP-051); Shipyard ⌘-click compares like the card's Compare toggle (UI-SHELL-070).

### 2.3 Sheets and dialogs (Return = `.defaultAction`, Esc and ⌘. = `.cancelAction`)

| Surface | ↩ (default) | ⎋ / ⌘. | Notes |
|---|---|---|---|
| New Game wizard | Next; Start on the summary page | Cancel | Back has no key |
| Open Saved Game | Open | Cancel | Delete… opens a destructive confirmation (Cancel default) |
| Game › Options | OK | Cancel | |
| Find System | Select | Cancel | |
| Ship purchase review | Buy | Cancel | |
| Retire | Cancel | Cancel | UX-VISION §5.6 "Cancel is the default button" |
| Cheat console | Run | Close | |
| Trade in orbit | Trade | Decline | UI-ENC-047 |
| Plunder | Done | Done | Esc added by UI-KEYS-021 |
| Jettison / Dump quantity | Jettison / Dump | Cancel | the sheet is the quantity-specific confirmation; the littering warning (ALR-047) still follows with Cancel default |
| Newspaper | Close | Close | |
| Narrative offer / message | Accept / Continue | Decline / Continue | Esc on a message page added by UI-KEYS-021 |
| Report sheets (arrival, arrest, escape pod, reactor) | Continue | Continue | Esc added by UI-KEYS-021 |
| System intel | Done | Done | Esc added by UI-KEYS-021 |
| Price Details | Done | Done | release 2.0 (UI-BRG-008) |
| Buy Fuel / Repair amount | Buy | Cancel | release 2.0 |
| About window | Done | Done (and ⌘W) | |
| Developer tester (Debug) | Close | Close | |
| Confirmation dialogs, destructive (ALR "(destructive)", `AppConfirmation` deletes and clears) | Cancel | Cancel | UI-SHELL Conventions |
| Confirmation dialogs, non-destructive | the confirm button | Cancel | |
| System alerts (`SystemAlert`) | OK | OK | |

## 3. Conflict and reserved-key audit (MENU-045)

- **UI-KEYS-005** {M12} [M][W][P] `KeyContext` has the cases `global` (menu bar), `mainWindow(DetailModeKind)`, `marketTable`, `marketField`, `mapCanvas`, `searchField`, `textField`, `encounter`, `transit`, `sheet(String)` (the `SheetRoute.key` or `AppConfirmation` name) and `dialog`. `KeyContext.canCoexist(_:_:) -> Bool` is a pure, symmetric matrix: a sheet or dialog excludes every main-window context (MENU-006, UI-SHELL-012); `encounter` excludes `marketTable`, `marketField` and the docked sections (the phases differ); `textField`/`searchField` exclude `marketTable` and `mapCanvas` (only one view has focus); `global` coexists with every context. A unit test checks symmetry and each listed exclusion. (source: MENU-006, MENU-009; UX-VISION §10 "Plain-letter keys are handled only by the focused view")
- **UI-KEYS-006** {M12} [M][W][P] No conflicts: for every pair of bindings with equal normalized shortcuts (UI-KEYS-007) whose contexts can coexist, both must carry the same `KeyActionID` (for example Esc → Stop from the Encounter menu and from the encounter view's exit command). A menu binding counts as active in a context only if `MenuRules.availability` can enable it there; the test evaluates `MenuRules` over the fixture contexts of MENU-015 plus encounter (pirate, police, trader fixtures), Market-table-focused and map-focused. Failures name both owners. (source: MENU-045; UX-VISION §10)
- **UI-KEYS-007** {M12} [M][W][P] Normalization for the audit: letters compare case-insensitively, and an uppercase letter or a shifted symbol implies ⇧ (`?` = ⇧`/`, `+` = ⇧`=`). ⌘+ and ⌘= are treated as one physical key (US layout), so the alias of UI-KEYS-013 is not a conflict. Esc (`\u{1B}`) and ⌘. both map to "cancel". Unit tests for each rule. (source: AppKit key-equivalent matching; HIG "Keyboards")
- **UI-KEYS-008** {M12} [M][W][P] `SystemShortcuts.reserved` lists the macOS 27 system and accessibility shortcuts that no custom binding (menu or view) may use, re-checked against Apple's "Mac keyboard shortcuts" support page for macOS 27 [verify] when this is implemented. A unit test checks every `KeyBinding` with a custom owner (`.menu`, `.view`, `.sheet`) against it. The list contains at least:
  - **System-wide:** ⌘Space, ⌥⌘Space, ⌃Space, ⌃⌥Space, ⌘⇥, ⇧⌘⇥, ⌥⌘⎋, ⌃⌘Q, ⇧⌘Q, ⌥⇧⌘Q, ⇧⌘3, ⇧⌘4, ⇧⌘5, ⇧⌘6, ⌃⇧⌘3, ⌃⇧⌘4, ⌥⌘D, ⌃⌘Space, ⌃↑, ⌃↓, ⌃←, ⌃→, ⌃1…⌃9 (Desktop N), F11.
  - **Full Keyboard Access and accessibility:** ⌃F1…⌃F8, ⌘F5 (VoiceOver), ⌥⌘F5 (Accessibility Shortcuts), ⌥⌘8, ⌥⌘=, ⌥⌘− (Zoom), ⌃⌥⌘8 (Invert Colors), ⌃⌥⌘, and ⌃⌥⌘. (contrast), ⇥, ⇧⇥, ⌃⇥, ⌃⇧⇥, Space.
  - **Modifier families:** any shortcut containing both ⌃ and ⌥ (the VoiceOver modifier) and any 🌐/fn shortcut (window tiling, emoji, dictation, Notification Center).
  - **Standard app shortcuts kept by their standard items only:** ⌘, ⌘H ⌥⌘H ⌘Q ⌘W ⌥⌘W ⌘M ⌥⌘M ⌘Z ⇧⌘Z ⌘X ⌘C ⌘V ⌥⇧⌘V ⌘A ⌘? ⌘` ⇧⌘` ⌃⌘F ⌃⌘S ⌃⌘I ⌘. (cancel).
  - **Reserved and kept free** (standard meaning in text views, no app item): ⌘G, ⇧⌘G, ⌘E, ⌘P, ⇧⌘P, ⌘T, ⌘B, ⌘I, ⌘U.
  
  This extends MENU-005's list; MENU-005's test stays as is. (source: research 05 §5; UX-VISION §10 "Shortcuts must not clash with standard macOS commands … including Full Keyboard Access" (MENU-045))
- **UI-KEYS-009** {M12} [M][W][P] Standard items keep their standard shortcuts: Settings… ⌘,, Close Window ⌘W, Minimize ⌘M, Enter Full Screen ⌃⌘F, the sidebar ⌃⌘S and the inspector ⌃⌘I come from the system scene or command groups (`SidebarCommands`, `InspectorCommands`), not from `MenuCatalog`. A unit test checks no `MenuCatalog` entry carries any of them, and `standardRoleItems` (Help ⌘?) is the only catalog entry with a standard-list shortcut. (source: MENU-005, MENU-012; UX-VISION §3 "standard InspectorCommands")
- **UI-KEYS-010** {M12} [UI] [M][W][P] Replacing `.textEditing` (MenuCommands.swift) removes the standard Find submenu's Find Next ⌘G, Find Previous ⇧⌘G, Use Selection for Find ⌘E and Jump to Selection ⌘J, so ⌘J belongs to Warp alone. A UI test in a docked Quick Start game opens Edit › Find and checks it contains only Find…, then presses ⌘J with a target in range and checks the day advances (no other item swallowed it). (source: MenuCommands.swift `CommandGroup(replacing: .textEditing)`; MENU-018, MENU-031)
- **UI-KEYS-011** {M12} [manual] [M][W][P] Menu-bar audit on macOS 27: the running app's menus, in a docked game and in an encounter (`-PMScenario pirateAmbush`), match §2.1 item for item, including the key equivalents the system draws; no system-added item (for example "Show Tab Bar", "Writing Tools", "Start Dictation" shortcuts) collides with a catalog shortcut. QA-REPORT row "UI-KEYS-011 menu-bar audit" with screenshots of each menu. (source: MENU-045)

## 4. In-view keys

- **UI-KEYS-012** {M12} [M][W][P] Market keyboard trading uses only plain B/S (1 unit) and ⇧B/⇧S (Buy Max / Sell All): `MarketKeyAction.make` returns nil whenever ⌘, ⌥ or ⌃ is held. Reason: menu key equivalents win over `.onKeyPress`, so ⌘S and ⇧⌘S would reach File › Save and Save As instead of "sell 20/100", and ⌥ changes the typed character. Since release 2.0 B and S trade the quantity typed in the selected row (digits edit it, UI-BRG-007). This amends the keyboard half of UI-SHELL-064. Unit tests: `make("s", [.command])`, `make("b", [.option])` and `make("b", [.control])` are nil; `make("B", [.shift])` is `.buyMax`. (source: MenuCatalog.swift ⌘S/⇧⌘S; MarketModels.swift `MarketKeyAction`; UI-KEYS-006)
- **UI-KEYS-013** {M12} [UI] [M][W][P] Map zoom: ⌘+ and its unshifted alias ⌘= both zoom in, ⌘− zooms out and ⌘0 is Fit Galaxy, only while a map canvas has focus (MAP-015, MENU-022). Because the catalog's `+` key equivalent does not match ⌘= on a US keyboard, the focused canvas adds `MapKeys` bindings for ⌘= (owner `.view(.mapCanvas)`, action `zoomIn`). A UI test focuses the Galaxy section map (Tab or click), presses ⌘=, ⌘−, ⌘+ and ⌘0 and checks `<scope>.zoomIn`/`.zoomOut` enablement and the zoom value change each time; with the map unfocused, ⌘= does nothing. (source: MAP-015 "⌘+ (and ⌘=)"; UX-VISION §10)
- **UI-KEYS-014** {M12} [UI] [M][W][P] The Encounter menu's plain-letter keys are active only while its items are shown and enabled (phase `.encounter`, `!isModal`, UI-ENC-034). A UI test in `-PMScenario pirateAmbush` reaches the plunder or trade sheet (via the fixture of UI-ENC-094 or an encounter fixture scenario), types "a" and "s" into the sheet's quantity field and checks the field shows them and no encounter action ran (the combat log is unchanged). (source: MENU-006, MENU-037; UX-VISION §10)
- **UI-KEYS-015** {M12} [M][W][P] The letters shared by the Encounter menu and the Market table (B, S) never coexist: the audit of UI-KEYS-006 finds the Encounter items disabled in every docked fixture context and the Market table context impossible in `.encounter`; the unit test asserts this pair explicitly. (source: UI-KEYS-005, UI-KEYS-006)
- **UI-KEYS-016** {M12} [manual] [M][W][P] Key-equivalent localization: catalog shortcuts use SwiftUI's default `.automatic` key-equivalent localization, so ⌘[ ⌘] ⌘+ ⌘? remap on non-US layouts and ⌘[ ⌘] mirror under right-to-left. QA-REPORT row "UI-KEYS-016 layouts": with the German and French input sources, Previous/Next Target, Zoom In and Help are reachable from the keyboard and the menus show the remapped glyphs. (source: `KeyboardShortcut.Localization.automatic`; research 05 §5)

## 5. Return and Esc

- **UI-KEYS-017** {M12} [M][W][P] `EscapeRouter.target(in: EscapeContext) -> EscapeTarget?` is a pure priority function, unit-tested with one row per level and with combinations: (1) a presented dialog → its cancel button; (2) a presented sheet → its ⎋ action from §2.3; (3) a focused text or search field with text → clear it; (4) an open map hover card, legend or suggestion list → close it; (5) an encounter with `canStop` → Stop; (6) a running transit playback → Skip; (7) the event feed overlay → Close; (8) a Shipyard compare selection → clear it; otherwise nil (Esc does nothing; it never closes a window or a game). (source: UX-VISION §1.2, §5.2 "Esc stops it"; HIG "Keyboards" Escape)
- **UI-KEYS-018** {M12} [UI] [M][W][P] The main window has one Esc handler: a single `.onExitCommand` at the window root that runs `EscapeRouter` (levels 3–8), replacing the per-view `.cancelAction` buttons of the feed overlay and the Shipyard compare panel and the per-view `.onExitCommand`s of Transit and Encounter; sheets keep their own `.cancelAction` (levels 1–2). At most one `.cancelAction` and one `.defaultAction` are live per window at any time. A UI test opens the feed overlay while a Shipyard compare selection exists and presses Esc twice: the first closes the overlay only, the second clears the selection. (source: FeedOverlay.swift and ShipyardSectionView.swift both use `.cancelAction`; UI-KEYS-017)
- **UI-KEYS-019** {M12} [UI] [M][W][P] Return outside sheets: the only `.defaultAction` buttons in the main window are Welcome › Quick Start, Transit › Skip, the encounter default action or Continue Decision (UI-ENC-029, UI-ENC-036) and the game-over card's New Game…; they never coexist (one `DetailMode` at a time). Bridge › Warp loses its `.defaultAction`: warping is irreversible and has ⌘J (UX-VISION §4.7 "it never warps directly, because warping is irreversible"). A UI test on Bridge with a target in range presses Return and checks the subtitle's day is unchanged, then presses ⌘J and checks it advanced. (source: BridgeSectionView.swift `Button("Warp") … .keyboardShortcut(.defaultAction)`; UX-VISION §4.7, §10)
- **UI-KEYS-020** {M12} [M][W][P] `SheetKeys.table(for: SheetRoute) -> SheetKeyRoles { defaultAction, escapeAction, defaultIsDestructive: false }` is an exhaustive switch over `SheetRoute` that encodes §2.3. A unit test checks every `SheetRoute` case is covered, that no default action is destructive, that Retire's default is Cancel, and, over every `WarningID` and `AppConfirmation`, that a destructive confirmation (`ConfirmationText.content(...).isDestructive`) has Cancel as both default and Esc. (source: UI-SHELL Conventions "Cancel is the default action for every destructive dialog"; UX-VISION §5.6)
- **UI-KEYS-021** {M12} [UI] [M][W][P] Every sheet answers Esc: single-button sheets (report sheets, system intel, plunder Done, narrative message, newspaper, About) map Esc and ⌘. to their only button through `.onExitCommand` on the sheet root, because a button carries one keyboard shortcut. A UI test opens each sheet of §2.3 that a fixture scenario reaches (the M9 identifier-walk fixtures, UI-ENC-096) and checks that Esc closes it with the §2.3 outcome (for narrative offers: declined, the quest state unchanged). (source: ReportSheetView.swift, SystemIntelSheet.swift, EncounterSheets.swift plunder `Done` have only `.defaultAction`; HIG "Sheets")
- **UI-KEYS-022** {M12} [UI] [M][W][P] Return in a focused text field runs the field's own submit action and never the window's default button: the Market quantity field buys (⇧↩ sells), map search chooses the highlighted suggestion (MAP-073), the wizard's name field moves to the next page, Find System selects the highlighted result. A UI test types a quantity in Market and presses Return: Held grows by that quantity and no other default action runs. (source: UI-SHELL-062, MAP-073)
- **UI-KEYS-023** {M12} [M][W][P] Dialog buttons follow the system: confirmation dialogs and alerts are `confirmationDialog`/`alert` from an optional item with `role: .cancel` and `role: .destructive` (UI-SHELL Conventions), so their Return/Esc behaviour is the system's. The unit test of UI-KEYS-020 also checks `PresentationHost` builds the destructive variant with the Cancel button carrying `.defaultAction`. (source: PresentationHost.swift; ALR §4)
- **UI-KEYS-024** {M12} [M][W][P] The app binds none of ⇥, ⇧⇥, ⌃⇥, Space or the arrow keys outside the focused views of §2.2, so Full Keyboard Access traversal and activation stay with the system. Checked by the reserved-list test (UI-KEYS-008), with the §2.2 arrow and Space-free bindings as the only exceptions. (source: UX-VISION §1.4 "Full Keyboard Access works everywhere")

## 6. Full keyboard navigation

- **UI-KEYS-025** {M12} [UI] [M][W][P] Every control is reachable: with Full Keyboard Access on (UI tests launch with `-AppleKeyboardUIMode 2` [verify the value on macOS 27]), pressing ⇥ repeatedly from the window's first control visits every interactive element of each surface in A11Y's surface catalog (A11Y-028) before cycling. The UI test records the identifier of the focused element after each ⇥ (`value(forKey: "hasKeyboardFocus")`) until it repeats and checks the set contains every interactive element the identifier walk finds on that surface (UI-SHELL-127), excluding disabled controls and menu-bar items. (source: UX-VISION §9 "Keyboard: full traversal"; PRD §9 M12 "full keyboard navigation")
- **UI-KEYS-026** {M12} [UI] [M][W][P] Focus order: the main window has three `.focusSection()`s (sidebar, detail, inspector), entered in that order; the toolbar is reached with ⌃F5 (system). Within the detail area the order is the visual reading order (top to bottom, leading to trailing). Golden orders are checked by the UI test for two sections:
  - Bridge: the target card's controls (`bridge.target.previous`, `bridge.target.next`, `bridge.target.track`, `bridge.target.plotRoute`, `bridge.target.showOnMap`, `bridge.target.jump` when shown, `bridge.target.warp`) are consecutive, in their visual order, before the fuel (`bridge.fuel.*`), repair (`bridge.repair.*`), newspaper (`bridge.newspaper.read`), special-event (`bridge.special.*`) and galaxy-code (`bridge.galaxyCode.copy`) controls, which follow the card layout top to bottom;
  - Market: `market.filter`, `market.table`, the selected row's controls (`market.row.<item>.sell`, `.quantity`, `.buy`), then `market.recommendations`, `market.why` and the footer.
  
  The exact golden lists are captured from the M12 layout and committed with the test.
  
  Other sections are covered by UI-KEYS-025 and the [manual] row of UI-KEYS-029. (source: UX-VISION §3 anatomy, §9)
- **UI-KEYS-027** {M12} [UI] [M][W][P] Default focus (`.defaultFocus` / `@FocusState`), applied when the surface appears and after ⌘1–⌘9:
  - Welcome → Quick Start; Bridge → `bridge.target.next`; Market → `market.table` (with the first stocked row selected); Shipyard → the ship list; Outfitter → the offers list; Crew → the crew list; Bank → its first enabled action; Galaxy → the map canvas; Quests → the first quest card; Logbook → the log list (Statistics and Achievements tabs: the first chart or badge);
  - Encounter view → the default action's button, else the first enabled action; Transit → Skip; game-over card → New Game…;
  - sheets → the first text field, else the default button; the New Game wizard → the commander name field.
  
  A UI test presses ⌘2 in a Quick Start game and then B (no click): Held of the first stocked row becomes 1; it presses ⌘7 and then → and checks the map viewport moved. (source: UX-VISION §1.4 "Keyboard first"; UI-SHELL-064, MAP-015)
- **UI-KEYS-028** {M12} [UI] [M][W][P] Visible focus: every custom focusable view (the map canvas, the Market table, achievement badges, quest cards, log day groups) shows the system focus ring (`.focusable()` with `.focusEffectDisabled(false)`), and the app target contains no `.focusEffectDisabled()` / `.focusEffectDisabled(true)`. The source-audit test (UI-KEYS-034) checks the latter; flow 6 screenshots (A11Y-029) show the ring on the map canvas and the Market table. (source: UX-VISION §9 "a visible focus ring on custom controls")
- **UI-KEYS-029** {M12} [manual] [M][W][P] Keyboard-only pass on macOS 27 with Full Keyboard Access on and the mouse untouched: start a game, trade, plot a route, warp through an encounter (attack, flee, plunder), read the newspaper, use the Logbook search, change Text Size in Settings, open and close every sheet of §2.3, retire, and reach High Scores. Every context-menu command has a keyboard path (Market Jettison… / Dump… through the row's controls or a menu item, map Set Target / Track / Plot Route / Find Prices through the Game menu, search or the system element actions of MAP-082, log Copy through Edit › Copy). QA-REPORT row "UI-KEYS-029 keyboard-only pass" lists any gap as ✗. (source: UX-VISION §1.4, §9)
- **UI-KEYS-030** {M12} [UI] [M][W][P] Keyboard-only scenario (automated subset of UI-KEYS-029), with no `click()` after launch (`-PMResetState -PMSeed <flowSeed> -PMFastTravel -PMAudio off -PMTips off`): ↩ (Quick Start) → ⌘2 → B → ⌘1 → ⌘] → ⌘J → wait for "Day 1" → ⌘9 → ⌘F, type a word, ⎋ → ⌘, → ⇥ to `settings.textSize` and choose the next value with the arrow keys → ⌘W → ⌘S. Each step checks its visible result (Held 1, target changed, day advanced, Logbook shown and filtered then cleared, the setting changed, the slot saved). (source: UX-VISION §1.4; PRD §8.2 "UI flows")

## 7. HIG and Liquid Glass audit

- **UI-KEYS-031** {M12} [UI] [M][W][P] There is no toolbar (UI-NAV-001): in a docked game the main window's toolbar holds no item of the app; navigation is the dock bar and status is the status bar, both at the top of the window. The UI test checks that the toolbar has no identified descendants, that the dock bar is above the status bar, that every page's dock button is in view and that cash is shown in the status bar. (rewritten for release 2.0)
- **UI-KEYS-032** {M12} [manual] [M][W][P] Liquid Glass on macOS 27: the toolbar, sidebar and inspector use the system glass with no custom backgrounds (`.scrollContentBackground(.hidden)`, opaque fills) layered over it; Warp keeps its place when the window narrows (`visibilityPriority(.high)`); the two custom glass surfaces (map HUD, encounter action bar) do not sit on other glass; content areas (tables, cards) use standard backgrounds. QA-REPORT row with light and dark screenshots of the main window, the Galaxy HUD and the encounter bar. (source: UX-VISION §7 "Liquid Glass")
- **UI-KEYS-033** {M12} [M][W][P] Menu-title ellipsis: a `MenuCatalog` title ends with "…" iff the item opens a sheet, dialog or window that asks for more input before acting: New Game…, Open Saved Game…, Save As…, Import…, Export…, Find…, Find System…, Plot Route…, Options…, Retire…, Use Singularity…. Unit test over every `MenuItemID` with the expected set. (source: HIG "Menus" ellipsis rule)
- **UI-KEYS-034** {M12} [M][W][P] `SourceAuditTests` (app test target; reads `SpaceTraderMac/**/*.swift` located from `#filePath`) checks: `.glassEffect(` occurs only in `Map/MapHUDViews.swift`, `Map/HeatmapHUDView.swift` and `Views/Encounter/EncounterActionBar.swift`; `GlassEffectContainer` occurs nowhere else; `.popover(` and `.popoverTip(` occur nowhere (extends UI-SHELL-108); `.focusEffectDisabled()` and `.focusEffectDisabled(true)` occur nowhere; `.keyboardShortcut(.defaultAction)` never follows `role: .destructive` within the same `Button` declaration. Each failure names file and line. (source: UX-VISION §7 "Custom .glassEffect is limited to two floating elements"; PRD §6.5 "Never use .popover")
- **UI-KEYS-035** {M12} [manual] [M][W][P] HIG checklist on macOS 27, one QA-REPORT row per item with ✓/✗:
  - menu items in Title Case, labels and help tags in sentence case; button labels are verbs ("Buy", "Warp", "Hire") except standard OK/Cancel/Done/Close;
  - every toolbar item and icon-only button has a help tag (`.help`), and disabled controls show their reason there (UI-SHELL Conventions "Inline reasons");
  - sheet buttons trailing-aligned with the default rightmost and Cancel to its left; destructive buttons use the destructive role; no sheet stacks on another (UX-VISION §1.2);
  - Settings changes apply immediately (no OK/Apply), the tab is remembered, and Settings never holds per-save options (UX-VISION §2);
  - SF Symbols for all chrome; custom glyphs only for game data (ART);
  - the main window respects its 1100×720 minimum, Enter Full Screen works with the sidebar, toolbar and inspector intact, and ⌘W keeps the app running (UI-SHELL-015).
  
  (source: PRD §9 M12 "HIG … audit"; research 05)

## 8. Scenarios

- **UI-KEYS-036** {M12} [UI] [M][W][P] Global shortcut sweep in one Quick Start game (`-PMSeed <mapFlowSeed>`): ⌘1…⌘9 select each section (root identifiers); ⌃⌘I toggles the inspector and ⌃⌘S the sidebar; ⌘] then ⌘[ change and restore `toolbar.target`; ⌥⌘F opens Find System and ⎋ closes it; ⌘F on Market focuses `market.filter`, on Galaxy the map search field and on Logbook `logbook.search`; ⇧⌘M opens the Galaxy Chart window and ⌘W closes it; ⌥⌘O opens Options and ⎋ closes it; after a warp, ⇧⌘F is enabled and refuels (status fuel full), and ⇧⌘N opens the newspaper and ⎋ closes it. (source: UX-VISION §10; MENU-020, MENU-027, MENU-029, MENU-035)
- **UI-KEYS-037** {M12} [UI] [M][W][P] Encounter key sweep with `-PMScenario pirateAmbush`: Return triggers the default action (Flee for a hostile pirate, UI-ENC-029) and the log shows its row; on a relaunch, R starts Resolve and ⎋ stops the repeat (`encounter.action.stop` no longer enabled, the log stops growing); ⌥A toggles `encounter.autoRepeat`; pressing a letter whose action is not offered (for example U) changes nothing. (source: UI-ENC-028…033, UI-ENC-040)

## 9. Notes

- **Code changes this spec requires at M12** (for the implementer's checklist; each is owned by the bullet cited): remove Bridge Warp's `.defaultAction` (UI-KEYS-019); `MarketKeyAction` ignores ⌘/⌥/⌃ (UI-KEYS-012); ⌘= alias on the focused map (UI-KEYS-013); one `EscapeRouter` at the main-window root replacing the feed overlay's and Shipyard's `.cancelAction` (UI-KEYS-017/018); Esc on single-button sheets (UI-KEYS-021); `KeyBindingTable`, `SystemShortcuts`, `SheetKeys`, `SourceAuditTests` (UI-KEYS-001, 008, 020, 034); default focus per surface (UI-KEYS-027).
- **Classic shortcuts dropped** are listed in MENU §5.
- **Help ⌘?:** kept as the standard Help item's role key (MENU-005 `standardRoleItems`); the system's "Show Help menu" (⇧⌘/) shortcut can take precedence, which is standard macOS behaviour and not a conflict.
- **Implementation notes (M12).** (1) The main window's Esc router (UI-KEYS-018) is bound as the window's one `.cancelAction` (an invisible button in `WindowEscapeRouter`, plus `.onExitCommand`), because the exit command only reaches a focused SwiftUI view; views register their level 3/4/7/8 handlers with `EscapeRegistry` (`.escapeHandler(_:active:perform:)`), so the Market filter and the Logbook search no longer have their own `.onExitCommand` (the map search keeps its key handler for the Galaxy Chart window, which has no router). (2) `KeyBindingTable` gives menu bindings the context in which `MenuRules` can enable them (Encounter items `.encounter`, Zoom In/Out/Fit `.mapCanvas`, all others `.global`). (3) `SheetKeys` works on `SheetSurface` (every `SheetRoute` plus the Market jettison/dump sheets, System intel, About and the dialogs); `SheetKeys.table(for: SheetRoute)` maps a route to its surface; single-button sheets use `.sheetEscape` (exit command plus an invisible `.cancelAction`). (4) Help › Keyboard Shortcuts adds a "Window" group (Welcome, Transit, game over, the Esc router) between Encounter and Sheets. (5) Focus order: in the two-column Bridge layout the left column (system, fuel, repair) precedes the right column (mini chart, target card); the UI test checks the target card's controls are reached in their visual order and attaches the captured Bridge and Market Tab orders (`bridge-tab-order`, `market-tab-order`) instead of committing golden lists. (6) Default focus (UI-KEYS-027) is applied to the Galaxy map canvas (focusable with `.edit` interactions, focused after it appears, so ⌘=/⌘−/⌘0 and the arrows act at once; the canvas also answers ⌘− and ⌘0 itself). On macOS 27 a SwiftUI focus binding on the Market `Table`, and `.focused`/`.defaultFocus` on buttons (Welcome, Bridge, Transit, encounter bar, game-over card), made mouse clicks on those controls unreliable in the UI flows, so they are left to the system's initial key view; the Market table is reached from the keyboard with ⌘F then ⇥ (UI test). Market ⌘F, which published an unread focused value, now focuses the filter through `contextSearch` (MENU-018).
