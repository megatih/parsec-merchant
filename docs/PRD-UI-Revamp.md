# Parsec Merchant 2.0: interface revamp PRD

> **What this is.** The complete specification for release 2.0.0: a new interface, new procedural ships, portraits and endings, on unchanged game rules. It extends `docs/PRD.md` and `docs/PRD-1.1.md` and wins where they differ. Milestones M18–M28.
>
> **Who reads it.** An autonomous agent with no memory of earlier sessions and nobody to ask. Every decision is made here. Where this file says "assumption", act on it; do not stop to confirm.
>
> **Words.** MUST is a hard requirement. SHOULD may be deviated from only with an ADR in `docs/adr/`. Paths without a prefix are relative to the repository root. `APP/` means `SpaceTraderMac/`, `PA/` means `Packages/ParsecKit/Sources/ParsecArt/`.

## 0. Running it (owner)

1. Pre-flight: `git status` is clean on `main`, `gh auth status` succeeds, and macOS has granted UI-automation permission to the terminal (needed for `scripts/verify.sh --ui`).
2. Start the run with:
   `/goal Implement docs/PRD-UI-Revamp.md from M18 to M28. Done when one turn shows the unedited output of scripts/final-check.sh ending with "FINAL CHECK 10/10 PASS" and "EXIT=0" on a clean tree whose HEAD equals origin/main and is tagged v2.0.0.`
3. Approved in advance: pushing to `origin/main`, pushing tags `m18-done`…`m28-done` and `v2.0.0`, and publishing the GitHub release `v2.0.0` with `scripts/release.sh`.

---

## 1. Summary, goals, non-goals, protected assets

### 1.1 Summary

Parsec Merchant 1.1.0 is a complete, native macOS 27 remake of Space Trader with three rulesets (Modern, Windows 2.01, Palm 1.2.2). Its interface spreads the trade loop over a sidebar, a toolbar, an inspector and nine sections. Release 2.0.0 replaces that with:

- a **Bridge** that holds the whole core loop on one screen with no scrolling;
- one **dock bar** for every secondary screen and one **status bar** for what must always be visible;
- a single **design system** for the game area, inside native macOS window chrome and menus;
- new **procedural ships** (hard-sci-fi, built from statistics and installed equipment, with seeded liveries per role), new **procedural portraits** (faces, unique per character) and new **ending scenes**.

Game rules do not change.

### 1.2 Goals

| ID | Goal | Measured by |
|---|---|---|
| G1 | The core loop (arrive, read, sell, buy, refuel, repair, choose a destination by comparing prices, warp) needs no screen change. | Flow test UI-BRG-040; click table in §2.4 |
| G2 | The Bridge never scrolls, hides or collapses anything, from 1200 × 680 pt upward. | Layout tests UI-BRG-030…036 |
| G3 | One navigation model, one component set, one vocabulary taken from the original game. | Source audits UI-DS-020…026, UI-NAV-001…012 |
| G4 | Ships show what they are: statistics, installed equipment and role are visible; no opponent looks like the player's ship. | ART-SHIP tests |
| G5 | Every character has their own stable face. | ART-FACE tests |
| G6 | Full keyboard operation, menu commands, help tags, VoiceOver labels, contrast, and no meaning carried by colour alone. | §3.6 and M27 tests |
| G7 | Game behaviour is bit-identical to 1.1.0. | `scripts/logic-frozen.sh` |
| G8 | Planet graphics are untouched. | `scripts/protected-check.sh` |

### 1.3 Non-goals

- No change to rules, formulas, data tables, balance, RNG, save format or the three rulesets.
- No new information for the player beyond what 1.1.0 already exposes (current system data, public facts of other systems, the fair trade intel of `ParsecInsights`).
- No external image assets, fonts or third-party dependencies. All art stays drawn in code (ART-001, ART-066).
- No new languages. English stays the only localization; every string still goes through the catalog.
- No change to audio, haptics, App Intents, the differential harness, cheats, or the Foundation Models flavor text, beyond re-wiring them to the new views.
- No iOS, iPadOS or controller support.

### 1.4 Protected assets (off-limits)

The planet graphics MUST NOT change. "Unchanged" means both: the files below are byte-identical to commit `296ad2c6729fa626fd826b44f112ac2c959eb870`, and the planet pixels are identical (PROT-003).

**A. Planet sources (never edit, move, rename or delete):**

```
Packages/ParsecKit/Sources/ParsecArt/Planets/PlanetArt.swift
Packages/ParsecKit/Sources/ParsecArt/Planets/PlanetCache.swift
Packages/ParsecKit/Sources/ParsecArt/Planets/PlanetClass.swift
Packages/ParsecKit/Sources/ParsecArt/Planets/PlanetLayers.swift
Packages/ParsecKit/Sources/ParsecArt/Planets/PlanetNoise.swift
Packages/ParsecKit/Sources/ParsecArt/Planets/PlanetRecipe.swift
Packages/ParsecKit/Sources/ParsecArt/Planets/PlanetSphere.swift
Packages/ParsecKit/Sources/ParsecArt/Planets/PlanetTextureBaker.swift
SpaceTraderMac/Art/PlanetMetalView.swift
SpaceTraderMac/Art/PlanetPortrait.swift
SpaceTraderMac/Art/PlanetSphereShader.swift
SpaceTraderMac/Art/MapArt.swift
```

**B. Shared files the planets depend on (frozen for the same reason):**

```
Packages/ParsecKit/Sources/ParsecArt/Core/ArtRandom.swift
Packages/ParsecKit/Sources/ParsecArt/Core/ArtPalette.swift
Packages/ParsecKit/Sources/ParsecArt/Core/ArtGeometry.swift
Packages/ParsecKit/Sources/ParsecArt/Core/ArtAccessibility.swift
Packages/ParsecKit/Sources/ParsecArt/Space/SpaceArt.swift
```

**C. Planet tests and tools (frozen so the proof cannot be weakened):**

```
Packages/ParsecKit/Tests/ParsecArtTests/PlanetSpaceTests.swift
Packages/ParsecKit/Tests/ParsecArtTests/PlanetSphereTests.swift
SpaceTraderMacTests/PlanetLiveTests.swift
Packages/ParsecKit/Sources/pmart/PlanetSheet.swift
docs/adr/0004-live-planet-metal-layer.md
```

Consequences:
- New colours, geometry helpers and seed helpers go in **new** files (for example `PA/Core/ArtPalette2.swift`); never add to a frozen file.
- Views use the planets through their existing public API only (`PlanetHero`, `PlanetPortrait`, `PlanetArt`, `PlanetRenderer`, `MapArtRenderer`). If a planet view cannot be used at the size a wireframe gives, change the surrounding layout, not the planet file.
- `APP/Art/ArtAdapters.swift` is shared with ships and may be edited, but its `planetInput` function and `SystemText.planetLabel` MUST keep their behaviour (covered by PROT-003).
- The endings (`PA/Scenes/Endings.swift`) are **not** protected. The owner decided on 2026-11-19 that all four endings are redesigned (§5.3).

**Game-logic freeze (not art, but equally off-limits):** `Packages/ParsecKit/Sources/ParsecEngine`, `Sources/ParsecInsights`, `Sources/ParsecPersistence` and their test targets `Tests/ParsecEngineTests`, `Tests/ParsecInsightsTests`, `Tests/ParsecPersistenceTests`, `Tests/ParsecScenarioTests`, the shared `Tests/Fixtures`, and `Sources/pmsim`, are byte-identical to tag `v1.1.0`. The reference sources in `/Users/megatih/Downloads/SpaceTraderSource201` and `docs/reference/` stay read-only as before.

- **PROT-001** {M18} `scripts/protected-check.sh` exits 0 only if `git diff --exit-code 296ad2c6729fa626fd826b44f112ac2c959eb870 -- <every path in lists A, B, C>` reports nothing and every listed path exists.
- **PROT-002** {M18} `scripts/logic-frozen.sh` exits 0 only if `git diff --exit-code v1.1.0 -- <the frozen package paths above>` reports nothing and the behaviour fingerprints of §8.2 match.
- **PROT-003** {M18} `Packages/ParsecKit/Tests/ParsecArtTests/PlanetFrozenTests.swift` pins SHA-256 pixel fingerprints of planets, recorded at M18 before any other change, and fails if one differs.

---

## 2. Audit findings and task analysis

The full audit is `docs/research/09-ui-audit.md`. Research sources are in `docs/research/10-ui-revamp-research.md`. This section holds what the design is built on.

### 2.1 What exists

- SwiftUI on macOS 27, Swift 6, one `@Observable` store (`APP/Session/GameSession.swift`), pure view models (`APP/Session/*Models.swift`), commands through `session.send(_:)`, previews read from `GameState` / `GameEngine`, one presentation queue (`APP/Views/Presentation/PresentationHost.swift`), one key binding table (`APP/Keys/KeyBindingTable.swift`), one menu catalog (`APP/Menus/MenuCatalog.swift`).
- Shell: `NavigationSplitView` sidebar (9 sections) + toolbar + inspector + status bar under the detail column. Main window minimum 1100 × 720 pt content plus a toolbar.
- Art: `ParsecArt` package target; ships are parametric side views with no role input; portraits are faceless helmets shown on one screen; planets are baked spheres (protected); endings share one file.
- 1,371 package tests, 516 app tests, 52 UI tests; gates in `scripts/verify.sh` and `scripts/final-check.sh`.

### 2.2 The problems that drive the design

| # | Problem | Evidence |
|---|---|---|
| P1 | The Bridge scrolls and still lacks buying and selling. | `APP/Views/Sections/BridgeSectionView.swift:14` |
| P2 | Trading and dock services are on different screens; arrival never returns to the Bridge. | `MarketSectionView.swift`, UI-ENC-055 |
| P3 | Cash is not in the status bar. | `APP/Views/Shell/StatusBarView.swift:15-27` |
| P4 | Destination prices can be compared for one target at a time, from another screen. | `APP/Views/Market/MarketIntelViews.swift:9-42` |
| P5 | No one-click "sell the hold"; seven controls per market row. | `APP/Session/MarketModels.swift:8-43` |
| P6 | Sidebar and inspector take 440–640 pt of width; the Market is in compact mode at the default size. | `MarketSectionView.swift:118-124` |
| P7 | The same action or number appears in up to four places under different names. | audit §6.2, §6.3 |
| P8 | Four tab styles, four card styles, seven radii, no spacing tokens, raw colours. | audit §6.4 |
| P9 | Police, pirates and traders fly identical ships; portraits have no faces. | audit §4 |

Pieter Spronck reached the same conclusion about the original: it "contains too many screens", buying and selling should be one "Cargo Trading" screen, and a "nerve centre" screen should reach every basic function in one tap (Spronck, *Palm Game Design*, 2001; see the research appendix).

### 2.3 Player tasks, ranked

Frequency is per full game. A full game is about 250–650 warps depending on ruleset and skill (the scenario bot reaches the moon on day 265, 336 and 657 in the three rulesets). Importance: H = failure loses money, ship or the game.

| Rank | Task | Times per game | Importance | Home |
|---|---|---|---|---|
| 1 | Read the situation on arrival (prices, cash, bays, fuel, hull, notices) | every warp | H | Bridge + status bar |
| 2 | Sell cargo | every warp, 1–3 goods | H | Bridge |
| 3 | Choose a destination by comparing prices in range | every warp | H | Bridge |
| 4 | Buy cargo | every warp, 1–2 goods | H | Bridge |
| 5 | Warp | every warp | H | Bridge |
| 6 | Resolve encounters | 1–5 per warp | H | Encounter page |
| 7 | Refuel | every 1–2 warps (or automatic) | H | Bridge |
| 8 | Repair | after fights (or automatic) | H | Bridge |
| 9 | Read the newspaper; answer a Special offer | most arrivals; ~40 times | M | Bridge notice → sheet |
| 10 | Check quest deadlines | weekly | M | Bridge notice → Quests |
| 11 | Plan a long route, find a system, use a wormhole | ~50 | M | Galactic Chart |
| 12 | Bank: loan, repay, insurance | ~20 | M | Bank |
| 13 | Equipment: buy, sell | ~15 | M | Equipment |
| 14 | Personnel: hire, fire | ~10 | L | Personnel |
| 15 | Shipyard: buy a ship, escape pod | ~6 | H | Shipyard |
| 16 | Commander Status: skills, record, reputation, worth | occasional | L | Commander Status |
| 17 | Options, save, load, retire | rare | L | menus, Options |

Ranks 1–5, 7 and 8 are the core loop and live on the Bridge with their controls. Rank 6 interrupts the loop and gets its own page. Rank 9–10 get a one-click notice on the Bridge. Everything else is a secondary page.

### 2.4 Core loop cost, today and after

Pointer only, docked, starting on the Bridge. A screen change is a page switch or a sheet.

| Step | Clicks today | Screen changes today | Clicks after | Screen changes after |
|---|---|---|---|---|
| Arrive, read the situation | 0–2 | 0–2 | 0 | 0 |
| Sell one good, all units | 2–3 | 1 | 1 (All) | 0 |
| Sell the whole hold (3 goods) | 5–7 | 1 | 1 (Sell All Cargo) | 0 |
| Buy one good, maximum | 2 | 0–1 | 1 (Max) | 0 |
| Refuel | 2 | 1 | 1 | 0 |
| Repair | 1 | 0 | 1 | 0 |
| Choose a destination and compare its prices | 2–4 | 1–3 | 1 per candidate (click on the chart) | 0 |
| Warp | 1–4 | 1–3 | 1 | 1 (transit) |
| Encounter action | 1 per action | 0 | 1 per action | 0 |
| **Uneventful loop: sell 2 goods, buy 1, refuel, compare 2 systems, warp** | **12–14** | **4–5** | **6** | **1** |

---

## 3. Design principles and design system

### 3.1 Principles

