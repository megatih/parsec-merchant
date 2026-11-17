// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecPersistence

/// The game phase as the menus see it (MENU-002).
nonisolated enum MenuPhase: String, Sendable, Equatable {
    case none, docked, inTransit, encounter, gameOver

    init(_ phase: GamePhase?) {
        switch phase {
        case nil: self = .none
        case .docked: self = .docked
        case .inTransit: self = .inTransit
        case .encounter: self = .encounter
        case .gameOver: self = .gameOver
        }
    }
}

/// What ⌘F does in the shown section (MENU-018): Market's filter, the galaxy map search (MAP-070), or Find System.
nonisolated enum SearchContext: String, Sendable, Equatable {
    case market, galaxy, other
}

/// One Open Recent row (MENU-016).
nonisolated struct RecentSlot: Sendable, Equatable, Identifiable {
    var id: String
    var title: String
    var isCurrentIronmanSlot: Bool
}

/// Everything the menu rules need, built from the session after every step and presentation change (MENU-002).
/// It holds no engine reference.
nonisolated struct MenuContext: Sendable, Equatable {
    var hasGame = false
    var phase: MenuPhase = .none
    var isModal = false
    var isIronman = false
    var currentSlotID: String?
    var canRevertToAutosave = false
    var recentSlots: [RecentSlot] = []
    var warpPreview: WarpTargetPreview?
    var targetIsCurrentSystem = true
    var jumpAvailable = false
    /// Why the singularity jump is not possible (`JumpPreview.rejection`).
    var jumpRejection: CommandError?
    /// MENU-032: Use Singularity… is shown only while `quests.canSuperWarp` is true.
    var singularityShown = false
    var hasDestinations = false
    var targetIsTracked = false
    /// The current target's name, for the Track item's title (MENU-034).
    var targetName = ""
    var canBuyFuel = false
    var canRepair = false
    var fuelFull = true
    var hullFull = true
    var selectedSection: Section = .bridge
    var searchContext: SearchContext = .other
    /// MAP-015: the map whose canvas has keyboard focus (enables the View zoom items).
    var focusedMap: MapScope?
    /// MAP-070: the Galaxy Chart window is key (⌘F searches its map).
    var galaxyIsKey = false

    static let noGame = MenuContext()

    /// The state-derived part of the context (pure; `make(session:)` adds the session and store facts).
    static func make(state: GameState?, isModal: Bool, selectedSection: Section = .bridge, currentSlotID: String? = nil,
                     canRevertToAutosave: Bool = false, recentSlots: [RecentSlot] = [], focusedMap: MapScope? = nil,
                     galaxyIsKey: Bool = false) -> MenuContext {
        var c = MenuContext()
        c.isModal = isModal
        c.selectedSection = selectedSection
        c.focusedMap = focusedMap
        c.galaxyIsKey = galaxyIsKey
        c.searchContext = galaxyIsKey || selectedSection == .galaxy ? .galaxy : selectedSection == .market ? .market : .other
        c.currentSlotID = currentSlotID
        c.canRevertToAutosave = canRevertToAutosave
        c.recentSlots = recentSlots
        guard let state else { return c }
        c.hasGame = true
        c.phase = MenuPhase(state.phase)
        c.isIronman = state.ironman
        let current = state.commander.currentSystem
        c.targetIsCurrentSystem = state.warpSystem == current
        c.warpPreview = state.warpTargetPreview(state.warpSystem)
        c.jumpAvailable = state.jumpPreview.available
        c.jumpRejection = state.jumpPreview.rejection
        c.singularityShown = state.quests.canSuperWarp
        c.hasDestinations = !state.destinations.isEmpty
        c.targetIsTracked = state.trackedSystem == state.warpSystem
        c.targetName = state.systemName(state.warpSystem)
        let ship = state.commander.ship
        let spec = ship.spec(state.ruleset)
        c.fuelFull = ship.fuel >= state.fuelCapacity
        c.hullFull = ship.hull >= ship.hullStrength(state.ruleset)
        c.canBuyFuel = !c.fuelFull && state.commander.cash >= spec.fuelCost
        c.canRepair = !c.hullFull && state.commander.cash >= spec.repairCost
        return c
    }

    /// The menu-bar context of the session (MENU-002).
    @MainActor
    static func make(session: GameSession, focusedMap: MapScope? = nil) -> MenuContext {
        let ironmanSlot = session.state?.ironman == true ? session.gameID : nil
        let recent = session.recentSlots().map { slot in
            RecentSlot(id: slot.id, title: SlotText.recentTitle(slot), isCurrentIronmanSlot: slot.id == ironmanSlot)
        }
        return make(state: session.state, isModal: session.isModal, selectedSection: session.selectedSection,
                    currentSlotID: session.currentSlotID, canRevertToAutosave: session.canRevertToAutosave, recentSlots: recent,
                    focusedMap: focusedMap, galaxyIsKey: session.galaxyWindowIsKey)
    }
}

