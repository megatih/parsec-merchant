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

    @Test("ART-SHIP-005 ART-SHIP-009 silhouettes: the ten buyable types and five special designs are pairwise below IoU 0.85")
    func distinctSilhouettes() {
        let kinds = ShipArtKind.buyable + [.spaceMonster, .dragonfly, .mantis, .scarab, .scorpion]
        let masks = kinds.map { (kind: $0, pixels: Self.mask($0)) }
        var worst = (0.0, "")
        for m in masks {
            let c = m.pixels.coverage(threshold: 127)
            #expect(c >= 0.04 && c <= 0.85, "\(m.kind) covers \(c)")
        }
        for i in masks.indices {
            for j in masks.indices where j > i {
                let v = ArtSnapshot.iou(masks[i].pixels.mask, masks[j].pixels.mask)
                if v > worst.0 { worst = (v, "\(masks[i].kind)/\(masks[j].kind)") }
                #expect(v < 0.85, "\(masks[i].kind) vs \(masks[j].kind): IoU \(v)")
            }
        }
        print("ART-SHIP-005 worst pair \(worst.1) IoU \(worst.0)")
    }

    @Test("ART-007 17 art kinds in ShipType order; ten buyable")
    func kinds() {
        #expect(ShipArtKind.allCases.count == 17)
        #expect(ShipArtKind.allCases.map(\.rawValue) == Array(0..<17))
        #expect(ShipArtKind.custom.rawValue == 15 && ShipArtKind.scorpion.rawValue == 16)
        #expect(ShipArtKind.buyable.count == 10 && ShipArtKind.buyable.allSatisfy(\.isBuyable))
    }

    @Test("ART-008 ART-SHIP-002 ShipArtInput carries ShipArtStats: clamped, with price and tech tiers and optional installed equipment")
    func input() {
        let i = ShipArtInput(kind: .wasp, sizeClass: 9, hullFraction: 1.4, shield: ShieldDisplay(kind: .reflective, fraction: -1))
        #expect(i.sizeClass == 5 && i.stats.sizeClass == 5 && i.hullFraction == 1 && i.shield?.fraction == 0)
        #expect(ShipArtInput(kind: .gnat).stats == ShipArtStats.standard(.gnat))
        #expect(ShipArtStats.priceThresholds == [5000, 20000, 50000, 90000, 200_000])
        #expect([0, 4999, 5000, 60000, 500_000].map(ShipArtStats.priceTier(price:)) == [0, 0, 1, 3, 5])
        let s = ShipArtStats(sizeClass: -3, cargoBays: -1, weaponSlots: 2, shieldSlots: 1, gadgetSlots: 0, crewQuarters: 1, fuelTanks: 14,
                             hullStrength: 100, priceTier: 9, techTier: 12, weapons: [0, 2])
        #expect(s.sizeClass == 0 && s.cargoBays == 0 && s.priceTier == 5 && s.techTier == 7 && s.weapons == [0, 2] && s.shields == nil)
        // ART-SHIP-002: a designed ship in a class's style is that class's design for the same statistics.
        let a = ShipArtInput(kind: .hornet, liverySeed: 7).geometry.description
        let b = ShipArtInput(kind: .custom, stats: ShipArtStats.standard(.hornet), liverySeed: 7, style: .hornet).geometry.description
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

    @Test("ART-087 no ship fitting is named for insect anatomy")
    func noInsects() throws {
        var files: [URL] = []
        for folder in ["Sources/ParsecArt/Ships", "Sources/ParsecArt/Ships2"] {
            let dir = ArtSnapshot.packageRoot.appendingPathComponent(folder)
            files += try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        }
        #expect(files.count >= 8)
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

    @Test("ART-089 ART-SHIP-012 pmart sheet has ships, liveries, fittings and endings pages")
    func sheetPages() throws {
        let root = ArtSnapshot.packageRoot.appendingPathComponent("Sources/pmart")
        let sheet = try String(contentsOf: root.appendingPathComponent("ContactSheet.swift"), encoding: .utf8)
        #expect(sheet.contains("case \"ships\": image = IconExport.render(ShipSheet.sheet") && sheet.contains("case \"endings\""))
        #expect(sheet.contains("case \"liveries\"") && sheet.contains("case \"fittings\""))
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
                let b = ShipArtInput(kind: kind, stats: s).geometry.bounds
                return b.width * ShipArtLayout.scale(bounds: b, size: frame, mode: .relative, sizeClass: sizeClass)
            }
            func bounds(_ sizeClass: Int) -> CGRect {
                var s = ShipArtStats.standard(kind)
                s.sizeClass = sizeClass
                return ShipArtInput(kind: kind, stats: s).geometry.bounds
            }
            let ratio = width(4, size) / width(0, size) * (bounds(0).width / bounds(4).width)
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
