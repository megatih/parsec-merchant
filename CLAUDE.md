# Parsec Merchant: project memory for Claude Code

A native macOS 27 remake of Space Trader (Pieter Spronck, GPL). It is built from the C# port at `/Users/megatih/Downloads/SpaceTraderSource201`, which is **read-only reference: never modify it**. The only exception is the differential harness (PRD §8.4), which compiles a *copy* under `build/harness/` (gitignored).

## Source of truth
1. `docs/PRD.md` is **normative**: decisions, architecture, milestones, gates, operating rules. For M14–M17 (release 1.1.0) `docs/PRD-1.1.md` extends it and wins where they differ.
2. `docs/design/UX-VISION.md` is the design direction for every screen.
3. `docs/specs/*.md` holds requirements with IDs (ECO-012…). Tests reference these IDs.
4. `docs/research/01–06` is research input. **The QA ERRATA block at the top of each file overrides that file's body.** Re-verify every value against the source before encoding it.
5. `PROGRESS.md` holds the current milestone, next step, blockers and the last gate result. **Read it first, update it after every step.**

## Commands
- **Gates:**
  - `scripts/verify.sh --quick` between small steps.
  - `scripts/verify.sh` before every commit.
  - `scripts/verify.sh --ui` at the end of M7, M8, M9, M12, M13, M14, M15, M16 and M17.
  - Success prints `ALL GATES PASSED` and `EXIT=0`.
- Completion: `scripts/final-check.sh` (M17).
- Engine fast loop: `swift test --package-path Packages/ParsecKit --filter <Suite>`
- App build: `xcodebuild -project SpaceTraderMac.xcodeproj -scheme SpaceTraderMac -destination 'platform=macOS' -derivedDataPath build/DD build`
- Benchmarks: `swift run --package-path Packages/ParsecKit -c release pmsim bench`
- Harness: `scripts/harness.sh`, which regenerates the fixtures in `Packages/ParsecKit/Tests/Fixtures/harness/`
- Fuzz: `swift run --package-path Packages/ParsecKit -c release pmsim fuzz --games 2000 --seed 1 --ruleset all`

## Architecture rules (hard)
- `Packages/ParsecKit/Sources/ParsecEngine` is pure Swift. It is value types only, `Sendable` and deterministic, with an injected RNG. It must **not** import SwiftUI, AppKit or Combine, must not use singletons, and must not produce user-facing strings: emit typed events and errors, and let the app localize them.
- Rules differ only through `Ruleset` tables, flags and content packs. Never write `if ruleset.id == …`.
- WinForms logic belongs in the engine: commands plus pure `preview` queries.
- The app target defaults to MainActor isolation. Audio synthesis lives in the `ParsecAudio` package target (`nonisolated`, allocation-free). The app only wires it up.
- **Never use `.popover`** (macOS 27 crash). Use overlays, sheets or the inspector instead.
- Swift 6 language mode, zero warnings, no third-party dependencies.
- Every source file starts with `// SPDX-License-Identifier: GPL-2.0-or-later`.
- **No original Space Trader images**, in any form. All art is drawn in code (ParsecArt).

## Conventions
- **Swift Testing** (`import Testing`) for unit and scenario tests. Name tests by requirement ID: `@Test("CMB-007 …")`. XCUITest is for UI flows only.
- **Integer math must match the source exactly.** Swift `/` truncates the same way C# and C do. Where the source wraps, use `&+` and `&*`. Cite `File.cs:line` in the spec, not in the code.
- **Every interactive view** gets an `.accessibilityIdentifier`. **Every user string** goes through `Localizable.xcstrings`.
- **Commits:** small, conventional (`feat(engine): …`), made only when green. Tag `mN-done` at the end of each milestone, then push.
- **Debug launch arguments:** `-PMSeed`, `-PMScenario`, `-PMFlavor template`, `-PMFastTravel`, `-PMSlowTravel <n>`, `-PMAudio off`, `-PMResetState`, `-PMA11y`, `-PMTips off|all`, `-PMWindowSize min|default`, `-PMAppearance light|dark`.
- **Requirement IDs:** match `\*\*[A-Z][A-Z0-9]*(-[A-Z0-9]+)*-[0-9]{3}\*\*` with `/usr/bin/grep -E`. In this shell `grep` is a ugrep wrapper, so scripts must call `/usr/bin/grep`.
- **Blockers:** follow PRD §11.6. Write them in PROGRESS.md, print `BLOCKED: …`, and carry on with unblocked work.

## Gotchas
- **Project file:** the project uses the JSON `SpaceTraderMac.xcodeproj/project.xcproj` with synchronized folders. Back it up (git) before editing it. Follow PRD §6.3 for package linking.
- **Renaming:** target and folder names stay `SpaceTraderMac`. Only the product and display name are "Parsec Merchant". `TEST_HOST` must match the product name. The Debug bundle id ends in `.debug` so its sandbox container stays separate from Release.
- **Never commit** these (all gitignored): `docs/reference/palm-src/` (it contains copyrighted bitmaps), `.claude/skills/` (Apple content), build outputs, or `Config/Local.xcconfig`.
- **Warnings gate:** counts only compiler and linker `warning:` lines. `appintentsmetadataprocessor` noise doesn't count.
- **Data quirk:** the C# port swaps the fuel and repair cost columns relative to Palm (see PRD MOD-017).
- **Palm content:** Palm quest text lives in binary `Rsc` files. Reuse the C# strings for events the two versions share.
