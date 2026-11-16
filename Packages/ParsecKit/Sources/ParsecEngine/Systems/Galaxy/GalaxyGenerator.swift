// SPDX-License-Identifier: GPL-2.0-or-later
// New-game construction (docs/specs/GAL.md). Windows 2.01 algorithm (Game.cs:110-133), with RNG call order preserved.

/// Well-known system ids (indices into the 128-name C# list; the first 120 coincide with Palm).
public enum SystemID {
    public static let acamar = 0, baratas = 6, daled = 17, devidia = 22, endor = 25, gemulon = 32, japori = 41
    public static let kravat = 50, melina = 59, nix = 67, og = 70, regulas = 82, utopia = 109, zalkon = 118
    public static let centauri = 120, galvon = 121, inthara = 122, qonos = 124
}

/// Well-known crew member ids (C# `CrewMemberId`).
public enum CrewID {
    public static let commander = 0, zeethibal = 30, opponent = 31, wild = 32, jarek = 33, famousCaptain = 34
    public static let dragonfly = 35, scarab = 36, spaceMonster = 37, princess = 53, scorpion = 54
    public static let count = 55
}

/// Ships that persist between encounters.
public struct SpecialShips: Codable, Sendable, Equatable {
    public var dragonfly: Ship
    public var scarab: Ship
    public var scorpion: Ship
    public var spaceMonster: Ship
}

/// Output of new-game generation.
public struct GeneratedGame: Sendable {
    public var galaxy: Galaxy
    public var mercenaries: [CrewMember]
    public var commander: Commander
    public var specialShips: SpecialShips
    public var sellPrices: [Int]
    public var buyPrices: [Int]
    public var veryRareEncounters: [VeryRareEncounter]
    public var rng: RNGState
    /// Number of universes generated before placement succeeded.
    public var attempts: Int
}

public enum GalaxyGenerator {
    /// Distance between two points under the ruleset's distance rule.
    public static func distance(_ ax: Int, _ ay: Int, _ bx: Int, _ by: Int, rule: DistanceRule) -> Int {
        let sq = (ax - bx) * (ax - bx) + (ay - by) * (ay - by)
        switch rule {
        case .floor:
            return Int(Double(sq).squareRoot().rounded(.down))
        case .rounded:
            return palmSqrt(sq)
        }
    }

    /// Palm `Math.c` integer square root rounded to nearest. [verify against Math.c in M5]
    static func palmSqrt(_ a: Int) -> Int {
        var i = 0
        while i * i < a { i += 1 }
        if i > 0, (i * i - a) > (a - (i - 1) * (i - 1)) { i -= 1 }
        return i
    }

    public static func distance(_ a: StarSystem, _ b: StarSystem, rule: DistanceRule) -> Int {
        distance(a.x, a.y, b.x, b.y, rule: rule)
    }

