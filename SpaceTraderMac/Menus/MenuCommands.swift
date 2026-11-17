// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The menu bar (MENU §3). Declared once; each group's items are views that observe the session, so titles and
/// enablement update without rebuilding the menus (MENU-007). Titles, shortcuts and identifiers come from
/// `MenuCatalog`; enablement from `MenuRules` (MENU-003/004).
struct MenuCommands: Commands {
    let session: GameSession
    let helpRouter: HelpRouter

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            AppInfoMenuItems()
        }
        // The whole File menu sits in the New group so the system Close Window (⌘W, in the Save group) stays last.
        CommandGroup(replacing: .newItem) {
            FileOpenMenuItems(session: session)
            FileSaveMenuItems(session: session)
            FileTransferMenuItems(session: session)
        }
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .textEditing) {
            FindMenuItems(session: session)
        }
        SidebarCommands()
        InspectorCommands()
        CommandGroup(after: .sidebar) {
            SectionMenuItems(session: session)
        }
        CommandMenu("Game") {
            GameMenuItems(session: session)
        }
        CommandMenu("Encounter") {
            EncounterMenuItems(session: session)
        }
        CommandGroup(before: .windowList) {
            WindowMenuItems()
        }
        CommandGroup(replacing: .help) {
            HelpMenuItems(helpRouter: helpRouter)
        }
    }
}

/// A catalog item: title, shortcut, identifier and enablement in one place.
struct MenuItemButton: View {
    let id: MenuItemID
    var title: String?
    let availability: MenuAvailability
    let action: () -> Void

    var body: some View {
        let entry = MenuCatalog.entry(for: id)
        Button {
            action()
        } label: {
            if let title { Text(verbatim: title) } else { Text(entry.titleKey) }
        }
        .modifier(OptionalShortcut(shortcut: entry.shortcut))
        .disabled(!availability.isEnabled)
        .accessibilityIdentifier(entry.identifier)
    }
}

/// Applies a catalog shortcut when there is one.
struct OptionalShortcut: ViewModifier {
    let shortcut: MenuShortcut?

    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut.keyboardShortcut)
        } else {
            content
        }
    }
}

// MARK: Parsec Merchant

struct AppInfoMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuItemButton(id: .about, availability: .enabled) { openWindow(id: AppWindowID.about) }
    }
}

// MARK: File

struct FileOpenMenuItems: View {
    let session: GameSession

    var body: some View {
        let ctx = MenuContext.make(session: session)
        MenuItemButton(id: .newGame, availability: MenuRules.availability(of: .newGame, in: ctx)) { session.requestNewGame() }
        MenuItemButton(id: .quickStart, availability: MenuRules.availability(of: .quickStart, in: ctx)) { session.requestQuickStart() }
        MenuItemButton(id: .open, availability: MenuRules.availability(of: .open, in: ctx)) { session.present(.sheet(.openSavedGame)) }
        Menu {
            ForEach(0..<MenuCatalog.openRecentRows, id: \.self) { row in
                if ctx.recentSlots.indices.contains(row) {
                    let slot = ctx.recentSlots[row]
                    Button {
                        session.requestOpen(slotID: slot.id)
                    } label: {
                        Text(verbatim: slot.title)
                    }
                    .disabled(!MenuRules.recentRowAvailability(row, in: ctx).isEnabled)
                    .accessibilityIdentifier(MenuCatalog.openRecentRowIdentifier(row))
                }
            }
            if ctx.recentSlots.isEmpty {
                Button("No Recent Games") {}
                    .disabled(true)
                    .accessibilityIdentifier("menu.file.openRecent.none")
            }
        } label: {
            Text(MenuCatalog.entry(for: .openRecent).titleKey)
        }
        .disabled(!MenuRules.availability(of: .openRecent, in: ctx).isEnabled)
        .accessibilityIdentifier(MenuCatalog.entry(for: .openRecent).identifier)
        Divider()
    }
}

struct FileSaveMenuItems: View {
    let session: GameSession

    var body: some View {
        let ctx = MenuContext.make(session: session)
        MenuItemButton(id: .save, availability: MenuRules.availability(of: .save, in: ctx)) { session.save() }
        MenuItemButton(id: .saveAs, availability: MenuRules.availability(of: .saveAs, in: ctx)) { session.saveAs() }
        MenuItemButton(id: .revert, availability: MenuRules.availability(of: .revert, in: ctx)) {
            session.present(.appConfirmation(.revertToAutosave))
        }
        Divider()
    }
}

struct FileTransferMenuItems: View {
    let session: GameSession

    var body: some View {
        let ctx = MenuContext.make(session: session)
        MenuItemButton(id: .importSave, availability: MenuRules.availability(of: .importSave, in: ctx)) { session.requestImport() }
        MenuItemButton(id: .export, availability: MenuRules.availability(of: .export, in: ctx)) { session.requestExport() }
        MenuItemButton(id: .closeGame, availability: MenuRules.availability(of: .closeGame, in: ctx)) { session.requestCloseGame() }
        Divider()
    }
}

// MARK: Edit

/// MENU-018: Find… ⌘F is the context search (Market: its filter; elsewhere: Find System).
struct FindMenuItems: View {
    let session: GameSession
    @FocusedValue(\.contextSearch) private var contextSearch

    var body: some View {
        let ctx = MenuContext.make(session: session)
        Menu {
            MenuItemButton(id: .find, availability: MenuRules.availability(of: .find, in: ctx)) {
                ContextSearch.perform(ctx.searchContext, focused: contextSearch, session: session)
            }
        } label: {
            Text("Find")
        }
    }
}

/// What ⌘F does in a section that has its own search field (the Market publishes one with `focusedSceneValue`).
struct ContextSearchAction {
    let run: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var contextSearch: ContextSearchAction?
}

