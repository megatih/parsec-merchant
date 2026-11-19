// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// The Bridge's intel for one state: built on first use and kept until the state or the journal changes.
struct BridgeIntelCache {
    var generation: Int
    var journalRevision: Int
    var gameID: String?
    var intel: MarketIntelModel
    var cargo: BridgeCargoModel
}

extension GameSession {
    /// UI-BRG-005: the Cargo region's model for the current state. It is built synchronously, so the Target and ±
    /// columns change in the same frame as the Target System.
    var bridgeCargo: BridgeCargoModel? {
        bridgeIntel?.cargo
    }

    /// The intel behind the Bridge (best buys, best destinations, the target's quotes).
    var bridgeIntel: BridgeIntelCache? {
        guard let state else { return nil }
        // Read the observed counters so views that use the model follow them.
        let generation = stateGeneration, revision = journalRevision
        if let cache = bridgeIntelCache, cache.generation == generation, cache.journalRevision == revision, cache.gameID == gameID {
            return cache
        }
        let inputs = MarketIntelModel.Inputs.make(state: state, journal: journal)
        var intel = MarketIntelModel.make(book: inputs.book, snapshot: inputs.snapshot, target: inputs.target, breakdowns: inputs.breakdowns)
        // INT-038: "Show trade recommendations" governs the best-buy stars and the chart's best-destination diamonds.
        if !AppSettings(defaults: defaults).showRecommendations {
            intel.bestBuys = []
            intel.bestDestinations = []
        }
        let cache = BridgeIntelCache(generation: generation, journalRevision: revision, gameID: gameID, intel: intel,
                                     cargo: .make(state: state, intel: intel, book: inputs.book))
        bridgeIntelCache = cache
        return cache
    }

    /// UI-BRG-004: sends each sale of `SellAllCargo` in table order and stops at the first rejection or pending
    /// decision. Returns the number of sales made.
    @discardableResult
    func sellAllCargo() -> Int {
        guard let state else { return 0 }
        var sold = 0
        for command in SellAllCargo.make(state: state).commands {
            let serial = rejectionSerial
            send(command)
            if rejectionSerial != serial || presentation != nil { break }
            sold += 1
        }
        return sold
    }

    /// UI-BRG-007, UI-NAV-011: Buy, Buy Maximum, Sell or Sell All on the good selected in the Cargo region, with the
    /// quantity typed in its row. The B and S keys and the Trade menu both come here.
    func performTrade(_ action: MarketKeyAction) {
        guard selectedSection == .bridge, let item = marketSelection, let row = bridgeCargo?.row(item) else { return }
        let text = cargoQuantities[item] ?? ""
        let command: Command? = switch action {
        case .buy: row.buyCommand(text: text)
        case .sell: row.sellCommand(text: text)
        case .buyMax: row.maxCommand
        case .sellAll: row.allCommand
        }
        if let command { send(command) }
    }

    /// UI-BRG-008: Price Details… for one good.
    func showPriceDetails(_ item: TradeItemType) {
        marketSelection = item
        present(.sheet(.priceDetails(item)))
    }

    /// Dump… or Jettison… for one good (UI-SHELL-065).
    func showCargoDisposal(_ disposal: CargoDisposal) {
        present(.sheet(.cargoDisposal(disposal)))
    }

    /// Trade › Buy Fuel… and Repair…: a partial amount.
    func showServiceAmount(_ kind: DockServiceModel.Kind) {
        present(.sheet(.serviceAmount(kind)))
    }

    /// Find… on the Bridge's Target panel (the Find System sheet, ⌥⌘F).
    func showFindSystem() {
        present(.sheet(.findSystem))
    }

    /// UI-BRG-012: the Galactic Chart page, centred on the Target System.
    func openGalacticChartAtTarget() {
        guard let state else { return }
        selectedSection = .galaxy
        showOnMap(state.warpSystem)
    }

    /// UI-PG-040: the "Show Commander Status" App Intent also shows the page, when a docked game is on screen and
    /// nothing is being decided. It never interrupts a trip, an encounter or a dialog.
    func showCommanderStatusPage() {
        guard mode == .playing, isDocked, !isInputLocked else { return }
        selectedSection = .status
    }
}
