// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

extension QuestKit {
    /// The first system other than `sys` and `avoiding` reachable from `sys` by an ordinary warp on a full tank.
    static func neighbor(_ s: GameState, of sys: Int, avoiding: Set<Int> = []) -> Int? {
        let range = s.commander.ship.fuelTanks(s.ruleset)
        return s.galaxy.systems.indices.first { i in
            i != sys && !avoiding.contains(i) && !s.galaxy.wormholeExists(from: sys, to: i)
                && GalaxyGenerator.distance(s.galaxy.systems[i], s.galaxy.systems[sys], rule: s.ruleset.flags.distance) <= range
        }
    }

    /// A one-day warp from the current system to `target` without any encounter.
    static func hop(_ e: inout GameEngine, to target: Int) -> Bool {
        refuelAndTarget(&e, target)
        return quietWarp(&e)
    }

    /// The Scarab's end-point system and the wormhole system that leads into it.
    static func scarabRoute(_ s: GameState) -> (source: Int, end: Int)? {
        let holes = s.galaxy.wormholes
        guard let end = systems(s, with: .scarabDestroyed).first, let k = holes.firstIndex(of: end) else { return nil }
        return (holes[(k + holes.count - 1) % holes.count], end)
    }

    /// Docks at the wormhole source and targets the Scarab's end point through the wormhole.
    static func targetScarabWormhole(_ e: inout GameEngine) throws {
        let route = try #require(scarabRoute(e.state))
        dock(&e, at: route.source)
        e.perform(.buyFuel(credits: 100_000))
        e.perform(.selectWormhole(route.source))
    }
}

// MARK: - QST-MONSTER

@Suite("QST-MONSTER: the Space Monster at Acamar")
struct QuestMonsterSpecTests {
    typealias QK = QuestKit
    typealias SM = QuestStatus.SpaceMonster

    @Test("QST-MONSTER-001 statuses 0…3; a new game starts at 0")
    func statuses() {
        #expect([SM.notStarted, SM.atAcamar, SM.destroyed, SM.done] == Array(0...3))
        #expect(makeEngine(seed: 5).state.quests.spaceMonster == SM.notStarted)
    }

    @Test("QST-MONSTER-002 the start once at random, the reward at Acamar; table rows; both message-only")
    func eventsAndRows() {
        for seed in 1...6 {
            let s = makeEngine(seed: UInt64(seed)).state
            #expect(QK.systems(s, with: .spaceMonster).count == 1)
            #expect(QK.systems(s, with: .spaceMonsterKilled) == [SystemID.acamar] && SystemID.acamar == 0)
        }
        let s = makeEngine().state
        #expect(s.specialEventSpec(.spaceMonster).map { [$0.price, $0.occurrence] } == [0, 1])
        #expect(s.specialEventSpec(.spaceMonsterKilled).map { [$0.price, $0.occurrence] } == [-15_000, 0])
        #expect(s.specialEventSpec(.spaceMonster)?.messageOnly == true && s.specialEventSpec(.spaceMonsterKilled)?.messageOnly == true)
        var e = QK.engine { s in s.commander.policeRecordScore = -80 }
        QK.dock(&e, at: QK.systems(e.state, with: .spaceMonster).first ?? 1)
        #expect(e.perform(.specialEvent).decision == nil, "no consent needed")
    }

    @Test("QST-MONSTER-003 the start always shows; the reward only at status 2")
    func conditions() {
        var e = QK.engine { s in
            s.commander.policeRecordScore = -90
            s.commander.reputationScore = 0
        }
        QK.dock(&e, at: SystemID.acamar)
        for status in 0...3 {
            e.state.quests.spaceMonster = status
            e.state.galaxy.systems[SystemID.acamar].specialEvent = .spaceMonster
            #expect(e.state.specialEventAvailable == .spaceMonster)
            e.state.galaxy.systems[SystemID.acamar].specialEvent = .spaceMonsterKilled
            #expect((e.state.specialEventAvailable != nil) == (status == SM.destroyed), "\(status)")
        }
    }

