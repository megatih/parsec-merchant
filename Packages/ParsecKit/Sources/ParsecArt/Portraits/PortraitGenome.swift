// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// ART-FACE: characters with an authored portrait (special crew, passengers and the famous captains).
public enum PortraitRole: Int, CaseIterable, Sendable, Hashable {
    case wild, jarek, princess, zeethibal, ahab, conrad, huie
}

/// ART-FACE-001: everything that makes one face. Each gene is a small integer, so two genomes can be compared gene by
/// gene (ART-FACE-002) and a genome is a pure function of its seed.
public struct PortraitGenome: Sendable, Hashable {
    /// Head shape, each −4…4 (one step is 3 %, so at most ±12 % of the mean).
    public var cranium: Int
    public var jaw: Int
    public var chin: Int
    public var cheek: Int
    /// One of `skinCount` curated ramps, light to dark.
    public var skin: Int
    public var eyeShape: Int
    public var eyeColor: Int
    /// −2…2: the distance between the eye centres, one eye width ±10 %.
    public var eyeSpacing: Int
    public var browShape: Int
    public var browHeight: Int
    public var noseShape: Int
    public var noseSize: Int
    public var mouthShape: Int
    /// −2…2: the mouth width against the eye-centre spacing, ±10 %.
    public var mouthWidth: Int
    public var earShape: Int
    public var hairStyle: Int
    public var hairColor: Int
    /// 0 is none.
    public var facialHair: Int
    /// 0 young, 1 middle, 2 older.
    public var age: Int
    /// 0 none, 1 scar, 2 freckles, 3 implant, 4 eye patch.
    public var mark: Int
    public var attire: Int
    public var attireColor: Int
    /// 0 pilot wings, 1 fighter chevrons, 2 trader ledger bars, 3 engineer cog. The app sets it from the best skill.
    public var insignia: Int
    public var backdrop: Int

    public static let skinCount = 10, eyeShapeCount = 6, eyeColorCount = 6, browShapeCount = 5, noseShapeCount = 6
    public static let mouthShapeCount = 6, earShapeCount = 3, hairStyleCount = 14, hairColorCount = 8, facialHairCount = 6
    public static let attireCount = 8, attireColorCount = 8, backdropCount = 6, markCount = 5
    public static let geneCount = 24

    /// The genes in a fixed order (for gene distance and golden values).
    public var genes: [Int] {
        [cranium, jaw, chin, cheek, skin, eyeShape, eyeColor, eyeSpacing, browShape, browHeight, noseShape, noseSize, mouthShape,
         mouthWidth, earShape, hairStyle, hairColor, facialHair, age, mark, attire, attireColor, insignia, backdrop]
    }

    /// The number of genes that differ.
    public func distance(to other: PortraitGenome) -> Int {
        zip(genes, other.genes).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
    }

    /// ART-FACE-001: the genome of a seed. Presentation is drawn from the seed and never from a name.
    public static func make(seed: UInt64) -> PortraitGenome {
        var rng = ArtRandom(seed: ArtSeed.mix(seed, 0x4641_4345))
        let age = [0, 0, 1, 1, 1, 2][rng.int(0...5)]
        var hairColor = [0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 4, 5, 5][rng.int(0...14)]
        let skin = rng.int(0...(skinCount - 1))
        if hairColor == 5, skin >= 7 { hairColor = 0 }
        if age == 2, rng.unit() < 0.7 { hairColor = rng.int(6...7) }
        if age == 1, rng.unit() < 0.15 { hairColor = 6 }
        let markRoll = rng.unit()
        let mark = markRoll < 0.70 ? 0 : (markRoll < 0.80 ? 1 : (markRoll < 0.90 ? 2 : (markRoll < 0.96 ? 3 : 4)))
        // Moustaches and beards do not go with the long, tied or knotted styles.
        let hairStyle = rng.int(0...(hairStyleCount - 1))
        let wantsFacialHair = rng.unit() < 0.25, facialHairStyle = rng.int(1...(facialHairCount - 1))
        let facialHair = wantsFacialHair && ![7, 8, 9, 12].contains(hairStyle) ? facialHairStyle : 0
        return PortraitGenome(
            cranium: rng.int(-4...4), jaw: rng.int(-4...4), chin: rng.int(-4...4), cheek: rng.int(-4...4),
            skin: skin, eyeShape: rng.int(0...(eyeShapeCount - 1)), eyeColor: rng.int(0...(eyeColorCount - 1)),
            eyeSpacing: rng.int(-2...2), browShape: rng.int(0...(browShapeCount - 1)), browHeight: rng.int(-2...2),
            noseShape: rng.int(0...(noseShapeCount - 1)), noseSize: rng.int(-2...2), mouthShape: rng.int(0...(mouthShapeCount - 1)),
            mouthWidth: rng.int(-2...2), earShape: rng.int(0...(earShapeCount - 1)), hairStyle: hairStyle,
            hairColor: hairColor, facialHair: facialHair, age: age, mark: mark,
            attire: rng.int(0...(attireCount - 1)), attireColor: rng.int(0...(attireColorCount - 1)), insignia: rng.int(0...3),
            backdrop: rng.int(0...(backdropCount - 1)))
    }

