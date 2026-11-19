// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

/// Identifiers of the menu bar, files, options, settings, About, Help and the cheat console (UI-SHELL §18, MENU-003).
nonisolated extension AXID {
    enum Menu {
        /// Every catalog identifier plus the Open Recent rows.
        static var all: [String] {
            MenuItemID.allCases.map { MenuCatalog.entry(for: $0).identifier }
                + (0..<MenuCatalog.openRecentRows).map(MenuCatalog.openRecentRowIdentifier)
        }
    }

    enum Files {
        static let list = "openSaved.list"
        static let open = "openSaved.open"
        static let export = "openSaved.export"
        static let delete = "openSaved.delete"
        static let cancel = "openSaved.cancel"
        static func row(_ slotID: String) -> String { "openSaved.row.\(AXID.sanitized(slotID))" }
        static let all = [list, open, export, delete, cancel]
    }

    enum Options {
        static func field(_ f: OptionsDraft.Field) -> String { "options.\(f.rawValue)" }
        static let saveDefaults = "options.saveDefaults"
        static let loadDefaults = "options.loadDefaults"
        static let all = [saveDefaults, loadDefaults] + OptionsDraft.Field.allCases.map(field)
    }

    enum Settings {
        static func tab(_ t: SettingsTab) -> String { "settings.tab.\(t.rawValue)" }
        static let textSize = "settings.textSize"
        static let fastTravel = "settings.fastTravel"
        static let arrivalReportStyle = "settings.arrivalReportStyle"
        static let tacticalReadout = "settings.tacticalReadout"
        static let galaxyCode = "settings.galaxyCode"
        static let galaxyCodeCopy = "settings.galaxyCode.copy"
        static func clearHighScores(_ r: RulesetID) -> String { "settings.clearHighScores.\(r.rawValue)" }
        static let all = [textSize, fastTravel, arrivalReportStyle, tacticalReadout, galaxyCode, galaxyCodeCopy]
            + SettingsTab.allCases.map(tab) + RulesetID.allCases.map(clearHighScores)
    }

    enum About {
        static let window = "about.window"
        static let license = "about.license"
        static let licenseClose = "about.license.close"
        static let github = "about.github"
        static func link(_ name: String) -> String { "about.link.\(name)" }
        static let all = [window, license, licenseClose, github] + AboutContent.credits.map { link($0.id) }
    }

    enum Help {
        static let window = "help.window"
        static func topic(_ t: HelpTopic) -> String { "help.topic.\(t.rawValue)" }
        static let content = "help.content"
        static let all = [window, content] + HelpTopic.allCases.map(topic)
    }

    enum CheatConsole {
        static let sheet = "cheatConsole.sheet"
        static let flaggedNotice = "cheatConsole.flagged"
        static let code = "cheatConsole.code"
        static func field(_ name: String) -> String { "cheatConsole.field.\(name)" }
        static let run = "cheatConsole.run"
        static let readout = "cheatConsole.readout"
        static let close = "cheatConsole.close"
        static let all = [sheet, flaggedNotice, code, run, readout, close] + CheatForm.fieldNames.map(field)
    }

    /// Every identifier of this area (registered in `AXID.all`).
    static var menusFilesSettingsAll: [String] {
        Menu.all + Files.all + Options.all + Settings.all + About.all + Help.all + CheatConsole.all
    }
}
