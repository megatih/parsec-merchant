// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
@testable import ParsecMerchant

/// Builds sessions on throwaway stores and defaults.
@MainActor
enum TestSessions {
    static func make(seed: UInt64? = 1, fastTravel: Bool = true, dock: any SessionDock = NoDock()) throws -> GameSession {
        let id = UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pm-tests-\(id)", isDirectory: true)
        let defaults = try #require(UserDefaults(suiteName: "pm-tests-\(id)"))
        var options = LaunchOptions()
        options.seed = seed
        // Transit playbacks are skipped unless a test opts in (TransitTests use `fastTravel: false`).
        options.fastTravel = fastTravel
        return GameSession(stores: SessionStores(root: root, appVersion: "test"), launchOptions: options, defaults: defaults,
                           dock: dock)
    }

    /// A session with a Quick Start game (Modern, Normal, 5/5/5/5).
    static func playing(seed: UInt64 = 1) throws -> GameSession {
        let s = try make(seed: seed)
        s.requestQuickStart()
        #expect(s.engine != nil)
        return s
    }

    /// Replaces the session's game with a modified copy of its state (same game id).
    static func edit(_ session: GameSession, _ change: (inout GameState) -> Void) throws {
        var state = try #require(session.state)
        change(&state)
        session.install(GameEngine(state: state), gameID: session.gameID ?? "test", slotID: session.currentSlotID)
    }

    /// Answers whatever the session presents so a game can always move on (used to finish encounters).
    static func resolvePresentation(_ session: GameSession) {
        guard let p = session.presentation else { return }
        switch p {
        case let .confirmation(pending): session.confirm(pending)
        case let .sheet(.retire(pending)): session.confirm(pending)
        case .sheet(.tradeInOrbit):
            session.dismissPresentation()
            session.send(.resolveTradeInOrbit(quantity: 0))
        case .sheet(.plunder):
            session.dismissPresentation()
            session.send(.plunderDone)
        case .scoop:
            session.answerScoop(accept: false)
        case .sheet(.narrative(.offer)):
            session.dismissPresentation()
            session.send(.specialEvent, acknowledging: [.acceptSpecialEvent])
        case let .appConfirmation(c): session.confirm(c)
        case .systemAlert, .sheet: session.dismissPresentation()
        }
    }
}
