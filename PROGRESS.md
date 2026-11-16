# PROGRESS: Parsec Merchant

> The autonomous agent reads this first and updates it after every step. Keep it short and current.

## Status
- **Current milestone:** M0 (in progress)
- **Next step:** M0 specs: csharp-index.md, ALR.md (188), RUL.md, full RNG/GAL/ECO/SHP/CRW/BNK specs, skeletons for all other areas
- **Last gate result:** verify.sh default: ALL GATES PASSED (7/7) @ f477122
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
- [ ] docs/reference/csharp-index.md
- [ ] docs/specs: skeletons for every area + full RNG, GAL, ECO, SHP, CRW, BNK
- [ ] ALR.md (188 AlertTypes) and RUL.md matrix
- [ ] final-check.sh / release.sh / make-icon.sh / harness.sh stubs
- [ ] M0 exit: verify.sh PASS, tag m0-done, push

## Accepted assumptions and decisions log
- 2026-11-16: LSApplicationCategoryType = public.app-category.simulation-games (a Games sub-category).
- 2026-11-16: Test bundles access the engine via `@testable import ParsecMerchant`, not by linking package products, to avoid duplicate static linking (ADR-0001).
- 2026-11-16: Planning complete. Decisions D1–D5 are in PRD §2. The research dossiers are in `docs/research/`.

## Session log (newest first)
- 2026-11-16: M0 setup done (ladder step 2 succeeded), gates green, repo published.
- 2026-11-16: Docs created: PRD v1.1, UX vision, research 01–06 (with QA errata), QA logs 07–08, CLAUDE.md, GOAL.md. Owner approved D6 (dotnet differential harness).
