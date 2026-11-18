# ADR-0004: The live Bridge planet is a Metal layer at 30 fps; the mini chart's vortices stay still

- Status: accepted (2026-11-18, M14 spike)
- Refines: `docs/PRD-1.1.md` §4 D2 (fallback ladder), ART-052, MAP-095.

## Context
ART-052 gates the idle CPU of a docked Bridge at 5% (`scripts/idle-cpu.sh`, Release build). PRD-1.1 D2 asked for a spike
before any art work: a `CAMetalLayer` sphere on the Bridge driven by the view's display link, with a fallback ladder
(30 fps → 20 fps → `CALayer.contents` from the CPU projector at 12 fps) if the gate failed.

Measured in Release on the build machine (Apple silicon, 2x display; two 10 s samples per run with
`scripts/idle-cpu.sh`):

| Bridge configuration | Idle CPU |
|---|---|
| No ambient clock at all (planet paused, map vortex clock paused) | 0.2–0.4% |
| Map vortex `TimelineView` at 5 fps only (the 1.0 mechanism), planet paused | 4.8–5.0% |
| Final M14 build: Metal planet at 30 fps (520 px, ten texture samples per pixel), mini chart vortices still | 2.3–2.5% |

A time profile showed that the cost of the 1.0 mechanism is the SwiftUI `TimelineView` of the Bridge **mini chart**: each
tick runs an update, constraint and layout pass over the whole window (about 9 ms), whether or not a wormhole is inside
the mini chart's viewport. Hosting that overlay in its own `NSHostingView` did not remove the window pass. Keeping that
clock next to the Metal planet would leave no margin under the 5% gate.

Correction: the spike's own Metal measurement (about 0.3%) was wrong. Its shader failed to compile (the fragment input
lacked `[[stage_in]]`) and the view drew nothing; the ART-074 parity test found this. The table above has the figure
measured with the working renderer.

A second check confirmed that a `CGImage` drawn into a `Canvas` with `GraphicsContext.draw(Image(decorative:scale:))`
renders byte-identically across six fresh `ImageRenderer` passes through `ArtSnapshot` and pixel-exactly at 1:1.

## Decision
1. The live planet uses the first rung of the D2 ladder: a `CAMetalLayer` at 30 fps on the view's `CADisplayLink`
   (`NSView.displayLink(target:selector:)`), paused when the window is inactive or occluded. It costs about 2% CPU.
2. The planet no longer shares `AmbientSchedule`, so the remaining 5 fps clock would be paid by the Bridge only for the
   mini chart's few-pixel vortices. The mini chart therefore draws its vortices still (in the static canvas);
   `AmbientSchedule` keeps turning the vortices of the Galaxy section and the Galaxy Chart window, and only while a
   wormhole is inside the viewport. The 5% gate is unchanged.
3. Stills, tests, Reduce Motion and every fallback draw the CPU projector's `CGImage` in a `Canvas`.

## Consequences
- The idle docked Bridge measures 2.3–2.5% against the 5% budget, instead of 4.4–5.0% in 1.0.
- The Galaxy section with a wormhole in view still costs one 5 fps window pass, as in 1.0.
- If Metal is unavailable or the shader fails to compile, the still is shown; no animation is the degraded mode.
