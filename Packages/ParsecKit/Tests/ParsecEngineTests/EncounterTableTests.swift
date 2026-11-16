// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// Table 6.1 of docs/specs/ENC.md: actions and the safe Return default per encounter type.
enum EncounterTable61 {
    static let rows: [EncounterType: (actions: [EncounterAction], fallback: EncounterAction?)] = [
        .bottleGood: ([.drink, .ignore], .ignore),
        .bottleOld: ([.drink, .ignore], .ignore),
        .captainAhab: ([.attack, .ignore, .meet], .ignore),
        .captainConrad: ([.attack, .ignore, .meet], .ignore),
        .captainHuie: ([.attack, .ignore, .meet], .ignore),
        .dragonflyAttack: ([.attack, .flee], .flee),
        .dragonflyIgnore: ([.attack, .ignore], .ignore),
        .famousCaptainAttack: ([.attack, .flee], .flee),
        .famousCaptDisabled: ([.attack, .ignore], .ignore),
        .marieCeleste: ([.board, .ignore], .ignore),
        .marieCelestePolice: ([.attack, .flee, .yield, .bribe], .yield),
        .pirateAttack: ([.attack, .flee, .surrender], .flee),
        .pirateIgnore: ([.attack, .ignore], .ignore),
        .pirateFlee: ([.attack, .ignore], .ignore),
        .pirateSurrender: ([.attack, .plunder], nil),
        .pirateDisabled: ([.attack, .plunder], .plunder),
        .policeAttack: ([.attack, .flee, .surrender], .flee),
        .policeIgnore: ([.attack, .ignore], .ignore),
        .policeFlee: ([.attack, .ignore], .ignore),
        .policeSurrender: ([.attack, .flee, .surrender], .flee),
        .policeDisabled: ([.attack, .ignore], .ignore),
        .policeInspect: ([.attack, .flee, .submit, .bribe], .submit),
        .scarabAttack: ([.attack, .flee, .surrender], .flee),
        .scarabIgnore: ([.attack, .ignore], .ignore),
        .scorpionAttack: ([.attack, .flee], .flee),
        .scorpionIgnore: ([.attack, .ignore], .ignore),
        .spaceMonsterAttack: ([.attack, .flee], .flee),
        .spaceMonsterIgnore: ([.attack, .ignore], .ignore),
        .traderAttack: ([.attack, .flee], .flee),
        .traderIgnore: ([.attack, .ignore], .ignore),
        .traderFlee: ([.attack, .ignore], .ignore),
        .traderSurrender: ([.attack, .plunder], nil),
        .traderDisabled: ([.attack, .plunder], nil),
        .traderBuy: ([.attack, .ignore, .trade], .ignore),
        .traderSell: ([.attack, .ignore, .trade], .ignore),
    ]

    /// The table's own actions (excluding the meta actions stop, autoRepeat and resolve).
    static let tableActions: [EncounterAction] = [.attack, .flee, .surrender, .bribe, .submit, .yield, .ignore, .plunder, .trade, .board, .drink, .meet]
}

@Suite("ENC §6.1: action sets per encounter type")
struct EncounterTableTests {
    @Test("ENC-130 actions per type are exactly table 6.1; any other action is rejected with .encounterActionUnavailable and no state change",
          arguments: EncounterType.allCases)
    func actionSet(_ type: EncounterType) throws {
        #expect(EncounterTable61.rows.count == 35)
        let row = try #require(EncounterTable61.rows[type])
        #expect(type.actions == row.actions)
        for action in EncounterTable61.tableActions where !row.actions.contains(action) {
            var e = EncSpec.encounter(type)
            let before = e.state
            let r = e.perform(.encounter(action), acknowledging: Set(WarningID.allCases))
            #expect(r.rejection == .encounterActionUnavailable, "\(type) \(action)")
            #expect(e.state == before)
        }
    }

    @Test("ENC-131 stop (Interrupt) is available iff continueAttacking or continueFleeing, in addition to the type's actions",
          arguments: EncounterType.allCases)
    func stopAvailability(_ type: EncounterType) throws {
        var idle = EncSpec.encounter(type)
        #expect(idle.perform(.encounter(.stop)).rejection == .encounterActionUnavailable)
        #expect(try #require(idle.encounterPreview).canStop == false)
        for flag in [true, false] {
            var e = EncSpec.encounter(type)
            var enc = try #require(EncSpec.current(e))
            enc.continueAttacking = flag
            enc.continueFleeing = !flag
            e.state.phase = .encounter(enc)
            #expect(try #require(e.encounterPreview).canStop)
            let r = e.perform(.encounter(.stop))
            #expect(r.rejection == nil)
            let after = try #require(EncSpec.current(e))
            #expect(!after.continueAttacking && !after.continueFleeing && after.type == type)
        }
    }

    @Test("ENC-132 the preview's defaultAction is the Default column of table 6.1 (nil for none) and is always an available action",
          arguments: EncounterType.allCases)
    func defaultAction(_ type: EncounterType) throws {
        let row = try #require(EncounterTable61.rows[type])
        #expect(type.defaultAction == row.fallback)
        let preview = try #require(EncSpec.encounter(type).encounterPreview)
        #expect(preview.defaultAction == row.fallback)
        if let d = preview.defaultAction { #expect(row.actions.contains(d)) }
        // Never a destructive choice: no Attack, Surrender or Bribe; no Flee from an inspection or customs.
        #expect(![EncounterAction.attack, .surrender, .bribe].contains(preview.defaultAction))
        if type == .policeInspect || type == .marieCelestePolice { #expect(preview.defaultAction != .flee) }
    }
}
