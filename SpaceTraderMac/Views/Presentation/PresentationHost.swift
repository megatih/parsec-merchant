// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Presents `GameSession.presentation` (one at a time, UI-SHELL-005): engine confirmations and app confirmations as
/// confirmation dialogs, failures as alerts, everything else as sheets. Never a popover.
struct PresentationHost: ViewModifier {
    @Environment(GameSession.self) private var session

    private struct SheetItem: Identifiable {
        let id: String
        let route: SheetRoute
    }

    private struct DialogItem: Identifiable {
        let id: String
        let content: ConfirmationContent
        let onConfirm: @MainActor () -> Void
    }

    func body(content: Content) -> some View {
        let dialog = dialogItem
        content
            .sheet(item: sheetBinding) { item in
                SheetRouteView(route: item.route)
                    .environment(session)
            }
            .confirmationDialog(Text(verbatim: dialog?.content.title ?? ""), isPresented: dialogBinding(dialog),
                                titleVisibility: .visible, presenting: dialog) { item in
                if item.content.isDestructive {
                    Button(item.content.confirmLabel, role: .destructive) { item.onConfirm() }
                        .accessibilityIdentifier(confirmID)
                    Button("Cancel", role: .cancel) { session.cancel() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(cancelID)
                } else {
                    Button(item.content.confirmLabel) { item.onConfirm() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(confirmID)
                    Button("Cancel", role: .cancel) { session.cancel() }
                        .accessibilityIdentifier(cancelID)
                }
            } message: { item in
                Text(verbatim: item.content.message)
            }
            .alert(Text(verbatim: alertTitle), isPresented: alertBinding) {
                Button("OK") { session.dismissPresentation() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AXID.Dialog.systemAlertOK)
            } message: {
                Text(verbatim: alertMessage)
            }
    }

    // MARK: Sheets

    private var sheetBinding: Binding<SheetItem?> {
        Binding {
            if case let .sheet(route) = session.presentation, let id = session.presentation?.id {
                return SheetItem(id: id, route: route)
            }
            return nil
        } set: { newValue in
            if newValue == nil, case .sheet = session.presentation, let id = session.presentation?.id {
                session.dismissPresentation(ifCurrent: id)
            }
        }
    }

    // MARK: Confirmation dialogs

    private var isEngineConfirmation: Bool {
        if case .confirmation = session.presentation { return true }
        return false
    }

    private var confirmID: String {
        isEngineConfirmation ? AXID.Dialog.confirmationConfirm : AXID.Dialog.appConfirmationConfirm
    }

    private var cancelID: String {
        isEngineConfirmation ? AXID.Dialog.confirmationCancel : AXID.Dialog.appConfirmationCancel
    }

    private var dialogItem: DialogItem? {
        guard let presentation = session.presentation else { return nil }
        switch presentation {
        case let .confirmation(pending):
            guard let state = session.state else { return nil }
            let content = ConfirmationText.content(for: pending.confirmation, state: state)
            return DialogItem(id: presentation.id, content: content) { [session] in session.confirm(pending) }
        case let .appConfirmation(c):
            let content = AppConfirmationText.content(for: c, session: session)
            return DialogItem(id: presentation.id, content: content) { [session] in session.confirm(c) }
        case .systemAlert, .sheet:
            return nil
        }
    }

    private func dialogBinding(_ item: DialogItem?) -> Binding<Bool> {
        Binding {
            item != nil
        } set: { shown in
            if !shown, let id = item?.id { session.dismissPresentation(ifCurrent: id) }
        }
    }

    // MARK: Alerts

    private var currentAlert: SystemAlert? {
        if case let .systemAlert(a) = session.presentation { return a }
        return nil
    }

    private var alertBinding: Binding<Bool> {
        Binding {
            currentAlert != nil
        } set: { shown in
            if !shown, let id = session.presentation?.id, currentAlert != nil { session.dismissPresentation(ifCurrent: id) }
        }
    }

    private var alertTitle: String {
        switch currentAlert {
        case .saveFailed: String(localized: "The game couldn't be saved.")
        case .openFailed: String(localized: "The saved game couldn't be opened.")
        case .nothingToContinue: String(localized: "There's no game to continue.")
        case nil: ""
        }
    }

    private var alertMessage: String {
        switch currentAlert {
        case let .saveFailed(reason): reason
        case let .openFailed(reason, suggestion): [reason, suggestion].compactMap(\.self).joined(separator: "\n\n")
        case .nothingToContinue, nil: ""
        }
    }
}

/// Text of the app-layer confirmations.
enum AppConfirmationText {
    static func content(for c: AppConfirmation, session: GameSession) -> ConfirmationContent {
        switch c {
        case .discardUnsavedGame:
            ConfirmationContent(title: String(localized: "Discard the Current Game?"),
                                message: String(localized: "Your progress since the last save will be lost."),
                                confirmLabel: String(localized: "Discard"), isDestructive: true)
        case .revertToAutosave:
            ConfirmationContent(title: String(localized: "Revert to the Autosave?"),
                                message: String(localized: "Your progress since the autosave is lost."),
                                confirmLabel: String(localized: "Revert"), isDestructive: true)
        case .deleteSlot:
            ConfirmationContent(title: String(localized: "Delete This Saved Game?"),
                                message: String(localized: "This can't be undone."),
                                confirmLabel: String(localized: "Delete"), isDestructive: true)
        case .loadImportedSave:
            ConfirmationContent(title: String(localized: "Load the Imported Game Now?"),
                                message: String(localized: "The imported game was added to your saved games."),
                                confirmLabel: String(localized: "Load"), isDestructive: false)
        case let .clearHighScores(r):
            ConfirmationContent(title: String(localized: "Clear High Scores?"),
                                message: String(localized: "All \(String(localized: Names.ruleset(r))) high scores will be removed."),
                                confirmLabel: String(localized: "Clear"), isDestructive: true)
        case let .timewarpLoad(reloaded):
            ConfirmationContent(title: String(localized: "Load a Saved Game?"),
                                message: reloaded ? String(localized: "Really load another game?")
                                    : String(localized: "Loading a saved game keeps this game off the high-score table."),
                                confirmLabel: String(localized: "Load"), isDestructive: false)
        case .closeGame:
            ConfirmationContent(title: String(localized: "Close the Game?"),
                                message: String(localized: "You'll return to the Welcome window."),
                                confirmLabel: String(localized: "Close Game"), isDestructive: false)
        }
    }
}
