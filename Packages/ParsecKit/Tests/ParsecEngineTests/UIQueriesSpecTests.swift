// SPDX-License-Identifier: GPL-2.0-or-later
// UI-SHELL-115…123 (docs/specs/UI-SHELL.md "Engine additions"), SHP-077, SHP-079: the read-only queries the app shell
// reads. This file imports ParsecEngine WITHOUT @testable, so it compiles only while every query it calls is public.
import Testing
import Foundation
import ParsecEngine

/// Deterministic test values (SplitMix64).
private struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func engine(_ ruleset: RulesetID = .windows201, seed: UInt64 = 42,
                    _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
    var s = GameEngine(config: NewGameConfig(commanderName: "Test", ruleset: ruleset, seed: seed)).state
    adjust(&s)
    return GameEngine(state: s)
}

private func ship(_ type: ShipType, _ r: RulesetID, crew: [Int?] = [0]) -> Ship {
    var s = Ship(type: type, spec: Ruleset.named(r).tables.ship(type))
    s.crew = crew + Array(repeating: nil, count: max(0, s.crew.count - crew.count))
    return s
}

@Suite("UI shell engine queries (UI-SHELL-115…123)")
struct UIQueriesSpecTests {
    // MARK: UI-SHELL-115

    @Test("UI-SHELL-115 MAP-093 every preview and query the app reads is public and leaves the state unchanged")
    func publicQueries() {
        for r in RulesetID.allCases {
            let e = engine(r)
            let before = e.state
            let s = e.state
            let item = TradeItemType.water
            _ = (s.marketRows, s.marketBuyCheck(item), s.marketSellCheck(item, dump: false), s.marketFreeBays, s.cashToSpend)
            _ = (s.fuelCapacity, s.fullTankCost, s.fullRepairCost, s.escapePodOffered, s.shipsForSale)
            _ = (s.shipQuote(.firefly), s.shipWorth(forInsurance: false), s.shipWorth(forInsurance: true))
            let design = Designer.minimumDesign(size: .small, yard: .corellian)
            _ = (s.designQuote(design), Designer.sizes(for: .corellian), Designer.normalized(design, yard: .incom))
            _ = (s.crewPreview, s.mercenariesForHire, s.bankPreview, s.dailyCosts(to: s.warpSystem), s.interestCosts)
            _ = (s.destinations, s.warpTargetPreview(s.destinations.first ?? s.warpSystem), s.jumpPreview, s.transitPreview)
            _ = (s.policeRecord, s.reputation, s.shipSkills, s.worth, s.specialEventAvailable)
            _ = (s.specialEventSpec(.moon), s.scoreTenths(for: .retired))
            _ = (s.equipmentMarket, s.questLog, GalaxyCode(s).string)
            // MAP-093: the galaxy chart and route planner queries.
            _ = (s.ruleset.flags.distance.maxSquaredDistance(withinRange: s.fuelCapacity), s.fuelCostPerParsec,
                 s.wormholeTaxPerJump)
            let config = NewGameConfig(commanderName: "Q", ruleset: r, seed: 7)
            _ = (CommanderRules.validate(config), CommanderRules.preview(name: "Q", skills: [5, 5, 5, 5]))
            _ = (e.encounterPreview, e.policeStatus)
            let started = try? GameEngine.newGame(config).get()
            #expect(started?.state.seed == 7)
            #expect(e.state == before, "\(r)")
        }
    }

    // MARK: UI-SHELL-116 / 117

