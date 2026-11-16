# QA: Independent Review of the PRD Package

> Independent review 2026-11-16 of PRD v1.0, UX-VISION, CLAUDE.md and GOAL.md. All Critical and Major findings are resolved in PRD v1.1, UX-VISION, CLAUDE.md and GOAL.md (owner decision: differential harness allowed, D6). GameController support was deferred out of v1.

---

## Plan review: Parsec Merchant (GOAL.md, CLAUDE.md, PROGRESS.md, docs/PRD.md, docs/design/UX-VISION.md, research 01–06)

I edited nothing. All my experiments ran in copies inside the scratchpad, and I deleted them afterwards except `goal.txt`.

**What I checked locally:**
- **Toolchain:** Xcode 27.2, Swift 6.4.2, xcodegen 2.46.0, swiftlint 0.65.1, gh 2.x logged in. `xcprojformatter` and `mcpbridge run-agent skills export --output-dir` both exist.
- **Template build:** the template builds and tests headlessly. It is signed with "Apple Development … (W23HRVT3KD)", team FVX2F2KV5M, and took about 13 s.
- **SwiftPM in Swift 6.4:** `.treatAllWarnings(as: .error)` works, and `swift test --enable-code-coverage` writes `.build/debug/codecov/ParsecKit.json`.

---

### CRITICAL (each of these will stall the run or prevent "done")

**C1. `warnings-gate.sh` fails from day one, whatever the code does.**
- A clean template build already prints 3–4 lines like `appintentsmetadataprocessor … warning: Metadata extraction skipped, no AppIntents.framework dependency found`.
- So "zero `warning:` lines" can never pass, and the agent will be tempted to weaken the gate.
- **Fix:** count only compiler and linker diagnostics. Either:
  - grep `-E '^/.+:[0-9]+:[0-9]+: warning:|^ld: warning:'`, or
  - pass `-resultBundlePath build/results/app.xcresult` and count warnings with `xcrun xcresulttool get build-results --path …`.
- Also write the exclusion of `appintentsmetadataprocessor` into the PRD, so it isn't the agent's call. Adding a real App Intent ("Continue game") would also silence it.

**C2. `spec-trace` makes the M0 exit impossible.**
- M0 requires ≥400 spec IDs *and* "verify.sh passes", but spec-trace fails on any untagged ID that has no test, and M0 has no engine tests.
- **Fix:** give every requirement a milestone tag such as `{M3}`. spec-trace then enforces only IDs whose milestone is ≤ the current one (read from PROGRESS.md), and at M13 it requires zero deferred IDs.

**C3. The coverage gate contradicts the milestones and can't pass early.**
- §8.1 always requires Engine ≥90%, but the M2 exit says ≥85%.
- At M0 and M1, the Persistence and Insights targets are empty (0/0 lines gives NaN or 0%), so they fail.
- **Fix:** put a fixed ramp in PRD §8 so it doesn't count as "weakening":

  | Module | Not enforced | Enforced |
  |---|---|---|
  | Engine | until M1 | ≥85% from M2, ≥90% from M3 |
  | Persistence | until M5 | ≥85% from M6 |
  | Insights | until M9 | ≥85% from M10 |

- Implement the gate by parsing `$(swift test --show-codecov-path)` and summing `files[].summary.lines` where the filename contains `/Sources/ParsecEngine/`.
- Don't hard-code `ParsecKitPackageTests.xctest`. Swift 6.4 builds one `.xctest` per test target (verified), so that path no longer exists.

**C4. M8 needs UI tests but the gate never runs them there.**
- The M8 exit requires "UI flow 5 green", but GOAL.md and PRD §8.1 run `--ui` only at M7, M9, M12 and M13.
- **Fix:** add M8 to both lists, or make the GOAL say "wherever PRD §8.1 requires it" and list M8 in the PRD.

