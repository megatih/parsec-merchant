// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecArt
import SwiftUI

/// A development contact sheet of the art (not shipped).
@MainActor
enum ContactSheet {
    static func write(to url: URL, page: String? = nil) throws {
        let image: CGImage
        switch page {
        case nil: image = IconExport.render(sheet.background(Color(white: 0.85)), pixels: 1600)
        case "planets": image = IconExport.render(PlanetSheet.sheet, pixels: 1600)
        case "ships": image = IconExport.render(ShipSheet.sheet, pixels: 1600)
        case "endings": image = IconExport.render(ShipSheet.endings, pixels: 1600)
        case "portraits": image = IconExport.render(PortraitSheet.sheet.frame(width: 1600, height: 1600), pixels: 1600)
        case "portraits-1", "portraits-2", "portraits-3", "portraits-4":
            // A quarter of the sheet at a size where details can be judged.
            let n = (Int(String(page?.last ?? "1")) ?? 1) - 1
            image = IconExport.render(PortraitSheet.grid(Array(PortraitSheet.genomes[(n * 15)..<(n * 15 + 15)]), columns: 5, side: 300)
                .frame(width: 1600, height: 1600), pixels: 1600)
        case "portraits-small": image = IconExport.render(PortraitSheet.small, pixels: 1600)
        default: fail("unknown page \(page ?? "")")
        }
        try IconExport.writePNG(image, to: url)
    }

    static var sheet: some View {
        VStack(spacing: 6) {
            grid(ShipArtKind.allCases.map { kind in
                AnyView(ShipArt(ShipArtInput(kind: kind, sizeClass: 3, hullFraction: kind.rawValue % 3 == 0 ? 0.55 : 1,
                                             shield: kind.rawValue % 4 == 1 ? ShieldDisplay(kind: .energy, fraction: 0.7) : nil)))
            })
            grid(ShipArtKind.allCases.map { kind in AnyView(ShipArt(ShipArtInput(kind: kind, facing: .left), scaleMode: .relative)) })
            grid((0..<8).map { tech in
                AnyView(PlanetArt(PlanetArtInput(seed: UInt64(tech * 31 + 5), sizeClass: tech % 6, tech: tech, government: tech * 2,
                                                 resource: [nil, 3, 4, 8, 9, 10, 11, 1][tech], pressure: [nil, 1, 2, 5, nil, 6, 3, 1][tech])))
            } + [AnyView(PlanetArt(PlanetArtInput(seed: 99, tech: 7, government: 0), fillsFrame: true))])
            grid(CommodityGlyphKind.allCases.map { AnyView(CommodityGlyph(kind: $0).padding(20)) }
                 + EncounterBadgeKind.allCases.map { AnyView(EncounterBadgeGlyph(badge: $0).padding(20)) }
                 + [AnyView(IllegalBadge().padding(30))], columns: 16, cell: CGSize(width: 95, height: 95))
            grid(EquipmentGlyphKind.allCases.map { AnyView(EquipmentGlyph(kind: $0).padding(20)) }, columns: 16, cell: CGSize(width: 95, height: 95))
            grid((0..<12).map { AnyView(CharacterPortrait(seed: UInt64($0)).padding(10)) }
                 + (0..<4).map { AnyView(TribbleSprite(index: $0).padding(10)) }, columns: 16, cell: CGSize(width: 95, height: 95))
            grid([AnyView(AchievementBadgeArt(shape: .ship(.wasp), tier: .brass, locked: false).padding(8)),
                  AnyView(AchievementBadgeArt(shape: .commodity(.ore), tier: .silver, locked: false).padding(8)),
                  AnyView(AchievementBadgeArt(shape: .crown, tier: .bronze, locked: true).padding(8)),
                  AnyView(Vignette(kind: .object(.reactor))), AnyView(Vignette(kind: .object(.moonDeed))),
                  AnyView(Vignette(kind: .object(.gemulonFleet))), AnyView(Vignette(kind: .object(.experimentRip))),
                  AnyView(Vignette(kind: .object(.jewels))), AnyView(Vignette(kind: .object(.tonicBottle)))])
            grid(GameEndArt.allCases.map { AnyView(GameOverScene(end: $0)) }
                 + [AnyView(TransitScene(input: ShipArtInput(kind: .wasp, sizeClass: 3), progress: 0.4, phase: 1, wormhole: true)),
                    AnyView(WelcomeScene(phase: 3)), AnyView(WormholeVortexView(phase: 0)),
                    AnyView(CombatEffectsLayer(effects: [CombatEffect(.beam(from: .player, weapon: .military, hit: true), start: 0, duration: 0.25),
                                                          CombatEffect(.sparks(on: .opponent, count: 10), start: 0.03, duration: 0.4)],
                                               phase: 0.1).background(Color.black)),
                    AnyView(AppIconComposite())], columns: 9)
            Spacer(minLength: 0)
        }
        .frame(width: 1600, height: 1600)
    }

    static func grid(_ views: [AnyView], columns: Int = 9, cell: CGSize = CGSize(width: 170, height: 115)) -> some View {
        let rows = (views.count + columns - 1) / columns
        return VStack(spacing: 4) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(0..<columns, id: \.self) { c in
                        let i = r * columns + c
                        if i < views.count {
                            views[i].frame(width: cell.width, height: cell.height).background(Color.white.opacity(0.5))
                        } else {
                            Color.clear.frame(width: cell.width, height: cell.height)
                        }
                    }
                }
            }
        }
    }
}
