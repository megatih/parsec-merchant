# Parsec Merchant: UX Vision

> Normative design direction for the app layer. Where this document and `docs/PRD.md` conflict, the PRD wins. Research inputs: `docs/research/02` (the WinForms UI we are replacing and its 17 pain points), `03` (Spronck's own design critique, fan complaints, patterns from Endless Sky, EV Nova and Elite), and `05` (macOS 27 / HIG).

## 1. Design principles
1. **One cockpit, few screens.** Spronck's 2001 design post-mortem said the Palm game had "too many screens" and should "make do with about four main screens," with buy and sell merged and a "nerve centre." So: one main window, a sidebar of docked services, a persistent ship-status inspector, and a toolbar holding the always-relevant numbers.
2. **Never stack modal dialogs.** The WinForms port fires 3–10 OK-boxes in a row on arrival, arrest or ship purchase. Use these instead:
   - Outcomes go to the **event feed** and a **consolidated report sheet**.
   - Choices go to a single sheet or inline confirmation.
   - Validation errors go **inline**: disabled controls with a reason in the help tag or status text, not an alert.
3. **Show the money.** Every trade decision shows profit and loss right where you make it: per unit, per bay, and against the target system's price.
4. **Keyboard first, mouse friendly.** Every action has a menu item and a shortcut. Trading uses modifier-key quantity multipliers. Encounters use single keys. Full Keyboard Access works everywhere.
5. **Native, not themed.** Use stock SwiftUI and AppKit controls, system typography, SF Symbols and Liquid Glass applied by the system. Our personality comes from the *art* (procedural ships, planets, starfield), from *motion* and from *sound*, not from re-skinned controls.
6. **Respect the classic.** Every mechanic, quest and number of the chosen ruleset is present. Modernization only removes friction and adds understanding; it never changes outcomes, except through the explicitly chosen ruleset.
7. **Accessible by construction.** Everything works under VoiceOver, with Reduce Motion, Increase Contrast and Reduce Transparency, and at larger text sizes. Color is never the only signal: pair it with symbols, signs (+/−) or weight.

## 2. Window and scene structure
| Scene | Kind | Purpose |
|---|---|---|
| Main | `Window("Parsec Merchant", id: "main")`, min 1100×720, default 1320×860, restores frame | The game |
| Galaxy Chart | `Window(id: "galaxy")`, ⇧⌘M | A large, detachable map, ideal on a second display. It stays in sync with the main window. |
| Settings | `Settings` (⌘,) | App-wide only. Tabs: General (Text Size, fast travel, arrival report style, tactical readout), Sound, Intelligence (Foundation Models), Advanced (reset tips, achievements and high scores). **Per-save game options are not here.** They live in **Game › Options…** (⌥⌘O), a sheet that is disabled when no game is loaded. |
| High Scores | `Window(id: "scores")` | Top 10 per ruleset |
| About | Custom About panel | GPL notice, credits (Pieter Spronck, Sam Anderson, Samuel Goldstein, Matt Lee, Jay French, David Pierron) and "based on Space Trader" |

**When no game is loaded,** the main window shows a **Welcome** view. It has a starfield animation with the title, the actions **Quick Start** (Modern, Normal, balanced skills, one click), Continue (autosave), New Game…, Open Saved Game… and Import…, and a list of recent saves showing commander, day, worth, ruleset and an Ironman badge.

**Window behavior:**
- ⌘W closes the main window but keeps the app running. Reopen it from the Dock or Window › Parsec Merchant.
- Quitting autosaves.
- Window frames, the selected section and the inspector's visibility are restored at launch (`SceneStorage`/`defaultSize` plus frame autosave).
- Opening a `.parsecsave` file in Finder imports it and offers to load it.

## 3. Main window anatomy
```
┌ Title: Parsec Merchant — Cmdr. Shelby · "Folly"   subtitle: Day 34 · Lave · Credits 12,480 · Debt 0 ┐
│ Toolbar (glass, controls only):  ◧ sidebar │ ▸Target: Rhymus 8 pc ▾ │ ⟐ Warp ⌘J │ ⓘ inspector │
├──────────┬───────────────────────────────────────────────────────┬───────────────┤
│ Sidebar  │ Detail (section content)                              │ Inspector     │
│ ⌘1 Bridge│                                                       │ Ship portrait │
│ ⌘2 Market│                                                       │ Hull ▓▓▓▓░ 80%│
│ ⌘3 Ship- │                                                       │ Shields ▓▓▓░  │
│   yard   │                                                       │ Cargo by item │
│ ⌘4 Out-  │                                                       │ Crew & skills │
│   fitter │                                                       │ Record/Rep    │
│ ⌘5 Crew  │                                                       │ Active quests │
│ ⌘6 Bank  │                                                       │ Daily costs   │
│ ⌘7 Galaxy│                                                       │               │
│ ⌘8 Quests│                                                       │               │
│ ⌘9 Log-  │                                                       │               │
│   book   │                                                       │               │
│ ─ status │  Status bar: Bays 18/35 · Fuel 11/14 · Hull 80% │ Event feed: latest item · "Show Logbook" │
└──────────┴───────────────────────────────────────────────────────┴───────────────┘
```
- **Sidebar badges:** a "Special" sparkle on Bridge when a quest offer is here; the count of mercenaries for hire on Crew; a red dot on Bank when the debt warning applies.
- **Inspector** (⌃⌘I, using the standard `InspectorCommands`) is the replacement for Commander Status, Current Ship and Special Cargo. It updates live, every value has a help tag, and clicking a quest jumps to Quests.
- **Toolbar holds controls only.** Under Liquid Glass, toolbar items render as glass capsules that read as buttons, so the toolbar holds only the target picker, Warp and the inspector toggle, with Warp at `visibilityPriority(.high)`.
- **Status readouts** go elsewhere: commander, day, system, credits and debt in the window subtitle (`navigationSubtitle`); bays, fuel and hull in the bottom status bar; full details in the inspector header.
- **Status bar replacement:** a costs breakdown (mercenaries, insurance, interest, wormhole tax) shows in the help tag on the Warp button and in the Target card on Bridge, replacing the WinForms "Current Costs" dialog.

## 4. Sections

### 4.1 Bridge (the hub, ⌘1)
A two-column card layout:
- **System card:** a procedural planet portrait (style set by tech level, size and government; animated slowly unless Reduce Motion is on), name, size, tech, government, resource (or "Unknown"), police and pirate activity as levels (0–7 dots plus a word), and pressure ("Plague", "War"…) as a colored tag.
- **Dock services row:** fuel and hull gauges, each with *Fill Up* / *Repair* buttons plus a slider for a partial amount. Shows "Tank full" or "No repairs needed" when that applies.
- **Offers:**
  - Special event card, when present: title, a short story excerpt, price, and *Accept* / *Decline*. Opens the full narrative sheet.
  - Mercenary-for-hire card: links to Crew.
  - Newspaper card: masthead and price. *Read* opens the **Newspaper sheet**, a styled broadsheet with masthead, serif headlines and columns.
- **Target card:** the selected destination's information, distance in **parsecs**, fuel after the jump, costs breakdown, and buttons *Warp*, *Plot Route…*, *Show on Map*. ‹ › (⌘[ / ⌘]) cycle through systems in range. "Out of range" shows *Track* / *Untrack*.
- **Mini chart:** a short-range Canvas map, clickable. It is the same component as Galaxy, with a fixed zoom.

### 4.2 Market (⌘2): a unified trade table (buy and sell merged)
A `Table` with one row per commodity:

| Column | Content |
|---|---|
| Item | SF-symbol-style glyph + name; an *illegal* badge for Firearms and Narcotics |
| Here: Buy | price, or "—" if not sold |
| Here: Sell | price, or "—" if nobody buys it (a *Dump* fee shows when you hold it) |
| Stock | units available |
| Held | units in hold, with average cost paid |
| P/L | per-unit profit or loss if you sell here (green ▲ / red ▼ **with sign**) |
| Target | target system's sell price (from current intel; dimmed if the data is old), Δ vs here, **profit per bay** |
| History | Swift Charts sparkline of remembered prices at this system (Trade Intelligence) |
| Actions | − / + steppers, a quantity field, **Buy Max**, **Sell All** |

- **Quantity modifiers (Endless Sky style):** these apply **only to the − / + buttons and the B/S keys, never to row clicks** (⌘-click stays multi-select). A click is 1; ⇧ ×5; ⌘ ×20; ⇧⌘ ×100; ⌥ = max or all.
- **Keyboard:** B buys and S sells the selected row; ⇧B is Buy Max; ⇧S is Sell All; arrow keys move between rows.
  - These keys are handled by `.onKeyPress` on the **focused trade table** (type-to-select disabled). They are inactive while a quantity field has focus, so plain-letter shortcuts never fire while typing.
- **"Why this price?"**: the row detail shows the price breakdown from legitimate information: base for the tech level, government, size, pressure, the resource if known, and your record.
- **Haptic** `.alignment` when the quantity reaches max affordable, max bays or max stock.
- **Footer:** bays used/free (respects "leave N bays empty"), cash available (respects "reserve money"), and a projected profit summary for the current hold at the target.
- **Recommendations strip** (Trade Intelligence): "Best buy here for {target}: Robots +412/bay" and "Best destinations within range for your hold." These are computed from known intel only, never from hidden information (fairness rule).
- **Jettison and Dump** live in the Held cell's context menu, with confirmation when a littering penalty applies.

### 4.3 Shipyard (⌘3)
- **Ship grid:** cards for each ship sold here, each with a vector portrait, key stats and net price after trade-in. Your current ship is marked "Yours."
- **Compare mode:** select two or more ships (⌘-click) for a side-by-side stat table with deltas, against your ship by default. This replaces the WinForms Info and Buy buttons.
- **Purchase review sheet:** one sheet replaces the C# chain of up to 8 prompts. It shows:
  - trade-in breakdown
  - a checklist of transferable unique equipment, each with its transfer cost (Morgan's laser, Lightning shield, Fuel compactor, Hidden bays, Quantum disruptor)
  - escape pod transfer
  - crew that won't fit
  - cargo that will be lost
  - insurance effects
  - final cost
  
  *Buy Ship* is disabled with an inline reason when blocked (debt, cash, quarters, reactor).
- **Also here:** escape pod purchase and insurance status.
- **Custom Ship Designer** (Windows 2.01 and Modern rulesets, only at the 5 shipyard systems): a split view.
  - Left: allocation steppers (weapon, shield and gadget slots, crew, fuel, bays, hull) with a live "units used" bar that turns yellow at 80%, orange at 90% and red over 100%.
  - Right: a live vector preview of the ship with the selected silhouette, and a costs breakdown (base, design fee, crowding penalty, trade-in, total).
  - Templates save as JSON files in Application Support.
  - Validation is shown inline. This replaces the hidden-arrow hints.

### 4.4 Outfitter (⌘4)
- Three sections (Weapons, Shields, Gadgets). Each shows **your slots**, filled or empty, as slot tiles, and the **items for sale**.
- **Drag and drop:** dragging an item onto a free slot asks to buy it; dragging an installed item onto the "sell" well asks to sell it. Buttons and keys do the same for keyboard and VoiceOver users.
- The detail pane shows the item's vector icon, description, power or charge, buy and sell price, and a "vs. current" comparison.

### 4.5 Crew (⌘5)
- **Crew quarters** are shown as seats: commander, hired mercenaries, special passengers (Wild, Jarek, Princess) with a "passenger" badge, and empty seats.
- **For hire:** mercenary cards with a portrait (a procedural avatar from a seeded shape and color generator, no faces from external art), skills as four bars (Pilot, Fighter, Trader, Engineer), and daily wage.
- An **Effective skills** panel explains each value: base, best crew member, gadget bonus and difficulty adjustment.
- *Hire* and *Fire* (fire asks for confirmation; special passengers can't be fired).

### 4.6 Bank (⌘6)
- **Loan:** current debt, maximum loan (with the reason, e.g. "Clean record: up to 25,000"), and Borrow and Repay sliders. Shows an interest projection ("Each warp costs 10% interest: 1,250 cr").
- **Insurance:** ship value, no-claim discount meter (to 90%), daily premium, and Buy / Stop (requires an escape pod; the reason shows inline).
- **Debt warnings** appear as a banner, not modal alerts.

### 4.7 Galaxy (⌘7, or the detachable window)
- **Rendering:** a full SwiftUI `Canvas` showing a deep-space background (procedural starfield and nebula, static unless animated ambience is enabled).
- **Systems:** drawn as small planets. Visited systems are blue, unvisited green, matching classic convention, and each also carries a distinct **glyph shape** for colorblind users. The current system has a ring, the target a crosshair, and the tracked system a flag. Wormholes are swirling vortices with dashed arcs to their partners.
- **Overlays:**
  - fuel range circle
  - multi-jump route polyline with hop markers
  - quest location markers
- **Heatmap modes** (segmented control): None, Price of {commodity}, Profit for current hold, Police, Pirates, Tech level, Last visited. Heatmap data comes from **known intel only**; never-visited systems use the Average-Price estimate the original showed, marked "estimate".
- **Interaction:**
  - scroll or drag to pan; pinch and ⌘+ / ⌘− to zoom; "Fit Range" and "Fit Galaxy" buttons
  - hover shows an overlay card (never a popover): name, government, tech, distance, jumps needed, known prices and best profit
  - click selects a target; double-click sets the target and moves focus to Warp (it **never warps directly**, because warping is irreversible); ⌥-click tracks
  - right-click opens a context menu: Set Target, Track, Plot Route, Find Prices
- **Find** (⌘F is context search: on Galaxy it finds systems, in the Logbook it searches the log, in Market it filters items; Game › Find System… ⌥⌘F always opens system search): a search field with autocomplete over system names, plus filters ("has shipyard", "quest here", "sells Robots").
- **Route planner:** pick a destination out of range, and Dijkstra over in-range hops plus wormholes computes the fewest-jumps route or the cheapest route, showing costs per hop. The engine still warps one hop at a time; the plan simply pre-selects the next target after each arrival.

### 4.8 Quests (⌘8)
- Active quests as cards: title, progress steps (for example Dragonfly: Baratas ✓ → Melina ✓ → Regulas → Zalkon), deadline countdowns (Gemulon, Experiment, Reactor) as gauges, reward, and "Show on Map". Completed quests are collapsible.
- Quest text is generated from engine state. This replaces the logic that lived inside the C# FormViewQuests.

### 4.9 Logbook (⌘9): tabs Captain's Log, Statistics, Achievements
**Captain's Log tab:**
- A chronological, searchable feed of `GameEvent`s grouped by day and system: trades with profit, encounters with outcome, quest steps, news, arrests.
- Optional flavor text: a template sentence, or on-device Foundation Models prose when enabled.
- Filters by category. Export to a Markdown file.

### 4.10 Logbook: Statistics and Achievements tabs
- **Statistics:** net worth over time (Swift Charts line), profit by commodity (bars), kills by type, days, distance travelled, systems visited, best trade, encounters won, fled and surrendered.
- **Achievements:** at least 30 local achievements in a grid of badges (vector-drawn), each with progress. Disabled for saves that have used cheats.

## 5. Travel, encounters and events

### 5.1 Transit
- After Warp, the detail area shows a **Transit view**: a ship-silhouette animation across a 20-tick progress track toward the destination (≈1.2 s total; instant with Reduce Motion or the "Fast travel" setting).
- An uneventful trip simply completes into the **Arrival report**.

### 5.2 Encounter mode
When an encounter starts, the detail area becomes the **Encounter view** and the sidebar is disabled with a "In encounter" label. No sheet is used.
```
┌ "At 7 clicks from Rhymus you encounter a pirate Hornet." ───────── [Pirate badge] ┐
│   YOU: Gnat "Shelby's Folly"                OPPONENT: Hornet                     │
│   [vector ship, shield bubble, hull scorch]   [vector ship facing left]          │
│   Hull ███████░░ 78%  Shields ██░░ 40%        Hull █████░ 61%  Shields ░ 0%       │
│ ──────────────────────────────────────────────────────────────────────────────── │
│  Combat log (scrolls, newest at the bottom, round numbers):                      │
│   R1  The Hornet fires — hit! −18 hull.   You fire — hit! −24 hull.              │
│   R2  The Hornet is fleeing.                                                     │
│ ──────────────────────────────────────────────────────────────────────────────── │
│  [Attack A] [Flee F] [Surrender S]      ☐ Auto-repeat (⌥A)        Stop  Esc       │
└──────────────────────────────────────────────────────────────────────────────────┘
```
- **Buttons per encounter type** follow the classic mapping (`docs/research/02` §3), using plain labels: "Interrupt" becomes **Stop**, "Int." is dropped. Return triggers the default action, which is **never destructive or illegal**: never Attack against police or traders, never Surrender. In hostile pirate encounters the default is Flee, and in peaceful ones it is Ignore.
- **Keys:** A attack, F flee, S surrender, I ignore, B bribe, U submit, T trade, P plunder, O board, D drink, M meet, Y yield. Each also appears as a help tag.
- **Animation:** laser beams, shield ripples, hull sparks and screen shake on heavy hits; under Reduce Motion these become a brief color flash. The fighter-crop "damage stripe" idea from the original returns as a **live scorch mask** whose coverage equals the hull percentage.
- **Tactical readout** (an optional QoL setting): before your first action, a small panel shows public information only, namely the opponent's class and visible weapons and shields, and your flee odds as a word (Good, Fair or Poor).
- **Resolve** button: runs auto-repeat until the encounter ends (Esc stops it).
- **Auto-repeat** (classic "continuous attack/flight"): repeats every 0.6 s until the state changes or the player presses Esc.
- **Sub-flows:**
  - Plunder: a sheet with the victim's cargo and quantity steppers.
  - Trade in orbit: a compact offer sheet.
  - Bribe: confirmation with the amount.
  - Submit to inspection: confirmation that lists what will be found.
  - Attacking police or traders: consent dialog with the consequence spelled out ("Your police record will drop to Criminal").
- **Tribbles:** scattered tribble sprites on the encounter view (purely cosmetic, clickable for a "squeek" sound).
- **Very rare encounters** (Marie Celeste, famous captains, bottles) get a distinct "special" badge and custom intro text.

### 5.3 Arrival report (replaces the chained alerts)
By default this is a **non-modal expanding card at the top of Bridge**. A sheet is used only when the report contains a decision or a critical event: arrest, escape pod, insurance payoff, reactor meltdown warning or game over. It contains, in order:
- the encounters summary
- news headline teaser
- costs paid at departure
- automatic repairs and fuel
- tribble events
- reactor warnings
- debt warnings or reminders
- police record changes
- quest progress

Each item is also posted to the log.

### 5.4 Special events
A **narrative sheet** with title, illustration (procedural vignette: planet or ship), the full story text from the classic strings, price, and *Accept* / *Decline*. Pure messages have just *Continue*.

### 5.5 Game over
A full-window cinematic card for each ending:
- Destroyed: the player's own ship, scorched and tumbling among hull-plate debris.
- Retired: an orbital sunset: the sun sinking behind a planet's limb through layered atmosphere.
- Moon: a cratered moon lit by a low sun, with a glass dome habitat and the parent planet in the sky.

Each is a 16:9 scene lit by a sun, with depth and atmosphere, built from the same planet and ship art as the rest of the game.
- Moon-girl, a cosmetic variant in Modern only, when retiring to the moon after completing the Princess quest (PRD §4.3).

It shows the score breakdown, the high-score result (with Ironman and ↺ markers), a career summary card that can be shared with `ShareLink` as an image, and actions New Game and Main Menu.

### 5.6 Retire
- **Game › Retire…** opens a confirmation sheet with a score preview: "Retiring now scores 41.3%".
- Cancel is the default button.

## 6. Alert taxonomy (classic 188 AlertTypes → new home)
| Class | Classic examples | New presentation |
|---|---|---|
| Validation / can't do | CargoIF, CargoNoEmptyBays, EquipmentIF, ShipBuyIF, DebtNoBuy, LeavingIF* | Disabled control plus inline reason (help tag and footer text). Never a modal. |
| Consent / risk | EncounterAttackPolice, EquipmentBuy/Sell, ShipBuyConfirm, CrewFireMercenary, InsuranceStop, WildWontStayAboard*, EncounterDumpWarning | `confirmationDialog(item:)` with the consequence stated. The destructive button gets the destructive role. |
| Outcome / info | EncounterYouWin, EncounterEscaped, PiratesBounty, JailConvicted…, Tribbles*, Reactor*, Antidote*, Debt reminders | Event feed + log + arrival report. Rare, important ones (arrest, insurance payoff, death) get a dedicated report sheet. |
| Narrative | Special-event strings (46), quest completions, passenger chatter | Narrative sheet / log entry |
| System | File errors, version too new | Standard `alert(item:)` with a recovery suggestion |
| Removed | AppStart splash, Egg, Cheater (moved to the cheat console), the unused types | — |

M0 produces `docs/specs/ALR.md`, mapping **every** AlertType by name. A test asserts the mapping is complete.

## 7. Visual language
- **Palette:** system semantic colors for the UI. The game art uses a curated "deep space" palette defined as asset-catalog color sets with dark and light variants:
  - space background: indigo → near-black
  - visited: cyan-blue; unvisited: green
  - wormhole: amber → magenta
  - danger: system red; profit: system green; loss: system red
  - the accent color is a warm "brass" gold, the merchant's color, set in `AccentColor`
- **Typography:** SF Pro text styles. Numbers use `.monospacedDigit()`. Newspaper headlines use New York (serif). The title wordmark is drawn in code.
- **Iconography:** SF Symbols for UI chrome. Custom vector glyphs (SwiftUI `Shape`s) for the 10 commodities, the equipment types and the encounter badges.
- **Art (ParsecArt):**
  - **Ships** are generated from their statistics: cargo bays, weapon, shield and gadget slots, crew quarters, fuel tanks, hull strength, price and tech level decide the hull's archetype (hauler, courier, interceptor, gunship, cruiser), beam, cargo modules, hardpoints, plating and engines, so a freighter looks like a freighter and a warship like a warship. They are sleek, realistic top-down machines, never insects: the ship names are game data and do not shape the art. Each is shaded under one light with plating, panel lines, engine plumes, cockpit glass and navigation lights, and has a shield bubble and a scorch mask. Ship pictures use the space their panel gives them.
  - **Planets** have a procedural gradient, bands or craters, clouds and atmosphere rim, seeded per system id, with styles by tech level (pre-agricultural: earthy; hi-tech: city lights on the night side).
  - **App icon:** a brass-rimmed parsec ring around a cargo-hauler silhouette on deep indigo, rendered from code with `ImageRenderer` at all sizes, including the macOS 27 glass/clear icon variants where supported [verify].
- **Liquid Glass:** system glass on the toolbar, sidebar and inspector only. Custom `.glassEffect` is limited to two floating elements: the Galaxy map HUD (zoom and heatmap controls) and the Encounter action bar. Content areas (tables, cards) use standard backgrounds. The system adapts glass automatically for Reduce Transparency. Verify this; don't hand-roll it.
- **Motion:** spring animations ≤0.35 s for UI. Number tickers for cash changes. Everything is gated by `accessibilityReduceMotion`. No matched-geometry transitions across NavigationSplitView detail swaps.

## 8. Sound design (Audio & Haptics extra)
- **Procedural SFX**, synthesized with no external samples (no licensing risk):
  - UI: click and tick
  - buy and sell: coin chime, pitch rising with the amount
  - warp: whoosh plus sub-bass swell
  - lasers: pulse, beam and military, each with a distinct timbre
  - shield hit, hull hit, explosion, alarm (low hull), arrest siren
  - newspaper: page rustle (filtered noise)
  - achievement: chime
- **Ambient music:** an optional generative pad that shifts mood docked, in transit and in combat. Off by default.
- **Settings:** master, effects and music volumes. Sound is muted when the app is inactive (optional).
- **Haptics:** quantity snap points, warp departure, heavy hit (`.levelChange`). These only work on Force Touch trackpads.

## 9. Accessibility
- Every control has a label, a value and a hint. Tables carry `.accessibilityLabel`s for each column.
- **Galaxy map:** `.accessibilityChildren` provides one element per system (label "Rhymus, visited, 8 parsecs, Democracy, Hi-tech"; actions Set Target, Warp, Track) plus custom rotors: In Range, Quest Locations, Wormholes, Visited, Unvisited.
- **Encounter:** each new combat round is announced with `AccessibilityNotification.Announcement` (macOS has no live-region modifier). Ship portraits have labels such as "Your Gnat, hull 78%, shields 40%".
- **Text Size:** macOS has no system Dynamic Type, so Settings › General offers an in-app **Text Size** (applied via `.dynamicTypeSize`). It is tested at its largest value.
- **Differentiate Without Color:** honor `accessibilityDifferentiateWithoutColor` by adding shapes and signs.
- **Audio cues:** each one (low-hull alarm, siren) has a visual twin.
- **Encounter lock:** while an encounter is active, the ⌘1–⌘9 menu items and Warp in the detached Galaxy window are disabled too.
- **Increase Contrast:** bolder strokes and higher-contrast map colors.
- **Color pairing:** every color code has a shape or text twin.
- **Keyboard:** full traversal, plus a visible focus ring on custom controls (`.focusable()` and `.focusEffectDisabled(false)`).
- **UI tests** walk each section and check that elements have labels.

## 10. Keyboard map
| Action | Keys |
|---|---|
| New Game / Open / Save / Save As / Export | ⌘N / ⌘O / ⌘S / ⇧⌘S / ⇧⌘E |
| Sections (Bridge…Logbook) | ⌘1…⌘9 |
| Toggle Sidebar / Inspector | ⌃⌘S / ⌃⌘I |
| Game Options… / Retire… | ⌥⌘O / (menu only) |
| Warp to target | ⌘J |
| Previous / next system in range | ⌘[ / ⌘] |
| Context search / Find System… | ⌘F / ⌥⌘F |
| Galaxy window | ⇧⌘M |
| Map zoom in / out / fit (map focused) | ⌘+ / ⌘− / ⌘0 |
| Newspaper | ⇧⌘N |
| Fill fuel / Repair hull | ⇧⌘F / ⇧⌘R |
| Market: buy / sell / buy max / sell all | B / S / ⇧B / ⇧S |
| Encounter actions | A F S I B U T P O D M Y, R = Resolve, Return = safe default, Esc = stop auto-repeat |
| Settings | ⌘, |

Shortcuts must not clash with standard macOS commands: ⌘C, ⌘A, ⌘H, ⌘M, ⌘Q, ⌘W, ⇧⌘G (Find Previous), ⌘[ and ⌘] (no navigation history, so they are free for cycling targets). Plain-letter keys are handled only by the focused view through `.onKeyPress`. M12 writes the audit to `docs/specs/UI-KEYS.md`.

### 10.1 Menu bar (spec in `docs/specs/MENU.md`)
- **Parsec Merchant:** About, Settings… ⌘,, Services, Hide, Quit (autosaves).
- **File:** New Game… ⌘N, Quick Start, Open Saved Game… ⌘O, Open Recent ▸, Save ⌘S, Save As… ⇧⌘S, Import…, Export… ⇧⌘E, Revert to Autosave. Close is standard.
- **Edit:** standard (Undo is disabled because the game has no undo; Copy is enabled for the log and stats).
- **View:** Sidebar, Inspector, sections ⌘1–⌘9, Galaxy Chart ⇧⌘M, map zoom, Enter Full Screen.
- **Game:** Warp ⌘J, Previous/Next Target ⌘[ ⌘], Track/Untrack, Find System… ⌥⌘F, Plot Route…, Fill Fuel ⇧⌘F, Repair ⇧⌘R, Newspaper ⇧⌘N, Options… ⌥⌘O, Retire…
- **Encounter:** enabled only during encounters. It mirrors the action bar with its single-key shortcuts, plus Auto-repeat and Resolve.
- **Window:** standard, plus Galaxy Chart and High Scores.
- **Help:** Parsec Merchant Help, How Prices Work, Keyboard Shortcuts, Credits & License, GitHub Project.

## 11. Onboarding and help
- **New Game wizard (sheet):**
  1. Commander name.
  2. Difficulty, with a plain-language description of each level.
  3. **Ruleset** (Modern, recommended; Windows 2.01 Classic; Original Palm 1.2.2), each with a bullet summary of how it differs.
  4. Skill allocation: each skill starts at 1, and you distribute 16 more points (20 total, maximum 10 per skill). Each skill shows what it does.
  5. Optional galaxy code or seed, Ironman toggle, and ship name.
  6. A summary step.
- **First-run tips:** real **TipKit** inline tips on Market, Galaxy and Warp the first time each is visited. They can be dismissed and reset in Settings.
- **In-app Help window** (SwiftUI, Markdown content; not an Apple Help Book): adapted from the classic in-game help text (research `03`), with a section per screen and a "How prices work" explainer.

## 12. Where each classic WinForms surface ends up
| Classic | New home |
|---|---|
| Main window: system info / target / dock / cargo / shipyard panels | Bridge (system, dock, target, offers) + Market + Shipyard |
| Galactic chart, short-range chart, Find, Track | Galaxy section/window + Bridge mini chart + ⌘F |
| FormCargoBuy / FormCargoSell / FormJettison | Market inline quantities; jettison and dump in the context menu |
| FormBuyFuel / FormBuyRepairs | Bridge dock gauges with sliders |
| FormShipList / Form_Shipyard (designer) | Shipyard grid + compare + purchase review; Designer |
| FormEquipment | Outfitter |
| FormViewPersonnel | Crew |
| FormViewBank / GetLoan / PayBackLoan | Bank |
| FormViewCommander / FormViewShip | Inspector (+ Logbook › Statistics) |
| FormViewQuests | Quests |
| FormViewHighScores | High Scores window |
| FormOptions | Game › Options… sheet (per save); app-wide items in Settings |
| FormNewCommander | New Game wizard |
| FormEncounter / FormPlunder | Encounter mode + plunder sheet |
| FormCosts | Warp help tag + Target card costs breakdown |
| FormAlert (188) | See §6 |
| Newspaper alert | Newspaper sheet |
| FormFind + "Cheetah" cheat console | ⌘F search; cheat console = typing `Cheetah` in Find opens a developer sheet (flags the save) |
| FormMonster / FormTest | Debug-only developer sheet (cheats enabled) |
| FormAbout / splash | About panel / Welcome view |
