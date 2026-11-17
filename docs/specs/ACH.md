# ACH: Achievements

> Format (PRD §7): `- **ID** {Mn} [UI] [M][W][P] statement (source)`. `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2. `[UI]` = verified by app tests (`SpaceTraderMacTests`) or XCUITest (`SpaceTraderMacUITests`). Bullets without `[UI]` are pure logic in `Packages/ParsecKit/Sources/ParsecInsights/Achievements/` (tested in `ParsecInsightsTests`) or the store in `ParsecPersistence` (tested in `ParsecPersistenceTests`), unless they name an app type, in which case they are unit-tested in `SpaceTraderMacTests`. On a catalog bullet (§6) the ruleset tags say where the achievement is available.
> Milestones: everything here is {M10} (PRD §9 M10). Vector badge art and the achievement chime are {M11} (ART, AUD); accessibility polish and the Reset Tips pairing are {M12}.
> Normative inputs: PRD §6.4 ("Achievements are stored as JSON"), §6.5 (GameSession owns the Achievement service), §6.6 "Achievements (ACH): at least 30, as pure folds over the log, disabled when cheats are used" and its suggested set, §8.3 ("Cheats disable achievements and high scores"); UX-VISION §2 (Settings › Advanced "reset … achievements"), §4.10 (Achievements tab: grid of badges with progress, disabled for cheated saves), §8 ("achievement: chime"); CHEAT-004.
> **Ownership (do not restate, reference).** The statistics the conditions read: STAT-005…012. Log entries and recording order: LOG-008, LOG-013. Cheat flagging: CHEAT-001/002.

## 1. Model

- **ACH-001** {M10} [M][W][P] `AchievementID` is a `String`-raw-valued, `CaseIterable` enum with the 36 cases of §6, in that order. Raw values are lowerCamelCase and permanent (they key the store, ACH-011); a test fails if a raw value changes or a case is removed. (source: PRD §6.6 "at least 30")
- **ACH-002** {M10} [M][W][P] `AchievementCatalog.definition(_:ruleset:) -> AchievementDefinition { id, kind: .threshold(target: Int) | .flag, availability: (Ruleset) -> Bool, progress: (CareerStats) -> Int }`. An achievement is **satisfied** when `progress ≥ target` (threshold) or `progress == 1` (flag). Every condition is a pure function of `CareerStats` (STAT), so achievements are pure folds over the log. (source: PRD §6.6 "pure folds over the log")
- **ACH-003** {M10} [M][W][P] Availability uses ruleset content, never `ruleset.id`: the Sculpture and Princess achievements need `content` with those quest chains, the designer achievement needs `content.hasShipyards`. Every ruleset has at least 30 available achievements (Palm 1.2.2: 33). Unit test per ruleset. (source: CLAUDE.md "Never write `if ruleset.id == …`"; QST-INDEX §1 content-pack column)
- **ACH-004** {M10} [M][W][P] `AchievementCatalog.evaluate(_ stats: CareerStats, ruleset:) -> [AchievementProgress]` returns, for every available achievement in catalog order, `AchievementProgress { id, current: Int, target: Int, satisfied: Bool }` with `current` clamped to `target`. Unavailable achievements are omitted. (source: UX-VISION §4.10 "each with progress")
- **ACH-005** {M10} [M][W][P] `AchievementCatalog.satisfied(_ stats:, ruleset:) -> [AchievementID]` lists the satisfied ones in catalog order; empty whenever `stats.cheatsUsed` (ACH-008). (source: PRD §8.3)
- **ACH-006** {M10} [M][W][P] Unlock transition, run by the journal recorder (LOG-013 step 4): `newlyUnlocked = satisfied(stats after the step's entries) − satisfied(stats before)`, in catalog order. Each is appended as an `achievementUnlocked(id)` entry stamped like the step's other entries and returned in `JournalStepOutput.unlocked`. An achievement already satisfied when a journal is loaded or bootstrapped is never reported again by that journal. (source: PRD §6.6; LOG-013)
- **ACH-007** {M10} [M][W][P] Fold test per catalog entry: a hand-built entry list that just meets the condition satisfies it and one that just misses does not; and a scenario test per quest-chain achievement drives the chain's QST scenario to completion and checks the unlock entry appears exactly once. (source: PRD §6.6; QST scenario tests)

## 2. Cheats

- **ACH-008** {M10} [M][W][P] A game with `cheatsUsed` unlocks nothing: from the step in which the first `cheatsEnabled` entry is recorded, and for any journal that contains one (including scenario games, CHEAT-049, and bootstrapped states with `cheatsUsed`), `satisfied` is empty and no `achievementUnlocked` entry is appended. Progress is not counted for the rest of that game. (source: CHEAT-004; PRD §8.3)
- **ACH-009** {M10} [M][W][P] Unlocks earned before the first cheat stay unlocked in the app-wide store and their log entries stay in the journal; cheating never removes an achievement. A test unlocks First Profit, then sends `.cheat(.enable)`, then meets another condition and checks only the first unlock exists. (source: CHEAT-002 "cheatsUsed can never be cleared"; PRD §8.3)
- **ACH-010** {M10} [UI] [M][W][P] In a cheated game the Achievements tab shows the banner "Achievements are disabled for this game because cheats were used." (`logbook.achievements.disabled`) and no per-game progress; app-wide unlocked badges are still shown. (source: UX-VISION §4.10 "Disabled for saves that have used cheats")

## 3. Store (app-wide, JSON)

- **ACH-011** {M10} [M][W][P] `AchievementStore(root:)` (ParsecPersistence) keeps `root/Achievements.json` as `{"format":"parsec-merchant-achievements","schemaVersion":1,"unlocked":[AchievementRecord…]}` with `AchievementRecord { id: String, unlockedAt: String (ISO 8601 UTC, from an injected clock), gameID, rulesetID, day }`, sorted by `id`, encoded with sorted keys and written atomically (SAV-018). IDs are stored as raw strings, and records with unknown IDs are kept and rewritten unchanged, so an older app never drops a newer app's achievements. (source: PRD §6.4 "Achievements are stored as JSON"; SAV-018, SAV-049 pattern)
- **ACH-012** {M10} [M][W][P] `AchievementStore.unlock(_ ids: [String], gameID:, rulesetID:, day:) -> [String]` (a `mutating` method of the `Sendable` struct) adds a record for each id not already stored and returns the ids actually added (first unlock wins; a later unlock never overwrites the date). `records() -> [AchievementRecord]` and `isUnlocked(_:)` read it. Round trip and idempotence tests. (source: PRD §6.6)
- **ACH-013** {M10} [M][W][P] Robustness mirrors SAV-050: an unreadable file is quarantined to `Corrupt/` and the store continues empty; a future `schemaVersion` is left in place and the store refuses to write (unlocks are kept in memory for the session in `sessionOnly` and reported as not persisted by `isPersisting == false`). (source: SAV-050)
- **ACH-014** {M10} [M][W][P] `AchievementStore.reset()` deletes every record (writes an empty `unlocked` array). Journals keep their `achievementUnlocked` entries; because unlocks are transitions (ACH-006), a reset is not undone by loading a game that already satisfied an achievement. (source: UX-VISION §2 "Advanced (reset … achievements …)")
- **ACH-015** {M10} [M][W][P] Per-game unlock events live in the journal (`achievementUnlocked` entries, LOG-009) and app-wide unlocks in the store; the Logbook shows both ("Unlocked in this game on day N" vs "Unlocked on <date>"). `-PMResetState` clears the store with the rest of the sandbox data (CHEAT-051). (source: PRD §6.4, §6.6; CHEAT-051)

## 4. Session and presentation (app)

- **ACH-016** {M10} [M][W][P] `AchievementService` (the `SessionAchievements` implementation, PRD §6.5) receives each step's `JournalStepOutput.unlocked` and calls `AchievementStore.unlock` with the game's id, ruleset and day; for every id actually added it posts `FeedNote.achievementUnlocked(AchievementID)` to the feed (classified `.system`, `.notice`, text "Achievement unlocked: <name>"). Ids already in the store produce no note. (source: PRD §6.5 "services (… Achievement …)"; UX-VISION §5.3 feed)
- **ACH-017** {M10} [M][W][P] The M7 stand-in `SessionAchievements.observe(events:state:)` is replaced by `observe(_ output: JournalStepOutput, gameID:, state:)`; tests use an in-memory store rooted in a temporary directory. No achievement work runs for rejected steps or confirmation requests. (source: SessionServices.swift stand-ins; LOG-013)
- **ACH-018** {M10} [M][W][P] Achievements never change game state or RNG draws: a test plays the same scripted game with the real service and with `NoAchievements` and checks identical state hashes after every step. (source: PRD §6.6; PRD §6.2 "Determinism")
- **ACH-019** {M10} [UI] [M][W][P] The Achievements tab (`logbook.achievements`) is a grid of badges (`logbook.achievements.badge.<AchievementID>`), one per achievement available in the current ruleset, in catalog order. Each shows a symbol (an SF Symbol until M11), name, one-line description, a progress bar with "current / target" for threshold achievements (this game's progress, ACH-004), and, when unlocked app-wide, a seal plus "Unlocked <date>" (and "in this game, day N" if this journal has the entry). Locked and unlocked differ by symbol and text, not colour alone. A header shows "<n> of <m> unlocked". (source: UX-VISION §4.10 "a grid of badges (vector-drawn), each with progress"; §1.7)
- **ACH-020** {M10} [UI] [M][W][P] Unavailable achievements (ACH-003) are listed in a collapsed "Not available in this ruleset" group (`logbook.achievements.unavailable`), so the grid never shows a goal the player cannot reach. (source: ACH-003)
- **ACH-021** {M10} [UI] [M][W][P] Settings › Advanced gains "Reset Achievements…" (`settings.resetAchievements`), which asks `AppConfirmation.resetAchievements` (destructive, Cancel default: "Reset all achievements? This can't be undone.") and calls `AchievementStore.reset()`. (source: UX-VISION §2; UI-SHELL-101 "Reset Achievements {M10} (ACH)")
- **ACH-022** {M10} [UI] [M] A UI test launches with `-PMResetState` and `-PMSeed <achievementSeed>` (not a scenario, which would set `cheatsUsed`), starts a Quick Start game, buys one unit of the fixture item, warps to the next target, sells it, and finds the feed note and the First Profit badge marked unlocked. An app unit test checks, like UI-SHELL-129, that this seed's trip is uneventful and the sale makes a profit. (source: UX-VISION §4.10; PRD §8.2; UI-SHELL-129)

## 5. Later milestones

- **ACH-023** {M11} [UI] [M][W][P] Badges are vector-drawn by ParsecArt (one glyph per achievement, locked/unlocked variants), with `ImageRenderer` determinism and non-empty tests; an unlock plays the achievement chime (AUD) and its visual twin is the feed note. (source: UX-VISION §4.10 "vector-drawn", §8 "achievement: chime"; PRD §6.6 "Every audio cue has a visual twin")
- **ACH-024** {M12} [UI] [M][W][P] Accessibility: each badge reads "<name>, unlocked on <date>" or "<name>, locked, <current> of <target>"; the grid is reachable with Full Keyboard Access; checked by the M12 audit (flow 6). (source: UX-VISION §9)

## 6. Catalog (36 achievements; the suggested set of PRD §6.6 plus additions)

Each bullet: raw value, condition over `CareerStats`, threshold or flag. "Win" means the game ended with `boughtMoon` or `boughtMoonGirl`.

- **ACH-030** {M10} [M][W][P] `firstProfit` "First Profit": `firstProfitDay != nil` (a sale with profit > 0, docked or in orbit). Flag. (source: PRD §6.6 "First profit")
- **ACH-031** {M10} [M][W][P] `worth10k` "Making a Living": `peakWorth ≥ 10 000`. Threshold 10 000 (progress = `peakWorth`). (source: PRD §6.6 "net worth of 10k")
- **ACH-032** {M10} [M][W][P] `worth100k` "Merchant Prince": `peakWorth ≥ 100 000`. Threshold. (source: PRD §6.6 "100k")
- **ACH-033** {M10} [M][W][P] `worth1m` "Millionaire": `peakWorth ≥ 1 000 000`. Threshold. (source: PRD §6.6 "1M")
- **ACH-034** {M10} [M][W][P] `dragonfly` "Dragon Slayer": `questsCompleted[.dragonflyShield]`. Flag. (source: PRD §6.6 "Each quest chain completed"; QST-DRAGONFLY)
- **ACH-035** {M10} [M][W][P] `spaceMonster` "Monster Hunter": `questsCompleted[.spaceMonsterKilled]`. Flag. (source: QST-MONSTER)
- **ACH-036** {M10} [M][W][P] `scarab` "Scarab Breaker": `questsCompleted[.scarabUpgradeHull]`. Flag. (source: QST-SCARAB)
- **ACH-037** {M10} [M][W][P] `japori` "Plague Doctor": `questsCompleted[.japoriDelivery]`. Flag. (source: QST-JAPORI)
- **ACH-038** {M10} [M][W][P] `jarek` "Diplomatic Courier": `questsCompleted[.jarekGetsOut]`. Flag. (source: QST-JAREK)
- **ACH-039** {M10} [M][W][P] `wild` "Smuggler's Friend": `questsCompleted[.wildGetsOut]`. Flag. (source: QST-WILD)
- **ACH-040** {M10} [M][W][P] `reactor` "Hot Cargo": `questsCompleted[.reactorLaser]`. Flag. (source: QST-REACTOR)
- **ACH-041** {M10} [M][W][P] `gemulon` "Gemulon Saved": `questsCompleted[.gemulonFuel]`. Flag. (source: QST-GEMULON)
- **ACH-042** {M10} [M][W][P] `experiment` "Fabric Mender": `questsCompleted[.experimentStopped]`. Flag. (source: QST-EXPERIMENT)
- **ACH-043** {M10} [M][W][P] `artifact` "Relic Runner": `questsCompleted[.artifactDelivery]`. Flag. (source: QST-ARTIFACT)
- **ACH-044** {M10} [M][W] `sculpture` "Art Thief's Bane": `questsCompleted[.sculptureHiddenBays]`. Flag; available only with the Sculpture chain. (source: QST-SCULPTURE; QST-INDEX §1)
- **ACH-045** {M10} [M][W] `princess` "Royal Escort": `questsCompleted[.princessQuantum]`. Flag; available only with the Princess chain. (source: QST-PRINCESS; QST-INDEX §1)
- **ACH-046** {M10} [M][W][P] `moon` "Lord of the Moon": the game was won (`ended` is `boughtMoon` or `boughtMoonGirl`). Flag. (source: PRD §6.6 "buying the moon"; QST-MOON)
- **ACH-047** {M10} [M][W][P] `waspKiller` "Wasp Swatter": `destroyedByShipType[.wasp] ≥ 1`. Flag. (source: PRD §6.6 "Defeating a Wasp")
- **ACH-048** {M10} [M][W][P] `closeCall` "Close Call": `lowestHullPercentSurvived` exists and is < 10. Flag. (source: PRD §6.6 "surviving below 10% hull")
- **ACH-049** {M10} [M][W][P] `hero` "Hero of the Spaceways": `policeRecordHighest == .hero` (every game starts Clean, so this is Clean→Hero). Flag. (source: PRD §6.6 "Clean→Hero")
- **ACH-050** {M10} [M][W][P] `villain` "Most Wanted": `policeRecordLowest ≤ .villain`. Flag. (source: PRD §6.6 "reaching Villain")
- **ACH-051** {M10} [M][W][P] `debtFree` "Debt Free": `loansPaidOff ≥ 1` (a repayment that brought debt from above 0 to 0). Flag. (source: PRD §6.6 "Paying off a loan")
- **ACH-052** {M10} [M][W][P] `explorer50` "Explorer": `visitedCount ≥ 50`. Threshold 50. (source: PRD §6.6 "Visiting 50 systems")
- **ACH-053** {M10} [M][W][P] `explorerAll` "Cartographer": `visitedCount == systemCount`. Threshold `systemCount` (the ruleset's galaxy size). (source: PRD §6.6 "visiting every system")
- **ACH-054** {M10} [M][W][P] `wormhole` "Through the Wormhole": `wormholeJumps ≥ 1`. Flag. (source: PRD §6.6 "Using a wormhole")
- **ACH-055** {M10} [M][W][P] `winHard` "Hardened": won with `difficulty ≥ .hard`. Flag. (source: PRD §6.6 "Winning on Hard")
- **ACH-056** {M10} [M][W][P] `winImpossible` "Impossible Odds": won with `difficulty == .impossible`. Flag. (source: PRD §6.6 "winning on Impossible")
- **ACH-057** {M10} [M][W][P] `allCommodities` "Jack of All Trades": every `TradeItemType` has `itemsBought` or `itemsSold` true. Threshold 10 (progress = items traded). (source: PRD §6.6 "Trading every commodity")
- **ACH-058** {M10} [M][W][P] `tribbleMax` "Tribble Trouble": `maxTribbles ≥ 100 000`. Threshold 100 000. The PRD's suggested 1M is unreachable because the engine caps tribbles at 100 000 in every ruleset, so the cap is the goal. (source: PRD §6.6 "reaching 1M tribbles"; Travel.swift `maxTribbles = 100_000`; QST-TRIBBLES)
- **ACH-059** {M10} [M][W][P] `marieCeleste` "Ghost Ship": `marieCelesteFound` (an encounter of type `marieCeleste` began). Flag. (source: PRD §6.6 "Finding the Marie Celeste")
- **ACH-060** {M10} [M][W][P] `famousCaptains` "Star-Struck": all three of `famousCaptainsMet` (Ahab, Conrad, Huie). Threshold 3. (source: PRD §6.6 "meeting all three famous captains")
- **ACH-061** {M10} [M][W][P] `escapePod` "Escape Artist": `escapePodsUsed ≥ 1`. Flag. (source: PRD §6.6 "Escape-pod survivor")
- **ACH-062** {M10} [M][W] `designer` "Shipwright": `customShipsBuilt ≥ 1`. Flag; available only with `content.hasShipyards`. (source: PRD §6.6 "building a designer ship")
- **ACH-063** {M10} [M][W][P] `ironman` "Iron Will": `ironman` and the game ended `retired`, `boughtMoon` or `boughtMoonGirl` (death does not finish it). Flag. (source: PRD §6.6 "Finishing an Ironman game")
- **ACH-064** {M10} [M][W][P] `bountyHunter` "Bounty Hunter": `bountiesCollected ≥ 10`. Threshold 10. (source: addition; CMB bounty rules)
- **ACH-065** {M10} [M][W][P] `bigScore` "Big Score": `bestSale.profit ≥ 10 000`. Threshold 10 000 (progress = best sale profit, clamped at 0). (source: addition; UX-VISION §1.3)

## 7. Identifier catalog (extend, never rename)

| Area | Identifiers |
|---|---|
| Achievements | `logbook.achievements`, `logbook.achievements.badge.<AchievementID>`, `logbook.achievements.disabled`, `logbook.achievements.unavailable` |
| Settings | `settings.resetAchievements` |

## 8. Types proposed by this spec

- ParsecInsights: `AchievementID`, `AchievementDefinition`, `AchievementKind`, `AchievementCatalog` (`definition`, `evaluate`, `satisfied`), `AchievementProgress`.
- ParsecPersistence: `AchievementStore(root:clock:)`, `AchievementRecord`.
- App: `AchievementService` (implements `SessionAchievements`), `AchievementsView`, `AchievementText` (names and descriptions), `FeedNote.achievementUnlocked`, `AppConfirmation.resetAchievements`.

## 9. Notes

- **Deviation from the suggested set:** "reaching 1M tribbles" becomes the reachable cap of 100 000 (ACH-058). "Clean→Hero" is "reach Hero", since every game starts Clean (ACH-049). Two additions (ACH-064, ACH-065) bring the total to 36; every ruleset has at least 30 available.
- **Quest completion = the reward step.** Each chain counts on the `specialEventCompleted` of its final reward or resolution event (dragonflyShield, spaceMonsterKilled, scarabUpgradeHull, japoriDelivery, jarekGetsOut, wildGetsOut, reactorLaser, gemulonFuel, experimentStopped, artifactDelivery, sculptureHiddenBays, princessQuantum), never on a status code. That way failure paths that also reach "done" codes (a reactor lost in the escape pod, an artifact lost) never count.
- **Reloads do not disable achievements.** Only cheats do (PRD §8.3). A reload rewinds the journal; the app-wide store keeps what was unlocked.
- **Cross-spec follow-ups:** UI-SHELL-101's Reset Achievements is ACH-021; CHEAT-004 is implemented by ACH-008 (tests should cite both).
