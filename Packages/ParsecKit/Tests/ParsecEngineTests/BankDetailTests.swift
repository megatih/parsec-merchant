// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

@Suite("Bank details (BNK)")
struct BankDetailTests {
    @Test("BNK-001 BNK-002 BNK-008 starting money and constants; starting worth 11000")
    func start() {
        let s = makeEngine().state
        #expect(s.commander.cash == 1_000 && s.commander.debt == 0 && !s.commander.insurance && s.commander.noClaim == 0)
        #expect(s.worth == 11_000)
        #expect(QuestStatus.moonCost == 500_000)
    }

    @Test("BNK-004 BNK-010 worth uses the ship list price and is recomputed on every read")
    func worth() {
        var s = makeEngine().state
        s.commander.ship.hull = 10
        #expect(s.worth == 10_000 + 1_000)
        s.commander.cash = 5_000
        s.commander.debt = 2_000
        #expect(s.worth == 10_000 + 3_000)
        s.quests.moon = QuestStatus.Moon.bought
        #expect(s.worth == 13_000 + 500_000)
    }

    @Test("BNK-007 base worth formula (shared with SHP-027)")
    func baseWorth() {
        let s = makeEngine().state
        #expect(s.baseWorth(of: s.commander.ship, forInsurance: true) == 10_000 * 3 / 4 + 2_000 * 3 / 4)
    }

    @Test("BNK-012 BNK-013 BNK-014 max loan examples; Palm and C# forms agree")
    func maxLoanExamples() {
        func loan(_ worth: Int, record: Int = 0) -> Int { record >= 0 ? min(25_000, max(1_000, worth / 5_000 * 500)) : 500 }
        #expect(loan(11_000) == 1_000 && loan(123_456) == 12_000 && loan(4_999) == 1_000 && loan(-5) == 1_000)
        #expect(loan(260_000) == 25_000 && loan(1_000_000, record: -1) == 500)
        for w in stride(from: -20_000, to: 400_000, by: 37) { #expect((w / 10) / 500 * 500 == w / 5_000 * 500) }
        var e = makeEngine()
        let before = e.state.maxLoan
        _ = e.perform(.borrow(500))
        #expect(e.state.maxLoan == before)
    }

    @Test("BNK-003 BNK-020 BNK-022 BNK-023 interest: max(1, debt/10); shortfall goes to debt (unbounded)")
    func interest() {
        var s = makeEngine().state
        s.commander.debt = 5; s.commander.cash = 100
        s.payInterest()
        #expect(s.commander.cash == 99)
        s.commander.debt = 1_234; s.commander.cash = 50
        s.payInterest()
        #expect(s.commander.debt == 1_307 && s.commander.cash == 0)
        s.commander.debt = 1_234; s.commander.cash = 123
        s.payInterest()
        #expect(s.commander.debt == 1_234 && s.commander.cash == 0)
        s.commander.debt = 99_999; s.commander.cash = 0
        s.payInterest()
        #expect(s.commander.debt > 100_000)
        for d in 0...200_000 where Int(Double(d) * 0.1) != d / 10 { Issue.record("mismatch at \(d)") }
        for d in [Int(Int32.max) - 1, 999_999_999, 1_000_000_007] { #expect(Int(Double(d) * 0.1) == d / 10) }
    }

    @Test("BNK-029 BNK-031 BNK-032 debt blocks market buying (>100000), equipment (>0) and positive-price ships")
    func debtBlocks() {
        var e = makeEngine { s in setMarket(&s); s.commander.debt = 100_001; s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech }
        #expect(e.perform(.buyCargo(.water, quantity: 1)).rejection == .debtTooLargeToTrade)
        e.state.commander.debt = 1
        #expect(e.perform(.buyCargo(.water, quantity: 1)).rejection == nil)
        #expect(e.perform(.buyGadget(.navigatingSystem), acknowledging: [.buyEquipment]).rejection == .inDebt)
        #expect(e.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip]).rejection == .inDebt)
        // A trade with net price ≤ 0 is allowed in debt (selling the Gnat for a Flea).
        e.state.commander.cash = 0
        #expect(e.perform(.buyShip(.flea, transfers: []), acknowledging: [.buyShip]).rejection == nil)
    }

    @Test("BNK-040 BNK-042 premium examples (C# double arithmetic)")
    func premium() {
        func premium(_ w: Int, _ nc: Int) -> Int { max(1, Int(Double(w) * 0.0025 * Double(100 - nc) / 100.0)) }
        #expect(premium(10_000, 0) == 25 && premium(7_999, 1) == 19 && premium(-10, 0) == 1)
        var s = makeEngine().state
        s.commander.insurance = true
        #expect(s.insuranceCosts == premium(9_000, 0))
        s.commander.noClaim = 90
        #expect(s.insuranceCosts == premium(9_000, 90))
    }

    @Test("BNK-043 no-claim is stored clamped to 0…90")
    func noClaimClamp() {
        var s = makeEngine().state
        s.setNoClaim(120)
        #expect(s.commander.noClaim == 90)
        s.setNoClaim(-3)
        #expect(s.commander.noClaim == 0)
    }

    @Test("BNK-049 ship trade keeps insurance only if the pod is transferred")
    func insuranceOnTrade() {
        var keep = makeEngine { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 30_000; s.commander.ship.escapePod = true; s.commander.insurance = true; s.commander.noClaim = 10
        }
        _ = keep.perform(.buyShip(.firefly, transfers: [.escapePod]), acknowledging: [.buyShip])
        #expect(keep.state.commander.insurance && keep.state.commander.noClaim == 10)
        var drop = makeEngine { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 30_000; s.commander.ship.escapePod = true; s.commander.insurance = true; s.commander.noClaim = 10
        }
        _ = drop.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip])
        #expect(!drop.state.commander.insurance && drop.state.commander.noClaim == 0)
    }

