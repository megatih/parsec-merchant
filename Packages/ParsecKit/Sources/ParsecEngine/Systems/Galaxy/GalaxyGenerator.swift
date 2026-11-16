// SPDX-License-Identifier: GPL-2.0-or-later
// New-game construction (docs/specs/GAL.md): Windows 2.01 (Game.cs:110-133) and Palm 1.2.2 (Src/Traveler.c:StartNewGame)
// algorithms, with RNG call order preserved. Behaviour is selected by `RuleFlags.galaxy` (GalaxyRules.swift).

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

    /// Palm `Math.c:sqrt` (Math.c:44-55): smallest `i` with `i² ≥ a`, decremented if `i² − a > a − (i−1)²` (GAL-008).
    static func palmSqrt(_ a: Int) -> Int {
        var i = 0
        while i * i < a { i += 1 }
        if i > 0, (i * i - a) > (a - (i - 1) * (i - 1)) { i -= 1 }
        return i
    }

    public static func distance(_ a: StarSystem, _ b: StarSystem, rule: DistanceRule) -> Int {
        distance(a.x, a.y, b.x, b.y, rule: rule)
    }

    /// Builds a complete new game: C# `Game(name, difficulty, p, f, t, e)` (Game.cs:110-133) or Palm `StartNewGame` plus
    /// the New Commander form (Src/Traveler.c), as selected by `GalaxyRules.generationRollOrder` (RUL-024).
    public static func newGame(ruleset: Ruleset, difficulty: Difficulty, seed: UInt64, commanderName: String,
                               skills: [Int]) -> GeneratedGame {
        var rng = RNGState(kind: ruleset.rngKind, seed: seed)
        let rules = ruleset.flags.galaxy
        var galaxy: Galaxy
        var mercs: [CrewMember] = []
        var attempts = 0
        var placed: Bool
        repeat {
            attempts += 1
            galaxy = generateUniverse(ruleset: ruleset, difficulty: difficulty, rng: &rng)
            // Palm draws the mercenaries before placing events (GAL-011).
            if rules.generationRollOrder == .palm {
                mercs = generateCrew(galaxy: galaxy, ruleset: ruleset, difficulty: difficulty, rng: &rng)
            }
            placed = placeSpecialEvents(&galaxy, ruleset: ruleset, rng: &rng)
                && placeShipyards(&galaxy, ruleset: ruleset, rng: &rng)
        } while !placed && rules.regenerateGalaxyOnPlacementFailure

        // InitializeCommander
        let gnatSpec = ruleset.tables.ship(.gnat)
        var ship = Ship(type: .gnat, spec: gnatSpec)
        ship.crew[0] = CrewID.commander
        ship.weapons.append(.pulseLaser)
        let start = startSystem(galaxy: galaxy, ruleset: ruleset, reach: gnatSpec.fuelTanks, rng: &rng)
        galaxy.systems[start].visited = true
        var commander = Commander(name: commanderName, cash: ruleset.tables.startingCash, debt: 0, kills: Kills(),
                                  policeRecordScore: 0, reputationScore: 0, days: 0, insurance: false, noClaim: 0,
                                  ship: ship, priceCargo: Array(repeating: 0, count: 10), currentSystem: start,
                                  shipName: nil)

        if rules.generationRollOrder == .csharp {
            mercs = generateCrew(galaxy: galaxy, ruleset: ruleset, difficulty: difficulty, rng: &rng)
        }
        mercs[CrewID.commander] = CrewMember(id: CrewID.commander, pilot: skills[0], fighter: skills[1],
                                             trader: skills[2], engineer: skills[3], systemID: nil)
        let special = createShips(ruleset: ruleset)

        // CalculatePrices(Commander.CurrentSystem)
        let system = galaxy.systems[start]
        let criminal = commander.policeRecordScore < -5
        let sell = Pricing.sellPrices(in: system, criminal: criminal, ruleset: ruleset, rng: &rng)
        let trader = Skills.shipSkills(commander.ship, crew: mercs, difficulty: difficulty, ruleset: ruleset)[SkillType.trader.rawValue]
        let buy = Pricing.buyPrices(sell: sell, in: system, criminal: criminal, traderSkill: trader, ruleset: ruleset)

        placeLottery(&galaxy, start: start, difficulty: difficulty, ruleset: ruleset)
        commander.ship = ship
        return GeneratedGame(galaxy: galaxy, mercenaries: mercs, commander: commander, specialShips: special,
                             sellPrices: sell, buyPrices: buy, veryRareEncounters: VeryRareEncounter.allCases,
                             rng: rng, attempts: attempts)
    }

    /// GAL-060 (C#: the start system's event becomes Lottery unconditionally below Normal) / GAL-061 (Palm: only when
    /// the start system still has no event).
    static func placeLottery(_ galaxy: inout Galaxy, start: Int, difficulty: Difficulty, ruleset: Ruleset) {
        guard difficulty < .normal else { return }
        if !ruleset.flags.galaxy.lotteryRequiresFreeStart || galaxy.systems[start].specialEvent == nil {
            galaxy.systems[start].specialEvent = .lottery
        }
    }

    /// Start system: C# `InitializeCommander` (Game.cs:2685-2712, unbounded) or Palm (Traveler.c:1601-1630, 200 tries,
    /// strict tech on tries 0…99, last draw used unchecked when every try fails). RUL-030, RUL-031.
    static func startSystem<R: RandomSource>(galaxy: Galaxy, ruleset: Ruleset, reach: Int, rng: inout R) -> Int {
        let rules = ruleset.flags.galaxy
        let systems = galaxy.systems
        var tries = 0
        var last = 0
        while rules.startSystemMaxTries.map({ tries < $0 }) ?? true {
            let attempt = tries
            tries += 1
            let candidate = rng.next(below: systems.count)
            last = candidate
            let s = systems[candidate]
            guard s.specialEvent == nil else { continue }
            if attempt < rules.startSystemStrictTechTries, !rules.startSystemTechRange.contains(s.techLevel) { continue }
            var close = 0
            for i in systems.indices where close < 3 && i != candidate {
                let ok = rules.startReachUsesSquaredDistance
                    ? sqrDistance(systems[i], s) <= reach * reach
                    : distance(systems[i], s, rule: ruleset.flags.distance) <= reach
                if ok { close += 1 }
            }
            if close >= 3 { return candidate }
        }
        return last
    }

    /// Palm `SqrDistance` (Math.c:60-63): `dx² + dy²` in exact integer arithmetic (GAL-009).
    public static func sqrDistance(_ a: StarSystem, _ b: StarSystem) -> Int {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }

    /// RUL-022: offset added to a wormhole system's grid centre.
    static func centreOffset<R: RandomSource>(_ roll: CentreOffsetRoll, _ offset: Int, rng: inout R) -> Int {
        switch roll {
        case .symmetricRange: -rng.next(in: -offset + 1, offset)
        case .subtractFromHalf: offset - rng.next(below: 2 * offset + 1)
        }
    }

    /// RUL-023: one government/tech draw; `nil` when a rejection-sampled pair is outside the government's range.
    static func governmentAndTech<R: RandomSource>(_ t: RulesTables, _ method: SystemGenerationMethod,
                                                   rng: inout R) -> (PoliticalSystemSpec, TechLevel)? {
        switch method {
        case .governmentThenTech:
            let pol = t.politicalSystems[rng.next(below: t.politicalSystems.count)]
            let tech = TechLevel(rawValue: rng.next(in: pol.minTech.rawValue, pol.maxTech.rawValue + 1)) ?? .preAgricultural
            return (pol, tech)
        case .rejectionSampled:
            let tech = TechLevel(rawValue: rng.next(below: TechLevel.hiTech.rawValue + 1)) ?? .preAgricultural
            let pol = t.politicalSystems[rng.next(below: t.politicalSystems.count)]
            guard pol.minTech <= tech, tech <= pol.maxTech else { return nil }
            return (pol, tech)
        }
    }

    /// RUL-021 on a squared distance (Palm path).
    static func tooClose(squared sq: Int, ruleset: Ruleset) -> Bool {
        let m = ruleset.tables.minDistance
        switch ruleset.flags.galaxy.minDistanceTest {
        case .flooredBelowMinimum: return Int(Double(sq).squareRoot().rounded(.down)) < m
        case .squaredAtMostNextSquare: return sq <= (m + 1) * (m + 1)
        }
    }

    /// C# `Game.GenerateUniverse` (Game.cs:2175) or the Palm system loop (Traveler.c:1341-1441).
    static func generateUniverse<R: RandomSource>(ruleset: Ruleset, difficulty: Difficulty, rng: inout R) -> Galaxy {
        let t = ruleset.tables
        let rules = ruleset.flags.galaxy
        let count = t.systemNames.count
        var systems: [StarSystem] = []
        systems.reserveCapacity(count)
        var wormholes = [Int](repeating: 0, count: 6)
        switch rules.generationRollOrder {
        case .csharp:
            for i in 0..<count {
                var size = SystemSize(rawValue: rng.next(below: SystemSize.huge.rawValue + 1)) ?? .tiny
                var drawn = governmentAndTech(t, rules.systemGenerationMethod, rng: &rng)
                while drawn == nil { drawn = governmentAndTech(t, rules.systemGenerationMethod, rng: &rng) }
                guard var (pol, tech) = drawn else { break }
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
                    x = (t.galaxyWidth * (1 + 2 * (i % 3))) / 6 + centreOffset(rules.centreOffsetRoll, t.centralOffset, rng: &rng)
                    y = (t.galaxyHeight * (i < 3 ? 1 : 3)) / 4 + centreOffset(rules.centreOffsetRoll, t.centralOffset, rng: &rng)
                    wormholes[i] = i
                } else {
                    var ok = false
                    while !ok {
                        x = rng.next(in: 1, t.galaxyWidth)
                        y = rng.next(in: 1, t.galaxyHeight)
                        var closeFound = false
                        var tooNear = false
                        var j = 0
                        while j < i, !tooNear {
                            switch rules.minDistanceTest {
                            case .flooredBelowMinimum:
                                let d = distance(systems[j].x, systems[j].y, x, y, rule: ruleset.flags.distance)
                                if d < t.minDistance { tooNear = true }
                                if d < t.closeDistance { closeFound = true }
                            case .squaredAtMostNextSquare:
                                let sq = (systems[j].x - x) * (systems[j].x - x) + (systems[j].y - y) * (systems[j].y - y)
                                if tooClose(squared: sq, ruleset: ruleset) { tooNear = true }
                                if sq < t.closeDistance * t.closeDistance { closeFound = true }
                            }
                            j += 1
                        }
                        ok = closeFound && !tooNear
                    }
                }
                var s = StarSystem(id: i, x: x, y: y, size: size, techLevel: tech, politics: pol.type, pressure: pressure,
                                   specialResource: resource)
                s.tradeItems = Pricing.initialQuantities(for: s, difficulty: difficulty, ruleset: ruleset, rng: &rng)
                systems.append(s)
            }
        case .palm:
            // GAL-023: `i` advances only when an attempt is accepted; every rejection restarts from new X and Y.
            while systems.count < count {
                let i = systems.count
                let x: Int, y: Int
                if i < wormholes.count {
                    x = centreOffset(rules.centreOffsetRoll, t.centralOffset, rng: &rng) + (t.galaxyWidth * (1 + 2 * (i % 3))) / 6
                    y = centreOffset(rules.centreOffsetRoll, t.centralOffset, rng: &rng) + (t.galaxyHeight * (i < 3 ? 1 : 3)) / 4
                    wormholes[i] = i
                } else {
                    x = 1 + rng.next(below: t.galaxyWidth - 2)
                    y = 1 + rng.next(below: t.galaxyHeight - 2)
                    var closeFound = false
                    var tooNear = false
                    for j in 0..<i {
                        let sq = (systems[j].x - x) * (systems[j].x - x) + (systems[j].y - y) * (systems[j].y - y)
                        if tooClose(squared: sq, ruleset: ruleset) {
                            tooNear = true
                            break
                        }
                        if sq < t.closeDistance * t.closeDistance { closeFound = true }
                    }
                    if tooNear || !closeFound { continue }
                }
                guard let (pol, tech) = governmentAndTech(t, rules.systemGenerationMethod, rng: &rng) else { continue }
                let resource = rng.next(below: 5) >= 3
                    ? SpecialResource(rawValue: 1 + rng.next(below: SpecialResource.warlike.rawValue)) ?? .nothing
                    : .nothing
                let size = SystemSize(rawValue: rng.next(below: SystemSize.huge.rawValue + 1)) ?? .tiny
                let pressure = rng.next(below: 100) < 15
                    ? SystemPressure(rawValue: 1 + rng.next(below: SystemPressure.employment.rawValue)) ?? .none
                    : .none
                var s = StarSystem(id: i, x: x, y: y, size: size, techLevel: tech, politics: pol.type, pressure: pressure,
                                   specialResource: resource)
                s.tradeItems = Pricing.initialQuantities(for: s, difficulty: difficulty, ruleset: ruleset, rng: &rng)
                systems.append(s)
            }
        }
        // Shuffle locations so early-alphabet systems are not all central (GAL-029; identical in Palm).
        for i in 0..<count {
            let j = rng.next(below: count)
            if !wormholes.contains(j) {
                (systems[i].x, systems[j].x) = (systems[j].x, systems[i].x)
                (systems[i].y, systems[j].y) = (systems[j].y, systems[i].y)
                if let w = wormholes.firstIndex(of: i) { wormholes[w] = j }
            }
        }
        // Randomize wormhole order (GAL-030).
        for i in 0..<wormholes.count {
            let j = rng.next(below: wormholes.count)
            wormholes.swapAt(i, j)
        }
        return Galaxy(systems: systems, wormholes: wormholes)
    }

    /// C# `Game.FindDistantSystem` / Palm's distant loops: the closest system ≥ 70 parsecs from `base` without an event,
    /// ties to the lowest index, with Palm's (buggy) exclusion when requested (RUL-027).
    static func findDistantSystem(_ galaxy: inout Galaxy, from base: Int, event: SpecialEventType, rule: DistanceRule,
                                  exclusion: DistantExclusion = .none) -> Bool {
        var best = 999
        var found = -1
        for i in galaxy.systems.indices {
            let d = distance(galaxy.systems[base], galaxy.systems[i], rule: rule)
            guard d >= 70, d < best, galaxy.systems[i].specialEvent == nil else { continue }
            switch exclusion {
            case .none: break
            case .bestDistanceNotGemulonDaled:
                if best == SystemID.gemulon || best == SystemID.daled { continue }
            case .bestIndexNotDaledGemulon:
                if found == SystemID.daled || found == SystemID.gemulon { continue }
            }
            found = i
            best = d
        }
        if found >= 0 { galaxy.systems[found].specialEvent = event }
        return found >= 0
    }

    /// Whether the content pack carries `event` (Palm has no Sculpture or Princess events).
    static func contentHas(_ event: SpecialEventType, _ ruleset: Ruleset) -> Bool {
        let princess: [SpecialEventType] = [.princess, .princessCentauri, .princessInthara, .princessQonos,
                                            .princessQuantum, .princessReturned]
        let sculpture: [SpecialEventType] = [.sculpture, .sculptureDelivered, .sculptureHiddenBays]
        if princess.contains(event), !ruleset.content.hasPrincessQuest { return false }
        if sculpture.contains(event), !ruleset.content.hasSculptureQuest { return false }
        return ruleset.tables.specialEvents.contains { $0.type == event }
    }

    /// C# `Game.PlaceSpecialEvents` (Game.cs:2880) or Palm's placement (Traveler.c:1484-1598): fixed events, then the
    /// ruleset's `eventPlacement` steps. Returns false on a failure only when the ruleset regenerates (RUL-025).
    static func placeSpecialEvents<R: RandomSource>(_ galaxy: inout Galaxy, ruleset: Ruleset, rng: inout R) -> Bool {
        let rules = ruleset.flags.galaxy
        let regenerate = rules.regenerateGalaxyOnPlacementFailure
        let count = galaxy.systems.count
        for f in ruleset.tables.fixedSpecialEvents where f.system < count && contentHas(f.event, ruleset) {
            galaxy.systems[f.system].specialEvent = f.event
        }
        var freeWormhole = true
        var artifactDeliveryFailed = false
        for step in rules.eventPlacement {
            switch step {
            case .scarabEndpoint:
                switch rules.scarabEndpointPlacement {
                case .firstFreeWormhole:
                    if let w = galaxy.wormholes.first(where: { galaxy.systems[$0].specialEvent == nil }) {
                        galaxy.systems[w].specialEvent = .scarabDestroyed
                    } else {
                        if regenerate { return false }
                        freeWormhole = false
                    }
                case .randomWormhole(let retries):
                    // GAL-042: the G/D/N clause is reproduced (the end-point may land there and be overwritten).
                    let quirk = [SystemID.gemulon, SystemID.daled, SystemID.nix]
                    var k = 0
                    var j = rng.next(below: galaxy.wormholes.count)
                    while galaxy.systems[galaxy.wormholes[j]].specialEvent != nil, !quirk.contains(galaxy.wormholes[j]),
                          k < retries {
                        j = rng.next(below: galaxy.wormholes.count)
                        k += 1
                    }
                    if k < retries {
                        galaxy.systems[galaxy.wormholes[j]].specialEvent = .scarabDestroyed
                    } else {
                        if regenerate { return false }
                        freeWormhole = false
                    }
                }
            case .artifactDelivery:
                var placedAt: Int?
                switch rules.artifactDeliveryPlacement {
                case .lowestIndexHiTech:
                    placedAt = galaxy.systems.indices.first {
                        galaxy.systems[$0].specialEvent == nil && galaxy.systems[$0].techLevel == .hiTech
                    }
                case .randomTries(let tries):
                    let first = max(1, rules.randomEventFirstSystem)
                    for _ in 0..<tries {
                        let d = first + rng.next(below: count - first)
                        if galaxy.systems[d].specialEvent == nil, galaxy.systems[d].techLevel >= .hiTech,
                           d != SystemID.gemulon, d != SystemID.daled {
                            placedAt = d
                            break
                        }
                    }
                }
                if let placedAt {
                    galaxy.systems[placedAt].specialEvent = .artifactDelivery
                } else {
                    if regenerate { return false }
                    artifactDeliveryFailed = true
                }
            case let .distant(base, event, baseEvent, exclusion):
                guard base < count, contentHas(event, ruleset) else { continue }
                let found = findDistantSystem(&galaxy, from: base, event: event, rule: ruleset.flags.distance,
                                              exclusion: rules.distantPlacementExclusionBug ? exclusion : .none)
                if found {
                    if let baseEvent { galaxy.systems[base].specialEvent = baseEvent }
                } else if regenerate {
                    return false
                }
            case .randomEvents:
                let first = rules.randomEventFirstSystem
                for spec in ruleset.tables.specialEvents where spec.occurrence > 0 {
                    // GAL-044: a failed Palm artifact delivery zeroes the Alien Artifact occurrence for this game.
                    let n = spec.type == .artifact && artifactDeliveryFailed ? 0 : spec.occurrence
                    for _ in 0..<n {
                        var s: Int
                        repeat {
                            s = first + rng.next(below: count - first)
                        } while galaxy.systems[s].specialEvent != nil
                        // GAL-047: without a free wormhole the Scarab's draws are consumed but nothing is placed.
                        if spec.type != .scarab || freeWormhole { galaxy.systems[s].specialEvent = spec.type }
                    }
                }
            }
        }
        return true
    }

    /// C# `Game.PlaceShipyards`: each of the 5 shipyards on a random Hi-Tech system (collisions allowed unless
    /// `distinctShipyards`). Fails if fewer than 5 Hi-Tech systems exist. No draws without shipyards (Palm, GAL-051).
    static func placeShipyards<R: RandomSource>(_ galaxy: inout Galaxy, ruleset: Ruleset, rng: inout R) -> Bool {
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

    /// C# `Game.GenerateCrewMemberList` (Game.cs:2121) or the Palm mercenary loop (Traveler.c:1443-1481), driven by the
    /// content pack's roster (RUL-017).
    static func generateCrew<R: RandomSource>(galaxy: Galaxy, ruleset: Ruleset, difficulty: Difficulty,
                                              rng: inout R) -> [CrewMember] {
        let d = difficulty.rawValue
        let content = ruleset.content
        var used = [Int](repeating: 0, count: galaxy.systems.count)
        if SystemID.kravat < used.count { used[SystemID.kravat] = content.kravatMercenaryPreCount }
        var crew = [CrewMember?](repeating: nil, count: CrewID.count)
        func put(_ id: Int, _ p: Int, _ f: Int, _ t: Int, _ e: Int) {
            guard !content.randomMercenaryIDs.contains(id) else { return }
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
        for i in content.randomMercenaryIDs {
            var sys: Int
            repeat {
                sys = rng.next(below: galaxy.systems.count)
            } while used[sys] >= content.mercenariesPerSystem
            used[sys] += 1
            crew[i] = CrewMember(id: i, pilot: rng.randomSkill(), fighter: rng.randomSkill(), trader: rng.randomSkill(),
                                 engineer: rng.randomSkill(), systemID: sys)
        }
        for id in content.unplacedMercenaryIDs { crew[id]?.systemID = nil }
        crew[CrewID.commander] = CrewMember(id: 0, pilot: 1, fighter: 1, trader: 1, engineer: 1, systemID: nil)
        // Ids the content pack does not use (Palm 38…52) stay unplaced placeholders so crew ids keep indexing the array.
        return crew.enumerated().map { $1 ?? CrewMember(id: $0, pilot: 1, fighter: 1, trader: 1, engineer: 1, systemID: nil) }
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
