# Parsec Merchant 1.1 PRD: realistic art and pointer/touch-first UX

> **What this file is.** A prompt PRD for an autonomous Claude Code run started with `/goal` (run instructions in §0). It extends `docs/PRD.md`, which stays normative for everything this file does not change. Where the two disagree about M14–M17 work, this file wins, and the first step of M14 folds the differences back into `docs/PRD.md` so there is one source of truth again.
>
> **Who reads it.** An agent with no memory of the session that wrote it. Everything needed is here or in the files it names.

## 0. Running it (owner)

1. Pre-flight, as in `GOAL.md` §A: `gh auth setup-git`, UI-automation permission already granted, Mac kept awake (`caffeinate -dimsu`), hands off the mouse during `--ui` gate runs (end of M14, M15, M16, M17).
2. Review this file, then start `claude` in the repo root and turn on auto mode (`/goal` does not change permissions).
3. Paste this as one message:

```
/goal Every milestone M14–M17 in docs/PRD-1.1.md is implemented per its acceptance criteria. Each turn: read PROGRESS.md and continue from "Next step", following the resume and working rules in docs/PRD-1.1.md. Done means: PROGRESS.md reads "M17 done", git tags m14-done, m15-done, m16-done, m17-done and v1.1.0 exist, and one final turn shows the complete unedited output of scripts/final-check.sh ending in "FINAL CHECK 8/8 PASS" and "EXIT=0", plus git status showing a clean tree. No test, gate or threshold was weakened except the rewrites docs/PRD-1.1.md names. If an owner-only blocker stops all remaining work, PROGRESS.md records it and the final message starts with BLOCKED: and the exact thing needed.
```

4. `/goal` shows status, `/goal clear` stops, `claude --continue` resumes. Optional bound: append ` Or stop after 600 turns.`
5. **Approval given by starting the goal:** the agent may push to `main`, push tags, and publish GitHub release `v1.1.0` on `megatih/parsec-merchant`. Remove that from §6 M17 before starting if you want to publish by hand.

<context>

## 1. Why this work exists

Parsec Merchant 1.0 is complete: M0–M13 done, `scripts/final-check.sh` 8/8 PASS on 2026-11-18. The owner played it and asked for four changes:

1. **Graphics are too cartoonish.** Planets are not realistic or varied enough, and their animation is too slow to see.
2. **Ships look cartoonish and like insects**, because the art follows their names (Flea, Gnat, Wasp…). They should look realistic, sleek and sci-fi, shaped by each ship's statistics. Ship pictures are too small in several panels and cards and should use the space available.
3. **The retirement and other ending pictures** should be less cartoonish and more realistic.
4. **The game should be mouse- and touch-first** instead of keyboard-first, following the current macOS HIG and good engineering and design practice.

The owner's standard is how it looks and feels in the running app. Passing tests is necessary but does not by itself meet the request, which is why §5 requires you to look at rendered images and judge them against written criteria.

## 2. What the code does today (verified 2026-11-18 at commit e08f1ff)

**Planets** (`Packages/ParsecKit/Sources/ParsecArt/Planets/`, `Space/SpaceArt.swift`; app glue in `SpaceTraderMac/Art/ArtViews.swift`, `AmbientSchedule.swift`, `MapArt.swift`, `ArtAdapters.swift`):
- Flat SwiftUI `Canvas` vectors. A disk with a radial gradient, 3–7 continent blobs that slide sideways with no spherical projection, wavy cloud polygons, a terminator path.
- Every planet is an Earth-like water world apart from three resource overrides. No gas giants, ice, lava or barren worlds, and no sun.
- `PlanetRenderer.rotationPeriod = 60.0`, drawn at 5 fps (`AmbientSchedule.interval = 1/5`), in a 72×72 frame on the Bridge (`SpaceTraderMac/Views/Sections/BridgeSectionView.swift`). That is about 0.4 pt of movement per frame, which is why it looks still.
- No Metal or shaders anywhere in the project.

**Ships** (`Packages/ParsecKit/Sources/ParsecArt/Ships/`):
- 16 hand-authored insect blueprints chosen by name (`ShipBlueprints.swift`); only the Custom ship uses stats. `ShipArtInput` carries kind, size class, hull fraction and shield, but no statistics and no installed equipment.
- `.relative` scale mode uses the frame's short side (`ShipArt.swift`), so a ship in a wide, short pane stays small.
- Sizes today: Shipyard card 66×44 inside cards at least 230 pt wide; inspector 72×48 in a 260–380 pt column; designer 220×120 in a flexible box; encounter panes 90–120 pt high and full width, ship about 70 pt wide; transit ship about 65 pt in a 520×130 strip; narrative vignette 96×72; game over 280×150.
- `SpaceTraderMac/Art/EncounterStage.swift` hard-codes the combat-effects geometry (40 / 110 / 0.6), so beams and sparks miss the ships if the panes change without it.
- The app icon's "hauler" layer is the Beetle blueprint (`ParsecArt/Icon/AppIconArt.swift`); committed PNGs are checked by `scripts/make-icon.sh --check` inside `verify.sh`.

