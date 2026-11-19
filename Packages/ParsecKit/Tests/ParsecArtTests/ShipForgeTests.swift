// SPDX-License-Identifier: GPL-2.0-or-later
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import ParsecArt

/// ART-SHIP: ships built from statistics, with visible equipment and seeded liveries (docs/PRD-UI-Revamp.md §5.1).
@MainActor
@Suite("Ship forge (ART-SHIP)")
struct ShipForgeTests {
    static let size = CGSize(width: 240, height: 160)

    static func render(_ input: ShipArtInput, size: CGSize = ShipForgeTests.size) -> ArtPixels { ArtSnapshot.render(ShipArt(input), size: size) }

    static func stats(_ kind: ShipArtKind = .grasshopper, _ change: (inout ShipArtStats) -> Void = { _ in }) -> ShipArtStats {
        var s = ShipArtStats.standard(kind)
        change(&s)
        return s
    }

    @Test("ART-SHIP-001 every ship type renders at 96, 160 and 240 pt in both scale modes, identically twice")
    func renders() {
        for kind in ShipArtKind.allCases {
            for (side, mode) in [(96.0, ShipScaleMode.fit), (160, .relative), (240, .fit), (240, .relative)] {
                let (a, b) = ArtSnapshot.twice(ShipArt(ShipArtInput(kind: kind), scaleMode: mode), size: CGSize(width: side, height: side * 2 / 3))
                #expect(a.fingerprint == b.fingerprint, "\(kind) \(side)")
                #expect(a.coverage() > 0.01, "\(kind) \(side) \(mode)")
            }
        }
    }

    @Test("ART-SHIP-002 geometry is a pure function of the class design, the statistics and the equipment")
    func classAndStats() {
        for kind in ShipArtKind.buyable {
            let s = ShipArtStats.standard(kind)
            let a = ShipArtInput(kind: kind, stats: s, liverySeed: 3).geometry.description
            #expect(a == ShipArtInput(kind: kind, stats: s, liverySeed: 3).geometry.description, "pure")
            // A designed ship drawn in this class's style is the same design; the name alone changes nothing else.
            #expect(a == ShipArtInput(kind: .custom, stats: s, liverySeed: 3, style: kind).geometry.description)
            // Within a class every statistic still shapes the ship.
            for change in [{ (s: inout ShipArtStats) in s.cargoBays = s.cargoBays >= 40 ? 10 : 55 }, { $0.crewQuarters = $0.crewQuarters == 3 ? 1 : 3 },
                { $0.hullStrength += 100 },
                           { $0.shieldSlots += 1 }, { $0.fuelTanks = $0.fuelTanks > 10 ? 4 : 20 }, { $0.weaponSlots += 1 }, { $0.gadgetSlots += 1 }] {
                var other = s
                change(&other)
                #expect(ShipArtInput(kind: kind, stats: other, liverySeed: 3).geometry.description != a, "\(kind)")
            }
        }
        // Without a style, a designed ship takes the class that suits its statistics.
        #expect(ShipForge.designClass(ShipArtInput(kind: .custom, stats: ShipArtStats.standard(.termite))) == .termite)
        #expect(ShipForge.designClass(ShipArtInput(kind: .custom, stats: ShipArtStats.standard(.wasp))) == .wasp)
        #expect(ShipForge.designClass(ShipArtInput(kind: .custom, stats: ShipArtStats.standard(.flea))) == .flea)
        #expect(ShipForge.isSpecial(.mantis) && !ShipForge.isSpecial(.wasp) && !ShipForge.isSpecial(.custom))
        // Each class has its own design: the same statistics in two classes give two different hulls.
        let shared = ShipArtStats.standard(.bumblebee)
        let designs = Set(ShipArtKind.buyable.map { ShipArtInput(kind: $0, stats: shared).geometry.hull.description })
        #expect(designs.count == 10)
    }

