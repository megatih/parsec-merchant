# Parsec Merchant — Architecture Blueprint (Plan agent output)

> Produced 2026-11-16 during planning. docs/PRD.md is normative where the two differ.


> **Superseded where it conflicts with docs/PRD.md v1.1.** Known differences: Apple skills export to `.claude/skills/` (gitignored); the audio launch argument is `-PMAudio off`; there are 188 AlertTypes; package linking ladder, coverage ramp and gates follow PRD §6.3 and §8.

---

# Parsec Merchant: architecture and phased implementation blueprint

## 0. Findings that shape the plan

What I checked on this machine:

- **Template project** (`/Users/megatih/Documents/XcodeProjects/SpaceTraderMac/SpaceTraderMac.xcodeproj/project.xcproj`):
  - The app target has `SWIFT_VERSION 5.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` and `ENABLE_USER_SELECTED_FILES=readonly`. Export needs that changed to `readwrite`.
  - `TEST_HOST` is a hard-coded path: `$(BUILT_PRODUCTS_DIR)/SpaceTraderMac.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SpaceTraderMac`. Any change to PRODUCT_NAME breaks unit tests unless this is updated too.
  - There is no package-reference syntax anywhere in the file, and Xcode ships no sample of it. The keys exist in `/Applications/Xcode.app/Contents/Developer/usr/bin/xcprojformatter` (`packages`, `local`, `remote`, `package-product-members`, `package-dependencies`), but the exact schema is undocumented.
- **Tooling present:** `xcodegen`, `swiftlint`, `gh`, `xcrun swift-format`, `xcprojformatter`, and `xcrun mcpbridge` (which has `run-agent skills` / `plugin`). **No dotnet or mono**, so the C# code cannot be run for differential tests.
- **The Palm 1.2.2 C source is not on disk.** The "Original Palm" ruleset depends on getting it.
- **C# engine facts:**
  - `Game.cs` is 4,429 lines and `Form_SpaceTrader.cs` is 4,079.
  - `Functions.GetRandom` (an unseeded `System.Random`, `Next(min,max)`) is called 64 times in Game.cs, 26 in Ship.cs, 2 in StarSystem.cs, 2 in Form_Encounter.cs and 1 in CrewMember.cs.
  - Pieter's two-seed generator `Rand()` (Functions.cs:252) depends on C# `long` wrap-around. The Swift port must use `&*` and `&+`.
  - `Next(0,0)` returns 0, which matters for calls like `GetRandom(Opponent.Pilot)`.
  - Counts: `EncounterType` has 35 cases, `SpecialEventType` 46 (plus NA), `ShipType` 17 (including Custom, Scorpion and Bottle), `StarSystemId` about 129 entries, `AlertType` about 149.
  - Galaxy constants: `GalaxyWidth=154`, `GalaxyHeight=110`, `MaxRange=20`, `StartClicks=20`, `DebtTooLarge=100000`.
- **The travel loop (`Game.Travel`, Game.cs:3105) opens `FormEncounter.ShowDialog` inside the click loop.** It is the core thing to invert into a resumable state machine.

## A. Module / package structure

**Recommendation: one local SwiftPM package, `Packages/ParsecKit`, plus the existing app target.** Do not use a single target.

Why:
1. `swift test` runs the engine in seconds without the app host, the sandbox or signing. That makes the fast inner loop for an autonomous agent.
2. Package targets are nonisolated by default. Putting engine code in the app target would inherit `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` and make every model main-actor-bound, which is wrong for a pure, Sendable engine.
3. Module boundaries force the engine to have no UI imports. A lint check can grep for it.
4. A headless executable (`pmsim`) can fuzz thousands of games as a gate.

**Linking the package (the risky step), with a decision ladder for M0:**
1. Add the local package to `project.xcproj`. Iterate the JSON until `xcrun xcprojformatter SpaceTraderMac.xcodeproj` accepts it, `xcodebuild -list -json` shows it, and the app builds with `import ParsecEngine`. Cap this at about 6 attempts. Always back up the file first with `git stash` or a commit.
2. Fallback: switch to `xcodegen` (`project.yml` generates a classic `project.pbxproj` with `XCLocalSwiftPackageReference`, a well-known format). Delete `project.xcproj`. Record the choice in `docs/adr/0001-project-format.md`.
3. Last resort: ask the user for a 30-second step in Xcode (File > Add Package Dependencies > Add Local). Do not hack around it by compiling engine sources into the app target.

