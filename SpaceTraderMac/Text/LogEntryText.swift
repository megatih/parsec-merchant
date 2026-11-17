// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// LOG-023: localized text of every log entry kind (an exhaustive switch; `EventText` wording where the event already
/// has one).
@MainActor
enum LogEntryText {
    private static func n(_ v: Int) -> String { v.formatted() }
    private static func s(_ r: LocalizedStringResource) -> String { String(localized: r) }

    static func text(for entry: LogEntry, journal: GameJournal, state: GameState) -> String {
        s(resource(for: entry.kind, state: state))
    }

    static func resource(for kind: LogEntryKind, state: GameState) -> LocalizedStringResource {
        func sys(_ i: Int) -> String { Names.system(i, in: state) }
        switch kind {
        case let .journalStarted(start):
            return start.origin == .newGame
                ? "The log begins at \(sys(start.startSystem)) (\(s(Names.ruleset(start.rulesetID))), \(s(Names.difficulty(start.difficulty))))."
                : "The log resumes at \(sys(start.startSystem)); earlier entries are unknown."
        case .cheatsEnabled: return "Cheats were used. Achievements are disabled for this game."
        case let .gameEnded(end, score): return "\(s(Names.ending(end))) Final score \(ScoreText.score(score, ruleset: state.ruleset))."
        case let .achievementUnlocked(id): return "Achievement unlocked: \(AchievementText.name(id))"
        case let .trade(t): return trade(t)
        case let .departed(from, to, viaWormhole, parsecs):
            return viaWormhole ? "Departed \(sys(from)) through the wormhole to \(sys(to))."
                : "Departed \(sys(from)) for \(sys(to)) (\(MapText.parsecs(parsecs)))."
        case let .arrived(a):
            var line = a.firstVisit ? s("Arrived at \(sys(a.system)) for the first time.") : s("Arrived at \(sys(a.system)).")
            line += " " + (a.uneventful ? s("An uneventful trip.") : s("\(a.encounterCount) encounters on the way."))
            return "\(line)"
        case let .fabricRip(dest): return "A rip in the fabric of space-time flung you toward \(sys(dest))."
        case .singularityLost: return "The singularity was used up, but you couldn't leave."
        case let .encounter(r): return encounter(r)
        case let .police(p): return police(p)
        case let .finance(f): return finance(f)
        case let .ship(e): return ship(e)
        case let .crew(c): return crew(c, state: state)
        case let .quest(q): return quest(q)
        case let .news(news):
            let first = news.headlines.first.map { NewspaperText.headline($0, state: state) } ?? s("No headlines")
            return news.cost > 0 ? "Read the newspaper for \(n(news.cost)) cr.: \(first)" : "Read the newspaper: \(first)"
        case let .status(.policeRecord(from, to)):
            return "Police record: \(s(Names.policeRecord(from))) → \(s(Names.policeRecord(to)))."
        case let .status(.reputation(from, to)):
            return "Reputation: \(s(Names.reputation(from))) → \(s(Names.reputation(to)))."
        }
    }

    private static func trade(_ t: TradeEntry) -> LocalizedStringResource {
        let item = s(Names.item(t.item))
        let profit = t.profit.map { $0 >= 0 ? s(" (profit \(n($0)) cr.)") : s(" (loss \(n(-$0)) cr.)") } ?? ""
        switch t.action {
        case .buy: return "Bought \(t.quantity) \(item) for \(n(t.total)) cr."
        case .sell: return "Sold \(t.quantity) \(item) for \(n(t.total)) cr.\(profit)"
        case .dump: return "Dumped \(t.quantity) \(item) for \(n(t.total)) cr."
        case .jettison: return "Jettisoned \(t.quantity) \(item)."
        case .plunder: return "Plundered \(t.quantity) \(item)."
        case .scoop: return "Scooped up \(t.quantity) \(item)."
        case .orbitBuy: return "Bought \(t.quantity) \(item) in orbit for \(n(t.total)) cr."
        case .orbitSell: return "Sold \(t.quantity) \(item) in orbit for \(n(t.total)) cr.\(profit)"
        case .sealedCanisters: return "Three sealed canisters of \(item) were loaded."
        }
    }

    private static func encounter(_ r: EncounterRecord) -> LocalizedStringResource {
        "\(s(EncounterText.stance(r.type))): \(s(Names.ship(r.opponent))) — \(outcome(r.outcome))."
    }

    /// LOG-020: the outcome words.
    static func outcome(_ o: EncounterOutcomeKind) -> String {
        switch o {
        case let .destroyed(t): s("destroyed the \(s(Names.ship(t)))")
        case .disabled: s("disabled")
        case .escaped: s("escaped")
        case .opponentEscaped: s("the opponent escaped")
        case .plundered: s("plundered")
        case .traded: s("traded")
        case let .bribed(a): s("paid a bribe of \(n(a)) cr.")
        case let .fined(a): s("fined \(n(a)) cr.")
        case .inspectedClean: s("inspected, nothing found")
        case .yielded: s("yielded")
        case .arrested: s("arrested")
        case let .raided(units): s("raided, \(units) units taken")
        case .artifactSurrendered: s("surrendered the artifact")
        case let .drank(good): s(good ? "drank a good tonic" : "drank a strange brew")
        case let .trained(skill): s("trained \(s(Names.skill(skill)))")
        case .escapePod: s("escaped in the pod")
        case .killed: s("destroyed")
        case .passed: s("passed by")
        }
    }

