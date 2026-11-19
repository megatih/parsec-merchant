// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

/// Accessibility identifiers (UI-SHELL Conventions, §18). Dot-separated lowerCamelCase segments
/// `<scope>.<element>[.<qualifier>…]`; data qualifiers use engine case names or indices, never localized text.
/// Extend, never rename: UI tests mirror the identifiers they use in `SpaceTraderMacUITests/AXID.swift`.
nonisolated enum AXID {
    static let pattern = #"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$"#

    enum Welcome {
        static let root = "welcome.root"
        static let quickStart = "welcome.quickStart"
        static let continueGame = "welcome.continue"
        static let newGame = "welcome.newGame"
        static let open = "welcome.open"
        static let importSave = "welcome.import"
        static func recent(_ slotID: String) -> String { "welcome.recent.\(AXID.sanitized(slotID))" }
        static let all = [root, quickStart, continueGame, newGame, open, importSave]
    }

    enum NewGame {
        static let sheet = "newGame.sheet"
        static let name = "newGame.name"
        static func difficulty(_ d: Difficulty) -> String { "newGame.difficulty.\(d)" }
        static func ruleset(_ r: RulesetID) -> String { "newGame.ruleset.\(r.rawValue)" }
        static func skillIncrement(_ s: SkillType) -> String { "newGame.skill.\(s).increment" }
        static func skillDecrement(_ s: SkillType) -> String { "newGame.skill.\(s).decrement" }
        static func skillValue(_ s: SkillType) -> String { "newGame.skill.\(s).value" }
        static let balanced = "newGame.skills.balanced"
        static let pointsRemaining = "newGame.pointsRemaining"
        static let galaxyCode = "newGame.galaxyCode"
        static let seed = "newGame.seed"
        static let randomizeSeed = "newGame.randomizeSeed"
        static let ironman = "newGame.ironman"
        static let shipName = "newGame.shipName"
        static let back = "newGame.back"
        static let next = "newGame.next"
        static let cancel = "newGame.cancel"
        static let start = "newGame.start"
        static let all: [String] = [sheet, name, balanced, pointsRemaining, galaxyCode, seed, randomizeSeed, ironman,
                                    shipName, back, next, cancel, start]
            + Difficulty.allCases.map(difficulty) + RulesetID.allCases.map(ruleset)
            + SkillType.allCases.flatMap { [skillIncrement($0), skillDecrement($0), skillValue($0)] }
    }

    /// UI-NAV-002: the dock bar (the sidebar's successor; its rows' identifiers moved from `sidebar.` to `dock.`).
    enum Dock {
        static let bar = "dock.bar"
        static func button(_ s: Section) -> String { "dock.\(s.rawValue)" }
        static let options = "dock.options"
        static let phaseLabel = "dock.phaseLabel"
        static let bridgeBadge = "dock.bridge.badge"
        static let crewBadge = "dock.crew.badge"
        static let bankBadge = "dock.bank.badge"
        static let all = [bar, phaseLabel, bridgeBadge, crewBadge, bankBadge] + Section.allCases.map(button)
    }

    enum Status {
        static let bays = "status.bays"
        static let fuel = "status.fuel"
        static let hull = "status.hull"
        static let feed = "status.feed"
        static let feedList = "status.feed.list"
        static let feedClose = "status.feed.close"
        static let reason = "status.reason"
        static let bar = "status.bar"
        static let location = "status.location"
        static let cash = "status.cash"
        static let debt = "status.debt"
        static let shields = "status.shields"
        static let all = [bar, location, cash, debt, bays, fuel, hull, shields, feed, feedList, feedClose, reason]
    }

    enum Inspector {
        static let root = "inspector.root"
        static let hull = "inspector.hull"
        static let shields = "inspector.shields"
        static let cash = "inspector.cash"
        static let debt = "inspector.debt"
        static let worth = "inspector.worth"
        static func skill(_ s: SkillType) -> String { "inspector.skill.\(s)" }
        static func quest(_ index: Int) -> String { "inspector.quest.\(index)" }
        static let galaxyCode = "inspector.galaxyCode"
        static let galaxyCodeCopy = "inspector.galaxyCode.copy"
        static let all = [root, hull, shields, cash, debt, worth, galaxyCode, galaxyCodeCopy] + SkillType.allCases.map(skill)
    }

    /// Section roots; the section agents add their own element identifiers below these scopes.
    enum SectionRoot {
        static func root(_ s: Section) -> String { "\(s.rawValue).root" }
        static let all = Section.allCases.map(root)
    }

    enum Dialog {
        static let confirmationConfirm = "confirmation.confirm"
        static let confirmationCancel = "confirmation.cancel"
        static let appConfirmationConfirm = "appConfirmation.confirm"
        static let appConfirmationCancel = "appConfirmation.cancel"
        static let systemAlertOK = "systemAlert.ok"
        static let retireSheet = "retire.sheet"
        static let retireConfirm = "retire.confirm"
        static let retireCancel = "retire.cancel"
        static let placeholderClose = "placeholderSheet.close"
        static let all = [confirmationConfirm, confirmationCancel, appConfirmationConfirm, appConfirmationCancel,
                          systemAlertOK, retireSheet, retireConfirm, retireCancel, placeholderClose]
    }

    /// Every fixed identifier plus the parameterised ones expanded over their engine enums (UI-SHELL-128).
    static var all: [String] {
        Welcome.all + NewGame.all + Dock.all + Status.all + Inspector.all + SectionRoot.all
            + Dialog.all + gameOverArea + encounterAreaAll + shipyardArea + crewBankQuestsAll
            + Bridge.all + Market.all + menusFilesSettingsAll + mapAll + insightsAll + Sound.all + Tips.all
    }

    /// Keeps only characters the identifier scheme allows (slot ids are lowercase UUIDs with hyphens).
    static func sanitized(_ s: String) -> String {
        String(s.filter { $0.isLetter || $0.isNumber })
    }
}
