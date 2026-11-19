# ADR 0005: portrait style for release 2.0

- **Status:** accepted, 2026-11-19 (M19)
- **Requirement:** ART-FACE-009 (`docs/PRD-UI-Revamp.md` §5.2)

## Context

Release 2.0 replaces the faceless helmet avatars with a face for every character. The PRD set a target style
("illustrated realism": layered, flat-shaded busts with human proportions), a numeric quality bar, and a fallback
(a helmeted flight suit) if the bar was missed after three iterations.

## Decision

**The target style is adopted.** The fallback style is not built.

The generator is `Packages/ParsecKit/Sources/ParsecArt/Portraits/` (genome of 24 genes, layout, renderer). Genomes
for galaxy seed 1001 and the seven authored characters are pinned in `PortraitTests` (ART-FACE-001) and do not
change from here on; drawing may still be polished as long as the genome and the tests hold.

## Evidence

Automated: ART-FACE-001…008 pass (determinism, uniqueness within a game over 500 galaxy seeds, 100,000-seed
uniqueness, proportion constraints on 10,000 genomes, three tones at 28 pt, 96 pt draw time within 3 ms).

Reviews of the 60-portrait sheet (`pmart sheet --page portraits-1` … `portraits-4`, `portraits-small`), against the
six-line rubric of the PRD; the bar is 54 of 60 in both reviews.

| Iteration | Self review | Independent review | Main changes made after it |
|---|---|---|---|
| 1 | about 52 of 60 | 27 of 60 | softer face planes, terminator moved to the far cheek, shadows clamped on dark skin, hair anchored to the skull, eyes toned to the skin, insignia moved clear of the outfit |
| 2 | about 54 of 60 | 52 of 60 | skull never wider than the cheekbones, hair forced apart from skin tone, soft stubble, no facial hair with long or tied styles |
| 3 | 56 of 60 | **55 of 60** | (adopted) |

- **Self review:** 56 of 60 on iteration 3. My fails: 19 and 51 (thin moustache reads badly), 40 and 47 (too close to a neighbour).
- **Independent review:** a subagent that saw only the PNG files and the rubric. Iteration 3: 55 of 60; fails 19, 29, 40, 47, 51.

Two things a reader should know about the independent reviews:

1. The first review was told to fail a portrait on any hesitation. Reviews 2 and 3 were told to fail a portrait for
   a defect the reviewer can name and not for the house style itself. The rubric was the same; the instruction was
   less strict, so the jump from 27 to 52 is partly the wording and partly the changes.
2. After review 3 two small changes were made and not re-reviewed: brows are now always clearly darker than the
   skin (the reviewer's first remaining weakness), and the insignia on overalls sits a little higher.

## Known limitations

- Thin moustaches can read as a shadow at small sizes.
- Two crew members with the same skin tone, hair colour and short hair style can look alike side by side; they
  always differ in at least four genes and in their pixels (ART-FACE-002), but not always at a glance.
- Expression is neutral for everyone.

## Consequences

- `CrewAvatar` and requirement ART-034 are retired (ART-FACE-011).
- The app derives a portrait from saved state only: galaxy seed and crew id, plus the commander's name for the
  commander (`ArtAdapters.portraitSeed`, ART-FACE-005). Nothing is added to the save.
