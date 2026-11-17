// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// LLM-011: localized text of template flavor lines (key plus typed arguments, rendered in the reader's language);
/// generated prose is shown as stored.
@MainActor
enum FlavorCatalogText {
    static func text(for flavor: FlavorText?, state: GameState) -> String? {
        switch flavor {
        case nil: nil
        case let .generated(text): text
        case let .template(line): text(for: line, state: state)
        }
    }

    /// The typed arguments of a line, resolved to display text.
    struct Args {
        var system = ""
        var ship = ""
        var count = 0
    }

    static func args(_ line: FlavorLine, state: GameState) -> Args {
        var a = Args()
        for arg in line.args {
            switch arg {
            case let .system(i): a.system = Names.system(i, in: state)
            case let .ship(t): a.ship = String(localized: Names.ship(t))
            case let .count(n): a.count = n
            case .item, .credits, .skill: break
            }
        }
        return a
    }

    /// Every catalog key maps to a localized line; nil for an unknown key (a newer save), shown as no flavor.
    static func text(for line: FlavorLine, state: GameState) -> String? {
        resolve(line.key, args(line, state: state))
    }

    // One line per catalog key (28 groups × 3 variants), so the key count is the complexity.
    // swiftlint:disable:next cyclomatic_complexity
    static func resolve(_ key: String, _ a: Args) -> String? {
        let sys = a.system, ship = a.ship, n = a.count
        switch key {
        case "flavor.arrival.quiet.1": return String(localized: "The approach to \(sys) was calm; the docking clamps took us gently.")
        case "flavor.arrival.quiet.2": return String(localized: "Nothing stirred on the way to \(sys). The crew slept well.")
        case "flavor.arrival.quiet.3": return String(localized: "\(sys) control waved us in without a second glance.")
        case "flavor.arrival.eventful.1": return String(localized: "We limped into \(sys) after \(n) encounters on the way.")
        case "flavor.arrival.eventful.2": return String(localized: "\(n) close calls later, the lights of \(sys) never looked so good.")
        case "flavor.arrival.eventful.3": return String(localized: "The trip to \(sys) brought \(n) encounters; the crew wants shore leave.")
        case "flavor.arrival.firstVisit.1": return String(localized: "First landfall at \(sys). The charts did not do it justice.")
        case "flavor.arrival.firstVisit.2": return String(localized: "A new port: \(sys). The traders eyed our hold with interest.")
        case "flavor.arrival.firstVisit.3": return String(localized: "We added \(sys) to the log of places we have seen.")
        case "flavor.arrival.wormhole.1": return String(localized: "The wormhole spat us out near \(sys), stomachs still spinning.")
        case "flavor.arrival.wormhole.2": return String(localized: "Through the wormhole and into \(sys) in a heartbeat.")
        case "flavor.arrival.wormhole.3": return String(localized: "Space folded, and \(sys) was suddenly outside the viewport.")
        case "flavor.encounter.won.1": return String(localized: "The \(ship) learned to leave us alone.")
        case "flavor.encounter.won.2": return String(localized: "Our guns had the last word against the \(ship).")
        case "flavor.encounter.won.3": return String(localized: "The \(ship) drifted dark behind us as we moved on.")
        case "flavor.encounter.fled.1": return String(localized: "We outran the \(ship) with the engines screaming.")
        case "flavor.encounter.fled.2": return String(localized: "Discretion won the day; the \(ship) was left behind.")
        case "flavor.encounter.fled.3": return String(localized: "A hard burn put the \(ship) out of range.")
        case "flavor.encounter.surrendered.1": return String(localized: "We lowered our shields before the \(ship) and hoped for mercy.")
        case "flavor.encounter.surrendered.2": return String(localized: "The \(ship) took what it wanted. We kept our lives.")
        case "flavor.encounter.surrendered.3": return String(localized: "No heroics today: we yielded to the \(ship).")
        case "flavor.encounter.lost.1": return String(localized: "The \(ship) had the better of us.")
        case "flavor.encounter.lost.2": return String(localized: "A bitter day; the \(ship) won the exchange.")
        case "flavor.encounter.lost.3": return String(localized: "We will remember that \(ship) for a long time.")
        case "flavor.encounter.other.1": return String(localized: "The \(ship) and we went our separate ways.")
        case "flavor.encounter.other.2": return String(localized: "A brief meeting with a \(ship), nothing more.")
        case "flavor.encounter.other.3": return String(localized: "The \(ship) crossed our path and was gone.")
        case "flavor.quest.dragonfly.1", "flavor.quest.dragonfly.2", "flavor.quest.dragonfly.3":
            return String(localized: "Near \(sys) the Dragonfly business came to an end.")
        case "flavor.quest.spaceMonster.1", "flavor.quest.spaceMonster.2", "flavor.quest.spaceMonster.3":
            return String(localized: "At \(sys) the monster's story was finally told.")
        case "flavor.quest.scarab.1", "flavor.quest.scarab.2", "flavor.quest.scarab.3":
            return String(localized: "At \(sys) the Scarab chapter closed.")
        case "flavor.quest.japori.1", "flavor.quest.japori.2", "flavor.quest.japori.3":
            return String(localized: "At \(sys) the medicine reached those who needed it.")
        case "flavor.quest.jarek.1", "flavor.quest.jarek.2", "flavor.quest.jarek.3":
            return String(localized: "At \(sys) the ambassador's journey ended.")
        case "flavor.quest.wild.1", "flavor.quest.wild.2", "flavor.quest.wild.3":
            return String(localized: "At \(sys) Jonathan Wild's escape was complete.")
        case "flavor.quest.reactor.1", "flavor.quest.reactor.2", "flavor.quest.reactor.3":
            return String(localized: "At \(sys) the reactor was off our hands at last.")
        case "flavor.quest.gemulon.1", "flavor.quest.gemulon.2", "flavor.quest.gemulon.3":
            return String(localized: "At \(sys) the Gemulon affair was settled.")
        case "flavor.quest.experiment.1", "flavor.quest.experiment.2", "flavor.quest.experiment.3":
            return String(localized: "At \(sys) the experiment's fate was decided.")
        case "flavor.quest.artifact.1", "flavor.quest.artifact.2", "flavor.quest.artifact.3":
            return String(localized: "At \(sys) the artifact found its new keeper.")
        case "flavor.quest.moon.1", "flavor.quest.moon.2", "flavor.quest.moon.3":
            return String(localized: "At \(sys) the dream of a moon came closer.")
        case "flavor.quest.tribbles.1", "flavor.quest.tribbles.2", "flavor.quest.tribbles.3":
            return String(localized: "At \(sys) the tribble question was answered.")
        case "flavor.quest.sculpture.1", "flavor.quest.sculpture.2", "flavor.quest.sculpture.3":
            return String(localized: "At \(sys) the sculpture's travels ended.")
        case "flavor.quest.princess.1", "flavor.quest.princess.2", "flavor.quest.princess.3":
            return String(localized: "At \(sys) the Princess's story turned a page.")
        case "flavor.quest.generic.1": return String(localized: "Business at \(sys) concluded to everyone's satisfaction.")
        case "flavor.quest.generic.2": return String(localized: "A small favour done at \(sys).")
        case "flavor.quest.generic.3": return String(localized: "At \(sys) a strange offer paid off.")
        case "flavor.gameEnded.killed.1": return String(localized: "The log ends here, among the stars.")
        case "flavor.gameEnded.killed.2": return String(localized: "Space keeps its own accounts. This one is closed.")
        case "flavor.gameEnded.killed.3": return String(localized: "No more entries will be written in this log.")
        case "flavor.gameEnded.retired.1": return String(localized: "The commander hung up the flight jacket for good.")
        case "flavor.gameEnded.retired.2": return String(localized: "A quiet retirement, earned one trade at a time.")
        case "flavor.gameEnded.retired.3": return String(localized: "The ship was sold, the stories kept.")
        case "flavor.gameEnded.moon.1": return String(localized: "A moon of one's own: the finest trade of all.")
        case "flavor.gameEnded.moon.2": return String(localized: "The commander settled on a moon and watched the traders fly.")
        case "flavor.gameEnded.moon.3": return String(localized: "From rookie trader to moon owner. Not bad at all.")
        case "flavor.achievement.1": return String(localized: "A milestone worth noting in the log.")
        case "flavor.achievement.2": return String(localized: "The crew raised a glass to the occasion.")
        case "flavor.achievement.3": return String(localized: "Word of this will travel between the ports.")
        default: return nil
        }
    }
}