**Renaming (safest path):** keep the folder, target and scheme names `SpaceTraderMac`. Change only:
- `PRODUCT_NAME = "Parsec Merchant"`
- `PRODUCT_MODULE_NAME = ParsecMerchant` (tests then use `@testable import ParsecMerchant`)
- `INFOPLIST_KEY_CFBundleDisplayName = "Parsec Merchant"`
- `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Parsec Merchant.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Parsec Merchant"`
- the Products group entry `<PRODUCTS>/Parsec Merchant.app`
- the bundle id, to `io.github.megatih.ParsecMerchant`. Change it now, while no saves exist, so the sandbox container is final.

Also set `SWIFT_VERSION = 6.0` on all three targets, `INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.games` and `INFOPLIST_KEY_NSHumanReadableCopyright` (GPL notice). Rename the GitHub repo to `parsec-merchant`.

**Info.plist additions** (exported UTType `io.github.megatih.parsecmerchant.save`, extension `.parsecsave`) go in `Config/Info.plist`, **outside** the synchronized folders, with `INFOPLIST_FILE=Config/Info.plist` and `GENERATE_INFOPLIST_FILE=YES` so the two merge. A plist inside `SpaceTraderMac/` would be picked up as a resource and fail the build with a duplicate output.

```
SpaceTraderMac/                         (repo root)
├── CLAUDE.md                           agent rules, gate commands, conventions
├── PROGRESS.md                         milestone checklist, current step, last gate output, open questions
├── README.md  LICENSE (GPL-2.0 text)  CREDITS.md  CHANGELOG.md
├── Config/Info.plist                   UTType + document types (merged)
├── scripts/  verify.sh  coverage-gate.sh  spec-trace.sh  warnings-gate.sh  release.sh  make-icon.sh
├── docs/
│   ├── PRD.md
│   ├── adr/                            0001-project-format, 0002-shoebox-saves, 0003-rng, ...
│   ├── reference/  csharp-index.md (method -> file:line), palm-src/ (fetched GPL source), palm-diff.md
│   └── specs/  GLOSSARY.md RNG.md GAL.md ECO.md TRV.md ENC.md CMB.md POL.md CRW.md BNK.md SHP.md
│               QST-*.md (one per quest chain) NEWS.md OPT.md ALR.md (149-alert mapping) RUL.md
│               SAV.md SCORE.md INT.md ACH.md LOG.md LLM.md AUD.md UI-*.md MAP.md A11Y.md REL.md
├── Packages/ParsecKit/
│   ├── Package.swift                   tools 6.x, .macOS("27.0"), swiftLanguageModes [.v6], warnings as errors, zero 3rd-party deps
│   ├── Sources/
│   │   ├── ParsecEngine/   RNG/ Model/ Rulesets/{Modern,Windows201,Palm122}/ Data/ Systems/{Galaxy,Economy,
│   │   │                   Travel,Encounter,Combat,Police,Crew,Bank,Shipyard,Equipment,Quests,News,Arrival,Score}
│   │   │                   Engine/{GameEngine,Command,PendingDecision,GameEvent,CommandError,Invariants} Cheats/
│   │   ├── ParsecPersistence/  SaveEnvelope, SaveCodec, Migrator, SlotStore (URL-injected), HighScoreStore
│   │   ├── ParsecInsights/     TradeIntel, RoutePlanner, Stats reducers, Achievements, TemplateFlavor
│   │   ├── ParsecArt/          SwiftUI Shapes: procedural ships, planets, icons (SwiftUI only, no game state)
│   │   └── pmsim/              executable: fuzz, replay, scenario, dump-galaxy
│   └── Tests/  ParsecEngineTests/ ParsecScenarioTests/ ParsecPersistenceTests/ ParsecInsightsTests/
│       └── Fixtures/  saves/v1/*.json  golden/*.json  rng-vectors.json
├── SpaceTraderMac/                     (app target, synchronized)
│   ├── App/ ParsecMerchantApp.swift, Commands/, AppDelegate (terminate -> autosave)
│   ├── Session/ GameSession.swift, PresentationRouter.swift, EventFeed.swift, Services/
│   ├── Features/ Bridge Market Shipyard Outfitter Crew Bank Galaxy Encounter Transit News Quests Log Stats NewGame Settings HighScores Cheats
│   ├── Audio/ SynthEngine, SFX, AmbientMusic    Haptics/    Flavor/ FoundationModelsFlavor.swift
│   ├── Resources/ Localizable.xcstrings, Assets.xcassets
├── SpaceTraderMacTests/                (app-level: GameSession, routers, presentation mapping)
└── SpaceTraderMacUITests/              (XCUITest smoke flows)
```

