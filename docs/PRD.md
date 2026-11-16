# Parsec Merchant: Product Requirements Document (PRD) v1.1

> **Audience:** Claude Code (Opus 5.5), running autonomously under `/goal`, and the human owner (GitHub: `megatih`).
> **Status:** Approved for execution, 2026-11-16. v1.1 includes the findings of two independent QA reviews. **Normative:** MUST and MUST NOT are hard requirements. SHOULD may be deviated from only with an ADR recorded in `docs/adr/`.
> **Read order for the agent:**
> 1. `CLAUDE.md`
> 2. `PROGRESS.md`
> 3. This PRD
> 4. `docs/design/UX-VISION.md`
> 5. `docs/research/01–06`, only as needed. Each file's **QA ERRATA** block overrides its own body.

---

## 1. Product summary
**Parsec Merchant** is a native macOS remake of *Space Trader*, the classic Palm OS trading and combat game by Pieter Spronck (2000–2005, GPL). It is built from the C# port "Space Trader for Windows 2.01" by Jay French and David Pierron. The local source is at `/Users/megatih/Downloads/SpaceTraderSource201` and is read-only.

**The game.** The player is a starship commander who starts with 1,000 credits and a Gnat. They trade ten commodities across a galaxy of 120–128 systems, upgrade ships and equipment, hire crew, take loans and buy insurance, and face pirates, police and traders. The C# version has 46 special-event types, which group into about 15 quest chains. Endings are death, retirement, or buying a moon at Utopia.

**The goal is the definitive Mac version.** It contains every mechanic of the chosen ruleset and presents it through a modern, beautiful, keyboard-friendly, accessible macOS 27 interface. That interface removes the original's friction: chained modal dialogs, cramped panels and hidden information. It is **not** a replica of the WinForms UI.

### 1.1 Goals
- **G1 Faithful rules.** Three selectable rulesets (§4). Every formula, table and quest is implemented and tested against the source, including a differential harness that runs the C# code (§8.4).
- **G2 Best-in-class Mac UX** as described in `docs/design/UX-VISION.md`.
- **G3 Native technology.** SwiftUI on macOS 27, Swift 6 strict concurrency, Liquid Glass applied by the system, Swift Charts, Canvas, AVAudioEngine, TipKit, App Intents and Foundation Models (optional). Zero third-party dependencies.
- **G4 Extras.**
  - Trade intelligence.
  - Procedural audio and haptics.
  - Local achievements, statistics and the captain's log.
  - Optional on-device AI flavor text.
  - Quick Start, Ironman mode and shareable galaxy codes.
- **G5 Engineering quality.** A spec-driven, deterministic engine with a seeded RNG, scheduled coverage gates, fuzzing, zero compiler warnings and automated gates.
- **G6 Open-source release.** A public GitHub repo `megatih/parsec-merchant` under GPL-2.0-or-later, with an ad-hoc-signed release zip and a complete README.

### 1.2 Non-goals
- **No paid Apple services.** No Mac App Store, Game Center, iCloud, StoreKit, notarization or Developer ID (there is no paid developer account).
- **No iOS or iPadOS in v1.** Keep the engine platform-agnostic so a port remains possible.
- **No network play.** No multiplayer or network features. The network is used only for `gh`, `brew` (the harness) and fetching reference sources.
- **No original art.** None of the original artwork or images may be reused (© Alexander Lawrence and William W. Connors; not GPL).
- **No legacy saves.** No import of .NET `BinaryFormatter` saves.

