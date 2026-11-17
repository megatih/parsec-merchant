// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecAudio
import ParsecEngine

/// One cue of a step, with its offset from the step (AUD-031…034).
nonisolated struct ScheduledCue: Equatable, Sendable {
    var cue: SoundCue
    var variant: UInt8 = 0
    var pitch: Float = 0
    var gain: Float = 1
    var pan: Float = 0
    /// Seconds after the step (or after the playback releases it).
    var offset: Double = 0
    /// Position of the source event in the step, for the throttle's tie-break.
    var eventIndex = 0
    /// Revealed later by the transit playback: held while a playback runs (AUD-033).
    var revealedByPlayback = false

    var priority: UInt8 { cue.priority }

    func request(offsetBy shift: Double = 0) -> CueRequest {
        CueRequest(cue: cue, variant: variant, pitchSemitones: pitch, gain: gain, pan: pan,
                   delay: Float(min(2, max(0, offset - shift))))
    }
}

/// AUD-032 / ART-044: the combat effect timing that sound follows (the player's beam at 0 s, the opponent's at
/// 0.12 s, beams land 0.25 s later).
nonisolated enum CombatCueTiming {
    static let playerBeamStart = 0.0
    static let opponentBeamStart = 0.12
    static let beamDuration = 0.25
    /// The auto-repeat cadence; extra rounds of one step follow at this spacing.
    static let roundSpacing = 0.6
    /// Panning of the left (player) and right (opponent) panes.
    static let playerPan: Float = -0.4
    static let opponentPan: Float = 0.4
    /// The low-hull level (UI-ENC-100, `EncounterBarModel.isCritical`).
    static let lowHullPercent = 25
    /// With Fast travel the arrival-phase cues follow the warp by this much, keeping the order (AUD-033).
    static let fastArrivalDelay = 0.5
}

/// AUD-031 / AUD-035: engine events → cues, and cues → their visual twins. Pure; every map is an exhaustive switch.
enum AudioCueMap {
    /// Encounter types whose opponent shoots in a round (`executeRound`'s attacking branch).
    static let attackingTypes: Set<EncounterType> = [.dragonflyAttack, .famousCaptainAttack, .marieCelestePolice,
                                                     .pirateAttack, .policeAttack, .scarabAttack, .scorpionAttack,
                                                     .spaceMonsterAttack, .traderAttack]

    static func stingerVariant(_ badge: EncounterBadge) -> StingerVariant {
        switch badge {
        case .pirate: .pirate
        case .police: .police
        case .trader: .trader
        case .alien: .alien
        case .special: .special
        }
    }

    static func laserVariant(_ weapon: WeaponType) -> LaserVariant {
        switch weapon {
        case .pulseLaser: .pulse
        case .beamLaser: .beam
        case .militaryLaser: .military
        case .morgansLaser: .morgans
        case .photonDisruptor: .photonDisruptor
        case .quantumDisruptor: .quantumDisruptor
        }
    }

    static func hullPercent(_ ship: Ship, _ ruleset: Ruleset) -> Int {
        let strength = ship.hullStrength(ruleset)
        return strength <= 0 ? 0 : 100 * ship.hull / strength
    }

    /// AUD-031: every cue of `record`, before throttling and holding.
    static func requests(for record: StepRecord) -> [ScheduledCue] {
        let events = record.events
        let segmentStart = tripSegmentStart(events)
        let departed = events.contains { if case .departed = $0 { true } else { false } }
        var combat = CombatTracker(record: record)
        var out: [ScheduledCue] = []
        for (index, event) in events.enumerated() {
            var cues: [ScheduledCue]
            if case let .combatRound(_, playerHit, opponentHit, playerHull, opponentHull) = event {
                cues = combat.round(playerHit: playerHit, opponentHit: opponentHit, playerHull: playerHull,
                                    opponentHull: opponentHull)
            } else {
                if case .playerAttacked = event { combat.playerAttacked = true }
                if case .playerFled = event { combat.playerFled = true }
                cues = Self.cues(for: event).map {
                    var c = $0
                    c.offset += combat.elapsed
                    return c
                }
            }
            let inSegment = segmentStart.map { index >= $0 } ?? false
            for var c in cues {
                c.eventIndex = index
                if inSegment || Self.isRevealedLater(event) {
                    c.revealedByPlayback = true
                    if departed && inSegment { c.offset += CombatCueTiming.fastArrivalDelay }
                }
                out.append(c)
            }
        }
        if let alarm = combat.lowHullAlarm(index: events.count) { out.append(alarm) }
        return out
    }

