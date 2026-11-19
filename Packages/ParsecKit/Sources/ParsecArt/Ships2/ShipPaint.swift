// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-SHIP-006/008: paints a livery on a built hull: the pattern, the role's marks, the registry and the wear.
/// Paint is drawn as flat, non-solid parts clipped to the painted modules, so it never changes the silhouette.
enum ShipPaint {
    static func apply(_ b: inout ShipBuilder) {
        pattern(&b)
        switch b.livery.role {
        case .police: police(&b)
        case .pirate: pirate(&b)
        default: break
        }
        registry(&b)
        wear(&b)
    }

    /// A shape clipped to the painted modules.
    static func on(_ b: ShipBuilder, _ shape: Path) -> Path { shape.intersection(b.painted) }

    static func pattern(_ b: inout ShipBuilder) {
        let f = PaintFrame(b), l = b.livery
        let habitatMid = (f.habitat.lowerBound + f.habitat.upperBound) / 2, h = b.plan.half(at: habitatMid)
        switch l.pattern {
        case .noseCap:
            let x = f.nose.lowerBound + (f.nose.upperBound - f.nose.lowerBound) * 0.45
            b.add(on(b, Path(CGRect(x: x, y: 0, width: 1, height: 1))), .accent, solid: false, color: l.accent, flat: true, tag: "pattern")
        case .beamBand:
            b.add(on(b, Path(CGRect(x: habitatMid - 0.018, y: 0, width: 0.036, height: 1))), .accent, solid: false, color: l.accent, flat: true, tag: "pattern")
        case .twinStripes:
            for side in [-1.0, 1.0] {
                b.add(on(b, Path(CGRect(x: f.engine.lowerBound, y: 0.5 + side * h * 0.40 - 0.004, width: 1, height: 0.008))), .accent, solid: false,
                      color: l.accent, flat: true, tag: "pattern")
            }
        case .panelBlocks:
            var rng = ArtRandom(seed: l.detailSeed)
            for range in [f.habitat, f.engine] {
                let x = range.lowerBound + (range.upperBound - range.lowerBound) * rng.range(0.15...0.45)
                let side: Double = rng.unit() < 0.5 ? -1 : 1
                b.add(on(b, Path(CGRect(x: x, y: side < 0 ? 0 : 0.5, width: (range.upperBound - range.lowerBound) * 0.38, height: 0.5))), .accent,
                      solid: false, color: l.accent, flat: true, tag: "pattern")
            }
        case .tailChevron:
            let x0 = f.engine.lowerBound + 0.02, x1 = f.engine.upperBound + 0.04, e = 0.5
            b.add(on(b, ArtGeometry.polygon([CGPoint(x: x0, y: 0.5 - e), CGPoint(x: x0 + 0.03, y: 0.5 - e), CGPoint(x: x1, y: 0.5), CGPoint(x: x0 + 0.03,
                y: 0.5 + e),
                                             CGPoint(x: x0, y: 0.5 + e), CGPoint(x: x1 - 0.03, y: 0.5)])), .accent, solid: false, color: l.accent, flat: true,
                  tag: "pattern")
        case .spineLine:
            let glass = Path(CGRect(x: f.nose.lowerBound + 0.008, y: 0.4, width: (f.nose.upperBound - f.nose.lowerBound) * 0.6, height: 0.2))
            let stripe = Path(CGRect(x: f.habitat.lowerBound, y: 0.5 - 0.007, width: 1, height: 0.014)).subtracting(glass)
            b.add(on(b, stripe), .accent, solid: false, color: l.accent, flat: true, tag: "pattern")
        case .checker:
            // ART-SHIP-008: two rows of alternating blue and white cells across the beam of the habitat.
            let cell = 0.022, x0 = habitatMid - cell
            let columns = Int((h * 2 / cell).rounded(.up))
            for row in 0..<2 {
                for column in 0..<columns {
                    let rect = CGRect(x: x0 + Double(row) * cell, y: 0.5 - h + Double(column) * cell, width: cell, height: min(cell,
                        0.5 + h - (0.5 - h + Double(column) * cell)))
                    let blue = (row + column) % 2 == 0
                    b.add(on(b, Path(rect)), .accent, solid: false, color: blue ? ShipLivery.policeBlue : ShipLivery.policeWhite, flat: true, tag: "checker")
                    b.checkerCells.append((rect, blue))
                }
            }
        }
    }

    /// The police shield insignia on the engine block and two blue beacons on the habitat.
    static func police(_ b: inout ShipBuilder) {
        let f = PaintFrame(b)
        let c = CGPoint(x: (f.engine.lowerBound + f.engine.upperBound) / 2 + 0.02, y: 0.5), r = min(0.030, max(0.014, f.engineHalf * 0.55))
        let shield = ArtGeometry.closedSpline([
            SplinePoint(c.x + r, c.y, sharp: true), SplinePoint(c.x + r * 0.2, c.y - r * 0.85), SplinePoint(c.x - r * 0.8, c.y - r * 0.80, sharp: true),
            SplinePoint(c.x - r * 0.8, c.y + r * 0.80, sharp: true), SplinePoint(c.x + r * 0.2, c.y + r * 0.85),
        ])
        b.add(shield, .accent, solid: false, color: ShipLivery.policeBlue, flat: true, tag: "insignia")
        b.add(ArtGeometry.star(center: CGPoint(x: c.x - r * 0.1, y: c.y), points: 5, outer: r * 0.48, inner: r * 0.20, rotation: 0), .accent, solid: false,
              color: ShipLivery.policeWhite, flat: true, tag: "insigniaStar")
        let x = f.habitat.upperBound - 0.012
        b.lights.append(ShipLight(position: CGPoint(x: x, y: 0.5 - f.habitatHalf * 0.5), kind: .beacon))
        b.lights.append(ShipLight(position: CGPoint(x: x, y: 0.5 + f.habitatHalf * 0.5), kind: .beacon))
    }