    @Test("ART-SHIP-003 statistics shape every class monotonically: bays, quarters, hull, shield slots, fuel and size")
    func monotonic() {
        struct Counts {
            var doors: Int, cabins: Int, plates: Int, radiators: Int, tank: Double, nozzles: Int, beam: Double
        }
        func counts(_ kind: ShipArtKind, _ s: ShipArtStats) -> Counts {
            let g = ShipArtInput(kind: kind, stats: s).geometry
            let tank = g.parts.first { $0.tag == "tank" }?.path.boundingRect.width ?? 0
            return Counts(doors: g.count("cargoDoor"), cabins: g.count("cabin"), plates: g.count("plate"), radiators: g.count("radiator") / 2, tank: tank,
                          nozzles: g.glows.count, beam: g.hull.boundingRect.height)
        }
        var rng = ArtRandom(seed: 20)
        var designs = ShipArtKind.buyable.map { ($0, ShipArtStats.standard($0)) }
        for i in 0..<500 {
            designs.append((ShipArtKind.buyable[i % 10], ShipArtStats(sizeClass: rng.int(0...5), cargoBays: rng.int(0...80), weaponSlots: rng.int(0...5),
                                                                       shieldSlots: rng.int(0...3), gadgetSlots: rng.int(0...3), crewQuarters: rng.int(1...3),
                                                                       fuelTanks: rng.int(1...20), hullStrength: rng.int(10...400), priceTier: 2, techTier: 5)))
        }
        for (kind, base) in designs {
            let c = counts(kind, base)
            #expect(c.doors == ShipFrame.doorCount(bays: base.cargoBays) && c.cabins == min(3, max(1, base.crewQuarters)), "\(kind)")
            #expect(c.plates == ShipFrame.plateCount(hull: base.hullStrength) && c.radiators == 1 + min(3, base.shieldSlots), "\(kind)")
            var more = base
            more.cargoBays += 7
            #expect(counts(kind, more).doors >= c.doors && counts(kind, more).beam >= c.beam - 1e-9, "\(kind): more bays, more doors and no narrower")
            more = base
            more.crewQuarters += 1
            #expect(counts(kind, more).cabins >= c.cabins)
            more = base
            more.hullStrength += 60
            #expect(counts(kind, more).plates >= c.plates)
            more = base
            more.shieldSlots += 1
            #expect(counts(kind, more).radiators >= c.radiators)
            more = base
            more.fuelTanks = min(20, base.fuelTanks + 3)
            #expect(counts(kind, more).tank >= c.tank - 1e-9, "\(kind): more fuel, no shorter tanks")
            more = base
            more.sizeClass = min(5, base.sizeClass + 1)
            #expect(counts(kind, more).nozzles >= c.nozzles, "\(kind)")
        }
        #expect(ShipFrame.doorCount(bays: 0) == 0 && ShipFrame.doorCount(bays: 15) == 3 && ShipFrame.doorCount(bays: 200) == 12)
        #expect(ShipFrame.plateCount(hull: 25) == 1 && ShipFrame.plateCount(hull: 200) == 8 && ShipFrame.plateCount(hull: 900) == 12)
        #expect(ShipFrame.nozzleCount(sizeClass: 0) == 1 && ShipFrame.nozzleCount(sizeClass: 4) == 3)
        // Size class: relative mode draws a larger class longer in the same frame.
        let frame = CGSize(width: 200, height: 200)
        let lengths = (0...4).map { ShipArtLayout.frame(ShipArtInput(kind: .hornet, sizeClass: $0), mode: .relative, in: frame).width }
        #expect(zip(lengths, lengths.dropFirst()).allSatisfy { $0 < $1 }, "\(lengths)")
    }

