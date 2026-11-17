# LOG: Captain's log

> Format (PRD §7): `- **ID** {Mn} [UI] [M][W][P] statement (source)`. `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2. `[UI]` = verified by app tests (`SpaceTraderMacTests`) or XCUITest (`SpaceTraderMacUITests`). Bullets without `[UI]` are pure logic in `Packages/ParsecKit/Sources/ParsecInsights/Journal/` (tested in `ParsecInsightsTests`) or persistence in `ParsecPersistence` (tested in `ParsecPersistenceTests`), unless they name an app type, in which case they are unit-tested in `SpaceTraderMacTests`.
> Milestones: everything here is {M10} (PRD §9 M10). Accessibility polish (rotor, audit) is {M12}.
> Normative inputs: PRD §6.1 (ParsecInsights holds "Stats/Log folds"), §6.2 (determinism; no user-facing strings in the engine), §6.4 (save format), §6.5 (GameSession owns the feed and services), §6.6 "Statistics and Log (STAT, LOG): folds over the log. The log exports to Markdown."; UX-VISION §4.9 (Logbook ⌘9, Captain's Log tab), §5.3 ("Each item is also posted to the log"), §10.1 (Edit › Copy for the log); research 02 pain point "No persistent log".
> **Ownership (do not restate, reference).** The save envelope, codec and stores: SAV. Folds into statistics: STAT. Achievement evaluation and unlock entries: ACH. Flavor text generation: LLM. Seen prices and visits kept in the journal: INT-007…011. The in-memory feed (newest 500 items, cleared on load): UI-SHELL-008 and UI-ENC-064…067; the feed is unchanged and is not the log. Section, menu and shortcut: MENU-023, UI-SHELL-035.

## 1. Where the log lives (decision)

- **LOG-001** {M10} [M][W][P] **Decision: the log is persisted with the save, beside `state`, not inside it.** `SaveEnvelope` gains one top-level key, `journal` (a `GameJournal`), next to `state`. Reasons, all normative: (1) flavor text is cached in log entries (LLM-021) and "flavor never changes game state" (PRD §6.6), so the cache must not be part of `GameState` or its canonical hash; (2) the engine stays free of strings and of log bookkeeping, and every M1–M9 harness fixture, golden test and state hash stays valid; (3) the rules never read the log or intel, so they are not game state; (4) the canonical state hash used by `pmsim` replays and fuzzing (PRD §6.2) does not grow with the length of the game. This deliberately refines PRD §6.2's list ("event log, player intel" in `GameState`) and must be recorded in an ADR. (source: PRD §6.2, §6.4, §6.6; research 06 §B "intel … which the rules never read")
- **LOG-002** {M10} [M][W][P] `GameJournal` (ParsecInsights) is `Codable, Sendable, Equatable` and holds `entries: [LogEntry]`, `nextEntryID: Int`, `intel: IntelBook` (INT-007) and `openEncounter: EncounterLedger?` (LOG-019). It contains only structs, enums, arrays, `Int`, `Bool` and `String` (flavor text); no `Dictionary`, `Set`, floating point or `Date`, so SAV-004's sorted-key encoding is deterministic and SAV-006's integer rule holds. (source: SAV-004, SAV-006)
- **LOG-003** {M10} [M][W][P] Round trips: `SaveCodec` keeps the byte-identical round trip of SAV-005 with the journal included: `encode(decode(encode(e)))` equals `encode(e)` for envelopes whose journals contain entries of every `LogEntryKind`, template and generated flavor (including non-ASCII and JSON-special characters, SAV-007), an open encounter ledger and full intel histories. The M6 fuzz round-trip test (500 states) is extended to carry the journal `pmsim` records for each sampled state (LOG-037). (source: SAV-005, SAV-007; PRD §9 M6)
- **LOG-004** {M10} [M][W][P] Schema: v1 has not been released (SAV §15), so `journal` is added to schema version 1 without a migration step and the v1 fixtures are regenerated with journals by `pmsim write-save-fixtures`. Decoding stays tolerant: an envelope without `journal` (a pre-M10 development save) decodes with `GameJournal.bootstrap(from: state)` (LOG-006); one whose `journal` is present but undecodable is `SaveError.corrupt` like any other field (SAV-010). `ParsecPersistence` gains a dependency on `ParsecInsights` (both pure; no cycle). (source: SAV-012…015 and §15 "until v1 is released they must be regenerated")
- **LOG-005** {M10} [M][W][P] `GameJournal.start(state:)` creates the journal of a new game (New Game, Quick Start, `-PMScenario`): entry 1 is `journalStarted(JournalStart)` stamped with the state's day and system, followed by `cheatsEnabled` when `state.cheatsUsed` is already true (scenarios, CHEAT-049), and intel observes the starting system (INT-008, INT-010). `JournalStart { origin, rulesetID, difficulty, ironman, systemCount, startSystem, visitedSystems: [Int], kills: Kills }` with `origin == .newGame`. (source: PRD §6.6; CHEAT-049)
- **LOG-006** {M10} [M][W][P] `GameJournal.bootstrap(from:)` creates a journal for a state that has none: like LOG-005 with `origin == .resumed` and `visitedSystems` = every system with `visited == true`; entries before that point are unknown. STAT and ACH treat a resumed journal as a partial history (STAT-004). (source: LOG-004)
- **LOG-007** {M10} [M][W][P] `SlotStore.save(_:journal:slot:gameID:)`, `autosave(_:journal:gameID:)`, `LoadedGame.journal`, import (SAV-027) and export (SAV-029) carry the journal unchanged; import keeps it as is (SAV-028 changes only `ironman` and `reloadCount`). Loading for play (SAV-034) restores the journal saved with that state, so Revert to Autosave rewinds the log with the game. (source: SAV-027…029, SAV-034, SAV-039)

## 2. Entries

- **LOG-008** {M10} [M][W][P] `LogEntry { id: Int, day: Int, system: Int, worth: Int, kind: LogEntryKind, flavor: FlavorText? }`. `id` comes from `nextEntryID` (starting at 1, never reused, strictly increasing in `entries`); `day`, `system` and `worth` (`GameState.worth`, RUL-119) are taken from the state after the step that produced the entry; `flavor` is owned by LLM. Entries are appended in emission order and never edited, except `flavor` (LLM-021). (source: UX-VISION §4.9 "grouped by day and system")
- **LOG-009** {M10} [M][W][P] `LogEntryKind` cases (typed payloads; no strings except where noted):
  - `journalStarted(JournalStart)`, `cheatsEnabled`, `gameEnded(GameEndType, score: Int)`, `achievementUnlocked(AchievementID)`;
  - `trade(TradeEntry)` with `TradeEntry { action: TradeAction, item, quantity, total, profit: Int? }`, `TradeAction` ∈ `buy`, `sell`, `dump`, `jettison`, `plunder`, `scoop`, `orbitBuy`, `orbitSell`, `sealedCanisters`;
  - `departed(from:, to:, viaWormhole:, parsecs:)`, `arrived(TripArrival { system, from, viaWormhole, firstVisit, uneventful, encounterCount })`, `fabricRip(newDestination:)`, `singularityLost`;
  - `encounter(EncounterRecord)` (LOG-019);
  - `police(PoliceEntry)`: `arrested(term:, fine:, shipSold:)`, `caughtLittering`, `reactorConfiscated`;
  - `finance(FinanceEntry)`: `borrowed(amount)`, `repaid(amount:, remainingDebt:)`, `insuranceBought`, `insuranceStopped`, `debtWarning(debt)`, `debtReminder(debt)`;
  - `ship(ShipEntry)`: `boughtShip(ShipType, netPrice:)`, `customShipBuilt(ShipyardID)`, `equipment(EquipmentChange, price:)` (the bought or sold weapon, shield or gadget, taken from the command), `boughtEscapePod(price)`, `fuel(units:, cost:)`, `repair(points:, cost:)`, `autoFuelFailed`, `autoRepairFailed`, `escapePodUsed(insurancePayout:)`;
  - `crew(CrewEntry)`: `hired(crewID)`, `fired(crewID)`, `passengerConcerned(crewID)`, `passengerImpatient(crewID)`;
  - `quest(QuestEntry)`: `completed(SpecialEventType)`, `refused(SpecialEventType)`, `tribbles(from:, to:)`, `tribblesDied(TribbleDeath)`, `tribblesAteFood(eaten)`, `tribbleInspectorWarning(count)`, `reactorWarning(status)`, `reactorMeltdown`, `gemulonInvaded`, `experimentPerformed`, `wildLeftShip`, `easterEgg(shieldInstalled: Bool)`;
  - `news(NewsEntry { headlines: [Headline], cost: Int })`;
  - `status(StatusEntry)`: `policeRecord(from: PoliceRecordType, to:)`, `reputation(from: ReputationType, to:)`.
  
  (source: UX-VISION §4.9 "trades with profit, encounters with outcome, quest steps, news, arrests"; UI-ENC-099)
- **LOG-010** {M10} [M][W][P] `LogEntryKind.category: LogCategory` with cases `trade`, `travel`, `encounter`, `police`, `finance`, `ship`, `crew`, `quest`, `news`, `status`, `achievement`, `game`; every kind maps to exactly one category (exhaustive switch, unit test per kind). The app maps categories to the feed symbols of UI-ENC-065 where they exist. (source: UX-VISION §4.9 "Filters by category")
- **LOG-011** {M10} [M][W][P] `LogEntryKind.flavorSubject: FlavorSubject?` is non-nil exactly for `arrived`, `encounter`, `quest(.completed)`, `gameEnded` and `achievementUnlocked`; only those entries get flavor (LLM-006). (source: UX-VISION §4.9 "Optional flavor text")
- **LOG-012** {M10} [M][W][P] Engine types inside entries (`TradeItemType`, `ShipType`, `EncounterType`, `SpecialEventType`, `Headline`, `GameEndType`, …) use their engine `Codable` form; a change to one of them is a save schema change handled by `SaveMigrator` (SAV-012…015). (source: SAV-013)

## 3. Recording

- **LOG-013** {M10} [M][W][P] `JournalRecorder.record(_ step: JournalStep, into journal: inout GameJournal) -> JournalStepOutput` is pure. `JournalStep { command, before: GameState, result: StepResult, after: GameState }` (built from the app's `StepRecord`, UI-ENC-005). Rejected steps and confirmation requests are never recorded. In order it: (1) maps the step's events per the §3a table, opening/closing the encounter ledger (LOG-019); (2) appends the derived entries of LOG-016…018; (3) updates intel (INT-008, INT-010, INT-011); (4) runs the achievement transition of ACH-006 and appends its `achievementUnlocked` entries; (5) attaches template flavor (LLM-008). `JournalStepOutput { newEntries: [LogEntry], unlocked: [AchievementID] }`. (source: PRD §6.6 "folds over the log"; UX-VISION §5.3)
- **LOG-014** {M10} [M][W][P] Determinism: the recorder draws no random numbers, reads no clock, locale or `Hasher`, and its output depends only on the journal and the step. Recording the same command sequence twice from the same seed gives byte-identical journals (with template flavor). Property test over 50 games per ruleset driven by the `pmsim fuzz` command generator. (source: PRD §6.2 "Determinism")
- **LOG-015** {M10} [M][W][P] Exhaustiveness: the event mapping is an exhaustive `switch` over `GameEvent` with no `default`, so a new engine event fails to compile until it has a disposition; a test feeds one fixture per `GameEventKind` (UI-ENC-004) and checks the disposition of the table. (source: UI-ENC-004)

### 3a. Event dispositions (normative table)

| `GameEvent` | Disposition |
|---|---|
| `boughtCargo`, `soldCargo` (profit from the event), `dumpedCargo`, `jettisonedCargo`, `sealedCanisters` | `trade` entry |
| `plundered`, `scooped`, `orbitTradeCompleted` | `trade` entry (`plunder`, `scoop`, `orbitBuy`/`orbitSell`; an orbit sale's profit is `total − (before.priceCargo[item] − after.priceCargo[item])`) **and** folded into the open encounter |
| `combatRound`, `encounterChanged`, `playerAttacked`, `playerFled`, `opponentDestroyed`, `opponentDisabled`, `playerEscaped`, `opponentEscaped`, `bountyPaid`, `looted`, `blackmailed`, `bribed`, `fined`, `yielded`, `inspectionClean`, `artifactRelinquished`, `preciousHidden`, `sculptureTaken`, `wildJoinedPirates`, `tonicConsumed`, `captainTraining`, `scoopNoRoom`, `playerDestroyed`, `bothDestroyed` | folded into the open encounter (LOG-019) |
| `encounterStarted` | opens the encounter ledger |
| `departed` (parsecs = `distance(from,to)` under the ruleset rule from `before`, 0 via wormhole), `fabricRip`, `singularityLost` | `departed` / `fabricRip` / `singularityLost` entry |
| `arrived` (with `uneventfulTrip` of the same trip folded in as `uneventful`) | `arrived` entry |
| `uneventfulTrip` | folded into the next `arrived` entry |
| `arrested`, `caughtLittering`, `reactorConfiscated` | `police` entry (`reactorConfiscated` also folds into an open encounter) |
| `borrowed`, `repaid`, `insuranceBought`, `insuranceStopped`, `debtWarning`, `debtReminder` | `finance` entry |
| `boughtShip`, `customShipBuilt`, `boughtEquipment`, `soldEquipment`, `boughtEscapePod`, `boughtFuel`, `repairedHull`, `autoFuelFailed`, `autoRepairFailed`, `escapePodUsed` | `ship` entry (`escapePodUsed` also closes an open encounter) |
| `hired`, `fired`, `passengerConcerned`, `passengerImpatient` | `crew` entry |
| `specialEventCompleted`, `specialEventRefused`, `tribblesChanged`, `tribblesDied`, `tribblesAteFood`, `tribbleInspectorWarning`, `reactorWarning`, `reactorMeltdown`, `gemulonInvaded`, `experimentPerformed`, `wildLeftShip`, `easterEgg`, `easterEggNoShieldSlot` | `quest` entry |
| `gameEnded` | `gameEnded` entry (after any encounter closed in the same step) |
| `cheatUsed` | `cheatsEnabled` entry only when `before.cheatsUsed == false`; otherwise dropped |
| `gameStarted`, `optionsChanged`, `cheatReadout`, `departureBlocked`, `cannotTransfer`, `cannotAffordTransfer`, `cannotAffordAllTransfers` | dropped (settings, read-outs, or details already shown where the action was taken) |

- **LOG-016** {M10} [M][W][P] Newspaper: a step whose command is `.readNewspaper` and whose decision is `.newspaper(paper)` appends `news(NewsEntry { headlines: paper.headlines, cost })` with `cost = before.commander.cash − after.commander.cash`. (source: UI-ENC-099 "newspaper read"; NEWS)
- **LOG-017** {M10} [M][W][P] Status changes: after the event entries, when `before.policeRecord != after.policeRecord` a `status(.policeRecord(from:to:))` entry is appended, and likewise for `reputation`. (source: UX-VISION §5.3 "police record changes")
- **LOG-018** {M10} [M][W][P] `arrived.firstVisit` is `before.galaxy.systems[system].visited == false`; `encounterCount` is the number of encounter records closed since the matching `departed`. (source: UX-VISION §5.3)

## 4. Encounter ledger

- **LOG-019** {M10} [M][W][P] `EncounterLedger { type, opponent: ShipType, startDay, startSystem, clicks, rounds, minPlayerHull, playerHullStrength, events: [GameEvent], surrendered: Bool }` opens on `encounterStarted` (`playerHullStrength` from `before`), counts `combatRound`s and keeps the lowest `playerHull`, records `surrendered = true` when an accepted command in it is `.encounter(.surrender)`, and closes when the step ends with `after.phase` not `.encounter` (or a new `encounterStarted` arrives). Closing appends `encounter(EncounterRecord { type, opponent, rounds, outcome: EncounterOutcomeKind, bounty, minHullPercent, killsAfter: Kills })` with `minHullPercent = minPlayerHull × 100 / playerHullStrength` and `killsAfter` = `after.commander.kills`. It is saved with the journal, so a game saved mid-encounter resumes the same ledger. (source: UX-VISION §4.9 "encounters with outcome"; GameState.swift `Kills`)
- **LOG-020** {M10} [M][W][P] `EncounterOutcomeKind` uses the precedence of UI-ENC-052 (endings, arrest, combat results, plunder, trade, police, very rare) with cases `destroyed(ShipType)`, `disabled`, `escaped`, `opponentEscaped`, `plundered`, `traded`, `bribed(Int)`, `fined(Int)`, `inspectedClean`, `yielded`, `arrested`, `raided(units: Int)`, `artifactSurrendered`, `drank(good: Bool)`, `trained(SkillType)`, `escapePod`, `killed`, `passed`; an app test checks that the app's `EncounterOutcome.derive` and this derivation agree for every UI-ENC fixture. (source: UI-ENC-052)
- **LOG-021** {M10} [M][W][P] `EncounterRecord.result: EncounterResultClass` is `won` (`destroyed` or `disabled`), `fled` (`escaped`), `surrendered` (ledger `surrendered`, or `raided`/`artifactSurrendered`), `lost` (`killed`, `escapePod`, `arrested`) or `other`; STAT counts these (STAT-009). (source: UX-VISION §4.10 "encounters won, fled and surrendered")

## 5. Reading the log

- **LOG-022** {M10} [M][W][P] `LogQuery.groups(_ entries:, filter: LogFilter, matching: (LogEntry) -> Bool) -> [LogDayGroup]` groups entries by consecutive (day, system), newest group first and newest entry first within a group; `LogFilter` is a set of `LogCategory` (empty = all). The text predicate is supplied by the app (it matches localized text). (source: UX-VISION §4.9 "A chronological, searchable feed … grouped by day and system")
- **LOG-023** {M10} [M][W][P] `LogEntryText.text(for:, journal:, state:) -> String` (app) renders every `LogEntryKind` with localized strings and names (`Names`, `EventText` wording where the event already has one); an exhaustive test renders one fixture per kind and checks a non-empty localized result. Search matches the rendered text and the flavor text, case- and diacritic-insensitively. (source: UX-VISION §4.9 "searchable"; UI-SHELL Conventions "Localization")
- **LOG-024** {M10} [M][W][P] `LogMarkdown.render(journal:, header: LogMarkdownHeader, filter:, text: (LogEntry) -> String, flavor: (LogEntry) -> String?) -> String` (ParsecInsights, pure) writes `# <title>` and a metadata line (commander, ruleset, difficulty, galaxy code, all supplied by the app), then oldest first one `## Day <d> · <system>` heading per day/system group and one `- <text>` bullet per entry, followed by an indented italic flavor line when present. Markdown-significant characters in supplied text (`\ * _ [ ] # < > `` ` ``) are backslash-escaped; output ends with a single newline. Golden test with a stub renderer. (source: PRD §6.6 "The log exports to Markdown")

