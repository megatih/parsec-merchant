// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

@Suite("QST-JAPORI: antidote for Japori")
struct QuestJaporiSpecTests {
    typealias QK = QuestKit
    typealias JP = QuestStatus.Japori

    /// The quest engine with an empty hold (35 bays) and the commander docked at the pickup system.
    static func atPickup(_ adjust: (inout GameState) -> Void = { _ in }) -> (GameEngine, Int) {
        var e = QK.engine(adjust)
        let pickup = QK.systems(e.state, with: .japori).first ?? 1
        QK.dock(&e, at: pickup)
        return (e, pickup)
    }

    /// Fills the hold so that exactly `free` bays stay empty.
    static func leaveFree(_ s: inout GameState, _ free: Int) {
        s.commander.ship.cargo[TradeItemType.water.rawValue] = 0
        s.commander.ship.cargo[TradeItemType.water.rawValue] = s.freeCargoBays - free
    }

    @Test("QST-JAPORI-001 statuses 0…2; a new game starts at 0")
    func statuses() {
        #expect([JP.notStarted, JP.inTransit, JP.done] == Array(0...2))
        #expect(makeEngine(seed: 4).state.quests.japori == JP.notStarted)
    }

    @Test("QST-JAPORI-002 the pickup once at random, the delivery at Japori; the pickup asks for consent, the delivery is message-only")
    func eventsAndRows() {
        for seed in 1...6 {
            let s = makeEngine(seed: UInt64(seed)).state
            #expect(QK.systems(s, with: .japori).count == 1)
            #expect(QK.systems(s, with: .japoriDelivery) == [SystemID.japori] && SystemID.japori == 41)
        }
        let s = makeEngine().state
        #expect(s.specialEventSpec(.japori).map { [$0.price, $0.occurrence] } == [0, 1] && s.specialEventSpec(.japori)?.messageOnly == false)
        #expect(s.specialEventSpec(.japoriDelivery).map { [$0.price, $0.occurrence] } == [0, 0])
        #expect(s.specialEventSpec(.japoriDelivery)?.messageOnly == true)
        var (e, _) = Self.atPickup()
        #expect(e.perform(.specialEvent) == .needsConfirmation(Confirmation(.acceptSpecialEvent, amounts: [0])))
        e.state.quests.japori = JP.inTransit
        QK.dock(&e, at: SystemID.japori)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.japoriDelivery)])
    }

    @Test("QST-JAPORI-003 the pickup needs status 0 and record >= -5; the delivery needs status 1")
    func conditions() {
        var (e, _) = Self.atPickup()
        for (status, record, shown) in [(0, -5, true), (0, -6, false), (1, 0, false), (2, 0, false)] {
            e.state.quests.japori = status
            e.state.commander.policeRecordScore = record
            #expect((e.state.specialEventAvailable == .japori) == shown, "status \(status) record \(record)")
        }
        QK.dock(&e, at: SystemID.japori)
        for status in 0...2 {
            e.state.quests.japori = status
            e.state.commander.policeRecordScore = -50
            #expect((e.state.specialEventAvailable == .japoriDelivery) == (status == JP.inTransit))
        }
    }

    @Test("QST-JAPORI-005 fewer than 10 free bays rejects with noEmptyBays; otherwise status 1; the pickup stays either way")
    func pickup() {
        var (e, pickup) = Self.atPickup { s in Self.leaveFree(&s, 9) }
        let before = e.state
        #expect(e.perform(.specialEvent, acknowledging: QK.yes).rejection == .noEmptyBays && e.state == before)
        #expect(e.state.galaxy.systems[pickup].specialEvent == .japori)
        Self.leaveFree(&e.state, 10)
        #expect(e.perform(.specialEvent, acknowledging: QK.yes).events == [.specialEventCompleted(.japori)])
        #expect(e.state.quests.japori == JP.inTransit && e.state.galaxy.systems[pickup].specialEvent == .japori)
        #expect(e.state.specialEventAvailable == nil, "hidden while the status is not 0")
    }

    @Test("QST-JAPORI-006 the antidote fills 10 bays but is not cargo: it cannot be sold, dumped, jettisoned or stolen")
    func antidoteBays() {
        var (e, _) = Self.atPickup { s in
            s.commander.ship.cargo[TradeItemType.ore.rawValue] = 5
            setMarket(&s)
        }
        let free = e.state.freeCargoBays, filled = e.state.filledCargoBays, cargo = e.state.commander.ship.cargo
        let priced = e.state.commander.priceCargo
        e.perform(.specialEvent, acknowledging: QK.yes)
        #expect(e.state.freeCargoBays == free - 10 && e.state.filledCargoBays == filled + 10)
        #expect(e.state.commander.ship.cargo == cargo && e.state.commander.priceCargo == priced)
        // Selling every trade good leaves the antidote's 10 bays taken.
        e.perform(.sellCargo(.ore, quantity: 5), acknowledging: QK.yes)
        #expect(e.state.filledCargoBays == 10 && e.state.quests.japori == JP.inTransit)
        // Pirates find nothing to take: they blackmail instead, and the antidote stays.
        var p = e
        EncSpec.enter(&p, .pirateAttack)
        let r = p.perform(.encounter(.surrender), acknowledging: QK.yes)
        #expect(r.events.contains { if case .blackmailed = $0 { true } else { false } })
        #expect(p.state.quests.japori == JP.inTransit && p.state.filledCargoBays == 10)
    }

    @Test("QST-JAPORI-007 the delivery sets 2, raises two random skills, frees the bays, removes the event; Trader changes reprice")
    func delivery() {
        var e = QK.engine { s in
            s.quests.japori = JP.inTransit
            s.mercenaries[CrewID.commander].skills = [9, 9, 5, 9]
        }
        QK.dock(&e, at: SystemID.japori)
        let free = e.state.freeCargoBays
        e.perform(.specialEvent)
        // Only Trader can rise (9 + 1 would leave 1…9): both increases go to it, and buy prices follow the new skill.
        #expect(e.state.mercenaries[CrewID.commander].skills == [9, 9, 7, 9])
        #expect(e.state.quests.japori == JP.done && e.state.currentSystem.specialEvent == nil)
        #expect(e.state.freeCargoBays == free + 10)
        let s = e.state
        #expect(s.buyPrices == Pricing.buyPrices(sell: s.sellPrices, in: s.currentSystem, criminal: false, traderSkill: s.skill(.trader),
                                                 ruleset: s.ruleset))
    }

    @Test("QST-JAPORI-009 the escape pod resets the status to 0; the kept pickup shows again with record >= -5")
    func podFailure() {
        var (e, pickup) = Self.atPickup()
        e.perform(.specialEvent, acknowledging: QK.yes)
        let pod = QK.escapePod(e)
        #expect(pod.state.quests.japori == JP.notStarted && pod.state.freeCargoBays == pod.state.commander.ship.cargoBays(pod.ruleset))
        // The app's "return to" system is the first system holding the kept pickup.
        #expect(QK.systems(pod.state, with: .japori).first == pickup)
        var back = pod
        QK.dock(&back, at: pickup)
        #expect(back.state.specialEventAvailable == .japori)
    }

    @Test("QST-JAPORI-010 an arrest completes the delivery with no skill increase; the pickup stays hidden")
    func arrestFailure() {
        var (e, pickup) = Self.atPickup()
        e.perform(.specialEvent, acknowledging: QK.yes)
        let skills = e.state.mercenaries[CrewID.commander].skills
        var a = QK.arrest(e)
        #expect(a.state.quests.japori == JP.done && a.state.mercenaries[CrewID.commander].skills == skills)
        #expect(a.state.galaxy.systems[pickup].specialEvent == .japori)
        QK.dock(&a, at: pickup)
        a.state.commander.policeRecordScore = 0
        #expect(a.state.specialEventAvailable == nil)
    }

    @Test("QST-JAPORI-012 no IncDays rule reads the status")
    func noDeadline() {
        for status in 0...2 {
            var s = QK.engine { s in s.quests.japori = status }.state
            _ = s.incDays(200)
            #expect(s.quests.japori == status)
        }
    }

    @Test("QST-JAPORI-013 arrival headlines: the pickup at status 0 whatever the record, Japori at status 1")
    func news() {
        let base = QK.engine().state
        let pickup = QK.systems(base, with: .japori).first ?? 1
        func headline(_ sys: Int, _ status: Int, record: Int = 0) -> NewsEvent? {
            var s = base
            s.commander.currentSystem = sys
            s.commander.policeRecordScore = record
            s.quests.japori = status
            s.newsEvents = []
            s.addArrivalNews()
            return s.newsEvents.last
        }
        #expect(headline(pickup, 0) == .japori && headline(pickup, 0, record: -40) == .japori)
        #expect(headline(pickup, 1) == nil && headline(pickup, 2) == nil)
        #expect(headline(SystemID.japori, 1) == .japoriDelivery)
        #expect(headline(SystemID.japori, 0) == nil && headline(SystemID.japori, 2) == nil)
    }

    @Test("QST-JAPORI-014 scenario: consent, 2 free bays, warp to Japori, two random skill increases, 12 free bays again")
    func happyPath() throws {
        var (e, pickup) = Self.atPickup { s in
            Self.leaveFree(&s, 12)
            s.mercenaries[CrewID.commander].skills = [9, 9, 4, 4]
        }
        #expect(e.perform(.specialEvent) == .needsConfirmation(Confirmation(.acceptSpecialEvent, amounts: [0])))
        e.perform(.specialEvent, acknowledging: QK.yes)
        #expect(e.state.quests.japori == JP.inTransit && e.state.freeCargoBays == 2)
        #expect(e.state.galaxy.systems[pickup].specialEvent == .japori && e.state.specialEventAvailable == nil)
        try QK.prepareWarp(&e, to: SystemID.japori)
        try #require(QK.quietWarp(&e))
        #expect(e.state.newsEvents.contains(.japoriDelivery))
        // The two draws pick among the skills that can still rise (Trader and Engineer), in id order.
        var rng = e.state.rng
        var expected = [9, 9, 4, 4]
        for _ in 0..<2 { expected[2 + rng.next(below: 2)] += 1 }
        e.perform(.specialEvent)
        #expect(e.state.mercenaries[CrewID.commander].skills == expected)
        #expect(e.state.quests.japori == JP.done && e.state.freeCargoBays == 12 && e.state.currentSystem.specialEvent == nil)
    }

    @Test("QST-JAPORI-015 scenario failures: 9 bays, record -6, the pod restarts the quest, an arrest ends it")
    func failures() {
        // (a) 9 free bays.
        var (a, _) = Self.atPickup { s in Self.leaveFree(&s, 9) }
        let before = a.state
        #expect(a.perform(.specialEvent, acknowledging: QK.yes).rejection == .noEmptyBays && a.state == before)
        // (b) record -6.
        var (b, _) = Self.atPickup { s in s.commander.policeRecordScore = -6 }
        #expect(b.perform(.specialEvent, acknowledging: QK.yes).rejection == .noSpecialEvent)
        // (c) the pod: status 0, the pickup is offered again.
        var (c, pickup) = Self.atPickup()
        c.perform(.specialEvent, acknowledging: QK.yes)
        var pod = QK.escapePod(c)
        #expect(pod.state.quests.japori == JP.notStarted && QK.systems(pod.state, with: .japori).first == pickup)
        QK.dock(&pod, at: pickup)
        pod.state.commander.policeRecordScore = -5
        #expect(pod.perform(.specialEvent, acknowledging: QK.yes).events == [.specialEventCompleted(.japori)])
        // (d) arrest: delivered by the Space Corps, skills unchanged, no Japori button.
        let skills = c.state.mercenaries[CrewID.commander].skills
        var arrested = QK.arrest(c)
        #expect(arrested.state.quests.japori == JP.done && arrested.state.mercenaries[CrewID.commander].skills == skills)
        QK.dock(&arrested, at: SystemID.japori)
        #expect(arrested.state.specialEventAvailable == nil && arrested.perform(.specialEvent).rejection == .noSpecialEvent)
    }
}