    @Test("QST-MONSTER-005 QST-MONSTER-006 the start sets 1; the reward sets 3, removes the event and pays 15000 even with a large debt")
    func handlers() {
        var e = QK.engine()
        let start = QK.systems(e.state, with: .spaceMonster).first ?? 1
        QK.dock(&e, at: start)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.spaceMonster)])
        #expect(e.state.quests.spaceMonster == SM.atAcamar && e.state.galaxy.systems[start].specialEvent == nil)
        e.state.quests.spaceMonster = SM.destroyed
        e.state.commander.cash = 0
        e.state.commander.debt = 500_000
        QK.dock(&e, at: SystemID.acamar)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.spaceMonsterKilled)])
        #expect(e.state.commander.cash == 15_000 && e.state.commander.debt == 500_000)
        #expect(e.state.quests.spaceMonster == SM.done && e.state.currentSystem.specialEvent == nil)
    }

    @Test("QST-MONSTER-008 only status 1 meets the monster at Acamar, at click 1, first among the fixed checks, with its loadout")
    func encounter() {
        for status in 0...3 {
            var s = QK.engine { s in
                s.warpSystem = SystemID.acamar
                s.quests.spaceMonster = status
                s.quests.justLootedMarie = true
            }.state
            let enc = s.determineFixedEncounter(clicks: 1)
            #expect((enc?.type == .spaceMonsterAttack) == (status == SM.atAcamar), "\(status)")
            if status == SM.atAcamar {
                #expect(s.quests.justLootedMarie, "the customs check never ran")
                #expect(s.determineFixedEncounter(clicks: 2) == nil)
                let monster = enc?.opponent
                #expect(monster == s.specialShips.spaceMonster && monster?.hull == 500)
                #expect(monster?.weapons == [.militaryLaser, .militaryLaser, .militaryLaser])
                let d = s.difficulty.rawValue
                #expect(s.mercenaries[CrewID.spaceMonster].skills == [8 + d, 8 + d, 1, 1 + d])
            }
        }
    }

    @Test("QST-MONSTER-009 the monster cannot be disabled; no lasers is rejected; only destruction ends it")
    func noDisable() {
        var e = EncSpec.encounter(.spaceMonsterAttack, opponent: { s in s.specialShips.spaceMonster })
        #expect(!e.state.disableable(e.state.specialShips.spaceMonster))
        e.state.commander.ship.weapons = [.photonDisruptor, .photonDisruptor]
        #expect(e.perform(.encounter(.attack), acknowledging: QK.yes).rejection == .noLasers)
        var (s, enc0) = QuestShipCombatSpecTests.duel(.spaceMonsterAttack, { $0.specialShips.spaceMonster },
                                                      weapons: [.morgansLaser, .quantumDisruptor], disable: true)
        enc0.opponent.hull = 60
        var events: [GameEvent] = []
        #expect(QK.seek(&s) { p in
            var enc = enc0
            let (result, ev) = QuestShipCombatSpecTests.decide(&p, &enc)
            events = ev
            return result == .normal
        })
        #expect(events.last == .opponentDestroyed(.spaceMonster))
        #expect(!events.contains(.opponentDisabled(.spaceMonster)))
        #expect(s.quests.spaceMonster == SM.destroyed)
    }

    @Test("QST-MONSTER-010 QST-MONSTER-015 scenario: accept, meet the 500-hull monster at click 1, destroy it, news, reward")
    func happyPath() throws {
        var e = QK.engine()
        let start = try #require(QK.systems(e.state, with: .spaceMonster).first)
        QK.dock(&e, at: start)
        #expect(e.perform(.specialEvent).decision == nil)
        #expect(e.state.quests.spaceMonster == SM.atAcamar && e.state.galaxy.systems[start].specialEvent == nil)
        try QK.prepareWarp(&e, to: SystemID.acamar)
        try #require(QK.warpInto(&e, .spaceMonsterAttack, clicks: 1))
        #expect(e.encounter?.opponent.hull == 500)
        let before = e.state.commander
        var events: [GameEvent] = []
        try #require(QK.win(&e, .opponentDestroyed(.spaceMonster), events: &events))
        let c = e.state.commander
        #expect(e.state.quests.spaceMonster == SM.destroyed)
        #expect(c.kills.pirates == before.kills.pirates + 1 && c.policeRecordScore == before.policeRecordScore + 1)
        #expect(c.reputationScore == before.reputationScore + 6 && ShipType.spaceMonster.rawValue / 2 + 1 == 6)
        #expect(c.cash == before.cash && e.state.pendingScoop == nil)
        #expect(!events.contains { if case .bountyPaid = $0 { true } else { false } })
        #expect(c.currentSystem == SystemID.acamar && e.state.newsEvents.contains(.spaceMonsterKilled))
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.spaceMonsterKilled)])
        #expect(e.state.commander.cash == before.cash + 15_000)
        #expect(e.state.quests.spaceMonster == SM.done && e.state.currentSystem.specialEvent == nil)
    }

    @Test("QST-MONSTER-011 the damaged monster regrows by 1.05^n per IncDays, truncated and capped at 500")
    func regrowth() {
        var s = QK.engine().state
        for (hull, days, after) in [(100, 1, 105), (19, 1, 19), (200, 3, 231), (499, 1, 500), (500, 4, 500)] {
            s.specialShips.spaceMonster.hull = hull
            _ = s.incDays(days)
            #expect(s.specialShips.spaceMonster.hull == after, "\(hull) after \(days)")
        }
    }

    @Test("QST-MONSTER-011 QST-MONSTER-013 QST-MONSTER-016 scenario: escape at hull 200, no button, three days of regrowth, then 242")
    func escapeAndRetry() throws {
        var e = QK.engine { s in s.quests.spaceMonster = SM.atAcamar }
        try QK.prepareWarp(&e, to: SystemID.acamar)
        let near = e.state.commander.currentSystem
        try #require(QK.warpInto(&e, .spaceMonsterAttack, clicks: 1))
        QK.editEncounter(&e) { enc in enc.opponent.hull = 200 }
        try #require(QK.escape(&e))
        #expect(e.state.commander.currentSystem == SystemID.acamar && e.state.quests.spaceMonster == SM.atAcamar)
        #expect(e.state.specialShips.spaceMonster.hull == 200)
        #expect(e.state.specialEventAvailable == nil && e.state.newsEvents.contains(.spaceMonster))
        let far = try #require(QK.neighbor(e.state, of: near, avoiding: [SystemID.acamar]))
        for (target, hull) in [(near, 210), (far, 220), (near, 231)] {
            try #require(QK.hop(&e, to: target))
            #expect(e.state.specialShips.spaceMonster.hull == hull)
        }
        QK.refuelAndTarget(&e, SystemID.acamar)
        try #require(QK.warpInto(&e, .spaceMonsterAttack, clicks: 1))
        #expect(e.encounter?.opponent.hull == 242 && e.state.quests.spaceMonster == SM.atAcamar)
    }

    @Test("QST-MONSTER-013 arrest, the escape pod and ship purchase never change the status")
    func lossPaths() {
        for status in 0...3 {
            let e = QK.engine { s in s.quests.spaceMonster = status }
            for after in [QK.arrest(e), QK.escapePod(e), QK.buyShip(e), QK.buildShip(e)] {
                #expect(after.state.quests.spaceMonster == status)
            }
        }
    }

    @Test("QST-MONSTER-014 Acamar's headline: spaceMonster at status 1, spaceMonsterKilled at 2 or more, nothing at 0 or once handled")
    func news() {
        let base = QK.engine().state
        func headline(_ status: Int, event: SpecialEventType? = .spaceMonsterKilled) -> NewsEvent? {
            var s = base
            s.galaxy.systems[SystemID.acamar].specialEvent = event
            s.commander.currentSystem = SystemID.acamar
            s.quests.spaceMonster = status
            s.newsEvents = []
            s.addArrivalNews()
            return s.newsEvents.last
        }
        #expect(headline(0) == nil && headline(1) == .spaceMonster && headline(2) == .spaceMonsterKilled)
        #expect(headline(3, event: nil) == nil)
    }

    @Test("QST-MONSTER-017 scenario: no monster at status 0; the reward hidden at 0 and 1; disruptors alone are rejected")
    func gates() throws {
        var e = QK.engine()
        try QK.prepareWarp(&e, to: SystemID.acamar)
        try #require(QK.quietWarp(&e), "a quiet trip to Acamar exists at status 0")
        for status in [0, 1] {
            e.state.quests.spaceMonster = status
            #expect(e.perform(.specialEvent).rejection == .noSpecialEvent)
        }
        var a = QK.engine { s in s.quests.spaceMonster = SM.atAcamar; s.commander.ship.weapons = [.photonDisruptor] }
        try QK.prepareWarp(&a, to: SystemID.acamar)
        try #require(QK.warpInto(&a, .spaceMonsterAttack, clicks: 1))
        #expect(a.perform(.encounter(.attack), acknowledging: QK.yes).rejection == .noLasers)
    }
}

