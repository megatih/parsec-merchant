// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
@testable import ParsecMerchant

@MainActor
@Suite("PresentationRouter")
struct PresentationRouterTests {
    private let state = GameState(config: NewGameConfig(commanderName: "Router", seed: 1))

    @Test("UI-SHELL-006 every PendingDecision case and every WarningID routes as specified")
    func routes() throws {
        let offerJSON = #"{"direction":"traderSells","item":2,"unitPrice":30,"maxQuantity":3,"unitsAvailable":5,"costBasisPerUnit":0}"#
        let offer = try JSONDecoder().decode(OrbitTradeOffer.self, from: Data(offerJSON.utf8))
        let paperJSON = #"{"system":0,"government":0,"mastheadIndex":0,"headlines":[]}"#
        let paper = try JSONDecoder().decode(Newspaper.self, from: Data(paperJSON.utf8))
        for d in [PendingDecision.tradeInOrbit(offer), .plunder([1, 0, 0, 0, 0, 0, 0, 0, 0, 0]), .scoop(.water), .newspaper(paper)] {
            #expect(PresentationRouter.route(d, state: state, command: .warp) == .sheet(.decision(d)))
        }
        for w in WarningID.allCases {
            let c = Confirmation(w)
            let command: Command = w == .buyShip ? .buyShip(.firefly, transfers: []) : .warp
            let routed = PresentationRouter.route(.confirm(c), state: state, command: command, acknowledged: [.bribe])
            let pending = PendingConfirmation(command: command, confirmation: c, acknowledged: [.bribe])
            switch w {
            case .retire: #expect(routed == .sheet(.retire(pending)))
            case .buyShip: #expect(routed == .sheet(.shipPurchase(.ship(.firefly))))
            default: #expect(routed == .confirmation(pending), "\(w)")
            }
        }
        let design = ShipDesign(name: "X", size: .small, cargoBays: 10, fuelTanks: 10, hull: 50, weaponSlots: 1,
                                shieldSlots: 1, gadgetSlots: 1, crewQuarters: 1)
        #expect(PresentationRouter.route(.confirm(Confirmation(.buyShip)), state: state, command: .buildDesign(design, transfers: []))
            == .sheet(.shipPurchase(.design(design))))
    }
}