enum ContextSearch {
    /// Market with a published filter focuses it; Galaxy (section or key window) focuses the map search (MAP-070);
    /// everywhere else ⌘F opens Find System (UI-SHELL-085).
    static func perform(_ context: SearchContext, focused: ContextSearchAction?, session: GameSession) {
        if context == .market || context == .galaxy, let focused {
            focused.run()
        } else {
            session.present(.sheet(.findSystem))
        }
    }
}

// MARK: View

struct SectionMenuItems: View {
    let session: GameSession

    var body: some View {
        let ctx = MenuContext.make(session: session)
        Divider()
        ForEach(MenuCatalog.items(in: .view).filter { $0.section != nil }, id: \.self) { id in
            if let section = id.section {
                let entry = MenuCatalog.entry(for: id)
                Toggle(isOn: Binding { session.selectedSection == section } set: { if $0 { session.selectedSection = section } }) {
                    Text(entry.titleKey)
                }
                .modifier(OptionalShortcut(shortcut: entry.shortcut))
                .disabled(!MenuRules.availability(of: id, in: ctx).isEnabled)
                .accessibilityIdentifier(entry.identifier)
            }
        }
        Divider()
        MapViewMenuItems(session: session)
    }
}

/// MENU-022 / MAP-015: Galaxy Chart ⇧⌘M and the zoom items, which act on the focused map.
struct MapViewMenuItems: View {
    let session: GameSession
    @FocusedValue(\.mapControl) private var mapControl
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let ctx = MenuContext.make(session: session, focusedMap: mapControl?.scope)
        let a = { (id: MenuItemID) in MenuRules.availability(of: id, in: ctx) }
        MenuItemButton(id: .galaxyChart, availability: a(.galaxyChart)) { openWindow(id: GalaxyWindowMetrics.id) }
        MenuItemButton(id: .zoomIn, availability: mapControl?.canZoomIn == false ? .disabled(.noMapFocus) : a(.zoomIn)) {
            mapControl?.zoomIn()
        }
        MenuItemButton(id: .zoomOut, availability: mapControl?.canZoomOut == false ? .disabled(.noMapFocus) : a(.zoomOut)) {
            mapControl?.zoomOut()
        }
        MenuItemButton(id: .zoomFit, availability: a(.zoomFit)) { mapControl?.fit() }
        Divider()
    }
}

// MARK: Game

struct GameMenuItems: View {
    let session: GameSession

    var body: some View {
        let ctx = MenuContext.make(session: session)
        let a = { (id: MenuItemID) in MenuRules.availability(of: id, in: ctx) }
        MenuItemButton(id: .warp, availability: a(.warp)) { session.send(.warp) }
        if MenuRules.isShown(.jump, in: ctx) {
            MenuItemButton(id: .jump, availability: a(.jump)) { session.send(.jump) }
        }
        MenuItemButton(id: .previousTarget, availability: a(.previousTarget)) { session.send(.selectNextTarget(forward: false)) }
        MenuItemButton(id: .nextTarget, availability: a(.nextTarget)) { session.send(.selectNextTarget(forward: true)) }
        MenuItemButton(id: .track, title: ctx.hasGame ? MenuRules.trackTitle(ctx) : nil, availability: a(.track)) {
            if let state = session.state { session.send(MenuRules.trackCommand(ctx, warpSystem: state.warpSystem)) }
        }
        MenuItemButton(id: .findSystem, availability: a(.findSystem)) { session.present(.sheet(.findSystem)) }
        MenuItemButton(id: .plotRoute, availability: a(.plotRoute)) { session.plotRouteToTarget() }
        Divider()
        MenuItemButton(id: .fillFuel, availability: a(.fillFuel)) {
            if let state = session.state { session.send(.buyFuel(credits: state.fullTankCost)) }
        }
        MenuItemButton(id: .repair, availability: a(.repair)) {
            if let state = session.state { session.send(.repairHull(credits: state.fullRepairCost)) }
        }
        Divider()
        MenuItemButton(id: .options, availability: a(.options)) { session.present(.sheet(.gameOptions)) }
        Divider()
        MenuItemButton(id: .retire, availability: a(.retire)) { session.send(.retire) }
    }
}

// MARK: Window

struct WindowMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuItemButton(id: .mainWindow, availability: .enabled) { openWindow(id: SceneMetrics.mainWindowID) }
        MenuItemButton(id: .galaxyChartWindow, availability: .enabled) { openWindow(id: GalaxyWindowMetrics.id) }
        if MenuCatalog.entry(for: .highScores).milestone <= MenuCatalog.currentMilestone {
            MenuItemButton(id: .highScores, availability: .enabled) { openWindow(id: HighScoresWindowView.windowID) }
        }
        Divider()
    }
}

// MARK: Help

struct HelpMenuItems: View {
    let helpRouter: HelpRouter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some View {
        MenuItemButton(id: .help, availability: .enabled) { showHelp(.gettingStarted) }
        MenuItemButton(id: .prices, availability: .enabled) { showHelp(.howPricesWork) }
        MenuItemButton(id: .shortcuts, availability: .enabled) { showHelp(.keyboardShortcuts) }
        MenuItemButton(id: .credits, availability: .enabled) { openWindow(id: AppWindowID.about) }
        MenuItemButton(id: .github, availability: .enabled) { openURL(MenuCatalog.githubURL) }
    }

    private func showHelp(_ topic: HelpTopic) {
        helpRouter.topic = topic
        openWindow(id: AppWindowID.help)
    }
}

/// Scene identifiers of the auxiliary windows (UI-SHELL-014).
enum AppWindowID {
    static let about = "about"
    static let help = "help"
}