Rulesets live inside ParsecEngine, because the engine cannot run without tables. Tables are Swift `static let` arrays, not JSON resources: they are checked at compile time and need no `Bundle.module`.

## B. Engine design

**State: all value types.** `GameState: Codable, Sendable, Equatable` holds:
- `rulesetID`, `difficulty`, `day`
- `rng: RNGState`
- `galaxy` (systems, wormholes, shipyards)
- `commander` (cash, debt, policeScore, reputationScore, kills, ship, escape pod, insurance, noClaim)
- `mercenaries`
- `quests: QuestState` (typed enums per chain, with Int counters where the original counts days, for example Jarek, Reactor and Experiment)
- `options: GameOptions` (per-save, like the original)
- `news`
- `phase: GamePhase`
- `log: [LoggedEvent]`
- `intel: TradeIntel` (player knowledge, which the rules never read)
- `cheatsUsed`

There are no reference types and no singleton. Equality plus a stable hash (SHA-256 of canonical JSON) makes determinism checks easy.

**Phases:** `GamePhase = .docked | .inTransit(TransitState) | .encounter(EncounterState) | .gameOver(GameEnd)`.
- `TransitState`: `{destination, clicksRemaining, viaWormhole, raided, inspected, litterWarning, uneventful}`
- `EncounterState`: `{type: EncounterType, opponent: Ship, cmdrFleeing, oppFleeing, oppFleeingPrev, cmdrHit, oppHit, continueAttacking, continueFleeing, round}`

Travel becomes resumable. `advanceTransit()` runs clicks (repairs, then the encounter roll) until it either sets `.encounter` (and returns) or arrives (runs the Arrival pipeline, then `.docked`).

**API:**
```swift
public struct GameEngine: Sendable {
  public private(set) var state: GameState
  public let ruleset: Ruleset
  public mutating func perform(_ c: Command, acknowledging: Set<WarningID> = []) -> StepResult
  public func preview(_ c: Command) -> Preview     // pure: max buy qty, costs, legality
}
public struct StepResult { events: [GameEvent]; decision: PendingDecision?; rejection: CommandError? }
```
- `Command` is a Codable enum covering all player actions:
  - market and cargo: buy, sell, dump, jettison
  - ship services: fuel, repair, buyShip, equipment buy/sell, escape pod, insurance
  - crew and bank: hire/fire, borrow/repay
  - travel: warp, wormhole, singularity
  - quests and encounters: `answerSpecialEvent`, `encounter(action)` (attack, flee, surrender, bribe, submit, ignore, plunder, trade, board, drink, meet, yield), `plunderPick`, `tradeInOrbit`
  - news and setup: `buyNewspaper`, `setOptions`, `newGame(config)`, `cheat(code)`
  
  Commands are logged, so replays are possible.
- **Two-phase confirmation** replaces the WinForms `EncounterVerify*` dialogs. If an action needs consent (attacking police, a Wild-without-laser departure, surrender with the Princess aboard), `perform` returns `decision: .confirm(Confirmation{id: WarningID, ...})` and changes nothing. The UI re-sends the command with the acknowledgement.
- **Rejections** are typed `CommandError` values (`.debtTooLargeGrounded`, `.insufficientCashForMercenaries`, ...). They are never strings.
- **`PendingDecision`** covers decisions the engine forces: `.specialEvent(SpecialEventOffer)`, `.newspaperOffer(cost)`, `.tradeInOrbit(offer)`, `.plunder(available)`, `.encounter` (implied by the phase), `.arrivalReport`. While a decision is pending, only resolving commands are accepted. Tested by ENG-0xx.
- **Continuous attack:** the engine sets `continueAttacking`/`continueFleeing`. The UI repeats the action on a timer (0.6 s, or instant with Reduce Motion) and stops on a state change or Esc, matching the original's behaviour.
- **All UI-leaked logic moves into the engine:** cargo buy/sell caps (leave-empty bays, reserve money), fuel/repair costs, escape pod price, maximum loan, ship trade-in price, quest text parameters, and special-event dispatch. Each becomes a `preview` query with tests.

**Events and the log.** `GameEvent` is a Codable enum stamped with day and system: `.boughtCargo`, `.soldCargo(profit)`, `.encounterStarted`, `.shotFired(hit,damage)`, `.shipDestroyed`, `.arrested`, `.questAdvanced`, `.newsHeadline`, `.recordChanged`, and so on. Everything is appended to `state.log`. The captain's log, statistics and achievements are **pure folds** over the log (in ParsecInsights): deterministic and recomputable.

