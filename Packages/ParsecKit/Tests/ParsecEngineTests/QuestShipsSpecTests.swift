// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// Shared builders for the quest-chain scenario tests (Windows 2.01 ruleset).
enum QuestKit {
    static let yes: Set<WarningID> = Set(WarningID.allCases)

    /// A Windows game whose commander flies a Wasp (3 weapon, 2 shield, 2 gadget slots) with three Morgan's lasers and two
    /// charged Lightning shields, skills 8/8/8/8, 1 000 000 credits, record 0 and reputation 0. Pirates, police and
    /// traders that can be ignored are hidden, so a trip shows only encounters that must be faced.
    static func engine(seed: UInt64 = 11, _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
        var e = makeEngine(.windows201, seed: seed)
        var ship = Ship(type: .wasp, spec: e.ruleset.tables.ship(.wasp))
        ship.crew[0] = CrewID.commander
        ship.weapons = [.morgansLaser, .morgansLaser, .morgansLaser]
        ship.shields = [lightning(e.state), lightning(e.state)]
        e.state.commander.ship = ship
        e.state.mercenaries[CrewID.commander].skills = [8, 8, 8, 8]
        e.state.commander.cash = 1_000_000
        e.state.commander.policeRecordScore = 0
        e.state.commander.reputationScore = 0
        e.state.options.alwaysIgnorePirates = true
        e.state.options.alwaysIgnorePolice = true
        e.state.options.alwaysIgnoreTraders = true
        e.state.options.alwaysIgnoreTradeInOrbit = true
        adjust(&e.state)
        return e
    }

    static func lightning(_ s: GameState) -> ShieldInstance {
        ShieldInstance(type: .lightning, charge: s.ruleset.tables.shield(.lightning).power)
    }

    /// Systems whose special event is `ev`, in index order.
    static func systems(_ s: GameState, with ev: SpecialEventType) -> [Int] {
        s.galaxy.systems.indices.filter { s.galaxy.systems[$0].specialEvent == ev }
    }

    /// Puts the commander, docked, at `sys` (the trip there is not part of the requirement under test).
    static func dock(_ e: inout GameEngine, at sys: Int) {
        e.state.commander.currentSystem = sys
        e.state.warpSystem = sys
        e.state.phase = .docked
    }

