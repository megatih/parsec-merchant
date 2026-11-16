// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// A game at a Moon system with list-price worth exactly `worth` and `cash` in hand (debt makes up the difference).
private func moonEngine(worth: Int, cash: Int? = nil, _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
    QSTKit.engine(.moon) { s in
        let ship = s.commander.ship.spec(s.ruleset).price
        let c = cash ?? worth - ship
        s.commander.cash = c
        s.commander.debt = c + ship - worth
        adjust(&s)
    }
}

// MARK: - Moon

@Suite("Quest: buying a moon and retiring (QST-MOON {M4})")
struct QuestMoonSpecTests {
    @Test("QST-MOON-001 QST-MOON-014 Moon is shown iff moon == 0 and list-price worth > 400000 (400000 no, 400001 yes)")
    func threshold() {
        #expect(moonEngine(worth: 400_000).state.worth == 400_000)
        #expect(moonEngine(worth: 400_000).state.specialEventAvailable == nil)
        #expect(moonEngine(worth: 400_001).state.specialEventAvailable == .moon)
        #expect(moonEngine(worth: 900_000) { $0.quests.moon = 1 }.state.specialEventAvailable == nil)
        // Worth is list price + cash − debt: the same 400001 made of cash or offset by debt qualifies alike.
        #expect(moonEngine(worth: 400_001, cash: 450_000).state.specialEventAvailable == .moon)
    }

