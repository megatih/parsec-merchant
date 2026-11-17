// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecArt
import ParsecAudio
import ParsecEngine
import Testing
@testable import ParsecMerchant

@MainActor
@Suite("Audio cue map (AUD §4)")
struct AudioMapTests {
    /// AUD-031: the cue each fixture event must produce. Exhaustive with no `default` (AUD-053).
    static func expected(_ kind: GameEventKind) -> SoundCue? {
        switch kind {
        case .boughtCargo, .repaid: .coinOut
        case .soldCargo, .soldEquipment, .bountyPaid, .borrowed: .coinIn
        case .orbitTradeCompleted: .coinOut  // the fixture is `.traderSells`
        case .fined, .bribed, .blackmailed, .looted: .coinLoss
        case .dumpedCargo, .jettisonedCargo: .jettison
        case .boughtFuel: .fuelFill
        case .repairedHull: .repair
        case .boughtEquipment, .boughtEscapePod, .sealedCanisters: .equip
        case .boughtShip, .customShipBuilt: .shipPurchase
        case .departed: .warpDeparture
        case .arrived: .arrival
        case .encounterStarted: .encounterStinger
        case .combatRound: .laser
        case .opponentDestroyed, .playerDestroyed, .bothDestroyed, .reactorMeltdown, .escapePodUsed: .explosion
        case .opponentDisabled: .powerDown
        case .playerEscaped, .opponentEscaped: .escape
        case .arrested: .arrestSiren
        case .plundered, .scooped: .pickup
        case .specialEventCompleted, .captainTraining, .easterEgg: .questChime
        case .tonicConsumed: .drink
        case .gameEnded: .gameEndFanfare  // the fixture is `.retired`
        case .hired, .fired, .insuranceBought, .insuranceStopped, .inspectionClean: .uiConfirm
        case .departureBlocked, .scoopNoRoom: .rejected
        case .caughtLittering, .cannotTransfer, .cannotAffordTransfer, .cannotAffordAllTransfers, .fabricRip,
             .debtWarning, .debtReminder, .reactorWarning, .tribblesDied, .tribblesAteFood, .tribbleInspectorWarning,
             .passengerConcerned, .passengerImpatient, .autoFuelFailed, .autoRepairFailed, .easterEggNoShieldSlot,
             .wildLeftShip, .singularityLost, .gemulonInvaded, .experimentPerformed, .artifactRelinquished,
             .preciousHidden, .sculptureTaken, .wildJoinedPirates, .reactorConfiscated, .yielded, .specialEventRefused:
            .notice
        case .gameStarted, .encounterChanged, .uneventfulTrip, .tribblesChanged, .playerAttacked, .playerFled,
             .optionsChanged, .cheatUsed, .cheatReadout:
            nil
        }
    }

    @Test("AUD-031 AUD-053 one fixture of every GameEvent produces exactly the listed cue (or none)")
    func everyEvent() {
        for kind in GameEventKind.allCases {
            let cues = AudioCueMap.requests(for: AudioFixtures.record([kind.fixture])).map(\.cue)
            if let cue = Self.expected(kind) {
                if kind == .combatRound {
                    #expect(cues.first == .laser && cues.allSatisfy { [.laser, .shieldHit, .hullHit].contains($0) }, "\(kind)")
                } else {
                    #expect(cues == [cue], "\(kind) → \(cues)")
                }
            } else {
                #expect(cues.isEmpty, "\(kind) is silent")
            }
        }
    }

