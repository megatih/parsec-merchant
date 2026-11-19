// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

extension AXID {
    /// The trade sheets' identifiers (the rows are the Bridge's Cargo region, `BridgeID.Cargo`).
    nonisolated enum Market {
        static let disposalSheet = "market.disposal.sheet"
        static let disposalQuantity = "market.disposal.quantity"
        static let disposalConfirm = "market.disposal.confirm"
        static let disposalCancel = "market.disposal.cancel"
        static let priceDetailsSheet = "market.priceDetails.sheet"
        static let priceDetailsDone = "market.priceDetails.done"
        static let priceDetailsAdvice = "market.priceDetails.advice"
        static let all: [String] = [disposalSheet, disposalQuantity, disposalConfirm, disposalCancel,
                                    priceDetailsSheet, priceDetailsDone, priceDetailsAdvice]
    }
}