    @Test("QST-MOON-004 Moon: confirmation [500000]; cashToSpend < 500000 is insufficientFunds; debt alone does not block")
    func consentAndFunds() {
        var e = moonEngine(worth: 600_000, cash: 499_999)
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [500_000])))
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .insufficientFunds)
        var indebted = moonEngine(worth: 450_000, cash: 500_000)
        #expect(indebted.state.commander.debt > 0)
        #expect(indebted.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).events == [.specialEventCompleted(.moon)])
    }

    @Test("QST-MOON-005 QST-MOON-006 accepting sets moon 1, charges 500000, removes the event; worth is unchanged")
    func buy() {
        var e = moonEngine(worth: 700_000)
        let cash = e.state.commander.cash, worth = e.state.worth
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).events == [.specialEventCompleted(.moon)])
        #expect(e.state.quests.moon == 1 && e.state.commander.cash == cash - 500_000 && e.state.currentSystem.specialEvent == nil)
        #expect(e.state.worth == worth)
    }

    @Test("QST-MOON-007 the other Moon events stay but are hidden; the paper still lists every reachable Moon system")
    func otherMoons() throws {
        var e = moonEngine(worth: 700_000)
        let other = try #require(e.state.destinations.first { $0 != e.state.commander.currentSystem })
        e.state.galaxy.systems[other].specialEvent = .moon
        #expect(e.state.newspaper.headlines.contains(.moonForSale(system: other)))
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.galaxy.systems[other].specialEvent == .moon)
        #expect(e.state.newspaper.headlines.contains(.moonForSale(system: other)))
        QSTKit.dock(&e, at: other)
        #expect(e.state.specialEventAvailable == nil)
    }

    @Test("QST-MOON-008 MoonRetirement is shown iff moon == 1, a question [0]; declining changes nothing and keeps the offer")
    func retirementOffer() {
        for moon in 0...2 {
            #expect(QSTKit.shown(.moonRetirement) { $0.quests.moon = moon } == (moon == 1))
        }
        var e = QSTKit.engine(.moonRetirement) { $0.quests.moon = 1 }
        let before = e.state
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        #expect(e.state == before && e.state.specialEventAvailable == .moonRetirement)
    }

    @Test("QST-MOON-009 QST-MOON-010 retiring: moon 2, gameOver(.boughtMoon), event kept, no price; score on the final state")
    func retire() {
        var e = QSTKit.engine(.moonRetirement) { $0.quests.moon = 1; $0.commander.cash = 50_000 }
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        let score = e.state.score(for: .boughtMoon)
        #expect(r.events == [.specialEventCompleted(.moonRetirement), .gameEnded(.boughtMoon, score: score)])
        #expect(e.state.quests.moon == 2 && e.state.phase == .gameOver(.boughtMoon))
        #expect(e.state.commander.cash == 50_000 && e.state.currentSystem.specialEvent == .moonRetirement)
        #expect(e.state.worth == e.state.commander.ship.spec(e.ruleset).price + 50_000 + 500_000)   // the moon counts
        var noMoon = e.state
        noMoon.quests.moon = 0
        #expect(score > noMoon.score(for: .boughtMoon))
    }

    @Test("QST-MOON-011 after the ending every command is rejected with gameOver and the state no longer changes")
    func afterEnding() {
        var e = QSTKit.engine(.moonRetirement) { $0.quests.moon = 1 }
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        let final = e.state
        let commands: [Command] = [.warp, .jump, .specialEvent, .retire, .buyCargo(.water, quantity: 1), .buyFuel(credits: 10),
                                   .borrow(100), .selectTarget(3), .track(4), .readNewspaper, .encounter(.attack),
                                   .setOptions(GameOptions())]
        for c in commands {
            #expect(e.perform(c, acknowledging: Set(WarningID.allCases)).rejection == .gameOver, "\(c)")
        }
        #expect(e.state == final)
    }

    @Test("QST-MOON-015 funds: 499999 is insufficientFunds; exactly 500000 succeeds; reserved daily costs count")
    func funds() {
        var short = moonEngine(worth: 600_000, cash: 499_999)
        let before = short.state
        #expect(short.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .insufficientFunds)
        #expect(short.state == before)
        var exact = moonEngine(worth: 600_000, cash: 500_000)
        _ = exact.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(exact.state.commander.cash == 0 && exact.state.quests.moon == 1)
        var reserved = moonEngine(worth: 600_000, cash: 500_000) { $0.commander.debt = 10; $0.options.reserveMoney = true }
        #expect(reserved.state.cashToSpend == 499_999)                            // interest 1 is reserved
        #expect(reserved.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .insufficientFunds)
    }

    @Test("QST-MOON-016 full ending: buy, travel to Utopia, retire; the next warp is rejected with gameOver")
    func fullEnding() throws {
        var e = moonEngine(worth: 800_000)
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.quests.moon == 1)
        #expect(e.state.galaxy.systems[SystemID.utopia].specialEvent == .moonRetirement)
        _ = try #require(QSTKit.arrive(&e, at: SystemID.utopia))
        #expect(e.state.commander.currentSystem == SystemID.utopia && e.state.specialEventAvailable == .moonRetirement)
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.quests.moon == 2 && e.state.phase == .gameOver(.boughtMoon))
        #expect(r.events.last == .gameEnded(.boughtMoon, score: e.state.score(for: .boughtMoon)))
        #expect(e.perform(.warp).rejection == .gameOver)
    }

    @Test("QST-MOON-017 Utopia before buying offers nothing (noSpecialEvent)")
    func utopiaFirst() {
        var e = QSTKit.engine(nil) { $0.commander.cash = 900_000 }
        QSTKit.dock(&e, at: SystemID.utopia)
        #expect(e.state.currentSystem.specialEvent == .moonRetirement && e.state.specialEventAvailable == nil)
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .noSpecialEvent)
    }
}

// MARK: - One-offs

@Suite("Quest: one-off events (QST-ONEOFF {M4})")
struct QuestOneOffSpecTests {
    /// The first RNG offset at which the next `rand(10)` equals `item`.
    private static func canisters(_ item: Int, _ adjust: (inout GameState) -> Void) -> GameEngine? {
        var e = QSTKit.engine(.cargoForSale, adjust)
        for _ in 0..<500 {
            var peek = e.state.rng
            if peek.next(below: 10) == item { return e }
            _ = e.state.rng.next(below: 1_000)
        }
        return nil
    }

