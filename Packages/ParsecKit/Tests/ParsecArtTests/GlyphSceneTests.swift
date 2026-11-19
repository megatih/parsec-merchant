// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SwiftUI
import Testing
@testable import ParsecArt

@MainActor
@Suite("Glyphs, scenes and accessibility")
struct GlyphSceneTests {
    static func glyphOK<V: View>(_ view: V, points: Double) -> Bool {
        let (a, b) = ArtSnapshot.twice(view.foregroundStyle(.black), size: CGSize(width: points, height: points), scale: 2)
        return a == b && a.coverage() > 0.05 && a.coverage() < 0.95
    }

    @Test("ART-031 ten commodity glyphs and the illegal octagon are legible at 16 pt @2x")
    func commodities() {
        #expect(CommodityGlyphKind.allCases.count == 10)
        var prints = Set<String>()
        for kind in CommodityGlyphKind.allCases {
            #expect(Self.glyphOK(CommodityGlyph(kind: kind), points: 16), "\(kind)")
            prints.insert(ArtSnapshot.render(CommodityGlyph(kind: kind), size: CGSize(width: 32, height: 32)).fingerprint)
        }
        #expect(prints.count == 10)
        #expect(Self.glyphOK(IllegalBadge(), points: 16))
    }

    @Test("ART-032 sixteen equipment glyphs in enum order, all distinct")
    func equipment() {
        #expect(EquipmentGlyphKind.allCases.count == 16)
        #expect(EquipmentGlyphKind.allCases.first == .weapon(0) && EquipmentGlyphKind.allCases.last == .gadget(6))
        var prints = Set<String>()
        for kind in EquipmentGlyphKind.allCases {
            #expect(Self.glyphOK(EquipmentGlyph(kind: kind), points: 16), "\(kind)")
            prints.insert(ArtSnapshot.render(EquipmentGlyph(kind: kind), size: CGSize(width: 32, height: 32)).fingerprint)
        }
        #expect(prints.count == 16)
    }

    @Test("ART-033 five encounter badges; special is brass")
    func badges() {
        #expect(EncounterBadgeKind.allCases.map(\.rawValue).sorted() == ["alien", "pirate", "police", "special", "trader"])
        for badge in EncounterBadgeKind.allCases { #expect(Self.glyphOK(EncounterBadgeGlyph(badge: badge), points: 16), "\(badge)") }
        let special = ArtSnapshot.render(EncounterBadgeGlyph(badge: .special).foregroundStyle(.black), size: CGSize(width: 32, height: 32))
        let colored = stride(from: 0, to: special.bytes.count, by: 4).contains { special.bytes[$0] > special.bytes[$0 + 2] + 40 }
        #expect(colored)
    }

    @Test("ART-035 tribbles: 24 fur strokes, 4 warm colours; ±8° wiggle over 0.2 s or a scale pulse under Reduce Motion")
    func tribbles() {
        #expect(TribbleSprite.colors.count == 4)
        let peak = (0...20).map { TribbleSprite.wiggle(phase: Double($0) / 100, reduceMotion: false).rotation }
        #expect(abs((peak.max() ?? 0) - 8) < 0.1 && abs((peak.min() ?? 0) + 8) < 0.1)
        #expect(TribbleSprite.wiggle(phase: 0.3, reduceMotion: false) == (0, 1))
        let pulse = TribbleSprite.wiggle(phase: 0.1, reduceMotion: true)
        #expect(pulse.rotation == 0 && pulse.scale > 1)
    }

    @Test("ART-036 ACH-023 achievement medals: tier rims, emblems, and a locked state that is not colour only")
    func achievementBadges() {
        let size = CGSize(width: 48, height: 48)
        let tiers = AchievementTier.allCases.map { ArtSnapshot.render(AchievementBadgeArt(shape: .crown, tier: $0, locked: false), size: size).fingerprint }
        #expect(Set(tiers).count == 3)
        let unlocked = ArtSnapshot.render(AchievementBadgeArt(shape: .ship(.wasp), tier: .brass, locked: false), size: size)
        let locked = ArtSnapshot.render(AchievementBadgeArt(shape: .ship(.wasp), tier: .brass, locked: true), size: size)
        func grey(_ p: ArtPixels) -> [Int] {
            stride(from: 0, to: p.bytes.count, by: 4).map { (Int(p.bytes[$0]) + Int(p.bytes[$0 + 1]) + Int(p.bytes[$0 + 2])) / 30 }
        }
        #expect(grey(unlocked) != grey(locked))
        let emblems: [AchievementEmblem] = [.commodity(.ore), .equipment(.gadget(2)), .encounter(.police), .ship(.beetle), .planet, .crown, .wormhole,
                                            .tribble, .star(points: 6)]
        #expect(Set(emblems.map { ArtSnapshot.render(AchievementBadgeArt(shape: $0, tier: .silver, locked: false), size: size).fingerprint }).count
            == emblems.count)
    }