    @Test("ART-SHIP-004 every slot has a mount; each installed item is visible in its own shape; hidden cargo bays show nothing")
    func slots() {
        let empty = Self.stats()
        let bare = ShipArtInput(kind: .grasshopper, stats: empty).geometry
        #expect(bare.count("hardpoint") == empty.weaponSlots && bare.count("emitter") == empty.shieldSlots && bare.count("gadgetMount") == empty.gadgetSlots)
        #expect(bare.count("emptyHardpoint") == empty.weaponSlots && bare.count("emptyEmitter") == empty.shieldSlots)
        #expect(bare.count("weapon:") == 0 && bare.count("shield:") == 0 && bare.count("gadget:") == 0)
        let pristine = Self.render(ShipArtInput(kind: .grasshopper, stats: empty)).fingerprint
        var prints = Set([pristine])
        for weapon in 0..<6 {
            let g = ShipArtInput(kind: .grasshopper, stats: Self.stats { $0.weapons = [weapon] }).geometry
            #expect(g.count("weapon:\(weapon)") >= 1 && g.count("emptyHardpoint") == empty.weaponSlots - 1 && g.count("hardpoint") == empty.weaponSlots)
            prints.insert(Self.render(ShipArtInput(kind: .grasshopper, stats: Self.stats { $0.weapons = [weapon] })).fingerprint)
        }
        for shield in 0..<3 {
            let g = ShipArtInput(kind: .grasshopper, stats: Self.stats { $0.shields = [shield] }).geometry
            #expect(g.count("shield:\(shield)") == 1 && g.count("emptyEmitter") == empty.shieldSlots - 1)
            prints.insert(Self.render(ShipArtInput(kind: .grasshopper, stats: Self.stats { $0.shields = [shield] })).fingerprint)
        }
        for gadget in 0..<6 {
            let g = ShipArtInput(kind: .grasshopper, stats: Self.stats { $0.gadgets = [gadget] }).geometry
            #expect(g.count("gadget:\(gadget)") >= 1 && g.count("gadgetMount") == empty.gadgetSlots)
            prints.insert(Self.render(ShipArtInput(kind: .grasshopper, stats: Self.stats { $0.gadgets = [gadget] })).fingerprint)
        }
        // 6 weapons, 3 shields and 6 visible gadgets, each a different picture from the others and from the empty hull.
        #expect(prints.count == 16)
        let hidden = ShipArtInput(kind: .grasshopper, stats: Self.stats { $0.gadgets = [ShipFittings.hiddenBays] })
        #expect(Self.render(hidden).fingerprint == pristine && hidden.geometry.count("gadget:") == 0)
        // More installed than slots: the extra items are not drawn.
        #expect(ShipArtInput(kind: .gnat, stats: Self.stats(.gnat) { $0.weapons = [0, 1, 2] }).geometry.count("weapon:") == 1)
    }

    @Test("ART-SHIP-006 liveries vary: 2,000 seeds give at least 1,500 signatures per type and role, and 64 seeds give 64 pictures")
    func liveryVariety() {
        for role in [ShipRole.trader, .pirate] {
            let signatures = Set((0..<2000).map { ShipLivery.make(role: role, seed: UInt64($0)).signature })
            #expect(signatures.count >= 1500, "\(role): \(signatures.count)")
            for kind in ShipArtKind.buyable {
                let prints = Set((0..<64).map { Self.render(ShipArtInput(kind: kind, role: role,
                    liverySeed: UInt64($0) + 1000 * UInt64(kind.rawValue))).fingerprint })
                #expect(prints.count == 64, "\(kind) \(role): \(prints.count)")
            }
        }
        // The livery never changes the geometry's solid parts.
        let a = ShipArtInput(kind: .hornet, role: .trader, liverySeed: 1), b = ShipArtInput(kind: .hornet, role: .pirate, liverySeed: 9)
        #expect(a.geometry.bounds == b.geometry.bounds && a.geometry.count("cargoDoor") == b.geometry.count("cargoDoor"))
    }