## 6. Session integration (app)

- **LOG-025** {M10} [M][W][P] `GameSession` owns `journal: GameJournal?`, set on `install` (from `LoadedGame.journal`, from `GameJournal.start` for new games and scenarios) and cleared on Close Game. After every step consumed by UI-SHELL-003 (not rejected, not a confirmation request) it calls `JournalRecorder.record` with the step's `StepRecord` before the persistence triggers run, so autosaves and Ironman writes include the new entries. (source: PRD §6.5 "GameSession … owns … the feed and the services")
- **LOG-026** {M10} [M][W][P] Every save path writes the session's journal with the state: Save, Save As, autosave (SAV-038), Ironman writes (SAV-046), quit, and export. A unit test saves, loads and checks the journal equals the one in memory. (source: SAV-038, SAV-046)
- **LOG-027** {M10} [M][W][P] Journal changes that are not steps (a generated flavor arriving, LLM-021) do not bump `stateGeneration`, do not run persistence triggers and never touch `engine`; they are persisted by the next save. (source: PRD §6.6 "flavor never changes game state")
- **LOG-028** {M10} [M][W][P] UI-ENC-099 coverage: an app test plays a scripted trip with an encounter, an arrival report, a special event and a newspaper, and checks that the journal holds one entry for each arrival-report item, the encounter record, the quest entry and the news entry. (source: UI-ENC-099; UX-VISION §5.3 "Each item is also posted to the log")