**C5. The completion evaluator may lose evidence to context compaction.**
- Clauses (a)–(f) are likely to come from different turns hours apart. After compaction, early outputs such as `gh release view` vanish from the transcript, and the evaluator can't re-run anything.
- (a)'s "exit code 0" is invisible unless printed. (d) and (e) can be satisfied by the agent's own paraphrase.
- **Fix:**
  - Commit `scripts/final-check.sh` (written in M13), which runs all checks and prints one PASS/FAIL line each.
  - Require one turn to show its raw output, ending with a sentinel line and `EXIT=0`.
  - A proposed condition is below.

**C6. `git status` can never be clean (clause f), and the license check fails on its own files.**
- The `.gitignore` list in PRD §9/M0 misses:
  - `Packages/ParsecKit/.build/`
  - `.swiftpm/`
  - `dist/` (the release zip)
  - `*.xcresult`
  - `.claude/skills/`
  - `docs/reference/palm-src/`
- M12 has a UI test write `docs/screenshots/`. If that runs inside `verify.sh --ui`, the PNGs are regenerated with different bytes after the final commit.
- The Palm `Rsc/` folder fetched into `docs/reference/palm-src/` contains original bitmaps:
  - `license-check.sh` will hash-match them against themselves and fail.
  - Committing them would publish copyrighted art in the public repo.
- **Fix:**
  - gitignore `docs/reference/palm-src/` and commit only a fetch script with a SHA-256.
  - Have `license-check` exclude that path. Also hash `SpaceTraderSource201/App.ico`, which sits outside `images/`.
  - Export screenshots only when `PM_EXPORT_SCREENSHOTS=1`, using `xcrun xcresulttool export attachments --path … --output-path docs/screenshots` (verified to exist), never inside verify.
  - verify.sh may write only under `build/`.
  - Don't commit the Apple skills. They are Apple content and shouldn't go into a GPL repo.

**C7. Linking the package into the JSON project: half-verified, and the planned validator doesn't validate.**
- I tested in a copy:
  - A top-level `"packages": [ { "kind": "local", "path": "Packages/ParsecKit" } ]` is accepted.
  - `xcodebuild -list -json` then shows a `ParsecEngine` scheme.
  - However, the product-to-target link key wasn't found. Guesses like `{package, product}` in a frameworks phase were silently dropped by `xcprojformatter` with no error.
- So "validate with xcprojformatter" and "M0 exit: `-list -json` shows the package link" both give false positives.
- **Fix:**
  - The M0 exit should be a test in SpaceTraderMacTests that calls a `ParsecEngine` symbol and passes.
  - Best of all, add a pre-flight step for the owner (30 s in Xcode): File › Add Package Dependencies › Add Local, link ParsecEngine to the app, commit. The JSON then shows the canonical syntax for adding the other products (ParsecPersistence, ParsecInsights, ParsecArt).
  - Also: in xcodegen `project.yml` the syntax is `packages: ParsecKit: {path: Packages/ParsecKit}`. `XCLocalSwiftPackageReference` is a pbxproj object name, not yml.

