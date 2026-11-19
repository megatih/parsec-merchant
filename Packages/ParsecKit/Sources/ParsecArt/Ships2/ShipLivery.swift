// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// ART-SHIP: who flies a ship. The role decides the livery's visual language, never the geometry.
public enum ShipRole: Int, CaseIterable, Sendable, Hashable {
    case player, police, pirate, trader, famousCaptain, alien, special
    /// Shipyard listings show the player's own livery ("what you would fly").
    case yard
}

/// A livery's pattern: where the accent colour goes on the hull.
public enum LiveryPattern: Int, CaseIterable, Sendable, Hashable {
    case noseCap, beamBand, twinStripes, panelBlocks, tailChevron, spineLine
    /// Police only: a blue-and-white checker band across the beam.
    case checker
}

/// ART-SHIP-006: the paint of one ship: colours, pattern, marking and wear, all from a role and a seed.
public struct ShipLivery: Sendable, Hashable {
    public var role: ShipRole
    public var base: ArtRGB
    public var secondary: ArtRGB
    public var accent: ArtRGB
    public var pattern: LiveryPattern
    /// 0…15: the registry or unit mark (an abstract bar code, never text). Pirates use it as a tally of marks.
    public var marking: Int
    /// 0 (factory fresh) … 1 (battered).
    public var wear: Double
    /// Hues in degrees, kept for the signature and the "never the player's twin" rule.
    public var baseHue: Double
    public var accentHue: Double
    /// Colours of cargo containers; traders carry several.
    public var containers: [ArtRGB]
    /// Seeds panel layout, soot and salvage patches.
    public var detailSeed: UInt64

    /// ART-SHIP-006: what tells two liveries apart at a glance.
    public struct Signature: Sendable, Hashable {
        public var role: ShipRole
        public var pattern: LiveryPattern
        public var baseHueStep: Int
        public var accentHueStep: Int
        public var wearStep: Int
        public var marking: Int
    }

    public var signature: Signature {
        Signature(role: role, pattern: pattern, baseHueStep: Int(baseHue / 15) % 24, accentHueStep: Int(accentHue / 15) % 24,
                  wearStep: min(3, Int(wear / 0.25)), marking: marking)
    }

    public static let brass = ArtRGB(0.86, 0.69, 0.32)
    public static let playerHues: [Double] = [45, 60, 75, 90, 105, 270, 285, 300]
    public static let policeBlue = ArtRGB(0.12, 0.33, 0.78)
    public static let policeWhite = ArtRGB(0.93, 0.95, 0.97)