    /// Builds a complete new game (C# `Game(name, difficulty, p, f, t, e)` constructor).
    public static func newGame(ruleset: Ruleset, difficulty: Difficulty, seed: UInt64, commanderName: String,
                               skills: [Int]) -> GeneratedGame {
        var rng = RNGState(kind: ruleset.rngKind, seed: seed)
        var galaxy: Galaxy
        var attempts = 0
        repeat {
            attempts += 1
            galaxy = generateUniverse(ruleset: ruleset, difficulty: difficulty, rng: &rng)
        } while !(placeSpecialEvents(&galaxy, ruleset: ruleset, rng: &rng)
                  && placeShipyards(&galaxy, ruleset: ruleset, rng: &rng))

        // InitializeCommander
        let gnatSpec = ruleset.tables.ship(.gnat)
        var ship = Ship(type: .gnat, spec: gnatSpec)
        ship.crew[0] = CrewID.commander
        ship.weapons.append(.pulseLaser)
        var start = -1
        while start < 0 {
            let candidate = rng.next(below: galaxy.systems.count)
            let s = galaxy.systems[candidate]
            guard s.specialEvent == nil, s.techLevel > .preAgricultural, s.techLevel < .hiTech else { continue }
            var close = 0
            for i in galaxy.systems.indices where close < 3 {
                if i != candidate,
                   distance(galaxy.systems[i], s, rule: ruleset.flags.distance) <= gnatSpec.fuelTanks {
                    close += 1
                }
            }
            if close >= 3 { start = candidate }
        }
        galaxy.systems[start].visited = true
        var commander = Commander(name: commanderName, cash: ruleset.tables.startingCash, debt: 0, kills: Kills(),
                                  policeRecordScore: 0, reputationScore: 0, days: 0, insurance: false, noClaim: 0,
                                  ship: ship, priceCargo: Array(repeating: 0, count: 10), currentSystem: start,
                                  shipName: nil)

        var mercs = generateCrew(galaxy: galaxy, ruleset: ruleset, difficulty: difficulty, rng: &rng)
        mercs[CrewID.commander] = CrewMember(id: CrewID.commander, pilot: skills[0], fighter: skills[1],
                                             trader: skills[2], engineer: skills[3], systemID: nil)
        let special = createShips(ruleset: ruleset)

        // CalculatePrices(Commander.CurrentSystem)
        let system = galaxy.systems[start]
        let criminal = commander.policeRecordScore < -5
        let sell = Pricing.sellPrices(in: system, criminal: criminal, ruleset: ruleset, rng: &rng)
        let trader = Skills.shipSkills(commander.ship, crew: mercs, difficulty: difficulty, ruleset: ruleset)[SkillType.trader.rawValue]
        let buy = Pricing.buyPrices(sell: sell, in: system, criminal: criminal, traderSkill: trader, ruleset: ruleset)

        if difficulty < .normal {
            galaxy.systems[start].specialEvent = .lottery
        }
        commander.ship = ship
        return GeneratedGame(galaxy: galaxy, mercenaries: mercs, commander: commander, specialShips: special,
                             sellPrices: sell, buyPrices: buy, veryRareEncounters: VeryRareEncounter.allCases,
                             rng: rng, attempts: attempts)
    }

    /// C# `Game.GenerateUniverse` (Game.cs:2175).
    static func generateUniverse(ruleset: Ruleset, difficulty: Difficulty, rng: inout RNGState) -> Galaxy {
        let t = ruleset.tables
        let count = t.systemNames.count
        var systems: [StarSystem] = []
        systems.reserveCapacity(count)
        var wormholes = [Int](repeating: 0, count: 6)
        for i in 0..<count {
            var size = SystemSize(rawValue: rng.next(below: SystemSize.huge.rawValue + 1)) ?? .tiny
            var pol = t.politicalSystems[rng.next(below: t.politicalSystems.count)]
            var tech = TechLevel(rawValue: rng.next(in: pol.minTech.rawValue, pol.maxTech.rawValue + 1)) ?? .preAgricultural
            if i == SystemID.galvon, count > SystemID.galvon {
                size = .large
                pol = t.politics(.monarchy)
                tech = .hiTech
            }
            var pressure = SystemPressure.none
            var resource = SpecialResource.nothing
            if rng.next(below: 100) < 15 {
                pressure = SystemPressure(rawValue: rng.next(in: SystemPressure.war.rawValue,
                                                             SystemPressure.employment.rawValue + 1)) ?? .none
            }
            if rng.next(below: 5) >= 3 {
                resource = SpecialResource(rawValue: rng.next(in: SpecialResource.mineralRich.rawValue,
                                                              SpecialResource.warlike.rawValue + 1)) ?? .nothing
            }
            var x = 0, y = 0
            if i < wormholes.count {
                x = (t.galaxyWidth * (1 + 2 * (i % 3))) / 6 - rng.next(in: -t.centralOffset + 1, t.centralOffset)
                y = (t.galaxyHeight * (i < 3 ? 1 : 3)) / 4 - rng.next(in: -t.centralOffset + 1, t.centralOffset)
                wormholes[i] = i
            } else {
                var ok = false
                while !ok {
                    x = rng.next(in: 1, t.galaxyWidth)
                    y = rng.next(in: 1, t.galaxyHeight)
                    var closeFound = false
                    var tooClose = false
                    var j = 0
                    while j < i, !tooClose {
                        let d = distance(systems[j].x, systems[j].y, x, y, rule: ruleset.flags.distance)
                        if d < t.minDistance { tooClose = true }
                        if d < t.closeDistance { closeFound = true }
                        j += 1
                    }
                    ok = closeFound && !tooClose
                }
            }
            var s = StarSystem(id: i, x: x, y: y, size: size, techLevel: tech, politics: pol.type, pressure: pressure,
                               specialResource: resource)
            s.tradeItems = Pricing.initialQuantities(for: s, difficulty: difficulty, ruleset: ruleset, rng: &rng)
            systems.append(s)
        }
        // Shuffle locations so early-alphabet systems are not all central.
        for i in 0..<count {
            let j = rng.next(below: count)
            if !wormholes.contains(j) {
                (systems[i].x, systems[j].x) = (systems[j].x, systems[i].x)
                (systems[i].y, systems[j].y) = (systems[j].y, systems[i].y)
                if let w = wormholes.firstIndex(of: i) { wormholes[w] = j }
            }
        }
        // Randomize wormhole order.
        for i in 0..<wormholes.count {
            let j = rng.next(below: wormholes.count)
            wormholes.swapAt(i, j)
        }
        return Galaxy(systems: systems, wormholes: wormholes)
    }

