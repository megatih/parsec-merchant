// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SwiftUI

/// A button a sheet's Return or Esc presses (§2.3).
nonisolated enum SheetButton: String, Sendable, CaseIterable {
    case next, open, ok, select, buy, cancel, run, close, trade, decline, done, jettison, dump, accept, `continue`, confirm
    /// The destructive confirm button (Retire, Delete, Discard, Revert, Clear…); never a default (UI-KEYS-020).
    case destructiveConfirm

    /// Whether the button has the destructive role. Jettison and Dump are not: the quantity sheet is their confirmation and
    /// the littering warning (ALR-047) still follows with Cancel as its default.
    var isDestructive: Bool { self == .destructiveConfirm }

    var title: LocalizedStringResource {
        switch self {
        case .next: "Next (Start on the summary page)"
        case .open: "Open"
        case .ok: "OK"
        case .select: "Select"
        case .buy: "Buy"
        case .cancel: "Cancel"
        case .run: "Run"
        case .close: "Close"
        case .trade: "Trade"
        case .decline: "Decline"
        case .done: "Done"
        case .jettison: "Jettison"
        case .dump: "Dump"
        case .accept: "Accept"
        case .continue: "Continue"
        case .confirm: "the confirm button"
        case .destructiveConfirm: "the destructive button"
        }
    }
}

/// Every surface of §2.3: the `SheetRoute`s plus the Market quantity sheets, the System intel sheet, the About window
/// and the confirmation dialogs and alerts.
nonisolated enum SheetSurface: String, Sendable, CaseIterable {
    case newGame, openSavedGame, findSystem, shipPurchase, retire, cheatConsole, tradeInOrbit, plunder, jettison, dump,
         newspaper, narrativeOffer, narrativeMessage, report, systemIntel, about, developerTester, confirmationDestructive,
         confirmation, systemAlert, priceDetails, serviceAmount

    var context: KeyContext { self == .systemAlert ? .dialog : .sheet(rawValue) }

    var title: LocalizedStringResource {
        switch self {
        case .newGame: "New Game wizard"
        case .openSavedGame: "Open Saved Game"
        case .findSystem: "Find System"
        case .shipPurchase: "Ship purchase review"
        case .retire: "Retire"
        case .cheatConsole: "Cheat console"
        case .tradeInOrbit: "Trade in orbit"
        case .plunder: "Plunder"
        case .jettison: "Jettison"
        case .dump: "Dump"
        case .newspaper: "Newspaper"
        case .narrativeOffer: "Special event offer"
        case .narrativeMessage: "Special event message"
        case .report: "Reports"
        case .systemIntel: "System intel"
        case .about: "About window"
        case .developerTester: "Developer tester"
        case .confirmationDestructive: "Destructive confirmation"
        case .confirmation: "Confirmation"
        case .systemAlert: "Alert"
        case .priceDetails: "Price Details"
        case .serviceAmount: "Buy Fuel and Repair"
        }
    }
}

/// UI-KEYS-020: the Return and Esc buttons of a sheet.
nonisolated struct SheetKeyRoles: Equatable, Sendable {
    var defaultAction: SheetButton
    var escapeAction: SheetButton
    var defaultIsDestructive: Bool { defaultAction.isDestructive }
}