    @Test("AUD-016 AUD-031 amounts transpose coins; profit and trade direction choose the cue")
    func money() {
        func first(_ e: GameEvent) -> ScheduledCue? { AudioCueMap.requests(for: AudioFixtures.record([e])).first }
        #expect(first(.boughtCargo(item: .water, quantity: 1, total: 5))?.pitch == 0)
        #expect(first(.boughtCargo(item: .water, quantity: 1, total: 5000))?.pitch == 6)
        #expect(first(.soldCargo(item: .ore, quantity: 1, total: 500, profit: -1))?.cue == .coinLoss)
        #expect(first(.soldCargo(item: .ore, quantity: 1, total: 500, profit: 0))?.cue == .coinIn)
        #expect(first(.orbitTradeCompleted(direction: .traderBuys, item: .ore, quantity: 1, total: 10))?.cue == .coinIn)
        #expect(first(.fined(1_000_000))?.pitch == 12)
    }

    @Test("AUD-020 AUD-022 AUD-029 AUD-031 variants: wormhole warp, badge stingers, moon fanfare, killed is silent")
    func variants() {
        func cue(_ e: GameEvent) -> ScheduledCue? { AudioCueMap.requests(for: AudioFixtures.record([e])).first }
        #expect(cue(.departed(from: 0, to: 1, viaWormhole: true))?.variant == WarpVariant.wormhole.rawValue)
        #expect(cue(.departed(from: 0, to: 1, viaWormhole: false))?.variant == WarpVariant.normal.rawValue)
        let badges: [(EncounterType, ShipType, StingerVariant)] = [
            (.pirateAttack, .gnat, .pirate), (.pirateAttack, .mantis, .alien), (.policeInspect, .gnat, .police),
            (.traderSell, .gnat, .trader), (.spaceMonsterAttack, .spaceMonster, .alien), (.marieCeleste, .gnat, .special),
        ]
        for (type, ship, variant) in badges {
            let c = cue(.encounterStarted(type: type, opponent: ship, clicks: 3, playerCloaked: false))
            #expect(c?.variant == variant.rawValue, "\(type)")
        }
        #expect(cue(.gameEnded(.boughtMoon, score: 1))?.variant == FanfareVariant.moon.rawValue)
        #expect(cue(.gameEnded(.boughtMoonGirl, score: 1))?.variant == FanfareVariant.moon.rawValue)
        #expect(cue(.gameEnded(.retired, score: 1))?.variant == FanfareVariant.standard.rawValue)
        #expect(cue(.gameEnded(.killed, score: 1)) == nil)
        #expect(LaserVariant.allCases.count == WeaponType.allCases.count)
        #expect(WeaponType.allCases.map { AudioCueMap.laserVariant($0).rawValue } == Array(0..<6))
    }