    /// C# `Game.FindDistantSystem`: closest system ≥ 70 parsecs from `base` without an event.
    static func findDistantSystem(_ galaxy: inout Galaxy, from base: Int, event: SpecialEventType, rule: DistanceRule) -> Bool {
        var best = 999
        var found = -1
        for i in galaxy.systems.indices {
            let d = distance(galaxy.systems[base], galaxy.systems[i], rule: rule)
            if d >= 70, d < best, galaxy.systems[i].specialEvent == nil {
                found = i
                best = d
            }
        }
        if found >= 0 { galaxy.systems[found].specialEvent = event }
        return found >= 0
    }

    /// C# `Game.PlaceSpecialEvents` (Game.cs:2880).
    static func placeSpecialEvents(_ galaxy: inout Galaxy, ruleset: Ruleset, rng: inout RNGState) -> Bool {
        let fixed: [(Int, SpecialEventType)] = [
            (SystemID.baratas, .dragonflyBaratas), (SystemID.melina, .dragonflyMelina), (SystemID.regulas, .dragonflyRegulas),
            (SystemID.zalkon, .dragonflyDestroyed), (SystemID.daled, .experimentStopped), (SystemID.gemulon, .gemulonRescued),
            (SystemID.japori, .japoriDelivery), (SystemID.devidia, .jarekGetsOut), (SystemID.utopia, .moonRetirement),
            (SystemID.nix, .reactorDelivered), (SystemID.acamar, .spaceMonsterKilled), (SystemID.kravat, .wildGetsOut),
            (SystemID.endor, .sculptureDelivered), (SystemID.galvon, .princess), (SystemID.centauri, .princessCentauri),
            (SystemID.inthara, .princessInthara), (SystemID.qonos, .princessQonos),
        ]
        for (sys, ev) in fixed where sys < galaxy.systems.count {
            if ev == .sculptureDelivered, !ruleset.content.hasSculptureQuest { continue }
            if [.princess, .princessCentauri, .princessInthara, .princessQonos].contains(ev), !ruleset.content.hasPrincessQuest { continue }
            galaxy.systems[sys].specialEvent = ev
        }
        // Scarab endpoint: first wormhole system without an event.
        guard let w = galaxy.wormholes.first(where: { galaxy.systems[$0].specialEvent == nil }) else { return false }
        galaxy.systems[w].specialEvent = .scarabDestroyed
        // Artifact delivery: first Hi-Tech system without an event.
        guard let a = galaxy.systems.indices.first(where: {
            galaxy.systems[$0].specialEvent == nil && galaxy.systems[$0].techLevel == .hiTech
        }) else { return false }
        galaxy.systems[a].specialEvent = .artifactDelivery
        let rule = ruleset.flags.distance
        guard findDistantSystem(&galaxy, from: SystemID.nix, event: .reactor, rule: rule),
              findDistantSystem(&galaxy, from: SystemID.gemulon, event: .gemulon, rule: rule),
              findDistantSystem(&galaxy, from: SystemID.daled, event: .experiment, rule: rule) else { return false }
        if ruleset.content.hasSculptureQuest {
            guard findDistantSystem(&galaxy, from: SystemID.endor, event: .sculpture, rule: rule) else { return false }
        }
        for spec in ruleset.tables.specialEvents {
            for _ in 0..<spec.occurrence {
                var s: Int
                repeat {
                    s = rng.next(below: galaxy.systems.count)
                } while galaxy.systems[s].specialEvent != nil
                galaxy.systems[s].specialEvent = spec.type
            }
        }
        return true
    }

