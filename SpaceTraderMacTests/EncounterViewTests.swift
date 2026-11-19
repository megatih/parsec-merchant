// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import ParsecArt
import ParsecEngine
import SwiftUI
import Testing
@testable import ParsecMerchant

/// Encounter fixtures: a Quick Start game put into an encounter of a chosen type (UI-ENC tests).
@MainActor
enum EncFx {
    static func opponentShip(_ type: ShipType, in state: GameState, weapons: [WeaponType] = [.pulseLaser]) -> Ship {
        var ship = Ship(type: type, spec: state.ruleset.tables.ship(type))
        ship.weapons = weapons
        return ship
    }

    /// A playing session in an encounter (installed like a loaded game, so its log starts with "Encounter resumed.").
    static func session(_ type: EncounterType, opponent: ShipType = .gnat, weapons: [WeaponType] = [.pulseLaser], clicks: Int = 7,
                        seed: UInt64 = 1, configure: (inout GameState) -> Void = { _ in }) throws -> GameSession {
        let s = try TestSessions.playing(seed: seed)
        try TestSessions.edit(s) { st in
            st.encounterTransit = TransitState(destination: st.warpSystem, clicksRemaining: clicks, viaWormhole: false)
            st.phase = .encounter(EncounterState(type: type, opponent: opponentShip(opponent, in: st, weapons: weapons), clicks: clicks))
            configure(&st)
        }
        return s
    }

    static func state(_ type: EncounterType, opponent: ShipType = .gnat, configure: (inout GameState) -> Void = { _ in }) throws -> GameState {
        try #require(try session(type, opponent: opponent, configure: configure).state)
    }

    /// A pending plunder (the engine's memberwise initializer is internal; the offer is Codable).
    static func plunderOffer(_ cargo: [Int], marieCeleste: Bool = false) -> PlunderOffer? {
        let list = cargo.map(String.init).joined(separator: ",")
        let json = "{\"victimCargo\":[\(list)],\"marieCeleste\":\(marieCeleste),\"narcoticsBefore\":0}"
        return try? JSONDecoder().decode(PlunderOffer.self, from: Data(json.utf8))
    }

    static func encounter(_ s: GameState) -> EncounterState? {
        if case let .encounter(e) = s.phase { return e }
        return nil
    }
}

/// Records announcements (UI-ENC-025).
@MainActor
final class RecordingAnnouncer: Announcer {
    var texts: [String] = []
    var priorities: [AnnouncementPriority] = []
    func announce(_ text: String, priority: AnnouncementPriority) {
        texts.append(text)
        priorities.append(priority)
    }
}

@MainActor
struct EncounterViewTests {
    // MARK: §3 Encounter view