    /// Pirates: at least three mismatched salvage panels, jagged slash marks and a tally of kills; no registry.
    static func pirate(_ b: inout ShipBuilder) {
        let f = PaintFrame(b), l = b.livery
        var rng = ArtRandom(seed: ArtSeed.mix(l.detailSeed, 0x5041))
        let salvage = [ArtRGB(0.42, 0.40, 0.36), ArtRGB(0.30, 0.36, 0.40), ArtRGB(0.46, 0.33, 0.22), ArtRGB(0.36, 0.38, 0.28), ArtRGB(0.50, 0.48, 0.46)]
        for i in 0..<(3 + rng.int(0...2)) {
            let range = i % 2 == 0 ? f.habitat : f.engine
            let x = range.lowerBound + (range.upperBound - range.lowerBound) * rng.range(0.0...0.7)
            let y = 0.5 + rng.range(-1...0.4) * f.habitatHalf
            b.add(on(b, Path(CGRect(x: x, y: y, width: rng.range(0.025...0.05), height: rng.range(0.02...0.045)))), .secondary, solid: false,
                  color: salvage[rng.int(0...(salvage.count - 1))], flat: true, tag: "salvage")
        }
        let n = f.nose
        for i in 0..<2 {
            let x = n.lowerBound + 0.01 + Double(i) * 0.022
            b.add(on(b, ArtGeometry.polygon([CGPoint(x: x, y: 0.5 - f.habitatHalf), CGPoint(x: x + 0.010, y: 0.5 - f.habitatHalf), CGPoint(x: x + 0.022,
                y: 0.5 + f.habitatHalf),
                                             CGPoint(x: x + 0.012, y: 0.5 + f.habitatHalf)])), .accent, solid: false, color: l.accent, flat: true, tag: "slash")
        }
        for i in 0..<l.marking {
            let x = f.habitat.lowerBound + 0.008 + Double(i % 8) * 0.008, y = 0.5 + f.habitatHalf * (i < 8 ? 0.55 : 0.75)
            b.add(on(b, Path(CGRect(x: x, y: y, width: 0.003, height: 0.012))), .accent, solid: false, color: l.accent.shade(1.2), flat: true, tag: "tally")
        }
    }

    /// The registry: an abstract bar code on the engine block (never letters or digits). Traders wear it large; pirates none.
    static func registry(_ b: inout ShipBuilder) {
        let l = b.livery, f = PaintFrame(b)
        guard l.role != .pirate, l.role != .alien else { return }
        let scale = l.role == .trader ? 1.7 : 1.0
        let lum = 0.299 * l.secondary.r + 0.587 * l.secondary.g + 0.114 * l.secondary.b
        let ink = lum > 0.5 ? ArtRGB(0.08, 0.09, 0.11) : ArtRGB(0.92, 0.93, 0.94)
        var x = f.engine.lowerBound + 0.03
        let y = 0.5 + f.engineHalf * 0.22, height = min(0.016 * scale, max(0.006, f.engineHalf * 0.45))
        for bit in 0..<5 {
            let wide = (l.marking >> (bit % 4)) & 1 == 1
            let w = (wide ? 0.008 : 0.004) * scale
            if x + w < f.engine.upperBound + 0.05 {
                b.add(on(b, Path(CGRect(x: x, y: y, width: w, height: height))), .accent, solid: false, color: ink, flat: true, tag: "registry")
            }
            x += w + 0.004 * scale
        }
    }

    /// Wear: faded panels, replaced panels and soot behind the engine block, growing with the livery's wear.
    static func wear(_ b: inout ShipBuilder) {
        let l = b.livery, f = PaintFrame(b)
        guard l.wear > 0.05 else { return }
        var rng = ArtRandom(seed: ArtSeed.mix(l.detailSeed, 0x57))
        for _ in 0..<Int((l.wear * 7).rounded()) {
            let x = rng.range(f.engine.lowerBound...f.nose.upperBound), y = 0.5 + rng.range(-1...0.6) * f.habitatHalf
            let fade = rng.unit() < 0.5 ? ArtRGB(1, 1, 1, 0.10 + 0.10 * l.wear) : ArtRGB(0, 0, 0, 0.12 + 0.14 * l.wear)
            b.add(on(b, Path(CGRect(x: x, y: y, width: rng.range(0.02...0.06), height: rng.range(0.015...0.04)))), .dark, solid: false, color: fade, flat: true,
                  tag: "wear")
        }
        let soot = Path(CGRect(x: f.engine.lowerBound, y: 0, width: 0.03 + 0.04 * l.wear, height: 1))
        b.add(on(b, soot), .dark, solid: false, color: ArtRGB(0, 0, 0, 0.25 * l.wear), flat: true, tag: "soot")
    }
}

/// The stretches of a hull that paint refers to.
struct PaintFrame {
    var engine: ClosedRange<Double>
    var habitat: ClosedRange<Double>
    var nose: ClosedRange<Double>
    var habitatHalf: Double
    var engineHalf: Double

    init(_ b: ShipBuilder) {
        let tail = b.plan.tailX, widestAft = b.plan.stations.first { $0.halfWidth >= b.plan.maxHalf * 0.55 }?.x ?? tail
        engine = widestAft...(widestAft + 0.13)
        habitat = b.cabinRange
        nose = b.deck.lowerBound...b.plan.noseX
        habitatHalf = b.plan.half(at: (b.cabinRange.lowerBound + b.cabinRange.upperBound) / 2)
        engineHalf = b.plan.half(at: widestAft + 0.065)
    }
}
