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
    /// BNK-019: what "pay back everything" repays (Palm caps it at 99999).
    public var repayAllAmount: Int
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
    /// RUL-044: double precision in C#; Palm integer `((W×5)/2000)×(100−min(NoClaim,90))/100`.
    func insurancePremium(noClaim: Int) -> Int {
        let value = baseWorth(of: commander.ship, forInsurance: true)
        switch ruleset.flags.economy.insuranceFormula {
        case .doublePrecision: return max(1, Int(Double(value) * 0.0025 * Double(100 - noClaim) / 100.0))
        case .integer: return max(1, ((value * 5) / 2000) * (100 - min(noClaim, 90)) / 100)
        }
    }

    var bankPreview: BankPreview {
        BankPreview(debt: commander.debt, maxLoan: maxLoan, availableToBorrow: availableToBorrow, maxRepay: maxRepay,
                    insured: commander.insurance, currentPremium: insuranceCosts, premiumQuote: insurancePremium(noClaim: 0),
                    noClaim: min(commander.noClaim, 90),
                    // BNK-045: Palm shows "(maximum)" only at exactly 90 (its counter is stored unclamped).
                    noClaimAtMaximum: ruleset.flags.travel.noClaimTiming == .perWarp
                        ? commander.noClaim == 90 : commander.noClaim >= 90,
                    canBuyInsurance: commander.ship.escapePod && !commander.insurance,
                    repayAllAmount: ruleset.flags.economy.repayAllCap.map { min(maxRepay, $0) } ?? maxRepay)
    }

    /// BNK-051/061: the daily costs if warping to `target`.
    func dailyCosts(to target: Int) -> DailyCosts {
        var copy = self
        copy.warpSystem = target
        return DailyCosts(mercenaries: mercenaryCosts, insurance: insuranceCosts, interest: interestCosts,
                          wormholeTax: copy.wormholeCosts)
    }
}