**Alerts.** The about 149 `AlertType`s are classified in `docs/specs/ALR.md` into: validation error → `CommandError`; consent → `Confirmation`; outcome → `GameEvent` (shown in the feed, a toast or the consolidated arrival report); narrative → special-event sheet; dropped (with a reason). A test keeps the full list of legacy alert names and asserts every one has a mapping.

**RNG.** `RNGState` is a Codable enum stored in the save. It implements `protocol RandomSource { mutating func next(below: Int) -> Int; mutating func next(in: Range<Int>) -> Int }`:
- `DotNetRandom(seed)`: an exact port of .NET Framework `System.Random` (Knuth subtractive, seed array of 56), including `Next(0,0)==0`. Used by Windows 2.01.
- `PalmSysRandom`: the PalmOS `SysRandom` LCG, used by the Palm ruleset. Verify the constants against the Palm source and the OS docs.
- `PieterRand`: the two-seed `Rand`/`RandSeed` from Functions.cs:252-275, with wrapping arithmetic. Used by every ruleset for the newspaper and wherever the original uses `GetRandom2`.
- `Xoshiro256**`: used by Modern.

New Game takes an optional seed, shown in Settings > Advanced, so bug reports can be reproduced.

**Ruleset.** `protocol Ruleset: Sendable { id; tables: RulesTables; flags: RuleFlags; func makeRNG(seed:) -> RNGState }`:
- `RulesTables`: ship specs, weapons, shields, gadgets, trade items, political systems, system names and count (128 or 120), galaxy size (154x110 or 150x110), special events and placement rules, police thresholds, score formula constants.
- `RuleFlags`: about 30-60 booleans or enums, such as `hasSculptureQuest`, `hasPrincessQuest`, `hasDisruptors`, `hasHiddenBays`, `customShipyard`, `fixEscapePodExploit`, `paidNewspaper`, `trackAutoOff` semantics, plus each Modern fix as `MOD-0xx`.

Systems branch on flags, never on ruleset identity. `docs/specs/RUL.md` holds the diff matrix (row = behaviour, columns = three rulesets, cell = value plus a source citation such as file:line).

**Modern fixes.** M0 runs an exploit/bug audit of the C# source and writes `RUL-modern.md`. Each item gets an ID, a flag and a test. Candidates to verify, not facts: the insurance/no-claim reset, buy/sell price round-trip exploits, the hire/fire trick, trade-in-orbit pricing, and quest-state edge cases.

**Saves: shoebox, not document-based.**
- The game is one live session with autosave. High scores, achievements and settings are global. "New Game" is a wizard, not File > New.
- The new macOS 27 document API is too new for an agent to learn reliably.
- Document semantics (unsaved-changes prompts, versions, duplicates) clash with arrival autosave.

Layout:
- `~/Library/Containers/<bundle>/Data/Library/Application Support/Parsec Merchant/Saves/`
  - `slot-<uuid>.parsecsave`, with 3 rotating `.bak` copies
  - `autosave.parsecsave`, written on docking or arrival and on quit (`applicationShouldTerminate`)
- Commands: Import and Export (`fileImporter`/`fileExporter`, which needs `readwrite`), and opening a `.parsecsave` from Finder imports it into a slot.

Format: UTF-8 JSON with sorted keys:
```
{ "format":"parsec-merchant-save", "schemaVersion":1, "appVersion", "rulesetID",
  "summary":{commander, day, worth, systemName}, "state":{...} }
```
- `SaveMigrator` runs a chain of `[from: (inout [String: Any]) throws -> Void]` steps over raw JSON before typed decoding.
- Fixture files for every schema version stay in the tests forever.
- Writes are atomic. A decode failure moves the file to a `Corrupt/` folder and is never silently deleted.
- High scores: top 10 per ruleset, scored with each ruleset's formula.

## C. App / UI architecture

**`@Observable @MainActor final class GameSession`** owns `engine: GameEngine?`, `presentation: PresentationState` (the pending decision mapped to a sheet, encounter mode or transit HUD), `feed: [FeedItem]`, and services (`SaveService`, `AudioService`, `HapticsService`, `AchievementService`, `FlavorService`). `send(_:)` calls the engine synchronously (it takes microseconds), then sends events to the services. Heavy pure work (route planning, stats folds over long logs) runs in `Task.detached` on Sendable snapshots. Previews and tests build a session from fixture states.