/// Why a menu item is disabled (shown as the toolbar help tag for Warp).
nonisolated enum DisabledReason: Sendable, Equatable {
    case modal
    case noGame
    case gameEnded
    case notDocked
    case ironman
    case noAutosave
    case targetIsCurrentSystem
    case noDestinations
    case tankFull
    case hullIntact
    case cannotAfford
    case noMapFocus
    case currentIronmanSlot
    case engine(CommandError)

    @MainActor
    var text: String {
        switch self {
        case .modal: String(localized: "Finish the open dialog first.")
        case .noGame: String(localized: "No game is loaded.")
        case .gameEnded: String(localized: "The game has ended.")
        case .notDocked: String(localized: "Not possible right now.")
        case .ironman: String(localized: "Not available in an Ironman game.")
        case .noAutosave: String(localized: "There's no autosave of this game to go back to.")
        case .targetIsCurrentSystem: String(localized: "Choose a target system first.")
        case .noDestinations: String(localized: "No system is in range.")
        case .tankFull: String(localized: "The fuel tanks are full.")
        case .hullIntact: String(localized: "The hull needs no repairs.")
        case .cannotAfford: String(localized: "You can't afford it.")
        case .noMapFocus: String(localized: "Select the galaxy chart first.")
        case .currentIronmanSlot: String(localized: "This Ironman game is already loaded.")
        case let .engine(e): ReasonText.string(for: e)
        }
    }
}

/// Whether an item is enabled, and why not.
nonisolated struct MenuAvailability: Sendable, Equatable {
    var isEnabled: Bool
    var reason: DisabledReason?

    static let enabled = MenuAvailability(isEnabled: true, reason: nil)
    static func disabled(_ r: DisabledReason) -> MenuAvailability { MenuAvailability(isEnabled: false, reason: r) }
}

