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

/// What ⌘F does in the shown section (MENU-018): Market's filter, the galaxy map search (MAP-070), the Logbook's search
/// (LOG-032), or Find System.
nonisolated enum SearchContext: String, Sendable, Equatable {
    case market, galaxy, logbook, other
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
    /// UI-BRG-004: why Sell All Cargo cannot act; nil when it can.
    var sellAllBlocker: CommandError? = .cargoNoneToSell
    /// UI-BRG-008: a good is selected in the Bridge's Cargo region.
    var hasCargoSelection = false
    /// UI-NAV-011: why Buy, Sell and Sell All cannot act on the selected good; nil when they can.
    var tradeBuyBlocker: CommandError?
    var tradeSellBlocker: CommandError?
    var tradeSellAllBlocker: CommandError?
    /// The selected good can be dumped (or jettisoned) here.
    var canDumpSelection = false
    /// UI-NAV-011: the Bridge is the page and no text field has the focus, so B and S are the Trade keys.
    var tradeKeysActive = false
    var canRepair = false
    var fuelFull = true
    var hullFull = true
    /// UI-ENC-072: why Game › Newspaper is disabled (the unpaid paper is unaffordable, ALR-009).
    var newspaperBlocker: CommandError?
    var selectedSection: Section = .bridge
    var searchContext: SearchContext = .other
    /// MAP-015: the map whose canvas has keyboard focus (enables the View zoom items).
    var focusedMap: MapScope?
    /// MAP-070: the Galaxy Chart window is key (⌘F searches its map).
    var galaxyIsKey = false
    /// UI-ENC-034: the current encounter's actions for the Encounter menu (nil outside `.encounter`).
    var encounter: EncounterMenuState?

    static let noGame = MenuContext()

    /// The state-derived part of the context (pure; `make(session:)` adds the session and store facts).
    static func make(state: GameState?, isModal: Bool, selectedSection: Section = .bridge, currentSlotID: String? = nil,
                     canRevertToAutosave: Bool = false, recentSlots: [RecentSlot] = [], focusedMap: MapScope? = nil,
                     galaxyIsKey: Bool = false, transitPlaying: Bool = false, autoRepeatOn: Bool = true) -> MenuContext {
        var c = MenuContext()
        c.isModal = isModal
        c.selectedSection = selectedSection
        c.focusedMap = focusedMap
        c.galaxyIsKey = galaxyIsKey
        c.searchContext = galaxyIsKey || selectedSection == .galaxy ? .galaxy
            : selectedSection == .logbook ? .logbook : .other
        c.currentSlotID = currentSlotID
        c.canRevertToAutosave = canRevertToAutosave
        c.recentSlots = recentSlots
        guard let state else { return c }
        c.hasGame = true
        // UI-ENC-006: a running transit playback reads as `.inTransit` (the engine state is already final).
        c.phase = transitPlaying ? .inTransit : MenuPhase(state.phase)
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
        c.sellAllBlocker = SellAllCargo.make(state: state).blocker
        if case .encounter = state.phase { c.encounter = EncounterMenuState.make(engine: GameEngine(state: state), autoRepeatOn: autoRepeatOn) }
        c.newspaperBlocker = NewspaperCardModel.blocker(state: state)
        return c
    }

    /// The menu-bar context of the session (MENU-002).
    @MainActor
    static func make(session: GameSession, focusedMap: MapScope? = nil) -> MenuContext {
        let ironmanSlot = session.state?.ironman == true ? session.gameID : nil
        let recent = session.recentSlots().map { slot in
            RecentSlot(id: slot.id, title: SlotText.recentTitle(slot), isCurrentIronmanSlot: slot.id == ironmanSlot)
        }
        var c = make(state: session.state, isModal: session.isModal, selectedSection: session.selectedSection,
                     currentSlotID: session.currentSlotID, canRevertToAutosave: session.canRevertToAutosave, recentSlots: recent,
                     focusedMap: focusedMap, galaxyIsKey: session.galaxyWindowIsKey,
                     transitPlaying: session.transitPlayback != nil, autoRepeatOn: session.encounterUI.autoRepeatEnabled)
        c.hasCargoSelection = session.marketSelection != nil && session.selectedSection == .bridge
        if c.hasCargoSelection, let item = session.marketSelection, let row = session.bridgeCargo?.row(item) {
            c.tradeBuyBlocker = row.market.buyBlocker
            c.tradeSellBlocker = row.sellBlocker
            c.tradeSellAllBlocker = row.allBlocker
            c.canDumpSelection = CargoDisposal.dump(row.market) != nil
        }
        c.tradeKeysActive = session.selectedSection == .bridge && !session.textEntryFocused && c.phase == .docked && !c.isModal
        return c
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
    case noCargoSelection
    case noMapFocus
    case currentIronmanSlot
    case notInEncounter
    case autoRepeatUnavailable
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
        case .noCargoSelection: String(localized: "Select a good on the Bridge first.")
        case .noMapFocus: String(localized: "Select the galaxy chart first.")
        case .currentIronmanSlot: String(localized: "This Ironman game is already loaded.")
        case .notInEncounter: String(localized: "Only during an encounter.")
        case .autoRepeatUnavailable: String(localized: "Turn on Continuous attack in View › Options, or use Resolve.")
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
        case .find, .bridge, .shipyard, .outfitter, .crew, .bank, .commanderStatus, .galaxy, .quests, .options, .retire:
            return gameCommand(c)
        case .newspaper:
            return gameCommand(c, and: c.newspaperBlocker == nil, else: .engine(c.newspaperBlocker ?? .insufficientFunds))
        case .plotRoute:
            return gameCommand(c, and: !c.targetIsCurrentSystem, else: .targetIsCurrentSystem)
        case .logbook, .galaxyChart, .recentEvents:
            return anyGame(c)
        case .tradeBuy, .tradeBuyMax:
            return tradeCommand(c, blocker: c.tradeBuyBlocker)
        case .tradeSell:
            return tradeCommand(c, blocker: c.tradeSellBlocker)
        case .tradeSellAll:
            return tradeCommand(c, blocker: c.tradeSellAllBlocker)
        case .dumpCargo:
            let base = gameCommand(c, and: c.hasCargoSelection, else: .noCargoSelection)
            return base.isEnabled && !c.canDumpSelection ? .disabled(.engine(.cargoNoneToSell)) : base
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
        case .fillFuel, .buyFuelAmount:
            return gameCommand(c, and: c.canBuyFuel, else: c.fuelFull ? .tankFull : .cannotAfford)
        case .repair, .repairAmount:
            return gameCommand(c, and: c.canRepair, else: c.hullFull ? .hullIntact : .cannotAfford)
        case .sellAllCargo:
            return gameCommand(c, and: c.sellAllBlocker == nil, else: .engine(c.sellAllBlocker ?? .cargoNoneToSell))
        case .priceDetails:
            return gameCommand(c, and: c.hasCargoSelection, else: .noCargoSelection)
        case .encounterAttack, .encounterFlee, .encounterSurrender, .encounterIgnore, .encounterBribe, .encounterSubmit, .encounterTrade,
             .encounterPlunder, .encounterBoard, .encounterDrink, .encounterMeet, .encounterYield, .encounterAutoRepeat,
             .encounterResolve, .encounterStop:
            return encounterItem(item, in: c)
        }
    }

    /// UI-NAV-011: a Trade item that acts on the good selected on the Bridge.
    private static func tradeCommand(_ c: MenuContext, blocker: CommandError?) -> MenuAvailability {
        let base = gameCommand(c, and: c.hasCargoSelection, else: .noCargoSelection)
        guard base.isEnabled, let blocker else { return base }
        return .disabled(.engine(blocker))
    }

    /// UI-ENC-034 / MENU-036: an Encounter item is enabled iff nothing is presented, the phase is `.encounter` (a running
    /// playback reads as `.inTransit`, UI-ENC-006) and its action has no rejection; Resolve, Stop and Auto-repeat follow
    /// UI-ENC-031…033.
    static func encounterItem(_ item: MenuItemID, in c: MenuContext) -> MenuAvailability {
        if c.isModal { return .disabled(.modal) }
        if !c.hasGame { return .disabled(.noGame) }
        guard c.phase == .encounter, let enc = c.encounter else { return .disabled(.notInEncounter) }
        switch item.encounterAction {
        case nil:
            return enc.autoRepeatAvailable ? .enabled : .disabled(.autoRepeatUnavailable)
        case .stop?:
            return enc.canStop ? .enabled : .disabled(.engine(.encounterActionUnavailable))
        case .resolve?:
            guard enc.resolveShown else { return .disabled(.engine(.encounterActionUnavailable)) }
            return enc.resolveRejection.map { .disabled(.engine($0)) } ?? .enabled
        case let action?:
            guard let p = enc.preview(action) else { return .disabled(.engine(.encounterActionUnavailable)) }
            return p.rejection.map { .disabled(.engine($0)) } ?? .enabled
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
        case .encounterAttack, .encounterFlee, .encounterSurrender, .encounterIgnore, .encounterBribe, .encounterSubmit, .encounterTrade,
             .encounterPlunder, .encounterBoard, .encounterDrink, .encounterMeet, .encounterYield, .encounterResolve:
            MenuCatalog.entry(for: item).milestone <= MenuCatalog.currentMilestone && isEncounterItemShown(item, in: c)
        default: MenuCatalog.entry(for: item).milestone <= MenuCatalog.currentMilestone
        }
    }

    /// UI-ENC-034: during an encounter an action item is shown iff the preview offers it (Resolve iff Attack is offered);
    /// outside encounters every item is shown, disabled (the menu mirrors the action bar).
    static func isEncounterItemShown(_ item: MenuItemID, in c: MenuContext) -> Bool {
        guard let enc = c.encounter else { return true }
        if item == .encounterResolve { return enc.resolveShown }
        guard let action = item.encounterAction else { return true }
        return enc.preview(action) != nil
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