    /// Docks at a system from which `target` is an ordinary (non-wormhole) warp, refuels and targets `target`.
    static func prepareWarp(_ e: inout GameEngine, to target: Int, avoiding: Set<Int> = []) throws {
        let s = e.state
        let range = s.commander.ship.fuelTanks(s.ruleset)
        let from = try #require(s.galaxy.systems.indices.first { i in
            i != target && !avoiding.contains(i) && !s.galaxy.wormholeExists(from: i, to: target)
                && GalaxyGenerator.distance(s.galaxy.systems[i], s.galaxy.systems[target], rule: s.ruleset.flags.distance) <= range
        })
        dock(&e, at: from)
        refuelAndTarget(&e, target)
    }

    static func refuelAndTarget(_ e: inout GameEngine, _ target: Int) {
        e.perform(.buyFuel(credits: 100_000))
        e.perform(.selectTarget(target))
    }

    /// Tries `attempt` on copies of the engine, advancing the game RNG one draw between tries, and keeps the first
    /// copy for which it returns true. The RNG positions are the engine's own; nothing is hardcoded.
    static func seek(_ e: inout GameEngine, tries: Int = 4_000, _ attempt: (inout GameEngine) -> Bool) -> Bool {
        for _ in 0..<tries {
            var probe = e
            if attempt(&probe) {
                e = probe
                return true
            }
            _ = e.state.rng.next(below: 2)
        }
        return false
    }

    /// Same as `seek` for a bare state.
    static func seek(_ s: inout GameState, tries: Int = 4_000, _ attempt: (inout GameState) -> Bool) -> Bool {
        for _ in 0..<tries {
            var probe = s
            if attempt(&probe) {
                s = probe
                return true
            }
            _ = s.rng.next(below: 2)
        }
        return false
    }

    /// A normal warp to the current target that arrives without facing any encounter.
    static func quietWarp(_ e: inout GameEngine) -> Bool {
        let target = e.state.warpSystem
        return seek(&e) { p in
            let r = p.perform(.warp, acknowledging: yes)
            return r.rejection == nil && p.state.phase == .docked && p.state.commander.currentSystem == target
                && r.events.contains(.uneventfulTrip)
        }
    }

    /// A warp to the current target whose first shown encounter is `type` at click `clicks`.
    static func warpInto(_ e: inout GameEngine, _ type: EncounterType, clicks: Int) -> Bool {
        seek(&e) { p in
            let r = p.perform(.warp, acknowledging: yes)
            return r.rejection == nil && p.encounter?.type == type && p.encounter?.clicks == clicks
        }
    }

    /// Attacks until the encounter is over; returns every event.
    static func fight(_ e: inout GameEngine, limit: Int = 300) -> [GameEvent] {
        var events: [GameEvent] = []
        for _ in 0..<limit {
            guard e.encounter != nil else { break }
            let r = e.perform(.encounter(.attack), acknowledging: yes)
            events += r.events
            if r.rejection != nil || r.events.contains(where: startedEncounter) { break }
        }
        return events
    }

    /// Wins the current quest-ship fight and finishes the trip without another encounter.
    static func win(_ e: inout GameEngine, _ expected: GameEvent, events: inout [GameEvent]) -> Bool {
        var got: [GameEvent] = []
        let ok = seek(&e) { p in
            got = fight(&p)
            return p.state.phase == .docked && got.contains(expected) && !got.contains(where: startedEncounter)
        }
        events = got
        return ok
    }

    /// Flees from the current encounter successfully and finishes the trip without another encounter.
    static func escape(_ e: inout GameEngine) -> Bool {
        seek(&e) { p in
            let r = p.perform(.encounter(.flee), acknowledging: yes)
            return r.events.contains { if case .playerEscaped = $0 { true } else { false } } && p.state.phase == .docked
                && !r.events.contains(where: startedEncounter)
        }
    }

    /// Edits the encounter in progress (e.g. damage dealt earlier in the fight).
    static func editEncounter(_ e: inout GameEngine, _ edit: (inout EncounterState) -> Void) {
        guard var enc = e.encounter else { return }
        edit(&enc)
        e.state.phase = .encounter(enc)
    }

    // MARK: Quest-loss paths (arrest, escape pod, ship purchase)

    /// Surrenders to police on a one-click trip: the arrest runs, then arrival.
    static func arrest(_ e: GameEngine) -> GameEngine {
        var a = e
        EncSpec.enter(&a, .policeAttack)
        a.perform(.encounter(.surrender), acknowledging: yes)
        return a
    }

    /// Loses the ship in a pirate fight with an escape pod: the pod sequence runs, then arrival.
    static func escapePod(_ e: GameEngine) -> GameEngine {
        var p = e
        p.state.commander.ship.escapePod = true
        EncSpec.enter(&p, .pirateAttack)
        _ = p.finishEncounter(.escapePod)
        return p
    }

    /// Buys a Gnat at a Hi-Tech system.
    static func buyShip(_ e: GameEngine) -> GameEngine {
        var b = e
        b.state.galaxy.systems[b.state.commander.currentSystem].techLevel = .hiTech
        b.perform(.buyShip(.gnat, transfers: []), acknowledging: yes)
        return b
    }

    /// Builds a small custom design at a shipyard.
    static func buildShip(_ e: GameEngine) -> GameEngine {
        var b = e
        b.state.galaxy.systems[b.state.commander.currentSystem].shipyard = .sienar
        let d = ShipDesign(name: "Folly", size: .tiny, cargoBays: 10, fuelTanks: 15, hull: 10, weaponSlots: 1, shieldSlots: 0,
                           gadgetSlots: 1, crewQuarters: 1)
        b.perform(.buildDesign(d, transfers: []), acknowledging: yes)
        return b
    }

    static func startedEncounter(_ ev: GameEvent) -> Bool {
        if case .encounterStarted = ev { true } else { false }
    }

    static func ended(_ events: [GameEvent], _ type: GameEndType) -> Bool {
        events.contains { if case .gameEnded(type, _) = $0 { true } else { false } }
    }
}

// MARK: - QST-DRAGONFLY

@Suite("QST-DRAGONFLY: the stolen Dragonfly")
struct QuestDragonflySpecTests {
    typealias QK = QuestKit
    typealias DF = QuestStatus.Dragonfly

