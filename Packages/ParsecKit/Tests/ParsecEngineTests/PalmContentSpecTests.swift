// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
@testable import ParsecEngine

/// Palm 1.2.2 content pack and the general ruleset requirements (docs/specs/RUL.md §1, §5 General/Content packs;
/// GAL-002, GAL-006, GAL-040, GAL-063).
@Suite("Palm content pack and ruleset structure (RUL-001…019)")
struct PalmContentSpecTests {
    static let all: [Ruleset] = [.modern, .windows201, .palm122]

    static func game(_ r: Ruleset, seed: UInt64, difficulty: Difficulty = .normal) -> GeneratedGame {
        GalaxyGenerator.newGame(ruleset: r, difficulty: difficulty, seed: seed, commanderName: "T", skills: [5, 5, 5, 5])
    }

    static var engineSources: [(name: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/ParsecEngine")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        return files.compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).map { (url.lastPathComponent, $0) } }
    }

    // MARK: General

    @Test("RUL-001 every ruleset exposes tables, flags, content and rngKind; no engine source compares a ruleset id")
    func noRulesetIDBranches() throws {
        for r in Self.all {
            let labels = Set(Mirror(reflecting: r).children.compactMap(\.label))
            #expect(labels.isSuperset(of: ["id", "tables", "flags", "content", "rngKind"]), "\(r.id)")
            #expect(Ruleset.named(r.id).id == r.id)
        }
        let sources = Self.engineSources
        #expect(sources.count > 20)
        let ids = "(modern|windows201|palm122)"
        let alternatives = [#"ruleset\.id"#, #"\br\.id\s*[!=]="#, #"rulesetID\s*[!=]="#, #"[!=]=\s*\."# + ids + #"\b"#,
                            #"case\s+\."# + ids + #"\s*:"#, #"RulesetID\."# + ids]
        let pattern = try Regex(alternatives.joined(separator: "|"))
        for (name, text) in sources where name != "Ruleset.swift" {
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                #expect(line.firstMatch(of: pattern) == nil, "\(name):\(n + 1) compares a ruleset id: \(line)")
            }
        }
        // Ruleset.swift itself only maps ids to presets (`named`), it never branches on behaviour.
        let rulesetFile = try #require(sources.first { $0.name == "Ruleset.swift" }).text
        let caseLines = rulesetFile.split(separator: "\n").filter { $0.firstMatch(of: pattern) != nil }
        #expect(caseLines.count == 3 && caseLines.allSatisfy { $0.contains(": .") }, "\(caseLines)")
    }

    @Test("RUL-002 the ruleset is fixed at New Game, survives a save round trip and no command changes it")
    func rulesetStoredInSave() throws {
        for id in RulesetID.allCases {
            var e = makeEngine(id, seed: 5)
            #expect(e.state.rulesetID == id && e.ruleset.id == id)
            let commands: [Command] = [.buyFuel(credits: 10), .buyCargo(.water, quantity: 1), .borrow(500),
                                       .setOptions(GameOptions()), .selectTarget(3), .track(4), .warp, .readNewspaper]
            for c in commands { _ = e.perform(c, acknowledging: Set(WarningID.allCases)) }
            #expect(e.state.rulesetID == id)
            let data = try JSONEncoder().encode(e.state)
            let loaded = try JSONDecoder().decode(GameState.self, from: data)
            #expect(loaded.rulesetID == id && loaded.ruleset.id == id && loaded == e.state)
        }
    }

    @Test("RUL-003 rows without a MOD or kept-as-designed note: Modern equals Windows 2.01 (galaxy rules, distance, content tables)")
    func modernEqualsWindowsOnUnflaggedRows() {
        let m = Ruleset.modern, w = Ruleset.windows201
        #expect(m.flags.galaxy == w.flags.galaxy)
        #expect(m.flags.distance == w.flags.distance)
        #expect(m.tables.ships == w.tables.ships && m.tables.weapons == w.tables.weapons && m.tables.shields == w.tables.shields)
        #expect(m.tables.gadgets == w.tables.gadgets && m.tables.tradeItems == w.tables.tradeItems)
        #expect(m.tables.politicalSystems == w.tables.politicalSystems && m.tables.specialEvents == w.tables.specialEvents)
        #expect(m.tables.fixedSpecialEvents == w.tables.fixedSpecialEvents && m.tables.systemNames == w.tables.systemNames)
        #expect(m.tables.galaxyWidth == w.tables.galaxyWidth && m.tables.minDistance == w.tables.minDistance)
        #expect(m.content.hasShipyards == w.content.hasShipyards && m.content.hasDisruptors == w.content.hasDisruptors)
        #expect(m.content.randomMercenaryIDs == w.content.randomMercenaryIDs
                && m.content.mercenariesPerSystem == w.content.mercenariesPerSystem)
        #expect(m.newspaperRNG == w.newspaperRNG)
    }