**C8. Blockers lead to loops or an "impossible" verdict.**
- A turn that ends asking for UI-automation permission gets judged "not met", re-prompted, and burns turns. It may also be judged "impossible".
- **Fix:**
  - Add pre-flight owner steps before `/goal`:
    1. `gh auth setup-git`. git has only the Xcode `osxkeychain` helper and no token, so `git push` and `gh repo create --push` may hang.
    2. Run the template UI test once and grant the Accessibility/Automation prompts.
    3. Link the package (C7).
    4. Disable screen lock and run `caffeinate -dimsu`.
    5. Answer the open decisions (Major #1).
  - In the GOAL, say blockers mean "not yet, never impossible" and that the agent should keep doing unblocked work.

---

### MAJOR

**Gaps against the owner's request**

1. **Open decisions left to the agent.**
   - UX §5.5 says the Moon-girl ending is "[PRD decides]", but the PRD doesn't. In fact `GameEndType.BoughtMoonGirl` exists in the C# source but never fires (research 02 §8 #16). Decide per ruleset.
   - Bug dispositions are missing for research 01 §13 #6 (Worth uses list price, no trader discount), #9 (absolute price variance), #14 (Morgan's laser and disruptor damage the Scarab) and #15 (the singularity costs no day, fuel or fees). The MOD list is "closed", so these would silently be kept. Require RUL.md to carry a keep/fix row for all 21 bugs.
2. **Missing UX surfaces:**
   - Retire action: where it lives, confirmation, and score preview.
   - A full menu-bar spec: App / File / Edit (Undo disabled) / View / Game / Encounter / Window / Help. The HIG requires it, and the agent will improvise otherwise.
   - Window and section state restoration.
   - What ⌘W does to the single `Window`.
   - Opening a `.parsecsave` from Finder in a non-document app (needs an `NSApplicationDelegateAdaptor` `application(_:open:)` handler or `handlesExternalEvents`).
   - Ship and commander identity: the UX mock shows a ship name ("Shelby's Folly") that isn't in the game.
3. **QA is too thin and self-certified.** Add:
   - **Accessibility audit:** `try app.performAccessibilityAudit()` in UI flow 6.
   - **Release-build smoke test:** sandbox writes plus a save/load round-trip under Release, because UI tests only exercise Debug.
   - **Clean-clone build:** actually run `git clone` into a temp folder, then `xcodebuild build`, with output shown, as part of final-check.
   - **Pseudo-localization run:** `-AppleLanguages` with a double-length pseudo-locale, for truncation.
   - **Localization completeness:** parse `Localizable.xcstrings` for `"state":"new"` or `stale`, or use `xcodebuild -exportLocalizations`.
   - **Economy sanity:** a greedy-trader `pmsim` bot reaches the moon within N days under every ruleset.
   - **Real tests for `[UI]` IDs:** require each `[UI]` ID to be referenced by an XCUITest or app test, or by a QA-REPORT row with a screenshot. Today they are untested.
4. **Fidelity has no differential oracle.** `dotnet` isn't installed and CLAUDE.md forbids compiling the C# source. Ask the owner now whether a copy outside the repo may be compiled as a headless harness (with WinForms stubs) to produce golden vectors. It's the biggest single fidelity lever. Otherwise, write "hand-computed goldens only" into the PRD as an accepted risk.

**Gates that can't be verified or run as written**

5. **`swiftlint --strict` defaults will explode on tables.** Rules like `line_length`, `file_length`, `type_body_length`, `identifier_name` and `large_tuple` will fire everywhere, and lint will scan `.build/` unless excluded. Give a baseline `.swiftlint.yml` in the PRD:
   - `excluded`: `.build`, `**/.build`, `build`, `docs`
   - opt-in: `force_unwrapping`, `force_try`
   - a custom regex `^import (SwiftUI|AppKit|Combine)` included only for `ParsecEngine/`
   - relaxed length limits for `*Tables*.swift`
6. **The spec ID count is broken.**
   - `grep -c '^\s*- \*\*[A-Z]\+-[0-9]\+\*\*' docs/specs/*.md` prints per-file counts (`file:N`), not a total.
   - It misses `A11Y-001` and `UI-KEYS-001` (verified: 2 of 4 test lines matched).
   - **Fix:** `cat docs/specs/*.md | /usr/bin/grep -cE '^\s*- \*\*[A-Z][A-Z0-9]*(-[A-Z0-9]+)*-[0-9]{3}\*\*'`, and use the same pattern in spec-trace.
   - Note that in the interactive shell `grep` is a ugrep wrapper, so scripts should call `/usr/bin/grep`.
7. **XCTest UI test names can't contain hyphens,** so "tests named by ID" fails for UI tests. Pick a convention, for example `XCTContext.runActivity(named: "UI-007 …")` or a `// covers: UI-007` comment, and make spec-trace scan for it.
8. **"≥400 IDs in M0" invites padding and shallow specs** written before any code. Instead, write the skeleton and full M1–M2 specs in M0, have each later milestone start by finishing its own area spec, and check the ≥400 total at M5.
9. **The fuzz gate is underspecified.**
   - Random-policy games may never end. Cap each game, for example at 3,000 commands or game end.
   - Define the determinism check (replay every 50th game and compare state hashes).
   - Define what `--ruleset all` does before M5.
   - Define the stub behavior in M0–M2.
   - The budget differs: research 06 says 60 s, the PRD 120 s.
10. **Performance gates are flaky as specified.** "Map frame under 4 ms" and "`perform` under 1 ms" would run in Debug builds with coverage instrumentation. Move them to a `pmsim bench` step in release mode (and a release-mode app perf test), with a defined N and a median measured via ContinuousClock.
11. **`swift build -Xswiftc -warnings-as-errors` followed by `swift test` without it rebuilds everything twice.** Use `swiftSettings: [.treatAllWarnings(as: .error)]` in Package.swift (verified to work) and plain `swift build`. Drop `--parallel` from the coverage run; Swift Testing parallelizes by default.
12. **The M11 icon gate is outdated for macOS 26+.** An `.appiconset` that isn't full-bleed gets boxed into a gray "legacy" squircle. Generate a Liquid Glass `.icon` bundle (layered PNGs plus `icon.json`) via `ImageRenderer`, keep the `.appiconset` as a fallback, and mark it [verify].

**Feasibility risks**

13. **Audio under MainActor default isolation can crash.** With `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`, a closure for an `AVAudioSourceNode` render block written in the app target can be inferred as `@MainActor`. Swift 6 runtime isolation checks then trap on the audio thread. **Fix:** move synthesis into a package target (`ParsecAudio`, which is nonisolated by default) with a unit test that calls the render function off the main thread. Keep only engine wiring in the app.
14. **Signing and sandbox containers.**
    - Debug builds (team-signed) and the ad-hoc Release share the bundle id, and therefore the sandbox container. macOS 14+ container protection can then prompt ("…access data from other apps") or refuse access when the ad-hoc copy launches. That endangers clause (e) and users who both build and download.
    - **Fix:** use `PRODUCT_BUNDLE_IDENTIFIER[config=Debug] = io.github.megatih.ParsecMerchant.debug`.
    - Release: build with `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` ("Sign to Run Locally"), so Xcode applies the entitlements correctly with no `get-task-allow`. Avoid `codesign --deep` (there are no nested frameworks; the package links statically).
    - Move `DEVELOPMENT_TEAM` into a gitignored `Config/Local.xcconfig` (included optionally), so a public clone builds without the owner's team ID. This also makes M13's clean-clone check honest.
    - Remove `REGISTER_APP_GROUPS`.
15. **Clause (e) can false-pass.**
    - `open` on an already-running app with the same bundle id just activates it.
    - The locally zipped copy has no quarantine flag, so Gatekeeper is never exercised.
    - **Fix:** `pkill -x`, then `open -n "<tmp>/Parsec Merchant.app"`, then `pgrep -lf "<tmp>"`. Document that a real Gatekeeper prompt can't be automated (ad-hoc apps always fail `spctl`; keep that out of the gates).
    - `pgrep -x "Parsec Merchant"` only works because the name is exactly 15 characters, under the 16-character `MAXCOMLEN` limit; matching by path is safer.
16. **Raise `MACOSX_DEPLOYMENT_TARGET` coverage: 27.2 locks out macOS 27.0 and 27.1 users.** Set 27.0 for both the app and the package; the package's `.macOS("27.0")` is already right.
17. **The GOAL says "run verify.sh every turn".** With UI tests taking over the mouse and keyboard, the owner can't use the Mac during `--ui` runs. Add a `--quick` mode (package build, tests, lint) for intermediate steps and keep the full gate for green commits and milestone exits.
18. **`gh repo create --public --push` at M0 publishes** local paths and the planning docs, and every later commit goes public. That's authorized, but `docs/reference` must already be ignored (C6) before the first push.

**Contradictions between documents**

19. **Apple skills export directory:** research 06 says `.claude/skills-apple`, the PRD says `.claude/skills`.
20. **Audio launch argument:** research 06 says `-PMAudio on`, the PRD and CLAUDE.md say `-PMAudio off`.
21. **AlertType count:** the docs say "~149 AlertTypes", but Enums.cs has 188 cases.
22. **M4 scope:** research 06 says "all 46 types", the PRD says "about fifteen chains". Clarify that it's 46 SpecialEventTypes grouped into about 15 chains.
23. **Skill points:** UX §11 says "20 points, each 1–10". The C# UI gives 16 to distribute (each skill starts at 1, total 20).
24. **Achievement count:** "about 30" in UX vs "≥30" in the PRD.
25. **Inspector shortcut:** UX says ⌥⌘I. The SwiftUI `InspectorCommands` standard is ⌃⌘I; use `InspectorCommands()`.
26. **UX §10 calls itself a "conflict audit in M12"**, but several conflicts are already known (see #27).

---

### UX-VISION: HIG and macOS issues

27. **Shortcut conflicts:**
    - **⇧⌘G** is the standard "Find Previous" (the app has ⌘F), and "Go to Folder" in Finder. Use ⌥⌘G or ⇧⌘M.
    - **⌘0** collides with zoom-reset convention, because the map uses ⌘+/⌘−. Put Fit Galaxy on ⌘0 only while the map has focus, or move Stats.
    - **⌘F** is ambiguous: the Log is also searchable. Define it as "search in the current context", with Galaxy Find as an explicit menu item.
    - **⌘[ / ⌘]** are Back/Forward by convention. That's acceptable, but don't also add navigation history.
    - **Market B/S** collides with `Table` type-to-select, and plain-letter `.keyboardShortcut`s can fire while the quantity field is focused. Scope them with `.onKeyPress` on the focused table, and disable type-select.
    - **⌘-click for ×20** collides with Table and Shipyard multi-select. Apply modifier multipliers only to the +/− buttons and the B/S keys, never to row clicks.
28. **Double-click on the map warps.** That's irreversible and costs fuel and days, so it invites accidents. Make double-click set the target and focus Warp; warp stays ⌘J or the button.
29. **The toolbar is full of status readouts** (Credits, Debt, Day, Bays, Fuel). Under Liquid Glass, toolbar items render as glass capsules that look like buttons. Keep the toolbar to controls (Target picker, Warp, inspector toggle). Put status in a window subtitle (`navigationSubtitle`), a bottom status bar or the inspector header.
30. **Glass and motion details:**
    - "Glass turned off for Reduce Transparency" is automatic for system and `.glassEffect` glass. Don't hand-roll it, just test it.
    - Drop the matched-geometry transition from the map hover card to the Bridge card. It crosses NavigationSplitView detail swaps and is unreliable.
31. **Per-save options don't belong in app Settings.** The HIG treats Settings as app-wide. Put them in Game › Options… (a sheet), and keep Settings to General, Sound, Intelligence and Advanced.
32. **The arrival report sheet still means one modal per warp,** which is the pain point being removed. Default to a non-modal expanding card on Bridge, and use a sheet only when it contains a decision or a critical event (arrest, insurance payoff, pod).
33. **Accessibility gaps:**
    - macOS has no system Dynamic Type, so "large text" QA has nothing to test. Add an in-app Text Size setting (`.dynamicTypeSize`) and test it.
    - Use `accessibilityDifferentiateWithoutColor`.
    - Announce combat rounds via `AccessibilityNotification.Announcement`; there's no live-region modifier on macOS.
    - Give every audio cue (low-hull alarm, siren) a visual twin.
    - Give the Canvas ship portraits in the encounter view accessibility labels.
    - Make Return's default encounter action never destructive (never Attack on police).
34. **Sidebar disabled during encounters:** the ⌘1–⌘0 menu items and the detached Galaxy window's Warp must be disabled too. The spec should say so.

---

### Making it "ultimate" and more fun (cheap, high value)

- **Quick Start** on the Welcome screen: Modern, Normal, balanced skills, one click.
- **Optional Ironman mode,** which fans asked for in research 03: a single autosave and a high-score badge.
- **Seed sharing:** a "Galaxy code" (ruleset plus seed) shown in the game, so friends can race the same galaxy. Add a Daily Seed.
- **Career summary card** at game over, rendered with `ImageRenderer` and shared through `ShareLink`.
- **"Why is this price?" explainer** in the Market row detail (tech level, pressure, resource, record), using only legitimate information. This addresses "hidden mechanics".
- **A tactical readout before fights,** showing only public stats: opponent ship class, weapons and shields if visible, and your flee odds as words rather than numbers. Gate it per ruleset as a QoL option.
- **"Resolve encounter" fast-forward,** alongside auto-repeat.
- **App Intents** ("Continue Parsec Merchant", "Show commander status"). These also fix C1's warning, and make sense on the Spotlight and Shortcuts side.
- **GameController support** for encounter keys and menus.
- **A Dock tile progress bar** during transit.
- **Use real TipKit** rather than "TipKit-style" tips.

---

### Proposed GOAL condition (2,396 characters; saved to `/private/tmp/claude-501/-Users-megatih-Documents-XcodeProjects-SpaceTraderMac/41153429-8b01-41f4-b2f9-1edc30fcbfec/scratchpad/goal.txt`)

```
/goal Build "Parsec Merchant", the native macOS 27 remake of Space Trader, in this repo as specified by docs/PRD.md (normative) and docs/design/UX-VISION.md. CLAUDE.md is project memory; docs/research/01-06 are inputs; /Users/megatih/Downloads/SpaceTraderSource201 is read-only.
Every turn: (1) read PROGRESS.md and continue from "Next step"; (2) work milestones M0→M13 in order (PRD §9), spec-first (IDs in docs/specs, tests named by ID, then code); (3) run scripts/verify.sh (with --ui wherever PRD §8.1 requires it) and paste its PASS/FAIL lines plus "EXIT=<code>"; (4) commit when green; at each milestone exit tag mN-done and push; (5) update PROGRESS.md; (6) end with one line: "Milestone Mx: <done>/<total> steps — gates <PASS|FAIL>".
Hard constraints (PRD §2, §3, §11): three rulesets (Modern default, Windows 2.01, Original Palm 1.2.2); all-new vector art, zero original images; GPL-2.0-or-later headers and credits; Swift 6, zero warnings; no third-party dependencies; no .popover; ParsecEngine pure, deterministic, UI-free; never weaken, skip or delete gates or tests, and never edit a gate's thresholds except as scheduled in PRD §8.
Blockers: if something truly needs the owner (UI-automation permission, package linking after the §6.3 ladder, a paid account), record it under Blockers in PROGRESS.md, print "BLOCKED: <what is needed>", and keep doing any unblocked work. A blocker means "not yet", never "impossible".
Done: the goal is met only when a single turn, after all of M0–M13 are checked, shows the complete unedited output of the committed script scripts/final-check.sh, which prints one PASS/FAIL line for each check below and ends with "FINAL CHECK 6/6 PASS" and "EXIT=0". Evidence from earlier turns, summaries or paraphrases do not count.
1. scripts/verify.sh --ui ends with "ALL GATES PASSED", exit 0, on the current HEAD.
2. PROGRESS.md has all 14 milestones M0–M13 marked [x] and no open blockers.
3. gh release view v1.0.0 --repo megatih/parsec-merchant lists Parsec-Merchant-1.0.0.zip.
4. docs/QA-REPORT.md contains every PRD §10 item, each marked ✓, and no ✗ or TODO.
5. The release zip, downloaded with gh release download into a new temp folder and unzipped with ditto, launches with open -n; pgrep -f finds that exact path; it is then quit.
6. git status --porcelain prints nothing and git rev-parse HEAD equals git rev-parse origin/main.
```

Optionally add "or stop after 600 turns" as a cost bound. Pair this with PRD edits for C1–C4, C6, M8 `--ui` and the coverage and spec-trace schedules, plus a "Pre-flight (owner)" section in GOAL.md:
1. `gh auth setup-git`
2. Grant UI-test permissions
3. Link the package in Xcode
4. Disable screen lock
5. Answer the open decisions: Moon-girl ending, bug dispositions #6/#9/#14/#15, and permission for a dotnet differential harness

