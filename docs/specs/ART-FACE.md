# ART-FACE: procedural portraits

> Format (PRD §7): `- **ID** {Mn} [UI] [M][W][P] statement`. `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2. `[UI]` = verified by app tests hosted in the app or by XCUITest.
> Milestones: M18–M28 (`docs/PRD-UI-Revamp.md` §7). The first number on the PROGRESS status line is the last finished milestone; an ID becomes due when its milestone is finished.
> Normative input: `docs/PRD-UI-Revamp.md` §5.2, which holds the wireframes, tables and reasons. These bullets are the testable statements; where a bullet and the PRD differ, fix the bullet.

## ART-FACE

- **ART-FACE-001** {M19} [M][W][P] Determinism: the same seed gives the same genome and the same pixels; genome hashes for galaxy seed 1001, crew ids 0–54, are pinned as golden values after the style decision (ART-FACE-009) and never change afterwards.
- **ART-FACE-002** {M19} [M][W][P] Uniqueness within a game: for each galaxy seed 1–500 and each ruleset's crew list, all portraits (commander, mercenaries, special characters, famous captains) have pairwise distinct genomes that differ in at least 4 genes, and distinct pixel fingerprints at 96 pt (fingerprints checked for seeds 1–20).
- **ART-FACE-003** {M19} [M][W][P] Uniqueness at large: 100,000 random seeds give at least 99,900 distinct genomes.
- **ART-FACE-004** {M19} [M][W][P] Proportion constraints hold for 10,000 genomes: eye line within 0.46–0.54; eyes mirror-symmetric in position; brows above eyes, nose between eye line and mouth, mouth above chin, all features inside the head outline with a 4% margin; no two feature bounding boxes overlap except brow/eye by at most 10%.
- **ART-FACE-005** {M19} [M][W][P] Stable across saves: loading each v1 save fixture and re-encoding it gives the same portrait seed for every crew id; renaming nothing changes nothing. (The commander's portrait depends on the name, which is fixed at New Game.)
- **ART-FACE-006** {M19} [M][W][P] Legibility: every portrait renders at 28, 64, 96 and 128 pt (28 pt is a floor for legibility, not a current placement); at 28 pt the render keeps at least three tones in the face region (not a blob) — measured as ≥ 3 colour clusters covering ≥ 10% each.
- **ART-FACE-007** {M19} [M][W][P] Performance: a 96 pt portrait draws in ≤ 3 ms median; genomes are cached.
- **ART-FACE-008** {M19} [M][W][P] `pmart sheet --page portraits` renders 60 portraits (galaxy seed 1001 ids 0–54 and five more seeds' commanders) at 128 pt; `--page portraits-small` the same at 28 and 64 pt.
- **ART-FACE-009** {M19} [M][W][P] **Style decision.** See the proof of concept in M19. The decision (target style or fallback) is recorded in `docs/adr/0005-portrait-style.md` with the review scores, and ART-FACE-001's golden values are pinned for the chosen style.
- **ART-FACE-010** {M23} [M][W][P] Every portrait view has an accessibility label "Portrait of ‹name›" and is decorative to keyboard focus.
- **ART-FACE-011** {M19} [M][W][P] ART-034 (helmet busts) is retired with its test in the same commit that lands ART-FACE-001…008.