    /// The first event of the trip part of a step: after `departed`, or the first click-loop result of a resumed trip.
    static func tripSegmentStart(_ events: [GameEvent]) -> Int? {
        for (i, e) in events.enumerated() {
            switch e {
            case .departed: return i + 1
            case .encounterStarted, .uneventfulTrip, .arrived, .fabricRip: return i
            default: continue
            }
        }
        return nil
    }

    /// AUD-033: events the playback reveals at its end.
    static func isRevealedLater(_ event: GameEvent) -> Bool {
        switch event {
        case .encounterStarted, .arrived, .arrested, .gameEnded: true
        default: false
        }
    }

    private static func coin(_ cue: SoundCue, _ amount: Int) -> [ScheduledCue] {
        [ScheduledCue(cue: cue, pitch: amountPitch(amount))]
    }

    private static func one(_ cue: SoundCue, variant: UInt8 = 0, pan: Float = 0) -> [ScheduledCue] {
        [ScheduledCue(cue: cue, variant: variant, pan: pan)]
    }

    // AUD-031 items 1–8 (combat rounds are handled by `CombatTracker`). Exhaustive, no `default`; one line per
    // engine event, so the case count is the complexity.
    // swiftlint:disable:next cyclomatic_complexity
    static func cues(for event: GameEvent) -> [ScheduledCue] {
        switch event {
        // 1. Money.
        case let .boughtCargo(_, _, total): return coin(.coinOut, total)
        case let .soldCargo(_, _, total, profit): return coin(profit >= 0 ? .coinIn : .coinLoss, total)
        case let .orbitTradeCompleted(direction, _, _, total):
            switch direction {
            case .traderSells: return coin(.coinOut, total)
            case .traderBuys: return coin(.coinIn, total)
            }
        case let .soldEquipment(price): return coin(.coinIn, price)
        case let .bountyPaid(amount): return coin(.coinIn, amount)
        case let .borrowed(amount): return coin(.coinIn, amount)
        case let .repaid(amount): return coin(.coinOut, amount)
        case let .fined(amount): return coin(.coinLoss, amount)
        case let .bribed(amount): return coin(.coinLoss, amount)
        case let .blackmailed(amount): return coin(.coinLoss, amount)
        case let .looted(units): return coin(.coinLoss, units)
        // 2. Cargo, services and equipment.
        case .dumpedCargo, .jettisonedCargo: return one(.jettison)
        case .boughtFuel: return one(.fuelFill)
        case .repairedHull: return one(.repair)
        case .boughtEquipment, .boughtEscapePod, .sealedCanisters: return one(.equip)
        case .boughtShip, .customShipBuilt: return one(.shipPurchase)
        // 3. Travel and encounters.
        case let .departed(_, _, viaWormhole):
            return one(.warpDeparture, variant: (viaWormhole ? WarpVariant.wormhole : .normal).rawValue)
        case .arrived: return one(.arrival)
        case let .encounterStarted(type, opponent, _, _):
            return one(.encounterStinger, variant: stingerVariant(type.badge(opponent: opponent)).rawValue,
                       pan: CombatCueTiming.opponentPan)
        // 4. Combat outcomes.
        case .combatRound: return []
        case .opponentDestroyed: return one(.explosion, pan: CombatCueTiming.opponentPan)
        case .playerDestroyed, .reactorMeltdown, .escapePodUsed: return one(.explosion, pan: CombatCueTiming.playerPan)
        case .bothDestroyed: return one(.explosion)
        case .opponentDisabled: return one(.powerDown, pan: CombatCueTiming.opponentPan)
        case .playerEscaped: return one(.escape, pan: CombatCueTiming.playerPan)
        case .opponentEscaped: return one(.escape, pan: CombatCueTiming.opponentPan)
        case .arrested: return one(.arrestSiren)
        case .plundered, .scooped: return one(.pickup)
        // 5. Quests and endings.
        case .specialEventCompleted, .captainTraining, .easterEgg: return one(.questChime)
        case .tonicConsumed: return one(.drink)
        case let .gameEnded(type, _):
            switch type {
            case .killed: return []
            case .retired: return one(.gameEndFanfare, variant: FanfareVariant.standard.rawValue)
            case .boughtMoon, .boughtMoonGirl: return one(.gameEndFanfare, variant: FanfareVariant.moon.rawValue)
            }
        // 6. Confirmations and rejections.
        case .hired, .fired, .insuranceBought, .insuranceStopped, .inspectionClean: return one(.uiConfirm)
        case .departureBlocked, .scoopNoRoom: return one(.rejected)
        // 7. Notices.
        case .caughtLittering, .cannotTransfer, .cannotAffordTransfer, .cannotAffordAllTransfers, .fabricRip,
             .debtWarning, .debtReminder, .reactorWarning, .tribblesDied, .tribblesAteFood, .tribbleInspectorWarning,
             .passengerConcerned, .passengerImpatient, .autoFuelFailed, .autoRepairFailed, .easterEggNoShieldSlot,
             .wildLeftShip, .singularityLost, .gemulonInvaded, .experimentPerformed, .artifactRelinquished,
             .preciousHidden, .sculptureTaken, .wildJoinedPirates, .reactorConfiscated, .yielded,
             .specialEventRefused:
            return one(.notice)
        // 8. Silent.
        case .gameStarted, .encounterChanged, .uneventfulTrip, .tribblesChanged, .playerAttacked, .playerFled,
             .optionsChanged, .cheatUsed, .cheatReadout:
            return []
        }
    }