**Endings** (`Packages/ParsecKit/Sources/ParsecArt/Scenes/Vignettes.swift`, `GameOverScene` and `EndingCanvas`; shown by `SpaceTraderMac/Views/GameOver/GameOverView.swift`):
- Retired: a three-colour gradient, a flat yellow circle and a dark arc. Bought moon: a flat gradient disk, an ellipse dome and a rectangle villa. Killed: the ship rotated, plus 14 three-point stars as debris. Spec: ART-041.

**Input model** (`SpaceTraderMac/`):
- `docs/design/UX-VISION.md` principle 4 reads "Keyboard first, mouse friendly". `docs/specs/UI-KEYS.md` mandates key hints and a keyboard-only scenario.
- Market (`Views/Sections/MarketSectionView.swift`): each `+`/`−` click trades 1 unit; 5, 20 and 100 need ⇧, ⌘, ⇧⌘; a typed amount needs Return or ⇧Return with no visible submit; Jettison and Dump exist only in a right-click menu; the whole actions cell is `.controlSize(.small)`.
- Shipyard compare needs ⌘-click. Map wheel-zoom needs ⌘; tracking needs ⌥-click or the context menu; the hover card cannot be clicked; glyph hit areas go down to about 16 pt and wormholes to about 12 pt (`Map/MapStyle.swift`).
- No hover feedback anywhere (`.onHover` is unused). No drag and drop, although UI-SHELL-078 and UX-VISION §4.4 promise it for the Outfitter. Context menus exist only on the map, the Market Held cell and two file lists.
- Small targets: map zoom HUD 24×22, tribbles 22×22, search suggestion rows with 3 pt padding, icon-only wizard ± buttons.
- No spec sets a minimum hit-target size.

## 3. Outside facts the design rests on

**Apple HIG, updated 28 October 2026 for Touch on Mac** (touch-display Macs and iPad through Sidecar):
- Keyboard and pointing device remain the primary inputs, and every function must stay available through them. "Handle keyboard shortcuts to help people accelerate actions and use keyboard-only work styles."
- "Keep the layout and size of interface elements the same when you support touch."
- "Make tap targets bigger, not the controls themselves." Apple's tech talks give 36 pt per axis as the touch target. Standard controls get this automatically, and steppers, sliders and dials expand on touch automatically.
- "Don't use touch as the only way to access controls or features", and provide touch equivalents for anything that needs a modifier key or a hovering pointer. Touch has no hover: reveal hidden controls on tap and offer them in a context menu.
- Standard gestures: tap selects, double tap opens, one-finger slide scrolls, pinch zooms, touch and hold opens the context menu, touch and hold then drag drags.
- Reported API names, not yet verified against the SDK: Info.plist `NSIsTouchNative`, SwiftUI `directTouchSystemGesturesDisabled()`.

So "pointer and touch first" here means: every action is discoverable and quick with a pointer or a finger alone, nothing needs a modifier key or the keyboard, and the keyboard remains a complete second path.

**Measured in this project (ART-052):** a SwiftUI `TimelineView` frame costs an update and layout pass over the whole window. Idle docked CPU was 4.5% at 5 fps, 5.4% at 10 fps and 11.8% with two 30 fps clocks, against a gate of 5% (`scripts/idle-cpu.sh`). A visibly animated planet therefore cannot be driven by `TimelineView`.

**Toolchain:** `.metal` files are not compiled by `swift build`/`swift test`, and the Metal toolchain is a separate download that a clean clone may lack. ART-001 forbids resources in `ParsecArt`.

**Realistic planet technique:** per-pixel ray–sphere projection of noise-based surface maps, with a day/night terminator, atmosphere rim, specular ocean glint, a separate faster cloud layer with shadow, and latitude bands with domain warping for gas giants.

</context>

<decisions>

## 4. Decisions already made

These were chosen after research and a design review. Build on them; do not reopen them unless a gate proves one unworkable, and then record an ADR in `docs/adr/` and take the fallback named here.

