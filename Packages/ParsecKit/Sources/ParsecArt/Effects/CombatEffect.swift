// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The two encounter panes.
public enum CombatSide: Sendable, Hashable {
    case player, opponent

    public var other: CombatSide { self == .player ? .opponent : .player }
}

/// ART-042: beam looks in `WeaponType` order.
public enum BeamKind: Int, CaseIterable, Sendable, Hashable {
    case pulse = 0, beam, military, morgans, photon, quantum
}

/// ART-047: the colour of a Reduce Motion flash (each also shows a static symbol, so it is not colour only).
public enum FlashTone: Sendable, Hashable {
    case hullHit, shieldHit, miss, heavyHit, explosion, powerDown, escape, arrive
}

/// ART-042: one visual effect with its start and duration (seconds from the start of the plan).
public struct CombatEffect: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case beam(from: CombatSide, weapon: BeamKind, hit: Bool)
        case shieldRipple(on: CombatSide, kind: ShieldDisplay.Kind)
        case sparks(on: CombatSide, count: Int)
        case shake(amplitude: Double)
        case explosion(on: CombatSide)
        case powerDown(on: CombatSide)
        case escape(side: CombatSide)
        case arrive(side: CombatSide)
        case flash(on: CombatSide, tone: FlashTone)
    }

    public var kind: Kind
    public var start: Double
    public var duration: Double
    /// Seeds the spark and debris positions (the round number).
    public var seed: Int

    public init(_ kind: Kind, start: Double, duration: Double, seed: Int = 0) {
        self.kind = kind
        self.start = start
        self.duration = duration
        self.seed = seed
    }

    public var end: Double { start + duration }

    public var isFlash: Bool {
        if case .flash = kind { return true }
        return false
    }

    /// The end of a plan (0 when empty).
    public static func end(of plan: [CombatEffect]) -> Double { plan.map(\.end).max() ?? 0 }

    /// ART-047: every effect becomes exactly one 0.2 s flash on the affected pane; nothing moves, scales or shakes.
    public static func reducedMotion(_ plan: [CombatEffect]) -> [CombatEffect] {
        plan.map { e in
            let (side, tone): (CombatSide, FlashTone) = switch e.kind {
            case let .beam(from, _, hit): (from.other, hit ? .hullHit : .miss)
            case let .shieldRipple(on, _): (on, .shieldHit)
            case let .sparks(on, _): (on, .hullHit)
            case .shake: (.player, .heavyHit)
            case let .explosion(on): (on, .explosion)
            case let .powerDown(on): (on, .powerDown)
            case let .escape(side): (side, .escape)
            case let .arrive(side): (side, .arrive)
            case let .flash(on, tone): (on, tone)
            }
            return CombatEffect(.flash(on: side, tone: tone), start: e.start, duration: CombatTiming.flash, seed: e.seed)
        }
    }
}

/// ART-044/046: the timing of combat effects, in seconds.
public enum CombatTiming {
    public static let playerBeamStart = 0.0
    public static let opponentBeamStart = 0.12
    public static let beam = 0.25
    /// Beams travel almost instantly; ripples and sparks start when the beam lands.
    public static let land = 0.03
    public static let ripple = 0.35
    public static let sparks = 0.40
    public static let shake = 0.30
    /// Every plan for a round ends within this time (less than the 0.6 s auto-repeat cadence).
    public static let roundBudget = 0.55
    public static let explosion = 0.8
    public static let powerDown = 0.4
    public static let escape = 0.5
    public static let arrive = 0.35
    public static let flash = 0.2
    /// The static symbol of a Reduce Motion flash stays this long.
    public static let symbolHold = 0.6
}

/// Pure motion of the panes and ships for a plan at time `t` (the app applies these as offsets and opacity).
public enum CombatMotion {
    /// ART-044: the shake offset (exponentially damped); zero when the plan has no shake.
    public static func shake(_ plan: [CombatEffect], at t: Double) -> CGSize {
        for e in plan {
            guard case let .shake(amplitude) = e.kind, t >= e.start, t <= e.end else { continue }
            let u = t - e.start
            let damp = exp(-u / e.duration * 4)
            return CGSize(width: amplitude * damp * sin(u * 2 * .pi * 18), height: amplitude * 0.5 * damp * cos(u * 2 * .pi * 15))
        }
        return .zero
    }

    /// ART-046: the ship's horizontal offset (escape slides off, arrive slides in), in pane widths.
    public static func shipOffset(_ plan: [CombatEffect], side: CombatSide, at t: Double) -> Double {
        let away: Double = side == .player ? -1 : 1
        for e in plan {
            switch e.kind {
            case let .escape(s) where s == side && t >= e.start:
                let u = min(1, (t - e.start) / e.duration)
                return away * u * u * 1.2
            case let .arrive(s) where s == side && t <= e.end:
                let u = max(0, (t - e.start) / e.duration)
                return away * (1 - u) * (1 - u) * 0.8
            default:
                continue
            }
        }
        return 0
    }

    /// ART-046: whether the ship is drawn (not after its explosion has finished, not after a finished escape).
    public static func shipVisible(_ plan: [CombatEffect], side: CombatSide, at t: Double) -> Bool {
        for e in plan where t >= e.end {
            switch e.kind {
            case let .explosion(s) where s == side: return false
            case let .flash(s, .explosion) where s == side: return false
            case let .flash(s, .escape) where s == side: return false
            default: continue
            }
        }
        return true
    }
}