    /// AUD-030 / AUD-036: the app-originated cues.
    static func cue(for app: AppCue) -> ScheduledCue {
        switch app {
        case .newspaper: ScheduledCue(cue: .newspaperRustle)
        case .achievement: ScheduledCue(cue: .achievementChime)
        case .tribble: ScheduledCue(cue: .tribbleSqueak, pan: CombatCueTiming.playerPan)
        case .testSound: ScheduledCue(cue: .coinIn)
        case .rejected: ScheduledCue(cue: .rejected)
        }
    }

    /// AUD-035: every cue's visual twin. Exhaustive, no `default`.
    static func visualTwin(_ cue: SoundCue) -> VisualTwin {
        switch cue {
        case .uiTick: .transitProgress
        case .uiConfirm: .controlState
        case .rejected: .statusText
        case .coinIn, .coinOut, .coinLoss: .cashTicker
        case .jettison, .pickup: .cargoCount
        case .fuelFill, .repair: .dockGauge
        case .equip, .shipPurchase: .slotTile
        case .warpDeparture: .transitView
        case .arrival: .arrivalReport
        case .encounterStinger: .encounterBadge
        case .laser: .beamEffect
        case .shieldHit: .shieldRipple
        case .hullHit: .hullSparks
        case .explosion: .explosionEffect
        case .powerDown: .disabledTag
        case .escape: .escapeEffect
        case .lowHullAlarm: .hullBarCritical
        case .arrestSiren, .drink: .reportSheet
        case .notice: .feedItem
        case .questChime: .narrativeSheet
        case .gameEndFanfare: .gameOverCard
        case .newspaperRustle: .newspaperSheet
        case .achievementChime: .achievementToast
        case .tribbleSqueak: .tribbleWiggle
        }
    }
}

/// AUD-032: follows the combat rounds of one step, so lasers, hits and the alarm match the effects (ART-043/044).
struct CombatTracker {
    let ruleset: Ruleset
    let opponentAttacks: Bool
    let continuingAttack: Bool
    let playerWeapon: WeaponType?
    let opponentWeapon: WeaponType?
    let playerShieldsBefore: Int
    let playerShieldsAfter: Int
    let opponentShieldsBefore: Int?
    let opponentShieldsAfter: Int?
    let hullPercentBefore: Int
    let hullPercentAfter: Int
    let playerAlive: Bool
    var playerHull: Int
    var opponentHull: Int
    var playerAttacked = false
    var playerFled = false
    var rounds = 0
    /// Seconds of rounds already placed in this step.
    var elapsed: Double { Double(max(0, rounds - 1)) * CombatCueTiming.roundSpacing }