## 7. Logbook (app)

- **LOG-029** {M10} [UI] [M][W][P] `Section.logbook` (`sidebar.logbook`, ⌘9, after Quests) shows the Logbook; it is available whenever a game is loaded, including an ended game (MENU-023), and is the only section available after the game has ended. Its root is `logbook.root`. (source: UX-VISION §4.9; MENU-023; UI-SHELL-035)
- **LOG-030** {M10} [UI] [M][W][P] A segmented tab control `logbook.tab` with `logbook.tab.log` (Captain's Log), `logbook.tab.statistics` and `logbook.tab.achievements`; the selected tab is restored per window (`@SceneStorage`). (source: UX-VISION §4.9 "tabs Captain's Log, Statistics, Achievements")
- **LOG-031** {M10} [UI] [M][W][P] Captain's Log tab: a list (`logbook.log.list`) of LOG-022 groups with section headers "Day N · <system>" and one row per entry (`logbook.entry.<id>`) showing the category symbol, the LOG-023 text and, when Settings › Intelligence › Show flavor text is on (LLM-027), the flavor line in secondary italic text. Encounter rows expand to show outcome, rounds and lowest hull. (source: UX-VISION §4.9)
- **LOG-032** {M10} [UI] [M][W][P] Search: ⌘F with the Logbook shown focuses `logbook.search` (MENU-018 context search gains `logbook`); typing filters rows live; Esc clears. Category filter toggles `logbook.filter.<LogCategory>` in a menu (`logbook.filter`); a "Clear filters" item (`logbook.filter.clear`). An empty result shows "No entries match". (source: UX-VISION §4.7 "⌘F … in the Logbook it searches the log", §4.9 "Filters by category")
- **LOG-033** {M10} [UI] [M][W][P] Export…: `logbook.export` opens `fileExporter` with a `.md` document (`UTType(filenameExtension: "md")`, conforming to plain text) named "<Commander> – Captain's Log.md", containing `LogMarkdown.render` of the current filter. (source: UX-VISION §4.9 "Export to a Markdown file")
- **LOG-034** {M10} [UI] [M][W][P] Edit › Copy (⌘C) with log rows selected copies their LOG-024 bullet lines (oldest first) to `NSPasteboard` as plain text. (source: UX-VISION §10.1 "Copy is enabled for the log and stats")
- **LOG-035** {M10} [UI] [M][W][P] The feed overlay (UI-SHELL-044) gains "Show Logbook" (`status.feed.showLogbook`), which closes the overlay and selects the Logbook's log tab; it is disabled while the encounter lock (MENU) applies. The game-over card gains "Show Logbook" (`gameOver.showLogbook`) and the Logbook in an ended game shows "Back to Summary" (`logbook.backToSummary`) returning to the card. (source: UI-ENC-099 "The feed overlay gains 'Show Logbook'"; UX-VISION §5.5)
- **LOG-036** {M10} [UI] [M][W][P] Identifier walk: UI-SHELL-127's walk is extended to the Logbook's three tabs, the search field, filter menu and export button. (source: PRD §6.5 "Every interactive element has an accessibilityIdentifier")

## 8. Performance and fuzzing

- **LOG-037** {M10} [M][W][P] `pmsim fuzz` records a journal for every game and checks after each step: ids strictly increasing; entry days non-decreasing; every entry's `system` is a valid index; the `arrived` entries' systems plus the start system equal the set of `visited` systems in the state; no entry is appended for a rejected step; and every 50th game's journal round-trips byte-identically through `SaveCodec`. (source: PRD §8.1 fuzzing; PRD §6.2 invariants)
- **LOG-038** {M10} [M][W][P] `pmsim bench` gains `journal.record` (median time of `JournalRecorder.record` over a fuzz game, budget 0.5 ms) and `journal.encode` (encoding a 20 000-entry journal, budget 300 ms); `--check` enforces both in release. (source: PRD §6.5 "Heavy pure work"; PRD §8.1 benchmarks)

## 9. Later milestones

- **LOG-039** {M12} [UI] [M][W][P] Accessibility: each log group is an accessibility container labelled "Day N, <system>"; a custom rotor "Log days" moves between groups; rows read text and flavor; checked in the M12 audit (flow 6) and at the largest Text Size (flow 7). (source: UX-VISION §9; PRD §9 M12)

## 10. Identifier catalog (extend, never rename)

| Area | Identifiers |
|---|---|
| Logbook | `sidebar.logbook`, `menu.view.logbook`, `logbook.root`, `logbook.tab`, `logbook.tab.log`, `logbook.tab.statistics`, `logbook.tab.achievements`, `logbook.backToSummary` |
| Captain's Log | `logbook.log.list`, `logbook.entry.<id>`, `logbook.search`, `logbook.filter`, `logbook.filter.<LogCategory>`, `logbook.filter.clear`, `logbook.export` |
| Elsewhere | `status.feed.showLogbook`, `gameOver.showLogbook` |

## 11. Types proposed by this spec

- ParsecInsights: `GameJournal` (`start(state:)`, `bootstrap(from:)`), `JournalStart`, `JournalOrigin` (`newGame`, `resumed`), `LogEntry`, `LogEntryKind`, `LogCategory`, `TradeEntry`, `TradeAction`, `TripArrival`, `PoliceEntry`, `FinanceEntry`, `ShipEntry`, `EquipmentChange`, `CrewEntry`, `QuestEntry`, `NewsEntry`, `StatusEntry`, `EncounterLedger`, `EncounterRecord`, `EncounterOutcomeKind`, `EncounterResultClass`, `JournalStep`, `JournalRecorder`, `JournalStepOutput`, `LogQuery`, `LogFilter`, `LogDayGroup`, `LogMarkdown`, `LogMarkdownHeader`.
- ParsecPersistence: `SaveEnvelope.journal: GameJournal`, `SlotStore.save(_:journal:slot:gameID:)`, `SlotStore.autosave(_:journal:gameID:)`, `LoadedGame.journal`.
- App: `Section.logbook`, `LogbookView`, `LogbookTab`, `CaptainsLogView`, `LogbookModel` (search text, filter, selection), `LogEntryText`, `LogMarkdownDocument` (`FileDocument` for export), `GameSession.journal`.

## 12. Notes

- **Cross-spec follow-ups (owned elsewhere):** SAV-001's key list gains `journal` and SAV §15's open question is closed by LOG-001; UI-SHELL-035's `Section` gains `.logbook` and `Section.isAvailable` lets only the Logbook through for an ended game; MENU-018's context search gains `logbook`; UI-ENC-099 is satisfied by LOG-019…021, LOG-028, LOG-035, STAT-021 and ACH-018; the `SessionAchievements.observe(events:state:)` stand-in (SessionServices.swift) is replaced by the journal output (ACH-017).
- **ADR needed:** LOG-001 refines PRD §6.2's `GameState` field list ("event log, player intel"); record it as an ADR before the code lands.
- **Feed vs log:** the feed stays an in-memory, 500-item, per-session list of raw events and notes (UI-SHELL-008); the log is the persistent, typed, curated history. They are built from the same steps but neither is derived from the other.
