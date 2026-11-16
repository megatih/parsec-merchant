// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// One localized feed line for every `GameEvent` (UI-SHELL-007/008). The engine never produces user strings.
enum EventText {
    private static func n(_ v: Int) -> String { v.formatted() }
    private static func s(_ r: LocalizedStringResource) -> String { String(localized: r) }

    // An exhaustive mapping over every engine event: one line per case, so the case count is the complexity.
    // swiftlint:disable:next cyclomatic_complexity
    static func text(for event: GameEvent, state: GameState) -> LocalizedStringResource {
        func sys(_ i: Int) -> String { Names.system(i, in: state) }
        func crew(_ i: Int) -> String { Names.crew(i, in: state) }
        switch event {
        case let .gameStarted(ruleset, _): return "A new game begins (\(s(Names.ruleset(ruleset))))."
        case let .boughtCargo(item, q, total): return "Bought \(q) \(s(Names.item(item))) for \(n(total)) cr."
        case let .soldCargo(item, q, total, profit): return "Sold \(q) \(s(Names.item(item))) for \(n(total)) cr. (profit \(n(profit)) cr.)."
        case let .dumpedCargo(item, q, cost): return "Dumped \(q) \(s(Names.item(item))) for \(n(cost)) cr."
        case let .jettisonedCargo(item, q): return "Jettisoned \(q) \(s(Names.item(item)))."
        case let .caughtLittering(record): return "Caught littering. Police record score now \(record)."
        case let .boughtFuel(units, cost): return "Bought \(units) units of fuel for \(n(cost)) cr."
        case let .repairedHull(points, cost): return "Repaired \(points) hull points for \(n(cost)) cr."
        case let .boughtEquipment(price): return "Bought equipment for \(n(price)) cr."
        case let .soldEquipment(price): return "Sold equipment for \(n(price)) cr."
        case let .boughtShip(type, net): return "Bought a \(s(Names.ship(type))) (net \(n(net)) cr.)."
        case let .cannotTransfer(item): return "Couldn't transfer the \(s(Names.transfer(item)))."
        case let .cannotAffordTransfer(item): return "Couldn't afford to transfer the \(s(Names.transfer(item)))."
        case .cannotAffordAllTransfers: return "Couldn't afford all the transfers."
        case .customShipBuilt: return "Your custom ship has been built."
        case let .combatRound(round, playerHit, opponentHit, _, _):
            return "Round \(round): \(playerHit ? s("you were hit") : s("you weren't hit")), \(opponentHit ? s("they were hit") : s("they weren't hit"))."
        case .playerDestroyed: return "Your ship was destroyed."
        case .bothDestroyed: return "Both ships were destroyed."
        case let .opponentDestroyed(type): return "You destroyed the \(s(Names.ship(type)))."
        case let .opponentDisabled(type): return "You disabled the \(s(Names.ship(type)))."
        case let .playerEscaped(wasHit): return wasHit ? "You escaped, but took a hit." : "You escaped."
        case .opponentEscaped: return "Your opponent escaped."
        case let .encounterChanged(type): return "The encounter changed: \(s(EncounterText.stance(type)))."
        case let .bountyPaid(amount): return "You earned a bounty of \(n(amount)) cr."
        case let .departed(from, to, wormhole):
            return wormhole ? "Departed \(sys(from)) through the wormhole to \(sys(to))." : "Departed \(sys(from)) for \(sys(to))."
        case let .fabricRip(dest): return "A rip in the fabric of space-time flung you toward \(sys(dest))."
        case let .encounterStarted(_, opponent, clicks, _): return "At \(clicks) clicks you meet a \(s(Names.ship(opponent)))."
        case .uneventfulTrip: return "An uneventful trip."
        case let .arrived(system): return "Arrived at \(sys(system))."
        case let .debtWarning(debt): return "Debt warning: you owe \(n(debt)) cr."
        case let .debtReminder(debt): return "Reminder: you owe the bank \(n(debt)) cr."
        case let .reactorWarning(status): return "The reactor is getting hot (status \(status))."
        case .reactorMeltdown: return "The reactor melted down."
        case let .tribblesChanged(from, to): return "Tribbles: \(n(from)) → \(n(to))."
        case let .tribblesDied(death):
            switch death {
            case .allFromReactor: return "The reactor's radiation killed all your tribbles."
            case .halfFromReactor: return "The reactor's radiation killed half your tribbles."
            case let .narcotics(converted): return "Your tribbles ate narcotics and died; \(converted) bays now hold furs."
            }
        case let .tribblesAteFood(eaten): return "Your tribbles ate \(eaten) units of food."
        case let .tribbleInspectorWarning(count): return "\(n(count)) tribbles aboard. Inspectors take note."
        case let .passengerConcerned(id): return "\(crew(id)) is getting concerned."
        case let .passengerImpatient(id): return "\(crew(id)) is impatient."
        case .autoFuelFailed: return "Not enough cash to fill the tank."
        case .autoRepairFailed: return "Not enough cash to repair the hull."
        case .easterEgg: return "You found a gift from the Og."
        case .easterEggNoShieldSlot: return "The Og had a gift, but you have no free shield slot."
        case let .escapePodUsed(payout): return "Your escape pod saved you. Insurance paid \(n(payout)) cr."
        case .wildLeftShip: return "Jonathan Wild left your ship."
        case .singularityLost: return "The singularity was used up, but you couldn't leave."
        case let .departureBlocked(reason): return "You couldn't depart: \(ReasonText.string(for: reason))"
        case .gemulonInvaded: return "Gemulon was invaded."
        case .experimentPerformed: return "The experiment at Daled was performed."
        case .playerAttacked: return "You attacked."
        case .playerFled: return "You tried to flee."
        case .artifactRelinquished: return "You surrendered the artifact."
        case .preciousHidden: return "Your precious cargo stayed hidden."
        case .sculptureTaken: return "The sculpture was taken."
        case let .blackmailed(amount): return "You were blackmailed for \(n(amount)) cr."
        case let .looted(units): return "Pirates looted \(units) units of cargo."
        case .wildJoinedPirates: return "Jonathan Wild joined the pirates."
        case let .bribed(amount): return "You paid a bribe of \(n(amount)) cr."
        case let .fined(amount): return "You were fined \(n(amount)) cr."
        case .inspectionClean: return "The inspection found nothing."
        case .reactorConfiscated: return "The police confiscated the reactor."
        case .yielded: return "You yielded to the police."
        case let .tonicConsumed(good): return good ? "The tonic did you good." : "The drink was a strange one."
        case let .captainTraining(skill): return "The captain trained your \(s(Names.skill(skill))) skill."
        case let .plundered(item, q): return "Plundered \(q) \(s(Names.item(item)))."
        case let .scooped(item): return "Scooped up a canister of \(s(Names.item(item)))."
        case .scoopNoRoom: return "No room to scoop the canister."
        case let .arrested(term, fine, shipSold):
            return shipSold ? "Arrested: \(term) days in jail, fined \(n(fine)) cr.; your ship was sold."
                : "Arrested: \(term) days in jail, fined \(n(fine)) cr."
        case let .boughtEscapePod(price): return "Bought an escape pod for \(n(price)) cr."
        case let .hired(id): return "Hired \(crew(id))."
        case let .fired(id): return "Fired \(crew(id))."
        case let .borrowed(amount): return "Borrowed \(n(amount)) cr."
        case let .repaid(amount): return "Repaid \(n(amount)) cr."
        case .insuranceBought: return "Bought insurance."
        case .insuranceStopped: return "Stopped insurance."
        case .optionsChanged: return "Options changed."
        case let .orbitTradeCompleted(direction, item, q, total):
            return direction == .traderSells ? "Bought \(q) \(s(Names.item(item))) in orbit for \(n(total)) cr."
                : "Sold \(q) \(s(Names.item(item))) in orbit for \(n(total)) cr."
        case let .specialEventCompleted(type): return "\(s(SpecialEventText.title(type))): done."
        case let .specialEventRefused(type, reason): return "\(s(SpecialEventText.title(type))): \(ReasonText.string(for: reason))"
        case let .sealedCanisters(item): return "Three sealed canisters of \(s(Names.item(item))) were loaded."
        case let .gameEnded(end, _): return Names.ending(end)
        case .cheatUsed: return "Cheat accepted. This game is now flagged."
        case .cheatReadout: return "Cheat readout available in the console."
        }
    }

    /// The feed line for an entry (events or app notes).
    static func text(for entry: FeedItem.Entry, state: GameState) -> LocalizedStringResource {
        switch entry {
        case let .event(e): text(for: e, state: state)
        case let .note(note): text(for: note)
        }
    }

    static func text(for note: FeedNote) -> LocalizedStringResource {
        switch note {
        case .gameSaved: "Game saved."
        case .recoveredFromBackup: "This save was damaged; an earlier backup was restored."
        }
    }
}