/// Every enablement rule of the menu bar (MENU-004). Menu items, the toolbar Warp button and the Bridge buttons that
/// mirror a menu item all use it.
nonisolated enum MenuRules {
    /// MENU-010: works with or without a game.
    static func sessionCommand(_ c: MenuContext) -> MenuAvailability {
        c.isModal ? .disabled(.modal) : .enabled
    }

    /// MENU-009: a loaded, docked game and nothing presented.
    static func gameCommand(_ c: MenuContext) -> MenuAvailability {
        if c.isModal { return .disabled(.modal) }
        if !c.hasGame { return .disabled(.noGame) }
        switch c.phase {
        case .docked: return .enabled
        case .gameOver: return .disabled(.gameEnded)
        case .none, .inTransit, .encounter: return .disabled(.notDocked)
        }
    }

    private static func gameCommand(_ c: MenuContext, and condition: Bool, else reason: DisabledReason) -> MenuAvailability {
        let base = gameCommand(c)
        guard base.isEnabled else { return base }
        return condition ? .enabled : .disabled(reason)
    }

    /// A loaded game, ended or not, and nothing presented.
    private static func anyGame(_ c: MenuContext) -> MenuAvailability {
        if c.isModal { return .disabled(.modal) }
        return c.hasGame ? .enabled : .disabled(.noGame)
    }

    /// SAV-041: a loaded game that has not ended.
    private static func liveGame(_ c: MenuContext) -> MenuAvailability {
        let base = anyGame(c)
        guard base.isEnabled else { return base }
        return c.phase == .gameOver ? .disabled(.gameEnded) : .enabled
    }

    static func availability(of item: MenuItemID, in c: MenuContext) -> MenuAvailability {
        switch item {
        case .about, .mainWindow, .galaxyChartWindow, .highScores, .help, .prices, .shortcuts, .credits, .github:
            return .enabled
        case .newGame, .quickStart, .open, .openRecent, .importSave:
            return sessionCommand(c)
        case .save:
            return liveGame(c)
        case .saveAs:
            let base = liveGame(c)
            return base.isEnabled && c.isIronman ? .disabled(.ironman) : base
        case .revert:
            if c.isModal { return .disabled(.modal) }
            if !c.hasGame { return .disabled(.noGame) }
            if c.isIronman { return .disabled(.ironman) }
            return c.canRevertToAutosave ? .enabled : .disabled(.noAutosave)
        case .export, .closeGame:
            return anyGame(c)
        case .find, .bridge, .market, .shipyard, .outfitter, .crew, .bank, .galaxy, .quests, .findSystem, .newspaper, .options, .retire:
            return gameCommand(c)
        case .plotRoute:
            return gameCommand(c, and: !c.targetIsCurrentSystem, else: .targetIsCurrentSystem)
        case .logbook, .galaxyChart:
            return anyGame(c)
        case .zoomIn, .zoomOut, .zoomFit:
            let base = anyGame(c)
            return base.isEnabled && c.focusedMap == nil ? .disabled(.noMapFocus) : base
        case .warp:
            return warp(c)
        case .jump:
            return gameCommand(c, and: c.jumpAvailable, else: .engine(c.jumpRejection ?? .noSingularity))
        case .previousTarget, .nextTarget:
            return gameCommand(c, and: c.hasDestinations, else: .noDestinations)
        case .track:
            return gameCommand(c, and: !c.targetIsCurrentSystem, else: .targetIsCurrentSystem)
        case .fillFuel:
            return gameCommand(c, and: c.canBuyFuel, else: c.fuelFull ? .tankFull : .cannotAfford)
        case .repair:
            return gameCommand(c, and: c.canRepair, else: c.hullFull ? .hullIntact : .cannotAfford)
        }
    }

    /// MENU-030: game command, a target other than the current system, in range and nothing blocking.
    static func warp(_ c: MenuContext) -> MenuAvailability {
        let base = gameCommand(c)
        guard base.isEnabled else { return base }
        if c.targetIsCurrentSystem { return .disabled(.targetIsCurrentSystem) }
        guard let p = c.warpPreview else { return .disabled(.noGame) }
        if !p.inRange { return .disabled(.engine(.destinationOutOfRange)) }
        if let blocking = p.blocking { return .disabled(.engine(blocking)) }
        return .enabled
    }

    /// MENU-016/017: an Open Recent row is a session command, except the current Ironman game's own slot.
    static func recentRowAvailability(_ row: Int, in c: MenuContext) -> MenuAvailability {
        let base = sessionCommand(c)
        guard base.isEnabled else { return base }
        guard c.recentSlots.indices.contains(row) else { return .disabled(.noGame) }
        return c.recentSlots[row].isCurrentIronmanSlot ? .disabled(.currentIronmanSlot) : .enabled
    }

    /// MENU-032: whether the item is shown at all (hidden, not disabled).
    static func isShown(_ item: MenuItemID, in c: MenuContext) -> Bool {
        switch item {
        case .jump: c.singularityShown
        default: MenuCatalog.entry(for: item).milestone <= MenuCatalog.currentMilestone
        }
    }

    /// MENU-034: the Track item's title and command for the current target.
    @MainActor
    static func trackTitle(_ c: MenuContext) -> String {
        c.targetIsTracked ? String(localized: "Stop Tracking “\(c.targetName)”") : String(localized: "Track “\(c.targetName)”")
    }

    static func trackCommand(_ c: MenuContext, warpSystem: Int) -> Command {
        c.targetIsTracked ? .track(nil) : .track(warpSystem)
    }
}
