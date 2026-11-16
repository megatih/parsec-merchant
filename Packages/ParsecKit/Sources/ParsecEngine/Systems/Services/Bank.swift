// SPDX-License-Identifier: GPL-2.0-or-later
// Bank helpers and previews (docs/specs/BNK.md).

/// BNK-060: the bank screen.
public struct BankPreview: Sendable, Equatable {
    public var debt: Int
    public var maxLoan: Int
    public var availableToBorrow: Int
    public var maxRepay: Int
    public var insured: Bool
    public var currentPremium: Int
    /// The premium if insurance were bought now (requires an escape pod).
    public var premiumQuote: Int
    public var noClaim: Int
    public var noClaimAtMaximum: Bool
    public var canBuyInsurance: Bool
}

/// BNK-061: the costs breakdown for a warp target.
public struct DailyCosts: Sendable, Equatable {
    public var mercenaries: Int
    public var insurance: Int
    public var interest: Int
    public var wormholeTax: Int
    public var total: Int { mercenaries + insurance + interest + wormholeTax }
}

public extension GameState {
    /// BNK-020: C# `Commander.PayInterest`.
    mutating func payInterest() {
        guard commander.debt > 0 else { return }
        let interest = max(1, Int(Double(commander.debt) * 0.1))
        if commander.cash > interest {
            commander.cash -= interest
        } else {
            commander.debt += interest - commander.cash
            commander.cash = 0
        }
    }

    /// BNK-043: the no-claim counter is stored clamped to 0…90.
    mutating func setNoClaim(_ value: Int) {
        commander.noClaim = max(0, min(90, value))
    }

    /// BNK-040: the insurance premium for the current ship and a given no-claim value.
    func insurancePremium(noClaim: Int) -> Int {
        max(1, Int(Double(baseWorth(of: commander.ship, forInsurance: true)) * 0.0025 * Double(100 - noClaim) / 100.0))
    }

    var bankPreview: BankPreview {
        BankPreview(debt: commander.debt, maxLoan: maxLoan, availableToBorrow: availableToBorrow, maxRepay: maxRepay,
                    insured: commander.insurance, currentPremium: insuranceCosts, premiumQuote: insurancePremium(noClaim: 0),
                    noClaim: commander.noClaim, noClaimAtMaximum: commander.noClaim >= 90,
                    canBuyInsurance: commander.ship.escapePod && !commander.insurance)
    }

    /// BNK-051/061: the daily costs if warping to `target`.
    func dailyCosts(to target: Int) -> DailyCosts {
        var copy = self
        copy.warpSystem = target
        return DailyCosts(mercenaries: mercenaryCosts, insurance: insuranceCosts, interest: interestCosts,
                          wormholeTax: copy.wormholeCosts)
    }
}
