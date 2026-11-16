# PROGRESS: Parsec Merchant

> The autonomous agent reads this first and updates it after every step. Keep it short and current.

## Status
- **Current milestone:** M0 (in progress)
- **Next step:** When RUL.md (agent) lands: verify, commit, tag m0-done, set milestone M1, then M1 exit check (RNG/GAL {M1} IDs must all be traced: spec-trace lists missing), then M2: add tests for every {M2} ID in ECO/SHP/CRW/BNK/ALR (spec-trace shows the list) + remaining M2 features (IncDays, preview APIs, special-event price check, price breakdown ECO-082, options OPT).
- **Last gate result:** verify.sh default ALL GATES PASSED @ c21cb4a (50 tests)
- **Blockers:** none

## Milestones
- [ ] M0 Tooling, project setup, specs, Palm source, GitHub repo
- [ ] M1 RNGs, tables, galaxy generation
- [ ] M2 Economy and services
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
- [ ] docs/reference/csharp-index.md (agent running)
- [x] docs/specs skeletons; ECO (83), SHP (85), CRW (69), BNK (63), ALR (188) written; [ ] RNG, GAL (agent running)
- [x] ALR.md; [ ] RUL.md (agent running)
- [x] final-check.sh (full), release/make-icon stubs, harness.sh (working; .NET 10 via dotnet-install.sh into build/harness/dotnet — brew cask needs sudo)
- [ ] M0 exit: verify.sh PASS, tag m0-done, push

## Accepted assumptions and decisions log
- 2026-11-16: Harness: .NET SDK installed with dotnet-install.sh into gitignored build/harness/dotnet (Homebrew cask is a sudo .pkg).
- 2026-11-16: Ahead of plan (M1 work done during M0): RNGs bit-exact vs .NET; galaxy/crew/start/prices bit-exact vs harness for 15 snapshots.
- 2026-11-16: Ruleset is a struct (tables/flags/content/rngKind) rather than a protocol; same capability as PRD §4.1.
- 2026-11-16: LSApplicationCategoryType = public.app-category.simulation-games (a Games sub-category).
- 2026-11-16: Test bundles access the engine via `@testable import ParsecMerchant`, not by linking package products, to avoid duplicate static linking (ADR-0001).
- 2026-11-16: Planning complete. Decisions D1–D5 are in PRD §2. The research dossiers are in `docs/research/`.

## Session log (newest first)
- 2026-11-17: M2 economy/services implemented (Market.swift, Services.swift) with 30 ID-named tests; RNG vectors (all generators) + galaxy invariants 1000 seeds pass; harness has 21 galaxy snapshots; pmsim dump-galaxy.
- 2026-11-16: M0 setup done (ladder step 2 succeeded), gates green, repo published.
- 2026-11-16: Docs created: PRD v1.1, UX vision, research 01–06 (with QA errata), QA logs 07–08, CLAUDE.md, GOAL.md. Owner approved D6 (dotnet differential harness).