**Scenes:**
- `Window("Parsec Merchant", id: "main")`: one game window, not a `WindowGroup`. It holds `NavigationSplitView` and a `.inspector` for ship status (hull, shields, fuel, cargo, record, quests summary), toggled with ⌥⌘I.
- `Window("Galaxy Chart", id: "galaxy")`: a large detachable chart, opened with ⇧⌘G.
- `Window("High Scores")`.
- `Settings` with tabs: Game (per-save options; disabled when no game is open), Appearance, Sound, Intelligence (Foundation Models toggle and status), Advanced (seed, reset).
- A custom About panel with GPL and credits text.
- `WelcomeView` when no game is loaded: Continue, New Game, Load, Import.

**Sidebar (⌘1-⌘0):** Bridge (system info, news, quest offers, warp target), Market, Shipyard, Outfitter, Crew, Bank, Galaxy, Quests, Captain's Log, Statistics & Achievements.

**Toolbar:** cash and debt, day, a destination picker and Warp (⌘J), "Next system in range" (⌘] and ⌘[), and a Fuel/Repair quick action. Lower-priority items use `visibilityPriority` so they collapse into the overflow menu.

**Encounter presentation:**
- While `phase == .encounter`, the detail area becomes `EncounterView` and the sidebar is disabled. This avoids stacking sheets.
- Sub-decisions (plunder, trade in orbit, confirmations) use `confirmationDialog(item:)`, `alert(item:)` or sheets.
- `TransitView` animates the 20-click progress. Reduce Motion skips it.
- **No popovers anywhere** (macOS 27 crash). Map hover cards are overlay views; detail uses the inspector.

**Encounter view:** two vector ships (ParsecArt) with hull and shield bars, an action bar whose buttons depend on the encounter type, and keyboard shortcuts: A attack, F flee, S surrender, I ignore, B bribe, T trade, P plunder, D board, Return = default, Esc = stop auto-repeat. There is also an animated combat log (a `List` of `GameEvent`s with phase-animated hit flashes and screen shake, turned off under Reduce Motion) and an "Auto" toggle for continuous attack.

**Menus (`.commands`):**
- File: New Game ⌘N, Open Save ⌘O, Save ⌘S, Save As ⇧⌘S, Import, Export ⌘E, Revert to Autosave.
- Game: Warp ⌘J, Buy Fuel, Repair, Newspaper ⌘P, Find System ⌘F.
- View: sections, Toggle Inspector, Galaxy Chart.
- Help.

The "Cheetah" cheat console opens from Find. Using cheats flags the save and disables achievements and high scores.

**Galaxy map: SwiftUI `Canvas`, not SpriteKit or Metal.** There are only 120-128 systems, which is trivial to draw.
- Interaction: pan with drag and scroll, zoom with `MagnifyGesture`, ⌘+ and ⌘−, and a fit-to-range button. `onContinuousHover` with nearest-system hit testing (a linear scan is fine) drives an overlay card.
- Layers: fuel-range circle, wormhole arcs, tracked system, quest markers, route polyline, and a heatmap (per selected good, colour by last-known price against the galactic mean, faded by age of the data).
- `TimelineView` only while animating.
- Accessibility: `.accessibilityChildren` exposes one element per system with label, value (distance, government, tech, known prices) and actions (select, warp). Custom rotors: "In range", "Quest locations", "Wormholes".

**Look, accessibility and localization:**
- Liquid Glass comes automatically on standard controls. Use `.glassEffect(.regular.interactive())` only for the floating map HUD and the encounter action bar, never behind dense tables.
- Use system text styles (Dynamic Type equivalent) and `@ScaledMetric`.
- Every interactive control gets an `.accessibilityIdentifier` (needed by XCUITest).
- `Localizable.xcstrings` with symbol generation (already on). The engine never produces user-facing strings, only typed events; the app formats them, so localization lives in one place. Quest and news text templates are keyed by event type with parameters.

**Audio and haptics:**
- `AVAudioEngine` plus `AVAudioSourceNode`. At launch, SFX (laser, hit, explosion noise burst, warp sweep, UI tick, cash register) are pre-rendered procedurally into `AVAudioPCMBuffer`s.
- Optional ambient music: a generative pad (slow chord walk, detuned saws, low-pass LFO), off by default.
- The render block must be `nonisolated` and allocation-free. This is a Swift 6 trap.
- Haptics: `NSHapticFeedbackManager` `.alignment` at slider snap points (max affordable or max bays) and `.levelChange` on a hit.