/// UI-KEYS-020 / §2.3: Return = `.defaultAction`, Esc and ⌘. = `.cancelAction`.
nonisolated enum SheetKeys {
    /// The surface of a route. Exhaustive over `SheetRoute` (a message-only narrative offer shows the message roles).
    @MainActor
    static func surface(for route: SheetRoute) -> SheetSurface {
        switch route {
        case .newGame: .newGame
        case .openSavedGame: .openSavedGame
        case .findSystem: .findSystem
        case .shipPurchase: .shipPurchase
        case .retire: .retire
        case .cheatConsole: .cheatConsole
        case .tradeInOrbit: .tradeInOrbit
        case .plunder: .plunder
        case .newspaper: .newspaper
        case let .narrative(page):
            switch page {
            case .offer: .narrativeOffer
            case .result: .narrativeMessage
            }
        case .report: .report
        case .developerTester: .developerTester
        case .priceDetails: .priceDetails
        case let .cargoDisposal(d): d.kind == .jettison ? .jettison : .dump
        case .serviceAmount: .serviceAmount
        }
    }

    @MainActor
    static func table(for route: SheetRoute) -> SheetKeyRoles { roles(surface(for: route)) }

    static func roles(_ surface: SheetSurface) -> SheetKeyRoles {
        switch surface {
        case .newGame: SheetKeyRoles(defaultAction: .next, escapeAction: .cancel)
        case .openSavedGame: SheetKeyRoles(defaultAction: .open, escapeAction: .cancel)
        case .findSystem: SheetKeyRoles(defaultAction: .select, escapeAction: .cancel)
        case .shipPurchase: SheetKeyRoles(defaultAction: .buy, escapeAction: .cancel)
        case .retire: SheetKeyRoles(defaultAction: .cancel, escapeAction: .cancel)
        case .cheatConsole: SheetKeyRoles(defaultAction: .run, escapeAction: .close)
        case .tradeInOrbit: SheetKeyRoles(defaultAction: .trade, escapeAction: .decline)
        case .plunder: SheetKeyRoles(defaultAction: .done, escapeAction: .done)
        case .jettison: SheetKeyRoles(defaultAction: .jettison, escapeAction: .cancel)
        case .dump: SheetKeyRoles(defaultAction: .dump, escapeAction: .cancel)
        case .newspaper: SheetKeyRoles(defaultAction: .close, escapeAction: .close)
        case .narrativeOffer: SheetKeyRoles(defaultAction: .accept, escapeAction: .decline)
        case .narrativeMessage: SheetKeyRoles(defaultAction: .continue, escapeAction: .continue)
        case .report: SheetKeyRoles(defaultAction: .continue, escapeAction: .continue)
        case .systemIntel: SheetKeyRoles(defaultAction: .done, escapeAction: .done)
        case .about: SheetKeyRoles(defaultAction: .done, escapeAction: .done)
        case .developerTester: SheetKeyRoles(defaultAction: .close, escapeAction: .close)
        case .confirmationDestructive: SheetKeyRoles(defaultAction: .cancel, escapeAction: .cancel)
        case .confirmation: SheetKeyRoles(defaultAction: .confirm, escapeAction: .cancel)
        case .systemAlert: SheetKeyRoles(defaultAction: .ok, escapeAction: .ok)
        case .priceDetails: SheetKeyRoles(defaultAction: .done, escapeAction: .done)
        case .serviceAmount: SheetKeyRoles(defaultAction: .buy, escapeAction: .cancel)
        }
    }

    /// The dialog surface of a confirmation (UI-KEYS-023: destructive ones default to Cancel).
    static func dialogSurface(isDestructive: Bool) -> SheetSurface { isDestructive ? .confirmationDestructive : .confirmation }

    /// §2.3 as bindings: Return and Esc of every surface.
    static var bindings: [KeyBinding] {
        SheetSurface.allCases.flatMap { surface -> [KeyBinding] in
            let r = roles(surface)
            let name = String(localized: surface.title)
            let defaultName = String(localized: r.defaultAction.title), escapeName = String(localized: r.escapeAction.title)
            return [
                KeyBinding(action: .sheet(surface, r.defaultAction), shortcut: WindowKeys.returnKey, context: surface.context,
                           owner: .sheet(.defaultAction), titleKey: "\(name): \(defaultName)"),
                KeyBinding(action: .sheet(surface, r.escapeAction), shortcut: WindowKeys.escapeKey, context: surface.context,
                           owner: .sheet(.cancelAction), titleKey: "\(name): \(escapeName)"),
            ]
        }
    }
}

/// UI-KEYS-023: which button of a confirmation dialog carries `.defaultAction` (`PresentationHost` builds from this).
nonisolated struct DialogButtonPlan: Equatable, Sendable {
    var confirmIsDefault: Bool
    var cancelIsDefault: Bool

    static func make(isDestructive: Bool) -> DialogButtonPlan {
        let surface = SheetKeys.dialogSurface(isDestructive: isDestructive)
        let cancelDefault = SheetKeys.roles(surface).defaultAction == .cancel
        return DialogButtonPlan(confirmIsDefault: !cancelDefault, cancelIsDefault: cancelDefault)
    }
}

/// UI-KEYS-021: Esc and ⌘. press a single-button sheet's only button. A button carries one keyboard shortcut, so the
/// sheet root also answers the exit command, and an invisible button carries `.cancelAction` (the exit command only
/// reaches a sheet whose view has focus).
struct SheetEscape: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onExitCommand(perform: action)
            .background {
                Button(action: action) { EmptyView() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .focusable(false)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("sheet.escape")
            }
    }
}

extension View {
    /// UI-KEYS-021: Esc and ⌘. run `action` (the only button of a single-button sheet).
    func sheetEscape(_ action: @escaping () -> Void) -> some View { modifier(SheetEscape(action: action)) }
}