**D1. Planets are baked on the CPU and projected onto a sphere.**
- `ParsecArt` gains a pure-Swift, deterministic `PlanetTextureBaker` that builds equirectangular RGBA8 maps from seeded 3D fBm noise: an albedo map with the ocean/specular mask in alpha, and an auxiliary map holding clouds, city lights, emissive (lava, war fires) and height. Sizes: 512×256 for the hero, 128×64 for stills, 64×32 for map minis. Baking is `Sendable`, runs off the main actor for the hero size, and is cached in a small byte-bounded LRU.
- `ParsecArt` gains `PlanetSphere.project(maps, uniforms, pixelSize) -> CGImage`: orthographic ray–sphere projection with axial tilt, terminator, atmosphere rim, ocean glint, cloud shadow and an analytic ring. `PlanetArt` draws that image at exact pixel size. This is the only path for stills, Reduce Motion, vignettes, map mini-planets, `pmart sheet` and every snapshot test.
- Reason: it gives a deterministic, testable picture that needs no GPU, and the same maps feed the live view.

**D2. The live Bridge planet is a Metal layer outside SwiftUI's update cycle.**
- New `SpaceTraderMac/Art/PlanetMetalView.swift`: an `NSViewRepresentable` over a `CAMetalLayer`, driven by the view's display link at 30 fps, paused when the window is inactive or occluded. It samples the baked maps and uses `PlanetSphere.uniforms(recipe:phase:)`, shared with the CPU projector, so both paths agree.
- The shader is Metal source in a Swift string (`SpaceTraderMac/Art/PlanetSphereShader.swift`) compiled once with `MTLDevice.makeLibrary(source:)`. No `.metal` file and no project-file edit.
- If there is no device or the shader fails to compile, and under Reduce Motion, show the CPU still.
- `ParsecArt` still never reads the clock: the app converts display-link time to `phase mod 600`.
- Fallback ladder if the idle-CPU gate fails: 20 fps, then a `CALayer.contents` update from the CPU projector at 12 fps and 1x scale.

**D3. Planet variety comes from a class taxonomy.**
- `PlanetClass`: terran, ocean, desert, ice, jungle, rocky, barren, volcanic, toxic, gas giant; rings are a modifier.
- A known special resource forces the matching class so the picture stays truthful: desert → desert, sweet oceans → ocean, lifeless → barren, rich fauna → jungle, weird mushrooms → toxic/fungal, rich or poor soil → terran tint, mineral rich/poor → rocky tint, and so on for all 13 resources. The adapter already passes the resource only for visited systems (ART-020 fairness); keep that.
- With no known resource the class is seed-weighted; gas giants appear only at size class large or above.
- Tech level keeps driving city-light density, orbital ring and satellites. Government motifs and pressure overlays remain as overlays on top of the sphere.

**D4. Planet motion and size.** Surface turns once per 24 s, clouds once per 20 s, gas-giant bands once per 15 s; all divide the 600 s phase wrap, so there is no jump. The Bridge planet becomes a hero of about 220–260 pt with a lit star glow sharing the terminator's light direction and a denser starfield behind it.

**D5. Ships come from a stat-driven generator plus a per-kind variant seed.**
- New `ShipArtStats` in `ParsecArt`: size class, cargo bays, weapon, shield and gadget slots, crew quarters, fuel tanks, hull strength, a price tier, a tech tier, and optional installed weapons, shields and gadgets. `ShipArtInput.stats` replaces `CustomShipParams`. `ParsecArt` may not import the engine, so `SpaceTraderMac/Art/ArtAdapters.swift` builds it from `ShipSpec` and the ship instance.
- New `ShipHullGenerator.make(stats, variant:)`: stats set continuous parameters (fineness ratio, beam, number of cargo modules, hardpoints, armour plating, engine count and size, sleekness from price and tech), and stat ratios pick an archetype (hauler, courier, interceptor, gunship, cruiser).
- `variant` is `ArtSeed.kind(kind)`. It selects among planform and nacelle families. Reason: Gnat, Firefly and Mosquito have nearly equal stats, and without a variant they would be indistinguishable and fail ART-013. The variant is keyed by the kind's id; it carries no name semantics, so nothing insect-like comes back.
- Special ships: the Space Monster stays organic and the Bottle stays a bottle. Dragonfly, Mantis, Scarab and Scorpion become distinct warship or alien designs with no insect anatomy (no antennae, legs, stingers, pincers, mandibles or segmented abdomens).
- Ship names are game data and do not change.

