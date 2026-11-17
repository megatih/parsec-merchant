// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-074: the narrative sheet's offer page, pure over the state and the engine's special-event preview.
struct NarrativeOffer: Equatable, Sendable {
    enum Vignette: String, Sendable {
        case planet, ship
    }

    var type: SpecialEventType
    var title: String
    var story: String
    /// "Costs N cr." / "You receive N cr." / nil for a free event.
    var priceLine: String?
    var messageOnly: Bool
    var vignette: Vignette
    /// Why Accept is disabled (UI-ENC-075), from `specialEventPreview.blocker`.
    var blocker: CommandError?

    var canAccept: Bool { blocker == nil }
}

enum NarrativeModel {
    /// The offer page of `type`. `preview` is `GameEngine.specialEventPreview` when it is this type's.
    static func offer(type: SpecialEventType, state: GameState, preview: SpecialEventPreview?) -> NarrativeOffer {
        let spec = state.specialEventSpec(type)
        let matching = preview?.type == type ? preview : nil
        let price = matching?.price ?? spec?.price ?? 0
        return NarrativeOffer(type: type, title: String(localized: SpecialEventText.title(type)),
                              story: String(localized: SpecialEventText.story(type)), priceLine: priceLine(price),
                              messageOnly: matching?.messageOnly ?? spec?.messageOnly ?? false, vignette: vignette(type),
                              blocker: matching?.blocker)
    }

    static func priceLine(_ price: Int) -> String? {
        if price > 0 { return String(localized: "Costs \(price.formatted()) cr.") }
        if price < 0 { return String(localized: "You receive \((-price).formatted()) cr.") }
        return nil
    }

    /// UI-ENC-073: the first sentence of the story, or its first 160 characters followed by "…".
    static func excerpt(_ story: String, limit: Int = 160) -> String {
        var end: String.Index?
        var i = story.startIndex
        while i < story.endIndex {
            let next = story.index(after: i)
            if ".!?".contains(story[i]), next == story.endIndex || story[next] == " " {
                end = next
                break
            }
            i = next
        }
        let sentence = String(story[..<(end ?? story.endIndex)])
        if sentence.count <= limit { return sentence }
        return String(story.prefix(limit)) + "…"
    }

    /// The vignette placeholder: a ship for the ship-chase chains, else the planet.
    static func vignette(_ type: SpecialEventType) -> NarrativeOffer.Vignette {
        switch type {
        case .dragonfly, .dragonflyBaratas, .dragonflyDestroyed, .dragonflyMelina, .dragonflyRegulas, .dragonflyShield, .scarab,
             .scarabDestroyed, .scarabUpgradeHull, .spaceMonster, .spaceMonsterKilled, .princess, .princessCentauri,
             .princessInthara, .princessQonos:
            .ship
        case .artifact, .artifactDelivery, .cargoForSale, .eraseRecord, .experiment, .experimentFailed, .experimentStopped,
             .gemulon, .gemulonFuel, .gemulonInvaded, .gemulonRescued, .japori, .japoriDelivery, .jarek, .jarekGetsOut, .lottery,
             .moon, .moonRetirement, .reactor, .reactorDelivered, .reactorLaser, .skill, .tribble, .tribbleBuyer, .wild,
             .wildGetsOut, .sculpture, .sculptureDelivered, .sculptureHiddenBays, .princessQuantum, .princessReturned:
            .planet
        }
    }
}

/// UI-ENC-078: the narrative result page for the ALR narrative rows, worded as the C# alerts (Form_Alert.cs).
enum NarrativeText {
    private static func s(_ r: LocalizedStringResource) -> String { String(localized: r) }

    /// The result page for an accepted step's events, or nil when its events go only to the feed.
    static func result(for events: [GameEvent], before: GameState, after: GameState) -> NarrativeResult? {
        for e in events {
            switch e {
            case let .specialEventRefused(type, reason):
                return NarrativeResult(type: type, title: s(SpecialEventText.title(type)), message: ReasonText.string(for: reason))
            case let .sealedCanisters(item):
                // ALR-163.
                let contents = s("The canisters contain \(s(Names.item(item))).")
                return NarrativeResult(type: .cargoForSale, title: s("Sealed Canisters"),
                                       message: s("You bought the sealed canisters and put them in your cargo bays.") + " " + contents)
            case let .specialEventCompleted(type):
                if let page = completed(type, before: before, after: after) { return page }
            default:
                continue
            }
        }
        return nil
    }

    /// The special event types whose completion has no result page (feed only, UI-ENC-077/079).
    static let feedOnly: Set<SpecialEventType> = Set(SpecialEventType.allCases.filter { !hasResultPage($0) })