// MARK: - QST-SCARAB

@Suite("QST-SCARAB: the stolen Scarab and the hull upgrade")
struct QuestScarabSpecTests {
    typealias QK = QuestKit
    typealias SC = QuestStatus.Scarab

    @Test("QST-SCARAB-001 statuses 0…3; a new game starts at 0")
    func statuses() {
        #expect([SC.notStarted, SC.hunting, SC.destroyed, SC.done] == Array(0...3))
        #expect(makeEngine(seed: 9).state.quests.scarab == SC.notStarted)
    }

    @Test("QST-SCARAB-002 the start once at random, the end point on a wormhole system, the upgrade never placed; table rows")
    func eventsAndRows() {
        for seed in 1...6 {
            let s = makeEngine(seed: UInt64(seed)).state
            #expect(QK.systems(s, with: .scarab).count == 1)
            let ends = QK.systems(s, with: .scarabDestroyed)
            #expect(ends.count == 1 && s.galaxy.wormholes.contains(ends[0]))
            #expect(QK.systems(s, with: .scarabUpgradeHull).isEmpty)
        }
        let s = makeEngine().state
        for (type, occurrence, messageOnly) in [(SpecialEventType.scarab, 1, true), (.scarabDestroyed, 0, true), (.scarabUpgradeHull, 0, false)] {
            let spec = s.specialEventSpec(type)
            #expect(spec?.price == 0 && spec?.occurrence == occurrence && spec?.messageOnly == messageOnly)
        }
        var e = QK.engine { s in s.quests.scarab = SC.destroyed }
        QK.dock(&e, at: 3)
        e.state.galaxy.systems[3].specialEvent = .scarabUpgradeHull
        #expect(e.perform(.specialEvent) == .needsConfirmation(Confirmation(.acceptSpecialEvent, amounts: [0])))
    }