    init(record: StepRecord) {
        ruleset = record.before.ruleset
        let me = record.before.commander.ship
        playerWeapon = me.weapons.max()
        playerHull = me.hull
        playerShieldsBefore = me.shieldCharge
        playerShieldsAfter = record.after.commander.ship.shieldCharge
        hullPercentBefore = AudioCueMap.hullPercent(me, ruleset)
        hullPercentAfter = AudioCueMap.hullPercent(record.after.commander.ship, ruleset)
        let ended = if case .gameOver = record.after.phase { true } else { false }
        playerAlive = record.after.commander.ship.hull > 0 && !ended
        if case let .encounter(enc) = record.before.phase {
            opponentAttacks = AudioCueMap.attackingTypes.contains(enc.type)
            continuingAttack = enc.continueAttacking
            opponentWeapon = enc.opponent.weapons.max()
            opponentHull = enc.opponent.hull
            opponentShieldsBefore = enc.opponent.shieldCharge
        } else {
            opponentAttacks = false
            continuingAttack = false
            opponentWeapon = nil
            opponentHull = 0
            opponentShieldsBefore = nil
        }
        if case let .encounter(after) = record.after.phase {
            opponentShieldsAfter = after.opponent.shieldCharge
        } else {
            opponentShieldsAfter = nil
        }
    }

    /// The cues of one `combatRound`.
    mutating func round(playerHit: Bool, opponentHit: Bool, playerHull newPlayerHull: Int,
                        opponentHull newOpponentHull: Int) -> [ScheduledCue] {
        rounds += 1
        let base = elapsed
        var cues: [ScheduledCue] = []
        let playerFired = (playerAttacked || continuingAttack || opponentHit) && !playerFled
        let opponentFired = opponentAttacks || playerHit
        let land = CombatCueTiming.beamDuration
        if playerFired, let weapon = playerWeapon {
            cues.append(ScheduledCue(cue: .laser, variant: AudioCueMap.laserVariant(weapon).rawValue,
                                     pan: CombatCueTiming.playerPan, offset: base + CombatCueTiming.playerBeamStart))
            if opponentHit {
                let hullDropped = newOpponentHull < opponentHull
                let shieldDropped = rounds == 1 && (opponentShieldsAfter.map { $0 < (opponentShieldsBefore ?? 0) } ?? false)
                let at = base + CombatCueTiming.playerBeamStart + land
                if shieldDropped || !hullDropped {
                    cues.append(ScheduledCue(cue: .shieldHit, pan: CombatCueTiming.opponentPan, offset: at))
                }
                if hullDropped { cues.append(ScheduledCue(cue: .hullHit, pan: CombatCueTiming.opponentPan, offset: at)) }
            }
        }
        if opponentFired, let weapon = opponentWeapon {
            cues.append(ScheduledCue(cue: .laser, variant: AudioCueMap.laserVariant(weapon).rawValue,
                                     pan: CombatCueTiming.opponentPan, offset: base + CombatCueTiming.opponentBeamStart))
            if playerHit {
                let hullDropped = newPlayerHull < playerHull
                let shieldDropped = rounds == 1 && playerShieldsAfter < playerShieldsBefore
                let at = base + CombatCueTiming.opponentBeamStart + land
                if shieldDropped || !hullDropped {
                    cues.append(ScheduledCue(cue: .shieldHit, pan: CombatCueTiming.playerPan, offset: at))
                }
                if hullDropped { cues.append(ScheduledCue(cue: .hullHit, pan: CombatCueTiming.playerPan, offset: at)) }
            }
        }
        playerHull = newPlayerHull
        opponentHull = newOpponentHull
        return cues
    }

    /// AUD-032: once when the player's hull crosses from above 25% to 25% or below in this step (re-arming after it
    /// rises above 25% again follows from comparing the step's before and after states).
    func lowHullAlarm(index: Int) -> ScheduledCue? {
        guard playerAlive, hullPercentBefore > CombatCueTiming.lowHullPercent,
              hullPercentAfter <= CombatCueTiming.lowHullPercent else { return nil }
        return ScheduledCue(cue: .lowHullAlarm, offset: elapsed + CombatCueTiming.opponentBeamStart + CombatCueTiming.beamDuration,
                            eventIndex: index)
    }
}