1. **The Bridge is home.** Arrival, launch and the Esc key all end there. Nothing needed for the core loop is anywhere else.
2. **Same elements at every size.** Resizing changes sizes, never the set of elements. Nothing on the Bridge scrolls, collapses, pages or hides.
3. **One click for a core action.** No double-click, modifier or context menu is ever the only way to do something.
4. **Show the decision, not the data.** A trade row puts what I hold, what I paid, what it sells for here, what it costs here and what it should fetch at the target side by side.
5. **Honest numbers.** A price for another system is an estimate or a memory and is always labelled as such. The interface never shows hidden state (UI-FAIR).
6. **Native frame, crafted interior.** Title bar, menu bar, shortcuts, sheets' behaviour, full screen and Settings are standard macOS. The game area inside the window uses the design system below.
7. **The original's words.** Terms come from Space Trader (§3.7).
8. **Never colour alone.** Every colour-coded state also has a symbol, text or shape.
9. **Rules decide, tables drive.** The interface reads the active `Ruleset`; it never branches on a ruleset id.

### 3.2 Window and scaling

| Item | Value |
|---|---|
| Minimum content size | **1200 × 680 pt** |
| Default content size | 1440 × 860 pt |
| Title bar | standard, with title and subtitle; **no toolbar** |
| Resizing | free; full screen supported |

