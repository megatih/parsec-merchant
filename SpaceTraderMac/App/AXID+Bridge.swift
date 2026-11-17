// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

extension AXID {
    /// Bridge (⌘1) identifiers (UI-SHELL §7 and §18).
    nonisolated enum Bridge {
        static let systemCard = "bridge.system"
        static let fuelFillUp = "bridge.fuel.fillUp"
        static let fuelAmount = "bridge.fuel.amount"
        static let fuelBuy = "bridge.fuel.buy"
        static let repairFull = "bridge.repair.full"
        static let repairAmount = "bridge.repair.amount"
        static let repairBuy = "bridge.repair.buy"
        static let special = "bridge.special"
        static let specialAccept = "bridge.special.accept"
        static let specialDecline = "bridge.special.decline"
        static let mercenaries = "bridge.mercenaries"
        static let newspaperRead = "bridge.newspaper.read"
        static let targetCard = "bridge.target"
        static let targetWarp = "bridge.target.warp"
        static let targetPrevious = "bridge.target.previous"
        static let targetNext = "bridge.target.next"
        static let targetTrack = "bridge.target.track"
        static let targetJump = "bridge.target.jump"
        static let galaxyCode = "bridge.galaxyCode"
        static let galaxyCodeCopy = "bridge.galaxyCode.copy"
        /// The partial-purchase sliders beside the amount fields (UI-ENC-096 walk).
        static let fuelSlider = "bridge.fuel.slider"
        static let repairSlider = "bridge.repair.slider"
        static let all = [systemCard, fuelFillUp, fuelAmount, fuelBuy, repairFull, repairAmount, repairBuy, special, specialAccept,
                          specialDecline, mercenaries, newspaperRead, targetCard, targetWarp, targetPrevious, targetNext,
                          targetTrack, targetJump, galaxyCode, galaxyCodeCopy, fuelSlider, repairSlider]
    }
}
