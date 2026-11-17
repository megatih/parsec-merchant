// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine

/// ART-043: the visual effects of one step, derived from its events and its before/after states. Pure: it never reads
/// the game RNG and never changes state.
enum CombatEffectPlanner {
    /// UI-ENC-098: a hull loss of at least this share of the player's maximum hull in one round shakes the panes.
    static let heavyHitShare = 0.15
    static let shakeAmplitude = 6.0

    /// ENC: the encounter types in which the opponent shoots during a round (`executeRound`'s attacking cases).
    static func opponentAttacks(_ t: EncounterType) -> Bool {
        switch t {
        case .dragonflyAttack, .famousCaptainAttack, .marieCelestePolice, .pirateAttack, .policeAttack, .scarabAttack, .scorpionAttack,
             .spaceMonsterAttack, .traderAttack:
            true
        case .bottleGood, .bottleOld, .captainAhab, .captainConrad, .captainHuie, .dragonflyIgnore, .famousCaptDisabled, .marieCeleste,
             .pirateIgnore, .pirateFlee, .pirateSurrender, .pirateDisabled, .policeIgnore, .policeFlee, .policeSurrender, .policeDisabled,
             .policeInspect, .scarabIgnore, .scorpionIgnore, .spaceMonsterIgnore, .traderIgnore, .traderFlee, .traderSurrender,
             .traderDisabled, .traderBuy, .traderSell:
            false
        }
    }

    static func plan(record: StepRecord?) -> [CombatEffect] {
        guard let record else { return [] }
        var effects: [CombatEffect] = []
        let playerFired = record.contains { if case .playerAttacked = $0 { true } else { false } }
        for event in record.events {
            switch event {
            case .encounterStarted:
                effects.append(CombatEffect(.arrive(side: .opponent), start: 0, duration: CombatTiming.arrive))
            case let .combatRound(round, _, _, playerHull, opponentHull):
                effects += roundEffects(record, round: round, playerFired: playerFired, playerHull: playerHull, opponentHull: opponentHull)
            case .opponentDestroyed:
                effects.append(CombatEffect(.explosion(on: .opponent), start: landing, duration: CombatTiming.explosion, seed: round(record)))
            case .playerDestroyed:
                effects.append(CombatEffect(.explosion(on: .player), start: landing, duration: CombatTiming.explosion, seed: round(record)))
            case .bothDestroyed:
                effects.append(CombatEffect(.explosion(on: .opponent), start: landing, duration: CombatTiming.explosion, seed: round(record)))
                effects.append(CombatEffect(.explosion(on: .player), start: landing, duration: CombatTiming.explosion, seed: round(record)))
            case .opponentDisabled:
                effects.append(CombatEffect(.powerDown(on: .opponent), start: landing, duration: CombatTiming.powerDown))
            case .playerEscaped:
                effects.append(CombatEffect(.escape(side: .player), start: 0, duration: CombatTiming.escape))
            case .opponentEscaped:
                effects.append(CombatEffect(.escape(side: .opponent), start: 0, duration: CombatTiming.escape))
            default:
                continue
            }
        }
        return effects
    }

    /// When the opponent's beam lands (the latest beam of a round).
    static let landing = CombatTiming.opponentBeamStart + CombatTiming.land

    static func round(_ record: StepRecord) -> Int {
        for e in record.events { if case let .combatRound(round, _, _, _, _) = e { return round } }
        return 0
    }

    private struct Side {
        var ship: Ship
        var hullAfter: Int
        var shieldAfter: Int
        var maxHull: Int
    }

    private static func roundEffects(_ record: StepRecord, round: Int, playerFired: Bool, playerHull: Int, opponentHull: Int) -> [CombatEffect] {
        guard case let .encounter(before) = record.before.phase else { return [] }
        let ruleset = record.before.ruleset
        var afterOpponentShield = 0
        if case let .encounter(after) = record.after.phase { afterOpponentShield = after.opponent.shieldCharge }
        let player = Side(ship: record.before.commander.ship, hullAfter: playerHull, shieldAfter: record.after.commander.ship.shieldCharge,
                          maxHull: max(1, record.before.commander.ship.hullStrength(ruleset)))
        let opponent = Side(ship: before.opponent, hullAfter: opponentHull, shieldAfter: afterOpponentShield,
                            maxHull: max(1, before.opponent.hullStrength(ruleset)))
        var effects: [CombatEffect] = []
        if playerFired {
            effects += shot(from: .player, shooter: player.ship, target: opponent, start: CombatTiming.playerBeamStart, round: round)
        }
        if opponentAttacks(before.type) {
            effects += shot(from: .opponent, shooter: opponent.ship, target: player, start: CombatTiming.opponentBeamStart, round: round)
            let loss = Double(player.ship.hull - playerHull) / Double(player.maxHull)
            if loss >= heavyHitShare {
                effects.append(CombatEffect(.shake(amplitude: shakeAmplitude), start: CombatTiming.opponentBeamStart + CombatTiming.land,
                                            duration: CombatTiming.shake))
            }
        }
        return effects
    }

    private static func shot(from side: CombatSide, shooter: Ship, target: Side, start: Double, round: Int) -> [CombatEffect] {
        guard let weapon = shooter.weapons.max() else { return [] }
        let shieldDropped = target.shieldAfter < target.ship.shieldCharge
        let hullLoss = max(0, target.ship.hull - target.hullAfter)
        var effects = [CombatEffect(.beam(from: side, weapon: ArtAdapters.beam(weapon), hit: shieldDropped || hullLoss > 0), start: start,
                                    duration: CombatTiming.beam, seed: round)]
        let land = start + CombatTiming.land
        if shieldDropped, let kind = target.ship.shields.map(\.type).max() {
            effects.append(CombatEffect(.shieldRipple(on: side.other, kind: ArtAdapters.shieldKind(kind)), start: land, duration: CombatTiming.ripple,
                                        seed: round))
        }
        if hullLoss > 0 {
            let share = min(1, Double(hullLoss) / Double(target.maxHull))
            effects.append(CombatEffect(.sparks(on: side.other, count: 4 + Int(12 * share)), start: land, duration: CombatTiming.sparks, seed: round))
        }
        return effects
    }
}