**D6. Ship rendering is top-down vector art with realistic shading:** plating gradients under one consistent light direction, panel lines, edge occlusion darkening, a specular strip, engine nozzles with a bloom plume, cockpit glass, navigation lights, and hardpoints for the equipment actually installed when that is supplied. Scorch, shield bubble, cloak and disabled states keep their existing contracts (ART-016…019).

**D7. Ship sizing uses one layout function.** `ShipArtLayout` redefines `.relative` as `k(sizeClass) × fit-to-reference-box`, bounded by both axes, keeping the huge-to-tiny ratio. `EncounterStage` derives its effects geometry from `ShipArtLayout.frame` instead of constants. Targets: Shipyard card full-width banner about 96 pt high; inspector full-width hero; designer preview fills its box; encounter panes 160–240 pt high; larger transit ship; portraits added to the purchase sheet and the compare header.

**D8. Endings are rebuilt from the new planet and ship art** (details in §6 M15).

**D9. Pointer and touch first, keyboard complete.**
- `KeyBindingTable`, the menus and every shortcut stay as they are, so the UI-KEYS-003 fixture and the M12 keyboard tests keep passing. Key hints move out of primary UI into menus, help tags and the Help page.
- A shared `pointerTarget()` modifier gives every custom interactive element a real frame of at least 36 pt on each axis, with the visible chrome allowed to stay smaller inside it. Reason: XCUITest measures the accessibility frame, and `contentShape` alone does not change it.
- A shared `hoverHighlight()` modifier gives tappable cards and rows hover feedback.
- No action may require a modifier key, a hover, or the keyboard.

**D10. Milestone mechanics.** `scripts/spec-trace.sh` line 35 treats every ID as due once the milestone is 13 or more. Change that threshold to 17, and keep the PROGRESS.md line as `M13 done (M14 in progress)` while working on M14 (and likewise later), flipping it only in each milestone's exit commit. `scripts/lib-milestone.sh` reads the first number, so IDs tagged for the milestone in progress are not due until it exits and every commit stays green. Rewrite existing requirement IDs in place and update their tests in the same commit; never renumber; delete a retired requirement together with its citations.

</decisions>

<milestones>

## 5. How every milestone is worked

1. **Specs first.** Amend or add requirement IDs in `docs/specs/` in the format `docs/PRD.md` §7 defines, and commit.
2. **Tests next.** Add or rewrite Swift Testing tests named by ID (`@Test("ART-070 …")`), and XCUITests with `// covers:` comments. They should fail for the right reason before the code exists.
3. **Implement** in small steps, `scripts/verify.sh --quick` between steps, `scripts/verify.sh` before each commit.
4. **Look at the result.** After each visual step, render and read the images yourself:
   - `swift run --package-path Packages/ParsecKit pmart sheet --out build/qa/<name>.png`, then open the PNG with the Read tool. Extend `Packages/ParsecKit/Sources/pmart/ContactSheet.swift` with the pages each milestone asks for.
   - App screens through `scripts/export-screenshots.sh` (see its header for `PM_EXPORT_SCREENSHOTS=1`, `--qa`, `--manual`) and read those PNGs too.
   - Judge them against the look criteria of the milestone. If a picture misses a criterion, fix the art and render again. Write one row per review in `docs/QA-REPORT.md` saying what was checked and on which commit.
5. **Exit.** Run `scripts/verify.sh --ui`, the performance checks the milestone names, update PROGRESS.md (flip the milestone line, tick the checklist, record gate output), commit, tag `mN-done`, push, and print the gate summary lines in that turn.

## 6. Milestones

### M14: planets and space

**Setup (first commits).**
- Commit this file. Apply D10 to `scripts/spec-trace.sh` and add a `PM_TRACE_MILESTONE=<n>` override for previewing untraced IDs.
- `docs/PRD.md`: add §9 rows for M14–M17 that point here, update §7 item 5, §8.1 (`--ui` at the end of M14–M17 as well), §10 and §13 for 18 milestones and v1.1.0. `CLAUDE.md`: same `--ui` list. `scripts/final-check.sh`: `TAG`/`ASSET` to 1.1.0, milestone regex and count to M0–M17 (18). `scripts/release.sh`: version 1.1.0. Bump the app's marketing version to 1.1.0.
- PROGRESS.md: add unchecked M14–M17 entries and set the status line per D10.

**Spike before any art work (timeboxed to one working session, throwaway branch).**
- Put a `CAMetalLayer` view showing any animated sphere on the Bridge, build Release, run `scripts/idle-cpu.sh`. Go if the result is at most 5%; otherwise walk the D2 ladder and record which rung passed in an ADR.
- Confirm that drawing a `CGImage` into a `Canvas` renders byte-identically twice through `ArtSnapshot`.