    @Test("UI-SHELL-116 UI-SHELL-117 galaxy code golden values in both directions")
    func galaxyCodeGolden() {
        let golden: [(GalaxyCode, String)] = [
            (GalaxyCode(ruleset: .modern, difficulty: .normal, seed: 1), "M2-1-V"),
            (GalaxyCode(ruleset: .windows201, difficulty: .normal, seed: 3_735_928_559), "W2-3FAV-FQF-1"),
            (GalaxyCode(ruleset: .palm122, difficulty: .impossible, seed: .max), "P4-FZZZ-ZZZZ-ZZZZ-Z-S"),
            (GalaxyCode(ruleset: .modern, difficulty: .beginner, seed: 0), "M0-0-M"),
        ]
        for (code, string) in golden {
            #expect(code.string == string)
            #expect(GalaxyCode(string: string) == code)
        }
        #expect(GalaxyCode(string: "m2-1-v") == golden[0].0)
        #expect(GalaxyCode(string: "M 2 1 V") == golden[0].0)
        // Crockford look-alikes: O → 0, I and L → 1.
        #expect(GalaxyCode(string: "MO-O-M") == golden[3].0)
        #expect(GalaxyCode(string: "M2-I-V") == golden[0].0 && GalaxyCode(string: "M2-l-V") == golden[0].0)
    }