    /// LOG-031: the expanded encounter row: outcome, rounds and lowest hull.
    static func encounterDetails(_ r: EncounterRecord) -> String {
        var parts = [outcome(r.outcome), String(localized: "\(r.rounds) rounds"), String(localized: "lowest hull \(r.minHullPercent)%")]
        if r.bounty > 0 { parts.append(String(localized: "bounty \(r.bounty.formatted()) cr.")) }
        return parts.joined(separator: " · ")
    }

    private static func police(_ p: PoliceEntry) -> LocalizedStringResource {
        switch p {
        case let .arrested(term, fine, shipSold):
            shipSold ? "Arrested: \(term) days in jail, fined \(n(fine)) cr.; your ship was sold."
                : "Arrested: \(term) days in jail, fined \(n(fine)) cr."
        case .caughtLittering: "Caught littering."
        case .reactorConfiscated: "The police confiscated the reactor."
        }
    }

    private static func finance(_ f: FinanceEntry) -> LocalizedStringResource {
        switch f {
        case let .borrowed(amount): "Borrowed \(n(amount)) cr."
        case let .repaid(amount, remaining):
            remaining == 0 ? "Repaid \(n(amount)) cr. The loan is paid off." : "Repaid \(n(amount)) cr.; \(n(remaining)) cr. still owed."
        case .insuranceBought: "Bought insurance."
        case .insuranceStopped: "Stopped insurance."
        case let .debtWarning(debt): "Debt warning: you owe \(n(debt)) cr."
        case let .debtReminder(debt): "Reminder: you owe the bank \(n(debt)) cr."
        }
    }

    private static func ship(_ e: ShipEntry) -> LocalizedStringResource {
        switch e {
        case let .boughtShip(type, net): "Bought a \(s(Names.ship(type))) (net \(n(net)) cr.)."
        case .customShipBuilt: "Your custom ship has been built."
        case let .equipment(change, price): equipment(change, price: price)
        case let .boughtEscapePod(price): "Bought an escape pod for \(n(price)) cr."
        case let .fuel(units, cost): "Bought \(units) units of fuel for \(n(cost)) cr."
        case let .repair(points, cost): "Repaired \(points) hull points for \(n(cost)) cr."
        case .autoFuelFailed: "Not enough cash to fill the tank."
        case .autoRepairFailed: "Not enough cash to repair the hull."
        case let .escapePodUsed(payout): "Your escape pod saved you. Insurance paid \(n(payout)) cr."
        }
    }

    private static func equipment(_ c: EquipmentChange, price: Int) -> LocalizedStringResource {
        switch c {
        case let .boughtWeapon(w): "Bought a \(s(Names.weapon(w))) for \(n(price)) cr."
        case let .boughtShield(sh): "Bought a \(s(Names.shield(sh))) for \(n(price)) cr."
        case let .boughtGadget(g): "Bought a \(s(Names.gadget(g))) for \(n(price)) cr."
        case let .soldWeapon(w): "Sold a \(s(Names.weapon(w))) for \(n(price)) cr."
        case let .soldShield(sh): "Sold a \(s(Names.shield(sh))) for \(n(price)) cr."
        case let .soldGadget(g): "Sold a \(s(Names.gadget(g))) for \(n(price)) cr."
        }
    }

    private static func crew(_ c: CrewEntry, state: GameState) -> LocalizedStringResource {
        switch c {
        case let .hired(id): "Hired \(Names.crew(id, in: state))."
        case let .fired(id): "Fired \(Names.crew(id, in: state))."
        case let .passengerConcerned(id): "\(Names.crew(id, in: state)) is getting concerned."
        case let .passengerImpatient(id): "\(Names.crew(id, in: state)) is impatient."
        }
    }

    private static func quest(_ q: QuestEntry) -> LocalizedStringResource {
        switch q {
        case let .completed(type): "\(s(SpecialEventText.title(type))): done."
        case let .refused(type): "\(s(SpecialEventText.title(type))): declined."
        case let .tribbles(from, to): "Tribbles: \(n(from)) → \(n(to))."
        case let .tribblesDied(death):
            switch death {
            case .allFromReactor: "The reactor's radiation killed all your tribbles."
            case .halfFromReactor: "The reactor's radiation killed half your tribbles."
            case let .narcotics(converted): "Your tribbles ate narcotics and died; \(converted) bays now hold furs."
            }
        case let .tribblesAteFood(eaten): "Your tribbles ate \(eaten) units of food."
        case let .tribbleInspectorWarning(count): "\(n(count)) tribbles aboard. Inspectors take note."
        case let .reactorWarning(status): "The reactor is getting hot (status \(status))."
        case .reactorMeltdown: "The reactor melted down."
        case .gemulonInvaded: "Gemulon was invaded."
        case .experimentPerformed: "The experiment at Daled was performed."
        case .wildLeftShip: "Jonathan Wild left your ship."
        case let .easterEgg(installed): installed ? "You found a gift from the Og." : "The Og had a gift, but you have no free shield slot."
        }
    }
}
