// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecArt
import SwiftUI

/// ART-079: the planet contact sheet: every class at hero size, tech levels, the 13 resources, pressures and mini sprites,
/// on dark and light backgrounds.
@MainActor
enum PlanetSheet {
    /// The first seed whose seed-weighted class is `cls` at `size`.
    static func seed(for cls: PlanetClass, size: Int, from start: UInt64 = 1) -> UInt64 {
        var s = start
        while PlanetRecipe.make(PlanetArtInput(seed: s, sizeClass: size)).planetClass != cls { s += 1 }
        return s
    }

    static func cell(_ input: PlanetArtInput, side: Double, fills: Bool = false, caption: String) -> AnyView {
        AnyView(VStack(spacing: 2) {
            PlanetArt(input, fillsFrame: fills).frame(width: side, height: side)
            Text(verbatim: caption).font(.system(size: 10)).foregroundStyle(.gray)
        })
    }

    static var sheet: some View {
        let classes = PlanetClass.allCases
        let heroes: [AnyView] = classes.map { cls in
            cell(PlanetArtInput(seed: seed(for: cls, size: 4), sizeClass: 4, tech: cls == .terran ? 5 : 2, government: 6), side: 240,
                 caption: "\(cls)")
        } + [cell(PlanetArtInput(seed: seed(for: .terran, size: 4, from: 400), sizeClass: 4, tech: 0, government: 6), side: 240, caption: "terran, other seed"),
             cell(PlanetArtInput(seed: seed(for: .gasGiant, size: 4, from: 200), sizeClass: 4, tech: 7, government: 0), side: 240,
                  caption: "gas giant, hi-tech, anarchy")]
        let tech: [AnyView] = [0, 2, 4, 5, 6, 7].map { t in
            cell(PlanetArtInput(seed: 77, sizeClass: 3, tech: t, government: [6, 12, 2, 7, 1, 5][t % 6], resource: 5), side: 240, caption: "rich soil, tech \(t)")
        }
        let resources: [AnyView] = (0...12).map { (r: Int) in
            cell(PlanetArtInput(seed: 21, sizeClass: 3, tech: 3, government: 6, resource: r), side: 112, caption: "res \(r)")
        }
        let pressures: [AnyView] = (1...7).map { (p: Int) in
            cell(PlanetArtInput(seed: 8, sizeClass: 3, tech: 5, government: 6, resource: 5, pressure: p), side: 112, caption: "pressure \(p)")
        }
        let minis: [AnyView] = classes.map { cls in
            cell(PlanetArtInput(seed: seed(for: cls, size: 4), sizeClass: 4, tech: 5), side: 28, fills: true, caption: "")
        } + classes.map { cls in
            cell(PlanetArtInput(seed: seed(for: cls, size: 4), sizeClass: 4, tech: 5), side: 14, fills: true, caption: "")
        }
        var ringed: UInt64 = 1
        while true {
            let rc = PlanetRecipe.make(PlanetArtInput(seed: ringed, sizeClass: 5))
            if rc.planetClass == .gasGiant, rc.ring != nil { break }
            ringed += 1
        }
        return VStack(spacing: 6) {
            row(Array(heroes[0..<6]), cell: 258)
            row(Array(heroes[6..<12]), cell: 258)
            row(tech, cell: 258)
            row(resources, cell: 118)
            HStack(spacing: 8) {
                row(pressures, cell: 118)
                row(minis, cell: 34)
            }
            HStack(spacing: 8) {
                PlanetArt(PlanetArtInput(seed: seed(for: .terran, size: 4), sizeClass: 4, tech: 6, government: 6)).frame(width: 500, height: 500)
                PlanetArt(PlanetArtInput(seed: ringed, sizeClass: 5, tech: 3, government: 6)).frame(width: 500, height: 500)
                VStack(spacing: 4) {
                    row(classes.prefix(5).map { light($0) }, cell: 110).background(Color(white: 0.93))
                    row(classes.suffix(5).map { light($0) }, cell: 110).background(Color(white: 0.93))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 1600, height: 1600)
        .background(Color(red: 0.03, green: 0.03, blue: 0.07))
        .environment(\.displayScale, 1)
    }

    static func light(_ cls: PlanetClass) -> AnyView {
        cell(PlanetArtInput(seed: seed(for: cls, size: 4), sizeClass: 4, tech: 2, government: 6), side: 104, caption: "\(cls)")
    }

    static func row(_ views: [AnyView], cell: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(views.indices, id: \.self) { i in views[i].frame(width: cell) }
        }
    }
}
