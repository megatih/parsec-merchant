// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import Testing
@testable import ParsecArt

@MainActor
@Suite("Effects and icon")
struct EffectsIconTests {
    static let everyKind: [CombatEffect] = [
        CombatEffect(.beam(from: .player, weapon: .pulse, hit: true), start: 0, duration: CombatTiming.beam),
        CombatEffect(.beam(from: .opponent, weapon: .quantum, hit: false), start: 0.12, duration: CombatTiming.beam),
        CombatEffect(.shieldRipple(on: .opponent, kind: .reflective), start: 0.03, duration: CombatTiming.ripple),
        CombatEffect(.sparks(on: .player, count: 9), start: 0.15, duration: CombatTiming.sparks, seed: 3),
        CombatEffect(.shake(amplitude: 6), start: 0.15, duration: CombatTiming.shake),
        CombatEffect(.explosion(on: .opponent), start: 0, duration: CombatTiming.explosion, seed: 1),
        CombatEffect(.powerDown(on: .opponent), start: 0, duration: CombatTiming.powerDown),
        CombatEffect(.escape(side: .player), start: 0, duration: CombatTiming.escape),
        CombatEffect(.arrive(side: .opponent), start: 0, duration: CombatTiming.arrive),
        CombatEffect(.flash(on: .player, tone: .hullHit), start: 0, duration: CombatTiming.flash),
    ]

    @Test("ART-042 effect kinds and the six beam kinds in WeaponType order")
    func kinds() {
        #expect(BeamKind.allCases.map(\.rawValue) == Array(0..<6))
        #expect(CombatEffect.end(of: Self.everyKind) == CombatTiming.explosion)
        #expect(CombatEffect.end(of: []) == 0)
    }

    @Test("ART-044 timing: player beam at 0 s, opponent at 0.12 s, 0.25 s beams; a round's effects fit in 0.55 s")
    func timing() {
        #expect(CombatTiming.playerBeamStart == 0 && CombatTiming.opponentBeamStart == 0.12 && CombatTiming.beam == 0.25)
        #expect(CombatTiming.ripple == 0.35 && CombatTiming.sparks == 0.40 && CombatTiming.shake == 0.30)
        let latestLanding = CombatTiming.opponentBeamStart + CombatTiming.land
        #expect(latestLanding + max(CombatTiming.sparks, CombatTiming.ripple, CombatTiming.shake) <= CombatTiming.roundBudget)
        #expect(CombatTiming.opponentBeamStart + CombatTiming.beam <= CombatTiming.roundBudget)
        #expect(CombatTiming.roundBudget < 0.6)
    }

    @Test("ART-045 every beam kind has its own colour; a miss renders differently from a hit")
    func looks() {
        #expect(Set(BeamKind.allCases.map(CombatEffectRenderer.beamColor)).count == 6)
        let size = CGSize(width: 240, height: 100)
        let hit = ArtSnapshot.render(CombatEffectsLayer(effects: [Self.everyKind[0]], phase: 0.1), size: size)
        let miss = ArtSnapshot.render(CombatEffectsLayer(effects: [CombatEffect(.beam(from: .player, weapon: .pulse, hit: false), start: 0, duration: 0.25)],
                                                         phase: 0.1), size: size)
        #expect(hit != miss)
        let beams = BeamKind.allCases.map { k in
            ArtSnapshot.render(CombatEffectsLayer(effects: [CombatEffect(.beam(from: .player, weapon: k, hit: true), start: 0, duration: 0.25)], phase: 0.1),
                               size: size).fingerprint
        }
        #expect(Set(beams).count == 6)
    }

    @Test("ART-046 explosion hides the ship afterwards; escape slides off; arrive slides in")
    func motion() {
        let boom = [CombatEffect(.explosion(on: .opponent), start: 0, duration: 0.8)]
        #expect(CombatMotion.shipVisible(boom, side: .opponent, at: 0.4))
        #expect(!CombatMotion.shipVisible(boom, side: .opponent, at: 0.81))
        #expect(CombatMotion.shipVisible(boom, side: .player, at: 0.9))
        let escape = [CombatEffect(.escape(side: .player), start: 0, duration: 0.5)]
        #expect(CombatMotion.shipOffset(escape, side: .player, at: 0) == 0)
        #expect(CombatMotion.shipOffset(escape, side: .player, at: 0.5) < -1)
        let arrive = [CombatEffect(.arrive(side: .opponent), start: 0, duration: 0.35)]
        #expect(CombatMotion.shipOffset(arrive, side: .opponent, at: 0) > 0.5)
        #expect(CombatMotion.shipOffset(arrive, side: .opponent, at: 0.35) == 0)
        let shake = [CombatEffect(.shake(amplitude: 6), start: 0, duration: 0.3)]
        #expect(CombatMotion.shake(shake, at: 0.01) != .zero)
        #expect(CombatMotion.shake(shake, at: 0.31) == .zero)
    }

