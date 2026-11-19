// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecArt
import SwiftUI

/// ART-FACE-008: contact sheets of the portraits (development aid, not shipped).
@MainActor
enum PortraitSheet {
    /// Galaxy seed 1001, crew ids 0…54, then the commanders of five more galaxy seeds.
    static var genomes: [PortraitGenome] {
        (0..<55).map { PortraitGenome.make(seed: ArtSeed.crew(galaxySeed: 1001, crewID: $0)) }
            + (1...5).map { PortraitGenome.make(seed: ArtSeed.crew(galaxySeed: UInt64($0), crewID: 0)) }
    }

    static var sheet: some View {
        grid(genomes, columns: 8, side: 190)
    }

    /// The same portraits at 28 pt and 64 pt, and the seven authored characters at 128 pt.
    static var small: some View {
        VStack(alignment: .leading, spacing: 16) {
            grid(genomes, columns: 30, side: 28)
            grid(genomes, columns: 20, side: 64)
            grid(PortraitRole.allCases.map { PortraitGenome.fixed($0) }, columns: 7, side: 190)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 1600, height: 1600, alignment: .topLeading)
        .background(Color(white: 0.16))
    }

    static func grid(_ genomes: [PortraitGenome], columns: Int, side: CGFloat) -> some View {
        let rows = (genomes.count + columns - 1) / columns
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(0..<columns, id: \.self) { c in
                        let i = r * columns + c
                        if i < genomes.count {
                            CharacterPortrait(genome: genomes[i]).frame(width: side, height: side)
                        }
                    }
                }
            }
        }
        .padding(side > 100 ? 12 : 0)
        .frame(maxWidth: .infinity, maxHeight: side > 100 ? .infinity : nil, alignment: .topLeading)
        .background(Color(white: 0.16))
    }
}