    @Test("ART-SHIP-007 an opponent is never the player's twin: a different signature and a hull hue at least 40° away")
    func neverTheTwin() {
        var rng = ArtRandom(seed: 0xBEEF)
        for i in 0..<100_000 {
            let playerSeed = rng.next(), seed = rng.next()
            let role = [ShipRole.trader, .pirate, .famousCaptain][i % 3]
            let player = ShipLivery.make(role: .player, seed: playerSeed)
            let other = ShipLivery.make(role: role, seed: seed, avoidingPlayer: playerSeed)
            #expect(other.signature != player.signature)
            #expect(ShipLivery.hueDistance(other.baseHue, player.baseHue) >= 40, "\(role) \(other.baseHue) vs \(player.baseHue)")
        }
        // The same type in the player's and in an opponent's livery are different pictures, whatever the seeds.
        for i in 0..<200 {
            let playerSeed = rng.next(), seed = rng.next(), kind = ShipArtKind.buyable[i % 10]
            let role = [ShipRole.trader, .pirate, .famousCaptain, .police][i % 4]
            let mine = Self.render(ShipArtInput(kind: kind, role: .player, liverySeed: playerSeed)).fingerprint
            #expect(mine != Self.render(ShipArtInput(kind: kind, role: role, liverySeed: seed, playerLiverySeed: playerSeed)).fingerprint)
        }
        // A captain's fixed livery is never altered by the rule.
        for k in 0..<3 {
            #expect(ShipLivery.make(role: .famousCaptain, seed: UInt64(k), avoidingPlayer: 77) == ShipLivery.make(role: .famousCaptain, seed: UInt64(k)))
        }
        #expect(Set((0..<3).map { ShipLivery.make(role: .famousCaptain, seed: UInt64($0)).base }).count == 3)
    }

    @Test("ART-SHIP-008 police wear the checker band, the insignia and blue beacons; pirates are worn with no registry; traders carry one")
    func roles() {
        for kind in ShipArtKind.buyable {
            for seed in [UInt64(1), 2, 3] {
                let input = ShipArtInput(kind: kind, role: .police, liverySeed: seed)
                let g = input.geometry
                #expect(g.checkerCells.count >= 4 && g.count("insignia") == 1 && g.lights.filter { $0.kind == .beacon }.count == 2)
                #expect(input.livery.wear <= 0.2)
                // The rendered band alternates blue and white: sample the centre of each cell that lies on the hull.
                let pixels = ArtSnapshot.render(ShipArt(input), size: CGSize(width: 480, height: 320))
                let t = ShipArtLayout.transform(bounds: g.bounds, size: CGSize(width: 480, height: 320), mode: .fit, sizeClass: input.sizeClass, facing: .right)
                var blue = 0, white = 0
                for cell in g.checkerCells where cell.rect.width > 0.012 && cell.rect.height > 0.012 {
                    let p = CGPoint(x: cell.rect.midX, y: cell.rect.midY).applying(t)
                    let i = (Int(p.y * 2) * pixels.width + Int(p.x * 2)) * 4
                    let r = Int(pixels.bytes[i]), b = Int(pixels.bytes[i + 2])
                    if cell.blue { blue += b > r + 40 ? 1 : 0 } else { white += r > 150 && abs(r - b) < 50 ? 1 : 0 }
                }
                #expect(blue >= 2 && white >= 2, "\(kind) seed \(seed): \(blue) blue, \(white) white")
                for role in [ShipRole.player, .pirate, .trader, .famousCaptain] {
                    let other = ShipArtInput(kind: kind, role: role, liverySeed: seed).geometry
                    #expect(other.checkerCells.isEmpty && other.count("insignia") == 0 && other.count("checker") == 0)
                }
                let pirate = ShipArtInput(kind: kind, role: .pirate, liverySeed: seed)
                #expect(pirate.livery.wear >= 0.6 && pirate.geometry.count("registry") == 0 && pirate.geometry.count("salvage") >= 3)
                let trader = ShipArtInput(kind: kind, role: .trader, liverySeed: seed)
                #expect(trader.geometry.count("registry") >= 1 && (0.2...0.6).contains(trader.livery.wear))
                #expect(ShipArtInput(kind: kind, role: .player, liverySeed: seed).livery.accent == ShipLivery.brass)
            }
        }
        // Beacons blink once a second and are steady under Reduce Motion.
        let on = ShipArtInput(kind: .hornet, role: .police, phase: 0.2), off = ShipArtInput(kind: .hornet, role: .police, phase: 0.7)
        #expect(Self.render(on) != Self.render(off))
        var still = on, stillLater = off
        still.accessibility = ArtAccessibility(reduceMotion: true)
        stillLater.accessibility = ArtAccessibility(reduceMotion: true)
        #expect(Self.render(still) == Self.render(stillLater))
        #expect(ShipLivery.make(role: .yard, seed: 5) == ShipLivery.make(role: .player, seed: 5))
    }

