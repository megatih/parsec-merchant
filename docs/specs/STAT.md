# STAT: Statistics

> Format (PRD §7): `- **ID** {Mn} [UI] [M][W][P] statement (source)`. `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2. `[UI]` = verified by app tests (`SpaceTraderMacTests`) or XCUITest (`SpaceTraderMacUITests`). Bullets without `[UI]` are pure logic in `Packages/ParsecKit/Sources/ParsecInsights/Stats/` tested in `ParsecInsightsTests`, unless they name an app type, in which case they are unit-tested in `SpaceTraderMacTests`.
> Milestones: everything here is {M10} (PRD §9 M10). Chart accessibility is {M12}.
> Normative inputs: PRD §6.1 ("Stats/Log folds" in ParsecInsights), §6.5 ("Heavy pure work, such as … folding statistics, runs off the main actor on Sendable snapshots"), §6.6 "Statistics and Log (STAT, LOG): folds over the log … A career summary card can be rendered with `ImageRenderer` and shared through `ShareLink`."; UX-VISION §4.10 (Statistics tab), §5.5 (career card), §10.1 (Copy for stats), §12 (FormViewCommander / FormViewShip → Inspector + Logbook › Statistics).
> **Ownership (do not restate, reference).** Log entries and their payloads: LOG-008…021. Achievement conditions over these statistics: ACH. The career card's state-derived fields: UI-ENC-083.

## 1. The fold

- **STAT-001** {M10} [M][W][P] `CareerStats` is a `Sendable, Equatable` value with `static func fold(_ entries: [LogEntry]) -> CareerStats` and `mutating func add(_ entry: LogEntry)`; `fold` equals `entries.reduce(into: CareerStats()) { $0.add($1) }`. It reads only the entries (no `GameState`), draws no random numbers and is total: an empty log gives the zero value. (source: PRD §6.6 "folds over the log")
- **STAT-002** {M10} [M][W][P] Incremental equivalence: property test over 50 recorded fuzz games per ruleset: folding all entries at once equals adding them one step at a time, and equals folding any prefix and then the rest. The session keeps one incremental `CareerStats` per game (rebuilt by `fold` on install) and advances it with each step's `newEntries` (LOG-013). (source: PRD §6.5 "folding statistics")
- **STAT-003** {M10} [M][W][P] The session rebuilds the stats off the main actor on load (a `nonisolated` async fold of the journal's entries) and applies the result only if the journal has not changed since; during the rebuild the Statistics tab shows a progress indicator. (source: PRD §6.5; MAP-062 pattern)
- **STAT-004** {M10} [M][W][P] `CareerStats.isPartial` is true when the first entry is `journalStarted` with origin `.resumed` (LOG-006); the Statistics tab then shows "Statistics since day N" instead of "since the start". (source: LOG-006)

## 2. Fields

- **STAT-005** {M10} [M][W][P] Time and travel: `startDay`, `lastDay` and `daysPlayed = lastDay − startDay` (from entry days); `warps` (count of `departed`), `wormholeJumps` (`departed` with `viaWormhole`), `parsecsTravelled` (sum of `departed.parsecs`), `arrivals`, `fabricRips`, `systemCount` (from `JournalStart`) and `visitedSystems` (a `[Bool]` of `systemCount`, seeded with `JournalStart.visitedSystems` and the start system, set by each `arrived`), `visitedCount`. (source: UX-VISION §4.10 "days, distance travelled, systems visited")
- **STAT-006** {M10} [M][W][P] Trade: `buys`, `sells` (counts of `trade` entries with action `buy`/`orbitBuy` and `sell`/`orbitSell`), `unitsBought`, `unitsSold`, `spentOnCargo` (sum of buy totals), `earnedFromCargo` (sum of sell totals), `profitByItem: [Int]` (one per `TradeItemType`, sum of sale profits, may be negative), `totalTradeProfit`, `itemsBought` and `itemsSold` (`[Bool]` per item), `bestSale: BestSale?` (`item, quantity, profit, day, system`; the largest single-sale profit, ties to the earlier entry), `firstProfitDay: Int?` (day of the first sale with profit > 0), `plunderedUnits`, `scoopedUnits`, `dumpCosts`. (source: UX-VISION §4.10 "profit by commodity", "best trade")
- **STAT-007** {M10} [M][W][P] Worth: `worthSamples: [WorthSample { day, worth }]` with one sample per day that has entries (the last entry's `worth` of that day), `peakWorth` (max over all entries' `worth`, including the start entry) and `latestWorth`. (source: UX-VISION §4.10 "net worth over time")
- **STAT-008** {M10} [M][W][P] Combat: `encounters` (count of `encounter` records), `encountersByType: [Int]` per `EncounterType`, `destroyedByShipType: [Int]` per `ShipType` (from `destroyed(ShipType)` outcomes), `kills: Kills` = the `killsAfter` of the newest encounter record, or `JournalStart.kills` when there is none (the engine's counters are the authority, because some kills are counted without a destroy event, e.g. disabled traders plundered, EncounterActions.swift), `bountiesCollected` (count) and `bountyTotal`, `lowestHullPercentSurvived: Int?` (lowest `minHullPercent` of an encounter whose result is not `lost`). (source: UX-VISION §4.10 "kills by type"; Combat.swift `encounterWon`)
- **STAT-009** {M10} [M][W][P] `encounterResults: [EncounterResultClass: Int]` is stored as five counters `won`, `fled`, `surrendered`, `lost`, `other` (LOG-021; no dictionary). (source: UX-VISION §4.10 "encounters won, fled and surrendered")
- **STAT-010** {M10} [M][W][P] Law and money: `arrests`, `finesPaid` (sum of `fined` outcomes and `arrested.fine`), `bribesPaid`, `inspectionsPassed`, `policeRecordLowest` / `policeRecordHighest` and `reputationHighest` (from `status` entries and the start), `borrowedTotal`, `repaidTotal`, `loansPaidOff` (count of `repaid` with `remainingDebt == 0`), `insurancePayouts` (sum of `escapePodUsed.insurancePayout`), `escapePodsUsed`. (source: PRD §6.6 suggested achievements; UX-VISION §4.10)
- **STAT-011** {M10} [M][W][P] Ship, crew and quests: `shipsBought` (count, including custom), `customShipsBuilt`, `equipmentBought`, `equipmentSold`, `fuelSpent`, `repairsSpent`, `mercenariesHired`, `questsCompleted: [Bool]` per `SpecialEventType` (from `quest(.completed)`), `maxTribbles` (max `tribbles.to`), `newspapersRead`, `marieCelesteFound`, `famousCaptainsMet: [Bool]` (Ahab, Conrad, Huie; from encounter types `captainAhab`, `captainConrad`, `captainHuie`). (source: PRD §6.6 suggested achievements)
- **STAT-012** {M10} [M][W][P] Game: `ruleset`, `difficulty`, `ironman` (from `JournalStart`), `cheatsUsed` (true once a `cheatsEnabled` entry is folded), `ended: GameEndType?` and `finalScore: Int?` (from `gameEnded`), `achievementsUnlocked` (count of `achievementUnlocked`). (source: CHEAT-004; SCORE)

## 3. Series for charts

- **STAT-013** {M10} [M][W][P] `CareerStats.worthSeries(maxPoints: Int) -> [WorthSample]` returns `worthSamples` unchanged when it has at most `maxPoints` entries; otherwise it splits the day range into `maxPoints` equal buckets (integer arithmetic) and keeps the last sample of each non-empty bucket, always including the first and last samples. Deterministic; unit tests with 10, 500 and 5 000 samples. (source: UX-VISION §4.10 "net worth over time (Swift Charts line)")
- **STAT-014** {M10} [M][W][P] `CareerStats.figures: [StatFigure]` returns the Statistics tiles in a fixed order with typed values (`.days`, `.parsecs`, `.systems(visited, of)`, `.credits`, `.count`, `.trade(BestSale)`): days played, parsecs travelled, systems visited, wormhole jumps, trades, total trade profit, best trade, encounters won / fled / surrendered, kills (pirates, police, traders), bounties, fines and bribes, arrests, peak worth. The app localizes them. (source: UX-VISION §4.10)

## 4. Agreement with the engine

- **STAT-015** {M10} [M][W][P] Property test over the `pmsim fuzz` games of every ruleset whose journal starts with origin `.newGame`: `kills == state.commander.kills`, `daysPlayed == state.commander.days − startDay`, `visitedCount` equals the number of systems with `visited == true`, and `latestWorth == state.worth`. Cheat steps are excluded from the generator for this test (cheats can set counters directly, CHEAT §3). (source: PRD §6.2 "Invariants"; LOG-037)
- **STAT-016** {M10} [M][W][P] A scenario test sells cargo bought at known prices and checks `profitByItem`, `totalTradeProfit` and `bestSale` against hand-computed values, including an orbit sale whose profit comes from the cost-basis difference (LOG §3a). (source: ECO cost basis `priceCargo`)

## 5. Statistics tab (app)

- **STAT-017** {M10} [UI] [M][W][P] The Statistics tab (`logbook.stats`) shows the STAT-014 tiles (`logbook.stats.figure.<StatFigureKind>`), a Swift Charts line of net worth over days (`logbook.stats.worthChart`, `worthSeries(maxPoints: 400)`), signed bars of profit by commodity (`logbook.stats.profitChart`, positive and negative bars also carry "+"/"−" labels), and bars of kills by ship type (`logbook.stats.killsChart`, ship types with zero omitted). Empty charts show "No data yet". (source: UX-VISION §4.10 "Statistics")
- **STAT-018** {M10} [UI] [M][W][P] The tab shows "Statistics since day N" for a partial history (STAT-004) and, for a cheated game, a notice "Cheats were used in this game" without hiding any figure (cheats disable achievements and high scores, not statistics). (source: PRD §8.3; STAT-004)
- **STAT-019** {M10} [UI] [M][W][P] Edit › Copy with the Statistics tab shown copies `StatsMarkdown.render(stats:, labels:)` (ParsecInsights, pure: a two-column Markdown table of the figures, labels supplied by the app) to the pasteboard. Golden test of the renderer with stub labels. (source: UX-VISION §10.1 "Copy is enabled for the log and stats")
- **STAT-020** {M10} [UI] [M][W][P] The inspector's commander area gains "Show Statistics" (`inspector.showStatistics`), which selects the Logbook's Statistics tab, replacing the classic Commander Status totals that are not already shown. (source: UX-VISION §12 "FormViewCommander / FormViewShip → Inspector (+ Logbook › Statistics)")

## 6. Career card

- **STAT-021** {M10} [M][W][P] `CareerCard.make(state:end:recorded:stats:)` gains `stats: CareerStats?` and, when present, the totals encounters won, fled and surrendered, best trade (item, profit), systems visited "N of M", parsecs travelled and achievements unlocked in this game. The state-derived fields of UI-ENC-083 are unchanged, including kills from `state.commander.kills`. Unit tests with and without stats. (source: UI-ENC-099 "The career card adds STAT totals"; UX-VISION §5.5)
- **STAT-022** {M10} [UI] [M][W][P] The game-over card's career card (UI-ENC) renders the STAT-021 rows, and the image shared through `ShareLink` (rendered with `ImageRenderer`) includes them; a test renders the card for a fixture game and checks a non-empty image of the expected size. (source: PRD §6.6 "A career summary card can be rendered with `ImageRenderer` and shared through `ShareLink`")

## 7. Later milestones

- **STAT-023** {M12} [UI] [M][W][P] Chart accessibility: each chart provides an `AXChartDescriptor` (audio graph) and a text summary ("Net worth rose from 1,000 to 312,400 credits over 412 days"); bars carry sign text so colour is never the only signal; checked by the M12 audit (flow 6). (source: UX-VISION §9, §1.7)

## 8. Identifier catalog (extend, never rename)

| Area | Identifiers |
|---|---|
| Statistics | `logbook.stats`, `logbook.stats.figure.<StatFigureKind>`, `logbook.stats.worthChart`, `logbook.stats.profitChart`, `logbook.stats.killsChart` |
| Elsewhere | `inspector.showStatistics` |

## 9. Types proposed by this spec

- ParsecInsights: `CareerStats` (`fold`, `add`, `worthSeries(maxPoints:)`, `figures`), `WorthSample`, `BestSale`, `StatFigure`, `StatFigureKind`, `StatsMarkdown`.
- App: `StatisticsView`, `StatFigureText`, `GameSession.careerStats`; `CareerCard.make(state:end:recorded:stats:)`.

## 10. Notes

- **Statistics are not gated by cheats.** PRD §8.3 disables achievements and high scores for cheated games; statistics stay visible with a notice (STAT-018).
- **Kill totals** come from the engine's counters (stamped into encounter records), not from counting destroy events, so the Logbook, inspector and career card always agree (STAT-008, STAT-015).
