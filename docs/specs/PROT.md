# PROT: protected planet graphics and frozen game logic

> Format (PRD §7): `- **ID** {Mn} [UI] [M][W][P] statement`. `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2. `[UI]` = verified by app tests hosted in the app or by XCUITest.
> Milestones: M18–M28 (`docs/PRD-UI-Revamp.md` §7). The first number on the PROGRESS status line is the last finished milestone; an ID becomes due when its milestone is finished.
> Normative input: `docs/PRD-UI-Revamp.md` §1.4, §8.2, which holds the wireframes, tables and reasons. These bullets are the testable statements; where a bullet and the PRD differ, fix the bullet.

## PROT

- **PROT-001** {M18} [M][W][P] `scripts/protected-check.sh` exits 0 only if `git diff --exit-code 296ad2c6729fa626fd826b44f112ac2c959eb870 -- <every path in lists A, B, C>` reports nothing and every listed path exists.
- **PROT-002** {M18} [M][W][P] `scripts/logic-frozen.sh` exits 0 only if `git diff --exit-code v1.1.0 -- <the frozen package paths above>` reports nothing and the behaviour fingerprints of §8.2 match.
- **PROT-003** {M18} [M][W][P] `Packages/ParsecKit/Tests/ParsecArtTests/PlanetFrozenTests.swift` pins SHA-256 pixel fingerprints of planets, recorded at M18 before any other change, and fails if one differs.