    /// The authored genome of a special character. It does not depend on any seed.
    public static func fixed(_ role: PortraitRole) -> PortraitGenome {
        switch role {
        case .wild: // Jonathan Wild: older, scarred, plain dark suit.
            PortraitGenome(cranium: 1, jaw: 3, chin: 1, cheek: -1, skin: 2, eyeShape: 2, eyeColor: 5, eyeSpacing: -1, browShape: 3, browHeight: -1,
                           noseShape: 4, noseSize: 1, mouthShape: 2, mouthWidth: 0, earShape: 1, hairStyle: 13, hairColor: 6, facialHair: 1,
                           age: 2, mark: 1, attire: 1, attireColor: 7, insignia: 1, backdrop: 5)
        case .jarek: // Ambassador Jarek: formal attire.
            PortraitGenome(cranium: 0, jaw: -1, chin: 0, cheek: 1, skin: 5, eyeShape: 0, eyeColor: 1, eyeSpacing: 0, browShape: 1, browHeight: 1,
                           noseShape: 0, noseSize: 0, mouthShape: 0, mouthWidth: 1, earShape: 0, hairStyle: 3, hairColor: 6, facialHair: 3,
                           age: 1, mark: 0, attire: 4, attireColor: 4, insignia: 2, backdrop: 1)
        case .princess: // Princess Ziyal: circlet and formal attire.
            PortraitGenome(cranium: -1, jaw: -3, chin: -1, cheek: 2, skin: 3, eyeShape: 3, eyeColor: 3, eyeSpacing: 0, browShape: 2, browHeight: 1,
                           noseShape: 2, noseSize: -1, mouthShape: 5, mouthWidth: -1, earShape: 2, hairStyle: 8, hairColor: 0, facialHair: 0,
                           age: 0, mark: 0, attire: 4, attireColor: 6, insignia: 0, backdrop: 4)
        case .zeethibal: // Zeethibal: the youngest, engineer attire.
            PortraitGenome(cranium: 0, jaw: -2, chin: -2, cheek: 0, skin: 7, eyeShape: 1, eyeColor: 0, eyeSpacing: 1, browShape: 0, browHeight: 0,
                           noseShape: 3, noseSize: -1, mouthShape: 3, mouthWidth: 0, earShape: 1, hairStyle: 5, hairColor: 0, facialHair: 0,
                           age: 0, mark: 2, attire: 3, attireColor: 2, insignia: 3, backdrop: 2)
        case .ahab: // Captain Ahab.
            PortraitGenome(cranium: 2, jaw: 4, chin: 2, cheek: 0, skin: 1, eyeShape: 5, eyeColor: 4, eyeSpacing: -1, browShape: 4, browHeight: -2,
                           noseShape: 4, noseSize: 2, mouthShape: 4, mouthWidth: 1, earShape: 0, hairStyle: 4, hairColor: 7, facialHair: 4,
                           age: 2, mark: 1, attire: 5, attireColor: 0, insignia: 1, backdrop: 0)
        case .conrad: // Captain Conrad.
            PortraitGenome(cranium: -2, jaw: 0, chin: 1, cheek: -2, skin: 8, eyeShape: 0, eyeColor: 0, eyeSpacing: 1, browShape: 1, browHeight: 0,
                           noseShape: 1, noseSize: 1, mouthShape: 1, mouthWidth: 0, earShape: 2, hairStyle: 1, hairColor: 0, facialHair: 2,
                           age: 1, mark: 0, attire: 5, attireColor: 3, insignia: 0, backdrop: 3)
        case .huie: // Captain Huie.
            PortraitGenome(cranium: 1, jaw: -2, chin: -1, cheek: 3, skin: 4, eyeShape: 4, eyeColor: 2, eyeSpacing: 0, browShape: 2, browHeight: 2,
                           noseShape: 5, noseSize: 0, mouthShape: 0, mouthWidth: -2, earShape: 1, hairStyle: 12, hairColor: 3, facialHair: 0,
                           age: 1, mark: 3, attire: 5, attireColor: 5, insignia: 2, backdrop: 5)
        }
    }
}
