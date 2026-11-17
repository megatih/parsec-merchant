// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// MAP-072 filters, combined with AND. `sells` is {M10}.
nonisolated enum SystemSearchFilter: String, CaseIterable, Sendable, Hashable {
    case visited, unvisited, inRange, questHere, hasShipyard, wormhole

    func matches(_ sys: MapSystem, in s: MapSnapshot) -> Bool {
        switch self {
        case .visited: sys.visited
        case .unvisited: !sys.visited
        case .inRange: sys.inRange
        case .questHere: sys.isQuestLocation
        case .hasShipyard: sys.visited && sys.hasShipyard
        case .wormhole: sys.wormholeDestination != nil
        }
    }

    /// `hasShipyard` is offered only when the ruleset has shipyards.
    static func offered(_ s: MapSnapshot) -> [SystemSearchFilter] {
        allCases.filter { $0 != .hasShipyard || s.hasShipyards }
    }
}

/// The inline map search (MAP-071…073). Pure.
nonisolated enum SystemSearch {
    static let suggestionLimit = 8

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// MAP-071: prefix matches first, then other substring matches, each in galaxy order. An empty query with filters
    /// lists the matching systems by distance, then index; an empty query without filters lists nothing.
    static func results(query: String, filters: Set<SystemSearchFilter>, snapshot s: MapSnapshot, sells: [SellsMatch?]? = nil) -> [Int] {
        let candidates = s.systems.filter { sys in
            filters.allSatisfy { $0.matches(sys, in: s) } && matchesSells(sys.index, sells)
        }
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        if q.isEmpty {
            return filters.isEmpty && sells == nil ? [] : s.byDistance(candidates.map(\.index))
        }
        var prefix: [Int] = [], inner: [Int] = []
        for sys in candidates {
            let name = fold(sys.name)
            if name.hasPrefix(q) {
                prefix.append(sys.index)
            } else if name.contains(q) {
                inner.append(sys.index)
            }
        }
        return prefix + inner
    }

    /// MAP-073: systems dimmed while filters are active (the non-matching ones).
    static func dimmed(filters: Set<SystemSearchFilter>, snapshot s: MapSnapshot, sells: [SellsMatch?]? = nil) -> Set<Int> {
        guard !filters.isEmpty || sells != nil else { return [] }
        return Set(s.systems.filter { sys in !(filters.allSatisfy { $0.matches(sys, in: s) } && matchesSells(sys.index, sells)) }
            .map(\.index))
    }

    /// INT-028: the "sells <item>" filter (nil: off). Per system, `TradeIntel.sells` from intel only.
    static func matchesSells(_ i: Int, _ sells: [SellsMatch?]?) -> Bool {
        guard let sells else { return true }
        return sells.indices.contains(i) && sells[i] != nil
    }

    /// INT-028: the per-system matches of "sells <item>".
    static func sells(_ item: TradeItemType, book: IntelBook, snapshot: IntelSnapshot) -> [SellsMatch?] {
        snapshot.systems.indices.map { TradeIntel.sells(item: item, system: $0, book: book, snapshot: snapshot) }
    }
}