    @Test("BNK-051 BNK-052 BNK-061 daily costs incl. wormhole tax 25 × C# fuel cost")
    func dailyCosts() {
        var s = makeEngine().state
        s.commander.debt = 3_000
        let w = s.galaxy.wormholes
        s.commander.currentSystem = w[0]
        let c = s.dailyCosts(to: w[1])
        #expect(c.interest == 300 && c.wormholeTax == 25 * 1 && c.mercenaries == 0 && c.insurance == 0 && c.total == 325)
        #expect(s.dailyCosts(to: w[2]).wormholeTax == 0)
    }

    @Test("BNK-054 BNK-056 cash to spend with Reserve Money; fuel/repairs/repay use cash")
    func reserveMoney() {
        var e = makeEngine { s in s.options.reserveMoney = true; s.commander.debt = 20_000; s.commander.cash = 1_000; s.commander.ship.fuel = 1 }
        #expect(e.state.cashToSpend == 1_000 - 2_000)
        #expect(e.perform(.buyFuel(credits: 5)).rejection == nil)
        #expect(e.perform(.repay(100)).rejection == nil)
        #expect(GameOptions().reserveMoney == false)
    }

    @Test("BNK-060 BNK-063 bank preview and error vocabulary")
    func preview() {
        var s = makeEngine().state
        s.commander.debt = 300
        let p = s.bankPreview
        #expect(p.maxLoan == 1_000 && p.availableToBorrow == 700 && p.maxRepay == 300 && !p.insured && !p.canBuyInsurance)
        let errors: [CommandError] = [.debtTooLargeForLoan, .noDebt, .invalidAmount, .exceedsAvailableLoan, .exceedsRepayable,
                                      .insuranceRequiresEscapePod, .insuranceAlreadyActive, .insuranceNotActive]
        #expect(Set(errors.map { "\($0)" }).count == 8)
    }
}