    @Test("QST-DRAGONFLY-001 statuses 0…6; a new game starts at 0")
    func statuses() {
        #expect([DF.notStarted, DF.flyBaratas, DF.flyMelina, DF.flyRegulas, DF.flyZalkon, DF.destroyed, DF.done] == Array(0...6))
        for seed in [1, 2, 3] as [UInt64] { #expect(makeEngine(seed: seed).state.quests.dragonfly == DF.notStarted) }
    }

    @Test("QST-DRAGONFLY-002 the start is placed once at random, the follow-ups at fixed systems, the shield never")
    func placement() {
        for seed in 1...6 {
            let s = makeEngine(seed: UInt64(seed)).state
            #expect(QK.systems(s, with: .dragonfly).count == 1, "seed \(seed)")
            #expect(QK.systems(s, with: .dragonflyBaratas) == [SystemID.baratas] && SystemID.baratas == 6)
            #expect(QK.systems(s, with: .dragonflyMelina) == [SystemID.melina] && SystemID.melina == 59)
            #expect(QK.systems(s, with: .dragonflyRegulas) == [SystemID.regulas] && SystemID.regulas == 82)
            #expect(QK.systems(s, with: .dragonflyDestroyed) == [SystemID.zalkon] && SystemID.zalkon == 118)
            #expect(QK.systems(s, with: .dragonflyShield).isEmpty)
        }
    }

    @Test("QST-DRAGONFLY-003 table rows; only the shield asks for consent (amounts [0]); no step changes cash")
    func tableRows() {
        let s = makeEngine().state
        let rows: [(SpecialEventType, Int, Bool)] = [(.dragonfly, 1, true), (.dragonflyBaratas, 0, true), (.dragonflyMelina, 0, true),
                                                     (.dragonflyRegulas, 0, true), (.dragonflyDestroyed, 0, true), (.dragonflyShield, 0, false)]
        for (type, occurrence, messageOnly) in rows {
            let spec = s.specialEventSpec(type)
            #expect(spec?.price == 0 && spec?.occurrence == occurrence && spec?.messageOnly == messageOnly, "\(type)")
        }
        // Every step through the chain, without consent: only the shield returns a confirmation.
        var e = QK.engine { s in s.commander.ship.shields = [] }
        let cash = e.state.commander.cash
        for (sys, ev, status) in [(SystemID.baratas, SpecialEventType.dragonfly, 0), (SystemID.baratas, .dragonflyBaratas, 1),
                                  (SystemID.melina, .dragonflyMelina, 2), (SystemID.regulas, .dragonflyRegulas, 3),
                                  (SystemID.zalkon, .dragonflyDestroyed, 5)] {
            QK.dock(&e, at: sys)
            e.state.galaxy.systems[sys].specialEvent = ev
            e.state.quests.dragonfly = status
            let r = e.perform(.specialEvent)
            #expect(r.decision == nil && r.events == [.specialEventCompleted(ev)], "\(ev)")
        }
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        #expect(e.perform(.specialEvent, acknowledging: QK.yes).events == [.specialEventCompleted(.dragonflyShield)])
        #expect(e.state.commander.cash == cash)
    }

    @Test("QST-DRAGONFLY-004 button conditions by record and status; follow-ups only in order")
    func conditions() {
        var e = QK.engine()
        func shown(_ ev: SpecialEventType, status: Int, record: Int = 0) -> Bool {
            QK.dock(&e, at: SystemID.zalkon)
            e.state.galaxy.systems[SystemID.zalkon].specialEvent = ev
            e.state.quests.dragonfly = status
            e.state.commander.policeRecordScore = record
            return e.state.specialEventAvailable == ev
        }
        #expect(shown(.dragonfly, status: 0, record: -5) && !shown(.dragonfly, status: 0, record: -6))
        for status in 0...6 {
            #expect(shown(.dragonflyBaratas, status: status) == (status > 0 && status < 5), "Baratas \(status)")
            #expect(shown(.dragonflyMelina, status: status) == (status > 1 && status < 5), "Melina \(status)")
            #expect(shown(.dragonflyRegulas, status: status) == (status > 2 && status < 5), "Regulas \(status)")
            #expect(shown(.dragonflyDestroyed, status: status) == (status == 5), "Destroyed \(status)")
            #expect(shown(.dragonflyShield, status: status, record: -50), "Shield \(status)")
        }
        // Only while docked.
        _ = shown(.dragonflyShield, status: 5)
        EncSpec.enter(&e, .pirateIgnore)
        #expect(e.state.specialEventAvailable == nil)
    }

    @Test("QST-DRAGONFLY-006 QST-DRAGONFLY-007 each message step adds one and removes the event, with no RNG draw or side effect")
    func messageSteps() {
        var e = QK.engine { s in
            s.commander.ship.cargo[TradeItemType.ore.rawValue] = 4
            s.commander.reputationScore = 12
        }
        let start = QK.systems(e.state, with: .dragonfly).first ?? 0
        for (sys, status) in [(start, 1), (SystemID.baratas, 2), (SystemID.melina, 3), (SystemID.regulas, 4)] {
            QK.dock(&e, at: sys)
            let before = e.state
            #expect(e.perform(.specialEvent).rejection == nil)
            #expect(e.state.quests.dragonfly == status && e.state.galaxy.systems[sys].specialEvent == nil)
            #expect(e.state.rng == before.rng, "no RNG draw")
            #expect(e.state.commander.ship == before.commander.ship && e.state.commander.cash == before.commander.cash)
            #expect(e.state.commander.policeRecordScore == 0 && e.state.commander.reputationScore == 12)
            #expect(e.state.mercenaries == before.mercenaries)
        }
    }

    @Test("QST-DRAGONFLY-008 Zalkon's message keeps status 5 and replaces the event with the shield offer, shown at once")
    func destroyedMessage() {
        var e = QK.engine { s in s.quests.dragonfly = DF.destroyed }
        QK.dock(&e, at: SystemID.zalkon)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.dragonflyDestroyed)])
        #expect(e.state.quests.dragonfly == DF.destroyed)
        #expect(e.state.currentSystem.specialEvent == .dragonflyShield && e.state.specialEventAvailable == .dragonflyShield)
    }

    @Test("QST-DRAGONFLY-009 the shield: consent, noFreeSlot changes nothing, else a Lightning shield at 350 and status 6")
    func shieldReward() {
        var e = QK.engine { s in s.quests.dragonfly = DF.destroyed }
        QK.dock(&e, at: SystemID.zalkon)
        e.state.galaxy.systems[SystemID.zalkon].specialEvent = .dragonflyShield
        #expect(e.perform(.specialEvent) == .needsConfirmation(Confirmation(.acceptSpecialEvent, amounts: [0])))
        let full = e.state
        #expect(e.perform(.specialEvent, acknowledging: QK.yes).rejection == .noFreeSlot)
        #expect(e.state == full, "rejected: offer and status kept")
        e.state.commander.ship.shields = [ShieldInstance(type: .energy, charge: 10)]
        #expect(e.perform(.specialEvent, acknowledging: QK.yes).events == [.specialEventCompleted(.dragonflyShield)])
        #expect(e.ruleset.tables.shield(.lightning).power == 350)
        #expect(e.state.commander.ship.shields == [ShieldInstance(type: .energy, charge: 10), ShieldInstance(type: .lightning, charge: 350)])
        #expect(e.state.quests.dragonfly == DF.done && e.state.currentSystem.specialEvent == nil)
    }

    @Test("QST-DRAGONFLY-010 the reward is an ordinary Lightning shield: sold, transferred at the unique price, never re-offered")
    func ordinaryShield() {
        var e = QK.engine { s in s.commander.ship.shields = []; s.quests.dragonfly = DF.destroyed }
        QK.dock(&e, at: SystemID.zalkon)
        e.state.galaxy.systems[SystemID.zalkon].specialEvent = .dragonflyShield
        e.perform(.specialEvent, acknowledging: QK.yes)
        #expect(e.state.commander.ship.shields == [QK.lightning(e.state)])
        // A ship trade offers it as the unique Lightning shield transfer.
        let quote = e.state.shipQuote(.hornet)
        #expect(quote.candidates.first { $0.item == .lightningShield }?.price == e.state.transferPrice(.lightningShield))
        // Selling it pays the ordinary 3/4 price; the offer does not come back.
        let cash = e.state.commander.cash
        let r = e.perform(.sellShield(index: 0), acknowledging: QK.yes)
        #expect(r.events == [.soldEquipment(price: e.ruleset.tables.shield(.lightning).price * 3 / 4)])
        #expect(e.state.commander.cash > cash && e.state.commander.ship.shields.isEmpty)
        #expect(e.state.quests.dragonfly == DF.done && e.state.currentSystem.specialEvent == nil && e.state.specialEventAvailable == nil)
    }

    @Test("QST-DRAGONFLY-013 CMB-045 destroying or disabling the Dragonfly: status 5, kill, record +1, reputation +6, no bounty or scoop")
    func defeat() throws {
        for disable in [false, true] {
            var e = QK.engine { s in
                s.quests.dragonfly = DF.flyZalkon
                if disable {
                    s.commander.ship.weapons = [.photonDisruptor, .photonDisruptor]
                    s.options.disableOpponents = true
                    for i in s.specialShips.dragonfly.shields.indices { s.specialShips.dragonfly.shields[i].charge = 0 }
                }
            }
            try QK.prepareWarp(&e, to: SystemID.zalkon)
            try #require(QK.warpInto(&e, .dragonflyAttack, clicks: 1))
            let before = e.state.commander
            var events: [GameEvent] = []
            try #require(QK.win(&e, disable ? .opponentDisabled(.dragonfly) : .opponentDestroyed(.dragonfly), events: &events))
            let c = e.state.commander
            #expect(e.state.quests.dragonfly == DF.destroyed)
            #expect(c.kills.pirates == before.kills.pirates + 1 && c.policeRecordScore == before.policeRecordScore + 1)
            #expect(c.reputationScore == before.reputationScore + 6 && ShipType.dragonfly.rawValue / 2 + 1 == 6)
            #expect(c.cash == before.cash && !events.contains { if case .bountyPaid = $0 { true } else { false } })
            #expect(e.state.pendingScoop == nil)
            #expect(events.contains(.arrived(system: SystemID.zalkon)) && c.currentSystem == SystemID.zalkon, "the trip continues")
        }
    }

    @Test("QST-DRAGONFLY-015 arrest, the escape pod and ship purchase keep the status; death by the Dragonfly ends the game")
    func lossPaths() throws {
        for status in 1...6 {
            let e = QK.engine { s in s.quests.dragonfly = status }
            for (name, after) in [("arrest", QK.arrest(e)), ("pod", QK.escapePod(e)), ("buy", QK.buyShip(e)), ("build", QK.buildShip(e))] {
                let happened = name == "arrest" ? after.state.commander.policeRecordScore == -5 : after.state.commander.ship != e.state.commander.ship
                #expect(happened, "\(name) happened")
                #expect(after.state.quests.dragonfly == status, "\(name) at \(status)")
            }
        }
        var e = QK.engine { s in s.quests.dragonfly = DF.flyZalkon; s.commander.ship.shields = [] }
        try QK.prepareWarp(&e, to: SystemID.zalkon)
        try #require(QK.warpInto(&e, .dragonflyAttack, clicks: 1))
        e.state.commander.ship.hull = 1
        var events: [GameEvent] = []
        try #require(QK.seek(&e) { p in
            events = QK.fight(&p)
            return p.state.phase == .gameOver(.killed)
        })
        #expect(events.contains(.playerDestroyed) && QK.ended(events, .killed))
        #expect(e.state.quests.dragonfly == DF.flyZalkon)
    }

    @Test("QST-DRAGONFLY-016 arrival headlines follow the system's event and the status")
    func news() {
        var e = QK.engine()
        let start = QK.systems(e.state, with: .dragonfly).first ?? 0
        func headline(_ sys: Int, _ status: Int, event: SpecialEventType? = nil) -> NewsEvent? {
            var s = e.state
            if let event { s.galaxy.systems[sys].specialEvent = event }
            s.commander.currentSystem = sys
            s.quests.dragonfly = status
            s.newsEvents = []
            s.addArrivalNews()
            return s.newsEvents.last
        }
        #expect(headline(start, 0) == .dragonfly)
        e.state.galaxy.systems[start].specialEvent = nil
        #expect(headline(start, 1) == nil, "handled start: no headline")
        for (sys, status, news) in [(SystemID.baratas, 1, NewsEvent.dragonflyBaratas), (SystemID.melina, 2, .dragonflyMelina),
                                    (SystemID.regulas, 3, .dragonflyRegulas)] {
            #expect(headline(sys, status) == news)
            #expect(headline(sys, status + 1) == nil && headline(sys, status - 1) == nil)
        }
        #expect(headline(SystemID.zalkon, 4) == .dragonflyZalkon)
        #expect(headline(SystemID.zalkon, 5) == .dragonflyDestroyed)
        #expect(headline(SystemID.zalkon, 3) == nil)
        #expect(headline(SystemID.zalkon, 5, event: .dragonflyShield) == nil)
    }

    @Test("QST-DRAGONFLY-017 scenario: start, Baratas, Melina, Regulas, the Zalkon fight at click 1, the message and the shield")
    func happyPath() throws {
        var e = QK.engine { s in s.commander.ship.shields = [QK.lightning(s)] }
        let start = try #require(QK.systems(e.state, with: .dragonfly).first)
        QK.dock(&e, at: start)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.dragonfly)])
        #expect(e.state.quests.dragonfly == DF.flyBaratas && e.state.galaxy.systems[start].specialEvent == nil)
        for (sys, status) in [(SystemID.baratas, DF.flyMelina), (SystemID.melina, DF.flyRegulas), (SystemID.regulas, DF.flyZalkon)] {
            QK.dock(&e, at: sys)
            #expect(e.perform(.specialEvent).rejection == nil)
            #expect(e.state.quests.dragonfly == status)
        }
        try QK.prepareWarp(&e, to: SystemID.zalkon)
        try #require(QK.warpInto(&e, .dragonflyAttack, clicks: 1))
        #expect(e.encounter?.opponent == e.state.specialShips.dragonfly)
        let before = e.state.commander
        var events: [GameEvent] = []
        try #require(QK.win(&e, .opponentDestroyed(.dragonfly), events: &events))
        #expect(e.state.quests.dragonfly == DF.destroyed)
        #expect(e.state.commander.kills.pirates == before.kills.pirates + 1)
        #expect(e.state.commander.policeRecordScore == before.policeRecordScore + 1)
        #expect(e.state.commander.reputationScore == before.reputationScore + 6)
        // Docked at Zalkon: the message replaces the event, then the shield needs consent.
        #expect(e.state.newsEvents.contains(.dragonflyDestroyed))
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.dragonflyDestroyed)])
        #expect(e.state.currentSystem.specialEvent == .dragonflyShield && e.state.quests.dragonfly == DF.destroyed)
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        e.perform(.specialEvent, acknowledging: QK.yes)
        #expect(e.state.commander.ship.shields.count == 2 && e.state.commander.ship.shields[1] == ShieldInstance(type: .lightning, charge: 350))
        #expect(e.state.quests.dragonfly == DF.done && e.state.currentSystem.specialEvent == nil && e.state.specialEventAvailable == nil)
    }

    @Test("QST-DRAGONFLY-018 scenario: the start needs record >= -5; follow-ups are hidden out of order")
    func gates() {
        var e = QK.engine { s in s.commander.policeRecordScore = -6 }
        let start = QK.systems(e.state, with: .dragonfly).first ?? 0
        QK.dock(&e, at: start)
        #expect(e.state.specialEventAvailable == nil && e.perform(.specialEvent).rejection == .noSpecialEvent)
        e.state.quests.dragonfly = DF.flyBaratas
        for (sys, shown) in [(SystemID.baratas, true), (SystemID.melina, false), (SystemID.regulas, false)] {
            QK.dock(&e, at: sys)
            #expect((e.state.specialEventAvailable != nil) == shown, "\(sys)")
            if !shown { #expect(e.perform(.specialEvent).rejection == .noSpecialEvent) }
        }
        e.state.quests.dragonfly = DF.notStarted
        QK.dock(&e, at: SystemID.baratas)
        #expect(e.perform(.specialEvent).rejection == .noSpecialEvent)
    }

    @Test("QST-DRAGONFLY-019 scenario (a): no free shield slot, sell one, then install")
    func failuresShield() {
        var e = QK.engine { s in s.quests.dragonfly = DF.destroyed }
        QK.dock(&e, at: SystemID.zalkon)
        e.state.galaxy.systems[SystemID.zalkon].specialEvent = .dragonflyShield
        let before = e.state
        #expect(e.perform(.specialEvent, acknowledging: QK.yes).rejection == .noFreeSlot && e.state == before)
        e.perform(.sellShield(index: 0), acknowledging: QK.yes)
        e.perform(.specialEvent, acknowledging: QK.yes)
        #expect(e.state.commander.ship.shields.last == QK.lightning(e.state) && e.state.quests.dragonfly == DF.done)
    }

    @Test("QST-DRAGONFLY-012 QST-DRAGONFLY-019 scenario (b): an escape keeps status 4 and the damage; the next trip meets it again")
    func failuresEscape() throws {
        var e = QK.engine { s in s.quests.dragonfly = DF.flyZalkon }
        try QK.prepareWarp(&e, to: SystemID.zalkon)
        let launch = e.state.commander.currentSystem
        try #require(QK.warpInto(&e, .dragonflyAttack, clicks: 1))
        QK.editEncounter(&e) { enc in enc.opponent.hull = 4 }
        try #require(QK.escape(&e))
        #expect(e.state.commander.currentSystem == SystemID.zalkon && e.state.quests.dragonfly == DF.flyZalkon)
        #expect(e.state.specialShips.dragonfly.hull == 4)
        #expect(e.state.specialEventAvailable == nil, "no button at status 4")
        QK.dock(&e, at: launch)
        QK.refuelAndTarget(&e, SystemID.zalkon)
        try #require(QK.warpInto(&e, .dragonflyAttack, clicks: 1))
        #expect(e.encounter?.opponent.hull == 4 && e.state.quests.dragonfly == DF.flyZalkon)
    }

    @Test("QST-DRAGONFLY-012 QST-DRAGONFLY-019 scenario (c): ignored while cloaked, no button at Zalkon; it waits for the next trip")
    func failuresCloaked() throws {
        var e = QK.engine { s in
            s.quests.dragonfly = DF.flyZalkon
            s.commander.ship.gadgets = [.cloakingDevice, .autoRepairSystem]
            s.mercenaries[CrewID.commander].skills[3] = 10
        }
        try QK.prepareWarp(&e, to: SystemID.zalkon)
        let launch = e.state.commander.currentSystem
        try #require(QK.warpInto(&e, .dragonflyIgnore, clicks: 1))
        let r = e.perform(.encounter(.ignore))
        #expect(r.events.contains(.arrived(system: SystemID.zalkon)))
        #expect(e.state.quests.dragonfly == DF.flyZalkon && e.state.specialEventAvailable == nil)
        QK.dock(&e, at: launch)
        QK.refuelAndTarget(&e, SystemID.zalkon)
        #expect(QK.warpInto(&e, .dragonflyIgnore, clicks: 1))
    }
}

