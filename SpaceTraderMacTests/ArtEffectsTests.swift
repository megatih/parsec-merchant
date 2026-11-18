// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ParsecArt
import ParsecEngine
import SwiftUI
import Testing
@testable import ParsecMerchant

/// Fixture step records for the combat effect planner (ART-043).
@MainActor
enum EffectFx {
    static func before(_ type: EncounterType = .pirateAttack, playerShields: [ShieldInstance] = [],
                       opponentShields: [ShieldInstance] = []) throws -> GameState {
        var state = try EncFx.state(type, opponent: .gnat)
        state.commander.ship.weapons = [.pulseLaser, .militaryLaser]
        state.commander.ship.shields = playerShields
        if case var .encounter(e) = state.phase {
            e.opponent.weapons = [.beamLaser]
            e.opponent.shields = opponentShields
            state.phase = .encounter(e)
        }
        return state
    }

    static func record(_ before: GameState, events: [GameEvent], change: (inout GameState) -> Void = { _ in }) -> StepRecord {
        var after = before
        change(&after)
        return StepRecord(command: .encounter(.attack), acknowledged: [], before: before, result: StepResult(events: events), after: after)
    }

    static func round(_ s: GameState, playerHull: Int, opponentHull: Int) -> GameEvent {
        .combatRound(round: 3, playerHit: playerHull < s.commander.ship.hull, opponentHit: true, playerHull: playerHull, opponentHull: opponentHull)
    }

    /// The engine's memberwise initializer is internal; the shield instance is Codable.
    static func shield(_ type: ShieldType, charge: Int) -> ShieldInstance {
        let json = "{\"type\":\(type.rawValue),\"charge\":\(charge)}"
        guard let shield = try? JSONDecoder().decode(ShieldInstance.self, from: Data(json.utf8)) else { fatalError("bad shield fixture") }
        return shield
    }

    static func opponentHull(_ s: GameState) -> Int {
        if case let .encounter(e) = s.phase { return e.opponent.hull }
        return 0
    }
}

@MainActor
@Suite("Combat effects in the app")
struct ArtEffectsTests {
    @Test("ART-043 a round where both sides fire: beams by highest weapon, ripples on dropped shields, sparks on hull loss")
    func bothFire() throws {
        let s = try EffectFx.before(playerShields: [EffectFx.shield(.energy, charge: 40)])
        let oppHull = EffectFx.opponentHull(s)
        let r = EffectFx.record(s, events: [.playerAttacked, EffectFx.round(s, playerHull: s.commander.ship.hull, opponentHull: oppHull - 10)]) {
            $0.commander.ship.shields[0].charge = 20
            if case var .encounter(e) = $0.phase {
                e.opponent.hull = oppHull - 10
                $0.phase = .encounter(e)
            }
        }
        let plan = CombatEffectPlanner.plan(record: r)
        #expect(plan.contains(CombatEffect(.beam(from: .player, weapon: .military, hit: true), start: 0, duration: 0.25, seed: 3)))
        #expect(plan.contains(CombatEffect(.beam(from: .opponent, weapon: .beam, hit: true), start: 0.12, duration: 0.25, seed: 3)))
        let ripple = CombatEffect(.shieldRipple(on: .player, kind: .energy), start: 0.15, duration: CombatTiming.ripple, seed: 3)
        #expect(plan.contains(ripple))
        let opponentMax = try #require(EncFx.encounter(s)).opponent.hullStrength(s.ruleset)
        let count = 4 + Int(12 * (10.0 / Double(opponentMax)))
        let sparks = CombatEffect(.sparks(on: .opponent, count: count), start: 0.03, duration: CombatTiming.sparks, seed: 3)
        #expect(plan.contains(sparks))
        #expect(!plan.contains { if case .shake = $0.kind { true } else { false } })
        #expect(CombatEffect.end(of: plan) <= CombatTiming.roundBudget)
    }

    @Test("UI-ENC-098 ART-043 ART-044 a heavy hit (≥ 15% of the player's hull) shakes; fleeing and non-attacking types fire one side; misses")
    func heavyHitFleeMiss() throws {
        let s = try EffectFx.before()
        let maxHull = s.commander.ship.hullStrength(s.ruleset)
        let heavy = s.commander.ship.hull - Int((Double(maxHull) * 0.2).rounded(.up))
        let hit = CombatEffectPlanner.plan(record: EffectFx.record(s, events: [EffectFx.round(s, playerHull: heavy, opponentHull: EffectFx.opponentHull(s))]) {
            $0.commander.ship.hull = heavy
        })
        #expect(hit.contains(CombatEffect(.shake(amplitude: 6), start: 0.15, duration: 0.3)))
        #expect(!hit.contains { if case .beam(from: .player, _, _) = $0.kind { true } else { false } }, "fleeing: the player did not fire")
        #expect(CombatEffect.end(of: hit) <= CombatTiming.roundBudget)
        let fleeing = try EffectFx.before(.pirateFlee)
        let miss = CombatEffectPlanner.plan(record: EffectFx.record(fleeing, events: [.playerAttacked,
                                                                                  EffectFx.round(fleeing, playerHull: fleeing.commander.ship.hull,
                                                                                                 opponentHull: EffectFx.opponentHull(fleeing))]))
        #expect(miss == [CombatEffect(.beam(from: .player, weapon: .military, hit: false), start: 0, duration: 0.25, seed: 3)])
    }