**Foundation Models:**
- `FlavorProvider` protocol. `TemplateFlavorProvider` (deterministic, seeded from the event hash) lives in ParsecInsights. `FoundationModelsFlavorProvider` sits behind `#if canImport(FoundationModels)` and the availability check, with a 4 s timeout and fallback.
- Generated text is cached in the log entry, so it is stable, and it never touches game state.
- The launch argument `-PMFlavor template` forces the fallback in tests.

## D. Testing strategy and completion gates

**Engine (Swift Testing, `ParsecEngineTests`):**
- Requirement IDs go in test names, e.g. `@Test("ECO-012 sell price includes police-record penalty")`.
- Golden, table-driven tests (`@Test(arguments:)`) for every formula, with expected values worked out by hand from the C# source. The citation goes in the spec, e.g. `Game.cs:534 CalculatePrices`.
- RNG vectors: the first 20 outputs of each generator for fixed seeds. .NET values are derived from the reference algorithm; optionally confirm them with `brew install --cask dotnet-sdk`, only with the user's permission.
- Property tests with a homemade generator (no dependencies): run N random command sequences per seed. Invariants: cash ≥ 0, cargo ≤ bays, quantities ≥ 0, hull ≤ max, crew ≤ quarters, a valid phase, determinism (same seed and commands give the same state hash), and save round-trips byte for byte.

**Scenarios (`ParsecScenarioTests`):** a small DSL:
```swift
Scenario(.modern, seed: 7) {
  start(...)
  mutate { $0.commander.cash = 50_000 }
  dock(.gemulon)
  expectOffer(.gemulon)
  accept()
  advanceDays(...)
  expect(...)
}
```
Every quest chain runs under every ruleset where it exists: Artifact, Dragonfly, Experiment, Gemulon, Japori, Jarek, Moon, Reactor, Scarab, Space Monster, Tribbles, Wild, Sculpture, Princess, Lottery/Skill/EraseRecord/CargoForSale. For Palm, assert that Sculpture and Princess are never placed. Encounter scenarios cover every `EncounterType` transition.

**Persistence:** fixture saves for each version, the migration chain, corrupt-file handling, and that the slot store works on a temporary directory.

**App:** `GameSession` tests for routing each `PendingDecision` to the right presentation, using fixture states.

**UI (XCUITest):** a handful of smoke flows:
1. Launch, New Game, buy, warp, dock.
2. A forced encounter via the launch argument `-PMScenario pirateAmbush`, then attack until resolved.
3. Save, then load.
4. Open Settings.

The `-PMScenario`, `-PMSeed` and `-PMFlavor` launch arguments are only honoured in Debug builds.

**Snapshots:** `ImageRenderer` renders each ParsecArt ship and the map at fixed sizes. The test checks the output is non-empty, the bounds, and that renders are deterministic (two renders give the same hash). It does not compare against stored pixels, which are too brittle across OS updates.

**Performance:** `pmsim fuzz --games 2000` must finish in under 60 s. A map frame with heatmap and route must take under 4 ms (measured with an `ImageRenderer` loop in a test, timed with `ContinuousClock`).