    @Test("QST-ONEOFF-001 CargoForSale: shown iff free bays ≥ 3 (antidote and reactor bays filled); 1000, funds checked")
    func cargoShown() {
        #expect(QSTKit.shown(.cargoForSale) { $0.commander.ship.cargo[0] = 12 })   // Gnat: 15 bays, 3 free
        #expect(!QSTKit.shown(.cargoForSale) { $0.commander.ship.cargo[0] = 13 })
        #expect(!QSTKit.shown(.cargoForSale) { $0.quests.japori = 1; $0.commander.ship.cargo[0] = 3 })
        #expect(!QSTKit.shown(.cargoForSale) { $0.quests.reactor = 3 })
        var e = QSTKit.engine(.cargoForSale) { $0.commander.cash = 999 }
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [1_000])))
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .insufficientFunds)
    }

    @Test("QST-ONEOFF-002 QST-ONEOFF-012 canisters: rand(10) = 5 loads 3 Firearms costing 1000 in total; 2 free bays hide it")
    func canistersLoad() throws {
        var e = try #require(Self.canisters(5) { $0.commander.cash = 1_000 })
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        let f = TradeItemType.firearms.rawValue
        #expect(r.events == [.sealedCanisters(.firearms), .specialEventCompleted(.cargoForSale)])
        #expect(e.state.commander.ship.cargo[f] == 3 && e.state.commander.priceCargo[f] == 1_000)
        #expect(e.state.commander.cash == 0 && e.state.currentSystem.specialEvent == nil)
        for item in [0, 8] {                                                      // any good, Narcotics included
            var any = try #require(Self.canisters(item) { _ in })
            _ = any.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
            #expect(any.state.commander.ship.cargo[item] == 3)
        }
        var full = QSTKit.engine(.cargoForSale) { $0.commander.ship.cargo[0] = 13 }
        #expect(full.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .noSpecialEvent)
    }

    @Test("QST-ONEOFF-003 canisters are ordinary cargo: prices untouched, sellable, and confiscated if illegal on arrest")
    func canistersOrdinary() throws {
        var e = try #require(Self.canisters(5) { setMarket(&$0) })
        let buy = e.state.buyPrices, sell = e.state.sellPrices
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.buyPrices == buy && e.state.sellPrices == sell)
        var sale = e
        let r = sale.perform(.sellCargo(.firearms, quantity: 3), acknowledging: Set(WarningID.allCases))
        #expect(r.rejection == nil && sale.state.commander.ship.cargo[TradeItemType.firearms.rawValue] == 0)
        _ = QSTKit.arrest(&e, destination: 9)
        #expect(e.state.commander.ship.cargo[TradeItemType.firearms.rawValue] == 0)
    }

    @Test("QST-ONEOFF-004 EraseRecord: shown iff record < −5; 5000, funds checked")
    func eraseShown() {
        #expect(QSTKit.shown(.eraseRecord) { $0.commander.policeRecordScore = -6 })
        #expect(!QSTKit.shown(.eraseRecord) { $0.commander.policeRecordScore = -5 })
        var e = QSTKit.engine(.eraseRecord) { $0.commander.policeRecordScore = -30; $0.commander.cash = 4_999 }
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [5_000])))
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .insufficientFunds)
    }

    @Test("QST-ONEOFF-005 QST-ONEOFF-013 erase: record 0, sell prices ×100/90 (100 → 111), buy unchanged, −5000")
    func erase() {
        var e = QSTKit.engine(.eraseRecord) { s in s.commander.policeRecordScore = -30; setMarket(&s, buy: 130, sell: 100) }
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(r.events == [.specialEventCompleted(.eraseRecord)])
        #expect(e.state.commander.policeRecordScore == 0 && e.state.sellPrices == Array(repeating: 111, count: 10))
        #expect(e.state.buyPrices == Array(repeating: 130, count: 10))
        #expect(e.state.commander.cash == 5_000 && e.state.currentSystem.specialEvent == nil)
        var lawful = QSTKit.engine(.eraseRecord) { $0.commander.policeRecordScore = -5 }
        #expect(lawful.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .noSpecialEvent)
    }

    @Test("QST-ONEOFF-007 Skill: always shown; 3000; cashToSpend 2999 is insufficientFunds")
    func skillShown() {
        #expect(QSTKit.shown(.skill) { $0.commander.policeRecordScore = -80 })
        var e = QSTKit.engine(.skill) { $0.commander.cash = 2_999 }
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [3_000])))
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .insufficientFunds)
    }

    @Test("QST-ONEOFF-008 QST-ONEOFF-014 skill: one rand(count) among skills < 9 (4/9/9/9 → Pilot 5); Trader change reprices")
    func skillIncrease() {
        var e = QSTKit.engine(.skill) { $0.mercenaries[CrewID.commander].skills = [4, 9, 9, 9] }
        var expected = e.state.rng
        _ = expected.next(below: 1)
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(r.events == [.specialEventCompleted(.skill)])                     // the app shows the skill-increase alert
        #expect(e.state.mercenaries[CrewID.commander].skills == [5, 9, 9, 9] && e.state.rng == expected)
        #expect(e.state.commander.cash == 7_000 && e.state.currentSystem.specialEvent == nil)
        // Only Trader eligible: it rises and buy prices are recalculated with the new Trader skill.
        var trader = QSTKit.engine(.skill) { s in s.mercenaries[CrewID.commander].skills = [9, 9, 4, 9]; setMarket(&s) }
        let traderBefore = trader.state.skill(.trader)
        _ = trader.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        var repriced = trader.state
        repriced.recalculateBuyPricesHere()
        #expect(trader.state.skill(.trader) == traderBefore + 1)
        #expect(trader.state.buyPrices == repriced.buyPrices && trader.state.buyPrices != Array(repeating: 100, count: 10))
    }

    @Test("QST-ONEOFF-009 QST-ONEOFF-014 all skills at 9: no draw, no change, but 3000 charged and the event removed")
    func skillMaxed() {
        var e = QSTKit.engine(.skill) { $0.mercenaries[CrewID.commander].skills = [9, 9, 9, 9] }
        let rng = e.state.rng
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.rng == rng && e.state.mercenaries[CrewID.commander].skills == [9, 9, 9, 9])
        #expect(e.state.commander.cash == 7_000 && e.state.currentSystem.specialEvent == nil)
    }

    @Test("QST-ONEOFF-011 Lottery: always shown, message-only, +1000 and removed; claimable on a later visit")
    func lottery() {
        var e = QSTKit.engine(.lottery) { $0.commander.policeRecordScore = -90 }
        let start = e.state.commander.currentSystem
        let other = QSTKit.nearest(to: start, in: e.state)
        QSTKit.dock(&e, at: other)
        QSTKit.dock(&e, at: start)                                                // still there on return
        var expected = e.state
        expected.commander.cash += 1_000
        expected.galaxy.systems[start].specialEvent = nil
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.lottery)])
        #expect(e.state == expected)
    }

    @Test("QST-ONEOFF-015 a new Beginner game offers the Lottery at the start; a new Normal game has none")
    func lotteryNewGame() {
        var beginner = makeEngine(difficulty: .beginner)
        #expect(beginner.state.specialEventAvailable == .lottery)
        let cash = beginner.state.commander.cash
        #expect(beginner.perform(.specialEvent).events == [.specialEventCompleted(.lottery)])
        #expect(beginner.state.commander.cash == cash + 1_000 && beginner.state.currentSystem.specialEvent == nil)
        let normal = makeEngine(difficulty: .normal)
        #expect(!normal.state.galaxy.systems.contains { $0.specialEvent == .lottery })
    }
}
