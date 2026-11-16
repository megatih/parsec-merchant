// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

extension GameEngine {
    /// The error `command` would be rejected with right now, or nil if the engine would accept it or ask to confirm.
    /// Runs the command on a throwaway copy (the engine is a value type), so the session's game never changes and the
    /// reason is exactly the engine's own (UI-SHELL Conventions "Inline reasons").
    func rejection(ifPerformed command: Command) -> CommandError? {
        var copy = self
        return copy.perform(command).rejection
    }
}

// MARK: - Crew (UI-SHELL-079…081)

/// The crew quarters, the mercenaries for hire and the effective-skills panel. Pure over the engine.
struct CrewModel: Equatable, Sendable {
    /// One seat of the crew quarters (UI-SHELL-079).
    struct Seat: Equatable, Sendable, Identifiable {
        enum Occupant: Equatable, Sendable {
            case commander(name: String, skills: [Int])
            case mercenary(crewID: Int, name: String, skills: [Int], dailyWage: Int)
            case passenger(crewID: Int, name: String)
            case vacant
        }

        var index: Int
        var occupant: Occupant
        /// Why Fire is unavailable for this seat (nil: Fire allowed). Only mercenaries and passengers have a Fire button.
        var fireBlocker: CommandError?

        var id: Int { index }

        var crewID: Int? {
            switch occupant {
            case .commander: CrewID.commander
            case let .mercenary(id, _, _, _), let .passenger(id, _): id
            case .vacant: nil
            }
        }

        var canBeFired: Bool {
            switch occupant {
            case .mercenary, .passenger: true
            case .commander, .vacant: false
            }
        }
    }

    /// A mercenary for hire here (UI-SHELL-080).
    struct HireCard: Equatable, Sendable, Identifiable {
        var crewID: Int
        var name: String
        /// Pilot, fighter, trader, engineer.
        var skills: [Int]
        var dailyWage: Int
        var blocker: CommandError?

        var id: Int { crewID }
    }

    /// One row of the effective-skills panel (UI-SHELL-081).
    struct SkillRow: Equatable, Sendable, Identifiable {
        var skill: SkillType
        var effective: Int
        var crewMaximum: Int
        var gadgetBonus: Int
        /// Only the Trader row has a haggling bonus (Jarek's haggling computer).
        var hagglingBonus: Int
        var difficultyAdjustment: Int

        var id: SkillType { skill }
    }

    /// The commander's standing shown on the commander's seat.
    struct Standing: Equatable, Sendable {
        var policeRecord: PoliceRecordType
        var policeScore: Int
        var reputation: ReputationType
        var kills: Int
    }

    static let passengerIDs: Set<Int> = [CrewID.wild, CrewID.jarek, CrewID.princess]

    var seats: [Seat]
    var forHire: [HireCard]
    var skills: [SkillRow]
    var freeQuarters: Int
    var dailyWages: Int
    var standing: Standing

    static func make(engine: GameEngine) -> CrewModel {
        let s = engine.state
        let preview = s.crewPreview
        let kills = s.commander.kills
        return CrewModel(
            seats: seats(engine: engine),
            forHire: preview.forHire.map { candidate in
                HireCard(crewID: candidate.id, name: Names.crew(candidate.id, in: s), skills: skills(of: candidate.id, in: s),
                         dailyWage: candidate.rate, blocker: engine.rejection(ifPerformed: .hire(crewID: candidate.id)))
            },
            skills: SkillType.allCases.map { skill in
                let i = skill.rawValue
                return SkillRow(skill: skill, effective: preview.effectiveSkills[i], crewMaximum: preview.crewMaximum[i],
                                gadgetBonus: preview.gadgetBonus[i], hagglingBonus: skill == .trader ? preview.hagglingBonus : 0,
                                difficultyAdjustment: preview.difficultyAdjustment)
            },
            freeQuarters: max(0, preview.freeQuarters - s.passengersOutsideCrew),
            dailyWages: preview.dailyMercenaryCost,
            standing: Standing(policeRecord: s.policeRecord, policeScore: s.commander.policeRecordScore,
                               reputation: s.reputation, kills: kills.pirates + kills.police + kills.traders))
    }

