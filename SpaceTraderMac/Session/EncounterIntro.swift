// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-016: the two header lines of the Encounter view, in the C# wording (`EncounterTextInitial`,
/// `EncounterActionInitial`).
struct EncounterIntro: Equatable, Sendable {
    /// "At 7 clicks from Sol you encounter a pirate gnat."
    var headline: String
    /// "Your opponent attacks."
    var action: String

    /// The intro for an `encounterStarted` event (nil for any other event). The destination is the trip's.
    static func make(started: GameEvent, state: GameState) -> EncounterIntro? {
        guard case let .encounterStarted(type, opponent, clicks, cloaked) = started else { return nil }
        let destination = Names.system(state.transitPreview?.destination ?? state.warpSystem, in: state)
        let ship = String(localized: Names.ship(opponent)).lowercased()
        let headline = String(localized: "At \(clicksText(clicks)) from \(destination) you encounter \(pretext(type, opponent: opponent)) \(ship).")
        return EncounterIntro(headline: headline, action: actionLine(type, opponent: opponent, cloaked: cloaked))
    }

    /// The intro of the encounter in `state` (a game loaded mid-encounter, UI-ENC-024).
    static func resumed(state: GameState) -> EncounterIntro? {
        guard case let .encounter(enc) = state.phase else { return nil }
        let cloaked = state.commander.ship.has(.cloakingDevice)
        return make(started: .encounterStarted(type: enc.type, opponent: enc.opponent.type, clicks: enc.clicks, playerCloaked: cloaked),
                    state: state)
    }

    /// C# `Functions.Multiples(clicks, "click")`.
    static func clicksText(_ clicks: Int) -> String {
        clicks == 1 ? String(localized: "1 click") : String(localized: "\(clicks) clicks")
    }

    /// C# `EncounterTextInitial` pretexts (Strings.cs `EncounterPretext*`). Types that are never initial use the noun
    /// of their family so a resumed game never shows an empty pretext.
    static func pretext(_ type: EncounterType, opponent: ShipType) -> String {
        switch type {
        case .bottleGood, .bottleOld: String(localized: "a floating")
        case .dragonflyAttack, .dragonflyIgnore, .scarabAttack, .scarabIgnore: String(localized: "a stolen")
        case .captainAhab: String(localized: "the famous Captain Ahab in a")
        case .captainConrad: String(localized: "the famous Captain Conrad in a")
        case .captainHuie: String(localized: "the famous Captain Huie in a")
        case .marieCeleste: String(localized: "a drifting")
        // C# maps the post-Marie police to the plain police pretext (`EncounterPretextMariePolice` is unused).
        case .marieCelestePolice, .policeAttack, .policeFlee, .policeIgnore, .policeInspect, .policeSurrender, .policeDisabled:
            String(localized: "a police")
        case .pirateAttack, .pirateFlee, .pirateIgnore, .pirateDisabled, .pirateSurrender:
            if opponent == .mantis { String(localized: "an alien") } else { String(localized: "a pirate") }
        case .scorpionAttack, .scorpionIgnore: String(localized: "the kidnappers in a")
        case .spaceMonsterAttack, .spaceMonsterIgnore: String(localized: "a horrifying")
        case .traderBuy, .traderFlee, .traderIgnore, .traderSell, .traderAttack, .traderDisabled, .traderSurrender:
            String(localized: "a trader")
        case .famousCaptainAttack, .famousCaptDisabled: String(localized: "a famous captain in a")
        }
    }

    /// C# `EncounterActionInitial` (Strings.cs `EncounterText*`); types that are never initial show their stance.
    static func actionLine(_ type: EncounterType, opponent: ShipType, cloaked: Bool) -> String {
        switch type {
        case .bottleGood, .bottleOld: String(localized: "It appears to be a rare bottle of Captain Marmoset's Skill Tonic!")
        case .captainAhab, .captainConrad, .captainHuie: String(localized: "The Captain requests a brief meeting with you.")
        case .dragonflyAttack, .pirateAttack, .policeAttack, .scarabAttack, .scorpionAttack, .spaceMonsterAttack:
            String(localized: "Your opponent attacks.")
        case .dragonflyIgnore, .pirateIgnore, .policeIgnore, .scarabIgnore, .scorpionIgnore, .spaceMonsterIgnore, .traderIgnore:
            if cloaked { String(localized: "It doesn't notice you.") } else { String(localized: "It ignores you.") }
        case .marieCeleste: String(localized: "The Marie Celeste appears to be completely abandoned.")
        case .marieCelestePolice:
            String(localized: "\"We know you removed illegal goods from the Marie Celeste. You must give them up at once!\"")
        case .pirateFlee, .policeFlee, .traderFlee: String(localized: "Your opponent is fleeing.")
        case .policeInspect: String(localized: "The police summon you to submit to an inspection.")
        case .policeSurrender: String(localized: "The police hail they want you to surrender.")
        case .traderBuy, .traderSell: String(localized: "You are hailed with an offer to trade goods.")
        case .famousCaptainAttack, .famousCaptDisabled, .policeDisabled, .pirateDisabled, .pirateSurrender, .traderAttack,
             .traderDisabled, .traderSurrender:
            CombatLog.stance(type: type, opponent: opponent, disabled: CombatLog.isDisabledType(type),
                             oppFleeing: CombatLog.isFleeOrSurrender(type))
        }
    }
}