## 2. Locked decisions (made by the owner; do not revisit)
| # | Decision |
|---|---|
| D1 | **Name.** "Parsec Merchant". Display name `Parsec Merchant`; bundle id `io.github.megatih.ParsecMerchant` (Debug: `…ParsecMerchant.debug`); repo `parsec-merchant`. Credit line: "Based on Space Trader by Pieter Spronck." "Space Trader" is a HermitWorks trademark and MUST NOT be the product name; use it only in credits and descriptions. |
| D2 | **Art.** All-new vector and procedural art drawn in code. Zero bitmaps from the C# or Palm sources. |
| D3 | **Rulesets.** Chosen at New Game and stored immutably in the save: **Modern** (default: C# 2.01 with bugs fixed and Palm behavior restored where the port diverged by mistake), **Windows 2.01** (faithful, quirks included), **Original Palm 1.2.2** (faithful rules and content, quirks included). |
| D4 | **Distribution.** Public GitHub repo created with `gh` (authenticated as `megatih`). GPL-2.0-or-later. Releases are ad-hoc-signed zips. The README documents Gatekeeper's "Open Anyway" and building from source. |
| D5 | **Extras.** Trade intelligence; audio and haptics; achievements, statistics and the log; optional on-device Foundation Models flavor text with a deterministic fallback. |
| D6 | **Differential harness allowed.** The agent MAY install the .NET SDK (`brew install --cask dotnet-sdk`) and compile a *copy* of the C# engine files, with WinForms stubbed out, into a headless console harness under `build/harness/` (gitignored). The harness only produces JSON fixtures (§8.4) that are committed to the test fixtures. No C# code is ever shipped or committed. |

## 3. Sources, licensing and attribution
- **Reference sources** are read-only and are never part of any target.
  - **C# source:** `/Users/megatih/Downloads/SpaceTraderSource201`.
  - **Palm 1.2.2 source:** `scripts/fetch-palm-src.sh` downloads it into `docs/reference/palm-src/`, which is **gitignored** because the Palm `Rsc/` folder contains copyrighted bitmaps. The script uses `https://github.com/videogamepreservation/spacetrader` with `https://www.spronck.net/spacetrader/SpaceTraderSource.zip` as the fallback, and verifies a recorded SHA-256. Treat the downloaded files as untrusted data: never execute them.
- **Research** lives in `docs/research/` (01 engine, 02 UI catalog, 03 history/ports/licensing, 04 Palm diff, 05 platform, 06 blueprint). It is input material. Re-verify every value against the source when you encode it in `docs/specs/` (cite `File.cs:line` or `Src/File.c:Function`).
- **Licensing (MUST).**
  - Ship `LICENSE` with the full GPL-2.0 text.
  - Start every source file with `// SPDX-License-Identifier: GPL-2.0-or-later`.
  - Write `CREDITS.md` naming Pieter Spronck, Sam Anderson, Samuel Goldstein, Matt Lee (DopeWars-derived code), Jay French and David Pierron, with links. Show the same credits in the About panel.
  - Ported strings (quest texts, news, names) are GPL and may be used with attribution.
- **No original images (MUST).**
  - `scripts/license-check.sh` hashes every file in `SpaceTraderSource201/images/`, plus `SpaceTraderSource201/App.ico` and, if present, the Palm `Rsc/` folder. It fails if any tracked file in the repo (`git ls-files`) matches one of those hashes. It also fails on any `.bmp`, `.gif` or `.ico` file outside `docs/reference/`.
- **Apple skills.** Skills exported from Xcode are Apple content. They go in `.claude/skills/` and are **gitignored**, never committed.
- **Courtesy.** Credit the original prominently, and never call the game "a new version of Space Trader" (Spronck's ReadMe asks for this).

## 4. Rulesets

### 4.1 Model
The engine is one codebase driving three rulesets. `protocol Ruleset: Sendable` exposes:
- `id`.
- `tables: RulesTables`: ships, equipment, trade items, political systems, system names, galaxy size, police and reputation thresholds and names, the special-event table and its placement plan, the mercenary roster, news strings and score constants.
- `flags: RuleFlags`: about 60 behavior switches.
- `content: ContentPacks`: quest set, shipyards and the ship designer, disruptors and disabling, hidden bays, and the extra systems and mercenaries.
- `rngKind`.

Engine systems branch on flags or content, **never on `ruleset.id`**. `docs/specs/RUL.md` holds the diff matrix:
- one row per behavior;
- columns for Modern, Windows 2.01 and Palm 1.2.2, each giving a value and a source citation;
- an ID `MOD-nnn` and a test for every Modern deviation;
- a **keep/fix row for each of the 21 port bugs** in research 01 §13 and for every errata item.

### 4.2 RNG fidelity
- **Windows 2.01** uses `DotNetRandom`, an exact port of .NET's seeded `System.Random`: the Knuth subtractive generator, with `Next(0,0)==0`. Modern .NET still uses this legacy algorithm whenever a seed is supplied, so the harness can confirm it.
- **Newspapers** use Pieter's `Rand`/`GetRandom2` exactly as each source implements it:
  - C#: 64-bit multiply-with-carry; the output is never negative.
  - Palm: the effective UInt16 LCG `SeedY = (30903*SeedY) & 0xFFFF`, with `RandSeed` parameters truncated to UInt16.
- **Palm game logic** used the unseeded ROM `SysRandom`. The Palm ruleset therefore aims to be **faithful to the rules, not to the random-number sequence**, using a documented LCG stand-in.
- **Modern** uses `Xoshiro256**`.
- **Call order.** Within each ruleset, the order of RNG calls SHOULD mirror the source, for example game construction order (errata 01 #4) and opponent generation order (Palm order per research 04).

### 4.3 Modern ruleset: required fixes (closed list; additions only via RUL.md audit rows with rationale)
| ID | Fix compared with Windows 2.01 | Ref |
|---|---|---|
| MOD-001 | Reset `Commander.PriceCargo` whenever the hold is cleared (ship trade; the Flea after an arrest or escape pod). This closes the infinite-money trade-in exploit. | 01 §13.1 |
| MOD-002 | The arrest fine is never negative: `min(80, max(0, −record))`, minimum 500. | 01 §13.2 |
| MOD-003 | Police record decay follows Palm's per-warp rule, applied in DoWarp outside the singularity guard (errata 04 #4). | 04 §3 |
| MOD-004 | The hardened (Scarab) hull halves damage **only for the player's ship**. | 01 §13.4 |
| MOD-005 | Random skill increases can reach 10. | 01 §13.5 |
| MOD-006 | Special resources affect quantities and prices whether or not the system has been visited. Only the *display* stays hidden until you visit. | 01 §13.7 |
| MOD-007 | Restocking checks each system's own `ItemTraded`. | 01 §13.8 |
| MOD-008 | Trade-in-orbit purchase quantities are capped using the in-orbit price and the free bays, so cash never goes negative. | 01 §13.10 |
| MOD-009 | The Kravat/Wild engineer-10 police boost checks whether Wild is aboard the **player's** ship. | 01 §13.11 |
| MOD-010 | The Marie Celeste exclusion is tested against the **destination** system. | 01 §13.12 |
| MOD-011 | Wild requires a real laser (Beam, Military or Morgan's); disruptors don't count. | 01 §13.13 |
| MOD-012 | Pirate looting can't crash when hidden bays exceed the cargo. | 01 §13.16 |
| MOD-013 | The 5 shipyards go on 5 distinct hi-tech systems. | 01 §13.17 |
| MOD-014 | The reactor damage multiplier is a real factor, `1+(D+1)×(D<Normal?0.25:0.33)`, applied before truncating. | 01 §13.19 |
| MOD-015 | The ×100/90 sell-price recalculation only happens if the commander was a criminal before EraseRecord or before delivering Wild. | 01 §13.20 |
| MOD-016 | Mercenaries lost to jail or the escape pod relocate the same way fired mercenaries do. | 01 §13.21 |
| MOD-017 | **Fuel and repair cost columns restored to the Palm values.** The fidelity audit confirmed the C# port swapped them. The wormhole tax follows the fuel cost. | 04 §1–2, errata |
| MOD-018 | The debt warning and the 5-day loan reminder can both fire. Both go into the arrival report. | 04 §3 |
| MOD-019 | **Worth uses trade-in value**, Palm `CurrentWorth`: ship trade-in value plus cargo cost basis plus cash minus debt, plus the moon if bought. This affects loans, fines, bribes, pirate scaling, the moon offer and the score. | errata 04 #1 |
| MOD-020 | The Wasp can appear as a random opponent: weight over indices 0..9, like Palm. | errata 01 #1 |
| MOD-021 | Integer price and quantity arithmetic matches the source exactly. Floating point is used only where the source uses it (insurance and interest), with explicit truncation. | |

**Kept as designed in Modern** (documented in RUL.md):
- absolute price variance (#9);
- Morgan's laser and the Quantum disruptor can hurt the Scarab (#14);
- a singularity jump costs no day, fuel or fees (#15);
- C#'s −1 skill adjustment on Hard (errata 04 #2).

**The "moon-girl" ending.** `GameEndType.BoughtMoonGirl` exists in C# but never fires. In Modern only, a cosmetic variant ending appears when you retire to the moon after completing the Princess quest. The score is the same.

**Quality-of-life features** (not rule changes; all rulesets):
- multiple save slots;
- autosave;
- optional **Ironman** mode: one save, no manual loading, and a badge on the high-score entry;
- a "reloaded" marker ↺ on high scores when a non-autosave was loaded (`reloadCount`);
- an optional, purely cosmetic ship name.

### 4.4 Palm 1.2.2 content pack (research 04 and its errata)
**Galaxy and data.**
- 120 systems on a 150×110 galaxy, `MINDISTANCE 6` (squared-distance test), integer square root with rounding.
- 37 events in Palm index order, with Palm's placement plan *including its placement bugs*.
- One mercenary per system (none at Kravat), 31 crew slots, and no C# extra systems or mercenaries.
- No Sculpture, Princess, Scorpion, disruptors, disabling, hidden bays, shipyards or ship designer.

**Formula differences.**
- Palm's `CRIMINALSCORE` −10 family of constants.
- The backwards opponent-equipment roll.
- The market quantity uses the size of system *i*.
- Palm formulas for tribbles, the newspaper, the score and arrests; worth based on trade-in value.
- A trader-skill discount on ships.
- Damage is based on Engineer skill; in-flight repairs are halved; cloaking gives +2.
- The fuel compactor sets fuel to 18.
- The open-quest cap of 3.
- No passenger impatience.
- Zeethibal is paid when `WildStatus == 2`.
- On Hard the skill adjustment is 0.

**Texts.** Palm's quest and news texts live in binary `Rsc` files. For events Palm shares with C#, reuse the C# strings, and note this in RUL.md.

## 5. Functional scope (engine)
Every subsystem below is specified in `docs/specs/<AREA>.md` with requirement IDs, and is implemented and tested for each ruleset it applies to. Research 01 and 04 (with errata) are the starting checklists.

| Area | Spec | Contents (non-exhaustive) |
|---|---|---|
| RNG | RNG.md | DotNetRandom, Palm LCG stand-in, PieterRand (C# and Palm variants), Xoshiro, seeding, serialization, test vectors |
| Galaxy | GAL.md | generation, placement with retry semantics, the wormhole ring, special events and shipyards, mercenaries, the start system, pressures |
| Economy | ECO.md | standard, sell and buy prices, criminal adjustments, quantities, restock, buy/sell/dump/jettison, littering, trade in orbit, leave-empty bays, reserve money, the "why this price" breakdown (legitimate information only) |
| Ships | SHP.md | specs, slots, equipment buy/sell, prices and tech gating, worth (per flag), purchase and trade-in with transfers and the escape pod, fuel, repairs, the custom ship designer |
| Crew | CRW.md | effective skills, hire/fire, wages, relocation, skill changes, tonics |
| Bank | BNK.md | max loan, borrowing and repayment, interest, debt limits and warnings, insurance and the no-claim bonus |
| Travel | TRV.md | warp checks and costs, wormholes, singularity, transit of 20 (C#) or 21 (Palm) clicks, per-click repairs, fabric rip, arrival pipeline order, IncDays |
| Encounters | ENC.md | encounter determination (fixed, random and very rare), opponent generation, all 35 encounter types with their state machine and actions |
| Combat | CMB.md | to-hit, damage, shields, disabling, flee and escape, outcome updates, auto-repeat, kills, bounty, scooping, plunder |
| Police | POL.md | records, reputation, inspection, submitting, fines, bribes, yielding, surrender, arrest, jail |
| Quests | QST-*.md | every special event in each content pack: preconditions, price, status codes, steps, rewards, failure paths and newspaper hooks |
| News | NEWS.md | cost, ordering, headlines, mastheads, PieterRand |
| Options | OPT.md | all classic options |
| Scoring | SCORE.md | worth, score per ruleset, endings including the Modern moon-girl variant, high scores, Ironman, ↺ |
| Cheats | CHEAT.md | the C# "Cheetah" codes and the Palm cheats. Using cheats flags the save and disables achievements and high scores. |
| Alerts | ALR.md | all **188** C# `AlertType`s, each mapped to CommandError, Confirmation, GameEvent, narrative or removed (UX-VISION §6) |
| Rulesets | RUL.md | the diff matrix, the MOD list, keep/fix rows, content packs |
| Saves | SAV.md | envelope, schema version, migration, autosave, slots, import/export, corruption handling, Ironman |
| Insights | INT/LOG/ACH/STAT/LLM.md | trade intelligence (player knowledge only), log, achievements, statistics, flavor text |
| UI | UI-*.md, MAP.md, A11Y.md, UI-KEYS.md, AUD.md, MENU.md | UI requirements by section, the map, accessibility, keyboard, audio, the full menu bar |

**Logic that lived in WinForms forms moves into the engine** as commands and pure `preview` queries: cargo caps, fuel and repair purchases, the escape pod price, max loan, net ship price, quest text parameters, special-event dispatch, and cheats.

## 6. Architecture

### 6.1 Repository layout (target)
```
/ (repo root = /Users/megatih/Documents/XcodeProjects/SpaceTraderMac)
├── CLAUDE.md PROGRESS.md GOAL.md README.md LICENSE CREDITS.md CHANGELOG.md .gitignore .swiftlint.yml
├── Config/ Info.plist (UTType + doc type, merged) · Shared.xcconfig · Local.xcconfig.example (DEVELOPMENT_TEAM; Local.xcconfig gitignored)
├── scripts/ verify.sh final-check.sh coverage-gate.sh spec-trace.sh warnings-gate.sh license-check.sh
│            fetch-palm-src.sh release.sh make-icon.sh harness.sh
├── docs/ PRD.md design/ research/ specs/ adr/ reference/{csharp-index.md, palm-src/ (gitignored)} QA-REPORT.md screenshots/
├── harness/  (C# harness *project skeleton*: .csproj template, stubs, driver — no copied C# game code; build output in build/harness)
├── Packages/ParsecKit/  (swift-tools 6.x, platforms .macOS("27.0"), Swift 6 mode, treatAllWarnings(as: .error), zero deps)
│   ├── Sources/ParsecEngine/      pure: Model, RNG, Rulesets/{Modern,Windows201,Palm122}, Systems/*, Engine/*
│   ├── Sources/ParsecPersistence/ SaveEnvelope, codec, migrator, SlotStore (URL-injected), HighScoreStore
│   ├── Sources/ParsecInsights/    TradeIntel, RoutePlanner, Stats/Log folds, Achievements, TemplateFlavor
│   ├── Sources/ParsecArt/         SwiftUI Shapes/Canvas drawing (ships, planets, glyphs, icon); no game state
│   ├── Sources/ParsecAudio/       procedural synthesis (nonisolated, allocation-free render), SFX/music generators
│   ├── Sources/pmsim/             executable: fuzz | bench | replay | scenario | bot | dump-galaxy
│   └── Tests/  ParsecEngineTests ParsecScenarioTests ParsecPersistenceTests ParsecInsightsTests ParsecArtTests ParsecAudioTests
│               Fixtures/{saves/v*/, golden/, harness/, rng-vectors.json}
├── SpaceTraderMac/       app target (synchronized): App/ Session/ Features/* Intents/ Resources/
├── SpaceTraderMacTests/  GameSession and presentation-routing tests (Swift Testing)
└── SpaceTraderMacUITests/ XCUITest flows + accessibility audit
```
**`.gitignore` MUST include:** `build/`, `DerivedData/`, `Packages/ParsecKit/.build/`, `.swiftpm/`, `dist/`, `*.xcresult`, `.DS_Store`, `xcuserdata/`, `*.xcuserstate`, `.claude/skills/`, `docs/reference/palm-src/`, `Config/Local.xcconfig`. This MUST be in place **before the first push**.

### 6.2 Engine (ParsecEngine), MUST
- **State.** Value types only. `GameState: Codable, Sendable, Equatable` holds: ruleset id, difficulty, day, `RNGState`, galaxy, commander and ship (including the optional cosmetic name), mercenaries, typed quest state, options, news, `phase`, event log, player intel, `cheatsUsed`, `reloadCount` and `ironman`.
  - No singletons and no reference types.
  - No imports of SwiftUI, AppKit or Combine.
- **Phases.** `GamePhase = .docked | .inTransit(TransitState) | .encounter(EncounterState) | .gameOver(GameEnd)`. Transit is resumable: the modal loop in C# `Game.Travel` becomes a state machine.
- **API.**
  - `mutating func perform(_ c: Command, acknowledging: Set<WarningID> = []) -> StepResult`, where `StepResult = {events, decision: PendingDecision?, rejection: CommandError?}`.
  - `func preview(_:) -> Preview` is pure.
- **Two-phase confirmations.** A risky command sent without an acknowledgement returns `.confirm(Confirmation)` and **does not change any state**.
- **`PendingDecision`** covers: special event, newspaper, trade in orbit, plunder, scoop, arrival report, game over. While one is pending, only commands that resolve it are accepted.
- **No user-facing strings in the engine.** It emits typed events and errors only; the app localizes them.
- **Determinism.** The same ruleset, seed and command sequence MUST produce an identical canonical state hash: SHA-256 of sorted-key JSON, computed in the tests and in `pmsim`. The engine itself stays dependency-free.
- **Invariants** (checked in debug builds and asserted by the fuzzer):
  - cash ≥ 0 (a quirk that allows otherwise must be documented as a flag);
  - cargo ≤ bays;
  - all quantities ≥ 0;
  - 0 ≤ hull ≤ max;
  - crew ≤ quarters;
  - the phase is valid;
  - every quest status is within range.

### 6.3 Project setup ladder (M0): follow in order; record the outcome in ADR-0001
1. **Rename settings only; keep the folder, target and scheme names `SpaceTraderMac`.**
   - `PRODUCT_NAME = "Parsec Merchant"` and `PRODUCT_MODULE_NAME = ParsecMerchant`.
   - `INFOPLIST_KEY_CFBundleDisplayName = "Parsec Merchant"`.
   - Bundle ids: `io.github.megatih.ParsecMerchant`, with `[config=Debug]` → `….debug`, plus `.Tests` and `.UITests`.
   - `TEST_HOST = $(BUILT_PRODUCTS_DIR)/Parsec Merchant.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Parsec Merchant`.
   - Update the Products group entry.
   - `SWIFT_VERSION = 6.0` for all targets.
   - `MACOSX_DEPLOYMENT_TARGET = 27.0` everywhere.
   - `ENABLE_USER_SELECTED_FILES = readwrite`.
   - Remove `REGISTER_APP_GROUPS`.
   - `INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.games`.
   - Copyright notice (GPL).
   - `INFOPLIST_FILE = Config/Info.plist`.
   - Move `DEVELOPMENT_TEAM` into an optional `Config/Local.xcconfig` (gitignored; commit an example file) so that public clones build with automatic local signing.
   - Remove the SwiftData template.
2. **Link the package by editing `project.xcproj`.** A top-level `"packages": [{ "kind": "local", "path": "Packages/ParsecKit" }]` is accepted (verified). The product-to-target link syntax is **undocumented**, and `xcprojformatter` silently drops unknown keys, so neither it nor `-list -json` counts as proof.
   - **Proof** is a unit test in `SpaceTraderMacTests` that calls a `ParsecEngine` symbol and passes under `xcodebuild test`.
   - At most 6 attempts, with a git checkpoint before each.
   - **Shortcut:** if the owner completed the pre-flight step (GOAL.md: adding the local package in Xcode), copy that canonical syntax to link the other products.
3. **Fallback: xcodegen.** Write `project.yml` with `packages: { ParsecKit: { path: Packages/ParsecKit } }` and per-target `dependencies: - package: ParsecKit, product: ParsecEngine`. Generate the classic project, delete `project.xcproj`, and keep the target names.
4. **Last resort: ask the owner.** Ask the owner to add the package in Xcode (File › Add Package Dependencies… › Add Local…). Print `BLOCKED: …` (§11). Never compile engine sources into the app target.

### 6.4 Persistence (ParsecPersistence)
**Shoebox model (ADR-0002).** Everything lives in the sandbox container under `Application Support/Parsec Merchant/`:
- `Saves/slot-<uuid>.parsecsave`, keeping 3 rotating backups.
- `Saves/autosave.parsecsave`, written after each docking or arrival, and on quit through `applicationShouldTerminate` on an `NSApplicationDelegateAdaptor`.

**Format.** UTF-8 JSON with sorted keys, shaped `{format:"parsec-merchant-save", schemaVersion, appVersion, rulesetID, summary{commander, day, worth, system, ironman}, state}`.
- Writes are atomic.
- The `SaveMigrator` chain operates on raw JSON.
- Fixtures for every schema version stay in the tests forever.
- Unreadable files move to `Corrupt/`; never delete them.

**UTType** `io.github.megatih.parsecmerchant.save` (`.parsecsave`):
- Import and export use `fileImporter` and `fileExporter`.
- Opening a save from Finder imports it into a slot through the delegate's `application(_:open:)`.

**High scores** are the top 10 per ruleset. Achievements are stored as JSON. App-wide settings go in `UserDefaults`.

### 6.5 App layer
- **`GameSession`** is an `@Observable @MainActor final class` that owns the engine, the presentation state, the feed and the services (Save, Audio, Haptics, Achievement, Flavor).
  - Engine calls are synchronous.
  - Heavy pure work, such as route planning or folding statistics, runs off the main actor on Sendable snapshots.
- **Scenes, sections, the full menu bar, the map, encounter mode, sheets and the keyboard map** follow UX-VISION.
  - **No `.popover`** anywhere.
  - **Every interactive element** has an `.accessibilityIdentifier`.
- **App Intents:** "Continue Game" and "Show Commander Status". These also give the build a real AppIntents dependency.
- **TipKit** provides the first-run tips.
- **Debug-only launch arguments:**
  - `-PMSeed <n>`
  - `-PMScenario <name>`
  - `-PMFlavor template`
  - `-PMFastTravel`
  - `-PMAudio off`
  - `-PMResetState` (wipes the sandbox data of the Debug build)
- **Localization:** `Localizable.xcstrings` (English), plus support for the pseudo-language QA run.

### 6.6 Extras
- **Trade intelligence (INT).**
  - Price snapshots for each visited system and day; newspaper hints.
  - Sparklines, map heatmaps, profit per bay, best buys and destinations.
  - A route planner: Dijkstra over in-range hops plus wormholes, minimizing jumps, cost or risk.
  - "Why this price" breakdown.
  - **Fairness:** only information the player has legitimately seen, plus the standard-price estimates shown on the Average Price List. Never hidden RNG or unvisited actual prices.
  - A **tactical readout** before combat shows public information only: the opponent's class and visible equipment, and your flee odds as a word. It is a QoL option and can be turned off.
- **Audio (AUD).**
  - Procedural synthesis in `ParsecAudio`. Render code is `nonisolated` and allocation-free.
  - A test calls the render function off the main thread.
  - No sample files.
  - Optional generative music, off by default.
  - Haptics via `NSHapticFeedbackManager`.
  - Every audio cue has a visual twin.
- **Achievements (ACH):** at least 30, as pure folds over the log, disabled when cheats are used. Suggested set:
  - First profit; net worth of 10k, 100k and 1M.
  - Each quest chain completed; buying the moon.
  - Defeating a Wasp; surviving below 10% hull.
  - Clean→Hero; reaching Villain.
  - Paying off a loan.
  - Visiting 50 systems; visiting every system.
  - Using a wormhole.
  - Winning on Hard; winning on Impossible.
  - Trading every commodity; reaching 1M tribbles.
  - Finding the Marie Celeste; meeting all three famous captains.
  - Escape-pod survivor; building a designer ship.
  - Finishing an Ironman game.
- **Statistics and Log (STAT, LOG):** folds over the log. The log exports to Markdown. A **career summary card** can be rendered with `ImageRenderer` and shared through `ShareLink`.
- **Flavor (LLM).**
  - `FlavorProvider` with two implementations:
    - `TemplateFlavorProvider`: deterministic.
    - `FoundationModelsFlavorProvider`: behind `#if canImport(FoundationModels)` and an availability check, with a 4 s timeout and fallback.
  - Results are cached in the log, and flavor never changes game state.
  - Tests force the template provider.
- **Galaxy code:** a short string encoding ruleset plus seed, shown in Bridge and Settings and accepted by the New Game wizard, so friends can play the same galaxy. **Quick Start** on Welcome uses Modern, Normal and balanced skills.

## 7. Spec-driven workflow (MUST)
1. **Requirement format.** Each requirement is one bullet: `- **ECO-012** {M2} [M][W][P] <testable statement> (source: Game.cs:534)`.
   - `{Mn}` is the milestone that must satisfy it.
   - `[M][W][P]` mark which rulesets it applies to.
   - `[UI]` marks requirements covered by app or UI tests.
   - `[manual]` marks requirements covered by a QA-REPORT row with a screenshot.
   - ID regex (use `/usr/bin/grep -E`, not shell aliases): `\*\*[A-Z][A-Z0-9]*(-[A-Z0-9]+)*-[0-9]{3}\*\*`.
2. **Spec timing.** M0 writes **the skeleton of every spec file plus the full RNG, GAL, ECO, SHP, CRW and BNK specs**. Each later milestone begins by completing its own area specs. The ≥400-ID total is checked at the end of M5.
3. **`docs/reference/csharp-index.md`** lists every C# method that contains game logic, with `File.cs:line` and its purpose.
4. **Tests cite requirement IDs.**
   - Swift Testing: `@Test("ECO-012 …")`.
   - XCUITest: `XCTContext.runActivity(named: "UI-007 …")` or a `// covers: UI-007` comment.
   - `[manual]` IDs: a QA-REPORT row.
5. **`scripts/spec-trace.sh`** reads the current milestone from PROGRESS.md. It fails if any ID tagged `{M≤current}` (and not `[manual]`) is unreferenced by a test, or if a test references an unknown ID. At M13 it requires **every** ID to be traced.
6. **When code exposes a spec error,** fix the spec first, citing the source, then fix the code.

## 8. Quality gates

### 8.1 `scripts/verify.sh`
It prints `PASS`/`FAIL` per step and ends with `ALL GATES PASSED` and `EXIT=0` (or `GATES FAILED` and `EXIT=1`). It writes only under `build/` and `.build`.

| Mode | Steps | When |
|---|---|---|
| `--quick` | 1, 2 (tests without coverage), 6 | between small steps |
| default | 1–7 | before every commit |
| `--ui` | 1–8 | at the end of M7, M8, M9, M12 and M13, and in final-check |

1. `swift build --package-path Packages/ParsecKit`. Warnings are errors via `swiftSettings: [.treatAllWarnings(as: .error)]`.
2. `swift test --package-path Packages/ParsecKit --enable-code-coverage`, then `scripts/coverage-gate.sh`. The gate parses the JSON at `swift test --show-codecov-path` and sums the line counts per module path (`/Sources/ParsecEngine/` …). **Schedule:**

   | Module | Not enforced | ≥85% | ≥90% |
   |---|---|---|---|
   | Engine | through M1 | from M2 | from M3 |
   | Persistence | through M5 | from M6 | — |
   | Insights | through M9 | from M10 | — |

   The script reads the current milestone from PROGRESS.md. These thresholds are *scheduled*, not weakened.
3. **Fuzz:** `swift run --package-path Packages/ParsecKit -c release pmsim fuzz --games 2000 --seed 1 --ruleset all`.
   - "all" means every ruleset implemented so far: Windows 2.01 from M3, and all three from M5. Before M3 the fuzz step is a no-op PASS.
   - Each game runs until it ends or for 3,000 commands, using a random legal-command policy.
   - Every 50th game is replayed and its state hashes compared.
   - Zero invariant violations and zero crashes allowed; budget 180 s.
4. **App build and tests:** `xcodebuild -project SpaceTraderMac.xcodeproj -scheme SpaceTraderMac -destination 'platform=macOS' -derivedDataPath build/DD -resultBundlePath build/results/app.xcresult build test -skip-testing:SpaceTraderMacUITests SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`.
   - Then `scripts/warnings-gate.sh` counts only compiler and linker diagnostics: lines matching `^/.+:[0-9]+:[0-9]+: warning:` or `^ld: warning:`, or warnings in the xcresult build results.
   - Tool noise such as `appintentsmetadataprocessor` is out of scope by definition.
   - If the project is generated by xcodegen, use the generated project name.
5. **`scripts/spec-trace.sh`.**
6. **`swiftlint --strict`** with the committed `.swiftlint.yml`:
   - `excluded: [.build, "**/.build", build, docs, harness]`
   - opt-in rules `force_unwrapping` and `force_try`
   - a custom rule forbidding `^import (SwiftUI|AppKit|Combine)` in `Packages/ParsecKit/Sources/ParsecEngine/`
   - relaxed `file_length`, `type_body_length`, `line_length` and `identifier_name` for `**/Tables/*.swift` and the test fixtures
7. **`scripts/license-check.sh`.**
8. **UI tests:** `xcodebuild … test -only-testing:SpaceTraderMacUITests -resultBundlePath build/results/ui.xcresult`.
   - Screenshots are exported only when `PM_EXPORT_SCREENSHOTS=1`, via `xcrun xcresulttool export attachments`, and never inside verify.
   - If macOS blocks automation, follow the §11 blocker protocol.

**Performance** is checked by `pmsim bench` (release build, N=1000, median measured with ContinuousClock): engine `perform` median under 0.5 ms; a full arrival pipeline under 5 ms. An app-level map-render benchmark lives in a release-configuration XCTest `measure` block, with a baseline recorded in M8: median frame under 8 ms. Benchmarks run at the end of each milestone from M8 on, and in final-check.

### 8.2 Test strategy
- **Golden tests:** table-driven `@Test(arguments:)`, with expected values from the harness (Windows 2.01) or worked out by hand from cited sources (Palm, Modern).
- **RNG vectors:** the first 20 outputs per generator for fixed seeds. DotNetRandom is confirmed by the harness.
- **Scenario DSL** covers:
  - every quest chain under every ruleset that has it, including failure paths;
  - every `EncounterType` and action transition;
  - arrest, the escape pod, every ending, Ironman, ↺.
- **Property and fuzz tests:** invariants, plus save round-trips that are byte-identical.
- **Persistence:** fixtures for every schema version, migration, corruption, slot rotation.
- **App:** routing for every `PendingDecision` and every ALR mapping, with an exhaustive switch and a test.
- **UI flows:**
  1. New Game, buy, warp, arrive.
  2. `-PMScenario pirateAmbush`, attack until resolved.
  3. Save and load.
  4. Settings and Game › Options.
  5. Galaxy: hover, select, set target, warp with ⌘J.
  6. Accessibility: walk every section, check labels, and call `try app.performAccessibilityAudit()`.
  7. Text Size set to its largest value; layouts must not clip, verified with screenshots.
- **Art:** `ImageRenderer` determinism and non-empty checks for each ship type, planet style and the icon.
- **Economy sanity:** `pmsim bot` runs a greedy trader. Under each ruleset on Normal it must grow net worth over 20 seeds without invariant violations. The median days-to-moon is recorded in the QA report and must be finite for Modern.

### 8.3 Fairness and integrity
- Cheats disable achievements and high scores.
- Loading a non-autosave increments `reloadCount` and marks the high-score entry with ↺.
- Ironman disables manual loading.

### 8.4 Differential harness (D6)
1. `scripts/harness.sh` installs `dotnet-sdk` via `brew install --cask dotnet-sdk` only if `dotnet` is missing. Run it once, and log the action in PROGRESS.md.
2. It copies the game-logic `.cs` files from `SpaceTraderSource201` into `build/harness/src/`.
3. It adds `harness/` stubs:
   - minimal `System.Windows.Forms` types such as `DialogResult`, and form stubs that auto-answer;
   - a replacement for the `BinaryFormatter` save calls.
4. It adds a driver that seeds `Functions.rand = new Random(seed)` and runs scripted scenarios: universe generation, prices, opponent generation, combat rounds and quest steps.
5. It emits JSON fixtures to `Packages/ParsecKit/Tests/Fixtures/harness/`.

Swift tests compare the Windows 2.01 ruleset against these fixtures. If the harness can't be built in about 6 attempts, record the reason in an ADR, fall back to hand-worked values, and continue. Never block on it.

## 9. Milestones
Each milestone ends as follows:
1. `scripts/verify.sh` (or `--ui` where §8.1 says so) passes.
2. Commit.
3. `git tag mN-done`, then push.
4. Update PROGRESS.md.

Don't start M(n+1) while the gate is red. Commit after every green step.

| M | Scope | Exit criteria (shown in the transcript) |
|---|---|---|
| **M0** | Tooling and specs: the §6.3 ladder; the package skeleton (all targets, one passing test each); `.gitignore` (§6.1) first; `.swiftlint.yml`; all scripts (`final-check.sh` as a stub); fetch the Palm source and record its hash; re-confirm MOD-017; export the Apple skills (`xcrun mcpbridge run-agent skills export --output-dir .claude/skills`; on failure, note it and continue); `csharp-index.md`; spec skeletons plus full RNG/GAL/ECO/SHP/CRW/BNK; ALR.md (188 rows); RUL.md matrix; create the repo (`gh repo create megatih/parsec-merchant --public --source . --remote origin --push`, with description and topics). | `verify.sh` PASS. The app-side test calling `ParsecEngine` passes. `git check-ignore docs/reference/palm-src` succeeds. `gh repo view megatih/parsec-merchant` succeeds. |
| **M1** | RNGs and vectors; Windows 2.01 tables; galaxy generation, placement, wormholes, mercenaries, start system; `pmsim dump-galaxy`; the harness (§8.4) with galaxy and RNG fixtures. | RNG and GAL tests green. Galaxy invariants hold over 1,000 seeds. The harness fixtures match (or the ADR fallback is recorded). |
| **M2** | Economy and services (ECO, SHP, CRW, BNK), including all logic moved out of the forms. | ECO/SHP/CRW/BNK golden and harness tests green. Engine coverage ≥85%. |
| **M3** | Travel, encounters (35 types), opponents, combat, police, arrest, escape pod, scooping, plunder, trade in orbit, very rare encounters, news, arrival pipeline. | TRV/ENC/CMB/POL/NEWS green. Fuzz clean on Windows 2.01. Engine coverage ≥90%. |
| **M4** | All 46 special events and quest chains (C# content), tribbles, endings, scoring. | A QST scenario for every chain, including failures. SCORE green. |
| **M5** | The Palm 1.2.2 pack and flags; Modern MOD-001…021; keep/fix rows. | The scenario matrix is green for all three rulesets. No open `[verify]` (or each is logged as an accepted assumption). Fuzz clean for all rulesets. ≥400 spec IDs (`cat docs/specs/*.md \| /usr/bin/grep -cE '<regex>'`). |
| **M6** | Persistence (envelope, migrator, slots, autosave, import/export model, Ironman), high scores, cheats. | SAV/SCORE/CHEAT green. Round-trips byte-identical over 500 fuzzed states. Persistence coverage ≥85%. |
| **M7** | App shell: GameSession; Welcome with Quick Start; the New Game wizard (ruleset, galaxy code, seed, Ironman, ship name); sections Bridge, Market, Shipyard plus Designer, Outfitter, Crew, Bank, Quests; inspector; status/subtitle; full menu bar (MENU.md); Settings; Game › Options sheet; save/load/import/export/Finder-open; Retire; About; Help; App Intents. Fully playable while docked. | App tests green. `verify.sh --ui`: flows 1, 3 and 4 green. |
| **M8** | Galaxy chart (Canvas, zoom and pan, hover overlay cards, range, wormholes, tracking, context search, route planner, detachable window, accessibility children and rotors). | MAP tests green. Map benchmark baseline recorded. `--ui` flow 5 green. |
| **M9** | Encounter mode, transit (Dock tile progress), auto-repeat, combat log, tactical readout, plunder/trade/consent sheets, the arrival report card, event feed, newspaper, special-event sheets, game over with the career card, high scores. | `--ui` flow 2 green. Every `PendingDecision` and ALR mapping has a presentation (test). |
| **M10** | Trade intelligence, the Logbook (log, statistics, achievements), flavor (templates plus Foundation Models). | INT/LOG/STAT/ACH/LLM green. Insights coverage ≥85%. With `-PMFlavor template` the app behaves identically. |
| **M11** | ParsecArt (17 ship types, planets, glyphs, effects); the app icon via `make-icon.sh`: a Liquid Glass `.icon` bundle (layered PNGs plus `icon.json`) [verify format] with a full-bleed `.appiconset` fallback; ParsecAudio SFX, music and haptics; Sound settings. | Art and audio tests green. `actool` reports no icon warnings. Launching with audio on produces no runtime errors. |
| **M12** | Polish: HIG, Liquid Glass and shortcut audit (UI-KEYS.md); Reduce Motion, Increase Contrast, Reduce Transparency and Differentiate Without Color; Text Size; full keyboard navigation; localization completeness (`xcodebuild -exportLocalizations`, plus a check that no catalog entry is `new` or `stale`); a pseudo-localization screenshot run; TipKit tips; performance pass; README screenshots (`PM_EXPORT_SCREENSHOTS=1`). | `verify.sh --ui` green, including flows 6 and 7. Localization check clean. |
| **M13** | Release:<ul><li>README covering features, screenshots, rulesets, installation with "Open Anyway" steps (System Settings › Privacy & Security), build from source, credits and license; plus CHANGELOG.</li><li>`release.sh`: Release build signed to run locally (`CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`, hardened runtime plus entitlements, no `--deep`), `codesign --verify --strict`, `ditto` to `dist/Parsec-Merchant-1.0.0.zip`, SHA-256.</li><li>Release-build smoke test: launch with `-PMScenario smoke`, which saves and loads in the sandbox and exits 0.</li><li>`gh release create v1.0.0`.</li><li>QA-REPORT.md and the full `final-check.sh`.</li></ul> | See §10 and GOAL.md. |

## 10. Final check and QA
**`scripts/final-check.sh`** is committed in M13 and runs these checks, printing `PASS`/`FAIL` for each. It ends with `FINAL CHECK n/8 PASS` and `EXIT=<code>`.
1. `scripts/verify.sh --ui` ends with `ALL GATES PASSED` on the current HEAD.
2. PROGRESS.md has all 14 milestones (M0 to M13) marked `[x]` and no open blockers.
3. `gh release view v1.0.0 --repo megatih/parsec-merchant` lists `Parsec-Merchant-1.0.0.zip`.
4. `docs/QA-REPORT.md` contains every item below, each marked ✓, with no ✗ or TODO.
5. Release launch:
   - `gh release download v1.0.0` into a new temp folder, then unzip it with `ditto`.
   - `pkill -x "Parsec Merchant"`, then `open -n <tmp>/Parsec\ Merchant.app`.
   - `pgrep -f "<tmp>/Parsec Merchant.app"` finds it, then quit it.
   
   Gatekeeper prompts can't be automated and aren't checked.
6. Clean clone: `git clone` the GitHub repo into a temp folder, then `xcodebuild build` succeeds without `Config/Local.xcconfig`.
7. `pmsim bench` meets the §8.1 budgets.
8. `git status --porcelain` prints nothing, and `git rev-parse HEAD` equals `git rev-parse origin/main`.

**QA-REPORT.md items:**
- Coverage matrices: every C# `AlertType` (188), `SpecialEventType` (46), `EncounterType` (35), `ShipType` (17), equipment type and option is handled, plus every Palm special event (37). Every form listed in UX-VISION §12 has a home.
- A `pmsim scenario` full game per ruleset reaches the moon, death and retirement endings.
- Economy-bot results.
- Accessibility audit result.
- Text Size and pseudo-localization screenshots.
- Light and dark mode.
- Smallest window size.
- License check.
- Credits visible.
- The release smoke test.
- Clean-clone build.

## 11. Operating rules for the autonomous agent
1. **Each session:** read CLAUDE.md, then PROGRESS.md, then run `scripts/verify.sh --quick` (once it exists) and print the summary.
2. **Small steps.** Commit when green with a conventional message. Tag and push at each milestone exit.
3. **PROGRESS.md is the memory that survives context compaction.** After each step, record what was done, the next step, blockers, accepted assumptions and the last gate summary.
4. **Don't guess rules.** Read the cited source and write the decision into the spec.
5. **End every turn** with `Milestone Mx: <done>/<total> steps — gates <PASS|FAIL>`.
6. **Blocker protocol.** Only the owner can resolve:
   - the package link after the full ladder,
   - UI-automation permission,
   - anything that needs a paid account.
   
   For these, record it under Blockers in PROGRESS.md, print `BLOCKED: <exactly what is needed>`, and **keep doing every unblocked task** (other milestones' engine work, specs, tests). A blocker means "not yet", never "impossible". Decide everything else yourself and record an ADR.
7. **Never:**
   - weaken, skip or delete gates or tests, or change thresholds except as scheduled in §8;
   - use original art or commit reference sources;
   - use `.popover`;
   - add third-party dependencies;
   - commit build products, secrets or Apple skills;
   - force-push `main`.
8. **Prefer well-established SwiftUI APIs.** For new macOS 27 APIs, consult `.claude/skills/` and record an ADR.
9. **Don't move the mouse or keyboard** during non-UI steps. UI tests run only in `--ui` mode.

## 12. Risks
| Risk | Mitigation |
|---|---|
| Context loss over a multi-day run | PROGRESS.md, specs and research on disk; frequent commits; final-check proves completion in a single turn |
| Package linking in the JSON xcproj | Owner pre-flight shortcut; §6.3 ladder; test-based proof |
| Fidelity errors | Differential harness; source citations; errata; golden tests; exact integer semantics |
| Strict concurrency (audio, Foundation Models) | `ParsecAudio` package target (nonisolated); Sendable engine; zero-warning gate |
| Sandbox container shared between Debug and Release | Debug bundle id `.debug` |
| UI tests: permissions and flakiness | Owner pre-flight grant; few flows; accessibility ids; `-PMScenario`; `--ui` only at set milestones |
| macOS 27 SwiftUI bugs | No popovers; explicit window sizes; static menus whose items observe state |
| Performance | Release-mode benchmarks; cached map projections and heatmaps |
| Foundation Models unavailable | Optional; timeout; template fallback |
| Gatekeeper for users | README steps; build from source |
| Palm source fetch fails | Implement from research 04; mark the ruleset "experimental"; log the assumption |
| git push authentication | Owner pre-flight `gh auth setup-git` |

## 13. Definition of Done (v1.0.0)
v1.0.0 is done when **one turn** shows the complete, unedited output of `scripts/final-check.sh` ending with `FINAL CHECK 8/8 PASS` and `EXIT=0`, after M0–M13 are all checked.
