// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// The classic newspaper string tables exported by the harness (Strings.cs).
struct NewsStrings: Decodable {
    let mastheads, headlines: [[String]]
    let villain, hero, external, externalPressures, internalPressure, events, systems, ships: [String]
    let moon, tribbleBuyer, shipyard: String

    static func vars(_ s: String, _ v: [String]) -> String {
        var out = s
        for (i, x) in v.enumerated() { out = out.replacingOccurrences(of: "^\(i + 1)", with: x) }
        return out
    }

    /// Renders a typed newspaper exactly like C# NewspaperHead/NewspaperText.
    func render(_ p: Newspaper, commander: String, shipType: ShipType) -> (head: String, text: String) {
        let sys = systems[p.system]
        let head = Self.vars(mastheads[p.government.rawValue][p.mastheadIndex], [sys])
        let items: [String] = p.headlines.map { h in
            switch h {
            case let .event(e): return Self.vars(events[e.rawValue], [commander, sys, ships[shipType.rawValue]])
            case let .internalPressure(pr): return internalPressure[pr.rawValue]
            case let .villain(i): return Self.vars(villain[i], [commander, sys])
            case let .hero(i): return Self.vars(hero[i], [commander, sys])
            case let .moonForSale(s): return Self.vars(moon, [systems[s]])
            case let .tribbleBuyer(s): return Self.vars(tribbleBuyer, [systems[s]])
            case let .shipyard(s): return Self.vars(shipyard, [systems[s]])
            case let .externalPressure(t, pr, s): return Self.vars(external[t], [externalPressures[pr.rawValue], systems[s]])
            case let .canned(g, i): return headlines[g.rawValue][i]
            }
        }
        return (head, items.joined(separator: "\n\n"))
    }
}

struct HarnessTravel: Decodable {
    struct Enc: Decodable {
        let clicks, type: Int
        let opp: HarnessOpponents.ShipDump
    }
    struct Warp: Decodable {
        let target, arrived, days, cash, debt, record, fuel, hull: Int
        let encounters: [Enc]
        let shields, buy, sell, stock, news, opponentSkills: [Int]
        let paperHead: String
        let paperText: String
    }
    let seed: Int32
    let difficulty: Int
    let warps: [Warp]
}

// Journeys replayed against C# Game.Warp with a recording FormEncounter stub (returns Normal, no fighting).
// Bit-exact agreement verifies warp checks/departure (costs, fuel, interest, IncDays, countdown, departure prices),
// per-click repairs, fixed/random/very-rare encounter determination, opponent generation in context, the cloak test,
// police inspection flag, trade-in-orbit roll, the arrival pipeline (tribbles, debt, repairs, shields,
// pressures/quantities, Easter egg, prices, arrival news) and the newspaper composition (masthead, events, pressures,
// hero/villain, distant-system stories with PieterRand, canned headlines), rendered with the classic string tables.
@Suite("Journeys vs C# harness (Windows 2.01)")
struct TravelHarnessTests {
    static let runs: [HarnessTravel] = (try? Fixtures.decode([HarnessTravel].self, "harness/travel-windows201.json")) ?? []
    static let strings: NewsStrings? = try? Fixtures.decode(NewsStrings.self, "harness/news-strings.json")

    @Test("Warps, encounters and arrivals match C#", arguments: 0..<9)
    func replay(_ index: Int) throws {
        try #require(index < Self.runs.count)
        let run = Self.runs[index]
        var e = GameEngine(config: NewGameConfig(commanderName: "Harness", difficulty: Difficulty(rawValue: run.difficulty) ?? .normal,
                                                 ruleset: .windows201, seed: UInt64(UInt32(bitPattern: run.seed))))
        e.state.options.alwaysIgnoreTraders = false
        for (w, expected) in run.warps.enumerated() {
            let tag = "seed \(run.seed) diff \(run.difficulty) warp \(w)"
            e.state.commander.ship.fuel = e.state.commander.ship.fuelTanks(e.ruleset)
            e.state.commander.cash = max(e.state.commander.cash, 20_000)
            if w % 5 == 4 { e.state.commander.policeRecordScore = -12 }
            e.state.commander.ship.hull = max(1, e.state.commander.ship.hull - (w % 3) * 7)
            let dest = e.state.destinations
            let target = dest[(w * 7) % dest.count]
            #expect(target == expected.target, "\(tag) target")
            _ = e.perform(.selectTarget(target))
            var seen: [EncounterState] = []
            _ = e.perform(.warp)
            while case let .encounter(enc) = e.state.phase {
                seen.append(enc)
                _ = e.finishEncounter(.normal)
            }
            #expect(seen.count == expected.encounters.count, "\(tag) encounter count \(seen.count) vs \(expected.encounters.count)")
            for (mine, theirs) in zip(seen, expected.encounters) {
                #expect(mine.clicks == theirs.clicks && mine.type.rawValue == theirs.type, "\(tag) encounter at \(theirs.clicks)")
                #expect(mine.opponent.type.rawValue == theirs.opp.type && mine.opponent.hull == theirs.opp.hull, "\(tag) opponent")
                #expect(mine.opponent.weapons.map(\.rawValue) == theirs.opp.weapons.filter { $0 >= 0 }, "\(tag) opp weapons")
                #expect(mine.opponent.cargo == theirs.opp.cargo, "\(tag) opp cargo")
            }
            let s = e.state
            #expect(s.commander.currentSystem == expected.arrived, "\(tag) arrived")
            #expect(s.commander.days == expected.days, "\(tag) days")
            #expect(s.commander.cash == expected.cash && s.commander.debt == expected.debt, "\(tag) cash/debt")
            #expect(s.commander.policeRecordScore == expected.record, "\(tag) record")
            #expect(s.commander.ship.fuel == expected.fuel && s.commander.ship.hull == expected.hull, "\(tag) fuel/hull")
            #expect(s.commander.ship.shields.map(\.charge) == expected.shields, "\(tag) shields")
            #expect(s.buyPrices == expected.buy && s.sellPrices == expected.sell, "\(tag) prices")
            #expect(s.currentSystem.tradeItems == expected.stock, "\(tag) stock")
            #expect(s.newsEvents.map(\.rawValue) == expected.news, "\(tag) news")
            #expect(s.mercenaries[CrewID.opponent].skills == expected.opponentSkills, "\(tag) opponent crew skills")
            if let strings = Self.strings {
                let (head, text) = strings.render(s.newspaper, commander: "Harness", shipType: s.commander.ship.type)
                #expect(head == expected.paperHead, "\(tag) masthead")
                #expect(text == expected.paperText, "\(tag) newspaper: \(text.prefix(80)) vs \(expected.paperText.prefix(80))")
            } else {
                Issue.record("news strings fixture missing")
            }
            if s.commander.currentSystem != expected.arrived || seen.count != expected.encounters.count { return }
        }
    }
}
