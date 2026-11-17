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

    @Test("ART-008 ShipArtInput clamps size class and fractions; custom kinds use the custom blueprint")
    func input() {
        let i = ShipArtInput(kind: .wasp, sizeClass: 9, hullFraction: 1.4, shield: ShieldDisplay(kind: .reflective, fraction: -1))
        #expect(i.sizeClass == 5 && i.hullFraction == 1 && i.shield?.fraction == 0)
        let custom = ShipArtInput(kind: .custom, custom: .standard)
        #expect(custom.blueprint == ShipBlueprints.custom(.standard))
        #expect(ShipArtInput(kind: .gnat).blueprint == ShipBlueprints.standard[1])
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

    @Test("ART-009 the shape grammar: symmetric blueprints equal their own mirror image")
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
        #expect(!ShipBlueprints.blueprint(.spaceMonster).symmetric && !ShipBlueprints.blueprint(.scorpion).symmetric)
    }

    @Test("ART-010 buyable designs carry their motifs")
    func buyableMotifs() {
        let s = ShipBlueprints.standard
        #expect(s.count == 10)
        #expect(s[0].features.contains(.skids) && s[0].wings.isEmpty && s[0].engines.count == 1 && s[0].cockpit.style == .bubble)
        #expect(s[1].features.contains(.antennae) && !s[1].wings.isEmpty)
        #expect(s[2].features.contains(.abdomenLight))
        #expect(s[3].features.contains(.proboscis) && s[3].features.contains(.hardpoints(2)) && s[3].wings[0].sweep == 0)
        #expect(s[4].features.contains(.stripes(3)) && s[4].wings[0].rounded)
        #expect(s[5].features.contains(.elytraSeam) && s[5].wings.isEmpty && s[5].livery.primary == .rust)
        #expect(s[6].features.contains(.stinger) && s[6].wings[0].sweep < 0 && s[6].features.contains(.hardpoints(3)))
        #expect(s[7].features.contains(.rearLegs) && s[7].cockpit.style == .slit)
        #expect(s[8].features.contains(.segments(3)) && s[8].features.contains(.mandibles))
        #expect(s[9].features.contains(.waist) && s[9].features.contains(.stinger) && s[9].livery.primary == .nightBlack)
    }

    @Test("ART-011 special designs carry their motifs")
    func specialMotifs() {
        let sp = ShipBlueprints.special
        #expect(sp.count == 6)
        #expect(sp[.spaceMonster]?.features.contains(.tentacles(6)) == true && sp[.spaceMonster]?.organicSeed == ArtSeed.kind(.spaceMonster))
        #expect(sp[.dragonfly]?.wings.first?.count == 2 && sp[.dragonfly]?.wings.first?.glass == true && sp[.dragonfly]?.cockpit.style == .compound)
        #expect(sp[.mantis]?.features.contains(.raptorialArms) == true)
        #expect(sp[.scarab]?.features.contains(.hornRam) == true && sp[.scarab]?.wings.isEmpty == true)
        #expect(sp[.bottle]?.isGlassHull == true && sp[.bottle]?.features.contains(.cork) == true && sp[.bottle]?.engines.isEmpty == true)
        #expect(sp[.scorpion]?.features.contains(.pincers) == true && sp[.scorpion]?.features.contains(.curledTail(5)) == true)
    }

    static func allPaths(_ bp: ShipBlueprint) -> String {
        ShipGeometry.make(bp).parts.map { $0.path.description }.joined(separator: "|")
    }

    @Test("ART-012 custom ships are modular and deterministic; every slot count changes the path")
    func custom() {
        let base = CustomShipParams.standard
        #expect(Self.allPaths(ShipBlueprints.custom(base)) == Self.allPaths(ShipBlueprints.custom(base)))
        let variants: [(String, (inout CustomShipParams) -> Void)] = [
            ("weapons", { $0.weaponSlots += 1 }), ("shields", { $0.shieldSlots += 1 }), ("gadgets", { $0.gadgetSlots += 1 }),
            ("crew", { $0.crewQuarters += 1 }), ("cargo", { $0.cargoBays += 20 }), ("base", { $0.base = .hornet }),
        ]
        for (name, change) in variants {
            var p = base
            change(&p)
            #expect(Self.allPaths(ShipBlueprints.custom(p)) != Self.allPaths(ShipBlueprints.custom(base)), "\(name)")
        }
        #expect(ShipBlueprints.custom(base).livery.primary == .brass)
        let flea = CustomShipParams(sizeClass: 1, weaponSlots: 1, shieldSlots: 0, gadgetSlots: 0, crewQuarters: 1, fuelTanks: 10, cargoBays: 10,
                                    hullStrength: 50, base: .flea)
        #expect(ShipBlueprints.custom(flea).hull == ShipBlueprints.standard[0].hull)
    }

    @Test("ART-014 relative mode scales by 0.5 + 0.1 × size class; huge/tiny width ratio is 0.9/0.5")
    func relativeScale() {
        let size = CGSize(width: 200, height: 200)
        for kind in [ShipArtKind.wasp, .gnat, .beetle] {
            let tiny = Self.mask(kind, mode: .relative, sizeClass: 0, size: size).maskWidth
            let huge = Self.mask(kind, mode: .relative, sizeClass: 4, size: size).maskWidth
            let ratio = Double(huge) / Double(tiny)
            #expect(abs(ratio / (0.9 / 0.5) - 1) < 0.03, "\(kind) ratio \(ratio)")
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
