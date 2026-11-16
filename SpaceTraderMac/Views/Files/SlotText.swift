// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecPersistence

/// Texts for saved-game slots and file failures (MENU-016, SAV-030, SAV-052, UI-SHELL-094).
enum SlotText {
    /// The system name of a slot summary (empty when the index is out of the ruleset's table).
    static func systemName(_ slot: SlotInfo) -> String {
        let names = Ruleset.named(slot.rulesetID).tables.systemNames
        return names.indices.contains(slot.summary.system) ? names[slot.summary.system] : ""
    }

    /// MENU-016: "<Commander> — Day N, <System> (<Ruleset>)" with " · Ironman" and " · Ended" suffixes.
    static func recentTitle(_ slot: SlotInfo) -> String {
        let s = slot.summary
        let ruleset = String(localized: Names.ruleset(slot.rulesetID))
        var title = String(localized: "\(s.commander) — Day \(s.day), \(systemName(slot)) (\(ruleset))")
        if s.ironman { title += String(localized: " · Ironman") }
        if s.ended { title += String(localized: " · Ended") }
        return title
    }

    /// SAV-030: the default export name "<Commander> – Day <N>.parsecsave".
    static func exportFileName(commander: String, day: Int) -> String {
        let safe = commander.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(safe) – Day \(day).\(SaveFileType.fileExtension)"
    }

    /// The export name without the extension (what `fileExporter` takes).
    static func exportBaseName(commander: String, day: Int) -> String {
        String(exportFileName(commander: commander, day: day).dropLast(SaveFileType.fileExtension.count + 1))
    }

    /// SAV-052, UI-SHELL-094: the reason and recovery suggestion of an open or import failure.
    static func openFailure(_ error: any Error) -> (reason: String, suggestion: String?) {
        switch error as? SaveError {
        case .unsupportedFutureVersion:
            return (String(localized: "This saved game was made by a newer version of Parsec Merchant."),
                    String(localized: "Update Parsec Merchant to open it. The file was left where it was."))
        case .notASave:
            return (String(localized: "This file isn't a Parsec Merchant saved game."), nil)
        case .corrupt, .migrationFailed:
            return (String(localized: "The saved game is damaged and no backup could be restored."),
                    String(localized: "The damaged file was moved to the Corrupt folder inside the Parsec Merchant folder."))
        case nil:
            return (String(localized: "The file couldn't be read."), nil)
        }
    }

    /// The `SystemAlert` for an open or import failure.
    static func openFailedAlert(_ error: any Error) -> SystemAlert {
        let f = openFailure(error)
        return .openFailed(reason: f.reason, suggestion: f.suggestion)
    }

    /// ALR-092: the reason shown when a save or export couldn't be written.
    static func saveFailure(_ error: any Error) -> String {
        String(localized: "The file couldn't be written: \(error.localizedDescription)")
    }
}