**Specs (`docs/specs/ART.md`).**
- Conventions: "drawn in code" also admits pixel buffers generated at run time by `ParsecArt`; Metal is allowed in the app target only, as a presentation of `ParsecArt`'s maps.
- Rewrite ART-006 (a warm 160 pt planet still within 4 ms; a cold hero bake within 80 ms off the main actor), ART-021 (drop "no per-pixel noise loops"; keep at least 195 distinct recipes in 200 seeds), ART-022…026 (class table, tech layers, periods of D4), ART-029 (map minis are cached sprites), ART-052 (planet driven by a display link, not `AmbientSchedule`; the 5% idle gate stays), ART-061.
- New IDs from ART-068: class taxonomy, resource-to-class table, baker determinism, projector contract, shared uniforms, GPU/CPU parity, fallback behaviour, display-link pause rules, hero size, star glow.
- Amend UI-SHELL-054 (system card hero) and MAP-095.

**Code.**
- `ParsecArt/Planets/`: new `PlanetNoise.swift`, `PlanetClass.swift`, `PlanetTextureBaker.swift`, `PlanetSphere.swift`; rewrite `PlanetRecipe.swift`, `PlanetArt.swift`; `PlanetLayers.swift` keeps only the overlays. Add `StarGlow` and a denser hero starfield in `Space/SpaceArt.swift`.
- App: `Art/PlanetMetalView.swift`, `Art/PlanetSphereShader.swift`; `PlanetPortrait` in `Art/ArtViews.swift` chooses Metal or the still; hero layout in `Views/Sections/BridgeSectionView.swift`; cached sprites in `Art/MapArt.swift`; `AmbientSchedule` remains for the map's wormhole vortices.
- `pmart`: a contact-sheet page of planet class × tech level × resource, at hero and mini sizes, light and dark.

**Tests.**
- `Packages/ParsecKit/Tests/ParsecArtTests/PlanetSpaceTests.swift`: rewrite the ART-021…026 cases (phase 0 equals phase 600; phase 0 differs from phase 6); class table exhaustive over size × resource; each resource class recognisable by colour statistics (for example desert has no ocean pixels, ice is mostly high-luminance); baker output identical twice and across LODs in class; ring and tilt present in the projection.
- `ArtCoreTests.swift`: the ART-006 budgets.
- `SpaceTraderMacTests/ArtEffectsTests.swift`: replace the grepped `TimelineView(AmbientSchedule…` planet string with the new rule (the planet files contain no `TimelineView`); keep the `AmbientSchedule.interval` check for the map.
- New app tests: the shader source compiles; an offscreen Metal render and the CPU projector agree within a mean absolute difference threshold (skipped with a recorded note when no device exists); Reduce Motion shows the still.

**Look criteria (judge the contact sheet and the Bridge screenshot).**
- A planet reads as a lit sphere: visible limb darkening, a soft terminator, an atmosphere rim on worlds that have air, surface features foreshortened toward the edge.
- At least ten clearly different world types are visible across the sheet, and two terran worlds with different seeds do not look alike.
- Nothing has a drawn outline or flat fill that reads as a cartoon; no visible noise banding or pixel stair-steps at 2x.
- In the running app the rotation and cloud drift are obvious within two seconds of looking.

**Exit checks.** `verify.sh --ui`; `scripts/bench-map.sh` at most 8 ms; `scripts/idle-cpu.sh` at most 5%; largest-text and pseudo-localization flows reviewed for the new Bridge layout at the 1100×720 minimum window.

### M15: ships, sizing, endings and icon

**Specs.**
- `docs/specs/ART.md`: rewrite conventions line 11 (shapes follow ship statistics; no insect anatomy), ART-008 (input carries `ShipArtStats`), ART-009…012 (generator grammar, archetype rules, variant seed, specials, designer), ART-013 (keep: pairwise mask IoU below 0.85 over all 17 kinds, coverage 8–85%), ART-014 (D7 layout, same 0.9/0.5 ratio), ART-016, ART-039…041, ART-053 (hauler is the generated freighter).
- New IDs: stat-to-geometry monotonic properties, equipment hardpoints, layout function, ending scene contracts.
- Amend `docs/design/UX-VISION.md` §7 (ships paragraph) and §5.5, `docs/specs/UI-ENC.md` UI-ENC-018/098/101, `docs/specs/UI-SHELL.md` UI-SHELL-047/068/074.

