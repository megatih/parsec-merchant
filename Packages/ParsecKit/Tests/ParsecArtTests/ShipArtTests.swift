// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import Testing
@testable import ParsecArt

@MainActor
@Suite("Ship art")
struct ShipArtTests {
    static func mask(_ kind: ShipArtKind, mode: ShipScaleMode = .fit, sizeClass: Int = 2, facing: ShipFacing = .right,
                     size: CGSize = CGSize(width: 128, height: 128)) -> ArtPixels {
        ArtSnapshot.render(ShipSilhouette(ShipArtInput(kind: kind, sizeClass: sizeClass, facing: facing), scaleMode: mode), size: size, scale: 1)
    }

    @Test("ART-013 every pair of the 17 silhouettes has IoU below 0.85; each covers 8%…85%")
    func distinctSilhouettes() {
        let masks = ShipArtKind.allCases.map { (kind: $0, pixels: Self.mask($0)) }
        var worst = (0.0, "")
        for m in masks {
            let c = m.pixels.coverage(threshold: 127)
            #expect(c >= 0.08 && c <= 0.85, "\(m.kind) covers \(c)")
        }
        var pairs = 0
        for i in masks.indices {
            for j in masks.indices where j > i {
                pairs += 1
                let v = ArtSnapshot.iou(masks[i].pixels.mask, masks[j].pixels.mask)
                if v > worst.0 { worst = (v, "\(masks[i].kind)/\(masks[j].kind)") }
                #expect(v < 0.85, "\(masks[i].kind) vs \(masks[j].kind): IoU \(v)")
            }
        }
        #expect(pairs == 136)
        print("ART-013 worst pair \(worst.1) IoU \(worst.0)")
    }

    @Test("ART-007 17 art kinds in ShipType order; ten buyable")
    func kinds() {
        #expect(ShipArtKind.allCases.count == 17)
        #expect(ShipArtKind.allCases.map(\.rawValue) == Array(0..<17))
        #expect(ShipArtKind.custom.rawValue == 15 && ShipArtKind.scorpion.rawValue == 16)
        #expect(ShipArtKind.buyable.count == 10 && ShipArtKind.buyable.allSatisfy(\.isBuyable))
    }

    @Test("ART-008 ShipArtInput carries ShipArtStats: clamped, with price and tech tiers and optional installed equipment")
    func input() {
        let i = ShipArtInput(kind: .wasp, sizeClass: 9, hullFraction: 1.4, shield: ShieldDisplay(kind: .reflective, fraction: -1))
        #expect(i.sizeClass == 5 && i.stats.sizeClass == 5 && i.hullFraction == 1 && i.shield?.fraction == 0)
        #expect(ShipArtInput(kind: .gnat).stats == ShipArtStats.standard(.gnat))
        #expect(ShipArtStats.priceThresholds == [5000, 20000, 50000, 90000, 200_000])
        #expect([0, 4999, 5000, 60000, 500_000].map(ShipArtStats.priceTier(price:)) == [0, 0, 1, 3, 5])
        let s = ShipArtStats(sizeClass: -3, cargoBays: -1, weaponSlots: 2, shieldSlots: 1, gadgetSlots: 0, crewQuarters: 1, fuelTanks: 14,
                             hullStrength: 100, priceTier: 9, techTier: 12, weapons: [0, 2])
        #expect(s.sizeClass == 0 && s.cargoBays == 0 && s.priceTier == 5 && s.techTier == 7 && s.weapons == [0, 2] && s.shields == nil)
        // The picture follows the statistics, not the kind: the same statistics and variant give the same hull.
        let a = ShipArtInput(kind: .gnat, stats: ShipArtStats.standard(.hornet), variant: 7).blueprint
        let b = ShipArtInput(kind: .wasp, stats: ShipArtStats.standard(.hornet), variant: 7).blueprint
        #expect(a == b)
    }