    /// Hue (degrees), saturation and lightness to sRGB.
    public static func hsl(_ h: Double, _ s: Double, _ l: Double) -> ArtRGB {
        let hue = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let c = (1 - abs(2 * l - 1)) * s, x = c * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1)), m = l - c / 2
        let (r, g, b): (Double, Double, Double) = switch Int(hue) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return ArtRGB(r + m, g + m, b + m)
    }

    /// The smaller angle between two hues, 0…180.
    public static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    /// ART-SHIP-006: the livery of a role and seed.
    public static func make(role requested: ShipRole, seed: UInt64) -> ShipLivery {
        let role = requested == .yard ? ShipRole.player : requested
        var rng = ArtRandom(seed: ArtSeed.mix(seed, 0x4C49_5652 &+ UInt64(role.rawValue)))
        let free: [LiveryPattern] = [.noseCap, .beamBand, .twinStripes, .panelBlocks, .tailChevron, .spineLine]
        let pattern = free[rng.int(0...(free.count - 1))], marking = rng.int(0...15), detail = rng.next()
        switch role {
        case .player, .yard:
            // A clean, lightly tinted hull with one brass stripe. The tints stay at least 40° away from the three famous
            // captains' hull hues (225°, 150°, 355°), so a captain's fixed livery never has to change (ART-SHIP-007).
            let hue = playerHues[rng.int(0...(playerHues.count - 1))]
            return ShipLivery(role: .player, base: hsl(hue, 0.07, 0.68), secondary: hsl(hue + 20, 0.10, 0.40), accent: brass, pattern: pattern,
                              marking: marking, wear: rng.range(0.0...0.3), baseHue: hue, accentHue: 42, containers: [hsl(hue + 20, 0.12, 0.46)],
                              detailSeed: detail)
        case .police:
            return ShipLivery(role: .police, base: policeWhite, secondary: ArtRGB(0.70, 0.74, 0.80), accent: policeBlue, pattern: .checker,
                              marking: marking, wear: rng.range(0.0...0.2), baseHue: 220, accentHue: 220, containers: [ArtRGB(0.70, 0.74, 0.80)],
                              detailSeed: detail)
        case .pirate:
            // Dark, matte hulls; hot accent marks.
            let families: [(Double, Double, Double)] = [(0, 0.02, 0.27), (18, 0.42, 0.29), (350, 0.48, 0.26), (80, 0.26, 0.27), (225, 0.30, 0.25),
                                                         (285, 0.26, 0.26)]
            let accents: [Double] = [2, 24, 48, 320, 95, 180]
            let f = families[rng.int(0...5)], accentHue = accents[rng.int(0...5)]
            let hue = f.0 + rng.range(-4...4)
            return ShipLivery(role: .pirate, base: hsl(hue, f.1, f.2), secondary: hsl(hue, f.1 * 0.8, f.2 * 0.62), accent: hsl(accentHue, 0.85, 0.50),
                              pattern: pattern, marking: marking, wear: rng.range(0.6...1.0), baseHue: (hue + 360).truncatingRemainder(dividingBy: 360),
                              accentHue: accentHue, containers: [hsl(hue, f.1 * 0.6, f.2 * 1.3), hsl(accentHue, 0.30, 0.28)], detailSeed: detail)
        case .trader:
            // Company colours: twelve hue families, a contrasting accent and containers of several owners.
            let hue = Double(rng.int(0...11)) * 30 + rng.range(-6...6)
            let accentHue = hue + [150.0, 180, 210, 90, 270, 120, 240, 30][rng.int(0...7)]
            let boxes = (0..<4).map { _ in hsl(Double(rng.int(0...11)) * 30, rng.range(0.35...0.6), rng.range(0.38...0.56)) }
            return ShipLivery(role: .trader, base: hsl(hue, rng.range(0.20...0.30), rng.range(0.50...0.60)), secondary: hsl(hue, 0.20, 0.34),
                              accent: hsl(accentHue, 0.70, 0.55), pattern: pattern, marking: marking, wear: rng.range(0.2...0.6),
                              baseHue: (hue + 360).truncatingRemainder(dividingBy: 360),
                              accentHue: (accentHue + 360).truncatingRemainder(dividingBy: 360), containers: boxes, detailSeed: detail)
        case .famousCaptain:
            // Three fixed liveries (Ahab, Conrad, Huie by seed mod 3), each with a gold command stripe.
            let fixed: [(ArtRGB, ArtRGB, Double)] = [(ArtRGB(0.90, 0.90, 0.88), ArtRGB(0.14, 0.20, 0.38), 225), (ArtRGB(0.13, 0.30, 0.22), ArtRGB(0.08,
                0.16, 0.12), 150),
                                                     (ArtRGB(0.55, 0.10, 0.14), ArtRGB(0.25, 0.06, 0.08), 355)]
            let k = Int(seed % 3)
            return ShipLivery(role: .famousCaptain, base: fixed[k].0, secondary: fixed[k].1, accent: ArtRGB(0.95, 0.78, 0.30), pattern: .twinStripes,
                              marking: k, wear: 0.1, baseHue: fixed[k].2, accentHue: 45, containers: [fixed[k].1], detailSeed: UInt64(k))
        case .alien:
            let hue = 130 + rng.range(-12...12)
            return ShipLivery(role: .alien, base: hsl(hue, 0.55, 0.36), secondary: hsl(280, 0.50, 0.38), accent: hsl(165, 0.90, 0.60), pattern: .spineLine,
                              marking: 0, wear: 0, baseHue: hue, accentHue: 165, containers: [], detailSeed: detail)
        case .special:
            return ShipLivery(role: .special, base: ArtRGB(0.62, 0.64, 0.68), secondary: ArtRGB(0.30, 0.32, 0.36), accent: ArtRGB(0.95, 0.50, 0.15),
                              pattern: .panelBlocks, marking: 0, wear: 0.2, baseHue: 220, accentHue: 25, containers: [], detailSeed: detail)
        }
    }

    /// ART-SHIP-007: a livery that is never the player's twin. If the signature equals the player's, or the base hues
    /// are within 40°, the seed is re-rolled (up to 16 times) and then the base hue is forced to the opposite side.
    public static func make(role: ShipRole, seed: UInt64, avoidingPlayer playerSeed: UInt64?) -> ShipLivery {
        var livery = make(role: role, seed: seed)
        guard let playerSeed, [.trader, .pirate].contains(role) else { return livery }
        let player = make(role: .player, seed: playerSeed)
        func clashes(_ l: ShipLivery) -> Bool {
            l.signature == player.signature || hueDistance(l.baseHue, player.baseHue) < 40
        }
        var attempt: UInt64 = 0
        while clashes(livery), attempt < 16 {
            attempt += 1
            livery = make(role: role, seed: seed &+ attempt)
        }
        if clashes(livery) {
            // Turn the hull colour to the far side of the colour wheel, keeping its saturation and lightness family.
            let hue = (player.baseHue + 180).truncatingRemainder(dividingBy: 360)
            let dark = role == .pirate
            livery.base = hsl(hue, dark ? 0.35 : 0.45, dark ? 0.22 : 0.50)
            livery.secondary = dark ? hsl(hue, 0.30, 0.14) : livery.secondary
            livery.baseHue = hue
        }
        return livery
    }
}
