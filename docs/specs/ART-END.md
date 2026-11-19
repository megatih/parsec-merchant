# ART-END: ending scenes

> Format (PRD §7): `- **ID** {Mn} [UI] [M][W][P] statement`. `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2. `[UI]` = verified by app tests hosted in the app or by XCUITest.
> Milestones: M18–M28 (`docs/PRD-UI-Revamp.md` §7). The first number on the PROGRESS status line is the last finished milestone; an ID becomes due when its milestone is finished.
> Normative input: `docs/PRD-UI-Revamp.md` §5.3, which holds the wireframes, tables and reasons. These bullets are the testable statements; where a bullet and the PRD differ, fix the bullet.

## ART-END

- **ART-END-001** {M26} [M][W][P] Each ending renders for every buyable ship type and a custom ship; twice gives identical pixels; each has an accessibility label describing the scene.
- **ART-END-002** {M26} [M][W][P] Planets in endings are drawn only through the protected planet API with fixed seeds; the protected files are unchanged (PROT-001).
- **ART-END-003** {M26} [M][W][P] The player's ship in every ending is built from the actual `ShipArtInput` at game end (statistics, equipment, livery), not a reference design; a test with two different final ships gets two different fingerprints for each ending.
- **ART-END-004** {M26} [M][W][P] Phases 0, 2 and 4 seconds differ from each other with motion on; with Reduce Motion the scene is the phase-4 frame from the start.
- **ART-END-005** {M26} [M][W][P] `pmart sheet --page endings` shows each ending at phases 0, 2 and 4. ART-084, ART-085 and ART-086 are rewritten in place for the new scenes.