    @Test("AUD-032 UI-ENC-100 a combat round: lasers at 0 / 0.12 s with the best weapon, hits when the beam lands")
    func combatRound() {
        let before = AudioFixtures.encounter(playerHull: 80, opponentHull: 25)
        var after = before
        after.commander.ship.hull = 70
        if case var .encounter(enc) = after.phase {
            enc.opponent.hull = 20
            after.phase = .encounter(enc)
        }
        let record = AudioFixtures.record([.playerAttacked, .combatRound(round: 1, playerHit: true, opponentHit: true,
                                                                         playerHull: 70, opponentHull: 20)],
                                          before: before, after: after, command: .encounter(.attack))
        let cues = AudioCueMap.requests(for: record)
        let laserPlayer = cues.first { $0.cue == .laser && $0.pan < 0 }
        let laserOpponent = cues.first { $0.cue == .laser && $0.pan > 0 }
        #expect(laserPlayer?.variant == LaserVariant.military.rawValue && laserPlayer?.offset == 0)
        #expect(laserOpponent?.variant == LaserVariant.beam.rawValue && laserOpponent?.offset == 0.12)
        #expect(cues.contains { $0.cue == .hullHit && $0.pan > 0 && abs($0.offset - CombatTiming.land) < 1e-9 })
        #expect(cues.contains { $0.cue == .hullHit && $0.pan < 0 && abs($0.offset - (0.12 + CombatTiming.land)) < 1e-9 })
        #expect(cues.allSatisfy { $0.offset <= 0.55 })

        // A miss is only the laser; a hit absorbed by shields is a shield hit.
        let miss = AudioFixtures.record([.playerAttacked, .combatRound(round: 1, playerHit: false, opponentHit: false,
                                                                       playerHull: 80, opponentHull: 25)],
                                        before: before, after: before)
        #expect(AudioCueMap.requests(for: miss).map(\.cue) == [.laser, .laser])
        let shielded = AudioFixtures.record([.playerAttacked, .combatRound(round: 1, playerHit: false, opponentHit: true,
                                                                           playerHull: 80, opponentHull: 25)],
                                            before: before, after: before)
        #expect(AudioCueMap.requests(for: shielded).contains { $0.cue == .shieldHit && $0.pan > 0 })
        // A fleeing player does not fire; a non-attacking opponent does not either.
        let fleeing = AudioFixtures.record([.playerFled, .combatRound(round: 1, playerHit: false, opponentHit: false,
                                                                      playerHull: 80, opponentHull: 25)],
                                           before: AudioFixtures.encounter(type: .pirateFlee), after: before)
        #expect(AudioCueMap.requests(for: fleeing).isEmpty)
        // Auto-repeat rounds (no `.playerAttacked`) fire while the attack continues.
        let repeating = AudioFixtures.record([.combatRound(round: 2, playerHit: false, opponentHit: false,
                                                           playerHull: 80, opponentHull: 25)],
                                             before: AudioFixtures.encounter(continueAttacking: true), after: before)
        #expect(AudioCueMap.requests(for: repeating).filter { $0.cue == .laser }.count == 2)
    }

    @Test("AUD-032 ART-043 ART-044 one timing source: laser and hit cues start exactly when the planner's beams, ripples and sparks start")
    func plannerTimingIsShared() {
        let before = AudioFixtures.encounter(playerHull: 80, opponentHull: 25)
        var after = before
        after.commander.ship.hull = 60
        if case var .encounter(enc) = after.phase {
            enc.opponent.hull = 20
            after.phase = .encounter(enc)
        }
        let record = AudioFixtures.record([.playerAttacked, .combatRound(round: 1, playerHit: true, opponentHit: true,
                                                                         playerHull: 60, opponentHull: 20)],
                                          before: before, after: after, command: .encounter(.attack))
        let plan = CombatEffectPlanner.plan(record: record)
        let cues = AudioCueMap.requests(for: record)
        func starts(_ match: (CombatEffect.Kind) -> Bool) -> Set<Double> { Set(plan.filter { match($0.kind) }.map(\.start)) }
        let beamStarts = starts { if case .beam = $0 { true } else { false } }
        let landStarts = starts {
            switch $0 {
            case .sparks, .shieldRipple: true
            default: false
            }
        }
        #expect(!beamStarts.isEmpty && !landStarts.isEmpty)
        #expect(Set(cues.filter { $0.cue == .laser }.map(\.offset)) == beamStarts)
        #expect(Set(cues.filter { $0.cue == .hullHit || $0.cue == .shieldHit }.map(\.offset)).isSubset(of: landStarts))
        // The opponent-attack rule is the planner's for every encounter type.
        for type in EncounterType.allCases {
            let s = AudioFixtures.encounter(type: type)
            let r = AudioFixtures.record([.combatRound(round: 1, playerHit: false, opponentHit: false, playerHull: 80, opponentHull: 25)],
                                         before: s, after: s)
            let opponentLaser = AudioCueMap.requests(for: r).contains { $0.cue == .laser && $0.pan > 0 }
            #expect(opponentLaser == CombatEffectPlanner.opponentAttacks(type), "\(type)")
        }
    }

