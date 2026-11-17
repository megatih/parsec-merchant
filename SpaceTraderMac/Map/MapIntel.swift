// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights
import SwiftUI

/// MAP-096: the HUD's heatmap choice. The commodity of `price` is a separate picker.
nonisolated enum MapHeatmapChoice: String, CaseIterable, Sendable {
    case none, price, holdProfit, police, pirates, techLevel, lastVisited

    func mode(item: TradeItemType) -> HeatmapMode {
        switch self {
        case .none: .none
        case .price: .price(item)
        case .holdProfit: .holdProfit
        case .police: .police
        case .pirates: .pirates
        case .techLevel: .techLevel
        case .lastVisited: .lastVisited
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .none: "None"
        case .price: "Price"
        case .holdProfit: "Profit for hold"
        case .police: "Police"
        case .pirates: "Pirates"
        case .techLevel: "Tech level"
        case .lastVisited: "Last visited"
        }
    }
}

/// MAP-096: per-system tint strengths (0…1) of a heatmap result, and the legend's labels (colour plus text).
nonisolated enum HeatmapTint {
    /// The normalized value of each system (nil where the value is nil).
    static func strengths(_ r: HeatmapResult) -> [Double?] {
        let span = Double(r.scale.max - r.scale.min)
        return r.values.map { v in
            guard let value = v.value else { return nil }
            return span > 0 ? Double(value - r.scale.min) / span : 1
        }
    }

    /// "Low 12 · High 4,300" plus the estimate note when any value is an estimate.
    static func legend(_ r: HeatmapResult) -> [String] {
        guard r.values.contains(where: { $0.value != nil }) else { return [String(localized: "No data")] }
        var lines = [String(localized: "Low \(r.scale.min.formatted()) · High \(r.scale.max.formatted())")]
        if r.values.contains(where: { $0.note == .estimate }) {
            lines.append(String(localized: "Dashed: estimate"))
        }
        if r.values.contains(where: { $0.note == .dateUnknown }) {
            lines.append(String(localized: "Visited, date unknown"))
        }
        return lines
    }

    static func color(_ t: Double) -> Color {
        Color(hue: 0.62 - 0.62 * t, saturation: 0.85, brightness: 0.95)
    }
}

/// INT-036 / MAP-047: the hover card's intel rows: up to three quotes (held items with the highest sell quote, else the
/// three highest quotes overall) with their age or "estimate", then the best profit for the hold.
nonisolated enum HoverIntel {
    static func rows(system: Int, book: IntelBook, snapshot: IntelSnapshot, itemName: (TradeItemType) -> String) -> [String] {
        let quotes = TradeItemType.allCases.map { TradeIntel.quote(item: $0, system: system, book: book, snapshot: snapshot) }
            .filter { $0.sell != nil }
        let held = quotes.filter { snapshot.cargo.indices.contains($0.item.rawValue) && snapshot.cargo[$0.item.rawValue] > 0 }
        let pool = held.isEmpty ? quotes : held
        let top = pool.sorted { ($0.sell ?? 0, -$0.item.rawValue) > ($1.sell ?? 0, -$1.item.rawValue) }.prefix(3)
        var rows = top.map { q in
            let when: String = switch q.staleness {
            case .estimate: String(localized: "estimate")
            case .live: String(localized: "live")
            case .fresh, .old:
                if let a = q.age, a > 0 { String(localized: "\(a) d ago") } else { String(localized: "today") }
            }
            return String(localized: "\(itemName(q.item)) \((q.sell ?? 0).formatted()) cr. (\(when))")
        }
        if snapshot.hasCargo, system != snapshot.currentSystem {
            let hold = TradeIntel.holdValue(at: system, book: book, snapshot: snapshot)
            let est = hold.usesEstimates ? " " + String(localized: "(estimate)") : ""
            rows.append(String(localized: "Best profit for your hold: \(IntelText.signed(hold.profit))") + est)
        }
        return rows
    }
}

/// INT-037: the System Intel sheet's rows and facts (pure over the intel inputs).
nonisolated struct SystemIntelModel: Sendable, Equatable {
    struct Row: Sendable, Equatable {
        var item: TradeItemType
        var quote: PriceQuote
    }

    var system: Int
    var rows: [Row]
    var knownResource: SpecialResource?
    var pressureHint: PressureHint?
    /// "Day N", "date unknown" or "never".
    var lastVisit: LastVisit

    enum LastVisit: Sendable, Equatable {
        case day(Int), dateUnknown, never
    }

    static func make(system: Int, book: IntelBook, snapshot: IntelSnapshot) -> SystemIntelModel {
        let intel = book.systems.indices.contains(system) ? book.systems[system] : SystemIntel()
        let facts = snapshot.systems.indices.contains(system) ? snapshot.systems[system] : nil
        let visit: LastVisit = if let d = intel.lastVisitDay { .day(d) } else if intel.visitCount > 0 || facts?.visited == true {
            .dateUnknown
        } else { .never }
        let resource = facts.flatMap { $0.visited ? $0.knownResource : nil }
        return SystemIntelModel(system: system,
                                rows: TradeItemType.allCases.map {
                                    Row(item: $0, quote: TradeIntel.quote(item: $0, system: system, book: book, snapshot: snapshot))
                                },
                                knownResource: resource, pressureHint: intel.pressureHint, lastVisit: visit)
    }
}

extension GameSession {
    /// The intel inputs of the current state (INT-001), the snapshot cached per state generation.
    func intelInputs() -> (book: IntelBook, snapshot: IntelSnapshot)? {
        guard let state else { return nil }
        let snapshot: IntelSnapshot
        if let cached = intelSnapshotCache, cached.generation == stateGeneration {
            snapshot = cached.snapshot
        } else {
            snapshot = IntelSnapshot(state)
            intelSnapshotCache = (stateGeneration, snapshot)
        }
        let book = journal?.intel ?? IntelBook(systems: Array(repeating: SystemIntel(), count: state.galaxy.systems.count))
        return (book, snapshot)
    }

    /// INT-028: the per-system matches of the "sells" filter (nil when the filter is off).
    func sellsMatches(_ item: TradeItemType?) -> [SellsMatch?]? {
        guard let item, let inputs = intelInputs() else { return nil }
        return SystemSearch.sells(item, book: inputs.book, snapshot: inputs.snapshot)
    }

    /// MAP-096: the heatmap of a mode for the current intel.
    func heatmap(_ mode: HeatmapMode) -> HeatmapResult? {
        guard mode != .none, let inputs = intelInputs() else { return nil }
        return HeatmapModel.values(mode: mode, intel: inputs.book, snapshot: inputs.snapshot)
    }
}
