// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecPersistence
import Testing
@testable import ParsecMerchant

@MainActor
@Suite("GameSession")
struct GameSessionTests {
    @Test("UI-SHELL-001 the session owns engine, ids, feed, presentation, section and the services")
    func ownership() throws {
        let s = try TestSessions.make()
        #expect(s.engine == nil && s.gameID == nil && s.currentSlotID == nil && s.feed.isEmpty && s.presentation == nil)
        #expect(s.selectedSection == .bridge && s.marketSelection == nil && s.lastManualSaveDays == 0)
        #expect(s.slotStore.root == s.highScoreStore.root)
        #expect(s.flavor.isTemplateOnly)
    }

    @Test("UI-SHELL-002 mode is derived: welcome → playing → gameOver(retired) → welcome")
    func modeTransitions() throws {
        let s = try TestSessions.make()
        #expect(s.mode == .welcome)
        s.requestQuickStart()
        #expect(s.mode == .playing)
        s.send(.retire)
        guard case let .sheet(.retire(pending)) = s.presentation else {
            Issue.record("retire should present the retire sheet")
            return
        }
        s.confirm(pending)
        #expect(s.mode == .gameOver(.retired))
        s.requestCloseGame()
        #expect(s.mode == .welcome)
        #expect(SessionMode.derive(from: nil) == .welcome)
    }

