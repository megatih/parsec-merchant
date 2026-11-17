// SPDX-License-Identifier: GPL-2.0-or-later
// What the player has seen (docs/specs/INT.md §2, INT-007…011): market observations, visits and pressure hints.
// Stored in the journal beside the state (LOG-001); arrays and integers only, so the save JSON stays deterministic.
import ParsecEngine

/// INT-009 / INT-014: fixed policy values.
public enum IntelPolicy {
    /// Observations kept per system.
    public static let historyLimit = 24
    /// Observations at most this many days old are `.fresh`.
    public static let recentDays = 7
}

/// INT-011: where a pressure hint came from.
public enum PressureHintSource: String, Codable, Sendable, Equatable {
    /// A newspaper headline the player read (INT-006).
    case news
    /// The current system's pressure while docked (INT-008).
    case observed
}

/// INT-011: a known pressure of a system, with the day it was learned.
public struct PressureHint: Codable, Sendable, Equatable {
    public var pressure: SystemPressure
    public var day: Int
    public var source: PressureHintSource

    public init(pressure: SystemPressure, day: Int, source: PressureHintSource) {
        self.pressure = pressure
        self.day = day
        self.source = source
    }
}

/// INT-007: one docked observation of a market (one element per `TradeItemType`).
public struct MarketObservation: Codable, Sendable, Equatable {
    public var day: Int
    public var buy: [Int]
    public var sell: [Int]
    public var stock: [Int]
    public var pressure: SystemPressure

    public init(day: Int, buy: [Int], sell: [Int], stock: [Int], pressure: SystemPressure) {
        self.day = day
        self.buy = buy
        self.sell = sell
        self.stock = stock
        self.pressure = pressure
    }
}

/// INT-007: what is known about one system.
public struct SystemIntel: Codable, Sendable, Equatable {
    /// nil when never visited, or visited on an unknown day (bootstrapped journal, INT-010).
    public var lastVisitDay: Int?
    public var visitCount: Int
    /// Oldest first, at most `IntelPolicy.historyLimit`.
    public var history: [MarketObservation]
    public var pressureHint: PressureHint?

    public init(lastVisitDay: Int? = nil, visitCount: Int = 0, history: [MarketObservation] = [],
                pressureHint: PressureHint? = nil) {
        self.lastVisitDay = lastVisitDay
        self.visitCount = visitCount
        self.history = history
        self.pressureHint = pressureHint
    }

    public var latest: MarketObservation? { history.last }

    /// INT-010: "visited, date unknown".
    public var visitDateUnknown: Bool { visitCount > 0 && lastVisitDay == nil }
}

/// INT-007: one `SystemIntel` per galaxy system (array index = system index).
public struct IntelBook: Codable, Sendable, Equatable {
    public var systems: [SystemIntel]

    public init(systems: [SystemIntel]) {
        self.systems = systems
    }

    public init(systemCount: Int) {
        systems = Array(repeating: SystemIntel(), count: max(0, systemCount))
    }

    public func intel(_ system: Int) -> SystemIntel {
        systems.indices.contains(system) ? systems[system] : SystemIntel()
    }

    /// INT-010: an arrival.
    public mutating func visit(_ system: Int, day: Int) {
        guard systems.indices.contains(system) else { return }
        systems[system].lastVisitDay = day
        systems[system].visitCount += 1
    }

    /// INT-008 / INT-009 / INT-011: records a docked observation (same day replaces; identical is not repeated).
    public mutating func observe(_ observation: MarketObservation, at system: Int) {
        guard systems.indices.contains(system) else { return }
        var s = systems[system]
        if let last = s.history.last, last.day == observation.day {
            s.history[s.history.count - 1] = observation
        } else if s.history.last != observation {
            s.history.append(observation)
        }
        if s.history.count > IntelPolicy.historyLimit { s.history.removeFirst(s.history.count - IntelPolicy.historyLimit) }
        s.pressureHint = observation.pressure == .none
            ? nil : PressureHint(pressure: observation.pressure, day: observation.day, source: .observed)
        systems[system] = s
    }

    /// INT-008: observes the current market when the state is docked; nothing in transit, encounter or game over.
    public mutating func observe(_ state: GameState) {
        guard case .docked = state.phase else { return }
        let system = state.commander.currentSystem
        observe(MarketObservation(day: state.commander.days, buy: state.buyPrices, sell: state.sellPrices,
                                  stock: state.galaxy.systems[system].tradeItems,
                                  pressure: state.galaxy.systems[system].pressure), at: system)
    }

    /// INT-006 / INT-011: a news hint; the newest hint per system wins (an equal day replaces).
    public mutating func hear(_ hint: PressureHint, about system: Int) {
        guard systems.indices.contains(system) else { return }
        if let old = systems[system].pressureHint, old.day > hint.day { return }
        systems[system].pressureHint = hint
    }

    /// INT-006: every external-pressure headline of a paper read on `day`.
    public mutating func read(_ headlines: [Headline], day: Int) {
        for case let .externalPressure(_, pressure, system) in headlines {
            hear(PressureHint(pressure: pressure, day: day, source: .news), about: system)
        }
    }
}