    /// C# `Game.PlaceShipyards`: each of the 5 shipyards on a random Hi-Tech system (collisions allowed unless
    /// `distinctShipyards`). Fails if fewer than 5 Hi-Tech systems exist.
    static func placeShipyards(_ galaxy: inout Galaxy, ruleset: Ruleset, rng: inout RNGState) -> Bool {
        guard ruleset.content.hasShipyards else { return true }
        var candidates = galaxy.systems.indices.filter { galaxy.systems[$0].techLevel == .hiTech }
        guard candidates.count >= ShipyardID.allCases.count else { return false }
        for yard in ShipyardID.allCases {
            let k = rng.next(below: candidates.count)
            galaxy.systems[candidates[k]].shipyard = yard
            if ruleset.flags.distinctShipyards { candidates.remove(at: k) }
        }
        return true
    }

    /// C# `Game.GenerateCrewMemberList` (Game.cs:2121).
    static func generateCrew(galaxy: Galaxy, ruleset: Ruleset, difficulty: Difficulty, rng: inout RNGState) -> [CrewMember] {
        let d = difficulty.rawValue
        var used = [Int](repeating: 0, count: galaxy.systems.count)
        used[SystemID.kravat] = 1
        var crew = [CrewMember?](repeating: nil, count: CrewID.count)
        func put(_ id: Int, _ p: Int, _ f: Int, _ t: Int, _ e: Int) {
            crew[id] = CrewMember(id: id, pilot: p, fighter: f, trader: t, engineer: e, systemID: nil)
        }
        put(CrewID.zeethibal, 5, 5, 5, 5)
        put(CrewID.opponent, 5, 5, 5, 5)
        put(CrewID.wild, 7, 10, 2, 5)
        put(CrewID.jarek, 3, 2, 10, 4)
        put(CrewID.princess, 4, 3, 8, 9)
        put(CrewID.famousCaptain, 10, 10, 10, 10)
        put(CrewID.dragonfly, 4 + d, 6 + d, 1, 6 + d)
        put(CrewID.scarab, 5 + d, 6 + d, 1, 6 + d)
        put(CrewID.scorpion, 8 + d, 8 + d, 1, 6 + d)
        put(CrewID.spaceMonster, 8 + d, 8 + d, 1, 1 + d)
        for i in 1..<CrewID.count where crew[i] == nil {
            var sys: Int
            repeat {
                sys = rng.next(below: galaxy.systems.count)
            } while used[sys] >= ruleset.content.mercenariesPerSystem
            used[sys] += 1
            crew[i] = CrewMember(id: i, pilot: rng.randomSkill(), fighter: rng.randomSkill(), trader: rng.randomSkill(),
                                 engineer: rng.randomSkill(), systemID: sys)
        }
        crew[CrewID.commander] = CrewMember(id: 0, pilot: 1, fighter: 1, trader: 1, engineer: 1, systemID: nil)
        return crew.map { $0 ?? CrewMember(id: 0, pilot: 1, fighter: 1, trader: 1, engineer: 1, systemID: nil) }
    }

    /// C# `Game.CreateShips` (Game.cs:743).
    static func createShips(ruleset: Ruleset) -> SpecialShips {
        func make(_ type: ShipType, crew: Int, weapons: [WeaponType], shields: [ShieldType], gadgets: [GadgetType]) -> Ship {
            var s = Ship(type: type, spec: ruleset.tables.ship(type))
            if !s.crew.isEmpty { s.crew[0] = crew }
            s.weapons = weapons
            s.shields = shields.map { ShieldInstance(type: $0, charge: ruleset.tables.shield($0).power) }
            s.gadgets = gadgets
            return s
        }
        return SpecialShips(
            dragonfly: make(.dragonfly, crew: CrewID.dragonfly, weapons: [.militaryLaser, .pulseLaser],
                            shields: [.lightning, .lightning, .lightning], gadgets: [.autoRepairSystem, .targetingSystem]),
            scarab: make(.scarab, crew: CrewID.scarab, weapons: [.militaryLaser, .militaryLaser], shields: [], gadgets: []),
            scorpion: make(.scorpion, crew: CrewID.scorpion, weapons: [.militaryLaser, .militaryLaser],
                           shields: [.reflective, .reflective], gadgets: [.autoRepairSystem, .targetingSystem]),
            spaceMonster: make(.spaceMonster, crew: CrewID.spaceMonster,
                               weapons: [.militaryLaser, .militaryLaser, .militaryLaser], shields: [], gadgets: []))
    }
}