**Code.**
- `ParsecArt/Ships/`: `ShipArtStats` in `ShipArtInput.swift`; new `ShipHullGenerator.swift` and `ShipSpecials.swift` replace `ShipBlueprints.swift`; upgrade `ShipRenderer.swift`, `ShipFeatures.swift`, `ShipGeometry.swift`; rewrite `ShipArtLayout` in `ShipArt.swift`. Keep `ShipScorch.swift` behaviour.
- App: adapters in `Art/ArtAdapters.swift`; `Art/EncounterStage.swift` geometry from the layout; resize `Views/Sections/ShipyardSectionView.swift`, `Views/Inspector/ShipInspectorView.swift`, `Views/Designer/DesignerView.swift`, `Views/Designer/ShipPurchaseSheet.swift`, `Views/Encounter/EncounterShipPane.swift`, `Views/Transit/TransitView.swift`, `Art/NarrativeVignette.swift` (about 160×120) per D7. Keep every accessibility identifier on the same container.
- **Endings** in `ParsecArt/Scenes/Vignettes.swift`, keeping the public `GameOverScene(end:phase:ship:accessibility:)` contract, the 4 s animate-then-hold timing and the Reduce Motion final frame:
  - *Retired:* an orbital sunset. A planet limb from the sphere projector fills the lower part of the frame; the atmosphere shows layered scattering from deep blue through orange to white at the limb; the sun, with bloom, sets behind the limb over the 4 s; cloud tops catch the low light; stars fade in as it sets.
  - *Bought moon:* a cratered moon surface from the baker's height map, lit by a low sun with long shadows; a glass dome habitat with interior light and a reflection highlight; the parent planet in the sky. The Modern princess variant keeps its two lit windows and a second docked ship, drawn with the new generator.
  - *Killed:* the player's actual ship from the new generator, scorched and tumbling; debris is hull-plate fragments with lit and shadowed faces and a fading glow, replacing the star shapes.
  - `SpaceTraderMac/Views/GameOver/GameOverView.swift`: the scene becomes a cinematic card of about 16:9 that fills the card width instead of 280×150.
- **Icon:** `ParsecArt/Icon/AppIconArt.swift` hauler layer uses the generated freighter; run `scripts/make-icon.sh` to regenerate the committed PNGs so `--check` passes.
- `pmart`: pages for all 17 kinds at 44 pt and 240 pt, both facings, light and dark; a stat sweep for the designer; the four endings at phase 0, 2 and 4.

**Tests.**
- `ShipArtTests.swift`: delete the insect-feature assertions of old ART-010/011 (this is the one planned test removal); add property tests (more cargo bays gives a wider or longer cargo section; more weapon slots gives more hardpoints; higher hull gives heavier plating; changing any stat changes the path); ART-013 over all 136 pairs using each ruleset's stat table; ART-014 ratio; mirroring; scorch within ±3 points; budget (240×160 within 4 ms).
- A source or geometry test that no ship feature named for insect anatomy remains.
- App tests: effects geometry tracks the layout at three pane sizes; adapters pass stats for every `ShipType` in every ruleset; ending scenes deterministic, held frame equal after 4 s, Reduce Motion equals the held frame, the two moon variants differ.
- `IconPipelineTests.swift` and `EffectsIconTests.swift` updated for the new hauler.

**Look criteria.**
- No ship reads as an insect. Each reads as a built machine: hull plating, engines, cockpit, hardpoints.
- A trader with 50–60 bays is visibly a freighter; a three-weapon ship is visibly a warship; an expensive high-tech ship is visibly sleeker than a cheap one.
- All 17 are told apart at 44 pt.
- In the Shipyard, inspector, designer, encounter and transit screenshots the ship fills its panel with comfortable margins, and combat beams start and end on the ships.
- The endings look like scenes lit by a sun, with depth and atmosphere, not flat shapes.
- The icon is still legible at 16 px (also an owner hand check).

**Exit checks.** `verify.sh --ui`; `scripts/make-icon.sh --check`; `scripts/idle-cpu.sh`; encounter, Shipyard and game-over UI flows.

### M16: pointer and touch first

**Start by checking the SDK** for `NSIsTouchNative` and `directTouchSystemGesturesDisabled` (search the macOS 27 SDK `.swiftinterface` and headers). Adopt them only if present; otherwise rely on standard gestures and record the assumption in PROGRESS.md.