    @Test("UI-ENC-015 the encounter detail is the Encounter view; sidebar, toolbar Warp and game commands are locked")
    func encounterDetail() throws {
        let s = try EncFx.session(.pirateAttack)
        #expect(DetailMode.derive(state: s.state, playback: nil, selected: .bank) == .encounter)
        #expect(SidebarLock.make(phase: s.state?.phase) == .inEncounter)
        let ctx = MenuContext.make(session: s)
        #expect(!MenuRules.warp(ctx).isEnabled && !MenuRules.availability(of: .bank, in: ctx).isEnabled)
        #expect(AXID.all.contains(AXID.Encounter.view))
        // The view renders in a window-less host with the session.
        let host = NSHostingView(rootView: EncounterView().environment(s))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width > 0)
    }

    @Test("UI-ENC-016 the intro reproduces the C# EncounterTextInitial / EncounterActionInitial wording")
    func introWording() throws {
        let st = try EncFx.state(.pirateAttack)
        let dest = Names.system(st.transitPreview?.destination ?? st.warpSystem, in: st)
        func intro(_ t: EncounterType, _ o: ShipType, _ clicks: Int = 7, cloaked: Bool = false) throws -> EncounterIntro {
            try #require(EncounterIntro.make(started: .encounterStarted(type: t, opponent: o, clicks: clicks, playerCloaked: cloaked), state: st))
        }
        #expect(try intro(.pirateAttack, .gnat).headline == "At 7 clicks from \(dest) you encounter a pirate gnat.")
        #expect(try intro(.pirateAttack, .gnat, 1).headline == "At 1 click from \(dest) you encounter a pirate gnat.")
        #expect(try intro(.pirateIgnore, .mantis).headline.contains("you encounter an alien mantis."))
        #expect(try intro(.bottleGood, .bottle).headline.hasSuffix("you encounter a floating bottle."))
        #expect(try intro(.captainAhab, .wasp).headline.hasSuffix("you encounter the famous Captain Ahab in a wasp."))
        #expect(try intro(.scarabAttack, .scarab).headline.hasSuffix("a stolen scarab."))
        #expect(try intro(.marieCeleste, .gnat).headline.hasSuffix("a drifting gnat."))
        #expect(try intro(.scorpionAttack, .scorpion).headline.hasSuffix("the kidnappers in a scorpion."))
        #expect(try intro(.spaceMonsterAttack, .spaceMonster).headline.hasSuffix("a horrifying space monster."))
        #expect(try intro(.traderSell, .beetle).headline.hasSuffix("a trader beetle."))
        // Strings.cs:120-132 fixtures for the second line.
        let fixtures: [(EncounterType, Bool, String)] = [
            (.bottleOld, false, "It appears to be a rare bottle of Captain Marmoset's Skill Tonic!"),
            (.captainConrad, false, "The Captain requests a brief meeting with you."),
            (.marieCeleste, false, "The Marie Celeste appears to be completely abandoned."),
            (.pirateAttack, false, "Your opponent attacks."),
            (.policeFlee, false, "Your opponent is fleeing."),
            (.traderIgnore, false, "It ignores you."),
            (.pirateIgnore, true, "It doesn't notice you."),
            (.policeInspect, false, "The police summon you to submit to an inspection."),
            (.marieCelestePolice, false, "\"We know you removed illegal goods from the Marie Celeste. You must give them up at once!\""),
            (.policeSurrender, false, "The police hail they want you to surrender."),
            (.traderBuy, false, "You are hailed with an offer to trade goods."),
        ]
        for (t, cloaked, expected) in fixtures { #expect(try intro(t, .gnat, cloaked: cloaked).action == expected) }
        // Non-initial types (only after a load) never show an empty line.
        #expect(EncounterIntro.actionLine(.traderSurrender, opponent: .gnat, cloaked: false)
            == "The trader ship hails that they wish to surrender to you.")
        #expect(EncounterIntro.make(started: .uneventfulTrip, state: st) == nil)
    }

    @Test("UI-ENC-017 the badge is a glyph plus a word; special encounters get the gold capsule")
    func badge() {
        let words: [(EncounterBadge, String)] = [(.pirate, "Pirate"), (.police, "Police"), (.trader, "Trader"), (.alien, "Alien"),
                                                 (.special, "Special")]
        for (b, w) in words {
            let m = EncounterBadgeModel(badge: b)
            #expect(m.word == w && m.glyph == ArtAdapters.badge(b) && m.isSpecial == (b == .special))
        }
        #expect(EncounterType.captainHuie.badge(opponent: .wasp) == .special)
        #expect(AXID.Encounter.all.contains(AXID.Encounter.badge))
    }

    @Test("UI-ENC-018 UI-ENC-019 UI-ENC-020 ship panes: titles, placeholder facing, bars and portrait labels")
    func shipPanes() throws {
        let s = try EncFx.session(.pirateDisabled) { st in
            st.commander.shipName = "Rocinante"
            if case var .encounter(e) = st.phase {
                e.opponentDisabled = true
                e.opponent.hull = e.opponent.hullStrength(st.ruleset) / 5
                st.phase = .encounter(e)
            }
        }
        let engine = try #require(s.engine)
        let preview = try #require(engine.encounterPreview)
        let player = ShipPaneModel.player(state: engine.state, preview: preview)
        let opponent = try #require(ShipPaneModel.opponent(state: engine.state, preview: preview))
        let type = String(localized: Names.ship(engine.state.commander.ship.type))
        #expect(player.title == "You: \(type) “Rocinante”" && player.facing == .right)
        #expect(opponent.title == "Opponent: Gnat" && opponent.facing == .left && opponent.isDisabled)
        #expect(opponent.hull.text == "Hull \(preview.opponentHullPercent)%" && opponent.hull.isCritical)
        #expect(opponent.shields.text == "No shields" && opponent.shields.percent == nil)
        #expect(player.hull.value == "\(preview.playerHullPercent)%")
        #expect(player.accessibilityLabel.hasPrefix("Your \(type), hull "))
        #expect(opponent.accessibilityLabel == "Pirate Gnat, hull \(preview.opponentHullPercent)%, no shields, disabled")
        #expect(EncounterBarModel(kind: .shields, percent: 40).text == "Shields 40%")
        #expect(EncounterBarModel(kind: .hull, percent: 26).isCritical == false)
        #expect(player.art.facing == .right && opponent.art.facing == .left && opponent.art.disabled)
        #expect(opponent.art.sizeClass == opponent.size.rawValue && player.art.sizeClass == player.size.rawValue)
        try TestSessions.edit(s) { $0.commander.shipName = nil }
        let unnamed = ShipPaneModel.player(state: try #require(s.state), preview: preview)
        #expect(unnamed.title == "You: \(type)")
        for id in [AXID.Encounter.player, AXID.Encounter.playerHull, AXID.Encounter.playerShields, AXID.Encounter.opponent,
                   AXID.Encounter.opponentHull, AXID.Encounter.opponentShields, AXID.Encounter.opponentDisabled] {
            #expect(AXID.all.contains(id))
        }
    }

    @Test("UI-ENC-021 log rows start with R<n>, are indexed from 0 and copy as their display text")
    func logRows() {
        let row = CombatLogLine(round: 3, text: "You hit the Gnat. The Gnat missed you.")
        #expect(row.display == "R3  You hit the Gnat. The Gnat missed you.")
        #expect(CombatLogLine(round: nil, text: "The Gnat attacks.").display == "The Gnat attacks.")
        #expect(AXID.Encounter.logRow(0) == "encounter.log.row.0" && AXID.all.contains(AXID.Encounter.log))
    }

    @Test("UI-ENC-022 round rows reproduce C# EncounterText with hull losses, then the EncounterAction stance")
    func combatRoundLines() throws {
        let before = try EncFx.state(.pirateAttack)
        var after = before
        var enc = try #require(EncFx.encounter(before))
        let oppHull = enc.opponent.hull
        let myHull = before.commander.ship.hull
        enc.round = 1
        enc.opponent.hull = oppHull - 12
        after.commander.ship.hull = myHull - 5
        after.phase = .encounter(enc)
        let events: [GameEvent] = [.playerAttacked, .combatRound(round: 1, playerHit: true, opponentHit: true, playerHull: myHull - 5,
                                                                   opponentHull: oppHull - 12)]
        let step = StepRecord(command: .encounter(.attack), acknowledged: [], before: before, result: StepResult(events: events), after: after)
        let lines = CombatLog.lines(for: step)
        #expect(lines.map(\.display) == ["R1  You hit the pirate ship. (−12 hull) The pirate ship hits you. (−5 hull)",
                                         "The pirate ship attacks."])
        // Fleeing commander and a previously fleeing opponent (Strings.cs:74-83).
        var fleeingBefore = before
        var fb = try #require(EncFx.encounter(before))
        fb.type = .pirateFlee
        fb.oppFleeing = true
        fleeingBefore.phase = .encounter(fb)
        var fleeAfter = fleeingBefore
        fb.cmdrFleeing = true
        fb.oppFleeing = true
        fleeAfter.phase = .encounter(fb)
        let fleeStep = StepRecord(command: .encounter(.flee), acknowledged: [], before: fleeingBefore,
                                  result: StepResult(events: [.combatRound(round: 2, playerHit: false, opponentHit: false,
                                                                           playerHull: myHull, opponentHull: oppHull)]),
                                  after: fleeAfter)
        #expect(CombatLog.lines(for: fleeStep).map(\.display) == ["R2  The pirate ship is still following you. The pirate ship didn't get away.",
                                                                    "The pirate ship is fleeing."])
        #expect(CombatLog.playerSentence(cmdrFleeing: false, opponentHit: false, ship: "Gnat") == "You missed the Gnat.")
        #expect(CombatLog.opponentSentence(oppFleeingPrev: false, playerHit: false, ship: "Gnat") == "The Gnat missed you.")
        #expect(CombatLog.stance(type: .traderSurrender, opponent: .gnat, disabled: false, oppFleeing: true)
            == "The trader ship hails that they wish to surrender to you.")
        #expect(CombatLog.stance(type: .pirateDisabled, opponent: .gnat, disabled: true, oppFleeing: false) == "The pirate ship has been disabled.")
        #expect(CombatLog.shipText(type: .famousCaptainAttack, opponent: .wasp) == "Captain")
        #expect(CombatLog.shipText(type: .pirateAttack, opponent: .mantis) == "alien ship")
        #expect(CombatLog.shipText(type: .policeFlee, opponent: .gnat) == "police ship")
        #expect(CombatLog.shipText(type: .dragonflyAttack, opponent: .dragonfly) == "Dragonfly")
        // A real attack through the session extends the log with an R1 row.
        let s = try EncFx.session(.pirateAttack)
        s.performEncounterAction(.attack)
        #expect(s.encounterUI.log.contains { $0.round == 1 })
    }

    @Test("UI-ENC-023 outcome lines exactly for the ALR combat-log events (one fixture per GameEvent case)")
    func outcomeEntries() throws {
        let st = try EncFx.state(.pirateAttack)
        for kind in GameEventKind.allCases {
            let event = kind.fixture
            let expected = EventSurfaces.surfaces(for: event).contains(.combatLog) && kind != .combatRound
            let entry = CombatLog.entry(for: event, state: st)
            #expect((entry != nil) == expected, "\(kind)")
            if let entry { #expect(!entry.text.isEmpty && entry.round == nil) }
        }
        #expect(CombatLog.entry(for: .encounterChanged(.pirateFlee), state: st)?.text == "The pirate ship is fleeing.")
    }

    @Test("UI-ENC-024 the log is cleared at encounterStarted and resumed loads start with Encounter resumed.")
    func logLifecycle() throws {
        let s = try EncFx.session(.pirateAttack)
        let log = s.encounterUI.log.map(\.text)
        #expect(log.first == "Encounter resumed." && log.count == 3 && log[2] == "Your opponent attacks.")
        // Warping from a docked game until an encounter starts: its log is fresh (no "Encounter resumed.").
        var found = false
        for seed in UInt64(1)...60 where !found {
            let p = try TestSessions.playing(seed: seed)
            p.send(.selectNextTarget(forward: true))
            p.send(.warp)
            guard case .encounter = p.state?.phase else { continue }
            found = true
            #expect(!p.encounterUI.log.contains { $0.text == "Encounter resumed." })
            #expect(p.encounterUI.intro != nil)
        }
        #expect(found)
        s.closeGame()
        #expect(s.encounterUI.log.isEmpty && s.encounterUI.intro == nil)
    }

    @Test("UI-ENC-025 each step's new rows are announced once, combined")
    func announcements() throws {
        let s = try EncFx.session(.pirateAttack)
        let recorder = RecordingAnnouncer()
        s.encounterUI.announcer = recorder
        s.performEncounterAction(.attack)
        #expect(recorder.texts.count == 1)
        #expect(recorder.texts.first?.hasPrefix("R1  ") == true)
        #expect(s.encounterUI.lastAnnouncement == recorder.texts.first)
    }

    @Test("UI-ENC-026 tribble count follows ENC-087 and positions are stable app-side hashes")
    func tribbles() {
        #expect(TribbleLayout.count(tribbles: 0) == 0)
        #expect(TribbleLayout.count(tribbles: 74) == 1)
        #expect(TribbleLayout.count(tribbles: 74 * 25) == 5)
        #expect(TribbleLayout.count(tribbles: 1_000_000) == 36)
        let a = TribbleLayout.positions(seed: 9, days: 12, clicks: 7, count: 10)
        #expect(a == TribbleLayout.positions(seed: 9, days: 12, clicks: 7, count: 10))
        #expect(a != TribbleLayout.positions(seed: 9, days: 13, clicks: 7, count: 10))
        #expect(a.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        #expect(AXID.Encounter.tribble(3) == "encounter.tribble.3")
    }

    // MARK: §4 Actions, keys and the Encounter menu

    @Test("UI-ENC-027 one button per offered action in table order, with key caps and help tags; locked input disables all")
    func actionBar() throws {
        let s = try EncFx.session(.pirateAttack)
        let engine = try #require(s.engine)
        let preview = try #require(engine.encounterPreview)
        let menu = try #require(EncounterMenuState.make(engine: engine, autoRepeatOn: true))
        let bar = EncounterActionBarModel.make(preview: preview, menu: menu, inputLocked: false)
        #expect(bar.buttons.map(\.action) == EncounterType.pirateAttack.actions)
        #expect(bar.buttons.first?.label == "Attack" && bar.buttons.first?.keyCap == "A" && bar.buttons.first?.help == "Attack (A)")
        #expect(bar.resolve != nil && bar.stop.label == "Stop")
        let locked = EncounterActionBarModel.make(preview: preview, menu: menu, inputLocked: true)
        #expect(locked.buttons.allSatisfy { !$0.isEnabled } && locked.resolve?.isEnabled == false)
        // A rejected action shows its reason as the help tag.
        let unarmed = try EncFx.session(.pirateAttack) { $0.commander.ship.weapons = [] }
        let up = try #require(unarmed.engine?.encounterPreview)
        let um = try #require(unarmed.engine.flatMap { EncounterMenuState.make(engine: $0, autoRepeatOn: true) })
        let attack = try #require(EncounterActionBarModel.make(preview: up, menu: um, inputLocked: false).buttons.first)
        #expect(!attack.isEnabled && attack.help == ReasonText.string(for: .noWeapons))
        #expect(AXID.all.contains(AXID.Encounter.actions) && AXID.all.contains(AXID.Encounter.action(.resolve)))
    }

    @Test("UI-ENC-028 encounter keys are unique, match the Encounter menu and never use ⌘ or ⌃")
    func keys() {
        let actions = EncounterAction.allCases.filter { $0 != .autoRepeat }
        let shortcuts = actions.compactMap(EncounterKeys.shortcut(for:)) + [EncounterKeys.autoRepeatToggle]
        #expect(shortcuts.count == actions.count + 1 && Set(shortcuts).count == shortcuts.count)
        #expect(EncounterKeys.shortcut(for: .autoRepeat) == nil)
        #expect(shortcuts.allSatisfy { !$0.modifiers.contains(.command) && !$0.modifiers.contains(.control) })
        let letters = "afsibutpodmy".map(String.init)
        let order: [EncounterAction] = [.attack, .flee, .surrender, .ignore, .bribe, .submit, .trade, .plunder, .board, .drink, .meet, .yield]
        #expect(order.map { EncounterKeys.shortcut(for: $0)?.key } == letters)
        #expect(EncounterKeys.keyCap(for: .resolve) == "R" && EncounterKeys.keyCap(for: .stop) == "Esc")
        #expect(EncounterKeys.key(for: .stop) == .escape && EncounterKeys.modifiers(for: .attack).isEmpty)
        for id in MenuItemID.encounterItems {
            let expected = id.encounterAction.flatMap(EncounterKeys.shortcut(for:)) ?? EncounterKeys.autoRepeatToggle
            #expect(MenuCatalog.entry(for: id).shortcut == expected, "\(id)")
        }
    }

    @Test("UI-ENC-029 Return is the safe default: never attack, surrender, resolve or autoRepeat; destructive yields default to Cancel")
    func defaultAction() throws {
        for type in EncounterType.allCases {
            if let d = type.defaultAction { #expect(![.attack, .surrender, .resolve, .autoRepeat].contains(d), "\(type)") }
        }
        let s = try EncFx.session(.pirateAttack)
        let engine = try #require(s.engine)
        let preview = try #require(engine.encounterPreview)
        let bar = EncounterActionBarModel.make(preview: preview, menu: try #require(EncounterMenuState.make(engine: engine, autoRepeatOn: true)),
                                               inputLocked: false)
        #expect(bar.buttons.filter(\.isDefault).map(\.action) == [.flee])
        #expect(EncounterType.marieCelestePolice.defaultAction == .yield && ConfirmationText.isDestructive(.surrenderToPolice))
    }

    @Test("UI-ENC-030 consent wording: police record word, bribe amount, inspection findings with arrest")
    func consentWording() throws {
        let st = try EncFx.state(.policeInspect)
        let attack = ConfirmationText.content(for: Confirmation(.attackPolice, amounts: [-30]), state: st)
        #expect(attack.message == "Your police record will drop to Criminal.")
        let engineAmount = ConfirmationText.content(for: Confirmation(.attackPolice, amounts: [-33]), state: st).message
        #expect(engineAmount == "Your police record will drop to \(ConfirmationText.recordWord(-33)).")
        #expect(ConfirmationText.content(for: Confirmation(.attackTrader, amounts: [-5]), state: st).message.hasSuffix("drop to Dubious."))
        #expect(ConfirmationText.content(for: Confirmation(.bribe, amounts: [1_500]), state: st).message.contains("1,500"))
        var loaded = st
        loaded.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 4
        loaded.quests.sculpture = QuestStatus.Sculpture.inTransit
        let findings = InspectionFindings.make(state: loaded)
        #expect(findings.illegalUnits == 4 && findings.sculpture && findings.willArrest)
        let submit = ConfirmationText.content(for: Confirmation(.submitInspection), state: loaded).message
        #expect(submit.contains("4 units of illegal goods") && submit.contains("a stolen sculpture") && submit.hasSuffix("You will be arrested."))
        let clean = ConfirmationText.content(for: Confirmation(.submitInspection), state: st).message
        #expect(clean == "The police will search your ship. They will find nothing illegal.")
    }

    @Test("UI-ENC-031 Resolve is shown iff Attack is offered, enabled iff Attack is, and sends .resolve")
    func resolve() throws {
        let s = try EncFx.session(.pirateAttack, opponent: .spaceMonster, weapons: [])
        let menu = try #require(s.engine.flatMap { EncounterMenuState.make(engine: $0, autoRepeatOn: true) })
        let bar = EncounterActionBarModel.make(preview: try #require(s.engine?.encounterPreview), menu: menu, inputLocked: false)
        #expect(bar.resolve?.help == "Attack until the encounter is resolved (R)" && bar.resolve?.isEnabled == true)
        s.performEncounterAction(.resolve)
        #expect(s.lastStep?.command == .encounter(.resolve))
        let bottle = try #require(try EncFx.session(.bottleGood, opponent: .bottle).engine)
        #expect(EncounterMenuState.make(engine: bottle, autoRepeatOn: true)?.resolveShown == false)
    }

    @Test("UI-ENC-032 Stop is enabled iff canStop, sends .stop and cancels; otherwise Esc does nothing")
    func stop() throws {
        let s = try EncFx.session(.pirateAttack)
        let before = s.state
        s.stopEncounter()
        #expect(s.state == before && s.lastStep == nil)
        let flagged = try EncFx.session(.pirateAttack) { st in
            if case var .encounter(e) = st.phase { e.continueAttacking = true; st.phase = .encounter(e) }
        }
        #expect(flagged.engine?.encounterPreview?.canStop == true)
        flagged.stopEncounter()
        #expect(flagged.lastStep?.command == .encounter(.stop))
        #expect(flagged.engine?.encounterPreview?.canStop == false)
        #expect(String(localized: MenuCatalog.entry(for: .encounterStop).titleKey) == "Stop")
    }

    @Test("UI-ENC-033 the Auto-repeat toggle needs Continuous attack or Resolve and only gates the app timer")
    func autoRepeatToggle() throws {
        let s = try EncFx.session(.pirateAttack) { $0.options.continuousAttack = false }
        let off = try #require(s.engine.flatMap { EncounterMenuState.make(engine: $0, autoRepeatOn: true) })
        #expect(!off.autoRepeatAvailable)
        let bar = EncounterActionBarModel.make(preview: try #require(s.engine?.encounterPreview), menu: off, inputLocked: false)
        #expect(bar.autoRepeatHelp == "Turn on Continuous attack in Game › Options…, or use Resolve.")
        let on = try EncFx.session(.pirateAttack) { $0.options.continuousAttack = true }
        #expect(on.engine.flatMap { EncounterMenuState.make(engine: $0, autoRepeatOn: true) }?.autoRepeatAvailable == true)
        let options = on.state?.options
        on.setAutoRepeat(false)
        #expect(!on.encounterUI.autoRepeatEnabled && on.state?.options == options)
        #expect(MenuRules.availability(of: .encounterAutoRepeat, in: .make(session: s)).reason == .autoRepeatUnavailable)
    }

    @Test("UI-ENC-034 MENU-036 the Encounter menu mirrors the preview: shown per action, enabled per rejection, locked when modal")
    func encounterMenu() throws {
        let s = try EncFx.session(.policeInspect)
        let ctx = MenuContext.make(session: s)
        let shown = MenuItemID.encounterItems.filter { MenuRules.isShown($0, in: ctx) }
        #expect(shown.contains(.encounterSubmit) && shown.contains(.encounterBribe) && !shown.contains(.encounterPlunder))
        #expect(shown.contains(.encounterResolve) && shown.contains(.encounterStop) && shown.contains(.encounterAutoRepeat))
        for id in shown where id != .encounterStop && id != .encounterResolve {
            guard let action = id.encounterAction else { continue }
            let p = try #require(ctx.encounter?.preview(action))
            #expect(MenuRules.availability(of: id, in: ctx).isEnabled == (p.rejection == nil), "\(id)")
        }
        #expect(MenuCatalog.entry(for: .encounterSubmit).identifier == "menu.encounter.submit")
        #expect(MenuCatalog.entry(for: .encounterAutoRepeat).identifier == "menu.encounter.autoRepeat")
        #expect(MenuCatalog.items(in: .encounter) == MenuItemID.encounterItems)
        let modal = MenuContext.make(state: s.state, isModal: true)
        #expect(MenuItemID.encounterItems.allSatisfy { !MenuRules.availability(of: $0, in: modal).isEnabled })
        let playing = MenuContext.make(state: s.state, isModal: false, transitPlaying: true)
        #expect(MenuItemID.encounterItems.allSatisfy { !MenuRules.availability(of: $0, in: playing).isEnabled })
        let docked = try #require(TestSessions.playing().state)
        let dockedCtx = MenuContext.make(state: docked, isModal: false)
        #expect(MenuItemID.encounterItems.allSatisfy { MenuRules.availability(of: $0, in: dockedCtx).reason == .notInEncounter })
        #expect(dockedCtx.encounter == nil)
        // Menu items drive the same session entry points.
        #expect(EncounterMenuItems(session: s).session === s)
    }

    @Test("UI-ENC-035 MENU-037 shortcut hygiene: only Encounter items lack ⌘/⌃, each equals EncounterKeys; the menu is milestone 9")
    func menuHygiene() {
        for id in MenuItemID.allCases {
            let e = MenuCatalog.entry(for: id)
            guard let sc = e.shortcut else { continue }
            if !sc.modifiers.contains(.command), !sc.modifiers.contains(.control) {
                #expect(e.menu == .encounter, "\(id)")
            }
        }
        #expect(MenuItemID.encounterItems.allSatisfy { MenuCatalog.entry(for: $0).milestone == 9 })
        #expect(!MenuCatalog.items(in: .encounter, milestone: 8).contains { MenuItemID.encounterItems.contains($0) })
        #expect(MenuShortcut(EncounterKeys.escapeKey, []).display == "⎋")
    }

    @Test("UI-ENC-036 an unpresented pending decision replaces the action bar with Continue Decision")
    func resumeDecision() throws {
        let s = try EncFx.session(.pirateSurrender) { st in
            st.pendingPlunder = EncFx.plunderOffer([0, 2, 0, 0, 0, 0, 0, 0, 0, 0])
        }
        let resume = try #require(s.encounterResumePresentation)
        #expect(resume == .sheet(.plunder(PlunderSheetContext(victimCargo: [0, 2, 0, 0, 0, 0, 0, 0, 0, 0], source: .opponent))))
        s.present(resume)
        #expect(s.encounterResumePresentation == nil)
        let scoop = try EncFx.session(.pirateAttack) { $0.pendingScoop = .water }
        #expect(scoop.encounterResumePresentation == .scoop(.water))
        #expect(try EncFx.session(.pirateAttack).encounterResumePresentation == nil)
        #expect(AXID.all.contains(AXID.Encounter.resumeDecision))
    }

    // MARK: §6 Tactical readout

    @Test("UI-ENC-042 the readout text: class with size, grouped equipment or Unarmed, odds as a word")
    func tacticalText() throws {
        // The engine's readout initializer and shield instances are internal; a shield is decoded from JSON.
        let shield = try JSONDecoder().decode(ShieldInstance.self, from: Data("{\"type\":0,\"charge\":10}".utf8))
        let s = try EncFx.session(.pirateAttack, weapons: [.pulseLaser, .pulseLaser, .beamLaser]) { st in
            if case var .encounter(e) = st.phase {
                e.opponent.shields = [shield]
                st.phase = .encounter(e)
            }
        }
        let st = try #require(s.state)
        let readout = try #require(s.engine?.tacticalReadout)
        #expect(TacticalText.shipClass(readout, ruleset: st.ruleset)
            == "Gnat (\(String(localized: Names.size(st.ruleset.tables.ship(.gnat).size))))")
        #expect(TacticalText.equipment(readout) == "2 × Pulse laser, Beam laser, Energy shield")
        let odds = try #require(TacticalText.fleeOdds(readout))
        #expect(["Good", "Fair", "Poor"].contains(odds))
        let unarmed = try #require(try EncFx.session(.pirateAttack, weapons: []).engine?.tacticalReadout)
        #expect(TacticalText.equipment(unarmed) == "Unarmed")
        let bottle = try #require(try EncFx.session(.bottleGood, opponent: .bottle, weapons: []).engine?.tacticalReadout)
        #expect(TacticalText.fleeOdds(bottle) == nil)
    }

    @Test("UI-ENC-043 the readout shows before the first action when the setting is on and hides after it")
    func tacticalVisibility() throws {
        let fresh = try TestSessions.playing()
        var started: GameSession?
        for seed in UInt64(1)...60 where started == nil {
            let p = try TestSessions.playing(seed: seed)
            p.send(.selectNextTarget(forward: true))
            p.send(.warp)
            if case .encounter = p.state?.phase { started = p }
        }
        let s = try #require(started)
        #expect(s.showsTacticalReadout && !fresh.showsTacticalReadout)
        s.defaults.set(false, forKey: AppSettingsKey.tacticalReadout)
        #expect(!s.showsTacticalReadout)
        s.defaults.set(true, forKey: AppSettingsKey.tacticalReadout)
        let action = try #require(s.engine?.encounterPreview?.actions.first { $0.enabled && $0.confirmation == nil }?.action)
        s.performEncounterAction(action)
        // Hidden after the action, unless the same step started the next encounter (a fresh readout).
        #expect(s.showsTacticalReadout == (s.lastStep?.encounterStarted != nil && s.lastStep?.command == .encounter(action)))
        // A resumed game counts as already acted.
        #expect(try !EncFx.session(.pirateAttack).showsTacticalReadout)
        for id in [AXID.Encounter.tactical, AXID.Encounter.tacticalClass, AXID.Encounter.tacticalEquipment, AXID.Encounter.tacticalFleeOdds] {
            #expect(AXID.all.contains(id))
        }
    }
}
