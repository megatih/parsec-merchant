// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// Localized texts of the arrival report and the report sheets (UI-ENC §8). Report-sheet sections reuse the C# alert
/// titles and messages (Form_Alert.cs) of the ALR rows they present.
enum ArrivalText {
    private static func s(_ r: LocalizedStringResource) -> String { String(localized: r) }
    private static func n(_ v: Int) -> String { v.formatted() }

    static func sectionTitle(_ kind: ArrivalSectionKind) -> String {
        switch kind {
        case .encounters: s("Encounters")
        case .news: s("News")
        case .costs: s("Departure costs")
        case .service: s("Automatic repairs and fuel")
        case .tribbles: s("Tribbles")
        case .reactor: s("Reactor")
        case .debt: s("Debt")
        case .police: s("Police record")
        case .quests: s("Quest progress")
        }
    }

    /// One encounter row: "Pirate Gnat, 7 clicks out: destroyed it (bounty 250 cr.)".
    static func encounterLine(_ e: EncounterSummary) -> String {
        let who = s(Names.badge(e.badge))
        let ship = s(Names.ship(e.opponent))
        return s("\(who) \(ship), \(e.clicks) clicks out: \(outcome(e.outcome))")
    }

    static func outcome(_ o: EncounterOutcome) -> String {
        switch o {
        case let .destroyed(type, bounty):
            if let bounty { return s("destroyed the \(s(Names.ship(type))) (bounty \(n(bounty)) cr.)") }
            return s("destroyed the \(s(Names.ship(type)))")
        case .disabled: return s("disabled it")
        case let .escaped(wasHit): return wasHit ? s("escaped, but took a hit") : s("escaped")
        case .opponentEscaped: return s("it got away")
        case let .plundered(items):
            let parts = TradeItemType.allCases.compactMap { item in items[item].map { "\($0) \(s(Names.item(item)))" } }
            return s("plundered \(parts.formatted(.list(type: .and)))")
        case let .traded(direction, item, quantity, total):
            return direction == .traderSells ? s("bought \(quantity) \(s(Names.item(item))) for \(n(total)) cr.")
                : s("sold \(quantity) \(s(Names.item(item))) for \(n(total)) cr.")
        case let .bribed(amount): return s("paid a bribe of \(n(amount)) cr.")
        case let .fined(amount): return s("fined \(n(amount)) cr.")
        case .inspectedClean: return s("passed the inspection")
        case .yielded: return s("yielded to the police")
        case .arrested: return s("arrested")
        case let .raided(units): return units > 0 ? s("pirates took \(units) units of cargo") : s("raided by pirates")
        case .artifactSurrendered: return s("surrendered the artifact")
        case let .drank(good): return good ? s("drank the tonic; it did you good") : s("drank the strange brew")
        case let .trained(skill): return s("trained your \(s(Names.skill(skill))) skill")
        case .escapePod: return s("escaped in the pod")
        case .killed: return s("your ship was destroyed")
        case .passed: return s("no incident")
        }
    }

    /// ALR-168 (C# `TravelUneventfulTrip`).
    static var uneventfulTrip: String { s("Uneventful trip.") }

    /// UI-ENC-012 / ALR-165: the fabric rip line (also the Transit banner).
    static func fabricRip(_ system: String) -> String {
        s("A fracture in the space-time fabric pulls you to \(system)!")
    }

    /// UI-ENC-055: "Arrived at Rhymus · 1 encounter · −120 cr".
    static func summary(system: String, encounters: Int, cashChange: Int) -> String {
        let money = cashChange == 0 ? s("±0 cr") : cashChange > 0 ? s("+\(n(cashChange)) cr") : s("−\(n(-cashChange)) cr")
        return s("Arrived at \(system) · \(encounters) encounters · \(money)")
    }

    static func cost(_ kind: CostKind, _ amount: Int) -> String {
        switch kind {
        case .mercenaries: s("Mercenaries: \(n(amount)) cr.")
        case .insurance: s("Insurance: \(n(amount)) cr.")
        case .interest: s("Interest: \(n(amount)) cr.")
        case .wormholeTax: s("Wormhole tax: \(n(amount)) cr.")
        case .total: s("Total: \(n(amount)) cr.")
        }
    }

    enum CostKind { case mercenaries, insurance, interest, wormholeTax, total }

    static func policeRecord(from: PoliceRecordType, to: PoliceRecordType) -> String {
        s("Police record: \(s(Names.policeRecord(from))) → \(s(Names.policeRecord(to)))")
    }

    static func reputation(from: ReputationType, to: ReputationType) -> String {
        s("Reputation: \(s(Names.reputation(from))) → \(s(Names.reputation(to)))")
    }

    static func questAdded(_ title: String) -> String { s("New: \(title)") }
    static func questRemoved(_ title: String) -> String { s("Closed: \(title)") }

    /// UI-ENC-063: the teaser of an unpaid paper.
    static func newspaperPrice(_ cost: Int) -> String { s("The local paper costs \(n(cost)) cr.") }

    /// ALR-132: the fuel-starvation warning status (C# `StatusReactorDate − 4`).
    static let fuelStarvationStatus = 16

    /// A trip event's report line: the C# reactor warnings (ALR-131…133), comm lines (UI-ENC-066), else the feed text.
    static func eventLine(_ e: GameEvent, state: GameState) -> String {
        switch e {
        case let .reactorWarning(status):
            if status == ReactorStatus.temperatureWarning {
                return s("The Ion Reactor is smoking and making loud noises. The display warns that the core is close to the melting temperature.")
            }
            if status >= Self.fuelStarvationStatus {
                return s("The Ion Reactor is emitting a shrill whine, and it's shaking. The display indicates that it is suffering from fuel starvation.")
            }
            return s("You notice the Ion Reactor has begun to consume fuel rapidly. In a single day, it has burned up nearly half a bay of fuel!")
        case .uneventfulTrip:
            return uneventfulTrip
        default:
            return FeedText.text(for: .event(e), state: state)
        }
    }
}

