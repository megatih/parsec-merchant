// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
@testable import ParsecEngine

@Suite("RNG contract (RNG.md)")
struct RNGContractTests {
    static var engineSourcesDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ParsecEngine")
    }

    static func engineSources() throws -> [(String, String)] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: engineSourcesDir, includingPropertiesForKeys: nil) else { return [] }
        return try e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    @Test("RNG-001 engine sources use no non-deterministic randomness or clocks")
    func noNondeterminism() throws {
        let forbidden = ["SystemRandomNumberGenerator", ".random(", "Date()", "UUID()", "hashValue", "arc4random", "drand48"]
        let sources = try Self.engineSources()
        #expect(!sources.isEmpty)
        for (name, text) in sources {
            for token in forbidden {
                #expect(!text.contains(token), "\(name) contains \(token)")
            }
        }
    }

    @Test("RNG-037 RNG-consuming engine code never iterates a Set or Dictionary")
    func noUnorderedIteration() throws {
        for (name, text) in try Self.engineSources() {
            #expect(!text.contains(".keys"), "\(name) iterates dictionary keys")
            #expect(!text.contains(".values"), "\(name) iterates dictionary values")
            #expect(text.range(of: #"for [a-z]+ in Set"#, options: .regularExpression) == nil, "\(name) iterates a Set")
        }
    }

    @Test("RNG-002 rulesets declare their game and newspaper generators")
    func rulesetGenerators() {
        #expect(Ruleset.windows201.rngKind == .dotNet && Ruleset.windows201.newspaperRNG == .csharp)
        #expect(Ruleset.modern.rngKind == .xoshiro && Ruleset.modern.newspaperRNG == .csharp)
        #expect(Ruleset.palm122.rngKind == .palmLCG && Ruleset.palm122.newspaperRNG == .palm)
        #expect(RNGState(kind: .xoshiro, seed: 1).kind == .xoshiro)
    }

    @Test("RNG-003 RNG-007 bounded draws stay in range; Palm/Xoshiro next(in:) = a + next(below: b − a)")
    func boundedRanges() {
        var p = PalmLCG(seed: 3), p2 = PalmLCG(seed: 3)
        var x = Xoshiro256StarStar(seed: 3), x2 = Xoshiro256StarStar(seed: 3)
        for n in 1...200 {
            let v = p.next(in: -5, n)
            #expect(v == -5 + p2.next(below: n + 5))
            let w = x.next(in: -5, n)
            #expect(w == -5 + x2.next(below: n + 5))
            #expect((-5..<n).contains(v) && (-5..<n).contains(w))
        }
    }

    @Test("RNG-013 large ranges consume two internal samples")
    func largeRange() {
        var a = DotNetRandom(seed: 9), b = DotNetRandom(seed: 9)
        _ = a.next(in: Int(Int32.min), Int(Int32.max))
        _ = b.internalSample()
        _ = b.internalSample()
        #expect(a == b)
    }

    @Test("RNG-014 Int32(Sample() × range) equals (k × range) / Int32.max for ranges 1…1024")
    func sampleIntegerEquivalence() {
        var r = DotNetRandom(seed: 1234)
        for i in 0..<200_000 {
            let k = r.internalSample()
            let range = 1 + i % 1024
            let viaDouble = Int(Double(k) * (1.0 / Double(Int32.max)) * Double(range))
            let viaInt = Int((Int64(k) * Int64(range)) / Int64(Int32.max))
            #expect(viaDouble == viaInt, "k \(k) range \(range)")
            if viaDouble != viaInt { break }
        }
    }

    @Test("RNG-015 RNG-028 game seeds bind to the low 32 bits")
    func seedBinding() {
        #expect(RNGState(kind: .dotNet, seed: 0x1_0000_0005) == .dotNet(DotNetRandom(seed: 5)))
        #expect(RNGState(kind: .dotNet, seed: 0xFFFF_FFFF) == .dotNet(DotNetRandom(seed: -1)))
        #expect(RNGState(kind: .palmLCG, seed: 0x2_0000_0007) == .palmLCG(PalmLCG(seed: 7)))
        var zero = PalmLCG(seed: 0)
        #expect(zero.sysRandom() == 0)
    }

    @Test("RNG-017 RNG-018 RNG-019 RNG-020 C# PieterRand: Int64, never negative, positive-only seeds, GetRandom2")
    func pieterCSharp() {
        for seed in [0, 1, -5, 999_999_999, Int(Int32.max)] {
            var r = PieterRand(variant: .csharp)
            r.seed(seed, seed)
            for _ in 0..<10_000 {
                let v = r.rand()
                #expect(v >= 0 && v < (Int64(1) << 48))
                if v < 0 { break }
            }
        }
        var neg = PieterRand(variant: .csharp), def = PieterRand(variant: .csharp)
        neg.seed(-3, -7)
        def.seed(0, 0)
        #expect(neg == def)
        var a = PieterRand(variant: .csharp), b = PieterRand(variant: .csharp)
        a.seed(11, 22)
        b.seed(11, 22)
        #expect(a.getRandom2(17) == Int(b.rand() % 17))
    }

    @Test("RNG-021 RNG-022 RNG-023 RNG-024 Palm PieterRand: UInt16 recurrence, truncated defaults and seeds")
    func pieterPalm() {
        var r = PieterRand(variant: .palm)
        r.seed(0, 0)
        var y: UInt32 = 21_989
        for _ in 0..<50 {
            y = (30_903 &* y) & 0xFFFF
            #expect(r.rand() == Int64(y))
        }
        var t = PieterRand(variant: .palm), d = PieterRand(variant: .palm)
        t.seed(5, 65_536)
        d.seed(5, 0)
        #expect(t == d)
        var g = PieterRand(variant: .palm), h = PieterRand(variant: .palm)
        g.seed(3, 4)
        h.seed(3, 4)
        #expect(g.getRandom2(10) == Int(h.rand()) % 10)
    }

    @Test("RNG-026 PalmLCG step: state = 0x015A4E35·state + 1, output (state >> 16) & 0x7FFF")
    func palmStep() {
        var g = PalmLCG(seed: 0xDEAD_BEEF)
        let expected = 0x015A_4E35 &* UInt32(0xDEAD_BEEF) &+ 1
        #expect(g.sysRandom() == Int((expected >> 16) & 0x7FFF))
        #expect(g.state == expected)
    }

    @Test("RNG-032 RNG-033 every generator round-trips through JSON mid-sequence")
    func codableRoundTrip() throws {
        let enc = JSONEncoder()
        let dec = JSONDecoder()
        for kind in RNGKind.allCases {
            for warm in [0, 1, 57, 1000] {
                var original = RNGState(kind: kind, seed: 0xFEED_FACE_CAFE_BEEF)
                for _ in 0..<warm { _ = original.next(below: 1000) }
                let data = try enc.encode(original)
                var restored = try dec.decode(RNGState.self, from: data)
                #expect(restored == original, "\(kind) warm \(warm)")
                let a = (0..<100).map { _ in original.next(below: 1_000_000) }
                let b = (0..<100).map { _ in restored.next(below: 1_000_000) }
                #expect(a == b, "\(kind) warm \(warm)")
            }
        }
        let xo = String(bytes: try enc.encode(Xoshiro256StarStar(seed: 0)), encoding: .utf8) ?? ""
        #expect(xo.contains("E220A8397B1DCDAF"))
    }

    @Test("RNG-034 RNG-036 identical command sequences give identical RNG; rejected/confirm/preview consume nothing")
    func determinismAndNonConsumption() {
        var a = makeEngine(.modern, seed: 5) { s in setMarket(&s) }
        var b = makeEngine(.modern, seed: 5) { s in setMarket(&s) }
        let cmds: [Command] = [.buyCargo(.water, quantity: 2), .sellCargo(.water, quantity: 1), .borrow(500)]
        for c in cmds {
            _ = a.perform(c)
            _ = b.perform(c)
            #expect(a.state == b.state)
        }
        let rngBefore = a.state.rng
        _ = a.perform(.buyCargo(.water, quantity: 999))
        _ = a.perform(.stopInsurance)
        _ = a.state.marketRows
        a.state.commander.ship.cargo[0] = 3
        _ = a.perform(.jettisonCargo(.water, quantity: 1))
        #expect(a.state.rng == rngBefore)
    }
}

