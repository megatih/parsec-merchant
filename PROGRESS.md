# PROGRESS: Parsec Merchant

> The autonomous agent reads this first and updates it after every step. Keep it short and current.

## Status
- **Current milestone:** M18 done; working on M19 (release 2.0, `docs/PRD-UI-Revamp.md`). The first number is the last finished milestone (spec-trace reads it).
- **Next step:** M19 portrait proof of concept: `PA/Portraits/` (genome, layers, renderer), ART-FACE-001…008 tests, `pmart sheet --page portraits`, two reviews, ADR 0005.
- **Last gate result:** 2026-11-19: M18 exit: `verify.sh` ALL GATES PASSED (incl. 7c-protected, 7d-logic-frozen); `protected-check.sh` PROTECTED OK (22 files); `logic-frozen.sh` LOGIC FROZEN OK.
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
- [x] M13 Final QA and GitHub release v1.0.0 (2026-11-18, tag m13-done; v1.0.0 published with zip + .sha256; verify --ui green; QA-REPORT all ✓ incl. owner hand checks; idle CPU 4.4%; final-check.sh)
- [x] M14 Planets and space (2026-11-18, tag m14-done; 10 planet classes baked from seeded noise and sphere-projected, live Metal Bridge planet at 30 fps (ADR-0004), hero stage with star glow, cached map sprites; ART-068…080; idle CPU 2.6%)
- [x] M15 Ships, sizing, endings and icon (2026-11-19, tag m15-done; stat-driven hull generator with archetypes and specials, no insect anatomy, D7 layout in every panel, lit ending scenes on a 16:9 card, icon hauler = generated freighter; verify --ui green in the mirror on d355f44, make-icon --check OK, idle CPU 3.2%/3.0%; QA-REPORT M15 visual review row)
- [x] M16 Pointer and touch first (2026-11-19, tag m16-done; UI-POINTER spec, 36 pt targets with unchanged density (PointerButtonStyle, pointerTarget), hover feedback, Market chips with Buy/Sell and a row that fits the default window, Shipyard Compare toggle and double-click, Outfitter drag and drop with a sell well, pinned map selection card, wheel zoom, context menus, sheet quantity chips; PointerTargetUITests and PointerOnlyScenarioUITests; verify --ui green in the mirror on d355f44; QA-REPORT M16 review and touch-checklist rows, hands-on touch part is owner hand check (h))
- [x] M17 Polish and release 1.1.0 (2026-11-19, tags m17-done and v1.1.0; README and QA screenshots re-exported and read, Help/README/CHANGELOG/CREDITS updated, QA-REPORT 1.1 rows, pmsim bench OK, bench-map 0.253 ms, idle CPU 3.2%/3.0%, release.sh PASS, clean-clone build, GitHub release v1.1.0, final-check.sh)
- [x] M18 Setup, freezes and baselines (release 2.0) (2026-11-19, tag m18-done; baselines: fuzz 4531100 / 4528609 / 3134221 commands, galaxy seed-1 hashes ff4fb0e3… / c04d544a… / 8f2dead9…, planet digests pinned in PlanetFrozenTests and PlanetInputFrozenTests)
- [ ] M19 Portrait proof of concept
- [ ] M20 Ships and liveries
- [ ] M21 Design system and shell
- [ ] M22 Bridge
- [ ] M23 Secondary pages
- [ ] M24 Charts
- [ ] M25 Encounter, transit, interruptions
- [ ] M26 Endings, welcome, new game, game over, icon
- [ ] M27 Keyboard, menus, accessibility, words, help
- [ ] M28 Release 2.0.0

## M18 checklist
- [x] PRD, audit and research committed
- [x] protected-check.sh, logic-frozen.sh, verify steps 7c/7d
- [x] spec-trace threshold 28; final-check/release/marketing version 2.0.0, 29 milestones, 10 checks
- [x] New spec files (123 IDs) from the PRD
- [x] Baselines measured and written into logic-frozen.sh
- [x] PlanetFrozenTests (PROT-003), PROT-001/002 tests
- [x] CLAUDE.md
- [x] Exit: verify.sh, protected-check, logic-frozen