    static func mirrorEqual(_ path: Path) -> Bool {
        let m = ArtGeometry.mirrorY(path)
        let a = path.boundingRect, b = m.boundingRect
        // SwiftUI `Path` stores single-precision coordinates, so "within 1e-9" holds for the geometry and 1e-6 for the stored path.
        let tol = 1e-6
        guard abs(a.minX - b.minX) < tol, abs(a.minY - b.minY) < tol, abs(a.maxX - b.maxX) < tol, abs(a.maxY - b.maxY) < tol else { return false }
        let n = 61
        for j in 0..<n {
            for i in 0..<n {
                let p = CGPoint(x: (Double(i) + 0.37) / Double(n), y: (Double(j) + 0.5) / Double(n))
                if path.contains(p) != m.contains(p) { return false }
            }
        }
        return true
    }

    static let reference = ShipArtKind.allCases.map { ShipArtStats.standard($0) }

    static func stats(bays: Int = 20, weapons: Int = 1, shields: Int = 1, gadgets: Int = 1, crew: Int = 1, fuel: Int = 14, hull: Int = 100,
                      size: Int = 2, price: Int = 2, tech: Int = 5) -> ShipArtStats {
        ShipArtStats(sizeClass: size, cargoBays: bays, weaponSlots: weapons, shieldSlots: shields, gadgetSlots: gadgets, crewQuarters: crew,
                     fuelTanks: fuel, hullStrength: hull, priceTier: price, techTier: tech)
    }

    @Test("ART-009 the generator grammar: symmetric hulls, the fixed length axis, and the stat formulas")
    func grammar() {
        for kind in ShipArtKind.allCases {
            let bp = ShipArtInput(kind: kind).blueprint
            let g = ShipGeometry.make(bp)
            #expect(!bp.hull.isEmpty)
            if bp.symmetric {
                #expect(Self.mirrorEqual(g.silhouette), "\(kind)")
                #expect(Self.mirrorEqual(g.hull), "\(kind)")
            }
        }
        #expect(!ShipArtInput(kind: .spaceMonster).blueprint.symmetric)
        for s in Self.reference {
            let bp = ShipHullGenerator.make(s, variant: 11)
            #expect(bp.noseX == ShipHullGenerator.noseX && bp.tailX == ShipHullGenerator.tailX)
            #expect(bp == ShipHullGenerator.make(s, variant: 11), "pure")
            #expect(bp.features.contains(.navigationLights))
            #expect(bp.plating == [60, 120, 180, 260, 360].filter { s.hullStrength >= $0 }.count)
            let engines = bp.engines.reduce(0) { $0 + ($1.yOffset > 0 ? 2 : 1) }
            #expect(engines >= 1 + (s.sizeClass >= 2 ? 1 : 0) + (s.sizeClass >= 4 ? 1 : 0) || !bp.nacelles.isEmpty)
        }
        #expect(abs(ShipHullGenerator.sleekness(Self.stats(price: 0, tech: 0)) - 0.08) < 1e-12)
        #expect(abs(ShipHullGenerator.sleekness(Self.stats(price: 2, tech: 5)) - 0.54) < 1e-12)
        #expect(ShipHullGenerator.sleekness(Self.stats(price: 5, tech: 7)) == 1)
        #expect(ShipHullGenerator.cargoModules(Self.stats(bays: 35)) == 3 && ShipHullGenerator.cargoModules(Self.stats(bays: 200)) == 6)
        let s = Self.stats(bays: 30, price: 2, tech: 5)
        #expect(abs(ShipHullGenerator.beam(s, archetype: .courier) - (0.100 + 0.0009 * 30) * (1.08 - 0.22 * 0.54) * (1.12 - 0.05 * 2)) < 1e-12)
        #expect(ShipHullGenerator.beam(Self.stats(bays: 80, price: 0, tech: 0), archetype: .hauler) <= 0.24)
    }