**Why 1200 × 680.**
- **Width 1200.** The Bridge needs a 10-row cargo table with destination columns and four trade buttons per row (about 760 pt) beside a chart and target panel (about 400 pt), plus margins.
- **Height 680.** Ten 36 pt rows (the project's pointer-target minimum, which also suits Macs with touch displays), a system panel, the dock bar and the status bar need 680 pt (budget in §4.2).
- **It fits the smallest supported Mac.** macOS 27 supports the MacBook Neo, whose 13.0-inch panel is 2408 × 1506 pixels (Apple's specification page). At 2× that is 1204 × 753 pt (arithmetic; Apple does not publish the default scaled mode). 680 pt of content plus a title bar (about 28 pt) plus a menu bar (24 pt, or up to about 38 pt on a display with a camera housing) is 732–746 pt, which fits 753 pt with the Dock hidden or at the side. In full screen it fits with room to spare. 1.1.0's 720 pt plus toolbar did not fit that display.
- **The HIG gives no numeric minimum for a Mac window.** It asks that windows "adapt fluidly to different sizes" and that games avoid fixed layouts; §3.2's scale rule and the flexible regions do that.
- Sources and their verification status are in the research appendix §4.5.

- **UI-DS-001** {M21} The main window's content minimum is 1200 × 680 pt and its default is 1440 × 860 pt, defined once in `SceneMetrics`. `-PMWindowSize min|default` applies those two sizes.
- **UI-DS-002** {M21} **Interface scale.** `s = clamp(min(W / 1200, H / 680), 1.0, 2.0)`, rounded down to a multiple of 0.05, where W × H is the window's content size. Every font size, spacing token, control size and fixed panel dimension in the game area is multiplied by `s`. `s` is published in the environment (`\.pmScale`).
- **UI-DS-003** {M21} **Leftover space.** Space beyond `1200·s × 680·s` goes to the flexible regions named in each wireframe (on the Bridge: the chart and the cargo rows). No element is added or removed at any size.
- **UI-DS-004** {M27} **Text Size.** The in-app Text Size setting has five steps that set the lower clamp of `s`: Standard 1.0, Large 1.15, Larger 1.3, Extra Large 1.5, Largest 2.0 (the HIG asks for enlargement up to 200% where possible, and macOS has no Dynamic Type). A step raises the window minimum to `1200·floor × 680·floor`. A step whose minimum does not fit the main screen's visible frame is disabled with a help tag giving the reason; entering full screen or enlarging the window always remains a way to get larger text, because `s` follows the window. This replaces the 0.85–2.0 `textScale` range; a stored value maps to the nearest available step at or below it.

### 3.3 Colour

The game area uses one dark "console" palette in both system appearances; window chrome, menus, sheets' frames and Settings follow the system appearance. (Assumption: a cockpit display reads best dark, and one palette halves the visual QA. `-PMAppearance` still switches the chrome.)

Tokens live in `APP/Design/PMColor.swift` as static `Color` values. Views MUST use tokens; raw colour literals are banned outside `APP/Design/` and `APP/Map/MapStyle.swift` (UI-DS-021).

| Token | sRGB hex | Use |
|---|---|---|
| `space` | `#070A12` | game-area background |
| `panel` | `#111827` | panel fill |
| `panelRaised` | `#1A2436` | selected row, hovered control, key cap |
| `panelInset` | `#0C1220` | gauges' track, fields, table header |
| `hairline` | `#2A3650` | panel border, row separators |
| `strongLine` | `#5A6E94` | control borders, focus-adjacent lines |
| `textPrimary` | `#E8EEF8` | values, titles |
| `textSecondary` | `#A9B6CC` | labels |
| `textDisabled` | `#7C89A1` | disabled text |
| `accent` | `#E0B050` | brass: primary button, selection, target marker, focus ring |
| `profit` | `#5BD68A` | gain, safe, full |
| `loss` | `#FF7A6B` | loss, danger, illegal |
| `caution` | `#F5B942` | warning, low fuel, deadline near |
| `info` | `#6CB6FF` | neutral highlight, estimate tag |
| `rolePolice` | `#5AA0FF` | police badge |
| `rolePirate` | `#FF6B5E` | pirate badge |
| `roleTrader` | `#7FD1AE` | trader badge |
| `roleAlien` | `#B48CFF` | alien and special badge |

- **UI-DS-010** {M21} Contrast, computed by a unit test with the WCAG relative-luminance formula: `textPrimary` and `textSecondary` on `panel`, `panelRaised` and `panelInset` ≥ 7:1; every signal and role colour on `panel` ≥ 4.5:1; `textDisabled` on `panel` ≥ 4.5:1; `strongLine` and `accent` against `panel` ≥ 3:1. If a hex value in the table fails, adjust its lightness until it passes and record the new value in this table.
- **UI-DS-011** {M21} With Increase Contrast on, `hairline` is replaced by `strongLine`, `textSecondary` by `textPrimary`, and panel borders are 2 pt.
- **UI-DS-012** {M21} Every use of `profit`, `loss`, `caution` or a role colour is paired with a symbol or word from the `ColorSignal` catalogue (`APP/Accessibility/DisplayStyles.swift`), which is extended to list every pairing. A unit test iterates the catalogue and asserts each entry has a non-colour twin.

### 3.4 Type, spacing, shape, motion

**Type.** System font (SF Pro) only; numbers always `.monospacedDigit()`. Sizes at `s = 1`:

| Style | Size / weight | Use |
|---|---|---|
| `title` | 17 semibold | page title, system name |
| `panelTitle` | 11 semibold, uppercase, +0.6 tracking | panel headers, column headers |
| `body` | 13 regular | text, labels |
| `value` | 13 medium, monospaced digits | numbers |
| `valueLarge` | 15 semibold, monospaced digits | status-bar values, Warp button |
| `caption` | 11 regular | tags ("est.", "3 d"), help lines |

No text is smaller than 11 pt at `s = 1`. The newspaper keeps its serif (New York) masthead and headlines.

**Spacing.** `PMSpace`: 4, 8, 12, 16, 24 (× `s`). Panel padding 12. Gap between panels 12. Row gap inside a table 0 with a hairline.

**Shape.** Two radii only: 4 (controls, chips, key caps) and 8 (panels, sheets' inner cards). Borders 1 pt `hairline`.

**Pointer targets.** Every interactive element has a hit area with a short side of at least 36 pt × `s` (`PointerTarget.minimum`, UI-PTR-001 stays).

**Motion.** Hover and press: 120 ms ease-out. Page change: 200 ms cross-fade. Value change (cash, bays): 250 ms number roll. Nothing in the interface is longer than 350 ms except transit, combat effects and endings. With Reduce Motion: no cross-fades or rolls (instant), art holds a still frame. All animation sites are registered in `MotionPolicy` as today.

**Materials.** `.glassEffect` is not used in the game area. The source audit that allows it in three files is rewritten to allow it in none (UI-DS-024). System sheets and menus keep the system look.

- **UI-DS-020** {M21} Tokens exist as `PMColor`, `PMFont`, `PMSpace`, `PMRadius`, `PMMotion` in `APP/Design/`.
- **UI-DS-021** {M27} Source audit: under `APP/Views/` and `APP/Map/` (except `MapStyle.swift`) there is no `Color(red:`, `Color(.s`, `Color.red|green|blue|orange|yellow|purple|pink`, `.foregroundStyle(.red|.green|.orange|.yellow|.blue)`, no `.font(.system(size:`, and no `cornerRadius:` literal other than through `PMRadius`.
- **UI-DS-022** {M27} Source audit: no `.padding(` with a numeric literal under `APP/Views/`; padding uses `PMSpace`.
- **UI-DS-023** {M27} Source audit: `GroupBox`, `Form`, `NavigationSplitView`, `.inspector(` and `.toolbar` do not appear under `APP/Views/` except in `Views/Settings/`, `Views/About/` and `Views/Developer/`.
- **UI-DS-024** {M21} Source audit: `.glassEffect(` and `GlassEffectContainer` appear nowhere in the app target; `.popover(` stays banned.

### 3.5 Components

All in `APP/Design/Components/`. Every screen is built from these; a screen-specific view may compose them but MUST NOT restyle a panel, button, gauge or row by hand.

| Component | What it is | States |
|---|---|---|
| `PMPanel(title:)` | bordered panel with an optional `panelTitle` header and trailing accessory | — |
| `PMButton(style:)` | `.primary` (brass fill, dark text), `.standard` (raised fill), `.quiet` (text + hairline on hover), `.danger` (loss outline) | normal, hover, pressed, focused, disabled |
| `PMKeyCap` | small rounded label showing a key ("B", "⇧S", "⌘J") | — |
| `PMStat(label:value:)` | label over or beside a value, optional symbol and tone | tone: neutral, profit, loss, caution |
| `PMGauge(value:total:)` | horizontal bar with a text value; tone by thresholds given by the caller | — |
| `PMBadge(text:symbol:tone:)` | capsule with symbol and text | — |
| `PMRow` | 36 pt table row with selection, hover and separators | normal, hover, selected, disabled |
| `PMField` | numeric text field on `panelInset` | normal, focused, invalid |
| `PMNotice` | fixed-size button: symbol, short label, optional count or tag; has an "empty" appearance | active, empty |
| `PMDockButton` | symbol over label with a key cap and optional count badge | normal, hover, current, disabled |
| `PMPage(title:)` | secondary-page frame: title row with Back to Bridge, content area | — |
| `PMSegmented` | the one tab control (used by Shipyard, Logbook, High Scores) | — |
| `PMEmptyState` | symbol, one sentence, optional action | — |

- **UI-DS-030** {M21} Each component exists, has an accessibility identifier parameter, applies `PointerTarget.minimum`, uses the system focus effect when keyboard-focused (a custom 2 pt `accent` ring only where the system effect cannot draw, such as a `Canvas` selection), has a visible pressed state, and has a unit test that renders every state without clipping at `s` = 1.0, 1.3 and 2.0.
- **UI-DS-031** {M21} A disabled `PMButton` always carries a help tag with the reason from `ReasonText`; the initializer takes the reason so it cannot be omitted. The existing audit "every `.disabled` has a `.help`" stays.
- **UI-DS-032** {M27} Every interactive component instance has an `.accessibilityIdentifier` matching `AXID.pattern`, an accessibility label that does not depend on colour or position, and a help tag (§3.6).

### 3.6 Platform conventions (Apple HIG for macOS)

The HIG pages consulted, with what was verified, are in the research appendix §4. Requirements:

- **UI-HIG-001** {M27} **Menu bar.** Menus in this order: App, File, Edit, View, Trade, Game, Encounter, Window, Help. Titles and items are in title case; an item ends with "…" only when it needs more input before acting. Every command reachable by a button in the game area also has a menu item (the list is §4.15) with the same name, and both are enabled and disabled by the same `MenuRules` entry.
- **UI-HIG-002** {M27} **Reserved shortcuts** are never rebound: ⌘Q, ⌘W, ⌥⌘W, ⌘H, ⌥⌘H, ⌘M, ⌥⌘M, ⌘, (Settings), ⌘` , ⌘Tab, ⌃⌘F (full screen), ⌘?, ⌘., ⌘N/⌘O/⌘S/⇧⌘S/⌘P, ⌘Z/⇧⌘Z, ⌘X/⌘C/⌘V/⌘A, ⌘F/⌘G (Find only), ⌘Space, ⌥⌘D, ⇧⌘3/4/5, ⌘F5, ⌥⌘8. No binding uses Control as its only modifier. `KeyAudit` asserts no binding in `KeyBindingTable` collides with them or with another binding in the same context.
- **UI-HIG-003** {M27} **Full keyboard operation.** With the system's keyboard navigation on, Tab and ⇧Tab reach every control on every page in reading order (left to right, top to bottom, panel by panel); Space or Return activates; arrow keys move within the cargo table, the chart, segmented controls and lists; Esc goes back (§4.1). A UI test completes the whole core loop without the pointer (UI-BRG-041).
- **UI-HIG-004** {M27} **Help tags.** Every control has one. Wording follows the HIG: a brief phrase of at most 75 characters that says what the control does, starting with a verb, in sentence case, with no ending punctuation and without repeating the control's name; the shortcut follows in parentheses if there is one (for example "Buy as many as cash and bays allow (⇧B)"). A unit test checks length, ending punctuation and that the text differs from the control's label. A disabled control's help tag is the reason instead.
- **UI-HIG-005** {M27} **VoiceOver.** Every control and every value has a label; a value is read with its unit and its label ("Cash, 12,345 credits"); a cargo row is one element with a full sentence value and custom actions Buy, Buy Maximum, Sell, Sell All; drawn art has a label from `ArtSurfaceAccessibility`; the existing rotors stay and gain "Cargo Rows". Announcements stay with `Announcer`.
- **UI-HIG-006** {M27} **System settings are respected:** Reduce Motion, Reduce Transparency (already satisfied: no materials), Increase Contrast (UI-DS-011), Differentiate Without Colour (already satisfied by UI-DS-012, and patterns on gauges). `-PMA11y` keeps overriding them for tests.
- **UI-HIG-007** {M21} The window supports full screen and standard title-bar behaviour; closing the main window does not quit (unchanged); the app keeps one Settings window (⌘,) for app-wide settings and uses the Options page for per-game options.

### 3.7 Vocabulary

Use these words everywhere (labels, menus, help tags, VoiceOver, Help pages, identifiers' display names). The right column must not appear in user-visible strings after M27 (UI-DS-026 checks the catalog).

| Use | Not |
|---|---|
| Bridge | Dashboard, Home |
| Cargo (the trade region); Buy, Sell, Max, All, Dump, Jettison | Market (as a screen name), Buy Max / Take All variants |
| Shipyard | Ship Yard, Hangar |
| Equipment | Outfitter |
| Personnel | Crew (as a screen name), Roster |
| Bank | Finance |
| Commander Status | Inspector, Ship Status |
| Quests | Missions |
| Galactic Chart | Galaxy, Galaxy Chart, Map |
| Short-Range Chart | Mini Chart |
| Target System | Destination (as a label), Target card |
| Warp | Jump (except the singularity "Jump") |
| Track / Stop Tracking | Untrack |
| Fill Tank | Fill Up, Fill Fuel |
| Repair Hull | Repair (alone) |
| Costs of the Next Warp | Daily Costs, Total costs |
| Average price, "est." | Predicted price |
| Police Record, Reputation | Notoriety |
| bays, credits ("cr."), parsecs | slots, $, ly |

- **UI-DS-026** {M27} A unit test scans `Localizable.xcstrings` English values and fails on any of: "Outfitter", "Inspector", "Untrack", "Fill Up", "Fill Fuel", "Galaxy Chart", "Daily Costs", "Notoriety", "Buy Max", "Take All".

---

## 4. Screens

### 4.1 Navigation model

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ● ● ●   Cmdr. Jameson — Bridge                         (native title bar) │
├──────────────────────────────────────────────────────────────────────────┤
│ DOCK BAR    (navigation; always while a game is loaded)                   │
│ STATUS BAR  (always while a game is loaded)                               │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ GAME AREA: exactly one of                                                │
│   Bridge · a secondary page · Transit · Encounter · Game Over            │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

Both bars are at the **top**. The HIG for macOS says to avoid placing controls or critical information at the bottom of a window, because people often move windows so the bottom edge is off screen.

Three layers, and only three:

1. **Pages** fill the game area. The dock bar switches between them. Pages: Bridge (home), Shipyard, Equipment, Personnel, Bank, Commander Status, Quests, Galactic Chart, Logbook, Options.
2. **Interruptions** are sheets and confirmation dialogs from the existing presentation queue: newspaper, special-event narrative, arrival and arrest reports, trade in orbit, plunder, ship purchase review, Dump, Find System, New Game, Open, Retire, confirmations. One at a time, as today.
3. **Automatic pages** replace the game area while the engine phase demands it: Transit, Encounter, Game Over. The dock bar is disabled with the reason in its help tags.

**Dock bar** (left to right, with key caps):

| ⌘1 | ⌘2 | ⌘3 | ⌘4 | ⌘5 | ⌘6 | ⌘7 | ⌘8 | ⌘9 | ⌥⌘O |
|---|---|---|---|---|---|---|---|---|---|
| Bridge | Shipyard | Equipment | Personnel | Bank | Commander Status | Quests | Galactic Chart | Logbook | Options |

- **UI-NAV-001** {M21} The shell is `dock bar / status bar / game area` in a plain `VStack`; nothing is pinned to the bottom edge of the window. `NavigationSplitView`, the sidebar, the inspector and the toolbar are removed. `Section` gets the cases `bridge, shipyard, equipment, personnel, bank, status, quests, chart, logbook, options` with raw values kept for the surviving cases; stored values of renamed cases are mapped when read (`outfitter` → `equipment`, `crew` → `personnel`, `galaxy` → `chart`, `market` → `bridge`), and anything unknown maps to `bridge`.
- **UI-NAV-002** {M21} The dock bar shows all ten buttons at every window size, each with symbol, label and key cap on one line; the current page's button is marked by `accent` underline **and** a filled symbol (not colour alone). Badges: Personnel shows the number of mercenaries for hire here; Quests shows the number of open quests with a deadline of 5 days or less.
- **UI-NAV-003** {M21} Esc on a secondary page returns to the Bridge (after the existing Esc router levels: clear a field, close an overlay). Every secondary page has a visible "Bridge" back button at the left of its title row with help tag "Return to the Bridge (Esc)".
- **UI-NAV-004** {M21} After a warp ends (arrival), after a game loads and after New Game, the page is the Bridge. This replaces UI-ENC-055.
- **UI-NAV-005** {M21} During transit and encounters every dock button is disabled with the help tag "Unavailable in transit" / "Unavailable during an encounter"; the status bar stays live.
- **UI-NAV-006** {M21} A page never opens another page except through: the dock bar, a menu command, Back, or a link whose label names the destination page (for example "Open Personnel"). A link changes the page; it never also changes the target or other game state, except "Show on Galactic Chart", which selects that system on the chart.
- **UI-NAV-007** {M23} The window title is "Cmdr. ‹name›" and the subtitle is the page name (the HIG says not to title a window with the app name). Cash, day and system are no longer in the subtitle (they are in the status bar).
- **UI-NAV-008** {M24} The separate Galactic Chart window (⇧⌘M) stays, with the same content as the page.
- **UI-NAV-009** {M21} With no game loaded the window shows the Welcome view with no status bar or dock bar.
- **UI-NAV-010** {M23} A dock button whose page has nothing to offer here is still enabled and the page says why (for example Shipyard in a system that sells no ships shows the escape pod, the designer if a yard is present, and a `PMEmptyState` "No ships for sale in this system"). Content availability comes from the engine previews and `Ruleset` tables.

### 4.2 Bridge

Wireframe at the minimum size, 1200 × 680 pt (`s` = 1). Measures in points.

```
 0                                                                                                   1200
 ┌──────────────────────────────────────────────────────────────────────────────────────────────────┐ 0
 │ DOCK BAR   Bridge ⌘1 · Shipyard ⌘2 · Equipment ⌘3 · … · Logbook ⌘9 · Options ⌥⌘O           h 44 │
 │ STATUS BAR Castor · Day 42 │ Cash │ Debt │ Bays │ Fuel │ Hull │ Shields │ message          h 36 │
 ├──────────────────────────────────────────────────────────────────────────────────────────────────┤ 80
 │┌ A · SYSTEM INFORMATION ───────────────────────────────┐ ┌ C · SHORT-RANGE CHART ──────────────┐│
 ││ ┌────────┐ Castor                 Fuel ███████░░ 10/14 │ │            · Deneva                 ││
 ││ │ planet │ Size        Huge          [Fill Tank 8 cr.]  │ │      ○ Helena      ○ Frolix         ││
 ││ │112×112 │ Tech level  Renaissance  Hull ██████░░░ 79%  │ │   ○ Iralius   ◎ Esmee (target)      ││
 ││ │        │ Government  Pacifist State [Repair Hull 210] │ │  ○ Hades   ● Castor   ○ Antedi      ││
 ││ │        │ Resources   Nothing special                  │ │     ○ Lowry      ( range circle )   ││
 ││ └────────┘ Status      Drought  [News 1 cr.][Special]   │ │  → tracked: Utopia 34 parsecs       ││
 ││ Police ●●○○○○○ Few · Pirates ●○○○○○○ Min. [Hire 2][Quest 5 d]│                [Galactic Chart ↗] ││
 │└────────────────────────────────────────────────────────┘ └────────────────────────────────────┘│
 │┌ B · CARGO ─────────────────────────────────────────────┐ ┌ D · TARGET SYSTEM ─────────────────┐│
 ││ Bays 5/15 · 10 free · Cash to spend 830 cr.             │ │ Esmee     9 parsecs   [In range]    ││
 ││ Hold: here 180 · at Esmee 145 est. ▼35 [Sell All Cargo] │ │ [           WARP  ⌘J              ] ││
 ││ GOOD     HOLD PAID SELL   BUY STOCK TARGET    ±         │ │ (blocker note line)                 ││
 ││ Water      5   34  36 ▲2  38   47  29 est.  ▼9  [ ][Buy][Max][Sell][All]                       ││
 ││ Furs       0    —  233   251   47 227 est. ▼24  [ ][Buy][Max][Sell][All]                       ││
 ││ Food       …                                            │ │ [‹ Previous][Next ›][Track][Find…]  ││
 ││ Ore        …                                            │ │ Size       Huge     Mercenaries 0 cr││
 ││ Games      …                                            │ │ Tech level Medieval Insurance   0 cr││
 ││ Firearms ⚠ Illegal …                                    │ │ Government Military Interest    0 cr││
 ││ Medicine   …                                            │ │ Resources  Unknown  Wormhole tax 0cr││
 ││ Machines   …                                            │ │ Police ●●●●●●● Swarms  Total    0 cr││
 ││ Narcotics ⚠ Illegal …                                   │ │ Pirates ○○○○○○○ Absent              ││
 ││ Robots     …                                            │ │ Fuel after warp 5 parsecs           ││
 │└────────────────────────────────────────────────────────┘ └────────────────────────────────────┘│
 └──────────────────────────────────────────────────────────────────────────────────────────────────┘ 680
```

(Cargo rows and the summary lines stay inside region B; the long lines and the uneven panel edges are limits of the drawing. The budget table below is exact.)

**Size budget at 1200 × 680.** Outer margin 8, gap 8.

| Region | x | y | w | h | Flexible? |
|---|---|---|---|---|---|
| Dock bar | 0 | 0 | 1200 | 44 | width |
| Status bar | 0 | 44 | 1200 | 36 | width |
| A · System Information | 8 | 88 | 776 | 144 | width, height |
| B · Cargo | 8 | 240 | 776 | 432 | width and height (rows 36 → 44 max, × `s`) |
| C · Short-Range Chart | 792 | 88 | 400 | 280 | **width and height (takes most leftover)** |
| D · Target System | 792 | 376 | 400 | 296 | width |

- Cargo panel: 2 summary lines × 20 + header row 24 + 10 rows × 36 + padding 8 = 432. The summary and Sell All Cargo are **above** the rows, and Warp is at the top of the Target panel, so the most important controls are never at the window's bottom edge.
- Cargo columns (inner width 760): Good 104, Hold 40, Paid 52, Sell 60, Buy 56, Stock 40, Target 72, ± 56, actions 232 (quantity field 40, Buy 46, Max 46, Sell 46, All 42, gaps 12), column gaps 48.
- System Information (inner 760 × 128): the planet in a 112 × 112 square (it grows with the panel; `PlanetHero` fills any frame it is given), a facts column about 260 wide (name, five fact lines, one activity line), and a services column about 360 wide: the Fuel line and the Hull line (gauge with its text, then its button) and the four notice buttons in a 2 × 2 grid or one row, whichever passes the fit test.

These numbers are the starting budget. The implementer may move up to 24 pt between neighbouring regions or columns to make the layout tests pass, but MUST NOT remove, merge, abbreviate beyond the listed labels, or relocate an element.

**Leftover distribution** above the minimum (after scaling by `s`): horizontally, 60% to the right column and 40% to the left; vertically, the chart grows with the right column, the cargo rows grow to at most 44 pt × `s`, and what remains goes to the chart and the System Information panel equally.

#### System Information (region A)

| Element | Content | Source |
|---|---|---|
| Planet | the live planet, unchanged art | `PlanetHero` (protected) |
| Name | system name, `title` style | `currentSystem` |
| Facts | Size, Tech level, Government, Resources, Status (pressure in words, as the original's System Information shows it) | `currentSystem`, `Text/` helpers |
| Activity | Police and Pirates as 7 pips **and** a word (Absent … Swarms) | `PoliticalSystemSpec` |
| Fuel | `PMGauge` "Fuel 10/14 parsecs" + `Fill Tank ‹cost› cr.` | `DockServiceModel`, `.buyFuel` |
| Hull | `PMGauge` "Hull 79%" + `Repair Hull ‹cost› cr.` | `DockServiceModel`, `.repairHull` |
| Notices | four `PMNotice` buttons: **News** (label "News ‹cost› cr."; reads the newspaper in its sheet), **Special** (opens the special offer's narrative sheet), **Hire** ("Hire ‹n›", the number of mercenaries for hire; opens Personnel), **Quest** ("Quest ‹n› d", the nearest deadline; opens Quests). Each has a symbol, and its help tag gives the full sentence (for example "Crystal and 1 other are looking for work") | existing models |

- A notice with nothing to show keeps its place, in its empty state ("No special offer", "Nobody for hire", "No deadlines"), disabled, with the reason as its help tag. It is never removed. A newspaper already bought stays enabled as "News" so it can be read again.
- Fill Tank and Repair Hull spend what the player can afford, as today. Partial amounts are in the Trade menu ("Buy Fuel…", "Repair…"), which open a small amount sheet. A full tank or hull disables the button with the reason "Tank is full" / "Hull is at full strength".
- Gauge tone: fuel is `caution` when the target is out of range for lack of fuel; hull is `caution` below 50% and `loss` below 25%, each with a ⚠ symbol.

#### Cargo (region B)

Ten rows, one per `TradeItemType`, always in table order, always all ten.

| Column | Shows | Rule |
|---|---|---|
| Good | name; "⚠ Illegal" badge where the current system's politics forbid it; "★" with the word "Best buy" in the help tag and label when `TradeIntel.bestBuys` names it | names from `Text/GameNames` |
| Hold | units held | `MarketRow.held` |
| Paid | average price paid per unit, or "—" | `MarketRow.costBasisPerUnit` |
| Sell | sell price here, or "no trade"; when held, ▲/▼ and the difference to Paid | `MarketRow` |
| Buy | buy price here, or "not sold" | `MarketRow` |
| Stock | units for sale here | `MarketRow` |
| Target | price at the Target System from `TradeIntel.quote`: the number and a tag "est." (estimate) or "‹n› d" (remembered, age in days); "—" if not traded there | `ParsecInsights` only |
| ± | Target minus the reference price here, signed, with ▲/▼. Reference = Buy if the good is sold here, else Sell. Bold when positive **and** Stock > 0 (the original's rule) | computed in the row model |
| Quantity | `PMField`, empty means 1 | — |
| Buy | buys the quantity | `.buyCargo` |
| Max | buys `marketBuyCheck` maximum | `.buyCargo` |
| Sell | sells the quantity; reads **Dump** when the good cannot be sold here and Hold > 0 (opens the existing Dump sheet) | `.sellCargo` / dump flow |
| All | sells every unit held | `.sellCargo` |

Summary, two lines above the column headers, always present:
- Line 1: `Bays ‹used›/‹total› · ‹free› free` · `Cash to spend ‹cashToSpend› cr.` (cash after the reserve options, as the engine computes it).
- Line 2: `Hold: here ‹value› cr. · at ‹target› ‹value› est. ▲/▼‹difference›` and the button **Sell All Cargo ‹proceeds› cr.**

Rules:
- **UI-BRG-001** {M22} The Cargo region shows exactly ten rows and the two summary lines at every window size and in every ruleset, with no scroll view.
- **UI-BRG-002** {M22} Buy, Max, Sell (or Dump) and All are separate visible buttons in every row. A button that cannot act is disabled with the engine's reason (`marketBuyCheck` / `marketSellCheck` → `ReasonText`) in its help tag.
- **UI-BRG-003** {M22} Buy and Sell send the quantity as typed; the engine's rejection, if any, appears in the status bar message slot. Max and All take their quantity from the engine checks, never from view arithmetic.
- **UI-BRG-004** {M22} **Sell All Cargo** sends `.sellCargo` for each held good that has a sell price here, in table order, and stops at the first rejection or pending decision. It is disabled with a reason when nothing can be sold. It adds no rule: the resulting state equals the same commands sent one by one (unit test compares states).
- **UI-BRG-005** {M22} The Target and ± columns always describe the current Target System and update in the same frame the target changes. With no valid quote they show "—". A number from another system is never shown without its "est." or age tag, and the Target column header's help tag says "Average price at the target. Estimates carry no guarantee" (the original's disclaimer).
- **UI-BRG-006** {M22} All intel numbers come from `ParsecInsights` (`TradeIntel.quote`, `bestBuys`, `holdValue`) with the active game's `Ruleset`; the row model contains no price formula. A test builds the Bridge model for one fixture per ruleset (`Tests/Fixtures/saves/v1/{modern,windows201,palm122}.parsecsave`) and compares every Target cell with `TradeIntel.quote`.
- **UI-BRG-007** {M22} Row selection: clicking a row or ↑/↓ selects it (`panelRaised` fill **and** a 3 pt `accent` bar at the left). Keys act on the selected row: B buy quantity, ⇧B Max, S sell quantity, ⇧S All; typing digits edits the row's quantity.
- **UI-BRG-008** {M22} The row context menu (on the whole row) offers Buy, Buy Maximum, Sell, Sell All, Dump…, Price Details…; every item also exists as a button or menu-bar command. **Price Details…** opens a sheet with the existing "Why this price?" breakdown and the price-history sparkline for that good.
- **UI-BRG-009** {M22} Illegal goods show the ⚠ symbol and the word "Illegal", not colour alone.

#### Short-Range Chart (region C)

The existing `GalaxyMapView(scope: .miniChart)`, restyled through `MapStyle` only.

- **UI-BRG-010** {M22} Shows every system the fixed zoom reaches, the range circle, wormholes, the current system, the Target System (brass reticle **and** the label "target"), the tracked system as an edge arrow with name and distance, and a brass diamond on systems named by `TradeIntel.bestDestinations`.
- **UI-BRG-011** {M22} One click on a system makes it the Target System (`.selectTarget`), in range or not. Hover shows the existing hover card. Arrow keys move the selection between systems when the chart has focus; Return on the chart moves focus to Warp.
- **UI-BRG-012** {M22} The "Galactic Chart" button in the chart's corner opens the Galactic Chart page centred on the Target System.
- **UI-BRG-013** {M22} A system reachable only through a wormhole from here is marked with the wormhole symbol and can be selected; the Target panel then shows "via wormhole".

#### Target System (region D)

| Element | Content |
|---|---|
| Header | name; `‹n› parsecs`; a `PMBadge`: "In range", "Out of range", "Via wormhole" or "Current system" |
| Facts | Size, Tech level, Government, Resources ("Unknown" until visited), Police and Pirates as pips and a word |
| Costs of the Next Warp | Mercenaries, Insurance, Interest, Wormhole tax, Total (`dailyCosts(to:)`) |
| Fuel | "Fuel after warp ‹n› parsecs" |
| Buttons | **Warp** (⌘J), `.primary`, full width, directly under the header; then Previous (⌘[), Next (⌘]), Track / Stop Tracking (⌘T), Find… (⌘F) |

- **UI-BRG-020** {M22} All elements are present at every size. When the target is the current system (the engine's state after arrival, `warpSystem == currentSystem`), the panel shows that system with the badge "Current system", cost lines of 0, and Warp disabled with the reason "Select a target system on the chart"; it is never empty.
- **UI-BRG-021** {M22} Warp is disabled with the engine's blocker (`warpBlocker()` / `warpTargetPreview.blocking`) as its help tag and as a one-line `caution` note under the button (text, not only a tag; its line is reserved so nothing moves).
- **UI-BRG-022** {M22} Warp is the only Warp control in the game area of the Bridge. Other entry points are the menu command and the Galactic Chart's own target strip. Return does not trigger Warp unless Warp has focus (the existing rule).
- **UI-BRG-023** {M22} Facts shown for the target are limited to public facts and known resources (`IntelSnapshot.publicSystem`).

#### Bridge layout proofs

- **UI-BRG-030** {M22} **No scroll containers.** Source audit: files under `APP/Views/Bridge/` contain none of `ScrollView`, `List(`, `Table(`, `Form`, `LazyVStack`, `LazyVGrid`, `DisclosureGroup`, `TabView`, `.sheet(`, `ViewThatFits`, `.lineLimit(` with truncation allowed on a value, or `.minimumScaleFactor(`.
- **UI-BRG-031** {M22} **Element manifest.** `BridgeManifest.all` lists the accessibility identifiers of every Bridge element: the 4 regions, 10 rows × (9 cells + 5 controls), 2 summary lines and Sell All Cargo, system facts (8), 2 gauges, 2 service buttons, 4 notices and their buttons, the chart and its button, the target facts (6), badge, 5 cost lines, fuel line, 5 buttons. The spec file lists them; identifiers follow `bridge.‹region›.‹element›[.‹good›]`.
- **UI-BRG-032** {M22} **Fit test (unit, hosted in the app).** `BridgeLayoutTests` renders the Bridge in an `NSHostingView` for every combination of: sizes 1200 × 680, 1204 × 700, 1280 × 800, 1440 × 860, 1728 × 1050, 2056 × 1290, 2560 × 1380; the three rulesets; and five states (new game; full hold with all ten goods held and 8-digit cash; in debt with insurance and two mercenaries; a wormhole system with a tracked system and an out-of-range target; all four notices active). Frames are collected through a preference key written by a `.layoutProbe(id)` modifier. The test asserts for every combination:
  1. every manifest identifier reports a frame (nothing missing);
  2. every frame has width and height > 0 and lies fully inside its region's frame, which lies fully inside the game area;
  3. the four regions, the rows, and the controls within a row do not overlap;
  4. every text probe's laid-out size is at least its ideal size at unlimited width (nothing truncated, wrapped beyond its line budget or scaled down);
  5. the hosting view contains no `NSScrollView` in its subview tree;
  6. every control's frame has a short side ≥ 36 × `s`.
- **UI-BRG-033** {M22} **Fit test (XCUITest).** At `-PMWindowSize min` and at 1728 × 1050: every manifest identifier `exists`, is inside the window frame, every button `isHittable`, and `app.windows["main"].scrollViews.count == 0` on the Bridge. Repeated with Text Size Large when the screen allows it.
- **UI-BRG-034** {M22} **Long strings.** The fit test also runs with the longest system name, good name, government name and resource name of each ruleset's tables, and with the pseudo-localization (double-length) variant; assertion 4 must hold.
- **UI-BRG-035** {M22} Resizing never changes the manifest: the set of identifiers found at 1200 × 680 equals the set at 2560 × 1380.
- **UI-BRG-036** {M22} The window cannot be made smaller than the minimum (UI test drags the corner and asserts the size).

#### Bridge flows

- **UI-BRG-040** {M22} **Core loop without leaving the Bridge (XCUITest, pointer).** From a seeded docked game with cargo: Sell All Cargo → Max on a good → Fill Tank → click a chart system → read its Target cells → click another → Warp. Asserts the page identifier stays `page.bridge` until Warp, and that the click count is ≤ 6.
- **UI-BRG-041** {M27} The same loop with the keyboard only.
- **UI-BRG-042** {M22} On arrival a one-line summary appears in the status bar's message slot ("Arrived at Esmee. 2 encounters. Hull −21"), and clicking it opens the full arrival report. Critical reports (arrest, escape pod, meltdown) still open as sheets. The setting "arrival report style" keeps its two values; "sheet" opens the full report automatically.

### 4.3 Status bar

```
┌───────────────────────────────────────────────────────────────────────────────────────────────────┐
│ ◉ Castor · Day 42 │ Cash 12,345 cr. │ Debt 0 cr. │ Bays 5/15 │ Fuel 10/14 │ Hull 79% │ Shields 100% │ ⓘ Sold 5 Water for 180 cr. │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Slot | Format | Tone |
|---|---|---|
| Location | symbol + system name · `Day n` (in transit: "→ ‹target›, ‹n› clicks") | — |
| Cash | `Cash 12,345 cr.` grouped digits, `valueLarge` | — |
| Debt | `Debt 0 cr.`; `loss` + ⚠ when > 0 | loss |
| Bays | `Bays used/total` | `caution` + ⚠ when full |
| Fuel | `Fuel n/tank` (parsecs) | `caution` + ⚠ when it cannot reach the target |
| Hull | `Hull n%` | caution < 50, loss < 25, each with ⚠ |
| Shields | `Shields n%`, or `Shields none` | — |
| Message | the most recent event or rejection, one line; click opens the Recent Events overlay | rejection = `caution` + ⚠ |

- **UI-SB-001** {M21} The status bar shows exactly these eight slots, in this order, on every page and during transit and encounters, spanning the full window width. Nothing else is added to it. Slots never appear or disappear; a value that does not apply shows its zero form ("Debt 0 cr.", "Shields none").
- **UI-SB-002** {M21} Labels are words, not icons alone; every value has a help tag naming it and where to change it (for example "Cargo bays in use. Trade on the Bridge").
- **UI-SB-003** {M21} The seven value slots never truncate at any supported size with 8-digit cash and debt; the message slot takes the remaining width and may truncate with an ellipsis, its full text being in the help tag, the overlay and VoiceOver.
- **UI-SB-004** {M21} A rejection stays in the message slot for 4 s and is announced to VoiceOver; then the latest event returns (existing behaviour).
- **UI-SB-005** {M21} Police Record, Reputation, skills, net worth and the galaxy code are **not** in the status bar; they are on Commander Status.

### 4.4 Secondary page template

```
┌ DOCK BAR · STATUS BAR ────────────────────────────────────────────────────┐
│ [‹ Bridge]   Shipyard                                    (page actions)   │  title row, h 44
│ ┌ panel ───────────────────────────┐ ┌ panel ───────────────────────────┐ │
│ │                                  │ │                                  │ │  content: a grid of PMPanels,
│ │                                  │ │                                  │ │  max width 1400·s, centred
│ └──────────────────────────────────┘ └──────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────┘
```

- **UI-PG-001** {M23} Every secondary page is a `PMPage`: Back button, title in `title` style, optional page actions at the right, then panels. Content width is capped at 1400 × `s` and centred. A page's content may scroll vertically as a whole only if its content cannot fit (lists such as the Logbook); panels themselves do not scroll, except list panels named below.
- **UI-PG-002** {M23} Each page opens with keyboard focus on its first control, restores its last selection during a session, and has an identifier `page.‹name›`.
- **UI-PG-003** {M23} Every page reads its content from the existing `…Model.make(state:)` types; a page shows only what its engine preview offers under the active ruleset (for example the Designer panel appears only when `designQuote` is available here).

### 4.5 Shipyard (⌘2)

`PMSegmented`: **Ships** | **Designer** (the second only where a yard is present).

- Ships: left, a list panel of ships for sale (`shipsForSale`), each row: small ship portrait in the player's livery, name, price after trade-in, blocker; right, a detail panel for the selected ship: large portrait, a comparison table "Current ship | Selected" (bays, weapon, shield and gadget slots, crew quarters, fuel, hull, with ▲/▼ per line), what is transferred or lost, and **Buy Ship…** (opens the existing purchase review sheet). Below: a Services panel: **Escape Pod** (price, Buy or "Installed") and a link "Open Bank" for insurance.
- Designer: the existing form rebuilt from components, with the live ship portrait.
- **UI-PG-010** {M23} Selecting is one click; buying is the button; double-click is only an accelerator. The Compare toggle is removed (the comparison is always shown).

### 4.6 Equipment (⌘3)

Three panels side by side, **Weapons**, **Shields**, **Gadgets**. Each: "Installed" slot tiles (item, glyph, sell price, **Sell**; or "Empty slot") then "For sale" rows (glyph, name, power or effect, price, **Buy**, blocker). Under them one panel with the player's ship drawn large, so a purchase visibly appears on the hull.

- **UI-PG-020** {M23} Buy and Sell are buttons; drag and drop stays as an accelerator. The 280 pt detail form is removed; item details are in each row and its help tag.

### 4.7 Personnel (⌘4)

- Left panel **Crew Quarters**: the commander and each quarter: portrait (96 pt), name, four skills as labelled bars with numbers, daily wage, **Fire**; empty quarters shown as "Vacant"; passengers (Jarek, Wild, the Princess) with their portraits.
- Right panel **For Hire**: the same card with **Hire** and the blocker.
- Bottom panel **Effective Skills**: the existing table.
- **UI-PG-030** {M23} Police Record, Reputation and kills are removed from this page (they are on Commander Status).

### 4.8 Bank (⌘5)

Three panels: **Loan** (debt, maximum loan, interest rule in words, amount field with slider, **Borrow**, **Repay**, **Repay All**), **Insurance** (ship value, no-claim as a gauge with percent, daily premium, **Buy Insurance** / **Stop Insurance**, the escape-pod requirement as a blocker), **Costs of the Next Warp** (the same five lines as the Target panel, from the same model).

### 4.9 Commander Status (⌘6)

Replaces the inspector. Four panels:
- **Commander**: portrait (128 pt), name, difficulty, day, the four skills "base (effective)", Police Record and Reputation as word and score, kills (pirate, trader, police), galaxy code with **Copy**.
- **Ship**: the player's ship (large), type and name, hull and shield gauges, installed weapons, shields and gadgets with glyphs, empty slots, escape pod, tribbles count if any.
- **Finances**: cash, debt, net worth, insurance and no-claim, **Show Statistics** (link "Open Logbook").
- **Cargo and Special Cargo**: ten goods with units and average cost; special cargo lines (artifact, reactor, …) as the engine exposes them.
- **UI-PG-040** {M23} The page shows every field the 1.1.0 inspector showed (a test compares against `InspectorModel`). The "Show Commander Status" App Intent opens this page.

### 4.10 Quests (⌘7), Logbook (⌘9), Options (⌥⌘O)

- **Quests**: one panel per open quest (title, the next step in one sentence, system link "Show on Galactic Chart", deadline as "‹n› days left" with a gauge and ⚠ at ≤ 5), then a list panel **Completed**, always expanded (no disclosure).
- **Logbook**: `PMSegmented` Captain's Log | Statistics | Achievements; content as today, rebuilt from components. The log is a list panel and may scroll.
- **Options**: the per-game options as panels (On Arrival, Newspaper, Tracking, Money, Always Ignore, Combat), each option a labelled toggle or field with a one-line explanation; **Save as Defaults**, **Load Defaults**; changes apply immediately through `.setOptions` (no OK/Cancel). App-wide settings stay in the Settings window (⌘,).
- **UI-PG-050** {M23} Options that a ruleset does not have are not shown; the list comes from the ruleset's option flags.

### 4.11 Galactic Chart (⌘8)

The existing map fills the page content. Its HUD is rebuilt from components (no glass):

```
┌ [‹ Bridge]  Galactic Chart                         [Find… ⌘F] [Fit Range] [Fit Galaxy] [− +] ┐
│ ┌ FILTERS & HEATMAP ┐                                              ┌ SELECTED SYSTEM ──────┐ │
│ │ ☐ Visited …       │                 (map canvas)                 │ name, facts, activity │ │
│ │ Heatmap: Off ▾    │                                              │ Average prices (10)   │ │
│ │ LEGEND            │                                              │ [Set as Target][Track]│ │
│ └───────────────────┘                                              │ [Plot Route]          │ │
│ ┌ ROUTE ────────────────────────────────┐ ┌ TARGET ─────────────────┴───────────────────┐ │
│ │ hops, totals, [Clear]                 │ │ Esmee · 9 parsecs · costs 0 cr.   [ WARP ]   │ │
│ └───────────────────────────────────────┘ └──────────────────────────────────────────────┘ │
```

- **UI-PG-060** {M24} Clicking a system selects it and fills the Selected System panel, including the ten average prices from `TradeIntel.quote` with their tags (this replaces the "Find Prices" sheet and the pinned card). **Set as Target** changes the Target System; selecting alone does not. (This differs from the Short-Range Chart, where one click sets the target, because the Galactic Chart is for looking around.)
- **UI-PG-061** {M24} One search: the Find System sheet (⌘F everywhere, ⌥⌘F kept as an alias). The inline map search is removed; the filters stay in the left panel. The cheat-code entry through Find stays.
- **UI-PG-062** {M24} Wormholes, tracking (Track / Stop Tracking button, and ⌥-click as an accelerator), Plot Route, heatmaps, legend, zoom, the singularity **Jump…** button (only where the engine offers it) and the keyboard map keys keep their behaviour.
- **UI-PG-063** {M24} MAP-097 and the intel fairness tests stay green unchanged.

### 4.12 Transit

Full game area: the transit scene, "En route to ‹target›", the 20-segment click track with the current click, the player's ship in its livery, **Skip** (Return or Esc). Status bar live, dock bar disabled.

### 4.13 Encounter

```
┌ DOCK BAR (disabled) · STATUS BAR (hull and shields live) ───────────────────────────────────┐
│ At 15 clicks from Kira you encounter a pirate Bumblebee.              ☠ PIRATE  (badge)      │
│ Your opponent attacks.                                                                       │
│ ┌ YOU · Gnat ─────────────────────────────┐   ┌ OPPONENT · Bumblebee ─────────────────────┐ │
│ │                                         │   │                                           │ │
│ │            (ship, player livery)        │   │          (ship, pirate livery)            │ │
│ │                                         │   │                               ┌portrait┐  │ │
│ │ Hull    ███████░░░ 79%                  │   │ Hull    ██████████ 99%        │(famous │  │ │
│ │ Shields none                            │   │ Shields none                  │captain)│  │ │
│ │ Weapons  Pulse laser                    │   │ Weapons  2 visible            └────────┘  │ │
│ └─────────────────────────────────────────┘   └───────────────────────────────────────────┘ │
│ [Attack A] [Flee F] [Surrender S]      [Resolve R] [Stop Esc] [☑ Auto-repeat ⌥A]             │
│ ┌ COMBAT LOG (latest at the top; list panel) ────────────────────────────────────────────────┐│
│ │ R1  You missed the pirate ship. The pirate ship hits you. (−21 hull)                       ││
│ └────────────────────────────────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

- **UI-ENC-200** {M25} Layout, top to bottom: intro lines and role badge; two ship panels that take 55% of the height; the action bar, full width; the combat log, so the controls never sit at the window's bottom edge. No floating bar, no empty band.
- **UI-ENC-201** {M25} The action bar shows exactly the actions `encounterPreview.actions` offers, each a `PMButton` with a `PMKeyCap` showing its key from `EncounterKeys`; the default action (`defaultAction`) is `.primary` and takes Return; a rejected action is disabled with its reason. Resolve, Stop and Auto-repeat appear under the conditions `canAutoRepeat` / `canStop` give, as today.
- **UI-ENC-202** {M25} The role badge shows a symbol **and** a word: Police, Pirate, Trader, Alien, Special (`EncounterBadge`), in the role colour.
- **UI-ENC-203** {M25} The opponent's ship is drawn with its role livery and installed equipment (§5.1). The opponent panel lists only what the 1.1.0 encounter view and tactical readout already show (hull percent, shield percent, and the tactical readout lines when that setting is on).
- **UI-ENC-204** {M25} A famous captain's encounter shows that captain's portrait (§5.2) in the opponent panel. Other opponents have no portrait.
- **UI-ENC-205** {M25} Plunder, Trade in Orbit and Make Room stay sheets, rebuilt from components, each with one row per good and the same Quantity / Max / All vocabulary as the Cargo region.
- **UI-ENC-206** {M25} Combat effects still aim at `ShipArtLayout.frame`; hits, misses, shield flashes and destruction have a text line in the log for each visual effect (no information only in animation).
- **UI-ENC-207** {M25} Every existing encounter requirement that is not about layout (UI-ENC IDs on behaviour, auto-repeat timing, deferred decisions, tribbles) stays and stays tested.

### 4.14 Welcome, New Game, Game Over, sheets

- **Welcome**: the starfield backdrop and wordmark, and a panel with Continue, New Game…, Open Saved Game…, Import…, Quick Start, and a Recent Games list panel. Components and tokens only.
- **New Game**: the six-step wizard becomes one sheet with three panels visible at once (Commander: name, portrait preview that changes with the name, difficulty; Skills: the four steppers with points left; Rules: ruleset with a one-line description each, Modern preselected, galaxy code field). **Start Game** is disabled with a reason until valid. Assumption: the wizard's steps existed for explanation only; no option is dropped.
- **Game Over**: the 16:9 ending scene (§5.3), then score, high-score line, the career card with the commander's portrait, and Main Menu / High Scores / Share / New Game….
- **Sheets** (newspaper, narrative, reports, purchase review, Dump, amount sheets, Find, Open, Retire, cheat console, confirmations): keep their flows; inner content rebuilt from components; default and cancel keys from `SheetKeys`.
- **UI-PG-070** {M26} After M26 no view under `APP/Views/` uses a pre-revamp container or style (the audits UI-DS-021…023 enforce this at M27; M26 removes the last users).

### 4.15 Menu bar

| Menu | Items (shortcut) |
|---|---|
| App | About Parsec Merchant, Settings… (⌘,), Hide, Quit |
| File | New Game… (⌘N), Quick Start, Open Saved Game… (⌘O), Open Recent ▸, Save (⌘S), Save As… (⇧⌘S), Revert to Autosave, Import…, Export… (⇧⌘E), Close Game |
| Edit | Undo/Redo/Cut/Copy/Paste/Select All (system), Find System… (⌘F) |
| View | Bridge (⌘1) … Logbook (⌘9), Options (⌥⌘O), Galactic Chart Window (⇧⌘M), Zoom In (⌘+), Zoom Out (⌘−), Fit Range (⌘0), Recent Events (⌘E), Enter Full Screen (system) |
| Trade | Buy (B), Buy Maximum (⇧B), Sell (S), Sell All (⇧S), Sell All Cargo (⌥⌘S), Dump…, Price Details… (⌘I), Buy Fuel…, Fill Tank (⇧⌘F), Repair…, Repair Hull (⇧⌘R) |
| Game | Warp (⌘J), Previous Target (⌘[), Next Target (⌘]), Track Target / Stop Tracking (⌘T), Plot Route…, Jump… (singularity), Read Newspaper (⇧⌘N), Retire… |
| Encounter | the existing items and keys |
| Window | Minimize (⌘M), Zoom, Parsec Merchant, Galactic Chart, High Scores |
| Help | Parsec Merchant Help (⌘?), How Prices Work, Keyboard Shortcuts, Credits & License, GitHub Project |

- **UI-NAV-011** {M27} The menu bar matches this table; single-letter Trade keys act only when no text field has focus and the Bridge is the page. `KeyAudit` finds no conflict. The Help "Keyboard Shortcuts" page is generated from `KeyBindingTable` as today.
- **UI-NAV-012** {M27} Help pages (`APP/Resources/Help/*.md`) are rewritten for the new screens and vocabulary; `l10n-check.sh` still requires one page per `HelpTopic`.

### 4.16 Fair information

- **UI-FAIR-001** {M22} Source audit over `APP/Views/`, `APP/Design/` and `APP/Session/*Models.swift`: for systems other than the current one, views read only through `IntelSnapshot`, `IntelBook`, `TradeIntel`, `warpTargetPreview`, `dailyCosts(to:)` and the existing map snapshot. The identifiers `.pressure`, `.specialResource`, `.tradeItems`, `.countDown`, `.specialEvent` and `.newspaper` (as opposed to `newspaperPreview`) do not appear in those files except on `currentSystem` in an allowlist kept in the test.
- **UI-FAIR-002** {M22} The existing fairness tests (INT-001…023, MAP-097) stay unchanged and green.

---

## 5. Procedural art

All of §5 is drawn in code in `ParsecArt`, deterministic, with no images, no `Date`, no system randomness (ART-001 stays). New randomness uses `ArtRandom` / `ArtSeed` (frozen files; call, do not edit).

### 5.1 Ships

**Look.** A believable working spacecraft seen from above (plan view), nose toward the opponent: built from functional modules on a structural spine, lit by one fixed key light from the upper left, flat-shaded in three tones per surface with panel lines. No cartoon outlines, no wings for show, no faces, no insect anatomy (ART-087 stays).

**Inputs.** `ShipArtInput` keeps its fields and gains `role: ShipRole` and `liverySeed: UInt64`. Geometry depends only on statistics and installed equipment, never on the ship's name or type id. Names of the public entry points stay (`ShipArt`, `ShipArtInput`, `ShipArtLayout.frame`, `ShipSilhouette`, `ShipArtEmblem`, `ShipScaleMode`) so call sites keep compiling; the generator behind them is replaced (new files under `PA/Ships2/`, old `PA/Ships/` generator files deleted once nothing calls them).

**Statistics → geometry.**

| Statistic | Module | Rule |
|---|---|---|
| Size class | overall length and beam | length factor tiny 0.45, small 0.55, medium 0.68, large 0.82, huge 1.00 of the frame in `.relative` mode; `.fit` fills the frame |
| Crew quarters | pressurised habitat segments with windows, at the nose | one segment per quarter (1–3) |
| Cargo bays | container blocks on the spine, in rows of two | `ceil(bays / 5)` blocks, 0 bays → none, at most 12 |
| Fuel tanks | two cylindrical propellant tanks beside the spine | tank length proportional to `fuelTanks / 20` |
| Hull strength | armour plates over the habitat and engine block, and outline weight | `clamp(hullStrength / 25, 1, 12)` plates |
| Size class | engine cluster | nozzles: 1, 1, 2, 2, 3 for tiny…huge; bell size grows with class |
| Shield slots | radiator pairs (black, edge-on) | `1 + shieldSlots` pairs |
| Weapon slots | hardpoints on the forward hull | one mount per slot; empty slot = capped mount |
| Shield slots | emitter sockets around the hull | one per slot; empty = bare socket |
| Gadget slots | utility mounts aft of the habitat | one per slot; empty = blank plate |

**Installed equipment is visible.**

| Item | Drawn as |
|---|---|
| Pulse laser | short single barrel |
| Beam laser | long single barrel |
| Military laser | twin barrels on a turret ring |
| Morgan's laser | oversized barrel with cooling coils |
| Photon disruptor | forward dish emitter |
| Quantum disruptor | ring emitter |
| Energy / Reflective / Lightning shield | small dome / mirrored plate / spiked coil at an emitter socket |
| Extra cargo bays | one extra container pod in a contrasting colour |
| Auto-repair system | folded manipulator arm on a cradle |
| Navigating system | dish antenna |
| Targeting system | sensor mast with a lens |
| Cloaking device | four dark vanes; when `cloaked`, the ship is drawn as a dashed shimmer outline |
| Fuel compactor | toroidal tank ring around the spine |
| Hidden cargo bays | **nothing** (they are hidden) |

Existing overlays stay: scorch by hull fraction, sparks when disabled, shield bubble by `ShieldDisplay`, engine plume by phase, navigation lights.

**Livery.** `ShipLivery.make(role:seed:)` returns: base colour, secondary colour, accent colour, pattern, marking, wear.

| Role | Used for | Visual language |
|---|---|---|
| `player` | the commander's ship everywhere | clean two-tone hull, one **brass** accent stripe, a registry mark; wear ≤ 0.3. Seed: `ArtSeed.of(gameSeed, shipType)` mixed with the commander's name hash. |
| `police` | police encounters | white or pale grey hull, a **blue-and-white checker band** across the beam, a shield insignia, two blue beacons that blink (steady with Reduce Motion); wear ≤ 0.2. The band and insignia are identical on every police ship; seeds vary panel layout, unit marking and wear. |
| `pirate` | pirate encounters, Scorpion | dark matte hull (charcoal, rust, oxblood), at least three mismatched salvage panels, jagged red slash marks, no registry, tally marks; wear ≥ 0.6. |
| `trader` | trader encounters, Marie Celeste | mid-tone company colours from a seeded palette of 12 hue families, multi-coloured containers, a large registry block; wear 0.2–0.6. |
| `famousCaptain` | Ahab, Conrad, Huie | three fixed liveries, one per captain, each with a gold command stripe. |
| `alien` | Mantis | not a human ship: asymmetric, organic-crystalline segments, iridescent green-violet, no markings, no containers. Fittings are still shown, in alien form. |
| `special` | Space Monster, Dragonfly, Scarab, bottle | fixed designs below. |
| `yard` | Shipyard listings | the **player's** livery (you are looking at what you would fly). |

Patterns (seeded, not police): nose cap, beam band, twin stripes, panel blocks, tail chevron, spine line. Markings are abstract bar-codes and geometric registry blocks, never letters or digits (no text to localize, no fake script). Wear adds faded panels, chipped edges, soot behind thrusters and replaced panels.

**Special ships and objects.**

| Subject | Design |
|---|---|
| Space Monster | a creature, not a vessel: segmented body, tendrils, bioluminescent nodes; no modules. |
| Dragonfly | stolen prototype: needle hull, test-flight orange-and-white panels, oversized shield emitters (it has 3 shield slots). |
| Scarab | hull-hardened raider: a heavy faceted dark shell covering most modules. |
| Scorpion | the kidnapper's warship: pirate role with a fixed black-and-red livery. |
| Mantis | alien role (above). The Gemulon invaders use it too. |
| Marie Celeste | a trader hull with every light off, no plume, an open cargo hatch and a slow tumble (static with Reduce Motion). |
| Bottle | a drifting sealed canister-bottle with a note; an object, drawn at object scale. |
| Cargo canister | the scooped container from the trader livery set. |
| Custom (Designer) ships | the same generator from the designed statistics, in the player's livery. |

**Seeds and uniqueness.**

- Opponent seed: `ArtSeed.of(gameSeed, days, encounter.clicks, encounterType, opponent.type)`. It uses saved state only, so a reloaded encounter looks the same, and it does not change between rounds. Nothing is added to `GameState` or the save.
- Livery signature: `(role, pattern, baseHue ÷ 15°, accentHue ÷ 15°, wear ÷ 0.25, marking id)`.
- **Never the player's twin:** if an opponent's ship type equals the player's and its livery signature equals the player's, or its base hue is within 40° of the player's base hue, the generator re-rolls with `seed &+ 1` (up to 16 times), then forces the base hue to the player's + 180°. Police, alien and special liveries cannot equal the player's by construction (the player palette excludes police white-and-checker).

Requirements (spec file `docs/specs/ART-SHIP.md`):

- **ART-SHIP-001** {M20} Every `ShipType` (17) and every ruleset's table renders without error at 96, 160 and 240 pt in both scale modes; rendering twice gives identical pixels (fingerprint).
- **ART-SHIP-002** {M20} Geometry is a pure function of `ShipArtStats` and the equipment lists: two inputs that differ only in `kind` produce identical geometry (special designs excepted).
- **ART-SHIP-003** {M20} Monotonic statistics: with everything else equal, more cargo bays never gives fewer container blocks; likewise crew quarters → habitat segments, hull strength → plates, shield slots → radiator pairs, fuel → tank length, size class → length. Tested over the full table of each ruleset and over 500 random Designer specifications.
- **ART-SHIP-004** {M20} Slots: the blueprint has exactly `weaponSlots` hardpoints, `shieldSlots` emitters and `gadgetSlots` mounts; each installed item yields its distinct part and each empty slot its empty part. Each of the 6 weapons, 3 shields and 6 visible gadgets changes the rendered pixels in its slot region; hidden cargo bays change nothing (pixel-identical).
- **ART-SHIP-005** {M20} Types are distinguishable: silhouette IoU between any two of the ten buyable types, pristine and unequipped, is < 0.85 (ART-013 rewritten).
- **ART-SHIP-006** {M20} Livery variety: for each buyable type and each of the roles trader and pirate, 2,000 consecutive seeds give at least 1,500 distinct livery signatures, and 64 consecutive seeds give 64 distinct pixel fingerprints at 240 × 160.
- **ART-SHIP-007** {M20} Never the player's twin: over 100,000 random (player seed, opponent seed, ship type, role ∈ {trader, pirate, famousCaptain}) cases, the opponent's signature differs from the player's and, when the types match, the base hues differ by ≥ 40°; and the two fingerprints differ.
- **ART-SHIP-008** {M20} Role legibility: every police render contains the checker band (a test samples the band region for alternating blue and white cells) and the insignia; no non-police render does. Pirate renders have wear ≥ 0.6 and no registry; trader renders have a registry block. Role is also always given in words by the encounter badge (UI-ENC-202), so role never depends on colour alone.
- **ART-SHIP-009** {M20} Special designs: Space Monster, Dragonfly, Scarab, Scorpion, Mantis, bottle and Marie Celeste each render through their own blueprint, pairwise IoU < 0.85 against every buyable type's silhouette for the first five, and the Marie Celeste render has no plume and no lit light.
- **ART-SHIP-010** {M20} Determinism and stability: livery and geometry for fixed inputs are pinned by golden signature values for 20 cases; the opponent seed is identical before and after a save/load round trip and across rounds of one encounter (app test using the `pirateAmbush` scenario).
- **ART-SHIP-011** {M20} Performance: a 240 × 160 ship draws in ≤ 4 ms median (ART-006 stays); blueprints are cached in a new cache type, not in a frozen file.
- **ART-SHIP-012** {M20} `pmart sheet --page ships` shows all 17 types; `--page liveries` shows 10 types × 4 roles × 4 seeds; `--page fittings` shows one hull with each item installed and empty.
- **ART-SHIP-013** {M25} Call sites: encounter panels pass the role from `EncounterBadge` / `OpponentType` and the opponent seed; Shipyard, Equipment, Commander Status, transit and the purchase sheet pass the player role and seed. The achievement emblems, the two ship vignettes and the combat-effect frame keep working through the retained entry points.
- **ART-SHIP-014** {M26} The app icon is regenerated from the new generator (a Beetle in a brass-accent livery) by `scripts/make-icon.sh`; the committed icon PNGs are replaced in the same commit and `scripts/make-icon.sh --check` passes.

**Look criteria** (judge on the contact sheets, write a QA-REPORT row): reads as machinery, not a toy; modules are recognisable (habitat, containers, tanks, radiators, engines); a Beetle or Termite looks like a freighter and a Wasp or Hornet like a warship before reading the label; police, pirate and trader versions of one type are told apart at 96 pt; no two neighbours on the liveries page look the same; installed weapons can be counted.

### 5.2 Portraits

**Subjects.** The commander (id 0), every hireable mercenary of each ruleset, Zeethibal, Wild, Jarek, the Princess, and the three famous captains. Everything else has no portrait.

**Where shown.** Personnel (96 pt), Commander Status (128 pt), New Game (preview), the career card (64 pt), the encounter panel for famous captains (72 pt).

**Target style: illustrated realism.** A front-facing head-and-shoulders bust, turned at most 8°, with real human proportions, built from layered vector shapes and shaded in four flat tones (light, mid, shadow, rim) from one key light at the upper left. It should read like a painted ID photograph, not a cartoon and not a photograph. Faceless helmets are no longer the default.

**Genome.** `PortraitGenome.make(seed:)` → at least 16 genes:

| Gene | Range |
|---|---|
| head shape (cranium width, jaw width, chin length, cheekbone) | 4 continuous values, each clamped to ±12% of the mean |
| skin tone | 10 curated ramps (each: light, mid, shadow, rim) |
| eyes | 6 lid shapes × 6 iris colours; spacing 1 eye-width ±10%; eye line at 0.48–0.52 of head height |
| brows | 5 shapes, height and angle clamped |
| nose | 6 shapes, length and width clamped |
| mouth | 6 shapes; width tied to eye-centre spacing ±10% |
| ears | 3 shapes, placed between brow and nose lines |
| hair | 14 styles including bald, as a back layer and a front layer; 8 colours |
| facial hair | none or 5 styles, at most 25% of seeds |
| age | 3 bands (lines, hair greying) |
| mark | none (70%), scar, freckles, implant, eye patch |
| attire | 8 collars and suits; accent colour |
| insignia | from the character's best skill: Pilot wings, Fighter chevrons, Trader ledger bars, Engineer cog (information the roster already shows) |
| backdrop | 6 muted panels |

Presentation is drawn from the seed and never inferred from a name (assumption: the original's names carry no stated gender, so the generator does not guess one).

**Seeds.** Mercenaries and passengers: `ArtSeed.crew(galaxySeed:crewID:)` (existing). Commander: the same mixed with a stable FNV-1a hash of the commander's name, so two games on one galaxy code get different commanders. Both inputs are in the save; nothing is added to it. Fixed designs (authored gene sets, not seeded): Wild (older, scarred, plain dark suit), Jarek (formal ambassador attire), the Princess (circlet, formal attire), Zeethibal (youngest age band, engineer attire), Ahab, Conrad, Huie (naval attire with a gold stripe matching their ship).

Requirements (spec file `docs/specs/ART-FACE.md`):

- **ART-FACE-001** {M19} Determinism: the same seed gives the same genome and the same pixels; genome hashes for galaxy seed 1001, crew ids 0–54, are pinned as golden values after the style decision (ART-FACE-009) and never change afterwards.
- **ART-FACE-002** {M19} Uniqueness within a game: for each galaxy seed 1–500 and each ruleset's crew list, all portraits (commander, mercenaries, special characters, famous captains) have pairwise distinct genomes that differ in at least 4 genes, and distinct pixel fingerprints at 96 pt (fingerprints checked for seeds 1–20).
- **ART-FACE-003** {M19} Uniqueness at large: 100,000 random seeds give at least 99,900 distinct genomes.
- **ART-FACE-004** {M19} Proportion constraints hold for 10,000 genomes: eye line within 0.46–0.54; eyes mirror-symmetric in position; brows above eyes, nose between eye line and mouth, mouth above chin, all features inside the head outline with a 4% margin; no two feature bounding boxes overlap except brow/eye by at most 10%.
- **ART-FACE-005** {M19} Stable across saves: loading each v1 save fixture and re-encoding it gives the same portrait seed for every crew id; renaming nothing changes nothing. (The commander's portrait depends on the name, which is fixed at New Game.)
- **ART-FACE-006** {M19} Legibility: every portrait renders at 28, 64, 96 and 128 pt (28 pt is a floor for legibility, not a current placement); at 28 pt the render keeps at least three tones in the face region (not a blob) — measured as ≥ 3 colour clusters covering ≥ 10% each.
- **ART-FACE-007** {M19} Performance: a 96 pt portrait draws in ≤ 3 ms median; genomes are cached.
- **ART-FACE-008** {M19} `pmart sheet --page portraits` renders 60 portraits (galaxy seed 1001 ids 0–54 and five more seeds' commanders) at 128 pt; `--page portraits-small` the same at 28 and 64 pt.
- **ART-FACE-009** {M19} **Style decision.** See the proof of concept in M19. The decision (target style or fallback) is recorded in `docs/adr/0005-portrait-style.md` with the review scores, and ART-FACE-001's golden values are pinned for the chosen style.
- **ART-FACE-010** {M23} Every portrait view has an accessibility label "Portrait of ‹name›" and is decorative to keyboard focus.
- **ART-FACE-011** {M19} ART-034 (helmet busts) is retired with its test in the same commit that lands ART-FACE-001…008.

**Quality bar (the proof of concept passes only if all hold):**
1. ART-FACE-001…008 are green.
2. Self review of the 60-portrait sheet with this rubric, one yes/no per portrait per line: (a) reads as a human face at 64 pt; (b) no feature is misplaced, floating or cut by the outline; (c) lighting is consistent; (d) it is not unsettling (no staring mismatched eyes, no mask-like symmetry errors); (e) it differs clearly from its sheet neighbours; (f) attire and insignia are readable. A portrait passes with six yeses. **At least 54 of 60 pass.**
3. An independent review by a subagent that is given only the PNG and the rubric (not the code or the self review) also passes at least 54 of 60.

**Fallback style ("flight suit")**, used if the bar is not met after three full iterations of the generator (an iteration = change, re-render, both reviews): the same genome, seeds and tests, but the bust wears a helmet with a raised or transparent visor; the face is reduced to skin tone, jaw and chin shape, mouth and the lower nose in shadow, with a rim light; identity comes from helmet shape (8), helmet colour and pattern (the livery pattern set), visor tint (6), decals, attire, insignia and the visible lower face. The rubric's line (a) becomes "reads as a suited person at 64 pt". The same 54-of-60 bar applies; if the fallback also misses it after two iterations, ship the fallback anyway, record the scores in the ADR and in `docs/QA-REPORT.md` as a known limitation, and continue. Portraits never block later milestones.

### 5.3 Endings

All four ending scenes are redrawn in the realistic style, in `PA/Scenes/Endings.swift` (free to edit) or new files beside it. The host keeps its contract: a 16:9 card, a 4-second animation that then holds, a still frame with Reduce Motion, `GameOverScene(end:phase:ship:accessibility:shipInput:)`.

| Ending | Scene |
|---|---|
| Retired (`retired`) | Low orbit at sunset: the limb of a planet with a thin lit atmosphere, the sun on the horizon with a physically plausible glow, the player's ship (real statistics, equipment and livery) small against the planet, drifting to a stop, engine plume fading. |
| Moon (`boughtMoon`) | The surface of the moon at Utopia: regolith with long shadows, a pressurised habitat with lit windows and a landing pad, the parent planet large in a black sky, the player's ship landed on the pad. |
| Moon with the Princess (`boughtMoonGirl`) | The same place, with a second, smaller ship in a distinct fixed livery landed beside the first and two lit habitat windows instead of one. |
| Killed (`killed`) | The player's own ship broken into drifting sections with its real livery and fittings recognisable, cooling debris, venting gas, a fading explosion light on the nearest pieces; no pilot shown. |

- **ART-END-001** {M26} Each ending renders for every buyable ship type and a custom ship; twice gives identical pixels; each has an accessibility label describing the scene.
- **ART-END-002** {M26} Planets in endings are drawn only through the protected planet API with fixed seeds; the protected files are unchanged (PROT-001).
- **ART-END-003** {M26} The player's ship in every ending is built from the actual `ShipArtInput` at game end (statistics, equipment, livery), not a reference design; a test with two different final ships gets two different fingerprints for each ending.
- **ART-END-004** {M26} Phases 0, 2 and 4 seconds differ from each other with motion on; with Reduce Motion the scene is the phase-4 frame from the start.
- **ART-END-005** {M26} `pmart sheet --page endings` shows each ending at phases 0, 2 and 4. ART-084, ART-085 and ART-086 are rewritten in place for the new scenes.

**Look criteria:** light has one direction and shadows agree with it; the planet and the ships share that light; scale is believable (a ship is small beside a planet, large beside a habitat window); the scene is recognisable without its caption; the killed scene is sombre, not gory.

---

## 6. Technical approach

### 6.1 Architecture stays

- The engine, insights and persistence packages are frozen (§1.4). Everything new is in the app target or in `ParsecArt` / `pmart`.
- `GameSession` remains the one store; views keep reading pure models built per render. New models: `BridgeModel` (regions A–D in one value), `CargoRowModel` (replaces `MarketRowModel`), `StatusBarModel` (extended), `StatusPageModel` (from `InspectorModel`).
- Commands still go through `session.send`. "Sell All Cargo" is a session method that loops over `send(.sellCargo…)`.
- The presentation queue, `MenuRules`, `KeyBindingTable`, `EscapeRouter`, `Announcer`, `MotionPolicy`, `ReasonText`, `PointerTarget`, `AXID` stay and are extended.
- `ParsecArt` still does not import the engine; `APP/Art/ArtAdapters.swift` maps engine values (now also role and seeds) to art inputs.

### 6.2 File plan

| Area | New or changed | Removed when unused |
|---|---|---|
| Design system | `APP/Design/PMColor.swift`, `PMFont.swift`, `PMSpace.swift`, `PMMotion.swift`, `PMScale.swift`, `APP/Design/Components/*.swift` | ad-hoc styles in views |
| Shell | `APP/Views/Shell/GameShellView.swift`, `StatusBarView.swift` (rewritten), `DockBarView.swift`; `APP/Session/Section.swift`, `DetailMode.swift`, `WindowTitles.swift`, `ShellModels.swift` | `MainShellView.swift`, `SidebarView.swift`, `ShellToolbar.swift`, `APP/Views/Inspector/` |
| Bridge | `APP/Views/Bridge/BridgeView.swift`, `SystemPanel.swift`, `CargoPanel.swift`, `CargoRow.swift`, `ChartPanel.swift`, `TargetPanel.swift`, `BridgeManifest.swift`, `LayoutProbe.swift`; `APP/Session/BridgeModels.swift`, `CargoModels.swift` | `Views/Sections/BridgeSectionView.swift`, `MarketSectionView.swift`, `Views/Market/MarketIntelViews.swift` (its breakdown moves to the Price Details sheet) |
| Pages | `APP/Views/Pages/{Shipyard,Equipment,Personnel,Bank,Status,Quests,Chart,Logbook,Options}Page.swift` | `Views/Sections/*`, `Views/Options/GameOptionsSheet.swift` |
| Encounter, transit | `APP/Views/Encounter/*` rewritten in place, `Views/Transit/TransitView.swift` | — |
| Map | `APP/Map/MapHUDViews.swift`, `HeatmapHUDView.swift`, `MapStyle.swift`, `MapPlacements.swift` (not `MapArt.swift`) | inline search, pinned card, `SystemIntelSheet.swift` |
| Art (package) | `PA/Ships2/*` (generator, livery, fittings, specials, renderer), `PA/Portraits/*`, `PA/Core/ArtPalette2.swift`, `PA/Scenes/Endings.swift`; `pmart` pages | `PA/Ships/ShipHullGenerator.swift`, `ShipSpecials.swift`, `ShipFeatures.swift`, `ShipBlueprint.swift`, `ShipGeometry.swift`, `ShipRenderer.swift` as replaced; `PA/Glyphs/CharacterArt.swift`'s `CrewAvatar` |
| Art (app) | `APP/Art/ArtAdapters.swift` (role, seeds; `planetInput` untouched), `ArtViews.swift`, `ShipSeeds.swift`, `PortraitView.swift` | `CrewAvatarView` |
| Identifiers | `APP/App/AXID+Bridge.swift` and friends, mirrored in `SpaceTraderMacUITests/` | identifiers of removed elements |
| Scripts | `scripts/protected-check.sh`, `scripts/logic-frozen.sh`; edits to `verify.sh`, `final-check.sh`, `release.sh`, `spec-trace.sh`, `export-screenshots.sh` | — |
| Specs | `docs/specs/UI-BRIDGE.md` (UI-BRG, UI-SB), `UI-NAV.md` (UI-NAV, UI-PG, UI-FAIR), `UI-DESIGN.md` (UI-DS, UI-HIG), `ART-SHIP.md`, `ART-FACE.md`, `ART-END.md`, `PROT.md`; rewrites in `UI-SHELL.md`, `UI-ENC.md`, `UI-KEYS.md`, `MENU.md`, `UI-POINTER.md`, `MAP.md`, `A11Y.md`, `ART.md` | retired IDs |

Synchronized folders mean new files need no project-file edit. If the project file must change, back it up with git first (CLAUDE.md).

### 6.3 Identifiers and old specs

- Elements that survive keep their accessibility identifiers. Elements that are removed lose theirs, with their UI tests, in the same commit. New identifiers follow `AXID.pattern`. This PRD suspends "extend, never rename" only for removed elements.
- Old requirement IDs follow PRD-1.1 D10: rewrite in place when the requirement still exists in a new form; delete the ID together with its test citations when the requirement is gone (sidebar, inspector, toolbar, compact market mode, chips, pinned card, inline map search, glass allowlist, Text Size range). Never renumber. Each deletion commit names the IDs in its message.
- Each requirement in this PRD is copied into its spec file in the project format `- **ID** {Mn} [M][W][P] [UI] text` before its tests are written. Requirements marked as judged by eye are `[manual]` and get a `docs/QA-REPORT.md` row.

### 6.4 Rulesets

Every model reads the active game's `Ruleset`: trade goods, ship and equipment tables, crew list, options, quests, and intel through `TradeIntel` with that ruleset. Tests that build screens run once per ruleset from the three save fixtures. There is no `if ruleset.id == …` anywhere (existing rule); the Bridge, the status bar and the dock bar are identical in all three rulesets, and pages show what the ruleset's previews offer (UI-PG-003, UI-PG-050).

### 6.5 Performance

- The Bridge re-renders on state change only; no `TimelineView` on the Bridge except the protected live planet's own display link and `AmbientSchedule`.
- Idle CPU docked on the Bridge ≤ 5% (`scripts/idle-cpu.sh`, the existing bar). Map render median < 8 ms (`scripts/bench-map.sh`). `pmsim bench --check` unchanged.

---

## 7. Milestones

**How every milestone is worked** (as in PRD-1.1 §5): specs first (copy the requirements into `docs/specs/`, commit) → tests that fail for the right reason → implement in small steps with `scripts/verify.sh --quick` between steps and `scripts/verify.sh` before each commit → look at the result (render `pmart` sheets or export screenshots, open the PNGs with the Read tool, judge against the look criteria, write a `docs/QA-REPORT.md` row) → exit checks → update `PROGRESS.md` → commit → tag `mN-done` → push.

**After every milestone the app builds, launches and a full game can be played.** M21 achieves this by hosting the old section views inside the new shell until their replacements land.

Order and dependencies: M18 → M19 → M20 → M21 → M22 → M23 → M24 → M25 → M26 → M27 → M28. M19 and M20 need only M18 and may be swapped; nothing else may be reordered.

### M18 · Setup, freezes and baselines

**Code and scripts.**
1. `PROGRESS.md`: add unchecked lines `- [ ] M18 …` to `- [ ] M28 …`. Keep the status line in the form `- **Current milestone:** M17 done; working on M18`. `scripts/lib-milestone.sh` reads the **first** number on that line, and `spec-trace.sh` treats requirement IDs tagged up to that number as due. So the first number is always the last **finished** milestone, and it is raised (`M18 done; working on M19`) only in a milestone's exit commit, when every ID of that milestone has its test. Requirement IDs of the milestone in progress can then be committed before their tests.
2. `scripts/spec-trace.sh`: change `m >= 17` to `m >= 28`.
3. `scripts/protected-check.sh` and `scripts/logic-frozen.sh` (§1.4, §8.2). Add both to `scripts/verify.sh` as steps `7c-protected` and `7d-logic-frozen` in every mode including `--quick`.
4. Baselines, measured **before any other change** and written into `scripts/logic-frozen.sh` and `PROGRESS.md`:
   - `swift run --package-path Packages/ParsecKit -c release pmsim fuzz --games 2000 --seed 1 --ruleset all` → the three command counts (expected from the 1.1.0 logs: modern 4531100, windows201 4528609, palm122 3134221; if the measured numbers differ, use the measured ones and note it);
   - `swift run --package-path Packages/ParsecKit -c release pmsim dump-galaxy --ruleset <r> --seed 1 | shasum -a 256` for the three rulesets.
5. `PlanetFrozenTests.swift` (PROT-003): fingerprints of `PlanetRenderer.image` for 10 planet classes × 2 seeds × LODs mini, still and hero, of `PlanetOverlayArt` for 3 inputs, and of the app's `planetInput` mapping for 5 systems of seed 1001 (app test). Record the values from the first run as literals.
6. Create the new spec files with every requirement of this PRD, each tagged with its milestone.
7. `scripts/final-check.sh`: `TAG=v2.0.0`, `ASSET=Parsec-Merchant-2.0.0.zip`, milestone regex `M([0-9]|1[0-9]|2[0-8])` and count 29, new checks 9 (`scripts/protected-check.sh`) and 10 (`scripts/logic-frozen.sh`), summary `FINAL CHECK n/10 PASS`. Required QA-REPORT rows: keep the 17 existing ones and add "Bridge layout", "Ship liveries", "Portraits", "Endings", "Keyboard-only loop". `scripts/release.sh`: `VERSION="2.0.0"`. `MARKETING_VERSION` 2.0.0 in `project.xcproj`.
8. `CLAUDE.md`: add this PRD to "Source of truth" (it wins for M18–M28), the two new scripts to "Commands", `--ui` at the end of M21–M28, and the protected list pointer.

**Exit checks.** `scripts/verify.sh` → `ALL GATES PASSED`; `scripts/protected-check.sh; echo $?` → 0; `scripts/logic-frozen.sh; echo $?` → 0; `git diff --stat v1.1.0 -- SpaceTraderMac Packages/ParsecKit/Sources` shows only the two UI commits already on `main` plus the version bump.

### M19 · Portrait proof of concept

**Spike (timebox: three iterations, §5.2).** Build `PA/Portraits/` (genome, layers, renderer), the `pmart` pages, and tests ART-FACE-001…008. Run both reviews. Decide target or fallback; write ADR 0005; pin golden values. No app view changes yet except replacing `CrewAvatarView`'s drawing with the new portrait at its existing call sites so the app shows it.

**Exit checks.** `swift test --package-path Packages/ParsecKit --filter Portrait` passes; `scripts/verify.sh` passes; ADR 0005 exists with both review scores; QA-REPORT row "Portraits (M19 proof of concept)" with the commit and the decision.

### M20 · Ships and liveries

**Code.** `PA/Ships2/*`, `ShipRole`, `ShipLivery`, fittings, specials; retained entry points re-pointed; `pmart` pages; `ArtAdapters` passes role and seeds from the existing call sites (encounter, shipyard, inspector, transit, endings keep working through the retained API). Old ship tests rewritten in place (ART-013, ART-081, ART-082, ART-088, ART-089 and the overlay tests ART-014…019 against the new renderer).

**Exit checks.** ART-SHIP-001…012 green; `scripts/verify.sh` passes (the icon check and the endings still pass because `AppIconArt` and `Endings.swift` keep calling the old generator and renderer until M26: keep the old files they need until then, and delete at M20 only what nothing calls); QA-REPORT row "Ship liveries (M20)" judged against the look criteria; ship draw median ≤ 4 ms printed by the test.

### M21 · Design system and shell

**Code.** Tokens and components (§3.3–3.5); `GameShellView` with the new status bar and dock bar; sidebar, toolbar and inspector removed; **old section views hosted unchanged as pages**, with temporary dock buttons "Market" (old market) and a temporary Commander Status page that wraps the old inspector form; Options stays a sheet for now. Window sizes and scale environment (UI-DS-001…003). UI tests and `UISurfaceCatalog` re-pointed from sidebar to dock bar in the same commits.

**Exit checks.** UI-DS-001…003, 010…012, 020, 024, 030, 031; UI-NAV-001…005, 009; UI-SB-001…005; UI-HIG-007 green. `scripts/verify.sh --ui` → `ALL GATES PASSED`. Screenshots of every page at the minimum size exported and read.

### M22 · Bridge

**Code.** `APP/Views/Bridge/*`, models, `BridgeManifest`, layout probes, Sell All Cargo, Price Details sheet, amount sheets; the temporary Market page and the old Bridge are deleted; Trade menu items added to `MenuCatalog` (final menu layout is M27).

**Exit checks.** UI-BRG-001…013, 020…023, 030…036, 040, 042; UI-FAIR-001, 002 green. `scripts/verify.sh --ui` passes. Run and print: `xcodebuild … test -only-testing:SpaceTraderMacTests/BridgeLayoutTests` (all size × ruleset × state combinations, count printed). Screenshots of the Bridge at 1200 × 680, 1440 × 860 and 2056 × 1290 exported, read and compared with the wireframe; QA-REPORT row "Bridge layout". `scripts/idle-cpu.sh` ≤ 5%.

### M23 · Secondary pages

**Code.** Shipyard, Equipment, Personnel, Bank, Commander Status, Quests, Logbook, Options pages (§4.4–4.10); portraits placed (ART-FACE-010); `APP/Views/Sections/` and `APP/Views/Inspector/` deleted.

**Exit checks.** UI-PG-001…003, 010, 020, 030, 040, 050; UI-NAV-006, 007, 010 green; a UI test buys a ship, buys and sells equipment, hires and fires, borrows and repays, toggles an option, each from its page. `scripts/verify.sh --ui` passes. Page screenshots read.

### M24 · Charts

**Code.** Galactic Chart page and window HUD (§4.11), single Find, chart restyle through `MapStyle` (not `MapArt.swift`).

**Exit checks.** UI-PG-060…063, UI-NAV-008 green; MAP tests green; `scripts/bench-map.sh` median < 8 ms; `scripts/verify.sh --ui` passes.

### M25 · Encounter, transit, interruptions

**Code.** Encounter page (§4.13), transit, plunder / trade-in-orbit / make-room sheets, newspaper, narrative and report sheets rebuilt from components; ship call sites final (ART-SHIP-013).

**Exit checks.** UI-ENC-200…207, ART-SHIP-013 green; the `pirateAmbush`, `encounter:pirateSurrender`, `encounter:traderSell`, `encounter:policeAttack` scenario UI tests pass; `scripts/verify.sh --ui` passes; encounter screenshots for police, pirate, trader, Mantis, Space Monster and a famous captain read against §5.1 look criteria.

### M26 · Endings, welcome, new game, game over, icon

**Code.** §5.3; Welcome, New Game sheet, Game Over; icon regenerated (ART-SHIP-014); the old ship generator files deleted.

**Exit checks.** ART-END-001…005, ART-SHIP-014, UI-PG-070 green; `scripts/make-icon.sh --check` passes; `pmart sheet --page endings` read against the look criteria; QA-REPORT row "Endings"; `scripts/verify.sh --ui` passes.

### M27 · Keyboard, menus, accessibility, words, help

**Code.** Final menu bar (§4.15), `KeyBindingTable` and `KeyAudit`, focus order, help tags, VoiceOver labels and actions, Text Size steps (UI-DS-004), vocabulary sweep, help pages, source audits UI-DS-021…023, README screenshots re-exported.

**Exit checks.** UI-HIG-001…006, UI-NAV-011, 012, UI-DS-004, 021, 022, 023, 026, 032, UI-BRG-041 green; the accessibility audit UI test (flow 6) passes on every page; the largest available Text Size test and the pseudo-localization test pass with the no-clipping check; `scripts/verify.sh --ui` passes; QA-REPORT rows "Keyboard-only loop", "Accessibility audit", "Text Size", "Light and dark" (chrome), "Smallest window" updated.

### M28 · Release 2.0.0

**Code.** CHANGELOG, README, CREDITS, `docs/design/UX-VISION.md` gets a header pointing to this PRD for everything it supersedes; QA-REPORT release rows; `scripts/release.sh`; `gh release create v2.0.0`.

**Exit checks.** `scripts/final-check.sh` → `FINAL CHECK 10/10 PASS`, `EXIT=0`.

---

## 8. Acceptance criteria

### 8.1 Checks every milestone must pass at exit

| # | Check | Command | Passes when |
|---|---|---|---|
| A1 | Build, tests, lint, coverage, fuzz, spec trace, license | `scripts/verify.sh` (M18–M20) or `scripts/verify.sh --ui` (M21–M28) | last lines are `ALL GATES PASSED` and `EXIT=0` |
| A2 | Protected files untouched | `scripts/protected-check.sh; echo EXIT=$?` | `EXIT=0` |
| A3 | Game logic unchanged | `scripts/logic-frozen.sh; echo EXIT=$?` | `EXIT=0` |
| A4 | Zero warnings | inside A1 (`warnings-gate.sh`) | 0 |
| A5 | Every new requirement due is traced to a test | inside A1 (`spec-trace.sh`) | no missing IDs |
| A6 | The app is playable | `swift run --package-path Packages/ParsecKit -c release pmsim scenario --ruleset all --seed 2` and the smoke UI test in A1 | same days as the M18 baseline; smoke passes |
| A7 | Milestone-specific exit checks | §7 | as listed |
| A8 | Evidence | the unedited tail of each command is in the conversation and the gate result is in `PROGRESS.md` | present |

### 8.2 The two freeze scripts, exactly

`scripts/protected-check.sh`:
1. `BASE=296ad2c6729fa626fd826b44f112ac2c959eb870`; fail if `git cat-file -e $BASE` fails.
2. For each path in lists A, B, C of §1.4: fail if the file does not exist; collect it.
3. `git diff --exit-code "$BASE" -- <paths>` and `git status --porcelain -- <paths>` must both be empty.
4. Print `PROTECTED OK (22 files)` and exit 0, or the diff stat and exit 1.

`scripts/logic-frozen.sh`:
1. `git diff --exit-code v1.1.0 -- Packages/ParsecKit/Sources/ParsecEngine Packages/ParsecKit/Sources/ParsecInsights Packages/ParsecKit/Sources/ParsecPersistence Packages/ParsecKit/Sources/pmsim Packages/ParsecKit/Tests/ParsecEngineTests Packages/ParsecKit/Tests/ParsecInsightsTests Packages/ParsecKit/Tests/ParsecPersistenceTests Packages/ParsecKit/Tests/ParsecScenarioTests` must be empty, and `git status --porcelain` for those paths must be empty.
2. `Packages/ParsecKit/Tests/Fixtures` is included in the diff of step 1.
3. Unless `--fast` is given: run the fuzz command and compare the three command counts with the M18 baseline; run the three `dump-galaxy` hashes and compare. `verify.sh --quick` calls it with `--fast`; other modes call it in full (the fuzz output of step 3 of `verify.sh` may be reused instead of running fuzz twice).
4. Print `LOGIC FROZEN OK` and exit 0, or the first difference and exit 1.

### 8.3 Requirement-to-test map (what proves each headline requirement)

| Requirement from the brief | Proved by |
|---|---|
| Build and tests pass | A1 |
| Bridge has no scroll containers | UI-BRG-030 (source audit), UI-BRG-032 item 5 (`NSScrollView` walk), UI-BRG-033 (`scrollViews.count == 0`) |
| Nothing clipped at the minimum size and larger | UI-BRG-032 items 1–4 and 6 over 6 sizes × 3 rulesets × 5 states; UI-BRG-034; UI-BRG-033 |
| No hidden or collapsed elements | UI-BRG-031, UI-BRG-035 (manifest equal at all sizes), UI-BRG-030 (no disclosure, tabs, lazy containers) |
| Core loop without leaving the Bridge | UI-BRG-040, UI-BRG-041 |
| Ship livery uniqueness | ART-SHIP-006, ART-SHIP-007 |
| Ships from statistics, equipment visible | ART-SHIP-002, 003, 004 |
| Police, pirate, trader, alien, special handled | ART-SHIP-008, 009 |
| Portrait uniqueness and stability | ART-FACE-001, 002, 003, 005 |
| Game logic unchanged | A3 (`logic-frozen.sh`), A6 |
| Protected files untouched | A2 (`protected-check.sh`), PROT-003 |
| Contrast, never colour alone | UI-DS-010, UI-DS-012, ART-SHIP-008, UI-ENC-202 |
| Keyboard and menus | UI-HIG-001…003, UI-NAV-011, UI-BRG-041 |
| Help tags and VoiceOver | UI-HIG-004, 005, UI-DS-031, 032, accessibility audit UI test |
| Consistent terminology | UI-DS-026 |
| Only information the game exposes | UI-FAIR-001, 002, UI-BRG-006, UI-BRG-023 |

---

## 9. Definition of done

The work is done when this single condition holds:

> On a clean working tree whose `HEAD` equals `origin/main` and carries the tag `v2.0.0`, the command `scripts/final-check.sh` prints `FINAL CHECK 10/10 PASS` followed by `EXIT=0`, and that complete, unedited output is shown in one turn.

`scripts/final-check.sh` (as retargeted in M18) makes that one condition cover everything: (1) `verify.sh --ui` all gates; (2) `PROGRESS.md` shows M0–M28 checked and no blocker; (3) the GitHub release `v2.0.0` has its zip; (4) `docs/QA-REPORT.md` has no ✗ or TODO and has every required row; (5) the released app launches; (6) a clean clone builds; (7) `pmsim bench --check`; (8) clean tree and `HEAD == origin/main`; (9) `protected-check.sh`; (10) `logic-frozen.sh`.

---

## 10. Risks, assumptions, working rules, resume

### 10.1 Risks

| Risk | Mitigation |
|---|---|
| Realistic procedural faces look uncanny. | Proof of concept at M19 with a numeric bar, two reviews, a defined fallback, and a rule that portraits never block (§5.2). |
| The Bridge does not fit at 1200 × 680 with long strings. | The fit test runs with the longest table strings and double-length pseudo-localization; allowed adjustments are spelled out in §4.2; removal of elements is not allowed. If it still cannot fit, raise the minimum **height** in 10 pt steps up to 720, then the width in 20 pt steps up to 1280, record an ADR with the reason, and update UI-DS-001; never add scrolling. |
| Rewriting the shell breaks most of the 52 UI tests at once. | M21 keeps old pages hosted and re-points tests to the dock bar in the same commits; `--ui` must be green at M21 exit before the Bridge is touched. |
| `--ui` runs take 53–86 minutes. | Use `--quick` and `verify.sh` during work; `--ui` once per milestone exit and after UI-test changes. Follow the mirror procedure in the PROGRESS decisions log. |
| A planet file needs a change to fit a layout. | Not allowed. Change the layout around it (§1.4). |
| Replacing the ship generator breaks the icon, emblems, vignettes, endings. | Entry points are retained; the icon keeps its old path until M26; each consumer is listed in §5.1 and ART-SHIP-013. |
| A view reads hidden state by accident. | UI-FAIR-001 source audit plus the existing fairness tests. |
| The three rulesets differ in content. | Every screen test runs per ruleset from the three save fixtures (§6.4). |
| Spec trace fails on new IDs before their tests exist. | The M18 threshold change makes IDs due by their `{Mn}` tag; write IDs with the milestone that tests them. |

### 10.2 Assumptions (acted on, not questions)

1. "Consider the ruleset" means: all numbers and content come from the active game's `Ruleset` tables and previews, the layout is the same for all three, and tests run per ruleset.
2. The game area is dark in both appearances; chrome follows the system. The HIG allows a dark-only appearance "in rare cases" such as immersive content, and asks for contrast of at least 4.5:1, striving for 7:1, which UI-DS-010 enforces.
3. Sell All Cargo, Fill Tank and Repair Hull act with one click and no confirmation; engine confirmations (for example illegal goods) still appear.
4. The Galactic Chart's click selects without changing the target; the Short-Range Chart's click sets the target.
5. Portrait presentation is seeded and independent of names; the commander's portrait depends on the galaxy seed and the commander's name.
6. Opponents other than famous captains have no portrait, because the game gives them no identity.
7. Ship markings are abstract shapes, not text.
8. The app icon changes to the new ship style.
9. The Text Size setting becomes five steps tied to the interface scale; the largest steps need a display big enough for the scaled minimum window.
10. The New Game wizard becomes one sheet with the same fields.
11. Exact prices in other systems cannot be shown because the engine does not have them before arrival; the Target column is the original's average-price estimate or a remembered price, labelled.
12. The separate Galactic Chart window, High Scores window, Settings, About and Help keep their behaviour and are restyled only where they draw game content.
13. The MacBook Neo's default scaled mode is assumed to be exactly 2× (1204 × 753 pt); Apple publishes only its pixel size. The minimum window is derived from the content budget and merely checked against that display, so it stands either way.
14. The dock bar and the status bar are at the top of the window, following the HIG's advice for macOS against controls and critical information at the bottom edge.

### 10.3 Working rules

- Everything in `CLAUDE.md`, `docs/PRD.md` §11 and `docs/PRD-1.1.md` §8 applies: no weakened, skipped or deleted gates or tests except the rewrites this file names (each replaced in the same commit); evidence over claims; small green conventional commits; no `.popover`; SPDX headers; every string localized; every interactive view identified; `/usr/bin/grep`; no pointer or keyboard use outside `--ui` runs; ignore `.claude/worktrees/`.
- Do not edit a file in §1.4. If a task seems to need it, the task is wrong: find another way and note it in `PROGRESS.md`.
- Do not add features, rules or information beyond this file. Do not refactor engine-facing code that the revamp does not touch.
- Reuse before writing: the helpers listed in PRD-1.1 §8, plus `TradeIntel`, `IntelSnapshot`, `MenuRules`, `ReasonText`, `ColorSignal`, `PointerButtonStyle`, `ArtSnapshot`, `UISurfaceCatalog`.
- For new macOS 27 SwiftUI APIs consult `.claude/skills/` (swiftui-whats-new-27, swiftui-specialist) and record an ADR.
- Blockers: `docs/PRD.md` §11.6. Record, print `BLOCKED: …`, continue with unblocked work. Design questions are never blockers: this file or its assumptions decide.
- End every turn with `Milestone Mx: <done>/<total> steps — gates <PASS|FAIL>`.

### 10.4 Start or resume

1. Read `CLAUDE.md`, `PROGRESS.md`, then this file's section for the current milestone and §1.4.
2. `git status`, `git log --oneline -15`.
3. `scripts/verify.sh --quick` and print its summary.
4. Continue from "Next step" in `PROGRESS.md`; update it after every step.

### 10.5 Research appendix

Sources, with what was read on the page and what could not be verified, are in `docs/research/10-ui-revamp-research.md`. The codebase audit is `docs/research/09-ui-audit.md`. Mechanics are cited from the repository's own sources and specs, which stay the ground truth.