## M14 checklist
- [x] Setup: PRD-1.1 committed, D10 spec-trace threshold 17 + PM_TRACE_MILESTONE, final-check/release/marketing version 1.1.0, PRD.md/CLAUDE.md folded
- [x] Spike: Metal layer idle CPU; CGImage-in-Canvas determinism (ADR-0004: Metal 30 fps ≈ +0.3% CPU, go; mini chart vortices still)
- [x] Specs: ART.md rewrites + new IDs from ART-068; UI-SHELL-054; MAP-095
- [x] Tests rewritten/added (PlanetSpaceTests, ArtCoreTests budgets, ArtEffectsTests, Metal parity)
- [x] ParsecArt: PlanetNoise, PlanetClass, PlanetTextureBaker, PlanetSphere, recipe/art rewrite, StarGlow
- [x] App: PlanetMetalView + shader, PlanetPortrait, Bridge hero, map sprites
- [x] pmart planet sheet; look review; QA-REPORT row
- [x] Exit: verify --ui, bench-map ≤ 8 ms, idle-cpu ≤ 5%, largest-text + pseudo-loc review at 1100×720, tag m14-done

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
- 2026-11-19: Release 2.0 (M18). The status line's first number is the last finished milestone (spec-trace due rule). The planet digests in PlanetFrozenTests were stable over three runs on this machine; they hash CPU-projected pixels, so a toolchain or OS change that alters floating-point output would show there first: compare against a checkout of 296ad2c before suspecting the code. Do not edit verify.sh while a verify run is in flight (bash reads the script as it runs).
- 2026-11-19: test and gate audit against 1.0 (`git diff m13-done HEAD` over the test folders and `scripts/`). Every changed or removed check is a rewrite PRD-1.1 names: `spec-trace.sh` threshold 13 → 17 and `PM_TRACE_MILESTONE` (D10, M14 step 1); ART-006 budgets, ART-021…026/029/052 planet tests (M14); the insect-motif assertions of ART-008…012 and the rebuilt endings (M15); MAP-020 hit radii, the Galaxy tip text, the Market identifier list (M16). No pre-existing threshold was lowered. The new M16 source audit is back to its first, strict form: the small-control allowlist holds only the route panel's progress spinner, and the hover audit exempts no file. To get there the route panel's objective and Clear buttons use regular bezels again (the panel's vertical padding went from 10 to 6 pt so it still fits at the largest Text Size), and the 36 pt target of `PointerButtonStyle` (an `.onTapGesture`) carries `hoverHighlight` itself: a push button tints on hover, the tint the size and shape of its bezel (checked on a screenshot of a hovered button). These two small UI changes landed after the v1.1.0 release was built, so `main` is ahead of the released app by them; tag and release were not rewritten.
- 2026-11-19: tag `m16-done` sits on b7d0fa1, where `spec-trace.sh` reported UI-PTR-020 untraced (found right after tagging). The next commit adds the trace (a `covers:` comment on the two M12 keyboard tests; no behaviour change) and `verify.sh` passes there. The tag was not moved: rewriting a pushed tag needs the owner's say-so.
- 2026-11-19: M16 push buttons: `PointerButtonStyle` (set on every scene root in `SceneAccessibility` and on each sheet root) keeps the system bezel and layout height and makes a centred 36 pt overlay the pressed and measured element (accessibilityRepresentation of the same button). Custom controls use `pointerTarget()` in their labels. Toggle-style buttons and other standard controls are exempt by element type in PointerTargetUITests, as are the system confirmation dialog's buttons (`appConfirmation.*`).
- 2026-11-19: Market chips live in an `@Observable` `TradeChipStore`; a plain `@State` dictionary did not redraw table cells. The pinned map card closes on a warp, not on every state change (its own commands change the state).
- 2026-11-18: Gates run in a mirror. The Debug and Release apps share the bundle id `io.github.megatih.ParsecMerchant` (the JSON project's `[config=Debug]` override is not applied), both are ad-hoc signed, and macOS re-asks for Documents access for the test host; the mirror at `~/Library/Caches/ParsecMerchantMirror` (not under /tmp: the `/tmp` symlink breaks the source audits' relative paths) avoids the prompt. Script: session scratchpad `mirror-run.sh` = rsync (excluding build, .build, dist, .claude) then run the command there.
- 2026-11-18: M16 SDK check: `NSIsTouchNative` and `directTouchSystemGesturesDisabled` are not in the macOS 27.2 SDK (headers and swiftinterface searched); standard gestures only (UI-PTR-016).
- 2026-11-18: M15: haulers with 55+ bays are spine freighters (containers outside a narrow spine), a stat rule that also keeps Beetle and Termite apart (ART-013 worst pair now gnat/scorpion 0.83). Larger size classes get a relatively narrower beam. A `cinema` planet LOD (1024×512) serves the endings' limb views. Ship edges use a fixed dark edge instead of the light dark-mode outline token.
- 2026-11-18: M16 Market row: chips + Sell + qty field + Buy + disposal button; the separate Max/All buttons are gone (chip Max then Buy/Sell is the same two clicks; ⇧B/⇧S and the accessibility actions remain).
- 2026-11-18: ParsecArt is compiled with -O in Debug too (Package.swift `artOptimised`): unoptimised per-pixel baking/projection is 20–30× slower (hero bake 136–220 ms vs 9 ms) and would stall the Debug app and UI tests. Budgets and debugFactor unchanged.
- 2026-11-18: SourceAuditTests UI-KEYS-035 forbids `Image(decorative` in app code, so the map's sprite draw lives in ParsecArt (`PlanetRenderer.drawSprite`).
- 2026-11-18: ADR-0004. Spike: idle floor 0.2–0.4%; the map's 5 fps vortex TimelineView alone costs ~4.5% (whole-window pass). The spike's Metal figure (~0.3%) was invalid (its shader did not compile, found by the ART-074 parity test); the working Metal planet at 30 fps measures 2.3–2.5% total idle. Decision: D2 rung 1 (Metal, 30 fps); the Bridge mini chart draws vortices still, the Galaxy section keeps AmbientSchedule and pauses it when no wormhole is in view. Idle-CPU readings are noisy while the App Store daemon is installing updates; re-measure on a quiet machine.
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
- 2026-11-18: M14 exit. Note for M17: the README Bridge screenshot is scrolled because the test clicks Target Next, which now sits lower on the taller page; fix the test's scroll position when re-exporting.
- 2026-11-18: M14 planets built: PlanetNoise/PlanetClass/PlanetTextureBaker/PlanetSphere/PlanetCache in ParsecArt (10 classes, rings, CPU projector), PlanetMetalView + shader string (GPU/CPU mean abs diff ≤ 0.011/255), PlanetHero stage with StarGlow, cached map sprites, mini chart vortices still. ART-068…080 traced.
- 2026-11-18: 1.1 work started (docs/PRD-1.1.md, M14–M17). Setup: spec-trace threshold 13 → 17 with PM_TRACE_MILESTONE preview; final-check/release retargeted to v1.1.0 and 18 milestones; marketing version 1.1.0.
- 2026-11-18: A11Y-027/042 screenshot review and fixes (sidebar, wizard header/footer, Market columns, Shipyard strip, Galaxy HUD layout, crew header/skills, Settings/Options buttons, feed overlay); the RTL pseudo run passes -AppleTextDirection YES and now mirrors; the galaxy map stays left to right. QA and README screenshots re-exported. Notes in A11Y.md §12a.
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
