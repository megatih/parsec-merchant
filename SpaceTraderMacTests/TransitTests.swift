// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
@testable import ParsecMerchant

/// Records the Dock calls the session makes (UI-ENC-010/011).
@MainActor
final class DockRecorder: SessionDock {
    var progress: [Double?] = []
    var badges: [String?] = []
    var attentionRequests = 0

    func setProgress(_ fraction: Double?) { progress.append(fraction) }
    func setBadge(_ label: String?) { badges.append(label) }
    func requestAttention() { attentionRequests += 1 }
}

@MainActor
enum TransitFixtures {
    static let base = GameState(config: NewGameConfig(commanderName: "Transit", seed: 5))

    static func encounterPhase(clicks: Int, type: EncounterType = .pirateAttack) -> GamePhase {
        let ship = Ship(type: .gnat, spec: base.ruleset.tables.ship(.gnat))
        return .encounter(EncounterState(type: type, opponent: ship, clicks: clicks))
    }

    static func state(_ phase: GamePhase, transit: TransitState? = nil) -> GameState {
        var s = base
        s.phase = phase
        s.encounterTransit = transit
        return s
    }

    static func step(_ command: Command = .warp, before: GameState, after: GameState, events: [GameEvent]) -> StepRecord {
        StepRecord(command: command, acknowledged: [], before: before, result: StepResult(events: events), after: after)
    }

    /// A playing session whose playbacks are not skipped and tick only when the test calls `advancePlayback()`.
    static func session(seed: UInt64, dock: any SessionDock = NoDock()) throws -> GameSession {
        let s = try TestSessions.make(seed: seed, fastTravel: false, dock: dock)
        s.playbackClock = nil
        s.requestQuickStart()
        return s
    }

    /// Runs the playback to its end, one tick at a time; returns the number of ticks.
    @discardableResult
    static func play(_ s: GameSession) -> Int {
        var ticks = 0
        while s.transitPlayback != nil, ticks < 100 {
            s.advancePlayback()
            ticks += 1
        }
        return ticks
    }
}

@MainActor
@Suite("Transit and routing (UI-ENC §1–2)")
struct TransitTests {
    // MARK: UI-ENC-001

    @Test("UI-ENC-001 DetailMode.derive over every phase, with and without a playback")
    func detailMode() {
        let playback = TransitPlayback(destination: 1, viaWormhole: false, fromClick: 20, toClick: 0, end: .arrival)
        let transit = TransitState(destination: 3, clicksRemaining: 12, viaWormhole: true)
        let phases: [GamePhase] = [.docked, .inTransit(transit), TransitFixtures.encounterPhase(clicks: 4), .gameOver(.killed)]
        for phase in phases {
            let s = TransitFixtures.state(phase)
            #expect(DetailMode.derive(state: s, playback: playback, selected: .bank) == .transit(playback))
            let mode = DetailMode.derive(state: s, playback: nil, selected: .bank)
            switch phase {
            case .docked: #expect(mode == .section(.bank))
            case .encounter: #expect(mode == .encounter)
            case .gameOver: #expect(mode == .gameOver(.killed))
            case .inTransit: #expect(mode == .transit(.frozen(transit)))
            }
        }
        #expect(DetailMode.derive(state: nil, playback: nil, selected: .bank) == .section(.bank))
    }

    // MARK: UI-ENC-007, -012, -013

