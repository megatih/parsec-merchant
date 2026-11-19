// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecArt
import SwiftUI

/// ART-089: the ship contact sheet: all 17 kinds at 44 pt and 240 pt in both facings on light and dark backgrounds, and
/// a designer statistics sweep.
@MainActor
enum ShipSheet {
    static func cell(_ input: ShipArtInput, width: Double, height: Double, mode: ShipScaleMode = .fit, caption: String = "") -> AnyView {
        AnyView(VStack(spacing: 1) {
            ShipArt(input, scaleMode: mode).frame(width: width, height: height)
            if !caption.isEmpty { Text(verbatim: caption).font(.system(size: 10)).foregroundStyle(.gray) }
        })
    }

    static func row(_ views: [AnyView], cell: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(views.indices, id: \.self) { i in views[i].frame(width: cell) }
        }
    }

    static var sheet: some View {
        let kinds = ShipArtKind.allCases
        let big: [AnyView] = kinds.map { cell(ShipArtInput(kind: $0), width: 240, height: 150, caption: "\($0)") }
        let small: [AnyView] = kinds.map { cell(ShipArtInput(kind: $0), width: 44, height: 30) }
        let smallLeft: [AnyView] = kinds.map { cell(ShipArtInput(kind: $0, facing: .left), width: 44, height: 30) }
        let left: [AnyView] = [ShipArtKind.gnat, .beetle, .hornet, .wasp, .termite, .scorpion].map { kind in
            cell(ShipArtInput(kind: kind, facing: .left, hullFraction: 0.6, shield: ShieldDisplay(kind: .energy, fraction: 0.6)), width: 240, height: 150,
                 caption: "\(kind), left, 60% hull, shield")
        }
        let relative: [AnyView] = kinds.prefix(10).map { cell(ShipArtInput(kind: $0, facing: .left), width: 150, height: 110, mode: .relative) }
        let designs = [(10, 0, 30, 0), (30, 1, 100, 2), (50, 2, 180, 3), (70, 4, 300, 5), (0, 6, 400, 5), (40, 3, 60, 1)]
        let sweep: [AnyView] = designs.map { bays, weapons, hull, tier in
            cell(ShipArtInput(kind: .custom, stats: ShipArtStats(sizeClass: min(5, tier), cargoBays: bays, weaponSlots: weapons, shieldSlots: tier / 2,
                                                                  gadgetSlots: tier / 2, crewQuarters: 1 + tier / 2, fuelTanks: 12 + tier * 2,
                                                                  hullStrength: hull, priceTier: tier, techTier: 4 + tier / 2)),
                 width: 240, height: 150, caption: "custom: \(bays) bays, \(weapons) weapons, hull \(hull), tier \(tier)")
        }
        return VStack(spacing: 6) {
            row(Array(big[0..<6]), cell: 258)
            row(Array(big[6..<12]), cell: 258)
            row(Array(big[12..<17]), cell: 258)
            row(small, cell: 50)
            row(smallLeft, cell: 50).background(Color(white: 0.93))
            row(left, cell: 258)
            row(relative, cell: 154).background(Color(white: 0.93))
            row(sweep, cell: 258)
            Spacer(minLength: 0)
        }
        .frame(width: 1600, height: 1600)
        .background(Color(red: 0.05, green: 0.06, blue: 0.11))
        .environment(\.displayScale, 1)
    }

    /// ART-089: the four endings at phase 0, 2 and 4.
    static var endings: some View {
        VStack(spacing: 8) {
            ForEach(GameEndArt.allCases, id: \.self) { end in
                HStack(spacing: 8) {
                    ForEach([0.0, 2.0, 4.0], id: \.self) { phase in
                        GameOverScene(end: end, phase: phase, ship: .wasp).frame(width: 520, height: 292)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 1600, height: 1600)
        .background(Color(red: 0.05, green: 0.06, blue: 0.11))
        .environment(\.displayScale, 1)
    }

    /// ART-SHIP-012: ten ship types × four roles × four seeds.
    static var liveries: some View {
        let roles: [ShipRole] = [.player, .police, .pirate, .trader]
        return VStack(spacing: 0) {
            ForEach(ShipArtKind.buyable, id: \.self) { kind in
                ForEach(0..<2, id: \.self) { half in
                    HStack(spacing: 2) {
                        ForEach(roles[(half * 2)..<(half * 2 + 2)], id: \.self) { role in
                            ForEach(0..<4, id: \.self) { seed in
                                ShipArt(ShipArtInput(kind: kind, role: role, liverySeed: UInt64(seed * 7919 + kind.rawValue * 31 + role.rawValue),
                                    playerLiverySeed: 1))
                                    .frame(width: 197, height: 78)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 1600, height: 1600)
        .background(Color(red: 0.05, green: 0.06, blue: 0.11))
        .environment(\.displayScale, 1)
    }

    /// ART-SHIP-012: one hull (a Grasshopper: 2 weapon, 2 shield and 3 gadget slots) with each item installed, and empty.
    static var fittings: some View {
        func ship(_ caption: String, weapons: [Int] = [], shields: [Int] = [], gadgets: [Int] = []) -> AnyView {
            var stats = ShipArtStats.standard(.grasshopper)
            stats.weapons = weapons
            stats.shields = shields
            stats.gadgets = gadgets
            return cell(ShipArtInput(kind: .grasshopper, stats: stats), width: 380, height: 190, caption: caption)
        }
        let weapons = ["pulse laser", "beam laser", "military laser", "Morgan's laser", "photon disruptor", "quantum disruptor"]
        let shields = ["energy shield", "reflective shield", "lightning shield"]
        let gadgets = ["extra cargo bays", "auto-repair system", "navigating system", "targeting system", "cloaking device", "fuel compactor",
            "hidden cargo bays"]
        var views: [AnyView] = [ship("empty")]
        views += weapons.indices.map { ship(weapons[$0], weapons: [$0, $0]) }
        views += shields.indices.map { ship(shields[$0], shields: [$0, $0]) }
        views += gadgets.indices.map { ship(gadgets[$0], gadgets: [$0]) }
        views.append(ship("fully fitted", weapons: [2, 3], shields: [1, 2], gadgets: [2, 3, 5]))
        return VStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { r in
                row(Array(views[(r * 4)..<min(views.count, r * 4 + 4)]), cell: 390)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 1600, height: 1600)
        .background(Color(red: 0.05, green: 0.06, blue: 0.11))
        .environment(\.displayScale, 1)
    }
}
