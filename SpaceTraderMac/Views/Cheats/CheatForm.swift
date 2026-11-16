// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// The cheat console's form (CHEAT-013): every code of the ruleset's set, with fields pre-filled from the game.
nonisolated struct CheatForm: Equatable, Sendable {
    /// The codes the console offers (the C# Find codes, or the Palm codes and Cheat form). Raw values are the code words.
    enum Code: String, CaseIterable, Sendable {
        case scratch = "Scratch", iou = "IOU", fame = "Fame", rapSheet = "RapSheet", deLorean = "DeLorean"
        case juice = "Juice", skin = "Skin", varmints = "Varmints", indemnity = "Indemnity"
        case bazaar = "Bazaar", rarity = "Rarity", lEngle = "L'Engle"
        case cover = "Cover", iron = "Iron", tool = "Tool", posse = "Posse", swag = "Swag"
        case ice = "Ice", status = "Status", knack = "Knack", go = "Go"
        case diamond = "Diamond", energize = "Energize", lifeBoat = "LifeBoat", yellow = "Yellow", planB = "PlanB", test = "Test"
        case events = "Events", eventsReset = "Events Reset", statusList = "Status List", monsterListing = "Monster.com"
        case moolah = "Moolah", palmGo = "Palm Go", quests = "Quests", commanderStatus = "Cheat Form"

        var set: CheatSet {
            switch self {
            case .moolah, .palmGo, .quests, .commanderStatus: .palm
            default: .windows
            }
        }

        /// The fields the code uses.
        var shape: Shape {
            switch self {
            case .scratch, .iou, .fame, .rapSheet, .deLorean, .juice, .skin, .varmints, .indemnity, .bazaar, .rarity, .lEngle:
                .number
            case .cover, .iron, .tool, .posse, .swag: .twoNumbers
            case .ice: .kill
            case .status: .quest
            case .knack: .knack
            case .go, .palmGo: .text
            case .commanderStatus: .palmForm
            case .diamond, .energize, .lifeBoat, .yellow, .planB, .test, .events, .eventsReset, .statusList, .monsterListing, .moolah,
                 .quests:
                .none
            }
        }
    }

    enum Shape: Sendable { case none, number, twoNumbers, kill, quest, knack, text, palmForm }

    /// Field names used for identifiers (`cheatConsole.field.<name>`).
    static let fieldNames = ["number", "second", "text", "kill", "quest", "skills", "credits", "debt", "reputation", "policeRecord",
                             "policeNegative", "moon", "lightningShield", "fuelCompactor", "morgansLaser", "singularity"]

    var code: Code
    var number = 0
    var second = 0
    var text = ""
    var kill: KillKind = .pirate
    var quest: QuestKey = .artifact
    var skills: [Int] = [1, 1, 1, 1]
    var palm = PalmCheatForm()

    /// The codes of a ruleset's cheat set, in console order.
    static func codes(for set: CheatSet) -> [Code] { Code.allCases.filter { $0.set == set } }

    /// A form for `code` with its numeric fields pre-filled with the game's current values.
    static func prefilled(_ code: Code, state: GameState) -> CheatForm {
        var f = CheatForm(code: code)
        let c = state.commander
        switch code {
        case .scratch: f.number = c.cash
        case .iou: f.number = c.debt
        case .fame: f.number = c.reputationScore
        case .rapSheet: f.number = c.policeRecordScore
        case .deLorean: f.number = c.days
        case .juice: f.number = c.ship.fuel
        case .skin: f.number = c.ship.hull
        case .varmints: f.number = c.ship.tribbles
        case .indemnity: f.number = c.noClaim
        case .bazaar: f.number = state.chanceOfTradeInOrbit
        case .rarity: f.number = state.chanceOfVeryRareEncounter
        case .lEngle: f.number = state.quests.fabricRipProbability
        case .swag: f.second = c.ship.cargo.first ?? 0
        case .ice: f.number = c.kills.pirates
        case .knack:
            f.number = 1
            if state.mercenaries.indices.contains(1) { f.skills = state.mercenaries[1].skills }
        case .commanderStatus:
            f.palm = PalmCheatForm(credits: c.cash, debt: c.debt, reputation: c.reputationScore,
                                   policeRecordMagnitude: abs(c.policeRecordScore), policeRecordNegative: c.policeRecordScore < 0,
                                   moon: state.quests.moon > 0, lightningShield: false, fuelCompactor: false,
                                   morgansLaser: false, singularity: state.quests.canSuperWarp)
        default: break
        }
        return f
    }

    // The engine command of the form.
    // swiftlint:disable:next cyclomatic_complexity
    func cheatCode() -> CheatCode {
        switch code {
        case .scratch: .scratch(number)
        case .iou: .iou(number)
        case .fame: .fame(number)
        case .rapSheet: .rapSheet(number)
        case .deLorean: .deLorean(number)
        case .juice: .juice(number)
        case .skin: .skin(number)
        case .varmints: .varmints(number)
        case .indemnity: .indemnity(number)
        case .bazaar: .bazaar(number)
        case .rarity: .rarity(number)
        case .lEngle: .lEngle(number)
        case .cover: .cover(slot: number, shield: second)
        case .iron: .iron(slot: number, weapon: second)
        case .tool: .tool(slot: number, gadget: second)
        case .posse: .posse(slot: number, mercenary: second)
        case .swag: .swag(item: number, quantity: second)
        case .ice: .ice(kill, number)
        case .status: .status(quest, number)
        case .knack: .knack(mercenary: number, skills: skills.map { Optional($0) })
        case .go: .go(text)
        case .palmGo: .palmGo(text)
        case .diamond: .diamond
        case .energize: .energize
        case .lifeBoat: .lifeBoat
        case .yellow: .yellow
        case .planB: .planB
        case .test: .test
        case .events: .events
        case .eventsReset: .eventsReset
        case .statusList: .statusList
        case .monsterListing: .monsterListing
        case .moolah: .moolah
        case .quests: .quests
        case .commanderStatus: .palmCheatForm(palm)
        }
    }
}