// MARK: - CMB / ENC quest-ship outcomes

@Suite("CMB/ENC: quest-ship combat outcomes")
struct QuestShipCombatSpecTests {
    typealias QK = QuestKit

    /// A Hornet-mounted commander against the persistent quest ship of `type`, with that ship's shields drained.
    static func duel(_ type: EncounterType, _ ship: (GameState) -> Ship, weapons: [WeaponType], disable: Bool) -> (GameState, EncounterState) {
        var s = CombatKit.state()
        s.commander.ship = CombatKit.playerShip(s, .hornet, weapons: weapons)
        s.commander.ship.hull = 10_000
        s.mercenaries[CrewID.commander].skills = [8, 8, 8, 8]
        s.options.disableOpponents = disable
        var opp = ship(s)
        for i in opp.shields.indices { opp.shields[i].charge = 0 }
        return (s, EncounterState(type: type, opponent: opp))
    }

    /// Plays rounds from `s` until the encounter is decided (not `.continue`).
    static func decide(_ s: inout GameState, _ enc: inout EncounterState) -> (RoundResult, [GameEvent]) {
        var all: [GameEvent] = []
        for _ in 0..<300 {
            let (result, events) = s.executeRound(&enc)
            all += events
            if result != .continue { return (result, all) }
        }
        return (.continue, all)
    }