    @Test("ART-SHIP-009 special designs: creature, alien, prototype, hardened raider, bottle, and the unlit hulk")
    func specials() {
        let monster = ShipArtInput(kind: .spaceMonster).geometry
        #expect(monster.organic && monster.count("tendril") >= 5 && monster.count("cargoDoor") == 0 && monster.count("cabin") == 0)
        let mantis = ShipArtInput(kind: .mantis, stats: Self.stats(.mantis) { $0.weapons = [2, 2, 2] }).geometry
        #expect(mantis.count("shard") >= 3 && mantis.count("cargoDoor") == 0 && mantis.count("registry") == 0 && mantis.count("weapon:") == 3)
        #expect(mantis.count("hardpoint") == 3 && mantis.count("emitter") == 1 && mantis.count("gadgetMount") == 3)
        let dragonfly = ShipArtInput(kind: .dragonfly).geometry
        #expect(dragonfly.count("emitter") == 3 && dragonfly.count("panel") >= 3)
        #expect(ShipArtInput(kind: .scarab).geometry.count("shell") == 1 && ShipArtInput(kind: .bottle).geometry.glass)
        let scorpion = ShipArtInput(kind: .scorpion)
        #expect(scorpion.geometry.count("cabin") == 2 && scorpion.geometry.paint == ArtRGB(0.11, 0.11, 0.12))
        // The Marie Celeste: a trader hull with no plume and no lit light, and an open hatch.
        let live = ShipArtInput(kind: .firefly, role: .trader, liverySeed: 4), hulk = ShipArtInput(kind: .firefly, role: .trader, liverySeed: 4, derelict: true)
        #expect(hulk.geometry.derelict && hulk.geometry.count("hatch") == 1 && live.geometry.count("hatch") == 0)
        #expect(Self.render(hulk) != Self.render(live))
        var later = hulk
        later.phase = 0.2
        #expect(Self.render(hulk) == Self.render(later), "a hulk has no flickering plume")
    }

    @Test("ART-SHIP-010 liveries and geometry of fixed inputs are pinned")
    func pinned() {
        var lines: [String] = []
        for (i, kind) in ShipArtKind.buyable.enumerated() {
            for role in [ShipRole.player, .trader] {
                let input = ShipArtInput(kind: kind, role: role, liverySeed: UInt64(100 + i), playerLiverySeed: 5)
                let s = input.livery.signature
                lines.append("\(kind)|\(role)|\(s.pattern)|\(s.baseHueStep)|\(s.accentHueStep)|\(s.wearStep)|\(s.marking)|\(input.geometry.parts.count)")
            }
        }
        let digest = SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(lines.count == 20)
        #expect(digest == "5efe3f6967fd5ae966d2bcc5f83e90dff8656bea98da0b5f804541bfcab31adf", "now \(digest)")
    }

    @Test("ART-SHIP-011 a 240 × 160 ship draws within 4 ms (median); built ships are cached")
    func budget() {
        let inputs = ShipArtKind.buyable.map { ShipArtInput(kind: $0, role: .trader, liverySeed: 3) }
        // The same measure as ART-006: 240 × 160 points at 1× scale.
        func once() { for i in inputs { _ = ArtSnapshot.render(ShipArt(i), size: Self.size, scale: 1) } }
        once()
        var times: [Double] = []
        for _ in 0..<15 {
            let start = DispatchTime.now().uptimeNanoseconds
            once()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(inputs.count))
        }
        let median = times.sorted()[times.count / 2]
        #expect(median <= 4.0, "median \(median) ms")
        print("ART-SHIP-011 median \(median) ms")
        let cache = ShipForgeCache()
        for i in 0..<600 { _ = cache.value(i) { i } }
        #expect(cache.value(599) { -1 } == 599 && cache.value(0) { -1 } == -1)
    }

    @Test("ART-SHIP-014 the app icon's ship is the forge's Hornet")
    func iconFreighter() {
        let detailed = AppIconArt.hauler(scale: 1), simple = AppIconArt.hauler(scale: 1, simplified: true)
        #expect(!detailed.isEmpty && !simple.isEmpty && detailed.boundingRect.width > 300)
        #expect(ShipArtInput(kind: .hornet).geometry.count("wing") == 2)
    }
}
