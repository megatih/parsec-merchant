# PROGRESS: Parsec Merchant

> The autonomous agent reads this first and updates it after every step. Keep it short and current.

## Status
- **Current milestone:** M13 (starting)
- **Next step:** M13: run scripts/release.sh (Release ad-hoc build + smoke + zip); export README/QA screenshots (scripts/export-screenshots.sh, then --qa); fill the remaining QA rows (Accessibility audit, Text Size, Pseudo-localization, Light and dark, Smallest window, Credits visible, Release smoke test, Clean-clone build) and resolve the 'partly/pending' manual rows; verify --ui; tag m13-done, push; gh release create v1.0.0 (release.sh --publish); final-check.sh.
- **Last gate result:** verify.sh --ui ALL GATES PASSED @ 28d1404 (M12 exit, 9/9 incl. 41 UI tests); pmsim bench --check OK
- **Blockers:** none

## Milestones
- [x] M0 Tooling, project setup, specs, Palm source, GitHub repo (2026-11-17, tag m0-done)
- [x] M1 RNGs, tables, galaxy generation (2026-11-17, tag m1-done; RNG bit-exact vs .NET, galaxy bit-exact vs C# harness on 21 snapshots, invariants on 1000 seeds × 2 rulesets)
- [x] M2 Economy and services (2026-11-17, tag m2-done; 146 tests; engine coverage 94.2%; market evolution bit-exact vs harness; designer)
- [x] M3 Travel, encounters, combat, police, news (2026-11-17, tag m3-done; opponents/combat/journeys/actions/newspaper bit-exact vs C# harness; fuzz 6000 games 0 violations; 382+ tests)
- [x] M4 Quests, endings, scoring (2026-11-17, tag m4-done; 46 special events bit-exact vs C# harness; QST scenario tests per chain incl. failures; SCORE; tribble/passenger notices)
- [x] M5 Rulesets (Palm 1.2.2 and Modern) (2026-11-17, tag m5-done; Palm content pack + galaxy, all RUL flags in per-area rule groups, MOD-001…021, no open [verify] (accepted assumptions in QA-REPORT), 1546 spec IDs)
- [x] M6 Persistence, high scores, cheats (2026-11-17, tag m6-done; SAV/SCORE/CHEAT/OPT traced; 500 fuzzed byte-identical round trips; v1 fixtures per ruleset)
- [x] M7 App shell and docked screens (2026-11-17, tag m7-done; GameSession, Welcome/wizard, Bridge/Market/Shipyard+Designer/Outfitter/Crew/Bank/Quests, menus, files, Settings/Options, About/Help, App Intents, cheat console; UI flows 1/3/4 + identifier walk green)
- [x] M8 Galaxy chart (2026-11-17, tag m8-done; Canvas map, hover cards, range ring, wormholes, route planner (ParsecInsights) + follower, search, detachable window, mini chart, VoiceOver children + rotors; flow 5 green; pmsim bench real)
- [x] M9 Encounter, transit, event UX (2026-11-17, tag m9-done; encounter view + combat log + auto-repeat + tactical readout, transit + Dock progress, arrival report, feed, styled newspaper, special-event narratives, game over + career card, high scores window, every PendingDecision/ALR presentation covered by a test; flow 2 green)
- [x] M10 Trade intelligence, log, stats, achievements, flavor (2026-11-17, tag m10-done; journal beside state (ADR-0003), trade intel (fair), Logbook ⌘9, 36 achievements, career stats, template + Foundation Models flavor with -PMFlavor template)
- [x] M11 Art, icon, audio, haptics (2026-11-17, tag m11-done; ParsecArt (17 ships, planets, glyphs, effects, scenes) + Liquid Glass .icon via make-icon.sh (actool clean, step 7b); ParsecAudio synth (allocation-free render), 30 cues with visual twins, music off by default, haptics, Sound settings)
- [x] M12 Polish, accessibility, localization, screenshots (2026-11-17, tag m12-done; UI-KEYS binding table + conflict audit + Esc router, A11Y (VoiceOver model, rotors, display settings, Text Size fallback, TipKit), flows 6/7 green, localization (2,221 keys, l10n-check in step 4, pseudo-localization), combat timing unified, AUD-049 release budget)
- [ ] M13 Final QA and GitHub release v1.0.0

## M0 checklist
- [x] .gitignore before first push
- [x] §6.3 ladder: rename settings, Swift 6, deployment 27.0, package linked via JSON (ADR-0001), APP-001 test passes
- [x] Package skeleton (Engine, Persistence, Insights, Art, Audio, pmsim + 6 test targets)
- [x] Gate scripts: verify, coverage-gate, spec-trace, warnings-gate, license-check, lib-milestone
- [x] LICENSE, CREDITS.md, .swiftlint.yml
- [x] Palm source fetched (gitignored, sha recorded); MOD-017 swap re-confirmed (DataTypes.h SHIPTYPE order; Global.c Gnat CostOfFuel 2 / RepairCosts 1 vs C# fuelCost 1 / repairCost 2)
- [x] Apple skills exported to .claude/skills (11 skills; must use an absolute --output-dir)
- [x] GitHub repo megatih/parsec-merchant created (public) and pushed
- [x] docs/reference/csharp-index.md (540 entries)
- [x] docs/specs skeletons; ECO (83), SHP (85), CRW (69), BNK (63), ALR (188) written; RNG (41), GAL (72) written
- [x] ALR.md; RUL.md (139 IDs, 102 flags, 34 bug dispositions)
- [x] final-check.sh (full), release/make-icon stubs, harness.sh (working; .NET 10 via dotnet-install.sh into build/harness/dotnet — brew cask needs sudo)
- [x] M0 exit: verify.sh ALL GATES PASSED, tag m0-done, push

## Accepted assumptions and decisions log
- 2026-11-17: Encounter API decisions: auto-repeat = .encounter(.autoRepeat), interrupt = .encounter(.stop), .encounter(.resolve) = attack + forceContinuous; rounds emit combatRound (no shotFired); stance changes emit encounterChanged; no encounterEnded event; nothing-illegal prompts are submitWithNothingIllegal (attack/bribe) and fleeInspection (flee); takeMarieCargo removed. Specs aligned to these names.
- 2026-11-17: coverage-gate.sh merges all profraws and exports across every per-target .xctest (SwiftPM's codecov JSON covers only one bundle in Swift 6.4). Thresholds unchanged.
- 2026-11-17: ALR.md {M2} Swift names aligned to the implemented ECO/SHP/BNK/CRW vocabulary.
- 2026-11-17: Lint thresholds are gates: never relax them; wrap long lines instead (auto-mode classifier correctly blocked a relaxation).
- 2026-11-17: RUL.md [verify] items accepted for now: designer cost columns keep C# (Modern); Palm SysRandom stand-in; escape-pod Scarab status kept (RUL-099).
- 2026-11-16: Harness: .NET SDK installed with dotnet-install.sh into gitignored build/harness/dotnet (Homebrew cask is a sudo .pkg).
- 2026-11-16: Ahead of plan (M1 work done during M0): RNGs bit-exact vs .NET; galaxy/crew/start/prices bit-exact vs harness for 15 snapshots.
- 2026-11-16: Ruleset is a struct (tables/flags/content/rngKind) rather than a protocol; same capability as PRD §4.1.
- 2026-11-16: LSApplicationCategoryType = public.app-category.simulation-games (a Games sub-category).
- 2026-11-16: Test bundles access the engine via `@testable import ParsecMerchant`, not by linking package products, to avoid duplicate static linking (ADR-0001).
- 2026-11-16: Planning complete. Decisions D1–D5 are in PRD §2. The research dossiers are in `docs/research/`.

## Session log (newest first)
- 2026-11-17: M11 exit. Notes: ImageRenderer.cgImage is not byte-deterministic — art tests/pmart render into a fixed RGBA sRGB CGContext; pmart icon works from the command line (no PM_ICON_OUT fallback needed). Open QA rows needing the owner at M13: AUD-052 (2-min listening + device switch), ART screenshot rows. Audio CombatTracker duplicates CombatEffectPlanner timing (unify in M12).
- 2026-11-17: M10 exit: INT/LOG/STAT/ACH/LLM (197 IDs). ADR-0003 journal saved beside state. ART/AUD specs for M11 written ahead. Insights coverage 99%. UI suite now launches with -PMFlavor template.
- 2026-11-17: M9 exit: UI-ENC (106 IDs) built by 5 worktree agents; pirateAmbush scenario seed 292 → target 46, 6 attacks; flows found 2 bugs (no report after loading mid-encounter; unidentified Bridge sliders). Duplicate auto Window-menu items removed with .commandsRemoved().
- 2026-11-17: M8 exit: MAP.md (104 IDs), route planner (lexicographic Dijkstra, verified vs brute force), app galaxy chart + flow 5. pmsim bench implemented (perform 0.0005 ms, arrival 0.04 ms, route 0.03 ms medians). Map render baseline 0.41 ms/frame (budget 8 ms). Deviation: flow 5 uses seed 13 (seed 11 meets police on the nearest warp).
- 2026-11-17: M7 exit: app built by six worktree agents (foundation, engine UI queries, four section/area agents) + UI-flow agent. Flows found two real bugs: AppKit opened a leftover launch argument as a document (fixed with NSTreatUnknownArgumentsAsOpen=NO) and container accessibilityIdentifiers overwrote children (fixed with .accessibilityElement(children: .contain)). NEWS-047 retagged M9 (styled newspaper). Interim encounter/game-over surfaces remain until M9.
- 2026-11-17: M6 exit: persistence rewrite (gameID/generation, backup recovery, validation, versioned high scores, loadForPlay reload rule, import clears Ironman), cheats (all C# Find codes + Palm codes/cheat form, cheatsUsed permanent), options (docked-only, normalized, Palm defaults). M7 specs UI-SHELL (129) + MENU (45) written. Decisions: galaxy code includes difficulty (generator needs it); interim encounter/game-over surfaces in M7 replaced in M9.
- 2026-11-17: M6 started: ParsecPersistence SaveEnvelope/SaveCodec (sorted-key JSON, byte-identical round trips)/SaveMigrator (raw JSON, v1)/SlotStore (atomic, 3 rotating backups, autosave, import/export, Corrupt/ quarantine)/HighScoreStore; engine HighScoreTable (top 10, SCORE-031…036).
- 2026-11-17: M5 exit: cross-area finish (Palm passengers outside the crew array, Palm Gemulon `> 7` rule, duplicate economy flags removed). Fuzz cash invariant now checks negative-cash transitions (allowed only for ECO-068 C# orbit cap and RUL-043 Palm dump precedence bug) — stricter than before (Windows now checked).
- 2026-11-17: M5: five area branches merged (Palm content pack + galaxy; economy; travel/news/score; encounters/combat/police; quests). Deduplicated flags (one per behaviour: moon-girl → quest, record decay → travel, Wild laser/quest-ship damage → quest); Palm arrest/pod run Arrival() once (meltdown twice); 971 tests; fuzz clean on all rulesets; 1530 spec IDs (≥400 ✓). MOD-n cited as RUL-1nn in tests.
- 2026-11-17: M5 started: 411 {M5} IDs (137 RUL). Added per-area rule groups (GalaxyRules, EconomyRules, TravelRules, EncounterRules, QuestRules) under RuleFlags so parallel agents never edit the same struct.
- 2026-11-17: M4 exit: 15 QST chain specs + index (304 IDs) and SCORE (41); four worktree agents traced all {M4} IDs with multi-step chain scenarios; engine additions: passengerConcerned/Impatient, tribblesDied/AteFood/InspectorWarning notices, retire docked-only. Decision: arrest/pod quest losses are derived by the app from state (no separate events). POL-085 retagged M5.
- 2026-11-17: M4 started: Command.specialEvent ports ShowSpecialButton + HandleSpecialEvent for all 46 events, bit-exact vs C# quest harness (46 events × 4 ship setups × 2 seeds); retire; C# score formula with Int32 wrap; gameEnded(type, score:) on every ending. SCORE.md written (top 10 per ruleset per PRD §6.4).
- 2026-11-17: M3 exit: five worktree agents traced all {M3} IDs (ENC, CMB, POL, TRV/NEWS, ALR/BNK/CRW); engine fixes found by tracing: Int32 arrest-fine wrap, Windows hidden-bay raid abort (+Modern clamp flag), quest-ship damage persists, stop while auto-repeating, Marie Celeste narcotics comparison, tribble sprite draws, initial oppFleeing, playerCloaked only for cloak-caused ignores, singularity consent/loss, selectWormhole/selectNextTarget, previews. Single arrested/escapePodUsed events (app derives report sections from state). Retags: ENC-188→M9, BNK-026/048 & CRW-048→M5.
- 2026-11-17: M3: encounter actions + Arrested bit-exact vs C# action harness; newspaper bit-exact (225 arrivals); real pmsim fuzz (2000 games × 3 rulesets, invariants, replay every 50th game, 0 violations); ENC/CMB/POL/TRV/NEWS specs written; action availability table, autoRepeat/resolve, encounter preview. 397 {M3} IDs were untraced; tracing delegated to five worktree agents.
- 2026-11-17: M3 progress: opponent generation (216 cases), combat rounds (162 fights/1834 rounds), journeys (225 warps/1415 encounters/arrival pipeline) all bit-exact vs C# harness. Harness commands: rng galaxy market opponents combat travel.
- 2026-11-17: M2 economy/services implemented (Market.swift, Services.swift) with 30 ID-named tests; RNG vectors (all generators) + galaxy invariants 1000 seeds pass; harness has 21 galaxy snapshots; pmsim dump-galaxy.
- 2026-11-16: M0 setup done (ladder step 2 succeeded), gates green, repo published.
- 2026-11-16: Docs created: PRD v1.1, UX vision, research 01–06 (with QA errata), QA logs 07–08, CLAUDE.md, GOAL.md. Owner approved D6 (dotnet differential harness).