    @Test("CMB-005 attacking the Scorpion needs disruptor power; the checks run no weapons, no lasers, no disruptors")
    func scorpionNeedsDisruptors() {
        func attempt(_ type: EncounterType, _ weapons: [WeaponType], _ ship: ShipType) -> CommandError? {
            var e = EncSpec.encounter(type, opponent: { s in EncSpec.ship(s, ship) })
            e.state.commander.ship.weapons = weapons
            return e.perform(.encounter(.attack), acknowledging: QK.yes).rejection
        }
        #expect(attempt(.scorpionAttack, [], .scorpion) == .noWeapons)
        #expect(attempt(.scorpionAttack, [.militaryLaser, .morgansLaser], .scorpion) == .noDisruptors)
        #expect(attempt(.scorpionAttack, [.photonDisruptor], .scorpion) == nil)
        #expect(attempt(.scorpionAttack, [.quantumDisruptor], .scorpion) == nil)
        #expect(attempt(.spaceMonsterAttack, [.photonDisruptor], .spaceMonster) == .noLasers)
        #expect(attempt(.spaceMonsterAttack, [], .spaceMonster) == .noWeapons)
    }

    @Test("CMB-042 the Scorpion never dies: at hull 0 after a player shot it is left at hull 1 and disabled")
    func scorpionNeverDies() {
        var (s, enc0) = Self.duel(.scorpionAttack, { $0.specialShips.scorpion }, weapons: [.morgansLaser, .morgansLaser], disable: false)
        enc0.opponent.hull = 3
        var hitSeen = false
        let found = QK.seek(&s) { p in
            var enc = enc0
            _ = p.executeAttack(commanderAttacks: true, fleeing: false, encounter: &enc)
            guard enc.opponent.hull != 3 else { return false }
            hitSeen = true
            #expect(enc.opponent.hull == 1 && enc.opponentDisabled)
            return true
        }
        #expect(found && hitSeen)
    }