    @Test("ART-043 endings: explosions, power-down, escapes and the opponent's arrival")
    func endings() throws {
        let s = try EffectFx.before()
        func kinds(_ events: [GameEvent]) -> [CombatEffect.Kind] { CombatEffectPlanner.plan(record: EffectFx.record(s, events: events)).map(\.kind) }
        #expect(kinds([.opponentDestroyed(.gnat)]) == [.explosion(on: .opponent)])
        #expect(kinds([.playerDestroyed]) == [.explosion(on: .player)])
        #expect(kinds([.bothDestroyed]) == [.explosion(on: .opponent), .explosion(on: .player)])
        #expect(kinds([.opponentDisabled(.gnat)]) == [.powerDown(on: .opponent)])
        #expect(kinds([.playerEscaped(wasHit: false)]) == [.escape(side: .player)])
        #expect(kinds([.opponentEscaped]) == [.escape(side: .opponent)])
        #expect(kinds([.encounterStarted(type: .pirateAttack, opponent: .gnat, clicks: 4, playerCloaked: false)]) == [.arrive(side: .opponent)])
        #expect(CombatEffectPlanner.plan(record: nil).isEmpty)
        #expect(CombatEffectPlanner.opponentAttacks(.policeAttack) && !CombatEffectPlanner.opponentAttacks(.policeInspect))
    }

    @Test("UI-ENC-098 ART-047 ART-048 under Reduce Motion the stage only flashes: no pane offset, no ship movement at 0…0.5 s")
    func reducedMotionStage() throws {
        let s = try EffectFx.before()
        let heavy = s.commander.ship.hull / 2
        let plan = CombatEffectPlanner.plan(record: EffectFx.record(s, events: [.playerAttacked,
                                                                             EffectFx.round(s, playerHull: heavy, opponentHull: 0),
                                                                             .playerEscaped(wasHit: true)]) { $0.commander.ship.hull = heavy })
        #expect(plan.contains { if case .shake = $0.kind { true } else { false } })
        for k in 0...5 {
            let t = Double(k) / 10
            let m = EncounterMotion.make(plan: plan, reduceMotion: true, at: t)
            #expect(m.shake == .zero && m.playerOffset == 0 && m.opponentOffset == 0, "t = \(t)")
            #expect(m.effects.allSatisfy { $0.isFlash })
            let moving = EncounterMotion.make(plan: plan, reduceMotion: false, at: t)
            if k == 2 { #expect(moving.playerOffset != 0 || moving.shake != .zero) }
        }
        let g = EncounterMotion.geometry(CGSize(width: 600, height: 200))
        #expect(g.player.maxX < g.opponent.minX)
    }

    @Test("ART-052 fast scenes use a 30 fps TimelineView; the Bridge planet and map vortices share the ambient clock; paused when inactive")
    func timelines() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SpaceTraderMac")
        func source(_ file: String) throws -> String { try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8) }
        // The game-over scene lives in ArtViews.swift next to the planet portrait.
        for file in ["Art/EncounterStage.swift", "Art/ArtViews.swift", "Art/AchievementArt.swift", "Views/Transit/TransitView.swift"] {
            #expect(try source(file).contains("TimelineView(.animation(minimumInterval: 1.0 / 30"), "\(file)")
        }
        let portraits = try source("Art/ArtViews.swift")
        #expect(portraits.contains("TimelineView(AmbientSchedule(paused: !appearsActive))") && portraits.contains("a11y.reduceMotion"))
        let map = try source("Map/GalaxyMapView.swift")
        #expect(map.contains("TimelineView(AmbientSchedule(paused: !swirl || reduceMotion))"))
        #expect(map.contains("vorticesInOverlay: !reduceMotion && appearsActive"))
    }

    @Test("ART-052 AmbientSchedule: 5 fps on whole multiples of 1/5 s, the same dates for every surface; one still frame when paused")
    func ambientSchedule() {
        #expect(AmbientSchedule.interval == 0.2)
        let a = Date(timeIntervalSinceReferenceDate: 1000.03), b = Date(timeIntervalSinceReferenceDate: 1000.11)
        let fromA = Array(AmbientSchedule(paused: false).entries(from: a, mode: .normal).prefix(4))
        let fromB = Array(AmbientSchedule(paused: false).entries(from: b, mode: .normal).prefix(4))
        #expect(fromA == fromB, "two surfaces started at different times tick on the same dates")
        #expect(abs((fromA.first?.timeIntervalSinceReferenceDate ?? 0) - 1000.2) < 1e-9)
        for (x, y) in zip(fromA, fromA.dropFirst()) { #expect(abs(y.timeIntervalSince(x) - 0.2) < 1e-9) }
        #expect(Array(AmbientSchedule(paused: true).entries(from: a, mode: .normal).prefix(3)) == [a])
        #expect(Array(AmbientSchedule(paused: false).entries(from: a, mode: .lowFrequency).prefix(3)) == [a])
    }

    @Test("ART-057 the built app carries the icon: AppIcon.icns, Assets.car and CFBundleIconName = AppIcon")
    func builtIcon() throws {
        let resources = try #require(Bundle.main.resourceURL)
        #expect(FileManager.default.fileExists(atPath: resources.appendingPathComponent("AppIcon.icns").path))
        #expect(FileManager.default.fileExists(atPath: resources.appendingPathComponent("Assets.car").path))
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String == "AppIcon")
    }
}