**Specs.**
- New `docs/specs/UI-POINTER.md`, IDs `UI-PTR-001…`: the principle; 36 pt targets; hover feedback; no modifier-only, hover-only or keyboard-only action; context menus on every entity; drag and drop with tap alternatives; double-click or double-tap as the primary action on cards; the gesture table of §3; touch equivalents for hover; the manual touch checklist.
- `docs/design/UX-VISION.md`: principle 4 becomes "Pointer and touch first, keyboard complete", with §4.2, §4.3, §4.4, §4.7 and §10 amended to match.
- Rewrite UI-SHELL-035 (no ⌘N hint in sidebar rows; it stays in the menu), UI-SHELL-062/063/064 (Market), UI-SHELL-070 (compare), UI-SHELL-078 (drag and drop is real), UI-ENC-027 (key caps move to the help tag), MAP-014 (plain wheel zooms about the pointer, two-finger scroll pans, pinch zooms), MAP-020 (hit radius at least 18 pt), MAP-044/048…053 (pinned selection card), A11Y-043 tip text. In `UI-KEYS.md`, modifiers are described as accelerators; the binding tables do not change.

**Code.**
- New `SpaceTraderMac/Accessibility/PointerTarget.swift` with `pointerTarget()` and `hoverHighlight()`; sweep every view.
- **Market:** per-row quantity chips (1 / 5 / 20 / Max) with explicit Buy and Sell buttons; a visible submit for the typed amount; a visible Jettison/Dump button; a full context menu on every row. The modifier multipliers stay as accelerators.
- **Shipyard:** a Compare toggle on each card; double-click opens the purchase sheet.
- **Outfitter:** `.draggable` and `.dropDestination` onto slots and a sell well; existing buttons remain as the tap path.
- **Map** (`Map/GalaxyMapView.swift`, `MapStyle.swift`, `HoverCard.swift`, `MapHUDViews.swift`, `MapPlacements.swift`): a click or tap pins a selection card with Set Target, Track and Plot Route buttons (hover still previews); plain wheel zoom; larger hit radii; 36 pt HUD buttons and search rows; tapping the mini chart opens the Galaxy section.
- **Encounter:** large buttons with the key in the help tag; Plunder, Trade and Make-room sheets get quantity chips beside their steppers.
- **Elsewhere:** sidebar rows without ⌘N; tribble buttons, wizard ± buttons and tip close buttons at 36 pt; bank slider steps scaled to the range; context menus for cargo rows, ships, equipment, crew, quests and systems that mirror the visible actions.
- Every new string goes in `Localizable.xcstrings`; every new control gets an accessibility identifier in the `AXID` files and the UI-test mirror.

**Tests.**
- New `SpaceTraderMacUITests/PointerTargetUITests.swift`: walk `UISurfaceCatalog`; every hittable button-type element with an app identifier measures at least 36 pt on its short side. Exempt by element type the standard controls the system already expands (steppers, sliders, checkboxes, pop-up buttons, table rows, toolbar items, window controls).
- New `SpaceTraderMacUITests/PointerOnlyScenarioUITests.swift`: new game → buy cargo with chips → pick a target on the map → warp → resolve an encounter → sell, using clicks only and no `typeKey` after launch.
- `SpaceTraderMacTests/SourceAuditTests.swift`: no `.controlSize(.small)` or `.mini` on buttons outside an allowlist; no action reachable only through `NSEvent.modifierFlags` or a modifier-qualified tap; every `.onTapGesture` card carries `hoverHighlight`.
- Update `BridgeMarketTests`, `ShipyardOutfitterTests`, `MapInteractionTests`, `EncounterViewTests`, `MenuTests` for the new controls.
- `KeyBindingTests` and `M12KeysUITests` keep passing; only focus-order goldens may change, and only where a new control was inserted.

**Look and feel criteria.**
- A player using only a mouse, or only a finger, can do everything in the game, and common trades take no more clicks than before.
- Every clickable thing reacts to the pointer before the click.
- Density is unchanged: controls did not grow, their targets did.

**Exit checks.** `verify.sh --ui` including the accessibility audit, largest-text, pseudo-localization, Reduce Motion and keyboard-only tests; a QA-REPORT row for the touch checklist, with the hands-on part listed in `docs/QA-HANDCHECKS.md` for the owner if no touch hardware is attached.

### M17: polish and release 1.1.0