    @Test("ART-047 the Reduce Motion plan is only flashes, one per input effect; nothing moves or shakes")
    func reduced() {
        let reduced = CombatEffect.reducedMotion(Self.everyKind)
        #expect(reduced.count == Self.everyKind.count)
        #expect(reduced.allSatisfy { $0.isFlash })
        #expect(reduced.allSatisfy { $0.duration == 0.2 })
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(CombatMotion.shake(reduced, at: t) == .zero)
            #expect(CombatMotion.shipOffset(reduced, side: .player, at: t) == 0)
            #expect(CombatMotion.shipOffset(reduced, side: .opponent, at: t) == 0)
        }
        #expect(!CombatMotion.shipVisible(reduced, side: .opponent, at: 0.25)) // white flash, then the exploded ship is gone
        #expect(reduced[0].kind == .flash(on: .opponent, tone: .hullHit))
        #expect(reduced[2].kind == .flash(on: .opponent, tone: .shieldHit))
    }

    @Test("ART-064 every effect renders at start, middle and end; non-empty in the middle; the reduced plan renders flashes")
    func effectRenders() {
        let size = CGSize(width: 240, height: 100)
        for e in Self.everyKind {
            for t in [e.start, e.start + e.duration / 2, e.end] {
                let p = ArtSnapshot.render(CombatEffectsLayer(effects: [e], phase: t), size: size)
                if t == e.start + e.duration / 2 { #expect(p.alphaSum > 0, "\(e.kind)") }
            }
        }
        for e in CombatEffect.reducedMotion(Self.everyKind) {
            #expect(ArtSnapshot.render(CombatEffectsLayer(effects: [e], phase: e.start + 0.1), size: size).alphaSum > 0)
        }
    }

    @Test("ART-053 the icon: three layers (stars without glass, ring and hauler with glass) and an indigo fill with a darker dark variant")
    func iconLayers() {
        #expect(AppIconArt.Layer.allCases.map(\.rawValue) == ["stars", "ring", "hauler"])
        #expect(!AppIconArt.Layer.stars.glass && AppIconArt.Layer.ring.glass && AppIconArt.Layer.hauler.glass)
        let light = AppIconArt.fill(scheme: .light), dark = AppIconArt.fill(scheme: .dark)
        #expect(light.top == ArtPalette.rgb(.spaceTop, scheme: .light))
        #expect(dark.top.r < light.top.r && dark.bottom.b < light.bottom.b)
        let hauler = AppIconArt.hauler(scale: 1)
        #expect(!hauler.isEmpty && hauler.boundingRect.midX > 400 && hauler.boundingRect.midX < 624)
    }

    @Test("ART-063 icon layers and every appiconset composite: identical twice, non-empty, opaque composite corners, clear layer corners")
    func iconRenders() {
        for layer in AppIconArt.Layer.allCases {
            let (a, b) = ArtSnapshot.twice(AppIconLayerView(layer), size: CGSize(width: 256, height: 256), scale: 1)
            #expect(a == b)
            #expect(a.coverage() > 0.001, "\(layer)")
            for (x, y) in [(0, 0), (255, 0), (0, 255), (255, 255)] { #expect(a.alpha(x, y) == 0, "\(layer)") }
        }
        for px in [16, 32, 64, 128, 256, 512, 1024] {
            let size = CGSize(width: px, height: px)
            let (a, b) = ArtSnapshot.twice(AppIconComposite(simplified: px <= 32), size: size, scale: 1)
            #expect(a == b)
            #expect(a.distinctColors >= 3)
            for (x, y) in [(0, 0), (px - 1, 0), (0, px - 1), (px - 1, px - 1)] { #expect(a.alpha(x, y) == 255, "\(px)") }
        }
        let full = ArtSnapshot.render(AppIconComposite(simplified: false), size: CGSize(width: 32, height: 32), scale: 1)
        let simple = ArtSnapshot.render(AppIconComposite(simplified: true), size: CGSize(width: 32, height: 32), scale: 1)
        #expect(full != simple)
    }

    @Test("ART-059 snapshots decode to 8-bit RGBA with a stable fingerprint")
    func snapshot() {
        let p = ArtSnapshot.render(Color.red, size: CGSize(width: 4, height: 3), scale: 2)
        #expect(p.width == 8 && p.height == 6 && p.bytes.count == 8 * 6 * 4)
        #expect(p.fingerprint.count == 64)
        #expect(p.bytes[0] > 200 && p.bytes[3] == 255)
    }
}