    @Test("RUL-004 table-driven: the three presets match the RUL §1 content rows and the §2 galaxy rows RUL-020…031")
    func presetsMatchTable() {
        typealias Row = (String, (Ruleset) -> String, [String])   // values for Modern, Windows 2.01, Palm 1.2.2
        let rows: [Row] = [
            ("RUL-010 systems", { "\($0.tables.systemNames.count)" }, ["128", "128", "120"]),
            ("RUL-011 size", { "\($0.tables.galaxyWidth)x\($0.tables.galaxyHeight)" }, ["154x110", "154x110", "150x110"]),
            ("RUL-012 events", { "\($0.tables.specialEvents.count)" }, ["46", "46", "37"]),
            ("RUL-013 quests", { "\($0.content.hasSculptureQuest)/\($0.content.hasPrincessQuest)" },
             ["true/true", "true/true", "false/false"]),
            ("RUL-014 shipyards", { "\($0.content.hasShipyards)" }, ["true", "true", "false"]),
            ("RUL-015 disruptors", { "\($0.content.hasDisruptors)/\($0.tables.weapons.count)" }, ["true/6", "true/6", "false/4"]),
            ("RUL-016 hidden bays", { "\($0.content.hasHiddenBays)/\($0.tables.gadgets.count)" }, ["true/7", "true/7", "false/6"]),
            ("RUL-017 roster", { "\($0.content.randomMercenaryIDs.count)/\($0.content.mercenariesPerSystem)" },
             ["44/3", "44/3", "31/1"]),
            ("RUL-019 rng", { "\($0.rngKind)/\($0.newspaperRNG)" }, ["xoshiro/csharp", "dotNet/csharp", "palmLCG/palm"]),
            ("RUL-020", { "\($0.flags.distance)" }, ["floor", "floor", "rounded"]),
            ("RUL-021", { "\($0.flags.galaxy.minDistanceTest)" },
             ["flooredBelowMinimum", "flooredBelowMinimum", "squaredAtMostNextSquare"]),
            ("RUL-022", { "\($0.flags.galaxy.centreOffsetRoll)/\($0.tables.centralOffset)" },
             ["symmetricRange/13", "symmetricRange/13", "subtractFromHalf/6"]),
            ("RUL-023", { "\($0.flags.galaxy.systemGenerationMethod)" },
             ["governmentThenTech", "governmentThenTech", "rejectionSampled"]),
            ("RUL-024", { "\($0.flags.galaxy.generationRollOrder)" }, ["csharp", "csharp", "palm"]),
            ("RUL-025", { "\($0.flags.galaxy.regenerateGalaxyOnPlacementFailure)" }, ["true", "true", "false"]),
            ("RUL-026", { "\($0.flags.galaxy.scarabEndpointPlacement)" },
             ["firstFreeWormhole", "firstFreeWormhole", "randomWormhole(retries: 20)"]),
            ("RUL-027", { "\($0.flags.galaxy.distantPlacementExclusionBug)" }, ["false", "false", "true"]),
            ("RUL-028", { "\($0.flags.galaxy.artifactDeliveryPlacement)" },
             ["lowestIndexHiTech", "lowestIndexHiTech", "randomTries(120)"]),
            ("RUL-029", { "\($0.flags.galaxy.randomEventFirstSystem)..\($0.tables.systemNames.count - 1)" },
             ["0..127", "0..127", "1..119"]),
            ("RUL-030", { r in
                let g = r.flags.galaxy
                return "\(g.startSystemMaxTries.map(String.init) ?? "inf")/\(g.startSystemTechRange.lowerBound.rawValue)-\(g.startSystemTechRange.upperBound.rawValue)"
            }, ["inf/1-6", "inf/1-6", "200/1-5"]),
            ("RUL-031", { "\($0.flags.galaxy.startReachUsesSquaredDistance)" }, ["false", "false", "true"]),
        ]
        for (name, value, expected) in rows {
            #expect(Self.all.map(value) == expected, "\(name)")
        }
    }

