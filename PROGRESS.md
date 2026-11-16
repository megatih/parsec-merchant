# PROGRESS: Parsec Merchant

> The autonomous agent reads this first and updates it after every step. Keep it short and current.

## Status
- **Current milestone:** M3 (in progress)
- **Next step:** M3: merge the five tracing branches (ENC, CMB, POL, TRV+NEWS, ALR/BNK/CRW tests; agents in worktrees), resolve reported engine/spec discrepancies, reach engine coverage ≥90% (83.3% before tracing), then verify.sh default and tag m3-done.
- **Last gate result:** verify.sh --quick ALL GATES PASSED (encounter API commit); default gate pending coverage
- **Blockers:** none

## Milestones
- [x] M0 Tooling, project setup, specs, Palm source, GitHub repo (2026-11-17, tag m0-done)
- [x] M1 RNGs, tables, galaxy generation (2026-11-17, tag m1-done; RNG bit-exact vs .NET, galaxy bit-exact vs C# harness on 21 snapshots, invariants on 1000 seeds × 2 rulesets)
- [x] M2 Economy and services (2026-11-17, tag m2-done; 146 tests; engine coverage 94.2%; market evolution bit-exact vs harness; designer)
- [ ] M3 Travel, encounters, combat, police, news
- [ ] M4 Quests, endings, scoring
- [ ] M5 Rulesets (Palm 1.2.2 and Modern)
- [ ] M6 Persistence, high scores, cheats
- [ ] M7 App shell and docked screens
- [ ] M8 Galaxy chart
- [ ] M9 Encounter, transit, event UX
- [ ] M10 Trade intelligence, log, stats, achievements, flavor
- [ ] M11 Art, icon, audio, haptics
- [ ] M12 Polish, accessibility, localization, screenshots
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
- 2026-11-17: M3: encounter actions + Arrested bit-exact vs C# action harness; newspaper bit-exact (225 arrivals); real pmsim fuzz (2000 games × 3 rulesets, invariants, replay every 50th game, 0 violations); ENC/CMB/POL/TRV/NEWS specs written; action availability table, autoRepeat/resolve, encounter preview. 397 {M3} IDs were untraced; tracing delegated to five worktree agents.
- 2026-11-17: M3 progress: opponent generation (216 cases), combat rounds (162 fights/1834 rounds), journeys (225 warps/1415 encounters/arrival pipeline) all bit-exact vs C# harness. Harness commands: rng galaxy market opponents combat travel.
- 2026-11-17: M2 economy/services implemented (Market.swift, Services.swift) with 30 ID-named tests; RNG vectors (all generators) + galaxy invariants 1000 seeds pass; harness has 21 galaxy snapshots; pmsim dump-galaxy.
- 2026-11-16: M0 setup done (ladder step 2 succeeded), gates green, repo published.
- 2026-11-16: Docs created: PRD v1.1, UX vision, research 01–06 (with QA errata), QA logs 07–08, CLAUDE.md, GOAL.md. Owner approved D6 (dotnet differential harness).
