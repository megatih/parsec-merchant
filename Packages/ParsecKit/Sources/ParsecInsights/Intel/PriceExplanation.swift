// SPDX-License-Identifier: GPL-2.0-or-later
// "Why this price?" (docs/specs/INT.md §4, INT-017/018) and the map heatmaps (§6, INT-024/025; MAP-097).
import ParsecEngine

/// INT-017: the factors of a price, in explanation order.
public enum PriceFactor: String, Sendable, Equatable, CaseIterable {
    case base, wanted, traderActivity, size, resource, pressure, criminal, fluctuation, buyMarkup
}

/// INT-017: one step of the explanation.
public struct PriceExplanationStep: Sendable, Equatable {
    public var factor: PriceFactor
    public var valueAfter: Int
    public var delta: Int

    public init(factor: PriceFactor, valueAfter: Int, delta: Int) {
        self.factor = factor
        self.valueAfter = valueAfter
        self.delta = delta
    }

    /// A step that changes nothing (the view may collapse it).
    public var isNeutral: Bool { delta == 0 }
}

/// INT-017 / INT-018: the current system's price breakdown as ordered steps. Offered only for the current system while
/// docked, where every input is visible; `fluctuation` is the difference to the visible price, never an RNG value.
public struct PriceExplanation: Sendable, Equatable {
    public var item: TradeItemType
    public var steps: [PriceExplanationStep]

    public static func make(_ b: PriceBreakdown) -> PriceExplanation {
        let sell = b.afterCriminal + b.fluctuation
        let values: [(PriceFactor, Int, Int)] = [
            (.base, b.base, b.base),
            (.wanted, b.afterWanted, b.afterWanted - b.base),
            (.traderActivity, b.afterTraderActivity, b.afterTraderActivity - b.afterWanted),
            (.size, b.afterSize, b.afterSize - b.afterTraderActivity),
            (.resource, b.afterResource, b.afterResource - b.afterSize),
            (.pressure, b.afterPressure, b.afterPressure - b.afterResource),
            (.criminal, b.afterCriminal, b.afterCriminal - b.afterPressure),
            (.fluctuation, sell, b.fluctuation),
            (.buyMarkup, sell + b.buyMarkup, b.buyMarkup),
        ]
        return PriceExplanation(item: b.item, steps: values.map { PriceExplanationStep(factor: $0.0, valueAfter: $0.1, delta: $0.2) })
    }

    /// The sell price (the `fluctuation` step's value).
    public var sellPrice: Int { steps.first { $0.factor == .fluctuation }?.valueAfter ?? 0 }
    /// The buy price (sell + markup).
    public var buyPrice: Int { steps.last?.valueAfter ?? 0 }
}

/// INT-024 / MAP-096: the heatmap modes.
public enum HeatmapMode: Sendable, Equatable, Hashable {
    case none
    case price(TradeItemType)
    case holdProfit
    case police
    case pirates
    case techLevel
    case lastVisited
}

/// INT-024: why a value is marked.
public enum HeatmapNote: String, Sendable, Equatable {
    /// An Average Price List estimate (never-observed system).
    case estimate
    /// Visited on an unknown day (bootstrapped journal).
    case dateUnknown
}

/// INT-024: one system's heatmap value.
public struct HeatmapValue: Sendable, Equatable {
    public var value: Int?
    public var note: HeatmapNote?
    public var age: Int?

    public init(value: Int?, note: HeatmapNote? = nil, age: Int? = nil) {
        self.value = value
        self.note = note
        self.age = age
    }

    /// MAP-097: the value is an estimate.
    public var isEstimate: Bool { note == .estimate }
}

/// INT-024: the range of the non-nil values (both 0 when there are none).
public struct HeatmapScale: Sendable, Equatable {
    public var min: Int
    public var max: Int

    public init(min: Int, max: Int) {
        self.min = min
        self.max = max
    }
}

/// INT-024: one value per system plus the scale.
public struct HeatmapResult: Sendable, Equatable {
    public var values: [HeatmapValue]
    public var scale: HeatmapScale
}

/// INT-024 / INT-025 / MAP-097: the pure heatmap model (known intel and public facts only).
public enum HeatmapModel {
    public static func values(mode: HeatmapMode, intel: IntelBook, snapshot: IntelSnapshot) -> HeatmapResult {
        let tables = snapshot.ruleset.tables
        let values: [HeatmapValue] = snapshot.systems.indices.map { i in
            switch mode {
            case .none:
                return HeatmapValue(value: nil)
            case let .price(item):
                let q = TradeIntel.quote(item: item, system: i, book: intel, snapshot: snapshot)
                switch q.source {
                case .estimate: return HeatmapValue(value: q.sell, note: q.sell == nil ? nil : .estimate)
                case .observed: return HeatmapValue(value: q.sell, age: q.age)
                case .live: return HeatmapValue(value: q.sell, age: 0)
                }
            case .holdProfit:
                guard snapshot.hasCargo, i != snapshot.currentSystem else { return HeatmapValue(value: nil) }
                let v = TradeIntel.holdValue(at: i, book: intel, snapshot: snapshot)
                return HeatmapValue(value: v.profit, note: v.usesEstimates ? .estimate : nil)
            case .police:
                return HeatmapValue(value: RouteSnapshot.activityWeight(tables.politics(snapshot.systems[i].politics).activityPolice))
            case .pirates:
                return HeatmapValue(value: RouteSnapshot.activityWeight(tables.politics(snapshot.systems[i].politics).activityPirates))
            case .techLevel:
                return HeatmapValue(value: snapshot.systems[i].techLevel.rawValue)
            case .lastVisited:
                let s = intel.intel(i)
                if s.visitDateUnknown { return HeatmapValue(value: nil, note: .dateUnknown) }
                guard let day = s.lastVisitDay else { return HeatmapValue(value: nil) }
                return HeatmapValue(value: snapshot.day - day)
            }
        }
        let present = values.compactMap(\.value)
        return HeatmapResult(values: values, scale: HeatmapScale(min: present.min() ?? 0, max: present.max() ?? 0))
    }
}
