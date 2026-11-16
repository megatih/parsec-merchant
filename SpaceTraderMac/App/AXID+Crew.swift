// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

/// Identifiers of the Crew (⌘5), Bank (⌘6), Quests (⌘8) sections and the Find System sheet (UI-SHELL §18).
extension AXID {
    nonisolated enum Crew {
        static func seat(_ index: Int) -> String { "crew.seat.\(index)" }
        static func hire(_ crewID: Int) -> String { "crew.hire.\(crewID)" }
        static func fire(_ crewID: Int) -> String { "crew.fire.\(crewID)" }
        static let effectiveSkills = "crew.effectiveSkills"
        static let all: [String] = [effectiveSkills] + (0..<CrewID.count).flatMap { [seat($0), hire($0), fire($0)] }
    }

    nonisolated enum Bank {
        static let borrowAmount = "bank.borrow.amount"
        static let borrowSlider = "bank.borrow.slider"
        static let borrowSubmit = "bank.borrow.submit"
        static let repayAmount = "bank.repay.amount"
        static let repaySlider = "bank.repay.slider"
        static let repaySubmit = "bank.repay.submit"
        static let repayAll = "bank.repay.all"
        static let insuranceBuy = "bank.insurance.buy"
        static let insuranceStop = "bank.insurance.stop"
        static let shipyardLink = "bank.insurance.shipyardLink"
        static let debtWarning = "bank.debtWarning"
        static let all = [borrowAmount, borrowSlider, borrowSubmit, repayAmount, repaySlider, repaySubmit, repayAll,
                          insuranceBuy, insuranceStop, shipyardLink, debtWarning]
    }

    nonisolated enum Quests {
        static func entry(_ index: Int) -> String { "quests.entry.\(index)" }
        static func system(entry index: Int, system: Int) -> String { "quests.entry.\(index).system.\(system)" }
        static let completed = "quests.completed"
        static let all: [String] = [completed] + (0..<4).map(entry)
    }

    nonisolated enum FindSystem {
        static let sheet = "findSystem.sheet"
        static let field = "findSystem.field"
        static func result(_ systemIndex: Int) -> String { "findSystem.result.\(systemIndex)" }
        static let track = "findSystem.track"
        static let select = "findSystem.select"
        static let cancel = "findSystem.cancel"
        static let all: [String] = [sheet, field, track, select, cancel] + (0..<4).map(result)
    }

    /// The identifiers of this area, concatenated into `AXID.all`.
    nonisolated static var crewBankQuestsAll: [String] { Crew.all + Bank.all + Quests.all + FindSystem.all }
}