    @Test("UI-SHELL-117 invalid galaxy codes are rejected")
    func galaxyCodeInvalid() {
        let invalid = [
            "", "M2V", "X2-1-V", "M5-1-V", "M2--V", "M2-1-W", "M2-U-V",
            // (Codes below are written without hyphens so they don't look like requirement IDs to spec-trace.)
            "M2 0000 0000 0000 01 ?",
            // 14 seed symbols, and a 13-symbol seed above UInt64.max (first symbol G = 16).
            "M2 0000 0000 0000 01 " + String(Self.check("M200000000000001")),
            "P4 GZZZ ZZZZ ZZZZ Z " + String(Self.check("P4GZZZZZZZZZZZZ")),
        ]
        for s in invalid { #expect(GalaxyCode(string: s) == nil, "\(s)") }
        // The 14-symbol case has a valid check symbol, so it is rejected for its length only.
        #expect(GalaxyCode(string: "M2 000 0000 0000 01 " + String(Self.check("M20000000000001"))) != nil)
    }

    /// The check symbol of UI-SHELL-116 over raw symbols.
    static func check(_ symbols: String) -> Character {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        let sum = symbols.enumerated().reduce(0) { $0 + ($1.offset + 1) * (alphabet.firstIndex(of: $1.element) ?? 0) }
        return alphabet[sum % 32]
    }

    @Test("UI-SHELL-117 round trip of 10,000 random codes per ruleset")
    func galaxyCodeRoundTrip() {
        var rng = SplitMix(state: 117)
        for r in RulesetID.allCases {
            for i in 0..<10_000 {
                let bits = rng.next()
                // Spread the seed lengths: shift by 0…63 bits.
                let seed = i % 2 == 0 ? bits : bits >> (rng.next() % 64)
                let code = GalaxyCode(ruleset: r, difficulty: Difficulty.allCases[Int(rng.next() % 5)], seed: seed)
                #expect(GalaxyCode(string: code.string) == code)
            }
        }
    }

    // MARK: UI-SHELL-118

    @Test("UI-SHELL-118 the same galaxy code gives the same galaxy for any commander")
    func sameGalaxy() {
        for r in RulesetID.allCases {
            for difficulty in [Difficulty.beginner, .hard] {
                let code = GalaxyCode(ruleset: r, difficulty: difficulty, seed: 2_026)
                func start(_ name: String, _ skills: [Int]) -> GameState {
                    GameEngine(config: NewGameConfig(commanderName: name, difficulty: code.difficulty, skills: skills,
                                                     ruleset: code.ruleset, seed: code.seed)).state
                }
                let a = start("Alice", [5, 5, 5, 5]), b = start("Bartholomew", [10, 1, 8, 1])
                #expect(a.galaxy == b.galaxy)
                #expect(a.mercenaries.map(\.systemID) == b.mercenaries.map(\.systemID))
                #expect(a.commander.currentSystem == b.commander.currentSystem)
                #expect(GalaxyCode(a) == code && GalaxyCode(b) == code)
            }
        }
    }

    // MARK: UI-SHELL-119 / SHP-079

    /// Fixture states for the ship-purchase blockers, keyed by the error each should trigger for some type.
    static func shipFixtures(_ r: RulesetID) -> [(CommandError?, GameEngine)] {
        let passengersAsCrew = r != .palm122
        func base(_ adjust: @escaping (inout GameState) -> Void) -> GameEngine {
            engine(r) { s in
                s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
                s.commander.cash = 1_000_000
                adjust(&s)
            }
        }
        return [
            (nil, base { _ in }),
            (.notSoldHere, base { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .earlyIndustrial }),
            (.alreadyOwnThisShipType, base { _ in }),
            (.inDebt, base { s in s.commander.debt = 500 }),
            (.insufficientFunds, base { s in s.commander.cash = 0 }),
            (.passengersNeedQuarters, base { s in
                s.commander.ship = ship(.beetle, r, crew: passengersAsCrew ? [0, CrewID.jarek, CrewID.wild] : [0])
                s.quests.jarek = QuestStatus.Jarek.started
                s.quests.wild = QuestStatus.Wild.started
            }),
            (.notEnoughQuarters, base { s in s.commander.ship = ship(.beetle, r, crew: [0, 1, 2]) }),
            (.reactorOnBoard, base { s in s.commander.ship = ship(.beetle, r); s.quests.reactor = 3 }),
            (.notAllowedInPhase, base { s in
                s.phase = .encounter(EncounterState(type: .pirateAttack, opponent: ship(.gnat, r)))
            }),
            (.gameOver, base { s in s.phase = .gameOver(.retired) }),
        ]
    }

    @Test("UI-SHELL-119 SHP-079 ShipQuote.blocker equals the rejection of buyShip for every type and fixture")
    func shipBlocker() {
        for r in RulesetID.allCases {
            for (expected, fixture) in Self.shipFixtures(r) {
                var seen: [CommandError?] = []
                for type in ShipType.buyable {
                    var e = fixture
                    let quote = e.state.shipQuote(type)
                    let result = e.perform(.buyShip(type, transfers: []))
                    #expect(quote.blocker == result.rejection, "\(r) \(type) \(String(describing: expected))")
                    if quote.blocker == nil {
                        if case .confirm(let c) = result.decision { #expect(c.warning == .buyShip) } else { Issue.record("no confirm") }
                    }
                    seen.append(quote.blocker)
                }
                #expect(seen.contains(expected), "\(r) fixture \(String(describing: expected)) saw \(seen)")
            }
        }
    }

    @Test("UI-SHELL-119 a designed ship's quote also shows the first TradeShip blocker")
    func designBlocker() {
        var e = engine(.modern) { s in
            s.galaxy.systems[s.commander.currentSystem].shipyard = .corellian
            s.commander.cash = 1_000_000
            s.commander.debt = 100
        }
        var design = Designer.minimumDesign(size: .medium, yard: .corellian)
        design.name = "Kestrel"
        let quote = e.state.designQuote(design)
        #expect(quote?.blocker == .inDebt && quote?.canBuild == false)
        #expect(e.perform(.buildDesign(design, transfers: [])).rejection == .inDebt)
    }

    // MARK: UI-SHELL-120 / SHP-077

    static func equipmentFixtures(_ r: RulesetID) -> [GameEngine] {
        func base(_ adjust: @escaping (inout GameState) -> Void) -> GameEngine {
            var e = engine(r) { s in
                s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
                s.commander.cash = 1_000_000
                s.commander.ship = ship(.wasp, r)
            }
            for cmd: Command in [.buyWeapon(.pulseLaser), .buyShield(.energy), .buyGadget(.extraCargoBays),
                                 .buyGadget(.navigatingSystem)] {
                _ = e.perform(cmd, acknowledging: [.buyEquipment])
            }
            var s = e.state
            adjust(&s)
            return GameEngine(state: s)
        }
        return [
            base { _ in },
            base { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .agricultural },
            base { s in s.commander.debt = 1 },
            base { s in s.commander.cash = 3_000 },
            base { s in s.commander.ship.cargo[TradeItemType.ore.rawValue] = s.freeCargoBays - 2 },
            base { s in s.commander.ship.weapons += [.pulseLaser, .beamLaser] },
            base { s in s.phase = .encounter(EncounterState(type: .pirateAttack, opponent: ship(.gnat, r))) },
            base { s in s.phase = .gameOver(.killed) },
        ]
    }

    @Test("UI-SHELL-120 SHP-077 SHP-078 equipmentMarket prices and blockers equal the buy and sell commands")
    func equipmentMarket() {
        for r in RulesetID.allCases {
            let tables = Ruleset.named(r).tables
            var blockers: Set<String> = []
            for fixture in Self.equipmentFixtures(r) {
                let market = fixture.state.equipmentMarket
                let expectedItems: [EquipmentItem] = WeaponType.allCases.filter { tables.contains($0) }.map { .weapon($0) }
                    + ShieldType.allCases.prefix(tables.shields.count).map { .shield($0) }
                    + GadgetType.allCases.filter { tables.contains($0) }.map { .gadget($0) }
                #expect(market.offers.map(\.item) == expectedItems)
                for offer in market.offers {
                    var e = fixture
                    let command: Command = switch offer.item {
                    case let .weapon(w): .buyWeapon(w)
                    case let .shield(s): .buyShield(s)
                    case let .gadget(g): .buyGadget(g)
                    }
                    let result = e.perform(command)
                    #expect(result.rejection == offer.buyBlocker, "\(r) \(offer.item)")
                    if offer.buyBlocker == nil {
                        #expect(result.decision == .confirm(Confirmation(.buyEquipment, amounts: [offer.buyPrice])))
                    }
                    blockers.insert(String(describing: offer.buyBlocker))
                }
                let ship = fixture.state.commander.ship
                #expect(market.installed.count == ship.weapons.count + ship.shields.count + ship.gadgets.count)
                for installed in market.installed {
                    var e = fixture
                    let command: Command
                    let base: Int
                    switch installed.item {
                    case let .weapon(w): command = .sellWeapon(index: installed.slot); base = tables.weapon(w).price
                    case let .shield(s): command = .sellShield(index: installed.slot); base = tables.shield(s).price
                    case let .gadget(g): command = .sellGadget(index: installed.slot); base = tables.gadget(g).price
                    }
                    #expect(installed.sellPrice == base * 3 / 4)
                    let result = e.perform(command)
                    #expect(result.rejection == installed.sellBlocker, "\(r) \(installed.item)")
                    if installed.sellBlocker == nil {
                        #expect(result.decision == .confirm(Confirmation(.sellEquipment, amounts: [installed.sellPrice])))
                    }
                    blockers.insert("sell " + String(describing: installed.sellBlocker))
                }
            }
            for b: CommandError in [.notSoldHere, .inDebt, .insufficientFunds, .noFreeSlot, .equipmentAlreadyOwned,
                                    .notAllowedInPhase, .gameOver] {
                #expect(blockers.contains(String(describing: Optional(b))), "\(r) \(b)")
            }
            #expect(blockers.contains("sell " + String(describing: Optional(CommandError.extraBaysInUse))), "\(r)")
        }
    }

    // MARK: UI-SHELL-121 (C#)

    static func csharpAll(_ r: RulesetID = .windows201) -> GameState {
        engine(r) { s in
            s.quests.gemulon = 3
            s.quests.experiment = 10
            s.quests.reactor = QuestStatus.Reactor.fuelOK
            s.quests.spaceMonster = QuestStatus.SpaceMonster.atAcamar
            s.quests.japori = QuestStatus.Japori.inTransit
            s.quests.dragonfly = QuestStatus.Dragonfly.flyMelina
            s.quests.princess = QuestStatus.Princess.flyQonos
            s.quests.scarab = QuestStatus.Scarab.hunting
            s.quests.sculpture = QuestStatus.Sculpture.inTransit
            s.quests.artifact = QuestStatus.Artifact.onBoard
            s.quests.jarek = QuestStatus.Jarek.impatient
            s.quests.wild = 4
            s.quests.moon = QuestStatus.Moon.bought
            s.commander.ship.crew = [0, CrewID.jarek, CrewID.wild]
            s.commander.ship.tribbles = 5
        }.state
    }

    @Test("UI-SHELL-121 C# quest log order, systems and days")
    func csharpOrder() {
        #expect(engine(.windows201).state.questLog.isEmpty)
        for r in [RulesetID.windows201, .modern] {
            let log = Self.csharpAll(r).questLog
            #expect(log.map(\.kind) == [
                .gemulonInformDays(4), .experimentInformTomorrow, .reactor, .spaceMonsterKill, .japoriDeliver, .dragonflyMelina,
                .princessQonos, .scarabFind, .sculpture, .artifact, .jarekImpatient, .wild, .tribbles, .moon,
            ])
            #expect(log.map(\.systems) == [
                [SystemID.gemulon], [SystemID.daled], [SystemID.nix], [SystemID.acamar], [SystemID.japori], [SystemID.melina],
                [SystemID.qonos], [], [SystemID.endor], [], [SystemID.devidia], [SystemID.kravat], [], [SystemID.utopia],
            ])
            #expect(log.map(\.daysLeft) == [4, 1, 19, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil])
        }
    }

    @Test("UI-SHELL-121 C# quest log branches and quirks")
    func csharpBranches() {
        func log(_ adjust: (inout GameState) -> Void) -> [QuestLogEntry] { engine(.windows201, adjust).state.questLog }
        #expect(log { $0.quests.gemulon = 6 }.map(\.kind) == [.gemulonInformTomorrow])
        #expect(log { $0.quests.gemulon = QuestStatus.Gemulon.fuel }.map(\.kind) == [.gemulonFuel])
        #expect(log { $0.quests.gemulon = QuestStatus.Gemulon.tooLate }.isEmpty)
        #expect(log { $0.quests.experiment = 4 } == [QuestLogEntry(kind: .experimentInformDays(7), systems: [SystemID.daled],
                                                                     daysLeft: 7)])
        #expect(log { $0.quests.reactor = 7 } == [QuestLogEntry(kind: .reactorFuel, systems: [SystemID.nix], daysLeft: 13)])
        // Quirk: a delivered reactor also lists the hidden compartments at Endor.
        #expect(log { $0.quests.reactor = QuestStatus.Reactor.delivered }.map(\.kind) == [.reactorLaser, .sculptureHiddenBays])
        #expect(log { $0.quests.dragonfly = QuestStatus.Dragonfly.destroyed }.map(\.kind) == [.dragonflyShield])
        for (status, kind) in [(1, QuestLogKind.dragonflyBaratas), (3, .dragonflyRegulas), (4, .dragonflyZalkon)] {
            #expect(log { $0.quests.dragonfly = status }.map(\.kind) == [kind])
        }
        let princess = CrewID.princess
        #expect(log { $0.quests.princess = 1 }.map(\.kind) == [.princessCentauri])
        #expect(log { $0.quests.princess = 2 }.map(\.kind) == [.princessInthara])
        #expect(log { $0.quests.princess = QuestStatus.Princess.rescued }
            == [QuestLogEntry(kind: .princessReturn(crewID: princess), systems: [SystemID.qonos, SystemID.galvon])])
        #expect(log { $0.quests.princess = QuestStatus.Princess.rescued; $0.commander.ship.crew = [0, princess] }
            == [QuestLogEntry(kind: .princessReturning(crewID: princess), systems: [SystemID.galvon])])
        // The C# switch names no status between rescued and returned (the impatience count).
        #expect(log { $0.quests.princess = 9; $0.commander.ship.crew = [0, princess] }.isEmpty)
        #expect(log { $0.quests.princess = QuestStatus.Princess.impatient; $0.commander.ship.crew = [0, princess] }.isEmpty)
        #expect(log { $0.quests.princess = QuestStatus.Princess.returned }.map(\.kind) == [.princessQuantum])
        #expect(log { $0.quests.jarek = 3; $0.commander.ship.crew = [0, CrewID.jarek] }.map(\.kind) == [.jarek])
        #expect(log { $0.quests.wild = QuestStatus.Wild.impatient; $0.commander.ship.crew = [0, CrewID.wild] }.map(\.kind)
            == [.wildImpatient])
        // Jarek and Wild need to be aboard (C# tests the crew, not the status).
        #expect(log { $0.quests.jarek = 3; $0.quests.wild = 3 }.isEmpty)
        let site = 77, yard = 88
        #expect(log { s in
            s.quests.scarab = QuestStatus.Scarab.destroyed
            for i in s.galaxy.systems.indices where s.galaxy.systems[i].specialEvent == .scarabDestroyed {
                s.galaxy.systems[i].specialEvent = nil
            }
            s.galaxy.systems[site].specialEvent = .scarabDestroyed
        } == [QuestLogEntry(kind: .scarabNotify(system: site), systems: [site])])
        #expect(log { s in
            s.quests.scarab = QuestStatus.Scarab.destroyed
            s.galaxy.systems[yard].specialEvent = .scarabUpgradeHull
        } == [QuestLogEntry(kind: .scarabHull(system: yard), systems: [yard])])
    }

    // MARK: UI-SHELL-122 (Palm)

    @Test("UI-SHELL-122 Palm quest log order and conditions; questLogOrder is a ruleset flag")
    func palmOrder() {
        #expect(Ruleset.palm122.flags.quest.questLogOrder == .palm)
        #expect(Ruleset.windows201.flags.quest.questLogOrder == .csharp && Ruleset.modern.flags.quest.questLogOrder == .csharp)
        var s = Self.csharpAll(.palm122)
        s.commander.ship.crew = [0]
        s.quests.jarek = QuestStatus.Jarek.started
        s.quests.wild = QuestStatus.Wild.started
        s.quests.dragonfly = QuestStatus.Dragonfly.done
        s.galaxy.systems[SystemID.zalkon].specialEvent = .dragonflyShield
        s.galaxy.systems[SystemID.nix].specialEvent = .reactorLaser
        #expect(s.questLog.map(\.kind) == [
            .spaceMonsterKill, .dragonflyShield, .japoriDeliver, .artifact, .wild, .jarek, .gemulonInformDays(4),
            .experimentInformTomorrow, .reactor, .reactorLaser, .scarabFind, .tribbles, .moon,
        ])
        #expect(s.questLog.count == s.openQuests)
        // Reward entries follow the event still in place, not the status.
        var p = engine(.palm122) { s in
            s.quests.reactor = 2
            s.quests.gemulon = QuestStatus.Gemulon.notStarted
            s.galaxy.systems[SystemID.gemulon].specialEvent = .gemulonFuel
        }.state
        #expect(p.questLog == [
            QuestLogEntry(kind: .gemulonFuel, systems: [SystemID.gemulon]),
            QuestLogEntry(kind: .reactorFuel, systems: [SystemID.nix], daysLeft: 18),
        ])
        p.galaxy.systems[SystemID.gemulon].specialEvent = nil
        p.quests.dragonfly = QuestStatus.Dragonfly.destroyed
        p.quests.reactor = QuestStatus.Reactor.delivered
        #expect(p.questLog.isEmpty)
        // No Princess, Sculpture or Scarab-hull entries in Palm.
        p.quests.princess = QuestStatus.Princess.flyCentauri
        p.quests.sculpture = QuestStatus.Sculpture.inTransit
        p.quests.scarab = QuestStatus.Scarab.destroyed
        #expect(p.questLog.isEmpty)
    }

    // MARK: UI-SHELL-123

    /// Strings.cs:162-196 (C# 2.01), copied verbatim; `\n` is `Environment.NewLine`.
    static let strings: [String: String] = [
        "QuestArtifact": "Deliver the alien artifact to Professor Berger at some hi-tech system.",
        "QuestDragonflyBaratas": "Follow the Dragonfly to Baratas.",
        "QuestDragonflyMelina": "Follow the Dragonfly to Melina.",
        "QuestDragonflyRegulas": "Follow the Dragonfly to Regulas.",
        "QuestDragonflyShield": "Get your lightning shield at Zalkon.",
        "QuestDragonflyZalkon": "Follow the Dragonfly to Zalkon.",
        "QuestExperimentInformDays": "Stop Dr. Fehler's experiment at Daled within ^1.",
        "QuestExperimentInformTomorrow": "Stop Dr. Fehler's experiment at Daled by tomorrow.",
        "QuestGemulonFuel": "Get your fuel compactor at Gemulon.",
        "QuestGemulonInformDays": "Inform Gemulon about alien invasion within ^1.",
        "QuestGemulonInformTomorrow": "Inform Gemulon about alien invasion by tomorrow.",
        "QuestJarek": "Take ambassador Jarek to Devidia.",
        "QuestJarekImpatient": "Take ambassador Jarek to Devidia.\nJarek is wondering why the journey is taking so long, "
            + "and is no longer of much help in negotiating trades.",
        "QuestJaporiDeliver": "Deliver antidote to Japori.",
        "QuestMoon": "Claim your moon at Utopia.",
        "QuestPrincessCentauri": "Follow the Scorpion to Centauri.",
        "QuestPrincessInthara": "Follow the Scorpion to Inthara.",
        "QuestPrincessQonos": "Follow the Scorpion to Qonos.",
        "QuestPrincessQuantum": "Get your Quantum Disruptor at Galvon.",
        "QuestPrincessReturn": "Transport ^1 from Qonos to Galvon.",
        "QuestPrincessReturning": "Return ^1 to Galvon.",
        "QuestPrincessReturningImpatient": "Return ^1 to Galvon.\nShe is becoming anxious to arrive at home, and is no "
            + "longer of any help in engineering functions.",
        "QuestReactor": "Deliver the unstable reactor to Nix for Henry Morgan.",
        "QuestReactorFuel": "Deliver the unstable reactor to Nix before it consumes all its fuel.",
        "QuestReactorLaser": "Get your special laser at Nix.",
        "QuestScarabFind": "Find and destroy the Scarab (which is hiding at the exit to a wormhole).",
        "QuestScarabHull": "Get your hull upgraded at ^1.",
        "QuestScarabNotify": "Notify the authorities at ^1 that the Scarab has been destroyed.",
        "QuestSculpture": "Deliver the stolen sculpture to Endor.",
        "QuestSculptureHiddenBays": "Have hidden compartments installed at Endor.",
        "QuestSpaceMonsterKill": "Kill the space monster at Acamar.",
        "QuestTribbles": "Get rid of those pesky tribbles.",
        "QuestWild": "Smuggle Jonathan Wild to Kravat.",
        "QuestWildImpatient": "Smuggle Jonathan Wild to Kravat.\nWild is getting impatient, and will no longer aid your "
            + "crew along the way.",
    ]

    /// The app-side mapping (as the app's localization does): the Strings.cs key and the `^1` argument of each kind.
    static func key(_ kind: QuestLogKind, systemNames: [String], crewNames: [Int: String]) -> (String, String?) {
        func days(_ n: Int) -> String { "\(n) day" + (n == 1 ? "" : "s") }
        switch kind {
        case let .gemulonInformDays(n): return ("QuestGemulonInformDays", days(n))
        case let .experimentInformDays(n): return ("QuestExperimentInformDays", days(n))
        case let .princessReturn(id): return ("QuestPrincessReturn", crewNames[id])
        case let .princessReturning(id): return ("QuestPrincessReturning", crewNames[id])
        case let .princessReturningImpatient(id): return ("QuestPrincessReturningImpatient", crewNames[id])
        case let .scarabNotify(system): return ("QuestScarabNotify", systemNames[system])
        case let .scarabHull(system): return ("QuestScarabHull", systemNames[system])
        default: return (plainKeys[kind] ?? "missing", nil)
        }
    }

    /// The Strings.cs key of each kind without a `^1` argument (coverage is checked against `strings` below).
    static let plainKeys: [QuestLogKind: String] = [
        .gemulonInformTomorrow: "QuestGemulonInformTomorrow", .gemulonFuel: "QuestGemulonFuel",
        .experimentInformTomorrow: "QuestExperimentInformTomorrow", .reactor: "QuestReactor",
        .reactorFuel: "QuestReactorFuel", .reactorLaser: "QuestReactorLaser", .spaceMonsterKill: "QuestSpaceMonsterKill",
        .japoriDeliver: "QuestJaporiDeliver", .dragonflyBaratas: "QuestDragonflyBaratas",
        .dragonflyMelina: "QuestDragonflyMelina", .dragonflyRegulas: "QuestDragonflyRegulas",
        .dragonflyZalkon: "QuestDragonflyZalkon", .dragonflyShield: "QuestDragonflyShield",
        .princessCentauri: "QuestPrincessCentauri", .princessInthara: "QuestPrincessInthara",
        .princessQonos: "QuestPrincessQonos", .princessQuantum: "QuestPrincessQuantum", .scarabFind: "QuestScarabFind",
        .sculpture: "QuestSculpture", .sculptureHiddenBays: "QuestSculptureHiddenBays", .artifact: "QuestArtifact",
        .jarek: "QuestJarek", .jarekImpatient: "QuestJarekImpatient", .wild: "QuestWild",
        .wildImpatient: "QuestWildImpatient", .tribbles: "QuestTribbles", .moon: "QuestMoon",
    ]

    @Test("UI-SHELL-123 every QuestLogKind maps to exactly one Strings.cs quest text")
    func kindTexts() {
        let names = Ruleset.windows201.tables.systemNames
        let crew = [CrewID.princess: "Ziyal"]
        let samples: [QuestLogKind] = [
            .gemulonInformDays(3), .gemulonInformTomorrow, .gemulonFuel, .experimentInformDays(2), .experimentInformTomorrow,
            .reactor, .reactorFuel, .reactorLaser, .spaceMonsterKill, .japoriDeliver, .dragonflyBaratas, .dragonflyMelina,
            .dragonflyRegulas, .dragonflyZalkon, .dragonflyShield, .princessCentauri, .princessInthara, .princessQonos,
            .princessReturn(crewID: CrewID.princess), .princessReturning(crewID: CrewID.princess),
            .princessReturningImpatient(crewID: CrewID.princess), .princessQuantum, .scarabFind,
            .scarabNotify(system: SystemID.og), .scarabHull(system: SystemID.og), .sculpture, .sculptureHiddenBays,
            .artifact, .jarek, .jarekImpatient, .wild, .wildImpatient, .tribbles, .moon,
        ]
        let keys = samples.map { Self.key($0, systemNames: names, crewNames: crew).0 }
        #expect(Set(keys) == Set(Self.strings.keys) && keys.count == Self.strings.count)
        func text(_ kind: QuestLogKind) -> String {
            let (key, arg) = Self.key(kind, systemNames: names, crewNames: crew)
            let template = Self.strings[key] ?? ""
            return arg.map { template.replacingOccurrences(of: "^1", with: $0) } ?? template
        }
        #expect(text(.gemulonInformDays(3)) == "Inform Gemulon about alien invasion within 3 days.")
        #expect(text(.princessReturn(crewID: CrewID.princess)) == "Transport Ziyal from Qonos to Galvon.")
        #expect(text(.scarabHull(system: SystemID.og)) == "Get your hull upgraded at Og.")
        #expect(samples.allSatisfy { !text($0).contains("^1") })
        // Every system an entry names appears in its text (C# hyperlinked system names found in the text).
        for entry in Self.csharpAll().questLog {
            for system in entry.systems { #expect(text(entry.kind).contains(names[system]), "\(entry.kind)") }
        }
    }
}
