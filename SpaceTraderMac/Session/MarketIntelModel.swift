// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// INT-029: everything the Market's intel columns, recommendations strip, "Why this price?" panel and footer show,
/// built only from `IntelBook` + `IntelSnapshot` (and the current system's ECO-082 breakdowns). Pure and `Sendable`, so
/// the Market builds it off the main actor once per state generation or journal change.
nonisolated struct MarketIntelModel: Sendable, Equatable {
    struct Row: Sendable, Equatable {
        var item: TradeItemType
        /// INT-030: the target's quote (nil when the target is the current system).
        var targetQuote: PriceQuote?
        /// INT-015.
        var profitPerBay: Int?
        /// INT-031: sell prices at the current system, oldest first (zeros where nobody bought it are skipped).
        var history: [Int]
        /// INT-022 (nil when not held).
        var sellAdvice: SellAdvice?
        /// INT-017 (current system only, INT-018).
        var explanation: PriceExplanation?
    }

    var target: Int
    var targetIsHere: Bool
    var rows: [Row]
    var bestBuys: [TradeRecommendation]
    var bestDestinations: [DestinationRecommendation]
    /// INT-034 (nil when the target is the current system).
    var holdAtTarget: HoldValue?

    func row(_ item: TradeItemType) -> Row? { rows.first { $0.item == item } }

    static func make(book: IntelBook, snapshot: IntelSnapshot, target: Int, breakdowns: [PriceBreakdown] = []) -> MarketIntelModel {
        let here = target == snapshot.currentSystem
        let current = book.systems.indices.contains(snapshot.currentSystem) ? book.systems[snapshot.currentSystem].history : []
        let rows = TradeItemType.allCases.map { item in
            Row(item: item,
                targetQuote: here ? nil : TradeIntel.quote(item: item, system: target, book: book, snapshot: snapshot),
                profitPerBay: here ? nil : TradeIntel.profitPerBay(item: item, target: target, book: book, snapshot: snapshot),
                history: current.compactMap { obs in
                    obs.sell.indices.contains(item.rawValue) && obs.sell[item.rawValue] > 0 ? obs.sell[item.rawValue] : nil
                },
                sellAdvice: TradeIntel.sellAdvice(item: item, book: book, snapshot: snapshot),
                explanation: snapshot.isDocked ? breakdowns.first { $0.item == item }.map(PriceExplanation.make) : nil)
        }
        return MarketIntelModel(target: target, targetIsHere: here, rows: rows,
                                bestBuys: here ? [] : TradeIntel.bestBuys(for: target, book: book, snapshot: snapshot),
                                bestDestinations: TradeIntel.bestDestinations(book: book, snapshot: snapshot),
                                holdAtTarget: here ? nil : TradeIntel.holdValue(at: target, book: book, snapshot: snapshot))
    }

    /// The inputs of one build, captured on the main actor (INT-003).
    struct Inputs: Sendable, Equatable {
        var book: IntelBook
        var snapshot: IntelSnapshot
        var target: Int
        var breakdowns: [PriceBreakdown]

        @MainActor
        static func make(state: GameState, journal: GameJournal?) -> Inputs {
            let book = journal?.intel ?? IntelBook(systems: Array(repeating: SystemIntel(), count: state.galaxy.systems.count))
            return Inputs(book: book, snapshot: IntelSnapshot(state), target: state.warpSystem,
                          breakdowns: state.phase == .docked ? TradeItemType.allCases.map(state.priceBreakdown) : [])
        }
    }

    /// INT-029: builds the model in a detached task (off the main actor).
    static func build(_ inputs: Inputs) async -> MarketIntelModel {
        await Task.detached(priority: .userInitiated) {
            make(book: inputs.book, snapshot: inputs.snapshot, target: inputs.target, breakdowns: inputs.breakdowns)
        }.value
    }
}