- Re-export README and QA screenshots with `scripts/export-screenshots.sh`, read each, and update `README.md` where it describes keyboard-first use or shows old art.
- Update `SpaceTraderMac/Resources/Help/` pages and the TipKit texts that teach modifiers; `CHANGELOG.md` 1.1.0 entry; `CREDITS.md` and the ART-067 provenance statement (all art still generated in code, no third-party assets).
- Run `swift run --package-path Packages/ParsecKit -c release pmsim bench`, `scripts/bench-map.sh`, `scripts/idle-cpu.sh`.
- Update `docs/QA-REPORT.md` rows that `scripts/final-check.sh` requires, and add the owner hand checks to `docs/QA-HANDCHECKS.md`: look of planets, ships and endings; icon at 16 px; touch on a touch-display Mac or Sidecar.
- `scripts/release.sh` for 1.1.0, publish GitHub release `v1.1.0`, then `scripts/final-check.sh`. Tag `m17-done` and `v1.1.0`, push.

</milestones>

<acceptance>

## 7. Done

The work is done when all of these hold and the evidence is printed in the conversation:

1. PROGRESS.md shows M14–M17 checked, the status line reads `M17 done`, and Blockers is `none`.
2. Tags `m14-done`, `m15-done`, `m16-done`, `m17-done` and `v1.1.0` exist and are pushed.
3. One turn shows the complete, unedited output of `scripts/final-check.sh` ending with `FINAL CHECK 8/8 PASS` and `EXIT=0`.
4. `git status` in that turn shows a clean tree.
5. `docs/QA-REPORT.md` has a visual review row for each of M14, M15 and M16 stating that the look criteria were met, on which commit.

Owner hand checks do not block completion; list them at the end for the owner.

</acceptance>

<working_rules>

## 8. Working rules

- **Project rules still apply:** everything in `CLAUDE.md` and `docs/PRD.md` §11. In short: the engine stays pure and untouched by this work; Swift 6 with zero warnings; no third-party dependencies; no bitmaps or original Space Trader images; never `.popover`; SPDX header on every source file; every user string localized; every interactive view identified; small conventional commits made only when green.
- **Tests verify behaviour.** Write general solutions. Do not hard-code values to satisfy a test, and do not delete, skip or loosen a test, gate or threshold to get to green. The only planned exceptions are the spec rewrites this file names (for example the insect-motif assertions and the 5 fps planet clock), and each must replace the old check with one for the new requirement in the same commit. If a test seems wrong, say so in PROGRESS.md and fix the cause.
- **Evidence over claims.** The goal is judged from what appears in the conversation. At each milestone exit and at the end, run the gates and let their real output show. Report failures as failures.
- **Scope.** Do what these milestones ask. Do not refactor unrelated code, add features, or change game rules. Reuse what exists before writing new helpers: `ArtCache`, `ArtRandom`/`ArtSeed`, `ArtGeometry`, `ArtPalette`/`ArtInk`, `ArtAccessibility`, `ShipScorch`, `Starfield`/`Nebula`, `ArtSnapshot`, `pmart` `ContactSheet`/`IconExport`, `ArtAdapters`, `WrappingHStack`, `PopUpMenuButton`, `PresentationHost`, `TradeQuantity`, `MapHitTester`, `UISurfaceCatalog` and `ParsecUITestCase`, the `SourceAuditTests` pattern, the `AXID+*` files.
- **Tools.** Run independent tool calls in parallel. Use subagents for wide searches or for an independent review of finished work (give them the code and the criteria, not your conclusion); do the building yourself. In this shell `grep` is a ugrep wrapper: call `/usr/bin/grep`. Ignore `.claude/worktrees/`.
- **New macOS 27 APIs:** consult `.claude/skills/` (swiftui-whats-new-27, swiftui-specialist) before use and record an ADR for any you adopt.
- **Blockers:** `docs/PRD.md` §11.6. Record under Blockers in PROGRESS.md, print `BLOCKED: <exactly what is needed>`, and continue with every task that is not blocked. Decide everything else yourself and note the decision in PROGRESS.md's decisions log.
- **Do not touch the mouse or keyboard** outside `--ui` runs; UI tests run only in that mode.

</working_rules>

<resume>

## 9. Start or resume here

Context is compacted during a long run, so the repository is the memory. At the start of every session and after any compaction:

1. Read `CLAUDE.md`, then `PROGRESS.md`, then this file's section for the current milestone.
2. Run `git status` and `git log --oneline -15` to see what is committed and what is in flight.
3. Run `scripts/verify.sh --quick` and print its summary.
4. Continue from "Next step" in PROGRESS.md.

After every step, update PROGRESS.md: current milestone and step, what was just done, the exact next action, the last gate result, any blocker, and any decision or assumption made. Commit it with the work. End every turn with `Milestone Mx: <done>/<total> steps — gates <PASS|FAIL>`.

</resume>