    @Test("RUL-005 every Palm event is a C# event type with the same title/text key; Palm adds no event type of its own")
    func palmEventsReuseCSharpStrings() {
        let csharp = Set(Ruleset.windows201.tables.specialEvents.map(\.type))
        let palm = Ruleset.palm122.tables.specialEvents.map(\.type)
        #expect(Set(palm).isSubset(of: csharp))
        #expect(Set(palm).count == palm.count)   // one C# string set per Palm entry
        #expect(Ruleset.palm122.tables.fixedSpecialEvents.allSatisfy { csharp.contains($0.event) })
    }

    @Test("RUL-006 the moon-girl ending appears only in Modern after the Princess quest, with the normal moon score")
    func moonGirlEnding() {
        for id in RulesetID.allCases {
            for princessDone in [false, true] {
                var e = makeEngine(id) { s in
                    s.galaxy.systems[s.commander.currentSystem].specialEvent = .moonRetirement
                    s.quests.moon = QuestStatus.Moon.bought
                    s.quests.princess = princessDone ? QuestStatus.Princess.done : QuestStatus.Princess.notStarted
                }
                let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
                let expected: GameEndType = id == .modern && princessDone ? .boughtMoonGirl : .boughtMoon
                #expect(e.state.phase == .gameOver(expected), "\(id) princess \(princessDone)")
                #expect(r.events.last == .gameEnded(expected, score: e.state.score(for: .boughtMoon)), "\(id)")
            }
        }
        #expect(Ruleset.modern.flags.quest.moonGirlEnding)
        #expect(!Ruleset.windows201.flags.quest.moonGirlEnding && !Ruleset.palm122.flags.quest.moonGirlEnding)
    }

    // MARK: Content packs