    @Test("ART-010 archetypes follow the statistics; the variant picks planform, wing, nacelle and livery families")
    func archetypes() {
        #expect(ShipArchetype.of(Self.stats(bays: 40, weapons: 1)) == .hauler)
        #expect(ShipArchetype.of(Self.stats(bays: 40, weapons: 2, size: 1)) == .interceptor)
        #expect(ShipArchetype.of(Self.stats(bays: 60, weapons: 3)) == .gunship)
        #expect(ShipArchetype.of(Self.stats(bays: 10, weapons: 2, size: 0)) == .interceptor)
        #expect(ShipArchetype.of(Self.stats(bays: 30, weapons: 2, size: 3)) == .cruiser)
        #expect(ShipArchetype.of(Self.stats(bays: 20, weapons: 1, size: 2)) == .courier)
        let expected: [ShipArchetype] = [.courier, .courier, .courier, .interceptor, .courier, .hauler, .gunship, .cruiser, .hauler, .gunship]
        #expect(ShipArtKind.buyable.map { ShipArchetype.of(ShipArtStats.standard($0)) } == expected)
        // A hauler is a cab, a neck and a long cargo body; an interceptor is a narrow dart.
        let hauler = ShipHullGenerator.make(ShipArtStats.standard(.termite), variant: 0)
        #expect(hauler.archetype == .hauler && hauler.features.contains(.cargoModules(6)))
        let dart = ShipHullGenerator.make(ShipArtStats.standard(.mosquito), variant: 0)
        #expect(dart.archetype == .interceptor && !dart.wings.isEmpty)
        #expect(ShipHullGenerator.beam(ShipArtStats.standard(.mosquito), archetype: .interceptor)
            < ShipHullGenerator.beam(ShipArtStats.standard(.termite), archetype: .hauler) * 0.6)
        // The largest haulers carry containers outside a spine; smaller ones have an integral hold.
        #expect(ShipHullGenerator.isSpineFreighter(ShipArtStats.standard(.termite)) && !ShipHullGenerator.isSpineFreighter(ShipArtStats.standard(.beetle)))
        #expect(hauler.cargoReach == ShipHullGenerator.spineCargoReach(beam: ShipHullGenerator.beam(ShipArtStats.standard(.termite), archetype: .hauler)))
        let f = ShipHullGenerator.Families(variant: 0x0203_0102)
        #expect(f.planform == 2 && f.wing == 1 && f.nacelle == 0x0203 % 3 && f.livery == 2)
        // The families change the hull: over 24 variants one set of statistics gives many different silhouettes.
        let s = ShipArtStats.standard(.gnat)
        let shapes = Set((0..<24).map { Self.allPaths(ShipHullGenerator.make(s, variant: ArtSeed.mix(99, UInt64($0)))) })
        #expect(shapes.count >= 12)
        // The variant of a kind is keyed by its id and nothing else.
        #expect(ShipArtInput(kind: .gnat).blueprint == ShipHullGenerator.make(s, variant: ArtSeed.kind(.gnat)))
    }

    @Test("ART-011 special ships: the organic monster, the bottle, and four built warships fitted from their statistics")
    func specials() {
        let monster = ShipArtInput(kind: .spaceMonster).blueprint
        #expect(monster.features.contains(.tentacles(6)) && monster.features.contains(.eyes(3)) && monster.organicSeed == ArtSeed.kind(.spaceMonster))
        #expect(monster.engines.isEmpty && monster.cockpit.style == .none)
        let bottle = ShipArtInput(kind: .bottle).blueprint
        #expect(bottle.isGlassHull && bottle.features.contains(.cork) && bottle.features.contains(.scroll) && bottle.engines.isEmpty)
        #expect(ShipArtInput(kind: .dragonfly).blueprint.features.contains(.shieldRing))
        #expect(ShipArtInput(kind: .mantis).blueprint.features.contains(.liveryBands(3)))
        let disc = ShipArtInput(kind: .scarab).blueprint
        #expect(disc.plating == 5 && disc.features.contains(.armour(5)) && disc.wings.isEmpty)
        let dreadnought = ShipArtInput(kind: .scorpion).blueprint
        #expect(dreadnought.features.contains(.spine(5)) && dreadnought.features.contains(.broadsides(3)) && dreadnought.livery.primary == .crimson)
        for kind in [ShipArtKind.dragonfly, .mantis, .scarab, .scorpion] {
            let s = ShipArtStats.standard(kind)
            let bp = ShipArtInput(kind: kind).blueprint
            #expect(bp.symmetric && bp.archetype == nil && !bp.engines.isEmpty, "\(kind)")
            #expect(bp.features.contains(.hardpoints(slots: s.weaponSlots, installed: Array(repeating: -1, count: s.weaponSlots))), "\(kind)")
            if s.shieldSlots > 0 { #expect(bp.features.contains(.shieldEmitters(slots: s.shieldSlots, installed: s.shieldSlots))) }
            // More weapons on the same hull show as more hardpoints.
            var armed = s
            armed.weaponSlots += 1
            #expect(Self.allPaths(ShipArtInput(kind: kind, stats: armed).blueprint) != Self.allPaths(bp))
        }
        for kind in ShipArtKind.buyable + [.custom] { #expect(ShipSpecials.blueprint(kind, stats: .standard(kind)) == nil) }
    }

    static func allPaths(_ bp: ShipBlueprint) -> String {
        ShipGeometry.make(bp).parts.map { $0.path.description }.joined(separator: "|")
    }

    @Test("ART-012 a custom ship is the generator's hull for its statistics in the yard livery; every statistic changes it")
    func custom() {
        let base = ShipArtStats.standard(.custom)
        func paths(_ s: ShipArtStats, variant: UInt64? = nil) -> String { Self.allPaths(ShipArtInput(kind: .custom, stats: s, variant: variant).blueprint) }
        #expect(paths(base) == paths(base))
        #expect(ShipArtInput(kind: .custom).blueprint.livery.primary == .brass)
        let changes: [(String, (inout ShipArtStats) -> Void)] = [
            ("weapons", { $0.weaponSlots += 1 }), ("shields", { $0.shieldSlots += 1 }), ("gadgets", { $0.gadgetSlots += 1 }),
            ("crew", { $0.crewQuarters += 1 }), ("cargo", { $0.cargoBays += 20 }), ("fuel", { $0.fuelTanks += 6 }),
            ("hull", { $0.hullStrength += 100 }), ("size", { $0.sizeClass += 2 }), ("price", { $0.priceTier += 2 }), ("tech", { $0.techTier -= 3 })
        ]
        for (name, change) in changes {
            var s = base
            change(&s)
            #expect(paths(s) != paths(base), "\(name)")
        }
        // The designer's hull style is a variant, not a borrowed shape.
        #expect(paths(base, variant: ArtSeed.kind(.hornet)) != paths(base, variant: ArtSeed.kind(.flea)))
    }

    @Test("ART-081 statistics shape the hull monotonically")
    func monotonic() {
        func area(_ n: Int, _ bp: ShipBlueprint) -> Double {
            let r = ShipFeatures.cargoRects(n, bp: bp)
            var box = CGRect.null
            for p in r.pairs { box = box.union(p).union(CGRect(x: p.minX, y: 1 - p.maxY, width: p.width, height: p.height)) }
            if let k = r.keel { box = box.union(k) }
            return box.isNull ? 0 : box.width * box.height
        }
        var bases = Self.reference.filter { $0.cargoBays > 0 || $0.weaponSlots > 0 }
        bases.append(Self.stats(bays: 5, weapons: 0, shields: 0, gadgets: 0, hull: 20, size: 0, price: 0, tech: 0))
        for base in bases {
            // Per archetype run: never smaller with +10 bays, larger with +20 (below 60), and the beam never shrinks.
            var areas: [Double] = [], beams: [Double] = [], kinds: [ShipArchetype] = [], spines: [Bool] = []
            for bays in stride(from: 0, through: 80, by: 10) {
                var s = base
                s.cargoBays = bays
                let archetype = ShipArchetype.of(s)
                let bp = ShipHullGenerator.make(s, variant: 5)
                areas.append(area(ShipHullGenerator.cargoModules(s), bp))
                beams.append(ShipHullGenerator.beam(s, archetype: archetype))
                kinds.append(archetype)
                spines.append(ShipHullGenerator.isSpineFreighter(s))
                let i = areas.count - 1
                if i >= 1, kinds[i] == kinds[i - 1] {
                    #expect(areas[i] >= areas[i - 1] - 1e-12, "\(bays) bays: the cargo section never shrinks")
                    #expect(beams[i] >= beams[i - 1])
                }
                if i >= 2, bays <= 60, kinds[i] == kinds[i - 2] {
                    #expect(areas[i] > areas[i - 2], "\(bays) bays: +20 bays enlarge the cargo section")
                }
            }
            for weapons in 0...8 {
                var s = base
                s.weaponSlots = weapons
                let bp = ShipHullGenerator.make(s, variant: 5)
                #expect(ShipFeatures.hardpointMounts(min(6, weapons), bp: bp).count == min(6, weapons))
            }
            var plating = -1, plate = CGRect.zero
            for hull in stride(from: 10, through: 500, by: 10) {
                var s = base
                s.hullStrength = hull
                let bp = ShipHullGenerator.make(s, variant: 5)
                #expect(bp.plating >= plating)
                if bp.plating > plating, bp.plating > 0 {
                    let r = ShipFeatures.armourPlate(bp.plating, bp: bp)
                    #expect(r.width > plate.width && r.height > plate.height, "armour level \(bp.plating)")
                    plate = r
                }
                plating = bp.plating
            }
            #expect(plating == 5)
            var engines = 0
            for size in 0...5 {
                var s = base
                s.sizeClass = size
                // Count within one archetype and nacelle family, so only the size changes.
                let layout = ShipHullGenerator.engines(.courier, family: 0, beam: 0.1, s: s, wings: [])
                let n = layout.engines.reduce(0) { $0 + ($1.yOffset > 0 ? 2 : 1) }
                #expect(n >= engines)
                engines = n
            }
            #expect(engines == 3)
        }
        var sleek = -1.0
        for tier in 0...5 {
            let s = Self.stats(price: tier, tech: 2 + tier)
            #expect(ShipHullGenerator.sleekness(s) > sleek)
            sleek = ShipHullGenerator.sleekness(s)
        }
        let cheap = ShipHullGenerator.make(Self.stats(price: 0, tech: 0), variant: 4)
        let fine = ShipHullGenerator.make(Self.stats(price: 5, tech: 7), variant: 4)
        #expect((cheap.hull.first?.halfWidth ?? 0) > 0 && fine.hull.first?.halfWidth == 0)
    }

    @Test("ART-082 hardpoints, emitters and sensors show what is installed")
    func equipment() {
        var s = Self.stats(weapons: 3, shields: 2, gadgets: 3, size: 3)
        func parts(_ s: ShipArtStats) -> [ShipPart] { ShipGeometry.make(ShipHullGenerator.make(s, variant: 3)).parts }
        func barrels(_ s: ShipArtStats) -> [CGRect] {
            let bp = ShipHullGenerator.make(s, variant: 3)
            let all = ShipFeatures.hardpoints(slots: s.weaponSlots, installed: s.weapons ?? Array(repeating: -1, count: s.weaponSlots), bp: bp)
            return all.filter { $0.role == .dark }.map(\.path.boundingRect)
        }
        #expect(barrels(s).count == 3, "unknown equipment: every slot has a standard barrel")
        s.weapons = []
        #expect(barrels(s).isEmpty)
        let mounts = ShipFeatures.hardpoints(slots: 3, installed: [], bp: ShipHullGenerator.make(s, variant: 3))
        #expect(mounts.count == 3 && mounts.allSatisfy { $0.role == .secondary })
        var counts: [Int] = []
        for n in 1...3 {
            s.weapons = Array(repeating: 0, count: n)
            counts.append(barrels(s).count)
        }
        #expect(counts == [1, 2, 3])
        s.weapons = [0]
        let pulse = barrels(s)[0]
        s.weapons = [2]
        let military = barrels(s)[0]
        #expect(military.width > pulse.width && military.height > pulse.height)
        // Emitters: one per slot, the installed ones lit.
        let bp = ShipHullGenerator.make(s, variant: 3)
        let none = ShipFeatures.shieldEmitters(slots: 2, installed: 0, bp: bp), one = ShipFeatures.shieldEmitters(slots: 2, installed: 1, bp: bp)
        #expect(none.count == 4 && none.filter { $0.role == .glow }.isEmpty && one.filter { $0.role == .glow }.count == 1)
        s.gadgets = [1]
        let few = parts(s).count
        s.gadgets = [1, 2, 3]
        #expect(parts(s).count > few)
    }

    @Test("ART-087 no ship fitting is named for insect anatomy")
    func noInsects() throws {
        let dir = ArtSnapshot.packageRoot.appendingPathComponent("Sources/ParsecArt/Ships")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        #expect(files.count >= 8)
        #expect(!files.contains { $0.lastPathComponent == "ShipBlueprints.swift" })
        let banned = ["antenna", "proboscis", "abdomen", "elytra", "mandible", "stinger", "pincer", "raptorial", "rearleg", "curledtail",
                      "hornram", "thorax", "compound"]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8).lowercased()
            for word in banned { #expect(!text.contains(word), "\(file.lastPathComponent) mentions \(word)") }
        }
    }

    @Test("ART-088 the reference table has the 17 kinds' statistics")
    func referenceTable() {
        #expect(Self.reference.count == 17)
        let flea = ShipArtStats.standard(.flea), wasp = ShipArtStats.standard(.wasp), beetle = ShipArtStats.standard(.beetle)
        #expect(flea.sizeClass == 0 && flea.cargoBays == 10 && flea.weaponSlots == 0 && flea.hullStrength == 25 && flea.priceTier == 0 && flea.techTier == 4)
        #expect(wasp.sizeClass == 4 && wasp.weaponSlots == 3 && wasp.hullStrength == 200 && wasp.priceTier == 5 && wasp.techTier == 7)
        #expect(beetle.cargoBays == 50 && beetle.weaponSlots == 0 && beetle.crewQuarters == 3)
        let custom = ShipArtStats.standard(.custom)
        #expect(custom.sizeClass == 2 && custom.cargoBays == 20 && custom.weaponSlots == 1 && custom.hullStrength == 100)
    }

    @Test("ART-089 pmart sheet has ships and endings pages")
    func sheetPages() throws {
        let root = ArtSnapshot.packageRoot.appendingPathComponent("Sources/pmart")
        let sheet = try String(contentsOf: root.appendingPathComponent("ContactSheet.swift"), encoding: .utf8)
        #expect(sheet.contains("case \"ships\": image = IconExport.render(ShipSheet.sheet") && sheet.contains("case \"endings\""))
        let ships = try String(contentsOf: root.appendingPathComponent("ShipSheet.swift"), encoding: .utf8)
        #expect(ships.contains("ShipArtKind.allCases") && ships.contains("width: 44") && ships.contains("width: 240") && ships.contains("facing: .left"))
    }

    @Test("ART-014 relative mode: k × the reference box, bounded by both axes; the size-4 to size-0 width ratio is 0.9/0.5")
    func relativeScale() {
        let size = CGSize(width: 200, height: 200)
        for kind in [ShipArtKind.wasp, .gnat, .beetle] {
            // Equal statistics apart from the size class; the engines sit inside the hull, so the silhouette's length is the hull's.
            func width(_ sizeClass: Int, _ frame: CGSize) -> Double {
                var s = ShipArtStats.standard(kind)
                s.sizeClass = sizeClass
                let input = ShipArtInput(kind: kind, stats: s, variant: 0)
                let b = ShipGeometry.make(input.blueprint).bounds
                return b.width * ShipArtLayout.scale(bounds: b, size: frame, mode: .relative, sizeClass: sizeClass)
            }
            let ratio = width(4, size) / width(0, size) * (ShipGeometry.make(ShipArtInput(kind: kind, sizeClass: 0, variant: 0).blueprint).bounds.width
                / ShipGeometry.make(ShipArtInput(kind: kind, sizeClass: 4, variant: 0).blueprint).bounds.width)
            #expect(abs(ratio / (0.9 / 0.5) - 1) < 0.03, "\(kind) ratio \(ratio)")
            // A wide, short pane gives the ship the height it has: the same size as in a square pane of that height.
            #expect(abs(width(2, CGSize(width: 600, height: 200)) - width(2, CGSize(width: 400, height: 200))) < 1e-9)
            #expect(width(2, CGSize(width: 600, height: 200)) > width(2, CGSize(width: 200, height: 200)), "a square pane is bounded by its width")
            #expect(width(2, CGSize(width: 600, height: 240)) > width(2, CGSize(width: 600, height: 120)))
        }
        #expect(ShipArtLayout.referenceBox == CGSize(width: 0.90, height: 0.56))
        let box = CGRect(x: 0.1, y: 0.3, width: 0.85, height: 0.4)
        for sizeClass in 0...5 {
            let relative = ShipArtLayout.scale(bounds: box, size: size, mode: .relative, sizeClass: sizeClass)
            #expect(relative <= ShipArtLayout.scale(bounds: box, size: size, mode: .fit, sizeClass: sizeClass))
            let k = 0.5 + 0.1 * Double(sizeClass)
            #expect(abs(relative - min(k * 200 / (0.90 * 1.16), 200 / (0.85 * 1.16))) < 1e-9)
        }
        let fit = Self.mask(.flea, mode: .fit, sizeClass: 0, size: size).maskWidth
        #expect(fit > Self.mask(.flea, mode: .relative, sizeClass: 0, size: size).maskWidth)
    }

    @Test("ART-015 facing left mirrors the geometry but not the light")
    func facing() {
        for kind in ShipArtKind.allCases {
            let right = Self.mask(kind, facing: .right).mirrored, left = Self.mask(kind, facing: .left)
            // Exact geometry mirror; the Core Graphics anti-aliasing of curves may differ by a few levels on edge pixels.
            let worst = stride(from: 3, to: left.bytes.count, by: 4).map { abs(Int(left.bytes[$0]) - Int(right.bytes[$0])) }.max() ?? 0
            #expect(worst <= 8, "\(kind): \(worst)")
        }
        let size = CGSize(width: 192, height: 128)
        let r = ArtSnapshot.render(ShipArt(ShipArtInput(kind: .hornet, facing: .right)), size: size)
        let l = ArtSnapshot.render(ShipArt(ShipArtInput(kind: .hornet, facing: .left)), size: size)
        #expect(l.bytes != r.mirrored.bytes)
    }

    @Test("ART-016 engine glow flickers ±12% over 0.4 s, steady under Reduce Motion, off when disabled")
    func glow() {
        let values = stride(from: 0.0, to: 0.4, by: 0.02).map { ShipRenderer.glowIntensity(phase: $0, reduceMotion: false) }
        #expect(abs((values.max() ?? 0) - 1.12) < 0.01 && abs((values.min() ?? 0) - 0.88) < 0.01)
        #expect(abs(ShipRenderer.glowIntensity(phase: 0.1, reduceMotion: false) - ShipRenderer.glowIntensity(phase: 0.5, reduceMotion: false)) < 1e-9)
        #expect(ShipRenderer.glowIntensity(phase: 0.1, reduceMotion: true) == 1)
        let size = CGSize(width: 192, height: 128)
        let reduce = ArtAccessibility(reduceMotion: true)
        #expect(ArtSnapshot.render(ShipArt(ShipArtInput(kind: .wasp, phase: 0.1)), size: size)
            != ArtSnapshot.render(ShipArt(ShipArtInput(kind: .wasp, phase: 0.3)), size: size))
        #expect(ArtSnapshot.render(ShipArt(ShipArtInput(kind: .wasp, phase: 0.1, accessibility: reduce)), size: size)
            == ArtSnapshot.render(ShipArt(ShipArtInput(kind: .wasp, phase: 0.3, accessibility: reduce)), size: size))
        #expect(ArtSnapshot.render(ShipArt(ShipArtInput(kind: .wasp, disabled: true, phase: 0.1)), size: size)
            == ArtSnapshot.render(ShipArt(ShipArtInput(kind: .wasp, disabled: true, phase: 0.3)), size: size))
    }

    @Test("ART-017 the shield bubble's coverage grows with the fraction; nothing at nil or zero")
    func shieldBubble() {
        let size = CGSize(width: 192, height: 128)
        func render(_ f: Double?, _ a11y: ArtAccessibility = .standard) -> ArtPixels {
            ArtSnapshot.render(ShipArt(ShipArtInput(kind: .mosquito, shield: f.map { ShieldDisplay(kind: .energy, fraction: $0) }, accessibility: a11y)),
                               size: size)
        }
        let none = render(nil)
        #expect(render(0) == none)
        let sums = [0.1, 0.4, 0.7, 1.0].map { render($0).alphaSum }
        #expect(zip(sums, sums.dropFirst()).allSatisfy { $0 < $1 }, "\(sums)")
        #expect(sums[0] > none.alphaSum)
        let rt = [0.2, 0.9].map { render($0, ArtAccessibility(reduceTransparency: true)).alphaSum }
        #expect(rt[0] < rt[1] && rt[1] < sums[3])
        #expect(render(0.5, ArtAccessibility(differentiateWithoutColor: true)) != render(0.5))
    }

    @Test("ART-018 the scorch covers 1 − hull of the hull area within ±3 points; destroyed ships are not drawn")
    func scorch() {
        let size = CGSize(width: 256, height: 256)
        for kind in ShipArtKind.allCases {
            let hull = ArtSnapshot.render(ShipScorchMask(input: ShipArtInput(kind: kind), scorch: false), size: size, scale: 1).alphaSum
            for h in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let s = ArtSnapshot.render(ShipScorchMask(input: ShipArtInput(kind: kind, hullFraction: h), scorch: true), size: size, scale: 1).alphaSum
                let covered = s / hull
                #expect(abs(covered - (1 - h)) <= 0.03, "\(kind) hull \(h): \(covered)")
            }
        }
        let gone = ArtSnapshot.render(ShipArt(ShipArtInput(kind: .gnat, hullFraction: 0)), size: CGSize(width: 96, height: 64))
        #expect(gone.coverage() == 0)
        let size2 = CGSize(width: 192, height: 128)
        let dwc = ArtSnapshot.render(ShipArt(ShipArtInput(kind: .gnat, hullFraction: 0.4, accessibility: ArtAccessibility(differentiateWithoutColor: true))),
                                     size: size2)
        #expect(dwc != ArtSnapshot.render(ShipArt(ShipArtInput(kind: .gnat, hullFraction: 0.4)), size: size2))
    }

    @Test("ART-019 disabled desaturates and adds sparks; cloaked is a faint dashed outline")
    func disabledCloaked() {
        let size = CGSize(width: 192, height: 128)
        let normal = ArtSnapshot.render(ShipArt(ShipArtInput(kind: .bumblebee)), size: size)
        let disabled = ArtSnapshot.render(ShipArt(ShipArtInput(kind: .bumblebee, disabled: true)), size: size)
        let cloaked = ArtSnapshot.render(ShipArt(ShipArtInput(kind: .bumblebee, cloaked: true)), size: size)
        #expect(disabled != normal)
        #expect(cloaked.alphaSum < normal.alphaSum * 0.3)
        #expect(cloaked.alphaSum > 0)
    }

    @Test("ART-060 UI-ENC-101 every kind, both facings and schemes, three states: byte-identical twice and non-empty")
    func shipDeterminism() {
        let size = CGSize(width: 240, height: 160)
        let states: [(String, (ShipArtKind, ShipFacing) -> ShipArtInput)] = [
            ("full", { ShipArtInput(kind: $0, facing: $1, hullFraction: 1, shield: ShieldDisplay(kind: .lightning, fraction: 1)) }),
            ("half", { ShipArtInput(kind: $0, facing: $1, hullFraction: 0.5) }),
            ("disabled", { ShipArtInput(kind: $0, facing: $1, hullFraction: 0.3, disabled: true) }),
        ]
        for kind in ShipArtKind.allCases {
            for facing in [ShipFacing.right, .left] {
                for scheme in [ColorScheme.light, .dark] {
                    for (name, make) in states {
                        let (a, b) = ArtSnapshot.twice(ShipArt(make(kind, facing)), size: size, scheme: scheme)
                        #expect(a.fingerprint == b.fingerprint, "\(kind) \(facing) \(scheme) \(name)")
                        #expect(a.isNonEmpty(), "\(kind) \(facing) \(scheme) \(name): \(a.coverage()) \(a.distinctColors)")
                    }
                }
            }
        }
    }
}
