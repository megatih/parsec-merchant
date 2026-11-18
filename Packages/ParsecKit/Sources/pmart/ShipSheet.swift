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
}