    /// The crew array as seats, then Palm passengers that hold no crew slot (CRW-044). Those take a quarter each, so
    /// they fill the last vacant seats (the engine's hire limit leaves exactly those free), or extra seats if none.
    static func seats(engine: GameEngine) -> [Seat] {
        let s = engine.state
        var seats = s.commander.ship.crew.enumerated().map { index, member -> Seat in
            guard let id = member else { return Seat(index: index, occupant: .vacant) }
            let occupant: Seat.Occupant
            if id == CrewID.commander {
                occupant = .commander(name: s.commander.name, skills: skills(of: id, in: s))
            } else if passengerIDs.contains(id) {
                occupant = .passenger(crewID: id, name: Names.crew(id, in: s))
            } else {
                occupant = .mercenary(crewID: id, name: Names.crew(id, in: s), skills: skills(of: id, in: s),
                                      dailyWage: s.dailyRate(of: id))
            }
            let blocker = id == CrewID.commander ? nil : engine.rejection(ifPerformed: .fire(crewID: id))
            return Seat(index: index, occupant: occupant, fireBlocker: blocker)
        }
        guard !s.ruleset.flags.economy.passengersAsCrew else { return seats }
        var outside: [Int] = []
        if s.jarekOnBoard { outside.append(CrewID.jarek) }
        if s.wildOnBoard { outside.append(CrewID.wild) }
        for id in outside where !s.commander.ship.hasCrew(id) {
            let seat = Seat(index: 0, occupant: .passenger(crewID: id, name: Names.crew(id, in: s)),
                            fireBlocker: .cannotFireSpecialPassenger)
            if let last = seats.lastIndex(where: { $0.occupant == .vacant }) {
                seats[last] = Seat(index: last, occupant: seat.occupant, fireBlocker: seat.fireBlocker)
            } else {
                seats.append(Seat(index: seats.count, occupant: seat.occupant, fireBlocker: seat.fireBlocker))
            }
        }
        return seats
    }

    static func skills(of id: Int, in s: GameState) -> [Int] {
        s.mercenaries.indices.contains(id) ? s.mercenaries[id].skills : [0, 0, 0, 0]
    }
}

// MARK: - Bank (UI-SHELL-082…084)

/// Everything the Bank section shows. Pure over the engine.
struct BankModel: Equatable, Sendable {
    /// Why the bank lends this much (BNK-011).
    enum LoanReason: Equatable, Sendable {
        case cleanRecord(Int)
        case criminalRecord(Int)

        var text: LocalizedStringResource {
            switch self {
            case let .cleanRecord(n): "Clean record: up to \(n.formatted())"
            case let .criminalRecord(n): "Criminal record: up to \(n.formatted())"
            }
        }
    }

    static let debtWarningThreshold = SidebarBadges.debtWarningThreshold
    static let debtLimit = 100_000

    var preview: BankPreview
    var loanReason: LoanReason
    /// Rejections of the smallest borrow / repay (nil: the control is usable).
    var borrowBlocker: CommandError?
    var repayBlocker: CommandError?
    var interestPerWarp: Int
    var shipValue: Int
    var hasEscapePod: Bool
    var buyInsuranceBlocker: CommandError?
    var stopInsuranceBlocker: CommandError?
    var dailyCosts: DailyCosts
    var debtWarning: Bool

    static func make(engine: GameEngine) -> BankModel {
        let s = engine.state
        let p = s.bankPreview
        return BankModel(
            preview: p,
            loanReason: s.commander.policeRecordScore >= 0 ? .cleanRecord(p.maxLoan) : .criminalRecord(p.maxLoan),
            borrowBlocker: engine.rejection(ifPerformed: .borrow(1)),
            repayBlocker: engine.rejection(ifPerformed: .repay(1)),
            interestPerWarp: s.interestCosts, shipValue: s.shipWorth(forInsurance: true),
            hasEscapePod: s.commander.ship.escapePod,
            buyInsuranceBlocker: p.insured ? nil : engine.rejection(ifPerformed: .buyInsurance),
            stopInsuranceBlocker: p.insured ? engine.rejection(ifPerformed: .stopInsurance) : nil,
            dailyCosts: s.dailyCosts(to: s.warpSystem),
            debtWarning: p.debt >= debtWarningThreshold)
    }

    /// The daily premium shown: the current one when insured, else what buying now would cost (UI-SHELL-083).
    var premium: Int { preview.insured ? preview.currentPremium : preview.premiumQuote }

    /// The no-claim meter's fraction of its 90% maximum.
    var noClaimFraction: Double { Double(min(preview.noClaim, 90)) / 90 }

    /// Keeps a typed or slid amount inside `0…limit`.
    static func clamp(_ amount: Int, to limit: Int) -> Int { min(max(0, amount), max(0, limit)) }

    /// The command Borrow sends, or nil while the amount can't be borrowed.
    func borrowCommand(amount: Int) -> Command? {
        borrowBlocker == nil && amount >= 1 && amount <= preview.availableToBorrow ? .borrow(amount) : nil
    }

    /// The command Repay sends, or nil while the amount can't be repaid.
    func repayCommand(amount: Int) -> Command? {
        repayBlocker == nil && amount >= 1 && amount <= preview.maxRepay ? .repay(amount) : nil
    }

    /// Repay All sends `repayAllAmount` (Palm caps it at 99,999, BNK-019).
    var repayAllCommand: Command? { repayBlocker == nil && preview.repayAllAmount >= 1 ? .repay(preview.repayAllAmount) : nil }
}
