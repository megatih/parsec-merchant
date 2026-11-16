// SPDX-License-Identifier: GPL-2.0-or-later
// Police record and reputation scales, the arrest term and fine, and the pure police status preview.
// docs/specs/POL.md §1, §8 and §11.

public extension PoliceRecordType {
    /// POL-002 / POL-006: the minimum score of each level (C# `Consts.PoliceRecordScore*`, also the code constants).
    static let minScores = [-100, -70, -30, -10, -5, 0, 5, 10, 25, 75]

    var minScore: Int { Self.minScores[rawValue] }

    /// POL-003 / POL-004: walks the table upward while `score >= minScore` and returns the last level passed
    /// (Psychopath when none), so every score below −70 is Psychopath.
    init(score: Int) {
        var i = 0
        while i < Self.minScores.count, score >= Self.minScores[i] { i += 1 }
        self = PoliceRecordType(rawValue: max(0, i - 1)) ?? .psychopath
    }
}

public extension ReputationType {
    /// POL-005: the minimum score of each level (C# `Consts.ReputationScore*`).
    static let minScores = [0, 10, 20, 40, 80, 150, 300, 600, 1_500]

    var minScore: Int { Self.minScores[rawValue] }

    /// POL-005: looked up like POL-003; negative scores are Harmless.
    init(score: Int) {
        var i = 0
        while i < Self.minScores.count, score >= Self.minScores[i] { i += 1 }
        self = ReputationType(rawValue: max(0, i - 1)) ?? .harmless
    }
}

public extension GameState {
    /// POL-005: the commander's reputation level.
    var reputation: ReputationType { ReputationType(score: commander.reputationScore) }

    /// POL-089: the jail term in days, from the current record.
    var arrestTerm: Int { max(30, -commander.policeRecordScore) }

    /// POL-089 / POL-090: the arrest fine from the current worth and record. C# computes it in Int32, so the product
    /// wraps exactly as the source does; MOD-002 (`arrestFineNeverNegative`) clamps the factor and the result.
    var arrestFine: Int {
        let record = commander.policeRecordScore
        let factor = ruleset.flags.arrestFineNeverNegative ? min(80, max(0, -record)) : min(80, -record)
        let w32 = Int32(truncatingIfNeeded: worth)
        var fine = Int((1 &+ w32 &* Int32(truncatingIfNeeded: factor) / 50_000) &* 500)
        if ruleset.flags.arrestFineNeverNegative { fine = max(500, fine) }
        if wildOnBoard { fine = Int(Double(fine) * 1.05) }
        return fine
    }
}

/// POL-117: what an inspection or customs encounter would cost right now.
public struct InspectionPreview: Sendable, Equatable {
    /// The bribe the police would ask, or nil when `bribeRejection` is set.
    public var bribe: Int?
    public var bribeRejection: CommandError?
    /// The fine a submit would charge (nil when nothing is detectable or for customs, which never fine).
    public var submitFine: Int?
    /// Whether submitting (or yielding to customs) ends in arrest.
    public var submitLeadsToArrest: Bool
    /// The jail term and fine that an arrest would cost.
    public var arrestTerm: Int
    public var arrestFine: Int
}

/// POL-117: pure police and reputation status for the commander screen and the encounter screen.
public struct PoliceStatus: Sendable, Equatable {
    public var record: Int
    public var recordType: PoliceRecordType
    public var reputation: Int
    public var reputationType: ReputationType
    public var kills: Kills
    /// Set only during a police inspection or post-Marie customs encounter.
    public var inspection: InspectionPreview?
}

extension GameEngine {
    /// POL-117: pure; never changes the state.
    public var policeStatus: PoliceStatus {
        let s = state
        var inspection: InspectionPreview?
        if let enc = encounter, enc.type == .policeInspect || enc.type == .marieCelestePolice {
            let customs = enc.type == .marieCelestePolice
            let amount = customs ? nil : s.bribeAmount
            let rejection: CommandError? = customs ? .bribeNotAccepted : (amount == nil ? .bribeNotPossible : nil)
            inspection = InspectionPreview(bribe: amount, bribeRejection: rejection,
                                           submitFine: !customs && s.detectableIllegalCargo ? s.inspectionFine : nil,
                                           submitLeadsToArrest: s.illegalSpecialCargo,
                                           arrestTerm: s.arrestTerm, arrestFine: s.arrestFine)
        }
        return PoliceStatus(record: s.commander.policeRecordScore, recordType: PoliceRecordType(score: s.commander.policeRecordScore),
                            reputation: s.commander.reputationScore, reputationType: s.reputation,
                            kills: s.commander.kills, inspection: inspection)
    }
}
