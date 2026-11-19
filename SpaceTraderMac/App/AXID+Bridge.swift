// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

extension AXID {
    /// Bridge (⌘1) identifiers (UI-SHELL §7 and §18).
    nonisolated enum Bridge {
        /// The singularity button, shown only while the portable singularity is aboard.
        static let targetJump = BridgeID.Target.jump
        /// The amount sheet of Trade › Buy Fuel… and Repair….
        static let serviceSheet = "bridge.service.sheet"
        static let serviceCancel = "bridge.service.cancel"
        static let fuelAmount = "bridge.fuel.amount"
        static let fuelBuy = "bridge.fuel.buy"
        static let fuelSlider = "bridge.fuel.slider"
        static let repairAmount = "bridge.repair.amount"
        static let repairBuy = "bridge.repair.buy"
        static let repairSlider = "bridge.repair.slider"
        // The chart's two identifiers are registered with the map's (`AXID.mapAll`).
        static let all = BridgeManifest.all.filter { !BridgeID.Chart.all.contains($0) }
            + [BridgeID.Cargo.header, BridgeID.Cargo.rows, targetJump, serviceSheet, serviceCancel, fuelAmount, fuelBuy, fuelSlider, repairAmount,
               repairBuy, repairSlider]
    }
}
