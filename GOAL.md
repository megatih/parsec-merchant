# Running the build with `/goal`

## A. Pre-flight (owner, about 10 minutes; do this before `/goal`)
1. **Git push auth:** `gh auth setup-git`. Without it, `git push` and `gh repo create --push` can hang.
2. **Allow UI automation once:** build and run the template's UI test, then grant the Accessibility and Automation prompts:
   ```
   xcodebuild -project SpaceTraderMac.xcodeproj -scheme SpaceTraderMac -destination 'platform=macOS' test -only-testing:SpaceTraderMacUITests
   ```
3. **Only if the agent prints `BLOCKED:` about package linking:** in Xcode, choose File › Add Package Dependencies… › Add Local… › `Packages/ParsecKit`, add the `ParsecEngine` product to the SpaceTraderMac target, then reply "done". The agent tries its PRD §6.3 ladder first; it is fully automatic in the best case.
4. **Keep the Mac awake:** turn off screen lock and sleep, and run `caffeinate -dimsu` in a spare terminal. Avoid using the mouse during `--ui` gate runs, which happen at the end of milestones M7, M8, M9, M12 and M13.
5. **Approvals already given:** the agent may run `brew install --cask dotnet-sdk` for the differential harness, create the public repo `megatih/parsec-merchant`, and publish release v1.0.0.

## B. Start
1. In `/Users/megatih/Documents/XcodeProjects/SpaceTraderMac`, run `claude` with model Opus 5.5.
2. Turn on **auto mode** (Shift+Tab). `/goal` doesn't change permissions by itself.
3. Paste the block below as one message (a single line). The condition is about 2,350 characters, under the 4,000-character limit.
4. Use `/goal` to see status and `/goal clear` to stop. `claude --continue` resumes the goal after a restart.
5. Optional cost bound: append ` Or stop after 800 turns.` to the end.

```
/goal Build "Parsec Merchant", the native macOS 27 remake of Space Trader, in this repo as specified by docs/PRD.md (normative) and docs/design/UX-VISION.md. CLAUDE.md is project memory; docs/research/01-06 are inputs (their QA ERRATA blocks override their bodies); /Users/megatih/Downloads/SpaceTraderSource201 is read-only (except the PRD §8.4 harness copy). Every turn: (1) read PROGRESS.md and continue from "Next step"; (2) work milestones M0→M13 in order (PRD §9), spec-first (IDs in docs/specs, tests cite IDs, then code); (3) run scripts/verify.sh in the mode PRD §8.1 requires (--quick between steps, default before commits, --ui at the end of M7, M8, M9, M12 and M13) and paste its PASS/FAIL lines plus "EXIT=<code>"; (4) commit when green; at each milestone exit tag mN-done and push; (5) update PROGRESS.md; (6) end with one line: "Milestone Mx: <done>/<total> steps — gates <PASS|FAIL>". Hard constraints (PRD §2, §3, §11): three rulesets (Modern default, Windows 2.01, Original Palm 1.2.2); all-new vector art and zero original images; GPL-2.0-or-later headers and credits; Swift 6 with zero compiler warnings; no third-party dependencies; no .popover; ParsecEngine pure, deterministic and UI-free; never weaken, skip or delete gates or tests, and never change thresholds except as scheduled in PRD §8; never commit reference sources, Apple skills or build outputs. Blockers: if something truly needs the owner (UI-automation permission, package linking after the §6.3 ladder, a paid account), record it under Blockers in PROGRESS.md, print "BLOCKED: <what is needed>", and keep doing all unblocked work. A blocker means "not yet", never "impossible". Done: the goal is met only when a single turn, after M0–M13 are all checked in PROGRESS.md, shows the complete unedited output of the committed scripts/final-check.sh. That output must have one PASS line for each of its 8 checks (PRD §10: verify --ui ALL GATES PASSED on HEAD; all milestones [x] with no open blockers; gh release v1.0.0 lists Parsec-Merchant-1.0.0.zip; QA-REPORT all ✓; the downloaded release app launches via open -n and pgrep -f finds that path; a clean clone builds; pmsim bench within budgets; git status --porcelain empty and HEAD == origin/main) and end with "FINAL CHECK 8/8 PASS" and "EXIT=0". Evidence from earlier turns, summaries or paraphrases does not count.
```