    @Test("CMB-045 ENC-017 disabling the Dragonfly, Scarab or Scorpion defeats it: kill, record +1, quest status, reputation, no bounty")
    func disabledQuestShips() {
        for (type, shipType) in [(EncounterType.dragonflyAttack, ShipType.dragonfly), (.scarabAttack, .scarab), (.scorpionAttack, .scorpion)] {
            let pick: (GameState) -> Ship = { s in
                switch shipType {
                case .dragonfly: s.specialShips.dragonfly
                case .scarab: s.specialShips.scarab
                default: s.specialShips.scorpion
                }
            }
            var (s, enc0) = Self.duel(type, pick, weapons: [.quantumDisruptor, .quantumDisruptor], disable: true)
            let before = s
            var outcome: (RoundResult, [GameEvent]) = (.continue, [])
            #expect(QK.seek(&s) { p in
                var enc = enc0
                outcome = Self.decide(&p, &enc)
                return outcome.1.contains(.opponentDisabled(shipType))
            }, "\(shipType)")
            let c = s.commander
            #expect(outcome.0 == .normal && outcome.1.last == .opponentDisabled(shipType))
            #expect(c.kills.pirates == before.commander.kills.pirates + 1 && c.policeRecordScore == before.commander.policeRecordScore + 1)
            #expect(c.reputationScore == before.commander.reputationScore + shipType.rawValue / 2 + 1)
            #expect(c.cash == before.commander.cash && s.pendingScoop == nil)
            #expect(!outcome.1.contains { if case .bountyPaid = $0 { true } else { false } })
            switch shipType {
            case .dragonfly: #expect(s.quests.dragonfly == QuestStatus.Dragonfly.destroyed)
            case .scarab: #expect(s.quests.scarab == QuestStatus.Scarab.destroyed)
            default: #expect(s.quests.princess == QuestStatus.Princess.rescued)
            }
        }
    }

    @Test("ENC-017 destroying the monster, Dragonfly or Scarab sets its status and adds a pirate kill and +1 record; the Scorpion is only disabled")
    func destroyedQuestShips() {
        let ships: [(EncounterType, ShipType)] = [(.spaceMonsterAttack, .spaceMonster), (.dragonflyAttack, .dragonfly), (.scarabAttack, .scarab),
                                                  (.scorpionAttack, .scorpion)]
        for (type, shipType) in ships {
            let pick: (GameState) -> Ship = { s in
                switch shipType {
                case .spaceMonster: s.specialShips.spaceMonster
                case .dragonfly: s.specialShips.dragonfly
                case .scarab: s.specialShips.scarab
                default: s.specialShips.scorpion
                }
            }
            var (s, enc0) = Self.duel(type, pick, weapons: [.morgansLaser, .morgansLaser, .morgansLaser], disable: false)
            enc0.opponent.hull = min(enc0.opponent.hull, 30)
            let before = s
            var outcome: (RoundResult, [GameEvent]) = (.continue, [])
            var final = enc0
            #expect(QK.seek(&s) { p in
                var enc = enc0
                outcome = Self.decide(&p, &enc)
                final = enc
                return outcome.0 == .normal
            }, "\(shipType)")
            #expect(s.commander.kills.pirates == before.commander.kills.pirates + 1, "\(shipType)")
            #expect(s.commander.policeRecordScore == before.commander.policeRecordScore + 1, "\(shipType)")
            switch shipType {
            case .spaceMonster: #expect(s.quests.spaceMonster == QuestStatus.SpaceMonster.destroyed && outcome.1.contains(.opponentDestroyed(.spaceMonster)))
            case .dragonfly: #expect(s.quests.dragonfly == QuestStatus.Dragonfly.destroyed && outcome.1.contains(.opponentDestroyed(.dragonfly)))
            case .scarab: #expect(s.quests.scarab == QuestStatus.Scarab.destroyed && outcome.1.contains(.opponentDestroyed(.scarab)))
            default:
                #expect(s.quests.princess == QuestStatus.Princess.rescued && outcome.1.last == .opponentDisabled(.scorpion))
                #expect(final.opponent.hull == 1 && !outcome.1.contains(.opponentDestroyed(.scorpion)))
            }
        }
    }

    @Test("ENC-166 quest outcomes of encounter actions: artifact to the Mantis, the sculpture, Wild joins pirates, famous-captain news, Marie Celeste")
    func questActionOutcomes() {
        // Surrendering the artifact to the Mantis.
        var m = EncSpec.encounter(.pirateAttack, with: { s in s.quests.artifact = QuestStatus.Artifact.onBoard },
                                  opponent: { s in EncSpec.ship(s, .mantis) })
        #expect(m.perform(.encounter(.surrender), acknowledging: QK.yes).events.first == .artifactRelinquished)
        #expect(m.state.quests.artifact == QuestStatus.Artifact.notStarted)
        // Pirates take an unhidden sculpture.
        var sc = EncSpec.encounter(.pirateAttack, with: { s in
            s.quests.sculpture = QuestStatus.Sculpture.inTransit
            s.commander.ship.cargo[TradeItemType.ore.rawValue] = 2
        })
        #expect(sc.perform(.encounter(.surrender), acknowledging: QK.yes).events.contains(.sculptureTaken))
        #expect(sc.state.quests.sculpture == QuestStatus.Sculpture.notStarted)
        // Wild joins pirates only when their ship has more than one crew quarter.
        for (pirate, joins) in [(ShipType.gnat, false), (.wasp, true)] {
            var w = EncSpec.encounter(.pirateAttack, with: { s in
                s.hireCrew(CrewID.wild)
                s.quests.wild = QuestStatus.Wild.started
                s.commander.ship.cargo[TradeItemType.ore.rawValue] = 2
            }, opponent: { s in EncSpec.ship(s, pirate) })
            let events = w.perform(.encounter(.surrender), acknowledging: QK.yes).events
            #expect(events.contains(.wildJoinedPirates) == joins, "\(pirate)")
            #expect(w.state.quests.wild == (joins ? QuestStatus.Wild.notStarted : QuestStatus.Wild.started), "\(pirate)")
        }
        // A famous-captain kill replaces the "attacked" headline with "destroyed".
        var s = CombatKit.state()
        s.newsEvents = [.captConradAttacked]
        var opp = CombatKit.opponent(&s, .wasp)
        opp.hull = 0
        var enc = EncounterState(type: .famousCaptainAttack, opponent: opp)
        _ = s.encounterWon(&enc)
        #expect(s.newsEvents == [.captConradDestroyed])
        // Boarding the Marie Celeste opens the plunder decision flagged for the customs check (ENC-161).
        var mc = EncSpec.encounter(.marieCeleste)
        let r = mc.perform(.encounter(.board), acknowledging: QK.yes)
        #expect(r.decision == .plunder(EncSpec.gnat(mc.state).cargo) && mc.state.pendingPlunder?.marieCeleste == true)
    }
}