**Gates (`scripts/verify.sh` runs them all and ends with `ALL GATES PASSED`, exit 0):**
1. `swift build --package-path Packages/ParsecKit` (package uses warnings-as-errors)
2. `swift test --package-path Packages/ParsecKit --parallel --enable-code-coverage`, then `scripts/coverage-gate.sh`: ParsecEngine line coverage at least 90%, Persistence and Insights at least 85% (`xcrun llvm-cov export -summary-only` parsed with `plutil` or `python3`)
3. `swift run --package-path Packages/ParsecKit -c release pmsim fuzz --games 2000 --seed 1 --ruleset all` exits 0
4. `xcodebuild -project SpaceTraderMac.xcodeproj -scheme SpaceTraderMac -destination 'platform=macOS' -derivedDataPath build/DD clean build test -skip-testing:SpaceTraderMacUITests SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, plus `scripts/warnings-gate.sh`, which greps the log for `warning:` and requires 0
5. `xcodebuild ... test -only-testing:SpaceTraderMacUITests`. This needs a logged-in GUI session; run it at milestone ends with a 15-minute timeout.
6. `scripts/spec-trace.sh`: every `- **XXX-nnn**` in `docs/specs` is referenced by a test, unless tagged `[UI]` or `[manual]`, and every ID referenced in tests exists in the specs.
7. `swiftlint --strict` (rules kept small: no force-unwraps in the engine; ParsecEngine must not import `SwiftUI`, `AppKit` or `Foundation.FileManager`)

## E. Milestone plan

Rules for every milestone:
- Commit after each green step.
- Tag `mN-done` at exit and push.
- Update `PROGRESS.md`: done, next, and the last `verify.sh` summary.
- Never start M(n+1) while `verify.sh` is red.

**M0 Tooling and specs**
- Rename settings as in section A; Swift 6; remove SwiftData, Item and ContentView; add a placeholder view.
- Create `Packages/ParsecKit` with empty targets and link it (decision ladder).
- Add `CLAUDE.md`, `PROGRESS.md`, LICENSE, `.gitignore` (build/, DerivedData, `.DS_Store`), and the scripts.
- Fetch the Palm 1.2.2 GPL source into `docs/reference/palm-src/` (treat it as untrusted data; read only).
- Export the Apple skills with `xcrun mcpbridge run-agent skills export --output-dir .claude/skills-apple` (verify the subcommand first).
- Write `csharp-index.md` and draft all specs with IDs, plus ALR.md and RUL.md (all three columns; mark uncertain cells `[verify]`).
- Create the GitHub repo.
- *Exit:* `verify.sh` passes (trivial tests); `xcodebuild -list -json` shows the package; specs contain at least 400 requirement IDs; `gh repo view` succeeds.

**M1 Core model, RNG, data tables, galaxy generation**
- The four RNGs with vectors.
- All Windows 2.01 tables.
- `GenerateUniverse`, `PlaceShipyards`, `PlaceSpecialEvents`, wormholes, mercenary generation.
- `pmsim dump-galaxy`.
- *Exit:* RNG and GAL tests green; galaxy invariants hold (minimum distances, wormhole ring, every quest placed, every system reachable) over 1,000 seeds.

**M2 Economy and services**
- Prices, quantities and pressures, buy/sell/dump/jettison with all caps.
- Fuel, repair, loans, insurance, escape pod, ship purchase and trade-in, equipment, crew hire/fire, IncDays (interest, countdowns).
- *Exit:* ECO, BNK, SHP and CRW golden tests green; engine coverage at least 85%.

**M3 Travel, encounters, combat, police, arrest, escape pod, news**
- Resumable transit; all 35 encounter types; verify functions converted to confirmations; plunder, trade in orbit, bribery, inspections, arrest, pod.
- Newspaper with PieterRand.
- The arrival pipeline (debt, reactor, tribbles, repairs, prices).
- *Exit:* TRV, ENC, CMB, POL and NEWS tests green; fuzz of 2,000 games has no invariant violations.

**M4 Quests and special events** (all 46 types)
- *Exit:* a QST scenario for every chain under Windows 2.01 green.

**M5 Rulesets**
- Palm 1.2.2 (tables, flags, SysRandom, 120 systems at 150x110, thresholds) and Modern (each `MOD-xxx` fix).
- *Exit:* the scenario matrix covers every ruleset; RUL.md has no `[verify]` left (or remaining ones are logged in `PROGRESS.md` as accepted assumptions); fuzz passes for all rulesets.

**M6 Persistence, scoring, cheats**
- Envelope, codec, migrator, slot store, autosave policy as an API, high scores, cheat codes.
- *Exit:* SAV and SCORE tests green; round-trip byte-identical over 500 fuzzed states.

**M7 App shell**
- GameSession, Welcome, New Game wizard (name, skill points, difficulty, ruleset, seed), sidebar, inspector, toolbar, menus and shortcuts, Settings, save/load/import/export.
- Market, Shipyard, Outfitter, Crew and Bank screens fully playable while docked.
- *Exit:* app tests green; UI smoke flows 1, 3 and 4 green.

**M8 Galaxy chart**
- Canvas map, zoom/pan, hover card, range and wormholes, track, Find, detachable window, accessibility children and rotors.
- *Exit:* MAP tests (projection maths, hit testing, route geometry) green; perf test under 4 ms; VoiceOver identifiers asserted in a UI test.

**M9 Encounter, transit, events UX**
- Encounter mode, auto-repeat, combat log animation, special-event sheets, arrival report, event feed, newspaper sheet, game-over and high-score flow.
- *Exit:* UI flow 2 green; every `PendingDecision` case has a presentation (an exhaustive switch the compiler checks, plus a test).

**M10 Trade intelligence, log, stats, achievements**
- Price memory, Swift Charts sparklines, heatmap, profit per bay, multi-jump route planner (Dijkstra over fuel-range hops plus wormholes, scored by profit, cost and risk).
- Captain's log, statistics, about 30 achievements.
- `TemplateFlavor` plus optional Foundation Models.
- *Exit:* INT, ACH, LOG and LLM tests green; the app behaves the same with `-PMFlavor template`.

**M11 Art and audio**
- ParsecArt procedural ships (17 types, each a parameter set), planets by tech level, app icon generated by `scripts/make-icon.sh` (a `swift run` render to PNG at all sizes, committed), SFX synth, ambient music, haptics, sound settings.
- *Exit:* art determinism snapshots green; launching the audio engine (`-PMAudio on`) gives no errors in the test log.

**M12 Polish, accessibility, localization**
- HIG pass, Liquid Glass audit, Reduce Motion and Increase Contrast, full keyboard navigation, every string in the catalog (an export check shows no missing strings), Help.
- *Exit:* `verify.sh` plus all UI tests green; an a11y UI test walks every sidebar section and checks for labelled elements.

**M13 Release**
- `scripts/release.sh`: archive Release, ad-hoc sign (`codesign --force --deep --options runtime --entitlements ... -s -`), verify (`codesign --verify --deep --strict`), `ditto -c -k --keepParent "Parsec Merchant.app"`, checksum.
- README (features, screenshots taken with `screencapture` from a UI test run, Gatekeeper "Open Anyway" steps for System Settings > Privacy & Security, build-from-source steps, GPL and credits, no original art).
- `gh release create v1.0.0`.
- *Exit:* `gh release view v1.0.0` lists the zip; on this Mac, a freshly unzipped copy launches (verified with `open` plus `pgrep`).

## F. Top risks and mitigations

1. **Context loss in a long autonomous run.** `PROGRESS.md` is the single source of the current state. Specs and the C# index (file:line for every method) live on disk. Commit after each green step. Each session starts with `cat PROGRESS.md` and `scripts/verify.sh`.
2. **Package syntax in the JSON xcproj.** Use the bounded-attempt ladder: `xcprojformatter` validation, then the xcodegen fallback, then ask the user. Always back up with git first. Never hand-edit Products IDs.
3. **Palm source unavailable or ambiguous.** Fetch it in M0. If it can't be found, build the Palm ruleset from documented differences, flag the cells as assumptions, and leave the Palm ruleset marked "experimental" rather than blocking the release.
4. **Fidelity bugs (integer division, C# rounding, long overflow, `Next(0,0)`).** Every formula spec cites file:line. Port C# integer arithmetic exactly (Swift `/` truncates the same way; use explicit `Int32` wrapping where C# uses `int` overflow). Golden tests use hand-computed values.
5. **Strict concurrency in the app** (MainActor default against audio render threads, Foundation Models async, `Task.detached` planning). Keep the engine fully Sendable values. Mark audio and synth code `nonisolated`. The warnings gate is zero.
6. **UI tests flaky or blocked** (automation permission, focus). Keep them few, gate them only at milestone ends with timeouts, use accessibility identifiers everywhere, and use `-PMScenario` to jump straight to states.
7. **macOS 27 SwiftUI bugs (popover crash, new APIs the agent doesn't know).** No popovers. Prefer APIs that have been stable for years. Use the exported Apple skills for anything new. Only one ADR per new-API adoption.
8. **Canvas performance and accessibility.** Precompute projected points and only redraw on change. The heatmap is drawn into a cached layer per (good, data version).
9. **Foundation Models unavailable or slow.** It is strictly optional, with timeout, cache and template fallback. CI and tests always use templates.
10. **Signing and Gatekeeper with the free team.** Release is ad-hoc signed; development uses automatic signing. Document `xattr`-free "Open Anyway" steps. The sandbox container path changes if the bundle id changes, so fix the id in M0.
11. **Licensing.** GPL-2.0-or-later headers in every file, CREDITS for Spronck, French and Pierron, and a check that no original image assets are copied: `scripts/verify.sh` asserts that no file from `SpaceTraderSource201/images` appears in the repo by hash.

### Critical Files for Implementation
- /Users/megatih/Documents/XcodeProjects/SpaceTraderMac/SpaceTraderMac.xcodeproj/project.xcproj
- /Users/megatih/Downloads/SpaceTraderSource201/Game.cs
- /Users/megatih/Downloads/SpaceTraderSource201/Functions.cs
- /Users/megatih/Downloads/SpaceTraderSource201/Enums.cs
- /Users/megatih/Downloads/SpaceTraderSource201/Ship.cs