@Suite("Galaxy data (GAL.md)")
struct GalaxyDataTests {
    @Test("GAL-001 GAL-005 Windows galaxy: 128 systems on 154×110, distances 7/13, 6 wormholes; port names 120…127")
    func constants() {
        let t = Ruleset.windows201.tables
        #expect(t.systemNames.count == 128 && t.galaxyWidth == 154 && t.galaxyHeight == 110)
        #expect(t.minDistance == 7 && t.closeDistance == 13)
        #expect(Array(t.systemNames[120...]) == ["Centauri", "Galvon", "Inthara", "Meridian", "Qonos", "Rae", "Weytahn", "Zonama"])
        #expect(t.systemNames.first == "Acamar" && t.systemNames[119] == "Zuul")
        let g = GameState(config: NewGameConfig(commanderName: "C", ruleset: .windows201, seed: 1)).galaxy
        #expect(g.wormholes.count == 6)
    }

    @Test("GAL-003 enum raw values match the source")
    func rawValues() {
        #expect(SystemSize.huge.rawValue == 4 && TechLevel.hiTech.rawValue == 7 && TechLevel.unavailable.rawValue == 8)
        #expect(SystemPressure.employment.rawValue == 7 && SpecialResource.warlike.rawValue == 12)
        #expect(Activity.swarms.rawValue == 7 && Activity.na.rawValue == 100)
    }