    @Test("UI-ENC-007 TransitPlayback.make: uneventful warp, encounter at click 7, resumed trip, fast playback")
    func playbackMake() throws {
        let docked = TransitFixtures.state(.docked)
        let uneventful = TransitFixtures.step(before: docked, after: docked,
                                              events: [.departed(from: 0, to: 4, viaWormhole: false), .uneventfulTrip, .arrived(system: 4)])
        let p = try #require(TransitPlayback.make(step: uneventful, fast: false))
        #expect(p.destination == 4 && p.fromClick == 20 && p.toClick == 0 && p.end == .arrival && p.tickCount == 20)
        #expect(TransitPlayback.make(step: uneventful, fast: true) == nil)
        #expect(TransitPlayback.tickInterval * p.tickCount == .milliseconds(1200))

        let transit = TransitState(destination: 4, clicksRemaining: 7, viaWormhole: true)
        let inEncounter = TransitFixtures.state(TransitFixtures.encounterPhase(clicks: 7), transit: transit)
        let toEncounter = TransitFixtures.step(before: docked, after: inEncounter, events: [
            .departed(from: 0, to: 4, viaWormhole: true),
            .encounterStarted(type: .pirateAttack, opponent: .gnat, clicks: 7, playerCloaked: false),
        ])
        let e = try #require(TransitPlayback.make(step: toEncounter, fast: false))
        #expect(e.fromClick == 20 && e.toClick == 7 && e.end == .encounter && e.viaWormhole && e.tickCount == 13)

        // The encounter ends and the trip continues to arrival (TRV-042): from click 6 down to 0.
        let resumed = TransitFixtures.step(.encounter(.ignore), before: inEncounter, after: docked,
                                           events: [.arrived(system: 4)])
        let r = try #require(TransitPlayback.make(step: resumed, fast: false))
        #expect(r.fromClick == 6 && r.toClick == 0 && r.end == .arrival && r.destination == 4 && r.viaWormhole)

        // A step that keeps the encounter going, a docked step and a confirmation-free arrest have no playback.
        let round = TransitFixtures.step(.encounter(.attack), before: inEncounter, after: inEncounter, events: [
            .combatRound(round: 1, playerHit: false, opponentHit: true, playerHull: 10, opponentHull: 5),
        ])
        #expect(TransitPlayback.make(step: round, fast: false) == nil)
        #expect(TransitPlayback.make(step: TransitFixtures.step(.buyFuel(credits: 10), before: docked, after: docked,
                                                                events: [.boughtFuel(units: 1, cost: 10)]), fast: false) == nil)
        let arrest = TransitFixtures.step(.encounter(.surrender), before: inEncounter, after: docked,
                                          events: [.arrested(term: 30, fine: 500, shipSold: false), .arrived(system: 4)])
        #expect(TransitPlayback.make(step: arrest, fast: false) == nil)

        // Another encounter later in the same trip, and a game that ends on arrival.
        let second = TransitFixtures.step(.encounter(.ignore), before: inEncounter,
                                          after: TransitFixtures.state(TransitFixtures.encounterPhase(clicks: 3), transit: transit),
                                          events: [.encounterStarted(type: .traderIgnore, opponent: .gnat, clicks: 3, playerCloaked: false)])
        let s2 = try #require(TransitPlayback.make(step: second, fast: false))
        #expect(s2.fromClick == 6 && s2.toClick == 3 && s2.end == .encounter)
        let ended = TransitFixtures.step(before: docked, after: TransitFixtures.state(.gameOver(.killed)), events: [
            .departed(from: 0, to: 4, viaWormhole: false), .reactorMeltdown, .gameEnded(.killed, score: 5),
        ])
        #expect(try #require(TransitPlayback.make(step: ended, fast: false)).end == .gameOver)
        let warned = TransitFixtures.step(before: docked, after: docked, events: [
            .departed(from: 0, to: 4, viaWormhole: false), .reactorWarning(status: ReactorStatus.temperatureWarning), .arrived(system: 4),
        ])
        #expect(try #require(TransitPlayback.make(step: warned, fast: false)).end == .report)
    }

    @Test("UI-ENC-012 a fabric rip redirects the playback and carries the banner's system")
    func fabricRip() throws {
        let docked = TransitFixtures.state(.docked)
        let step = TransitFixtures.step(before: docked, after: docked, events: [
            .departed(from: 0, to: 4, viaWormhole: false), .fabricRip(newDestination: 9), .uneventfulTrip, .arrived(system: 9),
        ])
        let p = try #require(TransitPlayback.make(step: step, fast: false))
        #expect(p.fabricRip == 9 && p.destination == 9)
        #expect(String(localized: TransitText.title(p, state: docked)).contains(Names.system(9, in: docked)))
        #expect(AXID.Transit.all.contains(AXID.Transit.fabricRip))
    }

    @Test("UI-ENC-013 a resting inTransit phase shows a frozen playback at its click with no ticks")
    func frozen() {
        let t = TransitState(destination: 2, clicksRemaining: 12, viaWormhole: false)
        let p = TransitPlayback.frozen(t)
        #expect(p.isFrozen && p.tickCount == 0 && p.click(atTick: 5) == 12 && p.clicksFlown(atTick: 0) == 8)
        #expect(DetailMode.derive(state: TransitFixtures.state(.inTransit(t)), playback: nil, selected: .bridge) == .transit(p))
    }

    // MARK: UI-ENC-010, -011

    @Test("UI-ENC-010 the Dock tile fraction is (20 − click) / 20 per tick, nil without a playback")
    func dockFraction() {
        let p = TransitPlayback(destination: 1, viaWormhole: false, fromClick: 20, toClick: 7, end: .encounter)
        let fractions = (0...p.tickCount).compactMap { DockTileProgress.fraction(playback: p, tick: $0) }
        #expect(fractions == (0...13).map { Double($0) / 20 })
        #expect(DockTileProgress.fraction(playback: p, tick: 99) == 13.0 / 20)
        #expect(DockTileProgress.fraction(playback: nil, tick: 3) == nil)
    }

    @Test("UI-ENC-011 the Dock badge is \"!\" only in an encounter while inactive; one attention request per encounter")
    func dockAttention() throws {
        #expect(DockAttention.badge(phase: TransitFixtures.encounterPhase(clicks: 3), isActive: false) == "!")
        #expect(DockAttention.badge(phase: TransitFixtures.encounterPhase(clicks: 3), isActive: true) == nil)
        #expect(DockAttention.badge(phase: .docked, isActive: false) == nil)
        #expect(DockAttention.badge(phase: nil, isActive: false) == nil)

        let dock = DockRecorder()
        let s = try TestSessions.make(seed: 1, dock: dock)
        s.requestQuickStart()
        try TestSessions.edit(s) { $0.phase = TransitFixtures.encounterPhase(clicks: 4) }
        s.setAppActive(false)
        #expect(dock.badges.last == "!" && dock.attentionRequests == 1)
        s.setAppActive(true)
        s.setAppActive(false)
        #expect(dock.badges.last == "!" && dock.attentionRequests == 1)
        s.setAppActive(true)
        #expect(dock.badges.last == .some(nil))
    }

    // MARK: Session: UI-ENC-005, -006, -008, -009, -010, -014

    /// The first seed whose first warp ends in an encounter (or docks, when `encounter` is false).
    private func warpSession(encounter: Bool, dock: any SessionDock = NoDock()) throws -> GameSession {
        for seed in UInt64(1)...80 {
            let s = try TransitFixtures.session(seed: seed, dock: dock)
            s.send(.selectNextTarget(forward: true))
            s.send(.warp)
            let inEncounter = if case .encounter = s.state?.phase { true } else { false }
            if inEncounter == encounter, s.transitPlayback != nil { return s }
        }
        throw CancellationError()
    }

    @Test("UI-ENC-005 the session keeps the last accepted step and clears it on new game, load and close")
    func lastStep() throws {
        let s = try TestSessions.playing()
        #expect(s.lastStep == nil)
        let before = try #require(s.state)
        s.send(.selectNextTarget(forward: true))
        s.send(.warp)
        let step = try #require(s.lastStep)
        #expect(step.command == .warp && step.after == s.state)
        #expect(step.before.phase == .docked && step.before.commander.days == before.commander.days)
        #expect(step.events.contains { if case .departed = $0 { true } else { false } })
        // A rejection or a confirmation request is not an accepted step.
        let recorded = s.lastStep
        s.send(.borrow(-5))
        #expect(s.lastStep == recorded)
        s.install(GameEngine(state: before), gameID: "x", slotID: nil)
        #expect(s.lastStep == nil)
        s.send(.selectNextTarget(forward: true))
        #expect(s.lastStep != nil)
        s.closeGame()
        #expect(s.lastStep == nil)
    }

    @Test("""
        UI-ENC-006 UI-ENC-009 UI-ENC-010 during a playback input is locked, menus read inTransit, the sidebar says In transit \
        and presentations wait; the Dock shows progress
        """)
    func playbackLocks() throws {
        let dock = DockRecorder()
        let s = try warpSession(encounter: false, dock: dock)
        let playback = try #require(s.transitPlayback)
        #expect(playback.end == .arrival && playback.fromClick == 20)
        #expect(s.isInputLocked && !s.isModal)
        #expect(MenuContext.make(session: s).phase == .inTransit)
        #expect(MenuRules.warp(MenuContext.make(session: s)).isEnabled == false)
        #expect(SidebarLock.make(phase: s.state?.phase, transitPlaying: true) == .inTransit)
        #expect(!WarpButtonModel.make(state: s.state, isModal: s.isInputLocked).isEnabled)
        #expect(DetailMode.derive(state: s.state, playback: s.transitPlayback, selected: s.selectedSection) == .transit(playback))
        // The step's events are already in the feed.
        #expect(s.feed.contains { if case .arrived? = $0.event { true } else { false } })
        s.presentAfterPlayback(.sheet(.developerTester))
        #expect(s.presentation == nil)
        let ticks = TransitFixtures.play(s)
        #expect(ticks == 20 && s.transitPlayback == nil)
        #expect(s.presentation == .sheet(.developerTester) && s.isInputLocked)
        s.dismissPresentation()
        #expect(!s.isInputLocked)
        #expect(MenuContext.make(session: s).phase == .docked)
        let fractions = dock.progress.compactMap(\.self)
        #expect(fractions.first == 0 && fractions.last == 19.0 / 20 && dock.progress.last == .some(nil))
    }

    @Test("UI-ENC-008 Skip ends the playback at once and shows the next detail mode; the title names the destination")
    func skip() throws {
        let s = try warpSession(encounter: true)
        let playback = try #require(s.transitPlayback)
        let state = try #require(s.state)
        #expect(String(localized: TransitText.title(playback, state: state)).hasPrefix("En route to"))
        #expect(playback.clicksFlown(atTick: 0) == 0)
        s.advancePlayback()
        #expect(s.transitTick == 1 && playback.clicksFlown(atTick: s.transitTick) == 1)
        let after = s.state
        s.skipPlayback()
        #expect(s.transitPlayback == nil && s.state == after)
        #expect(DetailMode.derive(state: s.state, playback: nil, selected: s.selectedSection) == .encounter)
        #expect([AXID.Transit.view, AXID.Transit.progress, AXID.Transit.skip].allSatisfy(AXID.all.contains))
    }

    @Test("UI-ENC-014 Encounter → Transit (rest of the trip) → next encounter or arrival, in step order")
    func encounterThenTransit() throws {
        var checked = false
        for seed in UInt64(1)...80 where !checked {
            let s = try TransitFixtures.session(seed: seed)
            s.send(.selectNextTarget(forward: true))
            s.send(.warp)
            guard case let .encounter(enc) = s.state?.phase, s.transitPlayback?.end == .encounter else { continue }
            #expect(s.transitPlayback?.toClick == enc.clicks)
            TransitFixtures.play(s)
            #expect(DetailMode.derive(state: s.state, playback: nil, selected: .bridge) == .encounter)
            // Leave the encounter with a harmless action; the rest of the trip plays back.
            let preview = try #require(s.engine?.encounterPreview)
            guard let action = [EncounterAction.ignore, .flee].first(where: { a in
                preview.actions.contains { $0.action == a && $0.enabled && $0.confirmation == nil }
            }) else { continue }
            s.send(.encounter(action))
            if case .encounter = s.state?.phase, s.transitPlayback == nil { continue }
            guard let resumed = s.transitPlayback else { continue }
            #expect(resumed.fromClick == enc.clicks - 1)
            #expect(DetailMode.derive(state: s.state, playback: s.transitPlayback, selected: .bridge) == .transit(resumed))
            TransitFixtures.play(s)
            let next = DetailMode.derive(state: s.state, playback: nil, selected: .bridge)
            #expect(next == .encounter || next == .section(.bridge))
            checked = true
        }
        #expect(checked)
    }
}
