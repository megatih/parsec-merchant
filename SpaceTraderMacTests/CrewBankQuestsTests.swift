// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
@testable import ParsecMerchant

@MainActor
@Suite("Crew, Bank, Quests and Find")
struct CrewBankQuestsTests {
    private func engine(_ ruleset: RulesetID = .modern, seed: UInt64 = 1, _ change: (inout GameState) -> Void = { _ in }) -> GameEngine {
        var s = GameState(config: NewGameConfig(commanderName: "Tester", ruleset: ruleset, seed: seed))
        change(&s)
        return GameEngine(state: s)
    }

    /// A paid mercenary (not special) placed at the current system.
    private func placeMercenary(_ s: inout GameState) -> Int {
        let id = 1
        s.mercenaries[id].systemID = s.commander.currentSystem
        return id
    }

    private func localized(_ r: LocalizedStringResource) -> String { String(localized: r) }

    // MARK: Crew

    @Test("UI-SHELL-079 crew quarters list the commander, mercenaries, passengers and vacant seats with identifiers")
    func seats() {
        let e = engine { s in
            s.commander.ship.crew = [CrewID.commander, 2, CrewID.jarek, nil]
        }
        let m = CrewModel.make(engine: e)
        #expect(m.seats.count == 4)
        #expect(m.seats[0].occupant == .commander(name: "Tester", skills: e.state.mercenaries[0].skills))
        guard case let .mercenary(id, name, skills, wage) = m.seats[1].occupant else {
            Issue.record("seat 1 is not a mercenary")
            return
        }
        #expect(id == 2 && name == Names.crew(2, in: e.state) && skills == e.state.mercenaries[2].skills)
        #expect(wage == e.state.dailyRate(of: 2) && wage > 0)
        #expect(m.seats[2].occupant == .passenger(crewID: CrewID.jarek, name: Names.crew(CrewID.jarek, in: e.state)))
        #expect(m.seats[3].occupant == .vacant && !m.seats[3].canBeFired && !m.seats[0].canBeFired)
        #expect(m.seats.map(\.index) == [0, 1, 2, 3])
        #expect(AXID.all.contains(AXID.Crew.seat(3)))
    }

    @Test("UI-SHELL-079 Palm passengers outside the crew array still appear as passenger seats")
    func palmPassengerSeats() {
        let e = engine(.palm122) { s in
            s.commander.ship.crew = [CrewID.commander, nil, nil]
            s.quests.wild = QuestStatus.Wild.started
        }
        #expect(e.state.passengersOutsideCrew == 1)
        let m = CrewModel.make(engine: e)
        #expect(m.seats.count == 3)
        #expect(m.seats[1].occupant == .vacant)
        #expect(m.seats[2].occupant == .passenger(crewID: CrewID.wild, name: Names.crew(CrewID.wild, in: e.state)))
        #expect(m.seats[2].fireBlocker == .cannotFireSpecialPassenger)
        #expect(m.freeQuarters == 1)
    }