    @Test("RUL-010 GAL-006 system lists: 128 in Modern/Windows, 120 Palm names identical to C# ids 0…119; Palm fixed ids")
    func systemLists() {
        #expect(Ruleset.modern.tables.systemNames.count == 128 && Ruleset.windows201.tables.systemNames.count == 128)
        let palm = Ruleset.palm122.tables.systemNames
        #expect(palm.count == 120 && palm.first == "Acamar" && palm.last == "Zuul")
        #expect(palm == Array(GameNames.systems.prefix(120)))
        #expect(Self.game(.palm122, seed: 3).galaxy.systems.count == 120)
        let fixed: [(String, Int)] = [("Acamar", 0), ("Baratas", 6), ("Daled", 17), ("Devidia", 22), ("Gemulon", 32),
                                      ("Japori", 41), ("Kravat", 50), ("Melina", 59), ("Nix", 67), ("Regulas", 82),
                                      ("Utopia", 109), ("Zalkon", 118)]
        for (name, id) in fixed { #expect(palm[id] == name, "\(name)") }
        #expect(SystemID.acamar == 0 && SystemID.baratas == 6 && SystemID.daled == 17 && SystemID.devidia == 22)
        #expect(SystemID.gemulon == 32 && SystemID.japori == 41 && SystemID.kravat == 50 && SystemID.melina == 59)
        #expect(SystemID.nix == 67 && SystemID.regulas == 82 && SystemID.utopia == 109 && SystemID.zalkon == 118)
    }

    @Test("RUL-011 GAL-002 Palm galaxy 150×110, MINDISTANCE 6, CLOSEDISTANCE 13, MAXRANGE 20, 6 wormholes")
    func palmConstants() {
        let p = Ruleset.palm122.tables, w = Ruleset.windows201.tables
        #expect(w.galaxyWidth == 154 && w.galaxyHeight == 110 && Ruleset.modern.tables.galaxyWidth == 154)
        #expect(p.galaxyWidth == 150 && p.galaxyHeight == 110 && p.minDistance == 6 && p.closeDistance == 13)
        #expect(p.ship(.flea).fuelTanks == 20)   // MAXRANGE: the Flea's tanks
        for seed in UInt64(0)..<20 {
            let g = Self.game(.palm122, seed: seed).galaxy
            #expect(g.wormholes.count == 6 && Set(g.wormholes).count == 6)
            #expect(g.systems.allSatisfy { $0.x >= 1 && $0.x <= 148 && $0.y >= 1 && $0.y <= 108 })
        }
    }

    @Test("RUL-012 GAL-040 Palm event table: 37 entries in Palm index order; shared events equal the C# rows")
    func palmEventTable() throws {
        let palm = Ruleset.palm122.tables.specialEvents
        let order: [SpecialEventType] = [
            .dragonflyDestroyed, .dragonflyBaratas, .dragonflyMelina, .dragonflyRegulas, .spaceMonsterKilled,
            .japoriDelivery, .moonRetirement, .moon, .skill, .tribble, .eraseRecord, .tribbleBuyer, .spaceMonster,
            .dragonfly, .cargoForSale, .dragonflyShield, .japori, .lottery, .artifactDelivery, .artifact, .jarek,
            .gemulon, .gemulonInvaded, .gemulonFuel, .experiment, .wild, .reactor, .reactorLaser, .scarab,
            .scarabUpgradeHull, .scarabDestroyed, .reactorDelivered, .jarekGetsOut, .gemulonRescued,
            .experimentStopped, .experimentFailed, .wildGetsOut,
        ]
        #expect(palm.map(\.type) == order)
        #expect(Ruleset.windows201.tables.specialEvents.count == 46 && Ruleset.modern.tables.specialEvents.count == 46)
        // 0…6 and 30…36 are fixed (occurrence 0); random ones sit in 7…29.
        for (i, e) in palm.enumerated() where e.occurrence > 0 { #expect((7...29).contains(i), "\(e.type)") }
        let occurrences = Dictionary(uniqueKeysWithValues: palm.map { ($0.type, $0.occurrence) })
        #expect(occurrences[.moon] == 4 && occurrences[.skill] == 3 && occurrences[.eraseRecord] == 3)
        #expect(occurrences[.tribbleBuyer] == 3 && occurrences[.cargoForSale] == 3 && occurrences[.scarab] == 1)
        let prices = Dictionary(uniqueKeysWithValues: palm.map { ($0.type, $0.price) })
        #expect(prices[.moon] == 500_000 && prices[.spaceMonsterKilled] == -15_000 && prices[.artifactDelivery] == -20_000)
        #expect(prices[.lottery] == -1_000 && prices[.skill] == 3_000 && prices[.eraseRecord] == 5_000)
        for e in palm {
            let c = try #require(Ruleset.windows201.tables.specialEvents.first { $0.type == e.type })
            #expect(c == e, "\(e.type) differs from the C# row")
        }
    }

    @Test("RUL-013 Sculpture, Princess and Scorpion content exist in Modern/Windows and are absent in Palm")
    func palmQuestsAbsent() {
        let quest: Set<SpecialEventType> = [.sculpture, .sculptureDelivered, .sculptureHiddenBays, .princess,
                                            .princessCentauri, .princessInthara, .princessQonos, .princessQuantum,
                                            .princessReturned]
        #expect(Set(Ruleset.palm122.tables.specialEvents.map(\.type)).isDisjoint(with: quest))
        for seed in UInt64(0)..<50 {
            let palm = Self.game(.palm122, seed: seed).galaxy.systems.compactMap(\.specialEvent)
            #expect(Set(palm).isDisjoint(with: quest), "seed \(seed)")
            let win = Set(Self.game(.windows201, seed: seed).galaxy.systems.compactMap(\.specialEvent))
            #expect(win.isSuperset(of: [.sculpture, .sculptureDelivered, .princess, .princessQonos]), "seed \(seed)")
        }
        // No Princess quest → status never leaves 0, which is what gates the Scorpion encounter.
        let e = makeEngine(.palm122)
        #expect(e.state.quests.princess == QuestStatus.Princess.notStarted && !Ruleset.palm122.content.hasPrincessQuest)
    }

    @Test("RUL-014 shipyards and the designer exist in Modern/Windows and are absent in Palm")
    func palmNoShipyards() {
        for seed in UInt64(0)..<50 {
            #expect(Self.game(.palm122, seed: seed).galaxy.systems.allSatisfy { $0.shipyard == nil }, "seed \(seed)")
            #expect(Self.game(.modern, seed: seed).galaxy.systems.contains { $0.shipyard != nil })
        }
        var e = makeEngine(.palm122)
        e.state.galaxy.systems[e.state.commander.currentSystem].shipyard = .corellian   // even a forced yard is ignored
        #expect(e.state.designQuote(ShipDesign(name: "X", size: .small, cargoBays: 10, fuelTanks: 10, hull: 50,
                                                weaponSlots: 1, shieldSlots: 0, gadgetSlots: 0, crewQuarters: 1)) == nil)
        var m = makeEngine(.modern)
        m.state.galaxy.systems[m.state.commander.currentSystem].shipyard = .corellian
        #expect(m.state.designQuote(ShipDesign(name: "X", size: .small, cargoBays: 10, fuelTanks: 10, hull: 50,
                                                weaponSlots: 1, shieldSlots: 0, gadgetSlots: 0, crewQuarters: 1)) != nil)
    }

    @Test("RUL-015 Palm weapons are Pulse, Beam, Military and Morgan's only; disruptors cannot be bought")
    func palmNoDisruptors() {
        let p = Ruleset.palm122.tables
        #expect(p.weapons.map(\.type) == [.pulseLaser, .beamLaser, .militaryLaser, .morgansLaser])
        #expect(p.weapons.allSatisfy { !$0.disabling } && !Ruleset.palm122.content.hasDisruptors)
        #expect(!p.contains(WeaponType.photonDisruptor) && !p.contains(WeaponType.quantumDisruptor))
        #expect(Ruleset.windows201.tables.weapon(.photonDisruptor).disabling && Ruleset.modern.content.hasDisruptors)
        var e = makeEngine(.palm122) { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 1_000_000
        }
        #expect(e.perform(.buyWeapon(.photonDisruptor), acknowledging: [.buyEquipment]).rejection == .notSoldHere)
        #expect(e.perform(.buyWeapon(.quantumDisruptor), acknowledging: [.buyEquipment]).rejection == .notSoldHere)
        var w = makeEngine(.windows201) { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 1_000_000
            s.commander.ship.weapons = []
        }
        #expect(w.perform(.buyWeapon(.photonDisruptor), acknowledging: [.buyEquipment]).rejection == nil)
    }

    @Test("RUL-016 Palm has no hidden cargo bays")
    func palmNoHiddenBays() {
        let p = Ruleset.palm122.tables
        #expect(p.gadgets.map(\.type) == [.extraCargoBays, .autoRepairSystem, .navigatingSystem, .targetingSystem,
                                          .cloakingDevice, .fuelCompactor])
        #expect(!p.contains(GadgetType.hiddenCargoBays) && !Ruleset.palm122.content.hasHiddenBays)
        #expect(Ruleset.windows201.tables.contains(GadgetType.hiddenCargoBays) && Ruleset.modern.content.hasHiddenBays)
        var e = makeEngine(.palm122) { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 1_000_000
        }
        #expect(e.perform(.buyGadget(.hiddenCargoBays), acknowledging: [.buyEquipment]).rejection == .notSoldHere)
        #expect(e.state.transferPrice(.hiddenCargoBays) == 0)
    }

    @Test("RUL-017 GAL-055 GAL-056 rosters: C# up to 3 per system (Kravat ≤ 2); Palm 1…29 at distinct non-Kravat systems")
    func mercenaryRosters() {
        for seed in UInt64(0)..<100 {
            for r in [Ruleset.windows201, .modern] {
                let m = Self.game(r, seed: seed).mercenaries
                #expect(m.count == 55)
                var per = [Int: Int]()
                for c in m { if let s = c.systemID { per[s, default: 0] += 1 } }
                #expect(per.values.allSatisfy { $0 <= 3 } && per[SystemID.kravat, default: 0] <= 2)
                #expect(m.filter { $0.systemID != nil }.count == 44)
            }
            let palm = Self.game(.palm122, seed: seed).mercenaries
            #expect(palm.count == CrewID.count)
            let placed = palm.filter { $0.systemID != nil }
            #expect(placed.map(\.id) == Array(1...29), "seed \(seed)")
            let systems = placed.compactMap(\.systemID)
            #expect(Set(systems).count == 29 && !systems.contains(SystemID.kravat) && systems.allSatisfy { $0 < 120 })
            // Zeethibal (30) and the opponent scratch slot (31) are drawn (random skills) but nowhere to hire.
            #expect(palm[CrewID.zeethibal].systemID == nil && palm[CrewID.opponent].systemID == nil)
            #expect(palm[1...31].allSatisfy { $0.skills.allSatisfy { (1...10).contains($0) } })
            #expect(palm[0].skills == [5, 5, 5, 5])
        }
        let e = makeEngine(.palm122)
        #expect(e.state.mercenariesForHire.allSatisfy { (1...29).contains($0) })
    }

    @Test("RUL-019 RNG packs: Xoshiro/DotNet/Palm LCG game RNG; C# MWC news (Modern, Windows) and the Palm UInt16 recurrence")
    func rngPacks() {
        #expect(Ruleset.modern.rngKind == .xoshiro && Ruleset.windows201.rngKind == .dotNet && Ruleset.palm122.rngKind == .palmLCG)
        #expect(makeEngine(.palm122).state.rng.kind == .palmLCG && makeEngine(.modern).state.rng.kind == .xoshiro)
        #expect(Ruleset.modern.newspaperRNG == .csharp && Ruleset.windows201.newspaperRNG == .csharp)
        #expect(Ruleset.palm122.newspaperRNG == .palm)
        var p = PieterRand(variant: .palm)
        p.seed(1234, 4321)
        var y: Int64 = 4321
        for _ in 0..<50 {
            y = (30_903 * y) & 0xFFFF
            #expect(p.rand() == y)
        }
        // RandSeed arguments are truncated to UInt16.
        var a = PieterRand(variant: .palm), b = PieterRand(variant: .palm)
        a.seed(65_536 + 77, 65_536 * 3 + 9)
        b.seed(77, 9)
        for _ in 0..<10 { #expect(a.rand() == b.rand()) }
        var c = PieterRand(variant: .csharp)
        c.seed(77, 9)
        let x1 = 18_000 * 77 + 0, y1 = 30_903 * 9 + 0
        #expect(c.rand() == Int64((x1 << 16) + (y1 & 0xFFFF)))
    }

    @Test("GAL-063 Palm builds the special ships with Palm's fixed equipment, drawing nothing; Monster hull 500")
    func palmSpecialShips() {
        let s = GalaxyGenerator.createShips(ruleset: .palm122)
        #expect(s.spaceMonster.hull == 500 && s.spaceMonster.weapons == [.militaryLaser, .militaryLaser, .militaryLaser])
        #expect(s.scarab.hull == 400 && s.scarab.weapons == [.militaryLaser, .militaryLaser] && s.scarab.shields.isEmpty)
        #expect(s.dragonfly.hull == 10 && s.dragonfly.weapons == [.militaryLaser, .pulseLaser])
        #expect(s.dragonfly.shields.map(\.type) == [.lightning, .lightning, .lightning]
                && s.dragonfly.shields.allSatisfy { $0.charge == 350 })
        #expect(s.dragonfly.gadgets == [.autoRepairSystem, .targetingSystem])
        #expect(makeEngine(.palm122).state.specialShips.spaceMonster.hull == 500)
    }

    @Test("Palm ship table: Palm fuel/repair columns (the C# port swapped them), every other column equal")
    func palmFuelRepairColumns() {
        let p = Ruleset.palm122.tables.ships, w = Ruleset.windows201.tables.ships
        #expect(p.prefix(10).map(\.fuelCost) == [1, 2, 3, 5, 7, 10, 15, 15, 20, 20])
        #expect(p.prefix(10).map(\.repairCost) == [1, 1, 1, 1, 1, 1, 2, 3, 4, 5])
        for (a, b) in zip(p.prefix(10), w.prefix(10)) {
            #expect(a.fuelCost == b.repairCost && a.repairCost == b.fuelCost)
            var a2 = a
            a2.fuelCost = b.fuelCost
            a2.repairCost = b.repairCost
            #expect(a2 == b, "\(a.type) differs beyond the swapped columns")
        }
    }
}