/// INT-030 / INT-031 / INT-033 / INT-034 / INT-035: the localized texts of the intel cells (IntelText).
nonisolated enum IntelText {
    /// "today", "3 d ago", "est." or "live".
    static func age(_ q: PriceQuote) -> String {
        switch q.staleness {
        case .live: String(localized: "live")
        case .estimate: String(localized: "est.")
        case .fresh, .old:
            if let a = q.age, a > 0 { String(localized: "\(a) d ago") } else { String(localized: "today") }
        }
    }

    /// The help tag naming the source and day (INT-030), plus a pressure hint (INT-016).
    static func help(_ q: PriceQuote) -> String {
        var s: String = switch q.source {
        case .live: String(localized: "Current price here.")
        case let .observed(day): String(localized: "Seen on day \(day).")
        case .estimate: String(localized: "Estimate from the Average Price List (not visited or never seen).")
        }
        if let hint = q.pressureHint {
            s += " " + String(localized: "News on day \(hint.day): \(pressure(hint.pressure))")
        }
        return s
    }

    static func pressure(_ p: SystemPressure) -> String {
        switch p {
        case .none: String(localized: "no unusual events")
        case .war: String(localized: "war")
        case .plague: String(localized: "plague")
        case .drought: String(localized: "drought")
        case .boredom: String(localized: "boredom")
        case .cold: String(localized: "cold weather")
        case .cropFailure: String(localized: "crop failure")
        case .employment: String(localized: "lack of workers")
        }
    }

    /// "+412" / "−12" with sign (never colour alone).
    static func signed(_ n: Int) -> String {
        n > 0 ? "+\(n.formatted())" : n < 0 ? "−\(abs(n).formatted())" : "0"
    }

    static func arrow(_ n: Int) -> String { n > 0 ? "▲" : n < 0 ? "▼" : "" }

    /// INT-031: the sparkline's accessibility value.
    static func historyValue(_ series: [Int]) -> String {
        guard let first = series.first, let last = series.last, series.count >= 2 else { return String(localized: "No history") }
        return String(localized: "Sell price over \(series.count) visits: from \(first) to \(last) credits")
    }

    /// INT-033: "Best buy here for Rhymus: Robots +412/bay (12 bays, +4,944)" with "est." for estimates.
    @MainActor
    static func buyRecommendation(_ r: TradeRecommendation, target: String) -> String {
        let est = r.staleness == .estimate ? " " + String(localized: "est.") : ""
        return String(localized: "Best buy here for \(target): \(String(localized: Names.item(r.item))) \(signed(r.profitPerBay))/bay (\(r.units) bays, \(signed(r.projectedProfit)))") + est
    }

    /// INT-033: "Best destinations for your hold: Rhymus +1,200".
    static func destinationRecommendation(_ d: DestinationRecommendation, system: String) -> String {
        let est = d.usesEstimates ? " " + String(localized: "est.") : ""
        return String(localized: "Best destinations for your hold: \(system) \(signed(d.profit))") + est
    }

    /// INT-034: "Hold at Rhymus: +1,200 est. · 2 items not bought there".
    static func holdProjection(_ h: HoldValue, target: String) -> String {
        var s = String(localized: "Hold at \(target): \(signed(h.profit))")
        if h.usesEstimates { s += " " + String(localized: "est.") }
        if !h.unsellable.isEmpty { s += " · " + String(localized: "\(h.unsellable.count) items not bought there") }
        return s
    }

    /// INT-035: "Sell here: +12/unit · Best known: Rhymus +40/unit (3 d ago)".
    static func sellAdvice(_ a: SellAdvice, systemName: (Int) -> String, today: Int) -> String {
        var parts: [String] = []
        if let here = a.herePerUnit { parts.append(String(localized: "Sell here: \(signed(here))/unit")) }
        if let best = a.bestSystem, let per = a.bestPerUnit {
            let when: String = switch a.bestSource {
            case .some(.estimate), nil: String(localized: "est.")
            case .some(.live): String(localized: "live")
            case .some(.observed):
                if let age = a.bestAge, age > 0 { String(localized: "\(age) d ago") } else { String(localized: "today") }
            }
            parts.append(String(localized: "Best known: \(systemName(best)) \(signed(per))/unit (\(when))"))
        }
        return parts.joined(separator: " · ")
    }

    /// INT-017 / INT-018: the factor labels of "Why this price?".
    static func factor(_ f: PriceFactor) -> String {
        switch f {
        case .base: String(localized: "Base price for the tech level")
        case .wanted: String(localized: "Wanted by the government")
        case .traderActivity: String(localized: "Trader activity")
        case .size: String(localized: "System size")
        case .resource: String(localized: "Special resource")
        case .pressure: String(localized: "Current events")
        case .criminal: String(localized: "Your police record")
        case .fluctuation: String(localized: "Market fluctuation")
        case .buyMarkup: String(localized: "Buy markup (trader skill)")
        }
    }
}