    @Test("AUD-032 UI-ENC-100 the low-hull alarm plays once when the hull crosses to 25% or below")
    func lowHullAlarm() {
        let max = AudioFixtures.maxHull(AudioFixtures.base)
        func record(from: Int, to: Int) -> StepRecord {
            let before = AudioFixtures.encounter(playerHull: from)
            var after = before
            after.commander.ship.hull = to
            return AudioFixtures.record([.combatRound(round: 1, playerHit: true, opponentHit: false, playerHull: to,
                                                      opponentHull: 10)], before: before, after: after)
        }
        func alarms(_ r: StepRecord) -> Int { AudioCueMap.requests(for: r).filter { $0.cue == .lowHullAlarm }.count }
        #expect(alarms(record(from: max * 30 / 100, to: max * 20 / 100)) == 1)
        #expect(alarms(record(from: max * 20 / 100, to: max * 10 / 100)) == 0)  // already critical: not re-armed
        #expect(alarms(record(from: max * 50 / 100, to: max * 40 / 100)) == 0)
        #expect(alarms(record(from: max * 30 / 100, to: 0)) == 0)  // destroyed: the explosion plays instead
        #expect(AudioCueMap.visualTwin(.lowHullAlarm) == .hullBarCritical)
        #expect(EncounterBarModel(kind: .hull, percent: 25).isCritical && !EncounterBarModel(kind: .hull, percent: 26).isCritical)
    }

    @Test("AUD-035 every cue has a twin, every twin is used, and mapped events reach their visual surfaces")
    func visualTwins() {
        let twins = Set(SoundCue.allCases.map(AudioCueMap.visualTwin))
        #expect(twins == Set(VisualTwin.allCases))
        for kind in GameEventKind.allCases where Self.expected(kind) != nil {
            let surfaces = EventSurfaces.surfaces(for: kind.fixture)
            #expect(surfaces.contains(.feed), "\(kind) reaches the feed with sound off")
        }
        #expect(EventSurfaces.surfaces(for: .arrested(term: 1, fine: 1, shipSold: false)).contains(.reportSheet))
        #expect(EventSurfaces.surfaces(for: .gameEnded(.retired, score: 1)).contains(.gameOverCard))
        #expect(EventSurfaces.surfaces(for: GameEventKind.combatRound.fixture).contains(.combatLog))
        #expect(EventSurfaces.surfaces(for: .opponentDestroyed(.gnat)).contains(.combatLog))
        for app in AppCue.allCases {
            _ = AudioCueMap.visualTwin(AudioCueMap.cue(for: app).cue)
        }
        #expect(AudioCueMap.visualTwin(AudioCueMap.cue(for: .newspaper).cue) == .newspaperSheet)
        #expect(AudioCueMap.visualTwin(AudioCueMap.cue(for: .tribble).cue) == .tribbleWiggle)
        #expect(AudioCueMap.visualTwin(AudioCueMap.cue(for: .achievement).cue) == .achievementToast)
    }

    @Test("AUD-034 throttle: a 20-event step yields at most 6 cues and keeps the explosion; duplicates merge")
    func throttle() {
        var events: [GameEvent] = (0..<18).map { _ in .boughtCargo(item: .water, quantity: 1, total: 10) }
        events.insert(.hired(crewID: 1), at: 3)
        events.append(.opponentDestroyed(.gnat))
        let cues = AudioCueMap.requests(for: AudioFixtures.record(events))
        #expect(cues.count == 20)
        let kept = CueScheduler.throttle(cues)
        #expect(kept.count <= 6)
        #expect(kept.contains { $0.cue == .explosion })
        // 18 identical coins at the same offset merge into one.
        #expect(kept.filter { $0.cue == .coinOut }.count == 1)
        let many = (0..<10).map { i in ScheduledCue(cue: .notice, offset: Double(i) * 0.1, eventIndex: i) }
            + [ScheduledCue(cue: .explosion, offset: 0.9, eventIndex: 10)]
        let top = CueScheduler.throttle(many)
        #expect(top.count == 6 && top.contains { $0.cue == .explosion })
        #expect(top.map(\.offset) == top.map(\.offset).sorted())
    }
}