    @Test("GAL-004 political systems table has 17 rows with source values")
    func politics() {
        let p = Ruleset.windows201.tables.politicalSystems
        #expect(p.count == 17)
        #expect(p[0] == PoliticalSystemSpec(type: .anarchy, reactionIllegal: 0, activityPolice: .absent, activityPirates: .swarms,
                                            activityTraders: .minimal, minTech: .preAgricultural, maxTech: .industrial,
                                            bribeLevel: 7, drugsOK: true, firearmsOK: true, wanted: .food))
        #expect(p[16].type == .theocracy && p[16].wanted == .narcotics && p[16].maxTech == .earlyIndustrial)
        #expect(p[5].drugsOK == false && p[5].firearmsOK == false)
    }

    @Test("GAL-007 distance is floor(sqrt(dx² + dy²)); Palm rounds")
    func distance() {
        #expect(GalaxyGenerator.distance(0, 0, 3, 4, rule: .floor) == 5)
        #expect(GalaxyGenerator.distance(0, 0, 1, 1, rule: .floor) == 1)
        #expect(GalaxyGenerator.distance(0, 0, 4, 4, rule: .floor) == 5)
        for dx in 0...40 { for dy in 0...40 {
            let d = GalaxyGenerator.distance(0, 0, dx, dy, rule: .floor)
            #expect(d * d <= dx * dx + dy * dy && (d + 1) * (d + 1) > dx * dx + dy * dy)
        } }
    }

    @Test("GAL-031 wormholes form a one-directional ring")
    func ring() {
        let g = Galaxy(systems: [], wormholes: [10, 20, 30, 40, 50, 60])
        #expect(g.wormholeExists(from: 10, to: 20) && !g.wormholeExists(from: 20, to: 10))
        #expect(g.wormholeExists(from: 60, to: 10) && g.wormholeExists(from: 30, to: nil))
        #expect(!g.wormholeExists(from: 11, to: nil) && g.wormholeDestination(from: 60) == 10)
    }

    @Test("GAL-038 exactly 47 systems have an event before the lottery")
    func eventCount() {
        for seed in 0..<50 {
            let g = GameState(config: NewGameConfig(commanderName: "C", difficulty: .normal, ruleset: .windows201, seed: UInt64(seed))).galaxy
            #expect(g.systems.filter { $0.specialEvent != nil }.count == 47, "seed \(seed)")
        }
    }

    @Test("GAL-039 a failed placement regenerates the universe with the RNG continuing")
    func regeneration() {
        // Make Hi-Tech rare (only Cybernetic and Galvon) so PlaceShipyards often fails.
        var r = Ruleset.windows201
        r.tables.politicalSystems = r.tables.politicalSystems.map { p in
            var p = p
            if p.type != .cybernetic, p.maxTech == .hiTech { p.maxTech = .postIndustrial }
            return p
        }
        var sawRetry = false
        for seed in 0..<40 {
            let g = GalaxyGenerator.newGame(ruleset: r, difficulty: .normal, seed: UInt64(seed), commanderName: "C", skills: [5, 5, 5, 5])
            if g.attempts > 1 { sawRetry = true }
            #expect(g.galaxy.systems.filter { $0.shipyard != nil }.allSatisfy { $0.techLevel == .hiTech })
        }
        #expect(sawRetry)
    }

    @Test("GAL-059 GAL-064 commander starting values; start system visited")
    func commanderStart() {
        let s = GameState(config: NewGameConfig(commanderName: "C", ruleset: .windows201, seed: 3))
        let c = s.commander
        #expect(c.cash == 1_000 && c.debt == 0 && c.days == 0 && c.policeRecordScore == 0 && c.reputationScore == 0)
        #expect(c.kills == Kills() && !c.insurance && c.noClaim == 0 && !c.ship.escapePod && c.priceCargo.allSatisfy { $0 == 0 })
        #expect(c.ship.type == .gnat && c.ship.weapons == [.pulseLaser] && c.ship.fuel == 14 && c.ship.hull == 100)
        #expect(s.currentSystem.visited)
        #expect(s.galaxy.systems.filter(\.visited).count == 1)
    }

    @Test("GAL-060 Beginner and Easy put the Lottery on the start system")
    func lottery() {
        for d in Difficulty.allCases {
            let s = GameState(config: NewGameConfig(commanderName: "C", difficulty: d, ruleset: .windows201, seed: 8))
            #expect((s.currentSystem.specialEvent == .lottery) == (d < .normal), "\(d)")
        }
    }

    @Test("GAL-062 CreateShips equips the persistent special ships")
    func specialShips() {
        let s = GameState(config: NewGameConfig(commanderName: "C", ruleset: .windows201, seed: 3)).specialShips
        #expect(s.dragonfly.weapons == [.militaryLaser, .pulseLaser] && s.dragonfly.shields.map(\.type) == [.lightning, .lightning, .lightning])
        #expect(s.dragonfly.gadgets == [.autoRepairSystem, .targetingSystem] && s.dragonfly.crew.first == CrewID.dragonfly)
        #expect(s.scarab.weapons == [.militaryLaser, .militaryLaser] && s.scarab.shields.isEmpty)
        #expect(s.scorpion.shields.map(\.type) == [.reflective, .reflective] && s.scorpion.gadgets == [.autoRepairSystem, .targetingSystem])
        #expect(s.spaceMonster.weapons == [.militaryLaser, .militaryLaser, .militaryLaser])
    }

    @Test("CRW-022 CRW-023 CRW-024 GAL-053 roster: 55 ids, special crew fixed skills, Zeethibal not special")
    func roster() {
        let s = GameState(config: NewGameConfig(commanderName: "C", difficulty: .hard, ruleset: .windows201, seed: 3))
        #expect(s.mercenaries.count == 55 && GameNames.crew.count == 55 && GameNames.crew[53] == "Ziyal")
        let d = Difficulty.hard.rawValue
        #expect(s.mercenaries[CrewID.wild].skills == [7, 10, 2, 5])
        #expect(s.mercenaries[CrewID.jarek].skills == [3, 2, 10, 4])
        #expect(s.mercenaries[CrewID.princess].skills == [4, 3, 8, 9])
        #expect(s.mercenaries[CrewID.dragonfly].skills == [4 + d, 6 + d, 1, 6 + d])
        #expect(s.mercenaries[CrewID.spaceMonster].skills == [8 + d, 8 + d, 1, 1 + d])
        #expect(s.dailyRate(of: CrewID.zeethibal) == 0 && s.mercenaries[CrewID.zeethibal].systemID == nil)
        for id in [CrewID.wild, CrewID.jarek, CrewID.princess, CrewID.famousCaptain] { #expect(s.mercenaries[id].systemID == nil) }
    }
}