/// The C# alert texts of the report-sheet sections (ALR rows; Form_Alert.cs).
enum ReportText {
    private static func s(_ r: LocalizedStringResource) -> String { String(localized: r) }

    /// One report section per ALR row: its C# title and message.
    static func section(_ alert: ReportAlert) -> ReportSection {
        switch alert {
        case .arrested:
            return ReportSection(title: s("Arrested"),
                                 lines: [s("You are arrested and taken to the space station, where you are brought before a court of law.")])
        case let .convicted(term, fine):
            let days = s("\(term) days")
            let credits = s("\(fine.formatted()) credits")
            return ReportSection(title: s("Convicted"), lines: [s("You are convicted to \(days) in prison and a fine of \(credits).")])
        case .hiddenCompartmentsRemoved:
            return ReportSection(title: s("Hidden Compartments Removed"),
                                 // swiftlint:disable:next line_length
                                 lines: [s("When your ship is impounded, the police go over it with a fine-toothed comb. You hidden compartments are found and removed.")])
        case .reactorConfiscated:
            return ReportSection(title: s("Police Confiscate Reactor"),
                                 lines: [s("The Police confiscate the Ion reactor as evidence of your dealings with unsavory characters.")])
        case .sculptureConfiscated:
            return ReportSection(title: s("Police Confiscate Sculpture"),
                                 lines: [s("The Police confiscate the stolen sculpture and return it to its rightful owner.")])
        case .wildArrested:
            return ReportSection(title: s("Wild Arrested"), lines: [s("Jonathan Wild is arrested, and taken away to stand trial.")])
        case .illegalGoodsImpounded:
            return ReportSection(title: s("Illegal Goods Impounded"), lines: [s("The police also impound all of the illegal goods you have on board.")])
        case .insuranceLost:
            return ReportSection(title: s("Insurance Lost"), lines: [s("Since you cannot pay your insurance while you're in prison, it is retracted.")])
        case .mercenariesLeave:
            return ReportSection(title: s("Mercenaries Leave"), lines: [s("Any mercenaries who were traveling with you have left.")])
        case .jarekTakenHome:
            return ReportSection(title: s("Jarek Taken Home"), lines: [s("The Space Corps decides to give ambassador Jarek a lift home to Devidia.")])
        case .princessTakenHome:
            return ReportSection(title: s("Princess Taken Home"),
                                 lines: [s("The Space Corps decides to give the Princess a ride home to Galvon since you obviously weren't up to the task.")])
        case .antidoteTaken:
            return ReportSection(title: s("Antidote Taken"),
                                 lines: [s("The Space Corps removed the antidote for Japori from your ship and delivered it, fulfilling your assignment.")])
        case .shipSold:
            return ReportSection(title: s("Ship Sold"), lines: [s("Because you don't have the credits to pay your fine, your ship is sold.")])
        case .tribblesRemoved:
            return ReportSection(title: s("Tribbles Removed"), lines: [s("The tribbles were sold with your ship.")])
        case .fleaBuilt:
            return ReportSection(title: s("Flea Built"), lines: [s("In 3 days and with 500 credits, you manage to convert your pod into a Flea.")])
        case .escapePodActivated:
            return ReportSection(title: s("Escape Pod Activated"),
                                 // swiftlint:disable:next line_length
                                 lines: [s("Just before the final demise of your ship, your escape pod gets activated and ejects you. After a few days, the Space Corps picks you up and drops you off at a nearby space port.")])
        case .sculptureSaved:
            return ReportSection(title: s("Sculpture Saved"),
                                 lines: [s("On your way to the escape pod, you grab the stolen sculpture. Oh well, at least you saved something.")])
        case .reactorDestroyed:
            return ReportSection(title: s("Reactor Destroyed"),
                                 lines: [s("The destruction of your ship was made much more spectacular by the added explosion of the Ion Reactor.")])
        case .tribblesKilled:
            return ReportSection(title: s("Tribbles Killed"), lines: [s("Your tribbles all died in the explosion.")])
        case let .antidoteDestroyed(system):
            return ReportSection(title: s("Antidote Destroyed"),
                                 lines: [s("The antidote for the Japori system has been destroyed with your ship. You should return to \(system) and get some more.")])
        case .artifactLost:
            return ReportSection(title: s("Artifact Lost"), lines: [s("The alien artifact has been lost in the wreckage of your ship.")])
        case let .insurancePayoff(amount):
            return ReportSection(title: s("Insurance"),
                                 lines: [s("Since your ship was insured, the bank pays you the total worth of the destroyed ship."),
                                         s("Insurance paid \(amount.formatted()) cr.")])
        case .reactorMeltdown:
            return ReportSection(title: s("Reactor Meltdown!"),
                                 lines: [s("Just as you approach the docking bay, the reactor explodes into a huge radioactive fireball!")])
        case .shipDestroyed:
            return ReportSection(title: s("Ship Destroyed"), lines: [s("Your ship was destroyed.")])
        case .reactorWarningTemperature:
            return ReportSection(title: s("Reactor Warning"),
                                 // swiftlint:disable:next line_length
                                 lines: [s("The Ion Reactor is smoking and making loud noises. The display warns that the core is close to the melting temperature.")])
        }
    }
}