    @Test("UI-SHELL-080 hire cards come from crewPreview.forHire; Hire is blocked without a free quarter")
    func hireCards() throws {
        var mercID = 0
        let full = engine { s in
            mercID = placeMercenary(&s)
            s.commander.ship.crew = [CrewID.commander]
        }
        let blocked = CrewModel.make(engine: full)
        let card = try #require(blocked.forHire.first { $0.crewID == mercID })
        #expect(blocked.forHire.map(\.crewID) == full.state.crewPreview.forHire.map(\.id))
        #expect(card.blocker == .noFreeQuarters && card.blocker == full.rejection(ifPerformed: .hire(crewID: mercID)))
        #expect(card.skills == full.state.mercenaries[mercID].skills && card.dailyWage == full.state.dailyRate(of: mercID))
        #expect(card.name == Names.crew(mercID, in: full.state))
        #expect(localized(ReasonText.text(for: .noFreeQuarters)) == "No free quarters.")

        let session = try TestSessions.playing()
        try TestSessions.edit(session) { s in
            mercID = placeMercenary(&s)
            s.commander.ship.crew = [CrewID.commander, nil]
        }
        let open = CrewModel.make(engine: try #require(session.engine))
        #expect(open.forHire.first { $0.crewID == mercID }?.blocker == nil)
        session.send(.hire(crewID: mercID))
        #expect(session.state?.commander.ship.crew == [CrewID.commander, mercID])
        #expect(AXID.all.contains(AXID.Crew.hire(mercID)))
    }

    @Test("UI-SHELL-080 Fire asks for confirmation (ALR-025); special passengers can't be fired")
    func fire() throws {
        let session = try TestSessions.playing()
        try TestSessions.edit(session) { s in s.commander.ship.crew = [CrewID.commander, 2, CrewID.princess] }
        let m = CrewModel.make(engine: try #require(session.engine))
        #expect(m.seats[1].fireBlocker == nil && m.seats[1].canBeFired)
        #expect(m.seats[2].fireBlocker == .cannotFireSpecialPassenger)
        #expect(localized(ReasonText.text(for: .cannotFireSpecialPassenger)) == "Passengers can't be fired.")
        session.send(.fire(crewID: 2))
        guard case let .confirmation(pending) = session.presentation else {
            Issue.record("no confirmation presented")
            return
        }
        #expect(pending.confirmation.warning == .fireMercenary)
        session.confirm(pending)
        #expect(session.state?.commander.ship.hasCrew(2) == false)
        #expect(AXID.all.contains(AXID.Crew.fire(2)))
    }

    @Test("UI-SHELL-081 the effective-skills panel shows each skill's parts, free quarters and daily wages")
    func effectiveSkills() {
        let e = engine { s in s.commander.ship.crew = [CrewID.commander, 2, nil] }
        let m = CrewModel.make(engine: e)
        let p = e.state.crewPreview
        #expect(m.skills.map(\.skill) == SkillType.allCases)
        #expect(m.skills.map(\.effective) == p.effectiveSkills && m.skills.map(\.crewMaximum) == p.crewMaximum)
        #expect(m.skills.map(\.gadgetBonus) == p.gadgetBonus)
        #expect(m.skills.allSatisfy { $0.difficultyAdjustment == p.difficultyAdjustment })
        #expect(m.skills.filter { $0.skill != .trader }.allSatisfy { $0.hagglingBonus == 0 })
        #expect(m.freeQuarters == 1 && m.dailyWages == p.dailyMercenaryCost && m.dailyWages == e.state.dailyRate(of: 2))
        #expect(m.standing.policeRecord == e.state.policeRecord && m.standing.reputation == e.state.reputation)
        #expect(AXID.all.contains(AXID.Crew.effectiveSkills))
    }

    // MARK: Bank

    @Test("UI-SHELL-082 loan: maximum with its reason, bounded borrow and repay, Repay All and the interest line")
    func loan() throws {
        let session = try TestSessions.playing()
        var m = BankModel.make(engine: try #require(session.engine))
        #expect(m.loanReason == .cleanRecord(m.preview.maxLoan))
        #expect(localized(m.loanReason.text) == "Clean record: up to \(m.preview.maxLoan.formatted())")
        #expect(m.repayBlocker == .noDebt && m.borrowBlocker == nil && m.repayAllCommand == nil)
        #expect(m.borrowCommand(amount: 0) == nil && m.borrowCommand(amount: m.preview.availableToBorrow + 1) == nil)
        #expect(BankModel.clamp(999_999, to: m.preview.availableToBorrow) == m.preview.availableToBorrow)
        #expect(BankModel.clamp(-5, to: 10) == 0)
        session.send(try #require(m.borrowCommand(amount: 500)))
        m = BankModel.make(engine: try #require(session.engine))
        #expect(m.preview.debt == 500 && m.interestPerWarp == 50 && m.repayBlocker == nil)
        #expect(localized("Each warp costs 10% interest: \(m.interestPerWarp.formatted()) cr.") == "Each warp costs 10% interest: 50 cr.")
        #expect(m.repayCommand(amount: m.preview.maxRepay + 1) == nil)
        #expect(m.repayAllCommand == .repay(m.preview.repayAllAmount))
        session.send(try #require(m.repayAllCommand))
        #expect(session.state?.commander.debt == 0)

        let criminal = BankModel.make(engine: engine { $0.commander.policeRecordScore = -1 })
        #expect(criminal.loanReason == .criminalRecord(500))
        #expect(localized(criminal.loanReason.text) == "Criminal record: up to 500")
        let maxed = BankModel.make(engine: engine { s in
            s.commander.policeRecordScore = -1
            s.commander.debt = 500
        })
        #expect(maxed.borrowBlocker == .debtTooLargeForLoan && maxed.borrowCommand(amount: 1) == nil)
        for id in [AXID.Bank.borrowAmount, AXID.Bank.borrowSubmit, AXID.Bank.repayAmount, AXID.Bank.repaySubmit, AXID.Bank.repayAll] {
            #expect(AXID.all.contains(id))
        }
    }

    @Test("UI-SHELL-083 insurance: ship value, no-claim meter, premium, Buy needs an escape pod, Stop confirms (ALR-107)")
    func insurance() throws {
        let session = try TestSessions.playing()
        var m = BankModel.make(engine: try #require(session.engine))
        #expect(m.shipValue == session.state?.shipWorth(forInsurance: true))
        #expect(!m.preview.canBuyInsurance && m.buyInsuranceBlocker == .insuranceRequiresEscapePod && !m.hasEscapePod)
        #expect(localized(ReasonText.text(for: .insuranceRequiresEscapePod)) == "Requires an escape pod.")
        #expect(m.premium == m.preview.premiumQuote)
        try TestSessions.edit(session) { $0.commander.ship.escapePod = true }
        m = BankModel.make(engine: try #require(session.engine))
        #expect(m.preview.canBuyInsurance && m.buyInsuranceBlocker == nil)
        session.send(.buyInsurance)
        m = BankModel.make(engine: try #require(session.engine))
        #expect(m.preview.insured && m.premium == m.preview.currentPremium && m.stopInsuranceBlocker == nil)
        session.send(.stopInsurance)
        guard case let .confirmation(pending) = session.presentation else {
            Issue.record("no confirmation presented")
            return
        }
        #expect(pending.confirmation.warning == .stopInsurance)
        session.cancel()
        #expect(session.state?.commander.insurance == true)

        let maxed = BankModel.make(engine: engine { s in
            s.commander.ship.escapePod = true
            s.commander.insurance = true
            s.commander.noClaim = 90
        })
        #expect(maxed.preview.noClaimAtMaximum && maxed.noClaimFraction == 1)
        #expect(AXID.all.contains(AXID.Bank.insuranceBuy) && AXID.all.contains(AXID.Bank.insuranceStop))
    }

    @Test("UI-SHELL-084 the debt banner shows from 75,000 debt, without an alert")
    func debtBanner() {
        #expect(!BankModel.make(engine: engine { $0.commander.debt = 74_999 }).debtWarning)
        #expect(BankModel.make(engine: engine { $0.commander.debt = 75_000 }).debtWarning)
        #expect(AXID.all.contains(AXID.Bank.debtWarning))
    }

    // MARK: Find System

    @Test("UI-SHELL-085 Find suggests case-insensitive substring matches in galaxy order and selects the first match")
    func findSystem() throws {
        let session = try TestSessions.playing()
        let state = try #require(session.state)
        let names = state.ruleset.tables.systemNames
        let expected = names.indices.filter { names[$0].lowercased().contains("an") }
        #expect(FindSystemModel.matches("AN", in: state) == expected && !expected.isEmpty)
        #expect(FindSystemModel.matches("", in: state).isEmpty)
        let first = try #require(expected.first)
        #expect(FindSystemModel.resolve("aN", track: false, state: state) == .select(system: first, track: false))
        #expect(FindSystemModel.resolve("qqqqzz", track: true, state: state) == .noMatch)
        #expect(FindSystemModel.resolve("Cheetah", track: false, state: state) == .cheat(.enable))
        #expect(FindSystemModel.commands(for: .select(system: first, track: true)) == [.selectTarget(first), .track(first)])

        session.present(.sheet(.findSystem))
        #expect(session.performFind(.noMatch) == false && session.presentation == .sheet(.findSystem))
        let target = names.firstIndex(of: "Zalkon") ?? first
        session.performFind(FindSystemModel.resolve("zalkon", track: true, state: state))
        #expect(session.presentation == nil)
        #expect(session.state?.warpSystem == target && session.state?.trackedSystem == target)

        let palm = engine(.palm122).state
        #expect(FindSystemModel.resolve("", track: false, state: palm) == FindSystemModel.Outcome.none)
        #expect(FindSystemModel.resolve("Timewarp", track: false, state: palm) == .timewarp)
        for id in [AXID.FindSystem.field, AXID.FindSystem.result(first), AXID.FindSystem.track, AXID.FindSystem.select] {
            #expect(id.range(of: AXID.pattern, options: .regularExpression) != nil)
        }
    }

    @Test("CHEAT-046 Palm Timewarp from Find warns or confirms before Open Saved Game and is refused in Ironman")
    func timewarp() throws {
        let session = try TestSessions.make()
        var config = session.quickStartConfig()
        config.ruleset = .palm122
        #expect(session.startNewGame(config) == nil)
        let state = try #require(session.state)
        #expect(FindSystemModel.resolve("Timewarp", track: false, state: state) == .timewarp)
        session.present(.sheet(.findSystem))
        #expect(session.performFind(.timewarp))
        #expect(session.presentation == .appConfirmation(.timewarpLoad(reloaded: false)))
        session.confirm(.timewarpLoad(reloaded: false))
        #expect(session.presentation == .sheet(.openSavedGame))
        #expect(session.state?.cheatsUsed == false)
        session.dismissPresentation()

        try TestSessions.edit(session) { $0.reloadCount = 1 }
        session.present(.sheet(.findSystem))
        session.performFind(.timewarp)
        #expect(session.presentation == .appConfirmation(.timewarpLoad(reloaded: true)))
        session.cancel()

        try TestSessions.edit(session) { $0.ironman = true }
        session.present(.sheet(.findSystem))
        #expect(session.performFind(.timewarp) == false)
        #expect(session.presentation == .sheet(.findSystem))
    }

    // MARK: Quests

    @Test("UI-SHELL-086 quest cards: title, chain steps, deadline gauge, system buttons that select the target and keep the page")
    func questCards() throws {
        let session = try TestSessions.playing()
        try TestSessions.edit(session) { s in
            s.quests.gemulon = 3
            s.quests.dragonfly = QuestStatus.Dragonfly.flyMelina
        }
        let state = try #require(session.state)
        let m = QuestsModel.make(state: state)
        #expect(m.cards.map(\.entry) == state.questLog)
        let gemulon = try #require(m.cards.first { $0.entry.kind == .gemulonInformDays(4) })
        #expect(gemulon.entry.daysLeft == 4 && gemulon.deadlineSpan == 6 && gemulon.steps == nil)
        #expect(QuestText.string(for: gemulon.entry.kind, state: state) == "Inform Gemulon about alien invasion within 4 days.")
        let dragonfly = try #require(m.cards.first { $0.entry.kind == .dragonflyMelina })
        #expect(dragonfly.steps?.map(\.system) == QuestsModel.dragonflyRoute)
        #expect(dragonfly.steps?.map(\.done) == [true, false, false, false])
        #expect(QuestsModel.steps(for: .princessReturning(crewID: CrewID.princess))?.map(\.done) == [true, true, true, false])
        #expect(QuestsModel.deadlineSpan(QuestLogEntry(kind: .experimentInformTomorrow, systems: [], daysLeft: 1)) == 10)
        #expect(QuestsModel.deadlineSpan(QuestLogEntry(kind: .reactor, systems: [], daysLeft: 19)) == 19)

        let system = try #require(dragonfly.entry.systems.first)
        session.selectedSection = .quests
        session.selectQuestSystem(system)
        #expect(session.state?.warpSystem == system && session.selectedSection == .quests, "UI-NAV-006: targeting keeps the page")
        #expect(AXID.Quests.system(entry: dragonfly.index, system: system)
            .range(of: AXID.pattern, options: .regularExpression) != nil)

        let empty = QuestsModel.make(state: engine().state)
        #expect(empty.cards.isEmpty && localized(QuestText.none) == "There are no open quests.")
    }

    @Test("UI-SHELL-087 the Completed group lists closed chains with Completed or Failed")
    func completed() {
        var q = QuestState()
        #expect(QuestsModel.finished(q).isEmpty)
        q.dragonfly = QuestStatus.Dragonfly.destroyed
        q.gemulon = QuestStatus.Gemulon.tooLate
        q.experiment = QuestStatus.Experiment.performed
        q.japori = QuestStatus.Japori.done
        q.spaceMonster = QuestStatus.SpaceMonster.destroyed
        let f = QuestsModel.finished(q)
        #expect(f.map(\.chain) == [.gemulon, .experiment, .japori])
        #expect(f.map(\.failed) == [true, true, false])
        q.dragonfly = QuestStatus.Dragonfly.done
        q.experiment = QuestStatus.Experiment.cancelled
        q.gemulon = QuestStatus.Gemulon.done
        q.scarab = QuestStatus.Scarab.done
        let g = QuestsModel.finished(q)
        #expect(g.map(\.chain) == [.gemulon, .experiment, .japori, .dragonfly, .scarab] && g.allSatisfy { !$0.failed })
        #expect(localized(g[0].outcome) == "Completed" && localized(f[0].outcome) == "Failed")
        #expect(AXID.all.contains(AXID.Quests.completed))
    }

    @Test("UI-SHELL-123 every QuestLogKind maps to its Strings.cs text with ^1 filled in")
    func questTexts() {
        let state = engine().state
        let princess = Names.crew(CrewID.princess, in: state)
        let sys = { (i: Int) in Names.system(i, in: state) }
        // Strings.cs:162-196 (QuestJarekImpatient, QuestPrincessReturningImpatient and QuestWildImpatient append a line).
        let fixtures: [(QuestLogKind, String)] = [
            (.artifact, "Deliver the alien artifact to Professor Berger at some hi-tech system."),
            (.dragonflyBaratas, "Follow the Dragonfly to Baratas."),
            (.dragonflyMelina, "Follow the Dragonfly to Melina."),
            (.dragonflyRegulas, "Follow the Dragonfly to Regulas."),
            (.dragonflyShield, "Get your lightning shield at Zalkon."),
            (.dragonflyZalkon, "Follow the Dragonfly to Zalkon."),
            (.experimentInformDays(5), "Stop Dr. Fehler's experiment at Daled within 5 days."),
            (.experimentInformTomorrow, "Stop Dr. Fehler's experiment at Daled by tomorrow."),
            (.gemulonFuel, "Get your fuel compactor at Gemulon."),
            (.gemulonInformDays(2), "Inform Gemulon about alien invasion within 2 days."),
            (.gemulonInformTomorrow, "Inform Gemulon about alien invasion by tomorrow."),
            (.jarek, "Take ambassador Jarek to Devidia."),
            (.jarekImpatient, "Take ambassador Jarek to Devidia.\n"
                + "Jarek is wondering why the journey is taking so long, and is no longer of much help in negotiating trades."),
            (.japoriDeliver, "Deliver antidote to Japori."),
            (.moon, "Claim your moon at Utopia."),
            (.princessCentauri, "Follow the Scorpion to Centauri."),
            (.princessInthara, "Follow the Scorpion to Inthara."),
            (.princessQonos, "Follow the Scorpion to Qonos."),
            (.princessQuantum, "Get your Quantum Disruptor at Galvon."),
            (.princessReturn(crewID: CrewID.princess), "Transport \(princess) from Qonos to Galvon."),
            (.princessReturning(crewID: CrewID.princess), "Return \(princess) to Galvon."),
            (.princessReturningImpatient(crewID: CrewID.princess),
             "Return \(princess) to Galvon.\nShe is becoming anxious to arrive at home, and is no longer of any help in engineering functions."),
            (.reactor, "Deliver the unstable reactor to Nix for Henry Morgan."),
            (.reactorFuel, "Deliver the unstable reactor to Nix before it consumes all its fuel."),
            (.reactorLaser, "Get your special laser at Nix."),
            (.scarabFind, "Find and destroy the Scarab (which is hiding at the exit to a wormhole)."),
            (.scarabHull(system: 5), "Get your hull upgraded at \(sys(5))."),
            (.scarabNotify(system: 7), "Notify the authorities at \(sys(7)) that the Scarab has been destroyed."),
            (.sculpture, "Deliver the stolen sculpture to Endor."),
            (.sculptureHiddenBays, "Have hidden compartments installed at Endor."),
            (.spaceMonsterKill, "Kill the space monster at Acamar."),
            (.tribbles, "Get rid of those pesky tribbles."),
            (.wild, "Smuggle Jonathan Wild to Kravat."),
            (.wildImpatient, "Smuggle Jonathan Wild to Kravat.\nWild is getting impatient, and will no longer aid your crew along the way."),
        ]
        #expect(fixtures.count == 34)
        for (kind, text) in fixtures {
            #expect(QuestText.string(for: kind, state: state) == text, "\(kind)")
        }
    }
}