    @Test("ART-037 the wordmark is the product name, brass gradient, solid under Increase Contrast")
    func wordmark() {
        #expect(Wordmark.title == "Parsec Merchant")
        let size = CGSize(width: 420, height: 60)
        let a = ArtSnapshot.render(Wordmark(size: 30), size: size)
        #expect(a.coverage() > 0.05)
        #expect(a != ArtSnapshot.render(Wordmark(size: 30, increaseContrast: true), size: size))
    }

    @Test("ART-038 the Welcome scene drifts on a 20 s cycle and is static under Reduce Motion")
    func welcome() {
        let size = CGSize(width: 200, height: 120)
        let a = ArtSnapshot.render(WelcomeScene(phase: 0, showsWordmark: false), size: size)
        #expect(a != ArtSnapshot.render(WelcomeScene(phase: 5, showsWordmark: false), size: size))
        #expect(ArtSnapshot.render(WelcomeScene(phase: 5, accessibility: ArtAccessibility(reduceMotion: true), showsWordmark: false), size: size) == a)
        #expect(WelcomeScene.cycle == 20)
    }

    @Test("ART-039 the transit scene moves the ship with progress; Reduce Motion shows the final frame")
    func transit() {
        let size = CGSize(width: 300, height: 90)
        let ship = ShipArtInput(kind: .gnat, sizeClass: 1)
        let early = ArtSnapshot.render(TransitScene(input: ship, progress: 0.1), size: size)
        let late = ArtSnapshot.render(TransitScene(input: ship, progress: 0.9), size: size)
        #expect(early != late)
        var reduced = ship
        reduced.accessibility = ArtAccessibility(reduceMotion: true)
        #expect(ArtSnapshot.render(TransitScene(input: reduced, progress: 0.1), size: size)
            == ArtSnapshot.render(TransitScene(input: reduced, progress: 1), size: size))
        #expect(ArtSnapshot.render(TransitScene(input: ship, progress: 0.5, wormhole: true), size: size)
            != ArtSnapshot.render(TransitScene(input: ship, progress: 0.5), size: size))
    }

    @Test("ART-040 vignettes: planet, ship and every object")
    func vignettes() {
        #expect(VignetteObject.allCases.count == 9)
        let size = CGSize(width: 120, height: 80)
        var prints = Set<String>()
        for o in VignetteObject.allCases { prints.insert(ArtSnapshot.render(Vignette(kind: .object(o)), size: size).fingerprint) }
        #expect(prints.count == 9)
    }

    @Test("ART-041 four endings that animate for at most 4 s, then hold; Reduce Motion shows the final frame")
    func endings() {
        #expect(GameEndArt.allCases.count == 4)
        #expect(GameOverScene.duration == 4)
        #expect(GameOverScene.time(phase: 9, reduceMotion: false) == 4)
        #expect(GameOverScene.time(phase: 1, reduceMotion: true) == 4)
        let size = CGSize(width: 160, height: 90)
        for end in GameEndArt.allCases {
            let (held, again) = ArtSnapshot.twice(GameOverScene(end: end, phase: 4), size: size)
            #expect(held == again, "\(end) is deterministic")
            #expect(held.coverage() == 1 || held.coverage() > 0.97, "\(end) fills its card")
            #expect(held == ArtSnapshot.render(GameOverScene(end: end, phase: 9), size: size), "\(end)")
            #expect(held != ArtSnapshot.render(GameOverScene(end: end, phase: 1), size: size), "\(end)")
            #expect(held == ArtSnapshot.render(GameOverScene(end: end, phase: 0, accessibility: ArtAccessibility(reduceMotion: true)), size: size))
        }
    }

    /// Pixels that are nearly white (the sun's disc and glare), and small bright specks on a dark sky (stars).
    static func bright(_ p: ArtPixels, rows: Range<Int>, over level: UInt8) -> Int {
        var n = 0
        for y in rows { for x in 0..<p.width where (0..<3).allSatisfy({ p.bytes[(y * p.width + x) * 4 + $0] >= level }) { n += 1 } }
        return n
    }

    @Test("ART-084 retired: the sun sinks behind the limb, the stars come out, the planet fills the lower frame")
    func retired() {
        let size = CGSize(width: 320, height: 180)
        let start = ArtSnapshot.render(GameOverScene(end: .retired, phase: 0), size: size)
        let held = ArtSnapshot.render(GameOverScene(end: .retired, phase: 4), size: size)
        let h = start.height
        #expect(Self.bright(start, rows: 0..<h, over: 235) > 3 * max(1, Self.bright(held, rows: 0..<h, over: 235)), "the sun has set")
        // Stars: lit pixels in the top fifth, far above the glow.
        func stars(_ p: ArtPixels) -> Int {
            var n = 0
            for y in 0..<(h / 5) { for x in 0..<p.width where Int(p.bytes[(y * p.width + x) * 4]) + Int(p.bytes[(y * p.width + x) * 4 + 1]) > 120 { n += 1 } }
            return n
        }
        #expect(stars(held) > stars(start))
        // The lower third is the planet: the scene draws it through the sphere projector, so it differs from the sky above.
        let recipe = EndingScenes.recipe(resource: 5, seed: 0x5245_5449)
        #expect(recipe.planetClass == .terran)
        var sky = 0, ground = 0
        for x in 0..<held.width {
            let top = (h / 10 * held.width + x) * 4, bottom = ((h - 4) * held.width + x) * 4
            sky += Int(held.bytes[top]) + Int(held.bytes[top + 1]) + Int(held.bytes[top + 2])
            ground += Int(start.bytes[bottom]) + Int(start.bytes[bottom + 1]) + Int(start.bytes[bottom + 2])
        }
        #expect(ground > 4 * sky, "at the start the day side fills the bottom of the frame")
    }

    @Test("ART-085 bought moon: a barren moon with a dome and the parent planet; the princess variant differs")
    func moon() {
        let size = CGSize(width: 320, height: 180)
        #expect(EndingScenes.recipe(resource: 8, seed: 0x4D4F_4F4E, tech: 0).planetClass == .barren)
        #expect(EndingScenes.recipe(resource: 4, seed: 0x5041_5245, size: 5).planetClass == .ocean)
        let plain = ArtSnapshot.render(GameOverScene(end: .boughtMoon), size: size)
        let princess = ArtSnapshot.render(GameOverScene(end: .boughtMoonGirl), size: size)
        #expect(plain != princess)
        // The difference is local (a second window and the docked ship), not another scene.
        var differing = 0
        for i in stride(from: 0, to: plain.bytes.count, by: 4) where plain.bytes[i] != princess.bytes[i] || plain.bytes[i + 1] != princess.bytes[i + 1] {
            differing += 1
        }
        #expect(differing > 40 && differing < plain.width * plain.height / 8)
        // The moon rises: the first frame has more sky.
        #expect(ArtSnapshot.render(GameOverScene(end: .boughtMoon, phase: 0), size: size) != plain)
    }

    @Test("ART-086 killed: the player's own ship, scorched and tumbling, among twelve hull plates; no star shapes")
    func killed() throws {
        let size = CGSize(width: 320, height: 180)
        #expect(EndingScenes.wreckHull == 0.25 && EndingScenes.tumblePeriod == 8 && EndingScenes.fragments == 12)
        let plates = EndingScenes.plates(seed: ArtSeed.kind(.wasp))
        #expect(plates.count == 12 && plates == EndingScenes.plates(seed: ArtSeed.kind(.wasp)) && Set(plates).count == 12)
        let wasp = ArtSnapshot.render(GameOverScene(end: .killed, ship: .wasp), size: size)
        let beetle = ArtSnapshot.render(GameOverScene(end: .killed, ship: .beetle), size: size)
        #expect(wasp != beetle)
        // The player's statistics, not just the kind, shape the wreck.
        var stats = ShipArtStats.standard(.wasp)
        stats.cargoBays = 70
        stats.weaponSlots = 0
        #expect(ArtSnapshot.render(GameOverScene(end: .killed, ship: .wasp, shipInput: ShipArtInput(kind: .wasp, stats: stats)), size: size) != wasp)
        #expect(ArtSnapshot.render(GameOverScene(end: .killed, phase: 2, ship: .wasp), size: size) != wasp, "it tumbles")
        let source = try String(contentsOf: ArtSnapshot.packageRoot.appendingPathComponent("Sources/ParsecArt/Scenes/Endings.swift"), encoding: .utf8)
        #expect(!source.contains("ArtGeometry.star") && source.contains("sparks: false"))
    }

    @Test("ART-049 art views are decorative (accessibility hidden) unless they carry their own label")
    func decorative() {
        for f in ArtCoreTests.sources where f.text.contains(": View {") && f.name != "ArtAccessibility.swift" {
            #expect(f.text.contains(".accessibilityHidden(true)") || f.text.contains(".accessibilityLabel("), "\(f.name)")
        }
    }

    @Test("ART-050 light and dark renders are both non-empty and differ where the palette has dark variants")
    func darkLight() {
        let size = CGSize(width: 120, height: 80)
        #expect(ArtPalette.hasDarkVariant(.spaceTop) && ArtPalette.hasDarkVariant(.outline))
        for kind in ShipArtKind.allCases {
            let l = ArtSnapshot.render(ShipArt(ShipArtInput(kind: kind)), size: size, scheme: .light)
            let d = ArtSnapshot.render(ShipArt(ShipArtInput(kind: kind)), size: size, scheme: .dark)
            #expect(l.isNonEmpty() && d.isNonEmpty() && l != d, "\(kind)")
        }
        for tech in 0...7 {
            let i = PlanetArtInput(seed: 4, tech: tech)
            #expect(ArtSnapshot.render(PlanetArt(i), size: size, scheme: .dark).coverage() > 0.05)
        }
        let space = [ColorScheme.light, .dark].map { ArtSnapshot.render(SpaceBackground(seed: 2), size: size, scheme: $0) }
        #expect(space[0] != space[1] && space.allSatisfy { $0.coverage() == 1 })
        for kind in CommodityGlyphKind.allCases {
            #expect(ArtSnapshot.render(CommodityGlyph(kind: kind), size: size, scheme: .dark).coverage() > 0.02)
        }
        let icon = [ColorScheme.light, .dark].map { ArtSnapshot.render(AppIconComposite(), size: CGSize(width: 64, height: 64), scheme: $0) }
        #expect(icon[0] != icon[1] && icon.allSatisfy { $0.coverage() == 1 })
    }

    @Test("ART-062 glyphs, avatars, sprites, medals, wordmark, space, vignettes and endings: identical twice and non-empty")
    func glyphDeterminism() {
        var views: [(String, AnyView, CGSize)] = []
        for k in CommodityGlyphKind.allCases {
            for s in [16.0, 64.0] { views.append(("\(k)\(s)", AnyView(CommodityGlyph(kind: k).foregroundStyle(.black)), CGSize(width: s, height: s))) }
        }
        for k in EquipmentGlyphKind.allCases {
            for s in [16.0, 64.0] { views.append(("\(k)\(s)", AnyView(EquipmentGlyph(kind: k).foregroundStyle(.black)), CGSize(width: s, height: s))) }
        }
        for b in EncounterBadgeKind.allCases {
            for s in [16.0, 64.0] { views.append(("\(b)\(s)", AnyView(EncounterBadgeGlyph(badge: b).foregroundStyle(.black)), CGSize(width: s, height: s))) }
        }
        for i in 0..<20 { views.append(("avatar\(i)", AnyView(CharacterPortrait(seed: UInt64(i))), CGSize(width: 48, height: 48))) }
        views.append(("tribble", AnyView(TribbleSprite(index: 2)), CGSize(width: 32, height: 32)))
        for t in AchievementTier.allCases {
            for locked in [false, true] {
                views.append(("medal\(t)\(locked)", AnyView(AchievementBadgeArt(shape: .star(points: 5), tier: t, locked: locked)), CGSize(width: 48, height: 48)))
            }
        }
        views.append(("wordmark", AnyView(Wordmark(size: 24)), CGSize(width: 320, height: 40)))
        for phase in [0.0, 1.5] {
            views.append(("stars\(phase)", AnyView(StarfieldView(seed: 4, phase: phase, animated: true)), CGSize(width: 100, height: 100)))
            views.append(("nebula\(phase)", AnyView(NebulaView(seed: 4)), CGSize(width: 100, height: 100)))
            views.append(("vortex\(phase)", AnyView(WormholeVortexView(phase: phase)), CGSize(width: 40, height: 40)))
        }
        views.append(("vplanet", AnyView(Vignette(kind: .planet(PlanetArtInput(seed: 3)))), CGSize(width: 120, height: 80)))
        views.append(("vship", AnyView(Vignette(kind: .ship(ShipArtInput(kind: .scarab)))), CGSize(width: 120, height: 80)))
        for o in VignetteObject.allCases { views.append(("v\(o)", AnyView(Vignette(kind: .object(o))), CGSize(width: 120, height: 80))) }
        for e in GameEndArt.allCases { views.append(("end\(e)", AnyView(GameOverScene(end: e)), CGSize(width: 160, height: 100))) }
        for (name, view, size) in views {
            let (a, b) = ArtSnapshot.twice(view, size: size)
            #expect(a.fingerprint == b.fingerprint, "\(name)")
            #expect(a.alphaSum > 0, "\(name)")
        }
    }
}
