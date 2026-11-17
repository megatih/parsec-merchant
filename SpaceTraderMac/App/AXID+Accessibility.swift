// SPDX-License-Identifier: GPL-2.0-or-later

/// A11Y identifiers: tips (A11Y-043) and Settings › Advanced › Reset Tips (A11Y-046).
nonisolated extension AXID {
    enum Tips {
        static let all = TipID.allCases.flatMap { [$0.identifier, $0.learnMoreIdentifier, $0.closeIdentifier] }
            + [resetTips, resetTipsStatus]
        static let resetTips = "settings.resetTips"
        static let resetTipsStatus = "settings.resetTips.status"
    }
}
