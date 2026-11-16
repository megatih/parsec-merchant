// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The menu bar. PLACEHOLDER for the MENU spec owner (MenuItemID, MenuCatalog, MenuRules, MenuContext): replace the
/// body with the full File/View/Game menus. The session API the items call is in `GameSession` and
/// `GameSession+Files.swift` (requestNewGame, requestQuickStart, requestOpen(slotID:), save, saveAs, revertToAutosave,
/// requestCloseGame, send(_:), present(_:), isModal, selectedSection, …).
struct MenuCommands: Commands {
    let session: GameSession

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Game…") { session.requestNewGame() }
                .keyboardShortcut("n")
                .disabled(session.isModal)
                .accessibilityIdentifier("menu.file.newGame")
        }
        CommandMenu("Go") {
            ForEach(Section.allCases) { section in
                Button(String(localized: section.title)) { session.selectedSection = section }
                    .keyboardShortcut(KeyEquivalent(section.shortcutDigit))
                    .disabled(!section.isAvailable(in: session.sectionContext) || session.isModal || !session.isDocked)
                    .accessibilityIdentifier("menu.view.\(section.rawValue)")
            }
        }
    }
}