    @Test("UI-SHELL-003 send: a rejection is stored and presents nothing; events reach the feed")
    func sendBranches() throws {
        let s = try TestSessions.playing()
        let feedBefore = s.feed.count
        s.send(.buyCargo(.water, quantity: 0))
        #expect(s.lastRejection == .invalidQuantity)
        #expect(s.presentation == nil)
        #expect(s.feed.count == feedBefore)
        let serial = s.rejectionSerial
        s.send(.buyCargo(.water, quantity: 0))
        #expect(s.rejectionSerial == serial + 1)
        // An accepted command clears the rejection and appends its events.
        let item = try #require(TradeItemType.allCases.first { (s.state?.buyPrices[$0.rawValue] ?? 0) > 0
            && (s.state?.currentSystem.tradeItems[$0.rawValue] ?? 0) > 0 })
        s.send(.buyCargo(item, quantity: 1))
        #expect(s.lastRejection == nil)
        guard case .boughtCargo? = s.feed.last?.event else {
            Issue.record("expected a boughtCargo feed item")
            return
        }
        // A confirmation is presented (retire → sheet); another decision is routed (newspaper → decision sheet).
        s.send(.retire)
        #expect(s.isModal)
        s.cancel()
        #expect(!s.isModal)
        s.send(.readNewspaper)
        guard case let .confirmation(pending) = s.presentation else {
            Issue.record("the newspaper asks to pay first")
            return
        }
        #expect(pending.confirmation.warning == .buyNewspaper)
        s.confirm(pending)
        guard case .sheet(.newspaper) = s.presentation else {
            Issue.record("the paper itself is a decision sheet")
            return
        }
    }

    @Test("UI-SHELL-004 a chain of two confirmations resends with both warnings; cancelling changes nothing")
    func confirmationChain() throws {
        let s = try TestSessions.playing()
        try TestSessions.edit(s) { st in
            st.quests.canSuperWarp = true
            st.commander.ship.crew.append(CrewID.wild)
            st.quests.wild = QuestStatus.Wild.started
            st.warpSystem = (st.commander.currentSystem + 1) % st.galaxy.systems.count
        }
        let before = try #require(s.state)
        s.send(.jump)
        guard case let .confirmation(first) = s.presentation else {
            Issue.record("expected the singularity confirmation")
            return
        }
        #expect(first.confirmation.warning == .useSingularity && first.acknowledged.isEmpty)
        // Cancel: dropped, nothing changes.
        s.cancel()
        #expect(s.state == before && s.presentation == nil)
        s.send(.jump)
        guard case let .confirmation(again) = s.presentation else { return }
        s.confirm(again)
        guard case let .confirmation(second) = s.presentation else {
            Issue.record("expected the Wild confirmation")
            return
        }
        #expect(second.confirmation.warning == .wildLeavesWithoutLaser)
        #expect(second.acknowledged == [.useSingularity])
        #expect(second.acknowledgingOnConfirm == [.useSingularity, .wildLeavesWithoutLaser])
        s.confirm(second)
        #expect(s.state?.quests.canSuperWarp == false)
        #expect(s.feed.contains { $0.event == .wildLeftShip })
    }

    @Test("UI-SHELL-005 one presentation at a time; the rest wait in FIFO order")
    func presentationQueue() throws {
        let s = try TestSessions.make()
        s.present(.systemAlert(.nothingToContinue))
        s.present(.appConfirmation(.closeGame))
        s.present(.sheet(.findSystem))
        #expect(s.presentation == .systemAlert(.nothingToContinue))
        #expect(s.pendingPresentations == [.appConfirmation(.closeGame), .sheet(.findSystem)])
        s.dismissPresentation()
        #expect(s.presentation == .appConfirmation(.closeGame))
        s.dismissPresentation(ifCurrent: "not-the-current-one")
        #expect(s.presentation == .appConfirmation(.closeGame))
        s.dismissPresentation(ifCurrent: Presentation.appConfirmation(.closeGame).id)
        #expect(s.presentation == .sheet(.findSystem))
        s.dismissPresentation()
        #expect(s.presentation == nil)
        let ids = [Presentation.sheet(.newGame), .sheet(.openSavedGame), .appConfirmation(.deleteSlot("a")),
                   .appConfirmation(.deleteSlot("b")), .systemAlert(.saveFailed(reason: "x"))].map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("UI-SHELL-008 feed items carry day and system after the step; capped at 500; cleared on another game")
    func feed() throws {
        let s = try TestSessions.playing()
        #expect(s.feed.count == 1)
        guard case .gameStarted? = s.feed.first?.event else {
            Issue.record("a new game starts the feed with gameStarted")
            return
        }
        for _ in 0..<260 {
            s.send(.borrow(10))
            s.send(.repay(10))
        }
        #expect(s.feed.count == GameSession.feedLimit)
        let last = try #require(s.feed.last)
        #expect(last.day == s.state?.commander.days && last.systemIndex == s.state?.commander.currentSystem)
        #expect(zip(s.feed, s.feed.dropFirst()).allSatisfy { $0.id < $1.id })
        s.requestCloseGame()
        #expect(s.feed.isEmpty)
    }

    @Test("UI-SHELL-009 a warp ends docked (arrival in the feed), in an encounter (interim panel) or at game over")
    func warpOutcomes() throws {
        var sawDocked = false, sawEncounter = false
        for seed in UInt64(1)...60 where !(sawDocked && sawEncounter) {
            let s = try TestSessions.playing(seed: seed)
            s.send(.selectNextTarget(forward: true))
            s.send(.warp)
            guard let state = s.state else { continue }
            switch state.phase {
            case .docked:
                sawDocked = true
                #expect(s.feed.contains { if case .arrived? = $0.event { true } else { false } })
            case .encounter:
                sawEncounter = true
                let engine = try #require(s.engine)
                #expect(InterimEncounterModel.make(engine: engine) != nil)
                #expect(s.mode == .playing)
            case .gameOver:
                #expect(GameOverCardModel.make(state: state, recorded: s.recordedScore, lastStep: s.lastStep, table: nil) != nil)
            case .inTransit:
                Issue.record("a warp step never rests in transit")
            }
        }
        #expect(sawDocked && sawEncounter)
    }

    @Test("UI-SHELL-010 the interim panel's actions can finish any encounter; Return sends the default action")
    func interimPanelFinishesEncounters() throws {
        var finished = 0
        for seed in UInt64(1)...80 {
            let s = try TestSessions.playing(seed: seed)
            s.send(.selectNextTarget(forward: true))
            s.send(.warp)
            var guardCount = 0
            while case .encounter = s.state?.phase, guardCount < 200 {
                guardCount += 1
                if s.isModal {
                    TestSessions.resolvePresentation(s)
                    continue
                }
                let engine = try #require(s.engine)
                let model = try #require(InterimEncounterModel.make(engine: engine))
                if let cmd = model.returnCommand, case let .encounter(a) = cmd {
                    #expect(model.preview.defaultAction == a)
                }
                let preferred: [EncounterAction] = [.ignore, .submit, .flee, .drink, .meet, .trade, .attack, .surrender, .yield, .bribe]
                let action = preferred.first { p in model.preview.actions.contains { $0.action == p && $0.enabled } }
                    ?? model.preview.actions.first { $0.enabled }?.action
                guard let action else {
                    Issue.record("no enabled action in an encounter (seed \(seed))")
                    break
                }
                s.send(.encounter(action))
            }
            if s.state?.phase == .docked || s.mode != .playing { finished += 1 }
        }
        #expect(finished == 80)
    }

    @Test("UI-SHELL-012 isModal follows the presentation")
    func isModal() throws {
        let s = try TestSessions.playing()
        #expect(!s.isModal)
        s.present(.sheet(.findSystem))
        #expect(s.isModal)
        s.dismissPresentation()
        #expect(!s.isModal)
    }

    @Test("UI-SHELL-019 Quick Start: Modern, Normal, 5/5/5/5, last name or Jameson, template options, -PMSeed")
    func quickStart() throws {
        let s = try TestSessions.make(seed: 42)
        let c = s.quickStartConfig()
        #expect(c.commanderName == "Jameson" && c.difficulty == .normal && c.skills == [5, 5, 5, 5])
        #expect(c.ruleset == .modern && c.seed == 42 && !c.ironman && c.shipName == nil && c.options == nil)
        var template = GameOptions()
        template.autoFuel = true
        OptionsTemplate.save(template, for: .modern, defaults: s.defaults)
        s.defaults.set("Zaphod", forKey: DefaultsKey.lastCommanderName)
        let c2 = s.quickStartConfig()
        #expect(c2.commanderName == "Zaphod" && c2.options == template)
    }

    @Test("UI-SHELL-020 newGameSeed is -PMSeed when given, otherwise random")
    func seeds() throws {
        #expect(try TestSessions.make(seed: 7).newGameSeed() == 7)
        let s = try TestSessions.make(seed: nil)
        let draws = Set((0..<8).map { _ in s.newGameSeed() })
        #expect(draws.count > 1)
    }

    @Test("UI-SHELL-030 Start: validation failure keeps nothing; success sets ids, feed, name, Bridge and the autosave")
    func startNewGame() throws {
        let s = try TestSessions.make()
        #expect(s.startNewGame(NewGameConfig(commanderName: "  ", seed: 1)) == .commanderNameRequired)
        #expect(s.engine == nil)
        s.selectedSection = .bank
        #expect(s.startNewGame(NewGameConfig(commanderName: "Ada", seed: 1)) == nil)
        #expect(s.gameID != nil && s.currentSlotID == nil && s.lastManualSaveDays == 0)
        #expect(s.selectedSection == .bridge)
        #expect(s.defaults.string(forKey: DefaultsKey.lastCommanderName) == "Ada")
        #expect(s.feed.map(\.event) == [.gameStarted(ruleset: .modern, seed: 1)])
        #expect(s.continueCandidate?.isAutosave == true)
        // Ironman: the current slot is the game id, and its slot is written instead of the autosave.
        let i = try TestSessions.make()
        #expect(i.startNewGame(NewGameConfig(commanderName: "Iron", seed: 2, ironman: true)) == nil)
        #expect(i.currentSlotID == i.gameID)
        #expect(i.listSlots().map(\.id) == [i.gameID])
    }

    @Test("UI-SHELL-033 Quick Start and Start converge: day 0, start system, the ruleset's starting cash")
    func converge() throws {
        let s = try TestSessions.playing(seed: 9)
        let state = try #require(s.state)
        #expect(state.commander.days == 0 && state.commander.cash == state.ruleset.tables.startingCash)
        let status = StatusBarModel.make(state: state, feed: [])
        #expect(status.day == 0 && status.cash == 1_000)
        #expect(status.systemName == Names.system(state.commander.currentSystem, in: state))
    }

    @Test("UI-SHELL-095 Close Game clears engine, ids and feed; SAV-043 asks first when days are unsaved")
    func closeGame() throws {
        let s = try TestSessions.playing()
        try TestSessions.edit(s) { $0.commander.days = 3 }
        #expect(s.needsDiscardConfirmation == false) // install resets the manual-save day
        s.lastManualSaveDays = 0
        #expect(s.needsDiscardConfirmation)
        s.requestCloseGame()
        #expect(s.presentation == .appConfirmation(.discardUnsavedGame))
        s.cancel()
        #expect(s.engine != nil && s.pendingReplace == nil)
        s.requestCloseGame()
        s.confirm(AppConfirmation.discardUnsavedGame)
        #expect(s.engine == nil && s.gameID == nil && s.currentSlotID == nil && s.feed.isEmpty && s.mode == .welcome)
    }

    @Test("SAV-043 no discard question for an Ironman or ended game, or when the days match the last manual save")
    func discardRule() throws {
        let s = try TestSessions.playing()
        #expect(!s.needsDiscardConfirmation)
        s.lastManualSaveDays = 5
        #expect(s.needsDiscardConfirmation)
        try TestSessions.edit(s) { $0.ironman = true }
        s.lastManualSaveDays = 5
        #expect(!s.needsDiscardConfirmation)
    }

    @Test("SAV-038 the autosave is written at creation and after arriving; quitting writes it too")
    func autosave() throws {
        let s = try TestSessions.playing(seed: 3)
        let created = try s.slotStore.load(slot: SlotStore.autosaveID)
        #expect(created.state.commander.days == 0 && created.gameID == s.gameID)
        s.send(.selectNextTarget(forward: true))
        s.send(.warp)
        while case .encounter = s.state?.phase {
            if s.isModal { TestSessions.resolvePresentation(s); continue }
            let model = try #require(s.engine.flatMap { InterimEncounterModel.make(engine: $0) })
            let a = model.preview.actions.first { $0.enabled }?.action ?? .ignore
            s.send(.encounter(a))
        }
        if s.state?.phase == .docked {
            #expect(try s.slotStore.load(slot: SlotStore.autosaveID).state == s.state)
        }
        try TestSessions.edit(s) { $0.commander.cash = 4_242 }
        s.writeOnQuit()
        #expect(try s.slotStore.load(slot: SlotStore.autosaveID).state.commander.cash == 4_242)
    }

    @Test("SAV-046 an Ironman game writes its slot after every accepted command and never the autosave")
    func ironmanWrites() throws {
        let s = try TestSessions.make()
        s.startNewGame(NewGameConfig(commanderName: "Iron", seed: 5, ironman: true))
        let id = try #require(s.gameID)
        s.send(.buyFuel(credits: 1))
        s.send(.selectNextTarget(forward: true))
        #expect(try s.slotStore.load(slot: id).state == s.state)
        #expect((try? s.slotStore.info(slot: SlotStore.autosaveID)) == nil)
    }

    @Test("SAV-040 Continue loads the newest unended autosave or Ironman slot; UI-SHELL-021 makes it current")
    func continueGame() throws {
        let s = try TestSessions.playing(seed: 4)
        let id = s.gameID
        s.send(.selectNextTarget(forward: true))
        s.closeGame()
        #expect(s.continueCandidate?.isAutosave == true)
        #expect(s.continueGame())
        #expect(s.gameID == id && s.currentSlotID == nil && s.selectedSection == .bridge && s.mode == .playing)
        let empty = try TestSessions.make()
        #expect(!empty.continueGame())
    }

    @Test("SAV-041 Save writes the current slot (or a new one); Save As always a new slot")
    func saveAndSaveAs() throws {
        let s = try TestSessions.playing()
        s.save()
        let first = try #require(s.currentSlotID)
        #expect(s.feed.last?.entry == .note(.gameSaved))
        s.save()
        #expect(s.currentSlotID == first)
        s.saveAs()
        #expect(s.currentSlotID != first)
        #expect(s.listSlots().filter { !$0.isAutosave }.count == 2)
    }

    @Test("SCORE-037 an ended game is recorded once and the outcome reaches the game-over card")
    func highScoreOnce() throws {
        let s = try TestSessions.playing()
        s.send(.retire)
        guard case let .sheet(.retire(p)) = s.presentation else { return }
        s.confirm(p)
        guard case .outcome(.entered(rank: 1))? = s.recordedScore else {
            Issue.record("first retirement enters at rank 1, got \(String(describing: s.recordedScore))")
            return
        }
        // Reopening the ended game (from its autosave) does not record it again.
        let id = try #require(s.gameID)
        s.closeGame()
        s.openSlot(SlotStore.autosaveID)
        #expect(s.gameID == id && s.recordedScore == .alreadyRecorded)
        #expect(GameOverCardModel.make(state: try #require(s.state), recorded: s.recordedScore, lastStep: nil, table: nil)?.highScoreText != nil)
    }
}
