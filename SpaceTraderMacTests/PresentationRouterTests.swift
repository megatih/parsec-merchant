// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
@testable import ParsecMerchant

/// Sample engine values the routing and coverage tests need (the engine types have no public memberwise inits).
@MainActor
enum RouteFixtures {
    static func offer() throws -> OrbitTradeOffer {
        let json = #"{"direction":"traderSells","item":2,"unitPrice":30,"maxQuantity":3,"unitsAvailable":5,"costBasisPerUnit":0}"#
        return try JSONDecoder().decode(OrbitTradeOffer.self, from: Data(json.utf8))
    }

    static func paper() throws -> Newspaper {
        let json = #"{"system":0,"government":0,"mastheadIndex":0,"headlines":[]}"#
        return try JSONDecoder().decode(Newspaper.self, from: Data(json.utf8))
    }

    /// One value of every `PendingDecision` case.
    static func decisions() throws -> [PendingDecision] {
        [.confirm(Confirmation(.bribe, amounts: [500])), .tradeInOrbit(try offer()),
         .plunder([1, 0, 0, 0, 0, 0, 0, 0, 0, 0]), .scoop(.water), .newspaper(try paper())]
    }

    /// A docked state with a special event offered at the current system.
    static func specialEventState() -> GameState {
        var s = GameState(config: NewGameConfig(commanderName: "Router", seed: 1))
        s.commander.cash = 600_000
        s.galaxy.systems[s.commander.currentSystem].specialEvent = .skill
        return s
    }
}

@MainActor
@Suite("PresentationRouter")
struct PresentationRouterTests {
    private let state = GameState(config: NewGameConfig(commanderName: "Router", seed: 1))

    @Test("UI-SHELL-006 UI-ENC-003 every PendingDecision case and every WarningID routes as specified")
    func routes() throws {
        let offer = try RouteFixtures.offer()
        let paper = try RouteFixtures.paper()
        let cargo = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        #expect(PresentationRouter.route(.tradeInOrbit(offer), state: state, command: .encounter(.trade)) == .sheet(.tradeInOrbit(offer)))
        #expect(PresentationRouter.route(.plunder(cargo), state: state, command: .encounter(.plunder))
            == .sheet(.plunder(PlunderSheetContext(victimCargo: cargo, source: .opponent))))
        #expect(PresentationRouter.route(.plunder(cargo), state: state, command: .encounter(.board))
            == .sheet(.plunder(PlunderSheetContext(victimCargo: cargo, source: .marieCeleste))))
        #expect(PresentationRouter.route(.scoop(.water), state: state, command: .encounter(.attack)) == .scoop(.water))
        #expect(PresentationRouter.route(.newspaper(paper), state: state, command: .readNewspaper) == .sheet(.newspaper(paper)))
        let special = RouteFixtures.specialEventState()
        for w in WarningID.allCases {
            let c = Confirmation(w)
            let command: Command = w == .buyShip ? .buyShip(.firefly, transfers: []) : .warp
            let routed = PresentationRouter.route(.confirm(c), state: special, command: command, acknowledged: [.bribe])
            let pending = PendingConfirmation(command: command, confirmation: c, acknowledged: [.bribe])
            switch w {
            case .retire: #expect(routed == .sheet(.retire(pending)))
            case .buyShip: #expect(routed == .sheet(.shipPurchase(.ship(.firefly))))
            case .acceptSpecialEvent: #expect(routed == .sheet(.narrative(.offer(.skill))))
            default: #expect(routed == .confirmation(pending), "\(w)")
            }
        }
        let design = ShipDesign(name: "X", size: .small, cargoBays: 10, fuelTanks: 10, hull: 50, weaponSlots: 1,
                                shieldSlots: 1, gadgetSlots: 1, crewQuarters: 1)
        #expect(PresentationRouter.route(.confirm(Confirmation(.buyShip)), state: state, command: .buildDesign(design, transfers: []))
            == .sheet(.shipPurchase(.design(design))))
    }

    @Test("UI-ENC-002 the new routes and the scoop presentation have stable, distinct keys; the queue keeps working")
    func routeKeys() throws {
        let routes: [SheetRoute] = [
            .tradeInOrbit(try RouteFixtures.offer()),
            .plunder(PlunderSheetContext(victimCargo: [], source: .opponent)),
            .plunder(PlunderSheetContext(victimCargo: [], source: .marieCeleste)),
            .newspaper(try RouteFixtures.paper()),
            .narrative(.offer(.moon)),
            .narrative(.result(NarrativeResult(type: .moon, title: "T", message: "M"))),
            .report(.arrival(ArrivalReport())), .report(.arrest(ArrestReport())), .report(.escapePod(EscapePodReport())),
            .report(.reactorMeltdown(ReactorReport())), .developerTester,
        ]
        let ids = routes.map { Presentation.sheet($0).id } + [Presentation.scoop(.water).id, Presentation.scoop(.ore).id]
        #expect(Set(ids).count == ids.count)
        #expect(Presentation.sheet(.narrative(.offer(.moon))).id == Presentation.sheet(.narrative(.offer(.moon))).id)
        #expect(ReportSheet.Kind.allCases.count == 4)

        let s = try TestSessions.playing()
        s.present(.scoop(.water))
        s.present(.sheet(.developerTester))
        #expect(s.presentation == .scoop(.water) && s.pendingPresentations == [.sheet(.developerTester)])
        s.dismissPresentation(ifCurrent: Presentation.sheet(.developerTester).id)
        #expect(s.presentation == .scoop(.water))
        s.dismissPresentation(ifCurrent: Presentation.scoop(.water).id)
        #expect(s.presentation == .sheet(.developerTester))
    }
}