    @Test("QST-SCARAB-003 the start needs status 0 and reputation 40; the end point and the upgrade need status 2")
    func conditions() {
        var e = QK.engine()
        QK.dock(&e, at: 3)
        func shown(_ ev: SpecialEventType, _ status: Int, reputation: Int = 40) -> Bool {
            e.state.galaxy.systems[3].specialEvent = ev
            e.state.quests.scarab = status
            e.state.commander.reputationScore = reputation
            return e.state.specialEventAvailable == ev
        }
        #expect(shown(.scarab, 0) && !shown(.scarab, 0, reputation: 39) && !shown(.scarab, 1))
        for status in 0...3 {
            #expect(shown(.scarabDestroyed, status) == (status == SC.destroyed))
            #expect(shown(.scarabUpgradeHull, status) == (status == SC.destroyed))
        }
    }

    @Test("QST-SCARAB-005 QST-SCARAB-008 the start sets 1 and is removed; the end-point message keeps 2 and becomes the upgrade offer")
    func handlers() {
        var e = QK.engine { s in s.commander.reputationScore = 40 }
        let start = QK.systems(e.state, with: .scarab).first ?? 1
        QK.dock(&e, at: start)
        e.perform(.specialEvent)
        #expect(e.state.quests.scarab == SC.hunting && e.state.galaxy.systems[start].specialEvent == nil)
        let end = QK.systems(e.state, with: .scarabDestroyed).first ?? 2
        e.state.quests.scarab = SC.destroyed
        QK.dock(&e, at: end)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.scarabDestroyed)])
        #expect(e.state.quests.scarab == SC.destroyed && e.state.currentSystem.specialEvent == .scarabUpgradeHull)
        #expect(e.state.specialEventAvailable == .scarabUpgradeHull)
    }

    @Test("QST-SCARAB-006 met only through the wormhole at click 20 at status 1; the persistent Scarab; Beam, Military and Photon do not hurt it")
    func encounter() throws {
        var e = QK.engine { s in s.quests.scarab = SC.hunting }
        try QK.targetScarabWormhole(&e)
        try #require(QK.warpInto(&e, .scarabAttack, clicks: 20))
        let scarab = try #require(e.encounter?.opponent)
        #expect(scarab == e.state.specialShips.scarab && scarab.hull == 400 && scarab.weapons == [.militaryLaser, .militaryLaser])
        let d = e.state.difficulty.rawValue
        #expect(e.state.mercenaries[CrewID.scarab].skills == [5 + d, 6 + d, 1, 6 + d])
        #expect(e.state.arrivedViaWormhole)
        // Other statuses never meet it on the same route.
        for status in [0, 2, 3] {
            var f = QK.engine { s in s.quests.scarab = status }
            try QK.targetScarabWormhole(&f)
            f.perform(.warp, acknowledging: QK.yes)
            #expect(f.encounter?.type != .scarabAttack && f.encounter?.type != .scarabIgnore, "\(status)")
        }
        // In Windows only Pulse, Morgan's and Quantum count: Beam, Military and Photon never damage it.
        var s = e.state
        s.commander.ship.weapons = [.beamLaser, .militaryLaser, .photonDisruptor]
        for _ in 0..<200 {
            var enc = try #require(e.encounter)
            _ = s.executeAttack(commanderAttacks: true, fleeing: false, encounter: &enc)
            #expect(enc.opponent.hull == 400 && !enc.opponentDisabled)
        }
        // Surrendering to it is a pirate raid.
        e.state.commander.ship.cargo[TradeItemType.ore.rawValue] = 3
        let r = e.perform(.encounter(.surrender), acknowledging: QK.yes)
        #expect(r.events.contains(.looted(units: 3)) && e.state.commander.ship.cargo[TradeItemType.ore.rawValue] == 0)
    }

    @Test("QST-SCARAB-007 CMB-045 destroying or disabling the Scarab: status 2, kill, record +1, reputation +7, no bounty or scoop")
    func defeat() throws {
        for disable in [false, true] {
            var e = QK.engine { s in
                s.quests.scarab = SC.hunting
                if disable {
                    s.commander.ship.weapons = [.quantumDisruptor, .quantumDisruptor]
                    s.options.disableOpponents = true
                }
            }
            try QK.targetScarabWormhole(&e)
            try #require(QK.warpInto(&e, .scarabAttack, clicks: 20))
            let before = e.state.commander
            var events: [GameEvent] = []
            try #require(QK.win(&e, disable ? .opponentDisabled(.scarab) : .opponentDestroyed(.scarab), events: &events))
            let c = e.state.commander
            #expect(e.state.quests.scarab == SC.destroyed)
            #expect(c.kills.pirates == before.kills.pirates + 1 && c.policeRecordScore == before.policeRecordScore + 1)
            #expect(c.reputationScore == before.reputationScore + 7 && ShipType.scarab.rawValue / 2 + 1 == 7)
            #expect(c.cash == before.cash && e.state.pendingScoop == nil)
            #expect(!events.contains { if case .bountyPaid = $0 { true } else { false } })
        }
    }

    @Test("QST-SCARAB-009 the upgrade: consent, then hullUpgraded, hull +50 whatever the damage, status 3, the event kept but hidden")
    func upgrade() {
        var e = QK.engine { s in
            var gnat = Ship(type: .gnat, spec: s.ruleset.tables.ship(.gnat))
            gnat.crew[0] = CrewID.commander
            gnat.hull = 60
            gnat.weapons = [.pulseLaser]
            gnat.gadgets = [.navigatingSystem]
            s.commander.ship = gnat
            s.quests.scarab = SC.destroyed
        }
        QK.dock(&e, at: 3)
        e.state.galaxy.systems[3].specialEvent = .scarabUpgradeHull
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        #expect(e.perform(.specialEvent, acknowledging: QK.yes).events == [.specialEventCompleted(.scarabUpgradeHull)])
        let ship = e.state.commander.ship
        #expect(ship.hullUpgraded && ship.hull == 110 && ship.hullStrength(e.ruleset) == 150)
        #expect(e.state.quests.scarab == SC.done)
        #expect(e.state.currentSystem.specialEvent == .scarabUpgradeHull && e.state.specialEventAvailable == nil)
    }

    @Test("QST-SCARAB-011 in Windows, after the upgrade, hull damage is halved for every defender")
    func halving() {
        for commanderAttacks in [true, false] {
            var s = CombatKit.state()
            s.commander.ship = CombatKit.playerShip(s, .wasp, weapons: [.pulseLaser])
            var enc0 = EncounterState(type: .pirateAttack, opponent: CombatKit.opponent(&s, .wasp, weapons: [.pulseLaser]))
            enc0.opponent.hull = 200
            let found = QK.seek(&s) { p in
                var plain = p, hard = p
                hard.quests.scarab = SC.done
                var e1 = enc0, e2 = enc0
                _ = plain.executeAttack(commanderAttacks: commanderAttacks, fleeing: false, encounter: &e1)
                _ = hard.executeAttack(commanderAttacks: commanderAttacks, fleeing: false, encounter: &e2)
                let loss1 = commanderAttacks ? 200 - e1.opponent.hull : p.commander.ship.hull - plain.commander.ship.hull
                let loss2 = commanderAttacks ? 200 - e2.opponent.hull : p.commander.ship.hull - hard.commander.ship.hull
                guard loss1 >= 2 else { return false }
                #expect(loss2 == loss1 / 2, "attacker is commander: \(commanderAttacks)")
                return true
            }
            #expect(found)
        }
    }

    @Test("QST-SCARAB-013 any ship purchase or custom build resets 3 to 0 with no upgrade; the quest cannot repeat")
    func purchaseResets() {
        for status in 0...3 {
            let e = QK.engine { s in
                s.quests.scarab = status
                s.commander.ship.hullUpgraded = status == SC.done
            }
            for after in [QK.buyShip(e), QK.buildShip(e)] {
                #expect(after.state.commander.ship.type != .wasp && !after.state.commander.ship.hullUpgraded)
                #expect(after.state.quests.scarab == (status == SC.done ? SC.notStarted : status))
            }
        }
        // After the reset: the start was removed and the kept upgrade offer needs status 2.
        var e = QK.engine { s in s.quests.scarab = SC.notStarted; s.commander.reputationScore = 100 }
        let route = QK.scarabRoute(e.state)
        e.state.galaxy.systems[route?.end ?? 0].specialEvent = .scarabUpgradeHull
        let start = QK.systems(e.state, with: .scarab).first ?? 1
        e.state.galaxy.systems[start].specialEvent = nil
        for sys in e.state.galaxy.systems.indices {
            QK.dock(&e, at: sys)
            #expect(![.scarab, .scarabDestroyed, .scarabUpgradeHull].contains(e.state.specialEventAvailable))
        }
    }

    @Test("QST-SCARAB-014 the escape pod and a ship sold for an arrest fine give a plain Flea but keep status 3")
    func podKeepsStatus() {
        let e = QK.engine { s in s.quests.scarab = SC.done; s.commander.ship.hullUpgraded = true }
        var broke = e
        broke.state.commander.cash = 0
        for after in [QK.escapePod(e), QK.arrest(broke)] {
            let ship = after.state.commander.ship
            #expect(ship.type == .flea && !ship.hullUpgraded && ship.hull == after.ruleset.tables.ship(.flea).hullStrength)
            #expect(after.state.quests.scarab == SC.done)
        }
    }

    @Test("QST-SCARAB-017 end-point headlines: scarabHarass at 1, scarabDestroyed at 2 or more, nothing once it is the upgrade")
    func news() {
        let base = QK.engine().state
        let start = QK.systems(base, with: .scarab).first ?? 1
        let end = QK.systems(base, with: .scarabDestroyed).first ?? 2
        func headline(_ sys: Int, _ status: Int, event: SpecialEventType? = nil) -> NewsEvent? {
            var s = base
            if let event { s.galaxy.systems[sys].specialEvent = event }
            s.commander.currentSystem = sys
            s.quests.scarab = status
            s.newsEvents = []
            s.addArrivalNews()
            return s.newsEvents.last
        }
        #expect(headline(start, 0) == .scarab)
        #expect(headline(end, 0) == nil && headline(end, 1) == .scarabHarass)
        #expect(headline(end, 2) == .scarabDestroyed && headline(end, 3) == .scarabDestroyed)
        #expect(headline(end, 2, event: .scarabUpgradeHull) == nil)
    }

    @Test("QST-SCARAB-018 scenario: accept, wormhole fight at click 20, news, message, upgrade, halved hits, then a new ship resets it")
    func happyPath() throws {
        var e = QK.engine { s in s.commander.reputationScore = 40 }
        let start = try #require(QK.systems(e.state, with: .scarab).first)
        QK.dock(&e, at: start)
        e.perform(.specialEvent)
        #expect(e.state.quests.scarab == SC.hunting)
        try QK.targetScarabWormhole(&e)
        try #require(QK.warpInto(&e, .scarabAttack, clicks: 20))
        e.state.commander.ship.weapons = [.pulseLaser, .pulseLaser, .pulseLaser]
        let rep = e.state.commander.reputationScore
        var events: [GameEvent] = []
        try #require(QK.win(&e, .opponentDestroyed(.scarab), events: &events))
        #expect(e.state.quests.scarab == SC.destroyed && e.state.commander.reputationScore == rep + 7)
        #expect(e.state.newsEvents.contains(.scarabDestroyed))
        e.perform(.specialEvent)
        #expect(e.state.currentSystem.specialEvent == .scarabUpgradeHull)
        let hull = e.state.commander.ship.hull, strength = e.state.commander.ship.hullStrength(e.ruleset)
        e.perform(.specialEvent, acknowledging: QK.yes)
        let ship = e.state.commander.ship
        #expect(ship.hullUpgraded && ship.hull == hull + 50 && ship.hullStrength(e.ruleset) == strength + 50)
        #expect(e.state.quests.scarab == SC.done && e.state.specialEventAvailable == nil)
        // A later hit on an opponent is halved (Windows).
        var probe = e.state
        let enc0 = EncounterState(type: .pirateAttack, opponent: CombatKit.opponent(&probe, .wasp))
        #expect(QK.seek(&probe) { p in
            var plain = p
            plain.quests.scarab = SC.notStarted
            var e1 = enc0, e2 = enc0
            _ = plain.executeAttack(commanderAttacks: true, fleeing: false, encounter: &e1)
            _ = p.executeAttack(commanderAttacks: true, fleeing: false, encounter: &e2)
            let full = enc0.opponent.hull - e1.opponent.hull
            return full >= 2 && enc0.opponent.hull - e2.opponent.hull == full / 2
        })
        let bought = QK.buyShip(e)
        #expect(bought.state.quests.scarab == SC.notStarted && !bought.state.commander.ship.hullUpgraded)
        var anywhere = bought
        for sys in anywhere.state.galaxy.systems.indices {
            QK.dock(&anywhere, at: sys)
            #expect(![.scarab, .scarabDestroyed, .scarabUpgradeHull].contains(anywhere.state.specialEventAvailable))
        }
    }

    @Test("QST-SCARAB-019 scenario (a) (b): reputation 39 hides the start; a normal warp to the end point has no Scarab")
    func failuresGates() throws {
        var e = QK.engine { s in s.commander.reputationScore = 39 }
        QK.dock(&e, at: QK.systems(e.state, with: .scarab).first ?? 1)
        #expect(e.perform(.specialEvent).rejection == .noSpecialEvent)
        var n = QK.engine { s in s.quests.scarab = SC.hunting }
        let route = try #require(QK.scarabRoute(n.state))
        try QK.prepareWarp(&n, to: route.end)
        try #require(QK.quietWarp(&n), "a normal warp to the end point meets no Scarab")
        #expect(!n.state.arrivedViaWormhole && n.state.commander.currentSystem == route.end)
        #expect(n.state.specialEventAvailable == nil && n.state.newsEvents.contains(.scarabHarass))
        #expect(n.state.quests.scarab == SC.hunting)
    }

    @Test("QST-SCARAB-007 QST-SCARAB-019 scenario (c): an escape keeps status 1 and the damage for the next wormhole arrival")
    func failuresEscape() throws {
        var e = QK.engine { s in s.quests.scarab = SC.hunting }
        try QK.targetScarabWormhole(&e)
        try #require(QK.warpInto(&e, .scarabAttack, clicks: 20))
        QK.editEncounter(&e) { enc in enc.opponent.hull = 150 }
        try #require(QK.escape(&e))
        #expect(e.state.quests.scarab == SC.hunting && e.state.specialShips.scarab.hull == 150)
        try QK.targetScarabWormhole(&e)
        try #require(QK.warpInto(&e, .scarabAttack, clicks: 20))
        #expect(e.encounter?.opponent.hull == 150)
    }

    @Test("QST-SCARAB-019 scenario (d): after the upgrade the escape pod gives a base Flea and keeps status 3")
    func failuresPod() {
        var e = QK.engine { s in s.quests.scarab = SC.destroyed }
        let end = QK.systems(e.state, with: .scarabDestroyed).first ?? 2
        QK.dock(&e, at: end)
        e.perform(.specialEvent)
        e.perform(.specialEvent, acknowledging: QK.yes)
        #expect(e.state.commander.ship.hullUpgraded && e.state.quests.scarab == SC.done)
        let pod = QK.escapePod(e)
        #expect(pod.state.commander.ship.type == .flea && pod.state.commander.ship.hull == 25 && !pod.state.commander.ship.hullUpgraded)
        #expect(pod.state.quests.scarab == SC.done)
    }
}