    static func hasResultPage(_ type: SpecialEventType) -> Bool {
        switch type {
        case .japori, .gemulonFuel, .sculptureHiddenBays, .dragonflyShield, .reactorLaser, .princessQuantum, .reactor,
             .scarabUpgradeHull, .eraseRecord, .moon, .jarek, .princessQonos, .wild, .skill, .tribbleBuyer, .tribble:
            true
        case .artifact, .artifactDelivery, .cargoForSale, .dragonfly, .dragonflyBaratas, .dragonflyDestroyed, .dragonflyMelina,
             .dragonflyRegulas, .experiment, .experimentFailed, .experimentStopped, .gemulon, .gemulonInvaded, .gemulonRescued,
             .japoriDelivery, .jarekGetsOut, .lottery, .moonRetirement, .reactorDelivered, .scarab, .scarabDestroyed,
             .spaceMonster, .spaceMonsterKilled, .wildGetsOut, .sculpture, .sculptureDelivered, .princess, .princessCentauri,
             .princessInthara, .princessReturned:
            false
        }
    }

    static func completed(_ type: SpecialEventType, before: GameState, after: GameState) -> NarrativeResult? {
        func page(_ title: LocalizedStringResource, _ message: String) -> NarrativeResult {
            NarrativeResult(type: type, title: s(title), message: message)
        }
        func passenger(_ crewID: Int) -> NarrativeResult {
            let name = Names.crew(crewID, in: after)
            return page("Passenger On Board",
                        s("You have taken \(name) on board. While on board \(name) will lend you expertise, but may stop helping if the journey takes too long."))
        }
        switch type {
        // ALR-002.
        case .japori: return page("Antidote", s("Ten of your cargo bays now contain antidote for the Japori system."))
        // ALR-083, 084, 086, 087, 089: equipment received.
        case .gemulonFuel: return page("Fuel Compactor", s("You now have a fuel compactor installed on your ship."))
        case .sculptureHiddenBays:
            return page("Hidden Compartments",
                        // swiftlint:disable:next line_length
                        s("You now have hidden compartments equivalent to 5 extra cargo bays installed in your ship. Police won't find illegal cargo hidden in these compartments."))
        case .dragonflyShield: return page("Lightning Shield", s("You now have one lightning shield installed on your ship."))
        case .reactorLaser: return page("Morgan's Laser", s("You now have Henry Morgan's special laser installed on your ship."))
        case .princessQuantum: return page("Quantum Disruptor", s("You now have one quantum disruptor installed on your ship."))
        // ALR-129.
        case .reactor:
            return page("Reactor", s("Five of your cargo bays now contain the unstable Ion Reactor, and ten of your bays contain enriched fuel."))
        // ALR-149, 150, 153.
        case .scarabUpgradeHull: return page("Hull Upgraded", s("Technicians spend the day retrofitting the hull of your ship."))
        case .eraseRecord: return page("Clean Record", s("The hacker resets your police record to Clean."))
        case .moon: return page("Moon Bought", s("You bought a moon in the Utopia system. Go there to claim it."))
        // ALR-162 (and ALR-184 for Wild with the sculpture aboard).
        case .jarek: return passenger(CrewID.jarek)
        case .princessQonos: return passenger(CrewID.princess)
        case .wild:
            var p = passenger(CrewID.wild)
            if after.sculptureOnBoard {
                // swiftlint:disable:next line_length
                p.message += "\n\n" + s("Jonathan Wild sees the stolen sculpture. \"Wow, I only know of one of these left in the whole Universe!\" he exclaims, \"Geurge Locas must be beside himself with it being stolen.\" He seems very impressed with you, which makes you feel much better about the item your delivering.")
            }
            return p
        // ALR-164: the skill named from the before/after difference.
        case .skill:
            var message = s("The alien increases one of your skills.")
            let old = before.mercenaries[CrewID.commander], new = after.mercenaries[CrewID.commander]
            if let skill = SkillType.allCases.first(where: { new.skill($0) > old.skill($0) }) {
                message += " " + s("Your \(s(Names.skill(skill))) skill increased.")
            }
            return page("Skill Increase", message)
        // ALR-171, 175.
        case .tribbleBuyer:
            return page("No More Tribbles", s("The alien uses his alien technology to beam over your whole collection of tribbles to his ship."))
        case .tribble: return page("A Tribble", s("You are now the proud owner of a little, cute, furry tribble."))
        // Feed only (the event's own story was the offer page, or the result is a quest step without an alert).
        case .artifact, .artifactDelivery, .cargoForSale, .dragonfly, .dragonflyBaratas, .dragonflyDestroyed, .dragonflyMelina,
             .dragonflyRegulas, .experiment, .experimentFailed, .experimentStopped, .gemulon, .gemulonInvaded, .gemulonRescued,
             .japoriDelivery, .jarekGetsOut, .lottery, .moonRetirement, .reactorDelivered, .scarab, .scarabDestroyed,
             .spaceMonster, .spaceMonsterKilled, .wildGetsOut, .sculpture, .sculptureDelivered, .princess, .princessCentauri,
             .princessInthara, .princessReturned:
            return nil
        }
    }
}
